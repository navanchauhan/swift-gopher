import Foundation

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Decides which gopher servers the proxy may fetch from.
public struct ProxyPolicy: Sendable {
    /// Host name this server advertises in its own menus.
    public var localHost: String
    /// Port this server advertises in its own menus.
    public var localPort: Int
    /// Allow fetching from gopher servers other than this one.
    public var allowRemoteHosts: Bool
    /// Allow remote servers on ports other than 70.
    public var allowAllPorts: Bool

    public init(localHost: String, localPort: Int, allowRemoteHosts: Bool = false, allowAllPorts: Bool = false) {
        self.localHost = localHost.lowercased()
        self.localPort = localPort
        self.allowRemoteHosts = allowRemoteHosts
        self.allowAllPorts = allowAllPorts
    }

    public func isLocal(host: String, port: Int) -> Bool {
        host.lowercased() == localHost && port == localPort
    }

    /// Whether `host:port` may be fetched, before address resolution. Remote hosts
    /// must additionally pass `isPublicAddress` once resolved.
    public func permits(host: String, port: Int) -> Bool {
        if isLocal(host: host, port: port) {
            return true
        }
        return allowRemoteHosts && (port == 70 || allowAllPorts)
    }
}

/// Classifies resolved IP addresses so the proxy can't be used to reach loopback,
/// private, link-local or otherwise internal networks.
public enum AddressFilter {
    public static func isPublic(_ address: String) -> Bool {
        if let octets = ipv4Octets(address) {
            return isPublicIPv4(octets)
        }
        if let bytes = ipv6Bytes(address) {
            return isPublicIPv6(bytes)
        }
        return false
    }

    static func isPublicIPv4(_ o: [UInt8]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _), (10, _), (127, _): return false
        case (100, 64...127): return false  // carrier-grade NAT
        case (169, 254): return false  // link-local
        case (172, 16...31): return false
        case (192, 168): return false
        case (192, 0) where o[2] == 0: return false  // IETF protocol assignments
        case (198, 18...19): return false  // benchmarking
        case (224..., _): return false  // multicast, reserved, broadcast
        default: return true
        }
    }

    static func isPublicIPv6(_ b: [UInt8]) -> Bool {
        // IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible (::a.b.c.d) addresses.
        if b[0..<10].allSatisfy({ $0 == 0 }) && ((b[10] == 0xff && b[11] == 0xff) || (b[10] == 0 && b[11] == 0)) {
            return isPublicIPv4(Array(b[12..<16]))
        }
        if b[0] == 0xff { return false }  // multicast
        if b[0] & 0xfe == 0xfc { return false }  // unique local fc00::/7
        if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return false }  // link-local fe80::/10
        if b[0] == 0xfe && b[1] & 0xc0 == 0xc0 { return false }  // site-local fec0::/10
        if b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b {  // NAT64 64:ff9b::/96
            return isPublicIPv4(Array(b[12..<16]))
        }
        if b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8 { return false }  // documentation
        return true
    }

    static func ipv4Octets(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        return octets.count == 4 ? octets : nil
    }

    static func ipv6Bytes(_ address: String) -> [UInt8]? {
        var storage = in6_addr()
        let result = address.withCString { inet_pton(AF_INET6, $0, &storage) }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: &storage) { Array($0) }
    }
}

/// Resolves host names to numeric addresses so the proxy can vet the address and
/// then connect to exactly that address (avoiding DNS rebinding between checks).
public enum AddressResolver {
    public static func resolve(host: String, port: Int) -> [String] {
        #if os(Windows)
        var wsaData = WSADATA()
        guard WSAStartup(0x0202, &wsaData) == 0 else { return [] }
        defer { WSACleanup() }
        #endif

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
        #else
        hints.ai_socktype = SOCK_STREAM
        #endif

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            return []
        }
        defer { freeaddrinfo(first) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            if let address = info.pointee.ai_addr, let numeric = numericHost(address, length: info.pointee.ai_addrlen) {
                if !addresses.contains(numeric) {
                    addresses.append(numeric)
                }
            }
            current = info.pointee.ai_next
        }
        return addresses
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>, length: some BinaryInteger) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        let status = getnameinfo(
            address,
            .init(length),
            &buffer,
            .init(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else { return nil }
        var host = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // Strip IPv6 zone identifiers such as `fe80::1%eth0`.
        if let percent = host.firstIndex(of: "%") {
            host = String(host[..<percent])
        }
        return host
    }
}
