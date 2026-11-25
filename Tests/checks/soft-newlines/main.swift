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

struct ChatHarness {
    var gate: SoftNewlines.Gate = { var g = SoftNewlines.Gate(); g.enabled = true; return g }()
    var composition = TextComposition()
    var draft = ""
    var submitted: [String] = []
    var sendingTyped = false

    mutating func send(_ event: InputEvent) {
        if TextInputRules.movesCaret(event), !sendingTyped {
            forgetTyped()
        }
        switch event {
        case .text(let s):
            for ch in s {
                if ch == "\n" || ch == "\r" || ch == "\r\n" || ch == "\t" {
                    submitted.append(draft)
                    draft = ""
                } else if ch == "\u{8}" {
                    if !draft.isEmpty { draft.removeLast() }
                } else {
                    draft.append(ch)
                }
            }
        case .key(let usage, let down, let mods):
            if down, usage == 0x28 {
                if mods & KeyModifiers.shift.rawValue != 0 {
                    draft.append("\n")
                } else {
                    submitted.append(draft)
                    draft = ""
                }
            }
        default:
            break
        }
    }

    mutating func apply(_ actions: [SoftNewlines.Action]) {
        for action in actions {
            switch action {
            case .text(let s):
                send(.text(s))
            case .backspaces(let n):
                for _ in 0..<n { send(.text("\u{8}")) }
            case .softNewline:
                sendingTyped = true
                for ev in KeyChord.press(0x28, with: .shift) { send(ev) }
                sendingTyped = false
            }
        }
    }

    mutating func forgetTyped() {
        guard !sendingTyped else { return }
        if gate.hasPendingReturn {
            apply(gate.flushPendingAsHard(in: &composition))
        }
        guard !composition.sent.isEmpty || composition.isComposing else { return }
        apply(SoftNewlines.actions(for: composition.forget(), soft: false))
    }

    mutating func insert(_ text: String, at now: Double) {
        apply(gate.insert(text, into: &composition, at: now))
    }

    mutating func replace(_ range: NSRange, with text: String, taken: Int? = nil, at now: Double) {
        apply(gate.replace(range, with: text, taken: taken ?? composition.generation, in: &composition, at: now))
    }

    mutating func select(_ range: NSRange) {
        if gate.hasPendingReturn {
            apply(gate.willSelect(in: &composition))
        }
        composition.select(range)
    }

    mutating func deleteBackward() {
        apply(gate.deleteBackward(in: &composition))
    }

    mutating func setMarked(_ text: String?, selected: NSRange, at now: Double) {
        apply(gate.setMarked(text, selected: selected, in: &composition, at: now))
    }

    mutating func unmark(at now: Double) {
        apply(gate.unmark(in: &composition, at: now))
    }

    mutating func timerFired() {
        apply(gate.flushPendingAsHard(in: &composition))
    }
}

func normalizeBreaks(_ s: String) -> String {
    var out = ""
    for ch in s {
        if ch == "\n" || ch == "\r" || ch == "\r\n" {
            out.append("\n")
        } else {
            out.append(ch)
        }
    }
    return out
}

// 1. Switch metadata & UserDefaults string/bool reading.
do {
    check(SoftNewlines.switchKey == "Sill.softNewlines" && SoftNewlines.defaultOn == false,
          "SoftNewlines switch key is Sill.softNewlines and defaults off upstream")
    check(SoftNewlines.Copy.title == "Soft Line Breaks" && SoftNewlines.Copy.footnote.contains("Shift-Return"),
          "Settings title and footnote name Shift-Return")
    let suiteName = "test.softNewlines.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    defer { suite.removePersistentDomain(forName: suiteName) }
    check(!SoftNewlines.isEnabled(in: suite), "unset UserDefaults follows defaultOn (false)")
    suite.set("1", forKey: SoftNewlines.switchKey)
    check(SoftNewlines.isEnabled(in: suite), "launch-argument string \"1\" enables SoftNewlines")
    suite.set(false, forKey: SoftNewlines.switchKey)
    check(!SoftNewlines.isEnabled(in: suite), "explicit false disables SoftNewlines")
}

// 2. Single-newline classification & action expansion.
check(SoftNewlines.isSingleNewline("\n") && SoftNewlines.isSingleNewline("\r") && SoftNewlines.isSingleNewline("\r\n"),
      "isSingleNewline matches LF, CR and CRLF")
check(!SoftNewlines.isSingleNewline("") && !SoftNewlines.isSingleNewline("\n\n") && !SoftNewlines.isSingleNewline("a\n"),
      "isSingleNewline rejects empty, double and text-bearing strings")
check(SoftNewlines.actions(for: [.text("\nhi\r\n\r")], soft: true) == [.softNewline, .text("hi"), .softNewline, .softNewline],
      "actions(soft: true) expands LF, CRLF and CR including leading, trailing and consecutive breaks")
check(SoftNewlines.actions(for: [.text("a\r\nb")], soft: false) == [.text("a\r\nb")],
      "actions(soft: false) preserves text verbatim")

// 3. CRLF-only insert & UTF-16 offset preservation on subsequent replace.
do {
    var h = ChatHarness()
    h.insert("before\r\nafter", at: 1.0)
    check(h.submitted.isEmpty && h.draft == "before\nafter" && h.composition.fence == 0,
          "CRLF-only multi-line insert stays in draft without submitting early")

    var h2 = ChatHarness()
    h2.insert("a\r\nb\nc", at: 1.0)
    check(h2.composition.document.utf16.count == 6,
          "TextComposition preserves exact 6 UTF-16 units for \"a\\r\\nb\\nc\"")
    h2.replace(NSRange(location: 3, length: 1), with: "B", at: 2.0)
    check(h2.submitted.isEmpty && h2.draft == "a\nB\nc",
          "subsequent replace at incoming UTF-16 offset after CRLF edits exact character")
}

// 4. WeType UITextDocumentProxy token-by-token streaming ("line 1", "\n", "line 2", "\n", "\n", "line 3")!
do {
    var h = ChatHarness()
    h.insert("First line", at: 10.000)
    h.insert("\n", at: 10.012)          // standalone "\n" token from UITextDocumentProxy
    h.insert("Second line", at: 10.025) // next token 13 ms later (<= 45 ms coalesceWindow) -> promotes "\n" to ⇧Return!
    h.insert("\n", at: 10.035)
    h.insert("\n", at: 10.042)          // consecutive standalone "\n" token -> both become ⇧Return!
    h.insert("Third line", at: 10.055)
    check(h.submitted.isEmpty && h.draft == "First line\nSecond line\n\nThird line" && h.composition.fence == 0,
          "WeType UITextDocumentProxy separate-token newline stream stays in one draft with zero early send",
          detail: "submitted=\(h.submitted), draft=\(h.draft.debugDescription)")

    // User then pauses and taps Return to send:
    h.insert("\n", at: 12.000)
    h.timerFired()
    check(h.submitted == ["First line\nSecond line\n\nThird line"] && h.draft.isEmpty
          && h.composition.fence == h.composition.sent.utf16.count,
          "standalone Return after coalesceWindow submits the whole multi-paragraph message once")
}

// 5. Fast two-thumb typist typing "o", "k", Return (25 ms & 40 ms gaps) STILL sends! (No backward burstWindow bug!)
do {
    var h = ChatHarness()
    h.insert("o", at: 0.000)
    h.insert("k", at: 0.025)
    h.insert("\n", at: 0.065)       // 40 ms after 'k', then user stops typing!
    check(h.gate.hasPendingReturn && h.submitted.isEmpty,
          "fast typist Return enters 45 ms lookahead instead of turning into permanent ⇧Return")
    h.timerFired()
    check(h.submitted == ["ok"] && h.draft.isEmpty && h.composition.fence == 3,
          "fast typist typing \"ok\" + Return submits \"ok\" cleanly after 45 ms")
}

// 6. Selection after pending Return settles Return at original position instead of deleting selected char (Codex P1 #2).
do {
    var h = ChatHarness()
    h.insert("abc", at: 1.0)
    h.insert("\n", at: 2.0)
    h.select(NSRange(location: 2, length: 1))   // selects 'c' 10 ms later
    check(h.submitted == ["abc"] && !h.gate.hasPendingReturn,
          "selection arriving while Return is pending settles Return before applying selection")
}

// 7. Empty setMarkedText(nil) does NOT extend the 45 ms deadline, and stale replace does NOT consume pending Send.
do {
    var h = ChatHarness()
    h.insert("one", at: 1.000)
    h.insert("\n", at: 2.000)
    h.setMarked(nil, selected: NSRange(location: 0, length: 0), at: 2.030)
    check(h.gate.pendingReturnAt == 2.000,
          "setMarked(nil) preserves original pendingReturnAt deadline")
    // Late edit at 2.060 (60 ms > 45 ms coalesceWindow) settles the expired Return as HARD first!
    h.insert("two", at: 2.060)
    check(h.submitted == ["one"] && h.draft == "two",
          "edit arriving after 45 ms original deadline settles expired Return as hard send first")

    // Stale-generation replace during 45 ms wait is refused BEFORE touching pendingReturnAt:
    var h2 = ChatHarness()
    h2.insert("old", at: 1.0)
    let staleGen = h2.composition.generation
    h2.forgetTyped()
    h2.draft = ""
    h2.insert("send", at: 2.0)
    h2.insert("\n", at: 3.000)
    h2.replace(NSRange(location: 0, length: 3), with: "OLD", taken: staleGen, at: 3.010)
    check(h2.gate.pendingReturnAt == 3.000 && h2.submitted.isEmpty,
          "rejected stale-generation replace leaves pending Return untouched")
    h2.timerFired()
    check(h2.submitted == ["send"] && h2.draft.isEmpty,
          "pending Return still submits \"send\" after stale replace was refused")
}

// 8. Whole-document correction & Korean cross-fence retype after an already-submitted hard Return.
do {
    var h = ChatHarness()
    h.insert("one", at: 1.0)
    h.insert("\n", at: 2.0)
    h.timerFired()
    h.insert("tow", at: 3.0)
    h.replace(NSRange(location: 0, length: 7), with: "one\ntwo", at: 3.5)
    check(h.submitted == ["one"] && h.draft == "two",
          "whole-document correction after hard Return preserves fenced prefix and fixes \"tow\" -> \"two\"")

    var kr = ChatHarness()
    kr.insert("한글", at: 1.0)
    kr.insert("\n", at: 2.0)
    kr.timerFired()
    kr.insert("ㅎ", at: 3.0)
    kr.select(NSRange(location: 2, length: 2))
    kr.deleteBackward()
    kr.insert("\n하", at: 3.1)
    check(kr.submitted == ["한글"] && kr.draft == "하",
          "Korean cross-fence retype after hard Return preserves syllable \"하\" without resending")
}

// 9. Literal U+2028, marked text CRLF + emoji, Tab fencing, deleteBackward cancelling pending Return, and disabled mode.
do {
    for mode in [false, true] {
        var h = ChatHarness()
        h.gate.enabled = mode
        h.insert("A\u{2028}B", at: 1.0)
        check(h.submitted.isEmpty && h.draft == "A\u{2028}B",
              "literal U+2028 stays Unicode text when enabled=\(mode)")
    }

    var hm = ChatHarness()
    hm.setMarked("A\r\n😀B\n", selected: NSRange(location: 3, length: 0), at: 1.0)
    check((hm.composition.marked! as NSString).substring(from: 3) == "😀B\n",
          "marked text with CRLF before emoji keeps UTF-16 caret at emoji boundary")
    hm.unmark(at: 1.1)
    check(hm.submitted.isEmpty && hm.draft == "A\n😀B\n" && hm.composition.fence == 0,
          "unmark commits multi-line marked text using soft newlines")

    var ht = ChatHarness()
    ht.insert("field1\tline1\nline2", at: 1.0)
    check(ht.submitted == ["field1"] && ht.draft == "line1\nline2" && ht.composition.fence == 7,
          "Tab inside soft-newline text fences field1 while keeping line1\\nline2 editable")

    var hb = ChatHarness()
    hb.insert("abc", at: 1.0)
    hb.insert("\n", at: 2.0)
    hb.deleteBackward()
    check(!hb.gate.hasPendingReturn && hb.submitted.isEmpty && hb.draft == "abc",
          "deleteBackward while Return is pending cancels it without deleting 'c'")

    var hd = ChatHarness()
    hd.gate.enabled = false
    hd.insert("line 1\nline 2", at: 1.0)
    hd.replace(NSRange(location: 7, length: 6), with: "two\r\nthree", at: 2.0)
    check(hd.submitted == ["line 1", "two"] && hd.draft == "three",
          "when disabled, embedded LF and CRLF send hard Returns")
}

// 10. 5,000 seeded random multi-paragraph dictation, token-streamed newlines, composition and chat sessions.
struct RNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
}

let chunks = ["hello", " world", "你好", "👋🏽", "e\u{301}", "a\nb", "o\r\nt", "p1\n\np2\r\np3", "\nleading", "trailing\r", "lit\u{2028}sep"]
let singleBreaks = ["\n", "\r", "\r\n"]
var rng = RNG(state: 0x50F7_2026_1126)
var randomFailure: String?

outer: for session in 0..<5_000 {
    var h = ChatHarness()
    h.gate.enabled = rng.int(5) != 0
    var now = 1.0
    for step in 0..<25 {
        let op = rng.int(9)
        switch op {
        case 0...2:
            now += rng.int(2) == 0 ? 0.015 : 0.120
            h.insert(rng.pick(chunks), at: now)
        case 3:
            now += rng.int(2) == 0 ? 0.015 : 0.120
            h.insert(rng.pick(singleBreaks), at: now)
            if h.gate.hasPendingReturn && rng.int(2) == 0 {
                now += 0.060
                h.timerFired()
            }
        case 4, 5:
            if !h.gate.hasPendingReturn, !h.composition.isComposing {
                let ns = h.composition.document as NSString
                if ns.length > 0 {
                    let a = rng.int(ns.length + 1)
                    let b = rng.int(ns.length + 1)
                    let lo = min(a, b), hi = max(a, b)
                    let r = ns.rangeOfComposedCharacterSequences(for: NSRange(location: lo, length: max(hi - lo, 0)))
                    if r.location + r.length <= ns.length {
                        now += 0.020
                        h.replace(r, with: rng.pick(chunks), at: now)
                    }
                }
            }
        case 6:
            now += 0.020
            h.deleteBackward()
        case 7:
            now += 0.020
            let m = rng.pick(["pin\r\nyin", "ㄋㄧˇ", "a\nb"])
            h.setMarked(m, selected: NSRange(location: (m as NSString).length, length: 0), at: now)
            if rng.int(2) == 0 {
                now += 0.015
                h.unmark(at: now)
            }
        default:
            now += 0.080
            h.forgetTyped()
            h.draft = ""
        }

        if !h.gate.hasPendingReturn && !h.composition.isComposing {
            let tailUTF16 = Array(h.composition.sent.utf16.dropFirst(h.composition.fence))
            let tail = String(utf16CodeUnits: tailUTF16, count: tailUTF16.count)
            let expectedDraft = normalizeBreaks(tail)
            if h.draft != expectedDraft {
                randomFailure = "session \(session) step \(step): draft \(h.draft.debugDescription) != expected \(expectedDraft.debugDescription)"
                break outer
            }
        }
    }
}
check(randomFailure == nil, "5,000 random multi-paragraph dictation, token-stream and chat sessions", detail: randomFailure ?? "")

print("soft-newlines: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
