//
//  gopherRequestResponseHandler.swift
//
//
//  Created by Navan Chauhan on 12/12/23.
//

import Foundation
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
        if let receivedString = buffer.getString(at: 0, length: buffer.readableBytes) {
            print("Received from server: \(receivedString)")
        }
        //completion(.success(receivedString))
        //context.close(promise: nil)
    }
    
    func channelInactive(context: ChannelHandlerContext) {
            // Parse GopherServerResponse
        parseGopherServerResponse(response: accumulatedData.readString(length: accumulatedData.readableBytes) ?? "")
            //completion(.success(accumulatedData.readString(length: accumulatedData.readableBytes) ?? ""))
        }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: ", error)
        context.close(promise: nil)
    }
    
    func createGopherItem(rawLine: String, itemType: gopherItemType = .info) -> gopherItem {
        var item = gopherItem(rawLine: rawLine)
        item.parsedItemType = itemType
        
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
    
    func parseGopherServerResponse(response: String) {
        var gopherServerResponse: [gopherItem] = []
        
        print("parsing")
        let carriageReturnCount = response.filter({ $0 == "\r" }).count
        let newlineCarriageReturnCount = response.filter({ $0 == "\r\n" }).count
        print("Carriage Returns: \(carriageReturnCount), Newline + Carriage Returns: \(newlineCarriageReturnCount)")
        
        for line in response.split(separator: "\r\n") {
            let lineItemType = getGopherFileType(item: "\(line.first ?? " ")")
            let item = createGopherItem(rawLine: String(line), itemType: lineItemType)
            print(item.message)
            gopherServerResponse.append(item)
            
        }
        
        print("done parsing")
        
        completion(.success(gopherServerResponse))
        
        //completion(.success(response))
    }
}

public struct gopherItem {
    
    public var rawLine: String
    public var message: String = ""
    public var parsedItemType: gopherItemType = .info
    public var host: String = "error.host"
    public var port: Int = 1
    public var selector: String = ""
    public var valid: Bool = true
    
    public init(rawLine: String) {
        self.rawLine = rawLine
    }
}

