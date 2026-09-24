import Foundation

/// Which way a connected device reaches this Mac, told from what its connection reports: over
/// peer-to-peer Wi-Fi (AWDL), or any other way. Turning Direct Wireless Connection off disconnects
/// the devices that come over AWDL (StreamServer), and only those.
///
/// Foundation only, so it is checked on its own with swiftc: no test can reach awdl0 headless
/// (docs/direct-wireless-plan.md, "Fixes after Noah's first sessions").
///
/// What a connection shows (2026-09-24, Sill.log and a local probe): an accepted connection's
/// endpoint is the device's address, and a link-local address carries the interface it lives on,
/// in the log's own text: "fe80::8425:bdff:fe62:8930%awdl0.63101" over AWDL,
/// "fe80::47b:5945:e0aa:d0ac%en0.55690" over Wi-Fi, "fe80::18fe:abff:febb:459f%anri0.61390" over
/// the USB cable, and no scope at all over IPv4 ("127.0.0.1:64431"). AWDL carries IPv6 link-local
/// addresses only, so a device on it always shows its scope. The path is the weaker witness: one
/// local connection's `availableInterfaces` listed both en0 and lo0.
enum ClientLink {
    /// awdl0 (AWDL) and llw0 (its low-latency companion) are the peer-to-peer Wi-Fi interfaces.
    /// Both report the interface type .wifi like en0, so only the name tells them apart; the
    /// device's DiscoveryPolicy.isPeerToPeer uses the same rule.
    static func isPeerToPeer(interface name: String) -> Bool {
        name.hasPrefix("awdl") || name.hasPrefix("llw")
    }

    /// The interface an endpoint's address is scoped to, read from the endpoint's description:
    /// "awdl0" from "fe80::1%awdl0.52397" (Network prints the port after a dot) or from
    /// "[fe80::1%awdl0]:52397". Nil without a scope (IPv4, a global IPv6 address) and for a numeric
    /// one ("%16"), which names no interface this rule could judge.
    static func scope(ofEndpoint description: String) -> String? {
        guard let percent = description.firstIndex(of: "%") else { return nil }
        let name = description[description.index(after: percent)...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard let first = name.first, first.isLetter else { return nil }
        return String(name)
    }

    /// Whether a device's connection runs over peer-to-peer Wi-Fi. The address's scope decides when
    /// it names an interface; without one, the path's interfaces do, and only when every one of them
    /// is peer-to-peer, so a device on any other interface is never taken for a direct one.
    /// `peerToPeer` is the interface rule; a test host adds its stand-in interface to it.
    static func runsPeerToPeer(endpoint: String, pathInterfaces: [String],
                               peerToPeer: (String) -> Bool = isPeerToPeer(interface:)) -> Bool {
        if let scope = scope(ofEndpoint: endpoint) { return peerToPeer(scope) }
        return !pathInterfaces.isEmpty && pathInterfaces.allSatisfy(peerToPeer)
    }
}
