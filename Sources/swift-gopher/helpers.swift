import Foundation

let versionString = "generated and served by swift-gopher/3.0.0"  // TODO: Handle automatic versioning

func buildVersionStringResponse() -> String {
    let repeatedString = "i" + String(repeating: "-", count: 72) + "\t\terror.host\t1\r\n"
    let versionResponseString =
        "i" + String(repeating: " ", count: 72 - versionString.count) + versionString
        + "\t\terror.host\t1\r\n"
    return "\(repeatedString)\(versionResponseString)"
}

enum GopherResponse {
    case menu(String)
    case text(String)
    case data(Data)

    var data: Data {
        switch self {
        case .menu(let string), .text(let string):
            return Data(string.utf8)
        case .data(let data):
            return data
        }
    }
}
