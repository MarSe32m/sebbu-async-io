//
//  AsyncUDPClient.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

public protocol AsyncUDPClientProtocol: Sendable {
    static func connect(to: Endpoint) async throws -> Self
    
    //TODO: We need a RawSpan version of this
    func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int
    
    //TODO: We need an OutputRawSpan version of this
    func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int

    consuming func close() async throws
}

public extension AsyncUDPClientProtocol {
    @inlinable
    func send(_ bytes: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await send(UnsafeRawBufferPointer(bytes))
    }
    
    @inlinable
    func send(_ bytes: Slice<UnsafeRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer)
    }
    
    @inlinable
    func send(_ bytes: Slice<UnsafeMutableRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer)
    }
    
    @inlinable
    func receive(into: Slice<UnsafeMutableRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        return try await receive(into: buffer)
    }
}

public final class AsyncUDPClient: AsyncUDPClientProtocol {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncUDPClient
    #elseif canImport(NIO)
    @usableFromInline
    internal typealias Implementation = NIOAsyncUDPClient
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
    public static func connect(to: Endpoint) async throws -> AsyncUDPClient {
        let client = try await Implementation.connect(to: to)
        return AsyncUDPClient(implementation: client)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await implementation.send(bytes)
    }
    
    @inlinable
    public func send(_ bytes: Slice<UnsafeRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer)
    }
    
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await implementation.receive(into: into)
    }
    
    @inlinable
    public func receive(into: Slice<UnsafeMutableRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        return try await receive(into: buffer)
    }

    @inlinable
    public consuming func close() async throws {
        try await implementation.close()
    }
}
