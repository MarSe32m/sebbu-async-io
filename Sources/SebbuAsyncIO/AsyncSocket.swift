public final class AsyncTCPStream: Sendable {
    #if os(Windows)
    @usableFromInline
    internal typealias Implementation = WindowsAsyncTCPStream
    #elseif os(Linux)
    internal typealias Implementation = LinuxAsyncTCPStream
    #elseif canImport(Darwin)
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

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        try await implementation.send(data)
    }

    @inlinable
    public func receive(atLeast: Int = 1, atMost: Int) async throws -> [UInt8] {
        try await implementation.receive(atLeast: atLeast, atMost: atMost)
    }

    @inline(always)
    public func receive(exactly: Int) async throws -> [UInt8] {
        try await receive(atLeast: exactly, atMost: exactly)
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
    internal typealias Implementation = LinuxAsyncTCPListener
    #elseif canImport(Darwin)
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
    internal typealias Implementation = LinuxAsyncUDPSocket
    #elseif canImport(Darwin)
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

    @inlinable
    public func send(_ data: [UInt8], to: Endpoint) async throws {
        try await implementation.send(data, to: to)
    }

    @inlinable
    public func receive(from: inout Endpoint) async throws -> [UInt8] {
        try await implementation.receive(from: &from)
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
    internal typealias Implementation = LinuxAsyncUDPClient
    #elseif canImport(Darwin)
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

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        try await implementation.send(data)
    }

    @inlinable
    public func receive() async throws -> [UInt8] {
        try await implementation.receive()
    }

    @inlinable
    public consuming func close() throws {
        try implementation.close()
    }
}