"""Mutants of VirtualDesktopSize.swift and DisplayMakeGuard.swift (Sources/SillHost): each changes one of them in one
place, is compiled with the check (main.swift) and must make it fail. A mutant that does not compile is not counted as
caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "virtual-desktop")
os.makedirs(OUT, exist_ok=True)
FILES = {"size": os.path.join(ROOT, "Sources/SillHost/VirtualDesktopSize.swift"),
         "guard": os.path.join(ROOT, "Sources/SillHost/DisplayMakeGuard.swift")}
MUTANTS = [
    # VirtualDesktopSize.device
    ("the room after the panel", "size", "[room, panel].compactMap({ $0 })", "[panel, room].compactMap({ $0 })"),
    ("an unusable room taken", "size", ".first(where: usable)", ".first"),
    ("no rounding to whole points first", "size",
     "var w = Double(source.width).rounded(), h = Double(source.height).rounded()",
     "var w = Double(source.width), h = Double(source.height)"),
    ("a short side under 800 not grown", "size", "        if short < Double(minSide) {", "        if short < 0 {"),
    ("grown by the longer side", "size", "        let short = min(w, h)\n", "        let short = max(w, h)\n"),
    ("grown and not rounded", "size", "            w = (w * grow).rounded(); h = (h * grow).rounded()",
     "            w = (w * grow); h = (h * grow)"),
    ("grown on one side only", "size", "            w = (w * grow).rounded(); h = (h * grow).rounded()",
     "            w = (w * grow).rounded()"),
    ("a long side over 4096 not shrunk", "size", "        if long > Double(maxSide) {", "        if long > 1e9 {"),
    ("shrunk on one side only (the shape lost)", "size", "            w = (w * shrink).rounded(); h = (h * shrink).rounded()",
     "            w = min(w, Double(maxSide)); h = min(h, Double(maxSide))"),
    ("no final hold to 800…4096", "size",
     "        let side = { (v: Double) in Int(min(max(v, Double(minSide)), Double(maxSide))) }",
     "        let side = { (v: Double) in Int(v) }"),
    ("the final hold without its floor", "size",
     "        let side = { (v: Double) in Int(min(max(v, Double(minSide)), Double(maxSide))) }",
     "        let side = { (v: Double) in Int(min(v, Double(maxSide))) }"),
    ("at 1x", "size", "    static let scale = 2\n", "    static let scale = 1\n"),
    ("the floor at 744 (an iPad mini's own)", "size", "    static let minSide = 800\n", "    static let minSide = 744\n"),
    ("the ceiling at 8192 points", "size", "    static let maxSide = 4096\n", "    static let maxSide = 8192\n"),
    ("a side of 0 taken", "size", "s.width > 0 && s.height > 0", "s.width >= 0 && s.height >= 0"),
    ("NaN taken", "size", "s.width.isFinite && s.height.isFinite && ", ""),
    ("the fallback at 1x", "size", "static let fallback = Size(widthPt: 1920, heightPt: 1080, scale: 2)",
     "static let fallback = Size(widthPt: 1920, heightPt: 1080, scale: 1)"),
    # The rate
    ("the rate not held to the Mac's limit", "size", "        min(max(24, limit), max(24, viewportFPS ?? 60))",
     "        max(24, viewportFPS ?? 60)"),
    ("the rate with no viewport 120", "size", "        min(max(24, limit), max(24, viewportFPS ?? 60))",
     "        min(max(24, limit), max(24, viewportFPS ?? 120))"),
    ("the rate's floor left out", "size", "        min(max(24, limit), max(24, viewportFPS ?? 60))",
     "        min(max(24, limit), viewportFPS ?? 60)"),
    ("the limit's floor left out", "size", "        min(max(24, limit), max(24, viewportFPS ?? 60))",
     "        min(limit, max(24, viewportFPS ?? 60))"),
    # Whose viewport
    ("the newest before the asker", "size", "        if let asker, sent.contains(asker) { return asker }\n", ""),
    ("an asker without a viewport taken", "size", "        if let asker, sent.contains(asker) { return asker }",
     "        if let asker { return asker }"),
    ("the newest without one taken", "size", "        if let newest, sent.contains(newest) { return newest }",
     "        if let newest { return newest }"),
    ("no newest at all", "size", "        if let newest, sent.contains(newest) { return newest }\n", ""),
    # The rate held
    ("Sill's display's rate never held to", "size", "        stop ?? (onSills ? sills : nil)", "        stop"),
    ("Sill's display's rate held off it too", "size", "        stop ?? (onSills ? sills : nil)", "        stop ?? sills"),
    ("Sill's display's rate before the stop's", "size", "        stop ?? (onSills ? sills : nil)",
     "        (onSills ? sills : nil) ?? stop"),
    # The line
    ("the mode asked said as the one it came up at", "size",
     "        let mode = \"\\(came.widthPt)×\\(came.heightPt) pt @\\(came.scale)× at \\(hz) Hz\"",
     "        let mode = \"\\(asked.widthPt)×\\(asked.heightPt) pt @\\(asked.scale)× at \\(hz) Hz\""),
    ("what was asked never said", "size", "        let askedWords = came == asked ? \"\" :",
     "        let askedWords = true ? \"\" :"),
    ("whose screen left out", "size", "device.map { \"for \\($0), its screen\" }", "device.map { _ in \"for a device\" }"),
    # DisplayMakeGuard
    ("trips at three", "guard", "    static let tripAt = 2\n", "    static let tripAt = 3\n"),
    ("trips at one", "guard", "    static let tripAt = 2\n", "    static let tripAt = 1\n"),
    ("a marker not counted", "guard", "        max(0, stops) + (markerFound ? 1 : 0)", "        max(0, stops)"),
    ("every launch counted", "guard", "        max(0, stops) + (markerFound ? 1 : 0)", "        max(0, stops) + 1"),
    ("a negative count kept", "guard", "        max(0, stops) + (markerFound ? 1 : 0)", "        stops + (markerFound ? 1 : 0)"),
    ("holds from one more", "guard", "    static func holds(stops: Int) -> Bool { stops >= tripAt }",
     "    static func holds(stops: Int) -> Bool { stops > tripAt }"),
    ("a display up resets nothing", "guard", "    static func afterMake(cameUp: Bool, stops: Int) -> Int { cameUp ? 0 : stops }",
     "    static func afterMake(cameUp: Bool, stops: Int) -> Int { stops }"),
    ("a failed make resets the count", "guard", "    static func afterMake(cameUp: Bool, stops: Int) -> Int { cameUp ? 0 : stops }",
     "    static func afterMake(cameUp: Bool, stops: Int) -> Int { 0 }"),
    ("the marker's time local", "guard", "        f.timeZone = TimeZone(identifier: \"UTC\")\n", "        f.timeZone = TimeZone(identifier: \"America/New_York\")\n"),
    ("any role read back", "guard", "        guard parts.count == 2, [\"stage\", \"desktop\"].contains(String(parts[0])), ",
     "        guard parts.count == 2, "),
    ("a marker's words never read back", "guard",
     "        let which = parse(marker).map {", "        let which = parse(\"\").map {"),
    ("the launch line when no marker", "guard", "        guard let marker else { return nil }\n",
     "        let marker = marker ?? \"\"\n"),
    ("Try Again's place left out", "guard", "+ \"it makes none by itself until you choose Try Again in Settings › Virtual Display.\"",
     "+ \"it makes none by itself.\""),
    ("the marker left at launch", "guard", "                try? FileManager.default.removeItem(at: marker)\n                writeStops(stops)",
     "                writeStops(stops)"),
    ("the count not kept at launch", "guard", "                try? FileManager.default.removeItem(at: marker)\n                writeStops(stops)",
     "                try? FileManager.default.removeItem(at: marker)"),
    ("an empty marker not counted", "guard",
     "?? (FileManager.default.fileExists(atPath: marker.path) ? \"\" : nil)", "?? nil"),
    ("the marker never written", "guard", "            guard FileManager.default.createFile(atPath: url.path, contents: data),",
     "            guard false, FileManager.default.createFile(atPath: url.path, contents: data),"),
    ("the marker left after a make", "guard",
     "        func made(cameUp: Bool) {\n            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.markerName))\n",
     "        func made(cameUp: Bool) {\n"),
    ("a reset not kept", "guard", "            if after != stops { stops = after; writeStops(after) }", "            if after != stops { stops = after }"),
    ("a clean quit counts", "guard",
     "        func quitting() {\n            try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.markerName))\n",
     "        func quitting() {\n"),
    ("Try Again not kept", "guard", "            stops = 0\n            writeStops(0)\n", "            stops = 0\n"),
    ("Try Again keeps holding", "guard", "            stops = 0\n            writeStops(0)\n", "            writeStops(0)\n"),
    ("the test store's count not read", "guard",
     "readStops: { Int(((try? String(contentsOf: file, encoding: .utf8)) ?? \"\").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 },",
     "readStops: { 0 },"),
]
caught = 0
for name, which, old, new in MUTANTS:
    path = FILES[which]
    orig = open(path).read()
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, os.path.basename(path))
    open(src, "w").write(orig.replace(old, new, 1))
    other = [p for k, p in FILES.items() if k != which]
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, *other, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    os.remove(src)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe, OUT], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
    else:
        print(f"{name}: NOT CAUGHT")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
