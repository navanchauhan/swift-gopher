import Foundation

let versionString = "generated and served by swift-gopher/1.0.0" // TODO: Handle automatic versioning

func buildVersionStringResponse() -> String {
    let repeatedString = "i" + String(repeating: "-", count: 80) + "\terror.host\t1\r\n"
    let versionResponseString = "i" + String(repeating: " ", count: 80 - versionString.count) + versionString + "\terror.host\t1\r\n"
    return "\(repeatedString)\(versionResponseString)"
}