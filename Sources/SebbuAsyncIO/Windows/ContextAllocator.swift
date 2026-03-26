#if os(Windows)
import SebbuTSDS
import Synchronization
import WinSDK

@usableFromInline
internal final class ContextAllocator: Sendable {
    @usableFromInline
    let contextCache: MPSCQueue<UnsafeMutablePointer<Context>>

    @usableFromInline
    let count: Atomic<Int> = .init(0)

    @usableFromInline
    let cacheSize: Int

    @inlinable
    init(cacheSize: Int) {
        self.cacheSize = cacheSize
        self.contextCache = MPSCQueue(cacheSize: cacheSize)
    }

    // This may be called from any number of threads simultaneously
    @inlinable
    nonisolated internal func push(_ context: consuming sending UnsafeMutablePointer<Context>) {
        context.pointee.reset()
        if count.wrappingAdd(1, ordering: .relaxed).newValue > cacheSize {
            count.wrappingSubtract(1, ordering: .relaxed)
            context.deinitialize(count: 1)
            context.deallocate()
        } else {
            let _ = contextCache.enqueue(context)
        }
    }

    // Note this is safe to call only from a single thread at a time. 
    // Thus is to be used only in thread local contexts
    @inlinable
    nonisolated internal func pop() -> sending UnsafeMutablePointer<Context> {
        if let context = contextCache.dequeue() {
            count.wrappingSubtract(1, ordering: .relaxed)
            return context
        }
        let context = UnsafeMutablePointer<Context>.allocate(capacity: 1)
        context.initialize(to: Context { [unowned(unsafe) self] in
            self.push($0)
        })
        return context
    }

    @inlinable
    nonisolated internal func clear() {
        while let pointer = contextCache.dequeue() {
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
    }
}

@usableFromInline
internal enum ThreadLocalContextAllocator {
    @usableFromInline
    typealias TlsGetValueFn = @convention(c) (DWORD) -> UnsafeMutableRawPointer?

    @usableFromInline
    static let tlsGetValue: TlsGetValueFn = {
        guard let kernel32 = "kernel32.dll".withCString({ GetModuleHandleA($0) }) else {
            return TlsGetValue(_:)
        }
        guard let symbol = "TlsGetValue2".withCString({ GetProcAddress(kernel32, $0) }) else {
            return TlsGetValue(_:)
        }
        print("Using tlsgetvalue2")
        // We use TlsGetValue2 if available because its a bit more performant 8)
        return unsafeBitCast(symbol, to: TlsGetValueFn.self)
    }()

    @usableFromInline
    static let tlsIndex: DWORD = {
        let idx = TlsAlloc()
        precondition(idx != TLS_OUT_OF_INDEXES, "TlsAlloc failed")
        return idx
    }()

    @inlinable
    static var current: ContextAllocator {
        let idx = tlsIndex
        if let raw = tlsGetValue(idx) {
            return Unmanaged<ContextAllocator>.fromOpaque(raw).takeUnretainedValue()
        }
        //TODO: This cache size should be configurable somehow
        let pool = ContextAllocator(cacheSize: 65536)
        let raw = Unmanaged.passRetained(pool).toOpaque()
        let ok = TlsSetValue(idx, raw)
        precondition(ok, "TlsSetValue failed")
        return pool
    }

    @inlinable
    @inline(always)
    static func allocate() -> UnsafeMutablePointer<Context> {
        current.pop()
    }
}
#endif