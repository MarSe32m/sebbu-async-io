import SebbuAsyncIO
import SystemPackage

func testFileReading() async throws -> [UInt8] {
    let path = FilePath("Package.swift")
    let file = try AsyncFile.open(path: path)
    var data: [UInt8] = []
    var offset: UInt = 0
    while true {
        do {
            let bytes = try await file.read(atMost: 1024, atAbsoluteOffset: offset)
            offset += UInt(bytes.count)
            data.append(contentsOf: bytes)
            if bytes.count == 0 { break }
        } catch let error {
            if error == .endOfFile { break }
            print("Error occurred:", error)
        }
    }
    print(String(decoding: data, as: UTF8.self))
    try file.close()
    return data
}

func testFileCreationAndDeletion() async throws {
    let path = FilePath("./test.txt")
    let file = try AsyncFile.create(path: path)
    let data = try await testFileReading()
    try await file.write(data: data, atAbsoluteOffset: 0)
    try await Task.sleep(for: .seconds(10))
    try file.close()
    try AsyncFile.delete(path: path)
}