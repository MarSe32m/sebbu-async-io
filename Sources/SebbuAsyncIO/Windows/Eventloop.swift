#if os(Windows)
import SebbuIOCP
import WinSDK

//TODO: Get rid of Foundation dependency
import FoundationEssentials

@usableFromInline
internal final class Eventloop: Sendable {
    public struct Completion: Sendable {
        public let bytes: Int
        public let key: UInt64

        @inlinable
        internal init(_ completion: IOCompletionPort.Completion) {
            self.bytes = completion.bytes
            self.key = completion.key
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
                let contextPointer = UnsafeMutableRawPointer(overlappedPtr).assumingMemoryBound(to: Context.self)
                if completion.wasError {
                    let error = switch completion.key {
                        // Socket IO
                        case 1: IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
                        // File IO
                        case 2: IOCompletionPort.IOCPError.error(GetLastError())
                        default: fatalError("Unreachable")
                    }
                    if case .wsaError(let errCode) = error {
                        if errCode == ERROR_OPERATION_ABORTED {
                            contextPointer.pointee.continuation.resume(throwing: _Concurrency.CancellationError())
                            continue
                        }
                    } else if case .error(let errCode) = error {
                        if errCode == ERROR_OPERATION_ABORTED {
                            contextPointer.pointee.continuation.resume(throwing: _Concurrency.CancellationError())
                            continue
                        }
                    }
                    contextPointer.pointee.continuation.resume(throwing: error)
                } else {
                    contextPointer.pointee.continuation.resume(returning: Completion(completion))
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
    internal func _enqueue(socket: SOCKET, operation: (_ context: UnsafeMutablePointer<Context>) -> Void) async throws -> Completion {
        let context = allocateContext(); defer { deallocate(context: context) }
        return try await withContextCancellationHandler(socket: socket, context: context) {
            operation(context) 
        }
    }

    @inlinable
    internal func _enqueue(handle: HANDLE, operation: (_ context: UnsafeMutablePointer<Context>) -> Void) async throws -> Completion {
        let context = allocateContext(); defer { deallocate(context: context) }
        return try await withContextCancellationHandler(handle: handle, context: context) {
            operation(context)
        }
    }

    @inlinable
    internal func accept(listenSocket: SOCKET, acceptSocket: SOCKET, addressBuffer: UnsafeMutableRawBufferPointer) async throws -> Completion {
        try await _enqueue(socket: listenSocket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try iocp.accept(listenSocket: listenSocket, acceptSocket: acceptSocket, addressBuffer: addressBuffer, overlapped: overlapped)
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func finishAccept(listenSocket: SOCKET, acceptSocket: SOCKET) throws {
        try iocp.finishAccept(listenSocket: listenSocket, acceptSocket: acceptSocket, key: 1)
    }

    @inlinable
    internal func connect(socket: SOCKET, destination: UnsafePointer<sockaddr_storage>, destinationLength: Int) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try iocp.connect(socket: socket, destination: destination, destinationLength: destinationLength, overlapped: overlapped)
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func finishConnect(socket: SOCKET) throws {
        try iocp.finishConnect(socket: socket)
    }

    @inlinable
    internal func send(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try iocp.send(socket: socket, buffers: .init(start: buffer, count: 1), flags: 0, overlapped: overlapped)
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func send(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, address: Endpoint) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try address.withSockAddrPointer { address, addressLength in
                    try iocp.send(socket: socket, buffers: .init(start: buffer, count: 1), flags: 0, address: address, addressLength: Int(addressLength), overlapped: overlapped)
                }
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func receive(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try iocp.receive(socket: socket, buffers: .init(start: buffer, count: 1), flags: 0, overlapped: overlapped)
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func receive(socket: SOCKET, buffer: UnsafeMutablePointer<WSABUF>, from: inout Endpoint) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try from.withMutableSockAddrStoragePointer { from, addressLength in 
                    try iocp.receiveFrom(socket: socket, buffers: .init(start: buffer, count: 1), flags: 0, address: from, addressLength: addressLength, overlapped: overlapped)
                }
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func readFile(handle: HANDLE, buffer: inout MutableRawSpan, offset: UInt64) async throws -> Completion {
        try await _enqueue(handle: handle) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try buffer.withUnsafeMutableBytes { buffer in 
                    try iocp.readFile(handle: handle, buffer: buffer, offset: offset, overlapped: overlapped)
                }
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func writeFile(handle: HANDLE, buffer: borrowing RawSpan, offset: UInt64) async throws -> Completion {
        try await _enqueue(handle: handle) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try buffer.withUnsafeBytes { buffer in 
                    try iocp.writeFile(handle: handle, buffer: buffer, offset: offset, overlapped: overlapped)
                }
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }

    @inlinable
    internal func transmitFile(socket: SOCKET, file: HANDLE) async throws -> Completion {
        try await _enqueue(socket: socket) { context in 
            let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
            do {
                try iocp.transmitFile(socket: socket, file: file, overlapped: overlapped)
            } catch let error {
                context.pointee.continuation.resume(throwing: error)
            }
        }
    }
}
#endif