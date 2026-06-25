#if os(Windows)
import Foundation
import Logging
import XCTest

@testable import swift_gopher

final class WindowsGopherRequestProcessorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try "Hello from text".write(
            to: tempDirectory.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0, 1, 2, 3]).write(to: tempDirectory.appendingPathComponent("image.png"))
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("folder"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testServesTextFile() {
        let response = processor().process("/hello.txt\r\n")

        guard case .text(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertEqual(body, "Hello from text")
    }

    func testServesBinaryFile() {
        let response = processor().process("/image.png\r\n")

        guard case .data(let data) = response else {
            return XCTFail("Expected data response")
        }
        XCTAssertEqual(data, Data([0, 1, 2, 3]))
    }

    func testGeneratesDirectoryMenuWithoutGophermap() {
        let response = processor().process("\r\n")

        guard case .menu(let menu) = response else {
            return XCTFail("Expected menu response")
        }
        XCTAssertTrue(menu.contains("0hello.txt\t/hello.txt\texample.test\t7070\r\n"))
        XCTAssertTrue(menu.contains("Iimage.png\t/image.png\texample.test\t7070\r\n"))
        XCTAssertTrue(menu.contains("1folder\t/folder\texample.test\t7070\r\n"))
        XCTAssertTrue(menu.contains("generated and served by swift-gopher/3.0.0"))
    }

    func testReadsGophermapWhenEnabled() throws {
        try "iWelcome\r\n1Folder\t/folder\texample.test\t7070\r\n".write(
            to: tempDirectory.appendingPathComponent("gophermap"),
            atomically: true,
            encoding: .utf8
        )

        let response = processor().process("\r\n")

        guard case .menu(let menu) = response else {
            return XCTFail("Expected menu response")
        }
        XCTAssertTrue(menu.contains("Welcome"))
        XCTAssertTrue(menu.contains("1Folder\t/folder\texample.test\t7070\r\n"))
    }

    func testCanDisableGophermap() throws {
        try "iOnly in map\r\n".write(
            to: tempDirectory.appendingPathComponent("gophermap"),
            atomically: true,
            encoding: .utf8
        )

        let response = processor(disableGophermap: true).process("\r\n")

        guard case .menu(let menu) = response else {
            return XCTFail("Expected menu response")
        }
        XCTAssertFalse(menu.contains("Only in map"))
        XCTAssertTrue(menu.contains("0hello.txt"))
    }

    func testReturnsErrorForMissingPath() {
        let response = processor().process("/missing.txt\r\n")

        guard case .menu(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertTrue(body.hasPrefix("3Error reading file"))
    }

    func testUrlRedirectResponse() {
        let response = processor().process("URL:https://example.com\r\n")

        guard case .text(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertTrue(body.contains("https://example.com"))
        XCTAssertTrue(body.contains("meta http-equiv=\"refresh\""))
    }

    func testSearchDisabledResponse() {
        let response = processor(enableSearch: false).process("/search\tHello\r\n")

        guard case .menu(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertEqual(body, "3Search is disabled on this server.\r\n")
    }

    func testSearchEnabledResponse() {
        let response = processor(enableSearch: true).process("/search\thello\r\n")

        guard case .menu(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertTrue(body.contains("hello.txt"))
        XCTAssertTrue(body.contains("generated and served by swift-gopher/3.0.0"))
    }

    func testSanitizesTraversal() {
        let response = processor().process("/../hello.txt\r\n")

        guard case .text(let body) = response else {
            return XCTFail("Expected string response")
        }
        XCTAssertEqual(body, "Hello from text")
    }

    private func processor(
        enableSearch: Bool = false,
        disableGophermap: Bool = false
    ) -> GopherRequestProcessor {
        GopherRequestProcessor(
            logger: Logger(label: "test.windows.gopher.processor"),
            gopherdataDir: tempDirectory.path,
            gopherdataHost: "example.test",
            gopherdataPort: 7070,
            enableSearch: enableSearch,
            disableGophermap: disableGophermap
        )
    }
}
#endif
