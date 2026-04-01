//
//  NIOAsyncUDPClient.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 1.4.2026.
//

#if canImport(NIO)
import NIO

public final class NIOAsyncUDPClient: AsyncUDPClientProtocol {
    public static func connect(to: Endpoint) async throws -> Self {
        fatalError("TODO: Implement")
    }
    
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        fatalError("TODO: Implement")
    }
    
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        fatalError("TODO: Implement")
    }
    
    
    public func close() throws {
        fatalError("TODO: Implement")
    }
    
    deinit { try? close() }
}
#endif
