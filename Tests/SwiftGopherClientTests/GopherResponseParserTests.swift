import Foundation
import XCTest

@testable import SwiftGopherClient

final class GopherResponseParserTests: XCTestCase {
    func testParsesCrLfDelimitedDirectoryResponse() {
        let response =
            "1Example\t/example\tlocalhost\t70\r\n"
            + "0Read me\t/readme.txt\tlocalhost\t70\r\n"
            + "iInfo line\t\terror.host\t1\r\n"

        let items = GopherResponseParser.parse(data: Data(response.utf8))

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].parsedItemType, .directory)
        XCTAssertEqual(items[0].message, "Example")
        XCTAssertEqual(items[0].selector, "/example")
        XCTAssertEqual(items[0].host, "localhost")
        XCTAssertEqual(items[0].port, 70)
        XCTAssertEqual(items[1].parsedItemType, .text)
        XCTAssertEqual(items[2].parsedItemType, .info)
    }

    func testParsesLfDelimitedResponse() {
        let response = "hWebsite\tURL:https://example.com\texample.com\t70\n"
        let items = GopherResponseParser.parse(data: Data(response.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].parsedItemType, .html)
        XCTAssertEqual(items[0].message, "Website")
        XCTAssertEqual(items[0].selector, "URL:https://example.com")
    }

    func testDefaultsMissingFields() {
        let response = "iJust info\r\n"
        let items = GopherResponseParser.parse(data: Data(response.utf8))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].message, "Just info")
        XCTAssertEqual(items[0].host, "error.host")
        XCTAssertEqual(items[0].port, 1)
        XCTAssertEqual(items[0].selector, "")
        XCTAssertNotNil(items[0].rawData)
    }

    func testParsesMediaItemTypes() {
        let response =
            "gAnimation\t/animation.gif\tlocalhost\t70\r\n"
            + "IPhoto\t/photo.png\tlocalhost\t70\r\n"
            + ":Bitmap\t/bitmap.bmp\tlocalhost\t70\r\n"
            + ";Video\t/video.mp4\tlocalhost\t70\r\n"
            + "<Audio\t/audio.mp3\tlocalhost\t70\r\n"

        let items = GopherResponseParser.parse(data: Data(response.utf8))

        XCTAssertEqual(items.map(\.parsedItemType), [.gif, .image, .bitmap, .movie, .sound])
        XCTAssertEqual(items.map(\.selector), [
            "/animation.gif",
            "/photo.png",
            "/bitmap.bmp",
            "/video.mp4",
            "/audio.mp3",
        ])
    }
}
