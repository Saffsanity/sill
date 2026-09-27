"""Mutants of PairingWindowAddress.choose and isTailscale: each must make the check print a FAIL."""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/PairingWindowAddress.swift")
NAME = "        if let name = vpn.first(where: { $0.parsed.kind == .name }) {\n"
LANLINE = "        if let lan {\n"
LAN = ("        if let lan {\n"
       "            let shown = typed(lan, ownPort: nil)\n"
       "            return Choice(primary: shown, secondary: other == shown ? nil : other)\n"
       "        }\n")
OTHER = "        if let other { return Choice(primary: other, secondary: nil) }\n"
FIRST = "        if let first = addresses.first { return Choice(primary: typed(first.host, ownPort: first.port), secondary: nil) }\n"
PORT = "            if let ownPort { p.port = ownPort } else if port != defaultPort { p.port = port }\n"
TS = ("        if let tailscale = vpn.first(where: { $0.parsed.kind == .ipv4 && isTailscale($0.parsed) })\n"
      "            ?? vpn.first(where: { $0.parsed.kind == .ipv6 && isTailscale($0.parsed) }) {\n")
OTHERSEL = "        let other = (vpn.first(where: { $0.parsed.kind == .ipv4 }) ?? vpn.first(where: { $0.parsed.kind == .ipv6 }))\n"
V4 = "            return octets.count == 4 && octets[0] == 100 && octets[1] & 0xC0 == 64\n"
V6 = "            return withUnsafeBytes(of: bytes) { Array($0.prefix(6)) } == [0xFD, 0x7A, 0x11, 0x5C, 0xA1, 0xE0]\n"
# The window's first rule, for the "this network's address first" mutant: the LAN (alone) before everything.
LANFIRST = "        if let lan { return Choice(primary: typed(lan, ownPort: nil), secondary: nil) }\n"
M = [
    # The name (unchanged from ae7f5c9).
    ("this network's address first (the window before)", NAME, LANFIRST + NAME),
    ("any VPN's IPv4 under the name", "$0.address.via == name.address.via && $0.parsed.kind == .ipv4", "$0.parsed.kind == .ipv4"),
    ("an IPv6 may be the line under the name", "$0.address.via == name.address.via && $0.parsed.kind == .ipv4", "$0.address.via == name.address.via && $0.parsed.kind != .name"),
    ("no line under the name", "secondary: v4.map { typed($0.parsed, ownPort: $0.address.port) })", "secondary: nil)"),
    ("the last VPN name, not the first", "if let name = vpn.first(where: { $0.parsed.kind == .name })", "if let name = vpn.last(where: { $0.parsed.kind == .name })"),
    ("names told by their text (.ts.net), not the parser", "if let name = vpn.first(where: { $0.parsed.kind == .name })", "if let name = vpn.first(where: { $0.address.host.hasSuffix(\".ts.net\") })"),
    ("any kind counts as a VPN", "guard a.kind == MacAddress.vpn, case .success(let parsed)", "guard case .success(let parsed)"),
    # Tailscale's addresses.
    ("any VPN's IP takes this network's place (ae7f5c9's rule)", TS,
     "        if let tailscale = vpn.first(where: { $0.parsed.kind == .ipv4 })\n            ?? vpn.first(where: { $0.parsed.kind == .ipv6 }) {\n"),
    ("Tailscale's IPs never take this network's place", TS,
     "        if let tailscale = vpn.first(where: { $0.parsed.kind == .ipv4 && isTailscale($0.parsed) && false })\n            ?? vpn.first(where: { $0.parsed.kind == .ipv6 && isTailscale($0.parsed) && false }) {\n"),
    ("a Tailscale IPv6 before its IPv4", TS,
     "        if let tailscale = vpn.first(where: { $0.parsed.kind == .ipv6 && isTailscale($0.parsed) })\n            ?? vpn.first(where: { $0.parsed.kind == .ipv4 && isTailscale($0.parsed) }) {\n"),
    ("no Tailscale IPv6", TS,
     "        if let tailscale = vpn.first(where: { $0.parsed.kind == .ipv4 && isTailscale($0.parsed) }) {\n"),
    ("a Tailscale IP with this network's address under it", "return Choice(primary: typed(tailscale.parsed, ownPort: tailscale.address.port), secondary: nil)",
     "return Choice(primary: typed(tailscale.parsed, ownPort: tailscale.address.port), secondary: lan.map { typed($0, ownPort: nil) })"),
    ("100.64/10 read as 100/8", V4, "            return octets.count == 4 && octets[0] == 100\n"),
    ("100.64/10 read as 100.0/9 (0-127)", V4, "            return octets.count == 4 && octets[0] == 100 && octets[1] & 0x80 == 0\n"),
    ("100.64/10 without its upper end (64-255)", V4, "            return octets.count == 4 && octets[0] == 100 && octets[1] >= 64\n"),
    ("100.64/10 one short at the top (64-126)", V4, "            return octets.count == 4 && octets[0] == 100 && (64...126).contains(octets[1])\n"),
    ("the first octet unchecked (x.64/10)", V4, "            return octets.count == 4 && octets[1] & 0xC0 == 64\n"),
    ("fd7a:115c:a1e0::/48 read as /32", V6, "            return withUnsafeBytes(of: bytes) { Array($0.prefix(4)) } == [0xFD, 0x7A, 0x11, 0x5C]\n"),
    ("fd7a:115c:a1e0::/48 read as fd7a::/16", V6, "            return withUnsafeBytes(of: bytes) { Array($0.prefix(2)) } == [0xFD, 0x7A]\n"),
    ("every IPv6 counts as Tailscale's", V6, "            return true\n"),
    ("names count as Tailscale's", "        case .name:\n            return false\n", "        case .name:\n            return true\n"),
    # Another VPN under this network's address.
    ("no line under this network's address", "return Choice(primary: shown, secondary: other == shown ? nil : other)", "return Choice(primary: shown, secondary: nil)"),
    ("another VPN first, this network's address under it (the prototype's order)", "return Choice(primary: shown, secondary: other == shown ? nil : other)",
     "return Choice(primary: other ?? shown, secondary: other == nil ? nil : shown)"),
    ("the line under may say the address again", "secondary: other == shown ? nil : other)", "secondary: other)"),
    ("another VPN's IPv6 before its IPv4", OTHERSEL,
     "        let other = (vpn.first(where: { $0.parsed.kind == .ipv6 }) ?? vpn.first(where: { $0.parsed.kind == .ipv4 }))\n"),
    ("another VPN's IPv6 never", OTHERSEL, "        let other = (vpn.first(where: { $0.parsed.kind == .ipv4 }))\n"),
    ("another VPN's last IPv4, not its first", OTHERSEL,
     "        let other = (vpn.last(where: { $0.parsed.kind == .ipv4 }) ?? vpn.first(where: { $0.parsed.kind == .ipv6 }))\n"),
    ("another VPN's IP without the door's port", "            .map { typed($0.parsed, ownPort: $0.address.port) }\n", "            .map { $0.parsed.text }\n"),
    ("no other VPN without a LAN address", OTHER, ""),
    # Ports and fallbacks (unchanged from ae7f5c9).
    ("the port always", PORT, "            if let ownPort { p.port = ownPort } else { p.port = port }\n"),
    ("the port never", PORT, "            if let ownPort { p.port = ownPort }\n"),
    ("an address's own port ignored", PORT, "            if port != defaultPort { p.port = port }\n"),
    ("no fallback to the first address listed", FIRST, ""),
    ("the first address listed before this network's", LAN, FIRST + LAN),
    ("no placeholder", "return Choice(primary: placeholder, secondary: nil)", "return Choice(primary: \"\", secondary: nil)"),
]
caught = 0
for name, old, new in M:
    src = open(F).read()
    if src.count(old) != 1: print(f"{name}: NOT APPLIED ({src.count(old)} matches)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "PairingWindowAddress.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        b = subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile\n{b.stdout}{b.stderr}"); continue
        out = subprocess.run([exe], capture_output=True, text=True).stdout
        fl = [l for l in out.splitlines() if l.startswith("FAIL")]
        print(f"{name}: {'caught (' + str(len(fl)) + ' FAIL, first: ' + fl[0][5:100] + ')' if fl else 'NOT CAUGHT'}")
        caught += bool(fl)
print(f"mutants caught: {caught} of {len(M)}")
