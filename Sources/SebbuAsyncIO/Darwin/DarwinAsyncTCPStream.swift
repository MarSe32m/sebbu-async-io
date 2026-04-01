#if canImport(Darwin)
import Network
import Foundation
import Darwin

@usableFromInline
internal final class DarwinAsyncTCPStream: AsyncTCPStreamProtocol {
    
    @usableFromInline
    let connection: NetworkConnection<TCP>
    
    @inlinable
    init(connection: NetworkConnection<TCP>) {
        self.connection = connection
    }
    
    @inlinable
    public static func connect(to: Endpoint) async throws -> DarwinAsyncTCPStream {
        guard let endpoint = to.endpoint else {
            fatalError("TODO: Throw a proper error")
        }
        let connection = NetworkConnection(to: endpoint) {
            TCP()
        }
        // We take an establishment report so that we attempt the connection right away
        let _ = try await connection.establishmentReport()
        return DarwinAsyncTCPStream(connection: connection)
    }

    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await connection.send(bytes)
        return bytes.count
    }
    
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        let data = try await connection.receive(atMost: into.count).content
        return data.withUnsafeBytes { receivedBytes in
            into.copyMemory(from: receivedBytes)
            return receivedBytes.count
        }
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        /*
        DispatchQueue.global().async {
            var nBytes: off_t = 0
            let fd: CInt = 0
            let sock: CInt = 0
            let res = Darwin.sendfile(fd, sock, off_t(0), &nBytes, nil, 0)
        }
         */
        //TODO: Use sendfile in a separate threadpool
        let fileSize = try file.fileSize
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Swift.min(65536, fileSize), alignment: 1)
        defer { buffer.deallocate() }
        var offset: UInt = 0
        while Int(offset) < fileSize {
            let bytesRead = try await file.read(into: buffer, atAbsoluteOffset: offset)
            let sentBytes = try await send(buffer[0..<bytesRead])
            //TODO: We are guaranteed that the whole buffer will be sent with the NetworkConnection?
           offset += UInt(sentBytes)
        }
    }

    @inlinable
    public consuming func close() throws {
        //TODO: How do we close a NetworkConnection?
        print("TODO: Explicit closing of a DarwinAsyncTCPStream not yet implemented")
    }

    deinit {
        try? close()
    }
}
#endif
