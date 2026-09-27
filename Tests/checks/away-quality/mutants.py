"""Mutants of the host's away-from-home rules (Sources/SillHost/HostConfig.swift, DeviceSettings.swift,
AwayPolicy.swift): each changes one file in one place, is compiled with the check by build.sh and
must make it fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
H = "Sources/SillHost/"
MUTANTS = [
    ("AQ1 standard away at Balanced", H + "HostConfig.swift", "awayBitrate: 4_000_000, awayCaptureScale: 1,", "awayBitrate: 15_000_000, awayCaptureScale: 1,"),
    ("AQ2 standard away at Retina", H + "HostConfig.swift", "awayBitrate: 4_000_000, awayCaptureScale: 1,", "awayBitrate: 4_000_000, awayCaptureScale: 2,"),
    ("AQ3 the away bitrate unbounded", H + "HostConfig.swift", "        c.awayBitrate = min(max(awayBitrate, 1_000_000), 200_000_000)\n", ""),
    ("AQ4 the away scale from the home one", H + "HostConfig.swift", "c.awayCaptureScale = awayCaptureScale >= 1.5 ? 2 : 1", "c.awayCaptureScale = captureScale >= 1.5 ? 2 : 1"),
    ("AQ5 effective swapped", H + "HostConfig.swift", "away ? (awayBitrate, awayCaptureScale) : (bitrate, captureScale)", "away ? (bitrate, captureScale) : (awayBitrate, awayCaptureScale)"),
    ("AQ6 the away scale's change unnamed", H + "HostConfig.swift", 'parts.append("away \\(scaleName(awayCaptureScale)) → \\(scaleName(new.awayCaptureScale))")', 'parts.append("\\(scaleName(awayCaptureScale)) → \\(scaleName(new.awayCaptureScale))")'),
    ("AQ7 a device's state ignores its route", H + "DeviceSettings.swift", "let pair = effective(away: away)", "let pair = effective(away: false)"),
    ("AQ8 an away pick sets the home bitrate", H + "DeviceSettings.swift", "if let v = change.bitrate { c.awayBitrate = v }", "if let v = change.bitrate { c.bitrate = v }"),
    ("AQ9 an away pick also sets the home bitrate", H + "DeviceSettings.swift", "        rest.bitrate = nil\n", ""),
    ("AQ10 an away pick also sets the home scale", H + "DeviceSettings.swift", "        rest.captureScale = nil\n", ""),
    ("AQ11 the remote door from this network counts as away", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet)", "remoteDoor && (origin == .vpn || origin == .internet || origin == .lan)"),
    ("AQ12 the home door counts as away from a VPN", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet)", "remoteDoor || origin == .vpn || origin == .internet"),
    ("AQ13 nobody connected clears the flag", H + "AwayPolicy.swift", "devicesAway.isEmpty ? current : devicesAway.allSatisfy { $0 }", "devicesAway.isEmpty ? false : devicesAway.allSatisfy { $0 }"),
    ("AQ14 one device away is enough", H + "AwayPolicy.swift", "devicesAway.isEmpty ? current : devicesAway.allSatisfy { $0 }", "devicesAway.isEmpty ? current : devicesAway.contains { $0 }"),
    ("AQ15 the away line names the away pair as the home one", H + "AwayPolicy.swift", '+ "The home quality stays \\(title(c.bitrate, c.captureScale))."', '+ "The home quality stays \\(title(c.awayBitrate, c.awayCaptureScale))."'),
    ("AQ16 the home line streams the away pair", H + "AwayPolicy.swift", "streaming at \\(title(c.bitrate, c.captureScale)).\"", "streaming at \\(title(c.awayBitrate, c.awayCaptureScale)).\""),
]
caught = 0
for name, rel, old, new in MUTANTS:
    path = os.path.join(ROOT, rel)
    src = open(path).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), ROOT, exe, f"{os.path.basename(rel)}={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=120)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
