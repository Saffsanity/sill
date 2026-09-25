import Foundation
import StreamProtocol

/// The address the pairing window gives to type on the device, under "Can’t scan? Tap Enter Code
/// Instead, and type:" (docs/remote-access-plan.md §6.2). A device that pairs away from home reaches
/// the Mac only through a VPN, so a VPN comes first (Noah, 2026-09-25: from an iPhone's hotspot
/// this network's 10.128.0.34 answered nothing, while the Tailscale address and its MagicDNS name
/// both paired). In order:
/// 1. the first VPN with a name (Tailscale's MagicDNS name), with that VPN's first IPv4 under it
///    when it has one;
/// 2. else the first VPN IPv4 ("VPN (utun6)" included), else the first VPN IPv6;
/// 3. else this network's address, as before (no VPN has an address);
/// 4. else the first address listed, as before (with no VPN and no LAN address only an internet
///    address or a test host's 127.0.0.1 can be there);
/// 5. else "this Mac’s address".
/// Names and IPs are told apart by the address parser and VPNs by their kind, never by the text (a
/// VPN host the parser refuses counts as none). Each value is written the way the parser writes it
/// back (an IPv6 address in brackets), with the address's own port when it has one (an address
/// name's), else the remote door's when it is not the one a device assumes. Pure: Foundation and
/// StreamProtocol, checked on its own with swiftc.
enum PairingWindowAddress {
    struct Choice: Equatable {
        /// What to type: "noahs-macbook-pro.tailc94091.ts.net", "100.65.142.55", "192.168.1.20".
        var primary: String
        /// The same VPN's IPv4 under its name ("or 100.65.142.55"); nil when there is none to show.
        var secondary: String?
    }

    static let placeholder = "this Mac’s address"

    /// `addresses` and `lan` are the remote status's (dial order: VPN names, VPN IPv4, VPN IPv6,
    /// this network's IPv4, then the internet's); `port` is the remote door's and `defaultPort` the
    /// one a device dials when none is typed.
    static func choose(from addresses: [MacAddress], lan: String?, port: Int, defaultPort: Int) -> Choice {
        let vpn = addresses.compactMap { a -> (address: MacAddress, parsed: ParsedAddress)? in
            guard a.kind == MacAddress.vpn, case .success(let parsed) = AddressParser.parse(a.host) else { return nil }
            return (a, parsed)
        }
        func typed(_ parsed: ParsedAddress, ownPort: Int?) -> String {
            var p = parsed
            if let ownPort { p.port = ownPort } else if port != defaultPort { p.port = port }
            return p.text
        }
        func typed(_ host: String, ownPort: Int?) -> String {
            guard case .success(let parsed) = AddressParser.parse(host) else { return host }
            return typed(parsed, ownPort: ownPort)
        }
        if let name = vpn.first(where: { $0.parsed.kind == .name }) {
            let v4 = vpn.first { $0.address.via == name.address.via && $0.parsed.kind == .ipv4 }
            return Choice(primary: typed(name.parsed, ownPort: name.address.port),
                          secondary: v4.map { typed($0.parsed, ownPort: $0.address.port) })
        }
        if let ip = vpn.first(where: { $0.parsed.kind == .ipv4 }) ?? vpn.first(where: { $0.parsed.kind == .ipv6 }) {
            return Choice(primary: typed(ip.parsed, ownPort: ip.address.port), secondary: nil)
        }
        if let lan { return Choice(primary: typed(lan, ownPort: nil), secondary: nil) }
        if let first = addresses.first { return Choice(primary: typed(first.host, ownPort: first.port), secondary: nil) }
        return Choice(primary: placeholder, secondary: nil)
    }
}
