import SystemPackage

public final class AsyncFile: Sendable {
    public enum Error: Swift.Error {
        case endOfFile
        case unknownError
    }
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncFile
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncFile
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncFile
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    public var fileSize: Int {
        get throws {
            try implementation.fileSize
        }
    }

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }
    
    public static func open(
        path: FilePath,
        //mode: FileOpenMode,
        //options: FileOpenOptions = []
    ) throws -> AsyncFile {
        let implementation = try Implementation.open(path: path)
        return AsyncFile(implementation: implementation)
    }

    public static func create(
        path: FilePath,
        //mode: FileCreateMode,
        //options: FileCreateOptions = []
    ) throws -> AsyncFile {
        let implementation = try Implementation.create(path: path)
        return AsyncFile(implementation: implementation)
    }

    public static func delete(path: FilePath) throws {
        try Implementation.delete(path: path)
    }

    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func read(into: UnsafeMutableRawBufferPointer, atAbsoluteOffset offset: UInt) async throws(AsyncFile.Error) -> Int {
        try await implementation.read(into: into, atAbsoluteOffset: offset)
    }

    @inlinable
    public func readUntilEndOfFile() async throws(AsyncFile.Error) -> [UInt8] {
        var data: [UInt8] = []
        let readBuffer: UnsafeMutableRawBufferPointer = .allocate(byteCount: 65536, alignment: 1)
        defer { readBuffer.deallocate() }
        var offset: UInt = 0
        while true {
            do {
                let bytesRead = try await read(into: readBuffer, atAbsoluteOffset: offset)
                if bytesRead == 0 { break }
                offset += UInt(bytesRead)
                data.append(contentsOf: readBuffer[0..<bytesRead])
            } catch {
                if error == .endOfFile { break }
            }
        }
        return data
    }
    
    //TODO: We need a RawSpan version of this
    @inlinable
    public func write(_ bytes: UnsafeRawBufferPointer, atAbsoluteOffset offset: UInt) async throws -> Int {
        try await implementation.write(bytes, atAbsoluteOffset: offset)
    }

    @inlinable
    public func writeAll(_ bytes: UnsafeRawBufferPointer, atAbsoluteOffset offset: UInt) async throws {
        var _offset: UInt = 0
        while _offset < UInt(bytes.count) {
            let bytesWritten = try await write(.init(start: bytes.baseAddress?.advanced(by: Int(_offset)), count: bytes.count - Int(_offset)), atAbsoluteOffset: offset + _offset)
            if bytesWritten == 0 {
                throw AsyncFile.Error.unknownError
            }
            _offset += UInt(bytesWritten)
        }
    }

    public consuming func close() throws {
        try implementation.close()
    }
}
