import Foundation
import CoreGraphics

var passed = 0
var failed = 0

func check(_ condition: Bool, _ label: String, detail: String = "") {
    if condition {
        passed += 1
        print("ok   \(label)")
    } else {
        failed += 1
        print("FAIL \(label)" + (detail.isEmpty ? "" : ": \(detail)"))
    }
}

let deviceOwner = NSObject()
let device = KeyStrokes.Device(deviceOwner)

func applyToMac(_ events: [InputEvent], keys: inout KeyStrokes) -> [KeyStroke] {
    var out: [KeyStroke] = []
    for ev in events {
        if case .key(let usage, let down, let mods) = ev,
           let strokes = keys.key(usage: usage, down: down, modifiers: mods, from: device) {
            out += strokes
        }
    }
    return out
}

func arrowDowns(_ events: [InputEvent]) -> [UInt16] {
    events.compactMap {
        if case .key(let u, true, _) = $0, (0x4F...0x52).contains(u) { return u }
        return nil
    }
}

// 1. Quick tap (< dragThreshold, < holdDelay): single press, spends latch when latched.
do {
    var s = ArrowScrub()
    var mac = KeyStrokes()
    let b = s.begin(cap: ArrowScrub.leftUsage, at: CGPoint(x: 100, y: 100), time: 1.0, latched: [])
    let m = s.move(to: CGPoint(x: 105, y: 102), time: 1.04)     // hypot(5,2) = 5.38 < 8
    let e = s.end(at: CGPoint(x: 105, y: 102), time: 1.08)
    _ = applyToMac(b.events + m.events + e.events, keys: &mac)
    check(b.events.isEmpty && m.events.isEmpty && e.events == KeyChord.press(ArrowScrub.leftUsage, with: [])
          && !e.spendsLatch && e.ticks == 0 && mac.down.isEmpty && mac.heldFlags == 0,
          "quick tap with jitter < 8 pt emits one left press and leaves Mac clean")

    var s2 = ArrowScrub()
    _ = s2.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 2.0, latched: .option)
    let e2 = s2.end(time: 2.05)
    _ = applyToMac(e2.events, keys: &mac)
    check(e2.events == KeyChord.press(ArrowScrub.rightUsage, with: .option) && e2.spendsLatch
          && mac.down.isEmpty && mac.heldFlags == 0,
          "quick tap with latched Option emits ⌥→, spends latch and leaves Mac clean")
}

// 2. Stationary hold (>= holdDelay): spends latch ONCE at holdReady, never double-spends on end (Codex P2 #6).
do {
    var s = ArrowScrub()
    var mac = KeyStrokes()
    _ = s.begin(cap: ArrowScrub.leftUsage, at: CGPoint(x: 50, y: 50), time: 10.0, latched: .option)
    let early = s.holdReady(at: 10.10)
    check(early.events.isEmpty && !early.spendsLatch, "holdReady before holdDelay emits nothing")
    let held = s.holdReady(at: 10.18)
    _ = applyToMac(held.events, keys: &mac)
    check(held.events == KeyChord.down(ArrowScrub.leftUsage, with: .option) && held.spendsLatch
          && mac.isDown(ArrowScrub.leftUsage) && mac.heldFlags == KeyStrokes.option,
          "holdReady at 0.18 s holds ⌥← down on the Mac and spends latch once")
    let up = s.end(at: CGPoint(x: 50, y: 50), time: 10.60)
    _ = applyToMac(up.events, keys: &mac)
    check(up.events == KeyChord.up(ArrowScrub.leftUsage, with: .option) && !up.spendsLatch
          && mac.down.isEmpty && mac.heldFlags == 0,
          "lifting after stationary hold releases ← and Option without spending a newly armed latch")

    // Cancel during hold:
    _ = s.begin(cap: ArrowScrub.upUsage, at: .zero, time: 20.0, latched: .shift)
    _ = applyToMac(s.holdReady(at: 20.20).events, keys: &mac)
    let c = s.cancel()
    _ = applyToMac(c.events, keys: &mac)
    check(mac.down.isEmpty && mac.heldFlags == 0 && !s.isActive && !c.spendsLatch,
          "cancel during stationary hold releases held arrow and Shift cleanly")
}

// 3. Hold-to-drag transition quantizes the very FIRST crossing movement and never re-spends latch (Codex P2 #6 & #8).
do {
    var s = ArrowScrub()
    var mac = KeyStrokes()
    _ = s.begin(cap: ArrowScrub.leftUsage, at: CGPoint(x: 100, y: 100), time: 1.0, latched: .shift)
    let holdDown = s.holdReady(at: 1.20)
    _ = applyToMac(holdDown.events, keys: &mac)
    let m1 = s.move(to: CGPoint(x: 100, y: 132), time: 1.40)    // +32 pt Y -> releases ← AND emits 2 ↓ immediately!
    let end = s.end(at: CGPoint(x: 100, y: 132), time: 1.45)
    _ = applyToMac(m1.events + end.events, keys: &mac)
    check(arrowDowns(m1.events) == [ArrowScrub.downUsage, ArrowScrub.downUsage]
          && !m1.spendsLatch && !end.spendsLatch && mac.down.isEmpty && mac.heldFlags == 0,
          "hold-to-drag transition releases held key and quantizes the crossing 32 pt drag immediately")
}

// 4. Cancel after a stepped scrub spends the captured latch so next typed key is not turned into ⌘W (Codex P1 #1).
do {
    var s = ArrowScrub()
    var mac = KeyStrokes()
    var uiLatch: KeyModifiers = .command
    _ = s.begin(cap: ArrowScrub.leftUsage, at: .zero, time: 0.0, latched: uiLatch)
    let m = s.move(to: CGPoint(x: -10, y: 0), time: 0.10)
    _ = applyToMac(m.events, keys: &mac)
    let c = s.cancel()
    if c.spendsLatch { uiLatch = [] }
    check(arrowDowns(m.events) == [ArrowScrub.leftUsage] && c.spendsLatch && uiLatch.isEmpty,
          "cancelling a scrub that already stepped spends Command latch so next letter is plain text")

    // Conversely, cancelling before any step keeps the unused latch:
    var s2 = ArrowScrub()
    var uiLatch2: KeyModifiers = .command
    _ = s2.begin(cap: ArrowScrub.leftUsage, at: .zero, time: 0.0, latched: uiLatch2)
    let c2 = s2.cancel()
    if c2.spendsLatch { uiLatch2 = [] }
    check(!c2.spendsLatch && uiLatch2 == .command,
          "cancelling a press before any step preserves unused Command latch")
}

// 5. Velocity acceleration, exact tier boundaries, and 120 Hz minSampleInterval jitter protection (Codex P2 #5).
do {
    // Slow: 16 pt in 0.20 s (80 pt/s < 240) -> 2 steps
    var slow = ArrowScrub()
    _ = slow.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 0.0, latched: [])
    let slowRes = slow.move(to: CGPoint(x: 16, y: 0), time: 0.20)
    let slowEnd = slow.end(time: 0.25)
    check(arrowDowns(slowRes.events) == [ArrowScrub.rightUsage, ArrowScrub.rightUsage] && slowRes.ticks == 2
          && slowEnd.events.isEmpty,
          "slow drag (80 pt/s) emits 1 step per 8 pt and stops with zero overshoot on lift")

    // Exact medium boundary: 24.0 pt in 0.10 s == 240.0 pt/s (>= mediumSpeed) -> 24 / 5.0 = 4 steps (slow would be 3)
    var med = ArrowScrub()
    _ = med.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 0.0, latched: [])
    let medRes = med.move(to: CGPoint(x: 24, y: 0), time: 0.10)
    _ = med.end(time: 0.12)
    check(arrowDowns(medRes.events).count == 4,
          "exact 240 pt/s boundary enters medium tier (1 step per 5 pt -> 4 steps in 24 pt)")

    // Exact fast boundary: 26.0 pt in 0.05 s == 520.0 pt/s (>= fastSpeed) -> 26 / 2.8 = 9 -> clamped to 8 (medium would be 5)
    var fast = ArrowScrub()
    _ = fast.begin(cap: ArrowScrub.leftUsage, at: .zero, time: 0.0, latched: [])
    let fastRes = fast.move(to: CGPoint(x: -26.0, y: 0), time: 0.05)
    _ = fast.end(time: 0.06)
    check(arrowDowns(fastRes.events) == Array(repeating: ArrowScrub.leftUsage, count: 8),
          "exact 520 pt/s boundary enters fast tier (1 step per 2.8 pt)")

    // 120 Hz callback jitter: 8 pt initial move at 0.10 s (1 step), then 1.8 pt move 0.5 ms later:
    // With 1/120 s floor, 1.8 / (1/120) = 216 pt/s (< 240 slow, 1.8 < 8 -> 0 steps);
    // without floor (e.g. 1 us), 1.8 / 0.0005 = 3600 pt/s (fast 2.8 pt); with 3.0 pt 0.5 ms later:
    // 3.0 / (1/120) = 360 pt/s (< 520 medium 5 pt -> 0 steps, whereas without floor 3.0 >= 2.8 -> 1 extra step!).
    var jitter = ArrowScrub()
    _ = jitter.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 0.0, latched: [])
    let j1 = jitter.move(to: CGPoint(x: 8.0, y: 0), time: 0.100)
    let j2 = jitter.move(to: CGPoint(x: 11.0, y: 0), time: 0.1005)   // +3.0 pt in 0.5 ms
    _ = jitter.end(time: 0.12)
    check(arrowDowns(j1.events).count == 1 && j2.events.isEmpty,
          "120 Hz minSampleInterval prevents 0.5 ms delivery jitter from triggering fastStepX on a 3 pt move")
}

// 6. Vertical scrubbing (with Shift selection modifiers!) & touchesEnded final-point flick (Codex P2 #9 & r4).
do {
    var v = ArrowScrub()
    var mac = KeyStrokes()
    _ = v.begin(cap: ArrowScrub.upUsage, at: CGPoint(x: 100, y: 100), time: 0.0, latched: .shift)
    let up2 = v.move(to: CGPoint(x: 100, y: 68), time: 0.20)
    let down1 = v.move(to: CGPoint(x: 100, y: 84), time: 0.40)
    let end = v.end(time: 0.45)
    let vStrokes = applyToMac(up2.events + down1.events + end.events, keys: &mac)
    let arrowKeyStrokes = vStrokes.filter { ($0.virtualKey == 125 || $0.virtualKey == 126) && $0.down }
    check(arrowDowns(up2.events) == [ArrowScrub.upUsage, ArrowScrub.upUsage]
          && arrowDowns(down1.events) == [ArrowScrub.downUsage]
          && arrowKeyStrokes.count == 3 && arrowKeyStrokes.allSatisfy({ $0.flags == KeyStrokes.shift })
          && end.spendsLatch && mac.down.isEmpty && mac.heldFlags == 0,
          "vertical scrub steps ↑/↓ every 16 pt carrying Shift modifier cleanly")

    // Flick where touchesMoved reached 6 pt (< 8 pt) and touchesEnded landed at -10 pt Y on `<` cap:
    var flick = ArrowScrub()
    _ = flick.begin(cap: ArrowScrub.leftUsage, at: CGPoint(x: 100, y: 100), time: 0.0, latched: .option)
    let fm = flick.move(to: CGPoint(x: 100, y: 94), time: 0.02)      // -6 pt (< 8 pt -> still waiting)
    let fe = flick.end(at: CGPoint(x: 100, y: 90), time: 0.04)       // -10 pt at lift -> Up flick, NOT Left tap!
    check(fm.events.isEmpty && arrowDowns(fe.events) == [ArrowScrub.upUsage] && fe.ticks == 1 && fe.spendsLatch,
          "touchesEnded lift point turns a fast 10 pt upward flick on `<` into ↑ instead of ←")
}

// 7. Coalesced vs incremental cross-axis drift dampening & combined 8-step frame budget (Codex P2 #10).
do {
    // Coalesced single (32, 16) update matches four (8, 4) updates: 4 Rights and ZERO Downs!
    var coal = ArrowScrub()
    _ = coal.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 0.0, latched: [])
    let cRes = coal.move(to: CGPoint(x: 32, y: 16), time: 0.20)
    _ = coal.end(time: 0.25)
    check(arrowDowns(cRes.events) == Array(repeating: ArrowScrub.rightUsage, count: 4),
          "coalesced (32, 16) horizontal drag dampens minor Y delta and emits 4 → with 0 ↓",
          detail: "got \(arrowDowns(cRes.events))")

    // 4 frames of (+3 pt X, +12 pt Y) plus a coalesced (+10 pt X, +32 pt Y) vertical swipe emit Downs only and ZERO Rights!
    var sv = ArrowScrub()
    _ = sv.begin(cap: ArrowScrub.downUsage, at: .zero, time: 0.0, latched: [])
    var vEvents: [InputEvent] = []
    for i in 1...4 {
        vEvents += sv.move(to: CGPoint(x: CGFloat(i * 3), y: CGFloat(i * 12)), time: Double(i) * 0.08).events
    }
    vEvents += sv.move(to: CGPoint(x: 22, y: 80), time: 0.52).events   // +10 pt X, +32 pt Y in one coalesced frame
    _ = sv.end(time: 0.55)
    check(arrowDowns(vEvents) == Array(repeating: ArrowScrub.downUsage, count: 5),
          "vertical scrub (+3, +12) × 4 then coalesced (+10, +32) dampens horizontal drift and emits 5 ↓ with 0 →",
          detail: "got \(arrowDowns(vEvents))")

    // Diagonal stall jump (300, 300) caps TOTAL emitted arrow presses across both axes to maxStepsPerUpdate (8):
    var diag = ArrowScrub()
    _ = diag.begin(cap: ArrowScrub.rightUsage, at: .zero, time: 0.0, latched: [])
    let jump = diag.move(to: CGPoint(x: 300, y: 300), time: 0.05)
    check(arrowDowns(jump.events).count == ArrowScrub.maxStepsPerUpdate && jump.ticks == ArrowScrub.maxStepsPerUpdate,
          "diagonal stall jump caps combined X+Y presses to maxStepsPerUpdate (8)")
}

// 8. Horizontal Option+Shift word selection scrub & FloatingCursor zero dead zone.
do {
    var s = ArrowScrub()
    var mac = KeyStrokes()
    let mods: KeyModifiers = [.option, .shift]
    _ = s.begin(cap: ArrowScrub.leftUsage, at: .zero, time: 0.0, latched: mods)
    let r1 = s.move(to: CGPoint(x: -16, y: 0), time: 0.20)
    let r2 = s.move(to: CGPoint(x: -24, y: 0), time: 0.35)
    let end = s.end(time: 0.40)
    let strokes = applyToMac(r1.events + r2.events + end.events, keys: &mac)
    let leftStrokes = strokes.filter { $0.virtualKey == 123 && $0.down }
    check(!r1.spendsLatch && !r2.spendsLatch && end.spendsLatch
          && leftStrokes.count == 3 && leftStrokes.allSatisfy({ $0.flags == (KeyStrokes.option | KeyStrokes.shift) })
          && mac.down.isEmpty && mac.heldFlags == 0,
          "horizontal Option+Shift scrub carries both modifiers on every step and spends latch once on lift")

    var f = ArrowScrub()
    _ = f.beginFloating(at: CGPoint(x: 50, y: 50), time: 0.0, latched: .option)
    _ = f.move(to: CGPoint(x: 50, y: 44), time: 0.05)
    let fEnd = f.end(time: 0.10)
    check(fEnd.events.isEmpty && !fEnd.spendsLatch,
          "beginFloating with sub-step travel emits no directional flick and keeps unspent latch")
}

// 9. 3,000 seeded random gesture sequences verifying Mac KeyStrokes hygiene & one-shot UI latch invariant.
struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func double(_ lo: Double, _ hi: Double) -> Double {
        lo + Double(next() % 10_000) / 10_000.0 * (hi - lo)
    }
}

let caps: [UInt16] = [ArrowScrub.leftUsage, ArrowScrub.rightUsage, ArrowScrub.upUsage, ArrowScrub.downUsage]
let modChoices: [KeyModifiers] = [[], .option, .shift, [.option, .shift], .command, [.control, .option]]
var rng = RNG(state: 0x5C8B_2026_1125)
var mac = KeyStrokes()
var s = ArrowScrub()
var randomFail: String?

for trial in 0..<3_000 {
    var t = Double(trial) * 2.0
    var p = CGPoint(x: 200, y: 200)
    let initialLatch = modChoices[rng.int(modChoices.count)]
    var uiLatch = initialLatch
    var sentModifiedKey = false

    func applyStep(_ res: ArrowScrub.StepResult) {
        for ev in res.events {
            if case .key(let u, true, let m) = ev, (0x4F...0x52).contains(u), m != 0 {
                sentModifiedKey = true
            }
        }
        _ = applyToMac(res.events, keys: &mac)
        if res.spendsLatch { uiLatch = [] }
    }

    if rng.int(5) == 0 {
        applyStep(s.beginFloating(at: p, time: t, latched: uiLatch))
    } else {
        applyStep(s.begin(cap: caps[rng.int(caps.count)], at: p, time: t, latched: uiLatch))
    }
    let steps = rng.int(8)
    for _ in 0..<steps {
        let action = rng.int(4)
        if action == 0 {
            t += rng.double(0.05, 0.25)
            applyStep(s.holdReady(at: t))
        } else {
            t += rng.double(0.001, 0.12)
            p.x += CGFloat(rng.double(-25, 25))
            p.y += CGFloat(rng.double(-25, 25))
            applyStep(s.move(to: p, time: t))
        }
    }
    t += 0.02
    if rng.int(6) == 0 {
        applyStep(s.cancel())
    } else {
        p.x += CGFloat(rng.double(-6, 6))
        p.y += CGFloat(rng.double(-6, 6))
        applyStep(s.end(at: p, time: t))
    }
    if !mac.down.isEmpty || mac.heldFlags != 0 || s.isActive {
        randomFail = "trial \(trial): down=\(mac.down), heldFlags=\(mac.heldFlags), phase=\(s.phase)"
        break
    }
    if sentModifiedKey && !uiLatch.isEmpty {
        randomFail = "trial \(trial): modified arrow went to Mac but uiLatch \(uiLatch) stayed armed"
        break
    }
}
check(randomFail == nil, "3,000 random tap/hold/scrub/cancel sequences keep Mac KeyStrokes and UI latch clean",
      detail: randomFail ?? "")

print("arrow-scrub: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
