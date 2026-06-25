//
//  gopherClient.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import GopherHelpers
import Logging

#if os(Windows)
import WinSDK
#else
import NIO
import NIOTransportServices
#endif

enum GopherClientError: Error, Sendable {
    case invalidPort
    case resolveFailed(Int32)
    case socketFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case receiveFailed(Int32)
    case invalidResponse
}

public enum GopherResponseKind: Sendable {
    case menu
    case text
    case data
}

public enum GopherClientResponse: Sendable {
    case menu([GopherItem])
    case text(String)
    case data(Data)
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
    private let logger = Logger(label: "com.navanchauhan.gopher.client")

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
    ///     which either contains an array of `GopherItem` on success or an `Error` on failure.
    public func sendRequest(
        to host: String,
        port: Int = 70,
        message: String,
        completion: @escaping (Result<[GopherItem], Error>) -> Void
    ) {
        sendResponse(to: host, port: port, message: message, as: .menu) { result in
            completion(result.flatMap { response in
                guard case .menu(let items) = response else {
                    return .failure(GopherClientError.invalidResponse)
                }
                return .success(items)
            })
        }
    }

    public func sendResponse(
        to host: String,
        port: Int = 70,
        message: String,
        as responseKind: GopherResponseKind = .menu,
        completion: @escaping (Result<GopherClientResponse, Error>) -> Void
    ) {
        guard (0...Int(UInt16.max)).contains(port) else {
            completion(.failure(GopherClientError.invalidPort))
            return
        }

        #if os(Windows)
            completion(Result {
                let data = try self.sendRawRequestSynchronously(to: host, port: port, message: message)
                return self.response(from: data, as: responseKind)
            })
        #else
        let bootstrap = self.createDataBootstrap(message: message) { result in
            completion(result.map { self.response(from: $0, as: responseKind) })
        }
        bootstrap.connect(host: host, port: port).whenComplete { result in
            switch result {
            case .success(let channel):
                channel.closeFuture.whenComplete { _ in
                    self.logger.info("Connection closed")
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
        #endif
    }

    public func sendRawRequest(
        to host: String,
        port: Int = 70,
        message: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        sendResponse(to: host, port: port, message: message, as: .data) { result in
            completion(result.flatMap { response in
                guard case .data(let data) = response else {
                    return .failure(GopherClientError.invalidResponse)
                }
                return .success(data)
            })
        }
    }

    /// Sends a request to a Gopher server using Swift concurrency.
    ///
    /// This method asynchronously establishes a connection and sends the request,
    /// returning the result as an array of `GopherItem`.
    ///
    /// - Parameters:
    ///   - host: The host address of the Gopher server.
    ///   - port: The port of the Gopher server. Defaults to 70.
    ///   - message: The message to be sent to the server.
    ///
    /// - Returns: An array of `GopherItem` representing the server's response.
    ///
    /// - Throws: An error if the connection fails or the server returns an invalid response.
    @available(macOS 10.15, iOS 13.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, * )
    public func sendRequest(to host: String, port: Int = 70, message: String) async throws
        -> [GopherItem]
    {
        return try await withCheckedThrowingContinuation { continuation in
            sendRequest(to: host, port: port, message: message) { result in
                switch result {
                case .success(let items):
                    continuation.resume(returning: items)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, * )
    public func sendResponse(
        to host: String,
        port: Int = 70,
        message: String,
        as responseKind: GopherResponseKind = .menu
    ) async throws -> GopherClientResponse {
        try await withCheckedThrowingContinuation { continuation in
            sendResponse(to: host, port: port, message: message, as: responseKind) { result in
                switch result {
                case .success(let response):
                    continuation.resume(returning: response)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @available(macOS 10.15, iOS 13.0, tvOS 12.0, watchOS 6.0, visionOS 1.0, * )
    public func sendRawRequest(to host: String, port: Int = 70, message: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sendRawRequest(to: host, port: port, message: message) { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func response(from data: Data, as responseKind: GopherResponseKind) -> GopherClientResponse {
        switch responseKind {
        case .menu:
            return .menu(GopherResponseParser.parse(data: data))
        case .text:
            return .text(String(data: data, encoding: .utf8) ?? "")
        case .data:
            return .data(data)
        }
    }

    #if os(Windows)
    private func sendRawRequestSynchronously(to host: String, port: Int, message: String) throws -> Data {
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

        return response
    }
    #else
    private func createDataBootstrap(
        message: String,
        completion: @escaping (Result<Data, Error>) -> Void
    ) -> NIOClientTCPBootstrapProtocol {
        let handler = GopherDataResponseHandler(message: message, completion: completion)

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

    private func shutdownEventLoopGroup() {
        do {
            try group.syncShutdownGracefully()
        } catch {
            logger.info("Failed to shutdown event loop group: \(error)")
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
