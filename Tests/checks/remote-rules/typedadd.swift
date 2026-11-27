// An address typed onto a saved Mac's record without pairing (Add an Address… on its row,
// 2026-11-27, branch `typed-address-without-repairing`; docs/remote-access-plan.md §7.2): what
// SavedMacs.addingTyped adds and refuses, where the added address sits in the record and in the
// dial, and what survives after it (a kind 18's refresh, the record's encoding). A function
// main.swift calls.
import Foundation
#if canImport(Darwin)
import Darwin
#endif

func typedAdd() {
    let day = 86_400.0
    let t0 = 1_794_000_000.0
    let fp = Data((0..<32).map { UInt8($0 &+ 41) })
    let id = MacID.make(fingerprint: fp)
    let wifi = MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi‑Fi")
    let tsName = MacAddress(host: "mac-mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale")
    /// A typed address as RemoteDialPolicy.address(for:) makes one: a port-forwarded name.
    let forwarded = MacAddress(host: "mac.example.net", port: 7456, kind: MacAddress.internet, via: "")
    let hotspot: [(address: [UInt8], prefix: Int)] = [([172, 20, 10, 2], 28)]
    func record(_ typed: [MacAddress]?, remembered: [RememberedAddress]? = nil) -> SavedMac {
        SavedMac(macID: id, fingerprint: Base64URL.encode(fp), name: "Mac mini",
                 recognitionKey: Base64URL.encode(Data(repeating: 9, count: 32)), remotePort: 7455,
                 addresses: [tsName, wifi], typedAddresses: typed, infoIssuedAt: 0, bonjourName: nil,
                 lastWorked: nil, pairedAt: Date(timeIntervalSince1970: t0), method: "qr",
                 lastConnectedAt: nil, lastRoute: nil, homeTLS: nil, revoked: nil, newKey: nil,
                 addressesListedAt: t0, rememberedAddresses: remembered)
    }
    func info(_ list: [MacAddress], issued: Double) -> MacInfo {
        MacInfo(macID: id, name: "Mac mini", issuedAt: issued, remoteAccess: true, remotePort: 7455,
                internet: false, addresses: list)
    }
    /// The dial a tap on the Remote row makes (StreamClient+Remote.dialSaved).
    func dial(_ m: SavedMac, at now: Double) -> [R.Candidate] {
        R.order(m.allAddresses, remembered: SavedMacs.remembered(m, now: now), remotePort: m.remotePort,
                lastWorked: m.lastWorked, localIPv4: hotspot)
    }
    func keys(_ cs: [R.Candidate]) -> [String] { cs.map(\.key) }
    /// The destination `addingTyped` compares: host at its effective port.
    func key(_ host: String, _ port: Int? = nil) -> String { "\(host.lowercased())|\(port ?? 7455)" }

    // MARK: Added

    var list = [record(nil)]
    var add = SavedMacs.addingTyped(forwarded, to: id, in: list, allowLoopback: false, now: t0)
    guard case .added(let added) = add else { print("FAIL typed add: a new address is added"); fails += 1; return }
    check("typed add: one typed address, last in the record",
          added[0].typedAddresses == [forwarded] && added[0].addresses == [tsName, wifi])
    check("typed add: the record's list is what changed, in place",
          added.count == 1 && added[0].macID == id)
    check("typed add: the record decodes with it",
          SavedMacs.decode(SavedMacs.encode(added)) == added)
    check("typed add: it is dialed, at its own port",
          keys(dial(added[0], at: t0)).contains(key("mac.example.net", 7456)))
    list = added

    // The second one goes after the first, so a list someone grows keeps its order.
    let second = MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale")
    add = SavedMacs.addingTyped(second, to: id, in: list, allowLoopback: false, now: t0)
    check("typed add: a second one goes after the first",
          { if case .added(let l) = add { return l[0].typedAddresses == [forwarded, second] }; return false }())

    // MARK: One destination once

    check("typed add: the same address again is refused",
          SavedMacs.addingTyped(forwarded, to: id, in: list, allowLoopback: false, now: t0) == .alreadyDialed)
    check("typed add: the same host at the record's port is the same destination",
          SavedMacs.addingTyped(MacAddress(host: "mac.example.net", kind: MacAddress.internet, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) == .alreadyDialed)
    check("typed add: the host's case is not a new destination",
          SavedMacs.addingTyped(MacAddress(host: "MAC.example.net", port: 7456, kind: MacAddress.internet, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) == .alreadyDialed)
    // A host without a port dials the record's own port (§7.5): with one typed at another port, it
    // is a destination of its own, and the second one of it is refused.
    let portless = MacAddress(host: "mac.example.net", kind: MacAddress.internet, via: "")
    var addPortless = SavedMacs.addingTyped(portless, to: id, in: list, allowLoopback: false, now: t0)
    check("typed add: a host without a port is a destination of its own, the record's",
          { if case .added(let l) = addPortless { return l[0].typedAddresses?.count == 2 }; return false }())
    if case .added(let l) = addPortless {
        check("typed add: the same destination again, without a port",
              SavedMacs.addingTyped(portless, to: id, in: l, allowLoopback: false, now: t0) == .alreadyDialed)
    }
    check("typed add: the same host at another port is added",
          SavedMacs.addingTyped(MacAddress(host: "mac.example.net", port: 7457, kind: MacAddress.internet, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) != .alreadyDialed)
    check("typed add: one of the Mac's own list is refused",
          SavedMacs.addingTyped(MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi‑Fi"),
                                to: id, in: list, allowLoopback: false, now: t0) == .alreadyDialed)
    check("typed add: a remembered address still within its season is refused",
          SavedMacs.addingTyped(MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
                                to: id, in: [record([forwarded], remembered: [RememberedAddress(
                                    address: MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
                                    listedAt: t0 - SavedMacs.rememberFor + day)])],
                                allowLoopback: false, now: t0) == .alreadyDialed)
    check("typed add: a remembered address past its season is added",
          SavedMacs.addingTyped(MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
                                to: id, in: [record([forwarded], remembered: [RememberedAddress(
                                    address: MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
                                    listedAt: t0 - SavedMacs.rememberFor - 1)])],
                                allowLoopback: false, now: t0) != .alreadyDialed)

    // MARK: Never saved

    check("typed add: a link-local IPv4 address is refused",
          SavedMacs.addingTyped(MacAddress(host: "169.254.100.5", kind: MacAddress.lan, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) == .notKeepable)
    check("typed add: a link-local IPv6 address is refused",
          SavedMacs.addingTyped(MacAddress(host: "fe80::1234", kind: MacAddress.lan, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) == .notKeepable)
    check("typed add: loopback is refused in Release",
          SavedMacs.addingTyped(MacAddress(host: "127.0.0.1", kind: MacAddress.lan, via: ""),
                                to: id, in: list, allowLoopback: false, now: t0) == .notKeepable)
    check("typed add: loopback is kept in DEBUG, for the simulator's hosts",
          SavedMacs.addingTyped(MacAddress(host: "127.0.0.1", kind: MacAddress.lan, via: ""),
                                to: id, in: list, allowLoopback: true, now: t0) != .notKeepable)

    // MARK: The cap

    let seven = (0..<7).map { MacAddress(host: "host\($0).example.net", kind: MacAddress.internet, via: "") }
    var capped = SavedMacs.addingTyped(MacAddress(host: "mac.example.net", kind: MacAddress.internet, via: ""),
                                       to: id, in: [record(seven)], allowLoopback: false, now: t0)
    check("typed add: the eighth typed address is added",
          { if case .added(let l) = capped { return l[0].typedAddresses?.count == 8 }; return false }())
    capped = SavedMacs.addingTyped(MacAddress(host: "another.example.net", kind: MacAddress.internet, via: ""),
                                   to: id, in: [record(seven + [forwarded])], allowLoopback: false, now: t0)
    check("typed add: the ninth is refused", capped == .full)

    // MARK: No such Mac, other records untouched

    check("typed add: a Mac ID no record has is missing",
          SavedMacs.addingTyped(forwarded, to: MacID.make(fingerprint: Data(repeating: 1, count: 32)),
                                in: list, allowLoopback: false, now: t0) == .missing)
    let other = SavedMac(macID: MacID.make(fingerprint: Data(repeating: 2, count: 32)),
                         fingerprint: Base64URL.encode(Data(repeating: 2, count: 32)), name: "Studio",
                         recognitionKey: Base64URL.encode(Data(repeating: 3, count: 32)), remotePort: 7455,
                         addresses: [wifi], typedAddresses: nil, infoIssuedAt: 0, bonjourName: nil, lastWorked: nil,
                         pairedAt: Date(timeIntervalSince1970: t0), method: "qr", lastConnectedAt: nil, lastRoute: nil)
    add = SavedMacs.addingTyped(forwarded, to: id, in: [other, record(nil)], allowLoopback: false, now: t0)
    check("typed add: another record in the list is untouched",
          { if case .added(let l) = add { return l[0] == other && l[1].typedAddresses?.count == 1 }; return false }())

    // MARK: What survives after it

    /// A kind 18 at `now`, with the Mac's own list as it gives it.
    func refresh(_ m: SavedMac, _ macList: [MacAddress], at now: Double) -> SavedMac {
        SavedMacs.refreshed(m, info: info(macList, issued: now - 7), fingerprint: fp,
                            allowLoopback: false, now: now) ?? m
    }
    var refreshed = refresh(list[0], [wifi], at: t0 + day)
    check("typed add: a kind 18's refresh keeps the typed address",
          refreshed.typedAddresses == [forwarded] && refreshed.addresses == [wifi])
    // The dial's own order (RemoteDialPolicy) puts the internet name before the LAN address this
    // hotspot does not share; both are there.
    let afterRefresh = keys(dial(refreshed, at: t0 + day))
    check("typed add: the dial after the refresh still has it, with the Mac's own list",
          afterRefresh.contains(key("192.168.1.20")) && afterRefresh.contains(key("mac.example.net", 7456)))
}
