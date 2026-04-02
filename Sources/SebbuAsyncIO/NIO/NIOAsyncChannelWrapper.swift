//
//  NIOAsyncChannelWrapper.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 2.4.2026.
//

#if canImport(NIO)
import NIO
import AsyncAlgorithms
import Synchronization

@usableFromInline
internal final class NIOAsyncChannelWrapper<Inbound: Sendable, Outbound: Sendable>: Sendable {
    @usableFromInline
    let channel: NIOAsyncChannel<Inbound, Outbound>
    
    @usableFromInline
    let receiveChannel: AsyncThrowingChannel<Inbound, any Error>
    
    @usableFromInline
    let sendChannel: AsyncThrowingChannel<Outbound, any Error>
    
    @usableFromInline
    let processingTask: Task<Void, Never>
    
    @inlinable
    init(channel _channel: NIOAsyncChannel<Inbound, Outbound>) {
        self.channel = _channel
        let _receiveChannel = AsyncThrowingChannel<Inbound, any Error>()
        let _sendChannel = AsyncThrowingChannel<Outbound, any Error>()
        self.receiveChannel = _receiveChannel
        self.sendChannel = _sendChannel
        self.processingTask = Task {
            do {
                try await _channel.executeThenClose { inbound, outbound in
                    try await withThrowingTaskGroup { group in
                        // Sending
                        group.addTask {
                            for try await data in _sendChannel {
                                try await outbound.write(data)
                            }
                            outbound.finish()
                        }
                        // Receiving
                        group.addTask {
                            for try await data in inbound {
                                await _receiveChannel.send(data)
                            }
                            _receiveChannel.finish()
                        }
                        try await group.waitForAll()
                    }
                }
            } catch {
                _receiveChannel.fail(error)
            }
        }
    }
    
    @inlinable
    func send(_ data: Outbound) async {
        await sendChannel.send(data)
    }
    
    @inlinable
    func receive() async throws -> Inbound? {
        for try await inbound in receiveChannel {
            return inbound
        }
        return nil
    }
    
    @inlinable
    func close() async throws {
        processingTask.cancel()
        receiveChannel.finish()
        sendChannel.finish()
        try await channel.channel.close(mode: .all)
    }
    
    @inlinable
    func syncClose() {
        channel.channel.close(promise: nil)
    }
}
#endif
