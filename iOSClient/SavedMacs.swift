import Foundation
import StreamProtocol

/// A Mac this device paired with (docs/remote-access-plan.md §7.2): what it needs to recognise the
/// Mac on a network (the recognition key resolves its Bonjour TXT tag) and to reach it from afar
/// (its pin, port and addresses). Saved only after a pairing whose proof_M checked; refreshed only
/// by a kind 18 that verifies against the pin. Keyed by Mac ID, never by name: two Macs can share
/// a name, and a stranger's Mac can take one.
struct SavedMac: Codable, Hashable, Identifiable {
    /// 16 Crockford characters; always `MacID.make(fingerprint)`.
    var macID: String
    /// base64url SHA-256 of the Mac's SPKI: the pin.
    var fingerprint: String
    /// From kind 20, then from each verified kind 18.
    var name: String
    /// base64url, 32 bytes, from kind 20: resolves the TXT tag.
    var recognitionKey: String
    /// From the link or the typed address, then kind 18.
    var remotePort: Int
    /// The Mac's own list (the link's, then kind 18's), in its dial order.
    var addresses: [MacAddress]
    /// Addresses typed on this device: kept when kind 18 refreshes the Mac's own.
    var typedAddresses: [MacAddress]?
    /// The newest kind 18 taken (seconds since 1970); an older or equal one is ignored.
    var infoIssuedAt: Double
    /// The service name of the last network or Direct connection to it (a host without the tag).
    var bonjourName: String?
    /// "host|port" of the address that last won a remote dial: dialed first next time.
    var lastWorked: String?
    var pairedAt: Date
    /// "qr" or "code".
    var method: String
    var lastConnectedAt: Date?
    /// "Tailscale", "your VPN", "the internet" or "by address".
    var lastRoute: String?

    var id: String { macID }
    var fingerprintData: Data? { Base64URL.decode(fingerprint).flatMap { $0.count == 32 ? $0 : nil } }
    var recognitionKeyData: Data? { Base64URL.decode(recognitionKey).flatMap { $0.count == 32 ? $0 : nil } }
    /// Every address to dial: the Mac's, then the typed ones.
    var allAddresses: [MacAddress] { addresses + (typedAddresses ?? []) }
}

/// The saved Macs' rules, pure (checked on their own with swiftc): storage, merging, refresh,
/// the cap, what is never saved, names for display, and recognising a TXT tag.
enum SavedMacs {
    /// UserDefaults key, JSON text. `-Sill.savedMacs '<JSON>'` seeds a run (the argument domain is
    /// never written); `'[]'` empties it.
    static let defaultsKey = "Sill.savedMacs"
    static let cap = 16

    static func decode(_ text: String?) -> [SavedMac] {
        guard let text, let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([SavedMac].self, from: data) else { return [] }
        // A record whose Mac ID is not its key's is damaged or forged: it would pin one Mac and
        // name another.
        return list.filter { mac in mac.fingerprintData.map { MacID.make(fingerprint: $0) == mac.macID } ?? false }
    }

    static func encode(_ list: [SavedMac]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    /// Link-local and zone-scoped addresses only work on the network they came from, and loopback
    /// only on the Mac itself; none is ever saved (loopback stays in DEBUG builds, for the
    /// simulator's tests against a host on the same Mac).
    static func keepable(_ host: String, allowLoopback: Bool) -> Bool {
        let h = host.lowercased()
        if h.isEmpty || h.contains("%") { return false }
        if h.hasPrefix("169.254.") || h.hasPrefix("fe8") || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb") { return false }
        if h.hasPrefix("127.") || h == "::1" || h == "localhost" { return allowLoopback }
        return true
    }

    static func filtered(_ addresses: [MacAddress], allowLoopback: Bool) -> [MacAddress] {
        addresses.filter { keepable($0.host, allowLoopback: allowLoopback) }
    }

    /// After a pairing: replaces the record with the same Mac ID, then keeps at most `cap`,
    /// dropping the one used longest ago (`lastConnectedAt ?? pairedAt`).
    static func adding(_ mac: SavedMac, to list: [SavedMac]) -> [SavedMac] {
        var next = list.filter { $0.macID != mac.macID }
        next.append(mac)
        while next.count > cap {
            guard let oldest = next.indices.min(by: { (next[$0].lastConnectedAt ?? next[$0].pairedAt) < (next[$1].lastConnectedAt ?? next[$1].pairedAt) })
            else { break }
            next.remove(at: oldest)
        }
        return next
    }

    /// A verified kind 18 laid over `mac`: nil unless the signing key is the pin, the Mac ID is the
    /// saved one and it is newer than the last taken. Refreshes the name, the port and the Mac's
    /// addresses; typed addresses and the one that last worked stay. An empty list, or one from a
    /// Mac with Remote Access off, leaves the saved addresses alone: the Mac sends none while off
    /// (and none before its first look at its networks), and a device that took that at home had
    /// nothing to dial once away, after Remote Access came back on.
    static func refreshed(_ mac: SavedMac, info: MacInfo, fingerprint: Data, allowLoopback: Bool) -> SavedMac? {
        guard mac.fingerprintData == fingerprint, info.macID == mac.macID, info.issuedAt > mac.infoIssuedAt else { return nil }
        var next = mac
        let clean = SafeText.label(info.name)
        if !clean.isEmpty { next.name = clean }
        if (1...65535).contains(info.remotePort) { next.remotePort = info.remotePort }
        let addresses = filtered(info.addresses, allowLoopback: allowLoopback)
        if info.remoteAccess, !addresses.isEmpty { next.addresses = addresses }
        next.infoIssuedAt = info.issuedAt
        return next
    }

    /// What each row calls its Mac: the saved name, and "Mac mini (2)" for the second one of that
    /// name by pairing date.
    static func displayNames(_ list: [SavedMac]) -> [String: String] {
        var out: [String: String] = [:]
        var seen: [String: Int] = [:]
        for mac in list.sorted(by: { ($0.pairedAt, $0.macID) < ($1.pairedAt, $1.macID) }) {
            let n = (seen[mac.name] ?? 0) + 1
            seen[mac.name] = n
            out[mac.macID] = n == 1 ? mac.name : "\(mac.name) (\(n))"
        }
        return out
    }

    /// The saved Mac whose recognition key made `tag`, if any.
    static func recognize(tag: String?, in list: [SavedMac]) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        return list.first { mac in mac.recognitionKeyData.map { RecognitionTag.matches(tag, recognitionKey: $0) } ?? false }?.macID
    }
}
