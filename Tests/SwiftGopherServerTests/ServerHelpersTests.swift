import XCTest

@testable import swift_gopher

final class ServerHelpersTests: XCTestCase {
    func testVersionStringUsesV3() {
        XCTAssertEqual(versionString, "generated and served by swift-gopher/3.0.3")
    }

    func testBuildVersionStringResponseUsesInfoLines() {
        let response = buildVersionStringResponse()

        XCTAssertTrue(response.contains("generated and served by swift-gopher/3.0.3"))
        XCTAssertTrue(response.hasPrefix("i"))
        XCTAssertTrue(response.hasSuffix("\r\n"))
    }
}
