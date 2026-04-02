//
//  NIOAsyncTCPStream.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO
import Synchronization

@usableFromInline
internal final class NIOAsyncTCPStream: AsyncTCPStreamProtocol {
    @usableFromInline
    let wrapper: NIOAsyncChannelWrapper<ByteBuffer, ByteBuffer>
    
    @usableFromInline
    let bufferedBytes: Mutex<ByteBuffer?> = Mutex(nil)
    
    @inlinable
    init(channel: NIOAsyncChannel<ByteBuffer, ByteBuffer>) {
        self.wrapper = NIOAsyncChannelWrapper(channel: channel)
    }
    
    @inlinable
    public static func connect(to: Endpoint) async throws -> NIOAsyncTCPStream {
        let channel = try await ClientBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .channelOption(.tcpOption(.tcp_nodelay), value: 1)
            .channelOption(.maxMessagesPerRead, value: 16)
            .channelOption(.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .connect(to: to.nioSocketAddress) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(
                            backPressureStrategy: .init(lowWatermark: 1, highWatermark: 4),
                            isOutboundHalfClosureEnabled: false,
                            inboundType: ByteBuffer.self,
                            outboundType: ByteBuffer.self
                        )
                    )
                }
            }
        return NIOAsyncTCPStream(channel: channel)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        let byteBuffer = ByteBuffer(bytes: bytes)
        await wrapper.send(byteBuffer)
        return bytes.count
    }
    
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        if into.isEmpty { return 0 }
        var bytesReceived = bufferedBytes.withLock { buffer in
            if var buf = buffer.take() {
                let bytesRead = buf.read(into: into)
                if buf.readableBytes > 0 { buffer = buf }
                return bytesRead
            }
            return 0
        }
        if bytesReceived > 0 { return bytesReceived }
        if var bytes = try await wrapper.receive() {
            bytesReceived += bytes.read(into: into)
            if bytes.readableBytes != 0 {
                bufferedBytes.withLock { $0 = bytes }
            }
            return bytesReceived
        }
        return bytesReceived
    }
    
//TODO: Implement with sendfile?
//    @inlinable
//    public func transmit(file: borrowing AsyncFile) async throws {
//        fatalError("TODO: Implement")
//    }

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
