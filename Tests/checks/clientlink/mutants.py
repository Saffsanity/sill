"""Each mutant of ClientLink.swift must fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "clientlink")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/ClientLink.swift")
orig = open(SRC).read()
MUTANTS = {
    # PR #6's five, on the new file
    "M1 no llw": ('name.hasPrefix("awdl") || name.hasPrefix("llw")', 'name.hasPrefix("awdl")'),
    "M2 numeric scope": ("guard let first = name.first, first.isLetter else { return nil }", "guard !name.isEmpty else { return nil }"),
    "M3 path contains": ("pathInterfaces.allSatisfy(peerToPeer)", "pathInterfaces.contains(where: peerToPeer)"),
    "M4 scope not decisive": ("if let scope = scope(ofEndpoint: endpoint) { return peerToPeer(scope) }",
                              "if let scope = scope(ofEndpoint: endpoint), peerToPeer(scope) { return true }"),
    "M5 scope to dot": (".prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }", '.prefix { $0 != "." }'),
    # the route's
    "R1 no anri rule": ('if name.hasPrefix("anri") || type == .wiredEthernet { return .wired }', "if type == .wiredEthernet { return .wired }"),
    "R2 first path interface wins": ("each.allSatisfy({ $0 == first })", "true"),
    "R3 scope typed by the first entry": ("interfaces.first { $0.name == scope }?.type", "interfaces.first?.type"),
    "R4 peer-to-peer checked last": ('        if peerToPeer(name) { return .direct }\n        if name.hasPrefix("anri") || type == .wiredEthernet { return .wired }\n        if type == .wifi { return .wifi }\n',
                                     '        if name.hasPrefix("anri") || type == .wiredEthernet { return .wired }\n        if type == .wifi { return .wifi }\n        if peerToPeer(name) { return .direct }\n'),
    "R5 scope ignored": ("if let scope = scope(ofEndpoint: endpoint) {\n            return route(", "if let scope = scope(ofEndpoint: endpoint), scope.isEmpty {\n            return route("),
    "R6 unknown type as Wi-Fi": ("        if type == .wifi { return .wifi }\n        return nil\n", "        if type == .wifi { return .wifi }\n        return .wifi\n"),
    "R7 stand-in dropped for a scope": ("return route(name: scope, type: interfaces.first { $0.name == scope }?.type, peerToPeer: peerToPeer)",
                                        "return route(name: scope, type: interfaces.first { $0.name == scope }?.type)"),
    "R8 wordless interfaces ignored": ("let each = interfaces.map { route(name: $0.name, type: $0.type, peerToPeer: peerToPeer) }",
                                       "let each = interfaces.map { route(name: $0.name, type: $0.type, peerToPeer: peerToPeer) }.filter { $0 != nil }"),
    "R9 anri needs the wired type": ('name.hasPrefix("anri") || type == .wiredEthernet', 'name.hasPrefix("anri") && type == .wiredEthernet'),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    assert orig.count(old) == 1, f"{name}: pattern found {orig.count(old)} times"
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", "-package-name", "sill", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:2]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
