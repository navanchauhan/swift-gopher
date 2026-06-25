#if os(Windows)
import Foundation
import GopherHelpers
import Logging
import WinSDK

final class WindowsGopherServer {
    private let host: String
    private let port: Int
    private let processor: GopherRequestProcessor
    private let logger: Logger

    init(
        host: String,
        port: Int,
        logger: Logger,
        gopherdataDir: String,
        gopherdataHost: String,
        enableSearch: Bool,
        disableGophermap: Bool
    ) {
        self.host = host
        self.port = port
        self.logger = logger
        self.processor = GopherRequestProcessor(
            logger: logger,
            gopherdataDir: gopherdataDir,
            gopherdataHost: gopherdataHost,
            gopherdataPort: port,
            enableSearch: enableSearch,
            disableGophermap: disableGophermap
        )
    }

    func run() throws {
        guard WindowsSockets.initialize() else {
            throw GopherServerError.wsaStartupFailed(WSAGetLastError())
        }

        let listenSocket = try WindowsSockets.bind(host: host, port: port)
        defer { closesocket(listenSocket) }

        guard listen(listenSocket, SOMAXCONN) != SOCKET_ERROR else {
            throw GopherServerError.listenFailed(WSAGetLastError())
        }

        logger.info("Server started and listening on \(host):\(port)")

        while true {
            let client = accept(listenSocket, nil, nil)
            if client == INVALID_SOCKET {
                throw GopherServerError.acceptFailed(WSAGetLastError())
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.handle(client: client)
            }
        }
    }

    private func handle(client: SOCKET) {
        defer { closesocket(client) }

        do {
            let request = try readRequest(from: client)
            let response = processor.process(request)
            try write(response: response, to: client)
        } catch {
            logger.error("Client handling failed: \(error)")
        }
    }

    private func readRequest(from socket: SOCKET) throws -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)

        while true {
            let received = buffer.withUnsafeMutableBufferPointer {
                recv(socket, $0.baseAddress!, Int32($0.count), 0)
            }
            if received == 0 {
                break
            }
            if received == SOCKET_ERROR {
                throw GopherServerError.receiveFailed(WSAGetLastError())
            }

            data.append(buffer, count: Int(received))
            if data.contains(10) || data.contains(13) {
                break
            }
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func write(response: ResponseType, to socket: SOCKET) throws {
        let data: Data
        switch response {
        case .string(let string):
            data = Data(string.utf8)
        case .data(let responseData):
            data = responseData
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            var sent = 0
            while sent < data.count {
                let result = send(socket, baseAddress + sent, Int32(data.count - sent), 0)
                if result == SOCKET_ERROR {
                    throw GopherServerError.sendFailed(WSAGetLastError())
                }
                sent += Int(result)
            }
        }
    }
}

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

    func process(_ originalRequest: String) -> ResponseType {
        var request = originalRequest.replacingOccurrences(of: "\r\0", with: "")

        if request.contains(delChar) || request.contains(backspaceChar) {
            request = processDeleteCharacter(request, 127)
            request = processDeleteCharacter(request, 8)
        }

        if request.hasSuffix("\n\n") {
            request = String(request.dropLast())
        }

        if request == "\r\n" || request == "\n" || request == "\r" || request.isEmpty {
            return .string(prepareGopherMenu(path: preparePath()))
        }

        if request.hasPrefix("URL:") {
            let url = String(request.dropFirst(4))
            return .string(
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
                return .string(performSearch(query: searchQuery.lowercased()))
            }
            return .string("3Search is disabled on this server.\r\n")
        }

        return requestHandler(path: preparePath(path: request))
    }

    private func requestHandler(path: URL) -> ResponseType {
        logger.info("Handling request for '\(path.path)'")

        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: path.path, isDirectory: &isDir) {
            if isDir.boolValue {
                return .string(prepareGopherMenu(path: path))
            }

            let fileType = getFileType(fileExtension: path.pathExtension)
            if fileType == .text || fileType == .html {
                do {
                    return .string(try String(contentsOfFile: path.path, encoding: .utf8))
                } catch {
                    logger.error("Error reading file: \(path.path) Error: \(error)")
                    return .string("3Error reading file...\t\terror.host\t1\r\n")
                }
            }

            do {
                return .data(try Data(contentsOf: path))
            } catch {
                logger.error("Error reading binary file: \(path.path) Error: \(error)")
                return .string("3Error reading file...\t\terror.host\t1\r\n")
            }
        }

        logger.error("Error reading directory: \(path.path) Directory does not exist.")
        return .string("3Error reading file...\t\terror.host\t1\r\n")
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
                    whereSeparator: { $0 == "\r" || $0 == "\n" }
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

                        let regex = try NSRegularExpression(pattern: "\\t+| {2,}")
                        let nsString = line as NSString
                        let range = NSRange(location: 0, length: nsString.length)
                        let matches = regex.matches(in: line, range: range)

                        var lastRangeEnd = 0
                        var components = [String]()
                        for match in matches {
                            let range = NSRange(
                                location: lastRangeEnd,
                                length: match.range.location - lastRangeEnd
                            )
                            components.append(nsString.substring(with: range))
                            lastRangeEnd = match.range.location + match.range.length
                        }

                        if lastRangeEnd < nsString.length {
                            components.append(nsString.substring(from: lastRangeEnd))
                        }

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

enum GopherServerError: Error {
    case wsaStartupFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case acceptFailed(Int32)
    case receiveFailed(Int32)
    case sendFailed(Int32)
    case resolveFailed(Int32)
    case socketFailed(Int32)
}

enum WindowsSockets {
    static func initialize() -> Bool {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }

    static func bind(host: String, port: Int) throws -> SOCKET {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP.rawValue
        hints.ai_flags = AI_PASSIVE

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let first = result else {
            throw GopherServerError.resolveFailed(status)
        }
        defer { freeaddrinfo(first) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            let socketHandle = socket(
                info.pointee.ai_family,
                info.pointee.ai_socktype,
                info.pointee.ai_protocol
            )

            if socketHandle != INVALID_SOCKET {
                var reuse: Int32 = 1
                setsockopt(
                    socketHandle,
                    SOL_SOCKET,
                    SO_REUSEADDR,
                    withUnsafePointer(to: &reuse) {
                        UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)
                    },
                    Int32(MemoryLayout<Int32>.size)
                )

                if WinSDK.bind(socketHandle, info.pointee.ai_addr, Int32(info.pointee.ai_addrlen)) == 0 {
                    return socketHandle
                }
                closesocket(socketHandle)
            }

            current = info.pointee.ai_next
        }

        throw GopherServerError.bindFailed(WSAGetLastError())
    }
}
#endif
