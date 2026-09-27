"""H3 (docs/update-notice-plan.md) mutants of GoodbyePolicy.swift: each changes it in one place, is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/GoodbyePolicy.swift")
MUTANTS = [
    ("an unknown reason reconnects unless told not to", "GoodbyePolicy.swift", "let reconnect = goodbye.reconnect == true", "let reconnect = goodbye.reconnect != false"),
    ("the host's message ignored", "GoodbyePolicy.swift", "return Outcome(text: message(goodbye) ?? own, reconnect: reconnect, remoteAllowed: saved, isNotice: true)", "return Outcome(text: own, reconnect: reconnect, remoteAllowed: saved, isNotice: true)"),
    ("the message not cleaned", "GoodbyePolicy.swift", "let text = SafeText.label(goodbye.message ?? \"\", limit: messageLimit)", "let text = goodbye.message ?? \"\""),
    ("an empty message shown", "GoodbyePolicy.swift", "return text.isEmpty ? nil : text", "return text"),
    ("no length limit", "GoodbyePolicy.swift", "static let messageLimit = 300", "static let messageLimit = 1000"),
    ("removed reconnects", "GoodbyePolicy.swift", "reconnect: false, remoteAllowed: false, isNotice: false)\n        case Goodbye.remoteOff:", "reconnect: true, remoteAllowed: false, isNotice: false)\n        case Goodbye.remoteOff:"),
    ("remoteOff allows the remote door", "GoodbyePolicy.swift", "return Outcome(text: \"\\(mac) turned off Remote Access.\", reconnect: true, remoteAllowed: false, isNotice: false)", "return Outcome(text: \"\\(mac) turned off Remote Access.\", reconnect: true, remoteAllowed: saved, isNotice: false)"),
    ("an unreadable goodbye is not a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy,\n                                            Goodbye.pairingRequired, \"\"]"),
    ("pairingRequired is a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy]"),
    ("pairingRequired reconnects", "GoodbyePolicy.swift", "Tap it to pair this \\(device).\",\n                           reconnect: false", "Tap it to pair this \\(device).\",\n                           reconnect: true"),
    ("notices inverted", "GoodbyePolicy.swift", "!knownReasons.contains(goodbye.reason)", "knownReasons.contains(goodbye.reason)"),
    ("quit allows the remote door for an unsaved Mac", "GoodbyePolicy.swift", "reconnect: true, remoteAllowed: saved, isNotice: false)\n        case Goodbye.removed:", "reconnect: true, remoteAllowed: true, isNotice: false)\n        case Goodbye.removed:"),
    ("saved and unsaved words swapped", "GoodbyePolicy.swift", "return Outcome(text: saved ? \"\\(mac) disconnected. Sill will reconnect when it can reach it.\"", "return Outcome(text: !saved ? \"\\(mac) disconnected. Sill will reconnect when it can reach it.\""),
    ("update reconnects unless told not to", "GoodbyePolicy.swift", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)", "reconnect: goodbye.reconnect != false, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)"),
    ("update without the App Store link", "GoodbyePolicy.swift", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: false, isNotice: true)"),
    ("minimumVersion shown as sent", "GoodbyePolicy.swift", "if let floor = goodbye.minimumVersion.flatMap({ SillVersion($0) }) { own += \" It needs version \\(floor) or later.\" }", "if let floor = goodbye.minimumVersion { own += \" It needs version \\(floor) or later.\" }"),
    ("update ignores the host's message", "GoodbyePolicy.swift", "return Outcome(text: message(goodbye) ?? own, reconnect: goodbye.reconnect == true", "return Outcome(text: own, reconnect: goodbye.reconnect == true"),
    ("update's own words without the device", "GoodbyePolicy.swift", "var own = \"Update Sill on this \\(device) to keep using \\(mac).\"", "var own = \"Update Sill to keep using \\(mac).\""),
]
caught = 0
for name, _, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "GoodbyePolicy.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
