"""H3 (docs/pointer-visibility-plan.md) mutants of iOSClient/PointerPresence.swift: each changes it in one
place, is compiled with the check and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/PointerPresence.swift")
MUTANTS = [
    # The sprite
    ("no portrait check", "                guard portrait else { return nil }\n", ""),
    ("the Pencil shown by default", "static let pencilShowsPointerByDefault = false", "static let pencilShowsPointerByDefault = true"),
    ("the Pencil's flip does nothing", "return pencilShowsPointer ? own : nil", "return nil"),
    ("shown while nothing streams", "        guard streaming else { return nil }\n", ""),
    ("the Mac's pointer shown off the stream", "return macInside ? mac : nil", "return mac"),
    ("the trackpad's arrow on any input", "            case .none:\n                return nil\n", "            case .none:\n                return own\n"),
    ("a linger by default", "static let trackpadLingerByDefault: Double? = nil", "static let trackpadLingerByDefault: Double? = 2"),
    ("the linger's end hides it already", "if let ends = lingerEnds, now > ends { return nil }", "if let ends = lingerEnds, now >= ends { return nil }"),
    ("a finger down does not stop the linger", "        if fingersOnTrackpad > 0 {\n            trackpadLiftedAt = nil\n        } else if wasDown {",
     "        if fingersOnTrackpad > 0 {\n        } else if wasDown {"),
    ("a lift without a finger down starts the linger", "        } else if wasDown {\n            trackpadLiftedAt = now", "        } else {\n            trackpadLiftedAt = now"),
    # The key row, and a new frame size
    ("the key row hides the Mac's arrow", "        guard macInside, let mac else { return (nil, .none) }\n        return (mac, .trackpad)\n",
     "        return (nil, .none)\n"),
    ("the key row leaves the pad's old cursor", "        guard control == .elsewhere else { return nil }\n        guard macInside, let mac else",
     "        if true { return nil }\n        guard macInside, let mac else"),
    ("the key row keeps the Mac's arrow off the stream", "guard macInside, let mac else { return (nil, .none) }", "guard let mac else { return (nil, .none) }"),
    ("a new frame re-centres under the Mac's control", "control == .here && own != nil && sprite(now: now) != nil", "own != nil && sprite(now: now) != nil"),
    ("a new frame re-centres a hidden pointer", "control == .here && own != nil && sprite(now: now) != nil", "control == .here && own != nil"),
    # Freshness and restatements
    ("`>` for `>=` in freshness", "(seen ?? 0) >= sentOnSession", "(seen ?? 0) > sentOnSession"),
    ("the pending move ignored", "!movePending && (seen ?? 0) >= sentOnSession", "(seen ?? 0) >= sentOnSession"),
    ("no seen counts as fresh", "(seen ?? 0) >= sentOnSession", "(seen ?? Int.max) >= sentOnSession"),
    ("a restatement off the stream", "        guard inside else { return false }\n", ""),
    ("a tolerance of 0.02", "static let restatementTolerance = 0.002", "static let restatementTolerance = 0.02"),
    ("only the anchor is restated", "return anchor.map(near) == true || recent.contains(where: near)", "return anchor.map(near) == true"),
    # The feed
    ("a stale report taken", "        guard PointerPresence.isFresh(seen: seen, sentOnSession: sentOnSession, movePending: movePending) else { return .stale }\n", ""),
    ("no carry-over", "        carrying = control == .here\n        return carrying\n", "        carrying = false\n        return control == .here\n"),
    ("the carry-over outlasts input", "        control = .here\n        carrying = false\n", "        control = .here\n"),
    ("the carry-over outlasts news", "            return .restatement\n        }\n        carrying = false\n", "            return .restatement\n        }\n"),
    ("positions of any age are recent", "recent.filter { now - $0.at <= Self.recentFor }.map(\\.point)", "recent.map(\\.point)"),
    ("a scroll's location is not remembered", "        case .scroll(let p):\n            remember(p, now: now)\n", "        case .scroll:\n            break\n"),
    ("the anchor ignores the Mac's position", "            mac = position\n            anchor = position\n", "            mac = position\n"),
    ("the anchor ignores this device's pointer", "            anchor = p\n            remember(p, now: now)\n", "            remember(p, now: now)\n"),
    ("a scroll moves the anchor", "        case .scroll(let p):\n            remember(p, now: now)\n", "        case .scroll(let p):\n            anchor = p\n            remember(p, now: now)\n"),
    ("takeovers on every report", "        if tookOver { takeovers += 1 }\n", "        takeovers += 1\n"),
    ("off the stream keeps the arrow", "        macInside = position != nil\n", "        if position != nil { macInside = true }\n"),
    ("news always changes something", "changed: before != (control, mac, macInside)", "changed: true"),
    ("input never says it came here", "        return came\n", "        return false\n"),
    ("tearDown forgets the takeovers", "        carrying = false\n        recent = []\n", "        carrying = false\n        recent = []\n        takeovers = 0\n"),
    ("tearDown keeps the anchor", "        macInside = false\n        anchor = nil\n", "        macInside = false\n"),
    ("the last 3 s unbounded", "        if recent.count >= Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit + 1) }\n", ""),
    # The pad
    ("no mid-stroke re-seed", "        guard takeovers != takeoversSeen else { return }\n", "        if true { return }\n"),
    ("a re-seed at every move", "        guard takeovers != takeoversSeen else { return }\n", ""),
    ("a stroke ignores the anchor", "        if let anchor { cursor = Self.clamped(anchor) }\n", ""),
    ("the pad's cursor unclamped", "cursor = Self.clamped(CGPoint(x: Double(cursor.x) + dx, y: Double(cursor.y) + dy))",
     "cursor = CGPoint(x: Double(cursor.x) + dx, y: Double(cursor.y) + dy)"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "PointerPresence.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        b = subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if b.returncode != 0 or not os.path.exists(exe):
            print(f"{name}: did not compile\n{b.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
