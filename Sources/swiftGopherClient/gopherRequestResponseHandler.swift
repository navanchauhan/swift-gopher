//
//  gopherRequestResponseHandler.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
import GopherHelpers
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
            parseGopherServerResponse(
                response: accumulatedData.readString(length: accumulatedData.readableBytes) ?? "",
                originalBytes: dataCopy)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: ", error)
        context.close(promise: nil)
    }

    func createGopherItem(rawLine: String, itemType: gopherItemType = .info, rawData: ByteBuffer)
        -> gopherItem
    {
        var item = gopherItem(rawLine: rawLine)
        item.parsedItemType = itemType
        item.rawData = rawData

        if rawLine.isEmpty {
            item.valid = false
        } else {
            let components = rawLine.components(separatedBy: "\t")

            // Handle cases where rawLine does not have any itemType in the first character
            item.message = String(components[0].dropFirst())

            if components.indices.contains(1) {
                item.selector = String(components[1])
            }

            if components.indices.contains(2) {
                item.host = String(components[2])
            }

            if components.indices.contains(3) {
                item.port = Int(String(components[3])) ?? 70
            }
        }

        return item
    }

    func parseGopherServerResponse(response: String, originalBytes: ByteBuffer) {
        var gopherServerResponse: [gopherItem] = []

        print("parsing")
        let carriageReturnCount = response.filter({ $0 == "\r" }).count
        let newlineCarriageReturnCount = response.filter({ $0 == "\r\n" }).count
        print(
            "Carriage Returns: \(carriageReturnCount), Newline + Carriage Returns: \(newlineCarriageReturnCount)"
        )

        if newlineCarriageReturnCount == 0 {
            for line in response.split(separator: "\n") {
                let lineItemType = getGopherFileType(item: "\(line.first ?? " ")")
                let item = createGopherItem(
                    rawLine: String(line), itemType: lineItemType, rawData: originalBytes)
                gopherServerResponse.append(item)

            }
        } else {
            for line in response.split(separator: "\r\n") {
                let lineItemType = getGopherFileType(item: "\(line.first ?? " ")")
                let item = createGopherItem(
                    rawLine: String(line), itemType: lineItemType, rawData: originalBytes)
                gopherServerResponse.append(item)

            }
        }

        print("done parsing")

        completion(.success(gopherServerResponse))
    }
}
