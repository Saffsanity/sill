"""H2 (docs/iphone-portrait-plan.md): each mutant changes PhonePortraitLayout.swift in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "phone-portrait")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 16:9 for 16:10": ("static let aspect: CGFloat = 1.6", "static let aspect: CGFloat = 16.0 / 9.0"),
    "M2 the picture's height rounded up": ("(pictureWidth / Self.aspect).rounded(.down)", "(pictureWidth / Self.aspect).rounded(.up)"),
    "M3 no minimum trackpad": ("let pictureHeight = min(natural, max(0, height - Self.fixedHeight - Self.minTrackpad))",
                               "let pictureHeight = natural"),
    "M4 the margin under the picture dropped": ("y: picture.maxY + Self.margin + Self.underPicture", "y: picture.maxY + Self.underPicture"),
    "M5 the strip above row 1": ("strip = CGRect(x: Self.side - Self.stripInset, y: row1.maxY + Self.band + Self.rowGap,",
                                 "strip = CGRect(x: Self.side - Self.stripInset, y: row1.minY - Self.rowGap - Self.stripHeight,"),
    "M6 row 1's width without its gaps": ("buttons = Self.split(row1, count: Button.allCases.count, gap: Self.gap)",
                                          "buttons = Self.split(row1, count: Button.allCases.count, gap: 0)"),
    "M7 one gap too many in a row": ("(row.width - CGFloat(count - 1) * gap)", "(row.width - CGFloat(count) * gap)"),
    "M8 the caps' gap 10": ("caps = Self.split(keys, count: Self.capCount, gap: Self.gap)", "caps = Self.split(keys, count: Self.capCount, gap: 10)"),
    "M9 seven caps": ("static let capCount = 6", "static let capCount = 7"),
    "M10 the trackpad to the edge": ("height: max(0, height - Self.bottom - padTop))", "height: max(0, height - padTop))"),
    "M11 the span as the pad's height": ("trackpadSpan = trackpad.width / Self.aspect", "trackpadSpan = trackpad.height"),
    "M12 the ruler's step never reduced": ("let rulerStep = max(0, min(maxRulerStep, room / rulerSpans))", "let rulerStep = maxRulerStep"),
    "M13 the ruler on Keyboard": ("(ruler, rulerStep) = Self.ruler(on: buttons[Button.textSize.rawValue], in: row1)",
                                  "(ruler, rulerStep) = Self.ruler(on: buttons[Button.keyboard.rawValue], in: row1)"),
    "M14 the drawer over row 1": ("drawer = CGRect(x: Self.side, y: panelTop,", "drawer = CGRect(x: Self.side, y: row1.minY,"),
    "M15 the panel 360 wide at the trailing edge": ("settings = CGRect(x: Self.side, y: panelTop, width: rowWidth,",
                                                    "settings = CGRect(x: width - Self.side - min(360, rowWidth), y: panelTop, width: min(360, rowWidth),"),
    "M16 one dim over row 1": ("dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),", "dim = [CGRect(x: 0, y: 0, width: width, height: row1.maxY),"),
    "M17 the anchor from row 1's top": ("y: height > 0 ? settings.minY / height : 0)", "y: height > 0 ? row1.minY / height : 0)"),
    "M18 the strip not widened": ("strip = CGRect(x: Self.side - Self.stripInset,", "strip = CGRect(x: Self.side,"),
    "M19 the panels without their gap": ("let panelTop = row1.maxY + Self.panelGap", "let panelTop = row1.maxY"),
    "M20 the drawer 380 wide": ("drawer = CGRect(x: Self.side, y: panelTop, width: rowWidth,",
                                "drawer = CGRect(x: Self.side, y: panelTop, width: min(380, rowWidth),"),
    "M21 the picture at the top edge": ("picture = CGRect(x: Self.margin, y: Self.margin,", "picture = CGRect(x: Self.margin, y: 0,"),
    "M22 the rows 8 pt from the sides": ("static let side: CGFloat = 14", "static let side: CGFloat = 8"),
    "M23 row 3 without its gap": ("keys = CGRect(x: Self.side, y: strip.maxY + Self.rowGap,", "keys = CGRect(x: Self.side, y: strip.maxY,"),
    "M24 the trackpad's least height 100": ("static let minTrackpad: CGFloat = 120", "static let minTrackpad: CGFloat = 100"),
    "M25 row 1 without its band above": ("y: picture.maxY + Self.margin + Self.underPicture + Self.band,",
                                         "y: picture.maxY + Self.margin + Self.underPicture,"),
    "M26 the strip without row 1's band under it": ("y: row1.maxY + Self.band + Self.rowGap,", "y: row1.maxY + Self.rowGap,"),
    "M27 the fixed height without the band": ("margin + margin + underPicture + band + buttonHeight + band + rowGap",
                                              "margin + margin + underPicture + buttonHeight + rowGap"),
    "M28 the band 4 pt": ("static let band: CGFloat = 6", "static let band: CGFloat = 4"),
    "M29 the Menus button under Aa": ("let settingsButton = buttons[Button.settings.rawValue]", "let settingsButton = buttons[Button.textSize.rawValue]"),
    "M30 the strip running under the Menus button": ("width: max(0, menus.minX - Self.gap - strip.minX)", "width: strip.width"),
    "M31 the Menus button at the strip's top": ("y: strip.minY + (Self.stripHeight - Self.buttonHeight) / 2,", "y: strip.minY,"),
    # Larger Picture (docs/larger-picture-plan.md).
    "L1 no clearance above the keyboard": ("static let keyboardClearance: CGFloat = 10", "static let keyboardClearance: CGFloat = 0"),
    "L2 the room's fixed height without the clearance": ("band + capHeight + rowGap + keyboardClearance", "band + capHeight + rowGap"),
    "L3 the room 16:10 whatever the keyboard": ("height: largerHeight ?? pictureHeight)", "height: pictureHeight)"),
    "L4 no least footprint": ("let footprint = keyboard.map { max($0, Self.minTrackpad + Self.bottom) }", "let footprint = keyboard"),
    "L5 the thumbnails' row kept": ("size: CGSize(width: max(0, width - 2 * (Self.side - Self.stripInset)), height: 0))",
                                    "size: CGSize(width: max(0, width - 2 * (Self.side - Self.stripInset)), height: Self.stripHeight))"),
    "L6 Menus at row 1's end": ("menus = six[1]", "menus = six[5]"),
    "L7 row 1 beside the menus as without them": ("buttonsBesideMenus = [six[0]] + six.dropFirst(2)", "buttonsBesideMenus = buttons"),
    "L8 the trackpad not from the keyboard's exact top": ("if let footprint { padTop = max(keys.maxY + Self.keyboardClearance, height - footprint) }",
                                                          "if let footprint { padTop = keys.maxY + Self.keyboardClearance + 0 * footprint }"),
    "L9 the frame the whole room": ("let tall = picture.width * h / w", "let tall = picture.height"),
    "L10 the frame against row 1": ("return CGRect(x: picture.minX, y: picture.minY, width: picture.width,",
                                    "return CGRect(x: picture.minX, y: picture.maxY - min(picture.height, (tall + 0.01).rounded(.down)), width: picture.width,"),
    "L11 the frame without its hundredth": ("height: min(picture.height, (tall + 0.01).rounded(.down)))", "height: min(picture.height, tall.rounded(.down)))"),
    "L12 a tall frame not centred": ("return CGRect(x: picture.minX + ((picture.width - wide) / 2).rounded(.down), y: picture.minY,",
                                     "return CGRect(x: picture.minX, y: picture.minY,"),
    "L13 the span as today's with the switch on": ("return trackpad.width * frame.height / frame.width", "return trackpadSpan"),
    "L14 the Home-button shape at 1.7": ("static let faceIDShape: CGFloat = 1.9", "static let faceIDShape: CGFloat = 1.7"),
    "L15 the wide keyboard from 428 (the 11 and the Air at 301)": ("static let wideKeyboardFrom: CGFloat = 414", "static let wideKeyboardFrom: CGFloat = 428"),
    "L16 the switch ignored": ("guard largerPicture, !foldable else { return nil }", "guard !foldable else { return nil }"),
    "L17 the hinge ignored": ("guard largerPicture, !foldable else { return nil }", "guard largerPicture else { return nil }"),
    "L18 the six-button ruler on the five's Aa": ("(rulerBesideMenus, rulerStepBesideMenus) = Self.ruler(on: buttonsBesideMenus[Button.textSize.rawValue], in: row1)",
                                                  "(rulerBesideMenus, rulerStepBesideMenus) = Self.ruler(on: buttons[Button.textSize.rawValue], in: row1)"),
    "L19 the room not in whole points": ("max(0, (height - $0 - Self.largerFixedHeight).rounded(.down))", "max(0, height - $0 - Self.largerFixedHeight)"),
    "L20 the SE's keyboard the classic 216": ("static let homeButtonKeyboard: CGFloat = 233", "static let homeButtonKeyboard: CGFloat = 216"),
    "L21 Menus before Apps": ("menus = six[1]", "menus = six[0]"),
    "L22 16:9 before the first frame": ("let (w, h) = known ? (video.width, video.height) : (Self.aspect, 1)", "let (w, h) = known ? (video.width, video.height) : (16, 9)"),
    "L23 the Face ID keyboard 291": ("static let faceIDKeyboard: CGFloat = 301", "static let faceIDKeyboard: CGFloat = 291"),
    "L24 the frame never wider than tall": ("if tall <= picture.height + 0.01 {", "if tall <= picture.height + 0.01 && tall >= picture.width {"),
    "L25 the minis' keyboard as the others' 301": ("static let miniKeyboard: CGFloat = 310", "static let miniKeyboard: CGFloat = 301"),
    "L26 the 301 keyboard from 375": ("static let faceIDKeyboardFrom: CGFloat = 390", "static let faceIDKeyboardFrom: CGFloat = 375"),
    "L27 Display Zoom's keyboard 301": ("if container.width >= miniKeyboardFrom { return miniKeyboard }\n        return wideKeyboard",
                                        "if container.width >= miniKeyboardFrom { return miniKeyboard }\n        return faceIDKeyboard"),
    "L28 the minis' keyboard from 360": ("static let miniKeyboardFrom: CGFloat = 375", "static let miniKeyboardFrom: CGFloat = 360"),
    # Larger Picture only where it is larger (the review of 2026-10-14).
    "N1 a room no taller than today's picture allowed": ("return larger.picture.height > PhonePortraitLayout(size: container).picture.height",
                                                         "return larger.picture.height >= PhonePortraitLayout(size: container).picture.height"),
    "N2 the room left unchecked (Display Zoom's smaller picture)": ("return larger.picture.height > PhonePortraitLayout(size: container).picture.height",
                                                                    "return true"),
    "N3 row 1's six buttons down to 40 pt": ("static let minButtonWidth: CGFloat = 44", "static let minButtonWidth: CGFloat = 40"),
    "N4 the six buttons left unchecked": ("&& larger.menus.width >= minButtonWidth", "&& larger.menus.width >= 0"),
    "N5 the keyboard whatever the gain": ("return largerPictureGains(container, keyboard: keyboard) ? keyboard : nil", "return keyboard"),
    "N6 the switch judged on the screen as it is held": ("let upright = CGSize(width: min(screen.width, screen.height), height: max(screen.width, screen.height))",
                                                         "let upright = screen"),
    # Larger Picture's drawer above row 1, clear of the keyboard (the review of 2026-10-14).
    "D1 the drawer under row 1 with Larger Picture": ("drawer = CGRect(x: Self.side, y: Self.margin, width: rowWidth, height: max(0, row1.minY - Self.panelGap - Self.margin))",
                                                      "drawer = CGRect(x: Self.side, y: panelTop, width: rowWidth, height: panelHeight)"),
    "D2 the drawer against row 1 without its gap": ("height: max(0, row1.minY - Self.panelGap - Self.margin))", "height: max(0, row1.minY - Self.margin))"),
    "D3 the drawer from the screen's top edge": ("drawer = CGRect(x: Self.side, y: Self.margin,", "drawer = CGRect(x: Self.side, y: 0,"),
    # Larger Picture only while a window streams (Noah, 2026-10-15: the Desktop's negative space).
    "S1 the Desktop with Larger Picture": ("switchOn && streaming == .window", "switchOn && streaming != .nothing"),
    "S2 nothing streaming with Larger Picture": ("switchOn && streaming == .window", "switchOn && streaming != .desktop"),
    "S3 what streams ignored (the Desktop and nothing with Larger Picture, as before 2026-10-15)": ("switchOn && streaming == .window", "switchOn"),
    "S4 the switch ignored while a window streams": ("switchOn && streaming == .window", "streaming == .window"),
    "S5 the rule turned around (the Desktop larger, a window not)": ("switchOn && streaming == .window", "switchOn && streaming != .window"),
    # Full Screen (Raffael, 2026-10-21).
    "F1 the keyboard ignored": ("let lift = max(bottom, keyboard.map { $0 + PhonePortraitLayout.keyboardClearance } ?? 0, Self.pad)",
                                "let lift = max(bottom, Self.pad)"),
    "F2 the keyboard's clearance dropped": ("keyboard.map { $0 + PhonePortraitLayout.keyboardClearance }", "keyboard.map { $0 }"),
    "F3 the home indicator ignored": ("let lift = max(bottom, keyboard", "let lift = max(0, keyboard"),
    "F4 the handle on row 1": ("y: row1.minY - PhonePortraitLayout.band - Self.handleHeight,", "y: row1.minY - Self.handleHeight,"),
    "F5 the drawer under the status bar": ("let panelTop = max(top, Self.pad) + PhonePortraitLayout.panelGap", "let panelTop = Self.pad + PhonePortraitLayout.panelGap"),
    "F6 the drawer over the controls": ("let panelBottom = (expanded ? ground.minY : handle.minY) - PhonePortraitLayout.panelGap",
                                        "let panelBottom = handle.minY - PhonePortraitLayout.panelGap"),
    "F7 the dim over the controls": ("dim = [CGRect(x: 0, y: 0, width: width, height: max(0, expanded ? ground.minY : handle.minY))]",
                                     "dim = [CGRect(x: 0, y: 0, width: width, height: height)]"),
    "F9 full screen's Menus at the row's end": ("menus = withMenus.remove(at: 1)", "menus = withMenus.remove(at: 5)"),
    "F8 the picture behind the controls": ("height: max(0, (expanded ? ground.minY : handle.minY - Self.pad) - top))",
                                           "height: height - top)"),
    "F10 the picture behind the notch": ("picture = CGRect(x: 0, y: top, width: width,", "picture = CGRect(x: 0, y: 0, width: width,"),
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
