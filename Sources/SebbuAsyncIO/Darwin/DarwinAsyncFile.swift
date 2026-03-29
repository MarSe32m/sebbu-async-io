#if canImport(Darwin)
import Darwin
import Dispatch
import SystemPackage

@usableFromInline
internal final class DarwinAsyncFile: Sendable {
    @usableFromInline
    final class Storage: @unchecked Sendable {
        @usableFromInline
        var fd: CInt?

        @usableFromInline
        init(fd: CInt) {
            self.fd = fd
        }
    }

    @usableFromInline
    let queue: DispatchQueue

    @usableFromInline
    let storage: Storage

    @usableFromInline
    init(fd: CInt) {
        self.queue = DispatchQueue(
            label: "DarwinAsyncFile",
            attributes: .concurrent
        )
        self.storage = Storage(fd: fd)
    }

    public var fileSize: Int {
        get throws {
            try self.queue.sync {
                guard let fd = self.storage.fd else {
                    //TODO: Throw EBADF
                    throw AsyncFile.Error.unknownError
                }

                var st = stat()
                guard Darwin.fstat(fd, &st) == 0 else {
                    //TODO: Throw errno?, EIO?
                    throw AsyncFile.Error.unknownError
                }

                guard st.st_size >= 0, st.st_size <= off_t(Int.max) else {
                    //TODO: Throw EOVERFLOW?
                    throw AsyncFile.Error.unknownError
                }

                return Int(st.st_size)
            }
        }
    }

    @inlinable
    public static func open(
        path: FilePath
        // mode: FileOpenMode,
        // options: FileOpenOptions = []
    ) throws -> DarwinAsyncFile {
        let flags = O_RDWR | O_CLOEXEC

        let fd: CInt = try path.withPlatformString { platformPath in
            let rawFD = Darwin.open(platformPath, flags)
            guard rawFD >= 0 else {
                //TODO: Throw errno? EIO?
                throw AsyncFile.Error.unknownError
            }
            return rawFD
        }

        return DarwinAsyncFile(fd: fd)
    }

    @inlinable
    public static func create(
        path: FilePath
        // mode: FileCreateMode,
        // options: FileCreateOptions = []
    ) throws -> DarwinAsyncFile {
        let flags = O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC
        let permissions: mode_t = 0o666

        let fd: CInt = try path.withPlatformString { platformPath in
            let rawFD = Darwin.open(platformPath, flags, permissions)
            guard rawFD >= 0 else {
                //TODO: Throw errno? EIO?
                throw AsyncFile.Error.unknownError
            }
            return rawFD
        }

        return DarwinAsyncFile(fd: fd)
    }

    @inlinable
    public static func delete(
        path: FilePath
    ) throws {
        try path.withPlatformString { platformPath in
            guard Darwin.unlink(platformPath) == 0 else {
                //TODO: Throw errno? EIO?
                throw AsyncFile.Error.unknownError
            }
        }
    }

    @inlinable
    public func read(
        atMost count: Int,
        atAbsoluteOffset offset: UInt
    ) async throws(AsyncFile.Error) -> [UInt8] {
        guard count >= 0 else {
            //TODO: Throw EINVAL
            throw AsyncFile.Error.unknownError
        }
        guard count > 0 else {
            return []
        }

        let maxOffset = UInt(off_t.max)
        let byteCount = UInt(count)

        guard offset <= maxOffset, byteCount <= maxOffset, offset <= maxOffset - byteCount else {
            //TODO: Throw EOVERFLOW
            throw AsyncFile.Error.unknownError
        }

        do {
            return try await withUnsafeThrowingContinuation {
                (continuation: UnsafeContinuation<[UInt8], any Error>) in

                self.queue.async {
                    guard let fd = self.storage.fd else {
                        //TODO: Thorw EBADF
                        continuation.resume(throwing: AsyncFile.Error.unknownError)
                        return
                    }

                    let baseOffset = off_t(offset)
                    var buffer = [UInt8](repeating: 0, count: count)
                    var totalRead = 0
                    var failure: CInt?

                    buffer.withUnsafeMutableBytes { rawBuffer in
                        guard let base = rawBuffer.baseAddress else { return }

                        while totalRead < count {
                            let n = Darwin.pread(
                                fd,
                                base.advanced(by: totalRead),
                                count - totalRead,
                                baseOffset + off_t(totalRead)
                            )

                            if n > 0 {
                                totalRead += n
                                continue
                            }

                            if n == 0 {
                                break // EOF
                            }

                            if errno == EINTR {
                                continue
                            }

                            failure = errno
                            break
                        }
                    }

                    if let failure {
                        //TODO: Throw failure errno
                        continuation.resume(throwing: AsyncFile.Error.unknownError)
                        return
                    }

                    if totalRead < buffer.count {
                        buffer.removeSubrange(totalRead..<buffer.count)
                    }

                    continuation.resume(returning: buffer)
                }
            }
        } catch let error as AsyncFile.Error {
            throw error
        } catch {
            fatalError("Unreachable")
        }
    }

    @inlinable
    public func write(
        data: [UInt8],
        atAbsoluteOffset offset: UInt
    ) async throws {
        guard !data.isEmpty else {
            return
        }

        let maxOffset = UInt(off_t.max)
        let byteCount = UInt(data.count)

        guard offset <= maxOffset, byteCount <= maxOffset, offset <= maxOffset - byteCount else {
            //TODO: Throw EOVERFLOW
            throw AsyncFile.Error.unknownError
            
        }

        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Swift.Error>) in
            self.queue.async {
                guard let fd = self.storage.fd else {
                    //TODO: Throw EBADF
                    continuation.resume(throwing: AsyncFile.Error.unknownError)
                    return
                }

                let baseOffset = off_t(offset)
                var totalWritten = 0
                var failure: CInt?

                data.withUnsafeBytes { rawBuffer in
                    guard let base = rawBuffer.baseAddress else { return }

                    while totalWritten < data.count {
                        let n = Darwin.pwrite(
                            fd,
                            base.advanced(by: totalWritten),
                            data.count - totalWritten,
                            baseOffset + off_t(totalWritten)
                        )

                        if n > 0 {
                            totalWritten += n
                            continue
                        }

                        if n == 0 {
                            failure = EIO
                            break
                        }

                        if errno == EINTR {
                            continue
                        }

                        failure = errno
                        break
                    }
                }

                if let failure {
                    //TODO: Throw `failure` errno? EIO?
                    continuation.resume(throwing: AsyncFile.Error.unknownError)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @inlinable
    public consuming func close() throws {
        let fdToClose: CInt? = self.queue.sync(flags: .barrier) {
            let fd = self.storage.fd
            self.storage.fd = nil
            return fd
        }

        guard let fdToClose else {
            return
        }

        while Darwin.close(fdToClose) == -1 {
            if errno == EINTR {
                continue
            }
            //TODO: Throw errno? EIO?
            throw AsyncFile.Error.unknownError
        }
    }

    @inlinable
    deinit {
        try? close()
    }
}
#endif
