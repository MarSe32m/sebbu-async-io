#if os(Windows)
import SebbuTSDS
import Synchronization

@usableFromInline
internal final class ContextAllocator: Sendable {
    @usableFromInline
    let contextCache: MPSCQueue<UnsafeMutablePointer<Context>>

    @usableFromInline
    let count: Atomic<Int> = .init(0)

    @usableFromInline
    let cacheSize: Int

    @usableFromInline
    let mutex: Mutex<Void> = .init(())

    @inlinable
    init(cacheSize: Int) {
        self.cacheSize = cacheSize
        self.contextCache = MPSCQueue(cacheSize: cacheSize)
    }

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

    @inlinable
    nonisolated internal func pop() -> sending UnsafeMutablePointer<Context> {
        do {
            mutex._unsafeLock(); defer { mutex._unsafeUnlock() }
            if let context = contextCache.dequeue() {
                count.wrappingSubtract(1, ordering: .relaxed)
                return context
            }
        }
        let context = UnsafeMutablePointer<Context>.allocate(capacity: 1)
        context.initialize(to: Context { @Sendable in
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
#endif