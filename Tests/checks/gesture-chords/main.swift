// H4 (docs/trackpad-gestures-plan.md §9.1): Sources/SillHost/GestureChords.swift on its own, the Mac's
// half of the trackpad gestures: each gesture to the Mac's own shortcut for its action (the first
// that is on and bound, its device-independent modifier bits only, never another action's), the
// reversal (the opposite gesture closes what Sill opened; the same gesture again does nothing; the
// Spaces leave a view open; other input forgets), unknown names, the log line and the TEST ONLY
// table. Then 5,000 random sequences of gestures, other input and random tables against a model
// written here from the plan, not from the file. Pure: nothing is posted anywhere.
//   swiftc -O -package-name sill Sources/SillHost/GestureChords.swift Tests/checks/gesture-chords/main.swift -o check && ./check
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

let fn: UInt64 = 0x800000, control: UInt64 = 0x040000, command: UInt64 = 0x100000, shift: UInt64 = 0x020000
let defaults = GestureChords.defaults

func chord(_ a: GestureAction, _ id: Int, _ key: UInt16, _ flags: UInt64) -> GestureOutcome { .chord(a, hotKey: id, keyCode: key, flags: flags) }
func isNothing(_ o: GestureOutcome, _ a: GestureAction?) -> Bool { if case .nothing(let x, _) = o { return x == a } else { return false } }
func reason(_ o: GestureOutcome) -> String { if case .nothing(_, let r) = o { return r } else { return "" } }
func with(_ changes: [Int: HotKey?]) -> [Int: HotKey] {
    var t = defaults
    for (id, k) in changes { t[id] = k }
    return t
}
let off = HotKey(enabled: false, keyCode: 160, modifiers: fn)

// MARK: - The default table: each gesture, fresh

let fresh: [(String, GestureOutcome, GestureAction?)] = [
    ("swipeUp", chord(.missionControl, 108, 160, fn), .missionControl),
    ("swipeDown", chord(.appExpose, 115, 160, control | fn), .appExpose),
    ("swipeLeft", chord(.nextSpace, 81, 124, control | fn), nil),
    ("swipeRight", chord(.previousSpace, 79, 123, control | fn), nil),
    ("pinch", chord(.apps, 173, 131, fn), .apps),
    ("spread", chord(.showDesktop, 36, 103, fn), .showDesktop),
]
for (g, want, open) in fresh {
    var c = GestureChords()
    let got = c.resolve(g, table: defaults)
    check("\(g) on the default table → \(want)", got == want)
    check("\(g) leaves open \(open.map { "\($0)" } ?? "nothing")", c.open == open)
}

// MARK: - The preference order and what is not on

func first(_ g: String, _ table: [Int: HotKey]) -> GestureOutcome { var c = GestureChords(); return c.resolve(g, table: table) }
check("108 off: Mission Control through 32 (⌃↑)", first("swipeUp", with([108: off])) == chord(.missionControl, 32, 126, control | fn))
check("108 on but unbound: through 32", first("swipeUp", with([108: HotKey(enabled: true, keyCode: HotKey.unbound, modifiers: fn)])) == chord(.missionControl, 32, 126, control | fn))
check("108 missing from the table: through 32", first("swipeUp", with([108: nil])) == chord(.missionControl, 32, 126, control | fn))
check("108 and 32 off: nothing, and never App Exposé's 115", isNothing(first("swipeUp", with([108: off, 32: off])), .missionControl))
check("its reason names the setting", reason(first("swipeUp", with([108: off, 32: off]))) == "no shortcut for Mission Control is on in Keyboard Shortcuts")
check("115 off: App Exposé through 33 (⌃↓)", first("swipeDown", with([115: off])) == chord(.appExpose, 33, 125, control | fn))
check("115 and 33 off: nothing (Application windows)", reason(first("swipeDown", with([115: off, 33: off]))) == "no shortcut for Application windows is on in Keyboard Shortcuts")
check("81 off: nothing, never 79's ⌃←", isNothing(first("swipeLeft", with([81: off])), .nextSpace))
check("79 off: nothing, never 81's ⌃→", isNothing(first("swipeRight", with([79: off])), .previousSpace))
check("81 off: the reason says Move right a space", reason(first("swipeLeft", with([81: off]))) == "no shortcut for Move right a space is on in Keyboard Shortcuts")
check("173 off, 160 off (as macOS ships 160): nothing", reason(first("pinch", with([173: off]))) == "no shortcut for Show Apps is on in Keyboard Shortcuts")
check("173 off, 160 set to ⌘⇧A: Apps through 160", first("pinch", with([173: off, 160: HotKey(enabled: true, keyCode: 0, modifiers: command | shift)])) == chord(.apps, 160, 0, command | shift))
check("160 set but 173 on: still 173 first", first("pinch", with([160: HotKey(enabled: true, keyCode: 0, modifiers: command | shift)])) == chord(.apps, 173, 131, fn))
check("36 off: Show Desktop through 110 (⌘ and the Mission Control key)", first("spread", with([36: off])) == chord(.showDesktop, 110, 160, command | fn))
check("36 and 110 off: nothing", isNothing(first("spread", with([36: off, 110: off])), .showDesktop))
var allOff: [Int: HotKey] = [:]
for id in GestureChords.hotKeyIDs { allOff[id] = off }
for g in ["swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread"] {
    check("everything off: \(g) posts nothing", { if case .nothing = first(g, allOff) { return true } else { return false } }())
}
check("an empty table (nothing read): nothing", isNothing(first("swipeUp", [:]), .missionControl))

// MARK: - A rebound shortcut: its key, its device-independent bits only

check("32 rebound to ⌘⇧1 with 108 off: exactly that", first("swipeUp", with([108: off, 32: HotKey(enabled: true, keyCode: 18, modifiers: command | shift)])) == chord(.missionControl, 32, 18, command | shift))
check("bits outside 16–23 dropped", first("swipeUp", with([108: HotKey(enabled: true, keyCode: 160, modifiers: 0x1_0000_0000 | fn | 0x100 | 0x2000_0000)])) == chord(.missionControl, 108, 160, fn))
check("the numeric-pad bit (21) kept, as stored", first("swipeLeft", with([81: HotKey(enabled: true, keyCode: 124, modifiers: control | fn | 0x200000)])) == chord(.nextSpace, 81, 124, control | fn | 0x200000))
check("no modifiers: flags 0", first("spread", with([36: HotKey(enabled: true, keyCode: 103, modifiers: 0)])) == chord(.showDesktop, 36, 103, 0))
check("caps lock and option kept", first("pinch", with([173: HotKey(enabled: true, keyCode: 131, modifiers: 0x010000 | 0x080000)])) == chord(.apps, 173, 131, 0x090000))
check("deviceIndependentBits is 16–23", GestureChords.deviceIndependentBits == 0xFF_0000)

// MARK: - The reversal

func run(_ steps: [String], _ table: [Int: HotKey] = defaults) -> (GestureChords, [GestureOutcome]) {
    var c = GestureChords()
    var out: [GestureOutcome] = []
    for s in steps {
        if s == "other" { c.otherInput() } else { out.append(c.resolve(s, table: table)) }
    }
    return (c, out)
}
var r = run(["swipeUp", "swipeDown"])
check("up then down: the down closes Mission Control with its own shortcut", r.1[1] == chord(.missionControl, 108, 160, fn))
check("up then down: nothing open after", r.0.open == nil)
r = run(["swipeDown", "swipeUp"])
check("down then up: the up closes App Exposé", r.1[1] == chord(.appExpose, 115, 160, control | fn))
check("down then up: nothing open after", r.0.open == nil)
r = run(["pinch", "spread"])
check("pinch then spread: the spread closes Apps", r.1[1] == chord(.apps, 173, 131, fn))
check("pinch then spread: nothing open after", r.0.open == nil)
r = run(["spread", "pinch"])
check("spread then pinch: the pinch brings the windows back (Show Desktop again)", r.1[1] == chord(.showDesktop, 36, 103, fn))
check("spread then pinch: nothing open after", r.0.open == nil)
r = run(["swipeUp", "swipeDown", "swipeDown"])
check("up, down, down: the second down is App Exposé", r.1[2] == chord(.appExpose, 115, 160, control | fn) && r.0.open == .appExpose)
for (g, a) in [("swipeUp", GestureAction.missionControl), ("swipeDown", .appExpose), ("pinch", .apps), ("spread", .showDesktop)] {
    r = run([g, g])
    check("\(g) twice: the second posts nothing", isNothing(r.1[1], a) && reason(r.1[1]) == "\(a.title) is already open")
    check("\(g) twice: still open", r.0.open == a)
}
r = run(["swipeUp", "swipeLeft", "swipeRight"])
check("up, left: the Space's own shortcut", r.1[1] == chord(.nextSpace, 81, 124, control | fn))
check("up, left, right: Mission Control stays open", r.1[2] == chord(.previousSpace, 79, 123, control | fn) && r.0.open == .missionControl)
r = run(["swipeUp", "swipeLeft", "swipeRight", "swipeDown"])
check("up, left, right, down: the down still closes Mission Control", r.1[3] == chord(.missionControl, 108, 160, fn) && r.0.open == nil)
r = run(["swipeUp", "pinch"])
check("up then pinch: Apps, which is now the open view", r.1[1] == chord(.apps, 173, 131, fn) && r.0.open == .apps)
r = run(["swipeUp", "pinch", "spread"])
check("up, pinch, spread: the spread closes Apps", r.1[2] == chord(.apps, 173, 131, fn) && r.0.open == nil)
r = run(["swipeUp", "spread"])
check("up then spread: Show Desktop, now open", r.1[1] == chord(.showDesktop, 36, 103, fn) && r.0.open == .showDesktop)
r = run(["swipeUp", "other", "swipeDown"])
check("up, other input, down: App Exposé, not a close", r.1[1] == chord(.appExpose, 115, 160, control | fn) && r.0.open == .appExpose)
r = run(["pinch", "other", "pinch"])
check("pinch, other input, pinch: Apps again", r.1[1] == chord(.apps, 173, 131, fn))
r = run(["other"])
check("other input with nothing open", r.0.open == nil)
// A view's shortcut turned off while it is open: the close posts nothing and it stays open.
var c = GestureChords()
_ = c.resolve("swipeUp", table: defaults)
let closeOff = c.resolve("swipeDown", table: with([108: off, 32: off]))
check("the close with Mission Control's shortcuts off posts nothing", isNothing(closeOff, .missionControl))
check("and Mission Control still counts as open", c.open == .missionControl)
check("a later close, the shortcut back on, closes it", c.resolve("swipeDown", table: defaults) == chord(.missionControl, 108, 160, fn) && c.open == nil)
// A view that could not open is not remembered.
c = GestureChords()
_ = c.resolve("pinch", table: with([173: off]))
check("Apps with no shortcut is not remembered as open", c.open == nil)
check("so the spread after it is Show Desktop", c.resolve("spread", table: defaults) == chord(.showDesktop, 36, 103, fn))

// MARK: - Names this Mac does not know

for bad in ["rotate", "", "SwipeUp", "swipe up", "swipeUp "] {
    var x = GestureChords()
    _ = x.resolve("swipeUp", table: defaults)
    let o = x.resolve(bad, table: defaults)
    check("\(bad.debugDescription): nothing, no action, Mission Control still open", isNothing(o, nil) && x.open == .missionControl)
}
check("action(for:): the six", ["swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread"].map { GestureChords.action(for: $0) }
      == [.missionControl, .appExpose, .nextSpace, .previousSpace, .apps, .showDesktop])
check("hotKeyIDs are every preferred id, once", Set(GestureChords.hotKeyIDs) == Set(GestureChords.preference.values.flatMap { $0 })
      && GestureChords.hotKeyIDs.count == Set(GestureChords.hotKeyIDs).count)
check("defaults hold every id", Set(defaults.keys) == Set(GestureChords.hotKeyIDs))
check("the preference lists, as the plan's §3 table", GestureChords.preference[.missionControl] == [108, 32] && GestureChords.preference[.appExpose] == [115, 33]
      && GestureChords.preference[.nextSpace] == [81] && GestureChords.preference[.previousSpace] == [79]
      && GestureChords.preference[.apps] == [173, 160] && GestureChords.preference[.showDesktop] == [36, 110])
check("isView: all but the Spaces", GestureAction.allCases.filter(\.isView) == [.missionControl, .appExpose, .apps, .showDesktop])

// MARK: - The log line

let dev = "iPad (iPad14,1)"
check("the line for a swipe up", GestureChords.line(device: dev, gesture: "swipeUp", fingers: 3, outcome: chord(.missionControl, 108, 160, fn), dryRun: false)
      == "Gesture from iPad (iPad14,1): swipe up → Mission Control (shortcut 108: key 160, fn)")
check("a swipe down that closes Mission Control", GestureChords.line(device: dev, gesture: "swipeDown", fingers: 3, outcome: chord(.missionControl, 108, 160, fn), dryRun: false)
      == "Gesture from iPad (iPad14,1): swipe down → closes Mission Control (shortcut 108: key 160, fn)")
check("a test host says it posted nothing", GestureChords.line(device: dev, gesture: "swipeUp", fingers: 3, outcome: chord(.missionControl, 108, 160, fn), dryRun: true)
      == "Gesture from iPad (iPad14,1): swipe up → Mission Control (shortcut 108: key 160, fn) (not posted: a test host)")
check("nothing, with its reason", GestureChords.line(device: dev, gesture: "pinch", fingers: 3, outcome: .nothing(.apps, reason: "no shortcut for Show Apps is on in Keyboard Shortcuts"), dryRun: true)
      == "Gesture from iPad (iPad14,1): pinch → nothing: no shortcut for Show Apps is on in Keyboard Shortcuts")
check("four fingers are named", GestureChords.line(device: dev, gesture: "swipeLeft", fingers: 4, outcome: chord(.nextSpace, 81, 124, control | fn), dryRun: false)
      == "Gesture from iPad (iPad14,1): swipe left, four fingers → the Space on the right (shortcut 81: key 124, control + fn)")
check("a Space's line never says closes", GestureChords.line(device: dev, gesture: "swipeRight", fingers: nil, outcome: chord(.previousSpace, 79, 123, control | fn), dryRun: false)
      == "Gesture from iPad (iPad14,1): swipe right → the Space on the left (shortcut 79: key 123, control + fn)")
check("an unknown name keeps only letters and digits, at most 32", GestureChords.line(device: dev, gesture: "ro\ntate!💥\u{202E}" + String(repeating: "x", count: 40), fingers: 3, outcome: .nothing(nil, reason: "not a gesture this Mac knows"), dryRun: false)
      == "Gesture from iPad (iPad14,1): \"rotate" + String(repeating: "x", count: 26) + "\" → nothing: not a gesture this Mac knows")
check("describe: no modifier", GestureChords.describe(keyCode: 103, flags: 0) == "key 103")
check("describe: command + fn", GestureChords.describe(keyCode: 160, flags: command | fn) == "key 160, command + fn")
check("describe: every modifier in the Mac's order", GestureChords.describe(keyCode: 1, flags: 0xFF0000) == "key 1, caps lock + control + option + shift + command + fn")

// MARK: - The TEST ONLY table

check("testTable(defaults) is the defaults", GestureChords.testTable("defaults") == defaults)
check("testTable: 108=off turns it off", GestureChords.testTable("108=off")?[108]?.enabled == false && GestureChords.testTable("108=off")?[32] == defaults[32])
check("testTable: two entries", { let t = GestureChords.testTable("36=off, 110=off"); return t?[36]?.enabled == false && t?[110]?.enabled == false }())
check("testTable: a rebinding in hex", GestureChords.testTable("32=18:0x120000")?[32] == HotKey(enabled: true, keyCode: 18, modifiers: 0x120000))
check("testTable: a rebinding in decimal", GestureChords.testTable("160=0:1179648")?[160] == HotKey(enabled: true, keyCode: 0, modifiers: 0x120000))
for bad in ["", "108", "x=off", "108=18", "108=a:1", "108=1:zz", "108=off,,", "-1=off", "108=off=1"] {
    check("testTable refuses \(bad.debugDescription)", GestureChords.testTable(bad) == nil)
}

// MARK: - 5,000 random sequences against a model

/// The model: the plan's §7.1 and §7.2 written again, with its own tables.
struct Model {
    static let prefs: [String: [Int]] = ["missionControl": [108, 32], "appExpose": [115, 33], "nextSpace": [81], "previousSpace": [79],
                                         "apps": [173, 160], "showDesktop": [36, 110]]
    static let base: [String: String] = ["swipeUp": "missionControl", "swipeDown": "appExpose", "swipeLeft": "nextSpace",
                                         "swipeRight": "previousSpace", "pinch": "apps", "spread": "showDesktop"]
    static let closer: [String: String] = ["missionControl": "swipeDown", "appExpose": "swipeUp", "apps": "spread", "showDesktop": "pinch"]
    var open: String?
    /// (action, id, key, flags) or (action?, nil…) for nothing.
    func pick(_ action: String, _ table: [Int: HotKey]) -> (String?, Int?, UInt16, UInt64) {
        for id in Model.prefs[action]! {
            if let k = table[id], k.enabled, k.keyCode != 0xFFFF { return (action, id, k.keyCode, k.modifiers & 0xFF0000) }
        }
        return (action, nil, 0, 0)
    }
    mutating func step(_ g: String, _ table: [Int: HotKey]) -> (String?, Int?, UInt16, UInt64) {
        guard let b = Model.base[g] else { return (nil, nil, 0, 0) }
        if let o = open, Model.closer[o] == g {
            let p = pick(o, table)
            if p.1 != nil { open = nil }
            return p
        }
        if open == b { return (b, nil, 0, 0) }
        let p = pick(b, table)
        if p.1 != nil, b != "nextSpace", b != "previousSpace" { open = b }
        return p
    }
}
func flatten(_ o: GestureOutcome) -> (String?, Int?, UInt16, UInt64) {
    switch o {
    case .chord(let a, let id, let k, let f): return (a.rawValue, id, k, f)
    case .nothing(let a, _): return (a?.rawValue, nil, 0, 0)
    }
}
var seed: UInt64 = 0x5EED_6E57
func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 17 }
func randomTable() -> [Int: HotKey] {
    var t: [Int: HotKey] = [:]
    for id in GestureChords.hotKeyIDs {
        switch next() % 6 {
        case 0: continue                                                          // not read
        case 1: t[id] = HotKey(enabled: false, keyCode: UInt16(next() % 200), modifiers: next() & 0xFFFF_FFFF)
        case 2: t[id] = HotKey(enabled: true, keyCode: HotKey.unbound, modifiers: next() & 0xFFFF_FFFF)
        case 3: t[id] = HotKey(enabled: true, keyCode: UInt16(next() % 200), modifiers: next() & 0xFFFF_FFFF)
        default: t[id] = defaults[id]
        }
    }
    return t
}
let names = ["swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread", "rotate", "other"]
var randomFailures = 0, steps = 0, chords = 0, reversals = 0
for _ in 0..<5_000 {
    var real = GestureChords()
    var model = Model()
    var table = randomTable()
    for _ in 0..<Int(1 + next() % 30) {
        if next() % 7 == 0 { table = randomTable() }
        let g = names[Int(next() % UInt64(names.count))]
        steps += 1
        if g == "other" {
            real.otherInput(); model.open = nil
        } else {
            let before = model.open
            let want = model.step(g, table)
            let got = flatten(real.resolve(g, table: table))
            if got.1 != nil { chords += 1 }
            if let b = before, Model.closer[b] == g { reversals += 1 }
            if got.0 != want.0 || got.1 != want.1 || got.2 != want.2 || got.3 != want.3 {
                randomFailures += 1
                if randomFailures <= 5 { print("  random: \(g) with open \(before ?? "nil"): got \(got), want \(want)") }
            }
        }
        if real.open?.rawValue != model.open {
            randomFailures += 1
            if randomFailures <= 5 { print("  random: after \(g) open is \(real.open.map { "\($0)" } ?? "nil"), model \(model.open ?? "nil")") }
        }
    }
}
check("5,000 random sequences (\(steps) steps, \(chords) chords, \(reversals) closes): outcome and open as the model", randomFailures == 0)

print("\(passes + fails) checks, \(fails) failed")
exit(fails == 0 ? 0 : 1)
