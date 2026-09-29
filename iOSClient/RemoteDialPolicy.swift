import Foundation
#if canImport(Darwin)
import Darwin
#endif
import StreamProtocol

/// How the device dials a saved Mac from afar (docs/remote-access-plan.md §7.5): the order of its
/// addresses, what ended each attempt, and which failure the status line words when every attempt
/// failed. Pure logic, Foundation only: checked on its own with swiftc, and fed by RemoteConnector.
enum RemoteDialPolicy {
    /// Attempts start this far apart, or at once when the one before fails.
    static let stagger = 1.0
    /// The whole dial gives up after this.
    static let wholeDial = 20.0
    /// The winner (pinned, `.ready`) must deliver a window list within this, or the dial failed as
    /// "didn't answer": with TLS 1.3 the device is ready before the Mac has judged its certificate.
    static let firstListDeadline = 10.0
    /// A pairing connection's kind 20 must follow its kind 19 within this.
    static let pairingReplyDeadline = 15.0

    /// Whether a code the scanner read starts a pairing (StreamClient.scanned). The scanner reports
    /// a code each time it finds it (a scanner shown again finds the one still in view) and each
    /// time the person taps its highlight. Never while a pairing runs or has just succeeded
    /// (`busy`): a second dial, once the first's kind 19 had spent the code, left the Mac listing
    /// a device that saved nothing. After a failure the same code (`secret` is the last one
    /// scanned) starts again only from a tap: found again by itself, it failed again and again
    /// until the Mac's door kept this device out for five minutes. Another code starts at once.
    static func scanStartsPairing(busy: Bool, failed: Bool, secret: Data, lastScanned: Data?, tapped: Bool) -> Bool {
        if busy { return false }
        return !(failed && !tapped && secret == lastScanned)
    }

    /// One address to dial.
    struct Candidate: Hashable {
        /// A name, an IPv4 address or an IPv6 address without brackets.
        var host: String
        var port: Int
        /// "vpn", "lan" or "internet" (MacAddress's kinds).
        var kind: String
        /// "Tailscale", "Wi‑Fi"…; "" for an address with no service name (typed, or from a link).
        var via: String

        /// "host|port", how `SavedMac.lastWorked` names the address that won.
        var key: String { "\(host)|\(port)" }
        var isName: Bool { IPv4.parse(host) == nil && !host.contains(":") }
        var isIPv6: Bool { host.contains(":") }
        /// "100.101.102.103", or "[fd7a::1]:7460" with a port other than the usual one: as the
        /// copy shows it.
        var display: String {
            port == 7455 ? host : "\(isIPv6 ? "[\(host)]" : host):\(port)"
        }
    }

    /// The dial order: the address that last worked; VPN names, VPN IPv4, VPN IPv6; LAN addresses
    /// in a subnet this device shares (it is at home, and Bonjour failed); internet names, then
    /// internet addresses; the other LAN addresses (reached through a VPN into the home network).
    /// Duplicates (same host and port) are dialed once. `localIPv4` is this device's own IPv4
    /// networks (address and prefix length).
    ///
    /// A loopback address goes before all of them: only a test host lists one (127.0.0.1, "This
    /// Mac", first in its list so the simulator on the same Mac reaches it that way), and it either
    /// is this very machine or nothing answers at once.
    static func order(_ addresses: [MacAddress], remotePort: Int, lastWorked: String?,
                      localIPv4: [(address: [UInt8], prefix: Int)]) -> [Candidate] {
        let all = addresses.map { Candidate(host: $0.host, port: $0.port ?? remotePort, kind: $0.kind, via: $0.via) }
        func vpn(_ c: Candidate) -> Bool { c.kind == MacAddress.vpn || isVPNAddress(c.host) }
        func shared(_ c: Candidate) -> Bool {
            guard let a = IPv4.parse(c.host) else { return false }
            return localIPv4.contains { IPv4.sameNetwork(a, $0.address, prefix: $0.prefix) }
        }
        let vpns = all.filter(vpn)
        let lans = all.filter { !vpn($0) && $0.kind == MacAddress.lan }
        let internet = all.filter { !vpn($0) && $0.kind != MacAddress.lan }
        func loopback(_ c: Candidate) -> Bool { c.host.hasPrefix("127.") || c.host == "::1" }
        var ordered = all.filter(loopback)
        ordered += vpns.filter(\.isName) + vpns.filter { !$0.isName && !$0.isIPv6 } + vpns.filter(\.isIPv6)
        ordered += lans.filter { shared($0) && !loopback($0) }
        ordered += internet.filter(\.isName) + internet.filter { !$0.isName }
        ordered += lans.filter { !shared($0) && !loopback($0) }
        if let lastWorked, let i = ordered.firstIndex(where: { $0.key == lastWorked }) {
            ordered.insert(ordered.remove(at: i), at: 0)
        }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.key.lowercased()).inserted }
    }

    /// Tailscale's shapes: 100.64/10, fd7a:115c:a1e0::/48, a .ts.net name. An address with one of
    /// them is a VPN address whatever kind it was saved with.
    static func isVPNAddress(_ host: String) -> Bool {
        if let a = IPv4.parse(host) { return a[0] == 100 && a[1] & 0xC0 == 64 }
        if host.lowercased().hasPrefix("fd7a:115c:a1e0:") { return true }
        return isTailscaleName(host)
    }

    /// The saved Macs whose key a dial of `old` at `candidate` takes in its place (Noah, 2026-09-28:
    /// Sill for Mac 0.4.0 made the Mac a new key, the device paired it again, and the old record
    /// stayed as a dead "‹Mac›" Remote row beside the working "‹Mac› (2)"). Only when the key that
    /// answers is one of these, and the handshake completes with it (TLS 1.3's CertificateVerify:
    /// the Mac holds that key), is `old` superseded (`SavedMacs.superseding`). Never on the name
    /// alone: all of these must hold.
    /// - Another record, not revoked or marked `newKey`, whose key is readable.
    /// - The same name (a Mac set up again keeps its name; two Macs of one name at home and at the
    ///   office are told apart by the rest).
    /// - Paired after `old` was last reached (`lastConnectedAt ?? pairedAt`): a record reached
    ///   since the other was paired is a Mac in use, not one set up again.
    /// - An address that names one machine wherever this device is: Tailscale's shapes, or an
    ///   internet address or name. A private or `.local` address can be another Mac on another
    ///   network (the home Mac's 192.168.1.10 is the office Mac's at the office), and a pin refused
    ///   there is no wrong Mac either (`classify`). Loopback only with `allowLoopback` (DEBUG: the
    ///   simulator's test hosts on this Mac).
    static func successors(of old: SavedMac, at candidate: Candidate, in list: [SavedMac], allowLoopback: Bool) -> [SavedMac] {
        let h = candidate.host.lowercased()
        let loopback = h.hasPrefix("127.") || h == "::1" || h == "localhost"
        let unique = isVPNAddress(h) || (candidate.kind != MacAddress.lan && kind(ofHost: h) == MacAddress.internet)
        guard unique || (loopback && allowLoopback) else { return [] }
        let lastReached = old.lastConnectedAt ?? old.pairedAt
        return list.filter { mac in
            mac.macID != old.macID && mac.revoked != true && mac.newKey != true && mac.fingerprintData != nil
                && mac.name == old.name && mac.pairedAt > lastReached
        }
    }

    static func isTailscaleName(_ host: String) -> Bool {
        let h = host.lowercased()
        return h.hasSuffix(".ts.net") || h.hasSuffix(".ts.net.")
    }

    /// The kind of an address that came without one (typed, or from a pairing link): Tailscale's
    /// shapes are "vpn", private and link-local ranges "lan" (loopback too: "This Mac" in the
    /// tests), anything else "internet".
    static func kind(ofHost host: String) -> String {
        if isVPNAddress(host) { return MacAddress.vpn }
        if let a = IPv4.parse(host) {
            let lan = a[0] == 10 || (a[0] == 172 && a[1] & 0xF0 == 16) || (a[0] == 192 && a[1] == 168)
                || (a[0] == 169 && a[1] == 254) || a[0] == 127
            return lan ? MacAddress.lan : MacAddress.internet
        }
        let h = host.lowercased()
        if h.contains(":") {
            let lan = h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe8") || h == "::1"
            return lan ? MacAddress.lan : MacAddress.internet
        }
        return h.hasSuffix(".local") || h == "localhost" ? MacAddress.lan : MacAddress.internet
    }

    /// A MacAddress for an address that came without a kind or a name.
    static func address(for parsed: ParsedAddress) -> MacAddress {
        let kind = kind(ofHost: parsed.host)
        let via = isVPNAddress(parsed.host) ? "Tailscale" : (parsed.host.hasPrefix("127.") ? "This Mac" : "")
        return MacAddress(host: parsed.host, port: parsed.port, kind: kind, via: via)
    }

    // MARK: Failures

    /// What ended one attempt (RemoteConnector reads it off Network.framework).
    enum End: Equatable {
        /// A TLS error before `.ready` (the attempt waited or failed with it).
        case tls(Int32)
        /// The first read after `.ready` failed with this TLS error (the Mac refused our key).
        case tlsAfterReady(Int32)
        case posix(Int32)
        case dns(Int32)
        /// The 10 s connect timeout.
        case timeout
        /// A wrong application protocol, or a message no Sill sends (oversized, not decodable).
        case notSill
        /// Kind 22 before the first window list.
        case goodbye(String)
        /// Ready, but no window list within `firstListDeadline`.
        case noWindowList
    }

    /// Why a dial failed, for the status line (§7.8), most telling first in `priority`.
    enum Failure: String, CaseIterable, Equatable {
        case wrongMac, revoked, remoteOff, busy, refused, vpnOff, nameNotFound, localNetwork, notSill, noAnswer
    }

    /// Wrong Mac first (the pin failed: acting on anything else would be wrong), then the Mac's own
    /// answers, then what this device can fix, then silence.
    static let priority: [Failure] = [.wrongMac, .revoked, .remoteOff, .busy, .refused, .vpnOff, .nameNotFound, .localNetwork, .notSill, .noAnswer]

    static func worst(_ failures: [Failure]) -> Failure? {
        priority.first { failures.contains($0) }
    }

    static let dnsNoSuchName: Int32 = -65538
    static let dnsNoSuchRecord: Int32 = -65554
    static let dnsPolicyDenied: Int32 = -65570

    /// One attempt's end as a failure; nil for one that does not count (another machine answered
    /// at a LAN address: only a stranger at that number, not a wrong Mac). `usedTunnel`: whether
    /// the attempt's path went through a tunnel interface (nil when unknown).
    static func classify(_ end: End, candidate: Candidate, usedTunnel: Bool?) -> Failure? {
        let vpnAddress = candidate.kind == MacAddress.vpn || isVPNAddress(candidate.host)
        switch end {
        case .tls(-9808):
            return candidate.kind == MacAddress.lan && !isVPNAddress(candidate.host) ? nil : .wrongMac
        case .tls(-9825), .tls(-9829), .tlsAfterReady(-9825), .tlsAfterReady(-9829), .goodbye(Goodbye.removed):
            return .revoked
        case .goodbye(Goodbye.remoteOff): return .remoteOff
        case .goodbye(Goodbye.busy): return .busy
        case .goodbye(Goodbye.internetOff): return .refused
        case .goodbye: return .refused
        // The Mac closed it before or during TLS: over its limits, a source it holds off, or an
        // origin its internet switch refuses.
        case .tls(-9816), .tls(-9806), .posix(ECONNREFUSED), .posix(ECONNRESET), .posix(ECONNABORTED), .posix(EPIPE):
            return .refused
        case .dns(dnsNoSuchName), .dns(dnsNoSuchRecord):
            return isTailscaleName(candidate.host) ? .vpnOff : .nameNotFound
        case .dns(dnsPolicyDenied):
            return candidate.kind == MacAddress.lan ? .localNetwork : .noAnswer
        case .dns:
            return .nameNotFound
        case .tls, .tlsAfterReady, .notSill:
            return .notSill
        case .timeout, .noWindowList, .posix(ETIMEDOUT), .posix(ENETUNREACH), .posix(EHOSTUNREACH),
             .posix(ENETDOWN), .posix(EHOSTDOWN), .posix(EADDRNOTAVAIL):
            return vpnAddress && usedTunnel == false ? .vpnOff : .noAnswer
        case .posix:
            return .noAnswer
        }
    }

    // MARK: IPv4 helpers

    enum IPv4 {
        /// Four decimal octets, nothing else.
        static func parse(_ s: String) -> [UInt8]? {
            let parts = s.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var out: [UInt8] = []
            for p in parts {
                guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isASCII && $0.isNumber }), let v = UInt8(p) else { return nil }
                out.append(v)
            }
            return out
        }

        static func sameNetwork(_ a: [UInt8], _ b: [UInt8], prefix: Int) -> Bool {
            guard a.count == 4, b.count == 4, (1...32).contains(prefix) else { return false }
            var bits = prefix
            for i in 0..<4 {
                let n = min(8, max(0, bits))
                let mask: UInt8 = n == 0 ? 0 : UInt8(truncatingIfNeeded: 0xFF << (8 - n))
                if a[i] & mask != b[i] & mask { return false }
                bits -= 8
            }
            return true
        }
    }
}
