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
        XCTAssertEqual(getGopherFileType(item: ":"), .bitmap)
        XCTAssertEqual(getGopherFileType(item: ";"), .movie)
        XCTAssertEqual(getGopherFileType(item: "<"), .sound)
        XCTAssertEqual(getGopherFileType(item: "h"), .html)
        XCTAssertEqual(getGopherFileType(item: "?"), .info)
    }

    func testLegacyMediaGopherItemTypeAliases() {
        XCTAssertEqual(getGopherFileType(item: "b"), .bitmap)
        XCTAssertEqual(getGopherFileType(item: "M"), .movie)
        XCTAssertEqual(getGopherFileType(item: "s"), .sound)
    }

    func testFileExtensionMapping() {
        XCTAssertEqual(getFileType(fileExtension: "txt"), .text)
        XCTAssertEqual(getFileType(fileExtension: "md"), .text)
        XCTAssertEqual(getFileType(fileExtension: "html"), .html)
        XCTAssertEqual(getFileType(fileExtension: "pdf"), .doc)
        XCTAssertEqual(getFileType(fileExtension: "png"), .image)
        XCTAssertEqual(getFileType(fileExtension: "BMP"), .bitmap)
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
        XCTAssertEqual(fileTypeToGopherItem(fileType: .bitmap), ":")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .movie), ";")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .sound), "<")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .html), "h")
        XCTAssertEqual(fileTypeToGopherItem(fileType: .info), "i")
    }

    func testFileTypesRoundTripThroughGopherItemCodes() {
        let roundTrippableTypes: [GopherItemType] = [
            .text,
            .directory,
            .nameserver,
            .error,
            .binhex,
            .bindos,
            .uuencoded,
            .search,
            .telnet,
            .binary,
            .mirror,
            .gif,
            .image,
            .tn3270Session,
            .bitmap,
            .movie,
            .sound,
            .doc,
            .html,
            .info,
        ]

        for type in roundTrippableTypes {
            let itemCode = fileTypeToGopherItem(fileType: type)
            XCTAssertEqual(getGopherFileType(item: itemCode), type)
        }
    }

    func testItemToImageTypeMapping() {
        var item = GopherItem(rawLine: "0hello")
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
