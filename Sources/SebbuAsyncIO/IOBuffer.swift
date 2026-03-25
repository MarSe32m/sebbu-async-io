public struct IOBuffer: ~Copyable {
    @usableFromInline
    let storage: UnsafeMutableRawBufferPointer

    @usableFromInline
    let capacity: Int

    @inlinable
    init(byteCount: Int) {
        let byteCount = Swift.max(byteCount, 1)
        self.storage = .allocate(byteCount: byteCount, alignment: MemoryLayout<UInt8>.alignment)
        self.capacity = byteCount
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