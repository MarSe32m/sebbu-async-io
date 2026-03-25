#if os(Windows)
import WinSDK
import SebbuIOCP
import Synchronization

@usableFromInline
struct ContextStateMachine: Sendable {
    @usableFromInline
    nonisolated(unsafe) let context: UnsafeMutablePointer<Context>

    @usableFromInline
    let skipSuccessCompletions: Bool

    @inlinable
    init(context: UnsafeMutablePointer<Context>, skipSuccessCompletions: Bool) {
        self.context = context
        self.skipSuccessCompletions = skipSuccessCompletions
    }

    @inlinable
    func enqueue() async throws -> Eventloop.SubmissionResult {
        let completion = try await withUnsafeThrowingContinuation { continuation in
            context.pointee.continuation = continuation
            let (exchanged, old) = context.pointee.state.compareExchange(expected: .start, desired: .continuationSupplied, ordering: .acquiringAndReleasing)
            if exchanged { return }
            
            assert(old == .dequeued, "Old state must have been dequeued!")
            
            let completion = context.pointee.completion
            let error = context.pointee.error
            context.pointee.continuation = nil
            context.cache()
            
            if let error {
                continuation.resume(throwing: error.underlyingError)
            } else {
                continuation.resume(returning: completion)
            }
        }
        return .completion(completion)
    }

    @inlinable
    func completeSynchronously() {
        if skipSuccessCompletions {
            context.cache()
            return
        }

        let (exchanged, old) = context.pointee.state.compareExchange(expected: .start, desired: .finishedSynchronously, ordering: .acquiringAndReleasing)
        if exchanged { return }

        assert(old == .dequeued, "Old state must be dequeued here!")
        context.cache()
    }

    @inlinable
    func cancel(socket: SOCKET) {
        cancel(handle: HANDLE(bitPattern: UInt(socket)))
    }

    @inlinable
    func cancel(handle: HANDLE!) {
        let cancelled = CancelIoEx(handle, UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self))
        if cancelled { return }

        let errorCode = GetLastError()
        if errorCode == ERROR_NOT_FOUND || errorCode == ERROR_OPERATION_ABORTED { return }
    }
}

extension Eventloop {
    @inlinable
    func withContext(context: UnsafeMutablePointer<Context>, socket: SOCKET, skipSuccessCompletions: Bool, operation: (_ context: UnsafeMutablePointer<OVERLAPPED>) throws -> IOCompletionPort.SubmissionResult) async throws -> Eventloop.SubmissionResult {
        try Task.checkCancellation()
        let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
        let stateMachine = ContextStateMachine(context: context, skipSuccessCompletions: skipSuccessCompletions)

        // Throwing operation means that the IOCP submission failed
        let result: IOCompletionPort.SubmissionResult
        do {
            result = try operation(overlapped)
        } catch {
            context.cache()
            throw error
        }

        switch (result, skipSuccessCompletions) {
            case (.completed, true):
                stateMachine.completeSynchronously()
                return .synchronous
            default:
                return try await withTaskCancellationHandler(operation: {
                    try await stateMachine.enqueue()
                }, onCancel: { stateMachine.cancel(socket: socket) })
        }
    }

    @inlinable
    func withContext(context: UnsafeMutablePointer<Context>, handle: HANDLE, skipSuccessCompletions: Bool, operation: (_ context: UnsafeMutablePointer<OVERLAPPED>) throws -> IOCompletionPort.SubmissionResult) async throws -> Eventloop.SubmissionResult {
        nonisolated(unsafe) let handle = handle
        try Task.checkCancellation()
        let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
        let stateMachine = ContextStateMachine(context: context, skipSuccessCompletions: skipSuccessCompletions)

        // Throwing operation means that the IOCP submission failed
        let result: IOCompletionPort.SubmissionResult
        do {
            result = try operation(overlapped)
        } catch {
            context.cache()
            throw error
        }

        switch (result, skipSuccessCompletions) {
            case (.completed, true):
                stateMachine.completeSynchronously()
                return .synchronous
            default:
                return try await withTaskCancellationHandler(operation: {
                    try await stateMachine.enqueue()
                }, onCancel: { stateMachine.cancel(handle: handle) })
        }
    }
}
#endif