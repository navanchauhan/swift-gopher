import Foundation
import GopherHelpers
import Logging

final class GopherRequestProcessor {
    private let gopherdataDir: String
    private let gopherdataHost: String
    private let gopherdataPort: Int
    private let logger: Logger
    private let enableSearch: Bool
    private let disableGophermap: Bool

    private let delChar = Character(UnicodeScalar(127))
    private let backspaceChar = Character(UnicodeScalar(8))

    init(
        logger: Logger,
        gopherdataDir: String = "./example-gopherdata",
        gopherdataHost: String = "localhost",
        gopherdataPort: Int = 70,
        enableSearch: Bool = false,
        disableGophermap: Bool = false
    ) {
        self.logger = logger
        self.gopherdataDir = gopherdataDir
        self.gopherdataHost = gopherdataHost
        self.gopherdataPort = gopherdataPort
        self.enableSearch = enableSearch
        self.disableGophermap = disableGophermap
    }

    func process(_ originalRequest: String) -> GopherResponse {
        var request = originalRequest.replacingOccurrences(of: "\r\0", with: "")

        if request.contains(delChar) || request.contains(backspaceChar) {
            request = processDeleteCharacter(request, 127)
            request = processDeleteCharacter(request, 8)
        }

        if request.hasSuffix("\n\n") {
            request = String(request.dropLast())
        }

        if request == "\r\n" || request == "\n" || request == "\r" || request.isEmpty {
            return .menu(prepareGopherMenu(path: preparePath()))
        }

        if request.hasPrefix("URL:") {
            let url = String(request.dropFirst(4))
            return .text(
                "<!DOCTYPE html><html><head><meta http-equiv=\"refresh\" content=\"0; url=\(url)\" /></head><body></body></html>"
            )
        }

        while request.hasSuffix("\n") || request.hasSuffix("\r") {
            request = String(request.dropLast())
        }

        if request.contains("\t") {
            if enableSearch {
                var searchQuery = request.components(separatedBy: "\t")[1]
                searchQuery = searchQuery.replacingOccurrences(of: "\r\n", with: "")
                return .menu(performSearch(query: searchQuery.lowercased()))
            }
            return .menu("3Search is disabled on this server.\r\n")
        }

        return requestHandler(path: preparePath(path: request))
    }

    private func requestHandler(path: URL) -> GopherResponse {
        logger.info("Handling request for '\(path.path)'")

        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: path.path, isDirectory: &isDir) {
            if isDir.boolValue {
                return .menu(prepareGopherMenu(path: path))
            }

            let fileType = getFileType(fileExtension: path.pathExtension)
            if fileType == .text || fileType == .html {
                do {
                    return .text(try String(contentsOfFile: path.path, encoding: .utf8))
                } catch {
                    logger.error("Error reading file: \(path.path) Error: \(error)")
                    return .menu("3Error reading file...\t\terror.host\t1\r\n")
                }
            }

            do {
                return .data(try Data(contentsOf: path))
            } catch {
                logger.error("Error reading binary file: \(path.path) Error: \(error)")
                return .menu("3Error reading file...\t\terror.host\t1\r\n")
            }
        }

        logger.error("Error reading directory: \(path.path) Directory does not exist.")
        return .menu("3Error reading file...\t\terror.host\t1\r\n")
    }

    private func preparePath(path: String = "/") -> URL {
        var sanitizedPath = sanitizeSelectorPath(path: path)
        let baseDir = URL(fileURLWithPath: gopherdataDir)

        if baseDir.path.hasSuffix("/") && sanitizedPath.hasPrefix("/") {
            sanitizedPath = String(sanitizedPath.dropFirst())
        }

        if sanitizedPath.hasPrefix("/") {
            sanitizedPath = String(sanitizedPath.dropFirst())
        }

        return baseDir.appendingPathComponent(sanitizedPath)
    }

    private func generateGopherItem(
        itemName: String,
        itemPath: URL,
        itemHost: String? = nil,
        itemPort: String? = nil
    ) -> String {
        let host = itemHost ?? gopherdataHost
        let port = itemPort ?? String(gopherdataPort)
        let basePath = URL(fileURLWithPath: gopherdataDir)
        var relativePath = itemPath.path.replacingOccurrences(of: basePath.path, with: "")
        if !relativePath.hasPrefix("/") {
            relativePath = "/\(relativePath)"
        }
        return "\(itemName)\t\(relativePath)\t\(host)\t\(port)\r\n"
    }

    private func generateGopherMap(path: URL) -> [String] {
        var items: [String] = []

        do {
            let itemsInDirectory = try FileManager.default.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil
            )

            for item in itemsInDirectory {
                let isDirectory =
                    try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                let name = item.lastPathComponent
                if isDirectory {
                    items.append(generateGopherItem(itemName: "1\(name)", itemPath: item))
                } else {
                    let fileType = getFileType(fileExtension: item.pathExtension)
                    let gopherFileType = fileTypeToGopherItem(fileType: fileType)
                    items.append(generateGopherItem(itemName: "\(gopherFileType)\(name)", itemPath: item))
                }
            }
        } catch {
            logger.error("Error reading directory: \(path.path)")
        }

        return items
    }

    private func prepareGopherMenu(path: URL = URL(fileURLWithPath: "/")) -> String {
        var gopherResponse: [String] = []

        do {
            let gophermapPath = path.appendingPathComponent("gophermap")
            if FileManager.default.fileExists(atPath: gophermapPath.path) && !disableGophermap {
                let contents = try String(contentsOfFile: gophermapPath.path, encoding: .utf8)
                let lines = contents.split(
                    omittingEmptySubsequences: false,
                    whereSeparator: \.isNewline
                ).map(String.init)

                for originalLine in lines {
                    var line = originalLine
                    if "0123456789+gIT:;<dhprsPXi".contains(line.prefix(1)) && line.count > 1 {
                        if line.hasSuffix("\n") {
                            line = String(line.dropLast())
                        }
                        if line.prefix(1) == "i" {
                            gopherResponse.append("\(line)\t\terror.host\t1\r\n")
                            continue
                        }

                        let components = GophermapLineParser.components(from: line)
                        guard components.count >= 3 else {
                            continue
                        }

                        let itemPort = components.count > 3 ? components[3] : "70"
                        gopherResponse.append(
                            "\(components[0])\t\(components[1])\t\(components[2])\t\(itemPort)\r\n"
                        )
                    } else {
                        line = line.replacingOccurrences(of: "\n", with: "")
                        gopherResponse.append("i\(line)\t\terror.host\t1\r\n")
                    }
                }
            } else {
                gopherResponse = generateGopherMap(path: path)
            }
        } catch {
            logger.error("Error reading directory: \(path.path)")
            gopherResponse.append("3Error reading directory...\r\n")
        }

        if enableSearch {
            gopherResponse.append("7Search Server\t/search\t\(gopherdataHost)\t\(gopherdataPort)\r\n")
        }

        gopherResponse.append(buildVersionStringResponse())
        return gopherResponse.joined(separator: "")
    }

    private func performSearch(query: String) -> String {
        var searchResults = [String: String]()
        let baseDir = URL(fileURLWithPath: gopherdataDir)
        let enumerator = FileManager.default.enumerator(at: baseDir, includingPropertiesForKeys: nil)

        while let file = enumerator?.nextObject() as? URL {
            let fileName = file.lastPathComponent
            let filePath = file.path
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if !isDirectory {
                let contents = try? String(contentsOfFile: filePath, encoding: .utf8)
                if fileName.lowercased().contains(query) || (contents?.lowercased().contains(query) ?? false) {
                    searchResults[fileName] = filePath
                }
            } else if fileName.lowercased().contains(query) {
                searchResults[fileName] = filePath
            }
        }

        var gopherResponse: [String] = []
        for (_, filePath) in searchResults {
            let url = URL(fileURLWithPath: filePath)
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let itemType = isDirectory ? "1" : fileTypeToGopherItem(fileType: getFileType(fileExtension: url.pathExtension))
            let itemPath = filePath.replacingOccurrences(of: baseDir.path, with: "")
            gopherResponse.append("\(itemType)\(itemPath)\t\(itemPath)\t\(gopherdataHost)\t\(gopherdataPort)\r\n")
        }

        if gopherResponse.isEmpty {
            gopherResponse.append("iNo results found for the query \(query)\r\n")
        }
        gopherResponse.append(buildVersionStringResponse())
        return gopherResponse.joined(separator: "")
    }

    private func sanitizeSelectorPath(path: String) -> String {
        var sanitizedRequest = path.replacingOccurrences(of: "\r\n", with: "")

        while sanitizedRequest.contains("..") {
            sanitizedRequest = sanitizedRequest.replacingOccurrences(of: "..", with: "")
        }

        while sanitizedRequest.contains("//") {
            sanitizedRequest = sanitizedRequest.replacingOccurrences(of: "//", with: "/")
        }

        return sanitizedRequest
    }

    private func processDeleteCharacter(_ input: String, _ asciiCode: UInt8) -> String {
        var result: [Character] = []
        for character in input {
            if character.asciiValue == asciiCode {
                if !result.isEmpty {
                    result.removeLast()
                }
            } else {
                result.append(character)
            }
        }
        return String(result)
    }
}

enum GophermapLineParser {
    static func components(from line: String) -> [String] {
        var components: [String] = []
        var current = ""
        var pendingSpaces = ""

        func flushCurrent() {
            components.append(current)
            current = ""
            pendingSpaces = ""
        }

        for character in line {
            if character == "\t" {
                flushCurrent()
            } else if character == " " {
                pendingSpaces.append(character)
            } else {
                if pendingSpaces.count >= 2 {
                    flushCurrent()
                } else {
                    current.append(contentsOf: pendingSpaces)
                    pendingSpaces = ""
                }
                current.append(character)
            }
        }

        current.append(contentsOf: pendingSpaces)
        if !current.isEmpty || line.hasSuffix("\t") {
            components.append(current)
        }
        return components
    }
}
