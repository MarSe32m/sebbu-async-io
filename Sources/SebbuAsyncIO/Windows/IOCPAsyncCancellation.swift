#if os(Windows)
import WinSDK
import SebbuIOCP
import Synchronization

@usableFromInline
struct CancellationContainer: ~Copyable, Sendable {
    @usableFromInline
    enum State: UInt8, AtomicRepresentable, Sendable {
        case initialized
        case enqueueing
        case enqueued
        case cancelled
    }
    
    @usableFromInline
    let state: Atomic<State> = .init(.initialized)

    @usableFromInline
    nonisolated(unsafe) let context: UnsafeMutablePointer<Context>

    @inlinable
    init(context: UnsafeMutablePointer<Context>) {
        self.context = .init(context)
    }

    @inlinable
    func enqueue(continuation: UnsafeContinuation<Eventloop.Completion, any Error>, _ operation: () -> Void) {
        if state.compareExchange(expected: .initialized, desired: .enqueueing, ordering: .sequentiallyConsistent).exchanged { 
            operation() 
            atomicMemoryFence(ordering: .sequentiallyConsistent)
        }
        if state.compareExchange(expected: .enqueueing, desired: .enqueued, ordering: .sequentiallyConsistent).original == .cancelled {
            continuation.resume(throwing: _Concurrency.CancellationError())
        }
    }

    @inlinable
    func cancel(socket: SOCKET) {
        cancel(handle: HANDLE(bitPattern: UInt(socket)))
    }

    @inlinable
    func cancel(handle: HANDLE!) {
        let oldState = state.exchange(.cancelled, ordering: .sequentiallyConsistent)
        // If the request has already been enqueud, then we may call CancelIoEx, otherwise the enqueue function will deal with cancellation
        if oldState == .enqueued {
            let cancelled = CancelIoEx(handle, UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self))
            if !cancelled {
                print("TODO: Handle failed cancellation: \(#file):\(#line)")
            }
        }
    }
}

@inlinable
func withContextCancellationHandler(socket: SOCKET, context: UnsafeMutablePointer<Context>, operation: () -> Void) async throws -> Eventloop.Completion {
    let cancellationContainer = CancellationContainer(context: context)
    return try await withTaskCancellationHandler(operation: {
        try await withUnsafeThrowingContinuation { continuation in 
            context.pointee.continuation = continuation
            cancellationContainer.enqueue(continuation: continuation, operation)
        }
    }, onCancel: { cancellationContainer.cancel(socket: socket) })
}

@inlinable
func withContextCancellationHandler(socket: SOCKET, continuation: UnsafeContinuation<Eventloop.Completion, any Error>, context: UnsafeMutablePointer<Context>, operation: () -> Void) async throws -> Eventloop.Completion {
    let cancellationContainer = CancellationContainer(context: context)
    return try await withTaskCancellationHandler(operation: {
        try await withUnsafeThrowingContinuation { continuation in 
            context.pointee.continuation = continuation
            cancellationContainer.enqueue(continuation: continuation, operation)
        }
    }, onCancel: { cancellationContainer.cancel(socket: socket) })
}


@inlinable
func withContextCancellationHandler(handle: HANDLE, context: UnsafeMutablePointer<Context>, operation: () -> Void) async throws -> Eventloop.Completion {
    let cancellationContainer = CancellationContainer(context: context)
    nonisolated(unsafe) let handle = handle
    return try await withTaskCancellationHandler(operation: {
        try await withUnsafeThrowingContinuation { continuation in 
            context.pointee.continuation = continuation
            cancellationContainer.enqueue(continuation: continuation, operation)
        }
    }, onCancel: { cancellationContainer.cancel(handle: handle) })
}
#endif