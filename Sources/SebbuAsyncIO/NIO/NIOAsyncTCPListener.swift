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
    let wrapper: NIOAsyncChannelWrapper<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>
    
    @inlinable
    init(channel: NIOAsyncChannel<NIOAsyncChannel<ByteBuffer, ByteBuffer>, Never>) {
        self.wrapper = NIOAsyncChannelWrapper(channel: channel)
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
        if let channel = try await wrapper.receive() {
            let implementation = NIOAsyncTCPStream(channel: channel)
            return AsyncTCPStream(implementation: implementation)
        }
        //TODO: A more descriptive error
        throw _Concurrency.CancellationError()
    }

    @inlinable
    public consuming func close() async throws {
        try await wrapper.close()
    }
    
    @inlinable
    deinit {
        wrapper.syncClose()
    }
}
#endif
