import SystemPackage
import WinSDK

public final class AsyncFile: Sendable {
    public enum Error: Swift.Error {
        case endOfFile
        case unknownError
    }
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncFile
    #elseif os(Linux)
    internal typealias Implementation = LinuxAsyncFile
    #elseif canImport(Darwin)
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

    public func read(atMost: Int, atAbsoluteOffset offset: UInt) async throws(AsyncFile.Error) -> [UInt8] {
        try await implementation.read(atMost: atMost, atAbsoluteOffset: offset)
    }

    public func readUntilEndOfFile() async throws(AsyncFile.Error) -> [UInt8] {
        var data: [UInt8] = []
        var offset: UInt = 0
        while true {
            do {
                let bytes = try await read(atMost: 65536, atAbsoluteOffset: offset)
                offset += UInt(bytes.count)
                data.append(contentsOf: bytes)
            } catch {
                if error == .endOfFile { break }
            }
        }
        return data
    }
 
    public func write(data: [UInt8], atAbsoluteOffset offset: UInt) async throws {
        try await implementation.write(data: data, atAbsoluteOffset: offset)
    }

    public consuming func close() throws {
        try implementation.close()
    }
}