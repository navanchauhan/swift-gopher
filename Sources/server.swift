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
  @Flag var disableSearch: Bool = false
  @Flag var disableGophermap: Bool = false

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
    let localEnableSearch = !disableSearch
    let localDisableGophermap = disableGophermap

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
          gopherdata_port: localPort,
          enableSearch: localEnableSearch,
          disableGophermap: localDisableGophermap
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
