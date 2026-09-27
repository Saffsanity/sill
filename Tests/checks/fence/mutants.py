"""Each mutant of SessionLink's fences, hold, adopt and unhold (follow-best-path and its review fixes), and of its
count of the inputs meant for the session's connection (pointer-visibility), must fail the fence check in some mode.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(WT, ".build", "checks", "fence")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = WT + "/iOSClient/SessionLink.swift"
orig = open(SRC).read()
MODES = ["ok", "timeout", "oldcloses", "hold", "holdclosed", "unhold", "adoptfence", "twofences", "twomoves", "holdfence", "holdadopt", "newsession", "newsessionhold", "count"]
ADOPT_END = "        holding = nil\n        return endedLocked(since: h.since)\n    }\n\n    /// Ends the hold on `c`"
UNHOLD_END = "        guard let h = holding, h.connection === c else { return nil }\n        holding = nil\n        return endedLocked(since: h.since)\n"
MUTANTS = {
    "H1 adopt drops what waited": (ADOPT_END, "        holding = nil; waiting = []\n        return Released(held: 0, waiting: 0, clear: true, seconds: 0, close: [])\n    }\n\n    /// Ends the hold on `c`"),
    "H2 hold holds nothing": ("        if holding == nil { holding = Hold(connection: c) }\n", ""),
    "H3 a closing connection releases its hold onto itself": (
        "        guard let i = fences.firstIndex(where: { $0.old === old }) else { return nil }\n",
        "        guard let i = fences.firstIndex(where: { $0.old === old }) else {\n            if let h = holding, h.connection === old { holding = nil; return endedLocked(since: h.since) }\n            return nil\n        }\n"),
    "H4 adopt ends an earlier hand-over's fence at once": (
        "        current = new\n        inputs = waitingInputs\n        guard let h = holding else { return nil }\n",
        "        current = new\n        inputs = waitingInputs\n        fences = []\n        guard let h = holding else { _ = endedLocked(since: 0); return nil }\n"),
    "H5 unhold drops what waited": (UNHOLD_END, "        guard let h = holding, h.connection === c else { return nil }\n        holding = nil; waiting = []\n        return Released(held: 0, waiting: 0, clear: true, seconds: 0, close: [])\n"),
    "H6 adopt keeps the old connection as the session's": ("        lock.lock(); defer { lock.unlock() }\n        current = new\n        inputs = waitingInputs\n        guard let h = holding",
                                                           "        lock.lock(); defer { lock.unlock() }\n        inputs = waitingInputs\n        guard let h = holding"),
    # review fixes
    "H7 a hand-over replaces an earlier fence (the finding)": ("        fences.append(Fence(old: old, nonce: nonce))\n", "        fences = [Fence(old: old, nonce: nonce)]\n"),
    "H8 a fence ending sends what waits despite the hold": ("        guard fences.isEmpty, holding == nil else {", "        guard fences.isEmpty else {"),
    "H9 a hold refused while a fence stands (before the fix)": ("        guard current === c else { return false }\n", "        guard current === c, fences.isEmpty else { return false }\n"),
    "H10 any pong on the old connection ends its fence": ("fences.firstIndex(where: { $0.old === old && $0.nonce == payload })", "fences.firstIndex(where: { $0.old === old })"),
    "H11 a fence ending sends what waits while another stands": ("        guard fences.isEmpty, holding == nil else {", "        guard holding == nil else {"),
    "H12 never clear": ("        return Released(held: out.count, waiting: 0, clear: true, seconds: seconds, close: close)\n",
                        "        return Released(held: out.count, waiting: 0, clear: false, seconds: seconds, close: close)\n"),
    "H13 clear while a fence or the hold still stands": ("            return Released(held: 0, waiting: waiting.count, clear: false, seconds: seconds, close: [])\n",
                                                          "            return Released(held: 0, waiting: waiting.count, clear: true, seconds: seconds, close: [])\n"),
    "H14 an old connection handed back while what waited still waits": ("            return Released(held: 0, waiting: waiting.count, clear: false, seconds: seconds, close: [])\n",
                                                                         "            defer { fencedOff = [] }\n            return Released(held: 0, waiting: waiting.count, clear: false, seconds: seconds, close: fencedOff)\n"),
    "H15 old connections never handed back (never closed)": ("        return Released(held: out.count, waiting: 0, clear: true, seconds: seconds, close: close)\n",
                                                             "        return Released(held: out.count, waiting: 0, clear: true, seconds: seconds, close: [])\n"),
    "H16 an old connection kept for closing twice": ("        let close = fencedOff\n        fencedOff = []\n", "        let close = fencedOff\n"),
    # review-moves-b: a new session (#13's adopt, connect) dropping a hand-over or a hold
    "N1 dropHandOver keeps what waited": ("        fences = []\n        holding = nil\n        waiting = []\n        fencedOff = []\n",
                                          "        fences = []\n        holding = nil\n        fencedOff = []\n"),
    "N2 dropHandOver keeps the fences": ("        fences = []\n        holding = nil\n        waiting = []\n        fencedOff = []\n",
                                         "        holding = nil\n        waiting = []\n        fencedOff = []\n"),
    "N3 dropHandOver keeps the hold": ("        fences = []\n        holding = nil\n        waiting = []\n        fencedOff = []\n",
                                       "        fences = []\n        waiting = []\n        fencedOff = []\n"),
    # ci-fence-fix (2026-09-26): the check waits on events now, not the clock, and no longer bounds how long a
    # fence stood; a fence that its own pong never ends (here it comes back on the new connection) must still fail it
    "F1 the fence ping goes out on the new connection": ("        old.send(content: fencePing, completion: .contentProcessed { _ in })\n",
                                                         "        new.send(content: fencePing, completion: .contentProcessed { _ in })\n"),
    # pointer-visibility: the inputs counted for the session's connection (docs/pointer-visibility-plan.md §3.3)
    "C1 the setter keeps counting across connections": ("set { lock.lock(); current = newValue; inputs = waitingInputs; lock.unlock() }",
                                                        "set { lock.lock(); current = newValue; lock.unlock() }"),
    "C2 the setter restarts at 0, dropping what waits for the new connection": ("set { lock.lock(); current = newValue; inputs = waitingInputs; lock.unlock() }",
                                                                                "set { lock.lock(); current = newValue; inputs = 0; lock.unlock() }"),
    "C3 a hand-over restarts at 0, not at what waits": ("        current = new\n        inputs = waitingInputs\n        fences.append(",
                                                        "        current = new\n        inputs = 0\n        fences.append("),
    "C4 a hand-over keeps counting": ("        current = new\n        inputs = waitingInputs\n        fences.append(", "        current = new\n        fences.append("),
    "C5 adopt keeps counting": ("        current = new\n        inputs = waitingInputs\n        guard let h = holding", "        current = new\n        guard let h = holding"),
    "C6 adopt restarts at 0, not at what was held": ("        current = new\n        inputs = waitingInputs\n        guard let h = holding",
                                                     "        current = new\n        inputs = 0\n        guard let h = holding"),
    "C7 what waits is not counted": ("            waiting.append(data)\n            if Self.isInput(data) { inputs += 1 }\n", "            waiting.append(data)\n"),
    "C8 what goes out at once is not counted": ("        if current != nil, Self.isInput(data) { inputs += 1 }\n", ""),
    "C9 an input with no connection counted": ("        if current != nil, Self.isInput(data) { inputs += 1 }\n", "        if Self.isInput(data) { inputs += 1 }\n"),
    "C10 every message counted, not only inputs": ("private static func isInput(_ data: Data) -> Bool { data.first == 8 }",
                                                   "private static func isInput(_ data: Data) -> Bool { !data.isEmpty }"),
    "C11 dropHandOver keeps counting what it dropped": ("        inputs -= waitingInputs\n", ""),
    "C12 unhold restarts the count": ("        guard let h = holding, h.connection === c else { return nil }\n        holding = nil\n        return endedLocked(since: h.since)\n",
                                      "        guard let h = holding, h.connection === c else { return nil }\n        holding = nil\n        inputs = 0\n        return endedLocked(since: h.since)\n"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    assert orig.count(old) == 1, f"{name}: pattern found {orig.count(old)} times"
    path = os.path.join(OUT, "SessionLink-mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, WT + "/Sources/StreamProtocol/StreamMessage.swift", os.path.join(SP, "main.swift"),
                        "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:800]}"); continue
    failed = []
    for m in MODES:
        try:
            r = subprocess.run([os.path.join(OUT, "mutant"), m], capture_output=True, text=True, timeout=30)
            if r.returncode != 0: failed.append(f"{m}: {r.stdout.strip().splitlines()[0] if r.stdout.strip() else 'no output'}")
        except subprocess.TimeoutExpired:
            failed.append(f"{m}: timed out")
    ok = bool(failed)
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} of {len(MODES)} modes fail, e.g. {failed[:2]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
