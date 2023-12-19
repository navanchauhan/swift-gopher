import Foundation

let versionString = "generated and served by swift-gopher/1.0.0"  // TODO: Handle automatic versioning

func buildVersionStringResponse() -> String {
  let repeatedString = "i" + String(repeating: "-", count: 72) + "\t\terror.host\t1\r\n"
  let versionResponseString =
    "i" + String(repeating: " ", count: 72 - versionString.count) + versionString
    + "\t\terror.host\t1\r\n"
  return "\(repeatedString)\(versionResponseString)"
}

enum ResponseType {
  case string(String)
  case data(Data)
}
