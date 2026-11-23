"""Each mutant changes iOSClient/PhoneKeyboardLift.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "phone-keyboard-lift")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PhoneKeyboardLift.swift")
LAYOUT = os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift")
orig = open(SRC).read()
MUTANTS = {
    # The key row's clearance and the lift.
    "K1 no clearance above the keyboard": ("keysTop + L.capHeight + L.keyboardClearance - $0", "keysTop + L.capHeight - $0"),
    "K2 the lift not in whole points": ("max(0, needed.rounded(.up))", "max(0, needed)"),
    "K3 the lift rounded down": ("needed.rounded(.up)", "needed.rounded(.down)"),
    "K4 no ceiling (rows over the picture's top)": ("let lifted = min(layout.picture.height, max(0, needed.rounded(.up)))",
                                                    "let lifted = max(0, needed.rounded(.up))"),
    "K5 a negative lift (rows pushed down for a short keyboard)": ("min(layout.picture.height, max(0, needed.rounded(.up)))",
                                                                   "min(layout.picture.height, needed.rounded(.up))"),
    "K6 a keyboard at the screen's foot counted": ("glass.flatMap { $0 < height ? $0 : nil }", "glass.flatMap { $0 <= height ? $0 : nil }"),
    "K7 any glass counted, under the foot too": ("let top: CGFloat? = glass.flatMap { $0 < height ? $0 : nil }", "let top: CGFloat? = glass"),
    "K8 the keyboard ignored (main's fault)": ("let needed = top.map { keysTop", "let needed = top.map { _ in 0 } ?? top.map { keysTop"),
    # Hide Thumbnails While Typing.
    "T1 the switch ignored": ("tucked = tuck && top != nil && !layout.largerPicture", "tucked = false && tuck && top != nil && !layout.largerPicture"),
    "T2 tucked whenever a keyboard is up": ("tucked = tuck && top != nil && !layout.largerPicture", "tucked = top != nil && !layout.largerPicture"),
    "T3 tucked without a keyboard": ("tucked = tuck && top != nil && !layout.largerPicture", "tucked = tuck && !layout.largerPicture"),
    "T4 tucked in Larger Picture": ("tucked = tuck && top != nil && !layout.largerPicture", "tucked = tuck && top != nil"),
    "T5 the tucked key row at the thumbnails' foot": ("let keysTop = tucked ? layout.strip.minY : layout.keys.minY",
                                                      "let keysTop = tucked ? layout.strip.maxY : layout.keys.minY"),
    "T6 the tucked key row where it was": ("let keysTop = tucked ? layout.strip.minY : layout.keys.minY", "let keysTop = layout.keys.minY"),
    "T7 moved without the tuck": ("var moved: Bool { tucked || lift > 0 }", "var moved: Bool { lift > 0 }"),
    # What lifts.
    "R1 row 1 left behind": ("row1 = layout.row1.offsetBy(dx: 0, dy: up)", "row1 = layout.row1"),
    "R2 row 1's buttons left behind": ("buttons = layout.buttons.map { $0.offsetBy(dx: 0, dy: up) }", "buttons = layout.buttons"),
    "R3 the six beside the menus left behind": ("buttonsBesideMenus = layout.buttonsBesideMenus.map { $0.offsetBy(dx: 0, dy: up) }",
                                                "buttonsBesideMenus = layout.buttonsBesideMenus"),
    "R4 Menus left behind": ("menus = layout.menus.offsetBy(dx: 0, dy: up)", "menus = layout.menus"),
    "R5 the thumbnails left behind": ("strip = layout.strip.offsetBy(dx: 0, dy: up)", "strip = layout.strip"),
    "R6 the thumbnails beside Menus left behind": ("stripBesideMenus = layout.stripBesideMenus.offsetBy(dx: 0, dy: up)",
                                                   "stripBesideMenus = layout.stripBesideMenus"),
    "R7 the ruler left behind": ("ruler = layout.ruler.offsetBy(dx: 0, dy: up)", "ruler = layout.ruler"),
    "R8 the six's ruler left behind": ("rulerBesideMenus = layout.rulerBesideMenus.offsetBy(dx: 0, dy: up)", "rulerBesideMenus = layout.rulerBesideMenus"),
    "R9 the key row lifted twice": ("let keysY = keysTop - lifted", "let keysY = keysTop - 2 * lifted"),
    "R10 the caps where they were": ("caps = layout.caps.map { CGRect(x: $0.minX, y: keysY, width: $0.width, height: $0.height) }",
                                     "caps = layout.caps"),
    # The trackpad, the drawer, the dim.
    "P1 the trackpad as laid out whatever moved": ("let padTop = tucked || lifted > 0 ? keys.maxY + L.rowGap : layout.trackpad.minY",
                                                   "let padTop = layout.trackpad.minY"),
    "P2 the trackpad not following the tucked key row": ("let padTop = tucked || lifted > 0 ?", "let padTop = lifted > 0 ?"),
    "P3 the trackpad against the key row": ("? keys.maxY + L.rowGap : layout.trackpad.minY", "? keys.maxY : layout.trackpad.minY"),
    "P4 the trackpad to the screen's foot": ("height: max(0, height - L.bottom - padTop))", "height: max(0, height - padTop))"),
    "D1 Larger Picture's drawer lifted, not shortened": ("drawer = CGRect(x: layout.drawer.minX, y: layout.drawer.minY, width: layout.drawer.width,\n                            height: max(0, layout.drawer.height - lift))",
                                                         "drawer = CGRect(x: layout.drawer.minX, y: layout.drawer.minY - lift, width: layout.drawer.width,\n                            height: layout.drawer.height)"),
    "D2 the standard drawer not reaching down": ("height: layout.drawer.height + lift)", "height: layout.drawer.height)"),
    "D3 the dim over the lifted row 1": ("dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),", "dim = [CGRect(x: 0, y: 0, width: width, height: layout.row1.minY),"),
    # The room and the frame.
    "F1 the room not shortened": ("height: layout.picture.height - lift)", "height: layout.picture.height)"),
    "F2 the frame never fitted": ("guard laid.height > room.height else { return laid }", "guard laid.height > room.height + 10_000 else { return laid }"),
    "F3 the frame squeezed (its shape lost)": ("let wide = min(room.width, (laid.width * room.height / laid.height + 0.01).rounded(.down))",
                                               "let wide = laid.width"),
    "F4 the frame not in whole points": ("(laid.width * room.height / laid.height + 0.01).rounded(.down))", "(laid.width * room.height / laid.height))"),
    "F5 the frame at the room's leading edge": ("CGRect(x: room.minX + ((room.width - wide) / 2).rounded(.down), y: room.minY,",
                                                "CGRect(x: room.minX, y: room.minY,"),
    "F6 the frame against row 1": ("y: room.minY, width: wide, height: room.height)", "y: room.minY + lift, width: wide, height: room.height)"),
    "F7 Larger Picture's frame the whole room": ("let laid = layout.largerPicture ? layout.pane(video: video) : layout.picture",
                                                 "let laid = layout.picture"),
    # The switch and its words.
    "S1 the switch on by default": ("static let defaultOn = false", "static let defaultOn = true"),
    "S2 another key": ('static let switchKey = "Sill.hideThumbnailsWhileTyping"', 'static let switchKey = "Sill.hideThumbnails"'),
    "S3 offered on an iPad": ("static func offered(phoneArrangement: Bool) -> Bool { phoneArrangement }",
                              "static func offered(phoneArrangement: Bool) -> Bool { true }"),
    "S4 the title": ('static let title = "Hide Thumbnails While Typing"', 'static let title = "Hide Thumbnails"'),
    "S5 the line with no keyboard": ('return "keys: no keyboard"', 'return "keys: none"'),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", LAYOUT, path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
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
