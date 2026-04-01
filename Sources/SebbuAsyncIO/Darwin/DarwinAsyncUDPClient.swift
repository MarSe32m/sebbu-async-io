#if canImport(Darwin)
import Network
import Foundation

@usableFromInline
internal final class DarwinAsyncUDPClient: AsyncUDPClientProtocol {
    @usableFromInline
    let connection: NetworkConnection<UDP>
    
    @inlinable
    init(connection: NetworkConnection<UDP>) {
        self.connection = connection
    }
    
    @inlinable
    public static func connect(to: Endpoint) async throws -> DarwinAsyncUDPClient {
        guard let endpoint = to.endpoint else {
            fatalError("TODO: Throw a proper error")
        }
        let connection = NetworkConnection(to: endpoint) {
            UDP()
        }
        // We take an establishment report so that we attempt the connection right away
        let _ = try await connection.establishmentReport()
        return DarwinAsyncUDPClient(connection: connection)
    }

    //TODO: We need a RawSpan version of this
    @inlinable
    public func send(_ bytes: UnsafeRawBufferPointer) async throws -> Int {
        try await connection.send(bytes)
        return bytes.count
    }

    //TODO: We need an OutputRawSpan version of this
    @inlinable
    public func receive(into: UnsafeMutableRawBufferPointer) async throws -> Int {
        try await connection.receive().content.withUnsafeBytes { bytes in
            into.copyMemory(from: bytes)
            return bytes.count
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
