#if os(Windows)
import Foundation
import GopherProxy
import Logging
import WinSDK

/// Winsock counterpart of `HTTPProxyHandler`: one HTTP request per connection.
final class WindowsHTTPProxyServer: @unchecked Sendable {
    private let host: String
    private let port: Int
    private let logger: Logger
    private let proxy: GopherHTTPProxy
    private var listenSocket: SOCKET = INVALID_SOCKET

    init(host: String, port: Int, logger: Logger, proxy: GopherHTTPProxy) {
        self.host = host
        self.port = port
        self.logger = logger
        self.proxy = proxy
    }

    /// Binds and listens, so startup errors surface before serving on a background thread.
    func bind() throws {
        guard WindowsSockets.initialize() else {
            throw GopherServerError.wsaStartupFailed(WSAGetLastError())
        }
        listenSocket = try WindowsSockets.bind(host: host, port: port)
        guard listen(listenSocket, SOMAXCONN) != SOCKET_ERROR else {
            closesocket(listenSocket)
            throw GopherServerError.listenFailed(WSAGetLastError())
        }
        logger.info("HTTP proxy listening on \(host):\(port)")
    }

    func serve() {
        defer { closesocket(listenSocket) }

        while true {
            let client = accept(listenSocket, nil, nil)
            if client == INVALID_SOCKET {
                logger.error("HTTP accept failed: \(WSAGetLastError())")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                self.handle(client: client)
            }
        }
    }

    private func handle(client: SOCKET) {
        defer { closesocket(client) }

        var timeout = DWORD(httpRequestTimeout * 1000)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(
                client,
                SOL_SOCKET,
                SO_RCVTIMEO,
                UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self),
                Int32(MemoryLayout<DWORD>.size)
            )
        }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while case .incomplete = HTTPRequestParser.parse(received) {
            let count = buffer.withUnsafeMutableBufferPointer {
                recv(client, $0.baseAddress!, Int32($0.count), 0)
            }
            guard count > 0 else { return }
            received.append(buffer, count: Int(count))
        }

        let response = Self.waitFor { [proxy, received] in await proxy.respond(to: received) } ?? Data()
        do {
            try send(response, to: client)
        } catch {
            logger.error("HTTP client handling failed: \(error)")
        }
    }

    private func send(_ data: Data, to socket: SOCKET) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let result = WinSDK.send(socket, baseAddress + sent, Int32(data.count - sent), 0)
                if result == SOCKET_ERROR {
                    throw GopherServerError.sendFailed(WSAGetLastError())
                }
                sent += Int(result)
            }
        }
    }

    /// Blocks the current (non-cooperative) thread until `operation` finishes.
    private static func waitFor<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }
}

/// Hands a value from a `Task` to the thread waiting on it; the semaphore orders the accesses.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
#endif
