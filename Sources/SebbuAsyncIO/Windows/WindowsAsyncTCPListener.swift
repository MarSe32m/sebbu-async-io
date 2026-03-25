#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncTCPListener: Sendable {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    let listenAddress: Endpoint

    @usableFromInline
    let skipSuccessCompletions: Bool

    @usableFromInline
    nonisolated(unsafe) var bufferCache: RawBufferPointerCache

    @usableFromInline
    let contextAllocator: ContextAllocator = ContextAllocator(cacheSize: 128)

    @inlinable
    init(socket: SOCKET, address: Endpoint, skipSuccessCompletions: Bool) {
        self.socket = socket
        self.listenAddress = address
        self.skipSuccessCompletions = skipSuccessCompletions
        self.bufferCache = .init(capacity: 128, bufferSize: (MemoryLayout<sockaddr_storage>.size + 16) * 2)
    }

    @inlinable
    public static func listen(on: Endpoint, backlog: Int) async throws -> WindowsAsyncTCPListener {
        let listenSocket = WSASocketW(on.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let res = withUnsafePointer(to: on.storage) { ptr in 
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in 
                bind(listenSocket, addr, Int32(on.storageLength))
            }
        }
        if res == SOCKET_ERROR { throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError()) }
        if WinSDK.listen(listenSocket, Int32(backlog)) == SOCKET_ERROR { 
            closesocket(listenSocket)
            throw IOCompletionPort.IOCPError.wsaError(WSAGetLastError())
        }
        try Eventloop.shared.associate(listenSocket)
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(listenSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncTCPListener(socket: listenSocket, address: on, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public func accept() async throws -> WindowsAsyncTCPStream {
        let context = contextAllocator.pop()
        let acceptSocket = WSASocketW(listenAddress.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, IPPROTO_TCP.rawValue, nil, 0, DWORD(WSA_FLAG_OVERLAPPED))
        let buffer = bufferCache.pop()
        defer { bufferCache.push(buffer) }
        let _ = try await Eventloop.shared.accept(context: context, listenSocket: socket, acceptSocket: acceptSocket, addressBuffer: buffer, skipSuccessCompletions: skipSuccessCompletions)
        do {
            try Eventloop.shared.finishAccept(listenSocket: socket, acceptSocket: acceptSocket)
        } catch {
            print("Accept error")
            closesocket(acceptSocket)
            throw error
        }
        let skipSuccessCompletions = SetFileCompletionNotificationModes(HANDLE(bitPattern: UInt(acceptSocket)), UCHAR(FILE_SKIP_COMPLETION_PORT_ON_SUCCESS))
        return WindowsAsyncTCPStream(socket: acceptSocket, skipSuccessCompletions: skipSuccessCompletions)
    }

    @inlinable
    public consuming func close() throws {
        closesocket(socket)
    }
    
    deinit {
        print("Listener closed")
        try? close()
        contextAllocator.clear()
    }
}
#endif