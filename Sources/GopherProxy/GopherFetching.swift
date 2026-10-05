import Foundation
import SwiftGopherClient

/// Fetches the raw bytes of a gopher response.
public protocol GopherFetching: Sendable {
    /// - Parameter request: The full request line without the trailing CRLF, i.e. the
    ///   selector, optionally followed by a tab and a search query.
    func fetch(host: String, port: Int, request: String) async throws -> Data
}

public enum ProxyFetchError: Error, CustomStringConvertible {
    case unresolvable(String)
    case forbiddenAddress(String)

    public var description: String {
        switch self {
        case .unresolvable(let host):
            return "Could not resolve \(host)"
        case .forbiddenAddress(let host):
            return "\(host) resolves to a private or reserved address"
        }
    }
}

/// Fetches from remote gopher servers with `GopherClient`, refusing to connect to
/// loopback, private or otherwise non-public addresses.
public final class RemoteGopherFetcher: GopherFetching, @unchecked Sendable {
    // GopherClient isn't Sendable, but it holds no mutable state after init.
    private let client: GopherClient
    private let allowPrivateAddresses: Bool

    public init(timeout: TimeInterval = 15, maxResponseSize: Int = 16 * 1024 * 1024, allowPrivateAddresses: Bool = false)
    {
        self.client = GopherClient(timeout: timeout, maxResponseSize: maxResponseSize)
        self.allowPrivateAddresses = allowPrivateAddresses
    }

    public func fetch(host: String, port: Int, request: String) async throws -> Data {
        let addresses = AddressResolver.resolve(host: host, port: port)
        guard let address = addresses.first else {
            throw ProxyFetchError.unresolvable(host)
        }
        // Every address must be public, otherwise a host could mix in internal ones.
        guard allowPrivateAddresses || addresses.allSatisfy(AddressFilter.isPublic) else {
            throw ProxyFetchError.forbiddenAddress(host)
        }

        // Connect to the vetted address rather than re-resolving the name.
        return try await client.sendRawRequest(to: address, port: port, message: request + "\r\n")
    }
}

/// A size- and age-bounded in-memory cache of gopher responses.
public actor ResponseCache {
    private struct Entry {
        let data: Data
        let storedAt: Date
    }

    private let ttl: TimeInterval
    private let maxBytes: Int
    private var entries: [String: Entry] = [:]
    /// Keys from least to most recently used.
    private var order: [String] = []
    private var totalBytes = 0

    public init(ttl: TimeInterval = 300, maxBytes: Int = 32 * 1024 * 1024) {
        self.ttl = ttl
        self.maxBytes = maxBytes
    }

    public func value(for key: String, now: Date = Date()) -> Data? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < ttl else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.data
    }

    public func insert(_ data: Data, for key: String, now: Date = Date()) {
        guard data.count <= maxBytes else { return }
        remove(key)
        entries[key] = Entry(data: data, storedAt: now)
        order.append(key)
        totalBytes += data.count

        while totalBytes > maxBytes, let oldest = order.first {
            remove(oldest)
        }
    }

    private func touch(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
            order.append(key)
        }
    }

    private func remove(_ key: String) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        totalBytes -= entry.data.count
        order.removeAll { $0 == key }
    }
}
