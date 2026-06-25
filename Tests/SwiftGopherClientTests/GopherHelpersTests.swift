import Foundation
import GopherHelpers
import XCTest

final class GopherHelpersTests: XCTestCase {
    func testGopherItemTypeMapping() {
        XCTAssertEqual(getGopherFileType(item: "0"), .text)
        XCTAssertEqual(getGopherFileType(item: "1"), .directory)
        XCTAssertEqual(getGopherFileType(item: "7"), .search)
        XCTAssertEqual(getGopherFileType(item: "9"), .binary)
        XCTAssertEqual(getGopherFileType(item: "g"), .gif)
        XCTAssertEqual(getGopherFileType(item: "I"), .image)
        XCTAssertEqual(getGopherFileType(item: "h"), .html)
        XCTAssertEqual(getGopherFileType(item: "?"), .info)
    }

    func testFileExtensionMapping() {
        XCTAssertEqual(getFileType(fileExtension: "txt"), .text)
        XCTAssertEqual(getFileType(fileExtension: "md"), .text)
        XCTAssertEqual(getFileType(fileExtension: "html"), .html)
        XCTAssertEqual(getFileType(fileExtension: "pdf"), .doc)
        XCTAssertEqual(getFileType(fileExtension: "png"), .image)
        XCTAssertEqual(getFileType(fileExtension: "gif"), .gif)
        XCTAssertEqual(getFileType(fileExtension: "mp3"), .sound)
        XCTAssertEqual(getFileType(fileExtension: "mp4"), .movie)
        XCTAssertEqual(getFileType(fileExtension: "unknown"), .binary)
    }

    func testFileTypeToGopherItemMapping() {
        XCTAssertEqual(fileTypeToGopherItem(fileType: .text), "0")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .directory), "1")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .search), "7")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .binary), "9")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .gif), "g")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .image), "I")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .html), "h")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .info), "i")
    }

    func testItemToImageTypeMapping() {
        var item = gopherItem(rawLine: "0hello")
        item.parsedItemType = .text
        XCTAssertEqual(itemToImageType(item), "doc.plaintext")

        item.parsedItemType = .directory
        XCTAssertEqual(itemToImageType(item), "folder")

        item.parsedItemType = .error
        XCTAssertEqual(itemToImageType(item), "exclamationmark.triangle")

        item.parsedItemType = .binary
        XCTAssertEqual(itemToImageType(item), "questionmark.square.dashed")
    }
}
