import Foundation
import GopherHelpers

enum GopherResponseParser {
    static func parse(data: Data) -> [gopherItem] {
        let response = String(data: data, encoding: .utf8) ?? ""
        let lines = response.split(whereSeparator: \.isNewline)

        return lines.map { line in
            let rawLine = String(line).trimmingCharacters(in: .newlines)
            return createGopherItem(
                rawLine: rawLine,
                itemType: getGopherFileType(item: "\(rawLine.first ?? " ")"),
                rawData: data
            )
        }
    }

    private static func createGopherItem(
        rawLine: String,
        itemType: gopherItemType = .info,
        rawData: Data
    ) -> gopherItem {
        var item = gopherItem(rawLine: rawLine)
        item.parsedItemType = itemType
        item.rawData = rawData

        if rawLine.isEmpty {
            item.valid = false
        } else {
            let components = rawLine.components(separatedBy: "\t")
            item.message = String(components[0].dropFirst())

            if components.indices.contains(1) {
                item.selector = components[1]
            }

            if components.indices.contains(2) {
                item.host = components[2]
            }

            if components.indices.contains(3) {
                item.port = Int(components[3]) ?? 70
            }
        }

        return item
    }
}
