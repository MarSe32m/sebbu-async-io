#if canImport(Darwin)

@usableFromInline
internal final class DarwinAsyncTCPStream: Sendable {
    @inlinable
    public static func connect(to: Endpoint) async throws -> DarwinAsyncTCPStream {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func receive(atLeast: Int = 1, atMost: Int) async throws -> [UInt8] {
        fatalError("TODO: Implement")
    }

    @inline(always)
    public func receive(exactly: Int) async throws -> [UInt8] {
        try await receive(atLeast: exactly, atMost: exactly)
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
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
