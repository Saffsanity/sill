// Sources/SillHost/ConsoleSession.swift on its own (issue #211):
//
//   swiftc -O Sources/SillHost/ConsoleSession.swift Tests/checks/console-session/main.swift \
//     -o .build/checks/console-session/check && .build/checks/console-session/check
//
// What it checks: the witness read from a session dictionary (the key's name, a CF boolean as
// CGSessionCopyCurrentDictionary gives it, numbers, no dictionary and no key saying nothing); kind
// 16's field (nil on the console, false off it); what a look changes and the line it prints, and
// a random model of looks (5,000 runs: the state is the last read that said anything, true before
// any; one line per change, alternating; the wire false exactly while off the console); the two
// lines' words; the TEST ONLY hook (a synthetic host only, its lines) and what its file says.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

// MARK: The witness

let key = "kCGSSessionOnConsoleKey"
eq(ConsoleSession.onConsoleKey, key, "the key, as this Mac's session dictionary has it")
let cfTrue = NSDictionary(dictionary: [key: kCFBooleanTrue!, "kCGSessionLoginDoneKey": kCFBooleanTrue!]) as? [String: Any]
let cfFalse = NSDictionary(dictionary: [key: kCFBooleanFalse!, "kCGSessionLoginDoneKey": kCFBooleanTrue!]) as? [String: Any]
eq(ConsoleSession.onConsole(dictionary: cfTrue), true, "a CF boolean true (CGSessionCopyCurrentDictionary's): on the console")
eq(ConsoleSession.onConsole(dictionary: cfFalse), false, "…false: off it")
eq(ConsoleSession.onConsole(dictionary: [key: NSNumber(value: 1)]), true, "a number 1: on")
eq(ConsoleSession.onConsole(dictionary: [key: NSNumber(value: 0)]), false, "a number 0: off")
eq(ConsoleSession.onConsole(dictionary: nil), nil, "no dictionary (no GUI session: a CLI over ssh): says nothing")
eq(ConsoleSession.onConsole(dictionary: [:]), nil, "no key: says nothing")
eq(ConsoleSession.onConsole(dictionary: ["kCGSessionOnConsoleKey": kCFBooleanFalse!]), nil, "another spelling of the key: says nothing")
eq(ConsoleSession.onConsole(dictionary: [key: "0"]), nil, "a string: says nothing")

// MARK: Kind 16's field

eq(ConsoleSession.wire(onConsole: true), nil, "on the console: no field, so the state is what it always was")
eq(ConsoleSession.wire(onConsole: false), false, "off it: false")

// MARK: A look

eq(ConsoleSession.next(current: true, read: nil)?.onConsole, nil, "on, a read that says nothing: no change")
eq(ConsoleSession.next(current: true, read: true)?.onConsole, nil, "on, read on: no change")
eq(ConsoleSession.next(current: true, read: false)?.onConsole, false, "on, read off: off")
eq(ConsoleSession.next(current: true, read: false)?.line, ConsoleSession.awayLine, "…with the away line")
eq(ConsoleSession.next(current: false, read: false)?.onConsole, nil, "off, read off: no change, no second line")
eq(ConsoleSession.next(current: false, read: nil)?.onConsole, nil, "off, a read that says nothing: still off")
eq(ConsoleSession.next(current: false, read: true)?.onConsole, true, "off, read on: back")
eq(ConsoleSession.next(current: false, read: true)?.line, ConsoleSession.backLine, "…with the back line")
eq(ConsoleSession.awayLine,
   "Console: another user's session, or the login window, has this Mac's screen; macOS drops the taps and keys devices send until it switches back to this one. Devices stay connected.",
   "the away line's words")
eq(ConsoleSession.backLine, "Console: this user's session has the screen again; devices' taps and keys reach it.", "the back line's words")
eq(ConsoleSession.lookInterval, 1.0, "a look every second while a device is connected")
eq(ConsoleSession.offConsoleInputKey, "in.offConsole", "the [1s] lines' key for input off the console")

// MARK: A model of looks

do {
    var seed: UInt64 = 0x5111_0211
    func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
    var bad = 0, runs = 0, changes = 0
    for _ in 0..<5_000 {
        runs += 1
        var state = true
        var lastSaid: Bool? = nil
        var lines: [String] = []
        var said = 0
        let n = Int(next() % 40)
        for _ in 0..<n {
            let r: Bool? = [true, false, nil][Int(next() % 3)]
            if let r { if r != (lastSaid ?? true) { said += 1 }; lastSaid = r }
            if let c = ConsoleSession.next(current: state, read: r) { state = c.onConsole; lines.append(c.line) }
        }
        changes += lines.count
        let want = lastSaid ?? true
        var ok = state == want && lines.count == said
        ok = ok && ConsoleSession.wire(onConsole: state) == (want ? nil : false)
        for (i, l) in lines.enumerated() { ok = ok && l == (i % 2 == 0 ? ConsoleSession.awayLine : ConsoleSession.backLine) }
        if !ok { bad += 1 }
    }
    check(bad == 0, "\(runs) random runs of looks: the state is the last read that said anything (true before any), one line per change, away and back in turn, the wire false exactly while off (\(changes) changes, \(bad) wrong)")
}

// MARK: TEST ONLY: SILL_TEST_CONSOLE_FILE

let none = ConsoleSession.testHook(synthetic: true, environment: [:])
check(none.path == nil && none.line == nil, "no variable: no file, no line")
let empty = ConsoleSession.testHook(synthetic: true, environment: ["SILL_TEST_CONSOLE_FILE": ""])
check(empty.path == nil && empty.line == nil, "an empty variable: none")
let real = ConsoleSession.testHook(synthetic: false, environment: ["SILL_TEST_CONSOLE_FILE": "/tmp/c"])
eq(real.path, nil, "a host that is not --synthetic: never takes it")
eq(real.line, "SILL_TEST_CONSOLE_FILE ignored: only a --synthetic host takes it.", "…and says so once")
let test = ConsoleSession.testHook(synthetic: true, environment: ["SILL_TEST_CONSOLE_FILE": "/tmp/c"])
eq(test.path, "/tmp/c", "a --synthetic host reads the file")
eq(test.line, "Test console: read from /tmp/c (\"off\": another user's session has the screen), never this Mac's session.", "…and says so")
eq(ConsoleSession.testRead(contents: nil), true, "no file: on the console")
eq(ConsoleSession.testRead(contents: ""), true, "an empty file: on")
eq(ConsoleSession.testRead(contents: "on\n"), true, "\"on\": on")
eq(ConsoleSession.testRead(contents: "off"), false, "\"off\": off")
eq(ConsoleSession.testRead(contents: "off\n"), false, "\"off\" with a newline (echo's): off")
eq(ConsoleSession.testRead(contents: "  off \n"), false, "…and with spaces around it")
eq(ConsoleSession.testRead(contents: "offline"), true, "another word: on")

print(failures == 0 ? "console-session: all passed" : "console-session: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
