import SebbuAsyncIO
fileprivate func clientFunc(_ client: AsyncTCPStream) async throws {
    while true {
        let bytes = try await client.receive(atMost: 1024)
        if bytes.isEmpty { break }
        try await client.send(bytes)
    }
}

fileprivate func serverFunc(_ server: AsyncTCPListener) async throws {
    try await withThrowingDiscardingTaskGroup { group in 
        while true {
            let client = try await server.accept()
            group.addTask { 
                do {
                    try await clientFunc(client) 
                } catch {
                    print("[Server]: A client failed with:", error)
                }
            }
        }
    }
}

fileprivate func localClientFunc(_ client: AsyncTCPStream) async throws {
    print("Connected to server!")
    while let line = readLine() {
        let bytes = [UInt8](line.utf8)
        try await client.send(bytes)
        let receivedBytes = try await client.receive(exactly: bytes.count)
        let decodedMessage = String(decoding: receivedBytes, as: UTF8.self)
        print("Received from server:", decodedMessage)
    }
}

public func tcpTest() async throws {
    let tcpListener = try await AsyncTCPListener.listen(on: .anyIPv4(port: 25565), backlog: 10000)
    async let _ = try await serverFunc(tcpListener)

    let client = try await AsyncTCPStream.connect(to: .loopbackIPv4(port: 25565))
    try await localClientFunc(client)
}