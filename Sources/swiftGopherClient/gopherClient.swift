//
//  gopherClient.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import GopherHelpers
import NIO
import NIOTransportServices

/// `GopherClient` is a class for handling network connections and requests to Gopher servers.
///
/// It utilizes `NIOTSEventLoopGroup` on iOS/macOS (Not sure why you would run this on watchOS/tvOS but it supports that as well) for network operations, falling back to `MultiThreadedEventLoopGroup` otherwise.
public class GopherClient {
    private let group: EventLoopGroup

    /// Initializes a new instance of `GopherClient`.
    ///
    /// It automatically chooses the appropriate `EventLoopGroup` based on the running platform.
    public init() {
        #if os(Linux)
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        #else
            if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, *) {
                self.group = NIOTSEventLoopGroup()
            } else {
                self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            }
        #endif
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    /// Sends a request to a Gopher server.
    ///
    /// - Parameters:
    ///   - host: The host address of the Gopher server.
    ///   - port: The port of the Gopher server. Defaults to 70.
    ///   - message: The message to be sent to the server.
    ///   - completion: A closure that handles the result of the request.
    ///
    /// The method asynchronously establishes a connection, sends the request, and calls the completion handler with the result.
    public func sendRequest(
        to host: String, port: Int = 70, message: String,
        completion: @escaping (Result<[gopherItem], Error>) -> Void
    ) {
        #if os(Linux)
            let bootstrap = ClientBootstrap(group: group)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(
                        GopherRequestResponseHandler(message: message, completion: completion))
                }
            bootstrap.connect(host: host, port: port).whenComplete { result in
                switch result {
                case .success(let channel):
                    channel.closeFuture.whenComplete { _ in
                        print("Connection closed")
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        #else

            if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, *) {
                let bootstrap = NIOTSConnectionBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandler(
                            GopherRequestResponseHandler(message: message, completion: completion))
                    }
                bootstrap.connect(host: host, port: port).whenComplete { result in
                    switch result {
                    case .success(let channel):
                        channel.closeFuture.whenComplete { _ in
                            print("Connection closed")
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } else {
                let bootstrap = ClientBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandler(
                            GopherRequestResponseHandler(message: message, completion: completion))
                    }
                bootstrap.connect(host: host, port: port).whenComplete { result in
                    switch result {
                    case .success(let channel):
                        channel.closeFuture.whenComplete { _ in
                            print("Connection closed")
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
        #endif

    }

    @available(iOS 13.0, *)
    @available(macOS 10.15, *)
    public func sendRequest(to host: String, port: Int = 70, message: String) async throws
        -> [gopherItem]
    {
        return try await withCheckedThrowingContinuation { continuation in
            let bootstrap = self.createBootstrap(message: message) { result in
                continuation.resume(with: result)
            }

            bootstrap.connect(host: host, port: port).whenComplete { result in
                switch result {
                case .success(let channel):
                    channel.closeFuture.whenComplete { _ in
                        print("Connection Closed")
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func createBootstrap(
        message: String,
        completion: @escaping (Result<[gopherItem], Error>) -> Void
    ) -> NIOClientTCPBootstrapProtocol {
        let handler = GopherRequestResponseHandler(message: message, completion: completion)

        #if os(Linux)
            return ClientBootstrap(group: eventLoopGroup)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(handler)
                }
        #else
            if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, *) {
                return NIOTSConnectionBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandler(handler)
                    }
            } else {
                return ClientBootstrap(group: group)
                    .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .channelInitializer { channel in
                        channel.pipeline.addHandler(handler)
                    }
            }
        #endif
    }

    /// Shuts down the event loop group, releasing any resources.
    ///
    /// This method is called during deinitialization to ensure clean shutdown of network resources.
    private func shutdownEventLoopGroup() {
        do {
            try group.syncShutdownGracefully()
        } catch {
            print("Error shutting down event loop group: \(error)")
        }
    }
}
