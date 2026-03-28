#if canImport(Darwin)

@usableFromInline
internal final class DarwinAsyncUDPClient: Sendable {
    @inlinable
    public static func connect(to: Endpoint) async throws -> DarwinAsyncUDPClient {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func receive() async throws -> [UInt8] {
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
