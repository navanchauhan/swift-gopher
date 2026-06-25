#if os(Windows)
import Foundation
import GopherHelpers
import Logging
import WinSDK

final class WindowsGopherServer: @unchecked Sendable {
    private let host: String
    private let port: Int
    private let processor: GopherRequestProcessor
    private let logger: Logger
    private var isRunning = false
    private var listenSocket: SOCKET = INVALID_SOCKET

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

        listenSocket = try WindowsSockets.bind(host: host, port: port)
        isRunning = true
        defer {
            closesocket(listenSocket)
            listenSocket = INVALID_SOCKET
            isRunning = false
        }

        guard listen(listenSocket, SOMAXCONN) != SOCKET_ERROR else {
            throw GopherServerError.listenFailed(WSAGetLastError())
        }

        logger.info("Server started and listening on \(host):\(port)")

        while isRunning {
            let client = accept(listenSocket, nil, nil)
            if client == INVALID_SOCKET {
                if !isRunning {
                    break
                }
                throw GopherServerError.acceptFailed(WSAGetLastError())
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.handle(client: client)
            }
        }
    }

    func stop() {
        isRunning = false
        if listenSocket != INVALID_SOCKET {
            closesocket(listenSocket)
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

    private func write(response: GopherResponse, to socket: SOCKET) throws {
        let data = response.data

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
