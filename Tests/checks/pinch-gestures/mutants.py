"""Mutants of PinchGestures.swift (Sources/SillHost): each changes it in one place, is compiled with the
check by build.sh and must make the check fail.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
P = "Sources/SillHost/PinchGestures.swift"
MUTANTS = [
    # The pointer
    ("the pointer never moves", P, "if hypot(pointer.x - location.x, pointer.y - location.y) > Self.pointerSlop { move = location }", "_ = pointer"),
    ("the pointer always moves", P, "if hypot(pointer.x - location.x, pointer.y - location.y) > Self.pointerSlop { move = location }", "move = location"),
    ("the pointer slop ten points", P, "package static let pointerSlop = 1.0", "package static let pointerSlop = 10.0"),
    ("the second gesture moves the pointer too", P,
     "            if at == nil || open.isEmpty {\n                // The first of the two",
     "            if true {\n                // The first of the two"),
    # Where
    ("a change posted where the device says", P, "            return Step(movePointerTo: nil, posts: [Post(kind, .changed, value, at: at)])",
     "            return Step(movePointerTo: nil, posts: [Post(kind, .changed, value, at: location)])"),
    ("an end posted where the device says", P, "            return Step(movePointerTo: nil, posts: [Post(kind, .ended, value, at: at)])",
     "            return Step(movePointerTo: nil, posts: [Post(kind, .ended, value, at: location)])"),
    ("the second gesture's began where the device says", P, "            let place = at ?? location\n", "            let place = location\n"),
    ("the place kept after the last end", P, "            if open.isEmpty { self.at = nil }\n", ""),
    # Order
    ("a began over an open one does not end it first", P,
     "            if open.contains(kind), let at { ending.append(Post(kind, .ended, 0, at: at)); open.remove(kind) }\n", ""),
    ("the end of the one before posted after the pointer moved", P,
     "            return Step(ending: ending, movePointerTo: move, posts: [Post(kind, .began, value, at: place)])",
     "            return Step(ending: [], movePointerTo: move, posts: ending + [Post(kind, .began, value, at: place)])"),
    ("a change with none open goes", P, "            guard open.contains(kind), let at else { return .nothing }\n            return Step(movePointerTo: nil, posts: [Post(kind, .changed",
     "            guard let at = at ?? Optional(location) else { return .nothing }\n            return Step(movePointerTo: nil, posts: [Post(kind, .changed"),
    ("an end with none open goes", P, "            guard open.contains(kind), let at else { return .nothing }\n            open.remove(kind)",
     "            guard let at = at ?? Optional(location) else { return .nothing }\n            open.remove(kind)"),
    ("an end leaves its gesture open", P, "            open.remove(kind)\n            if open.isEmpty", "            if open.isEmpty"),
    ("one kind's change goes for the other's open", P, "        case .changed:\n            guard open.contains(kind), let at",
     "        case .changed:\n            guard !open.isEmpty, let at"),
    # The values
    ("no bound on the magnification", P, "let bound = kind == .magnify ? Self.maxMagnification : Self.maxDegrees", "let bound = kind == .magnify ? Double.greatestFiniteMagnitude : Self.maxDegrees"),
    ("no bound on the turn", P, "let bound = kind == .magnify ? Self.maxMagnification : Self.maxDegrees", "let bound = kind == .magnify ? Self.maxMagnification : Double.greatestFiniteMagnitude"),
    ("the turn bounded as a magnification", P, "let bound = kind == .magnify ? Self.maxMagnification : Self.maxDegrees", "let bound = Self.maxMagnification"),
    ("only the top bound", P, "let value = min(max(raw, -bound), bound)", "let value = min(raw, bound)"),
    ("a value that is not a number goes", P, "guard raw.isFinite, location.x.isFinite", "guard location.x.isFinite"),
    ("a place that is not a number goes", P, "guard raw.isFinite, location.x.isFinite, location.y.isFinite else { return .nothing }",
     "guard raw.isFinite else { return .nothing }"),
    ("the bound on a doubling at two", P, "package static let maxMagnification = 1.0", "package static let maxMagnification = 2.0"),
    # The watchdog and the end
    ("the watchdog ends nothing", P, "    package mutating func idle() -> [Post] { closeAll() }", "    package mutating func idle() -> [Post] { [] }"),
    ("the host's end ends nothing", P, "    package mutating func releaseAll() -> [Post] { closeAll() }", "    package mutating func releaseAll() -> [Post] { [] }"),
    ("an end closes only the pinch", P, "let posts = Kind.allCases.filter { open.contains($0) }", "let posts = [Kind.magnify].filter { open.contains($0) }"),
    ("an end leaves them open", P, "        open = []\n        self.at = nil\n        return posts", "        return posts"),
    ("an end's value the last one, not 0", P, ".map { Post($0, .ended, 0, at: at) }", ".map { Post($0, .ended, 1, at: at) }"),
    ("the watchdog's second three", P, "package static let idleTimeout = 1.0", "package static let idleTimeout = 3.0"),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(WT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{os.path.basename(rel)}={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else r.stdout.strip()[-150:]})")
        else:
            print(f"{name}: SURVIVED")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
