import Foundation
import Darwin

/// The Mac's interfaces and addresses as `getifaddrs` reports them: names, flags (up,
/// point-to-point, loopback), each address with its prefix length. Both doors' origin checks read
/// it (`interfaces()`), and the remote door's address list reads the point-to-point tunnels that
/// are not network services from it. Cached for 2 s, so a burst of connections costs one read and
/// neither door needs a SystemConfiguration watcher.
///
/// Thread-safe: the doors call it on the network queue, the address list on its own queue.
final class InterfaceSnapshot: @unchecked Sendable {
    struct Entry: Sendable, Equatable {
        let name: String
        /// 4 or 16 bytes, without a zone.
        let address: [UInt8]
        let prefixBits: Int
        let up: Bool
        let pointToPoint: Bool
        let loopback: Bool
    }

    static let shared = InterfaceSnapshot()
    static let maxAge: CFAbsoluteTime = 2

    private let lock = NSLock()
    private var cached: (at: CFAbsoluteTime, entries: [Entry], interfaces: OriginPolicy.Interfaces)?

    /// For `OriginPolicy.classify`.
    func interfaces() -> OriginPolicy.Interfaces { current().interfaces }

    /// Every address of every interface.
    func entries() -> [Entry] { current().entries }

    /// Forget the cache (a network change the caller has heard of).
    func invalidate() {
        lock.lock(); cached = nil; lock.unlock()
    }

    private func current() -> (entries: [Entry], interfaces: OriginPolicy.Interfaces) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if let c = cached, now - c.at < Self.maxAge { lock.unlock(); return (c.entries, c.interfaces) }
        lock.unlock()
        let entries = Self.read()
        let interfaces = Self.policyInterfaces(entries)
        lock.lock(); cached = (now, entries, interfaces); lock.unlock()
        return (entries, interfaces)
    }

    /// One `getifaddrs` pass: IPv4 and IPv6 addresses only.
    static func read() -> [Entry] {
        var out: [Entry] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            let flags = ifa.ifa_flags
            let name = String(cString: ifa.ifa_name)
            var address: [UInt8] = []
            var bits = 0
            if family == AF_INET {
                address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { s in withUnsafeBytes(of: s.pointee.sin_addr) { Array($0) } }
                if let m = ifa.ifa_netmask {
                    bits = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { s in withUnsafeBytes(of: s.pointee.sin_addr) { Self.ones(Array($0)) } }
                }
            } else if family == AF_INET6 {
                address = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s in withUnsafeBytes(of: s.pointee.sin6_addr) { Array($0) } }
                if let m = ifa.ifa_netmask {
                    bits = m.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s in withUnsafeBytes(of: s.pointee.sin6_addr) { Self.ones(Array($0)) } }
                }
                // The kernel embeds the scope in bytes 2–3 of a link-local address; the address
                // itself has zeros there.
                if address[0] == 0xFE && address[1] & 0xC0 == 0x80 { address[2] = 0; address[3] = 0 }
            } else {
                continue
            }
            out.append(Entry(name: name, address: address, prefixBits: bits,
                             up: flags & UInt32(IFF_UP) != 0,
                             pointToPoint: flags & UInt32(IFF_POINTOPOINT) != 0,
                             loopback: flags & UInt32(IFF_LOOPBACK) != 0))
        }
        return out
    }

    /// The policy's view: each interface's kind, each local address's owner, and the on-link
    /// prefixes of every interface that is neither a tunnel nor loopback.
    static func policyInterfaces(_ entries: [Entry]) -> OriginPolicy.Interfaces {
        var result = OriginPolicy.Interfaces()
        for e in entries {
            let kind = OriginPolicy.interfaceKind(name: e.name, pointToPoint: e.pointToPoint, loopback: e.loopback)
            result.kind[e.name] = kind
            result.owner[e.address] = e.name
            if kind != .tunnel && kind != .loopback && e.prefixBits > 0 {
                result.prefixes.append((e.name, e.address, e.prefixBits))
            }
        }
        return result
    }

    private static func ones(_ mask: [UInt8]) -> Int {
        mask.reduce(0) { $0 + $1.nonzeroBitCount }
    }
}
