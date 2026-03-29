public final class AsyncTCPStream: Sendable {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncTCPStream
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncTCPStream
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncTCPStream
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }

    @inlinable
    public static func connect(to: Endpoint) async throws -> AsyncTCPStream {
        let stream = try await Implementation.connect(to: to)
        return AsyncTCPStream(implementation: stream)
    }

    //TODO: We need a RawSpan version of this
    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await implementation.send(bytes)
    }

    @inlinable
    public func sendAll(_ bytes: UnsafeRawBufferPointer) async throws {
        var bytesSent = 0
        while bytesSent < bytes.count {
            let buffer = UnsafeRawBufferPointer(start: bytes.baseAddress?.advanced(by: bytesSent), count: bytes.count - bytesSent)
            bytesSent += try await send(buffer)
        }
    }

    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await implementation.receive(into: into)
    }

    @inline(always)
    public func receive(exactly: Int, into: UnsafeMutableRawBufferPointer) async throws {
        precondition(exactly <= into.count)
        var bytesReceived = 0
        while bytesReceived < exactly {
            let buffer = UnsafeMutableRawBufferPointer(start: into.baseAddress?.advanced(by: bytesReceived), count: exactly - bytesReceived)
            bytesReceived += try await receive(into: buffer)
        }
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        try await implementation.transmit(file: file)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}

public final class AsyncTCPListener: Sendable {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncTCPListener
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncTCPListener
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncTCPListener
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }

    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> AsyncTCPListener {
        let listener = try await Implementation.listen(on: on, backlog: backlog)
        return AsyncTCPListener(implementation: listener)
    }

    @inlinable
    public func accept() async throws -> AsyncTCPStream {
        let _stream = try await implementation.accept()
        return AsyncTCPStream(implementation: _stream)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}

public final class AsyncUDPSocket: Sendable {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncUDPSocket
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncUDPSocket
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncUDPSocket
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }

    @inlinable
    public static func bind(to: Endpoint) async throws -> AsyncUDPSocket {
        let implementation = try await Implementation.bind(to: to)
        return AsyncUDPSocket(implementation: implementation)
    }

    //TODO: We need an RawSpan version of this
    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int {
        try await implementation.send(bytes, to: to)
    }

    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int {
        try await implementation.receive(into: into, from: &from)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}

public final class AsyncUDPClient: Sendable {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncUDPClient
    #elseif os(Linux)
    @usableFromInline
    internal typealias Implementation = LinuxAsyncUDPClient
    #elseif canImport(Darwin)
    @usableFromInline
    internal typealias Implementation = DarwinAsyncUDPClient
    #else
    #error("Platform not supported")
    #endif

    @usableFromInline
    let implementation: Implementation

    @inlinable
    init(implementation: Implementation) {
        self.implementation = implementation
    }
    @inlinable
    public static func connect(to: Endpoint) async throws -> AsyncUDPClient {
        let client = try await Implementation.connect(to: to)
        return AsyncUDPClient(implementation: client)
    }

    //TODO: We need a RawSpan version of this
    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await implementation.send(bytes)
    }

    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await implementation.receive(into: into)
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}
