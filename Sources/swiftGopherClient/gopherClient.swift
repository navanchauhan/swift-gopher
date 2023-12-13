//
//  gopherClient.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import NIO

public class GopherClient {
    private let group: EventLoopGroup

    public init() {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    deinit {
        try? group.syncShutdownGracefully()
    }

    public func sendRequest(to host: String, port: Int = 70, message: String, completion: @escaping (Result<[gopherItem], Error>) -> Void) {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandler(GopherRequestResponseHandler(message: message, completion: completion))
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
    
    private func shutdownEventLoopGroup() {
            do {
                try group.syncShutdownGracefully()
            } catch {
                print("Error shutting down event loop group: \(error)")
            }
        }
}
