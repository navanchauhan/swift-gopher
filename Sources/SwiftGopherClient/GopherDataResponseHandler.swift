import Foundation

#if !os(Windows)
import Logging
import NIO

final class GopherDataResponseHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var accumulatedData = ByteBuffer()
    private let message: String
    private let completion: (Result<Data, Error>) -> Void
    private let logger = Logger(label: "com.navanchauhan.gopher.client.data-handler")

    init(message: String, completion: @escaping (Result<Data, Error>) -> Void) {
        self.message = message
        self.completion = completion
    }

    func channelActive(context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        accumulatedData.writeBuffer(&buffer)
    }

    func channelInactive(context: ChannelHandlerContext) {
        var copy = accumulatedData
        completion(.success(Data(copy.readBytes(length: copy.readableBytes) ?? [])))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.info("Error: \(error)")
        completion(.failure(error))
        context.close(promise: nil)
    }
}
#endif
