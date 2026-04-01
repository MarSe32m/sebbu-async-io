//
//  AsyncUDPSocket.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

public protocol AsyncUDPSocketProtocol: Sendable {
    static func bind(to: Endpoint) async throws -> Self

    //TODO: We need an RawSpan version of this
    func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int
    
    //TODO: We need an OutputRawSpan version of this
    func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int
    
    consuming func close() throws
}

public extension AsyncUDPSocketProtocol {
    @inlinable
    func send(_ bytes: UnsafeMutableRawBufferPointer, to: Endpoint) async throws -> Int {
        try await send(UnsafeRawBufferPointer(bytes), to: to)
    }
    
    @inlinable
    func send(_ bytes: Slice<UnsafeRawBufferPointer>, to: Endpoint) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer, to: to)
    }
    
    @inlinable
    func send(_ bytes: Slice<UnsafeMutableRawBufferPointer>, to: Endpoint) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer, to: to)
    }
    
    @inlinable
    func receive(into: Slice<UnsafeMutableRawBufferPointer>, from: inout Endpoint) async throws -> Int {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        return try await receive(into: buffer, from: &from)
    }
}

public final class AsyncUDPSocket: AsyncUDPSocketProtocol {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncUDPSocket
    #elseif canImport(NIO)
    @usableFromInline
    internal typealias Implementation = NIOAsyncUDPSocket
//    #elseif canImport(Darwin)
//    @usableFromInline
//    internal typealias Implementation = DarwinAsyncUDPSocket
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
    public static func bind(to: Endpoint) async throws -> AsyncUDPSocket {
        let implementation = try await Implementation.bind(to: to)
        return AsyncUDPSocket(implementation: implementation)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int {
        try await implementation.send(bytes, to: to)
    }
    
    @inlinable
    public func send(_ bytes: Slice<UnsafeRawBufferPointer>, to: Endpoint) async throws -> Int {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        return try await send(buffer, to: to)
    }

    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int {
        try await implementation.receive(into: into, from: &from)
    }
    
    @inlinable
    public func receive(into: Slice<UnsafeMutableRawBufferPointer>, from: inout Endpoint) async throws -> Int {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        return try await receive(into: buffer, from: &from)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}
