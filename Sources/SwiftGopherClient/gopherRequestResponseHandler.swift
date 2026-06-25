//
//  gopherRequestResponseHandler.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import GopherHelpers

#if !os(Windows)
import NIO

final class GopherRequestResponseHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var accumulatedData: ByteBuffer
    private let message: String
    private let completion: (Result<[gopherItem], Error>) -> Void

    init(message: String, completion: @escaping (Result<[gopherItem], Error>) -> Void) {
        self.message = message
        self.completion = completion
        self.accumulatedData = ByteBuffer()
    }

    func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        context.writeAndFlush(self.wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        accumulatedData.writeBuffer(&buffer)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if let dataCopy = accumulatedData.getSlice(at: 0, length: accumulatedData.readableBytes) {
            var bytesCopy = dataCopy
            let bytes = bytesCopy.readBytes(length: bytesCopy.readableBytes) ?? []
            completion(.success(GopherResponseParser.parse(data: Data(bytes))))
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: ", error)
        context.close(promise: nil)
    }

}
#endif
