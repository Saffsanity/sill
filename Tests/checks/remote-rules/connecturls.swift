import Foundation

func connectionLinks() {
    let mac = savedMac(1)
    var other = savedMac(2)
    other.remotePort = 8443

    func link(_ suffix: String) -> ConnectionLink? {
        URL(string: "sill://connect" + suffix).flatMap(ConnectionLink.parse)
    }

    let copied = ConnectionLink.url(for: mac.macID).flatMap(ConnectionLink.parse)
    check("a copied connection link selects the exact Mac among Macs with the same name",
          copied?.target(in: [other, mac]) == .success(mac))
    check("a Mac ID is case insensitive and must use the Mac ID alphabet",
          link("?mac=\(mac.macID.lowercased())") == copied && ConnectionLink.url(for: "not-an-id") == nil)
    check("a connection link can select a saved IP or a typed name with its port",
          link("?address=100.64.0.9")?.target(in: [mac]) == .success(mac)
          && link("?address=HOME.example.net:7455")?.target(in: [other, mac]) == .success(mac))
    check("an address shared by saved Macs needs a port or a Mac ID to disambiguate",
          link("?address=100.64.0.9")?.target(in: [other, mac]) == .failure(.ambiguous)
          && link("?address=100.64.0.9:8443")?.target(in: [other, mac]) == .success(other))
    other.addresses = [MacAddress(host: "fd00::1", port: 443, kind: MacAddress.lan, via: "IPv6")]
    check("a bracketed IPv6 address uses the stored explicit port instead of the remote port",
          link("?address=%5Bfd00:0:0:0:0:0:0:1%5D:443")?.target(in: [other]) == .success(other)
          && link("?address=%5Bfd00::1%5D:8443")?.target(in: [other]) == .failure(.missing))
    check("unknown IDs and addresses cannot start a connection",
          copied?.target(in: [other]) == .failure(.missing)
          && link("?address=other.example.net")?.target(in: [mac]) == .failure(.missing))
    var revoked = mac; revoked.revoked = true
    var changedKey = mac; changedKey.newKey = true
    var noPin = mac; noPin.fingerprint = ""
    check("a link requires a current pairing and a saved pin",
          [revoked, changedKey, noPin].allSatisfy { copied?.target(in: [$0]) == .failure(.needsPairing) })

    for suffix in ["", "?mac", "?mac=123", "?mac=OOOOOOOOOOOOOOOO", "?address=",
                   "?address=1.2.3", "?address=mac.example.net:0", "?address=mac.example.net:65536",
                   "?address=fe80::1%25en0", "?address=mac.example.net&address=other.example.net",
                   "?mac=\(mac.macID)&address=mac.example.net", "/other?mac=\(mac.macID)",
                   ":7455?mac=\(mac.macID)", "?mac=\(mac.macID)#other"] {
        check("refuse malformed connection link \(suffix)", link(suffix) == nil)
    }
    check("app-only and pairing links are separate from connection links",
          ConnectionLink.parse(URL(string: "sill://")!) == nil
          && ConnectionLink.parse(URL(string: "sill://pair?mac=\(mac.macID)")!) == nil)
}
