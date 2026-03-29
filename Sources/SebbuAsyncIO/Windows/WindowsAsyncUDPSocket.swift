#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncUDPSocket: @unchecked Sendable {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    let skipSuccessCompletions: Bool

    @usableFromInline
    var wsaBufCache: PointerCache<WSABUF> = PointerCache(capacity: 2048)

    @inlinable
    init(socket: SOCKET, skipSuccessCompletions: Bool) {
        self.socket = socket
        self.skipSuccessCompletions = skipSuccessCompletions
    }

    @inlinable
    public static func bind(to: Endpoint) async throws -> WindowsAsyncUDPSocket {
        let clientSocket = WSASocketW(to.family == .IPv4 ? AF_INET : AF_INET6, SOCK_DGRAM, IPPROTO_UDP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let bindResult = to.withSockAddrPointer { addr, len in 
            WinSDK.bind(clientSocket, addr, len)
        }
        if bindResult == SOCKET_ERROR {
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        try Eventloop.shared.associate(clientSocket)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(clientSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncUDPSocket(socket: clientSocket, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer, to: Endpoint) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        _buffer.pointee.buf = .init(mutating: bytes.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(bytes.count)
        var bytesSent: UInt32 = 0
        let result = try await Eventloop.shared.send(socket: socket, buffer: _buffer, bytesSent: &bytesSent, address: to, skipSuccessCompletions: skipSuccessCompletions)
        return switch result {
            case .synchronous: Int(bytesSent)
            case .completion(let completion): completion.bytes
        }
    }

    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer, from: inout Endpoint) async throws -> Int {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        _buffer.pointee.buf = .init(into.baseAddress?.assumingMemoryBound(to: CHAR.self))
        _buffer.pointee.len = UInt32(into.count)
        var bytesReceived: UInt32 = 0
        let result = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, bytesReceived: &bytesReceived, from: &from, skipSuccessCompletions: skipSuccessCompletions)
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