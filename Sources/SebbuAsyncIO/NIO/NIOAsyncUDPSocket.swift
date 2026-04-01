//
//  NIOAsyncUDPSocket.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

public final class NIOAsyncUDPSocket: AsyncUDPSocketProtocol {
    
    public static func bind(to: Endpoint) async throws -> Self {
        fatalError("TODO: Implement")
    }
    
    public func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int {
        fatalError("TODO: Implement")
    }
    
    public func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int {
        fatalError("TODO: Implement")
    }
    
    public func close() throws {
        fatalError("TODO: Implement")
    }
    
    deinit { try? close() }
}
#endif
