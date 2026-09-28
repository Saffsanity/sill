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
    /// This device has seen the Mac's home door speak TLS: a TXT record with `p`, or a TLS session
    /// at home (docs/home-pairing-plan.md §7.3). Its rows are then dialed only over TLS, in DEBUG
    /// too, and a row of it without `p` reads "Update Sill" (no downgrade: its own Sill never goes
    /// back to plain, and someone may be replaying its tag). Kept by a new pairing with the same
    /// Mac (`SavedMacs.adding`). Optional, so a record from before it decodes.
    var homeTLS: Bool?
    /// The Mac removed this device (goodbye `removed`), or refused its key on a pinned home dial
    /// (-9825, -9829): no automatic reconnect, its row reads "Not paired" ("Wired" on the cable),
    /// and a tap asks, pinned to this record's key. Cleared by the next pairing, whose record
    /// replaces this one. Optional, so a record from before it decodes.
    var revoked: Bool?
    /// Another key answered as this Mac on a pinned home dial (-9808) and no other row of it was
    /// left (DiscoveryPolicy.afterPinRefused): the Mac was set up again (Noah, 2026-09-27: Sill for
    /// Mac 0.4.0 made a new key). No automatic reconnect, its rows read "Not paired", and a tap
    /// asks with any key, the Mac proving itself with its code; the pairing that follows replaces
    /// this record (`replacingNewKey`). Optional, so a record from before it decodes.
    var newKey: Bool?

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
    /// dropping the one used longest ago (`lastConnectedAt ?? pairedAt`). The record it replaces
    /// is the same Mac (the Mac ID is its key's), so what this device has seen of its home door
    /// stays (`homeTLS`): a pairing from away after a removal must not let a plain row of that Mac
    /// be dialed again. `revoked` goes with the old record.
    static func adding(_ mac: SavedMac, to list: [SavedMac]) -> [SavedMac] {
        var mac = mac
        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }
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

    /// `homeTLS` set on the Macs of `ids`: seen with `p`, or a TLS session at home with them ran
    /// (docs/home-pairing-plan.md §7.3). Nil when none changes, so a caller writes only a change.
    static func seenOverTLS(_ ids: Set<String>, in list: [SavedMac]) -> [SavedMac]? {
        guard list.contains(where: { ids.contains($0.macID) && $0.homeTLS != true }) else { return nil }
        return list.map { mac in
            guard ids.contains(mac.macID) else { return mac }
            var next = mac
            next.homeTLS = true
            return next
        }
    }

    /// `revoked` set on `id`: the Mac removed this device (goodbye `removed`), or refused its key on
    /// a pinned home dial (§7.6). Nil when `id` is not saved or is revoked already.
    static func revoking(_ id: String, in list: [SavedMac]) -> [SavedMac]? {
        guard list.contains(where: { $0.macID == id && $0.revoked != true }) else { return nil }
        return list.map { mac in
            guard mac.macID == id else { return mac }
            var next = mac
            next.revoked = true
            return next
        }
    }

    /// `newKey` set on `id` (SavedMac.newKey). Nil when `id` is not saved or is marked already.
    static func markingNewKey(_ id: String, in list: [SavedMac]) -> [SavedMac]? {
        guard list.contains(where: { $0.macID == id && $0.newKey != true }) else { return nil }
        return list.map { mac in
            guard mac.macID == id else { return mac }
            var next = mac
            next.newKey = true
            return next
        }
    }

    /// After a pairing that the re-pairing of `old` started (a tap on a row of a Mac marked
    /// `newKey`): `old` is gone once the Mac it paired with is saved as `new`, another Mac ID (its
    /// new key), since the person paired that Mac, by its code, in its place. Nothing changes when
    /// `old` is not marked or is `new` itself (the same key answered after all: `adding` replaced
    /// it already).
    static func replacingNewKey(old: String, new: String, in list: [SavedMac]) -> [SavedMac] {
        guard old != new, list.contains(where: { $0.macID == new }),
              list.contains(where: { $0.macID == old && $0.newKey == true }) else { return list }
        return list.filter { $0.macID != old }
    }

    /// DEBUG `-SillForgetHomeTLS 1` (§3.4, §7.9): `homeTLS` cleared on every saved Mac, so a DEBUG
    /// build dials an older Sill.app (another branch's) plainly again.
    static func forgettingHomeTLS(_ list: [SavedMac]) -> [SavedMac] {
        list.map { mac in
            var next = mac
            next.homeTLS = nil
            return next
        }
    }

    /// The saved Mac whose recognition key made `tag`, if any.
    static func recognize(tag: String?, in list: [SavedMac]) -> String? {
        guard let tag, !tag.isEmpty else { return nil }
        return list.first { mac in mac.recognitionKeyData.map { RecognitionTag.matches(tag, recognitionKey: $0) } ?? false }?.macID
    }
}
