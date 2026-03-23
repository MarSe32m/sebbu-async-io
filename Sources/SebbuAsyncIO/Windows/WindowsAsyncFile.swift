#if os(Windows)
import SystemPackage
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncFile: Sendable {
    @usableFromInline
    nonisolated(unsafe) let handle: HANDLE

    @usableFromInline
    let skipSuccessCompletions: Bool

    public var fileSize: Int {
        get throws {
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
    ) throws -> WindowsAsyncFile {
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
    ) throws -> WindowsAsyncFile {
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
    ) throws {
        let deleted = path.withPlatformString { path in 
            DeleteFileW(path)
        }
        if !deleted {
            throw IOCompletionPort.IOCPError.error(GetLastError())
        }
    }

    @inlinable
    public func read(atMost: Int, atAbsoluteOffset offset: UInt, wait: Bool = false) async throws(AsyncFile.Error) -> [UInt8] {
        var buffer: [UInt8] = .init(repeating: 0, count: Swift.min(atMost, 1 << 32 - 1))
        var result: Eventloop.SubmissionResult
        var bytesRead: UInt32 = 0
        do {
            var span = buffer.mutableSpan
            var bytes = span.mutableBytes
            result = try await Eventloop.shared.readFile(handle: handle, buffer: &bytes, bytesRead: &bytesRead, offset: UInt64(offset), skipSuccessCompletions: !wait && skipSuccessCompletions)
            extendLifetime(bytes)
        } catch let error as IOCompletionPort.IOCPError {
            if case .error(let errCode) = error {
                if errCode == ERROR_HANDLE_EOF {
                    throw AsyncFile.Error.endOfFile
                }
            }
            throw AsyncFile.Error.unknownError
        } catch {
            fatalError("Unreachable")
        }
        switch result {
            case .synchronous: buffer.removeLast(buffer.count - Int(bytesRead))
            case .completion(let completion): 
                buffer.removeLast(buffer.count - completion.bytes)
        }
        return buffer
    }

    @inlinable
    public func write(data: [UInt8], atAbsoluteOffset offset: UInt, wait: Bool = false) async throws {
        var bytesWritten = 0
        while bytesWritten < data.count {
            let bytes = data.span.extracting(bytesWritten..<(data.count - bytesWritten)).bytes
            var _bytesWritten: UInt32 = 0
            let result = try await Eventloop.shared.writeFile(handle: handle, buffer: bytes, bytesWritten: &_bytesWritten, offset: UInt64(offset), skipSuccessCompletions: !wait && skipSuccessCompletions)
            switch result {
                case .synchronous: bytesWritten += Int(_bytesWritten)
                case .completion(let completion):
                    bytesWritten += completion.bytes
            }
            extendLifetime(bytes)
        }
    }

    @inlinable
    public consuming func close() throws {
        CloseHandle(handle)
    }
}
#endif