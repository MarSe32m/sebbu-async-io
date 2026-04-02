//
//  NIOAsyncUDPSocket.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

public final class NIOAsyncUDPSocket: AsyncUDPSocketProtocol {
    @usableFromInline
    let wrapper: NIOAsyncChannelWrapper<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>
    
    @inlinable
    init(channel: NIOAsyncChannel<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>) {
        self.wrapper = NIOAsyncChannelWrapper(channel: channel)
    }
    
    public static func bind(to: Endpoint) async throws -> NIOAsyncUDPSocket {
        let channel = try await DatagramBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .channelOption(.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: 2048))
            .bind(to: to.nioSocketAddress) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel(
                        wrappingChannelSynchronously: channel,
                        configuration: .init(
                            backPressureStrategy: .init(lowWatermark: 8, highWatermark: 16),
                            isOutboundHalfClosureEnabled: false,
                            inboundType: AddressedEnvelope<ByteBuffer>.self,
                            outboundType: AddressedEnvelope<ByteBuffer>.self
                        )
                    )
                }
            }
        return NIOAsyncUDPSocket(channel: channel)
    }
    
    public func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int {
        let bytesSent = bytes.count
        //TODO: This is highly unoptimal...
        let bytes = ByteBuffer(bytes: bytes)
        await wrapper.send(AddressedEnvelope(remoteAddress: to.nioSocketAddress, data: bytes))
        return bytesSent
    }
    
    public func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int {
        if var packet = try await wrapper.receive() {
            let bytesReceived = packet.data.read(into: into)
            packet.remoteAddress.withSockAddr { remotePointer, remoteLength in
                from.withMutableSockAddrStoragePointer { storage, length in
                    length.pointee = .init(remoteLength)
                    storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                        pointer.pointee = remotePointer.pointee
                    }
                }
            }
            return bytesReceived
        }
        return 0
    }
    
    public func close() throws {
        try wrapper.close()
    }
    
    deinit { try? close() }
}
#endif
