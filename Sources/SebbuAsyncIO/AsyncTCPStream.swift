//
//  AsyncTCPStream.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

public protocol AsyncTCPStreamProtocol: Sendable {
    static func connect(to: Endpoint) async throws -> Self

    //TODO: We need a RawSpan version of this
    func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int

    //TODO: We need an OutputRawSpan version of this
    func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int
    
    func transmit(file: borrowing AsyncFile) async throws

    consuming func close() throws
}

public extension AsyncTCPStreamProtocol {
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
    func sendAll(_ bytes: UnsafeRawBufferPointer) async throws {
        if bytes.isEmpty { return }
        var bytesSent = 0
        while bytesSent < bytes.count {
            let bytesSentThisIteration = try await send(bytes[bytesSent...])
            bytesSent += bytesSentThisIteration
        }
    }
    
    @inlinable
    func sendAll(_ bytes: UnsafeMutableRawBufferPointer) async throws {
        let buffer = UnsafeRawBufferPointer(bytes)
        try await sendAll(buffer)
    }
    
    @inlinable
    func sendAll(_ bytes: Slice<UnsafeRawBufferPointer>) async throws {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        try await sendAll(buffer)
    }
    
    @inlinable
    func sendAll(_ bytes: Slice<UnsafeMutableRawBufferPointer>) async throws {
        let buffer = UnsafeRawBufferPointer(rebasing: bytes)
        try await sendAll(buffer)
    }
    
    @inlinable
    func receive(into: Slice<UnsafeMutableRawBufferPointer>) async throws -> Int {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        return try await receive(into: buffer)
    }

    @inlinable
    func receive(exactly: Int, into: UnsafeMutableRawBufferPointer) async throws {
        precondition(exactly <= into.count, "Cannot receive \(exactly) bytes into a buffer that only has \(into.count) bytes.")
        var bytesReceived = 0
        let slice = into[0..<exactly]
        while bytesReceived < exactly {
            let bytesReceivedThisIteration = try await receive(into: slice[bytesReceived...])
            bytesReceived += exactly
        }
    }
    
    @inlinable
    func receive(exactly: Int, into: Slice<UnsafeMutableRawBufferPointer>) async throws {
        let buffer = UnsafeMutableRawBufferPointer(rebasing: into)
        try await receive(exactly: exactly, into: buffer)
    }
}

public final class AsyncTCPStream: AsyncTCPStreamProtocol {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncTCPStream
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncTCPStream
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncTCPStream
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
    public static func connect(to: Endpoint) async throws -> AsyncTCPStream {
        let stream = try await Implementation.connect(to: to)
        return AsyncTCPStream(implementation: stream)
    }

    //TODO: We need a RawSpan version of this
    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await implementation.send(bytes)
    }
    
    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await implementation.receive(into: into)
    }
    
    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        try await implementation.transmit(file: file)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}
