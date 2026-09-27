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

/// The Mac's modifier keycodes (Carbon kVK_*) and the flag each holds: the model's own table.
let macModifiers: [UInt16: UInt64] = [55: command, 54: command, 56: shift, 60: shift,
                                      58: option, 61: option, 59: control, 62: control]

func names(_ flags: UInt64) -> String {
    let named: [(UInt64, String)] = [(capsLock, "caps lock"), (control, "control"), (option, "option"),
                                     (shift, "shift"), (command, "command")]
    var held = named.filter { flags & $0.0 != 0 }.map(\.1)
    let rest = flags & ~(capsLock | modifierBits)
    if rest != 0 { held.append("0x" + String(rest, radix: 16)) }
    return held.isEmpty ? "none" : held.joined(separator: " + ")
}

/// A device's connection: its ObjectIdentifier is the device KeyStrokes keeps keys for.
final class Conn {}

// HID usages the device sends, and the Mac's keycodes for them.
let uSpace: UInt16 = 0x2C, uEsc: UInt16 = 0x29, uS: UInt16 = 0x16, uC: UInt16 = 0x06
let uLeft: UInt16 = 0x50, uRight: UInt16 = 0x4F, uReturn: UInt16 = 0x28
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

    /// The modifiers the keys down on the Mac account for: a modifier key its own flag, any other key
    /// the flags its down carried.
    var accounted: UInt64 { down.reduce(0) { $0 | (macModifiers[$1.key] ?? $1.value) } }

    mutating func post(_ s: KeyStroke) {
        log.append(.key(s.virtualKey, s.down, s.flags))
        table = s.flags
        if s.down { down[s.virtualKey] = s.flags } else { down[s.virtualKey] = nil }
        judge("after \(log.last!)")
    }
    mutating func judge(_ when: String) {
        let stray = table & modifierBits & ~accounted
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
            for _ in string { log.append(.text); table = 0 }
            judge("after text")
        case .pointer, .scroll, .scrollGesture:
            log.append(.pointer(table))
            let stray = table & modifierBits & ~accounted
            if stray != 0 { broken.append("a pointer event carries \(names(stray)), which no key down accounts for") }
        }
    }
    mutating func send(_ events: [InputEvent], from c: Conn) { for e in events { input(e, from: c) } }
    mutating func leave(_ c: Conn) { for s in keys.release(ObjectIdentifier(c)) { post(s) } }
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

var rng = Rng(state: 0x5111_5EED)
var runs = 0, events = 0, brokenRuns = 0
let hardwareKeys: [UInt16] = [0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE7, uC, uS, uLeft, uEsc]
for run in 0..<3000 {
    var mac = Mac()
    var devices = [Device(), Device()]
    for i in devices.indices { devices[i].keyboard.before = rng.chance(30) }
    let steps = 20 + rng.below(60)
    for _ in 0..<steps {
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
    }
    // The session ends: the host quits (its keys all let go first), or every device leaves.
    if rng.chance(30) { for s in mac.keys.releaseAll() { mac.post(s) } }
    for d in devices {
        for old in d.lingering { mac.leave(old.conn) }
        mac.leave(d.conn)
    }
    mac.judge("once every device left")
    if !mac.down.isEmpty { mac.broken.append("once every device left, keys \(mac.down.keys.sorted()) are still down") }
    runs += 1; events += mac.log.count
    if !mac.broken.isEmpty {
        brokenRuns += 1
        if brokenRuns <= 3 { print("FAIL: random run \(run): \(mac.broken.first!) (and \(mac.broken.count - 1) more)") }
    }
}
check(brokenRuns == 0, "random sessions: \(brokenRuns) of \(runs) broke the invariant")
print("random: \(runs) sessions, \(events) events posted")

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
        case .pointer, .scroll, .scrollGesture: log.append(.pointer(table))
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

// MARK: The device's hardware keyboard (ForwardedKeys)

/// A hardware keyboard on this device and what UIKit tells InputOverlayView: the modifiers held after
/// each change, or, `before`, from before it (so a modifier's release still carries its own flag and
/// its press does not yet).
struct Keyboard {
    var physical: [UInt16] = []
    var before = false
    var forwarded = ForwardedKeys()
    var flags: UInt64 { physical.reduce(0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) } }
    /// A key pressed: its down if it goes to the Mac as a key, else a character typed (the text
    /// system; a modifier alone types nothing). Unseen (the overlay not taking keys), nothing.
    mutating func press(_ u: UInt16, seen: Bool = true) -> [InputEvent] {
        guard !physical.contains(u) else { return [] }
        let was = flags
        physical.append(u)
        guard seen else { return [] }
        if let e = forwarded.began(u, modifiers: before ? was : flags) { return [e] }
        return KeyModifiers.flag(forKey: u) == nil ? [.text("x")] : []
    }
    mutating func release(_ u: UInt16, seen: Bool = true) -> [InputEvent] {
        guard let i = physical.firstIndex(of: u) else { return [] }
        let was = flags
        physical.remove(at: i)
        guard seen else { return [] }
        _ = was   // UIKit's flags at a release: the up carries the modifier keys down on the Mac instead
        return forwarded.ended(u).map { [$0] } ?? []
    }
    /// A press cancelled: the same up.
    mutating func cancel(_ u: UInt16) -> [InputEvent] {
        guard let i = physical.firstIndex(of: u) else { return [] }
        physical.remove(at: i)
        return forwarded.ended(u).map { [$0] } ?? []
    }
}

// Which keys go to the Mac as keys: the ones the text system never delivers, ⌘, ⌃ and ⌥ themselves,
// and any key while ⌘, ⌃ or ⌥ is held; shift alone makes characters.
check([uLeft, uRight, 0x51, 0x52, uEsc, 0x4C, 0x4A, 0x4D, 0x4B, 0x4E, 0x3A, 0x45, uLCmd, uRCmd, uLCtrl, uRCtrl, uLOpt, uROpt]
        .allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: 0) },
      "arrows, escape, forward delete, home, end, page up and down, F1 and F12, ⌘, ⌃, ⌥: as keys")
check(![uS, uSpace, uReturn, 0x2A, 0x2B, uLShift, uRShift, 0x39].contains { ForwardedKeys.goesAsKey($0, modifiers: shift | capsLock) },
      "letters, space, return, delete, tab, shift and caps lock with shift: to the text system")
check([uS, uSpace, uReturn, uLShift].allSatisfy { ForwardedKeys.goesAsKey($0, modifiers: command) && ForwardedKeys.goesAsKey($0, modifiers: option)
                                                  && ForwardedKeys.goesAsKey($0, modifiers: control) },
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

// Random sessions on this device alone: its shortcuts (latched or Spotlight), the trackpad's modified
// clicks and drags, a hardware keyboard (with presses cancelled and the overlay letting go), text
// and taps. This Mac keeps the invariant after every event; a Mac from before this fix holds no
// modifier whenever nothing is pressed on the device, and at the end.
do {
    var rng = Rng(state: 0xDE71_CE5E)
    var sessions = 0, oldBroken = 0, newBroken = 0
    for run in 0..<2000 {
        var mac = Mac(), old = OldMac(); let a = Conn()
        var kb = Keyboard(); kb.before = rng.chance(40)
        var drag: KeyModifiers? = nil
        var overlay = true
        var oldHeld: String? = nil
        func latched() -> KeyModifiers { KeyModifiers(rawValue: rng.modifiers() & modifierBits) }
        func send(_ events: [InputEvent]) { mac.send(events, from: a); old.send(events) }
        for _ in 0..<(20 + rng.below(60)) {
            switch rng.below(12) {
            case 0: send(KeyChord.press(rng.pick([uSpace, uEsc, uS, uLeft, uRight, uReturn]), with: latched()))
            case 1: send(KeyChord.spotlight)
            case 2:
                let m = latched()
                send(KeyChord.modifiersDown(m) + [.pointer(.leftDown, x: 0.5, y: 0.5), .pointer(.leftUp, x: 0.5, y: 0.5)] + KeyChord.modifiersUp(m))
            case 3:
                if let m = drag { send([.pointer(.leftUp, x: 0.2, y: 0.2)] + KeyChord.modifiersUp(m)); drag = nil }
                else { let m = latched(); send(KeyChord.modifiersDown(m) + [.pointer(.leftDown, x: 0.2, y: 0.2)]); drag = m }
            case 4, 5, 6:
                send(kb.press(rng.pick([uLCmd, uRCmd, uLCtrl, uLOpt, uLShift, uC, uS, uLeft, uEsc, uSpace]), seen: overlay))
            case 7, 8:
                if !kb.physical.isEmpty { send(kb.release(kb.physical[rng.below(kb.physical.count)], seen: overlay)) }
            case 9:
                if !kb.physical.isEmpty, overlay { send(kb.cancel(kb.physical[rng.below(kb.physical.count)])) }
            case 10:
                // The overlay stops taking keys, or takes them again.
                if overlay { send(kb.forwarded.releaseAll()) }
                overlay.toggle()
            default: send([.text("y")] + tap)
            }
            if kb.physical.isEmpty, drag == nil, old.table & modifierBits != 0 {
                oldHeld = "nothing pressed, yet an older Mac holds \(names(old.table & modifierBits))"
                break
            }
        }
        if let m = drag { send([.pointer(.leftUp, x: 0.2, y: 0.2)] + KeyChord.modifiersUp(m)) }
        for u in kb.physical { send(kb.release(u, seen: overlay)) }
        if oldHeld == nil, old.table & modifierBits != 0 || !old.down.filter({ macModifiers[$0.key] != nil }).isEmpty {
            oldHeld = "at the end an older Mac holds \(names(old.table & modifierBits)), down \(old.down.keys.sorted())"
        }
        if let oldHeld {
            oldBroken += 1; if oldBroken <= 3 { print("FAIL: device run \(run): \(oldHeld)") }
        }
        mac.leave(a)
        mac.judge("at the end")
        if !mac.broken.isEmpty || mac.table & modifierBits != 0 {
            newBroken += 1; if newBroken <= 3 { print("FAIL: device run \(run): \(mac.broken.first ?? "the table holds \(names(mac.table))")") }
        }
        sessions += 1
    }
    check(newBroken == 0, "device sessions on this Mac: \(newBroken) of \(sessions) broke the invariant")
    check(oldBroken == 0, "device sessions on a Mac from before this fix: \(oldBroken) of \(sessions) left a modifier held")
    print("device: \(sessions) sessions")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
