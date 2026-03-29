#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncUDPClient: @unchecked Sendable {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    let skipSuccessCompletions: Bool

    @usableFromInline
    var wsaBufCache: PointerCache<WSABUF> = PointerCache(capacity: 128)

    @inlinable
    init(socket: SOCKET, skipSuccessCompletions: Bool) {
        self.socket = socket
        self.skipSuccessCompletions = skipSuccessCompletions
    }

    @inlinable
    public static func connect(to: Endpoint) async throws -> WindowsAsyncUDPClient {
        let clientSocket = WSASocketW(to.family == .IPv4 ? AF_INET : AF_INET6, SOCK_DGRAM, IPPROTO_UDP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        guard clientSocket != INVALID_SOCKET else {
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        let bindAddress = to.family == .IPv4 ? Endpoint.anyIPv4(port: 0) : Endpoint.anyIPv6(port: 0)
        let bindResult = bindAddress.withSockAddrPointer { addr, len in 
            WinSDK.bind(clientSocket, addr, len)
        }
        if bindResult == SOCKET_ERROR {
            closesocket(clientSocket)
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        let connectResult = to.withSockAddrPointer { addr, len in 
            WinSDK.connect(clientSocket, addr, len)
        }
        if connectResult == SOCKET_ERROR {
            closesocket(clientSocket)
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        try Eventloop.shared.associate(clientSocket)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(clientSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncUDPClient(socket: clientSocket, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        _buffer.pointee.buf = .init(mutating: bytes.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(bytes.count)
        var bytesSent: UInt32 = 0
        let result = try await Eventloop.shared.send(socket: socket, buffer: _buffer, bytesSent: &bytesSent, skipSuccessCompletions: skipSuccessCompletions)
        return switch result {
            case .synchronous: Int(bytesSent)
            case .completion(let completion): completion.bytes
        }
    }

    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        _buffer.pointee.buf = .init(into.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(into.count)
        var bytesReceived: UInt32 = 0
        let result = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, bytesReceived: &bytesReceived, skipSuccessCompletions: skipSuccessCompletions)
        return switch result {
            case .synchronous: Int(bytesReceived)
            case .completion(let completion): completion.bytes
        }
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