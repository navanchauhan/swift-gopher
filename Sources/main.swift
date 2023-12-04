// The Swift Programming Language
// https://docs.swift.org/swift-book

import ArgumentParser
import Foundation
import Logging
import NIO

@main
struct swiftGopher: ParsableCommand {
  @Option var gopherHostName: String = "localhost"
  @Option var port: Int = 8080
  @Option var gopherDataDir: String = "./example-gopherdata"
  @Option var host: String = "0.0.0.0"

  public mutating func run() throws {
    let eventLoopGroup = MultiThreadedEventLoopGroup(
      numberOfThreads: System.coreCount
    )

    defer {
      try! eventLoopGroup.syncShutdownGracefully()
    }

    let localGopherDataDir = gopherDataDir
    let localGopherHostName = gopherHostName
    let localPort = port

    let logger = Logger(label: "com.navanchauhan.gopher.server")

    let serverBootstrap = ServerBootstrap(
      group: eventLoopGroup
    )
    .serverChannelOption(
      ChannelOptions.backlog,
      value: 256
    )
    .serverChannelOption(
      ChannelOptions.socketOption(
        .so_reuseaddr
      ),
      value: 1
    )
    .childChannelInitializer { channel in
      channel.pipeline.addHandlers([
        BackPressureHandler(),
        GopherHandler(
             logger: logger,
          gopherdata_dir: localGopherDataDir,
          gopherdata_host: localGopherHostName,
          gopherdata_port: localPort
        ),
      ])
    }
    .childChannelOption(
      ChannelOptions.socketOption(
        .so_reuseaddr
      ),
      value: 1
    )
    .childChannelOption(
      ChannelOptions.maxMessagesPerRead,
      value: 16
    )
    .childChannelOption(
      ChannelOptions.recvAllocator,
      value: AdaptiveRecvByteBufferAllocator()
    )

    let defaultHost = host
    let defaultPort = port

    let channel = try serverBootstrap.bind(
      host: defaultHost,
      port: defaultPort
    ).wait()

    logger.info("Server started and listening on \(channel.localAddress!)")
    try channel.closeFuture.wait()
    logger.info("Server closed")
  }
}

enum ResponseType {
  case string(String)
  case data(Data)
}

enum gopherFileType {
  case text
  case directory
  case nameserver
  case error
  case binhex
  case bindos
  case uuencoded
  case indexSearch
  case telnet
  case binary
  case redundantServer
  case tn3270Session
  case gif
  case image
  case bitmap
  case movie
  case sound
  case doc
  case html
  case message
  case png
  case rtf
  case wavfile
  case pdf
  case xml
}

func getFileType(fileExtension: String) -> gopherFileType {
  switch fileExtension {
  case "txt":
    return .text
  case "md":
    return .text
  case "html":
    return .html
  case "pdf":
    return .pdf
  case "png":
    return .png
  case "gif":
    return .gif
  case "jpg":
    return .image
  case "jpeg":
    return .image
  case "mp3":
    return .sound
  case "wav":
    return .wavfile
  case "mp4":
    return .movie
  case "mov":
    return .movie
  case "avi":
    return .movie
  case "rtf":
    return .rtf
  case "xml":
    return .xml
  default:
    return .binary
  }
}

func fileTypeToGopherItem(fileType: gopherFileType) -> String {
  switch fileType {
  case .text:
    return "0"
  case .directory:
    return "1"
  case .nameserver:
    return "2"
  case .error:
    return "3"
  case .binhex:
    return "4"
  case .bindos:
    return "5"
  case .uuencoded:
    return "6"
  case .indexSearch:
    return "7"
  case .telnet:
    return "8"
  case .binary:
    return "9"
  case .redundantServer:
    return "+"
  case .tn3270Session:
    return "T"
  case .gif:
    return "g"
  case .image:
    return "I"
  case .bitmap:
    return "b"
  case .movie:
    return "M"
  case .sound:
    return "s"
  case .doc:
    return "d"
  case .html:
    return "h"
  case .message:
    return "i"
  case .png:
    return "p"
  case .rtf:
    return "t"
  case .wavfile:
    return "w"
  case .pdf:
    return "P"
  case .xml:
    return "x"
  }
}

final class GopherHandler: ChannelInboundHandler {
  typealias InboundIn = ByteBuffer
  typealias OutboundOut = ByteBuffer

  let gopherdata_dir: String
  let gopherdata_host: String
  let gopherdata_port: Int
  let logger: Logger

  init(
    logger: Logger,
    gopherdata_dir: String = "./example-gopherdata", gopherdata_host: String = "localhost",
    gopherdata_port: Int = 70
  ) {
    self.gopherdata_dir = gopherdata_dir
    self.gopherdata_host = gopherdata_host
    self.gopherdata_port = gopherdata_port
    self.logger = logger
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let input = self.unwrapInboundIn(data)

    guard let requestString = input.getString(at: 0, length: input.readableBytes) else {
      return
    }

    if let remoteAddress = context.remoteAddress {
        logger.info("Received request from \(remoteAddress) for \(requestString)")
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
            logger.error("Error reading file: \(path.path)")
            return .string("3Error reading file...\r\n")
          }
        } else {
          // Handle binary file
          do {
            let fileContents = try Data(contentsOf: path)
            return .data(fileContents)
          } catch {
            logger.error("Error reading file: \(path.path)")
            return .string("3Error reading file...\r\n")
          }
        }

      }
    } else {
      logger.error("Error reading file: \(path.path)")
      return .string("3Error reading file...\r\n")
    }

  }

  func preparePath(path: String = "/") -> URL {
    var sanitizedPath = sanitizeSelectorPath(path: path)
    let base_dir = URL(fileURLWithPath: gopherdata_dir)
    if base_dir.path.hasSuffix("/") && sanitizedPath.hasPrefix("/") {
      sanitizedPath = String(sanitizedPath.dropFirst())
    }
    let full_path = base_dir.appendingPathComponent(sanitizedPath)
    return full_path
  }

  func prepareGopherMenu(path: URL = URL(string: "/")!) -> String {
    var gopherResponse: [String] = []

    let fm = FileManager.default
    let absolute_base_path = URL(fileURLWithPath: gopherdata_dir)
    let relative_path = path.path.replacingOccurrences(of: absolute_base_path.path, with: "")

    do {
      let gophermap_path = path.appendingPathComponent("gophermap")
      if fm.fileExists(atPath: gophermap_path.path) {
        let gophermap_contents = try String(contentsOfFile: gophermap_path.path, encoding: .utf8)
        let gophermap_lines = gophermap_contents.components(separatedBy: "\n")
        for originalLine in gophermap_lines {
          // Only keep first 80 characters
          var line = String(originalLine)//.prefix(80)
           if "0123456789+gIT:;<dhprsPXi".contains(line.prefix(1)) && line.count > 1 {
            if line.hasSuffix("\n") {
              line = String(line.dropLast())
            }
            if line.prefix(1) == "i" {
              gopherResponse.append("\(line)\r\n")
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
            gopherResponse.append("i\(line)\r\n")
          }
        }
      } else {
        let items = try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)

        for item in items {
          let item_name = item.lastPathComponent
          var item_type = ""
          if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false {
            item_type = "1"
          } else {
            let fileType = getFileType(fileExtension: item.pathExtension)
            item_type = fileTypeToGopherItem(fileType: fileType)
          }
          let item_path = "\(relative_path)\(relative_path.hasSuffix("/") ? "" : "/")\(item_name)"
            .replacingOccurrences(of: "//", with: "/")
          let item_host = gopherdata_host
          let item_port = gopherdata_port
          let item_line = "\(item_type)\(item_name)\t\(item_path)\t\(item_host)\t\(item_port)\r\n"
          gopherResponse.append(item_line)
        }
      }
    } catch {
      logger.error("Error reading directory: \(path.path)")
      gopherResponse.append("3Error reading directory...\r\n")
    }

    // Append Search
    let search_line = "7Search Server\t/swiftSearch\t\(gopherdata_host)\t\(gopherdata_port)\r\n"
    gopherResponse.append(search_line)

    return gopherResponse.joined(separator: "")
  }

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

  private func processGopherRequest(_ request: String) -> ResponseType {
    // Implement your logic to handle the Gopher request and return a response
    // For example, you can retrieve a document based on the request string
    // Return the document or an appropriate response as a string

    // Example response (you should replace this with actual logic)
    if request == "\r\n" {
      return .string(prepareGopherMenu(path: preparePath()))
    } else if !request.contains("\t") {
      //TODO: Potential Bug in Gopher implementation? curl gopher://localhost:8080/new_folder/ does not work but curl gopher://localhost:8080//new_folder/ works (tested with gopher://gopher.meulie.net//EFFector/ as well)
      return requestHandler(path: preparePath(path: request))
    } else if request.contains("\t") {
      var searchQuery = request.components(separatedBy: "\t")[1]
      searchQuery = searchQuery.replacingOccurrences(of: "\r\n", with: "")
      return .string(performSearch(query: searchQuery.lowercased()))
    }

    return
      .string(
        "Hello from Gopher Server! You requested: \(request), but this request could not be processed.\r\n"
      )
  }
}
