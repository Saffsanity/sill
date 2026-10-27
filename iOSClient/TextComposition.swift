import Foundation
// In the app StreamProtocol is its own module; the text-composition check compiles this file together
// with Sources/StreamProtocol/Input.swift as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

// What the stream's input view holds for iPadOS's text system (#138): the text an input method is
// still composing (Zhuyin's ㄋㄧˇ, Pinyin's nihao, Japanese kana before conversion), kept on the device
// and sent only once chosen (or, as it stands, when the Mac's caret is about to move or the input view
// lets go of it), and what was typed since the Mac's caret was last moved by something else, so
// dictation and an input method can revise what they put there (a dictated word corrected a moment
// later: backspaces on the Mac, then the new text; Korean's syllables built again as each letter comes,
// through a selection: `selection`), all but what went before a Return or a Tab typed, which is final
// on the Mac (`fence`). Beside it, `TextInputRules`: which input moves the Mac's caret, where a Return
// or a Tab typed ends, and whose ⌃Space it is.
//
// Pure: Foundation and StreamProtocol's InputEvent only, checked on its own with swiftc
// (Tests/checks/text-composition). Offsets are UTF-16, as UITextInput's are; the Mac is sent whole
// characters.

struct TextComposition: Equatable {
    /// What goes to the Mac: text, or that many backspaces (each one deletes one character there).
    enum Output: Equatable {
        case text(String)
        case backspaces(Int)
    }

    /// Why a correction (`replace`) sends nothing, in the words the input view's Debug line uses.
    enum Refusal: String, Equatable {
        /// Its range was taken before a forget or a trim (`generation`).
        case forgotten = "a range taken before a forget or a trim"
        /// Its range starts past the end of the document: built again from offsets kept from before a
        /// forget or a trim.
        case pastEnd = "a range that starts past what was typed"
        /// It would change what went to the Mac before a Return or a Tab typed (`fence`).
        case final = "it would change what went before a Return or a Tab typed"
    }

    /// What was sent since the last `forget`, which the text system may still revise but before the
    /// `fence`. Kept whole while it may: the text system's offsets point into it, and cutting its front
    /// in the middle of an edit moved every offset under a correction still to come (dictation's, say,
    /// past 200 characters), which then landed at the end and typed the corrected words a second time.
    /// Past `limit` the input view trims it (`trim`), between edits, with the text system told.
    private(set) var sent = ""
    /// The text being composed, never sent while it is; nil when nothing is.
    private(set) var marked: String?
    /// The selection inside the marked text, relative to its start (UTF-16).
    private(set) var markedSelection = NSRange(location: 0, length: 0)
    /// What the text system selected of what was sent (UTF-16), for its next edit, which replaces it as in
    /// any text field: Korean's input method selects the syllables it is still building, deletes them and
    /// types them again (한ㄱ selected, deleted, then 한 and 그 typed; with the selection ignored, 한글
    /// reached the Mac as 한한한글 in the iPad simulator, 2026-10-20), and the text system selects the
    /// character a backspace deletes. Never empty, never while composing, and never wholly before the
    /// `fence` (one that only starts before it is kept: `retype`): nil is the caret at the end, where every
    /// edit, a forget and a trim put it back. An empty selection elsewhere (the caret moved, as the
    /// on-screen keyboard's trackpad does) is not kept: the Mac's caret cannot be moved from here.
    private(set) var selection: NSRange?
    /// Which document the text system's positions were taken in: each `forget` and each trim
    /// starts a new one, as every offset moves then. A correction whose range was taken in an older one
    /// is stale wherever its offsets fall now (`replace`). A Return or a Tab typed starts none: it keeps
    /// the document and every offset, and sets the `fence`.
    private(set) var generation = 0
    /// Where what was sent stops being final (UTF-16, into `sent`): just after the last Return or Tab
    /// typed as text (a hardware one without shift, the on-screen keyboard's return key, dictation's "new
    /// line"; alone or anywhere inside other text: `TextInputRules.endOfReturnOrTab`). What lies before it,
    /// the Return or the Tab included, may be past the Mac's caret now (a chat sent the line, a terminal
    /// ran the command, a form went on to its next field), so nothing the text system does reaches into
    /// it: a correction that would change it sends nothing (`replace`), a selection that starts in it is
    /// not kept (`select`), and the backspaces an edit sends stop at it (`commit`). Only the person's own
    /// backspace goes back across it, and takes it back to what is left (`deleteBackward`), so what was
    /// before the deleted Return stays final too. What follows it, in the same text or typed later, is
    /// typed where the caret went and is revised as any typing is, and the document and every offset the
    /// text system holds are kept across it: dictation's "new line" said in the middle of what it is
    /// typing loses none of its words. 0 when nothing is final; a forget puts it back at 0, a trim moves
    /// it with the text it keeps.
    private(set) var fence = 0
    /// What a selection that reached back across the fence would have deleted before it, which its
    /// deletion left in place, here and on the Mac: Korean's input method rebuilds the character before
    /// the syllable it is building together with it, so right after a Return it selects that Return with
    /// the syllable, deletes both and types both again (한글⏎, then ㅎ and ㅏ: "\nㅎ" selected, deleted,
    /// then "\n" and "하" typed; the iPad simulator, 2026-10-27, where the refused selection let a second
    /// "\n" through). Only what followed the fence goes from the Mac; text typed next that starts with
    /// this is not typed again, and text that does not would change what is final, and sends nothing.
    /// Empty but right after such a deletion; the next edit, and a new selection, end it.
    private(set) var retype = ""

    /// Past this many characters, the tail is due a trim (`wantsTrim`): only a long stretch of typing or
    /// dictation with no click, key or pick in it gets there.
    static let limit = 4_000
    /// What a trim keeps, in characters: more than any correction dictation or an input method makes.
    static let keep = 1_000

    /// The document the text system sees: what was sent, then what is being composed.
    var document: String { sent + (marked ?? "") }
    var length: Int { sent.utf16.count + (marked?.utf16.count ?? 0) }
    var isComposing: Bool { marked != nil }

    var markedRange: NSRange? {
        marked.map { NSRange(location: sent.utf16.count, length: $0.utf16.count) }
    }

    /// The caret is at the end, or where the input method put it inside the marked text, or what the text
    /// system selected for its next edit.
    var selectedRange: NSRange {
        guard marked != nil else { return selection ?? NSRange(location: length, length: 0) }
        return NSRange(location: sent.utf16.count + markedSelection.location, length: markedSelection.length)
    }

    /// The text system selects `range` of the document for its next edit: kept, inside what was sent,
    /// when it selects something while nothing is being composed (the input method's own selection is
    /// the marked text's then); an empty one, the caret moved, puts the caret back at the end, and so does
    /// one wholly before the fence, in what is final on the Mac (the next edit then goes at the end: the
    /// text system selects the character a backspace deletes, so the person's backspace right after a
    /// Return deletes that Return, as asked). One that reaches back across the fence from after it is
    /// kept: its deletion leaves what is final in place (`retype`).
    mutating func select(_ range: NSRange) {
        guard marked == nil else { return }
        let count = sent.utf16.count
        let start = min(max(range.location, 0), count)
        let end = min(max(range.location + range.length, start), count)
        selection = end > start && end > fence ? NSRange(location: start, length: end - start) : nil
        if selection != nil { retype = "" }
    }

    /// Text typed or committed: it replaces the marked text if there is any, else the selection if there
    /// is one, and goes to the Mac. Over a selection that reaches back across the fence it goes only
    /// while it leaves what is final as it is; right after such a selection's deletion, what it starts
    /// with of what that deletion left in place (`retype`) is not typed again.
    mutating func insert(_ text: String) -> [Output] {
        if marked == nil, let selection {
            let new = sentReplacing(selection, with: text)
            guard keepsFinal(new) else { self.selection = nil; return [] }
            return commit(new)
        }
        guard let rest = typedAfterRetype(text) else { return [] }
        return commit(sent + rest)
    }

    /// The input method's composition so far (an empty one ends it: nothing is sent). One that starts
    /// over a selection replaces it, as in a text field: the selected text goes from the Mac first (what
    /// of it follows the fence, when the selection reaches back across it, nothing held back for the
    /// composition), and the composition follows what was sent, as every composition does here.
    @discardableResult
    mutating func setMarked(_ text: String?, selected: NSRange) -> [Output] {
        guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); return [] }
        var out: [Output] = []
        if marked == nil, let selection { out = deleteSelection(selection) }
        retype = ""
        marked = text
        let count = text.utf16.count
        let location = min(max(selected.location, 0), count)
        markedSelection = NSRange(location: location, length: min(max(selected.length, 0), count - location))
        return out
    }

    /// The composition is accepted as it stands: sent.
    mutating func unmark() -> [Output] {
        guard let marked else { return [] }
        retype = ""
        return commit(sent + marked)
    }

    /// Backspace: inside a composition it edits the composition; otherwise it deletes the selection if
    /// there is one, else one backspace to the Mac, whether or not this side still remembers what it
    /// deletes. It is the person's (the on-screen keyboard's, a hardware one's without ⌘, ⌃ or ⌥, both
    /// as text), the one edit that goes back across the fence: deleting the Return typed last deletes it
    /// on the Mac as the person asked (in an editor it joins the lines; in a chat that sent the line it
    /// deletes nothing), and the fence comes back to what is left (`commit`), all of it still final. A
    /// selection that reaches back across the fence is deleted only after it (`deleteSelection`).
    mutating func deleteBackward() -> [Output] {
        retype = ""
        if var text = marked {
            text.removeLast()
            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))
            return []
        }
        if let selection { return deleteSelection(selection) }
        guard !sent.isEmpty else { return [.backspaces(1)] }
        return commit(String(sent.dropLast()))
    }

    /// `range` of the document replaced with `text` (dictation's corrections, an input method's own
    /// edits): any composition ends, and the Mac is brought to the new document by deleting back to
    /// where the old and new first differ and typing the rest. Nothing is sent when the correction
    /// would land elsewhere than it means, or change what is final (`refusal`): rather than its
    /// replacement typed a second time at the caret (dictation's last correction of a phrase, its
    /// punctuation or capitals, coming after a click), or the Return typed again with the line before it
    /// (the message sent twice, the command run twice).
    mutating func replace(_ range: NSRange, with text: String, taken: Int? = nil) -> [Output] {
        guard refusal(range, with: text, taken: taken) == nil else { return [] }
        retype = ""
        return commit(replacing(range, with: text))
    }

    /// Why `replace` would send nothing, or nil when it goes: a range taken before this side forgot or
    /// trimmed what it held (`taken`, its positions' `generation`, older than the document's), or one the
    /// text system built again from offsets it kept, which then starts past the document's end, no longer
    /// points at the text it means (the Mac's caret moved since, or every offset did); and a replacement
    /// that would change anything before the fence (its first change before it, wherever its range starts:
    /// dictation's whole utterance sent again from its start, adding only words after the Return, goes)
    /// would backspace over a Return or a Tab the Mac has acted on. A range rebuilt from kept offsets that
    /// starts inside the document after a forget (at its start, say: what was typed began there) cannot be
    /// told from one taken since, and goes: its replacement is typed where the caret is now.
    func refusal(_ range: NSRange, with text: String, taken: Int? = nil) -> Refusal? {
        if let taken, taken != generation { return .forgotten }
        guard range.location <= length else { return .pastEnd }
        guard keepsFinal(replacing(range, with: text)) else { return .final }
        return nil
    }

    /// The Mac's caret is about to move some other way (a click, an arrow, a shortcut, a pick): what is
    /// being composed goes to the Mac first, as it stands, where the caret still is, as a text field keeps
    /// a composition when a tap moves its caret; then what was sent is forgotten, nothing of it is final
    /// any more, and every position the text system holds is stale. Kept on the device across the move,
    /// the composition was lost: told that the document changed, iPadOS's input method dropped it at the
    /// next key.
    mutating func forget() -> [Output] {
        let out = unmark()
        sent = ""
        generation += 1
        selection = nil
        fence = 0
        retype = ""
        return out
    }

    /// The tail is past `limit` and nothing is being composed: the input view trims it at its next turn.
    var wantsTrim: Bool { marked == nil && sent.count > Self.limit }

    /// The tail's last `keep` characters are kept, when it wants a trim, and the fence with them (at their
    /// start when it fell in what was cut). Every offset moves: the input view tells the text system, as
    /// for a `forget`, and every position it holds is stale.
    mutating func trim() {
        guard wantsTrim else { return }
        let kept = String(sent.suffix(Self.keep))
        fence = max(fence - (sent.utf16.count - kept.utf16.count), 0)
        sent = kept
        generation += 1
        selection = nil
        retype = ""
    }

    /// The document with `range` of it replaced by `text`, the range cut at the document's end.
    private func replacing(_ range: NSRange, with text: String) -> String {
        let utf16 = Array(document.utf16)
        let start = min(max(range.location, 0), utf16.count)
        let end = min(max(range.location + range.length, start), utf16.count)
        let before = String(utf16CodeUnits: Array(utf16[..<start]), count: start)
        let after = String(utf16CodeUnits: Array(utf16[end...]), count: utf16.count - end)
        return before + text + after
    }

    /// Whether `new` keeps what lies before the fence as the Mac has it, unit for unit.
    private func keepsFinal(_ new: String) -> Bool {
        new.utf16.starts(with: sent.utf16.prefix(fence))
    }

    /// A selection deleted (a backspace over it, or a composition starting over it): what of it follows
    /// the fence goes from the Mac; what of it lies before, final, stays, and becomes `retype`.
    private mutating func deleteSelection(_ selection: NSRange) -> [Output] {
        guard selection.location < fence else { return commit(sentReplacing(selection, with: "")) }
        let units = Array(sent.utf16)
        let kept = String(utf16CodeUnits: Array(units[selection.location..<fence]), count: fence - selection.location)
        let out = commit(sentReplacing(NSRange(location: fence, length: selection.location + selection.length - fence), with: ""))
        retype = kept
        return out
    }

    /// What of text typed right after a selection's deletion left what is final in place is still to be
    /// typed: what it starts with of `retype` is on the Mac already. All of it when it is part of
    /// `retype` (the rest of which waits for the next text); nil when it starts otherwise, as it would
    /// change what is final. `retype` is spent.
    private mutating func typedAfterRetype(_ text: String) -> String? {
        let pending = retype
        retype = ""
        guard !pending.isEmpty else { return text }
        if text.hasPrefix(pending) { return String(text.dropFirst(pending.count)) }
        if pending.hasPrefix(text) { retype = String(pending.dropFirst(text.count)); return "" }
        return nil
    }

    /// What was sent with `range` of it (UTF-16) replaced by `text`: a selection's edit.
    private func sentReplacing(_ range: NSRange, with text: String) -> String {
        let units = Array(sent.utf16)
        let lower = min(range.location, units.count), upper = min(range.location + range.length, units.count)
        return String(utf16CodeUnits: Array(units[..<lower]), count: lower) + text
            + String(utf16CodeUnits: Array(units[upper...]), count: units.count - upper)
    }

    /// The document becomes `new`, all of it sent: backspaces over what differs, then the rest. The caret
    /// is at the end again. While `new` keeps what is final, the difference is looked for after the
    /// fence, so no backspace ever reaches into it, even where its last character and the first after it
    /// make one together (a CR there and an LF typed later); only the person's own backspace leaves `new`
    /// without it, and the fence then comes back to what is left. A Return or a Tab this sends puts the
    /// fence just after the last one.
    private mutating func commit(_ new: String) -> [Output] {
        selection = nil
        marked = nil
        markedSelection = NSRange(location: 0, length: 0)
        let from = keepsFinal(new) ? fence : 0
        let units = Array(sent.utf16), newUnits = Array(new.utf16)
        let old = Array(String(utf16CodeUnits: Array(units[from...]), count: units.count - from))
        let now = Array(String(utf16CodeUnits: Array(newUnits[from...]), count: newUnits.count - from))
        var common = 0
        while common < old.count, common < now.count, old[common] == now[common] { common += 1 }
        var out: [Output] = []
        if old.count > common { out.append(.backspaces(old.count - common)) }
        if now.count > common { out.append(.text(String(now[common...]))) }
        sent = new
        fence = min(fence, newUnits.count)
        if case .text(let typed)? = out.last, let end = TextInputRules.endOfReturnOrTab(in: typed) {
            fence = newUnits.count - typed.utf16.count + end
        }
        return out
    }
}

/// The stream's input view's rules beside its document (#138).
enum TextInputRules {
    /// The modifier bits a key carries (UIKeyModifierFlags raw values, as KeyModifiers' are).
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let option: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    /// Space's HID usage.
    static let space: UInt16 = 0x2C

    /// Whether an input sent to the Mac, by any path (the picture, the portrait trackpad and key row, a
    /// hardware keyboard, Esc's key command), may move its caret: a button going down (a click, or the
    /// start of a drag) or a key going down (an arrow, Return as a key, ⇧Return and ⇧Tab among them, a
    /// shortcut, a modifier). Then what was typed is no longer just before the caret there, so the input
    /// view forgets it (`TextComposition.forget`, what is composed going first), and a correction
    /// dictation makes later never backspaces where the caret is now. Typing leaves it: text, a backspace
    /// among it, and a Return or a Tab typed as text, which keeps what was typed and makes what came
    /// before it final instead (`endOfReturnOrTab`, `TextComposition.fence`). Moves, scrolls and every up
    /// leave it too.
    static func movesCaret(_ event: InputEvent) -> Bool {
        switch event {
        case .pointer(let action, _, _): return action == .leftDown || action == .rightDown
        case .key(_, let down, _): return down
        case .text, .scroll, .scrollGesture: return false
        }
    }

    /// Where the last Return or Tab ("\n", "\r" or "\t") in text typed for the Mac ends, in UTF-16 units
    /// from the text's start, or nil when it carries none: a hardware Return or Tab without shift and the
    /// on-screen keyboard's return key arrive as "\n" and "\t", and dictation's "new line" can come inside
    /// a phrase. Sent, it may have taken the Mac's caret past everything typed before it (a chat sent the
    /// line, a terminal ran the command, a form went on to its next field), so what came before it, the
    /// Return or the Tab included, is final (`TextComposition.fence`): a correction dictation makes of it
    /// later (its capital, its full stop: iPadOS's dictation keeps revising while the keyboard is up)
    /// sends nothing, rather than backspacing over the Return and typing it all again (the message sent
    /// twice, the command run twice, backspaces into the next field). What follows it, in the same text
    /// or typed later, went where the caret went and is revised as any typing is. Unicode scalars, not
    /// characters: "\r\n" is one Character.
    static func endOfReturnOrTab(in text: String) -> Int? {
        var end: Int?
        var offset = 0
        for scalar in text.unicodeScalars {
            offset += scalar.utf16.count
            if scalar == "\n" || scalar == "\r" || scalar == "\t" { end = offset }
        }
        return end
    }

    /// Whether text typed for the Mac carries a Return or a Tab, alone or anywhere among other text
    /// (`endOfReturnOrTab`).
    static func carriesReturnOrTab(_ text: String) -> Bool { endOfReturnOrTab(in: text) != nil }

    /// Whether an active input mode (`UITextInputMode.activeInputModes`, by its primary language) is a
    /// keyboard a person switches to: every one but Emoji and dictation.
    static func isKeyboard(_ language: String) -> Bool {
        language != "emoji" && language != "dictation"
    }

    /// Whether a hardware key's press is iPadOS's own switch between keyboards, never the Mac's: Space
    /// with control alone (caps lock aside) while the person set up keyboards in two languages or more
    /// in Settings › General › Keyboard › Keyboards (Emoji and dictation aside, and a third-party
    /// keyboard in a language already there counted once), as any iPad text field switches them and as
    /// macOS's own ⌃Space does with several input sources. With one, ⌃Space is the Mac's shortcut
    /// (Xcode's completions, VS Code's suggestions). Judged at the press: the release follows wherever
    /// the press went (ForwardedKeys). The keyboards are asked for only for ⌃Space.
    static func isKeyboardSwitch(usage: UInt16, modifiers: UInt64, keyboards languages: @autoclosure () -> [String]) -> Bool {
        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }
        return Set(languages().filter(isKeyboard)).count >= 2
    }
}
