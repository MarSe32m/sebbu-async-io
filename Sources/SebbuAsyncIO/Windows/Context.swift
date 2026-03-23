#if os(Windows)
import WinSDK
import SebbuIOCP
import Synchronization

//FIXME: Define this in a C module
@usableFromInline
internal struct Context: ~Copyable {
    @usableFromInline
    var overlapped: OVERLAPPED

    @usableFromInline
    enum State: UInt, AtomicRepresentable {
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
    var continuation: UnsafeContinuation<Eventloop.Completion, any Swift.Error>

    @usableFromInline
    var completion: Eventloop.Completion = Eventloop.Completion()
    
    @usableFromInline
    var error: Error? = nil

    @usableFromInline
    let state: Atomic<State>

    public init() {
        self.overlapped = OVERLAPPED()
        self.continuation = unsafeBitCast(Int(0), to: UnsafeContinuation<Eventloop.Completion, any Swift.Error>.self)
        self.state = .init(.start)
    }
}
#endif