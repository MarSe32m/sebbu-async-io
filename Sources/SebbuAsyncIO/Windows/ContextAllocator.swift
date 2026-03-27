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

@used
@c
private func flsCleanup(_ raw: UnsafeMutableRawPointer?) {
    guard let raw else { return }
    let allocator = Unmanaged<ContextAllocator>.fromOpaque(raw).takeUnretainedValue()
    ThreadLocalContextAllocator.cache(allocator)
}

@usableFromInline
internal enum ThreadLocalContextAllocator {
    // We use a very big size here to ensure no allocator is dropped
    @usableFromInline
    static let cachedAllocators: LockedQueue<ContextAllocator> = .init()

    @inlinable
    static func createAllocator() -> ContextAllocator {
        if let allocator = cachedAllocators.dequeue() {
            return allocator
        }
        //TODO: This cache size should be configurable somehow
        let allocator = ContextAllocator(cacheSize: 2048)
        // Retain the allocator with immortal +1
        let _ = Unmanaged.passRetained(allocator)
        return allocator
    }

    @inlinable
    static func cache(_ allocator: ContextAllocator) {
        let enqueued = cachedAllocators.enqueue(allocator) == nil
        precondition(enqueued, "Failed to cache a context allocator")
    }

    @usableFromInline
    static let flsIndex: DWORD = {
        let idx = FlsAlloc(flsCleanup(_:))
        precondition(idx != FLS_OUT_OF_INDEXES, "FlsAlloc failed")
        return idx
    }()

    @inlinable
    static var current: ContextAllocator {
        let idx = flsIndex
        if let raw = FlsGetValue(idx) {
            return Unmanaged<ContextAllocator>.fromOpaque(raw).takeUnretainedValue()
        }
        let allocator = createAllocator()
        let raw = Unmanaged.passUnretained(allocator).toOpaque()
        let ok = FlsSetValue(idx, raw)
        precondition(ok, "FlsSetValue failed")
        return allocator
    }

    @inlinable
    @inline(always)
    static func allocate() -> UnsafeMutablePointer<Context> {
        current.pop()
    }
}
#endif