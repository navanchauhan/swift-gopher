import Foundation

/// A parsed HTTP/1.x request. Only the parts the proxy needs are kept.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    /// The request target, e.g. `/example.com:70/1/foo?q=bar`.
    public var target: String
    public var headers: [String: String]

    public init(method: String, target: String, headers: [String: String] = [:]) {
        self.method = method
        self.target = target
        self.headers = headers
    }

    /// Path component of the target, still percent-encoded.
    public var path: String {
        String(target.prefix { $0 != "?" })
    }

    /// Query component of the target (without the `?`), still encoded.
    public var query: String? {
        guard let index = target.firstIndex(of: "?") else { return nil }
        return String(target[target.index(after: index)...])
    }

    /// Decodes an `application/x-www-form-urlencoded` query parameter.
    public func queryValue(_ name: String) -> String? {
        guard let query else { return nil }
        for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard Self.formDecode(parts[0]) == name else { continue }
            return parts.count > 1 ? Self.formDecode(parts[1]) : ""
        }
        return nil
    }

    private static func formDecode(_ value: Substring) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }
}

public enum HTTPRequestParser {
    /// Requests whose header section exceeds this size are rejected.
    public static let maxHeaderSize = 16 * 1024

    public enum Result: Sendable, Equatable {
        /// More bytes are needed before the request can be parsed.
        case incomplete
        case complete(HTTPRequest)
        case invalid
    }

    /// Parses the request line and headers. Request bodies are ignored since the
    /// proxy only serves `GET` and `HEAD`.
    public static func parse(_ data: Data) -> Result {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeaderSize ? .invalid : .incomplete
        }
        guard end.lowerBound <= maxHeaderSize,
            let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8)
        else {
            return .invalid
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3,
            requestLine[2].hasPrefix("HTTP/1."),
            !requestLine[0].isEmpty,
            requestLine[1].hasPrefix("/")
        else {
            return .invalid
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return .complete(
            HTTPRequest(method: String(requestLine[0]), target: String(requestLine[1]), headers: headers)
        )
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [(String, String)]
    public var body: Data

    public init(status: Int, headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.0.lowercased() == name.lowercased() }?.1
    }

    /// Serializes the response for a connection that is closed after one exchange.
    public func serialized(includeBody: Bool = true) -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasonPhrase(for: status))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var data = Data(head.utf8)
        if includeBody {
            data.append(body)
        }
        return data
    }

    static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 502: return "Bad Gateway"
        default: return "Unknown"
        }
    }
}
