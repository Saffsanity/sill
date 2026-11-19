// PinchRouting (iOSClient/PinchRouting.swift) on its own: who a two-finger pinch belongs to (the picture's zoom,
// the Mac's own pinch, or nobody), from fingers on the picture, a trackpad of Sill's own or one connected to an
// iPad, with Pinch at Zoom Picture or Zoom on ‹Mac› and a Mac that takes the pinch or not; whether a turn goes
// too (Rotate on ‹Mac›); the two switches as UserDefaults holds them; and the Settings panel's rows and words.
// PR #261 (mrandika) and its review of 2026-11-18. Who decides a stroke of fingers, a scroll or a pinch, is
// StreamZoom.Stroke's (Tests/checks/stream-zoom).
//   swiftc -O iOSClient/PinchRouting.swift Tests/checks/pinch-routing/main.swift -o check && ./check
import Foundation

typealias R = PinchRouting
// A launch argument in a child run of this check, as `-Sill.pinchZoomsMac 1` gives it (a string in the argument
// domain): it says what it read, and nothing else.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--child" {
    print(R.zoomOnMacStored ? "zoom on mac" : "zoom picture", R.rotateStored ? "rotate on" : "rotate off")
    exit(0)
}
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

// MARK: - Every combination, written out

struct Case { let source: R.Source, zoomOnMac: Bool, macTakes: Bool, owner: R.Owner, what: String }
let table: [Case] = [
    // Fingers on the picture.
    Case(source: .fingers, zoomOnMac: false, macTakes: true,  owner: .picture, what: "fingers, Zoom Picture, a Mac with the pinch: the picture zooms"),
    Case(source: .fingers, zoomOnMac: true,  macTakes: true,  owner: .mac,     what: "fingers, Zoom on Mac, a Mac with the pinch: the Mac's pinch"),
    Case(source: .fingers, zoomOnMac: false, macTakes: false, owner: .picture, what: "fingers, Zoom Picture, a Mac before the pinch: the picture zooms"),
    Case(source: .fingers, zoomOnMac: true,  macTakes: false, owner: .picture, what: "fingers, Zoom on Mac kept, a Mac before the pinch: the picture still zooms"),
    // A trackpad of Sill's own (the on-screen one, or Trackpad mode's over the picture).
    Case(source: .pad, zoomOnMac: false, macTakes: true,  owner: .none, what: "the pad, Zoom Picture: nobody's (its two fingers scroll, as before)"),
    Case(source: .pad, zoomOnMac: true,  macTakes: true,  owner: .mac,  what: "the pad, Zoom on Mac, a Mac with the pinch: the Mac's pinch, at the pointer"),
    Case(source: .pad, zoomOnMac: false, macTakes: false, owner: .none, what: "the pad, Zoom Picture, a Mac before the pinch: nobody's"),
    Case(source: .pad, zoomOnMac: true,  macTakes: false, owner: .none, what: "the pad, Zoom on Mac kept, a Mac before the pinch: nobody's"),
    // A trackpad connected to an iPad: its pinch has no touches.
    Case(source: .pointer, zoomOnMac: false, macTakes: true,  owner: .none, what: "a connected trackpad, Zoom Picture: nobody's (as before #261: it went nowhere)"),
    Case(source: .pointer, zoomOnMac: true,  macTakes: true,  owner: .mac,  what: "a connected trackpad, Zoom on Mac, a Mac with the pinch: the Mac's pinch, at the pointer"),
    Case(source: .pointer, zoomOnMac: false, macTakes: false, owner: .none, what: "a connected trackpad, Zoom Picture, a Mac before the pinch: nobody's"),
    Case(source: .pointer, zoomOnMac: true,  macTakes: false, owner: .none, what: "a connected trackpad, Zoom on Mac kept, a Mac before the pinch: nobody's"),
]
check("the table is every combination once", Set(table.map { "\($0.source)\($0.zoomOnMac)\($0.macTakes)" }).count == 12
      && R.Source.allCases.count == 3)
for c in table {
    check(c.what, R.owner(c.source, zoomOnMac: c.zoomOnMac, macTakesPinch: c.macTakes) == c.owner)
}

// MARK: - What the callers rely on, over all combinations

let bools = [false, true]
var combos: [(source: R.Source, zoomOnMac: Bool, macTakes: Bool, owner: R.Owner)] = []
for s in R.Source.allCases { for z in bools { for m in bools {
    combos.append((s, z, m, R.owner(s, zoomOnMac: z, macTakesPinch: m)))
} } }
check("the Mac is sent a pinch only by a Mac that takes it", combos.allSatisfy { $0.owner != .mac || $0.macTakes })
check("the Mac is sent a pinch only under Zoom on Mac (new behaviour off unless turned on)", combos.allSatisfy { $0.owner != .mac || $0.zoomOnMac })
check("the picture is zoomed only by fingers on it, never by a trackpad", combos.allSatisfy { $0.owner != .picture || $0.source == .fingers })
check("fingers on the picture always belong to the picture or the Mac, so a pinch there is never lost",
      combos.filter { $0.source == .fingers }.allSatisfy { $0.owner == .picture || $0.owner == .mac })
check("Zoom Picture (the default): fingers zoom the picture and nothing else changes owner, whatever the Mac takes",
      combos.filter { !$0.zoomOnMac }.allSatisfy { $0.owner == ($0.source == .fingers ? .picture : .none) })
check("Zoom on Mac: every source goes to the Mac exactly when the Mac takes the pinch",
      combos.filter { $0.zoomOnMac }.allSatisfy { ($0.owner == .mac) == $0.macTakes })
check("a kept Zoom on Mac never costs the picture its zoom on a Mac that cannot take the pinch",
      combos.filter { $0.source == .fingers && $0.zoomOnMac && !$0.macTakes }.allSatisfy { $0.owner == .picture })
check("one choice for every source: on a Mac that takes the pinch, all three go the same way",
      bools.allSatisfy { z in Set(R.Source.allCases.map { R.owner($0, zoomOnMac: z, macTakesPinch: true) == .mac }).count == 1 })

// MARK: - The turn

for s in R.Source.allCases { for z in bools { for r in bools { for m in bools {
    let turns = R.turns(s, zoomOnMac: z, rotate: r, macTakesPinch: m)
    check("turn \(s) zoomOnMac \(z) rotate \(r) macTakes \(m): \(turns)",
          turns == (r && z && m))
} } } }
check("a turn goes only with the pinch: never while the picture zooms", combos.allSatisfy { c in
    !R.turns(c.source, zoomOnMac: c.zoomOnMac, rotate: true, macTakesPinch: c.macTakes) || c.owner == .mac })

// MARK: - The Mac's flag

check("a Mac before it (nil) takes no pinch", !R.macTakes(nil))
check("0 is not taking it", !R.macTakes(0))
check("generation 1 takes it, and a later one", R.macTakes(1) && R.macTakes(2))

// MARK: - The switches as UserDefaults holds them

check("Pinch: Zoom Picture unless chosen", R.zoomOnMacDefault == false && R.on(stored: nil, standard: R.zoomOnMacDefault) == false)
check("Rotate on Mac: off unless turned on", R.rotateDefault == false && R.on(stored: nil, standard: R.rotateDefault) == false)
check("the keys: the PR's own for Pinch, and Rotate's", R.zoomOnMacKey == "Sill.pinchZoomsMac" && R.rotateKey == "Sill.rotateOnMac")
check("the panel's Bool", R.on(stored: true, standard: false) && !R.on(stored: false, standard: true))
check("a number", R.on(stored: NSNumber(value: 1), standard: false) && !R.on(stored: NSNumber(value: 0), standard: true))
check("a launch argument's string: 1, YES, true on; 0, NO off",
      ["1", "YES", "true"].allSatisfy { R.on(stored: $0, standard: false) } && ["0", "NO", "false"].allSatisfy { !R.on(stored: $0, standard: true) })
check("anything else: the standard", R.on(stored: [1], standard: false) == false && R.on(stored: Data(), standard: true) == true)
func child(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    p.arguments = ["--child", "x"] + args
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
check("-Sill.pinchZoomsMac 1 -Sill.rotateOnMac 1 in a run: both on", child(["-Sill.pinchZoomsMac", "1", "-Sill.rotateOnMac", "1"]) == "zoom on mac rotate on")
check("-Sill.pinchZoomsMac YES alone: Zoom on Mac, Rotate off", child(["-Sill.pinchZoomsMac", "YES"]) == "zoom on mac rotate off")
check("nothing: Zoom Picture, Rotate off", child([]) == "zoom picture rotate off")

// MARK: - The Settings panel's rows

check("the control shows Zoom on Mac only while it is what happens",
      R.shownZoomOnMac(stored: true, macTakesPinch: true) && !R.shownZoomOnMac(stored: true, macTakesPinch: false)
      && !R.shownZoomOnMac(stored: false, macTakesPinch: true) && !R.shownZoomOnMac(stored: false, macTakesPinch: false))
check("the control shows what fingers do: for every stored value and Mac, Zoom on Mac exactly when fingers are the Mac's",
      bools.allSatisfy { z in bools.allSatisfy { m in R.shownZoomOnMac(stored: z, macTakesPinch: m) == (R.owner(.fingers, zoomOnMac: z, macTakesPinch: m) == .mac) } })
check("the control can be changed only for a Mac that takes the pinch", R.enabled(macTakesPinch: true) && !R.enabled(macTakesPinch: false))
check("Rotate on Mac shows under Zoom on Mac, for a Mac that takes the pinch, and nowhere else",
      R.rotateRowShown(zoomOnMac: true, macTakesPinch: true) && !R.rotateRowShown(zoomOnMac: true, macTakesPinch: false)
      && !R.rotateRowShown(zoomOnMac: false, macTakesPinch: true) && !R.rotateRowShown(zoomOnMac: false, macTakesPinch: false))
check("the row's words: Pinch, Zoom Picture, Zoom on ‹Mac›, Rotate on ‹Mac›",
      R.title == "Pinch" && R.zoomPictureTitle == "Zoom Picture" && R.zoomOnMacTitle(mac: "Studio") == "Zoom on Studio"
      && R.rotateTitle(mac: "the Mac") == "Rotate on the Mac")
check("the Mac's segment: its name up to 12 characters", R.segmentNameLimit == 12 && R.zoomOnMacTitle(mac: "MacBook Pros") == "Zoom on MacBook Pros")
check("past 12, the Mac (a segmented control neither wraps nor shrinks)", R.zoomOnMacTitle(mac: "Noah’s MacBook Pro") == "Zoom on the Mac"
      && R.zoomOnMacTitle(mac: "MacBook Pro 1") == "Zoom on the Mac")
let footnote = R.footnote(mac: "Studio", device: "iPad", macTakesPinch: true)
check("the footnote, the review's words: \(footnote)", footnote ==
      "Zoom Picture magnifies the picture on this iPad, up to 5×, and sends nothing. Zoom on Studio sends the pinch to the app under your fingers, as Studio’s trackpad would, so Maps, Safari or Preview zoom their own content. On a trackpad, it goes where the pointer is.")
check("the footnote on an iPhone and for an unnamed Mac", R.footnote(mac: "the Mac", device: "iPhone", macTakesPinch: true).hasPrefix("Zoom Picture magnifies the picture on this iPhone")
      && R.footnote(mac: "the Mac", device: "iPhone", macTakesPinch: true).contains("as the Mac’s trackpad would"))
check("the footnote for a Mac that cannot take the pinch: update Sill there",
      R.footnote(mac: "Studio", device: "iPad", macTakesPinch: false) == "Update Sill on Studio to send pinches to its apps.")
check("Rotate's footnote, the review's words",
      R.rotateFootnote == "Turn two fingers to rotate what’s under them in apps that rotate, such as Preview, Photos and Maps.")

// MARK: - What a surface has open on the Mac (MacPinchSent)

do {
    var m = MacPinchSent()
    check("nothing open at first", !m.isOpen && m.place(.stroke) == nil && m.at(.magnify, .stroke) == nil)
    m.began(.magnify, .stroke, at: (0.25, 0.5))
    check("a stroke's pinch open, where it began", m.isOpen && m.at(.magnify, .stroke)! == (0.25, 0.5))
    check("the trackpad's change does not reach the stroke's pinch", m.at(.magnify, .pointer) == nil)
    check("the stroke's turn would begin where its pinch is", m.place(.stroke)! == (0.25, 0.5) && m.place(.pointer) == nil)
    m.began(.rotate, .stroke, at: m.place(.stroke)!)
    check("both open at one place", m.at(.rotate, .stroke)! == (0.25, 0.5) && m.at(.magnify, .stroke)! == (0.25, 0.5))
    m.ended(.magnify)
    check("the pinch ends, the turn goes on where it was", m.at(.magnify, .stroke) == nil && m.at(.rotate, .stroke)! == (0.25, 0.5) && m.isOpen)
    check("the turn's place is still the stroke's for its next pinch", m.place(.stroke)! == (0.25, 0.5))
    m.ended(.rotate)
    check("both ended: nothing open", !m.isOpen && m.place(.stroke) == nil)
    m.began(.magnify, .pointer, at: (0.9, 0.1))
    m.began(.magnify, .stroke, at: (0.2, 0.2))
    check("a stroke's pinch over the trackpad's: the stroke's now, the trackpad's end goes nowhere",
          m.at(.magnify, .stroke)! == (0.2, 0.2) && m.at(.magnify, .pointer) == nil)
    m.forget()
    check("forgotten (another session): nothing open", !m.isOpen && m.at(.magnify, .stroke) == nil)
}

print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(Int32(min(fails, 100)))
