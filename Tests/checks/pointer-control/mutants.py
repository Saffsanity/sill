"""H3 (docs/pointer-visibility-plan.md) mutants of PointerControl.swift (Sources/SillHost) and of kind 26
in StreamProtocol (Pointer.swift, StreamMessage.swift): each changes one file in one place, is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
CONTROL = "Sources/SillHost/PointerControl.swift"
POINTER = "Sources/StreamProtocol/Pointer.swift"
MESSAGE = "Sources/StreamProtocol/StreamMessage.swift"
MUTANTS = [
    # The settle
    ("no settle after a pointer input", CONTROL, "        if movesPointer { sillUntil = max(sillUntil, now + Self.settle) }\n", ""),
    ("keys and text open the settle", CONTROL, "if movesPointer { sillUntil", "if true || movesPointer { sillUntil"),
    ("sillMoved opens no settle", CONTROL, "    mutating func sillMoved(now: Double) {\n        sillUntil = max(sillUntil, now + Self.settle)\n",
     "    mutating func sillMoved(now: Double) {\n"),
    ("a later note cuts the settle short (no max)", CONTROL, "    mutating func sillMoved(now: Double) {\n        sillUntil = max(sillUntil, now + Self.settle)\n",
     "    mutating func sillMoved(now: Double) {\n        sillUntil = now + Self.settle\n"),
    ("the settle's end is inside it", CONTROL, "        if now < sillUntil {", "        if now <= sillUntil {"),
    ("the settle does not follow Sill's motion", CONTROL, "        if now < sillUntil {\n            last = p\n", "        if now < sillUntil {\n"),
    # A real move
    ("`last` moved at every read (a slow drift never hands over)", CONTROL,
     "guard hypot(p.x - from.x, p.y - from.y) >= Self.minMove else { return false }",
     "guard hypot(p.x - from.x, p.y - from.y) >= Self.minMove else { last = p; return false }"),
    ("a move must be more than 0.5 pt", CONTROL, ">= Self.minMove else", "> Self.minMove else"),
    ("a move of 1 pt", CONTROL, "static let minMove: CGFloat = 0.5", "static let minMove: CGFloat = 1"),
    ("a real move leaves the controller", CONTROL, "        controller = .mac\n        return handedOver\n", "        return handedOver\n"),
    ("a hand-over reported while the Mac had it", CONTROL, "let handedOver = controller != .mac", "let handedOver = true"),
    # The gap
    ("no gap: a read after one counts from the old position", CONTROL, "let watched = now - previousAt <= Self.settle", "let watched = true"),
    ("the gap's edge is a gap", CONTROL, "let watched = now - previousAt <= Self.settle", "let watched = now - previousAt < Self.settle"),
    # One controller
    ("only pointer input hands the pointer over", CONTROL, "        controller = .client(client)\n        if movesPointer",
     "        if movesPointer { controller = .client(client) }\n        if movesPointer"),
    ("any device leaving hands the pointer back", CONTROL, "if controller == .client(client) { controller = .mac }", "controller = .mac"),
    # Moving (Q4)
    ("still only after 0.2 s", CONTROL, "static let stillAfter = 0.1", "static let stillAfter = 0.2"),
    ("a change across a gap is motion", CONTROL, "if watched, let before = previous, before != p { changedAt = now }",
     "if let before = previous, before != p { changedAt = now }"),
    # Which inputs move the pointer
    ("a scroll gesture moves nothing", CONTROL, "        case .pointer, .scroll, .scrollGesture: return true\n        case .text, .key: return false\n",
     "        case .pointer, .scroll: return true\n        case .text, .key, .scrollGesture: return false\n"),
    ("an undecodable payload moves the pointer", CONTROL, ".map(movesPointer) ?? false", ".map(movesPointer) ?? true"),
    # The fraction
    ("inside judged after rounding", CONTROL, "let inside = x >= 0 && x < 1 && y >= 0 && y < 1",
     "let inside = MacPointer.rounded(x) >= 0 && MacPointer.rounded(x) < 1 && MacPointer.rounded(y) >= 0 && MacPointer.rounded(y) < 1"),
    ("the column at maxX inside", CONTROL, "let inside = x >= 0 && x < 1 && y >= 0 && y < 1", "let inside = x >= 0 && x <= 1 && y >= 0 && y < 1"),
    ("the row at maxY inside", CONTROL, "let inside = x >= 0 && x < 1 && y >= 0 && y < 1", "let inside = x >= 0 && x < 1 && y >= 0 && y <= 1"),
    ("the column at minX outside", CONTROL, "let inside = x >= 0 && x < 1 && y >= 0 && y < 1", "let inside = x > 0 && x < 1 && y >= 0 && y < 1"),
    ("y against the width", CONTROL, "let y = Double((p.y - r.minY) / r.height)", "let y = Double((p.y - r.minY) / r.width)"),
    ("x from the rectangle's origin ignored", CONTROL, "let x = Double((p.x - r.minX) / r.width)", "let x = Double(p.x / r.width)"),
    ("a non-finite point or rectangle let through", CONTROL, "[r.minX, r.minY, r.width, r.height, p.x, p.y].allSatisfy({ $0.isFinite })", "true"),
    # Kind 26 (StreamProtocol)
    ("rounded to 3 places", POINTER, "(v * 10_000).rounded() / 10_000", "(v * 1_000).rounded() / 1_000"),
    ("rounded toward zero", POINTER, "(v * 10_000).rounded() / 10_000", "(v * 10_000).rounded(.towardZero) / 10_000"),
    ("a position without inside", POINTER, "guard inside == true, let x, let y, x.isFinite, y.isFinite", "guard let x, let y, x.isFinite, y.isFinite"),
    ("a non-finite position", POINTER, "guard inside == true, let x, let y, x.isFinite, y.isFinite", "guard inside == true, let x, let y"),
    ("inside left out of the JSON when false", POINTER, "self.x = x; self.y = y; self.inside = inside; self.seen = seen",
     "self.x = x; self.y = y; self.inside = inside == false ? nil : inside; self.seen = seen"),
    # Numbers no plan will take (250 to 254): a kind renumbered onto a taken one does not compile, so the
    # next kind moves none of these (docs/audio-plan.md §3.1).
    ("kind 26 numbered 251", MESSAGE, "    case macPointer = 26 ", "    case macPointer = 251 "),
    ("kind 26 numbered 252", MESSAGE, "    case macPointer = 26 ", "    case macPointer = 252 "),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(WT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        if rel == CONTROL:
            mf = os.path.join(t, "PointerControl.swift"); open(mf, "w").write(src.replace(old, new, 1))
            args = [os.path.join(HERE, "build.sh"), WT, exe, mf]
        else:
            folder = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), folder)
            open(os.path.join(folder, os.path.basename(rel)), "w").write(src.replace(old, new, 1))
            args = [os.path.join(HERE, "build.sh"), WT, exe, os.path.join(WT, CONTROL), folder]
        subprocess.run(args, capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
