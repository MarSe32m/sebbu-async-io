#if os(Windows)
import WinSDK
import SebbuIOCP

@usableFromInline
internal final class WindowsAsyncUDPSocket: @unchecked Sendable {
    @usableFromInline
    let socket: SOCKET

    @usableFromInline
    var wsaBufCache: PointerCache<WSABUF> = PointerCache(capacity: 2048)

    @inlinable
    init(socket: SOCKET) {
        self.socket = socket
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
        return WindowsAsyncUDPSocket(socket: clientSocket)
    }

    @inlinable
    public func send(_ data: [UInt8], to: Endpoint) async throws {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        data.withUnsafeBytes { buffer in 
            _buffer.pointee.buf = .init(mutating: buffer.baseAddress?.assumingMemoryBound(to: CHAR.self))
            _buffer.pointee.len = UInt32(buffer.count)
        }
        let _ = try await Eventloop.shared.send(socket: socket, buffer: _buffer, address: to)
    }

    @inlinable
    public func receive(from: inout Endpoint) async throws -> [UInt8] {
        let _buffer = wsaBufCache.allocateUninitialized()
        defer { wsaBufCache.deallocateAndDeinitialize(_buffer) }
        _buffer.initialize(to: WSABUF())
        var data: [UInt8] = .init(repeating: 0, count: 1500)
        data.withUnsafeMutableBytes { buffer in 
            _buffer.pointee.buf = .init(buffer.baseAddress?.assumingMemoryBound(to: CHAR.self))
            _buffer.pointee.len = UInt32(buffer.count)
        }
        let completion = try await Eventloop.shared.receive(socket: socket, buffer: _buffer, from: &from)
        data.removeLast(data.count - completion.bytes)
        return data
    }

    @inlinable
    public consuming func close() throws {
        closesocket(socket)
    }
}
#endif