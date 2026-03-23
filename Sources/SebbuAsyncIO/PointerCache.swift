import Synchronization
import BasicContainers
import DequeModule

@usableFromInline
struct PointerCache<T: ~Copyable>: @unchecked Sendable, ~Copyable {
    @usableFromInline
    let mutex: Mutex<Void> = Mutex(())

    @usableFromInline
    var cache: Cache<UnsafeMutablePointer<T>>

    init(capacity: Int) {
        cache = .init(capacity: capacity)
    }

    @inlinable
    mutating func allocateUninitialized() -> UnsafeMutablePointer<T> {
        mutex._unsafeLock(); defer { mutex._unsafeUnlock() }
        if let pointer = cache.pop() { return pointer }
        return .allocate(capacity: 1)
    }

    @inlinable
    mutating func deallocateAndDeinitialize(_ pointer: UnsafeMutablePointer<T>) {
        pointer.deinitialize(count: 1)
        mutex._unsafeLock(); defer { mutex._unsafeUnlock() }
        if let pointer = cache.push(pointer) {
            pointer.deallocate()
        }
    }

    @inlinable
    deinit {
        mutex.withLock { _ in 
            cache.deallocatePointers()
        }
    }
}

@usableFromInline
struct RawBufferPointerCache: @unchecked Sendable, ~Copyable {
    @usableFromInline
    let mutex: Mutex<Void> = Mutex(())

    @usableFromInline
    var cache: RigidArray<UnsafeMutableRawBufferPointer>

    @usableFromInline
    let bufferSize: Int

    @inlinable
    init(capacity: Int, bufferSize: Int) {
        cache = .init(capacity: capacity)
        self.bufferSize = bufferSize
    }

    @inlinable
    mutating func pop() -> UnsafeMutableRawBufferPointer {
        mutex._unsafeLock(); defer { mutex._unsafeUnlock() }
        return cache.popLast() ?? .allocate(byteCount: bufferSize, alignment: 1)
    }

    @inlinable
    mutating func push(_ buffer: UnsafeMutableRawBufferPointer) {
        mutex._unsafeLock(); defer { mutex._unsafeUnlock() }
        if cache.isFull { buffer.deallocate() }
        else { cache.append(buffer) }
    }

    @inlinable
    deinit {
        mutex.withLock { _ in 
            for i in cache.indices {
                cache[i].deallocate()
            }
        }
    }
}

@usableFromInline
struct Cache<T: ~Copyable>: @unchecked Sendable, ~Copyable {
    @usableFromInline
    let mutex: Mutex<Void> = Mutex(())

    @usableFromInline
    var cache: RigidDeque<T>

    init(capacity: Int) {
        cache = .init(capacity: capacity)
    }

    @inlinable
    mutating func push(_ element: consuming T) -> T? {
        if cache.isFull { return element }
        cache.append(element)
        return nil
    }

    @inlinable
    mutating func pop() -> T? {
        cache.popFirst()
    }

    @inlinable
    func deallocatePointers<S: ~Copyable>() where T == UnsafeMutablePointer<S> {
        for i in cache.indices {
            cache[i].deallocate()
        }
    } 
}