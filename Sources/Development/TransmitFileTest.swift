import SebbuAsyncIO

fileprivate func serverFunc(_ server: AsyncTCPListener) async throws {
    let file = try AsyncFile.open(path: "Package.swift")
    let byteCount = try file.fileSize
    do {
        try await withThrowingDiscardingTaskGroup { group in
            while true {
                print("Accepting")
                let client = try await server.accept()
                group.addTask {
                    print("Client connected")
                    let bytesCountBytes = withUnsafeBytes(of: byteCount) { [UInt8]($0) }
                    try await client.send(bytesCountBytes)

                    try await client.transmit(file: file)
                    let bytes = try await client.receive(exactly: 8)
                    let bytesReceived = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
                    print("Client said they received: ", bytesReceived, byteCount)
                }
            }
        }
    } catch {
        print("Server error:", error)
    }
    
}

fileprivate func localClientFunc(_ client: AsyncTCPStream) async throws {
    print("Connected to server!")
    var bytes = try await client.receive(exactly: 8)
    let bytesToReceive = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int.self) }
    
    bytes = try await client.receive(exactly: bytesToReceive)
    let byteCountBytes = withUnsafeBytes(of: bytes.count) { [UInt8]($0) }
    try await client.send(byteCountBytes)
}

public func transmitFileTest() async throws {
    let tcpListener = try await AsyncTCPListener.listen(on: .anyIPv4(port: 25565), backlog: 10000)
    async let _ = try await serverFunc(tcpListener)

    try await withThrowingDiscardingTaskGroup { group in 
        for _ in 0..<1000 {
            let client = try await AsyncTCPStream.connect(to: .loopbackIPv4(port: 25565))
            try await localClientFunc(client)
        }
        for _ in 0..<1000 {
            group.addTask {
                let client = try await AsyncTCPStream.connect(to: .loopbackIPv4(port: 25565))
                try await localClientFunc(client)
            }
        }
    }
    print("Done")
}
