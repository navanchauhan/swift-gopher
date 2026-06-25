//
//  swiftGopherClientTests.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import XCTest

@testable import SwiftGopherClient

final class GopherClientTests: XCTestCase {

    var client: GopherClient!

    override func setUp() {
        super.setUp()
        client = GopherClient()
    }

    override func tearDown() {
        client = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(client, "GopherClient should be initialized successfully")
    }

    func testSendRequestCompletion() {
        let expectation = XCTestExpectation(description: "Send request completion")

        client.sendRequest(to: "gopher.navan.dev", message: "\r\n") { result in
            switch result {
            case .success(let items):
                XCTAssertFalse(items.isEmpty, "Response should contain gopher items")
            case .failure(let error):
                XCTFail("Request failed with error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }

    @available(iOS 13.0, macOS 10.15, *)
    func testSendRequestAsync() async throws {
        do {
            let items = try await client.sendRequest(to: "gopher.navan.dev", message: "\r\n")
            XCTAssertFalse(items.isEmpty, "Response should contain gopher items")
        } catch {
            XCTFail("Async request failed with error: \(error)")
        }
    }

    func testInvalidPort() {
        let expectation = XCTestExpectation(description: "Invalid port request")

        client.sendRequest(to: "localhost", port: Int(UInt16.max) + 1, message: "") { result in
            switch result {
            case .success:
                XCTFail("Request should fail for invalid port")
            case .failure(let error):
                XCTAssertTrue(error is GopherClientError)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testCustomPort() {
        let expectation = XCTestExpectation(description: "Custom port request")

        client.sendRequest(to: "gopher.navan.dev", port: 70, message: "\r\n") { result in
            switch result {
            case .success(let items):
                XCTAssertFalse(items.isEmpty, "Response should contain gopher items")
            case .failure(let error):
                XCTFail("Request failed with error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)
    }
}
