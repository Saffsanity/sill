"""Mutants of PinchRouting.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. M1-M10 were the pull request's own (#261, mrandika), on its rule of fingers and the
trackpad; its review (2026-11-18) gave the rule three sources, the turn, the two switches and their words,
and these. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "pinch-routing")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PinchRouting.swift")
orig = open(SRC).read()
RULE = "        if zoomOnMac && macTakesPinch { return .mac }\n        return source == .fingers ? .picture : .none\n"
MUTANTS = [
    # Who a pinch belongs to.
    ("P1 a Mac that cannot take the pinch is sent it", RULE,
     "        if zoomOnMac { return .mac }\n        return source == .fingers ? .picture : .none\n"),
    ("P2 Zoom Picture sends the pinch to a Mac that takes it", RULE,
     "        if macTakesPinch { return .mac }\n        return source == .fingers ? .picture : .none\n"),
    ("P3 a trackpad's pinch zooms the picture", RULE,
     "        if zoomOnMac && macTakesPinch { return .mac }\n        return .picture\n"),
    ("P4 fingers' pinch goes nowhere under Zoom Picture", RULE,
     "        if zoomOnMac && macTakesPinch { return .mac }\n        return .none\n"),
    ("P5 a trackpad's pinch the Mac's whatever the choice (the PR's first rule)", RULE,
     "        if source != .fingers { return macTakesPinch ? .mac : .none }\n        if zoomOnMac && macTakesPinch { return .mac }\n        return .picture\n"),
    ("P6 Zoom on Mac only for fingers", RULE,
     "        if zoomOnMac && macTakesPinch && source == .fingers { return .mac }\n        return source == .fingers ? .picture : .none\n"),
    # The turn.
    ("P7 the turn without Rotate on Mac", "rotate && owner(source, zoomOnMac: zoomOnMac, macTakesPinch: macTakesPinch) == .mac",
     "owner(source, zoomOnMac: zoomOnMac, macTakesPinch: macTakesPinch) == .mac"),
    ("P8 the turn while the picture zooms", "rotate && owner(source, zoomOnMac: zoomOnMac, macTakesPinch: macTakesPinch) == .mac", "rotate"),
    # The Mac's flag.
    ("P9 a Mac's 0 takes the pinch", "static func macTakes(_ pinch: Int?) -> Bool { (pinch ?? 0) >= 1 }", "static func macTakes(_ pinch: Int?) -> Bool { pinch != nil }"),
    # The switches.
    ("P10 Zoom on Mac by default", "static let zoomOnMacDefault = false", "static let zoomOnMacDefault = true"),
    ("P11 Rotate on Mac on by default", "static let rotateDefault = false", "static let rotateDefault = true"),
    ("P12 Pinch's key another (the PR's key lost)", 'static let zoomOnMacKey = "Sill.pinchZoomsMac"', 'static let zoomOnMacKey = "Sill.zoomOnMac"'),
    ("P13 Rotate's key another (-Sill.rotateOnMac 1 does nothing)", 'static let rotateKey = "Sill.rotateOnMac"', 'static let rotateKey = "Sill.rotate"'),
    ("P14 the panel's switch ignored", "case let flag as Bool: return flag", "case let flag as Bool: return flag && standard"),
    ("P15 a launch argument's string read as YES alone", "case let text as String: return NSString(string: text).boolValue",
     'case let text as String: return text == "YES"'),
    ("P16 a number read as off", "case let number as NSNumber: return number.boolValue", "case let number as NSNumber: return number.boolValue && false"),
    ("P17 Rotate as stored reads Pinch's key", "on(stored: UserDefaults.standard.object(forKey: rotateKey), standard: rotateDefault)",
     "on(stored: UserDefaults.standard.object(forKey: zoomOnMacKey), standard: rotateDefault)"),
    # The rows.
    ("P18 the control shows what is stored whatever the Mac", "static func shownZoomOnMac(stored: Bool, macTakesPinch: Bool) -> Bool { stored && macTakesPinch }",
     "static func shownZoomOnMac(stored: Bool, macTakesPinch: Bool) -> Bool { stored }"),
    ("P19 the control enabled for every Mac", "static func enabled(macTakesPinch: Bool) -> Bool { macTakesPinch }",
     "static func enabled(macTakesPinch: Bool) -> Bool { true }"),
    ("P20 Rotate's row under Zoom Picture too", "static func rotateRowShown(zoomOnMac: Bool, macTakesPinch: Bool) -> Bool { zoomOnMac && macTakesPinch }",
     "static func rotateRowShown(zoomOnMac: Bool, macTakesPinch: Bool) -> Bool { macTakesPinch }"),
    ("P21 Rotate's row for a Mac that cannot take it", "static func rotateRowShown(zoomOnMac: Bool, macTakesPinch: Bool) -> Bool { zoomOnMac && macTakesPinch }",
     "static func rotateRowShown(zoomOnMac: Bool, macTakesPinch: Bool) -> Bool { zoomOnMac }"),
    # The words.
    ("P22 the footnote without the trackpad's sentence", " On a trackpad, it goes where the pointer is.", ""),
    ("P23 the update line for every Mac", "guard macTakesPinch else { return \"Update Sill on", "guard true else { return \"Update Sill on"),
    ("P24 the segment's other name", 'static func zoomOnMacTitle(mac: String) -> String { "Zoom on \\(mac)" }',
     'static func zoomOnMacTitle(mac: String) -> String { "Zoom App" }'),
    ("P25 Rotate's words without its apps", "in apps that rotate, such as Preview, Photos and Maps.", "in apps."),
    ("P26 the picture's segment the PR's word", 'static let zoomPictureTitle = "Zoom Picture"', 'static let zoomPictureTitle = "Zoom Stream"'),
    # What a surface has open on the Mac (MacPinchSent).
    ("P27 a change reaches a gesture another source opened", "guard let o = open[kind], o.source == source else { return nil }",
     "guard let o = open[kind] else { return nil }"),
    ("P28 a second gesture of a source not joined to the first's place", "for kind in [Kind.magnify, .rotate] { if let o = open[kind], o.source == source { return (o.x, o.y) } }",
     "_ = source"),
    ("P29 an end leaves its gesture open", "mutating func ended(_ kind: Kind) { open[kind] = nil }", "mutating func ended(_ kind: Kind) { }"),
    ("P30 forgetting forgets nothing", "mutating func forget() { open = [:] }", "mutating func forget() { }"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "PinchRouting.swift")
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
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
