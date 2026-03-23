#if os(Windows)
import SebbuIOCP
import WinSDK

//TODO: Get rid of Foundation dependency
import FoundationEssentials

@usableFromInline
internal final class Eventloop: Sendable {
    public enum SubmissionResult: Sendable {
        case synchronous
        case completion(Completion)
    }

    public struct Completion: Sendable {
        public let bytes: Int
        public let key: UInt64

        @inlinable
        internal init(_ completion: IOCompletionPort.Completion) {
            self.bytes = completion.bytes
            self.key = completion.key
        }

        @inlinable
        internal init() {
            bytes = 0
            key = 0
        }
    }

    @usableFromInline
    let iocp: IOCompletionPort

    @usableFromInline
    static let shared: Eventloop = Eventloop()

    @usableFromInline
    nonisolated(unsafe) var contextCache: PointerCache<Context> = PointerCache(capacity: 65536)

    internal init() {
        self.iocp = try! IOCompletionPort(numberOfConcurrentThreads: 0)
        for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
            var thread = Thread {
                self.workerFunction()
            }
            thread.detach()
        }
    }

    internal func workerFunction() {
        while true {
            do {
                let completion: IOCompletionPort.Completion = try iocp.wait()
                guard let overlappedPtr = completion.overlapped else {
                    precondition(completion.key == 0, "Shutdown message requires completion.key to be 0")
                    break
                }
                let context = UnsafeMutableRawPointer(overlappedPtr).assumingMemoryBound(to: Context.self)
                let _completion = Completion(completion)
                context.pointee.completion = _completion
                var error: Context.Error? = nil
                if completion.wasError {
                    let _error = switch completion.key {
                        // Socket IO
                        case 1: IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
                        // File IO
                        case 2: IOCompletionPort.IOCPError.error(GetLastError())
                        default: fatalError("Unreachable")
                    }
                    if case .wsaError(let errCode) = _error {
                        if errCode == ERROR_OPERATION_ABORTED {
                            error = .cancellation
                        }
                    } else if case .error(let errCode) = _error {
                        if errCode == ERROR_OPERATION_ABORTED {
                            error = .cancellation
                        }
                    }
                }
                let originalState = context.pointee.state.exchange(.dequeued, ordering: .acquiringAndReleasing)
                switch originalState {
                    case .start: break
                    case .finishedSynchronously: deallocate(context: context)
                    case .continuationSupplied:
                        if let error {
                            context.pointee.continuation.resume(throwing: error.underlyingError)
                        } else {
                            context.pointee.continuation.resume(returning: _completion)
                        }
                        deallocate(context: context)
                    case .dequeued: fatalError("Unreachable")
                }
            } catch {
                // This should never be reached
                fatalError("\(error) not handled")
            }
        }
    }

    @inlinable
    internal func allocateContext() -> UnsafeMutablePointer<Context> {
        contextCache.allocate()
    }

    @inlinable
    internal func deallocate(context: UnsafeMutablePointer<Context>) {
        contextCache.deallocateAndDeinitialize(context)
    }

    @inlinable
    internal func associate(_ socket: SOCKET) throws {
        try iocp.associate(socket, key: 1)
    }

    @inlinable
    internal func associate(_ handle: HANDLE) throws {
        try iocp.associate(handle, key: 2)
    }

    @inlinable
    internal func accept(listenSocket: SOCKET, acceptSocket: SOCKET, addressBuffer: UnsafeMutableRawBufferPointer, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: listenSocket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try iocp.accept(listenSocket: listenSocket, acceptSocket: acceptSocket, addressBuffer: addressBuffer, overlapped: overlapped)
        }
    }

    @inlinable
    internal func finishAccept(listenSocket: SOCKET, acceptSocket: SOCKET) throws {
        try iocp.finishAccept(listenSocket: listenSocket, acceptSocket: acceptSocket, key: 1)
    }

    @inlinable
    internal func connect(socket: SOCKET, destination: UnsafePointer<sockaddr_storage>, destinationLength: Int, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try iocp.connect(socket: socket, destination: destination, destinationLength: destinationLength, overlapped: overlapped)
        }
    }

    @inlinable
    internal func finishConnect(socket: SOCKET) throws {
        try iocp.finishConnect(socket: socket)
    }

    @inlinable
    internal func send(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, bytesSent: UnsafeMutablePointer<UInt32>, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try iocp.send(socket: socket, buffers: .init(start: buffer, count: 1), bytesSent: bytesSent, flags: 0, overlapped: overlapped)
        }
    }

    @inlinable
    internal func send(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, bytesSent: UnsafeMutablePointer<UInt32>, address: Endpoint, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try address.withSockAddrPointer { address, addressLength in 
                try iocp.send(socket: socket, buffers: .init(start: buffer, count: 1), bytesSent: bytesSent, flags: 0, address: address, addressLength: Int(addressLength), overlapped: overlapped)
            }
        }
    }

    @inlinable
    internal func receive(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, bytesReceived: UnsafeMutablePointer<UInt32>, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try iocp.receive(socket: socket, buffers: .init(start: buffer, count: 1), bytesReceived: bytesReceived, flags: 0, overlapped: overlapped)
        }
    }

    @inlinable
    internal func receive(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, bytesReceived: UnsafeMutablePointer<UInt32>, from: inout Endpoint, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try from.withMutableSockAddrStoragePointer { from, addressLength in 
                try iocp.receiveFrom(socket: socket, buffers: .init(start: buffer, count: 1), bytesReceived: bytesReceived, flags: 0, address: from, addressLength: addressLength, overlapped: overlapped)
            }
        }
    }

    @inlinable
    internal func readFile(handle: HANDLE, buffer: inout MutableRawSpan, bytesRead: UnsafeMutablePointer<UInt32>, offset: UInt64, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(handle: handle, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try buffer.withUnsafeMutableBytes { buffer in 
                try iocp.readFile(handle: handle, buffer: buffer, bytesRead: bytesRead, offset: offset, overlapped: overlapped)
            }
        }
    }

    @inlinable
    internal func writeFile(handle: HANDLE, buffer: borrowing RawSpan, bytesWritten: UnsafeMutablePointer<UInt32>, offset: UInt64, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(handle: handle, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try buffer.withUnsafeBytes { buffer in 
                try iocp.writeFile(handle: handle, buffer: buffer, bytesWritten: bytesWritten, offset: offset, overlapped: overlapped)
            }
        }
    }

    @inlinable
    internal func transmitFile(socket: SOCKET, file: HANDLE, skipSuccessCompletions: Bool) async throws -> SubmissionResult {
        try await withContext(socket: socket, skipSuccessCompletions: skipSuccessCompletions) { overlapped in 
            try iocp.transmitFile(socket: socket, file: file, overlapped: overlapped)
        }
    }
}
#endif