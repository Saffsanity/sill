import Foundation

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

func u(_ s: String) -> TypedText.Step { .unicode(Array(s.utf16)) }

// 1. Empty and single control characters.
check(TypedText.steps(for: "") == [], "empty string produces no steps")
check(TypedText.steps(for: "\n") == [.returnKey], "LF produces one returnKey")
check(TypedText.steps(for: "\r") == [.returnKey], "CR produces one returnKey")
check(TypedText.steps(for: "\r\n") == [.returnKey], "CRLF grapheme cluster produces one returnKey, not two")
check(TypedText.steps(for: "\t") == [.tabKey], "Tab produces tabKey")
check(TypedText.steps(for: "\u{8}") == [.backspaceKey], "BS (U+0008) produces backspaceKey")
check(TypedText.steps(for: "\u{7F}") == [u("\u{7F}")], "DEL (U+007F) stays unicode")
check(TypedText.steps(for: "\u{2028}") == [u("\u{2028}")], "U+2028 line separator stays unicode")

// 2. Adjacent and mixed line breaks.
check(TypedText.steps(for: "\n\n") == [.returnKey, .returnKey], "two LFs produce two returnKeys")
check(TypedText.steps(for: "\r\r") == [.returnKey, .returnKey], "two CRs produce two returnKeys")
check(TypedText.steps(for: "\r\n\r\n") == [.returnKey, .returnKey], "two CRLFs produce two returnKeys")
check(TypedText.steps(for: "\n\r") == [.returnKey, .returnKey], "LF then CR (two graphemes) produces two returnKeys")
check(TypedText.steps(for: "\r\n\n\r") == [.returnKey, .returnKey, .returnKey], "CRLF + LF + CR produces three returnKeys")

// 3. Mixed text and controls.
check(
    TypedText.steps(for: "a\r\nb\rc\nd\te\u{8}f") == [
        u("a"), .returnKey, u("b"), .returnKey, u("c"), .returnKey, u("d"), .tabKey, u("e"), .backspaceKey, u("f")
    ],
    "mixed ASCII, CRLF, CR, LF, Tab and Backspace"
)

// 4. Multi-scalar grapheme clusters stay whole as one unicode step with full UTF-16.
let wave = "👋🏽"
let accent = "e\u{301}"
let family = "👨‍👩‍👧‍👦"
check(TypedText.steps(for: wave) == [u(wave)] && Array(wave.utf16).count == 4,
      "skin-tone emoji stays one unicode step of 4 UTF-16 code units")
check(TypedText.steps(for: accent) == [u(accent)] && Array(accent.utf16).count == 2,
      "decomposed combining mark stays one unicode step of 2 UTF-16 code units")
check(TypedText.steps(for: family) == [u(family)] && Array(family.utf16).count == 11,
      "ZWJ family emoji stays one unicode step of 11 UTF-16 code units")
check(TypedText.steps(for: "你好\r\n\(wave)") == [u("你"), u("好"), .returnKey, u(wave)],
      "CJK + CRLF + skin-tone emoji")

// 5. 2,000 seeded random strings mixing graphemes and controls.
struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func pick<T>(_ items: [T]) -> T { items[Int(next() % UInt64(items.count))] }
}

let atoms = ["a", "Z", " ", "你", "한", "e\u{301}", "👋🏽", "👨‍👩‍👧‍👦", "\n", "\r", "\r\n", "\t", "\u{8}", "\u{2028}"]
var rng = RNG(state: 0x5111_2026_1125)
var randomMismatch: String?
for trial in 0..<2_000 {
    let len = Int(rng.next() % 24)
    var s = ""
    for _ in 0..<len { s += rng.pick(atoms) }
    let got = TypedText.steps(for: s)
    var expected: [TypedText.Step] = []
    for ch in s {
        if ch == "\n" || ch == "\r" || ch == "\r\n" { expected.append(.returnKey) }
        else if ch == "\t" { expected.append(.tabKey) }
        else if ch == "\u{8}" { expected.append(.backspaceKey) }
        else { expected.append(.unicode(Array(ch.utf16))) }
    }
    if got != expected || got.count != s.count {
        randomMismatch = "trial \(trial): \(s.debugDescription) -> \(got) != \(expected)"
        break
    }
}
check(randomMismatch == nil, "2,000 random strings with controls, CJK, combining marks and emoji", detail: randomMismatch ?? "")

print("typed-text: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
