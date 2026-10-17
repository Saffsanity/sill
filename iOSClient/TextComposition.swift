import Foundation

// What the stream's input view holds for iPadOS's text system (#138): the text an input method is
// still composing (Zhuyin's ㄋㄧˇ, Pinyin's nihao, Japanese kana before conversion), kept on the device
// and never sent, and a tail of what was typed since the Mac's caret was last moved by something else,
// so dictation and an input method can revise what they put there (a dictated word corrected a moment
// later: backspaces on the Mac, then the new text).
//
// Pure: Foundation only, so it is checked on its own with swiftc (Tests/checks/text-composition).
// Offsets are UTF-16, as UITextInput's are; the Mac is sent whole characters.

struct TextComposition: Equatable {
    /// What goes to the Mac: text, or that many backspaces (each one deletes one character there).
    enum Output: Equatable {
        case text(String)
        case backspaces(Int)
    }

    /// The tail of what was sent since the last `reset`, which the text system may still revise.
    private(set) var sent = ""
    /// The text being composed, never sent while it is; nil when nothing is.
    private(set) var marked: String?
    /// The selection inside the marked text, relative to its start (UTF-16).
    private(set) var markedSelection = NSRange(location: 0, length: 0)

    /// How much of what was sent is kept, in characters: enough for a dictated sentence's corrections.
    static let keep = 200

    /// The document the text system sees: what was sent, then what is being composed.
    var document: String { sent + (marked ?? "") }
    var length: Int { document.utf16.count }
    var isComposing: Bool { marked != nil }

    var markedRange: NSRange? {
        marked.map { NSRange(location: sent.utf16.count, length: $0.utf16.count) }
    }

    /// The caret is at the end, or where the input method put it inside the marked text.
    var selectedRange: NSRange {
        guard marked != nil else { return NSRange(location: length, length: 0) }
        return NSRange(location: sent.utf16.count + markedSelection.location, length: markedSelection.length)
    }

    /// Text typed or committed: it replaces the marked text, if any, and goes to the Mac.
    mutating func insert(_ text: String) -> [Output] {
        commit(sent + text)
    }

    /// The input method's composition so far (an empty one ends it: nothing is sent).
    mutating func setMarked(_ text: String?, selected: NSRange) {
        guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); return }
        marked = text
        let count = text.utf16.count
        let location = min(max(selected.location, 0), count)
        markedSelection = NSRange(location: location, length: min(max(selected.length, 0), count - location))
    }

    /// The composition is accepted as it stands: sent.
    mutating func unmark() -> [Output] {
        guard let marked else { return [] }
        return commit(sent + marked)
    }

    /// Backspace: inside a composition it edits the composition; otherwise one backspace to the Mac,
    /// whether or not this side still remembers what it deletes.
    mutating func deleteBackward() -> [Output] {
        if var text = marked {
            text.removeLast()
            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))
            return []
        }
        guard !sent.isEmpty else { return [.backspaces(1)] }
        return commit(String(sent.dropLast()))
    }

    /// `range` of the document replaced with `text` (dictation's corrections, an input method's own
    /// edits): any composition ends, and the Mac is brought to the new document by deleting back to
    /// where the old and new first differ and typing the rest.
    mutating func replace(_ range: NSRange, with text: String) -> [Output] {
        let utf16 = Array(document.utf16)
        let start = min(max(range.location, 0), utf16.count)
        let end = min(max(range.location + range.length, start), utf16.count)
        let before = String(utf16CodeUnits: Array(utf16[..<start]), count: start)
        let after = String(utf16CodeUnits: Array(utf16[end...]), count: utf16.count - end)
        return commit(before + text + after)
    }

    /// The Mac's caret moved some other way (a click, an arrow, a shortcut): what was sent is forgotten;
    /// a composition carries on.
    mutating func reset() {
        sent = ""
    }

    /// The document becomes `new`, all of it sent: backspaces over what differs, then the rest.
    private mutating func commit(_ new: String) -> [Output] {
        marked = nil
        markedSelection = NSRange(location: 0, length: 0)
        let old = Array(sent), now = Array(new)
        var common = 0
        while common < old.count, common < now.count, old[common] == now[common] { common += 1 }
        var out: [Output] = []
        if old.count > common { out.append(.backspaces(old.count - common)) }
        if now.count > common { out.append(.text(String(now[common...]))) }
        sent = String(now.suffix(Self.keep))
        return out
    }
}
