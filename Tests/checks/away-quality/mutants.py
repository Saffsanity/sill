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
    ("AQ11 the remote door from this network counts as away", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay || origin == .lan)"),
    ("AQ12 the home door counts as away from a VPN", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)", "remoteDoor || origin == .vpn || origin == .internet || origin == .relay"),
    # Issue #326: a relay on this Mac is away, as a VPN.
    ("AQ40 a relay on this Mac at home (the rule before #326)", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)", "remoteDoor && (origin == .vpn || origin == .internet)"),
    ("AQ41 loopback at the remote door away too", H + "AwayPolicy.swift", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay)", "remoteDoor && (origin == .vpn || origin == .internet || origin == .relay || origin == .loopback)"),
    ("AQ13 nobody connected clears the flag", H + "AwayPolicy.swift", "devicesAway.isEmpty ? current : devicesAway.allSatisfy { $0 }", "devicesAway.isEmpty ? false : devicesAway.allSatisfy { $0 }"),
    ("AQ14 one device away is enough", H + "AwayPolicy.swift", "devicesAway.isEmpty ? current : devicesAway.allSatisfy { $0 }", "devicesAway.isEmpty ? current : devicesAway.contains { $0 }"),
    ("AQ15 the away line names the away pair as the home one", H + "AwayPolicy.swift", '+ "The home quality stays \\(title(c.bitrate, c.captureScale))."', '+ "The home quality stays \\(title(c.awayBitrate, c.awayCaptureScale))."'),
    ("AQ16 the home line streams the away pair", H + "AwayPolicy.swift", "streaming at \\(title(c.bitrate, c.captureScale)).\"", "streaming at \\(title(c.awayBitrate, c.awayCaptureScale)).\""),
    ("AQ-O1 standard shows this account off console", H + "HostConfig.swift", "offConsoleView: false, headlessDisplay: true, virtualDesktop: false)",
     "offConsoleView: true, headlessDisplay: true, virtualDesktop: false)"),
    ("AQ-O2 the off-console view's change unnamed", H + "HostConfig.swift",
     '        if offConsoleView != new.offConsoleView { parts.append("off-console view \\(onOff(offConsoleView)) → \\(onOff(new.offConsoleView))") }\n', ""),
    ("AQ-O3 the off-console view's switch never stored", H + "HostConfig.swift", "        self.offConsoleView = offConsoleView\n", "        self.offConsoleView = false\n"),
    # A Mac with no screen's display (PR #200), the Mac's alone: on in both (Noah on #61), its switch in Sill.app and the CLI.
    ("AQ-H1 standard makes no display for a Mac with no screen", H + "HostConfig.swift", "offConsoleView: false, headlessDisplay: true, virtualDesktop: false)",
     "offConsoleView: false, headlessDisplay: false, virtualDesktop: false)"),
    ("AQ-H2 Sill.app's display for a Mac with no screen off", H + "HostConfig.swift", "        c.sendAudio = true\n",
     "        c.sendAudio = true\n        c.headlessDisplay = false\n"),
    ("AQ-H3 its change unnamed", H + "HostConfig.swift",
     '        if headlessDisplay != new.headlessDisplay { parts.append("headless display \\(onOff(headlessDisplay)) → \\(onOff(new.headlessDisplay))") }\n', ""),
    ("AQ-H4 its switch never stored", H + "HostConfig.swift", "        self.headlessDisplay = headlessDisplay\n", "        self.headlessDisplay = true\n"),
    ("AQ17 standard shares no clipboard", H + "HostConfig.swift", "requirePairing: true, shareClipboard: true, sendAudio: false,", "requirePairing: true, shareClipboard: false, sendAudio: false,"),
    ("AQ18 the clipboard's change unnamed", H + "HostConfig.swift", '        if shareClipboard != new.shareClipboard { parts.append("share clipboard \\(onOff(shareClipboard)) → \\(onOff(new.shareClipboard))") }\n', ""),
    ("AQ19 the clipboard's switch never stored", H + "HostConfig.swift", "        self.shareClipboard = shareClipboard\n", "        self.shareClipboard = true\n"),
    # Send Audio, a device's to set too (docs/audio-plan.md, Q8 as Noah revised it on 2026-10-27).
    ("AQ20 a device's Send Audio dropped, as the beta's hosts did", H + "DeviceSettings.swift",
     "var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed, sendAudio: c.sendAudio)",
     "var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed)"),
    ("AQ21 a device's Send Audio named as refused", H + "DeviceSettings.swift", "        var refused: [String] = []\n",
     '        var refused: [String] = c.sendAudio != nil ? ["send audio (set on this Mac only)"] : []\n'),
    ("AQ22 only a device's Send Audio on taken", H + "DeviceSettings.swift", "sendAudio: c.sendAudio)", "sendAudio: c.sendAudio == true ? true : nil)"),
    ("AQ23 a device never sees Send Audio on", H + "DeviceSettings.swift", "directWireless: directWireless, sendAudio: sendAudio,",
     "directWireless: directWireless, sendAudio: false,"),
    ("AQ24 Send Audio's change unnamed", H + "HostConfig.swift", 'if sendAudio != new.sendAudio { parts.append(', 'if false { parts.append('),
    ("AQ25 a device's Send Audio laid over nothing", H + "DeviceSettings.swift", "        if let v = change.sendAudio { c.sendAudio = v }\n", ""),
    ("AQ26 a device's Send Audio dropped away from home", H + "DeviceSettings.swift", "        rest.captureScale = nil\n",
     "        rest.captureScale = nil\n        rest.sendAudio = nil\n"),
    # Sill.app's defaults: the CLI's with the virtual display on (Noah, 2026-10-27).
    ("AQ27 Sill.app's virtual display off (the default before 2026-10-27)", H + "HostConfig.swift",
     "        c.virtualDisplay = true\n", "        c.virtualDisplay = false\n"),
    ("AQ28 the CLI's virtual display on by default", H + "HostConfig.swift",
     "prioritizeSpeed: false, virtualDisplay: false, directWireless: false,", "prioritizeSpeed: false, virtualDisplay: true, directWireless: false,"),
    ("AQ29 Sill.app's defaults another knob off the CLI's too", H + "HostConfig.swift",
     "        c.virtualDisplay = true\n", "        c.virtualDisplay = true\n        c.directWireless = true\n"),
    ("AQ30 Sill.app's Send Audio off (the default before 2026-10-27)", H + "HostConfig.swift",
     "        c.sendAudio = true\n", "        c.sendAudio = false\n"),
    # Direct Wireless only from a paired session at home (2026-10-29, the security scan's finding 8).
    ("AQ31 Direct Wireless from an unpaired session (the rule before 2026-10-29)", H + "DeviceSettings.swift",
     "            } else if !paired {\n", "            } else if false {\n"),
    ("AQ32 only an unpaired device's on refused (off taken)", H + "DeviceSettings.swift",
     "            } else if !paired {\n", "            } else if !paired && v {\n"),
    ("AQ33 Direct Wireless from afar", H + "DeviceSettings.swift",
     "            if fromRemote {\n                refused.append(", "            if false {\n                refused.append("),
    ("AQ34 an unpaired session's refusal unnamed", H + "DeviceSettings.swift",
     '                refused.append("direct wireless (only a paired device)")\n', "                _ = refused\n"),
    ("AQ35 the unpaired reason first, from afar too", H + "DeviceSettings.swift",
     "            if fromRemote {\n                refused.append(\"direct wireless (not from a remote connection)\")\n            } else if !paired {",
     "            if !paired {\n                refused.append(\"direct wireless (only a paired device)\")\n            } else if fromRemote {"),
    ("AQ36 the plain door counts as paired", H + "DeviceSettings.swift",
     "        guard let key else { return false }\n", "        guard let key else { return true }\n"),
    ("AQ37 any key counts as paired", H + "DeviceSettings.swift",
     "        return trusted.contains(key)\n", "        return !key.isEmpty\n"),
    ("AQ38 a key counts once the list has any", H + "DeviceSettings.swift",
     "        return trusted.contains(key)\n", "        return !trusted.isEmpty\n"),
    ("AQ39 a prefix of a paired key counts", H + "DeviceSettings.swift",
     "        return trusted.contains(key)\n", "        return trusted.contains { $0.starts(with: key) }\n"),
    # The Virtual Desktop's switch (phase 2b of docs/virtual-desktop-plan.md as revised 2026-11-18).
    ("AQ-V1 the Virtual Desktop on in standard", H + "HostConfig.swift",
     "offConsoleView: false, headlessDisplay: true, virtualDesktop: false)", "offConsoleView: false, headlessDisplay: true, virtualDesktop: true)"),
    ("AQ-V2 the Virtual Desktop's change unnamed", H + "HostConfig.swift", "if virtualDesktop != new.virtualDesktop { parts.append(", "if false { parts.append("),
    ("AQ-V3 the Virtual Desktop never kept", H + "HostConfig.swift", "        self.virtualDesktop = virtualDesktop\n", "        self.virtualDesktop = false\n"),
    ("AQ-V4 a device's Virtual Desktop laid over nothing", H + "DeviceSettings.swift", "        if let v = change.virtualDesktop { c.virtualDesktop = v }\n", ""),
    ("AQ-V5 taken from an unpaired session", H + "DeviceSettings.swift",
     "            if !paired {\n                refused.append(\"virtual desktop (only a paired device)\")",
     "            if false {\n                refused.append(\"virtual desktop (only a paired device)\")"),
    ("AQ-V6 refused from away, as Direct Wireless", H + "DeviceSettings.swift",
     "            if !paired {\n                refused.append(\"virtual desktop (only a paired device)\")",
     "            if !paired || fromRemote {\n                refused.append(\"virtual desktop (only a paired device)\")"),
    ("AQ-V7 on taken where it cannot be made", H + "DeviceSettings.swift", "            } else if v, !virtualDesktopAvailable {", "            } else if false {"),
    ("AQ-V8 off refused where it cannot be made", H + "DeviceSettings.swift", "            } else if v, !virtualDesktopAvailable {",
     "            } else if !virtualDesktopAvailable {"),
    ("AQ-V9 not reported to devices (a host before 2b's)", H + "DeviceSettings.swift",
     "directWireless: directWireless, sendAudio: sendAudio, virtualDesktop: virtualDesktop)",
     "directWireless: directWireless, sendAudio: sendAudio, virtualDesktop: nil)"),
    ("AQ-V9b reported always off", H + "DeviceSettings.swift",
     "directWireless: directWireless, sendAudio: sendAudio, virtualDesktop: virtualDesktop)",
     "directWireless: directWireless, sendAudio: sendAudio, virtualDesktop: false)"),
    ("AQ-V10 a taken Virtual Desktop dropped", H + "DeviceSettings.swift", "                ok.virtualDesktop = v\n", ""),
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
