//
//  NIOAsyncTCPStream.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

@usableFromInline
internal final class NIOAsyncTCPStream: AsyncTCPStreamProtocol {
    
    @inlinable
    public static func connect(to: Endpoint) async throws -> NIOAsyncTCPStream {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        fatalError("TODO: Implement")
    }
    
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public consuming func close() throws {
        fatalError("TODO: Implement")
    }

    deinit { try? close() }
}
#endif
