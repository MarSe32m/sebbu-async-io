//
//  ByteBuffer extensions.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 2.4.2026.
//

#if canImport(NIO)
import NIOCore

extension ByteBuffer {
    @inlinable
    mutating func read(into: UnsafeMutableRawBufferPointer) -> Int {
        readWithUnsafeReadableBytes { buffer in
            let bytesToRead = Swift.min(into.count, buffer.count)
            let buffer = UnsafeRawBufferPointer(rebasing: buffer[0..<bytesToRead])
            into.copyMemory(from: buffer)
            return bytesToRead
        }
    }
}
#endif
