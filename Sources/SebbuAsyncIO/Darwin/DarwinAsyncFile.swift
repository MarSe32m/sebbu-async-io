#if canImport(Darwin)
import SystemPackage

@usableFromInline
internal final class DarwinAsyncFile: Sendable {
    public var fileSize: Int {
        get throws {
            fatalError("TODO: Implement")
        }
    }

    @inlinable
    public static func open(
        path: FilePath,
        //mode: FileOpenMode,
        //options: FileOpenOptions = []
    ) throws -> DarwinAsyncFile {
        fatalError("TODO: Implement")
    }

    @inlinable
    public static func create(
        path: FilePath,
        //mode: FileCreateMode,
        //options: FileCreateOptions = []
    ) throws -> DarwinAsyncFile {
        fatalError("TODO: Implement")
    }

    @inlinable
    public static func delete(
        path: FilePath
    ) throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func read(atMost: Int, atAbsoluteOffset offset: UInt) async throws(AsyncFile.Error) -> [UInt8] {
        fatalError("TODO: Implement")
    }

    @inlinable
    public func write(data: [UInt8], atAbsoluteOffset offset: UInt) async throws {
        fatalError("TODO: Implement")
    }

    @inlinable
    public consuming func close() throws {
        fatalError("TODO: Implement")
    }
    
    @inlinable
    deinit {
        try? close()
    }
}
#endif
