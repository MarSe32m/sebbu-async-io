#if canImport(Darwin)

@usableFromInline
internal final class DarwinAsyncTCPListener: Sendable {
    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> DarwinAsyncTCPListener {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func accept() async throws -> DarwinAsyncTCPStream {
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
