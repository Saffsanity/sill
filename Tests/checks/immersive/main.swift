// ImmersivePolicy (iOSClient/ImmersivePolicy.swift) on its own: when Immersive applies, which of its three
// states the stream screen is in, what each event does to the bar and the auto-hide timer, the
// shortcut's chord and the top edge's swipe (docs/immersive-plan.md). Scenario by scenario, then
// 20,000 random sessions against the plan's invariants:
//   I1 the state is off exactly when Immersive does not apply;
//   I2 the panel's size (full screen or not) changes only when the state moves between off and the
//      other two: revealing and hiding the bar never resize it;
//   I3 while something holds the bar it is shown;
//   I4 the shortcut is taken only while Immersive applies;
//   I5 the auto-hide never hides a held bar, and the timer is never left running while held or off.
//   swiftc -O iOSClient/ImmersivePolicy.swift Tests/checks/immersive/main.swift -o check && ./check
import Foundation

typealias P = ImmersivePolicy
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

// MARK: - When it applies (R2, R12, Stage Manager)

do {
    var all = 0, on = 0
    for bits in 0..<64 {
        let b = (0..<6).map { bits & (1 << $0) != 0 }
        let got = P.applies(switchOn: b[0], keyboardAttached: b[1], landscape: b[2], streaming: b[3],
                            voiceOver: b[4], fillsScreen: b[5])
        let want = b[0] && b[1] && b[2] && b[3] && !b[4] && b[5]
        all += 1
        if got { on += 1 }
        if got != want { check("applies \(b)", false) }
    }
    check("applies: exactly one of 64 combinations (switch, keyboard, sideways, streaming, VoiceOver off, full screen)", on == 1 && all == 64)
    check("applies: all six together", P.applies(switchOn: true, keyboardAttached: true, landscape: true, streaming: true, voiceOver: false, fillsScreen: true))
    check("applies: not with VoiceOver", !P.applies(switchOn: true, keyboardAttached: true, landscape: true, streaming: true, voiceOver: true, fillsScreen: true))
    check("applies: not with nothing streaming", !P.applies(switchOn: true, keyboardAttached: true, landscape: true, streaming: false, voiceOver: false, fillsScreen: true))
    check("applies: not with no keyboard", !P.applies(switchOn: true, keyboardAttached: false, landscape: true, streaming: true, voiceOver: false, fillsScreen: true))
    check("applies: not upright", !P.applies(switchOn: true, keyboardAttached: true, landscape: false, streaming: true, voiceOver: false, fillsScreen: true))
    check("applies: not in a Stage Manager window", !P.applies(switchOn: true, keyboardAttached: true, landscape: true, streaming: true, voiceOver: false, fillsScreen: false))
    check("applies: not with the switch off", !P.applies(switchOn: false, keyboardAttached: true, landscape: true, streaming: true, voiceOver: false, fillsScreen: true))
}

// MARK: - Filling the screen

check("fills: 13\" iPad Pro sideways, the whole screen", P.fills(size: (1376, 1032), screen: (1376, 1032)))
check("fills: the screen's bounds the other way round", P.fills(size: (1376, 1032), screen: (1032, 1376)))
check("fills: within a point", P.fills(size: (1375.5, 1032), screen: (1376, 1032)))
check("fills: not a Stage Manager window", !P.fills(size: (1100, 800), screen: (1376, 1032)))
check("fills: not Split View's half", !P.fills(size: (684, 1032), screen: (1376, 1032)))
check("fills: not a slide-over window", !P.fills(size: (375, 1032), screen: (1376, 1032)))
check("fills: not a zero size", !P.fills(size: (0, 0), screen: (1376, 1032)))
check("fills: not a scene a column narrower", !P.fills(size: (1374, 1032), screen: (1376, 1032)))

// MARK: - The shortcut

let ctrl: UInt64 = 1 << 18, opt: UInt64 = 1 << 19, cmd: UInt64 = 1 << 20, shift: UInt64 = 1 << 17
let caps: UInt64 = 1 << 16, keypad: UInt64 = 1 << 21
check("chord: ⌃⌥⌘B", P.isToggle(usage: 0x05, modifiers: ctrl | opt | cmd))
check("chord: ⌃⌥⌘B with caps lock on", P.isToggle(usage: 0x05, modifiers: ctrl | opt | cmd | caps))
check("chord: ⌃⌥⌘B with the keypad bit", P.isToggle(usage: 0x05, modifiers: ctrl | opt | cmd | keypad))
check("chord: not ⇧⌃⌥⌘B", !P.isToggle(usage: 0x05, modifiers: shift | ctrl | opt | cmd))
check("chord: not ⌃⌘B", !P.isToggle(usage: 0x05, modifiers: ctrl | cmd))
check("chord: not ⌥⌘B", !P.isToggle(usage: 0x05, modifiers: opt | cmd))
check("chord: not ⌃⌥B", !P.isToggle(usage: 0x05, modifiers: ctrl | opt))
check("chord: not ⌘B (bold on the Mac)", !P.isToggle(usage: 0x05, modifiers: cmd))
check("chord: not B", !P.isToggle(usage: 0x05, modifiers: 0))
check("chord: not ⌃⌥⌘N", !P.isToggle(usage: 0x11, modifiers: ctrl | opt | cmd))
check("chord: not ⌃⌘F (the Mac's Enter Full Screen)", !P.isToggle(usage: 0x09, modifiers: ctrl | cmd))
do {
    var count = 0
    for usage in UInt16(0)...UInt16(0xE7) {
        for mask in 0..<64 {
            let mods = (0..<6).reduce(UInt64(0)) { mask & (1 << $1) != 0 ? $0 | (1 << UInt64(16 + $1)) : $0 }
            if P.isToggle(usage: usage, modifiers: mods) { count += 1 }
        }
    }
    // B with ⌃⌥⌘, and caps lock and the keypad bit either way: four.
    check("chord: exactly four of every usage × 64 flag sets", count == 4)
}

// MARK: - The edge

check("edge: straight down from the very top", P.revealsFromEdge(startY: 0, dx: 0, dy: 30))
check("edge: down from 20 pt", P.revealsFromEdge(startY: 20, dx: 3, dy: 30))
check("edge: not from 21 pt", !P.revealsFromEdge(startY: 21, dx: 0, dy: 30))
check("edge: not from mid-screen", !P.revealsFromEdge(startY: 400, dx: 0, dy: 30))
check("edge: not sideways along the top (a browser's tabs)", !P.revealsFromEdge(startY: 5, dx: 40, dy: 10))
check("edge: not diagonal at exactly 45°", !P.revealsFromEdge(startY: 5, dx: 20, dy: 20))
check("edge: not up", !P.revealsFromEdge(startY: 5, dx: 0, dy: -30))
check("edge: not a drag that has not moved", !P.revealsFromEdge(startY: 5, dx: 0, dy: 0))
check("edge: not from above the screen", !P.revealsFromEdge(startY: -1, dx: 0, dy: 30))

// MARK: - Scenarios

do {
    var p = P()
    check("start: off", p.state == .off)
    check("start: toggle not taken while off", p.toggle() == (false, .keep) && p.state == .off)
    check("start: edge does nothing while off", p.edgeSwipe() == .keep && p.state == .off)

    // Entering: the switch's change applies as Settings closes, so applies and held change together.
    check("enter: immersed, timer stopped", p.update(applies: true, held: false) == .stop && p.state == .immersed)
    check("enter again (repeat): nothing", p.update(applies: true, held: false) == .keep && p.state == .immersed)

    var t = p.toggle()
    check("shortcut: reveals, timer starts", t == (true, .start) && p.state == .revealed)
    check("touch: restarts the timer", p.touched() == .start)
    t = p.toggle()
    check("shortcut again: hides, timer stops", t == (true, .stop) && p.state == .immersed)
    check("touch while hidden: nothing", p.touched() == .keep)

    check("edge: reveals, timer starts", p.edgeSwipe() == .start && p.state == .revealed)
    p.timerFired()
    check("timer: hides", p.state == .immersed)

    // Something opens over the stream (Settings from the revealed bar).
    _ = p.edgeSwipe()
    check("held: the bar stays, timer stopped", p.update(applies: true, held: true) == .stop && p.state == .revealed)
    p.timerFired()
    check("held: a late timer does not hide it", p.state == .revealed)
    t = p.toggle()
    check("held: the shortcut is taken but changes nothing", t == (true, .keep) && p.state == .revealed)
    check("held: edge changes nothing", p.edgeSwipe() == .keep && p.state == .revealed)
    check("held: touch does not start the timer", p.touched() == .keep)
    check("released: the bar lingers, timer starts", p.update(applies: true, held: false) == .start && p.state == .revealed)
    p.timerFired()
    check("released: then hides", p.state == .immersed)

    // A taker opening while immersed (the tour, ⌘. opening Settings): the bar comes.
    check("held from immersed: revealed", p.update(applies: true, held: true) == .stop && p.state == .revealed)
    check("released: lingers", p.update(applies: true, held: false) == .start && p.state == .revealed)

    // Detaching the keyboard while revealed: off at once, the reveal forgotten.
    check("detach: off, timer stopped", p.update(applies: false, held: false) == .stop && p.state == .off)
    check("attach again: immersed, not revealed", p.update(applies: true, held: false) == .stop && p.state == .immersed)

    // Entering with something open: revealed, held.
    var q = P()
    check("enter held: revealed, timer stopped", q.update(applies: true, held: true) == .stop && q.state == .revealed)
    check("enter held then released: lingers", q.update(applies: true, held: false) == .start && q.state == .revealed)

    // Held while off, then applies: revealed; held off while not applying: nothing pending.
    var r = P()
    _ = r.update(applies: false, held: true)
    check("held while off: still off", r.state == .off)
    _ = r.update(applies: false, held: false)
    check("released while off: entering later is immersed", r.update(applies: true, held: false) == .stop && r.state == .immersed)

    // Rotating to portrait and back.
    var s = P()
    _ = s.update(applies: true, held: false)
    _ = s.toggle()
    _ = s.update(applies: false, held: false)
    check("portrait: off", s.state == .off)
    _ = s.update(applies: true, held: false)
    check("back sideways: immersed", s.state == .immersed)

    // The timer firing while off never revives anything.
    var u = P()
    u.timerFired()
    check("timer while off: off", u.state == .off)

    check("panel: full screen immersed and revealed, not off",
          P.fillsScreen(.immersed) && P.fillsScreen(.revealed) && !P.fillsScreen(.off))
    check("bar: shown off and revealed, not immersed",
          P.barShown(.off) && P.barShown(.revealed) && !P.barShown(.immersed))
    check("auto-hide: 4 s", P.autoHide == 4)
}

// MARK: - Random sessions

enum Ev { case update(Bool, Bool), toggle, edge, touch, fire }
var rng = SystemRandomNumberGenerator()
func pick() -> Ev {
    switch Int.random(in: 0..<10, using: &rng) {
    case 0, 1, 2: return .update(Bool.random(using: &rng) || Bool.random(using: &rng), Bool.random(using: &rng))
    case 3, 4: return .toggle
    case 5: return .edge
    case 6: return .touch
    default: return .fire
    }
}

var broken: [String: Int] = [:]
func bad(_ name: String) { broken[name, default: 0] += 1 }
var timerRuns = 0
for _ in 0..<20_000 {
    var p = P()
    var applies = false, held = false
    var timer = false
    for _ in 0..<40 {
        let before = p.state
        var resized = false
        let ev = pick()
        var out: P.Timer = .keep
        switch ev {
        case .update(let a, let h):
            applies = a; held = h
            out = p.update(applies: a, held: h)
            resized = P.fillsScreen(before) != P.fillsScreen(p.state)
        case .toggle:
            let r = p.toggle()
            out = r.timer
            if r.taken != applies { bad("I4 the shortcut taken \(r.taken) while applying \(applies)") }
        case .edge: out = p.edgeSwipe()
        case .touch: out = p.touched()
        case .fire:
            if timer {
                p.timerFired()
                timer = false
                timerRuns += 1
                if held && applies && p.state != .revealed { bad("I5 the timer hid a held bar") }
            }
        }
        switch out { case .start: timer = true; case .stop: timer = false; case .keep: break }
        let after = p.state
        if (after == .off) != !applies { bad("I1 state \(after.rawValue) while applying \(applies)") }
        if P.fillsScreen(before) != P.fillsScreen(after) {
            if case .update = ev {} else { bad("I2 the panel resized on a reveal or hide") }
            if !resized { bad("I2 resized without an update") }
        }
        if applies && held && after != .revealed { bad("I3 held but \(after.rawValue)") }
        if timer && (held || !applies) { bad("I5 the timer left running while \(held ? "held" : "off")") }
        if timer && after != .revealed { bad("I5 the timer running with the bar \(after.rawValue)") }
    }
}
check("random: 20,000 sessions of 40 events hold I1–I5", broken.isEmpty)
for (k, v) in broken.sorted(by: { $0.key < $1.key }) { print("     \(v)× \(k)") }
check("random: the timer ran out sometimes", timerRuns > 1000)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
