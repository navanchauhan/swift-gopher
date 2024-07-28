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
/// This client utilizes Swift NIO for efficient, non-blocking network operations. It automatically
/// chooses the appropriate `EventLoopGroup` based on the running platform:
/// - On iOS/macOS 10.14+, it uses `NIOTSEventLoopGroup` for optimal performance.
/// - On Linux or older Apple platforms, it falls back to `MultiThreadedEventLoopGroup`.
///
/// The client supports both synchronous (completion handler-based) and asynchronous (Swift concurrency) APIs
/// for sending requests to Gopher servers.
public class GopherClient {
    /// The event loop group used for managing network operations.
    private let group: EventLoopGroup

    /// Initializes a new instance of `GopherClient`.
    ///
    /// This initializer automatically selects the appropriate `EventLoopGroup` based on the running platform.
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

    /// Cleans up resources when the instance is deinitialized.
    deinit {
        self.shutdownEventLoopGroup()
    }

    /// Sends a request to a Gopher server using a completion handler.
    ///
    /// This method asynchronously establishes a connection, sends the request, and calls the completion
    /// handler with the result.
    ///
    /// - Parameters:
    ///   - host: The host address of the Gopher server.
    ///   - port: The port of the Gopher server. Defaults to 70.
    ///   - message: The message to be sent to the server.
    ///   - completion: A closure that handles the result of the request. It takes a `Result` type
    ///     which either contains an array of `gopherItem` on success or an `Error` on failure.
    public func sendRequest(
        to host: String,
        port: Int = 70,
        message: String,
        completion: @escaping (Result<[gopherItem], Error>) -> Void
    ) {
        let bootstrap = self.createBootstrap(message: message, completion: completion)
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

    /// Sends a request to a Gopher server using Swift concurrency.
    ///
    /// This method asynchronously establishes a connection and sends the request,
    /// returning the result as an array of `gopherItem`.
    ///
    /// - Parameters:
    ///   - host: The host address of the Gopher server.
    ///   - port: The port of the Gopher server. Defaults to 70.
    ///   - message: The message to be sent to the server.
    ///
    /// - Returns: An array of `gopherItem` representing the server's response.
    ///
    /// - Throws: An error if the connection fails or the server returns an invalid response.
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

    /// Creates a bootstrap for connecting to a Gopher server.
    ///
    /// This method sets up the appropriate bootstrap based on the platform and configures
    /// the channel with a `GopherRequestResponseHandler`.
    ///
    /// - Parameters:
    ///   - message: The message to be sent to the server.
    ///   - completion: A closure that handles the result of the request.
    ///
    /// - Returns: A `NIOClientTCPBootstrapProtocol` configured for Gopher communication.
    private func createBootstrap(
        message: String,
        completion: @escaping (Result<[gopherItem], Error>) -> Void
    ) -> NIOClientTCPBootstrapProtocol {
        let handler = GopherRequestResponseHandler(message: message, completion: completion)

        #if os(Linux)
            return ClientBootstrap(group: group)
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
