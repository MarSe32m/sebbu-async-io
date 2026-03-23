#if os(Windows)
extension PointerCache<Context> {
    @inlinable 
    mutating func allocate() -> UnsafeMutablePointer<Context> {
        let pointer = allocateUninitialized()
        pointer.initialize(to: Context())
        return pointer
    }
}
#endif