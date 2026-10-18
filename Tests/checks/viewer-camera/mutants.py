"""docs/iphone-viewer-plan.md: each mutant changes ViewerCamera.swift in one place and must fail the
check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "viewer-camera")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/ViewerCamera.swift")
orig = open(SRC).read()
MUTANTS = {
    "V1 fitted to fill (max for min)": ("let s = min(screen.width / video.width, screen.height / video.height)",
                                        "let s = max(screen.width / video.width, screen.height / video.height)"),
    "V2 no zoom cap": ("static let maxZoom: CGFloat = 8", "static let maxZoom: CGFloat = 80"),
    "V3 zoom below fit allowed": ("zoom = min(Self.maxZoom, max(1, zoom * scale))", "zoom = min(Self.maxZoom, max(0.5, zoom * scale))"),
    "V4 a smaller picture not centred": ("if size <= screen + ViewerCamera.slack { return (screen - size) / 2 }",
                                         "if size <= screen + ViewerCamera.slack { return 0 }"),
    "V5 a gap allowed at the start": ("return min(0, max(screen - size, screen / 2 - center * size))",
                                      "return max(screen - size, screen / 2 - center * size)"),
    "V6 a gap allowed at the end": ("return min(0, max(screen - size, screen / 2 - center * size))",
                                    "return min(0, screen / 2 - center * size)"),
    "V7 the edge band 22": ("static let edge: CGFloat = 44", "static let edge: CGFloat = 22"),
    "V8 the push the wrong way": ("if at.x < edgeX { r.origin.x += edgeX - at.x; moved = true }",
                                  "if at.x < edgeX { r.origin.x -= edgeX - at.x; moved = true }"),
    "V9 the right edge never pushed": ("else if at.x > screen.width - edgeX { r.origin.x -= at.x - (screen.width - edgeX); moved = true }",
                                       "else if at.x > screen.width { r.origin.x -= at.x - screen.width; moved = true }"),
    "V10 the band not a quarter on a small screen": ("let edgeX = min(Self.edge, screen.width / 4), edgeY = min(Self.edge, screen.height / 4)",
                                                     "let edgeX = Self.edge, edgeY = Self.edge"),
    "V11 no slack (floating point moves a fitted picture)": ("static let slack: CGFloat = 0.5", "static let slack: CGFloat = 0"),
    "V12 the pinch pans from `from` not `to`": ("settle(CGRect(x: to.x - fx * size.width, y: to.y - fy * size.height,",
                                                "settle(CGRect(x: from.x - fx * size.width, y: from.y - fy * size.height,"),
    "V13 center not written back from the clamp": ("        let clamped = rect\n        center = CGPoint(x: (screen.width / 2 - clamped.minX) / clamped.width,\n                         y: (screen.height / 2 - clamped.minY) / clamped.height)\n", ""),
    "V14 Fill does not fill (min)": ("return min(Self.maxZoom, max(1, max(screen.width / f.width, screen.height / f.height)))",
                                     "return min(Self.maxZoom, max(1, min(screen.width / f.width, screen.height / f.height)))"),
    "V15 Fit keeps the zoom": ("        if isZoomedIn {\n            zoom = 1\n", "        if isZoomedIn {\n            zoom = max(zoom, 1)\n"),
    "V16 Fill ignores the focus": ("            if let focus { center = focus }\n", ""),
    "V17 a rotation not clamped": ("        if r.width > 0, r.height > 0 { settle(r) }\n", ""),
    "V18 the vertical push forgotten": ("if at.y < edgeY { r.origin.y += edgeY - at.y; moved = true }", "if at.y < edgeY { moved = true }"),
    "V19 a zero scale taken": ("guard before.width > 0, before.height > 0, scale > 0 else { return }", "guard before.width > 0, before.height > 0 else { return }"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
