#if os(Windows)
import WinSDK
import SebbuIOCP

//FIXME: Define this in a C module
@usableFromInline
internal struct Context {
    @usableFromInline
    var overlapped: OVERLAPPED
    @usableFromInline
    var continuation: UnsafeContinuation<Eventloop.Completion, any Error>

    public init() {
        self.overlapped = OVERLAPPED()
        self.continuation = unsafeBitCast(Int(0), to: UnsafeContinuation<Eventloop.Completion, any Error>.self)
    }
}

extension PointerCache<Context> {
    @inlinable
    mutating func allocate(continuation: UnsafeContinuation<Eventloop.Completion, any Error>) -> UnsafeMutablePointer<Context> {
        let pointer = allocateUninitialized()
        var context = Context()
        context.continuation = continuation
        pointer.initialize(to: context)
        return pointer
    }

    @inlinable 
    mutating func allocate() -> UnsafeMutablePointer<Context> {
        let pointer = allocateUninitialized()
        pointer.initialize(to: Context())
        return pointer
    }
}
#endif