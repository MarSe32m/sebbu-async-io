import SebbuAsyncIO

func serverFunc(_ server: AsyncUDPSocket) async throws {
    var endpoint = Endpoint.anyIPv4(port: 0)
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1500, alignment: 1)
    defer { buffer.deallocate() }
    while true {
        let bytesReceived = try await server.receive(into: buffer, from: &endpoint)
        let bytesSent = try await server.send(.init(start: buffer.baseAddress, count: bytesReceived), to: endpoint)
        if bytesSent != bytesReceived {
            print("Didn't send as much as was received?")
        }
    }
}

func localClientFunc(_ client: AsyncUDPClient) async throws {
    print("Send lines!")
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 1500, alignment: 1)
    defer { buffer.deallocate() }
    while let line = readLine() {
        let byteCount = line.utf8.span.bytes.withUnsafeBytes {
            buffer.copyMemory(from: $0)
            return $0.count
        }
        let bytesSent = try await client.send(.init(start: buffer.baseAddress, count: byteCount))
        let bytesReceived = try await client.receive(into: buffer)
        if bytesSent != bytesReceived {
            print("Client didn't receive as many bytes as they sent?")
        }
        let decodedMessage = String(decoding: buffer[0..<bytesReceived], as: UTF8.self)
        print("Received from server:", decodedMessage)
    }
}

func udpTest() async throws {
    let udpSocket = try await AsyncUDPSocket.bind(to: .anyIPv4(port: 25566))
    async let _ = try await serverFunc(udpSocket)

    let udpClient = try await AsyncUDPClient.connect(to: .loopbackIPv4(port: 25566))
    try await localClientFunc(udpClient)
}