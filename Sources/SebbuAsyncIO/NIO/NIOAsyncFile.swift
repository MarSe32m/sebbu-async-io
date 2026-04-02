//
//  NIOAsyncFile.swift
//  sebbu-async-io
//
//  Created by Sebastian Toivonen on 2.4.2026.
//

#if canImport(NIO)
import NIO
import _NIOFileSystem
import SystemPackage

@usableFromInline
internal final class NIOAsyncFile: AsyncFileProtocol {
    @usableFromInline
    static let fileSystem = FileSystem(threadPool: .singleton)
    
    @usableFromInline
    var fileSize: Int {
        get async throws {
            try await Int(handle.info().size)
        }
    }
    
    @usableFromInline
    let handle: ReadWriteFileHandle
    
    @inlinable
    init(handle: ReadWriteFileHandle) {
        self.handle = handle
    }

    @inlinable
    static func open(path: SystemPackage.FilePath) async throws -> NIOAsyncFile {
        let handle = try await fileSystem.openFile(forReadingAndWritingAt: path, options: .modifyFile(createIfNecessary: false))
        return NIOAsyncFile(handle: handle)
    }
    
    @inlinable
    static func create(path: SystemPackage.FilePath) async throws -> NIOAsyncFile {
        let handle = try await fileSystem.openFile(forReadingAndWritingAt: path, options: .newFile(replaceExisting: true))
        return NIOAsyncFile(handle: handle)
    }
    
    @inlinable
    static func delete(path: SystemPackage.FilePath) async throws {
        let _ = try await fileSystem.removeItem(at: path)
    }
    
    //TODO: We need an OutputRawSpan version of this
    @inlinable
    func read(into: UnsafeMutableRawBufferPointer, atAbsoluteOffset offset: UInt) async throws(AsyncFile.Error) -> Int {
        do {
            var buffer = try await handle.readChunk(fromAbsoluteOffset: Int64(offset), length: .bytes(Int64(into.count)))
            return buffer.read(into: into)
        } catch {
            throw AsyncFile.Error.unknownError
        }
    }
    //TODO: We need a RawSpan version of this
    @inlinable
    func write(_ bytes: UnsafeRawBufferPointer, atAbsoluteOffset offset: UInt) async throws -> Int {
        let buffer = ByteBuffer(bytes: bytes)
        return Int(try await handle.write(contentsOf: buffer, toAbsoluteOffset: Int64(offset)))
    }
    
    @inlinable
    func close() async throws {
        try await handle.close(makeChangesVisible: true)
    }
    
    @inlinable
    deinit {
        let handle = self.handle
        //TODO: This is suboptimal...
        Task { try await handle.close(makeChangesVisible: true) }
    }
}
#endif
