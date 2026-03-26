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
        guard clientSocket != INVALID_SOCKET else {
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        
        let bindAddress = to.family == .IPv4 ? Endpoint.anyIPv4(port: 0) : Endpoint.anyIPv6(port: 0)
        let bindResult = bindAddress.withSockAddrPointer { addr, len in 
            bind(clientSocket, addr, len)
        }
        if bindResult == SOCKET_ERROR {
            closesocket(clientSocket)
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        
        try Eventloop.shared.associate(clientSocket)
        let destination = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        destination.initialize(to: to.storage.storage.pointee)
        defer { destination.deallocate() }
        
        do {
            let _ = try await Eventloop.shared.connect(socket: clientSocket, destination: destination, destinationLength: Int(to.storage.length.pointee), skipSuccessCompletions: false)
            try Eventloop.shared.finishConnect(socket: clientSocket)
        } catch {
            closesocket(clientSocket)
            throw error
        }
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(clientSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncTCPStream(socket: clientSocket, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        
        let buffer = IOBuffer(copying: data)
        var bytesSent = 0
        while bytesSent < data.count {
            let chunkCount = Swift.min(data.count - bytesSent, Int(UInt32.max))
            let bufferSlice = buffer.bytes(offset: bytesSent, count: chunkCount)
            _buffer.pointee.buf = .init(mutating: bufferSlice.baseAddress?.assumingMemoryBound(to: CHAR.self))
            _buffer.pointee.len = UInt32(bufferSlice.count)
            var submittedBytes: UInt32 = 0
            let result = try await Eventloop.shared.send(socket: socket, buffer: _buffer, bytesSent: &submittedBytes, skipSuccessCompletions: skipSuccessCompletions)
            let sentThisIteration = switch result {
                case .synchronous: Int(submittedBytes)
                case .completion(let completion): completion.bytes
            }
            if sentThisIteration == 0 {
                throw IOCompletionPort.IOCPError.wsaError(WSAECONNRESET)
            }
            bytesSent += sentThisIteration
        }
    }

    @inlinable
    public func receive(atLeast: Int = 1, atMost: Int) async throws -> [UInt8] {
        precondition(atLeast <= atMost, "atLeast must be less than or equal to atMost")
        precondition(atLeast >= 0, "atLeast must be positive")
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())

        let buffer = IOBuffer(byteCount: Swift.min(atMost, Int(UInt32.max)))
        var bytesReceived: Int = 0
        while bytesReceived < atLeast {
            let bufferSlice = buffer.bytes(offset: bytesReceived, count: buffer.capacity - bytesReceived)
            _buffer.pointee.buf = .init(mutating: bufferSlice.baseAddress?.assumingMemoryBound(to: CHAR.self))
            _buffer.pointee.len = UInt32(bufferSlice.count)
            var submittedBytes: UInt32 = 0
            let result = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, bytesReceived: &submittedBytes, skipSuccessCompletions: skipSuccessCompletions)
            let receivedThisIteration = switch result {
                case .synchronous: Int(submittedBytes)
                case .completion(let completion): completion.bytes
            }
            if receivedThisIteration == 0 { break }
            bytesReceived += receivedThisIteration
        }
        return buffer.toArray(count: bytesReceived)
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

    deinit {
        try? close()
    }
}
#endif