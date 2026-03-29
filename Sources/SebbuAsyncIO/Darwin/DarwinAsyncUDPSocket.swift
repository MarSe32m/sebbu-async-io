#if canImport(Darwin)
import NIOCore
import NIOPosix

@usableFromInline
internal final class DarwinAsyncUDPSocket: Sendable {
    @usableFromInline
    let readStream: AsyncThrowingStream<AddressedEnvelope<ByteBuffer>, any Error>
    
    @usableFromInline
    let readContinuation: AsyncThrowingStream<AddressedEnvelope<ByteBuffer>, any Error>.Continuation
    
    @usableFromInline
    let channel: NIOAsyncChannel<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>
    
    @usableFromInline
    let outboundWriter: NIOAsyncChannelOutboundWriter<AddressedEnvelope<ByteBuffer>>
    
    @usableFromInline
    let processingTask: Task<Void, any Error>
    
    @inlinable
    init(channel: NIOAsyncChannel<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>) async throws {
        self.channel = channel
        let (_readStream, _readContinuation) = AsyncThrowingStream<AddressedEnvelope<ByteBuffer>, any Error>.makeStream()
        self.readStream = _readStream
        self.readContinuation = _readContinuation
        
        nonisolated(unsafe) var processingTask: Task<Void, any Error> = Task {}
        let outbound = try await withUnsafeThrowingContinuation { continuation in
            let _processingTask = Task {
                try await channel.executeThenClose { inbound, outbound in
                    continuation.resume(returning: (outbound))
                    do {
                        for try await packet in inbound {
                            _readContinuation.yield(packet)
                        }
                        _readContinuation.finish()
                    } catch {
                        _readContinuation.finish(throwing: error)
                    }
                    
                }
            }
            processingTask = _processingTask
        }
        self.processingTask = processingTask
        self.outboundWriter = outbound
    }
    
    @inlinable
    public static func bind(to: Endpoint) async throws -> DarwinAsyncUDPSocket {
        let bindAddress = to.nioSocketAddress
        let channel = try await DatagramBootstrap(group: .singletonMultiThreadedEventLoopGroup)
            .channelOption(.socketOption(.so_reuseaddr), value: 1)
            .bind(to: bindAddress).get()
        let asyncChannel = try await channel.eventLoop.submit {
            try NIOAsyncChannel<AddressedEnvelope<ByteBuffer>, AddressedEnvelope<ByteBuffer>>(
                wrappingChannelSynchronously: channel)
        }.get()
        return try await DarwinAsyncUDPSocket(channel: asyncChannel)
    }

    @inlinable
    public func send(_ data: [UInt8], to: Endpoint) async throws {
        //TODO: This is highly unoptimal...
        let bytes = ByteBuffer(bytes: data)
        try await outboundWriter.write(AddressedEnvelope(remoteAddress: to.nioSocketAddress, data: bytes))
    }

    @inlinable
    public func receive(from: inout Endpoint) async throws -> [UInt8] {
        //TODO: This is highly unoptimal...
        for try await var addressedEnvelope in readStream {
            addressedEnvelope.remoteAddress.withSockAddr { remotePointer, remoteLength in
                from.withMutableSockAddrStoragePointer { storage, length in
                    length.pointee = .init(remoteLength)
                    storage.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
                        pointer.pointee = remotePointer.pointee
                    }
                }
            }
            return addressedEnvelope.data.readBytes(length: addressedEnvelope.data.readableBytes) ?? []
        }
        //TODO: Should we throw an error here?
        return []
    }

    @inlinable
    public consuming func close() throws {
        processingTask.cancel()
        outboundWriter.finish()
        channel.channel.close(promise: nil)
    }
    
    deinit {
        try? close()
    }
}
#endif
