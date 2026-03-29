#if canImport(Darwin)
import Network

@usableFromInline
internal final class DarwinAsyncTCPListener: Sendable {
    @usableFromInline
    let listener: NetworkListener<TCP>
    
    @usableFromInline
    let stream: AsyncThrowingStream<NetworkConnection<TCP>, any Error>
    
    @usableFromInline
    let continuation: AsyncThrowingStream<NetworkConnection<TCP>, any Error>.Continuation
    
    @usableFromInline
    let listenerTask: Task<Void, Never>
    
    @inlinable
    init(listener: NetworkListener<TCP>) {
        self.listener = listener
        let (_stream, _continuation) = AsyncThrowingStream<NetworkConnection<TCP>, any Error>.makeStream()
        self.stream = _stream
        self.continuation = _continuation
        self.listenerTask = Task.detached {
            do {
                try await listener.run { _continuation.yield($0) }
            } catch {
                _continuation.finish(throwing: error)
            }
        }
    }
    
    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> DarwinAsyncTCPListener {
        let parameters = NWParameters.tcp
            .localEndpoint(on.endpoint)
            //.localPort(.init(rawValue: on.port)!)
            .localEndpointReuseAllowed(true)
        let listener = try NetworkListener(using: .parameters(initialParameters: parameters, {
            TCP()
        }))
        return DarwinAsyncTCPListener(listener: listener)
    }

    @inlinable
    public func accept() async throws -> DarwinAsyncTCPStream {
        for try await connection in stream {
            return DarwinAsyncTCPStream(connection: connection)
        }
        //TODO: Throw a more descriptive error
        throw _Concurrency.CancellationError()
    }

    @inlinable
    public consuming func close() throws {
        listenerTask.cancel()
    }
    
    deinit {
        try? close()
    }
}
#endif
