//
//  swiftGopherServerTests.swift
//
//
//  Created by Navan Chauhan on 7/28/24.
//

import ArgumentParser
import NIO
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

}
