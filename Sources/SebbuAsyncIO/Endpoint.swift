#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
import Network
import Foundation
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
    internal final class Storage: @unchecked Sendable {
        @usableFromInline
        let storage: UnsafeMutablePointer<sockaddr_storage>

        @usableFromInline
        let length: UnsafeMutablePointer<socklen_t>

        @inlinable
        convenience init() {
            self.init(storage: .init(), length: 0)
        }

        @inlinable
        init(storage: sockaddr_storage, length: socklen_t) {
            self.storage = .allocate(capacity: 1)
            self.length = .allocate(capacity: 1)
            self.storage.initialize(to: storage)
            self.length.initialize(to: length)
        }

        @inlinable
        func copy() -> Storage {
            Storage(storage: storage.pointee, length: length.pointee)
        }

        @inlinable
        deinit {
            storage.deallocate()
            length.deallocate()
        }
    }

    @usableFromInline
    var storage: Storage

    public init() {
        storage = Storage()
    }

    @inlinable
    init(storage: sockaddr_storage, length: socklen_t) {
        self.storage = Storage(storage: storage, length: length)
    }

    // MARK: - Construction
    public static func ipv4(host: String, port: UInt16) async throws -> Endpoint {
        try await resolve(host: host, port: port, family: .IPv4)
    }

    public static func ipv6(host: String, port: UInt16) async throws -> Endpoint {
        try await resolve(host: host, port: port, family: .IPv6)
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
        self.init(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in>.size))
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

        self.init(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in6>.size))
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
        return Endpoint(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in>.size))
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
        return Endpoint(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in>.size))
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

        return Endpoint(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in6>.size))
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

        return Endpoint(storage: storage, length: socklen_t(MemoryLayout<sockaddr_in6>.size))
    }

    // MARK: - Properties
    public var family: Family {
        switch Int32(storage.storage.pointee.ss_family) {
        case AF_INET:
            return .IPv4
        case AF_INET6:
            return .IPv6
        default:
            fatalError("Unreachable")
        }
    }

    public var port: UInt16 {
        switch family {
        case .IPv4:
            return storage.storage.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt16(bigEndian: $0.pointee.sin_port)
            }
        case .IPv6:
            return storage.storage.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                UInt16(bigEndian: $0.pointee.sin6_port)
            }
        }
    }

    public var host: String? {
        switch Int32(storage.storage.pointee.ss_family) {
        case AF_INET:
            let addr = storage.storage.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            return numericHostString(family: AF_INET, address: addr)
        case AF_INET6:
            let addr = storage.storage.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee.sin6_addr
            }
            return numericHostString(family: AF_INET6, address: addr)
        default: fatalError("Unreachable")
        }
    }
    
    #if canImport(Network)
    public var endpoint: NWEndpoint? {
        switch family {
        case .IPv4:
            return withUnsafePointer(to: storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                    let addr = sin.pointee.sin_addr
                    let ipData = withUnsafeBytes(of: addr) { Data($0) }
                    guard let ipv4 = IPv4Address(ipData) else {
                        return nil
                    }
                    let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: sin.pointee.sin_port))!
                    return .hostPort(host: .ipv4(ipv4), port: port)
                }
            }
        case .IPv6:
            return withUnsafePointer(to: storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                    let addr = sin6.pointee.sin6_addr
                    let ipData = withUnsafeBytes(of: addr) { Data($0) }
                    guard let ipv6 = IPv6Address(ipData) else {
                        return nil
                    }
                    let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: sin6.pointee.sin6_port))!
                    return .hostPort(host: .ipv6(ipv6), port: port)
                }
            }
        }
    }
    #endif

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
        try storage.storage.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            try body($0, socklen_t(storage.length.pointee))
        }
    }

    /// Useful for syscalls that may write through the sockaddr pointer.
    @inlinable
    public mutating func withMutableSockAddrStoragePointer<R>(
        _ body: (UnsafeMutablePointer<sockaddr_storage>, UnsafeMutablePointer<socklen_t>) throws -> R
    ) rethrows -> R {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.copy()
        }
        return try storage.length.withMemoryRebound(to: socklen_t.self, capacity: 1) { socklen in
            return try body(storage.storage, socklen)
        }
    }
}

// MARK: - Resolution

extension Endpoint {
    @usableFromInline
    static func resolve(host: String, port: UInt16, family: Family) async throws -> Endpoint {
        try await withUnsafeThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let _family = family == .IPv4 ? AF_INET : AF_INET6
                var hints = addrinfo()
                hints.ai_flags = AI_NUMERICSERV
                hints.ai_family = _family

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
                var current = result
                while let addrInfoPtr = current {
                    defer { current = current?.pointee.ai_next }
                    if addrInfoPtr.pointee.ai_family != _family { continue }
                    if let endpoint = try? Endpoint(addrInfo: addrInfoPtr.pointee) {
                        continuation.resume(returning: endpoint)
                        return
                    }
                }
                continuation.resume(throwing: Error.noResult)
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

        self.init(storage: storage, length: socklen_t(length))
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
