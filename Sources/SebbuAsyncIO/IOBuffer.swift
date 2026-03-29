public struct IOBuffer: ~Copyable {
    @usableFromInline
    let storage: UnsafeMutableRawBufferPointer

    @usableFromInline
    let capacity: Int

    @inlinable
    @inline(always)
    public subscript(_ index: Int) -> UInt8 {
        @_transparent
        unsafeAddress {
            precondition(index >= 0 && index < capacity, "Index out of range")
            return UnsafePointer(storage.baseAddress!.advanced(by: index).assumingMemoryBound(to: UInt8.self))
        }
        @_transparent
        unsafeMutableAddress {
            precondition(index >= 0 && index < capacity, "Index out of range")
            return storage.baseAddress!.advanced(by: index).assumingMemoryBound(to: UInt8.self)
            
        }
    }
    
    @inlinable
    @inline(always)
    public subscript(unchecked index: Int) -> UInt8 {
        @_transparent
        unsafeAddress {
            UnsafePointer(storage.baseAddress!.advanced(by: index).assumingMemoryBound(to: UInt8.self))
        }
        @_transparent
        unsafeMutableAddress {
            storage.baseAddress!.advanced(by: index).assumingMemoryBound(to: UInt8.self)
        }
    }
    
    @inlinable
    public init(capacity: Int) {
        let byteCount = Swift.max(capacity, 1)
        self.storage = .allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
        self.capacity = byteCount
    }
    
    @inlinable
    init(byteCount: Int) {
        self.init(capacity: byteCount)
    }

    @inlinable
    init(copying data: [UInt8]) {
        self.init(byteCount: data.count)
        if data.isEmpty { return }
        data.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress, let destinationBase = storage.baseAddress else { return }
            destinationBase.copyMemory(from: sourceBase, byteCount: data.count)
        }
    }

    @inlinable
    var baseAddress: UnsafeMutableRawPointer? {
        storage.baseAddress
    }

    @inlinable
    func bytes(offset: Int = 0, count: Int? = nil) -> UnsafeMutableRawBufferPointer {
        precondition(offset >= 0 && offset <= capacity, "offset must stay within the allocated buffer")
        let requestedCount = count ?? Swift.max(capacity - offset, 0)
        precondition(requestedCount >= 0 && requestedCount <= capacity - offset, "requested byte range must stay within the allocated buffer")
        return UnsafeMutableRawBufferPointer(
            start: storage.baseAddress?.advanced(by: offset),
            count: requestedCount
        )
    }

    @inlinable
    func toArray(count: Int) -> [UInt8] {
        guard count > 0, let baseAddress = storage.baseAddress else { return [] }
        return Array(UnsafeBufferPointer(start: baseAddress.assumingMemoryBound(to: UInt8.self), count: count))
    }

    @inlinable
    deinit {
        storage.deallocate()
    }
}
