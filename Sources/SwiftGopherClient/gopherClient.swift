//
//  gopherClient.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import GopherHelpers

#if os(Windows)
import WinSDK
#else
import NIO
import NIOTransportServices
#endif

enum GopherClientError: Error {
    case invalidPort
    case resolveFailed(Int32)
    case socketFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case invalidResponse
}

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
    #if !os(Windows)
    /// The event loop group used for managing network operations.
    private let group: EventLoopGroup
    #endif

    /// Initializes a new instance of `GopherClient`.
    ///
    /// This initializer automatically selects the appropriate `EventLoopGroup` based on the running platform.
    public init() {
        #if os(Windows)
            _ = WindowsSockets.initialize()
        #else
        #if os(Linux)
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        #else
            if #available(macOS 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, *) {
                self.group = NIOTSEventLoopGroup()
            } else {
                self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
            }
        #endif
        #endif
    }

    /// Cleans up resources when the instance is deinitialized.
    deinit {
        #if !os(Windows)
        self.shutdownEventLoopGroup()
        #endif
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
        #if os(Windows)
            DispatchQueue.global(qos: .userInitiated).async {
                completion(Result { try self.sendRequestSynchronously(to: host, port: port, message: message) })
            }
        #else
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
        #endif
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
    @available(macOS 10.15, iOS 13.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, * )
    public func sendRequest(to host: String, port: Int = 70, message: String) async throws
        -> [gopherItem]
    {
        #if os(Windows)
            return try await withCheckedThrowingContinuation { continuation in
                sendRequest(to: host, port: port, message: message) { result in
                    continuation.resume(with: result)
                }
            }
        #else
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
        #endif
    }

    #if os(Windows)
    private func sendRequestSynchronously(to host: String, port: Int, message: String) throws
        -> [gopherItem]
    {
        guard (0...Int(UInt16.max)).contains(port) else {
            throw GopherClientError.invalidPort
        }

        let socket = try WindowsSockets.connect(host: host, port: port)
        defer { closesocket(socket) }

        var request = Array(message.utf8)
        try request.withUnsafeMutableBufferPointer { buffer in
            var sent = 0
            while sent < buffer.count {
                let result = send(socket, buffer.baseAddress! + sent, Int32(buffer.count - sent), 0)
                if result == SOCKET_ERROR {
                    throw GopherClientError.sendFailed(WSAGetLastError())
                }
                sent += Int(result)
            }
        }

        var response = Data()
        var receiveBuffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let received = receiveBuffer.withUnsafeMutableBufferPointer { buffer in
                recv(socket, buffer.baseAddress!, Int32(buffer.count), 0)
            }
            if received == 0 {
                break
            }
            if received == SOCKET_ERROR {
                throw GopherClientError.receiveFailed(WSAGetLastError())
            }
            response.append(receiveBuffer, count: Int(received))
        }

        return GopherResponseParser.parse(data: response)
    }
    #else
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
    #endif
}

#if os(Windows)
enum WindowsSockets {
    static func initialize() -> Bool {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }

    static func connect(host: String, port: Int) throws -> SOCKET {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP.rawValue

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let first = result else {
            throw GopherClientError.resolveFailed(status)
        }
        defer { freeaddrinfo(first) }

        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            let socketHandle = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if socketHandle != INVALID_SOCKET {
                if WinSDK.connect(socketHandle, info.pointee.ai_addr, Int32(info.pointee.ai_addrlen)) == 0 {
                    return socketHandle
                }
                closesocket(socketHandle)
            }
            current = info.pointee.ai_next
        }

        throw GopherClientError.connectFailed(WSAGetLastError())
    }
}
#endif
