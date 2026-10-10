import Foundation

#if !os(Windows)
import Logging
import NIO

final class GopherDataResponseHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private var accumulatedData = ByteBuffer()
    private var didComplete = false
    private var timeoutTask: Scheduled<Void>?
    private let message: String
    private let timeout: TimeInterval?
    private let maxResponseSize: Int?
    private let completion: (Result<Data, Error>) -> Void
    private let logger = Logger(label: "com.navanchauhan.gopher.client.data-handler")

    init(
        message: String,
        timeout: TimeInterval? = nil,
        maxResponseSize: Int? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.message = message
        self.timeout = timeout
        self.maxResponseSize = maxResponseSize
        self.completion = completion
    }

    func channelActive(context: ChannelHandlerContext) {
        if let timeout {
            let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
            let loopBoundSelf = NIOLoopBound(self, eventLoop: context.eventLoop)
            timeoutTask = context.eventLoop.scheduleTask(in: .nanoseconds(Int64(timeout * 1_000_000_000))) {
                loopBoundSelf.value.fail(context: loopBoundContext.value, error: GopherClientError.timedOut)
            }
        }

        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !didComplete else { return }
        var buffer = unwrapInboundIn(data)
        accumulatedData.writeBuffer(&buffer)

        if let maxResponseSize, accumulatedData.readableBytes > maxResponseSize {
            fail(context: context, error: GopherClientError.responseTooLarge(limit: maxResponseSize))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        guard !didComplete else { return }
        didComplete = true
        var copy = accumulatedData
        completion(.success(Data(copy.readBytes(length: copy.readableBytes) ?? [])))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.info("Error: \(error)")
        fail(context: context, error: error)
    }

    private func fail(context: ChannelHandlerContext, error: Error) {
        timeoutTask?.cancel()
        guard !didComplete else {
            context.close(promise: nil)
            return
        }
        didComplete = true
        completion(.failure(error))
        context.close(promise: nil)
    }
}
#endif
