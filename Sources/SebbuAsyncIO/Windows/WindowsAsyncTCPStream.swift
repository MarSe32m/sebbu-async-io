#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncTCPStream: @unchecked Sendable, AsyncTCPStreamProtocol {
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
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())

        let chunkSize = Swift.min(bytes.count, Int(UInt32.max))
        _buffer.pointee.buf = .init(mutating: bytes.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(chunkSize)
        var submittedBytes: UInt32 = 0
        let result = try await Eventloop.shared.send(socket: socket, buffer: _buffer, bytesSent: &submittedBytes, skipSuccessCompletions: skipSuccessCompletions)
        let bytesSent = switch result {
            case .synchronous: Int(submittedBytes)
            case .completion(let completion): completion.bytes
        }
        return bytesSent
    }

    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())

        let bufferSize = Swift.min(into.count, Int(UInt32.max))
        _buffer.pointee.buf = .init(mutating: into.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(bufferSize)
        var submittedBytes: UInt32 = 0
        let result = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, bytesReceived: &submittedBytes, skipSuccessCompletions: skipSuccessCompletions)
        let bytesReceived = switch result {
            case .synchronous: Int(submittedBytes)
            case .completion(let completion): completion.bytes
        }
        return bytesReceived
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