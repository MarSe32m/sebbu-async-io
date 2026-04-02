#if os(Windows)
import SystemPackage
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncFile: AsyncFileProtocol {
    @usableFromInline
    nonisolated(unsafe) let handle: HANDLE

    @usableFromInline
    let skipSuccessCompletions: Bool

    public var fileSize: Int {
        get async throws {
            var upperSize: DWORD = 0
            let lowerSize = GetFileSize(handle, &upperSize)
            if lowerSize == INVALID_FILE_SIZE {
                //TODO: More specific error handling
                throw AsyncFile.Error.unknownError
            }
            return Int(UInt64(upperSize) << 32 | UInt64(lowerSize))
        }
    }

    @inlinable
    init(handle: HANDLE, skipSuccessCompletions: Bool) {
        self.handle = handle
        self.skipSuccessCompletions = skipSuccessCompletions
    }

    @inlinable
    public static func open(
        path: FilePath,
        //mode: FileOpenMode,
        //options: FileOpenOptions = []
    ) async throws -> WindowsAsyncFile {
        let handle = path.withPlatformString { path in 
            CreateFileW(path, GENERIC_READ | UInt32(bitPattern: GENERIC_WRITE), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw IOCompletionPort.IOCPError.error(GetLastError())
        }
        try Eventloop.shared.associate(handle)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(handle, UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncFile(handle: handle, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public static func create(
        path: FilePath,
        //mode: FileCreateMode,
        //options: FileCreateOptions = []
    ) async throws -> WindowsAsyncFile {
        let handle = path.withPlatformString { path in 
            CreateFileW(path, GENERIC_READ | UInt32(bitPattern: GENERIC_WRITE), DWORD(FILE_SHARE_READ), nil, DWORD(CREATE_NEW), DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else {
            throw IOCompletionPort.IOCPError.error(GetLastError())
        }
        try Eventloop.shared.associate(handle)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(handle, UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncFile(handle: handle, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public static func delete(
        path: FilePath
    ) async throws {
        let deleted = path.withPlatformString { path in 
            DeleteFileW(path)
        }
        if !deleted {
            throw IOCompletionPort.IOCPError.error(GetLastError())
        }
    }

    @inlinable
    public func read(into: UnsafeMutableRawBufferPointer, atAbsoluteOffset offset: UInt) async throws(AsyncFile.Error) -> Int {
        var result: Eventloop.SubmissionResult
        var bytesRead: UInt32 = 0
        do {
            var span = MutableRawSpan(_unsafeStart: into.baseAddress!, byteCount: into.count)
            result = try await Eventloop.shared.readFile(handle: handle, buffer: &span, bytesRead: &bytesRead, offset: UInt64(offset), skipSuccessCompletions: skipSuccessCompletions)
        } catch let error as IOCompletionPort.IOCPError {
            if case .error(let errCode) = error, errCode == ERROR_HANDLE_EOF {
                throw AsyncFile.Error.endOfFile
            }
            throw AsyncFile.Error.unknownError
        } catch {
            fatalError("Unreachable")
        }
        return switch result {
            case .synchronous: Int(bytesRead)
            case .completion(let completion): completion.bytes
        }
    }

    @inlinable
    public func write(_ bytes: UnsafeRawBufferPointer, atAbsoluteOffset offset: UInt) async throws -> Int {
        let chunkCount = Swift.min(bytes.count, Int(UInt32.max))
        let chunk = UnsafeRawBufferPointer(start: bytes.baseAddress, count: chunkCount)
        let bytes = RawSpan(_unsafeStart: chunk.baseAddress!, byteCount: chunkCount)
        var _bytesWritten: UInt32 = 0
        let result = try await Eventloop.shared.writeFile(handle: handle, buffer: bytes, bytesWritten: &_bytesWritten, offset: UInt64(offset), skipSuccessCompletions: skipSuccessCompletions)
        extendLifetime(bytes)
        return switch result {
            case .synchronous: Int(_bytesWritten)
            case .completion(let completion): completion.bytes
        }
    }

    @inlinable
    public consuming func close() async throws {
        CloseHandle(handle)
    }
    
    @inlinable
    deinit {
        CloseHandle(handle)
    }
}
#endif
