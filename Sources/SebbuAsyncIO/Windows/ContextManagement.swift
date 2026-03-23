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
    func enqueue(eventloop: Eventloop) async throws -> Eventloop.SubmissionResult {
        let completion = try await withUnsafeThrowingContinuation { continuation in
            context.pointee.continuation = continuation
            let (exchanged, old) = context.pointee.state.compareExchange(expected: .start, desired: .continuationSupplied, ordering: .acquiringAndReleasing)
            if exchanged { return }
            assert(old == .dequeued, "Old state must have been dequeued!")
            defer { eventloop.deallocate(context: context) }
            if let error = context.pointee.error {
                continuation.resume(throwing: error.underlyingError)
            }
            continuation.resume(returning: context.pointee.completion)
        }
        return .completion(completion)
    }

    @inlinable
    func completeSynchronously(eventloop: Eventloop) {
        if skipSuccessCompletions {
            eventloop.deallocate(context: context)
            return
        }
        let (exchanged, old) = context.pointee.state.compareExchange(expected: .start, desired: .finishedSynchronously, ordering: .acquiringAndReleasing)
        if exchanged { return }
        assert(old == .dequeued, "Old state must be dequeued here!")
        eventloop.deallocate(context: context)
    }

    @inlinable
    func cancel(socket: SOCKET) {
        cancel(handle: HANDLE(bitPattern: UInt(socket)))
    }

    @inlinable
    func cancel(handle: HANDLE!) {
        let cancelled = CancelIoEx(handle, UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self))
        if !cancelled {
            let errorCode = GetLastError()
            if errorCode == ERROR_NOT_FOUND {
                print("Context not found")
            }
            print("TODO: Handle failed cancellation: \(#file):\(#line)")
        }
    }
}

extension Eventloop {
    @inlinable
    func withContext(socket: SOCKET, skipSuccessCompletions: Bool, operation: (_ context: UnsafeMutablePointer<OVERLAPPED>) throws -> IOCompletionPort.SubmissionResult) async throws -> Eventloop.SubmissionResult {
        try Task.checkCancellation()
        let context = allocateContext()
        let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
        let stateMachine = ContextStateMachine(context: context, skipSuccessCompletions: skipSuccessCompletions)
        // Throwing operation means that the IOCP submission failed
        let result: IOCompletionPort.SubmissionResult
        do {
            result = try operation(overlapped)
        } catch {
            deallocate(context: context)
            throw error
        }
        switch result {
        case .completed:
            stateMachine.completeSynchronously(eventloop: self)
            return .synchronous
        case .enqueued:
            return try await withTaskCancellationHandler(operation: {
                try await stateMachine.enqueue(eventloop: self)
            }, onCancel: { stateMachine.cancel(socket: socket) })
        }
    }

    @inlinable
    func withContext(handle: HANDLE, skipSuccessCompletions: Bool, operation: (_ context: UnsafeMutablePointer<OVERLAPPED>) throws -> IOCompletionPort.SubmissionResult) async throws -> Eventloop.SubmissionResult {
        nonisolated(unsafe) let handle = handle
        try Task.checkCancellation()
        let context = allocateContext()
        let overlapped = UnsafeMutableRawPointer(context).assumingMemoryBound(to: OVERLAPPED.self)
        let stateMachine = ContextStateMachine(context: context, skipSuccessCompletions: skipSuccessCompletions)
        // Throwing operation means that the IOCP submission failed
        let result: IOCompletionPort.SubmissionResult
        do {
            result = try operation(overlapped)
        } catch {
            deallocate(context: context)
            throw error
        }
        switch result {
        case .completed:
            stateMachine.completeSynchronously(eventloop: self)
            return .synchronous
        case .enqueued:
            return try await withTaskCancellationHandler(operation: {
                try await stateMachine.enqueue(eventloop: self)
            }, onCancel: { stateMachine.cancel(handle: handle) })
        }
    }
}
#endif