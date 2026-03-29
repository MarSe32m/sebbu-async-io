import SebbuAsyncIO

fileprivate func serverFunc(_ server: AsyncTCPListener) async throws {
    let file = try AsyncFile.open(path: "Package.swift")
    let byteCount = try file.fileSize
    do {
        try await withThrowingDiscardingTaskGroup { group in
            while true {
                let client = try await server.accept()
                group.addTask {
                    print("Client connected")
                    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 65536, alignment: 1)
                    buffer.storeBytes(of: byteCount, as: Int.self)
                    try await client.sendAll(.init(start: buffer.baseAddress, count: 8))

                    try await client.transmit(file: file)
                    try await client.receive(exactly: 8, into: buffer)
                    let bytesReceived = buffer.loadUnaligned(as: Int.self)
                    print("Client said they received: ", bytesReceived, byteCount)
                }
            }
        }
    } catch {
        print("Server error:", error)
    }
    
}

fileprivate func localClientFunc(_ client: AsyncTCPStream) async throws {
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 65536, alignment: 1)
    defer { buffer.deallocate() }
    //print("Connected to server!")
    try await client.receive(exactly: 8, into: buffer)
    let bytesToReceive = buffer.loadUnaligned(as: Int.self)
    try await client.receive(exactly: bytesToReceive, into: buffer)
    buffer.storeBytes(of: bytesToReceive, as: Int.self)
    try await client.sendAll(.init(start: buffer.baseAddress, count: 8))
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
