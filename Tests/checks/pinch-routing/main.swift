// PinchRouting (iOSClient/PinchRouting.swift) on its own: who a two-finger pinch on the stream's picture
// belongs to. The three places that ask (InputOverlayView.zoomTouch, gestureRecognizerShouldBegin and
// handlePinch) all go through it, so the picture's zoom and the Mac's pinch can never both happen, nor
// neither when one should.
//   swiftc -O iOSClient/PinchRouting.swift Tests/checks/pinch-routing/main.swift -o check && ./check
import Foundation

typealias R = PinchRouting
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

// MARK: - Every combination, written out

struct Case { let fingers: Bool, zoomApp: Bool, macTakes: Bool, owner: R.Owner, what: String }
let table: [Case] = [
    // Fingers on the glass.
    Case(fingers: true,  zoomApp: false, macTakes: true,  owner: .picture, what: "fingers, Zoom Stream, a Mac with the pinch: the picture zooms"),
    Case(fingers: true,  zoomApp: true,  macTakes: true,  owner: .mac,     what: "fingers, Zoom App, a Mac with the pinch: the Mac's pinch"),
    Case(fingers: true,  zoomApp: false, macTakes: false, owner: .picture, what: "fingers, Zoom Stream, a Mac before the pinch: the picture zooms"),
    Case(fingers: true,  zoomApp: true,  macTakes: false, owner: .picture, what: "fingers, Zoom App kept, a Mac before the pinch: the picture still zooms"),
    // The iPad's trackpad: no touches.
    Case(fingers: false, zoomApp: false, macTakes: true,  owner: .mac,     what: "trackpad, Zoom Stream, a Mac with the pinch: the Mac's pinch"),
    Case(fingers: false, zoomApp: true,  macTakes: true,  owner: .mac,     what: "trackpad, Zoom App, a Mac with the pinch: the Mac's pinch"),
    Case(fingers: false, zoomApp: false, macTakes: false, owner: .none,    what: "trackpad, Zoom Stream, a Mac before the pinch: nobody's"),
    Case(fingers: false, zoomApp: true,  macTakes: false, owner: .none,    what: "trackpad, Zoom App, a Mac before the pinch: nobody's"),
]
check("the table is every combination once", Set(table.map { "\($0.fingers)\($0.zoomApp)\($0.macTakes)" }).count == 8)
for c in table {
    check(c.what, R.owner(fingersOnGlass: c.fingers, zoomApp: c.zoomApp, macTakesPinch: c.macTakes) == c.owner)
}

// MARK: - What the callers rely on, over all combinations

let bools = [false, true]
var combos: [(fingers: Bool, zoomApp: Bool, macTakes: Bool, owner: R.Owner)] = []
for f in bools { for z in bools { for m in bools {
    combos.append((f, z, m, R.owner(fingersOnGlass: f, zoomApp: z, macTakesPinch: m)))
} } }

check("the Mac is sent a pinch only by a Mac that takes it",
      combos.allSatisfy { $0.owner != .mac || $0.macTakes })
check("the picture is zoomed only by fingers on the glass, never by the trackpad",
      combos.allSatisfy { $0.owner != .picture || $0.fingers })
check("fingers on the glass always belong to the picture or the Mac, so a pinch is never lost",
      combos.filter { $0.fingers }.allSatisfy { $0.owner == .picture || $0.owner == .mac })
check("Zoom Stream (the default): fingers always zoom the picture, whatever the Mac takes",
      combos.filter { $0.fingers && !$0.zoomApp }.allSatisfy { $0.owner == .picture })
check("Zoom App with fingers goes to the Mac exactly when the Mac takes the pinch",
      combos.filter { $0.fingers && $0.zoomApp }.allSatisfy { ($0.owner == .mac) == $0.macTakes })
check("a kept Zoom App never costs the picture its zoom on a Mac that cannot take the pinch",
      combos.filter { $0.fingers && $0.zoomApp && !$0.macTakes }.allSatisfy { $0.owner == .picture })
check("the trackpad ignores the stored choice",
      bools.allSatisfy { m in R.owner(fingersOnGlass: false, zoomApp: false, macTakesPinch: m) == R.owner(fingersOnGlass: false, zoomApp: true, macTakesPinch: m) })

print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(Int32(min(fails, 100)))
