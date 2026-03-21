#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

import Dispatch

public struct Endpoint: Sendable, CustomStringConvertible {
    public enum Family: Sendable {
        case IPv4
        case IPv6
    }

    public enum Error: Swift.Error, Sendable, CustomStringConvertible {
        case resolutionFailed(code: Int32, message: String)
        case noResult
        case addressTooLarge
        case invalidIPAddress(String)
        #if os(Windows)
        case unsupportedFamily(ADDRESS_FAMILY)
        #else
        case unsupportedFamily(sa_family_t)
        #endif

        public var description: String {
            switch self {
            case let .resolutionFailed(code, message):
                return "Socket address resolution failed (\(code)): \(message)"
            case .noResult:
                return "Socket address resolution returned no results"
            case .addressTooLarge:
                return "Resolved socket address does not fit in sockaddr_storage"
            case let .invalidIPAddress(ip):
                return "Invalid IP address: \(ip)"
            case let .unsupportedFamily(family):
                return "Unsupported socket family: \(family)"
            }
        }
    }

    @usableFromInline
    var storage: sockaddr_storage

    @usableFromInline
    var storageLength: Int32

    public init() {
        storage = sockaddr_storage()
        storageLength = 0
    }

    @inlinable
    init(storage: sockaddr_storage, storageLength: Int32) {
        self.storage = storage
        self.storageLength = storageLength
    }

    // MARK: - Construction

    public static func ipv4(host: String, port: UInt16) async throws -> Endpoint {
        try await resolve(host: host, port: port, family: numericCast(AF_INET))
    }

    public static func ipv6(host: String, port: UInt16) async throws -> Endpoint {
        try await resolve(host: host, port: port, family: numericCast(AF_INET6))
    }

    /// Fast path for a numeric IPv4 literal such as "127.0.0.1".
    public init(ipv4 ip: String, port: UInt16) throws {
        var addr = sockaddr_in()
        #if os(Windows)
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = port.bigEndian
        #else
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port.bigEndian)
        #endif

        let ok: Bool = ip.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sin_addr) { ptr in
                inet_pton(AF_INET, cs, ptr) == 1
            }
        }

        guard ok else {
            throw Error.invalidIPAddress(ip)
        }

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }
        self.init(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in>.size))
    }

    /// Fast path for a numeric IPv6 literal such as "::1".
    public init(ipv6 ip: String, port: UInt16) throws {
        var addr = sockaddr_in6()
        #if os(Windows)
        addr.sin6_family = ADDRESS_FAMILY(AF_INET6)
        addr.sin6_port = port.bigEndian
        #else
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = in_port_t(port.bigEndian)
        #endif

        let ok: Bool = ip.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sin6_addr) { ptr in
                inet_pton(AF_INET6, cs, ptr) == 1
            }
        }

        guard ok else {
            throw Error.invalidIPAddress(ip)
        }

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }

        self.init(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in6>.size))
    }

    public static func anyIPv4(port: UInt16) -> Endpoint {
        var addr = sockaddr_in()
        #if os(Windows)
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in4addr_any
        #else
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port.bigEndian)
        addr.sin_addr = in_addr(s_addr: in_addr_t(INADDR_ANY))
        #endif

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }
        return Endpoint(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in>.size))
    }

    public static func loopbackIPv4(port: UInt16) -> Endpoint {
        var addr = sockaddr_in()
        #if os(Windows)
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in4addr_loopback
        #else
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port.bigEndian)
        addr.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK))
        #endif

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }
        return Endpoint(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in>.size))
    }

    public static func loopbackIPv6(port: UInt16) -> Endpoint {
        var addr = sockaddr_in6()
        #if os(Windows)
        addr.sin6_family = ADDRESS_FAMILY(AF_INET6)
        addr.sin6_port = port.bigEndian
        #else
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = in_port_t(port.bigEndian)
        #endif
        addr.sin6_addr = in6addr_loopback

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }

        return Endpoint(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in6>.size))
    }

    public static func anyIPv6(port: UInt16) -> Endpoint {
        var addr = sockaddr_in6()
        #if os(Windows)
        addr.sin6_family = ADDRESS_FAMILY(AF_INET6)
        addr.sin6_port = port.bigEndian
        #else
        addr.sin6_family = sa_family_t(AF_INET6)
        addr.sin6_port = in_port_t(port.bigEndian)
        #endif
        addr.sin6_addr = in6addr_any

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { dest in
            withUnsafeBytes(of: addr) { src in 
                dest.copyMemory(from: src)
            }
        }

        return Endpoint(storage: storage, storageLength: Int32(MemoryLayout<sockaddr_in6>.size))
    }

    // MARK: - Properties
    public var family: Family {
        switch Int32(storage.ss_family) {
        case AF_INET:
            return .IPv4
        case AF_INET6:
            return .IPv6
        default:
            fatalError("Unreachable")
        }
    }

    public var port: UInt16 {
        return withUnsafePointer(to: storage) { storagePointer in
            storagePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in 
                switch Int32(sockaddrPointer.pointee.sa_family) {
                    case AF_INET:
                        return sockaddrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            UInt16(bigEndian: $0.pointee.sin_port)
                        }
                    case AF_INET6:
                        return sockaddrPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                            UInt16(bigEndian: $0.pointee.sin6_port)
                        }
                    default: fatalError("Unreachable")
                }
            }
        }
    }

    public var host: String? {
        let family = Int32(storage.ss_family)

        switch family {
        case AF_INET:
            let addr = withUnsafePointer(to: storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr
                }
            }
            return numericHostString(family: AF_INET, address: addr)

        case AF_INET6:
            let addr = withUnsafePointer(to: storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr
                }
            }
            return numericHostString(family: AF_INET6, address: addr)

        default:
            fatalError("Unreachable")
        }
    }

    public var description: String {
        let hostText = host ?? "<unknown>"
        switch family {
        case .IPv4:
            return "\(hostText):\(port)"
        case .IPv6:
            return "[\(hostText)]:\(port)"
        }
    }

    // MARK: - Pointer access
    @inlinable
    public func withSockAddrPointer<R>(
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> R
    ) rethrows -> R {
        try withUnsafePointer(to: storage) {
            try $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, storageLength)
            }
        }
    }

    /// Useful for syscalls that may write through the sockaddr pointer.
    @inlinable
    public mutating func withMutableSockAddrStoragePointer<R>(
        _ body: (UnsafeMutablePointer<sockaddr_storage>, UnsafeMutablePointer<socklen_t>) throws -> R
    ) rethrows -> R {
        try body(&storage, &storageLength)
    }
}

// MARK: - Resolution

extension Endpoint {
    @usableFromInline
    static func resolve(host: String, port: UInt16, family: Int32) async throws -> Endpoint {
        try await withUnsafeThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_flags = AI_NUMERICSERV
                hints.ai_family = family

                let service = String(port)
                var result: UnsafeMutablePointer<addrinfo>?

                let status: Int32 = host.withCString { hostPtr in
                    service.withCString { servicePtr in
                        getaddrinfo(hostPtr, servicePtr, &hints, &result)
                    }
                }

                guard status == 0 else {
                    continuation.resume(throwing: Error.resolutionFailed(code: status, message: gaiMessage(for: status)))
                    return
                }

                defer {
                    if let result {
                        freeaddrinfo(result)
                    }
                }

                guard let first = result else {
                    continuation.resume(throwing: Error.noResult)
                    return
                }
                do {
                    let endpoint = try Endpoint(addrInfo: first.pointee)
                    continuation.resume(returning: endpoint)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @usableFromInline
    init(addrInfo: addrinfo) throws {
        guard let aiAddr = addrInfo.ai_addr else {
            throw Error.noResult
        }

        let length = Int(addrInfo.ai_addrlen)
        guard length <= MemoryLayout<sockaddr_storage>.size else {
            throw Error.addressTooLarge
        }

        var storage = sockaddr_storage()
        withUnsafeMutableBytes(of: &storage) { destBytes in
            destBytes.initializeMemory(as: UInt8.self, repeating: 0)
            memcpy(destBytes.baseAddress!, aiAddr, length)
        }

        self.init(storage: storage, storageLength: Int32(length))
    }
}

// MARK: - Helpers
@usableFromInline
func gaiMessage(for code: Int32) -> String {
    #if os(Windows)
    if let cString = WinSDK.gai_strerrorA(code) {
        return String(cString: cString)
    } else {
        return "Unknown error"
    }
    #else
    if let cString = gai_strerror(code) {
        return String(cString: cString)
    } else {
        return "Unknown error"
    }
    #endif
}

@usableFromInline
func numericHostString<T>(family: Int32, address: T) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))

    let result: UnsafePointer<CChar>? = withUnsafePointer(to: address) { ptr in
    #if os(Windows)
        inet_ntop(family, ptr, &buffer, buffer.count)
    #else
        inet_ntop(
            family,
            UnsafeRawPointer(ptr),
            &buffer,
            socklen_t(buffer.count)
        )
    #endif
    }
    guard let result else {
        return nil
    }
    let count = strlen(result)
    return String(decoding: buffer[0..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}