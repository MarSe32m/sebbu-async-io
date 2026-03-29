#if canImport(Darwin)
import Network
import Foundation

@usableFromInline
internal final class DarwinAsyncUDPClient: Sendable {
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

    @inlinable
    public func send(_ data: [UInt8]) async throws {
        try await connection.send(data)
    }

    @inlinable
    public func receive() async throws -> [UInt8] {
        try await [UInt8](connection.receive().content)
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
