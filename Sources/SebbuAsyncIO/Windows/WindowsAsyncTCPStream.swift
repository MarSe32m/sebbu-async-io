#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncTCPStream: @unchecked Sendable {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    let skipSuccessCompletions: Bool

    @usableFromInline
    var wsaBufCache: PointerCache<WSABUF> = PointerCache(capacity: 128)

    @usableFromInline
    init(socket: SOCKET, skipSuccessCompletions: Bool) {
        self.socket = socket
        self.skipSuccessCompletions = skipSuccessCompletions
    }

    @inlinable
    public static func connect(to: Endpoint) async throws -> WindowsAsyncTCPStream {
        let clientSocket = WSASocketW(to.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let _bindAddress = to.family == .IPv4 ? Endpoint.anyIPv4(port: 0) : Endpoint.anyIPv6(port: 0)
        let bindResult = _bindAddress.withSockAddrPointer { addr, len in 
            bind(clientSocket, addr, len)
        }
        if bindResult == SOCKET_ERROR {
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        try Eventloop.shared.associate(clientSocket)
        let destination = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        destination.initialize(to: to.storage)
        defer { destination.deallocate() }
        let _ = try await Eventloop.shared.connect(socket: clientSocket, destination: destination, destinationLength: Int(to.storageLength), skipSuccessCompletions: false)
        try Eventloop.shared.finishConnect(socket: clientSocket)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(clientSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncTCPStream(socket: clientSocket, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        var bytesSent = 0
        while bytesSent < data.count {
            data.withUnsafeBytes { buffer in 
                _buffer.pointee.buf = .init(mutating: buffer.baseAddress?.advanced(by: bytesSent).assumingMemoryBound(to: CHAR.self))
                _buffer.pointee.len = UInt32(buffer.count - bytesSent)
            }
            var _bytesSent: UInt32 = 0
            let result = try await Eventloop.shared.send(socket: socket, buffer: _buffer, bytesSent: &_bytesSent, skipSuccessCompletions: skipSuccessCompletions)
            switch result {
                case .synchronous: bytesSent += Int(_bytesSent)
                case .completion(let completion): 
                    bytesSent += completion.bytes
            }
        }
        if bytesSent < data.count { print("Send failure?") }
    }

    @inlinable
    public func receive(atLeast: Int = 1, atMost: Int) async throws -> [UInt8] {
        precondition(atLeast <= atMost, "atLeast must be less than or equal to atMost")
        precondition(atLeast >= 0, "atLeast must be positive")
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        var bytesReceived: Int = 0
        var data: [UInt8] = .init(repeating: 0, count: Swift.min(atMost, 1 << 32 - 1))
        outer: while bytesReceived < atLeast {
            data.withUnsafeMutableBytes { buffer in 
                _buffer.pointee.buf = .init(buffer.baseAddress?.advanced(by: bytesReceived).assumingMemoryBound(to: CHAR.self))
                _buffer.pointee.len = UInt32(buffer.count - bytesReceived)
            }
            var _bytesReceived: UInt32 = 0
            let result = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, bytesReceived: &_bytesReceived, skipSuccessCompletions: skipSuccessCompletions)
            switch result {
                case .synchronous: 
                    bytesReceived += Int(_bytesReceived)
                    if _bytesReceived == 0 { break outer }
                case .completion(let completion): 
                    bytesReceived += completion.bytes
                    if completion.bytes == 0 { break outer }
            }
        }
        data.removeLast(data.count - bytesReceived)
        if data.count < atLeast { print("Receive failure?") }
        return data
    }

    @inline(always)
    public func receive(exactly: Int, wait: Bool = false) async throws -> [UInt8] {
        try await receive(atLeast: exactly, atMost: exactly)
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        let _ = try await Eventloop.shared.transmitFile(socket: socket, file: file.implementation.handle, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public consuming func close() throws {
        closesocket(socket)
    }
}
#endif