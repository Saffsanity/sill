import Foundation

// A device's key held down repeats on the Mac as the Mac's own keyboard repeats a key (#162):
// KeyRepeat (Sources/SillHost/KeyRepeat.swift), put through a model of InputInjector's glue with the
// real KeyStrokes: each keyboard event posted is told to the repeat (`posted`), and the repeat is
// stepped at the times it names (`step`), as InputInjector's task does, with each device's messages (a
// device pings every 0.25 s) and where input lands. The scenarios give the exact events and times; the
// random sessions hold the rule to its invariants, safe (a repeat only of the last key pressed, still
// down on the Mac, after the delay, its device heard, its input landing, with the flags in force) and
// live (with nothing in the way, a repeat at every interval after the delay).
//
// Compiled with Sources/StreamProtocol, Sources/SillHost/KeyRepeat.swift and KeyStrokes.swift as one
// module (-package-name sill), as build.sh does.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func near(_ a: Double, _ b: Double, _ e: Double = 1e-6) -> Bool { abs(a - b) <= e }

let command = KeyStrokes.command, shift = KeyStrokes.shift, control = KeyStrokes.control
let option = KeyStrokes.option, capsLock = KeyStrokes.capsLock

func names(_ f: UInt64) -> String { KeyStrokes.names(f) }

// HID usages a device sends, and the Mac's keycodes.
let uLeft: UInt16 = 0x50, uRight: UInt16 = 0x4F, uUp: UInt16 = 0x52, uZ: UInt16 = 0x1D, uA: UInt16 = 0x04
let uEsc: UInt16 = 0x29, uCaps: UInt16 = 0x39, uFwdDel: UInt16 = 0x4C, uDel: UInt16 = 0x2A, uTab: UInt16 = 0x2B
let uLCtrl: UInt16 = 0xE0, uLShift: UInt16 = 0xE1, uLOpt: UInt16 = 0xE2, uLCmd: UInt16 = 0xE3, uRCmd: UInt16 = 0xE7
let kLeft: UInt16 = 123, kRight: UInt16 = 124, kUp: UInt16 = 126, kZ: UInt16 = 6, kA: UInt16 = 0, kEsc: UInt16 = 53
let kCaps: UInt16 = 57, kCmd: UInt16 = 55, kRCmd: UInt16 = 54, kOpt: UInt16 = 58, kShift: UInt16 = 56

/// This Mac's settings (InitialKeyRepeat 30, KeyRepeat 2): 0.5 s, then 30 a second.
let thisMac = KeyRepeat.Timing(delay: 0.5, interval: 1.0 / 30)

func key(_ usage: UInt16, _ down: Bool, _ modifiers: UInt64 = 0) -> InputEvent {
    .key(hidUsage: usage, down: down, modifiers: modifiers)
}

/// A device's connection.
final class Conn {}

/// InputInjector's glue as the model has it, with the coordinator's part (where input lands) and each
/// device's messages.
struct Glue {
    enum Posted: Equatable, CustomStringConvertible {
        case down(UInt16, UInt64), up(UInt16, UInt64), repeated(UInt16, UInt64), text, chord
        var description: String {
            switch self {
            case .down(let k, let f): return "key \(k) down (\(names(f)))"
            case .up(let k, let f): return "key \(k) up (\(names(f)))"
            case .repeated(let k, let f): return "key \(k) repeat (\(names(f)))"
            case .text: return "text"
            case .chord: return "chord"
            }
        }
    }
    var keys = KeyStrokes()
    var rep = KeyRepeat()
    /// The Mac's settings as NSEvent gives them at each key's down (KeyRepeat.timing's answer).
    var timing: KeyRepeat.Timing? = thisMac
    var now = 0.0
    var log: [(t: Double, e: Posted)] = []
    /// When the repeat's task steps next (nil: no task), and the press it was started for.
    var nextStep: Double?
    var scheduled: (key: UInt16, pressedAt: Double)?
    /// Each device's pings: spells of one every 0.25 s from `from` until `until` (nil: on), and its input.
    var pings: [ObjectIdentifier: [(from: Double, until: Double?)]] = [:]
    var messages: [ObjectIdentifier: [Double]] = [:]
    /// Where input lands at a time (the coordinator's KeyRepeat.Landing).
    var landing: (Double) -> KeyRepeat.Landing = { _ in .lands }
    /// How late the task's n-th wake is (a busy main actor).
    var late: (Int) -> Double = { _ in 0 }
    var steps = 0

    /// When `d` was last heard by `t` (StreamServer.lastHeard): its last ping or input; nil once it left.
    func lastHeard(_ d: ObjectIdentifier, at t: Double) -> Double? {
        guard pings[d] != nil || messages[d] != nil else { return nil }
        var best: Double?
        for p in pings[d] ?? [] where t >= p.from {
            let end = min(t, p.until ?? t)
            let last = p.from + (((end - p.from) / 0.25).rounded(.down)) * 0.25
            best = max(best ?? last, last)
        }
        for m in messages[d] ?? [] where m <= t { best = max(best ?? m, m) }
        return best
    }

    mutating func join(_ c: Conn, at t: Double = 0) { pings[ObjectIdentifier(c)] = [(t, nil)] }
    /// The device's pings stop at `t` (the last before it was its last word).
    mutating func silence(_ c: Conn, from t: Double) {
        let d = ObjectIdentifier(c)
        guard var spells = pings[d] else { return }
        spells.removeAll { $0.from > t }                            // a resume still to come is called off
        if let last = spells.indices.last { spells[last].until = min(spells[last].until ?? t, t) }
        pings[d] = spells
    }
    /// They come again from `t`.
    mutating func resume(_ c: Conn, at t: Double) { pings[ObjectIdentifier(c), default: []].append((t, nil)) }

    /// InputInjector.post(strokes:by:): each stroke told to the repeat, then the task for a new press.
    mutating func post(_ strokes: [KeyStroke], by device: ObjectIdentifier?) {
        for s in strokes {
            rep.posted(virtualKey: s.virtualKey, down: s.down, flags: s.flags, by: device, at: now, timing: s.down ? timing : nil)
            log.append((now, s.down ? .down(s.virtualKey, s.flags) : .up(s.virtualKey, s.flags)))
        }
        if !strokes.isEmpty { changed() }
    }
    /// InputInjector.repeatChanged: a new press starts the task, whose first step is at once.
    mutating func changed() {
        let press = rep.held.map { (key: $0.virtualKey, pressedAt: $0.pressedAt) }
        if let press, let was = scheduled, was.key == press.key, was.pressedAt == press.pressedAt { return }
        scheduled = press
        nextStep = press == nil ? nil : now
    }
    mutating func stop() { rep.stop(); changed() }

    /// A device's input at `now`: the coordinator's `.input` (nowhere to land: the repeat stops, and
    /// only the up of a key down goes), then InputInjector.apply.
    mutating func input(_ e: InputEvent, from c: Conn) {
        let d = ObjectIdentifier(c)
        messages[d, default: []].append(now)
        if landing(now) == .nowhere {
            stop()
            guard case .key(let u, false, _) = e, keys.isDown(u) else { return }
        }
        switch e {
        case .key(let u, let down, let m):
            guard let strokes = keys.key(usage: u, down: down, modifiers: m, from: d) else { return }
            post(strokes, by: d)
        case .text:
            post(keys.text(from: d), by: nil)
            log.append((now, .text))
            stop()
        default: break
        }
    }
    /// A trackpad gesture's shortcut (InputInjector.chord): a key of its own, then no repeat.
    mutating func chord() { log.append((now, .chord)); stop() }
    /// A device leaves: its keys go up (InputInjector.releaseKeys); it is no longer heard.
    mutating func leave(_ c: Conn) {
        let d = ObjectIdentifier(c)
        post(keys.release(d), by: nil)
        pings[d] = nil; messages[d] = nil
    }
    /// The host ends (InputInjector.releaseAll).
    mutating func hostEnds() { post(keys.releaseAll(), by: nil); stop() }
    /// A switch dropped what was held (StreamCoordinator.select).
    mutating func dropped() { stop() }

    /// The clock to `t`: every step due before then, at its time plus its lateness, as the task runs
    /// them (an event at the same moment as a step goes first).
    mutating func run(to t: Double) {
        while let at = nextStep, at < t - 1e-9 {
            now = max(now, at)
            steps += 1
            let heard = rep.held.flatMap { lastHeard($0.device, at: now) }
            switch rep.step(at: now, heard: heard, landing: landing(now), holding: keys.heldFlags) {
            case .idle: nextStep = nil; scheduled = nil
            case .wait(let until): nextStep = max(until, now + 0.001) + late(steps)
            case .post(let k, let f, let next): log.append((now, .repeated(k, f))); nextStep = max(next, now + 0.001) + late(steps)
            }
        }
        now = max(now, t)
    }
    /// At `t`: the clock there, then `body`.
    mutating func at(_ t: Double, _ body: (inout Glue) -> Void) { run(to: t); body(&self) }

    var repeats: [(t: Double, key: UInt16, flags: UInt64)] {
        log.compactMap { if case .repeated(let k, let f) = $0.e { return ($0.t, k, f) }; return nil }
    }
    func repeats(between a: Double, _ b: Double) -> [(t: Double, key: UInt16, flags: UInt64)] {
        repeats.filter { $0.t >= a && $0.t < b }
    }
}

/// The repeats a key held from `down` to `up` gets with nothing in the way: one at `down + delay` and
/// every interval after, while before the up.
func expectedTimes(down: Double, up: Double, timing: KeyRepeat.Timing = thisMac) -> [Double] {
    var out: [Double] = []
    var t = down + timing.delay
    while t <= up - 1e-9 { out.append(t); t += timing.interval }
    return out
}
func sameTimes(_ got: [Double], _ want: [Double], _ e: Double = 1e-6) -> Bool {
    got.count == want.count && zip(got, want).allSatisfy { near($0, $1, e) }
}

// MARK: The Mac's settings

check(KeyRepeat.timing(delay: 0.5, interval: 1.0 / 30) == thisMac, "this Mac's 0.5 s and 1/30 s as they are")
check(KeyRepeat.timing(delay: 0.25, interval: 2) == KeyRepeat.Timing(delay: 0.25, interval: 2),
      "System Settings' shortest delay and slowest rate as they are")
check(KeyRepeat.timing(delay: 2, interval: 1.0 / 30) == KeyRepeat.Timing(delay: 2, interval: 1.0 / 30), "the longest delay, 2 s")
check(KeyRepeat.timing(delay: 5000, interval: 1.0 / 30) == nil, "a delay of 5,000 s (Key Repeat Rate Off, as reported): no repeat")
check(KeyRepeat.timing(delay: 0.5, interval: 5000) == nil, "an interval of 5,000 s: no repeat")
check(KeyRepeat.timing(delay: 60, interval: 0.03) == nil && KeyRepeat.timing(delay: 0.5, interval: 60) == nil,
      "a minute or more: no repeat")
check(KeyRepeat.timing(delay: 59.5, interval: 0.03) != nil && KeyRepeat.timing(delay: 0.5, interval: 59.5) != nil,
      "under a minute: a repeat")
check(KeyRepeat.timing(delay: .nan, interval: 0.03) == nil && KeyRepeat.timing(delay: 0.5, interval: .nan) == nil
      && KeyRepeat.timing(delay: .infinity, interval: 0.03) == nil && KeyRepeat.timing(delay: 0.5, interval: -.infinity) == nil,
      "not finite: no repeat")
check(KeyRepeat.timing(delay: 0, interval: 0.03) == nil && KeyRepeat.timing(delay: 0.5, interval: 0) == nil
      && KeyRepeat.timing(delay: -1, interval: 0.03) == nil && KeyRepeat.timing(delay: 0.5, interval: -0.03) == nil,
      "zero or less: no repeat")
check(KeyRepeat.timing(delay: 0.05, interval: 0.001) == KeyRepeat.Timing(delay: 0.1, interval: 0.015),
      "under the shortest delay and interval: those (got \(String(describing: KeyRepeat.timing(delay: 0.05, interval: 0.001))))")
check(KeyRepeat.timing(delay: 1.0 / 6, interval: 1.0 / 60) == KeyRepeat.Timing(delay: 1.0 / 6, interval: 1.0 / 60),
      "`defaults`' faster settings over the floor as they are")
check(KeyRepeat.shortestDelay == 0.1 && KeyRepeat.shortestInterval == 0.015 && KeyRepeat.off == 60
      && KeyRepeat.silence == 0.5 && KeyRepeat.lookAgain == 0.05 && KeyRepeat.firstWord == 0.3, "the constants")

// MARK: Which keys repeat

let macKeys = Set(KeyStrokes.virtualKeys.values)
let modifierCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62]
check(macKeys.filter { !KeyRepeat.repeats(virtualKey: $0) } == modifierCodes.union([57]),
      "of the keys a device sends, only the modifiers' own and Caps Lock never repeat: \(macKeys.filter { !KeyRepeat.repeats(virtualKey: $0) }.sorted())")
check([63, 72, 73, 74].allSatisfy { !KeyRepeat.repeats(virtualKey: $0) }, "fn and the media keys never repeat")
check([0, 6, 36, 48, 49, 51, 53, 117, 115, 119, 116, 121, 123, 124, 125, 126, 96, 122, 111, 18, 29, 27, 50].allSatisfy { KeyRepeat.repeats(virtualKey: $0) },
      "letters, Return, Tab, Space, Delete, Esc, Forward Delete, Home, End, Page Up and Down, the arrows, F-keys, digits, - and ` repeat")
check(KeyStrokes.modifierKeys.allSatisfy { usage, flag in KeyRepeat.modifierKeys[KeyStrokes.virtualKeys[usage]!] == flag }
      && KeyRepeat.modifierKeys.count == 8, "the modifiers' keycodes hold KeyStrokes' flags")

// MARK: A key held

// The left arrow held 1.2 s: its down, a repeat 0.5 s later and every 1/30 s after, with no flags,
// then its up; nothing after.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(2.215) { $0.input(key(uLeft, false), from: a) }
    g.run(to: 4)
    let reps = g.repeats
    check(sameTimes(reps.map(\.t), expectedTimes(down: 1.0, up: 2.215)), "← held 1.2 s: \(reps.count) repeats at \(reps.map { String(format: "%.4f", $0.t) })")
    check(reps.count == 22 && reps.allSatisfy { $0.key == kLeft && $0.flags == 0 }, "22 repeats of ←, no flags: \(reps.count)")
    check(g.log.first?.e == .down(kLeft, 0) && g.log.last?.e == .up(kLeft, 0) && g.log.count == 24, "down, the repeats, up: \(g.log.map(\.e))")
    check(g.rep.held == nil && g.nextStep == nil, "nothing held after its up, no task")
}
// A tap: down and up 0.1 s apart (and 0.45 s apart: still under the delay): no repeat.
do {
    for hold in [0.1, 0.45, 0.499] {
        var g = Glue(); let a = Conn(); g.join(a)
        g.at(1.0) { $0.input(key(uEsc, true), from: a) }
        g.at(1.0 + hold) { $0.input(key(uEsc, false), from: a) }
        g.run(to: 3)
        check(g.repeats.isEmpty, "Esc tapped for \(hold) s: no repeat, got \(g.repeats.count)")
    }
}
// Held exactly to the first repeat's time and just past it.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uRight, true), from: a) }
    g.at(1.501) { $0.input(key(uRight, false), from: a) }
    check(g.repeats.count == 1 && near(g.repeats[0].t, 1.5), "→ held 0.501 s: one repeat, at 0.5 s: \(g.repeats.map(\.t))")
}
// The slowest rate and a shorter delay: 0.25 s, then every 2 s.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.timing = KeyRepeat.timing(delay: 0.25, interval: 2)
    g.at(1.0) { $0.input(key(uDel, true), from: a) }
    g.at(5.5) { $0.input(key(uDel, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), [1.25, 3.25, 5.25]), "Delete held 4.5 s at 0.25 s and 2 s: \(g.repeats.map(\.t))")
}
// Off: nothing repeats, however long the key is held; and settings under the floor take the floor.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.timing = KeyRepeat.timing(delay: 5000, interval: 1.0 / 30)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(4.0) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats.isEmpty && g.rep.held == nil, "Key Repeat Off: no repeat in 3 s, got \(g.repeats.count)")
    var f = Glue(); f.join(a, at: 0.05)       // a ping at 1.05 s, between the press and its first repeat (firstWord)
    f.timing = KeyRepeat.timing(delay: 0.01, interval: 0.001)
    f.at(1.0) { $0.input(key(uLeft, true), from: a) }
    f.at(1.2) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(f.repeats.map(\.t), expectedTimes(down: 1.0, up: 1.2, timing: KeyRepeat.Timing(delay: 0.1, interval: 0.015))),
          "a delay of 0.01 s and 1 ms take 0.1 s and 15 ms: \(f.repeats.map(\.t))")
}
// The settings are read at each key's down: a change applies from the next key.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.2) { $0.timing = KeyRepeat.timing(delay: 1, interval: 0.1) }
    g.at(1.62) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 1.62)), "a change while held leaves that key's repeat: \(g.repeats.map(\.t))")
    g.at(2.0) { $0.input(key(uLeft, true), from: a) }
    g.at(3.25) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats(between: 2, 4).map(\.t), [3.0, 3.1, 3.2]), "the next key takes the new settings: \(g.repeats(between: 2, 4).map(\.t))")
}

// MARK: Modifiers

// ⌥← from a hardware keyboard (ForwardedKeys: ⌥'s own key, then ← carrying option), ⌥ let go while ←
// stays down: the repeats carry option until then and nothing after, and the repeat goes on.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(0.9) { $0.input(key(uLOpt, true, option), from: a) }
    g.at(1.0) { $0.input(key(uLeft, true, option), from: a) }
    g.at(1.8) { $0.input(key(uLOpt, false, 0), from: a) }
    g.at(2.4) { $0.input(key(uLeft, false, 0), from: a) }
    let before = g.repeats(between: 0, 1.8), after = g.repeats(between: 1.8, 3)
    check(!before.isEmpty && before.allSatisfy { $0.flags == option }, "⌥← repeats carry option: \(before.map { names($0.flags) })")
    check(!after.isEmpty && after.allSatisfy { $0.flags == 0 }, "after ⌥'s up, plain ← repeats: \(after.map { names($0.flags) })")
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.4)), "⌥'s up neither stops nor delays the repeat: \(g.repeats.map(\.t))")
    check(g.log.contains { $0.e == .up(kOpt, 0) }, "⌥'s own up is posted")
}
// ⌥ let go before the first repeat: none carries it.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(0.9) { $0.input(key(uLOpt, true, option), from: a) }
    g.at(1.0) { $0.input(key(uLeft, true, option), from: a) }
    g.at(1.2) { $0.input(key(uLOpt, false, 0), from: a) }
    g.at(1.9) { $0.input(key(uLeft, false, 0), from: a) }
    check(!g.repeats.isEmpty && g.repeats.allSatisfy { $0.flags == 0 }, "⌥ up before the first repeat: plain repeats: \(g.repeats.map { names($0.flags) })")
}
// ⇧ pressed while ← repeats (the key row's latched shift is its own key; so is a device's ⇧ key): the
// repeats after it carry shift, as a Mac's do (holding ← and pressing ⇧ selects), and stop carrying it
// at its up.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.input(key(uLShift, true, shift), from: a) }
    g.at(2.0) { $0.input(key(uLShift, false, 0), from: a) }
    g.at(2.3) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 0, 1.7).allSatisfy { $0.flags == 0 } && g.repeats(between: 1.7, 2.0).allSatisfy { $0.flags == shift }
          && !g.repeats(between: 1.7, 2.0).isEmpty && g.repeats(between: 2.0, 3).allSatisfy { $0.flags == 0 },
          "⇧ held from 1.7 to 2.0 s: \(g.repeats.map { "\(String(format: "%.3f", $0.t)) \(names($0.flags))" })")
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.3)), "⇧'s down and up neither stop nor delay it")
}
// A hardware ⇧→: shift is only in the key's own word (the text system keeps ⇧'s key): every repeat
// carries it.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uRight, true, shift), from: a) }
    g.at(1.8) { $0.input(key(uRight, false, shift), from: a) }
    check(!g.repeats.isEmpty && g.repeats.allSatisfy { $0.flags == shift }, "⇧→ repeats carry shift: \(g.repeats.map { names($0.flags) })")
}
// What the host says of it in its window lists (WindowList.keyRepeat), which a device needs before it sends a
// hardware keyboard's characters as keys.
check(KeyRepeat.generation == 1, "keyRepeat 1 in every window list")

// Letters, as a device sends them while the Mac types a hardware keyboard's characters (KeyTyping, #162's
// letters: "hold p didnt work"): P held repeats as ← does, with no flags; then E pressed while P is held
// takes over after its own delay, and P never again.
let uP: UInt16 = 0x13, uE: UInt16 = 0x08, kP: UInt16 = 35, kE: UInt16 = 14
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uP, true), from: a) }
    g.at(2.215) { $0.input(key(uP, false), from: a) }
    g.run(to: 4)
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.215)) && g.repeats.count == 22
          && g.repeats.allSatisfy { $0.key == kP && $0.flags == 0 },
          "P held 1.2 s: \(g.repeats.count) repeats of key \(g.repeats.first?.key ?? 0) from 0.5 s at the Mac's rate")
    var two = Glue(); let b = Conn(); two.join(b)
    two.at(1.0) { $0.input(key(uP, true), from: b) }
    two.at(1.8) { $0.input(key(uE, true), from: b) }
    two.at(2.5) { $0.input(key(uE, false), from: b) }
    two.at(2.9) { $0.input(key(uP, false), from: b) }
    two.run(to: 4)
    check(two.repeats(between: 0, 1.8).allSatisfy { $0.key == kP } && two.repeats(between: 1.8, 4).allSatisfy { $0.key == kE }
          && sameTimes(two.repeats(between: 1.8, 4).map(\.t), expectedTimes(down: 1.8, up: 2.5)),
          "P held, then E: P's repeats, then E's after its own delay, P's never again: \(two.repeats.map { "\($0.key)" })")
}
// ⇧ held, A held, ⇧ let go: capitals, then small letters, as a Mac's own keyboard types them (Shift is a key of
// its own while the Mac types a hardware keyboard's characters).
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(0.8) { $0.input(key(uLShift, true, shift), from: a) }
    g.at(1.0) { $0.input(key(uA, true, shift), from: a) }
    g.at(1.9) { $0.input(key(uLShift, false, 0), from: a) }
    g.at(2.4) { $0.input(key(uA, false, 0), from: a) }
    let before = g.repeats(between: 0, 1.9), after = g.repeats(between: 1.9, 3)
    check(!before.isEmpty && before.allSatisfy { $0.key == kA && $0.flags == shift } && !after.isEmpty && after.allSatisfy { $0.flags == 0 },
          "⇧A held, ⇧ let go: \(before.count) with shift, then \(after.count) without")
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.4)), "⇧'s up neither stops nor delays A's repeat")
}
// A with Caps Lock on (the device's: the down carries caps lock and shift, no Shift key held): every repeat a
// capital.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uA, true, capsLock | shift), from: a) }
    g.at(1.9) { $0.input(key(uA, false, 0), from: a) }
    check(!g.repeats.isEmpty && g.repeats.allSatisfy { $0.key == kA && $0.flags == capsLock | shift },
          "A with Caps Lock on held: every repeat carries caps lock and shift: \(g.repeats.map { names($0.flags) })")
}
// ⌘Z held: ⌘'s key, then Z with command: the repeats are ⌘Z (an undo at each), as a Mac's.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(0.8) { $0.input(key(uLCmd, true, command), from: a) }
    g.at(1.0) { $0.input(key(uZ, true, command), from: a) }
    g.at(2.0) { $0.input(key(uZ, false, command), from: a) }
    g.at(2.1) { $0.input(key(uLCmd, false, 0), from: a) }
    check(g.repeats.count == expectedTimes(down: 1.0, up: 2.0).count && g.repeats.allSatisfy { $0.key == kZ && $0.flags == command },
          "⌘Z held 1 s: \(g.repeats.count) repeats of ⌘Z")
}
// Left and right ⌘: one let go, the other still holds command for the repeats.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(0.8) { $0.input(key(uLCmd, true, command), from: a) }
    g.at(0.85) { $0.input(key(uRCmd, true, command), from: a) }
    g.at(1.0) { $0.input(key(uUp, true, command), from: a) }
    g.at(1.7) { $0.input(key(uLCmd, false, command), from: a) }
    g.at(2.0) { $0.input(key(uRCmd, false, 0), from: a) }
    g.at(2.3) { $0.input(key(uUp, false, 0), from: a) }
    check(!g.repeats(between: 1.7, 2.0).isEmpty && g.repeats(between: 0, 2.0).allSatisfy { $0.flags == command }
          && !g.repeats(between: 2.0, 3).isEmpty && g.repeats(between: 2.0, 3).allSatisfy { $0.flags == 0 },
          "left ⌘ up keeps the right one's command: \(g.repeats.map { "\(String(format: "%.3f", $0.t)) \(names($0.flags))" })")
}
// Caps Lock on: its flag rides with the key's own word, and the repeats keep it.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true, 1 << 16), from: a) }
    g.at(1.7) { $0.input(key(uLeft, false, 1 << 16), from: a) }
    check(!g.repeats.isEmpty && g.repeats.allSatisfy { $0.flags == capsLock }, "caps lock rides along: \(g.repeats.map { names($0.flags) })")
}
// A modifier's own key never repeats, held as long as it may; nor does Caps Lock's.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLCmd, true, command), from: a) }
    g.at(4.0) { $0.input(key(uLCmd, false, 0), from: a) }
    g.at(5.0) { $0.input(key(uCaps, true), from: a) }
    g.at(8.0) { $0.input(key(uCaps, false), from: a) }
    g.run(to: 9)
    check(g.repeats.isEmpty && g.nextStep == nil, "⌘ held 3 s and Caps Lock held 3 s: no repeat, got \(g.repeats.count)")
}

// MARK: One key at a time

// Another key's down stops the one before and repeats itself; the first's up later changes nothing,
// and the first never takes over again.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.input(key(uRight, true), from: a) }
    g.at(2.4) { $0.input(key(uLeft, false), from: a) }
    g.at(2.95) { $0.input(key(uRight, false), from: a) }
    g.run(to: 4)
    check(sameTimes(g.repeats.filter { $0.key == kLeft }.map(\.t), expectedTimes(down: 1.0, up: 1.7)), "← repeats until → goes down")
    check(sameTimes(g.repeats.filter { $0.key == kRight }.map(\.t), expectedTimes(down: 1.7, up: 2.95)), "→ from 0.5 s after its down to its up, ←'s up between")
    var h = Glue(); h.join(a)
    h.at(1.0) { $0.input(key(uLeft, true), from: a) }
    h.at(1.7) { $0.input(key(uRight, true), from: a) }
    h.at(2.4) { $0.input(key(uRight, false), from: a) }
    h.at(4.0) { $0.input(key(uLeft, false), from: a) }
    check(h.repeats(between: 2.4, 5).isEmpty, "← still down after →'s up: it does not repeat again, got \(h.repeats(between: 2.4, 5).count)")
}
// The same key pressed again (a second down without an up): the delay starts over.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.6) { $0.input(key(uLeft, true), from: a) }
    g.at(2.25) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 1.6) + expectedTimes(down: 1.6, up: 2.25)),
          "a second down starts the delay over: \(g.repeats.map(\.t))")
}
// A key that never repeats stops the one before (Caps Lock), a modifier's own key does not.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.input(key(uCaps, true), from: a) }
    g.at(1.8) { $0.input(key(uCaps, false), from: a) }
    g.at(2.5) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 1.7, 3).isEmpty && !g.repeats(between: 0, 1.7).isEmpty, "Caps Lock's down stops ←'s repeat")
}
// Typed text and a gesture's shortcut are keys pressed after the held one: it stops.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.input(.text("a"), from: a) }
    g.at(2.5) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 1.7, 3).isEmpty && !g.repeats(between: 0, 1.7).isEmpty, "text stops the repeat")
    var h = Glue(); h.join(a)
    h.at(1.0) { $0.input(key(uLeft, true), from: a) }
    h.at(1.7) { $0.chord() }
    h.at(2.5) { $0.input(key(uLeft, false), from: a) }
    check(h.repeats(between: 1.7, 3).isEmpty && !h.repeats(between: 0, 1.7).isEmpty, "a gesture's shortcut stops the repeat")
}
// A pointer's click or a scroll changes nothing (a Mac's keyboard repeats under the mouse).
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.6) { $0.input(.pointer(.leftDown, x: 0.5, y: 0.5), from: a) }
    g.at(1.7) { $0.input(.pointer(.leftUp, x: 0.5, y: 0.5), from: a) }
    g.at(1.8) { $0.input(.scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1), from: a) }
    g.at(2.4) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.4)), "a click and a scroll leave the repeat alone")
}

// MARK: Two devices

// Device B's ⌘ while A's ← repeats: the repeats carry command (a Mac with two keyboards does), until
// B lets go of it.
do {
    var g = Glue(); let a = Conn(), b = Conn(); g.join(a); g.join(b, at: 0.1)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.6) { $0.input(key(uLCmd, true, command), from: b) }
    g.at(1.9) { $0.input(key(uLCmd, false, 0), from: b) }
    g.at(2.3) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 1.6, 1.9).allSatisfy { $0.flags == command } && !g.repeats(between: 1.6, 1.9).isEmpty
          && g.repeats(between: 1.9, 3).allSatisfy { $0.flags == 0 } && g.repeats(between: 0, 1.6).allSatisfy { $0.flags == 0 },
          "another device's ⌘: \(g.repeats.map { "\(String(format: "%.3f", $0.t)) \(names($0.flags))" })")
}
// B presses the key A holds, and lets it go: the key is up on the Mac, nothing repeats; A's own up
// later changes nothing.
do {
    var g = Glue(); let a = Conn(), b = Conn(); g.join(a); g.join(b)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.6) { $0.input(key(uLeft, true), from: b) }
    g.at(2.25) { $0.input(key(uLeft, false), from: b) }
    g.at(3.0) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 1.6) + expectedTimes(down: 1.6, up: 2.25)),
          "B's press of the same key starts it over, B's up ends it: \(g.repeats.map(\.t))")
}
// B's key down stops A's repeat; B leaving later leaves A's key down and not repeating.
do {
    var g = Glue(); let a = Conn(), b = Conn(); g.join(a); g.join(b)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.6) { $0.input(key(uEsc, true), from: b) }
    g.at(2.4) { $0.leave(b) }
    g.at(3.5) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.filter { $0.key == kEsc }.map(\.t), expectedTimes(down: 1.6, up: 2.4)), "B's Esc repeats until B leaves")
    check(g.repeats(between: 2.4, 4).isEmpty, "then nothing: A's ← was replaced")
    check(g.log.contains { $0.t == 2.4 && $0.e == .up(kEsc, 0) }, "B's Esc goes up as B leaves")
}

// MARK: The repeat stops

// The device leaves while its key repeats: the key goes up (InputInjector.releaseKeys), no repeat after.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.leave(a) }
    g.run(to: 4)
    check(g.repeats(between: 1.7, 5).isEmpty && g.log.contains { $0.t == 1.7 && $0.e == .up(kLeft, 0) } && g.nextStep == nil,
          "the device leaves: ← up, no repeat after")
}
// The host ends (Quit, a signal): every key up, no repeat after.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLOpt, true, option), from: a) }
    g.at(1.05) { $0.input(key(uLeft, true, option), from: a) }
    g.at(1.7) { $0.hostEnds() }
    g.run(to: 4)
    check(g.repeats(between: 1.7, 5).isEmpty && g.nextStep == nil && g.keys.down.isEmpty, "the host ends: no repeat, nothing down")
}
// Input with nowhere to land (the stream stopped, the window went): the repeat stops, at its next
// step, and the key's up still goes when it comes; it lands again, and ← (still down) does not repeat
// until it is pressed again.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.landing = { t in t >= 1.7 && t < 2.0 ? .nowhere : .lands }
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.run(to: 2.5)
    check(g.repeats(between: 1.7, 2.6).isEmpty && !g.repeats(between: 0, 1.7).isEmpty && g.rep.held == nil,
          "nowhere to land from 1.7 s: no repeat, then or after it lands again: \(g.repeats(between: 1.7, 2.6).map(\.t))")
    g.at(2.6) { $0.input(key(uLeft, false), from: a) }
    check(g.log.contains { $0.t == 2.6 && $0.e == .up(kLeft, 0) }, "the key's up goes")
    g.at(3.0) { $0.input(key(uLeft, true), from: a) }
    g.at(3.6) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats(between: 3, 4).map(\.t), expectedTimes(down: 3.0, up: 3.6)), "a new press repeats again")
}
// Input arriving with nowhere to land stops it at once (the coordinator's input handler), and the key's
// up then still goes.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    var nowhere = false
    g.landing = { _ in nowhere ? .nowhere : .lands }
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.run(to: 1.7)
    nowhere = true
    g.input(.pointer(.move, x: 0.1, y: 0.1), from: a)
    nowhere = false
    g.run(to: 2.4)
    check(g.repeats(between: 1.7, 3).isEmpty && g.rep.held == nil, "a move with nowhere to land stops the repeat")
}
// A switch drops what was held (StreamCoordinator.select): no repeat into the next source.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(1.7) { $0.dropped() }
    g.at(2.6) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 1.7, 3).isEmpty && g.log.contains { $0.t == 2.6 && $0.e == .up(kLeft, 0) }, "dropped at a switch: no repeat, the up goes")
}

// MARK: Input held for an app's activation

// While input waits for an activation (StreamCoordinator's hold, at most 0.6 s) no repeat goes out
// ahead of it; once it is released the repeat goes on, one at once and then on its cadence, never two
// closer than half an interval.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.landing = { t in t >= 1.6 && t < 1.75 ? .held : .lands }
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(2.3) { $0.input(key(uLeft, false), from: a) }
    let reps = g.repeats.map(\.t)
    check(g.repeats(between: 1.6, 1.75).isEmpty, "no repeat while input is held: \(g.repeats(between: 1.6, 1.75).map(\.t))")
    let after = g.repeats(between: 1.75, 3).map(\.t)
    check(!after.isEmpty && after[0] < 1.75 + KeyRepeat.lookAgain + 1e-9, "one at once after the hold: \(after.first ?? -1)")
    check(zip(reps, reps.dropFirst()).allSatisfy { $1 - $0 >= thisMac.interval / 2 - 1e-9 }, "never two closer than half an interval")
}

// MARK: The device gone quiet

// The device stops being heard (its last ping at 1.5 s): the repeats stop half a second later, and
// once it is heard again (3.0 s) they start over after the delay.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.silence(a, from: 1.6)
    g.resume(a, at: 3.0)
    g.at(4.0) { $0.input(key(uLeft, false), from: a) }
    let quiet = g.repeats(between: 2.0 + 1e-9, 3.5 - 1e-9)
    check(quiet.isEmpty, "no repeat between half a second after the last ping and the delay after the next: \(quiet.map(\.t))")
    check(!g.repeats(between: 1.5, 2.0 + 1e-9).isEmpty, "repeats until the device has been quiet half a second")
    let back = g.repeats(between: 3.0, 4.1)
    check(!back.isEmpty && back[0].t >= 3.5 - 1e-9 && back[0].t <= 3.5 + KeyRepeat.lookAgain + 1e-9,
          "heard again at 3.0 s: the repeat starts over 0.5 s later: \(back.first.map { $0.t } ?? -1)")
    check(sameTimes(back.map(\.t), expectedTimes(down: back[0].t - 0.5, up: 4.0)), "then on its cadence")
}
// The device quiet from just before its key's down, its last word: no repeat. The down says nothing of the key
// half a second on (KeyRepeat.firstWord: the first repeat needs a word heard since, within 0.3 s of it).
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.silence(a, from: 0.9)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.run(to: 3)
    check(g.repeats.isEmpty, "its last word was the key's down: no repeat: \(g.repeats.map(\.t))")
    var h = Glue(); h.join(a)
    h.timing = KeyRepeat.timing(delay: 0.6, interval: 1.0 / 30)
    h.silence(a, from: 0.9)
    h.at(1.0) { $0.input(key(uLeft, true), from: a) }
    h.run(to: 3)
    check(h.repeats.isEmpty, "with a delay of 0.6 s, quiet past it: no repeat: \(h.repeats.map(\.t))")
}
// The device that left is not heard at all (StreamServer.lastHeard: nil): no repeat even before its
// keys come up (a key let go from another path in the model).
do {
    var r = KeyRepeat()
    let d = ObjectIdentifier(Conn())
    r.posted(virtualKey: kLeft, down: true, flags: 0, by: d, at: 1.0, timing: thisMac)
    check(r.step(at: 1.0, heard: nil, landing: .lands, holding: 0) == .wait(until: 1.5), "before the delay: wait for it")
    if case .wait = r.step(at: 1.5, heard: nil, landing: .lands, holding: 0) {} else { check(false, "not heard: no repeat") }
    check(r.held?.quietSince != nil, "not heard counts as quiet")
}
// A pause in the device's messages shorter than half a second changes nothing.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.silence(a, from: 1.6)
    g.resume(a, at: 1.95)
    g.at(2.4) { $0.input(key(uLeft, false), from: a) }
    check(sameTimes(g.repeats.map(\.t), expectedTimes(down: 1.0, up: 2.4)), "a 0.45 s pause between pings: the repeat goes on")
}

// MARK: The first repeat's word (KeyRepeat.firstWord)

// A key pressed for a moment (a letter typed, a Delete: up 0.1 s after its down, as the Mac types a hardware
// keyboard's characters, #162's letters), its up held back by a stalled link. The link keeps the device's messages
// in order: the pings due during the stall come after the up, together when it ends. A ping sent while the key
// was down, before the up, is no word that it is still down half a second on: never a repeat, at any phase of the
// pings and any stall. Before the first-word rule a stall of more than 0.4 s repeated it one to three times on this
// Mac (and in this model whatever the phase: the key's own down counted as the word).
do {
    var repeated: [String] = [], runs = 0
    for phase in stride(from: 0.0, to: 0.25, by: 0.01) {
        for stall in [0.3, 0.41, 0.45, 0.5, 0.6, 1.0, 2.0] {
            var g = Glue(); let a = Conn(); g.join(a)
            let down = 1.0 + phase, up = down + 0.1
            g.at(down) { $0.input(key(uA, true), from: a) }
            g.silence(a, from: up)                 // nothing heard after the up until the stall ends
            g.resume(a, at: up + stall)
            g.at(up + stall) { $0.input(key(uA, false), from: a) }
            g.run(to: up + stall + 1)
            runs += 1
            if !g.repeats.isEmpty { repeated.append("phase \(phase), stall \(stall): \(g.repeats.count)") }
        }
    }
    check(repeated.isEmpty, "a letter typed, its up held back by a stall: never repeated (\(repeated.count) of \(runs): \(repeated.prefix(4)))")
    // Held for real, the same pings: its first repeat on time at every phase (a ping comes within any 0.3 s).
    var late: [String] = []
    for phase in stride(from: 0.0, to: 0.25, by: 0.01) {
        var g = Glue(); let a = Conn(); g.join(a)
        let down = 1.0 + phase
        g.at(down) { $0.input(key(uA, true), from: a) }
        g.at(down + 1.0) { $0.input(key(uA, false), from: a) }
        if !sameTimes(g.repeats.map(\.t), expectedTimes(down: down, up: down + 1.0)) { late.append("phase \(phase): \(g.repeats.first?.t ?? -1)") }
    }
    check(late.isEmpty, "a key held 1 s: its first repeat at 0.5 s and then on its cadence at every phase of the pings: \(late)")
}
// A ping late (the one due at 1.25 s heard at 1.52 s): the first repeat waits for it and goes at once, then on its
// cadence; nothing quiet, nothing started over.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uA, true), from: a) }
    g.silence(a, from: 1.2)
    g.resume(a, at: 1.52)
    g.at(2.0) { $0.input(key(uA, false), from: a) }
    let t = g.repeats.map(\.t)
    check(!t.isEmpty && t[0] >= 1.52 - 1e-9 && t[0] <= 1.52 + KeyRepeat.lookAgain + 1e-9 && g.rep.held == nil,
          "a late ping: the first repeat when it comes: \(t.first ?? -1)")
    check(t.count >= 13 && zip(t, t.dropFirst()).allSatisfy { $1 - $0 >= thisMac.interval / 2 - 1e-9 }, "then on: \(t.count) repeats")
}
// System Settings' shortest Delay Until Repeat (0.25 s, under firstWord): any word since the press will do. A ping
// between the press and the first repeat: on time; the device quiet from the press: none.
do {
    var g = Glue(); let a = Conn(); g.join(a, at: 0.05)     // pings at 1.05, 1.30…
    g.timing = KeyRepeat.timing(delay: 0.25, interval: 1.0 / 30)
    g.at(1.0) { $0.input(key(uA, true), from: a) }
    g.at(1.6) { $0.input(key(uA, false), from: a) }
    check(!g.repeats.isEmpty && near(g.repeats[0].t, 1.25), "a 0.25 s delay, a ping since the press: the first repeat at 0.25 s: \(g.repeats.first?.t ?? -1)")
    var h = Glue(); h.join(a, at: 0.05)
    h.timing = KeyRepeat.timing(delay: 0.25, interval: 1.0 / 30)
    h.silence(a, from: 0.99)
    h.at(1.0) { $0.input(key(uA, true), from: a) }
    h.run(to: 3)
    check(h.repeats.isEmpty, "a 0.25 s delay, nothing heard since the press: no repeat: \(h.repeats.map(\.t))")
}
// After a quiet spell the repeat starts over, and its first repeat needs a word too: heard again for a moment (a
// ping at 3.0 s and a message at 3.1 s, then a second stall), no repeat after it. Without the word the repeat
// starting over at 3.0 s would go out at 3.5 s on the message heard at 3.1 s.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.silence(a, from: 1.6)
    g.resume(a, at: 3.0)
    g.silence(a, from: 3.0)
    g.at(3.1) { $0.input(.pointer(.move, x: 0.5, y: 0.5), from: a) }
    g.at(5.0) { $0.input(key(uLeft, false), from: a) }
    check(g.repeats(between: 2.2, 5.1).isEmpty, "heard again for a moment after a quiet spell: no repeat after it: \(g.repeats(between: 2.2, 5.1).map(\.t))")
    // Heard again for good: the repeat starts over after the delay, on time.
    var h = Glue(); h.join(a)
    h.at(1.0) { $0.input(key(uLeft, true), from: a) }
    h.silence(a, from: 1.6)
    h.resume(a, at: 3.0)
    h.at(5.0) { $0.input(key(uLeft, false), from: a) }
    let back = h.repeats(between: 2.2, 5.1)
    check(!back.isEmpty && back[0].t >= 3.5 - 1e-9 && back[0].t <= 3.5 + KeyRepeat.lookAgain + 1e-9,
          "heard again for good: the repeat starts over 0.5 s later: \(back.first?.t ?? -1)")
}

// MARK: Late steps

// A busy main actor: every wake 10 ms late keeps the cadence (each repeat due an interval after the
// one before); every wake 50 ms late (more than an interval) gives one repeat a wake, never a burst.
do {
    var g = Glue(); let a = Conn(); g.join(a)
    g.late = { _ in 0.01 }
    g.at(1.0) { $0.input(key(uLeft, true), from: a) }
    g.at(3.0) { $0.input(key(uLeft, false), from: a) }
    let n = g.repeats.count, want = expectedTimes(down: 1.0, up: 3.0).count
    check(abs(n - want) <= 1, "10 ms late at each wake: \(n) repeats in 2 s, \(want) on time")
    var h = Glue(); h.join(a)
    h.late = { _ in 0.05 }
    h.at(1.0) { $0.input(key(uLeft, true), from: a) }
    h.at(3.0) { $0.input(key(uLeft, false), from: a) }
    let t = h.repeats.map(\.t)
    check(zip(t, t.dropFirst()).allSatisfy { $1 - $0 >= thisMac.interval / 2 - 1e-9 } && t.count >= 10,
          "50 ms late at each wake: \(t.count) repeats, never two within half an interval")
    var j = Glue(); j.join(a)
    j.late = { n in n == 3 ? 0.2 : 0 }      // one wake 0.2 s late (six intervals)
    j.at(1.0) { $0.input(key(uLeft, true), from: a) }
    j.at(2.0) { $0.input(key(uLeft, false), from: a) }
    let u = j.repeats.map(\.t)
    check(zip(u, u.dropFirst()).allSatisfy { $1 - $0 >= thisMac.interval / 2 - 1e-9 }, "one wake 0.2 s late: no burst after it: \(u)")
}

// MARK: The step itself

do {
    var r = KeyRepeat()
    let d = ObjectIdentifier(Conn())
    check(r.step(at: 0, heard: 0, landing: .lands, holding: 0) == .idle, "nothing held: idle")
    r.posted(virtualKey: kLeft, down: true, flags: option, by: d, at: 1.0, timing: thisMac)
    check(r.held?.due == 1.5 && r.held?.carried == option && r.held?.pressedAt == 1.0, "a down: due after the delay, its flags carried")
    check(r.step(at: 1.2, heard: 1.2, landing: .lands, holding: option) == .wait(until: 1.5), "before it is due: wait")
    check(r.step(at: 1.5, heard: 1.4, landing: .lands, holding: shift) == .post(virtualKey: kLeft, flags: option | shift, next: 1.5 + 1.0 / 30),
          "due: a repeat with what the down carried and what is held now, the next an interval later")
    r.posted(virtualKey: kOpt, down: false, flags: 0, by: d, at: 1.51, timing: nil)
    check(r.held?.carried == 0, "⌥'s up takes option out of what it carries")
    r.posted(virtualKey: kShift, down: true, flags: shift, by: d, at: 1.52, timing: thisMac)
    check(r.held?.virtualKey == kLeft && r.held?.due == 1.5 + 1.0 / 30, "a modifier's down leaves the press as it is")
    check(r.step(at: 1.6, heard: 1.5, landing: .held, holding: 0) == .wait(until: 1.6 + 1.0 / 30),
          "held behind an activation: look again an interval on (under lookAgain)")
    check(r.step(at: 1.6, heard: 1.5, landing: .nowhere, holding: 0) == .idle && r.held == nil, "nowhere to land: idle, nothing held")
    r.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 2.0, timing: thisMac)
    r.posted(virtualKey: kA, down: false, flags: 0, by: d, at: 2.1, timing: nil)
    check(r.held?.virtualKey == kZ, "another key's up leaves the repeat")
    r.posted(virtualKey: kZ, down: false, flags: 0, by: d, at: 2.2, timing: nil)
    check(r.held == nil, "its own up ends it")
    r.posted(virtualKey: kZ, down: true, flags: 0, by: nil, at: 2.3, timing: thisMac)
    check(r.held == nil, "a down with no device: no repeat")
    r.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 2.4, timing: nil)
    check(r.held == nil, "a down with no timing (Off): no repeat")
    r.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 2.5, timing: thisMac)
    r.posted(virtualKey: kCaps, down: true, flags: 0, by: d, at: 2.6, timing: thisMac)
    check(r.held == nil, "a key that never repeats stops the one before")
    r.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 3.0, timing: thisMac)
    r.stop()
    check(r.held == nil, "stop")
    // Quiet and back.
    r.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 4.0, timing: thisMac)
    check(r.step(at: 4.5, heard: 3.9, landing: .lands, holding: 0) == .wait(until: 4.5 + 1.0 / 30) && r.held?.quietSince == 3.9,
          "heard 0.6 s ago: quiet, nothing posted")
    check(r.step(at: 4.6, heard: 3.9, landing: .lands, holding: 0) == .wait(until: 4.6 + 1.0 / 30), "still quiet")
    check(r.step(at: 4.7, heard: 4.65, landing: .lands, holding: 0) == .wait(until: 5.2) && r.held?.quietSince == nil,
          "heard again: wait the delay over")
    check(r.step(at: 5.2, heard: 5.0, landing: .lands, holding: 0) == .post(virtualKey: kZ, flags: 0, next: 5.2 + 1.0 / 30), "then repeat")
    check(r.step(at: 5.2 + 1.0 / 30 + 0.2, heard: 5.4, landing: .lands, holding: 0)
          == .post(virtualKey: kZ, flags: 0, next: 5.2 + 1.0 / 30 + 0.2 + 1.0 / 60), "0.2 s late: one repeat, the next half an interval on")
    check(r.step(at: 5.44, heard: 5.4, landing: .lands, holding: 0) == .wait(until: 5.2 + 1.0 / 30 + 0.2 + 1.0 / 60),
          "before that, a wait")
    // A slow rate looks again at most every lookAgain while waiting.
    var s = KeyRepeat()
    s.posted(virtualKey: kZ, down: true, flags: 0, by: d, at: 0, timing: KeyRepeat.Timing(delay: 0.5, interval: 2))
    check(s.step(at: 0.5, heard: 0.5, landing: .held, holding: 0) == .wait(until: 0.5 + KeyRepeat.lookAgain), "a 2 s interval: held, look again in 50 ms")
    check(s.step(at: 0.6, heard: 0, landing: .lands, holding: 0) == .wait(until: 0.6 + KeyRepeat.lookAgain), "quiet: look again in 50 ms")
}

// MARK: Random sessions

struct Rng {
    var state: UInt64
    mutating func next() -> UInt64 { state ^= state << 13; state ^= state >> 7; state ^= state << 17; return state }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    mutating func pick<T>(_ a: [T]) -> T { a[below(a.count)] }
    mutating func time(_ max: Double) -> Double { Double(below(Int(max * 1000))) / 1000 }
}

/// What a session's repeats must be, judged against the Mac's view of each posted event and the model's
/// own record of the last press: the safe invariants always; with `strict` (nothing in the way: every
/// device heard, input landing, no late wake, the Mac's settings), the exact times too.
struct Judge {
    var timing: KeyRepeat.Timing?
    var down: [UInt16: Bool] = [:]
    /// The last press that may repeat: its key, time, device and flags less the modifiers let go since;
    /// nil once something stopped it.
    var press: (key: UInt16, t: Double, device: ObjectIdentifier, flags: UInt64)?
    var lastRepeat: Double?
    var broken: [String] = []
    mutating func posted(_ e: Glue.Posted, at t: Double, by device: ObjectIdentifier?, heldFlags: UInt64) {
        switch e {
        case .down(let k, let f):
            down[k] = true
            if KeyRepeat.modifierKeys[k] != nil { return }
            if let device, timing != nil, KeyRepeat.repeats(virtualKey: k) { press = (k, t, device, f); lastRepeat = nil } else { press = nil }
        case .up(let k, _):
            down[k] = false
            if let flag = KeyRepeat.modifierKeys[k] { press?.flags &= ~flag } else if press?.key == k { press = nil }
        case .text, .chord: press = nil
        case .repeated: break
        }
    }
}

do {
    var rng = Rng(state: 0x1EE7_5EED_C0DE)
    var sessions = 0, repeatsSeen = 0, strictSessions = 0, strictRepeats = 0
    var brokenSessions = 0
    let usages: [UInt16] = [uLeft, uRight, uUp, uZ, uA, uEsc, uFwdDel, uDel, uTab, uCaps, uLCmd, uRCmd, uLOpt, uLShift, uLCtrl]
    for run in 0..<2400 {
        let strict = run < 600
        var g = Glue()
        g.timing = strict ? thisMac : rng.pick([thisMac, KeyRepeat.timing(delay: 0.25, interval: 0.1)!, KeyRepeat.timing(delay: 0.15, interval: 0.015)!, nil])
        let conns = [Conn(), Conn(), Conn()]
        for c in conns { g.join(c, at: 0) }
        var landingWindows: [(Double, Double, KeyRepeat.Landing)] = []
        if !strict {
            for _ in 0..<rng.below(3) {
                let a = rng.time(9); landingWindows.append((a, a + rng.time(1), rng.chance(50) ? .held : .nowhere))
            }
            if rng.chance(30) { g.late = { n in n % 7 == 0 ? 0.04 : 0.003 } }
        }
        let windows = landingWindows
        g.landing = { t in windows.first { t >= $0.0 && t < $0.1 }?.2 ?? .lands }
        var judge = Judge(timing: g.timing)
        var physical: [ObjectIdentifier: [UInt16]] = [:]
        var events: [(Double, Int)] = []
        for _ in 0..<(10 + rng.below(30)) { events.append((rng.time(10), rng.below(1000))) }
        events.sort { $0.0 < $1.0 }
        var logged = 0
        var left: Set<ObjectIdentifier> = []
        func judgeNew(_ g: Glue, by device: ObjectIdentifier?) {
            while logged < g.log.count {
                let (t, e) = g.log[logged]
                logged += 1
                if case .repeated(let k, let f) = e {
                    repeatsSeen += 1
                    if strict { strictRepeats += 1 }
                    var why: [String] = []
                    if judge.down[k] != true { why.append("its key is up on the Mac") }
                    if !KeyRepeat.repeats(virtualKey: k) { why.append("the key never repeats") }
                    guard let p = judge.press, p.key == k else {
                        judge.broken.append("t=\(t): a repeat of \(k), not the last key pressed (\(String(describing: judge.press?.key)))"); continue
                    }
                    if let tm = judge.timing, t < p.t + tm.delay - 1e-9 { why.append("before the delay (\(t - p.t) s after its down)") }
                    if let h = g.lastHeard(p.device, at: t), t - h > KeyRepeat.silence + 1e-9 { why.append("its device quiet \(t - h) s") }
                    if g.lastHeard(p.device, at: t) == nil { why.append("its device not heard") }
                    if g.landing(t) != .lands { why.append("input does not land (\(g.landing(t)))") }
                    let want = p.flags | g.keys.heldFlags
                    if f != want { why.append("flags \(names(f)), want \(names(want))") }
                    if let last = judge.lastRepeat, let tm = judge.timing, t - last < tm.interval / 2 - 1e-9 { why.append("\(t - last) s after the last") }
                    if strict, let tm = judge.timing {
                        let n = ((t - p.t - tm.delay) / tm.interval).rounded()
                        if abs(t - (p.t + tm.delay + n * tm.interval)) > 1e-6 { why.append("off its cadence") }
                        if let last = judge.lastRepeat, abs(t - last - tm.interval) > 1e-6 { why.append("a repeat missed (\(t - last) s after the last)") }
                        else if judge.lastRepeat == nil, abs(t - p.t - tm.delay) > 1e-6 { why.append("the first repeat late (\(t - p.t) s)") }
                    }
                    judge.lastRepeat = t
                    if !why.isEmpty { judge.broken.append("t=\(String(format: "%.4f", t)): a repeat of \(k): " + why.joined(separator: ", ")) }
                } else {
                    judge.posted(e, at: t, by: device, heldFlags: g.keys.heldFlags)
                }
            }
        }
        for (t, roll) in events {
            g.run(to: t)
            judgeNew(g, by: nil)
            let live = conns.filter { !left.contains(ObjectIdentifier($0)) }
            guard let c = live.isEmpty ? nil : live[roll % live.count] else { break }
            let d = ObjectIdentifier(c)
            switch roll % 13 {
            case 0, 1, 2, 3, 4:
                let u = rng.pick(usages)
                let m = rng.chance(20) ? rng.pick([command, option, shift, control, 1 << 16]) : 0
                g.at(t) { $0.input(key(u, true, m), from: c) }
                if physical[d]?.contains(u) != true { physical[d, default: []].append(u) }
            case 5, 6, 7:
                if let keys = physical[d], !keys.isEmpty {
                    let u = keys[rng.below(keys.count)]
                    g.at(t) { $0.input(key(u, false, 0), from: c) }
                    physical[d]?.removeAll { $0 == u }
                }
            case 8: if !strict { g.at(t) { $0.input(.text("x"), from: c) } }
            case 9: if !strict { g.at(t) { $0.chord() } }
            case 10: if !strict && rng.chance(30) { g.at(t) { $0.leave(c) }; left.insert(d) }
            case 11: if !strict { g.silence(c, from: t); g.resume(c, at: t + rng.time(1.5)) }
            default: if !strict && rng.chance(20) { g.at(t) { $0.dropped() } }
            }
            judgeNew(g, by: d)
        }
        g.run(to: 11)
        judgeNew(g, by: nil)
        g.hostEnds()
        g.run(to: 13)
        judgeNew(g, by: nil)
        let afterEnd = g.log.filter { $0.t > 11 + 1e-9 }.contains { if case .repeated = $0.e { return true }; return false }
        if afterEnd { judge.broken.append("a repeat after the host ended") }
        // Liveness in the strict sessions: a press still the last one, held past its delay with the
        // device heard and input landing, got every repeat (checked at each repeat above), and the
        // first: a press that is still on at 11 s and was made by 10 s has repeated.
        if strict, let p = judge.press, judge.down[p.key] == true, p.t + thisMac.delay < 10.9, judge.lastRepeat == nil {
            judge.broken.append("a press at \(p.t) s held to the end never repeated")
        }
        if strict { strictSessions += 1 }
        if !judge.broken.isEmpty {
            brokenSessions += 1
            if brokenSessions <= 4 { print("FAIL: session \(run): " + judge.broken.prefix(3).joined(separator: "; ")) }
        }
        sessions += 1
    }
    check(brokenSessions == 0, "random sessions: \(brokenSessions) of \(sessions) broke an invariant")
    check(strictRepeats > 5000 && repeatsSeen > strictRepeats + 2000, "the sessions repeat: \(strictRepeats) strict, \(repeatsSeen) in all")
    print("random: \(sessions) sessions (\(strictSessions) with nothing in the way), \(repeatsSeen) repeats")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
