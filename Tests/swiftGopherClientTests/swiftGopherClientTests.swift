//
//  swiftGopherClientTests.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import NIO
import XCTest

@testable import swiftGopherClient

final class GopherClientTests: XCTestCase {

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    super.tearDown()
  }

  func testGopherServerConnection() {
    let expectation = XCTestExpectation(
      description: "Connect and receive response from Gopher server")
    let client = GopherClient()
    client.sendRequest(to: "gopher.floodgap.com", message: "\r\n") { result in
      switch result {
      case .success(_):
        expectation.fulfill()
      case .failure(let error):
        print("Error \(error)")
      }
    }

    wait(for: [expectation], timeout: 30)
  }
}
