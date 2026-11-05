//
//  swiftGopherServerTests.swift
//
//
//  Created by Navan Chauhan on 7/28/24.
//

import ArgumentParser
import GopherProxy
import Logging
import XCTest

@testable import swift_gopher

final class SwiftGopherTests: XCTestCase {

    func testDefaultValues() throws {
        let gopher = try swiftGopher.parse([])

        XCTAssertEqual(gopher.gopherHostName, "localhost")
        XCTAssertEqual(gopher.host, "0.0.0.0")
        XCTAssertEqual(gopher.port, 8080)
        XCTAssertEqual(gopher.gopherDataDir, "./example-gopherdata")
        XCTAssertFalse(gopher.disableSearch)
        XCTAssertFalse(gopher.disableGophermap)
        XCTAssertNil(gopher.httpPort)
        XCTAssertFalse(gopher.httpAllowRemoteHosts)
        XCTAssertFalse(gopher.httpAllowAllPorts)
        XCTAssertNil(gopher.httpHeadMarkup)
        XCTAssertNil(gopher.httpContentSecurityPolicy)
    }

    func testCustomValues() throws {
        let args = [
            "--gopher-host-name", "example.com",
            "--host", "127.0.0.1",
            "--port", "9090",
            "--gopher-data-dir", "/custom/path",
            "--disable-search",
            "--disable-gophermap",
        ]

        let gopher = try swiftGopher.parse(args)

        XCTAssertEqual(gopher.gopherHostName, "example.com")
        XCTAssertEqual(gopher.host, "127.0.0.1")
        XCTAssertEqual(gopher.port, 9090)
        XCTAssertEqual(gopher.gopherDataDir, "/custom/path")
        XCTAssertTrue(gopher.disableSearch)
        XCTAssertTrue(gopher.disableGophermap)
    }

    func testShortOptions() throws {
        let args = [
            "-g", "short.com",
            "-h", "192.168.1.1",
            "-p", "7070",
            "-d", "/short/path",
        ]

        let gopher = try swiftGopher.parse(args)

        XCTAssertEqual(gopher.gopherHostName, "short.com")
        XCTAssertEqual(gopher.host, "192.168.1.1")
        XCTAssertEqual(gopher.port, 7070)
        XCTAssertEqual(gopher.gopherDataDir, "/short/path")
    }

    func testHTTPProxyOptions() throws {
        let gopher = try swiftGopher.parse([
            "--http-port", "8081",
            "--http-allow-remote-hosts",
            "--http-allow-all-ports",
            "--http-head-markup", "<meta name=\"test\">",
            "--http-content-security-policy", "default-src 'none'",
        ])

        XCTAssertEqual(gopher.httpPort, 8081)
        XCTAssertTrue(gopher.httpAllowRemoteHosts)
        XCTAssertTrue(gopher.httpAllowAllPorts)
        XCTAssertEqual(gopher.httpHeadMarkup, "<meta name=\"test\">")
        XCTAssertEqual(gopher.httpContentSecurityPolicy, "default-src 'none'")
    }

    func testHTTPProxyOptionsReachGeneratedResponses() async throws {
        let command = try swiftGopher.parse([
            "--http-port", "8081", "--http-head-markup", "<meta name=\"custom\">",
            "--http-content-security-policy", "default-src 'none'",
        ])
        let proxy = command.makeProxy(logger: Logger(label: "test"))
        let response = await proxy.handle(HTTPRequest(method: "GET", target: "/invalid:0/1/"))
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("<meta name=\"custom\">\n</head>"))
        XCTAssertEqual(response.header("Content-Security-Policy"), "default-src 'none'")
    }

    func testHTTPProxyOptionValidation() {
        XCTAssertThrowsError(try swiftGopher.parse(["--http-head-markup", "<meta>"]))
        XCTAssertThrowsError(try swiftGopher.parse(["--http-content-security-policy", "default-src 'none'"]))
        for separator in ["\r", "\n", "\r\n"] {
            XCTAssertThrowsError(try swiftGopher.parse(["--http-port", "8081", "--http-content-security-policy", "x\(separator)Injected: yes"]))
        }
        XCTAssertThrowsError(try swiftGopher.parse(["--http-port", "8080"]))
        XCTAssertThrowsError(try swiftGopher.parse(["--http-port", "70000"]))
        XCTAssertThrowsError(try swiftGopher.parse(["--http-allow-remote-hosts"]))
        XCTAssertThrowsError(try swiftGopher.parse(["--http-port", "8081", "--http-allow-all-ports"]))
    }
}
