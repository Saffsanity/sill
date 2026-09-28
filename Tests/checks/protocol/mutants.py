"""H3 mutants: each copies Sources/StreamProtocol, applies one mutation, compiles it with the check
and expects at least one FAIL. usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    ("Damm table entry swapped", "Pairing.swift", "[7, 0, 9, 2, 1, 5, 4, 8, 6, 3]", "[7, 0, 9, 2, 1, 5, 4, 8, 3, 6]"),
    ("typed-code check digit ignored", "Pairing.swift", "guard checkDigit(kept.compactMap { $0.wholeNumberValue }) == 0", "guard checkDigit(kept.compactMap { $0.wholeNumberValue }) >= 0"),
    ("proof_D label changed", "Pairing.swift", 'Data("\\(label) device".utf8)', 'Data("\\(label) devices".utf8)'),
    ("proof_M fingerprints swapped", "Pairing.swift", "m.append(macFingerprint); m.append(deviceFingerprint)", "m.append(deviceFingerprint); m.append(macFingerprint)"),
    ("PBKDF2 rounds cut", "Pairing.swift", "rounds: UInt32 = 600_000", "rounds: UInt32 = 60_000"),
    ("tag label changed", "Pairing.swift", 'static let label = "sill-tag-v1"', 'static let label = "sill-tag-v2"'),
    ("tag compares 5 bytes", "Pairing.swift", "for (a, b) in zip(expected, bytes.suffix(6))", "for (a, b) in zip(expected.prefix(5), bytes.suffix(6))"),
    ("link skips m == MacID(k)", "Pairing.swift", "guard m == MacID.make(fingerprint: fp) else { return .failure(.macIDMismatch) }", ""),
    ("link takes repeated k", "Pairing.swift", "guard values.count == 1, let v = values[0].value", "guard values.count >= 1, let v = values[0].value"),
    ("parser allows leading zeros", "AddressParser.swift", '($0 == "0" || $0.first != "0")', "true"),
    ("parser drops the inet_aton rule", "AddressParser.swift", "if acceptedByInetAton(String(h)) { return .failure(.ipv4) }", ""),
    ("parser keeps zones", "AddressParser.swift", 'if s.contains("%") { return .failure(.zone) }', ""),
    ("parser splits a bare IPv6 at its last colon", "AddressParser.swift", "if colons >= 2 {", "if colons >= 99 {"),
    ("SafeText keeps format characters", "SafeText.swift", "case .control, .format, .surrogate, .privateUse, .unassigned:", "case .control, .surrogate, .privateUse, .unassigned:"),
    ("SafeText keeps newlines", "SafeText.swift", "if s.properties.isWhitespace ||", "if (s.properties.isWhitespace && s != \"\\n\") ||"),
    ("Mac ID alphabet with I", "RemoteIdentity.swift", 'Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")', 'Array("0123456789ABCDEFGHIKMNPQRSTVWXYZ")'),
    ("SPKI without the curve OID", "RemoteIdentity.swift", "DER.sequence([DER.oid(DER.ecPublicKey), DER.oid(DER.prime256v1)])", "DER.sequence([DER.oid(DER.ecPublicKey)])"),
    ("kind 18 skips the macID binding", "Remote.swift", "guard decoded.macID == MacID.make(fingerprint: fp) else { return nil }", ""),
    ("kind 18 skips the signature", "Remote.swift", "publicKey.isValidSignature(signature, for: bytes),", ""),
    ("server verify block blind to ALPN", "RemoteTLS.swift", "complete(verify(peerLeaf(metadata).flatMap { SPKI.fingerprint(of: $0) }, negotiatedALPN(metadata)))", "complete(verify(peerLeaf(metadata).flatMap { SPKI.fingerprint(of: $0) }, nil))"),
    ("a host stops offering sill-pair/1", "RemoteTLS.swift", "public static let serverALPNs = [sessionALPN, pairingALPN]", "public static let serverALPNs = [sessionALPN]"),
    ("a later host offers sill/2 instead of sill/1", "RemoteTLS.swift", "public static let serverALPNs = [sessionALPN, pairingALPN]", 'public static let serverALPNs = ["sill/2", pairingALPN]'),
    ("the server offers sill/1 alone, whatever serverALPNs says", "RemoteTLS.swift",
     "for alpn in serverALPNs { sec_protocol_options_add_tls_application_protocol(sp, alpn) }", "sec_protocol_options_add_tls_application_protocol(sp, sessionALPN)"),
]
results = []
for name, file, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), src)
        path = os.path.join(src, file); text = open(path).read()
        if old not in text:
            results.append((name, "NOT APPLIED")); print(f"{name}: NOT APPLIED"); continue
        open(path, "w").write(text.replace(old, new, 1))
        files = [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.endswith(".swift")]
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *files, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            results.append((name, "did not compile")); print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe, t], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        verdict = f"caught ({len(failed)} FAIL, first: {failed[0][5:90] if failed else '-'})" if failed else "NOT CAUGHT"
        results.append((name, verdict)); print(f"{name}: {verdict}")
caught = sum(1 for _, v in results if v.startswith("caught"))
print(f"mutants caught: {caught} of {len(results)}")
sys.exit(0 if caught == len(results) else 1)
