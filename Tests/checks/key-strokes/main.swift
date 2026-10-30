import Foundation

// The Mac's modifier keys after a device's keys (CLAUDE.md, "The stuck command after Spotlight"):
// KeyStrokes (Sources/SillHost), the keyboard events InputInjector posts for a device's keys, put
// through a model of InputInjector's glue and of the Mac's HID state table.
//
// The model KeyStrokes is written against (inferred: nothing may be posted while this is built): the
// table holds the flags of the last keyboard event posted, a key's down or up or a modifier key's
// flags-changed, and every pointer or scroll event InputInjector makes from its source starts from
// them. Typed text goes out with no flags, a character's down and up. On 2026-09-23 the text typed
// after the Spotlight key inherited its command that way (InputInjector.type sets none since).
//
// The invariant: after every event, whatever shift, control, option or command the table holds is
// accounted for by a key down on the Mac, a modifier's own key or a key whose down carried it (a
// chord still under way), and so is every pointer event's. With nothing down, none is set.
//
// The inference has a tripwire, the check a quarter of a second after each key's up (KeyUpCheck): on
// a Mac that keeps its table through some ups (a modifier key's own, or any other key's), every
// modifier such an up leaves set that no key down accounts for is reported by the read after it, and
// on a Mac as the model says none ever is. And input with nowhere to land (DroppedInput) is dropped
// but for the up of a key or a button the Mac has down, so neither stays down there.
//
// Compiled with Sources/StreamProtocol and Sources/SillHost/KeyStrokes.swift as one module
// (-package-name sill), as build.sh does.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

let command = KeyStrokes.command, shift = KeyStrokes.shift, control = KeyStrokes.control
let option = KeyStrokes.option, capsLock = KeyStrokes.capsLock
/// The four that change a click or a scroll while they are set.
let modifierBits: UInt64 = shift | control | option | command
/// fn (CGEventFlags' maskSecondaryFn), which only a gesture's shortcut carries (GestureChords): held
/// to the same rule.
let fn: UInt64 = 0x80_0000

/// The Mac's modifier keycodes (Carbon kVK_*) and the flag each holds: the model's own table.
let macModifiers: [UInt16: UInt64] = [55: command, 54: command, 56: shift, 60: shift,
                                      58: option, 61: option, 59: control, 62: control]

func names(_ flags: UInt64) -> String {
    let named: [(UInt64, String)] = [(capsLock, "caps lock"), (control, "control"), (option, "option"),
                                     (shift, "shift"), (command, "command"), (fn, "fn")]
    var held = named.filter { flags & $0.0 != 0 }.map(\.1)
    let rest = flags & ~(capsLock | modifierBits | fn)
    if rest != 0 { held.append("0x" + String(rest, radix: 16)) }
    return held.isEmpty ? "none" : held.joined(separator: " + ")
}

/// A device's connection: its ObjectIdentifier is the device KeyStrokes keeps keys for.
final class Conn {}

// HID usages the device sends, and the Mac's keycodes for them.
let uSpace: UInt16 = 0x2C, uEsc: UInt16 = 0x29, uS: UInt16 = 0x16, uC: UInt16 = 0x06
let uLeft: UInt16 = 0x50, uRight: UInt16 = 0x4F, uReturn: UInt16 = 0x28
let uA: UInt16 = 0x04, uE: UInt16 = 0x08, uP: UInt16 = 0x13, uZ: UInt16 = 0x1D, u1: UInt16 = 0x1E, u0: UInt16 = 0x27
let uDelete: UInt16 = 0x2A, uTab: UInt16 = 0x2B, uMinus: UInt16 = 0x2D, uSlash: UInt16 = 0x38, uCapsLock: UInt16 = 0x39
let uLCtrl: UInt16 = 0xE0, uLShift: UInt16 = 0xE1, uLOpt: UInt16 = 0xE2, uLCmd: UInt16 = 0xE3
let uRCtrl: UInt16 = 0xE4, uRShift: UInt16 = 0xE5, uROpt: UInt16 = 0xE6, uRCmd: UInt16 = 0xE7
let kSpace: UInt16 = 49, kEsc: UInt16 = 53, kS: UInt16 = 1, kC: UInt16 = 8, kLeft: UInt16 = 123, kRight: UInt16 = 124
let kCmd: UInt16 = 55, kRCmd: UInt16 = 54, kShift: UInt16 = 56, kOpt: UInt16 = 58, kCtrl: UInt16 = 59

func key(_ usage: UInt16, _ down: Bool, _ modifiers: UInt64 = 0) -> InputEvent {
    .key(hidUsage: usage, down: down, modifiers: modifiers)
}
/// A shortcut as every device before this fix sends it, and a test client does: one key down and up,
/// both carrying the modifiers (the Spotlight key's ⌘Space, the key row's ⌘esc, a latched ⌘S).
func bare(_ usage: UInt16, _ modifiers: UInt64) -> [InputEvent] { [key(usage, true, modifiers), key(usage, false, modifiers)] }
let tap: [InputEvent] = [.pointer(.move, x: 0.5, y: 0.5), .pointer(.leftDown, x: 0.5, y: 0.5), .pointer(.leftUp, x: 0.5, y: 0.5)]
let scroll: InputEvent = .scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1)
/// The modifier keys in the order the trackpad presses them (KeyModifiers.keys): control, shift,
/// option, command; and the flag of each.
let pressOrder: [(UInt16, UInt64)] = [(uLCtrl, control), (uLShift, shift), (uLOpt, option), (uLCmd, command)]
/// What the portrait trackpad sends around a modified click (TrackpadSurface.pressModifiers and
/// releaseModifiers): each modifier's key down with the flags so far, the click, then the keys up in
/// reverse with the flags left.
func aroundClick(_ modifiers: UInt64) -> [InputEvent] {
    let keys = pressOrder.filter { modifiers & $0.1 != 0 }
    var held: UInt64 = 0, out: [InputEvent] = []
    for (u, f) in keys { held |= f; out.append(key(u, true, held)) }
    out += [.pointer(.leftDown, x: 0.5, y: 0.5), .pointer(.leftUp, x: 0.5, y: 0.5)]
    for (u, f) in keys.reversed() { held &= ~f; out.append(key(u, false, held)) }
    return out
}

/// InputInjector's glue as the model has it, and the Mac's side.
struct Mac {
    enum Event: Equatable, CustomStringConvertible {
        case key(UInt16, Bool, UInt64)   // a virtual key down or up, and the flags it carries
        case text                        // a typed character: its down and up, with no flags
        case pointer(UInt64)             // a pointer or scroll event, and the flags it starts from
        var description: String {
            switch self {
            case .key(let k, let d, let f): return "key \(k) \(d ? "down" : "up") (\(names(f)))"
            case .text: return "text"
            case .pointer(let f): return "pointer (\(names(f)))"
            }
        }
    }
    var keys = KeyStrokes()
    /// The HID state table's flags: the last keyboard event's.
    var table: UInt64 = 0
    /// Keycodes whose down was posted and whose up has not been, with the flags the down carried.
    var down: [UInt16: UInt64] = [:]
    var log: [Event] = []
    var broken: [String] = []

    /// The check after each key's up (KeyUpCheck), as InputInjector runs it: every up that should take
    /// modifiers out of the table, until `read`, and a gesture's shortcut, checked its own way (#38's
    /// checkModifiersLeft: the chord's modifiers not set before it).
    var upCheck = KeyUpCheck()
    var armed: [(key: UInt16, id: Int, cleared: UInt64)] = []
    var gestureArmed: [UInt64] = []
    /// The table as the Mac holds it: what this host's events left (`real`: `table`, unless the Mac
    /// ignores some ups, `ignore`) with the Mac's own keyboard (`own`) on top.
    enum Ignore { case nothing, modifierUps, keyUps }
    var ignore = Ignore.nothing
    var real: UInt64 = 0
    var own: UInt64 = 0
    var macTable: UInt64 { real | own }

    /// The modifiers the keys down on the Mac account for: a modifier key its own flag, any other key
    /// the flags its down carried.
    var accounted: UInt64 { down.reduce(0) { $0 | (macModifiers[$1.key] ?? $1.value) } }

    /// One keyboard event posted; `checked`, as every device key's is (a gesture's are not).
    mutating func post(_ s: KeyStroke, checked: Bool = true) {
        if checked, let check = upCheck.posting(s, table: macTable, posted: table) { armed.append((s.virtualKey, check.id, check.cleared)) }
        log.append(.key(s.virtualKey, s.down, s.flags))
        table = s.flags
        if !ignores(s) { real = s.flags }
        if s.down { down[s.virtualKey] = s.flags } else { down[s.virtualKey] = nil }
        judge("after \(log.last!)")
    }
    func ignores(_ s: KeyStroke) -> Bool {
        switch ignore {
        case .nothing: return false
        case .modifierUps: return !s.down && macModifiers[s.virtualKey] != nil
        case .keyUps: return !s.down && macModifiers[s.virtualKey] == nil
        }
    }
    /// The checks armed so far, read now (as a quarter of a second after the last of them, with no key
    /// posted since): what each reports, keycode and modifiers (a gesture's as key 0); then none is armed.
    mutating func read() -> [(key: UInt16, left: UInt64)] {
        let keysLeft = armed.compactMap { a -> (key: UInt16, left: UInt64)? in
            let left = upCheck.read(a.id, table: macTable, posted: table, held: keys.heldFlags)
            return left == 0 ? nil : (a.key, left)
        }
        let gesturesLeft = gestureArmed.compactMap { carried -> (key: UInt16, left: UInt64)? in
            macTable & carried == 0 ? nil : (0, macTable & carried)
        }
        armed = []; gestureArmed = []
        return keysLeft + gesturesLeft
    }
    mutating func judge(_ when: String) {
        let stray = table & (modifierBits | fn) & ~accounted
        if stray != 0 {
            broken.append("\(when): the table holds \(names(stray)) with " + (down.isEmpty ? "nothing" : down.keys.sorted().map(String.init).joined(separator: ", ")) + " down")
        }
    }
    mutating func input(_ e: InputEvent, from c: Conn) {
        let d = ObjectIdentifier(c)
        switch e {
        case .key(let usage, let isDown, let modifiers):
            for s in keys.key(usage: usage, down: isDown, modifiers: modifiers, from: d) ?? [] { post(s) }
        case .text(let string):
            for s in keys.text(from: d) { post(s) }
            for _ in string { log.append(.text); table = 0; real = 0 }   // a character's down, with no flags
            judge("after text")
        case .pointer, .scroll, .scrollGesture, .magnify:
            log.append(.pointer(table))
            let stray = table & (modifierBits | fn) & ~accounted
            if stray != 0 { broken.append("a pointer event carries \(names(stray)), which no key down accounts for") }
        }
    }
    mutating func send(_ events: [InputEvent], from c: Conn) { for e in events { input(e, from: c) } }
    mutating func leave(_ c: Conn) { for s in keys.release(ObjectIdentifier(c)) { post(s) } }
    /// A trackpad gesture's shortcut (InputInjector.chord): the table read just before it, and its
    /// own check after it.
    mutating func gesture(_ keyCode: UInt16, _ flags: UInt64) {
        let before = macTable
        for s in KeyStrokes.chord(virtualKey: keyCode, flags: flags, before: before) { post(s, checked: false) }
        if flags & (modifierBits | fn) & ~before != 0 { gestureArmed.append(flags & (modifierBits | fn) & ~before) }
    }
    /// Everything posted since `from`.
    func since(_ from: Int) -> [Event] { Array(log[from...]) }
}

func expect(_ got: [Mac.Event], _ want: [Mac.Event], _ what: String, line: Int = #line) {
    check(got == want, "\(what): posted \(got), expected \(want)", line: line)
}
func clean(_ mac: Mac, _ what: String, line: Int = #line) {
    check(mac.broken.isEmpty, "\(what): " + mac.broken.joined(separator: "; "), line: line)
}

// MARK: Units

check(KeyStrokes.flags(fromDevice: 0) == 0, "no modifiers: no flags")
check(KeyStrokes.flags(fromDevice: 1 << 16) == capsLock && KeyStrokes.flags(fromDevice: 1 << 17) == shift
      && KeyStrokes.flags(fromDevice: 1 << 18) == control && KeyStrokes.flags(fromDevice: 1 << 19) == option
      && KeyStrokes.flags(fromDevice: 1 << 20) == command, "each device bit is the same CGEventFlags bit")
check(KeyStrokes.flags(fromDevice: (1 << 21) | (1 << 24) | 0xFFFF | (1 << 23)) == 0,
      "the numeric pad, iOS-only and low bits never reach the Mac")
check(KeyStrokes.flags(fromDevice: 0x1F_0000 | (1 << 21)) == capsLock | modifierBits, "all five, nothing else")
check(command == 0x10_0000 && shift == 0x02_0000 && control == 0x04_0000 && option == 0x08_0000 && capsLock == 0x01_0000,
      "CGEventFlags' masks")
check(KeyStrokes.virtualKeys.count == 82, "82 keys a device can send, as before (got \(KeyStrokes.virtualKeys.count))")
let modifierKeycodes: [(UInt16, UInt16)] = [(uLCtrl, 59), (uLShift, 56), (uLOpt, 58), (uLCmd, 55), (uRCtrl, 62), (uRShift, 60), (uROpt, 61), (uRCmd, 54)]
check(modifierKeycodes.allSatisfy { KeyStrokes.virtualKeys[$0.0] == $0.1 }, "the eight modifier keys' keycodes")
check(KeyStrokes.virtualKeys[uSpace] == kSpace && KeyStrokes.virtualKeys[uEsc] == kEsc && KeyStrokes.virtualKeys[0x04] == 0
      && KeyStrokes.virtualKeys[uS] == kS && KeyStrokes.virtualKeys[uC] == kC && KeyStrokes.virtualKeys[uLeft] == kLeft
      && KeyStrokes.virtualKeys[uRight] == kRight && KeyStrokes.virtualKeys[0x27] == 29 && KeyStrokes.virtualKeys[0x45] == 111,
      "space, escape, letters, arrows, digits and F12 as before")
check(KeyStrokes.virtualKeys[0x32] == nil && KeyStrokes.virtualKeys[0x68] == nil, "0x32 (non-US #) and F13 are not keys a device sends")
let modifierFlags: [(UInt16, UInt64)] = [(uLCtrl, control), (uLShift, shift), (uLOpt, option), (uLCmd, command),
                                         (uRCtrl, control), (uRShift, shift), (uROpt, option), (uRCmd, command)]
check(KeyStrokes.modifierKeys.count == 8 && modifierFlags.allSatisfy { KeyStrokes.modifierKeys[$0.0] == $0.1 },
      "the eight modifier keys and the flag each holds")
check(Set(KeyStrokes.virtualKeys.values).count == KeyStrokes.virtualKeys.count, "no two keys share a keycode")
check(KeyStrokes.names(0) == "none" && KeyStrokes.names(command) == "command"
      && KeyStrokes.names(command | shift | control) == "control + shift + command"
      && KeyStrokes.names(capsLock | option) == "caps lock + option", "the flags' names, in the Mac's order")

// MARK: A shortcut sent as one key down and up (every device before this fix, and test clients)

// The Spotlight key: ⌘Space. The down carries command, which opens Spotlight; the up leaves nothing
// held, so the next tap is a plain click (it was a ⌘-click until something was typed).
do {
    var mac = Mac(); let a = Conn()
    mac.send(bare(uSpace, command) + tap, from: a)
    expect(mac.log, [.key(kSpace, true, command), .key(kSpace, false, 0), .pointer(0), .pointer(0), .pointer(0)],
           "the Spotlight key, then a tap")
    check(mac.table == 0 && mac.keys.heldFlags == 0, "nothing held after the Spotlight key")
    clean(mac, "the Spotlight key")
}
// The key row's ⌘esc and a latched ⌘S on the software keyboard, then a scroll.
do {
    var mac = Mac(); let a = Conn()
    mac.send(bare(uEsc, command) + bare(uS, command) + [scroll], from: a)
    expect(mac.log, [.key(kEsc, true, command), .key(kEsc, false, 0), .key(kS, true, command), .key(kS, false, 0), .pointer(0)],
           "⌘esc and ⌘S, then a scroll")
    clean(mac, "⌘esc and ⌘S")
}
// Two modifiers (the key row's ⌃⇧→), and caps lock: the down carries all it was sent with, the up
// none of them (caps lock is no key held down).
do {
    var mac = Mac(); let a = Conn()
    mac.send(bare(uRight, control | shift) + bare(uLeft, capsLock | option) + tap, from: a)
    expect(mac.log, [.key(kRight, true, control | shift), .key(kRight, false, 0),
                     .key(kLeft, true, capsLock | option), .key(kLeft, false, 0),
                     .pointer(0), .pointer(0), .pointer(0)], "⌃⇧→ and ⌥← with caps lock on")
    clean(mac, "⌃⇧→ and ⌥←")
}
// Plain keys are as they were: no flags either way.
do {
    var mac = Mac(); let a = Conn()
    mac.send(bare(uReturn, 0) + bare(uLeft, 0), from: a)
    expect(mac.log, [.key(36, true, 0), .key(36, false, 0), .key(kLeft, true, 0), .key(kLeft, false, 0)], "return and ←")
}
// A key no Mac key answers to posts nothing and changes nothing.
do {
    var mac = Mac(); let a = Conn()
    check(mac.keys.key(usage: 0x68, down: true, modifiers: command, from: ObjectIdentifier(a)) == nil, "F13: no event")
    mac.send([key(0x68, true, command)] + tap, from: a)
    expect(mac.log, [.pointer(0), .pointer(0), .pointer(0)], "F13 with command, then a tap")
    check(!mac.keys.isDown(0x68) && mac.keys.heldFlags == 0, "F13 is not down")
}

// MARK: Modifier keys of their own (the trackpad's modified clicks, hardware keyboards)

// The trackpad's latched ⌘-click: the ⌘ key down (a flags-changed with command), the click, which
// starts from command, then the ⌘ key up with nothing left; the tap after is plain.
do {
    var mac = Mac(); let a = Conn()
    mac.send(aroundClick(command) + tap, from: a)
    expect(mac.log, [.key(kCmd, true, command), .pointer(command), .pointer(command), .key(kCmd, false, 0),
                     .pointer(0), .pointer(0), .pointer(0)], "a latched ⌘-click, then a tap")
    clean(mac, "a latched ⌘-click")
}
// Three held around a click, each key with the flags so far, and each up leaving the rest.
do {
    var mac = Mac(); let a = Conn()
    mac.send(aroundClick(control | shift | command), from: a)
    let all = control | shift | command
    expect(mac.log, [.key(kCtrl, true, control), .key(kShift, true, control | shift), .key(kCmd, true, all),
                     .pointer(all), .pointer(all),
                     .key(kCmd, false, control | shift), .key(kShift, false, control), .key(kCtrl, false, 0)],
           "⌃⇧⌘ around a click")
    clean(mac, "⌃⇧⌘ around a click")
}
// A modifier's up that still carries its own flag (a hardware key's release, as a device may report
// it): posted without it.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uLCmd, false, command)] + tap, from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kCmd, false, 0), .pointer(0), .pointer(0), .pointer(0)],
           "⌘ down and up, the up still saying command")
    clean(mac, "a ⌘ up saying command")
}
// A modifier's down that does not carry its own flag yet (the flags from before the press): posted with it.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLOpt, true, 0)] + tap + [key(uLOpt, false, 0)], from: a)
    expect(mac.log, [.key(kOpt, true, option), .pointer(option), .pointer(option), .pointer(option), .key(kOpt, false, 0)],
           "⌥ down saying nothing, a tap, ⌥ up")
}
// Left and right command: one up leaves the other's command.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uRCmd, true, command), key(uLCmd, false, command)] + tap
             + [key(uRCmd, false, 0)] + tap, from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kRCmd, true, command), .key(kCmd, false, command),
                     .pointer(command), .pointer(command), .pointer(command),
                     .key(kRCmd, false, 0), .pointer(0), .pointer(0), .pointer(0)], "left and right command")
    clean(mac, "left and right command")
}
// The right-hand keys hold their flags as the left do.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uRCtrl, true, control), key(uRShift, true, control | shift), key(uROpt, true, control | shift | option)], from: a)
    check(mac.keys.heldFlags == control | shift | option, "right control, shift and option held: \(names(mac.keys.heldFlags))")
    expect(mac.log, [.key(62, true, control), .key(60, true, control | shift), .key(61, true, control | shift | option)],
           "right control, shift and option down")
    mac.send([key(uROpt, false, control | shift), key(uRShift, false, control), key(uRCtrl, false, 0)], from: a)
    check(mac.table == 0 && mac.keys.heldFlags == 0, "and up")
    clean(mac, "the right-hand modifiers")
}
// A hardware ⌘C from a device that sends the ⌘ key's release: as a keyboard, the C up still with
// command (⌘ is still down), then the ⌘ up with nothing.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command), key(uC, false, command), key(uLCmd, false, 0)] + tap, from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kC, true, command), .key(kC, false, command), .key(kCmd, false, 0),
                     .pointer(0), .pointer(0), .pointer(0)], "a hardware ⌘C, the ⌘ key's release sent")
    clean(mac, "a hardware ⌘C")
}
// ⌘ let go before C: the C up carries nothing.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command), key(uLCmd, false, 0), key(uC, false, 0)], from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kC, true, command), .key(kCmd, false, 0), .key(kC, false, 0)],
           "⌘ let go before C")
    clean(mac, "⌘ let go before C")
}

// MARK: A device's own word on what it holds

// A hardware ⌘C from a device whose ⌘ release never comes (before this fix the device's text path
// took it). ⌘ stays down on the Mac, as the device last said, so a tap is a ⌘-click; the device's
// next text says it holds nothing, and the ⌘ key goes up before the text.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command), key(uC, false, command)] + tap, from: a)
    let n = mac.log.count
    mac.send([.text("x")] + tap, from: a)
    expect(mac.since(n), [.key(kCmd, false, 0), .text, .pointer(0), .pointer(0), .pointer(0)],
           "text after a ⌘ whose release was lost, then a tap")
    clean(mac, "a lost ⌘ release, then text")
}
// Or its next key, sent without command: the ⌘ key goes up first.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command), key(uC, false, command)], from: a)
    let n = mac.log.count
    mac.send(bare(uLeft, 0) + tap, from: a)
    expect(mac.since(n), [.key(kCmd, false, 0), .key(kLeft, true, 0), .key(kLeft, false, 0), .pointer(0), .pointer(0), .pointer(0)],
           "← without command after a lost ⌘ release")
    clean(mac, "a lost ⌘ release, then ←")
}
// A key that still says command keeps it: ⌘ held for two shortcuts in a row.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command)] + bare(uC, command) + bare(uS, command) + [key(uLCmd, false, 0)], from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kC, true, command), .key(kC, false, command),
                     .key(kS, true, command), .key(kS, false, command), .key(kCmd, false, 0)], "⌘ held for ⌘C and ⌘S")
}
// A key sent with option while this device holds control and option: control goes up first, option stays.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCtrl, true, control), key(uLOpt, true, control | option)], from: a)
    let n = mac.log.count
    mac.send(bare(uLeft, option), from: a)
    expect(mac.since(n), [.key(kCtrl, false, option), .key(kLeft, true, option), .key(kLeft, false, option)],
           "⌥← while ⌃ and ⌥ were held")
    check(mac.keys.heldFlags == option, "option still held")
}

// MARK: Leaving

// A device that leaves in the middle of a shortcut: its key goes up, and nothing is left.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uSpace, true, command)], from: a)
    mac.leave(a)
    mac.send(tap, from: b)
    expect(mac.log, [.key(kSpace, true, command), .key(kSpace, false, 0), .pointer(0), .pointer(0), .pointer(0)],
           "a device leaving between ⌘Space's down and up, then another device's tap")
    clean(mac, "a device leaving mid-shortcut")
}
// Holding ⌘ around a drag: its ⌘ key goes up.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command), .pointer(.leftDown, x: 0.5, y: 0.5)], from: a)
    let n = mac.log.count
    mac.leave(a)
    expect(mac.since(n), [.key(kCmd, false, 0)], "a device leaving mid-⌘-drag")
    check(mac.table == 0 && mac.down.isEmpty, "nothing down after it left")
}
// Holding ⌃⇧ and C: C goes up with ⌃⇧ still held, then the modifiers, each leaving the rest.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCtrl, true, control), key(uLShift, true, control | shift), key(uC, true, control | shift)], from: a)
    let n = mac.log.count
    mac.leave(a)
    expect(mac.since(n), [.key(kC, false, control | shift), .key(kShift, false, control), .key(kCtrl, false, 0)],
           "a device leaving while holding ⌃⇧C")
    clean(mac, "a device leaving while holding ⌃⇧C")
    check(mac.keys.release(ObjectIdentifier(a)).isEmpty, "a second release has nothing to let go")
}

// The host going (Quit, a signal it catches): every key down goes up, whoever pressed it, the
// other keys first with what is still held, then the modifiers from the right-hand ⌘ down.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command)], from: a)
    mac.send([key(uLOpt, true, option), key(uEsc, true, option)], from: b)
    let n = mac.log.count
    for s in mac.keys.releaseAll() { mac.post(s) }
    expect(mac.since(n), [.key(kC, false, option | command), .key(kEsc, false, option | command),
                          .key(kCmd, false, option), .key(kOpt, false, 0)], "the host going with ⌘C and ⌥esc down")
    check(mac.table == 0 && mac.down.isEmpty && mac.keys.heldFlags == 0, "nothing down after it")
    check(mac.keys.releaseAll().isEmpty, "a second time: nothing")
    clean(mac, "the host going")
}
// A device's text with two modifier keys it never let go: ⌘ goes up first, then ⌃.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCtrl, true, control), key(uLCmd, true, control | command)], from: a)
    let n = mac.log.count
    mac.send([.text("x")], from: a)
    expect(mac.since(n), [.key(kCmd, false, control), .key(kCtrl, false, 0), .text], "text with ⌃ and ⌘ still down")
}

// MARK: Two devices

// One device holds ⌘ (a ⌘-drag on its trackpad) while another sends ⌘Space: the up leaves the first
// device's ⌘, which its drag still needs, and its own ⌘ up then leaves nothing.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.send(bare(uSpace, command), from: b)
    mac.send([.pointer(.move, x: 0.4, y: 0.4)], from: a)
    mac.send([key(uLCmd, false, 0)], from: a)
    mac.send(tap, from: b)
    expect(mac.log, [.key(kCmd, true, command), .key(kSpace, true, command), .key(kSpace, false, command), .pointer(command),
                     .key(kCmd, false, 0), .pointer(0), .pointer(0), .pointer(0)], "⌘Space from B while A holds ⌘")
    clean(mac, "two devices, one holding ⌘")
}
// A key's down carries what another device holds, as a Mac does with two keyboards.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLOpt, true, option)], from: a)
    mac.send(bare(uEsc, 0), from: b)
    expect(mac.log, [.key(kOpt, true, option), .key(kEsc, true, option), .key(kEsc, false, option)], "esc from B while A holds ⌥")
}
// One device's text, its keys sent without a modifier and its leaving let go of nothing another holds.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.send([.text("x")] + bare(uLeft, 0), from: b)
    mac.leave(b)
    check(mac.keys.heldFlags == command && mac.down[kCmd] != nil, "A's ⌘ still down after B's text, key and leaving")
    let n = mac.log.count
    mac.send([.text("y")], from: a)
    expect(mac.since(n), [.key(kCmd, false, 0), .text], "then A's own text lets it go")
}
// A key another device holds down stays down when this one leaves.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command)], from: a)
    mac.send([key(uEsc, true, 0)], from: b)
    let n = mac.log.count
    mac.leave(b)
    expect(mac.since(n), [.key(kEsc, false, command)], "B leaving while A holds ⌘C: only B's escape goes up")
    check(mac.keys.isDown(uC) && mac.keys.isDown(uLCmd), "A's C and ⌘ still down")
}
// Both press ⌘; the first to leave leaves the other's.
do {
    var mac = Mac(); let a = Conn(), b = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.send([key(uLCmd, true, command)], from: b)
    mac.leave(a)
    check(mac.keys.heldFlags == command && mac.keys.isDown(uLCmd), "B's ⌘ outlives A")
    mac.leave(b)
    check(mac.table == 0 && mac.keys.heldFlags == 0 && !mac.keys.isDown(uLCmd), "and goes with B")
    clean(mac, "both pressing ⌘")
}
// A move: the session's next connection sends the ⌘ key's release; it goes up, and the old
// connection's leaving has nothing left to let go.
do {
    var mac = Mac(); let a = Conn(), a2 = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.send([key(uLCmd, false, 0)], from: a2)
    mac.leave(a)
    expect(mac.log, [.key(kCmd, true, command), .key(kCmd, false, 0)], "⌘ down on one connection, up on the next")
}
// A key's up on the next connection, then the old one leaving: the key is up, nothing more goes out.
do {
    var mac = Mac(); let a = Conn(), a2 = Conn()
    mac.send([key(uLCmd, true, command), key(uC, true, command)], from: a)
    mac.send([key(uC, false, command), key(uLCmd, false, 0)], from: a2)
    check(!mac.keys.isDown(uC) && !mac.keys.isDown(uLCmd), "C and ⌘ are up")
    let n = mac.log.count
    mac.leave(a)
    expect(mac.since(n), [], "the old connection leaving after its keys came up on the new one")
}
// The old connection leaving first lets go of its ⌘; the next one's release then posts an up with nothing.
do {
    var mac = Mac(); let a = Conn(), a2 = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.leave(a)
    mac.send([key(uLCmd, false, 0)] + tap, from: a2)
    expect(mac.log, [.key(kCmd, true, command), .key(kCmd, false, 0), .key(kCmd, false, 0), .pointer(0), .pointer(0), .pointer(0)],
           "⌘ let go by the old connection's leaving, then released by the new one")
    clean(mac, "a move")
}

// MARK: A trackpad gesture's shortcut (GestureChords, InputInjector.chord)

// Mission Control (the Mission Control key, fn): down with exactly its own flags, up with what the
// table held before it, nothing; the tap after is plain.
do {
    check(KeyStrokes.chord(virtualKey: 160, flags: fn, before: 0) == [KeyStroke(virtualKey: 160, down: true, flags: fn),
                                                                      KeyStroke(virtualKey: 160, down: false, flags: 0)],
          "the Mission Control key: down with fn, up with nothing")
    var mac = Mac(); let a = Conn()
    mac.gesture(160, fn)
    mac.send(tap, from: a)
    expect(mac.log, [.key(160, true, fn), .key(160, false, 0), .pointer(0), .pointer(0), .pointer(0)], "Mission Control, then a tap")
    clean(mac, "Mission Control")
}
// The Space on the right (⌃→ with fn) while a device holds ⌘: the shortcut exactly (no command: that
// would be another), and its up puts command back.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.gesture(124, control | fn)
    mac.send(tap, from: a)
    expect(mac.log, [.key(kCmd, true, command), .key(kRight, true, control | fn), .key(kRight, false, command),
                     .pointer(command), .pointer(command), .pointer(command)], "⌃→ while a device holds ⌘")
    clean(mac, "⌃→ while ⌘ is held")
}
// Between an older device's ⌘Space down and up: the gesture's up leaves command for the Space still
// down, and the Space's up then clears it.
do {
    var mac = Mac(); let a = Conn()
    mac.send([key(uSpace, true, command)], from: a)
    mac.gesture(103, fn)
    mac.send([key(uSpace, false, command)] + tap, from: a)
    expect(mac.log, [.key(kSpace, true, command), .key(103, true, fn), .key(103, false, command), .key(kSpace, false, 0),
                     .pointer(0), .pointer(0), .pointer(0)], "Show Desktop (F11) inside ⌘Space")
    clean(mac, "a gesture inside a shortcut")
}

// MARK: What is down

do {
    var keys = KeyStrokes(); let a = ObjectIdentifier(Conn())
    _ = keys.key(usage: uSpace, down: true, modifiers: command, from: a)
    check(keys.isDown(uSpace) && !keys.isDown(uEsc), "Space is down, escape is not")
    _ = keys.key(usage: uSpace, down: false, modifiers: command, from: a)
    check(!keys.isDown(uSpace), "Space is up")
    _ = keys.key(usage: uRCmd, down: true, modifiers: command, from: a)
    check(keys.isDown(uRCmd) && keys.heldFlags == command, "right ⌘ is down and holds command")
    _ = keys.key(usage: uRCmd, down: false, modifiers: 0, from: a)
    check(!keys.isDown(uRCmd) && keys.heldFlags == 0, "right ⌘ is up")
}

// MARK: The check after a key's up (KeyUpCheck, InputInjector.checkKeyModifiersLeft)
//
// A quarter of a second after an up whose down put a modifier in the table, the table is read again.
// The review found none armed for anything this device sends: its shortcut's key comes up while the
// modifier's own key is still down (so that up keeps ⌘), and a modifier key's own up was never
// checked. Every key's up is judged now, whichever path made it.

/// `events` from one device on a Mac that ignores `ignoring`, with the Mac's own keyboard holding
/// `own`: each check armed ("keycode: modifiers"), and each report, read right after the event that
/// armed it.
func upChecks(_ events: [InputEvent], ignoring: Mac.Ignore = .nothing, own: UInt64 = 0) -> (armed: [String], reported: [String]) {
    var mac = Mac(); mac.ignore = ignoring; mac.own = own
    let a = Conn()
    var armed: [String] = [], reported: [String] = []
    for e in events {
        mac.input(e, from: a)
        armed += mac.armed.map { "\($0.key): \(names($0.cleared))" }
        reported += mac.read().map { "\($0.key): \(names($0.left))" }
    }
    return (armed, reported)
}
/// The same for the check's report: on a Mac as the model says, nothing; on a Mac ignoring `ups`,
/// `want`.
func tripwire(_ events: [InputEvent], _ want: [String], ignoring ups: Mac.Ignore, _ what: String, line: Int = #line) {
    let fine = upChecks(events), bad = upChecks(events, ignoring: ups)
    check(fine.armed == want && fine.reported.isEmpty, "\(what): armed \(fine.armed), reported \(fine.reported) on a Mac as the model says; expected \(want) armed", line: line)
    check(bad.reported == want, "\(what) on a Mac ignoring \(ups): reported \(bad.reported), expected \(want)", line: line)
}

// This device's Spotlight key: ⌘'s key up is checked for command (Space's up keeps it: ⌘ is down).
tripwire(KeyChord.spotlight, ["55: command"], ignoring: .modifierUps, "this device's Spotlight key")
// The clipboard's ⌘V (paste right away): the same, V's up keeping command while ⌘ is down.
tripwire(KeyChord.paste, ["55: command"], ignoring: .modifierUps, "Paste right away's ⌘V")
// The key row's ⌘esc, a latched ⌘S on the software keyboard, and ⌃⇧→: each modifier key's up.
tripwire(KeyChord.press(uEsc, with: .command), ["55: command"], ignoring: .modifierUps, "the key row's ⌘esc")
tripwire(KeyChord.press(uS, with: .command), ["55: command"], ignoring: .modifierUps, "a latched ⌘S")
tripwire(KeyChord.press(uRight, with: [.control, .shift]), ["56: shift", "59: control"], ignoring: .modifierUps, "⌃⇧→")
// The trackpad's ⌘-click, and a drag that ends.
tripwire(aroundClick(command), ["55: command"], ignoring: .modifierUps, "the trackpad's ⌘-click")
tripwire(KeyChord.modifiersDown(.option) + [.pointer(.leftDown, x: 0.2, y: 0.2), .pointer(.move, x: 0.3, y: 0.3), .pointer(.leftUp, x: 0.3, y: 0.3)]
         + KeyChord.modifiersUp(.option), ["58: option"], ignoring: .modifierUps, "the trackpad's ⌥-drag")
// A hardware ⌘C (ForwardedKeys): C's up keeps command, ⌘'s up is checked.
do {
    var kb = Keyboard()
    tripwire(kb.press(uLCmd) + kb.press(uC) + kb.release(uC) + kb.release(uLCmd), ["55: command"], ignoring: .modifierUps, "a hardware ⌘C")
}
// An older device's shortcut, one key down and up: the key's up is checked, for what it carried
// (caps lock is no modifier a click or a scroll starts from).
tripwire(bare(uSpace, command), ["49: command"], ignoring: .keyUps, "an older device's Spotlight key")
tripwire(bare(uLeft, capsLock | option), ["123: option"], ignoring: .keyUps, "an older device's ⌥← with caps lock on")
// The ups KeyStrokes makes itself: a lost ⌘ release let go before text (whose characters, with no
// flags, then put the table back on any Mac), and a device that leaves.
for ignoring in [Mac.Ignore.nothing, .modifierUps] {
    let lost = upChecks([key(uLCmd, true, command), key(uC, true, command), key(uC, false, command), .text("x")], ignoring: ignoring)
    check(lost.armed == ["55: command"] && lost.reported.isEmpty, "a lost ⌘ release, then text, on a Mac ignoring \(ignoring): \(lost)")
}
do {
    for ignoring in [Mac.Ignore.nothing, .modifierUps] {
        var mac = Mac(); mac.ignore = ignoring; let a = Conn()
        mac.send([key(uLCtrl, true, control), key(uLCmd, true, control | command), .pointer(.leftDown, x: 0.5, y: 0.5)], from: a)
        mac.leave(a)
        let armed = mac.armed.map { "\($0.key): \(names($0.cleared))" }, reported = mac.read().map { "\($0.key): \(names($0.left))" }
        check(armed == ["55: command", "59: control"] && reported == (ignoring == .nothing ? [] : ["55: command", "59: control"]),
              "a device leaving mid-⌃⌘-drag on a Mac ignoring \(ignoring): armed \(armed), reported \(reported)")
    }
}
// Nothing to check: plain keys, and a key's up while its modifier's key is still down.
check(upChecks(bare(uReturn, 0) + bare(uLeft, 0) + [.text("ab")] + tap).armed.isEmpty, "plain keys and text arm nothing")
check(upChecks([key(uLCmd, true, command)] + bare(uC, command) + bare(uS, command)).armed.isEmpty, "⌘ held for ⌘C and ⌘S: nothing yet")
// The Mac's own ⌘ held since before the Spotlight key: its up leaves it, and no check says otherwise;
// also once an earlier check for command has been read (a read check is done with).
do {
    let own = upChecks(KeyChord.spotlight + bare(uSpace, command), own: command)
    check(own.armed.isEmpty && own.reported.isEmpty, "the Mac's own ⌘ held: armed \(own.armed), reported \(own.reported)")
    var mac = Mac(); let a = Conn()
    mac.send(KeyChord.spotlight, from: a)
    let first = mac.read()
    mac.own = command
    mac.send(KeyChord.spotlight, from: a)
    check(first.isEmpty && mac.armed.isEmpty && mac.read().isEmpty, "the Mac's own ⌘ pressed after a check was read: armed \(mac.armed)")
}
// A down while a check is unread finds its modifiers in the table: on a Mac that left them, they are
// no keyboard's, and the down's own up is checked for them. (⌃⇧ let go around a drag, and the right
// ⌃ pressed before the read: the drag's ups are read with ⌃ held again, then ⌃'s up alone.)
do {
    var mac = Mac(); mac.ignore = .modifierUps; let a = Conn()
    mac.send([key(uLCtrl, true, control), key(uLShift, true, control | shift), .pointer(.leftDown, x: 0.5, y: 0.5),
              .pointer(.leftUp, x: 0.5, y: 0.5), key(uLShift, false, control), key(uLCtrl, false, 0), key(uRCtrl, true, control)], from: a)
    let masked = mac.read()
    mac.send([key(uRCtrl, false, 0)], from: a)
    check(masked.isEmpty && mac.read().map { "\($0.key): \(names($0.left))" } == ["62: control"],
          "an up left control while right ⌃ went down before the read: its up reports it")
}
// Left and right ⌘: only the last up takes command out.
check(upChecks([key(uLCmd, true, command), key(uRCmd, true, command), key(uLCmd, false, command), key(uRCmd, false, 0)]).armed == ["54: command"],
      "left then right ⌘ up: \(upChecks([key(uLCmd, true, command), key(uRCmd, true, command), key(uLCmd, false, command), key(uRCmd, false, 0)]).armed)")
// Each down is checked once: a second up of the same key (a move's next connection releasing what the
// old one's leaving let go) arms nothing more, and a key another device presses after an older
// device left mid-shortcut starts afresh.
do {
    var mac = Mac(); let a = Conn(), a2 = Conn()
    mac.send([key(uLCmd, true, command)], from: a)
    mac.leave(a)
    mac.send([key(uLCmd, false, 0)], from: a2)
    check(mac.armed.map(\.key) == [55], "⌘ let go by a leaving connection, then released on the next: \(mac.armed)")
    var two = Mac(); let b = Conn(), c = Conn()
    two.send([key(uSpace, true, command)], from: b)
    two.leave(b)
    two.send(bare(uSpace, 0), from: c)
    check(two.armed.map { "\($0.key): \(names($0.cleared))" } == ["49: command"], "an older device leaving mid-⌘Space, then a plain Space: \(two.armed)")
}
// A modifier pressed again before the read, or held by another key down: not reported.
check(KeyUpCheck.left(command, table: command, posted: 0, held: 0) == command, "the read: command still set")
check(KeyUpCheck.left(command, table: command, posted: command, held: 0) == 0, "the read: command pressed again since")
check(KeyUpCheck.left(command, table: command, posted: 0, held: command) == 0, "the read: command held by a key down")
check(KeyUpCheck.left(command, table: command | shift, posted: 0, held: 0) == command, "the read: only what the up should have taken out")
check(KeyUpCheck.left(command | option, table: 0, posted: 0, held: 0) == 0, "the read: the table put back")
// A gesture's shortcut is checked its own way (#38), not here.
do {
    var mac = Mac()
    mac.gesture(124, control | fn)
    check(mac.armed.isEmpty, "a gesture arms no key check: \(mac.armed)")
}
// Before the review: only a key sent with a modifier (not a modifier's own key) was remembered at its
// down and judged at its up, with what the up carried. This device's paths armed nothing.
do {
    struct Before {
        var keys = KeyStrokes(); var chords: [UInt16: UInt64] = [:]; var armed = 0
        mutating func send(_ events: [InputEvent], from c: Conn) {
            for e in events {
                guard case .key(let u, let d, let m) = e, let strokes = keys.key(usage: u, down: d, modifiers: m, from: ObjectIdentifier(c)) else { continue }
                let chord = KeyStrokes.flags(fromDevice: m) & modifierBits
                if d, chord != 0, KeyStrokes.modifierKeys[u] == nil { chords[u] = chord }
                if !d, let carried = chords.removeValue(forKey: u), let up = strokes.last, carried & ~up.flags != 0 { armed += 1 }
            }
        }
    }
    var before = Before(); let a = Conn()
    before.send(KeyChord.spotlight + KeyChord.press(uEsc, with: .command) + aroundClick(command), from: a)
    check(before.armed == 0, "the rule before the review arms nothing for this device's keys (\(before.armed))")
    var now = Mac()
    now.send(KeyChord.spotlight + KeyChord.press(uEsc, with: .command) + aroundClick(command), from: a)
    check(now.armed.count == 3, "now each arms one: \(now.armed)")
}

// MARK: Input with nowhere to land (DroppedInput, StreamCoordinator)
//
// Nothing streams (between sources, or the stream stopped: the window closed under a drag), or a
// switch drops what was held for an activation: the coordinator drops the input but for the up of a
// key or a button the Mac has down, which InputInjector posts, a button's where the pointer is. Before
// the review a button's up was dropped there: the Mac's button stayed down, and InputInjector posted
// every later move as a drag.

/// InputInjector's buttons and keys as the coordinator reaches them, the input placed on a source or
/// with nowhere to land.
struct Glue {
    var keys = KeyStrokes()
    var left = false, right = false
    var log: [String] = []
    mutating func input(_ e: InputEvent, placed: Bool, from c: Conn) {
        guard placed || DroppedInput.stillGoes(e, keyDown: keys.isDown, leftDown: left, rightDown: right) else { return }
        let at = placed ? "" : " where the pointer is"
        switch e {
        case .pointer(.move, _, _): log.append(left ? "left drag" : right ? "right drag" : "move")
        case .pointer(.leftDown, _, _): left = true; log.append("left down")
        case .pointer(.leftUp, _, _): left = false; log.append("left up" + at)
        case .pointer(.rightDown, _, _): right = true; log.append("right down")
        case .pointer(.rightUp, _, _): right = false; log.append("right up" + at)
        case .key(let u, let d, let m):
            for s in keys.key(usage: u, down: d, modifiers: m, from: ObjectIdentifier(c)) ?? [] {
                log.append("key \(s.virtualKey) \(s.down ? "down" : "up") (\(names(s.flags)))")
            }
        case .text: log.append("text")
        case .scroll, .scrollGesture, .magnify: log.append("scroll")
        }
    }
    mutating func send(_ events: [InputEvent], placed: Bool, from c: Conn) { for e in events { input(e, placed: placed, from: c) } }
}
let move: InputEvent = .pointer(.move, x: 0.5, y: 0.5)
// A drag whose window closes: the moves with nowhere to land are dropped, the button's up goes where
// the pointer is, and on the next source a move is a move.
do {
    var g = Glue(); let a = Conn()
    g.send([.pointer(.leftDown, x: 0.5, y: 0.5), move], placed: true, from: a)
    g.send([move, .pointer(.leftUp, x: 0.6, y: 0.6)], placed: false, from: a)
    g.send([move], placed: true, from: a)
    check(g.log == ["left down", "left drag", "left up where the pointer is", "move"], "a drag whose window closed: \(g.log)")
}
// The right button alike, and one button's up says nothing of the other's.
do {
    var g = Glue(); let a = Conn()
    g.send([.pointer(.rightDown, x: 0.5, y: 0.5)], placed: true, from: a)
    g.send([.pointer(.leftUp, x: 0.5, y: 0.5), .pointer(.rightUp, x: 0.5, y: 0.5), .pointer(.rightUp, x: 0.5, y: 0.5)], placed: false, from: a)
    g.send([move], placed: true, from: a)
    check(g.log == ["right down", "right up where the pointer is", "move"], "a right drag cut off: \(g.log)")
}
// A switch drops what was held: a click held whole goes nowhere (its down never went), a key's up
// whose down went goes, and downs, moves, scrolls and text never do.
do {
    var g = Glue(); let a = Conn()
    g.send([key(uLCmd, true, command)], placed: true, from: a)
    g.send([.pointer(.leftDown, x: 0.5, y: 0.5), move, .pointer(.leftUp, x: 0.5, y: 0.5), key(uC, true, command), key(uC, false, command),
            key(uLCmd, false, 0), .text("x"), scroll, .scrollGesture(.ended, x: 0.5, y: 0.5), .pointer(.rightDown, x: 0.5, y: 0.5)],
           placed: false, from: a)
    check(g.log == ["key 55 down (command)", "key 55 up (none)"], "a switch's drop: \(g.log)")
    check(!g.left && !g.right && !g.keys.isDown(uLCmd) && !g.keys.isDown(uC), "nothing down after it")
}
// A stray up (nothing down) goes nowhere either.
check(!DroppedInput.stillGoes(.pointer(.leftUp, x: 0, y: 0), keyDown: { _ in false }, leftDown: false, rightDown: true)
      && !DroppedInput.stillGoes(.pointer(.rightUp, x: 0, y: 0), keyDown: { _ in false }, leftDown: true, rightDown: false)
      && !DroppedInput.stillGoes(key(uC, false, 0), keyDown: { _ in false }, leftDown: true, rightDown: true)
      && DroppedInput.stillGoes(key(uC, false, 0), keyDown: { $0 == uC }, leftDown: false, rightDown: false),
      "an up goes only for what is down")
// Random: a device's finger and keys, each event placed or not; whatever it does, once it has let go
// of everything nothing is down on the Mac, and a move while none of its buttons is down is a move.
do {
    var rng = Rng(state: 0x0D_0A7E)
    var bad = 0
    for run in 0..<2000 {
        var g = Glue(); let a = Conn()
        var finger: PointerAction? = nil       // the device's button down (leftDown or rightDown)
        var held: [UInt16] = []                 // the device's keys down
        var problem: String? = nil
        for _ in 0..<(10 + rng.below(40)) {
            let placed = rng.chance(60)
            var e: InputEvent
            switch rng.below(8) {
            case 0, 1:
                if let f = finger { e = .pointer(f == .leftDown ? .leftUp : .rightUp, x: 0.5, y: 0.5); finger = nil }
                else { finger = rng.chance(70) ? .leftDown : .rightDown; e = .pointer(finger!, x: 0.5, y: 0.5) }
            case 2, 3: e = move
            case 4, 5:
                let u = rng.pick([uLCmd, uLShift, uC, uEsc])
                if let i = held.firstIndex(of: u) { held.remove(at: i); e = key(u, false, 0) }
                else { held.append(u); e = key(u, true, u == uLCmd ? command : u == uLShift ? shift : 0) }
            case 6: e = .text("z")
            default: e = scroll
            }
            let n = g.log.count
            g.input(e, placed: placed, from: a)
            if placed, e == move, finger == nil, g.log.count > n, g.log.last != "move", problem == nil {
                problem = "a move with no button down went as \(g.log.last!)"
            }
        }
        // It lets go of everything, each up placed or not.
        if let f = finger { g.input(.pointer(f == .leftDown ? .leftUp : .rightUp, x: 0.5, y: 0.5), placed: rng.chance(50), from: a) }
        for u in held { g.input(key(u, false, 0), placed: rng.chance(50), from: a) }
        if problem == nil, g.left || g.right || !g.keys.down.isEmpty {
            problem = "after it let go: left \(g.left), right \(g.right), keys \(g.keys.down.keys.sorted())"
        }
        if let problem { bad += 1; if bad <= 3 { print("FAIL: nowhere-to-land run \(run): \(problem)") } }
    }
    check(bad == 0, "input with nowhere to land: \(bad) of 2000 runs left something down")
}

// MARK: Random sessions
//
// Two devices sending what devices from before this fix send: shortcuts as one key down and up with
// random modifiers, the trackpad's modified clicks and drags, a hardware keyboard judged again at
// each release (so a modifier's release is lost, or carries its own flag), text, taps and scrolls;
// with connections ending (the device back on a new one) and sessions moving to a new connection
// while the old one lingers. The invariant after every event; at the end, once the host has quit or
// every device has left, nothing down and no modifier set.

/// SplitMix64: the same runs every time.
struct Rng {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    mutating func pick<T>(_ xs: [T]) -> T { xs[below(xs.count)] }
    mutating func modifiers() -> UInt64 {
        var m: UInt64 = 0
        for f in [shift, control, option, command] where chance(35) { m |= f }
        if chance(10) { m |= capsLock }
        return m
    }
}

/// A hardware keyboard on a device from before this fix (InputOverlayView.forward): a key goes to the
/// Mac when it is "raw" at that moment (an arrow, escape, or any key while ⌘, ⌃ or ⌥ is held),
/// judged again at its release. UIKit reports the modifiers held after the change, or, `before`,
/// from before it (a modifier's release then still carries its own flag).
struct OldKeyboard {
    var physical: [UInt16] = []
    var before = false
    static let modifierOf: [UInt16: UInt64] = [0xE0: control, 0xE1: shift, 0xE2: option, 0xE3: command,
                                               0xE4: control, 0xE5: shift, 0xE6: option, 0xE7: command]
    var flags: UInt64 { physical.reduce(0) { $0 | (Self.modifierOf[$1] ?? 0) } }
    static func raw(_ usage: UInt16, _ flags: UInt64) -> Bool {
        flags & (command | control | option) != 0 || [uLeft, uRight, uEsc, 0x51, 0x52, 0x3A].contains(usage)
    }
    mutating func press(_ usage: UInt16) -> [InputEvent] {
        guard !physical.contains(usage) else { return [] }
        let was = flags
        physical.append(usage)
        let now = before ? was : flags
        if Self.raw(usage, now) { return [key(usage, true, now)] }
        return Self.modifierOf[usage] == nil ? [.text("x")] : []   // the text system types it
    }
    mutating func release(_ usage: UInt16) -> [InputEvent] {
        guard let i = physical.firstIndex(of: usage) else { return [] }
        let was = flags
        physical.remove(at: i)
        let now = before ? was : flags
        return Self.raw(usage, now) ? [key(usage, false, now)] : []
    }
}

struct Device {
    var conn = Conn()
    var lingering: [(conn: Conn, steps: Int)] = []   // a moved session's old connections, until they leave
    var keyboard = OldKeyboard()
    var dragMods: UInt64? = nil                      // a modified drag under way on the trackpad
}

/// Gestures' shortcuts as macOS 27 has them (GestureChords.defaults): the Mission Control and
/// Launchpad keys, ⌃ and an arrow with fn, F11, and ⌘ with the Mission Control key.
let gestureShortcuts: [(key: UInt16, flags: UInt64)] = [(160, fn), (126, control | fn), (125, control | fn), (124, control | fn),
                                                        (123, control | fn), (131, fn), (103, fn), (160, command | fn)]
/// The check after each key's up across a session (KeyUpCheck): its reads after every step, and
/// every modifier the Mac's table holds that no key down accounts for must have been reported by
/// then. On a Mac as the model says none is ever reported; on one that keeps its table through
/// some ups, what such an up leaves is.
struct Tripwire {
    var reported: UInt64 = 0
    var missed: String? = nil
    var falseReport: String? = nil
    mutating func step(_ mac: inout Mac, _ when: String) {
        let got = mac.read().reduce(0) { $0 | $1.left }
        if mac.ignore == .nothing, got != 0, falseReport == nil { falseReport = "\(when): \(names(got)) reported on a Mac as the model says" }
        reported |= got
        let stray = mac.macTable & (modifierBits | fn) & ~mac.accounted & ~reported
        if stray != 0, missed == nil { missed = "\(when): the Mac's table holds \(names(stray)), which no key down accounts for and no check reported" }
    }
}

var rng = Rng(state: 0x5111_5EED)
var runs = 0, events = 0, brokenRuns = 0, missedRuns = 0, falseReports = 0
var reportedRuns: [Mac.Ignore: Int] = [:]
let hardwareKeys: [UInt16] = [0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE7, uC, uS, uLeft, uEsc]
// A Mac as the model says (the invariant and no report), then Macs that keep their table through a
// modifier key's up, or through any other key's (every modifier left set reported).
for (ignore, count) in [(Mac.Ignore.nothing, 3000), (.modifierUps, 1000), (.keyUps, 1000)] {
for run in 0..<count {
    var mac = Mac(); mac.ignore = ignore
    var tripwire = Tripwire()
    var devices = [Device(), Device()]
    for i in devices.indices { devices[i].keyboard.before = rng.chance(30) }
    let steps = 20 + rng.below(60)
    for step in 0..<steps {
        let i = rng.below(devices.count)
        var d = devices[i]
        let c = d.conn
        switch rng.below(15) {
        case 0, 1: mac.send(bare(rng.pick([uSpace, uEsc, uS, uLeft, uRight, uReturn]), rng.modifiers()), from: c)
        case 2: mac.send(aroundClick(rng.modifiers() & modifierBits), from: c)
        case 3:
            if let m = d.dragMods {
                mac.send([.pointer(.leftUp, x: 0.3, y: 0.3)], from: c)
                var held = m
                for (u, f) in pressOrder.reversed() where m & f != 0 { held &= ~f; mac.input(key(u, false, held), from: c) }
                d.dragMods = nil
            } else {
                let m = rng.modifiers() & modifierBits
                var held: UInt64 = 0
                for (u, f) in pressOrder where m & f != 0 { held |= f; mac.input(key(u, true, held), from: c) }
                mac.send([.pointer(.leftDown, x: 0.3, y: 0.3)], from: c)
                d.dragMods = m
            }
        case 4, 5, 6: mac.send(d.keyboard.press(rng.pick(hardwareKeys)), from: c)
        case 7, 8, 9:
            if !d.keyboard.physical.isEmpty { mac.send(d.keyboard.release(d.keyboard.physical[rng.below(d.keyboard.physical.count)]), from: c) }
        case 10: mac.send([.text("ab")], from: c)
        case 11: mac.send(tap + [scroll], from: c)
        case 12:
            // The connection ends (Wi-Fi gone, the app in the background): its keys are let go; the
            // device comes back on a new one with nothing held.
            mac.leave(c)
            let lingering = d.lingering
            d = Device(); d.keyboard.before = rng.chance(30); d.lingering = lingering
        case 14 where rng.chance(50):
            // A trackpad gesture: one of the Mac's shortcuts for it (GestureChords.defaults).
            let shortcut = rng.pick(gestureShortcuts)
            mac.gesture(shortcut.key, shortcut.flags)
        case 13:
            // The session moves to a new connection; the old one leaves a few steps later.
            d.lingering.append((d.conn, 1 + rng.below(5)))
            d.conn = Conn()
        default:
            mac.send([.pointer(.move, x: 0.6, y: 0.6)], from: c)
        }
        for j in d.lingering.indices { d.lingering[j].steps -= 1 }
        for old in d.lingering where old.steps <= 0 { mac.leave(old.conn) }
        d.lingering.removeAll { $0.steps <= 0 }
        devices[i] = d
        tripwire.step(&mac, "step \(step)")
    }
    // The session ends: the host quits (its keys all let go first), or every device leaves.
    if rng.chance(30) { for s in mac.keys.releaseAll() { mac.post(s) } }
    for d in devices {
        for old in d.lingering { mac.leave(old.conn) }
        mac.leave(d.conn)
    }
    tripwire.step(&mac, "once every device left")
    // The invariant is the model's Mac's: a gesture's up gives back the table as it read it, which on
    // a Mac keeping it through some ups holds what they left.
    if ignore == .nothing { mac.judge("once every device left") } else { mac.broken = [] }
    if !mac.down.isEmpty { mac.broken.append("once every device left, keys \(mac.down.keys.sorted()) are still down") }
    runs += 1; events += mac.log.count
    if !mac.broken.isEmpty {
        brokenRuns += 1
        if brokenRuns <= 3 { print("FAIL: random run \(run): \(mac.broken.first!) (and \(mac.broken.count - 1) more)") }
    }
    if let missed = tripwire.missed {
        missedRuns += 1
        if missedRuns <= 3 { print("FAIL: random run \(run) on a Mac ignoring \(ignore): \(missed)") }
    }
    if let report = tripwire.falseReport {
        falseReports += 1
        if falseReports <= 3 { print("FAIL: random run \(run): \(report)") }
    }
    if tripwire.reported != 0 { reportedRuns[ignore, default: 0] += 1 }
}
}
check(brokenRuns == 0, "random sessions: \(brokenRuns) of \(runs) broke the invariant")
check(missedRuns == 0, "random sessions on a Mac keeping its table through some ups: \(missedRuns) of 2000 left a modifier set that no check reported")
check(falseReports == 0 && reportedRuns[.nothing] == nil, "random sessions on a Mac as the model says: \(falseReports) reported a modifier")
check((reportedRuns[.modifierUps] ?? 0) > 500 && (reportedRuns[.keyUps] ?? 0) > 500,
      "the Macs keeping their table report in most sessions: \(reportedRuns)")
print("random: \(runs) sessions, \(events) events posted; checks reported in \(reportedRuns[.modifierUps] ?? 0) of 1000 sessions on a Mac ignoring modifier keys' ups and \(reportedRuns[.keyUps] ?? 0) of 1000 ignoring other keys' ups")

// MARK: - The device (iOSClient/KeyChords.swift)
//
// What this device sends: a shortcut with the modifiers' own keys pressed around it, as a keyboard
// does and as the trackpad already did around a modified click, and a hardware key's up whenever
// its down went. Put through this Mac's rule and through the rule of every Mac before this fix (a
// key's flags exactly as the device sent them), which a device must keep working with (CLAUDE.md,
// "Compatibility floor"): on both, nothing is left held.

/// A Mac from before this fix (Sill.app 0.3.x, SillHost before 2026-09-27): each key event carries
/// exactly the device's modifiers; text goes out with none; a device leaving lets go of nothing.
struct OldMac {
    var table: UInt64 = 0
    var down: [UInt16: UInt64] = [:]
    var log: [Mac.Event] = []
    var accounted: UInt64 { down.reduce(0) { $0 | (macModifiers[$1.key] ?? $1.value) } }
    mutating func input(_ e: InputEvent) {
        switch e {
        case .key(let usage, let isDown, let modifiers):
            guard let k = KeyStrokes.virtualKeys[usage] else { return }
            let f = KeyStrokes.flags(fromDevice: modifiers)
            log.append(.key(k, isDown, f)); table = f
            if isDown { down[k] = f } else { down[k] = nil }
        case .text: log.append(.text); table = 0
        case .pointer, .scroll, .scrollGesture, .magnify: log.append(.pointer(table))
        }
    }
    mutating func send(_ events: [InputEvent]) { for e in events { input(e) } }
}

let ksCommand = KeyModifiers.command.rawValue, ksShift = KeyModifiers.shift.rawValue
let ksControl = KeyModifiers.control.rawValue, ksOption = KeyModifiers.option.rawValue
check(ksCommand == command && ksShift == shift && ksControl == control && ksOption == option,
      "the device's modifier bits are the Mac's")

// The Spotlight key: ⌘'s own key down, Space down and up with command, ⌘ up with nothing.
check(KeyChord.spotlight == [key(uLCmd, true, command), key(uSpace, true, command), key(uSpace, false, command), key(uLCmd, false, 0)],
      "the Spotlight key sends \(KeyChord.spotlight)")
// The clipboard's ⌘V after a Paste's receipt (paste right away, docs/clipboard-plan.md): the same shape,
// V for Space; on this Mac command for V alone and nothing held after, nor on a Mac from before
// 2026-09-27 (which posts each key's flags as they come), and ⌘'s up is the one up checked.
do {
    let uV: UInt16 = 0x19, kV: UInt16 = 9
    check(ClipboardPolicy.pasteKey == uV && KeyStrokes.virtualKeys[uV] == kV, "⌘V's key is V, the Mac's virtual key 9")
    check(KeyChord.paste == [key(uLCmd, true, command), key(uV, true, command), key(uV, false, command), key(uLCmd, false, 0)],
          "Paste right away sends \(KeyChord.paste)")
    var mac = Mac(); let a = Conn()
    mac.send(KeyChord.paste + tap, from: a)
    check(Array(mac.log.prefix(4)) == [.key(kCmd, true, command), .key(kV, true, command), .key(kV, false, command), .key(kCmd, false, 0)]
          && mac.log.dropFirst(4).allSatisfy { $0 == .pointer(0) } && mac.table == 0 && mac.down.isEmpty && mac.broken.isEmpty,
          "⌘V on this Mac, then a tap that is no ⌘-click: \(mac.log)")
    var old = OldMac()
    old.send(KeyChord.paste + tap)
    check(old.log.contains(.key(kV, true, command)) && old.table == 0 && old.down.isEmpty && old.log.last == .pointer(0),
          "⌘V on a Mac from before 2026-09-27 leaves nothing: \(old.log)")
}
// A key with nothing latched: the key alone, as before.
check(KeyChord.press(uEsc, with: []) == bare(uEsc, 0), "escape with nothing latched: \(KeyChord.press(uEsc, with: []))")
// Two latched: each modifier's key down in the trackpad's order with the flags so far, the key, the
// modifiers' keys up in reverse with the flags left.
check(KeyChord.press(uRight, with: [.control, .shift]) == [key(uLCtrl, true, control), key(uLShift, true, control | shift),
                                                          key(uRight, true, control | shift), key(uRight, false, control | shift),
                                                          key(uLShift, false, control), key(uLCtrl, false, 0)],
      "⌃⇧→: \(KeyChord.press(uRight, with: [.control, .shift]))")
check(KeyChord.modifiersDown([.command, .shift]) == [key(uLShift, true, shift), key(uLCmd, true, shift | command)]
      && KeyChord.modifiersUp([.command, .shift]) == [key(uLCmd, false, shift), key(uLShift, false, 0)],
      "the trackpad's ⌘⇧ around a click, as before")
check(KeyChord.modifiersDown([]).isEmpty && KeyChord.modifiersUp([]).isEmpty, "nothing latched: no modifier keys")
check([(uLCtrl, KeyModifiers.control), (uLShift, .shift), (uLOpt, .option), (uLCmd, .command),
       (uRCtrl, .control), (uRShift, .shift), (uROpt, .option), (uRCmd, .command)].allSatisfy { KeyModifiers.flag(forKey: $0.0) == $0.1 }
      && KeyModifiers.flag(forKey: uSpace) == nil && KeyModifiers.flag(forKey: 0x39) == nil,
      "the eight modifier keys' modifiers, and none for Space or caps lock")

// Every latched combination with a few keys, on this Mac and on one from before this fix: the key
// goes out with its modifiers, and nothing is held after.
do {
    var combos = 0
    for bits in 0..<16 {
        var latched: KeyModifiers = []
        if bits & 1 != 0 { latched.insert(.control) }
        if bits & 2 != 0 { latched.insert(.shift) }
        if bits & 4 != 0 { latched.insert(.option) }
        if bits & 8 != 0 { latched.insert(.command) }
        for u in [uSpace, uEsc, uS, uLeft, uReturn] {
            var mac = Mac(), old = OldMac(); let a = Conn()
            let events = KeyChord.press(u, with: latched) + tap
            mac.send(events, from: a); old.send(events)
            let k = KeyStrokes.virtualKeys[u]!
            let sent = mac.log.contains(.key(k, true, latched.rawValue))
            check(sent && mac.table == 0 && mac.down.isEmpty && mac.broken.isEmpty,
                  "\(u) with \(names(latched.rawValue)) on this Mac: \(mac.log)")
            check(old.log.contains(.key(k, true, latched.rawValue)) && old.table == 0 && old.down.isEmpty
                  && !old.log.contains(where: { if case .pointer(let f) = $0 { return f != 0 }; return false }),
                  "\(u) with \(names(latched.rawValue)) on a Mac from before this fix: \(old.log)")
            combos += 1
        }
    }
    check(combos == 80, "80 combinations")
}
// The Spotlight key on a Mac from before this fix: the older device's ⌘Space left command there (the
// bug), this device's leaves nothing.
do {
    var old = OldMac()
    old.send(bare(uSpace, command) + tap)
    check(old.table == command && old.log.last == .pointer(command), "an older device's Spotlight key leaves command on an older Mac")
    var fixed = OldMac()
    fixed.send(KeyChord.spotlight + tap)
    check(fixed.table == 0 && fixed.log.last == .pointer(0), "this device's Spotlight key leaves nothing on an older Mac: \(fixed.log)")
}

// MARK: The key row's caps held (HeldCap, #162)
//
// Escape, tab and the arrows of the key row go down when a finger lands on them and up when it leaves
// (HeldCap), so the Mac repeats a cap held down (KeyRepeat, Tests/checks/key-repeat); what is latched
// goes down with the key, its modifiers' own keys first, and is spent at the touch; one cap at a time;
// the Button's own action after a touch sends nothing, and an assistive technology's activation (no
// touch) the whole press, as before.

let uUp: UInt16 = 0x52, uDown: UInt16 = 0x51

// A key going down and up with what is latched: `press` is exactly `down` then `up`.
check(KeyChord.down(uLeft, with: [.option]) == [key(uLOpt, true, option), key(uLeft, true, option)]
      && KeyChord.up(uLeft, with: [.option]) == [key(uLeft, false, option), key(uLOpt, false, 0)],
      "⌥←'s down and up: \(KeyChord.down(uLeft, with: [.option])) then \(KeyChord.up(uLeft, with: [.option]))")
check(KeyChord.down(uEsc, with: []) == [key(uEsc, true, 0)] && KeyChord.up(uEsc, with: []) == [key(uEsc, false, 0)],
      "escape with nothing latched: its down, its up")
do {
    var all = true
    for bits in 0..<16 {
        var latched: KeyModifiers = []
        if bits & 1 != 0 { latched.insert(.control) }
        if bits & 2 != 0 { latched.insert(.shift) }
        if bits & 4 != 0 { latched.insert(.option) }
        if bits & 8 != 0 { latched.insert(.command) }
        for u in [uEsc, uTab, uLeft, uRight, uUp, uDown] where KeyChord.press(u, with: latched) != KeyChord.down(u, with: latched) + KeyChord.up(u, with: latched) {
            all = false
        }
    }
    check(all, "a press is its down then its up, for every latch")
}

// A finger on escape, then off: its down at the touch, its up at the release; the Button's action as
// the finger lifts sends nothing more, before the press ends or after it.
do {
    var h = HeldCap()
    check(h.touchDown(uEsc, latched: [], at: 1.0) == [key(uEsc, true, 0)] && h.down?.usage == uEsc, "escape's touch: its down")
    check(h.touchUp(uEsc, at: 1.8) == [key(uEsc, false, 0)] && h.down == nil, "the release: its up")
    check(h.activated(uEsc, latched: [], at: 1.81).isEmpty, "the action just after: nothing")
    check(h.activated(uEsc, latched: [], at: 1.85) == KeyChord.press(uEsc, with: []), "a second activation after it is a press of its own")
    var g = HeldCap()
    _ = g.touchDown(uTab, latched: [.option], at: 1.0)
    check(g.activated(uTab, latched: [.shift], at: 1.5) == [key(uTab, false, option), key(uLOpt, false, 0)] && g.down == nil,
          "the action before the press's end is told: it is the release, the key and its ⌥ up")
    check(g.touchUp(uTab, at: 1.51).isEmpty, "then the press's end: nothing more")
    check(g.activated(uTab, latched: [], at: 3.0) == KeyChord.press(uTab, with: []), "a later activation: the whole press")
    // The latch is spent when a key goes down with it: a touch's down, a whole press; never by an up.
    check(HeldCap.spendsLatch(KeyChord.down(uEsc, with: [])) && HeldCap.spendsLatch(KeyChord.press(uTab, with: [.shift]))
          && !HeldCap.spendsLatch(KeyChord.up(uLeft, with: [.option])) && !HeldCap.spendsLatch([]),
          "the latch: spent by a down or a press, not by an up or nothing")
}
// With ⌥ latched: ⌥'s own key and ← go down at the touch, ← and then ⌥ come up at the release; a
// modifier latched meanwhile is not the held cap's (touchUp takes no latch).
do {
    var h = HeldCap()
    check(h.touchDown(uLeft, latched: [.option], at: 1.0) == [key(uLOpt, true, option), key(uLeft, true, option)], "⌥ latched: ⌥ and ← down")
    check(h.down?.modifiers == [.option], "the cap holds what it went down with")
    check(h.touchUp(uLeft, at: 2.0) == [key(uLeft, false, option), key(uLOpt, false, 0)], "the release: ← up, then ⌥ up")
}
// VoiceOver, Switch Control or a keyboard activates a cap with no touch: the whole press with what is
// latched, as before; also long after a touch that slid off the cap (no action came for it).
do {
    var h = HeldCap()
    check(h.activated(uTab, latched: [.shift], at: 5.0) == KeyChord.press(uTab, with: [.shift]), "an activation with no touch: ⇧Tab pressed")
    _ = h.touchDown(uEsc, latched: [], at: 6.0)
    _ = h.touchUp(uEsc, at: 6.2)
    check(h.activated(uEsc, latched: [], at: 7.0) == KeyChord.press(uEsc, with: []), "0.8 s after a slid-off touch: the whole press")
    _ = h.touchDown(uEsc, latched: [], at: 8.0)
    check(h.activated(uEsc, latched: [], at: 8.4) == [key(uEsc, false, 0)], "the action with the finger still on it, as told: its up")
    check(h.activated(uEsc, latched: [], at: 8.45) == KeyChord.press(uEsc, with: []), "a second activation: its own press")
    check(h.touchUp(uEsc, at: 8.5).isEmpty, "the press's end after: nothing more")
}
// A finger on a second cap: the first comes up first (one key at a time), then the second goes down;
// the first's own release and action later send nothing.
do {
    var h = HeldCap()
    check(h.touchDown(uLeft, latched: [.command], at: 1.0) == [key(uLCmd, true, command), key(uLeft, true, command)], "⌘←'s touch")
    check(h.touchDown(uRight, latched: [], at: 1.5) == [key(uLeft, false, command), key(uLCmd, false, 0), key(uRight, true, 0)],
          "a finger on →: ← and ⌘ up, then → down")
    check(h.touchUp(uLeft, at: 1.7).isEmpty && h.activated(uLeft, latched: [], at: 1.7).isEmpty, "←'s release and action: nothing")
    check(h.down?.usage == uRight, "→ is the cap down")
    check(h.touchUp(uRight, at: 2.0) == [key(uRight, false, 0)] && h.activated(uRight, latched: [], at: 2.0).isEmpty, "→'s release, its action")
}
// The same cap's press told twice (no release between): one down. Off the cap and back: up, then down.
do {
    var h = HeldCap()
    check(h.touchDown(uUp, latched: [], at: 1.0) == [key(uUp, true, 0)] && h.touchDown(uUp, latched: [.shift], at: 1.1).isEmpty,
          "a second press of the cap down: nothing, and the latch stays (nothing came back)")
    check(h.touchUp(uUp, at: 1.2) == [key(uUp, false, 0)] && h.touchDown(uUp, latched: [], at: 1.3) == [key(uUp, true, 0)]
          && h.touchUp(uUp, at: 1.4) == [key(uUp, false, 0)] && h.activated(uUp, latched: [], at: 1.4).isEmpty,
          "slid off and back on: up, down again, up, and its action nothing")
}
// The key row leaves the screen with a cap held: it comes up, with its modifiers; its release after
// sends nothing.
do {
    var h = HeldCap()
    check(h.releaseAll().isEmpty, "nothing held: nothing to let go")
    _ = h.touchDown(uDown, latched: [.shift, .control], at: 1.0)
    check(h.releaseAll() == [key(uDown, false, shift | control), key(uLShift, false, control), key(uLCtrl, false, 0)] && h.down == nil,
          "⌃⇧↓ held as the row goes: ↓, ⇧ and ⌃ up")
    check(h.touchUp(uDown, at: 1.5).isEmpty, "the release after: nothing")
}
// Held on this Mac and on one from before 2026-09-27 (which posts each key's flags as they come): the
// key is down on the Mac from the touch to the release, carrying what was latched, and nothing is left
// held after; for every latch and every held cap.
do {
    var combos = 0, ok = true
    for bits in 0..<16 {
        var latched: KeyModifiers = []
        if bits & 1 != 0 { latched.insert(.control) }
        if bits & 2 != 0 { latched.insert(.shift) }
        if bits & 4 != 0 { latched.insert(.option) }
        if bits & 8 != 0 { latched.insert(.command) }
        for u in [uEsc, uTab, uLeft, uRight, uUp, uDown] {
            var mac = Mac(), old = OldMac(); let a = Conn()
            var h = HeldCap()
            let downs = h.touchDown(u, latched: latched, at: 1.0)
            mac.send(downs, from: a); old.send(downs)
            let k = KeyStrokes.virtualKeys[u]!
            let heldNow = mac.down[k] == latched.rawValue && old.down[k] == latched.rawValue
            let ups = h.touchUp(u, at: 2.0) + tap
            mac.send(ups, from: a); old.send(ups)
            if !(heldNow && mac.down.isEmpty && mac.table == 0 && mac.broken.isEmpty && old.down.isEmpty && old.table == 0) {
                ok = false; print("FAIL: \(u) held with \(names(latched.rawValue)): this Mac \(mac.log), older \(old.log)")
            }
            combos += 1
        }
    }
    check(ok && combos == 96, "96 held caps on this Mac and an older one: down while held, nothing left after")
}
// Random key row sessions: fingers landing on and leaving the six caps (two at once), their actions in
// the window or not, activations with no touch, latches made and spent as the key row spends them, and
// the row leaving the screen. Whenever no cap is down, nothing is held on this Mac or an older one;
// while one is down its key is the one down on the Mac, with what it went down with.
do {
    var rng = Rng(state: 0xCA95_4E1D)
    var broken = 0, sessions = 0, holds = 0, presses = 0
    let caps: [UInt16] = [uEsc, uTab, uLeft, uRight, uUp, uDown]
    for run in 0..<2000 {
        var mac = Mac(), old = OldMac(); let a = Conn()
        var h = HeldCap()
        var latched: KeyModifiers = []
        var t = 1.0
        var fingers: [UInt16] = []
        var problem: String?
        func send(_ events: [InputEvent]) { mac.send(events, from: a); old.send(events) }
        for step in 0..<(10 + rng.below(40)) {
            t += Double(rng.below(400)) / 1000
            switch rng.below(9) {
            case 0, 1, 2:
                let u = rng.pick(caps)
                let events = h.touchDown(u, latched: latched, at: t)
                send(events)
                if HeldCap.spendsLatch(events) { latched = []; holds += 1 }
                if !fingers.contains(u) { fingers.append(u) }
            case 3, 4:
                if let u = fingers.isEmpty ? nil : fingers[rng.below(fingers.count)] {
                    // The release: the press's end and the Button's action, in either order, or the end alone
                    // (the finger slid off the cap).
                    let action = rng.chance(70), first = rng.chance(50)
                    if action && first { send(h.activated(u, latched: latched, at: t)) }
                    send(h.touchUp(u, at: t))
                    fingers.removeAll { $0 == u }
                    if action && !first { t += Double(rng.below(30)) / 1000; send(h.activated(u, latched: latched, at: t)) }
                }
            case 5:
                let u = rng.pick(caps)
                if !fingers.contains(u) {
                    let events = h.activated(u, latched: latched, at: t + 1)
                    t += 1
                    send(events)
                    if HeldCap.spendsLatch(events) { latched = []; presses += 1 }
                }
            case 6, 7:
                latched.formSymmetricDifference(rng.pick([KeyModifiers.control, .shift, .option, .command]))
            default:
                if rng.chance(30) { send(h.releaseAll()); fingers = [] }
            }
            let modifierKeysDown = mac.down.keys.filter { macModifiers[$0] != nil }
            if let held = h.down {
                let k = KeyStrokes.virtualKeys[held.usage]!
                let others = mac.down.keys.filter { macModifiers[$0] == nil && $0 != k }
                if mac.down[k] != held.modifiers.rawValue || !others.isEmpty || old.down[k] != held.modifiers.rawValue {
                    problem = "step \(step): cap \(held.usage) down with \(names(held.modifiers.rawValue)), the Mac has \(mac.down)"
                }
            } else if !mac.down.isEmpty || mac.table & modifierBits != 0 || !old.down.isEmpty || old.table & modifierBits != 0 || !modifierKeysDown.isEmpty {
                problem = "step \(step): no cap down, yet this Mac has \(mac.down) (\(names(mac.table))), an older one \(old.down)"
            }
            if !mac.broken.isEmpty { problem = "step \(step): " + mac.broken[0] }
            if problem != nil { break }
        }
        if let problem { broken += 1; if broken <= 3 { print("FAIL: key row run \(run): \(problem)") } }
        sessions += 1
    }
    check(broken == 0, "key row sessions: \(broken) of \(sessions) left something held or the wrong key down")
    check(holds > 10_000 && presses > 1_000, "the sessions hold caps and press them: \(holds) holds, \(presses) presses")
}

// MARK: The device's hardware keyboard (ForwardedKeys)

/// A hardware keyboard on this device and what UIKit tells InputOverlayView: the modifiers held after
/// each change, or, `before`, from before it (so a modifier's release still carries its own flag and
/// its press does not yet).
struct Keyboard {
    var physical: [UInt16] = []
    var before = false
    var forwarded = ForwardedKeys()
    /// Who types the characters as each key goes down (KeyTyping: the overlay asks it at each press):
    /// iPadOS's text system, as before, unless a test says the Mac.
    var typing = KeyTyping.text
    /// Caps Lock on: the iPad's own state, which its key toggles (that key is the text system's whoever
    /// types, and types nothing), carried in UIKit's flags as alphaShift.
    var capsLockOn = false
    /// The clock UIPress timestamps and the key commands' firing share (systemUptime).
    var time: Double = 1000
    var flags: UInt64 {
        physical.reduce(capsLockOn ? capsLock : 0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) }
    }
    /// What the overlay does with an answer of `pressed` or `released`: to the Mac, to the text system
    /// (a character typed; a modifier alone, Caps Lock or a key's up types nothing), or nowhere.
    func outcome(_ p: ForwardedKeys.Press, _ u: UInt16, down: Bool) -> [InputEvent] {
        switch p {
        case .send(let e): return [e]
        case .text: return down && KeyModifiers.flag(forKey: u) == nil && u != uCapsLock ? [.text("x")] : []
        case .swallow: return []
        }
    }
    /// A key pressed, as pressesBegan has it (`pressed`): its down if it goes to the Mac as a key, else
    /// a character typed. Unseen (the overlay not taking keys), nothing. Caps Lock's press toggles it.
    mutating func press(_ u: UInt16, seen: Bool = true) -> [InputEvent] {
        guard !physical.contains(u) else { return [] }
        let was = flags
        physical.append(u)
        time += 0.2
        if u == uEsc { escSeen = seen }
        if u == uCapsLock { capsLockOn.toggle() }
        guard seen else { return [] }
        return outcome(forwarded.pressed(u, modifiers: before ? was : flags, at: time, typing: typing), u, down: true)
    }
    mutating func release(_ u: UInt16, seen: Bool = true) -> [InputEvent] {
        guard let i = physical.firstIndex(of: u) else { return [] }
        physical.remove(at: i)
        time += 0.2
        guard seen else { return [] }
        // UIKit's flags at a release: the up carries the modifier keys down on the Mac instead.
        return outcome(forwarded.released(u), u, down: false)
    }
    /// A press cancelled: the same up.
    mutating func cancel(_ u: UInt16) -> [InputEvent] {
        guard let i = physical.firstIndex(of: u) else { return [] }
        physical.remove(at: i)
        return outcome(forwarded.released(u), u, down: false)
    }

    /// How a device hands over a hardware Escape (InputOverlayView): `.commandOnly` keeps it from
    /// pressesBegan and fires the key command (the reported iPad); `.pressFirst` gives pressesBegan the
    /// press and fires the command only when pressesBegan hands it on (the iOS 27 simulator: never,
    /// as the overlay keeps Esc, but a device might fire both); `.commandFirst` fires the command, then
    /// gives pressesBegan the same press.
    enum EscOrder { case commandOnly, pressFirst, commandFirst }

    /// Esc pressed with what is held, its key command firing 2 ms after the press, in `order`. The
    /// command fires with UIKit's flags.
    mutating func esc(_ order: EscOrder) -> [InputEvent] {
        guard !physical.contains(uEsc) else { return [] }
        let held = flags
        physical.append(uEsc)
        time += 0.2
        let pressedAt = time, firedAt = time + 0.002
        switch order {
        case .commandOnly:
            escSeen = false
            return forwarded.commanded(uEsc, modifiers: held, at: firedAt)
        case .pressFirst:
            escSeen = true
            return outcome(forwarded.pressed(uEsc, modifiers: held, at: pressedAt, typing: typing), uEsc, down: true)
                + forwarded.commanded(uEsc, modifiers: held, at: firedAt)
        case .commandFirst:
            escSeen = true
            return forwarded.commanded(uEsc, modifiers: held, at: firedAt)
                + outcome(forwarded.pressed(uEsc, modifiers: held, at: pressedAt, typing: typing), uEsc, down: true)
        }
    }
    /// Whether pressesBegan saw the last Esc, so pressesEnded sees its release too.
    var escSeen = true
    /// Esc let go: pressesEnded only where pressesBegan had the press.
    mutating func releaseEsc() -> [InputEvent] { release(uEsc, seen: escSeen) }
}

// Which keys go to the Mac as keys: the ones the text system never delivers, ⌘, ⌃ and ⌥ themselves,
// any key while ⌘, ⌃ or ⌥ is held, and return and tab with shift (their "\n" and "\t" carry none);
// shift alone otherwise makes characters.
check([uLeft, uRight, 0x51, 0x52, uEsc, 0x4C, 0x4A, 0x4D, 0x4B, 0x4E, 0x3A, 0x45, uLCmd, uRCmd, uLCtrl, uRCtrl, uLOpt, uROpt]
        .allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: 0, typing: .text) },
      "arrows, escape, forward delete, home, end, page up and down, F1 and F12, ⌘, ⌃, ⌥: as keys")
check(![uS, uSpace, 0x2A, uLShift, uRShift, 0x39].contains { ForwardedKeys.goesAsKey($0, modifiers: shift | capsLock, typing: .text) },
      "letters, space, delete, shift and caps lock with shift: to the text system")
check([uReturn, 0x2B].allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: shift, typing: .text)
                                   && ForwardedKeys.goesAsKey($0, modifiers: shift | capsLock, typing: .text) },
      "return and tab with shift: as keys (the text system's \\n and \\t carry no shift)")
check(![uReturn, 0x2B].contains { ForwardedKeys.goesAsKey($0, modifiers: 0, typing: .text) || ForwardedKeys.goesAsKey($0, modifiers: capsLock, typing: .text) },
      "return and tab alone, or with caps lock: to the text system (an IME's return confirms its text)")
// ⇧Return and ⇧Tab: the key's down carries shift (the text system's, so no shift key went), its up
// the keys down: none; either Mac is left nothing.
for (u, name) in [(uReturn, "⇧Return"), (UInt16(0x2B), "⇧Tab")] {
    var kb = Keyboard()
    let events = kb.press(uLShift) + kb.press(u) + kb.release(u) + kb.release(uLShift)
    check(events == [key(u, true, shift), key(u, false, 0)], "\(name): \(events)")
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events + tap, from: a); old.send(events + tap)
    check(mac.table == 0 && mac.broken.isEmpty && old.table == 0 && old.log.last == .pointer(0), "\(name) leaves nothing on either Mac")
}
check([uS, uSpace, uReturn, uLShift].allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: command, typing: .text)
                                                  && ForwardedKeys.goesAsKey($0, modifiers: option, typing: .text)
                                                  && ForwardedKeys.goesAsKey($0, modifiers: control, typing: .text) },
      "any key while ⌘, ⌃ or ⌥ is held: as a key")

// ⌘C, ⌘ let go last: the ⌘ key's up goes to the Mac although UIKit no longer says command.
for before in [false, true] {
    var kb = Keyboard(); kb.before = before
    let events = kb.press(uLCmd) + kb.press(uC) + kb.release(uC) + kb.release(uLCmd)
    check(events == [key(uLCmd, true, command), key(uC, true, command), key(uC, false, before ? command : command), key(uLCmd, false, 0)],
          "⌘C (UIKit's flags \(before ? "before" : "after") each change): \(events)")
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events + tap, from: a); old.send(events + tap)
    check(mac.table == 0 && mac.broken.isEmpty && old.table == 0 && old.log.last == .pointer(0), "⌘C leaves nothing on either Mac")
    check(kb.forwarded.down.isEmpty, "nothing forwarded is down")
}
// ⌘ let go before C: C's up still goes (its down did), with what UIKit says then.
do {
    var kb = Keyboard()
    let events = kb.press(uLCmd) + kb.press(uC) + kb.release(uLCmd) + kb.release(uC)
    check(events == [key(uLCmd, true, command), key(uC, true, command), key(uLCmd, false, 0), key(uC, false, 0)], "⌘ let go before C: \(events)")
}
// C pressed alone goes to the text system, and its up too, even while ⌘ is held by then.
do {
    var kb = Keyboard()
    let events = kb.press(uC) + kb.press(uLCmd) + kb.release(uC) + kb.release(uLCmd)
    check(events == [.text("x"), key(uLCmd, true, command), key(uLCmd, false, 0)], "C, then ⌘, C up, ⌘ up: \(events)")
}
// Shift held before ⌘ (shift alone is the text system's): the shortcut's down has both, but ⌘'s own
// key and every up carry only the modifier keys down on the Mac, so an older Mac is left no shift.
do {
    var kb = Keyboard()
    let events = kb.press(uLShift) + kb.press(uLCmd) + kb.press(uS) + kb.release(uS) + kb.release(uLCmd) + kb.release(uLShift)
    check(events == [key(uLCmd, true, command), key(uS, true, shift | command), key(uS, false, command), key(uLCmd, false, 0)],
          "⇧, then ⌘S: \(events)")
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events + tap, from: a); old.send(events + tap)
    check(mac.table == 0 && mac.broken.isEmpty && old.table == 0 && old.log.last == .pointer(0), "⇧⌘S leaves nothing on either Mac")
}
// ⌘ let go before S while shift is still held: S's up carries nothing (shift is the text system's),
// so an older Mac is left no shift either.
do {
    var kb = Keyboard()
    let events = kb.press(uLShift) + kb.press(uLCmd) + kb.press(uS) + kb.release(uLCmd) + kb.release(uS) + kb.release(uLShift)
    check(events == [key(uLCmd, true, command), key(uS, true, shift | command), key(uLCmd, false, 0), key(uS, false, 0)],
          "⇧⌘S, ⌘ let go first: \(events)")
    var old = OldMac()
    old.send(events + tap)
    check(old.table == 0 && old.log.last == .pointer(0), "an older Mac is left nothing: \(old.log)")
}
// Left and right ⌘: the left's up keeps command while the right is down.
do {
    var kb = Keyboard()
    let events = kb.press(uLCmd) + kb.press(uRCmd) + kb.release(uLCmd) + kb.release(uRCmd)
    check(events == [key(uLCmd, true, command), key(uRCmd, true, command), key(uLCmd, false, command), key(uRCmd, false, 0)],
          "left and right ⌘: \(events)")
}
// A press cancelled (the app going to the background with ⌘ and C held): C's up with command, then ⌘'s.
do {
    var kb = Keyboard()
    let events = kb.press(uLCmd) + kb.press(uC) + kb.cancel(uC) + kb.cancel(uLCmd)
    check(events == [key(uLCmd, true, command), key(uC, true, command), key(uC, false, command), key(uLCmd, false, 0)],
          "⌘C cancelled: \(events)")
    check(kb.cancel(uS).isEmpty, "a press never made: nothing")
}
// The overlay no longer taking keys (the Settings panel, the tour) while ⌥, ⌘ and ← are down: every
// key down on the Mac goes up, the last pressed first; releases after that are the text system's.
do {
    var kb = Keyboard()
    _ = kb.press(uLOpt) + kb.press(uLCmd) + kb.press(uLeft)
    let ups = kb.forwarded.releaseAll()
    check(ups == [key(uLeft, false, option | command), key(uLCmd, false, option), key(uLOpt, false, 0)], "releaseAll: \(ups)")
    check(kb.forwarded.down.isEmpty && kb.forwarded.releaseAll().isEmpty, "then nothing is down")
    check(kb.release(uLCmd).isEmpty, "a release after that: nothing")
}

// Esc through its key command (#67): down and up at once, as the press would have sent them.
do {
    var kb = Keyboard()
    let events = kb.esc(.commandOnly) + kb.releaseEsc()
    check(events == [key(uEsc, true, 0), key(uEsc, false, 0)], "Esc by its key command alone: \(events)")
    check(kb.forwarded.down.isEmpty && kb.forwarded.swallowed.isEmpty, "then nothing is down or swallowed")
}
// ⇧Esc: the down carries shift (the text system's, so no shift key went), the up the keys down: none.
do {
    var kb = Keyboard()
    let events = kb.press(uLShift) + kb.esc(.commandOnly) + kb.releaseEsc() + kb.release(uLShift)
    check(events == [key(uEsc, true, shift), key(uEsc, false, 0)], "⇧Esc by its key command: \(events)")
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events + tap, from: a); old.send(events + tap)
    check(mac.table == 0 && mac.broken.isEmpty && old.table == 0 && old.log.last == .pointer(0), "⇧Esc leaves nothing on either Mac")
}
// ⌘Esc, ⌘ forwarded first: Esc's down and up both carry command (⌘ is down on the Mac), then ⌘'s up.
do {
    var kb = Keyboard()
    let events = kb.press(uLCmd) + kb.esc(.commandOnly) + kb.releaseEsc() + kb.release(uLCmd)
    check(events == [key(uLCmd, true, command), key(uEsc, true, command), key(uEsc, false, command), key(uLCmd, false, 0)],
          "⌘Esc by its key command: \(events)")
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events + tap, from: a); old.send(events + tap)
    check(mac.table == 0 && mac.broken.isEmpty && old.table == 0 && old.log.last == .pointer(0), "⌘Esc leaves nothing on either Mac")
}
// The two channels with one key press: the press first, then its command (sends nothing; the press's up
// follows), or the command first, then its press (swallowed, and its up): one Esc either way.
for order in [Keyboard.EscOrder.pressFirst, .commandFirst] {
    var kb = Keyboard()
    let events = kb.esc(order) + kb.releaseEsc()
    check(events == [key(uEsc, true, 0), key(uEsc, false, 0)], "Esc through both channels (\(order)): sent once: \(events)")
    check(kb.forwarded.down.isEmpty && kb.forwarded.swallowed.isEmpty, "Esc through both channels (\(order)): nothing left")
}
// The press the command sent is the one no later than it: a later Esc is a new press, sent.
do {
    var kb = Keyboard()
    _ = kb.esc(.commandFirst) + kb.releaseEsc()
    let again = kb.press(uEsc) + kb.release(uEsc)
    check(again == [key(uEsc, true, 0), key(uEsc, false, 0)], "a later Esc press after a command's: sent: \(again)")
}
// Held, the command repeats: each repeat a down and up; the press it came with swallowed with its up.
do {
    var f = ForwardedKeys()
    let first = f.commanded(uEsc, modifiers: 0, at: 5.0)
    let repeated = f.commanded(uEsc, modifiers: 0, at: 5.5)
    let press = f.pressed(uEsc, modifiers: 0, at: 4.999, typing: .text)
    let up = f.released(uEsc)
    check(first == [key(uEsc, true, 0), key(uEsc, false, 0)] && repeated == first && press == .swallow && up == .swallow,
          "a repeating command and its one press: \(first) \(repeated) \(press) \(up)")
    check(f.released(uEsc) == .text, "a second release of a swallowed press: the text system's")
}
// Esc down through pressesBegan (held): the command sends nothing while it is down.
do {
    var f = ForwardedKeys()
    let down = f.pressed(uEsc, modifiers: 0, at: 1.0, typing: .text)
    let command = f.commanded(uEsc, modifiers: 0, at: 1.1)
    let up = f.released(uEsc)
    check(down == .send(key(uEsc, true, 0)) && command.isEmpty && up == .send(key(uEsc, false, 0)),
          "the command while the press holds Esc down: nothing: \(down) \(command) \(up)")
}
// The overlay letting go (the Settings panel, the tour) forgets a swallowed press: UIKit sends no up.
do {
    var f = ForwardedKeys()
    _ = f.commanded(uEsc, modifiers: 0, at: 2.0)
    _ = f.pressed(uEsc, modifiers: 0, at: 1.99, typing: .text)
    check(f.swallowed == [uEsc], "a swallowed press is remembered")
    check(f.releaseAll().isEmpty && f.swallowed.isEmpty, "releaseAll forgets it")
}
// `pressed` and `released` are `began` and `ended` for every other key.
do {
    var f = ForwardedKeys()
    check(f.pressed(uS, modifiers: 0, at: 1, typing: .text) == .text && f.pressed(uLeft, modifiers: 0, at: 1, typing: .text) == .send(key(uLeft, true, 0))
          && f.released(uLeft) == .send(key(uLeft, false, 0)) && f.released(uS) == .text,
          "pressed and released for S and ←")
    check(f.commanded(uS, modifiers: 0, at: 2).isEmpty, "a key the text system takes: no command sends it")
}

// MARK: Who types a hardware keyboard's characters (KeyTyping, #162's letters)

// While the Mac types them (`.keys`: a keyboard in the Latin alphabet selected on the iPad, nothing
// composed, nothing latched), every key that types a character goes to the Mac as a key, so the Mac
// repeats a held one and its own layout and dead keys apply; otherwise (`.text`) they go to iPadOS's text
// system, as before, and while an input method composes (`.composing`) the overlay hands every key to it
// before ForwardedKeys is asked (here, as the text system's).
let characterKeys = Set(0x04...0x1D).union(0x1E...0x27).union([uReturn, uDelete, uTab, uSpace]).union(0x2D...0x31)
    .union(0x33...0x38).union([uLShift, uRShift])
check(ForwardedKeys.characterUsages == characterKeys,
      "the character keys: the letters, the digits, Return, Delete, Tab, Space, - = [ ] \\ ; ' ` , . / and Shift's two: "
        + "\(ForwardedKeys.characterUsages.sorted().map { String($0, radix: 16) })")
check(characterKeys.allSatisfy { KeyStrokes.virtualKeys[$0] != nil },
      "every character key is a key every Sill for Mac answers to (none is dropped by a Mac from before)")
check(characterKeys.allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: 0, typing: .keys)
                                 && ForwardedKeys.goesAsKey($0, modifiers: shift | capsLock, typing: .keys) },
      "while the Mac types: every character key as a key, with shift or caps lock too")
check(!characterKeys.subtracting(ForwardedKeys.keyUsages).contains { u in
          [KeyTyping.text, .composing].contains { ForwardedKeys.goesAsKey(u, modifiers: 0, typing: $0)
                                                  || (u != uReturn && u != uTab && ForwardedKeys.goesAsKey(u, modifiers: shift | capsLock, typing: $0)) } },
      "while iPadOS types: the character keys to the text system, as before (⇧Return and ⇧Tab aside)")
check(ForwardedKeys.keyUsages.allSatisfy { u in [KeyTyping.keys, .text, .composing].allSatisfy { ForwardedKeys.goesAsKey(u, modifiers: 0, typing: $0) } },
      "the keys the text system never delivers: as keys whoever types")
check(characterKeys.allSatisfy { u in [KeyTyping.keys, .text].allSatisfy { ForwardedKeys.goesAsKey(u, modifiers: command, typing: $0)
                                                                         && ForwardedKeys.goesAsKey(u, modifiers: option, typing: $0) } },
      "a character key with ⌘ or ⌥: a shortcut, as a key whoever types")
// Caps Lock, the keypad, the ISO keyboards' Non-US # and \ and the international keys: no Sill for Mac
// before has a key for the last three (KeyStrokes.virtualKeys), and Caps Lock is the iPad's own state.
let textAlways: [UInt16] = [uCapsLock, 0x32, 0x64, 0x53, 0x54, 0x58, 0x59, 0x62, 0x63, 0x67, 0x85, 0x87, 0x89]
check(!textAlways.contains { ForwardedKeys.goesAsKey($0, modifiers: 0, typing: .keys) || ForwardedKeys.goesAsKey($0, modifiers: shift, typing: .keys) },
      "Caps Lock, the keypad, Non-US # and \\, the international keys: the text system's whoever types")
check(textAlways.filter { $0 != uCapsLock }.allSatisfy { KeyStrokes.virtualKeys[$0] == nil },
      "the keys left to the text system are ones a Mac from before has no key for (but Caps Lock)")

/// A key's events on this Mac and on one from before (each left nothing held, the tap after plain): what
/// the Mac posted.
func onBothMacs(_ events: [InputEvent], _ what: String, line: Int = #line) -> [Mac.Event] {
    var mac = Mac(), old = OldMac(); let a = Conn()
    mac.send(events, from: a); old.send(events)
    let posted = mac.log
    mac.send(tap, from: a); old.send(tap)
    check(mac.table == 0 && mac.broken.isEmpty && mac.down.isEmpty && old.table == 0 && old.down.isEmpty && old.log.last == .pointer(0),
          "\(what) leaves nothing on either Mac: \(mac.log) / \(old.log)", line: line)
    return posted
}

// A held P, the reported key (Noah, 2026-10-29: "hold p didnt work"): its down goes at the press and its
// up at the release, so the Mac repeats it between them (KeyRepeat); the text system never sees it.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uP) + kb.release(uP)
    check(events == [key(uP, true, 0), key(uP, false, 0)], "P held while the Mac types: \(events)")
    expect(onBothMacs(events, "P held"), [.key(35, true, 0), .key(35, false, 0)], "P held: the Mac's P (kVK_ANSI_P)")
    var text = Keyboard()
    check(text.press(uP) + text.release(uP) == [.text("x")], "P while iPadOS types: the text system's, as before")
}
// E, which iPadOS's press and hold gave its accent popover: a key, the text system never sees it.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uE) + kb.release(uE)
    check(events == [key(uE, true, 0), key(uE, false, 0)], "E held while the Mac types: \(events)")
}
// Every character key alone: down and up as a key, nothing left down on the device.
do {
    var bad: [UInt16] = []
    for u in characterKeys.sorted() {
        var kb = Keyboard(); kb.typing = .keys
        let events = kb.press(u) + kb.release(u)
        let isShift = KeyModifiers.flag(forKey: u) == .shift
        let want = isShift ? [key(u, true, shift), key(u, false, 0)] : [key(u, true, 0), key(u, false, 0)]
        if events != want || !kb.forwarded.down.isEmpty { bad.append(u) }
    }
    check(bad.isEmpty, "each character key alone while the Mac types: \(bad.map { String($0, radix: 16) })")
}
// ⇧A: Shift's own key goes first (so the Mac knows it is held: the repeats of a held A follow it), then
// A with shift, A's up with shift still held, Shift's up with nothing.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uLShift) + kb.press(uA) + kb.release(uA) + kb.release(uLShift)
    check(events == [key(uLShift, true, shift), key(uA, true, shift), key(uA, false, shift), key(uLShift, false, 0)], "⇧A: \(events)")
    expect(onBothMacs(events, "⇧A"), [.key(56, true, shift), .key(0, true, shift), .key(0, false, shift), .key(56, false, 0)],
           "⇧A on the Mac: Shift's flags-changed, A with shift, Shift let go")
}
// Shift let go before A: Shift's up first (the Mac's repeats of A go on without it), then A's up.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uLShift) + kb.press(uA) + kb.release(uLShift) + kb.release(uA)
    check(events == [key(uLShift, true, shift), key(uA, true, shift), key(uLShift, false, 0), key(uA, false, 0)], "⇧A, ⇧ let go first: \(events)")
    _ = onBothMacs(events, "⇧A with ⇧ let go first")
}
// The right Shift, and both: the left's up keeps shift while the right is down.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uLShift) + kb.press(uRShift) + kb.press(uZ) + kb.release(uLShift) + kb.release(uZ) + kb.release(uRShift)
    check(events == [key(uLShift, true, shift), key(uRShift, true, shift), key(uZ, true, shift), key(uLShift, false, shift),
                     key(uZ, false, shift), key(uRShift, false, 0)], "both Shifts around Z: \(events)")
    _ = onBothMacs(events, "both Shifts around Z")
}
// Caps Lock on (the iPad's): a letter goes down with shift too, so the Mac types a capital whatever it
// makes of a posted caps lock flag; its up with nothing held. Caps Lock's own key types nothing.
do {
    var kb = Keyboard(); kb.typing = .keys
    let toggle = kb.press(uCapsLock) + kb.release(uCapsLock)
    check(toggle.isEmpty && kb.capsLockOn, "Caps Lock's key: the text system's, nothing typed: \(toggle)")
    let events = kb.press(uA) + kb.release(uA)
    check(events == [key(uA, true, capsLock | shift), key(uA, false, 0)], "A with Caps Lock on: \(events)")
    expect(onBothMacs(events, "A with Caps Lock on"), [.key(0, true, capsLock | shift), .key(0, false, 0)], "A with Caps Lock on, on the Mac")
    // A digit and a punctuation key: Caps Lock changes neither on a Mac, so no shift.
    let digit = kb.press(u1) + kb.release(u1) + kb.press(uSlash) + kb.release(uSlash)
    check(digit == [key(u1, true, capsLock), key(u1, false, 0), key(uSlash, true, capsLock), key(uSlash, false, 0)],
          "1 and / with Caps Lock on: no shift: \(digit)")
    // ⇧A with Caps Lock on: shift once.
    let shifted = kb.press(uLShift) + kb.press(uA) + kb.release(uA) + kb.release(uLShift)
    check(shifted == [key(uLShift, true, shift), key(uA, true, capsLock | shift), key(uA, false, shift), key(uLShift, false, 0)],
          "⇧A with Caps Lock on: \(shifted)")
    // ⌘A, ⌥E and ⌃A with Caps Lock on: the shortcut as it is, never ⌘⇧A.
    let chords = kb.press(uLCmd) + kb.press(uA) + kb.release(uA) + kb.release(uLCmd)
        + kb.press(uLOpt) + kb.press(uE) + kb.release(uE) + kb.release(uLOpt)
        + kb.press(uLCtrl) + kb.press(uA) + kb.release(uA) + kb.release(uLCtrl)
    check(chords == [key(uLCmd, true, command), key(uA, true, capsLock | command), key(uA, false, command), key(uLCmd, false, 0),
                     key(uLOpt, true, option), key(uE, true, capsLock | option), key(uE, false, option), key(uLOpt, false, 0),
                     key(uLCtrl, true, control), key(uA, true, capsLock | control), key(uA, false, control), key(uLCtrl, false, 0)],
          "⌘A, ⌥E and ⌃A with Caps Lock on: no shift added: \(chords)")
    _ = onBothMacs(events + digit + shifted + chords, "Caps Lock's keys")
    // Off again: plain letters.
    _ = kb.press(uCapsLock) + kb.release(uCapsLock)
    check(!kb.capsLockOn && kb.press(uA) + kb.release(uA) == [key(uA, true, 0), key(uA, false, 0)], "Caps Lock off again: a plain A")
    // While iPadOS types, Caps Lock's letters are the text system's as before.
    var text = Keyboard(); text.capsLockOn = true
    check(text.press(uA) + text.release(uA) == [.text("x")], "A with Caps Lock on while iPadOS types: the text system's")
}
check(ForwardedKeys.carried(uA, modifiers: capsLock) == capsLock | shift && ForwardedKeys.carried(uA, modifiers: 0) == 0
      && ForwardedKeys.carried(uZ, modifiers: capsLock) == capsLock | shift && ForwardedKeys.carried(0x1E, modifiers: capsLock) == capsLock
      && ForwardedKeys.carried(uA, modifiers: capsLock | command) == capsLock | command
      && ForwardedKeys.carried(uLeft, modifiers: capsLock) == capsLock,
      "carried: shift for a letter A to Z with Caps Lock on and no shortcut, nothing else")
check(KeyModifiers.capsLock.rawValue == capsLock, "the device's caps lock bit is the Mac's")
// ⌥E, then E: both keys, so the Mac's dead key makes é (as a keyboard plugged into it does); before,
// ⌥E went as a key and E as typed text.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uLOpt) + kb.press(uE) + kb.release(uE) + kb.release(uLOpt) + kb.press(uE) + kb.release(uE)
    check(events == [key(uLOpt, true, option), key(uE, true, option), key(uE, false, option), key(uLOpt, false, 0),
                     key(uE, true, 0), key(uE, false, 0)], "⌥E, then E while the Mac types: \(events)")
    expect(onBothMacs(events, "⌥E, E"), [.key(58, true, option), .key(14, true, option), .key(14, false, option), .key(58, false, 0),
                                       .key(14, true, 0), .key(14, false, 0)], "⌥E, then E on the Mac")
    var text = Keyboard()
    check(text.press(uLOpt) + text.press(uE) + text.release(uE) + text.release(uLOpt) + text.press(uE) + text.release(uE)
          == [key(uLOpt, true, option), key(uE, true, option), key(uE, false, option), key(uLOpt, false, 0), .text("x")],
          "⌥E, then E while iPadOS types: as before, E typed as text")
}
// Return, Delete, Tab and Space as keys; ⇧Return and ⇧Tab with Shift's own key around them.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = [uReturn, uDelete, uTab, uSpace].flatMap { kb.press($0) + kb.release($0) }
    check(events == [uReturn, uDelete, uTab, uSpace].flatMap { [key($0, true, 0), key($0, false, 0)] }, "Return, Delete, Tab, Space: \(events)")
    expect(onBothMacs(events, "Return, Delete, Tab, Space"), [36, 51, 48, 49].flatMap { [Mac.Event.key($0, true, 0), .key($0, false, 0)] },
           "Return, Delete, Tab, Space on the Mac")
    let shifted = kb.press(uLShift) + kb.press(uReturn) + kb.release(uReturn) + kb.press(uTab) + kb.release(uTab) + kb.release(uLShift)
    check(shifted == [key(uLShift, true, shift), key(uReturn, true, shift), key(uReturn, false, shift), key(uTab, true, shift),
                      key(uTab, false, shift), key(uLShift, false, 0)], "⇧Return, ⇧Tab while the Mac types: \(shifted)")
    _ = onBothMacs(shifted, "⇧Return, ⇧Tab")
}
// ⌘S, Esc and ← are as they were.
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uLCmd) + kb.press(uS) + kb.release(uS) + kb.release(uLCmd) + kb.press(uLeft) + kb.release(uLeft)
        + kb.esc(.commandFirst) + kb.releaseEsc() + kb.press(uEsc) + kb.release(uEsc)
    var was = Keyboard()
    let before = was.press(uLCmd) + was.press(uS) + was.release(uS) + was.release(uLCmd) + was.press(uLeft) + was.release(uLeft)
        + was.esc(.commandFirst) + was.releaseEsc() + was.press(uEsc) + was.release(uEsc)
    check(events == before, "⌘S, ←, Esc by both channels and by its press: the same whoever types: \(events)")
}
// A key's way is decided at its down: A down while the Mac types, the keyboard switched to one iPadOS
// types (by the Globe key, say: ⌃Space lets the keys held come up at its Space, below), A's up still to the
// Mac; and the other way, nothing to the Mac.
do {
    var kb = Keyboard(); kb.typing = .keys
    var events = kb.press(uA)
    kb.typing = .text
    events += kb.release(uA)
    check(events == [key(uA, true, 0), key(uA, false, 0)], "A down while the Mac types, up after a switch: \(events)")
    var other = Keyboard(); other.typing = .text
    var typed = other.press(uA)
    other.typing = .keys
    typed += other.release(uA)
    check(typed == [.text("x")] && other.forwarded.down.isEmpty, "A down while iPadOS types, up after a switch: no stray up: \(typed)")
    // Shift held across a switch: its up follows its down to the Mac; a letter in between is the text system's.
    var held = Keyboard(); held.typing = .keys
    var around = held.press(uLShift)
    held.typing = .text
    around += held.press(uA) + held.release(uA) + held.release(uLShift)
    check(around == [key(uLShift, true, shift), .text("x"), key(uLShift, false, 0)], "Shift held across a switch: \(around)")
    _ = onBothMacs(events + around, "keys across a switch")
}
// ⌃Space as iPadOS's own switch between keyboards (two languages set up: TextInputRules.isKeyboardSwitch, judged
// in the overlay before `pressed`): the Space goes to iPadOS, so the Mac never hears a key go down, which on a Mac
// stops the key repeating before it (KeyRepeat). Every key down on the Mac but the modifiers' own comes up at the
// Space (ForwardedKeys.keyboardSwitch), the last pressed first, ⌃ (and ⇧) at their own releases; the keys' own
// releases later are the text system's. Before, a letter held across the switch went on repeating on the Mac, with
// control while ⌃ was down (⌃P, a line up), then plain until it came up.
extension Keyboard {
    /// The Space of ⌃Space taken by iPadOS (InputOverlayView.forward's switch): a key down the Mac never hears,
    /// and the ups the switch sends.
    mutating func iPadOSSwitch() -> [InputEvent] {
        guard !physical.contains(uSpace) else { return [] }
        physical.append(uSpace)
        time += 0.2
        return forwarded.keyboardSwitch()
    }
}
do {
    var kb = Keyboard(); kb.typing = .keys
    var events = kb.press(uP) + kb.press(uLCtrl) + kb.iPadOSSwitch()
    kb.typing = .text                                      // now Zhuyin, say
    events += kb.release(uSpace) + kb.release(uLCtrl) + kb.release(uP)
    check(events == [key(uP, true, 0), key(uLCtrl, true, control), key(uP, false, control), key(uLCtrl, false, 0)],
          "P held across iPadOS's ⌃Space: P up at the Space, ⌃ at its own release, P's release nothing: \(events)")
    check(kb.forwarded.down.isEmpty, "P held across iPadOS's ⌃Space: nothing left down")
    expect(onBothMacs(events, "P held across iPadOS's ⌃Space"),
           [.key(35, true, 0), .key(59, true, control), .key(35, false, control), .key(59, false, 0)],
           "P held across iPadOS's ⌃Space on the Mac: P's up while ⌃ is down, before any other key")
    // ⇧, P and ← held: both keys up, the last pressed first, with what the modifier keys hold; ⇧ stays down for
    // its own release.
    var two = Keyboard(); two.typing = .keys
    var held = two.press(uLShift) + two.press(uP) + two.press(uLeft) + two.press(uLCtrl) + two.iPadOSSwitch()
    held += two.release(uSpace) + two.release(uLCtrl) + two.release(uLeft) + two.release(uP) + two.release(uLShift)
    check(held == [key(uLShift, true, shift), key(uP, true, shift), key(uLeft, true, shift), key(uLCtrl, true, shift | control),
                   key(uLeft, false, shift | control), key(uP, false, shift | control), key(uLCtrl, false, shift), key(uLShift, false, 0)],
          "⇧, P and ← held across iPadOS's ⌃Space: \(held)")
    _ = onBothMacs(held, "⇧, P and ← held across iPadOS's ⌃Space")
    // An arrow held while iPadOS types the characters (it repeats on every Mac with key repeat): the same.
    var arrow = Keyboard()
    let a = arrow.press(uRight) + arrow.press(uLCtrl) + arrow.iPadOSSwitch() + arrow.release(uSpace) + arrow.release(uLCtrl)
        + arrow.release(uRight)
    check(a == [key(uRight, true, 0), key(uLCtrl, true, control), key(uRight, false, control), key(uLCtrl, false, 0)],
          "→ held across iPadOS's ⌃Space: \(a)")
    // Nothing held but ⌃: ⌃'s own keys alone, as before.
    var bare = Keyboard(); bare.typing = .keys
    let b = bare.press(uLCtrl) + bare.iPadOSSwitch() + bare.release(uSpace) + bare.release(uLCtrl)
    check(b == [key(uLCtrl, true, control), key(uLCtrl, false, 0)], "⌃Space with nothing held: \(b)")
    // A key pressed again after the switch goes down and up as any key does.
    var again = Keyboard(); again.typing = .keys
    _ = again.press(uP) + again.press(uLCtrl) + again.iPadOSSwitch() + again.release(uSpace) + again.release(uLCtrl) + again.release(uP)
    let next = again.press(uP) + again.release(uP)
    check(next == [key(uP, true, 0), key(uP, false, 0)], "P again after the switch: \(next)")
}
// Two letters held, one let go: each down and up once, the Mac repeating the last pressed (KeyRepeat).
do {
    var kb = Keyboard(); kb.typing = .keys
    let events = kb.press(uP) + kb.press(uE) + kb.release(uP) + kb.release(uE)
    check(events == [key(uP, true, 0), key(uE, true, 0), key(uP, false, 0), key(uE, false, 0)], "P and E held: \(events)")
}
// The overlay letting go (Settings, the tour) with Shift and P down: both come up, the last pressed first.
do {
    var kb = Keyboard(); kb.typing = .keys
    _ = kb.press(uLShift) + kb.press(uP)
    let ups = kb.forwarded.releaseAll()
    check(ups == [key(uP, false, shift), key(uLShift, false, 0)], "releaseAll with ⇧P down: \(ups)")
    check(kb.release(uP).isEmpty && kb.release(uLShift).isEmpty, "the releases after it: nothing")
    // Cancelled presses (the app going to the background): the same ups.
    var c = Keyboard(); c.typing = .keys
    let cancelled = c.press(uLShift) + c.press(uP) + c.cancel(uP) + c.cancel(uLShift)
    check(cancelled == [key(uLShift, true, shift), key(uP, true, shift), key(uP, false, shift), key(uLShift, false, 0)], "⇧P cancelled: \(cancelled)")
}
// A key no Sill for Mac has (the keypad's 1) stays the text system's while the Mac types.
do {
    var kb = Keyboard(); kb.typing = .keys
    check(kb.press(0x59) + kb.release(0x59) == [.text("x")], "the keypad's 1 while the Mac types: the text system's")
}
// UIKit's flags from before each change (a modifier's press not yet in its own flags): Shift's down still
// carries shift, as every modifier key's own down carries what the keys down hold.
do {
    var kb = Keyboard(); kb.typing = .keys; kb.before = true
    let events = kb.press(uLShift) + kb.press(uA) + kb.release(uA) + kb.release(uLShift)
    check(events == [key(uLShift, true, shift), key(uA, true, shift), key(uA, false, shift), key(uLShift, false, 0)],
          "⇧A with UIKit's flags from before each change: \(events)")
}

// Random sessions on this device alone: its shortcuts (latched or Spotlight), the trackpad's modified
// clicks and drags, a hardware keyboard (with presses cancelled and the overlay letting go, Return
// and Tab among its keys (⇧Return and ⇧Tab go as keys), Esc through its key command in each
// order, letters, digits, Delete, Shift and Caps Lock, typed by the Mac or by iPadOS's text system and
// the keyboard switched between the two mid-session), text and taps. This Mac keeps the invariant after
// every event; a Mac from before this fix holds no modifier whenever nothing is pressed on the device,
// and at the end; and once every key is let go nothing is down on the Mac.
do {
    var rng = Rng(state: 0xDE71_CE5E)
    var sessions = 0, oldBroken = 0, newBroken = 0, missed = 0, falseReports = 0, leftDown = 0, macTyped = 0, switched = 0, ctrlSpaceSwitches = 0, switchLeftDown = 0
    var reported: [Mac.Ignore: Int] = [:]
    for (ignore, count) in [(Mac.Ignore.nothing, 2000), (.modifierUps, 500), (.keyUps, 500)] {
    for run in 0..<count {
        var mac = Mac(), old = OldMac(); let a = Conn()
        mac.ignore = ignore
        var tripwire = Tripwire()
        var kb = Keyboard(); kb.before = rng.chance(40); kb.typing = rng.chance(50) ? .keys : .text
        if kb.typing == .keys { macTyped += 1 }
        var drag: KeyModifiers? = nil
        var overlay = true
        var oldHeld: String? = nil
        func latched() -> KeyModifiers { KeyModifiers(rawValue: rng.modifiers() & modifierBits) }
        func send(_ events: [InputEvent]) { mac.send(events, from: a); old.send(events) }
        for step in 0..<(20 + rng.below(60)) {
            defer { tripwire.step(&mac, "step \(step)") }
            switch rng.below(13) {
            case 0: send(KeyChord.press(rng.pick([uSpace, uEsc, uS, uLeft, uRight, uReturn]), with: latched()))
            case 1: send(KeyChord.spotlight)
            case 2:
                let m = latched()
                send(KeyChord.modifiersDown(m) + [.pointer(.leftDown, x: 0.5, y: 0.5), .pointer(.leftUp, x: 0.5, y: 0.5)] + KeyChord.modifiersUp(m))
            case 3:
                if let m = drag { send([.pointer(.leftUp, x: 0.2, y: 0.2)] + KeyChord.modifiersUp(m)); drag = nil }
                else { let m = latched(); send(KeyChord.modifiersDown(m) + [.pointer(.leftDown, x: 0.2, y: 0.2)]); drag = m }
            case 4, 5, 6:
                let u = rng.pick([uLCmd, uRCmd, uLCtrl, uLOpt, uLShift, uRShift, uC, uS, uP, uA, u1, uDelete, uCapsLock, uLeft,
                                  uEsc, uSpace, uReturn, 0x2B])
                // Esc, half the time through its key command, in one of the three orders.
                if u == uEsc, overlay, rng.chance(50) {
                    send(kb.esc(rng.pick([.commandOnly, .pressFirst, .commandFirst])))
                } else {
                    send(kb.press(u, seen: overlay))
                }
            case 7, 8:
                if !kb.physical.isEmpty {
                    let u = kb.physical[rng.below(kb.physical.count)]
                    send(kb.release(u, seen: overlay && (u != uEsc || kb.escSeen)))
                }
            case 9:
                if !kb.physical.isEmpty, overlay {
                    let u = kb.physical[rng.below(kb.physical.count)]
                    if u == uEsc, !kb.escSeen { kb.physical.removeAll { $0 == u } } else { send(kb.cancel(u)) }
                }
            case 10:
                // The overlay stops taking keys, or takes them again.
                if overlay { send(kb.forwarded.releaseAll()) }
                overlay.toggle()
            case 11:
                // The keyboard switched between one the Mac types and one iPadOS's text system types: by the
                // Globe key, keys down stay the way they went; by ⌃Space, iPadOS's switch (while the overlay
                // takes keys), whose Space the Mac never hears, every key down on the Mac but a modifier's own
                // comes up (ForwardedKeys.keyboardSwitch).
                if overlay, rng.chance(50), !kb.physical.contains(uSpace) {
                    let ctrl = !kb.physical.contains(uLCtrl)
                    if ctrl { send(kb.press(uLCtrl)) }
                    send(kb.iPadOSSwitch())
                    if kb.forwarded.down.contains(where: { KeyModifiers.flag(forKey: $0) == nil }) {
                        switchLeftDown += 1
                        if switchLeftDown <= 3 { print("FAIL: device run \(run): after iPadOS's ⌃Space \(kb.forwarded.down) still down") }
                    }
                    send(kb.release(uSpace))
                    if ctrl { send(kb.release(uLCtrl)) }
                    ctrlSpaceSwitches += 1
                }
                kb.typing = kb.typing == .keys ? .text : .keys
                switched += 1
            default: send([.text("y")] + tap)
            }
            if kb.physical.isEmpty, drag == nil, old.table & modifierBits != 0 {
                oldHeld = "nothing pressed, yet an older Mac holds \(names(old.table & modifierBits))"
                break
            }
        }
        if let m = drag { send([.pointer(.leftUp, x: 0.2, y: 0.2)] + KeyChord.modifiersUp(m)) }
        for u in kb.physical { send(kb.release(u, seen: overlay && (u != uEsc || kb.escSeen))) }
        if !mac.down.isEmpty || !kb.forwarded.down.isEmpty {
            leftDown += 1
            if leftDown <= 3 { print("FAIL: device run \(run): with every key let go, keys \(mac.down.keys.sorted()) are down on the Mac, \(kb.forwarded.down) forwarded") }
        }
        if oldHeld == nil, old.table & modifierBits != 0 || !old.down.filter({ macModifiers[$0.key] != nil }).isEmpty {
            oldHeld = "at the end an older Mac holds \(names(old.table & modifierBits)), down \(old.down.keys.sorted())"
        }
        if let oldHeld, ignore == .nothing {
            oldBroken += 1; if oldBroken <= 3 { print("FAIL: device run \(run): \(oldHeld)") }
        }
        mac.leave(a)
        tripwire.step(&mac, "at the end")
        if ignore == .nothing {
            mac.judge("at the end")
            if !mac.broken.isEmpty || mac.table & modifierBits != 0 {
                newBroken += 1; if newBroken <= 3 { print("FAIL: device run \(run): \(mac.broken.first ?? "the table holds \(names(mac.table))")") }
            }
        }
        if let m = tripwire.missed { missed += 1; if missed <= 3 { print("FAIL: device run \(run) on a Mac ignoring \(ignore): \(m)") } }
        if let f = tripwire.falseReport { falseReports += 1; if falseReports <= 3 { print("FAIL: device run \(run): \(f)") } }
        if tripwire.reported != 0 { reported[ignore, default: 0] += 1 }
        sessions += 1
    }
    }
    check(leftDown == 0, "device sessions: \(leftDown) of \(sessions) left a key down on the Mac once every key was let go")
    check(macTyped > 1000 && switched > 1000, "the Mac typed in \(macTyped) sessions, and keyboards switched \(switched) times")
    check(switchLeftDown == 0 && ctrlSpaceSwitches > 500,
          "iPadOS's ⌃Space: \(switchLeftDown) of \(ctrlSpaceSwitches) left a key but a modifier down on the Mac")
    check(newBroken == 0, "device sessions on this Mac: \(newBroken) of 2000 broke the invariant")
    check(oldBroken == 0, "device sessions on a Mac from before this fix: \(oldBroken) of 2000 left a modifier held")
    check(missed == 0, "device sessions on a Mac keeping its table through some ups: \(missed) of 1000 left a modifier set that no check reported")
    check(falseReports == 0 && reported[.nothing] == nil, "device sessions on a Mac as the model says: \(falseReports) reported a modifier")
    check((reported[.modifierUps] ?? 0) > 250, "this device's modifier keys' ups are checked: \(reported)")
    print("device: \(sessions) sessions (the Mac typing in \(macTyped), \(switched) keyboard switches); checks reported in \(reported[.modifierUps] ?? 0) of 500 on a Mac ignoring modifier keys' ups and \(reported[.keyUps] ?? 0) of 500 ignoring other keys' ups")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
