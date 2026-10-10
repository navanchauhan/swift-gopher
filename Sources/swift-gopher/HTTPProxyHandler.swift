import Foundation
import GopherProxy
import Logging

#if !os(Windows)
import NIO

/// Reads one HTTP request, answers it through `GopherHTTPProxy`, then closes.
final class HTTPProxyHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let proxy: GopherHTTPProxy
    private let logger: Logger
    private var received = Data()
    private var isResponding = false
    private var timeoutTask: Scheduled<Void>?

    init(proxy: GopherHTTPProxy, logger: Logger) {
        self.proxy = proxy
        self.logger = logger
    }

    func channelActive(context: ChannelHandlerContext) {
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        timeoutTask = context.eventLoop.scheduleTask(in: .seconds(Int64(httpRequestTimeout))) {
            loopBoundContext.value.close(promise: nil)
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !isResponding else { return }
        let input = unwrapInboundIn(data)
        received.append(contentsOf: input.readableBytesView)

        if case .incomplete = HTTPRequestParser.parse(received) {
            return
        }
        isResponding = true
        timeoutTask?.cancel()

        if let remoteAddress = context.remoteAddress {
            logger.info("Received HTTP request from \(remoteAddress)")
        }

        let request = received
        let proxy = self.proxy
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let promise = context.eventLoop.makePromise(of: Data.self)
        promise.completeWithTask {
            await proxy.respond(to: request) ?? Data()
        }
        promise.futureResult.whenSuccess { response in
            let context = loopBoundContext.value
            let buffer = context.channel.allocator.buffer(bytes: response)
            context.writeAndFlush(NIOAny(buffer)).whenComplete { _ in
                loopBoundContext.value.close(promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        timeoutTask?.cancel()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.info("HTTP error: \(error)")
        context.close(promise: nil)
    }
}
#endif
