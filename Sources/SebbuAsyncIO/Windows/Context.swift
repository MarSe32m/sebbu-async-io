#if os(Windows)
@preconcurrency import WinSDK
import SebbuIOCP
import Synchronization

//FIXME: Define this in a C module
@usableFromInline
@frozen
internal struct Context: ~Copyable, Sendable {
    @usableFromInline
    var overlapped: OVERLAPPED

    @usableFromInline
    enum State: UInt, AtomicRepresentable, Sendable {
        case start
        case dequeued
        case continuationSupplied
        case finishedSynchronously
    }

    @usableFromInline
    enum Error: Swift.Error {
        case iocp(IOCompletionPort.IOCPError)
        case cancellation

        @usableFromInline
        var underlyingError: any Swift.Error {
            switch self {
                case .iocp(let err): err
                case .cancellation: _Concurrency.CancellationError()
            }
        }
    }

    @usableFromInline
    var continuation: UnsafeContinuation<Eventloop.Completion, any Swift.Error>? = nil

    @usableFromInline
    var completion: Eventloop.Completion = Eventloop.Completion()
    
    @usableFromInline
    var error: Error? = nil

    @usableFromInline
    let state: Atomic<State>

    @usableFromInline
    nonisolated(unsafe) let deallocator: (consuming sending UnsafeMutablePointer<Context>) -> Void

    @inlinable
    public init(_ deallocator: @escaping ((consuming sending UnsafeMutablePointer<Context>) -> Void)) {
        self.overlapped = OVERLAPPED()
        self.state = .init(.start)
        self.deallocator = deallocator
    }

    @inlinable
    public mutating func reset() {
        self.overlapped = OVERLAPPED()
        self.state.store(.start, ordering: .relaxed)
        self.error = nil
        self.completion = Eventloop.Completion()
        self.continuation = nil
    }
}

internal extension UnsafeMutablePointer<Context> {
    @inline(always)
    @inlinable
    func cache() {
        nonisolated(unsafe) let _self = self
        pointee.deallocator(_self)
    }
}
#endif