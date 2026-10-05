import Foundation
import Logging

/// Serves gopher content over HTTP as server-rendered HTML.
///
/// URLs mirror `gopher://` URLs: `/{host}:{port}/{type}{selector}`, with `/`
/// showing this server's root menu and `?q=` supplying search (type 7) queries.
/// The proxy is transport-agnostic; callers feed it parsed requests.
public struct GopherHTTPProxy: Sendable {
    private let policy: ProxyPolicy
    private let local: GopherFetching
    private let remote: GopherFetching
    private let cache: ResponseCache?
    private let title: String
    private let logger: Logger

    /// - Parameters:
    ///   - local: Fetches from this server, typically without going over the network.
    ///   - remote: Fetches from other servers when the policy allows it.
    ///   - cache: Caches remote responses. Local responses are never cached.
    public init(
        policy: ProxyPolicy,
        local: GopherFetching,
        remote: GopherFetching,
        cache: ResponseCache? = ResponseCache(),
        title: String? = nil,
        logger: Logger = Logger(label: "com.navanchauhan.gopher.proxy")
    ) {
        self.policy = policy
        self.local = local
        self.remote = remote
        self.cache = cache
        self.title = title ?? policy.localHost
        self.logger = logger
    }

    /// Turns raw request bytes into response bytes, or `nil` if more bytes are needed.
    public func respond(to data: Data) async -> Data? {
        switch HTTPRequestParser.parse(data) {
        case .incomplete:
            return nil
        case .invalid:
            return errorResponse(status: 400, message: "Malformed HTTP request.").serialized()
        case .complete(let request):
            let response = await handle(request)
            return response.serialized(includeBody: request.method != "HEAD")
        }
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.method == "GET" || request.method == "HEAD" else {
            var response = errorResponse(status: 405, message: "Only GET and HEAD are supported.")
            response.headers.append(("Allow", "GET, HEAD"))
            return response
        }

        let location: GopherLocation
        if request.path == "/" {
            location = GopherLocation(host: policy.localHost, port: policy.localPort)
        } else if let parsed = GopherLocation(proxyPath: request.path) {
            location = parsed
        } else {
            return errorResponse(status: 404, message: "That is not a gopher address.")
        }

        guard policy.permits(host: location.host, port: location.port) else {
            return errorResponse(
                status: 403,
                message: "This proxy does not fetch from \(location.host):\(location.port).",
                location: location
            )
        }

        switch location.type {
        case "1":
            return await render(location, request: location.selector) { renderer.menu($0, location: location) }
        case "0":
            return await render(location, request: location.selector) { renderer.text($0, location: location) }
        case "7":
            let query = request.queryValue("q")?
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            guard let query, !query.isEmpty else {
                return html(renderer.searchForm(location: location))
            }
            return await render(location, request: "\(location.selector)\t\(query)") {
                renderer.menu($0, location: location)
            }
        case "h":
            if location.selector.hasPrefix("URL:") {
                let url = String(location.selector.dropFirst(4))
                guard HTMLRenderer.isSafeExternalURL(url) else {
                    return errorResponse(status: 400, message: "Refusing to redirect to \(url).", location: location)
                }
                return HTTPResponse(status: 302, headers: securityHeaders + [("Location", url)])
            }
            // Show remote HTML as source rather than rendering untrusted markup.
            return await render(location, request: location.selector) { renderer.text($0, location: location) }
        case "i", "3", "2", "8", "T", "+":
            return errorResponse(
                status: 400,
                message: "Items of type '\(location.type)' can't be viewed through this proxy.",
                location: location
            )
        default:
            return await download(location)
        }
    }

    private var renderer: HTMLRenderer {
        HTMLRenderer(title: title) { location in
            policy.permits(host: location.host, port: location.port) ? location.proxyPath : location.gopherURL
        }
    }

    private func render(
        _ location: GopherLocation,
        request: String,
        _ body: (Data) -> String
    ) async -> HTTPResponse {
        switch await fetch(location, request: request) {
        case .success(let data):
            return html(body(data))
        case .failure(let error):
            return error.response
        }
    }

    /// Serves images inline and everything else as an attachment.
    private func download(_ location: GopherLocation) async -> HTTPResponse {
        let data: Data
        switch await fetch(location, request: location.selector) {
        case .success(let fetched):
            data = fetched
        case .failure(let error):
            return error.response
        }

        if let imageType = Self.sniffImageType(data) {
            return HTTPResponse(status: 200, headers: securityHeaders + [("Content-Type", imageType)], body: data)
        }

        let filename = Self.downloadFilename(for: location.selector)
        return HTTPResponse(
            status: 200,
            headers: securityHeaders + [
                ("Content-Type", "application/octet-stream"),
                ("Content-Disposition", "attachment; filename=\"\(filename)\""),
            ],
            body: data
        )
    }

    private func fetch(_ location: GopherLocation, request: String) async -> Result<Data, HTTPResponseError> {
        let isLocal = policy.isLocal(host: location.host, port: location.port)
        let cacheKey = "\(location.host):\(location.port)\n\(request)"

        if !isLocal, let cached = await cache?.value(for: cacheKey) {
            return .success(cached)
        }

        do {
            let fetcher = isLocal ? local : remote
            let data = try await fetcher.fetch(host: location.host, port: location.port, request: request)
            if !isLocal {
                await cache?.insert(data, for: cacheKey)
            }
            return .success(data)
        } catch {
            logger.info("Proxy fetch of \(location.gopherURL) failed: \(error)")
            return .failure(
                HTTPResponseError(
                    response: errorResponse(
                        status: 502,
                        message: "Couldn't fetch \(location.gopherURL): \(error)",
                        location: location
                    )
                )
            )
        }
    }

    private func html(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: securityHeaders + [("Content-Type", "text/html; charset=utf-8")],
            body: Data(body.utf8)
        )
    }

    private func errorResponse(status: Int, message: String, location: GopherLocation? = nil) -> HTTPResponse {
        html(renderer.error(status: status, message: message, location: location), status: status)
    }

    private var securityHeaders: [(String, String)] {
        [
            (
                "Content-Security-Policy",
                "default-src 'none'; style-src 'unsafe-inline'; img-src 'self'; form-action 'self'; "
                    + "base-uri 'none'; frame-ancestors 'none'"
            ),
            ("X-Content-Type-Options", "nosniff"),
            ("Referrer-Policy", "no-referrer"),
        ]
    }

    static func sniffImageType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: Array("GIF8".utf8)) { return "image/gif" }
        if bytes.starts(with: Array("BM".utf8)) { return "image/bmp" }
        if bytes.count >= 12, bytes.starts(with: Array("RIFF".utf8)), Array(bytes[8..<12]) == Array("WEBP".utf8) {
            return "image/webp"
        }
        return nil
    }

    static func downloadFilename(for selector: String) -> String {
        let last = selector.split(separator: "/").last.map(String.init) ?? ""
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let cleaned = String(last.filter { allowed.contains($0) }).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "download" : cleaned
    }
}

/// Wraps a ready-made error page so it can travel through `Result`.
private struct HTTPResponseError: Error {
    let response: HTTPResponse
}
