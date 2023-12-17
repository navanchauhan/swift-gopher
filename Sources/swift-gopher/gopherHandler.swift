import ArgumentParser
import Foundation
import GopherHelpers
import Logging
import NIO

final class GopherHandler: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer
  typealias OutboundOut = ByteBuffer

  let gopherdata_dir: String
  let gopherdata_host: String
  let gopherdata_port: Int
  let logger: Logger
  let enableSearch: Bool
  let disableGophermap: Bool

  init(
    logger: Logger,
    gopherdata_dir: String = "./example-gopherdata", gopherdata_host: String = "localhost",
    gopherdata_port: Int = 70, enableSearch: Bool = false,
    disableGophermap: Bool = false
  ) {
    self.gopherdata_dir = gopherdata_dir
    self.gopherdata_host = gopherdata_host
    self.gopherdata_port = gopherdata_port
    self.logger = logger
    self.enableSearch = enableSearch
    self.disableGophermap = disableGophermap
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let input = self.unwrapInboundIn(data)

    guard let requestString = input.getString(at: 0, length: input.readableBytes) else {
      return
    }

    if let remoteAddress = context.remoteAddress {
      logger.info(
        "Received request from \(remoteAddress) for '\(requestString.replacingOccurrences(of: "\r\n", with: "<GopherSequence>").replacingOccurrences(of: "\n", with: "<Linebreak>"))'"
      )
    } else {
      logger.warning("Unable to retrieve remote address")
    }

    let response = processGopherRequest(requestString)

    var buffer: ByteBuffer

    switch response {
    case .string(let string):
      buffer = context.channel.allocator.buffer(string: string)
    case .data(let data):
      buffer = context.channel.allocator.buffer(bytes: data)
    }

    context.writeAndFlush(self.wrapOutboundOut(buffer)).whenComplete { _ in
      context.close(mode: .all, promise: nil)
    }
  }

  func requestHandler(path: URL) -> ResponseType {
    logger.info("Handling request for '\(path.path)'")

    // Check if path is a directory or a file
    let fm = FileManager.default
    var isDir: ObjCBool = false

    if fm.fileExists(atPath: path.path, isDirectory: &isDir) {
      if isDir.boolValue {
        return .string(prepareGopherMenu(path: path))
      } else {
        // Check if file is plain text or binary
        let fileExtension = path.pathExtension
        let fileType = getFileType(fileExtension: fileExtension)

        if fileType == .text || fileType == .html {
          do {
            let fileContents = try String(contentsOfFile: path.path, encoding: .utf8)

            return .string(fileContents)
          } catch {
            logger.error("Error reading file: \(path.path) Error: \(error)")
            return .string("3Error reading file...\t\terror.host\t1\r\n")
          }
        } else {
          // Handle binary file
          do {
            let fileContents = try Data(contentsOf: path)
            return .data(fileContents)
          } catch {
            logger.error("Error reading binary file: \(path.path) Error: \(error)")
            return .string("3Error reading file...\t\terror.host\t1\r\n")
          }
        }

      }
    } else {
      logger.error("Error reading directory: \(path.path) Directory does not exist.")
      return .string("3Error reading file...\t\terror.host\t1\r\n")
    }

  }

  func preparePath(path: String = "/") -> URL {
    var sanitizedPath = sanitizeSelectorPath(path: path)
    let base_dir = URL(fileURLWithPath: gopherdata_dir)
    if base_dir.path.hasSuffix("/") && sanitizedPath.hasPrefix("/") {
      sanitizedPath = String(sanitizedPath.dropFirst())
    }

    // Now check if there is still a prefix
    if sanitizedPath.hasPrefix("/") {
      sanitizedPath = String(sanitizedPath.dropFirst())
    }

    let full_path = base_dir.appendingPathComponent(sanitizedPath)
    return full_path
  }

  func generateGopherItem(
    item_name: String, item_path: URL, item_host: String? = nil, item_port: String? = nil
  ) -> String {
    let myItemHost = item_host ?? gopherdata_host
    let myItemPort = item_port ?? String(gopherdata_port)
    let base_path = URL(fileURLWithPath: gopherdata_dir)
    var relative_path = item_path.path.replacingOccurrences(of: base_path.path, with: "")
    if !relative_path.hasPrefix("/") {
      relative_path = "/\(relative_path)"
    }
    return "\(item_name)\t\(relative_path)\t\(myItemHost)\t\(myItemPort)\r\n"
  }

  func generateGopherMap(path: URL) -> [String] {
    var items: [String] = []

    var basePath = URL(fileURLWithPath: gopherdata_dir).path
    if basePath.hasSuffix("/") {
      basePath = String(basePath.dropLast())
    }

    let fm = FileManager.default
    do {
      print("Reading directory: \(path.path)")
      let itemsInDirectory = try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
      for item in itemsInDirectory {
        let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        let name = item.lastPathComponent
        if isDirectory {
          items.append(generateGopherItem(item_name: "1\(name)", item_path: item))
        } else {
          let fileType = getFileType(fileExtension: item.pathExtension)
          let gopherFileType = fileTypeToGopherItem(fileType: fileType)
          items.append(generateGopherItem(item_name: "\(gopherFileType)\(name)", item_path: item))
        }
      }
    } catch {
      print("Error reading directory: \(path.path)")
    }
    return items
  }

  func prepareGopherMenu(path: URL = URL(string: "/")!) -> String {
    var gopherResponse: [String] = []

    let fm = FileManager.default

    do {
      let gophermap_path = path.appendingPathComponent("gophermap")
      if fm.fileExists(atPath: gophermap_path.path) && !disableGophermap {
        let gophermap_contents = try String(contentsOfFile: gophermap_path.path, encoding: .utf8)
        let gophermap_lines = gophermap_contents.components(separatedBy: "\n")
        for originalLine in gophermap_lines {
          // Only keep first 80 characters
          var line = String(originalLine)  //.prefix(80)
          if "0123456789+gIT:;<dhprsPXi".contains(line.prefix(1)) && line.count > 1 {
            if line.hasSuffix("\n") {
              line = String(line.dropLast())
            }
            if line.prefix(1) == "i" {
              gopherResponse.append("\(line)\t\terror.host\t1\r\n")
              continue
            }

            let regex = try! NSRegularExpression(pattern: "\\t+| {2,}")
            let nsString = line as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: String(line), range: range)

            var lastRangeEnd = 0
            var components = [String]()

            for match in matches {
              let range = NSRange(
                location: lastRangeEnd, length: match.range.location - lastRangeEnd)
              components.append(nsString.substring(with: range))
              lastRangeEnd = match.range.location + match.range.length
            }

            if lastRangeEnd < nsString.length {
              components.append(nsString.substring(from: lastRangeEnd))
            }

            if components.count < 3 {
              continue
            }

            let item_name = components[0]
            let item_path = components[1]
            let item_host = components[2]
            let item_port = components.count > 3 ? components[3] : "70"

            let item_line = "\(item_name)\t\(item_path)\t\(item_host)\t\(item_port)\r\n"
            gopherResponse.append(item_line)
          } else {
            line = line.replacingOccurrences(of: "\n", with: "")
            gopherResponse.append("i\(line)\t\terror.host\t1\r\n")
          }
        }
      } else {
        print("No gophermap found for \(path.path)")
        gopherResponse = generateGopherMap(path: path)
      }
    } catch {
      logger.error("Error reading directory: \(path.path)")
      gopherResponse.append("3Error reading directory...\r\n")
    }

    // Append Search
    if enableSearch {
      let search_line = "7Search Server\t/search\t\(gopherdata_host)\t\(gopherdata_port)\r\n"
      gopherResponse.append(search_line)
    }

    // Append Server Info
    gopherResponse.append(buildVersionStringResponse())

    return gopherResponse.joined(separator: "")
  }

  // TODO: Refactor
  func performSearch(query: String) -> String {
    // Really basic search implementation

    var search_results = [String: String]()

    let fm = FileManager.default

    let base_dir = URL(fileURLWithPath: gopherdata_dir)

    let enumerator = fm.enumerator(at: base_dir, includingPropertiesForKeys: nil)

    while let file = enumerator?.nextObject() as? URL {
      let file_name = file.lastPathComponent
      let file_path = file.path
      let file_type =
        try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false ? "1" : "0"

      if file_type == "0" {
        // Check if file name or contents match the query
        let file_contents = try? String(contentsOfFile: file_path, encoding: .utf8)
        if file_name.lowercased().contains(query)
          || (file_contents?.lowercased().contains(query) ?? false)
        {
          search_results[file_name] = file_path
        }
      } else {
        // Check if directory name matches the query
        if file_name.lowercased().contains(query) {
          search_results[file_name] = file_path
        }
      }
    }

    // Prepare Gopher menu with search results
    var gopherResponse: [String] = []

    for (_, file_path) in search_results {
      let item_type =
        try? URL(fileURLWithPath: file_path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        ?? false ? "1" : "0"
      let item_host = gopherdata_host
      let item_port = gopherdata_port
      let item_path = file_path.replacingOccurrences(of: base_dir.path, with: "")
      let item_line =
        "\(item_type ?? "0")\(item_path)\t\(item_path)\t\(item_host)\t\(item_port)\r\n"
      gopherResponse.append(item_line)
    }

    if gopherResponse.count == 0 {
      gopherResponse.append("iNo results found for the query \(query)\r\n")
    }
    gopherResponse.append(buildVersionStringResponse())
    return gopherResponse.joined(separator: "")

  }

  func sanitizeSelectorPath(path: String) -> String {
    // Replace \r\n with empty string
    var sanitizedRequest = path.replacingOccurrences(of: "\r\n", with: "")

    // Basic escape against directory traversal
    while sanitizedRequest.contains("..") {
      sanitizedRequest = sanitizedRequest.replacingOccurrences(of: "..", with: "")
    }

    while sanitizedRequest.contains("//") {
      sanitizedRequest = sanitizedRequest.replacingOccurrences(of: "//", with: "/")
    }

    return sanitizedRequest
  }

  func channelReadComplete(context: ChannelHandlerContext) {
    context.flush()
  }

  func errorCaught(context: ChannelHandlerContext, error: Error) {
    print("Error: \(error)")
    logger.error("Error: \(error)")
    context.close(promise: nil)
  }

  private func processGopherRequest(_ originalRequest: String) -> ResponseType {
    var request = originalRequest

    // Fix for "Gopher" (iOS) client sending an extra \n
    if request.hasSuffix("\n\n") {
      request = String(request.dropLast())
    }

    if request == "\r\n" {  // Empty request
      return .string(prepareGopherMenu(path: preparePath()))
    }

    // Again, fix for the iOS client. Might as well make my own client
    if request.hasSuffix("\n") {
      request = String(request.dropLast())
    }

    if request.contains("\t") {
      if enableSearch {
        var searchQuery = request.components(separatedBy: "\t")[1]
        searchQuery = searchQuery.replacingOccurrences(of: "\r\n", with: "")
        return .string(performSearch(query: searchQuery.lowercased()))
      } else {
        return .string("3Search is disabled on this server.\r\n")
      }
    }

    //TODO: Potential Bug in Gopher implementation? curl gopher://localhost:8080/new_folder/ does not work but curl gopher://localhost:8080//new_folder/ works (tested with gopher://gopher.meulie.net//EFFector/ as well)
    return requestHandler(path: preparePath(path: request))
  }
}
