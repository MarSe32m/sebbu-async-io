#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncTCPListener: AsyncTCPListenerProtocol {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    let family: Endpoint.Family

    @usableFromInline
    let skipSuccessCompletions: Bool

    @usableFromInline
    nonisolated(unsafe) var bufferCache: RawBufferPointerCache

    @inlinable
    init(socket: SOCKET, family: Endpoint.Family, skipSuccessCompletions: Bool) {
        self.socket = socket
        self.family = family
        self.skipSuccessCompletions = skipSuccessCompletions
        self.bufferCache = .init(capacity: 128, bufferSize: (MemoryLayout<sockaddr_storage>.size + 16) * 2)
    }

    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> WindowsAsyncTCPListener {
        let listenSocket = WSASocketW(on.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let res = on.withSockAddrPointer { addr, len in 
            bind(listenSocket, addr, len)
        }
        if res == SOCKET_ERROR { throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError()) }
        if WinSDK.listen(listenSocket, Int32(backlog)) == SOCKET_ERROR { 
            closesocket(listenSocket)
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        try Eventloop.shared.associate(listenSocket)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(listenSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncTCPListener(socket: listenSocket, family: on.family, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func accept() async throws -> AsyncTCPStream {
        let acceptSocket = WSASocketW(family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let buffer = bufferCache.pop()
        defer { bufferCache.push(buffer) }
        let _ = try await Eventloop.shared.accept(listenSocket: socket, acceptSocket: acceptSocket, addressBuffer: buffer, skipSuccessCompletions: skipSuccessCompletions)
        do {
            try Eventloop.shared.finishAccept(listenSocket: socket, acceptSocket: acceptSocket)
        } catch {
            closesocket(acceptSocket)
            throw error
        }
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(acceptSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        let implementation = WindowsAsyncTCPStream(socket: acceptSocket, skipSuccessCompletions: skipSuccessCompletions)
        return AsyncTCPStream(implementation: implementation)
    }

    @inlinable
    public consuming func close() async throws {
        closesocket(socket)
    }
    
    @inlinable
    deinit {
        closesocket(socket)
    }
}
#endif