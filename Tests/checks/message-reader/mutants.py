"""Each mutant of MessageReader.swift must fail the message-reader check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "message-reader")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/MessageReader.swift")
orig = open(SRC).read()
PIECE_READ = "connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, Self.piece))"
PIECE_CLOSURE = "maximumLength: min(remaining, Self.piece)) { [self] data, _, isComplete, error in\n            guard stillReads() else { return }\n"
MUTANTS = {
    # The plan's five (docs/remote-bundle-plan.md §11, H5)
    "R1 the stamp only at the message's end": [
        ("                onBytes(data.count)\n                if buffer.isEmpty,", "                if buffer.isEmpty,"),
        ("                    onMessage(header, payload)\n", "                    onBytes(payload.count)\n                    onMessage(header, payload)\n")],
    "R2 minimumIncompleteLength = remaining": [
        (PIECE_READ, "connection.receive(minimumIncompleteLength: remaining, maximumLength: min(remaining, Self.piece))")],
    "R3 no piece cap": [(PIECE_READ, "connection.receive(minimumIncompleteLength: 1, maximumLength: remaining)")],
    "R4 the end in the middle of a message ignored": [
        ("            if ended {\n                self.header = nil", "            if error != nil {\n                self.header = nil")],
    "R5 no cap check": [("            guard header.payloadLength <= cap else {", "            guard header.payloadLength <= cap || cap > 0 else {")],
    # And the rest of the contract
    "R6 whole pieces (the minimum at the piece)": [
        (PIECE_READ, "connection.receive(minimumIncompleteLength: min(remaining, Self.piece), maximumLength: min(remaining, Self.piece))")],
    "R7 the frame cap for every kind": [
        ("let cap = header.kind == .frame ? StreamMessage.maxFramePayload : StreamMessage.maxOtherHostPayload", "let cap = StreamMessage.maxFramePayload")],
    "R8 the other cap for every kind": [
        ("let cap = header.kind == .frame ? StreamMessage.maxFramePayload : StreamMessage.maxOtherHostPayload", "let cap = StreamMessage.maxOtherHostPayload")],
    "R9 a message cut short delivered at the end": [
        ("            if ended {\n                self.header = nil", "            if ended {\n                if !buffer.isEmpty { onMessage(header, buffer) }\n                self.header = nil")],
    "R10 no stillReads before a read": [("    private func readHeader() {\n        guard stillReads() else { return }\n", "    private func readHeader() {\n")],
    "R11 no stillReads in a piece's callback": [(PIECE_CLOSURE, "maximumLength: min(remaining, Self.piece)) { [self] data, _, isComplete, error in\n")],
    "R12 a header's read not reported": [("            onBytes(data.count)\n            // Nothing a Sill host sends", "            // Nothing a Sill host sends")],
    "R13 a piece replaces the buffer": [("                    buffer.append(data)\n", "                    buffer = data\n")],
    "R14 the reading stops after an empty payload": [
        ("end is not this reader's to report.\n                if ended { if stillReads() { onEnd(.closed(error)) } } else { readHeader() }\n",
         "end is not this reader's to report.\n                if ended { if stillReads() { onEnd(.closed(error)) } }\n")],
    "R15 the end between messages ignored": [("                if isComplete || error != nil { onEnd(.closed(error)) }\n", "                if error != nil { onEnd(.closed(error)) }\n")],
    "R16 a read after the end that came with a message": [
        ("                    if ended { if stillReads() { onEnd(.closed(error)) } } else { readHeader() }\n", "                    readHeader()\n")],
    "R17 the end reported after the message that came with it stopped the reading": [
        ("                    if ended { if stillReads() { onEnd(.closed(error)) } } else { readHeader() }\n",
         "                    if ended { onEnd(.closed(error)) } else { readHeader() }\n")],
    # Not a mutant here: dropping the check for an end that came with a header (`guard !ended`
    # after the header). Network reports the end with the last bytes of a read of 1 to 256 KB, but
    # never with a header's read (minimum = maximum = 14 bytes), even when the end is already there
    # (2026-09-26), so no case can tell the two apart; the check stays for a stack that does. For
    # the same reason not R17's twin after an empty payload (whose message ends at its header).
}
caught = 0
for name, edits in MUTANTS.items():
    src = orig
    for old, new in edits:
        n = src.count(old)
        if n != 1:
            print(f"{name}: NOT APPLIED (pattern found {n} times)")
            src = None
            break
        src = src.replace(old, new)
    if src is None: continue
    path = os.path.join(OUT, "MessageReader.swift")
    open(path, "w").write(src)
    b = subprocess.run(["swiftc", "-O", path, os.path.join(ROOT, "Sources/StreamProtocol/StreamMessage.swift"),
                        os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    try:
        r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=180)
        failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
        ok = r.returncode != 0
        detail = f"{len(failed)} failing, e.g. {failed[:2]}" if failed else f"exit status {r.returncode}"
    except subprocess.TimeoutExpired:
        ok, detail = True, "timed out (180 s)"
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {detail}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
