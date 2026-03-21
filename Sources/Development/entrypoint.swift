@main
struct Entry {
    static func main() async throws {
        //let _ = try await testFileReading()
        //try await testFileCreationAndDeletion()
        //try await udpTest()
        //try await tcpTest()
        try await transmitFileTest()
    }
}