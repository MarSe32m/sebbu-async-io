#if canImport(Darwin)
import Network
import Foundation

@usableFromInline
internal final class DarwinAsyncTCPStream: Sendable {
    
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
        print("Connecting")
        // We take an establishment report so that we attempt the connection right away
        let _ = try await connection.establishmentReport()
        print("Connected")
        return DarwinAsyncTCPStream(connection: connection)
    }

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        try await connection.send(data)
    }

    @inlinable
    public func receive(atLeast: Int = 1, atMost: Int) async throws -> [UInt8] {
        [UInt8](try await connection.receive(atLeast: atLeast, atMost: atMost).content)
    }

    @inline(always)
    public func receive(exactly: Int) async throws -> [UInt8] {
        try await receive(atLeast: exactly, atMost: exactly)
    }

    @inlinable
    public func transmit(file: borrowing AsyncFile) async throws {
        //TODO: Use sendfile in a separate threadpool
        let fileSize = try file.fileSize
        var offset: UInt = 0
        while Int(offset) < fileSize {
            let bytes = try await file.read(atMost: 65536, atAbsoluteOffset: offset)
            offset += UInt(bytes.count)
            try await send(bytes)
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
