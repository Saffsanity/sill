import Foundation

// KeycodeTyping and HangulRun (Sources/SillHost/KeycodeTyping.swift): the keys an app that reads only
// a key event's virtual key (Parallels Desktop's VM windows) is sent for a device's text, where every
// character used to reach the guest as key 0, the A key ("aaaa", "ㅁㅁㅁㅁ"; 2026-11-26).
//
// Against a model of the guest's 2-set Korean input method: it holds committed characters' keys and the
// keys of the one it is composing (the last); a key adds to the composing one, a backspace deletes one
// key of the composing one, or a whole committed character. What the guest shows, as keys per
// character, must be the device's text after each event, as the device's Korean keyboard sends it.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias S = KeycodeTyping.Stroke

// A US keyboard.
check(KeycodeTyping.strokes(for: "a") == [S(key: 0, shift: false)], "a is the A key")
check(KeycodeTyping.strokes(for: "A") == [S(key: 0, shift: true)], "A is shift and the A key")
check(KeycodeTyping.strokes(for: " ") == [S(key: 49, shift: false)], "space")
check(KeycodeTyping.strokes(for: "!") == [S(key: 18, shift: true)], "! is shift 1")
check(KeycodeTyping.strokes(for: "?") == [S(key: 44, shift: true)], "? is shift /")
check(KeycodeTyping.strokes(for: "z") == [S(key: 6, shift: false)], "z")
check(KeycodeTyping.strokes(for: "5") == [S(key: 23, shift: false)], "5")
check(KeycodeTyping.strokes(for: "あ") == nil && KeycodeTyping.strokes(for: "😀") == nil, "no key types kana or an emoji")
var keysSeen = Set<UInt16>()
for scalar in 0x21...0x7E { let c = Character(UnicodeScalar(scalar)!); if let s = KeycodeTyping.strokes(for: c) { keysSeen.insert(s[0].key) } else { check(false, "printable ASCII \(c) has a key") } }
check(keysSeen.count == 47, "47 keys type printable ASCII, \(keysSeen.count)")

// The 2-set layout.
for (c, keys) in [("한", "gks"), ("글", "rmf"), ("닭", "ekfr"), ("과", "rhk"), ("뷁", "qnpfr"), ("ㅁ", "a"),
                  ("까", "Rk"), ("의", "dml"), ("값", "rkqt"), ("ㅘ", "hk"), ("힣", "glg"), ("가", "rk")] as [(Character, String)] {
    check(KeycodeTyping.hangulKeys(c) == keys, "\(c) is \(keys), not \(KeycodeTyping.hangulKeys(c) ?? "nil")")
}
check(KeycodeTyping.hangulKeys("a") == nil, "a is not Hangul")
check(KeycodeTyping.readsKeyCodes(bundleID: "com.parallels.desktop.console"), "Parallels reads keys")
check(!KeycodeTyping.readsKeyCodes(bundleID: "com.apple.TextEdit") && !KeycodeTyping.readsKeyCodes(bundleID: nil), "TextEdit does not")

// The guest.
struct Guest {
    var committed: [[S]] = []
    var composing: [S] = []
    mutating func apply(_ actions: [HangulRun.Action]) {
        for action in actions {
            switch action {
            case .stroke(let s): composing.append(s)
            case .backspace:
                if !composing.isEmpty { composing.removeLast() } else if !committed.isEmpty { committed.removeLast() }
            }
        }
    }
    mutating func commit() { if !composing.isEmpty { committed.append(composing); composing = [] } }
    /// What it shows, as its keys all told: a 2-set input method splits them into characters itself.
    var keys: [S] { committed.flatMap { $0 } + composing }
}
func keys(_ text: String) -> [S] { text.flatMap { KeycodeTyping.strokes(for: $0)! } }

/// The device's events: text ("t:한그") or a backspace ("b").
func session(_ events: [String], line: Int = #line) -> (Guest, HangulRun, [HangulRun.Action]) {
    var guest = Guest(), run = HangulRun(), device = "", all: [HangulRun.Action] = []
    for event in events {
        if event == "b" {
            device = String(device.dropLast())
            if !run.backspace() { guest.apply([.backspace]); all.append(.backspace) }
        } else if event == "settle" {
            let a = run.settle(); guest.apply(a); all += a
        } else {
            let text = String(event.dropFirst(2)); device += text
            let a = run.type(Array(text)); guest.apply(a); all += a
        }
        if event != "b" { check(guest.keys == keys(device), "after \(event): the guest holds \(device)'s keys", line: line) }
    }
    return (guest, run, all)
}

// 한글 as the device's Korean keyboard sends it: ㅎ; 하; 한; 한ㄱ; 한그 (한ㄱ deleted); 글. Only new keys.
do {
    let (_, _, all) = session(["t:ㅎ", "b", "t:하", "b", "t:한", "t:ㄱ", "b", "b", "t:한그", "b", "t:글"])
    check(all == keys("한글").map { .stroke($0) }, "한글 is g k s r m f, no backspace: \(all)")
}
// 하 then ㄴ then ㅏ: the ㄴ moves to the next syllable (하나), the keys only grow.
do {
    let (_, _, all) = session(["t:ㅎ", "b", "t:하", "b", "t:한", "b", "t:하나"])
    check(all == keys("하나").map { .stroke($0) }, "하나 is g k s k: \(all)")
}
// The person's backspace inside the syllable being composed: 한 back to 하, one key.
do {
    let (_, _, all) = session(["t:ㅎ", "b", "t:하", "b", "t:한", "b", "t:하"])
    check(all.last == .backspace && all.filter { $0 == .backspace }.count == 1, "한 to 하 is one backspace: \(all)")
}
// A backspace nothing follows waits, then deletes (the composing syllable key by key).
do {
    var (guest, run, _) = session(["t:ㄱ"])
    check(run.backspace(), "a backspace inside the run waits")
    let a = run.settle(); guest.apply(a)
    check(a == [.backspace] && guest.keys.isEmpty, "then goes: \(a)")
    check(!run.backspace(), "a backspace with nothing in the run goes now")
}
// Deleting back into a committed character: the composing one key by key, the committed one whole, then
// what is left of it typed again.
do {
    var guest = Guest(), run = HangulRun()
    guest.apply(run.type(Array("한")))
    guest.commit()                       // the guest committed 한 as 글 began (its own rule)
    guest.apply(run.type(Array("글")))
    _ = run.backspace(); _ = run.backspace()
    let a = run.type(Array("하")); guest.apply(a)
    check(guest.keys == keys("하"), "한글, two backspaces, 하: the guest holds 하, \(guest.keys)")
}
// The run's end sends its waiting backspaces and forgets it.
do {
    var run = HangulRun()
    _ = run.type(Array("가"))
    _ = run.backspace()
    check(run.end() == [.backspace, .backspace], "the end deletes 가's two keys")
    check(run.isEmpty, "and the run is empty")
}

print("keycode-typing: \(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
