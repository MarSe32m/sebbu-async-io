#if canImport(Darwin)
@usableFromInline
internal final class DarwinAsyncUDPSocket: Sendable {
    @inlinable
    public static func bind(to: Endpoint) async throws -> DarwinAsyncUDPSocket {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func send(_ data: [UInt8], to: Endpoint) async throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func receive(from: inout Endpoint) async throws -> [UInt8] {
        fatalError("TODO: Implement")
    }

    @inlinable
    public consuming func close() throws {
        fatalError("TODO: Implement")
    }
    
    deinit {
        try? close()
    }
}
#endif
