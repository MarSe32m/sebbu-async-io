//
//  AsyncTCPListener.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

public protocol AsyncTCPListenerProtocol: Sendable {
    static func listen(on: Endpoint, backlog: Int) async throws -> Self
    func accept() async throws -> AsyncTCPStream
    consuming func close() async throws
}

public final class AsyncTCPListener: AsyncTCPListenerProtocol {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncTCPListener
    #elseif canImport(NIO)
    @usableFromInline
    internal typealias Implementation = NIOAsyncTCPListener
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }

    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> AsyncTCPListener {
        let listener = try await Implementation.listen(on: on, backlog: backlog)
        return AsyncTCPListener(implementation: listener)
    }

    @inlinable
    public func accept() async throws -> AsyncTCPStream {
        try await implementation.accept()
    }

    @inlinable
    public consuming func close() async throws {
        try await implementation.close()
    }
}
