"""Mutants of PictureFit.swift (iOSClient): each changes it in one place and must make the check (main.swift) fail.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "picture-fit")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PictureFit.swift")
orig = open(SRC).read()
MUTANTS = [
    ("F1 three pixels to spare", "    static let spare: CGFloat = 2\n", "    static let spare: CGFloat = 3\n"),
    ("F2 one pixel to spare", "    static let spare: CGFloat = 2\n", "    static let spare: CGFloat = 1\n"),
    ("F3 a picture larger than its pane one for one", "        return wide >= 0 && high >= 0 && wide <= spare + 0.002 && high <= spare + 0.002\n",
     "        return wide <= spare + 0.002 && high <= spare + 0.002\n"),
    ("F4 the height never looked at", "        return wide >= 0 && high >= 0 && wide <= spare + 0.002 && high <= spare + 0.002\n",
     "        return wide >= 0 && wide <= spare + 0.002\n"),
    ("F5 no thousandth of a pixel", "        let wide = pane.width + 0.001 - videoSize.width, high = pane.height + 0.001 - videoSize.height\n",
     "        let wide = pane.width - videoSize.width, high = pane.height - videoSize.height\n"),
    ("F6 the pane in points, not pixels", "        let pane = CGSize(width: bounds.width * s, height: bounds.height * s)\n",
     "        let pane = CGSize(width: bounds.width, height: bounds.height)\n"),
    ("F7 one for one in the middle", "            return CGRect(x: bounds.minX, y: bounds.minY, width: videoSize.width / s, height: videoSize.height / s)\n",
     "            return CGRect(x: bounds.midX - videoSize.width / s / 2, y: bounds.midY - videoSize.height / s / 2, width: videoSize.width / s, height: videoSize.height / s)\n"),
    ("F8 one for one at the pane's size (a hair's scale)", "            return CGRect(x: bounds.minX, y: bounds.minY, width: videoSize.width / s, height: videoSize.height / s)\n",
     "            return bounds\n"),
    ("F9 never one for one", "        if oneToOne(in: bounds, videoSize: videoSize, screenScale: screenScale), let s = screenScale {\n",
     "        if false, let s = screenScale {\n"),
    ("F10 the fit by the larger side (cropped)", "        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)\n",
     "        let scale = max(bounds.width / videoSize.width, bounds.height / videoSize.height)\n"),
    ("F11 the fit at the top", "                      y: bounds.minY + (bounds.height - size.height) / 2,\n", "                      y: bounds.minY,\n"),
    ("F12 no picture drawn somewhere", "        guard usable(videoSize), usable(bounds.size) else { return .zero }\n", ""),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "PictureFit.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
