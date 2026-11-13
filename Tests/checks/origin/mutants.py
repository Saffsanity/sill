"""H3 (OriginPolicy) mutants: each must make the check fail."""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
M = [
    ("awdl not peer-to-peer", 'if name.hasPrefix("awdl") || name.hasPrefix("llw") { return .peerToPeer }', 'if name.hasPrefix("llw") { return .peerToPeer }'),
    ("172.16/12 as 172.16/8", "(a[0] == 172 && a[1] & 0xF0 == 16)", "(a[0] == 172 && a[1] >= 16)"),
    ("on-link ignores the arrival interface", "let own = arrival.flatMap { a in kind == .lan || kind == .other ? a : nil }", "let own: String? = nil"),
    ("home door admits vpn", "o == .loopback || o == .direct || o == .lan", "o == .loopback || o == .direct || o == .lan || o == .vpn"),
    ("remote door ignores the internet switch", "case .internet: return internetAccess", "case .internet: return true"),
    ("remote door admits direct", "case .direct: return false", "case .direct: return true"),
    ("no unmapping of IPv4-mapped sources", "if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return Array(b[12...]) }", ""),
    ("link-local before the tunnel rule", "        switch kind {\n        case .peerToPeer: return .direct\n        case .tunnel: return .vpn\n        default: break\n        }\n        if IPBytes.isLinkLocal(source) { return .lan }",
     "        if IPBytes.isLinkLocal(source) { return .lan }\n        switch kind {\n        case .peerToPeer: return .direct\n        case .tunnel: return .vpn\n        default: break\n        }"),
    ("private sources are internet", "if onLink || IPBytes.isPrivate(source) { return .lan }", "if onLink { return .lan }"),
    ("scope ignored", "if let scope, !scope.isEmpty { return scope }", ""),
    # Issue #326: a connection from this Mac itself at the remote door is a relay on it.
    ("loopback at the remote door stays loopback (the rule before #326)", "        case .loopback: return .relay\n", "        case .loopback: return .loopback\n"),
    ("this Mac's own LAN address not a relay", "        case .lan: return isThisMac(remote, interfaces: interfaces) ? .relay : .lan\n", "        case .lan: return .lan\n"),
    ("every LAN source a relay", "        case .lan: return isThisMac(remote, interfaces: interfaces) ? .relay : .lan\n", "        case .lan: return .relay\n"),
    ("this Mac at its own tunnel address a relay", "        case .direct, .vpn, .internet, .relay: return o\n",
     "        case .vpn: return isThisMac(remote, interfaces: interfaces) ? .relay : .vpn\n        case .direct, .internet, .relay: return o\n"),
    ("own addresses compared with the kernel's scope bytes", "interfaces.owner[IPBytes.unscoped(source)] != nil", "interfaces.owner[source] != nil"),
    ("loopback not this Mac", "        return IPBytes.isLoopback(source) || interfaces.owner[IPBytes.unscoped(source)] != nil\n",
     "        return interfaces.owner[IPBytes.unscoped(source)] != nil\n"),
    ("a relay refused with internet access off", "        case .loopback, .lan, .vpn, .relay: return true\n",
     "        case .loopback, .lan, .vpn: return true\n        case .relay: return internetAccess\n"),
    ("the home door admits a relay", "o == .loopback || o == .direct || o == .lan", "o == .loopback || o == .direct || o == .lan || o == .relay"),
    ("a relay labelled by address", '        case .relay: return "through a relay on this Mac"\n', '        case .relay: return "by address"\n'),
]
caught = 0
for name, old, new in M:
    with tempfile.TemporaryDirectory() as t:
        src = open(os.path.join(WT, "Sources/SillHost/OriginPolicy.swift")).read()
        if old not in src: print(f"{name}: NOT APPLIED"); continue
        open(os.path.join(t, "OriginPolicy.swift"), "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        r = subprocess.run(["swiftc", "-O", os.path.join(t, "OriginPolicy.swift"), os.path.join(WT, "Sources/SillHost/InterfaceSnapshot.swift"),
                            os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if r.returncode: print(f"{name}: did not compile {r.stderr[:300]}"); continue
        out = subprocess.run([exe], capture_output=True, text=True).stdout
        f = [l for l in out.splitlines() if l.startswith("FAIL")]
        print(f"{name}: {'caught (' + str(len(f)) + ' FAIL, first: ' + f[0][5:80] + ')' if f else 'NOT CAUGHT'}")
        caught += bool(f)
print(f"mutants caught: {caught} of {len(M)}")
