// TextComposition (iOSClient/TextComposition.swift) on its own: an input method's composition stays on
// the device until it is committed, and every edit the text system makes reaches the Mac as backspaces
// and text that leave the Mac's text equal to the document (#138). What was typed is kept whole while
// the text system may revise it (a long dictation's corrections land where they were made), trimmed only
// past its limit, and a correction whose range was taken before a forget or a trim sends nothing,
// wherever its offsets fall now; what the text system selects is replaced by its next edit (Korean's
// syllables); a Return or a Tab typed as text goes whole and makes what came before it final, through
// the app's own path (`type`): what was typed is kept, and a correction that would change what came
// before it sends nothing (the fence), while one of what follows it goes, and Korean's rebuild of the
// Return with the syllable after it sends that Return once. Then TextInputRules: which
// input moves the Mac's caret, where a Return or a Tab typed ends, which input modes are keyboards, and
// whose ⌃Space it is; and KeyTyping: who types a hardware keyboard's characters, the Mac (as keys) or
// iPadOS's text system, by the keyboard selected, marked text and the key row's latch. Scenario by
// scenario, then 25,000 seeded random edit sequences against a model of the Mac's text field.
//   swiftc -O iOSClient/TextComposition.swift Sources/StreamProtocol/Input.swift \
//       Tests/checks/text-composition/main.swift -o check && ./check
import Foundation

typealias C = TextComposition
typealias R = TextInputRules
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

/// A chat on the Mac (Messages, Slack): what the outputs leave in its message field, where a Return sends
/// the field as a message (an empty one sends none) and a backspace deletes the field's last character
/// (nothing in an empty field: the line it would reach was sent). What a Return typed may do on the Mac.
struct Chat: Equatable {
    var field = ""
    var messages: [String] = []
    mutating func apply(_ outputs: [C.Output]) {
        for output in outputs {
            switch output {
            case .backspaces(let n): field = String(field.dropLast(n))
            case .text(let text):
                for character in text {
                    if character == "\n" || character == "\r" || character == "\r\n" {
                        if !field.isEmpty { messages.append(field) }
                        field = ""
                    } else {
                        field.append(character)
                    }
                }
            }
        }
    }
}

/// What the app does with what an edit leaves (InputOverlayView.typed, each output through
/// StreamClient.sendInput): each output goes to the Mac, and before one that may move the Mac's caret
/// (TextInputRules.movesCaret) the input view forgets what was typed (StreamClient.onCaretMayMove, then
/// InputOverlayView.forgetTyped, which does nothing while nothing is remembered or composed), what that
/// forget sends going first. No text moves the caret since the fence (a Return or a Tab typed keeps what
/// was typed), so this never forgets but under a mutant that says one does, as the app then would.
/// What goes reaches both the Mac's text field (`mac`) and a chat (`chat`). True when it forgot.
@discardableResult
func type(_ outputs: [C.Output], into c: inout C, mac: inout String, chat: inout Chat) -> Bool {
    var forgot = false
    for output in outputs {
        if case .text(let text) = output, R.movesCaret(.text(text)), !c.sent.isEmpty || c.isComposing {
            let forgotten = c.forget()
            apply(forgotten, to: &mac)
            chat.apply(forgotten)
            forgot = true
        }
        apply([output], to: &mac)
        chat.apply([output])
    }
    return forgot
}

/// The same, to the Mac's text field alone.
@discardableResult
func type(_ outputs: [C.Output], into c: inout C, mac: inout String) -> Bool {
    var chat = Chat()
    return type(outputs, into: &c, mac: &mac, chat: &chat)
}

/// A range of whole characters of `s`, in UTF-16 offsets, as UIKit's ranges are.
func utf16Range(_ s: String, characters: Range<Int>) -> NSRange {
    let chars = Array(s)
    let loc = String(chars[..<characters.lowerBound]).utf16.count
    let len = String(chars[characters]).utf16.count
    return NSRange(location: loc, length: len)
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
    check("the length is the document's, the composition's included", c.length == 3 && c.document == "a你好")
    check("the caret inside a composition is after what was sent", c.selectedRange == NSRange(location: 3, length: 0))
    check("unmark sends the composition", c.unmark() == [.text("你好")] && c.document == "a你好")
    check("unmark with nothing composed sends nothing", c.unmark() == [])
}

do {   // the input method's caret inside its composition (Japanese, moving between clauses)
    var c = C()
    _ = c.insert("x")
    c.setMarked("きょうは", selected: NSRange(location: 1, length: 2))
    check("a selection inside the composition is kept, after what was sent", c.selectedRange == NSRange(location: 2, length: 2))
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
    check("an empty composition ends it", !c.isComposing && c.sent.isEmpty && c.markedRange == nil)
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    check("a nil composition ends it", !c.isComposing)
}

do {   // dictation corrects a word it already typed
    var c = C()
    var mac = ""
    apply(c.insert("I sea it"), to: &mac)
    apply(c.replace(NSRange(location: 2, length: 3), with: "see"), to: &mac)
    check("a correction deletes back to the change and types the rest", mac == "I see it" && c.document == "I see it")
    let out = c.replace(NSRange(location: 8, length: 0), with: ".")
    apply(out, to: &mac)
    check("an insertion at the end is only typed", out == [.text(".")] && mac == "I see it.")
}

do {   // a long dictation: its corrections land where they were made, however much came before
    var c = C()
    var mac = ""
    var ok = true
    var phrase = 0
    while c.sent.count < 1_500 {
        phrase += 1
        let start = c.length
        apply(c.insert("wurd\(phrase) "), to: &mac)          // the first hypothesis
        apply(c.replace(NSRange(location: start, length: c.length - start), with: "word\(phrase), "), to: &mac)   // corrected
        if mac != c.document { ok = false; break }
    }
    check("a dictation of 1,500 characters corrected phrase by phrase: the Mac's text is the document", ok && mac == c.document)
    check("…and nothing of it was cut from under a correction", c.sent.count >= 1_500 && c.sent.hasPrefix("word1, "))
    let first = utf16Range(c.document, characters: 0..<4)
    apply(c.replace(first, with: "Word"), to: &mac)
    check("a correction at the very start of a long dictation goes there", mac == c.document && mac.hasPrefix("Word1, "))
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
    let combining = c.insert("e")
    apply(combining, to: &mac)
    let accent = c.insert("\u{301}")
    apply(accent, to: &mac)
    check("a combining mark that joins the last character retypes it whole", accent == [.backspaces(1), .text("é")] && mac == "abé")
}

do {   // a forget (the Mac's caret is about to move: a click, a key, a pick) sends what is composed
       // first, as it stands, where the caret still is, then forgets everything
    var c = C()
    var mac = ""
    apply(c.insert("hello"), to: &mac)
    c.setMarked("ㄏㄠ", selected: NSRange(location: 2, length: 0))
    let out = c.forget()
    apply(out, to: &mac)
    check("a forget sends what is composed, as it stands, before the caret moves", out == [.text("ㄏㄠ")] && mac == "helloㄏㄠ")
    check("…then forgets it all", c.sent.isEmpty && !c.isComposing && c.length == 0 && c.markedRange == nil)
    check("a forget with nothing composed sends nothing", c.forget() == [] && c.sent.isEmpty)
}

do {   // a correction taken before a forget: nothing goes to the Mac
    var c = C()
    var mac = "earlier text "
    apply(c.insert("I sea it"), to: &mac)
    let stale = NSRange(location: 2, length: 3)        // "sea", taken before the Mac's caret moved
    apply(c.forget(), to: &mac)                        // a click on the Mac
    apply(c.insert("x"), to: &mac)                     // typed where the caret is now
    let out = c.replace(stale, with: "see")
    check("a range that starts past the document after a forget sends nothing", out == [] && mac == "earlier text I sea itx")
    check("…and changes nothing here", c.sent == "x" && !c.isComposing)
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    let underComposition = c.replace(NSRange(location: 9, length: 1), with: "y")
    check("…a composition in progress carries on", underComposition == [] && c.marked == "ㄋ")
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    let atEnd = c.replace(NSRange(location: c.length, length: 0), with: "z")
    apply(atEnd, to: &mac)
    check("an insertion at the very end still goes", atEnd == [.text("z")] && c.sent == "xz")
    let overhanging = c.replace(NSRange(location: 1, length: 40), with: "Z")
    apply(overhanging, to: &mac)
    check("a range that starts inside and runs past the end is cut at the end",
          overhanging == [.backspaces(1), .text("Z")] && c.sent == "xZ" && mac == "earlier text I sea itxZ")
}

do {   // dictation's last correction of a phrase (its punctuation and capitals) comes after a click: its
       // range was taken before the forget and reaches into what was typed since
    var c = C()
    var mac = "earlier "
    apply(c.insert("hello"), to: &mac)
    let taken = c.generation
    let phrase = NSRange(location: 0, length: 5)       // "hello", as the text system holds it
    apply(c.forget(), to: &mac)                        // a click on the Mac
    check("a forget starts a new document", c.generation == taken + 1)
    apply(c.insert("x"), to: &mac)                     // typed where the caret is now
    check("typing keeps the document", c.generation == taken + 1)
    let out = c.replace(phrase, with: "Hello.", taken: taken)
    check("a correction taken before a forget sends nothing, even where what was typed since reaches",
          out == [] && mac == "earlier hellox" && c.sent == "x")
    let now = c.replace(NSRange(location: 0, length: 1), with: "y", taken: c.generation)
    apply(now, to: &mac)
    check("…and one taken since goes", now == [.backspaces(1), .text("y")] && mac == "earlier helloy")
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    let marked = c.generation
    let composed = c.forget()
    apply(composed, to: &mac)
    check("a forget while composing sends the composition, then starts a new document",
          composed == [.text("ㄋ")] && mac == "earlier helloyㄋ" && c.generation == marked + 1 && !c.isComposing)
    check("…and a correction of the composition taken before it sends nothing",
          c.replace(NSRange(location: 1, length: 1), with: "你", taken: marked) == [] && c.length == 0 && mac == "earlier helloyㄋ")
}

do {   // dictation types a phrase, the person presses Return (a chat sends the line, a terminal runs it),
       // then dictation's last pass over the phrase, its capital and full stop, comes with the range it
       // took before the Return: #147's first verification, where it sent 15 backspaces and "Send the
       // build.\n" (the line twice)
    var c = C()
    var mac = ""
    var chat = Chat()
    type(c.insert("send the build"), into: &c, mac: &mac, chat: &chat)
    let taken = c.generation
    let phrase = NSRange(location: 0, length: 14)       // "send the build", as the text system holds it
    let typed = c.insert("\n")                          // a hardware Return, or the keyboard's return key
    check("a Return typed as text goes to the Mac as text", typed == [.text("\n")])
    let forgot = type(typed, into: &c, mac: &mac, chat: &chat)
    check("…whole, after the phrase: the line sent once", mac == "send the build\n" && chat.messages == ["send the build"])
    check("…and what was typed is kept, the same document, what came before the Return final: the fence just after it",
          !forgot && c.sent == "send the build\n" && c.generation == taken && c.fence == 15)
    let out = c.replace(phrase, with: "Send the build.", taken: taken)
    type(out, into: &c, mac: &mac, chat: &chat)
    check("a correction of the phrase before it sends nothing: the line goes once",
          out == [] && mac == "send the build\n" && chat.messages == ["send the build"] && c.sent == "send the build\n" && c.fence == 15)
    check("…and says why", c.refusal(phrase, with: "Send the build.", taken: taken) == .final)
    let itself = c.replace(NSRange(location: 14, length: 1), with: " now\n", taken: taken)
    type(itself, into: &c, mac: &mac, chat: &chat)
    check("…nor does one that would replace the Return itself (no second message)",
          itself == [] && mac == "send the build\n" && chat.messages == ["send the build"])
    c.select(NSRange(location: 14, length: 1))          // the text system selects the character a backspace deletes
    check("the Return selected for a backspace is wholly final: not kept", c.selection == nil)
    let back = c.deleteBackward()
    type(back, into: &c, mac: &mac, chat: &chat)
    check("the person's backspace right after it still reaches the Mac, and the fence comes back to what is left",
          back == [.backspaces(1)] && mac == "send the build" && c.sent == "send the build" && c.fence == 14)
    check("…all of it still final: a correction of the phrase sends nothing",
          c.replace(phrase, with: "Send the build.", taken: taken) == [] && chat.messages == ["send the build"])
    type(c.insert("ok"), into: &c, mac: &mac, chat: &chat)
    let corrected = c.replace(NSRange(location: 14, length: 2), with: "OK", taken: c.generation)
    type(corrected, into: &c, mac: &mac, chat: &chat)
    check("…and what is typed after it is corrected as before",
          corrected == [.backspaces(2), .text("OK")] && mac == "send the buildOK" && c.sent == "send the buildOK"
          && c.generation == taken && chat.field == "OK" && chat.messages == ["send the build"])
}

do {   // dictation's "new line" said in the middle of what it is typing, then its last pass over the whole
       // phrase, through the range from where the phrase began (as in the long dictation above): #147's
       // second verification, where b1012a17 forgot at the Return and typed the corrected phrase again,
       // Return included (a second, garbled message), and 2dc6c75 backspaced over the Return
    for prefix in ["", "earlier "] {
        var c = C()
        var mac = ""
        var chat = Chat()
        if !prefix.isEmpty { type(c.insert(prefix), into: &c, mac: &mac, chat: &chat) }
        let start = c.length
        let taken = c.generation
        let forgot = type(c.insert("send the build\ndeploy it "), into: &c, mac: &mac, chat: &chat)
        check("text with a Return inside goes to the Mac whole, what was typed kept, the fence just after the Return" + (prefix.isEmpty ? "" : " (after earlier typing)"),
              !forgot && mac == prefix + "send the build\ndeploy it " && c.sent == mac && c.generation == taken && c.fence == start + 15)
        let whole = NSRange(location: start, length: c.length - start)
        let out = c.replace(whole, with: "Send the build.\nDeploy it. ", taken: taken)
        type(out, into: &c, mac: &mac, chat: &chat)
        check("…the last pass over the whole phrase sends nothing: the line went once, no second message" + (prefix.isEmpty ? "" : " (after earlier typing)"),
              out == [] && mac == prefix + "send the build\ndeploy it " && chat.messages == [prefix + "send the build"] && chat.field == "deploy it ")
        let after = NSRange(location: start + 15, length: c.length - start - 15)
        let words = c.replace(after, with: "Deploy it. ", taken: taken)
        type(words, into: &c, mac: &mac, chat: &chat)
        check("…a correction of only the words after the Return goes as before" + (prefix.isEmpty ? "" : " (after earlier typing)"),
              words == [.backspaces(10), .text("Deploy it. ")] && mac == prefix + "send the build\nDeploy it. "
              && chat.messages == [prefix + "send the build"] && chat.field == "Deploy it. ")
    }
}

do {   // the same words typed after the Return rather than with it
    var c = C()
    var mac = ""
    var chat = Chat()
    for text in ["send the build", "\n", "deploy it "] { type(c.insert(text), into: &c, mac: &mac, chat: &chat) }
    check("words typed after a Return follow the fence", c.fence == 15 && mac == "send the build\ndeploy it ")
    check("…a correction of the whole phrase sends nothing",
          c.replace(NSRange(location: 0, length: 25), with: "Send the build.\nDeploy it. ", taken: c.generation) == [])
    let words = c.replace(NSRange(location: 15, length: 10), with: "Deploy it. ", taken: c.generation)
    type(words, into: &c, mac: &mac, chat: &chat)
    check("…one of the words after it goes",
          words == [.backspaces(10), .text("Deploy it. ")] && chat.messages == ["send the build"] && chat.field == "Deploy it. ")
}

do {   // dictation sending each hypothesis of one utterance again, whole, through the range it holds from
       // where the utterance began, "new line" said in the middle (S2 of #147's second verification)
    var c = C()
    var mac = ""
    var chat = Chat()
    let taken = c.generation, start = c.length
    var held = 0
    var outs: [[C.Output]] = []
    for hypothesis in ["send", "send the build", "send the build\ndeploy", "send the build\ndeploy it", "Send the build.\nDeploy it."] {
        let out = c.replace(NSRange(location: start, length: held), with: hypothesis, taken: taken)
        type(out, into: &c, mac: &mac, chat: &chat)
        outs.append(out)
        held = hypothesis.utf16.count
    }
    check("every word of an utterance with \"new line\" in it arrives once, the line sent once",
          mac == "send the build\ndeploy it" && chat.messages == ["send the build"] && chat.field == "deploy it")
    check("…a hypothesis that only adds words after the Return goes, though its range starts before it",
          outs[2] == [.text("\ndeploy")] && outs[3] == [.text(" it")])
    check("…and the last pass, which would change the line before the Return, sends nothing", outs[4] == [])
    var d = C()
    var dmac = ""
    var dchat = Chat()
    type(d.replace(NSRange(location: 0, length: 0), with: "send the build\ndeploy", taken: 0), into: &d, mac: &dmac, chat: &dchat)
    let revised = d.replace(NSRange(location: 0, length: 21), with: "send the build\nDeploy it", taken: 0)
    type(revised, into: &d, mac: &dmac, chat: &dchat)
    check("…one that revises a word after the Return as it adds more goes too: what follows the Return in the same text is typed where the caret went",
          revised == [.backspaces(6), .text("Deploy it")] && dmac == "send the build\nDeploy it" && dchat.messages == ["send the build"])
}

do {   // a Tab typed as text: a form goes on to its next field
    var c = C()
    var mac = ""
    type(c.insert("Noah"), into: &c, mac: &mac)
    let taken = c.generation
    let forgot = type(c.insert("\t"), into: &c, mac: &mac)
    check("a Tab typed as text goes, what was typed kept, what came before it final",
          !forgot && mac == "Noah\t" && c.sent == "Noah\t" && c.generation == taken && c.fence == 5)
    let out = c.replace(NSRange(location: 0, length: 4), with: "Noah S", taken: taken)
    check("…so a correction of what came before it sends no backspaces into the next field", out == [] && mac == "Noah\t")
    type(c.insert("Saffer"), into: &c, mac: &mac)
    let next = c.replace(NSRange(location: 5, length: 6), with: "Saffer.", taken: taken)
    type(next, into: &c, mac: &mac)
    check("…and what is typed in the next field is corrected there", next == [.text(".")] && mac == "Noah\tSaffer." && c.sent == mac)
}

do {   // a second Return, and two in one text: the fence moves to just after the last
    var c = C()
    var mac = ""
    var chat = Chat()
    type(c.insert("one\n"), into: &c, mac: &mac, chat: &chat)
    type(c.insert("two"), into: &c, mac: &mac, chat: &chat)
    let two = c.replace(NSRange(location: 4, length: 3), with: "Two", taken: c.generation)
    type(two, into: &c, mac: &mac, chat: &chat)
    check("a line after a Return is corrected as typing is", two == [.backspaces(3), .text("Two")] && c.fence == 4)
    type(c.insert("\n"), into: &c, mac: &mac, chat: &chat)
    check("a second Return moves the fence to just after it", c.fence == 8 && c.sent == "one\nTwo\n")
    check("…so the line between the two is final too",
          c.replace(NSRange(location: 4, length: 3), with: "TWO", taken: c.generation) == [] && chat.messages == ["one", "Two"])
    type(c.insert("a\nb\nc"), into: &c, mac: &mac, chat: &chat)
    check("two Returns in one text: the fence after the second", c.fence == 12)
    check("…the line between them is final",
          c.replace(NSRange(location: 10, length: 1), with: "B", taken: c.generation) == [] && chat.messages == ["one", "Two", "a", "b"])
    let last = c.replace(NSRange(location: 12, length: 1), with: "C", taken: c.generation)
    type(last, into: &c, mac: &mac, chat: &chat)
    check("…what follows the last goes", last == [.backspaces(1), .text("C")] && mac == "one\nTwo\na\nb\nC" && chat.field == "C")
}

do {   // a Return inside the text (dictation's "new line" in a phrase), and one a correction or a candidate brings
    var c = C()
    var mac = ""
    type(c.insert("dear Ann"), into: &c, mac: &mac)
    let taken = c.generation
    let forgot = type(c.insert(",\nthanks"), into: &c, mac: &mac)
    check("text with a Return inside it goes to the Mac whole", mac == "dear Ann,\nthanks")
    check("…what was typed is kept, the fence just after the Return",
          !forgot && c.sent == "dear Ann,\nthanks" && c.generation == taken && c.fence == 10)
    check("…so a correction of what came before the Return sends nothing",
          c.replace(NSRange(location: 0, length: 4), with: "Dear", taken: taken) == [] && mac == "dear Ann,\nthanks")
    let thanks = c.replace(NSRange(location: 10, length: 6), with: "thanks!", taken: taken)
    type(thanks, into: &c, mac: &mac)
    check("…and one of what follows it in the same text goes as before", thanks == [.text("!")] && mac == "dear Ann,\nthanks!")
    let ending = c.replace(NSRange(location: 10, length: 7), with: "Thanks.\n", taken: taken)
    let ended = type(ending, into: &c, mac: &mac)
    check("a correction that brings a Return goes whole and moves the fence after it",
          ending == [.backspaces(7), .text("Thanks.\n")] && !ended && mac == "dear Ann,\nThanks.\n" && c.fence == 18 && c.generation == taken)
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    check("…a composition after it carries on through a correction before it, which sends nothing",
          c.replace(NSRange(location: 0, length: 4), with: "Dear", taken: taken) == [] && c.marked == "ㄋ" && mac == "dear Ann,\nThanks.\n")
    let chosen = type(c.insert("你\n"), into: &c, mac: &mac)
    check("a candidate that brings one replaces the composition, goes whole and moves the fence after it",
          !chosen && mac == "dear Ann,\nThanks.\n你\n" && !c.isComposing && c.sent == mac && c.fence == c.sent.utf16.count)
}

do {   // Zhuyin and Korean right after a Return: the composition and the syllables follow the fence
    var c = C()
    var mac = ""
    type(c.insert("abc\n"), into: &c, mac: &mac)
    c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    c.setMarked("ㄋㄧˇ", selected: NSRange(location: 3, length: 0))
    check("a composition after a Return follows what was sent", c.markedRange == NSRange(location: 4, length: 3) && mac == "abc\n")
    type(c.insert("你"), into: &c, mac: &mac)
    check("…and its candidate goes once", mac == "abc\n你" && c.fence == 4)
    var k = C()
    var kmac = ""
    type(k.insert("한"), into: &k, mac: &kmac)
    type(k.insert("\n"), into: &k, mac: &kmac)
    type(k.insert("ㄱ"), into: &k, mac: &kmac)
    k.select(NSRange(location: 2, length: 1))
    check("a selection after the fence is kept: Korean builds its syllable after a Return", k.selection == NSRange(location: 2, length: 1))
    type(k.deleteBackward(), into: &k, mac: &kmac)
    type(k.insert("그"), into: &k, mac: &kmac)
    k.select(NSRange(location: 2, length: 1))
    type(k.deleteBackward(), into: &k, mac: &kmac)
    type(k.insert("글"), into: &k, mac: &kmac)
    check("…and 한⏎글 reaches the Mac once", kmac == "한\n글" && k.sent == kmac)
    k.select(NSRange(location: 0, length: 1))
    check("one wholly before the fence is not kept: the caret stays at the end",
          k.selection == nil && k.selectedRange == NSRange(location: 3, length: 0))
    k.select(NSRange(location: 0, length: 2))
    check("…nor one that ends at it", k.selection == nil)
    let back = k.deleteBackward()
    type(back, into: &k, mac: &kmac)
    check("…so the next backspace deletes the last character, as the person's own does", back == [.backspaces(1)] && kmac == "한\n")
}

do {   // Korean right after a Return as its input method does it (2-Set on a hardware keyboard, the iPad
       // simulator, 2026-10-27: g k s r m f, Return, g k s): it rebuilds the character before the syllable
       // it is building together with it, so it selects the Return with the syllable, deletes both and types
       // both again; with that selection refused the Mac got a second Return at each of the first
       // syllable's letters
    var c = C()
    var mac = ""
    var chat = Chat()
    for text in ["한", "글", "\n", "ㅎ"] { type(c.insert(text), into: &c, mac: &mac, chat: &chat) }
    c.select(NSRange(location: 2, length: 2))           // "\nㅎ"
    check("a selection that reaches back across the fence from after it is kept", c.selection == NSRange(location: 2, length: 2))
    let deleted = c.deleteBackward()
    type(deleted, into: &c, mac: &mac, chat: &chat)
    check("…its deletion deletes only what follows the fence, the Return left in place here and on the Mac",
          deleted == [.backspaces(1)] && mac == "한글\n" && c.sent == "한글\n" && c.retype == "\n" && c.fence == 3)
    let again = c.insert("\n")
    type(again, into: &c, mac: &mac, chat: &chat)
    check("…the Return the input method types again goes no second time", again == [] && mac == "한글\n" && c.retype.isEmpty)
    type(c.insert("하"), into: &c, mac: &mac, chat: &chat)
    c.select(NSRange(location: 2, length: 2))           // "\n하", for ㄴ
    type(c.deleteBackward(), into: &c, mac: &mac, chat: &chat)
    type(c.insert("\n한"), into: &c, mac: &mac, chat: &chat)
    check("…nor when it comes with the syllable: 한글⏎한 once, one message",
          mac == "한글\n한" && c.sent == mac && chat.messages == ["한글"] && chat.field == "한" && c.fence == 3)
    c.select(NSRange(location: 2, length: 2))
    let over = c.insert("\n하")
    type(over, into: &c, mac: &mac, chat: &chat)
    check("text typed over such a selection that keeps the Return goes as the syllable alone",
          over == [.backspaces(1), .text("하")] && mac == "한글\n하" && chat.messages == ["한글"])
    c.select(NSRange(location: 2, length: 2))
    let changed = c.insert("하")
    check("…and one that would replace the Return sends nothing", changed == [] && c.selection == nil && mac == "한글\n하")
    c.select(NSRange(location: 2, length: 2))
    type(c.deleteBackward(), into: &c, mac: &mac, chat: &chat)
    let other = c.insert("x")
    check("after such a deletion, text that does not start with what it left would change what is final: nothing sent",
          other == [] && mac == "한글\n" && c.sent == mac && c.retype.isEmpty)
    type(c.insert("\t"), into: &c, mac: &mac, chat: &chat)
    c.select(NSRange(location: 2, length: 2))           // the Return and the Tab, all of it final
    check("a selection wholly before the fence is not kept", c.selection == nil)
    var d = C()
    var dmac = ""
    for text in ["ab\n", "c"] { type(d.insert(text), into: &d, mac: &dmac) }
    d.select(NSRange(location: 1, length: 3))           // "b\nc"
    type(d.deleteBackward(), into: &d, mac: &dmac)
    check("what such a deletion left is all of what it took before the fence", d.retype == "b\n" && dmac == "ab\n")
    check("…typed again in pieces, none of it goes again", d.insert("b") == [] && d.retype == "\n" && d.insert("\nC") == [.text("C")])
    d.select(NSRange(location: 1, length: 3))
    type(d.deleteBackward(), into: &d, mac: &dmac)
    d.select(NSRange(location: 3, length: 0))
    check("…an empty selection keeps it", d.retype == "b\n")
    var e = C()
    var emac = ""
    for text in ["ab\n", "cd"] { type(e.insert(text), into: &e, mac: &emac) }
    e.select(NSRange(location: 1, length: 3))           // "b\nc"
    type(e.deleteBackward(), into: &e, mac: &emac)
    check("…(what it left: \"b\\n\", the Mac's \"ab\\nd\")", e.retype == "b\n" && emac == "ab\nd" && e.sent == emac)
    e.select(NSRange(location: 3, length: 1))           // "d", after the fence
    check("…a new selection ends it", e.retype.isEmpty)
    type(e.insert("D"), into: &e, mac: &emac)
    let next = e.insert("b\nY")
    type(next, into: &e, mac: &emac)
    check("…so text typed after it that starts as that did goes whole", next == [.text("b\nY")] && emac == "ab\nDb\nY")
}

do {   // a CRLF, one character of two scalars, and a CR typed apart from the LF after it
    var c = C()
    var mac = ""
    type(c.insert("x\r\ny"), into: &c, mac: &mac)
    check("a CRLF inside the text puts the fence after its LF", c.fence == 3)
    check("…and a correction of the line before it sends nothing", c.replace(NSRange(location: 0, length: 1), with: "X", taken: c.generation) == [])
    var d = C()
    var dmac = ""
    type(d.insert("x\r"), into: &d, mac: &dmac)
    let lf = d.insert("\n")
    type(lf, into: &d, mac: &dmac)
    check("a CR, then the LF typed apart: the LF goes, no backspace over the CR",
          lf == [.text("\n")] && dmac == "x\r\n" && d.sent == "x\r\n" && d.fence == 3)
}

do {   // a forget and a trim: the fence goes with what was typed, and moves with what a trim keeps
    var c = C()
    var mac = ""
    type(c.insert("send the build\n"), into: &c, mac: &mac)
    _ = c.forget()                                        // a click on the Mac
    check("a forget takes the fence with what was typed", c.fence == 0 && c.sent.isEmpty)
    type(c.insert("abc"), into: &c, mac: &mac)
    let typed = c.replace(NSRange(location: 0, length: 3), with: "Abc", taken: c.generation)
    check("…and what is typed after it is corrected from its start", typed == [.backspaces(3), .text("Abc")])
    var t = C()
    _ = t.insert(String(repeating: "字", count: 3_500) + "\n" + String(repeating: "a", count: 600))
    check("a long text with a Return in it wants a trim, the fence after its Return", t.wantsTrim && t.fence == 3_501)
    t.trim()
    check("a trim moves the fence with the text it keeps: just after the same Return",
          t.sent.count == C.keep && t.fence == 400 && Array(t.sent.utf16)[399] == 0x0A && t.generation == 1)
    check("…what came before it still final", t.replace(NSRange(location: 0, length: 1), with: "x", taken: t.generation) == [])
    check("…what follows it revised as before",
          t.replace(NSRange(location: 999, length: 1), with: "b", taken: t.generation) == [.backspaces(1), .text("b")])
    var u = C()
    _ = u.insert(String(repeating: "字", count: 10) + "\n" + String(repeating: "a", count: 3_995))
    u.trim()
    check("a trim that cuts away the Return leaves nothing final", u.fence == 0 && u.sent.count == C.keep
          && u.replace(NSRange(location: 0, length: 1), with: "b", taken: u.generation) == [.backspaces(1_000), .text("b" + String(repeating: "a", count: 999))])
}

do {   // a phrase with no Return or Tab: what was typed is kept, so dictation's correction lands where it was
       // made, as before
    var c = C()
    var mac = ""
    type(c.insert("send the build"), into: &c, mac: &mac)
    let taken = c.generation
    let out = c.replace(NSRange(location: 0, length: 14), with: "Send the build.", taken: taken)
    let forgot = type(out, into: &c, mac: &mac)
    check("a phrase without a Return or a Tab is kept: its correction goes as backspaces and the rest typed",
          !forgot && out == [.backspaces(14), .text("Send the build.")] && mac == "Send the build."
          && c.sent == "Send the build." && c.generation == taken && c.fence == 0)
}
do {   // Korean: the input method selects the syllables it is still building, deletes them and types them
       // again, as each letter comes (2-Set on a hardware keyboard in the iPad simulator, 2026-10-20: g k s
       // r m f, 한글; ignoring the selection, the Mac got 한한한글)
    var c = C()
    var mac = ""
    apply(c.insert("ㅎ"), to: &mac)
    c.select(NSRange(location: 0, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("하"), to: &mac)
    c.select(NSRange(location: 0, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("한"), to: &mac)
    apply(c.insert("ㄱ"), to: &mac)
    c.select(NSRange(location: 0, length: 2))
    check("a selection is kept for the next edit", c.selection == NSRange(location: 0, length: 2) && c.selectedRange == NSRange(location: 0, length: 2))
    let deleted = c.deleteBackward()
    apply(deleted, to: &mac)
    check("a backspace deletes the selection, all of it", deleted == [.backspaces(2)] && mac == "" && c.selection == nil)
    apply(c.insert("한"), to: &mac)
    apply(c.insert("그"), to: &mac)
    c.select(NSRange(location: 1, length: 1))
    apply(c.deleteBackward(), to: &mac)
    apply(c.insert("글"), to: &mac)
    check("Korean's syllables reach the Mac once: 한글", mac == "한글" && c.document == "한글")
}

do {   // a selection's edit, wherever it is, then the caret at the end again
    var c = C()
    var mac = ""
    apply(c.insert("abcd"), to: &mac)
    c.select(NSRange(location: 1, length: 2))           // "bc"
    let out = c.insert("X")
    apply(out, to: &mac)
    check("text typed over a selection replaces it", out == [.backspaces(3), .text("Xd")] && mac == "aXd")
    check("…and the caret is at the end again", c.selection == nil && c.selectedRange == NSRange(location: 3, length: 0))
    c.select(NSRange(location: 1, length: 0))           // the caret moved, nothing selected
    check("an empty selection is not kept: the caret stays at the end", c.selection == nil && c.selectedRange == NSRange(location: 3, length: 0))
    apply(c.insert("e"), to: &mac)
    check("…and typing goes on at the end", mac == "aXde")
    c.select(NSRange(location: 2, length: 99))
    check("a selection past the end is cut at the end", c.selection == NSRange(location: 2, length: 2))
    c.select(NSRange(location: -3, length: 4))
    check("…and one from before the start at the start", c.selection == NSRange(location: 0, length: 1))
    c.select(NSRange(location: 9, length: 2))
    check("…and one wholly past the end is none", c.selection == nil)
    c.select(NSRange(location: 3, length: 1))
    apply(c.replace(NSRange(location: 0, length: 1), with: "A", taken: c.generation), to: &mac)
    check("a correction ends the selection", c.selection == nil && mac == "AXde")
    c.select(NSRange(location: 0, length: 1))
    apply(c.forget(), to: &mac)
    check("a forget ends it", c.selection == nil && c.selectedRange == NSRange(location: 0, length: 0))
    let emoji = c.insert("a👍🏽")
    apply(emoji, to: &mac)
    c.select(utf16Range(c.sent, characters: 1..<2))
    let gone = c.deleteBackward()
    apply(gone, to: &mac)
    check("a selected emoji is one backspace", gone == [.backspaces(1)] && c.sent == "a")
}

do {   // a selection and a composition
    var c = C()
    var mac = ""
    apply(c.insert("ab"), to: &mac)
    c.select(NSRange(location: 1, length: 1))
    let out = c.setMarked("ㄋ", selected: NSRange(location: 1, length: 0))
    apply(out, to: &mac)
    check("a composition over a selection replaces it: the selected text goes from the Mac first",
          out == [.backspaces(1)] && mac == "a" && c.document == "aㄋ" && c.selection == nil)
    c.select(NSRange(location: 0, length: 1))
    check("no selection is kept while an input method composes", c.selection == nil && c.selectedRange == NSRange(location: 2, length: 0))
    apply(c.insert("你"), to: &mac)
    check("…and its candidate follows what was sent", mac == "a你")
    c.select(NSRange(location: 0, length: 1))
    check("an empty composition with nothing composed sends nothing and leaves a selection as it was",
          c.setMarked("", selected: NSRange(location: 0, length: 0)) == [] && c.selection == NSRange(location: 0, length: 1) && mac == "a你")
}

do {   // the tail: kept whole to its limit, trimmed past it, never while composing
    var c = C()
    _ = c.insert(String(repeating: "字", count: C.limit))
    check("a tail of exactly the limit wants no trim", !c.wantsTrim && c.sent.count == C.limit)
    c.trim()
    check("…and a trim then keeps it all, and the document", c.sent.count == C.limit && c.generation == 0)
    _ = c.insert("x")
    check("one character past the limit wants a trim", c.wantsTrim)
    c.setMarked("ㄅ", selected: NSRange(location: 1, length: 0))
    check("no trim while an input method composes", !c.wantsTrim)
    c.trim()
    check("…and a trim then does nothing", c.sent.count == C.limit + 1 && c.marked == "ㄅ" && c.generation == 0)
    c.setMarked(nil, selected: NSRange(location: 0, length: 0))
    let lastCharacter = NSRange(location: c.length - 1, length: 1)
    c.select(lastCharacter)
    c.trim()
    check("a trim ends a selection", c.selection == nil)
    check("a trim keeps the last characters", c.sent.count == C.keep && c.sent.hasSuffix("字x") && !c.wantsTrim)
    check("…and starts a new document", c.generation == 1)
    check("…so a correction taken before it sends nothing",
          c.replace(lastCharacter, with: "y", taken: 0) == [] && c.sent.hasSuffix("字x"))
    check("the limits as documented", C.limit == 4_000 && C.keep == 1_000)
}

do {   // a selection out of range is clamped
    var c = C()
    c.setMarked("ㄋㄧ", selected: NSRange(location: 9, length: 4))
    check("the marked selection stays inside the composition", c.selectedRange == NSRange(location: 2, length: 0))
    c.setMarked("ㄋㄧ", selected: NSRange(location: 1, length: 9))
    check("…and so does its length", c.selectedRange == NSRange(location: 1, length: 1))
}

// MARK: - Which input moves the Mac's caret

check("a click moves the caret", R.movesCaret(.pointer(.leftDown, x: 0.5, y: 0.5)))
check("a right click moves the caret", R.movesCaret(.pointer(.rightDown, x: 0.5, y: 0.5)))
check("a pointer move does not", !R.movesCaret(.pointer(.move, x: 0.5, y: 0.5)))
check("a button's up does not", !R.movesCaret(.pointer(.leftUp, x: 0.5, y: 0.5)) && !R.movesCaret(.pointer(.rightUp, x: 0.5, y: 0.5)))
check("a key going down does (an arrow, a shortcut, a modifier)",
      R.movesCaret(.key(hidUsage: 0x50, down: true, modifiers: 0)) && R.movesCaret(.key(hidUsage: 0xE3, down: true, modifiers: R.command)))
check("a key going up does not", !R.movesCaret(.key(hidUsage: 0x50, down: false, modifiers: 0)))
check("typed text does not, a backspace among it",
      !R.movesCaret(.text("a")) && !R.movesCaret(.text("\u{8}")) && !R.movesCaret(.text("send the build")) && !R.movesCaret(.text("你好")))
check("nor does a Return or a Tab typed as text: what was typed is kept, what came before it made final (the fence)",
      !R.movesCaret(.text("\n")) && !R.movesCaret(.text("\t")) && !R.movesCaret(.text("\r"))
      && !R.movesCaret(.text("dear Ann,\nthanks")) && !R.movesCaret(.text("a\r\nb")))
check("where a Return or a Tab typed ends: just after the last one, in UTF-16 units, alone or among other text",
      R.endOfReturnOrTab(in: "\n") == 1 && R.endOfReturnOrTab(in: "\t") == 1 && R.endOfReturnOrTab(in: "\r") == 1
      && R.endOfReturnOrTab(in: "done.\n") == 6 && R.endOfReturnOrTab(in: "dear Ann,\nthanks") == 10
      && R.endOfReturnOrTab(in: "\tindented") == 1 && R.endOfReturnOrTab(in: "a\nb\tc") == 4 && R.endOfReturnOrTab(in: "👍🏽\nx") == 5)
check("…a CRLF after its LF, one Character of two scalars", R.endOfReturnOrTab(in: "a\r\nb") == 3 && R.carriesReturnOrTab("\r\n"))
check("…none in text without one", R.endOfReturnOrTab(in: "send the build") == nil && !R.carriesReturnOrTab("send the build")
      && R.carriesReturnOrTab("done.\n") && R.carriesReturnOrTab("\tx"))
check("…and nothing else that is blank", !R.carriesReturnOrTab(" ") && !R.carriesReturnOrTab("\u{A0}") && !R.carriesReturnOrTab("\u{3000}") && !R.carriesReturnOrTab(""))
check("a scroll does not", !R.movesCaret(.scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1)))
check("a scroll's phases do not", [ScrollPhase.began, .ended, .momentumBegan, .momentumEnded].allSatisfy { !R.movesCaret(.scrollGesture($0, x: 0.5, y: 0.5)) })

// MARK: - Keyboards and ⌃Space

check("a language's keyboard is a keyboard", R.isKeyboard("en-US") && R.isKeyboard("zh-Hant") && R.isKeyboard("ja-JP"))
check("Emoji and dictation are not", !R.isKeyboard("emoji") && !R.isKeyboard("dictation"))

let capsLock: UInt64 = 1 << 16, numericPad: UInt64 = 1 << 21
func switches(_ modifiers: UInt64, _ keyboards: [String], usage: UInt16 = R.space) -> Bool {
    R.isKeyboardSwitch(usage: usage, modifiers: modifiers, keyboards: keyboards)
}
let two = ["en-US", "zh-Hant", "emoji"]
check("⌃Space with two keyboards is iPadOS's switch", switches(R.control, two))
check("…with caps lock on too", switches(R.control | capsLock, two) && switches(R.control | numericPad, two))
check("⌃Space with one keyboard (and Emoji) is the Mac's", !switches(R.control, ["en-US", "emoji"]))
check("…with one keyboard, Emoji and dictation, the Mac's", !switches(R.control, ["en-US", "emoji", "dictation"]))
check("…with no keyboard listed, the Mac's", !switches(R.control, []))
check("a third-party keyboard in the same language counts once", !switches(R.control, ["en-US", "en-US", "emoji"]))
check("two layouts of one language set up in two languages' keyboards switch", switches(R.control, ["en-US", "en-GB"]))
check("three keyboards switch", switches(R.control, ["en-US", "zh-Hant", "ja-JP"]))
check("⌃⇧Space is the Mac's", !switches(R.control | R.shift, two))
check("⌃⌥Space and ⌃⌘Space are the Mac's", !switches(R.control | R.option, two) && !switches(R.control | R.command, two))
check("Space alone, ⇧Space, ⌥Space and ⌘Space are not the switch",
      !switches(0, two) && !switches(R.shift, two) && !switches(R.option, two) && !switches(R.command, two))
check("⌃ with another key is not the switch", !switches(R.control, two, usage: 0x2B) && !switches(R.control, two, usage: 0x04))
var keyboardsAsked = 0
func keyboards() -> [String] { keyboardsAsked += 1; return two }
_ = R.isKeyboardSwitch(usage: 0x04, modifiers: R.control, keyboards: keyboards())
_ = R.isKeyboardSwitch(usage: R.space, modifiers: 0, keyboards: keyboards())
_ = R.isKeyboardSwitch(usage: R.space, modifiers: R.command, keyboards: keyboards())
check("the keyboards are asked for only for ⌃Space, not for every key", keyboardsAsked == 0)
_ = R.isKeyboardSwitch(usage: R.space, modifiers: R.control, keyboards: keyboards())
check("…and are for it", keyboardsAsked == 1)
check("Space's usage", R.space == 0x2C)
check("the modifier bits are UIKeyModifierFlags'", R.shift == 1 << 17 && R.control == 1 << 18 && R.option == 1 << 19 && R.command == 1 << 20)

// MARK: - Who types a hardware keyboard's characters (KeyTyping, #162's letters)

typealias T = KeyTyping
func typing(_ mode: String?, _ keyboards: [String] = [], composing: Bool = false, latched: Bool = false, macRepeats: Bool = true) -> T {
    T.of(inputMode: mode, keyboards: keyboards, composing: composing, latched: latched, macRepeats: macRepeats)
}
// The Latin alphabet typed directly: the Mac types (its own layout, dead keys and key repeat).
let latin = ["en-US", "en", "en-GB", "en-AU", "en_US", "fr-FR", "fr-CA", "de-DE", "de-CH", "es-ES", "es-MX", "pt-BR", "it-IT",
             "nl-NL", "sv-SE", "nb-NO", "da-DK", "fi-FI", "pl-PL", "cs-CZ", "hu-HU", "ro-RO", "tr-TR", "az", "uz", "sr-Latn",
             "hi-Latn", "mi", "id-ID", "ms-MY", "fil", "ca", "ga", "cy"]
check("a keyboard in the Latin alphabet: the Mac types its characters (\(latin.filter { typing($0) != .keys }))",
      latin.allSatisfy { typing($0) == .keys && T.typesOnMac($0) })
// An input method's keyboard, which composes or may: iPadOS's text system, so its first key reaches it. In
// the Latin alphabet, those whose input manager composes text (TextInput's doesComposeText in the iOS 27.0
// simulator runtime): Vietnamese and Hawaiian; every other one is in another script (the transliteration
// keyboards' languages, Ainu's Katakana and the Cree syllabics among them).
let composes = ["zh-Hans", "zh-Hant", "zh-Hans-CN", "zh-Hant-TW", "zh-Hant-HK", "yue-Hant", "ja-JP", "ja", "ko-KR", "ko", "vi", "vi-VN",
                "haw", "haw-US", "ain", "crk", "crj", "csw", "hi-Translit", "kn-Translit", "ur-Translit"]
check("an input method's keyboard (Chinese, Cantonese, Japanese, Korean, Vietnamese, Hawaiian, transliteration): iPadOS types (\(composes.filter { typing($0) != .text }))",
      composes.allSatisfy { typing($0) == .text && !T.typesOnMac($0) })
check("the Latin alphabet's composing keyboards are Vietnamese's and Hawaiian's", T.composingLatin == ["vi", "haw"])
// Keyboards in the Latin alphabet that compose a letter with its accents (UIKeyboardComposesText, some with a
// composition map for their on-screen layout: Czech, Slovak, Faroese, Samoan, Tongan, Navajo, Guarani, Kabyle,
// Mi'kmaq…) and no input manager of their own: the Mac types, as for every Latin keyboard. A hardware
// keyboard's dead keys make those, and the Mac's input source has its own (DEVELOPMENT.md).
let onScreenAccents = ["cs-CZ", "sk-SK", "fo", "sm", "to", "nv", "gn", "kab-Latn", "mic", "atj", "gwi", "dgr"]
check("a Latin keyboard that composes a letter with its accents: the Mac types (\(onScreenAccents.filter { typing($0) != .keys }))",
      onScreenAccents.allSatisfy { typing($0) == .keys })
// Another script: iPadOS's text system, whose keyboard says which script is meant.
let scripts = ["ru-RU", "uk-UA", "be", "bg", "sr", "sr-Cyrl", "mk", "kk", "mn", "el-GR", "he-IL", "ar", "ar-SA", "fa", "ur", "th-TH",
               "hi", "hi-IN", "bn", "gu", "mr", "pa", "ta", "te", "ka", "hy", "am", "my", "km", "lo", "si", "bo", "chr", "ug"]
check("a keyboard in another script (Cyrillic, Greek, Hebrew, Arabic, Thai, the Indic scripts…): iPadOS types (\(scripts.filter { typing($0) != .text }))",
      scripts.allSatisfy { typing($0) == .text && !T.typesOnMac($0) })
check("Emoji, dictation and a language Foundation does not know: iPadOS types",
      ["emoji", "dictation", "", "xx-YY", "mul"].allSatisfy { typing($0) == .text && !T.typesOnMac($0) })
// Composing comes first, then the latch.
check("marked text: the input method composes, whatever the keyboard",
      ["en-US", "zh-Hant", "ru-RU", "emoji"].allSatisfy { typing($0, composing: true) == .composing && typing($0, composing: true, latched: true) == .composing }
      && typing(nil, ["en-US"], composing: true) == .composing)
// A Mac from before key repeat (its window list says no keyRepeat): iPadOS types, as before, whatever the
// keyboard, since that Mac would type each key once where iPadOS repeats Delete and Space; marked text still first.
check("a Mac that repeats no key: iPadOS types, whatever the keyboard",
      (latin + composes + scripts + ["emoji"]).allSatisfy { typing($0, macRepeats: false) == .text }
      && typing(nil, ["en-US"], macRepeats: false) == .text && typing("en-US", latched: true, macRepeats: false) == .text)
check("…and marked text is the input method's whatever the Mac", typing("zh-Hant", composing: true, macRepeats: false) == .composing
      && typing("en-US", composing: true, macRepeats: false) == .composing)
check("a modifier latched on the key row: iPadOS types, so the character makes the latched shortcut as before",
      typing("en-US", latched: true) == .text && typing("fr-FR", latched: true) == .text && typing(nil, ["en-US"], latched: true) == .text)
// No keyboard selected (iPadOS gives none): the keyboards set up decide, Emoji and dictation aside.
check("none selected, only Latin keyboards set up: the Mac types",
      typing(nil, ["en-US"]) == .keys && typing(nil, ["en-US", "fr-FR", "emoji", "dictation"]) == .keys)
check("none selected, an input method's or another script's keyboard among them: iPadOS types",
      typing(nil, ["en-US", "zh-Hant"]) == .text && typing(nil, ["ru-RU", "en-US"]) == .text && typing(nil, ["ja-JP"]) == .text)
check("none selected and none set up (or only Emoji and dictation): iPadOS types",
      typing(nil, []) == .text && typing(nil, ["emoji"]) == .text && typing(nil, ["emoji", "dictation"]) == .text)
var setUpAsked = 0
func setUp() -> [String] { setUpAsked += 1; return ["en-US"] }
_ = T.of(inputMode: "en-US", keyboards: setUp(), composing: false, latched: false, macRepeats: true)
_ = T.of(inputMode: "zh-Hant", keyboards: setUp(), composing: false, latched: false, macRepeats: true)
_ = T.of(inputMode: nil, keyboards: setUp(), composing: true, latched: false, macRepeats: true)
_ = T.of(inputMode: nil, keyboards: setUp(), composing: false, latched: false, macRepeats: false)
check("the keyboards set up are asked for only when none is selected", setUpAsked == 0)
_ = T.of(inputMode: nil, keyboards: setUp(), composing: false, latched: false, macRepeats: true)
check("…and are then", setUpAsked == 1)
// Whether the session's Mac repeats a held key, by its window list's `keyRepeat` (the stream screens'
// `macRepeatsKeys`): any generation from 1, so a later one is sent the characters as keys too; none
// (a Mac from before key repeat) and 0, never.
check("the Mac repeats held keys from keyRepeat 1 on, a later generation too; nil and 0 never",
      !T.macRepeats(keyRepeat: nil) && !T.macRepeats(keyRepeat: 0) && T.macRepeats(keyRepeat: 1) && T.macRepeats(keyRepeat: 2)
      && T.macRepeats(keyRepeat: 7))

// MARK: - Random edit sequences

/// SplitMix64: the same sequences on every run, so a failure can be run again.
struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
var generator = Seeded(state: 0x5111_0138)

/// `type`, also saying how short the Mac's text got (UTF-16 units) as the outputs went, so a backspace
/// that reached into what was final shows, and whether a text among them carried a Return or a Tab.
@discardableResult
func typeLow(_ outputs: [C.Output], into c: inout C, mac: inout String) -> (forgot: Bool, low: Int, returned: Bool) {
    var low = mac.utf16.count
    var forgot = false, returned = false
    for output in outputs {
        forgot = type([output], into: &c, mac: &mac) || forgot
        low = min(low, mac.utf16.count)
        if case .text(let text) = output, R.carriesReturnOrTab(text) { returned = true }
    }
    return (forgot, low, returned)
}

/// `runs` sequences of 12 edits each from `alphabet`, with selections among them, and forgets, stale
/// corrections, corrections of what is final and trims when `forgets`, each edit's outputs going to the
/// Mac as the app sends them (`type`), against a model of the Mac's text field: it always ends with
/// what is remembered, and is exactly that while nothing was forgotten; a new document (`generation`)
/// comes with a forget or a trim, and only then (a Return or a Tab typed starts none); what was sent
/// before the fence is never changed or deleted on the Mac but by the person's own backspace, which
/// alone takes the fence back, and what follows the fence never holds a Return or a Tab; a selection is
/// never empty, never while composing, inside what was sent and not wholly before the fence, and gone
/// after an edit; what a selection's deletion left before the fence is the end of what is final.
/// The first failure is printed; the number of failed runs, of stale corrections tried (past the end,
/// and taken in a document since forgotten), of selections an edit replaced, of edits that sent a
/// Return or a Tab (each moving the fence after it), of corrections of what is final (none of which
/// sent anything), and of selections reaching back across the fence that a backspace or a composition
/// deleted (what is final left in place), are returned.
func randomRuns(_ runs: Int, alphabet: [String], forgets: Bool) -> (fails: Int, stale: Int, taken: Int, replaced: Int, fenced: Int, refused: Int, crossed: Int) {
    func word() -> String { (0..<Int.random(in: 1...3, using: &generator)).map { _ in alphabet.randomElement(using: &generator)! }.joined() }
    var failed = 0, staleTried = 0, takenTried = 0, replaced = 0, fenced = 0, refused = 0, crossed = 0
    var firstFailure: String?
    for run in 0..<runs {
        var c = C()
        var mac = ""
        var everReset = false
        var stale: NSRange?
        var taken: (range: NSRange, generation: Int)?
        for step in 0..<12 {
            let before = c
            let macBefore = mac
            // The Mac's units that are final: what it had from before what is remembered, and what is
            // remembered up to the fence.
            let final = macBefore.utf16.count - before.sent.utf16.count + before.fence
            var why: String?
            var low = mac.utf16.count
            var returned = false
            var rebuilt = false
            let op = forgets ? Int.random(in: 0..<12, using: &generator) : [0, 1, 2, 3, 4, 9].randomElement(using: &generator)!
            switch op {
            case 0: (_, low, returned) = typeLow(c.insert(word()), into: &c, mac: &mac)
            case 1:
                let w = word()
                (_, low, returned) = typeLow(c.setMarked(w, selected: NSRange(location: Int.random(in: 0...w.utf16.count, using: &generator), length: 0)), into: &c, mac: &mac)
                if let selected = before.selection {
                    // What of it follows the fence, when it reaches back across it.
                    let from = max(selected.location, before.fence)
                    let gone = NSRange(location: from, length: selected.location + selected.length - from)
                    if c.sent != (before.sent as NSString).replacingCharacters(in: gone, with: "") {
                        why = "a composition over a selection did not replace it"
                    }
                } else if c.sent != before.sent { why = "a composition changed what was sent" }
            case 2: (_, low, returned) = typeLow(c.unmark(), into: &c, mac: &mac)
            case 3: (_, low, returned) = typeLow(c.deleteBackward(), into: &c, mac: &mac)
            case 4:
                // Whole characters only: UIKit's ranges never split one.
                let chars = Array(c.document)
                let a = Int.random(in: 0...chars.count, using: &generator)
                let b = Int.random(in: a...chars.count, using: &generator)
                let range = utf16Range(c.document, characters: a..<b)
                if c.length > 0, stale == nil { stale = NSRange(location: c.length + 1, length: Int.random(in: 0...3, using: &generator)) }
                if taken == nil { taken = (range, c.generation) }
                let replacement = word()
                let refusal = c.refusal(range, with: replacement, taken: c.generation)
                let out = c.replace(range, with: replacement, taken: c.generation)
                (_, low, returned) = typeLow(out, into: &c, mac: &mac)
                if refusal != nil {
                    refused += 1
                    if refusal != .final || out != [] || c != before { why = "a correction refused for what is final changed something" }
                }
            case 5:
                // As the input view's own forget sends it: what was composed goes with it, and there is
                // nothing left to forget after it.
                let forgot = typeLow(c.forget(), into: &c, mac: &mac)
                low = forgot.low
                everReset = true
                if c.isComposing { why = "a forget kept the composition on the device" }
                else if let composed = before.marked, !mac.hasSuffix(before.sent + composed) {
                    why = "a forget lost what was composed"
                } else if forgot.forgot { why = "a forget's own composition made the input view forget again" }
            case 6:
                // A correction whose range the text system took before a forget: past the document's end.
                guard let range = stale, range.location > c.length else { break }
                staleTried += 1
                let out = c.replace(range, with: word())
                if out != [] || c != before { why = "a stale correction changed something" }
            case 7:
                c.trim()
                everReset = everReset || c.sent != before.sent
            case 8:
                // A correction whose range the text system took in a document since forgotten, wherever
                // its offsets fall now (inside what was typed since, too).
                guard let (range, generation) = taken, generation != c.generation else { break }
                takenTried += 1
                let out = c.replace(range, with: word(), taken: generation)
                if out != [] || c != before { why = "a correction taken before a forget changed something" }
            case 9:
                // A selection of whole characters of what was sent (UIKit's never split one), or the caret
                // moved inside it: half of them in what follows the fence, as an input method's own are
                // (Korean's syllables after a Return), the rest anywhere.
                let chars = Array(c.sent)
                let finalCharacters = String(utf16CodeUnits: Array(c.sent.utf16.prefix(c.fence)), count: c.fence).count
                let a = Int.random(in: (Bool.random(using: &generator) ? finalCharacters : 0)...chars.count, using: &generator)
                let b = Int.random(in: a...chars.count, using: &generator)
                c.select(utf16Range(c.sent, characters: a..<b))
                if c.sent != before.sent || c.marked != before.marked { why = "a selection changed the document" }
            case 10:
                // A correction whose first change falls before the fence (dictation's last pass over a phrase
                // a Return or a Tab followed), from anywhere in what is final to anywhere after it.
                guard c.fence > 0 else { break }
                let finalCharacters = String(utf16CodeUnits: Array(c.sent.utf16.prefix(c.fence)), count: c.fence).count
                let chars = Array(c.document)
                let a = Int.random(in: 0..<finalCharacters, using: &generator)
                let b = Int.random(in: a...chars.count, using: &generator)
                refused += 1
                let out = c.replace(utf16Range(c.document, characters: a..<b), with: "¶" + word(), taken: c.generation)
                if out != [] || c != before { why = "a correction of what is final changed something" }
            case 11:
                // Korean's rebuild right after a Return: the last characters before the fence selected with
                // what follows it, deleted, then typed again with the next text, or not.
                guard c.fence > 0, !c.isComposing, c.fence < c.sent.utf16.count else { break }
                let finalCharacters = String(utf16CodeUnits: Array(c.sent.utf16.prefix(c.fence)), count: c.fence).count
                let chars = Array(c.sent)
                let a = Int.random(in: max(finalCharacters - 2, 0)..<finalCharacters, using: &generator)
                let selected = utf16Range(c.sent, characters: a..<chars.count)
                let kept = String(utf16CodeUnits: Array(Array(c.sent.utf16)[selected.location..<c.fence]), count: c.fence - selected.location)
                let afterFence = String(utf16CodeUnits: Array(c.sent.utf16.dropFirst(c.fence)), count: c.sent.utf16.count - c.fence).count
                c.select(selected)
                rebuilt = true
                let deleted = c.deleteBackward()
                low = typeLow(deleted, into: &c, mac: &mac).low
                crossed += 1
                let w = word()
                let retyped = Bool.random(using: &generator)
                let out = c.insert(retyped ? kept + w : w)
                low = min(low, typeLow(out, into: &c, mac: &mac).low)
                if deleted != [.backspaces(afterFence)] || c.sent.utf16.count < before.fence {
                    why = "a selection reaching back across the fence deleted what was final"
                } else if retyped, out != [C.Output.text(w)] {
                    why = "what a selection's deletion left was typed again, or the rest not"
                } else if !retyped, !w.hasPrefix(kept), !kept.hasPrefix(w), out != [] {
                    why = "text in place of what was final went"
                }
            default: break
            }
            let unchanged = c == before
            if why == nil, let selected = c.selection,
               c.isComposing || selected.length == 0 || selected.location + selected.length > c.sent.utf16.count
                || selected.location + selected.length <= c.fence {
                why = "a selection while composing, empty, past what was sent or wholly before the fence"
            }
            if why == nil, !c.retype.isEmpty,
               !String(utf16CodeUnits: Array(c.sent.utf16.prefix(c.fence)), count: c.fence).hasSuffix(c.retype) {
                why = "what a selection's deletion left is not the end of what is final"
            }
            if why == nil, [0, 3, 4, 5].contains(op), c.selection != nil, !unchanged { why = "an edit or a forget kept the selection" }
            if before.selection != nil, [0, 1, 3].contains(op) { replaced += 1 }
            if let selected = before.selection, selected.location < before.fence, op == 1 || op == 3 { crossed += 1 }
            if rebuilt, c.selection != nil { why = why ?? "a rebuild kept its selection" }
            let newDocument = op == 5 || (op == 7 && before.wantsTrim)
            if why == nil, c.generation != before.generation + (newDocument ? 1 : 0) {
                why = "the document's generation moved without a forget or a trim, or stayed through one"
            }
            if why == nil, c.fence < 0 || c.fence > c.sent.utf16.count { why = "the fence outside what was sent" }
            if why == nil, R.carriesReturnOrTab(String(utf16CodeUnits: Array(c.sent.utf16.dropFirst(c.fence)), count: c.sent.utf16.count - c.fence)) {
                why = "a Return or a Tab typed after the fence"
            }
            // Only the person's own backspace reaches into what is final (an edit of the text system never
            // does), and only it, a forget and a trim take the fence back.
            let personsBackspace = op == 3 && before.selection == nil && !before.isComposing
            if why == nil, !personsBackspace, op != 5, op != 7 {
                if low < final || !Array(mac.utf16).starts(with: Array(macBefore.utf16).prefix(final)) {
                    why = "an edit's backspaces reached into what was final"
                } else if c.fence < before.fence {
                    why = "the fence went back without the person's backspace, a forget or a trim"
                }
            }
            if returned, op != 5 {
                fenced += 1
                if why == nil, c.fence <= before.fence { why = "a Return or a Tab sent left the fence where it was" }
            }
            if why == nil, c.length != c.document.utf16.count { why = "the length is not the document's" }
            if why == nil, !mac.hasSuffix(c.sent) { why = "the Mac's text does not end with what is remembered" }
            if why == nil, !everReset, mac != c.sent { why = "with nothing forgotten, the Mac's text is not what was sent" }
            if why == nil, let m = c.markedRange, m.location != c.sent.utf16.count { why = "the composition does not follow what was sent" }
            if let why {
                failed += 1
                if firstFailure == nil { firstFailure = "run \(run), step \(step): \(why) (Mac \(mac.debugDescription), sent \(c.sent.debugDescription), fence \(c.fence))" }
                break
            }
        }
    }
    if let firstFailure { print("     \(firstFailure)") }
    return (failed, staleTried, takenTried, replaced, fenced, refused, crossed)
}

// Forgets among the edits. No lone combining mark here: one typed right after a forget joins a
// character the Mac has from before it, which this side never knew (the model's suffix would not hold).
// No lone CR either: an LF typed after it joins it, one character on the Mac (the scenarios have it).
let forgetful = randomRuns(20_000, alphabet: ["a", "b", "你", "好", "ㄋ", "ˇ", "👍🏽", "é", "e", " ", "\n", "\t", "\r\n"], forgets: true)
check("20,000 seeded random sequences: the Mac's text always ends with what is remembered, and is it while nothing was forgotten",
      forgetful.fails == 0)
check("…stale corrections among them (\(forgetful.stale) past the end, \(forgetful.taken) taken before a forget), none of which sent anything",
      forgetful.stale > 1_000 && forgetful.taken > 1_000)
check("…and \(forgetful.replaced) selections replaced by the next insert, backspace or composition", forgetful.replaced > 500)
check("…and \(forgetful.fenced) edits that sent a Return or a Tab, each making what came before it final", forgetful.fenced > 1_000)
check("…and \(forgetful.refused) corrections of what was final, none of which sent anything", forgetful.refused > 1_000)
check("…and \(forgetful.crossed) selections reaching back across the fence deleted (Korean's rebuild after a Return among them), what was final left in place",
      forgetful.crossed > 1_000)
// No forget: a combining mark that joins the character before it is retyped with it.
let joining = randomRuns(5_000, alphabet: ["a", "e", "\u{301}", "👍", "\u{1F3FD}", "ㄋ", "ˇ", " "], forgets: false)
check("5,000 seeded random sequences with combining marks and skin tones: the Mac's text is what was sent",
      joining.fails == 0 && joining.fenced == 0 && joining.refused == 0)
check("…\(joining.replaced) selections among them replaced", joining.replaced > 500)

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
