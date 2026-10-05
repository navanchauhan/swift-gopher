import Foundation

/// A gopher resource, addressed the same way as a `gopher://` URL (RFC 4266).
public struct GopherLocation: Sendable, Equatable {
    public var host: String
    public var port: Int
    /// The gopher item type character, e.g. `1` for a menu or `0` for text.
    public var type: Character
    public var selector: String

    public init(host: String, port: Int = 70, type: Character = "1", selector: String = "") {
        self.host = host
        self.port = port
        self.type = type
        self.selector = selector
    }

    /// The proxy path for this location: `/{host}:{port}/{type}{selector}`.
    public var proxyPath: String {
        "/\(authority)/\(type)\(Self.encode(selector))"
    }

    /// The equivalent `gopher://` URL.
    public var gopherURL: String {
        "gopher://\(authority)/\(type)\(Self.encode(selector))"
    }

    private var authority: String {
        let host = self.host.contains(":") ? "[\(self.host)]" : self.host
        return "\(host):\(port)"
    }

    /// Parses a proxy path produced by `proxyPath`. Returns `nil` for anything that
    /// does not name a gopher resource, or whose selector could not be sent safely.
    public init?(proxyPath path: String) {
        guard path.hasPrefix("/") else { return nil }
        let trimmed = path.dropFirst()
        let authorityEnd = trimmed.firstIndex(of: "/") ?? trimmed.endIndex
        guard let authority = trimmed[..<authorityEnd].removingPercentEncoding,
            let (host, port) = Self.parseAuthority(authority)
        else {
            return nil
        }

        var rest = trimmed[authorityEnd...].dropFirst()
        let type = rest.popFirst() ?? "1"
        guard let selector = String(rest).removingPercentEncoding,
            // Check scalars: "\r\n" is a single Character, so a Character check misses it.
            !selector.unicodeScalars.contains(where: { $0 == "\t" || $0 == "\r" || $0 == "\n" }),
            type.isASCII, !type.isWhitespace
        else {
            return nil
        }

        self.init(host: host, port: port, type: type, selector: selector)
    }

    private static func parseAuthority(_ authority: String) -> (String, Int)? {
        var host: Substring
        var portString: Substring?

        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return nil }
            host = authority[authority.index(after: authority.startIndex)..<close]
            let after = authority[authority.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else { return nil }
                portString = after.dropFirst()
            }
        } else if let colon = authority.lastIndex(of: ":") {
            host = authority[..<colon]
            portString = authority[authority.index(after: colon)...]
        } else {
            host = Substring(authority)
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else {
            return nil
        }

        var port = 70
        if let portString {
            guard let parsed = Int(portString), (1...65535).contains(parsed) else { return nil }
            port = parsed
        }
        return (String(host).lowercased(), port)
    }

    private static let selectorAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: ";")
        return set
    }()

    private static func encode(_ selector: String) -> String {
        selector.addingPercentEncoding(withAllowedCharacters: selectorAllowed) ?? ""
    }
}
