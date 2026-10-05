import Foundation
import XCTest

@testable import GopherProxy

/// Records requests and replies with canned responses keyed by request string.
private final class FakeFetcher: GopherFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [String: Data]
    private(set) var requests: [(host: String, port: Int, request: String)] = []

    init(_ responses: [String: String] = [:], data: [String: Data] = [:]) {
        self.responses = responses.mapValues { Data($0.utf8) }.merging(data) { $1 }
    }

    func fetch(host: String, port: Int, request: String) async throws -> Data {
        lock.withLock { requests.append((host, port, request)) }
        guard let response = responses[request] else {
            throw URLError(.fileDoesNotExist)
        }
        return response
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }
}

final class GopherProxyTests: XCTestCase {
    private let menu = """
        iWelcome <friend>\t\terror.host\t1\r
        1Docs\t/docs\tgopher.example\t70\r
        0Read me\t/readme.txt\tgopher.example\t70\r
        1Elsewhere\t/\tother.example\t70\r
        1Odd port\t/\tother.example\t7070\r
        hHomepage\tURL:https://example.com/\tgopher.example\t70\r
        hBad link\tURL:javascript:alert(1)\tgopher.example\t70\r
        8Telnet\t\tbbs.example\t23\r
        7Search\t/search\tgopher.example\t70\r
        .\r

        """

    private func makeProxy(
        local: FakeFetcher,
        remote: FakeFetcher = FakeFetcher(),
        allowRemoteHosts: Bool = false,
        allowAllPorts: Bool = false,
        cache: ResponseCache? = nil
    ) -> GopherHTTPProxy {
        GopherHTTPProxy(
            policy: ProxyPolicy(
                localHost: "gopher.example",
                localPort: 70,
                allowRemoteHosts: allowRemoteHosts,
                allowAllPorts: allowAllPorts
            ),
            local: local,
            remote: remote,
            cache: cache
        )
    }

    private func get(_ proxy: GopherHTTPProxy, _ target: String) async -> HTTPResponse {
        await proxy.handle(HTTPRequest(method: "GET", target: target))
    }

    private func body(_ response: HTTPResponse) -> String {
        String(decoding: response.body, as: UTF8.self)
    }

    func testRootRendersLocalMenu() async {
        let local = FakeFetcher(["": menu])
        let response = await get(makeProxy(local: local), "/")

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.header("Content-Type"), "text/html; charset=utf-8")
        let html = body(response)
        XCTAssertTrue(html.contains("Welcome &lt;friend&gt;"))
        XCTAssertTrue(html.contains("<a href=\"/gopher.example:70/1/docs\">Docs</a>"))
        XCTAssertTrue(html.contains("<a href=\"/gopher.example:70/0/readme.txt\">Read me</a>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com/\" rel=\"noreferrer\">Homepage</a>"))
        XCTAssertTrue(html.contains("<a href=\"telnet://bbs.example:23\">Telnet</a>"))
        XCTAssertFalse(html.contains("javascript:"))
        XCTAssertFalse(html.contains("<script"))
    }

    func testRemoteLinksPointAtGopherURLsWhenRemoteHostsAreDisabled() async {
        let response = await get(makeProxy(local: FakeFetcher(["": menu])), "/")
        let html = body(response)
        XCTAssertTrue(html.contains("<a href=\"gopher://other.example:70/1/\">Elsewhere</a>"))
    }

    func testRemoteLinksAreProxiedWhenAllowed() async {
        let response = await get(makeProxy(local: FakeFetcher(["": menu]), allowRemoteHosts: true), "/")
        let html = body(response)
        XCTAssertTrue(html.contains("<a href=\"/other.example:70/1/\">Elsewhere</a>"))
        // Non-70 ports still need --http-allow-all-ports.
        XCTAssertTrue(html.contains("<a href=\"gopher://other.example:7070/1/\">Odd port</a>"))
    }

    func testTextIsEscapedAndTerminatorRemoved() async {
        let local = FakeFetcher(["/readme.txt": "<b>hi</b> & bye\r\n.\r\n"])
        let response = await get(makeProxy(local: local), "/gopher.example:70/0/readme.txt")

        XCTAssertEqual(response.status, 200)
        XCTAssertTrue(body(response).contains("<pre class=\"text\">&lt;b&gt;hi&lt;/b&gt; &amp; bye</pre>"))
    }

    func testRemoteHostsAreForbiddenByDefault() async {
        let remote = FakeFetcher(["": menu])
        let response = await get(makeProxy(local: FakeFetcher(), remote: remote), "/other.example:70/1/")

        XCTAssertEqual(response.status, 403)
        XCTAssertEqual(remote.requestCount, 0)
    }

    func testRemoteHostsOnOtherPortsNeedAllowAllPorts() async {
        let remote = FakeFetcher(["/": menu])
        let denied = await get(
            makeProxy(local: FakeFetcher(), remote: remote, allowRemoteHosts: true),
            "/other.example:7070/1/"
        )
        XCTAssertEqual(denied.status, 403)

        let allowed = await get(
            makeProxy(local: FakeFetcher(), remote: remote, allowRemoteHosts: true, allowAllPorts: true),
            "/other.example:7070/1/"
        )
        XCTAssertEqual(allowed.status, 200)
        XCTAssertEqual(remote.requests.first?.host, "other.example")
        XCTAssertEqual(remote.requests.first?.port, 7070)
    }

    func testSearchShowsFormThenSendsQuery() async {
        let local = FakeFetcher(["/search\thello world": "0Result\t/r.txt\tgopher.example\t70\r\n"])
        let proxy = makeProxy(local: local)

        let form = await get(proxy, "/gopher.example:70/7/search")
        XCTAssertEqual(form.status, 200)
        XCTAssertTrue(body(form).contains("<form class=\"search\" method=\"get\" action=\"/gopher.example:70/7/search\">"))
        XCTAssertEqual(local.requestCount, 0)

        let results = await get(proxy, "/gopher.example:70/7/search?q=hello+world")
        XCTAssertEqual(results.status, 200)
        XCTAssertTrue(body(results).contains("Result"))
    }

    func testSearchQueryCannotInjectRequestLines() async {
        let local = FakeFetcher(["/search\ta  b": ""])
        let response = await get(makeProxy(local: local), "/gopher.example:70/7/search?q=a%0D%0Ab")
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(local.requests.first?.request, "/search\ta  b")
    }

    func testSelectorsWithControlCharactersAreRejected() async {
        let local = FakeFetcher()
        let response = await get(makeProxy(local: local), "/gopher.example:70/0/a%0D%0Aevil")
        XCTAssertEqual(response.status, 404)
        XCTAssertEqual(local.requestCount, 0)
    }

    func testImagesAreServedInlineWithSniffedType() async {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0])
        let local = FakeFetcher(data: ["/cat.png": png])
        let response = await get(makeProxy(local: local), "/gopher.example:70/I/cat.png")

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.header("Content-Type"), "image/png")
        XCTAssertEqual(response.body, png)
    }

    func testBinariesAreAttachmentsWithSafeFilenames() async {
        let local = FakeFetcher(data: ["/files/we\"ird name.zip": Data([1, 2, 3])])
        let response = await get(makeProxy(local: local), "/gopher.example:70/9/files/we%22ird%20name.zip")

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.header("Content-Type"), "application/octet-stream")
        XCTAssertEqual(response.header("Content-Disposition"), "attachment; filename=\"weirdname.zip\"")
    }

    func testDisguisedHTMLIsNotServedInline() async {
        let local = FakeFetcher(["/x.png": "<script>alert(1)</script>"])
        let response = await get(makeProxy(local: local), "/gopher.example:70/I/x.png")
        XCTAssertEqual(response.header("Content-Type"), "application/octet-stream")
        XCTAssertEqual(response.header("X-Content-Type-Options"), "nosniff")
    }

    func testURLItemsRedirectOnlyToSafeSchemes() async {
        let proxy = makeProxy(local: FakeFetcher())

        let redirect = await get(proxy, "/gopher.example:70/hURL:https://example.com/")
        XCTAssertEqual(redirect.status, 302)
        XCTAssertEqual(redirect.header("Location"), "https://example.com/")

        let refused = await get(proxy, "/gopher.example:70/hURL:javascript:alert(1)")
        XCTAssertEqual(refused.status, 400)
        XCTAssertNil(refused.header("Location"))
    }

    func testFetchFailuresReturnBadGateway() async {
        let response = await get(makeProxy(local: FakeFetcher()), "/gopher.example:70/1/missing")
        XCTAssertEqual(response.status, 502)
    }

    func testUnsupportedMethodsAndItemTypes() async {
        let proxy = makeProxy(local: FakeFetcher())
        let post = await proxy.handle(HTTPRequest(method: "POST", target: "/"))
        XCTAssertEqual(post.status, 405)
        XCTAssertEqual(post.header("Allow"), "GET, HEAD")

        let telnet = await get(proxy, "/gopher.example:70/8/")
        XCTAssertEqual(telnet.status, 400)
    }

    func testRemoteResponsesAreCached() async {
        let remote = FakeFetcher(["/": menu])
        let proxy = makeProxy(local: FakeFetcher(), remote: remote, allowRemoteHosts: true, cache: ResponseCache())

        _ = await get(proxy, "/other.example:70/1/")
        _ = await get(proxy, "/other.example:70/1/")
        XCTAssertEqual(remote.requestCount, 1)
    }

    func testRespondSerializesAndOmitsBodyForHEAD() async throws {
        let proxy = makeProxy(local: FakeFetcher(["": menu]))

        let incomplete = await proxy.respond(to: Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8))
        XCTAssertNil(incomplete)

        let getResponse = await proxy.respond(to: Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        let get = try XCTUnwrap(getResponse)
        let getText = String(decoding: get, as: UTF8.self)
        XCTAssertTrue(getText.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(getText.contains("Connection: close\r\n"))
        XCTAssertTrue(getText.contains("<!DOCTYPE html>"))

        let headResponse = await proxy.respond(to: Data("HEAD / HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        let head = try XCTUnwrap(headResponse)
        let headText = String(decoding: head, as: UTF8.self)
        XCTAssertTrue(headText.hasSuffix("\r\n\r\n"))
        XCTAssertFalse(headText.contains("<!DOCTYPE html>"))

        let badResponse = await proxy.respond(to: Data("nonsense\r\n\r\n".utf8))
        let bad = try XCTUnwrap(badResponse)
        XCTAssertTrue(String(decoding: bad, as: UTF8.self).hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }
}

final class GopherLocationTests: XCTestCase {
    func testRoundTripsThroughProxyPath() {
        let locations = [
            GopherLocation(host: "gopher.example", port: 70, type: "1", selector: ""),
            GopherLocation(host: "gopher.example", port: 7070, type: "0", selector: "/a b/c?d#e%f.txt"),
            GopherLocation(host: "::1", port: 70, type: "1", selector: "/x"),
        ]
        for location in locations {
            XCTAssertEqual(GopherLocation(proxyPath: location.proxyPath), location, location.proxyPath)
        }
    }

    func testParsesDefaults() {
        XCTAssertEqual(GopherLocation(proxyPath: "/Gopher.Example"), GopherLocation(host: "gopher.example"))
        XCTAssertEqual(
            GopherLocation(proxyPath: "/[::1]:7070/0/x"),
            GopherLocation(host: "::1", port: 7070, type: "0", selector: "/x")
        )
    }

    func testRejectsInvalidPaths() {
        XCTAssertNil(GopherLocation(proxyPath: "/"))
        XCTAssertNil(GopherLocation(proxyPath: "/host:0/1/"))
        XCTAssertNil(GopherLocation(proxyPath: "/host:99999/1/"))
        XCTAssertNil(GopherLocation(proxyPath: "/ho%20st:70/1/"))
        XCTAssertNil(GopherLocation(proxyPath: "/host:70/0/a%09b"))
        XCTAssertNil(GopherLocation(proxyPath: "/host:70/0/a%0D%0Ab"))
        XCTAssertNil(GopherLocation(proxyPath: "/host:70/0/a%0Ab"))
    }

    func testGopherURL() {
        XCTAssertEqual(
            GopherLocation(host: "gopher.example", type: "0", selector: "/a b.txt").gopherURL,
            "gopher://gopher.example:70/0/a%20b.txt"
        )
    }
}

final class HTTPRequestParserTests: XCTestCase {
    func testParsesRequest() {
        let result = HTTPRequestParser.parse(Data("GET /a?q=x+y%21 HTTP/1.1\r\nHost: Example\r\n\r\n".utf8))
        guard case .complete(let request) = result else {
            return XCTFail("Expected a complete request, got \(result)")
        }
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/a")
        XCTAssertEqual(request.queryValue("q"), "x y!")
        XCTAssertEqual(request.headers["host"], "Example")
    }

    func testIncompleteAndInvalid() {
        XCTAssertEqual(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(Data("GET / SPDY/3\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(HTTPRequestParser.parse(Data("GET http://x/ HTTP/1.1\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(HTTPRequestParser.parse(Data("GET / HTTP/1.1\r\nbroken\r\n\r\n".utf8)), .invalid)
        let huge = Data(repeating: UInt8(ascii: "a"), count: HTTPRequestParser.maxHeaderSize + 1)
        XCTAssertEqual(HTTPRequestParser.parse(huge), .invalid)
    }
}

final class ProxyPolicyTests: XCTestCase {
    func testLocalAlwaysPermitted() {
        let policy = ProxyPolicy(localHost: "Gopher.Example", localPort: 7070)
        XCTAssertTrue(policy.permits(host: "gopher.example", port: 7070))
        XCTAssertFalse(policy.permits(host: "gopher.example", port: 70))
        XCTAssertFalse(policy.permits(host: "other.example", port: 70))
    }

    func testRemotePorts() {
        let policy = ProxyPolicy(localHost: "a", localPort: 70, allowRemoteHosts: true)
        XCTAssertTrue(policy.permits(host: "b", port: 70))
        XCTAssertFalse(policy.permits(host: "b", port: 22))
    }

    func testAddressFilter() {
        for address in [
            "127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0",
            "224.0.0.1", "::1", "::", "fe80::1", "fd00::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1",
            "not-an-ip",
        ] {
            XCTAssertFalse(AddressFilter.isPublic(address), address)
        }
        for address in ["1.1.1.1", "172.32.0.1", "2606:4700:4700::1111", "::ffff:8.8.8.8"] {
            XCTAssertTrue(AddressFilter.isPublic(address), address)
        }
    }

    func testResolvesNumericAddresses() {
        XCTAssertEqual(AddressResolver.resolve(host: "127.0.0.1", port: 70), ["127.0.0.1"])
        XCTAssertEqual(AddressResolver.resolve(host: "::1", port: 70), ["::1"])
    }

    func testRemoteFetcherRefusesPrivateAddresses() async {
        do {
            _ = try await RemoteGopherFetcher().fetch(host: "127.0.0.1", port: 70, request: "")
            XCTFail("Expected loopback to be refused")
        } catch let error as ProxyFetchError {
            guard case .forbiddenAddress = error else {
                return XCTFail("Unexpected error \(error)")
            }
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

final class ResponseCacheTests: XCTestCase {
    func testExpiresAndEvicts() async {
        let cache = ResponseCache(ttl: 10, maxBytes: 4)
        let start = Date()

        await cache.insert(Data([1, 2]), for: "a", now: start)
        let fresh = await cache.value(for: "a", now: start.addingTimeInterval(5))
        XCTAssertEqual(fresh, Data([1, 2]))
        let expired = await cache.value(for: "a", now: start.addingTimeInterval(11))
        XCTAssertNil(expired)

        await cache.insert(Data([1, 2]), for: "a", now: start)
        await cache.insert(Data([3, 4]), for: "b", now: start)
        _ = await cache.value(for: "a", now: start)  // "a" becomes most recently used
        await cache.insert(Data([5, 6]), for: "c", now: start)
        let a = await cache.value(for: "a", now: start)
        let b = await cache.value(for: "b", now: start)
        XCTAssertNotNil(a)
        XCTAssertNil(b)
    }
}
