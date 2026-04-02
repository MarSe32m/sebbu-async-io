//
//  NIOAsyncTCPListener.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

@usableFromInline
internal final class NIOAsyncTCPListener: AsyncTCPListenerProtocol {
    @usableFromInline
    let channel: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>
    
    @usableFromInline
    let listenerTask: Task<Void, Never>
    
    @usableFromInline
    let stream: AsyncThrowingStream<NIOAsyncChannel<ByteBuffer, ByteBuffer>, any Error>
    
    @inlinable
    init(channel _channel: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>) {
        self.channel = _channel
        let (_stream, continuation) = AsyncThrowingStream<NIOAsyncChannel<ByteBuffer, ByteBuffer>, any Error>.makeStream()
        self.stream = _stream
        self.listenerTask = Task {
            do {
                try await _channel.executeThenClose { inbound, _ in
                    for try await channel in inbound {
                        //TODO: Back pressure?
                        continuation.yield(channel)
                    }
                }
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.finish()
        }
    }
    
    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> NIOAsyncTCPListener {
        let channel = try await ServerBootstrap(group: .singletonMultiThreadedEventLoopGroup)
                    .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                    .bind(to: on.nioSocketAddress) { channel in
                        channel.eventLoop.makeCompletedFuture {
                            return try NIOAsyncChannel(
                                wrappingChannelSynchronously: channel,
                                configuration: NIOAsyncChannel.Configuration(
                                    inboundType: ByteBuffer.self,
                                    outboundType: ByteBuffer.self
                                )
                            )
                        }
                    }
        return NIOAsyncTCPListener(channel: channel)
    }

    @inlinable
    public func accept() async throws -> AsyncTCPStream {
        for try await channel in stream {
            //TODO: Construct implementation -> return AsyncTCPStream(implementation: implementation)
            let implementation = NIOAsyncTCPStream(channel: channel)
            return AsyncTCPStream(implementation: implementation)
        }
        //TODO: A more descriptive error
        throw _Concurrency.CancellationError()
    }

    @inlinable
    public consuming func close() throws {
        listenerTask.cancel()
        channel.channel.close(promise: nil)
    }
    
    deinit { try? close() }
}
#endif
