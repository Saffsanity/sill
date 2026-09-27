"""Mutants of Sources/StreamProtocol/HostSettings.swift's new wire types and helpers: each must compile
and fail the away-wire check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "away-wire")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/StreamProtocol/HostSettings.swift")
orig = open(SRC).read()
MUTANTS = {
    "W1 away under another name on the wire": [("    /// Away from home: nil from a host without a remote door, and from older hosts.\n",
        "    enum CodingKeys: String, CodingKey { case settings, persistent, virtualDisplayAvailable, virtualDisplayNote, softwareEncoder, stream, answering, away = \"awayQuality\", link }\n    /// Away from home: nil from a host without a remote door, and from older hosts.\n")],
    "W2 the link never set by the init": [("self.away = away; self.link = link", "self.away = away; self.link = nil")],
    "W3 isBehind for anything not stalled": [("public var isBehind: Bool { state == Self.behind }", "public var isBehind: Bool { state != Self.stalled }")],
    "W4 behind spelt otherwise": [('public static let behind = "behind"', 'public static let behind = "Behind"')],
    "W5 a hand-set bitrate named as its title": [('QualityPreset(rawValue: bitrate)?.name ?? "\\(mbps(bitrate)) Mbps"',
                                                  'QualityPreset(rawValue: bitrate)?.name ?? title(forBitrate: bitrate)')],
    "W6 a preset named by its title": [('QualityPreset(rawValue: bitrate)?.name ?? "\\(mbps(bitrate)) Mbps"',
                                        'QualityPreset(rawValue: bitrate)?.title ?? "\\(mbps(bitrate)) Mbps"')],
    "W7 Retina only above 1.5": [('captureScale >= 1.5 ? "Retina" : "Standard"', 'captureScale > 1.5 ? "Retina" : "Standard"')],
    "W8 carried under another name on the wire": [("    /// What the link carried in the seconds it was the limit, kilobits per second; nil until three\n",
        "    enum CodingKeys: String, CodingKey { case state, withheldPerSecond, bitrate, carriedKbps = \"carried\", suggestedBitrate, suggestedCaptureScale }\n    /// What the link carried in the seconds it was the limit, kilobits per second; nil until three\n")],
    "W9 thisConnectionAway under another name on the wire": [("    /// The Mac counts this connection as away: its Quality and Resolution picks set the away\n",
        "    enum CodingKeys: String, CodingKey { case homeBitrate, homeCaptureScale, awayBitrate, awayCaptureScale, thisConnectionAway = \"away\", awayRunning }\n    /// The Mac counts this connection as away: its Quality and Resolution picks set the away\n")],
}
caught = 0
for name, edits in MUTANTS.items():
    src = orig
    for old, new in edits:
        n = src.count(old)
        if n != 1:
            print(f"{name}: NOT APPLIED (pattern found {n} times)"); src = None; break
        src = src.replace(old, new)
    if src is None: continue
    path = os.path.join(OUT, "HostSettings.swift")
    open(path, "w").write(src)
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=120)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:2]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
