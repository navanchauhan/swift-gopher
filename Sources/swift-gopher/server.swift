// The Swift Programming Language
// https://docs.swift.org/swift-book

import ArgumentParser
import Foundation
import GopherProxy
import Logging

#if !os(Windows)
import NIO
#endif

@main
struct swiftGopher: ParsableCommand {
    @Option(name: [.short, .long], help: "Hostname used for generating selectors")
    var gopherHostName: String = "localhost"
    @Option(name: [.short, .long])
    var host: String = "0.0.0.0"
    @Option(name: [.short, .long])
    var port: Int = 8080
    @Option(name: [.customShort("d"), .long], help: "Data directory to map")
    var gopherDataDir: String = "./example-gopherdata"
    @Flag(help: "Disable full-text search feature")
    var disableSearch: Bool = false
    @Flag(help: "Disable reading gophermap files to override automatic generation")
    var disableGophermap: Bool = false
    @Option(help: "Also serve an HTTP proxy for browsing gopher in a web browser on this port")
    var httpPort: Int?
    @Flag(help: "Let the HTTP proxy fetch from other gopher servers, not just this one")
    var httpAllowRemoteHosts: Bool = false
    @Flag(help: "Let the HTTP proxy connect to remote gopher servers on ports other than 70")
    var httpAllowAllPorts: Bool = false

    func validate() throws {
        if let httpPort, !(1...65535).contains(httpPort) {
            throw ValidationError("--http-port must be between 1 and 65535")
        }
        if httpPort == port {
            throw ValidationError("--http-port must differ from --port")
        }
        if httpPort == nil && (httpAllowRemoteHosts || httpAllowAllPorts) {
            throw ValidationError("--http-allow-remote-hosts and --http-allow-all-ports require --http-port")
        }
        if httpAllowAllPorts && !httpAllowRemoteHosts {
            throw ValidationError("--http-allow-all-ports requires --http-allow-remote-hosts")
        }
    }

    func makeProxy(logger: Logger) -> GopherHTTPProxy {
        makeHTTPProxy(
            logger: logger,
            gopherdataDir: gopherDataDir,
            gopherdataHost: gopherHostName,
            gopherdataPort: port,
            enableSearch: !disableSearch,
            disableGophermap: disableGophermap,
            allowRemoteHosts: httpAllowRemoteHosts,
            allowAllPorts: httpAllowAllPorts
        )
    }

    public mutating func run() throws {
        let logger = Logger(label: "com.navanchauhan.gopher.server")

        #if os(Windows)
        if let httpPort {
            let httpServer = WindowsHTTPProxyServer(
                host: host,
                port: httpPort,
                logger: logger,
                proxy: makeProxy(logger: logger)
            )
            try httpServer.bind()
            Thread.detachNewThread { httpServer.serve() }
        }

        try WindowsGopherServer(
            host: host,
            port: port,
            logger: logger,
            gopherdataDir: gopherDataDir,
            gopherdataHost: gopherHostName,
            enableSearch: !disableSearch,
            disableGophermap: disableGophermap
        ).run()
        #else
        let eventLoopGroup = MultiThreadedEventLoopGroup(
            numberOfThreads: System.coreCount
        )

        defer {
            do {
                try eventLoopGroup.syncShutdownGracefully()
            } catch {
                logger.info("Error shutting down event loop group: \(error)")
            }
        }

        let localGopherDataDir = gopherDataDir
        let localGopherHostName = gopherHostName
        let localPort = port
        let localEnableSearch = !disableSearch
        let localDisableGophermap = disableGophermap

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

        var httpChannel: Channel?
        if let httpPort {
            let proxy = makeProxy(logger: logger)
            httpChannel = try ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(HTTPProxyHandler(proxy: proxy, logger: logger))
                    }
                }
                .bind(host: defaultHost, port: httpPort)
                .wait()
            logger.info("HTTP proxy listening on \(httpChannel!.localAddress!)")
        }

        try channel.closeFuture.wait()
        try httpChannel?.close().wait()
        logger.info("Server closed")
        #endif
    }
}
