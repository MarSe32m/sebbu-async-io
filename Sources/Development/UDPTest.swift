import SebbuAsyncIO

func serverFunc(_ server: AsyncUDPSocket) async throws {
    var endpoint = Endpoint.anyIPv4(port: 0)
    while true {
        let data = try await server.receive(from: &endpoint)
        try await server.send(data, to: endpoint)
    }
}

func localClientFunc(_ client: AsyncUDPClient) async throws {
    print("Send lines!")
    while let line = readLine() {
        let bytes = [UInt8](line.utf8)
        try await client.send(bytes)
        let receivedBytes = try await client.receive()
        let decodedMessage = String(decoding: receivedBytes, as: UTF8.self)
        print("Received from server:", decodedMessage)
    }
}

func udpTest() async throws {
    let udpSocket = try await AsyncUDPSocket.bind(to: .anyIPv4(port: 25566))
    async let _ = try await serverFunc(udpSocket)

    let udpClient = try await AsyncUDPClient.connect(to: .loopbackIPv4(port: 25566))
    try await localClientFunc(udpClient)
}