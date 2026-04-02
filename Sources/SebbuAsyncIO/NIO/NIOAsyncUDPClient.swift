//
//  NIOAsyncUDPClient.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

public final class NIOAsyncUDPClient: AsyncUDPClientProtocol {
    @usableFromInline
    let wrapper: NIOAsyncChannelWrapper<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>
    
    @inlinable
    init(channel: NIOAsyncChannel<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>) {
        self.wrapper = NIOAsyncChannelWrapper(channel: channel)
    }
    
    public static func connect(to: Endpoint) async throws -> NIOAsyncUDPClient {
        let channel = try await DatagramBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .channelOption(.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 2048))
            .channelOption(.maxMessagesPerRead, value: 16)
            .connect(to: to.nioSocketAddress) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(
                            backPressureStrategy: .init(
                                lowWatermark: 8, highWatermark: 16
                            ),
                            isOutboundHalfClosureEnabled: false,
                            inboundType: AddressedEnvelope<ByteBuffer>.self,
                            outboundType: AddressedEnvelope<ByteBuffer>.self)
                    )
                }
            }
        return NIOAsyncUDPClient(channel: channel)
    }
    
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        let byteBuffer = ByteBuffer(bytes: bytes)
        wrapper.channel.channel.writeAndFlush(byteBuffer, promise: nil)
        //await wrapper.send(byteBuffer)
        return bytes.count
    }
    
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        if var packet = try await wrapper.receive() {
            return packet.data.read(into: into)
        }
        return 0
    }
    
    public func close() throws {
        try wrapper.close()
    }
    
    deinit { try? close() }
}
#endif
