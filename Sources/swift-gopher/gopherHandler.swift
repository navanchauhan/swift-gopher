import Foundation
import Logging

#if !os(Windows)
import NIO

final class GopherHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let logger: Logger
    private let processor: GopherRequestProcessor
    private var buffer = ByteBuffer()

    init(
        logger: Logger,
        gopherdata_dir: String = "./example-gopherdata",
        gopherdata_host: String = "localhost",
        gopherdata_port: Int = 70,
        enableSearch: Bool = false,
        disableGophermap: Bool = false
    ) {
        self.logger = logger
        self.processor = GopherRequestProcessor(
            logger: logger,
            gopherdataDir: gopherdata_dir,
            gopherdataHost: gopherdata_host,
            gopherdataPort: gopherdata_port,
            enableSearch: enableSearch,
            disableGophermap: disableGophermap
        )
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var input = unwrapInboundIn(data)
        buffer.writeBuffer(&input)

        guard let requestString = buffer.getString(at: 0, length: buffer.readableBytes),
            requestString.contains(where: \.isNewline)
        else {
            return
        }

        if let remoteAddress = context.remoteAddress {
            logger.info("Received request from \(remoteAddress) for '\(requestString.logDescription)'")
        } else {
            logger.warning("Unable to retrieve remote address")
        }

        let response = processor.process(requestString)
        let outputBuffer = context.channel.allocator.buffer(bytes: response.data)
        context.writeAndFlush(wrapOutboundOut(outputBuffer)).whenComplete { _ in
            context.close(mode: .all, promise: nil)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.info("Error: \(error)")
        context.close(promise: nil)
    }
}

private extension String {
    var logDescription: String {
        replacingOccurrences(of: "\r\n", with: "<GopherSequence>")
            .replacingOccurrences(of: "\n", with: "<Linebreak>")
    }
}
#endif
