"""H3 (step 5) mutants of DiscoveryPolicy's remote rules, RemoteDialPolicy and SavedMacs: each must
make at least one check FAIL."""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(WT, "iOSClient/DiscoveryPolicy.swift"); R = os.path.join(WT, "iOSClient/RemoteDialPolicy.swift")
S = os.path.join(WT, "iOSClient/SavedMacs.swift")
M = [
    (D, "remote rows at once", "guard localNetworkDenied || now >= searchingSince + networkFirst else { return [] }", "guard true else { return [] }"),
    (D, "remote rows beside a listed Mac", "return saved.filter { !listedIDs.contains($0.macID) }", "return saved"),
    (D, "no 120 s stop", "guard !listed, now < lostAt + redialWindow else { return (false, nil) }", "guard !listed else { return (false, nil) }"),
    (D, "dial while listed", "guard !listed, now < lostAt + redialWindow else { return (false, nil) }", "guard now < lostAt + redialWindow else { return (false, nil) }"),
    (D, "no path-change exemption", "if !pathChangedSinceLoss, let left = networkLeftAt {", "if let left = networkLeftAt {"),
    (D, "no network grace", "if !pathChangedSinceLoss, let left = networkLeftAt { due = max(due, left + networkGrace) }", ""),
    (D, "remembered Direct not waited for", "var due = lostAt + (rememberedDirect ? directWait : remoteWait)", "var due = lostAt + remoteWait"),
    (D, "sightings: the leave not written", "        for name in previous.since.keys where !listed.contains(name) { next.leftAt[name] = now }\n", ""),
    (D, "sightings: a leave dated at the first sighting", "for name in previous.since.keys where !listed.contains(name) { next.leftAt[name] = now }",
        "for name in previous.since.keys where !listed.contains(name) { next.leftAt[name] = previous.since[name] }"),
    (D, "flat retries", "static let remoteRetry: [Double] = [2, 4, 8, 10]", "static let remoteRetry: [Double] = [2, 2, 2, 2]"),
    (R, "lastWorked ignored", "            ordered.insert(ordered.remove(at: i), at: 0)\n", ""),
    (R, "no dedupe", "return ordered.filter { seen.insert($0.key.lowercased()).inserted }", "return ordered"),
    (R, "shared LAN not before internet", "        ordered += lans.filter { shared($0) && !loopback($0) }\n        ordered += internet.filter(\\.isName) + internet.filter { !$0.isName }\n",
        "        ordered += internet.filter(\\.isName) + internet.filter { !$0.isName }\n        ordered += lans.filter { shared($0) && !loopback($0) }\n"),
    (R, "IPv6 VPN before IPv4", "ordered += vpns.filter(\\.isName) + vpns.filter { !$0.isName && !$0.isIPv6 } + vpns.filter(\\.isIPv6)", "ordered += vpns.filter(\\.isName) + vpns.filter(\\.isIPv6) + vpns.filter { !$0.isName && !$0.isIPv6 }"),
    (R, "LAN pin mismatch counts", "return candidate.kind == MacAddress.lan && !isVPNAddress(candidate.host) ? nil : .wrongMac", "return .wrongMac"),
    (R, "priority: refused before revoked", "static let priority: [Failure] = [.wrongMac, .revoked, .remoteOff, .busy, .refused,", "static let priority: [Failure] = [.wrongMac, .refused, .revoked, .remoteOff, .busy,"),
    (R, "VPN off never detected", "return vpnAddress && usedTunnel == false ? .vpnOff : .noAnswer", "return .noAnswer"),
    (R, "ts.net not found is not VPN off", "return isTailscaleName(candidate.host) ? .vpnOff : .nameNotFound", "return .nameNotFound"),
    (R, "CGNAT range too wide", "if let a = IPv4.parse(host) { return a[0] == 100 && a[1] & 0xC0 == 64 }", "if let a = IPv4.parse(host) { return a[0] == 100 }"),
    (S, "no cap", "static let cap = 16", "static let cap = 99"),
    (S, "cap drops the newest", "guard let oldest = next.indices.min(by:", "guard let oldest = next.indices.max(by:"),
    (S, "loopback always kept", "if h.hasPrefix(\"127.\") || h == \"::1\" || h == \"localhost\" { return allowLoopback }", ""),
    (S, "link-local kept", "if h.hasPrefix(\"169.254.\") || h.hasPrefix(\"fe8\")", "if h.hasPrefix(\"169.254.x\") || h.hasPrefix(\"fe8x\")"),
    (S, "refresh takes an equal issuedAt", "info.issuedAt > mac.infoIssuedAt", "info.issuedAt >= mac.infoIssuedAt"),
    (S, "refresh with another key", "guard mac.fingerprintData == fingerprint, info.macID == mac.macID", "guard info.macID == mac.macID"),
    (S, "refresh drops typed addresses", "        next.infoIssuedAt = info.issuedAt\n", "        next.infoIssuedAt = info.issuedAt\n        next.typedAddresses = nil\n"),
    (S, "forged records kept", "return list.filter { mac in mac.fingerprintData.map { MacID.make(fingerprint: $0) == mac.macID } ?? false }", "return list"),
    (S, "no (2) suffix", "out[mac.macID] = n == 1 ? mac.name : \"\\(mac.name) (\\(n))\"", "out[mac.macID] = mac.name"),
    (S, "an empty kind 18 list replaces", "if info.remoteAccess, !addresses.isEmpty { next.addresses = addresses }", "next.addresses = addresses"),
    (S, "a Remote Access off list replaces", "if info.remoteAccess, !addresses.isEmpty { next.addresses = addresses }", "if !addresses.isEmpty { next.addresses = addresses }"),
    (S, "an empty list after filtering replaces", "let addresses = filtered(info.addresses, allowLoopback: allowLoopback)\n        if info.remoteAccess, !addresses.isEmpty", "let addresses = filtered(info.addresses, allowLoopback: allowLoopback)\n        if info.remoteAccess, !info.addresses.isEmpty"),
    (R, "a scan starts over a running pairing", "        if busy { return false }\n", ""),
    (R, "a held code starts by itself", "return !(failed && !tapped && secret == lastScanned)", "return true"),
    (R, "a tap never retries", "return !(failed && !tapped && secret == lastScanned)", "return !(failed && secret == lastScanned)"),
    (R, "any code is held after a failure", "return !(failed && !tapped && secret == lastScanned)", "return !(failed && !tapped)"),
    # Pairing at home (docs/home-pairing-plan.md, step 4): the home model and the saved Macs' home fields.
    (D, "S4 homeEnd: removed misspelt", "        if goodbye == \"removed\" { return .removed }", "        if goodbye == \"remove\" { return .removed }"),
    (D, "S4 homeEnd: pairingRequired misspelt", "        if goodbye == \"pairingRequired\" { return .pairingRequired }", "        if goodbye == \"pairingrequired\" { return .pairingRequired }"),
    (D, "S4 askAnswer: the cable's method misspelt", "guard method == \"cable\", askedCable", "guard method == \"usb\", askedCable"),
    (D, "S4 askAnswer: shown misspelt", "        case \"shown\"?: return .shown", "        case \"show\"?: return .shown"),
    (D, "S4 askAnswer: busy misspelt", "        case \"busy\"?: return .busy(", "        case \"Busy\"?: return .busy("),
    (D, "S4 rowWord: a revoked Mac dialed pinned", "            if saved && !revoked && !newKey { return .method(method) }", "            if saved && !newKey { return .method(method) }"),
    (D, "S4 homeDial: a homeTLS Mac dialed plain in DEBUG", "            return debug && !homeTLS ? .plain : .updateSill", "            return debug ? .plain : .updateSill"),
    (S, "S4 adding forgets homeTLS", "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n", ""),
    (S, "S4 seenOverTLS marks nothing", "            next.homeTLS = true\n            return next\n        }\n    }\n\n    /// `revoked`", "            return next\n        }\n    }\n\n    /// `revoked`"),
    (S, "S4 revoking marks nothing", "            next.revoked = true\n", ""),
    (S, "S4 recognize: any tag names the first Mac", "        return list.first { mac in mac.recognitionKeyData.map { RecognitionTag.matches(tag, recognitionKey: $0) } ?? false }?.macID", "        return list.first?.macID"),
    (S, "S4 seenOverTLS marks every Mac", "            guard ids.contains(mac.macID) else { return mac }\n            var next = mac\n            next.homeTLS = true", "            var next = mac\n            next.homeTLS = true"),
    (S, "S4 seenOverTLS reports a change that is none", "        guard list.contains(where: { ids.contains($0.macID) && $0.homeTLS != true }) else { return nil }", "        guard list.contains(where: { ids.contains($0.macID) }) else { return nil }"),
    (S, "S4 revoking marks every Mac", "            guard mac.macID == id else { return mac }\n            var next = mac\n            next.revoked = true", "            var next = mac\n            next.revoked = true"),
    (S, "S4 revoking twice", "        guard list.contains(where: { $0.macID == id && $0.revoked != true }) else { return nil }", "        guard list.contains(where: { $0.macID == id }) else { return nil }"),
    (S, "S4 forgettingHomeTLS sets false", "            next.homeTLS = nil\n", "            next.homeTLS = false\n"),
    (S, "S4 forgettingHomeTLS forgets nothing", "            next.homeTLS = nil\n", ""),
]
caught = 0
for f, name, old, new in M:
    src = open(f).read()
    if old not in src: print(f"{name}: NOT APPLIED"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, os.path.basename(f)); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        args = [os.path.join(HERE, "build.sh"), WT, exe, mf if f == D else D, mf if f == R else R, mf if f == S else S]
        subprocess.run(args, capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        out = subprocess.run([exe], capture_output=True, text=True).stdout
        fl = [l for l in out.splitlines() if l.startswith("FAIL")]
        print(f"{name}: {'caught (' + str(len(fl)) + ' FAIL, first: ' + fl[0][5:80] + ')' if fl else 'NOT CAUGHT'}")
        caught += bool(fl)
print(f"mutants caught: {caught} of {len(M)}")
