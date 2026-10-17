// TextComposition (iOSClient/TextComposition.swift) on its own: an input method's composition stays on
// the device until it is committed, and every edit the text system makes reaches the Mac as backspaces
// and text that leave the Mac's text equal to the document (#138). Scenario by scenario, then 20,000
// random edit sequences against a model of the Mac's text field.
//   swiftc -O iOSClient/TextComposition.swift Tests/checks/text-composition/main.swift -o check && ./check
import Foundation

typealias C = TextComposition
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

/// The Mac's text field: what the outputs leave there.
func apply(_ outputs: [C.Output], to text: inout String) {
    for output in outputs {
        switch output {
        case .text(let t): text += t
        case .backspaces(let n): text = String(text.dropLast(n))
        }
    }
}

// MARK: - Scenarios

do {   // Zhuyin: symbols composed, then a candidate committed through insertText
    var c = C()
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    c.setMarked("ㄋㄧˇ", selected: NSRange(location: 3, length: 0))
    check("a composition is not sent", c.sent.isEmpty && c.isComposing && c.markedRange == NSRange(location: 0, length: 3))
    check("the caret sits where the input method put it", c.selectedRange == NSRange(location: 3, length: 0))
    let out = c.insert("你")
    check("the candidate replaces the composition and goes out", out == [.text("你")] && !c.isComposing && c.sent == "你")
}

do {   // a composition accepted as it stands (unmarkText), after text already sent
    var c = C()
    _ = c.insert("a")
    c.setMarked("你好", selected: NSRange(location: 2, length: 0))
    check("the marked range follows what was sent", c.markedRange == NSRange(location: 1, length: 2))
    check("unmark sends the composition", c.unmark() == [.text("你好")] && c.document == "a你好")
    check("unmark with nothing composed sends nothing", c.unmark() == [])
}

do {   // backspace inside a composition edits it, outside it reaches the Mac
    var c = C()
    c.setMarked("ㄋㄧ", selected: NSRange(location: 2, length: 0))
    check("backspace in a composition sends nothing", c.deleteBackward() == [] && c.marked == "ㄋ")
    check("the last symbol's backspace ends it", c.deleteBackward() == [] && !c.isComposing)
    check("backspace with nothing remembered still reaches the Mac", c.deleteBackward() == [.backspaces(1)])
    _ = c.insert("你好")
    check("a remembered character is one backspace", c.deleteBackward() == [.backspaces(1)] && c.sent == "你")
}

do {   // an empty composition ends it without sending
    var c = C()
    c.setMarked("ㄅ", selected: NSRange(location: 1, length: 0))
    c.setMarked("", selected: NSRange(location: 0, length: 0))
    check("an empty composition ends it", !c.isComposing && c.sent.isEmpty)
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    check("a nil composition ends it", !c.isComposing)
}

do {   // dictation corrects a word it already typed
    var c = C()
    var mac = ""
    apply(c.insert("I sea it"), to: &mac)
    apply(c.replace(NSRange(location: 2, length: 3), with: "see"), to: &mac)
    check("a correction deletes back to the change and types the rest", mac == "I see it" && c.document == "I see it")
    apply(c.replace(NSRange(location: 8, length: 0), with: "."), to: &mac)
    check("an insertion at the end is only typed", mac == "I see it." )
}

do {   // a replacement over the composition commits it
    var c = C()
    var mac = ""
    apply(c.insert("x"), to: &mac)
    c.setMarked("ni", selected: NSRange(location: 2, length: 0))
    apply(c.replace(NSRange(location: 1, length: 2), with: "你"), to: &mac)
    check("replacing the marked text commits the replacement", mac == "x你" && !c.isComposing)
}

do {   // emoji and combining marks count as one character on the Mac
    var c = C()
    var mac = ""
    apply(c.insert("a👍🏽é"), to: &mac)
    let out = c.deleteBackward()
    apply(out, to: &mac)
    check("one backspace per character, not per UTF-16 unit", out == [.backspaces(1)] && mac == "a👍🏽")
    let utf16 = c.document.utf16.count
    apply(c.replace(NSRange(location: 1, length: utf16 - 1), with: "b"), to: &mac)
    check("a replacement over an emoji deletes it once", mac == "ab")
}

do {   // reset forgets what was sent, not the composition
    var c = C()
    _ = c.insert("hello")
    c.setMarked("ㄏ", selected: NSRange(location: 1, length: 0))
    c.reset()
    check("reset forgets what was sent", c.sent.isEmpty && c.marked == "ㄏ" && c.markedRange == NSRange(location: 0, length: 1))
}

do {   // only a tail is kept
    var c = C()
    _ = c.insert(String(repeating: "字", count: C.keep + 50))
    check("only the last characters are kept", c.sent.count == C.keep)
}

do {   // a selection out of range is clamped
    var c = C()
    c.setMarked("ㄋㄧ", selected: NSRange(location: 9, length: 4))
    check("the marked selection stays inside the composition", c.selectedRange == NSRange(location: 2, length: 0))
}

// MARK: - Random edit sequences

var generator = SystemRandomNumberGenerator()
let alphabet: [String] = ["a", "b", "你", "好", "ㄋ", "ˇ", "👍🏽", "é", " ", "\n"]
func word() -> String { (0..<Int.random(in: 1...3, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! }.joined() }
var randomFails = 0
for _ in 0..<20_000 {
    var c = C()
    var mac = ""
    for _ in 0..<12 {
        switch Int.random(in: 0..<7, using: &generator) {
        case 0: apply(c.insert(word()), to: &mac)
        case 1: c.setMarked(word(), selected: NSRange(location: 0, length: 0))
        case 2: apply(c.unmark(), to: &mac)
        case 3: apply(c.deleteBackward(), to: &mac)
        case 4:
            // Whole characters only: UIKit's ranges never split one.
            let chars = Array(c.document)
            let a = Int.random(in: 0...chars.count, using: &generator)
            let b = Int.random(in: a...chars.count, using: &generator)
            let loc = String(chars[..<a]).utf16.count, len = String(chars[a..<b]).utf16.count
            apply(c.replace(NSRange(location: loc, length: len), with: word()), to: &mac)
        case 5: c.reset()
        default: break
        }
        // Whatever the Mac held before the last reset, its tail is always the remembered text.
        if !mac.hasSuffix(c.sent) || c.sent.count > C.keep { randomFails += 1; break }
    }
}
check("20,000 random sequences: the Mac's text always ends with what is remembered", randomFails == 0)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
