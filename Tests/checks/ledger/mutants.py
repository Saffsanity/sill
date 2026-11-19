"""Mutants of the device's settings ledger (iOSClient/HostSettingsLedger.swift) and of the merge it
uses in Sources/StreamProtocol/HostSettings.swift, the sound's seventh field and Direct Wireless's
rule 10 among them: each must compile and fail the ledger check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "ledger")
os.makedirs(OUT, exist_ok=True)
LEDGER = "iOSClient/HostSettingsLedger.swift"
WIRE = "Sources/StreamProtocol/HostSettings.swift"
MUTANTS = {
    "L1 rule 9: Send Audio sent to a host without sound": (LEDGER,
        "            if field == .sendAudio, shown.sendAudio == nil { continue }\n", ""),
    "L2 rule 9: Direct Wireless sent to an older host": (LEDGER,
        "            if field == .directWireless, shown.directWireless == nil { continue }\n", ""),
    "L3 a change's fields without Send Audio": (LEDGER, "        if sendAudio != nil { f.append(.sendAudio) }\n", ""),
    "L4 Send Audio's single field as Direct Wireless": (LEDGER,
        "case .sendAudio: HostSettingsChange(sendAudio: sendAudio)", "case .sendAudio: HostSettingsChange(directWireless: sendAudio)"),
    "L5 adding drops another pick's Send Audio": (LEDGER, "sendAudio: other.sendAudio ?? sendAudio)", "sendAudio: sendAudio)"),
    "L6 rule 2: what is shown sent again": (LEDGER, "            guard single.applied(to: shown) != shown else { continue }\n", ""),
    "L7 rule 4: an answer clears every pick": (LEDGER, "for (field, entry) in pending where entry.token == token {",
                                               "for (field, entry) in pending {"),
    "L8 rule 5: a refusal never reported": (LEDGER, "if entry.change.applied(to: s.settings) != s.settings { refused.insert(field) }",
                                            "if entry.change.applied(to: s.settings) == s.settings { refused.insert(field) }"),
    "L9 rule 6: a pick dropped at the timeout itself": (LEDGER, "now - $0.value.sentAt <= timeout", "now - $0.value.sentAt < timeout"),
    "L10 rule 7: a reset keeps the picks": (LEDGER, "        host = nil\n        pending = [:]\n", "        host = nil\n"),
    "L11 isEmpty without Send Audio": (WIRE, "&& directWireless == nil && sendAudio == nil", "&& directWireless == nil"),
    "L12 applied(to:) without Send Audio": (WIRE, "        if let v = sendAudio { r.sendAudio = v }\n", ""),
    # Direct Wireless only from a paired session (2026-10-29, the security scan's finding 8): rule 10.
    "L13 rule 10 dropped: Direct Wireless sent on an unpaired session": (LEDGER,
        "            if field == .directWireless, host?.takesDirectWireless == false { continue }\n", ""),
    "L14 an older Mac's silence read as unpaired": (LEDGER,
        "var takesDirectWireless: Bool { sessionPaired != false }", "var takesDirectWireless: Bool { sessionPaired == true }"),
    "L15 rule 10 holds back every field": (LEDGER,
        "            if field == .directWireless, host?.takesDirectWireless == false { continue }\n",
        "            if host?.takesDirectWireless == false { continue }\n"),
    "L16 sessionPaired never kept": (WIRE, "        self.sessionPaired = sessionPaired\n", "        self.sessionPaired = nil\n"),
}
caught = 0
for name, (rel, old, new) in MUTANTS.items():
    files = {f: open(os.path.join(ROOT, f)).read() for f in (WIRE, LEDGER)}
    n = files[rel].count(old)
    if n != 1:
        print(f"{name}: NOT APPLIED (pattern found {n} times)"); continue
    files[rel] = files[rel].replace(old, new)
    paths = []
    for f, text in files.items():
        paths.append(os.path.join(OUT, "mutant-" + os.path.basename(f)))
        open(paths[-1], "w").write(text)
    b = subprocess.run(["swiftc", "-O", *paths, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:110] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
