"""H3 mutants: each copies Sources/StreamProtocol, applies one mutation, compiles it with the check
and expects at least one FAIL. usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    ("reverse scrolling never reverses", "ScrollDirection.swift", "reversed && reversible(source) ? -1 : 1", "false && reversible(source) ? -1 : 1"),
    ("reverse scrolling turns every source around", "ScrollDirection.swift", "reversed && reversible(source) ? -1 : 1", "reversed ? -1 : 1"),
    ("reverse scrolling on for fingers with the switch off", "ScrollDirection.swift", "reversed && reversible(source) ? -1 : 1", "reversible(source) ? -1 : 1"),
    ("reverse scrolling halves instead of turning around", "ScrollDirection.swift", "reversed && reversible(source) ? -1 : 1", "reversed && reversible(source) ? -0.5 : 1"),
    ("reverse scrolling leaves the finger's drag", "ScrollDirection.swift",
     "case .finger, .pad: return true\n        case .trackpad, .wheel: return false", "case .pad: return true\n        case .finger, .trackpad, .wheel: return false"),
    ("reverse scrolling leaves the on-screen pad", "ScrollDirection.swift",
     "case .finger, .pad: return true\n        case .trackpad, .wheel: return false", "case .finger: return true\n        case .pad, .trackpad, .wheel: return false"),
    ("reverse scrolling turns a connected trackpad around", "ScrollDirection.swift",
     "case .finger, .pad: return true\n        case .trackpad, .wheel: return false", "case .finger, .pad, .trackpad: return true\n        case .wheel: return false"),
    ("reverse scrolling turns a wheel around", "ScrollDirection.swift",
     "case .finger, .pad: return true\n        case .trackpad, .wheel: return false", "case .finger, .pad, .wheel: return true\n        case .trackpad: return false"),
    ("Off is not offered", "TextScale.swift", "offered ? [off] + scales : scales", "scales"),
    ("Off is always offered", "TextScale.swift", "offered ? [off] + scales : scales", "[off] + scales"),
    ("an untouched Aa reads 1×", "TextScale.swift", "scale ?? (offered ? off : 1.0)", "scale ?? 1.0"),
    ("Off sends a scale", "TextScale.swift", "position == off ? nil : position", "position"),
    ("Off is titled 1×", "TextScale.swift", 'position == off ? "Off" : number(position) + "×"', 'number(position) + "×"'),
    ("a decrement skips Off", "TextScale.swift", "detents[up ? min(i + 1, detents.count - 1) : max(i - 1, 0)]", "detents[up ? min(i + 1, detents.count - 1) : max(i - 1, offered ? 1 : 0)]"),
    ("a fit never ends", "TextScale.swift", "previous != nil && now == nil", "false"),
    ("any viewport without a scale ends a fit", "TextScale.swift", "previous != nil && now == nil", "now == nil"),
    ("Off offered with the virtual display on", "TextScale.swift", "        return virtualDisplay != true\n", "        return true\n"),
    ("no Off before the Mac said", "TextScale.swift", "        return virtualDisplay != true\n", "        return virtualDisplay == false\n"),
    ("where the window streams ignored", "TextScale.swift", "        if case .window = source, let staged = onVirtualDisplay { return !staged }\n", ""),
    ("Off on the virtual display", "TextScale.swift", "if case .window = source, let staged = onVirtualDisplay { return !staged }", "if case .window = source, let staged = onVirtualDisplay { return staged || !staged }"),
    ("in place, the setting decides", "TextScale.swift", "if case .window = source, let staged = onVirtualDisplay { return !staged }", "if case .window = source, let staged = onVirtualDisplay, staged { return false }"),
    ("the Desktop's stream decides", "TextScale.swift", "if case .window = source, let staged = onVirtualDisplay { return !staged }", "if let staged = onVirtualDisplay { return !staged }"),
    ("Aa usable over the Desktop", "TextScale.swift", "if case .window = source { return true }\n        return false", "return source != .none"),
    ("Aa usable with nothing streaming", "TextScale.swift", "if case .window = source { return true }\n        return false", "return source != .desktop"),
    ("Aa never usable", "TextScale.swift", "if case .window = source { return true }\n        return false", "return false"),
    ("the dimmed hint loses its window", "TextScale.swift", 'unavailableHint = "Available for a window."', 'unavailableHint = "Unavailable."'),
    ("1× titled 1.×", "TextScale.swift", '        if text.hasSuffix(".") { text.removeLast() }\n', ''),
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
    ("the clipboard numbered 30", "StreamMessage.swift", "case clipboard = 32", "case clipboard = 30"),
    ("the server offers sill/1 alone, whatever serverALPNs says", "RemoteTLS.swift",
     "for alpn in serverALPNs { sec_protocol_options_add_tls_application_protocol(sp, alpn) }", "sec_protocol_options_add_tls_application_protocol(sp, sessionALPN)"),
    # Kind 43, the Mac's sound (Audio.swift, docs/audio-plan.md §3.2)
    ("kind 43 as 254", "StreamMessage.swift", "    case audio = 43 ", "    case audio = 254 "),
    ("kind 43: bytes left over accepted", "Audio.swift", "            guard offset == d.count else { return nil }\n", ""),
    ("kind 43: a count of 0 accepted", "Audio.swift", "            guard count >= 1 else { return nil }\n", ""),
    ("kind 43: the packets' cap lifted", "Audio.swift", "public static let maxPacketsPayload = 16384", "public static let maxPacketsPayload = 65536"),
    ("kind 43: the format's cap lifted", "Audio.swift", "public static let maxFormatPayload = 4096", "public static let maxFormatPayload = 8192"),
    ("kind 43: any flag a segment start", "Audio.swift", "segmentStart: flags & 1 == 1", "segmentStart: flags != 0"),
    ("kind 43: the epoch read a byte late", "Audio.swift", "let epoch = Int(d.readBigEndian(UInt16.self, at: 1))", "let epoch = Int(d.readBigEndian(UInt16.self, at: 2))"),
    ("kind 43: the epoch clamped, not wrapped", "Audio.swift", "d.appendBigEndian(UInt16(truncatingIfNeeded: epoch))", "d.appendBigEndian(UInt16(clamping: epoch))"),
    ("kind 43: an unknown type read as packets", "Audio.swift", "        case typePackets:\n            guard payload.count", "        case typePackets, 3:\n            guard payload.count"),
    ("kind 43: only the first packet read", "Audio.swift", "            for _ in 0..<count {", "            for _ in 0..<1 {"),
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
