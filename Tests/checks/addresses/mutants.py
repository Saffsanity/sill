"""H3 (step 3) mutants of AddressList and PairingWindow."""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
A = os.path.join(WT, "Sources/SillHost/AddressList.swift"); P = os.path.join(WT, "Sources/SillHost/PairingWindow.swift")
M = [
    (A, "unnamed tunnels shown", "services.filter { !$0.name.isEmpty && isTunnel($0.interface) }", "services.filter { isTunnel($0.interface) }"),
    (A, "temporary IPv6 shown", "return e.flags & IPv6Entry.temporary == 0 && e.flags & IPv6Entry.deprecated == 0", "return e.flags & IPv6Entry.deprecated == 0"),
    (A, "deprecated IPv6 shown", "return e.flags & IPv6Entry.temporary == 0 && e.flags & IPv6Entry.deprecated == 0", "return e.flags & IPv6Entry.temporary == 0"),
    (A, "100.64/10 on a LAN shown", "return onTunnel || !IPBytes.isCarrierShared(b)", "return true"),
    (A, "global IPv6 without the switch", "        if input.internet {\n            if let name = input.addressName {", "        if let v6 = stableGlobalV6(input) { add(MacAddress(host: v6, kind: MacAddress.internet, via: \"IPv6\")) }\n        if input.internet {\n            if let name = input.addressName {"),
    (A, "no cap", "static let maxCount = 12", "static let maxCount = 99"),
    (A, "LAN before VPN", "        if let lan = primaryLAN(input), let a = lan.ipv4.first(where: { routableV4($0, onTunnel: false) }) {", "        if false, let lan = primaryLAN(input), let a = lan.ipv4.first(where: { routableV4($0, onTunnel: false) }) {"),
    (A, "MagicDNS without ts.net", ".first(where: { $0.lowercased().hasSuffix(\".ts.net\") })", ".first"),
    (P, "no spacing", "if now < w.nextAllowedAt { return .busy(retryAfter: w.nextAllowedAt - now) }", ""),
    (P, "no per-source rule", "        if let last = w.lastAttemptBySource[source], now - last < Self.sourceSpacing {\n            return .busy(retryAfter: Self.sourceSpacing - (now - last))\n        }", ""),
    (P, "six failures", "static let maxFailures = 5", "static let maxFailures = 6"),
    (P, "reusable window", "            state = .closed(.used)\n", ""),
    (P, "no expiry", "        if now >= w.expiresAt {\n            state = .closed(.expired)\n            return .closed(.expired)\n        }", ""),
    (P, "code proof without K accepted as wrong, not busy", "            guard let k = w.codeKey else { return .busy(retryAfter: 1) }", "            guard let k = w.codeKey else { return .reject(triesLeft: 9) }"),
    (P, "flat spacing", "static let spacing: [Double] = [1, 2, 4, 8]", "static let spacing: [Double] = [1, 1, 1, 1]"),
]
caught = 0
for f, name, old, new in M:
    src = open(f).read()
    if old not in src: print(f"{name}: NOT APPLIED"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, os.path.basename(f)); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        args = [os.path.join(HERE, "build.sh"), WT, exe] + ([mf] if f == A else [A, mf])
        subprocess.run(args, capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        out = subprocess.run([exe], capture_output=True, text=True).stdout
        fl = [l for l in out.splitlines() if l.startswith("FAIL")]
        print(f"{name}: {'caught (' + str(len(fl)) + ' FAIL, first: ' + fl[0][5:90] + ')' if fl else 'NOT CAUGHT'}")
        caught += bool(fl)
print(f"mutants caught: {caught} of {len(M)}")
