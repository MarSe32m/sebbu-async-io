import SebbuAsyncIO
import SystemPackage

func testFileReading() async throws -> [UInt8] {
    let path = FilePath("Package.swift")
    let file = try await AsyncFile.open(path: path)
    let data = try await file.readUntilEndOfFile()
    print(String(decoding: data, as: UTF8.self))
    try await file.close()
    return data
}

func testFileCreationAndDeletion() async throws {
    let path = FilePath("./test.txt")
    let file = try await AsyncFile.create(path: path)
    let data = try await testFileReading()
    let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: data.count, alignment: 1)
    defer { buffer.deallocate() }
    buffer.copyBytes(from: data)
    try await file.writeAll(buffer, atAbsoluteOffset: 0)
    try await Task.sleep(for: .seconds(10))
    try await file.close()
    try await AsyncFile.delete(path: path)
}
