import Foundation
import GopherHelpers

/// Parses raw gopher menu responses into `GopherItem`s.
public enum GopherResponseParser {
    public static func parse(data: Data) -> [GopherItem] {
        // Decode leniently so menus with stray non-UTF-8 bytes still parse.
        let response = String(decoding: data, as: UTF8.self)
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
        itemType: GopherItemType = .info,
        rawData: Data
    ) -> GopherItem {
        var item = GopherItem(rawLine: rawLine)
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
