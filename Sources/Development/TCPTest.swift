import SebbuAsyncIO

fileprivate func clientFunc(_ client: AsyncTCPStream) async throws {
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1024, alignment: 1)
    defer { buffer.deallocate() }
    while true {
        let bytesReceived = try await client.receive(into: buffer)
        if bytesReceived == 0 { break }
        try await client.sendAll(.init(start: buffer.baseAddress, count: bytesReceived))
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
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 65536, alignment: 1)
    defer { buffer.deallocate() }
    while let line = readLine() {
        let byteCount = line.utf8.span.bytes.withUnsafeBytes {
            buffer.copyMemory(from: $0)
            return $0.count
        }
        try await client.sendAll(.init(start: buffer.baseAddress, count: byteCount))
        try await client.receive(exactly: byteCount, into: buffer)
        let decodedMessage = String(decoding: buffer[0..<byteCount], as: UTF8.self)
        print("Received from server:", decodedMessage)
    }
}

public func tcpTest() async throws {
    let tcpListener = try await AsyncTCPListener.listen(on: .anyIPv4(port: 25565), backlog: 10000)
    async let _ = try await serverFunc(tcpListener)

    let client = try await AsyncTCPStream.connect(to: .loopbackIPv4(port: 25565))
    try await localClientFunc(client)
}