import Foundation
#if canImport(StreamProtocol)
import StreamProtocol
#endif

// Soft Line Breaks (`Sill.softNewlines`, Settings › This iPad / This iPhone): separates a person's own
// Return key tap from line breaks produced by multi-line voice dictation or input-method rewrites
// (such as WeType's and Doubao's AI voice polish over `UITextDocumentProxy`, which may either emit
// multi-line strings or stream `insertText("line 1")`, `insertText("\n")`, `insertText("line 2")`
// back-to-back within milliseconds).
//
// When enabled:
//   - Line breaks ("\n", "\r" and "\r\n") inside multi-character `insertText` / `unmarkText` commits and
//     inside `replace` revisions keep their exact UTF-16 representation in `TextComposition`, leave
//     `TextComposition.fence` open (unless a Tab also moved focus), and go out to the Mac as `.softNewline`
//     (`⇧Return`).
//   - A standalone `insertText("\n")` waits briefly (`coalesceWindow`, 45 ms): if another edit immediately
//     follows within `coalesceWindow` (as in token-streamed `UITextDocumentProxy` dictation output), that
//     pending break is promoted to `.softNewline`; otherwise (including after fast two-thumb typing like
//     "ok" + Return where nothing follows the Return) it flushes as a plain Return and advances `fence`.
//   - `TextComposition` stores the original UTF-16 strings without any placeholder character, preserving
//     CRLF offsets, emoji surrogate pairs in marked text, fenced hard Returns, Korean `retype`, and
//     literal U+2028 characters.
//
// Pure: Foundation + TextComposition + StreamProtocol only, checked standalone in `Tests/checks/soft-newlines`.

enum SoftNewlines {
    /// Device-local `UserDefaults` key. `-Sill.softNewlines 1` turns it on for one run, `0` off.
    static let switchKey = "Sill.softNewlines"
    /// Off unless turned on by this device's owner (per the 2026-11-18 rule).
    static let defaultOn = false

    /// Lookahead window (seconds) after a standalone Return to detect immediately following streamed text.
    static let coalesceWindow: Double = 0.045

    enum Copy {
        static let title = "Soft Line Breaks"
        static let footnote = "Sends Shift-Return for line breaks inside multi-line dictation, pasted paragraphs or input-method rewrites so fields that insert a new line on Shift-Return stay open instead of submitting early. Tapping Return on its own still sends Return."
    }

    enum Action: Equatable {
        case text(String)
        case backspaces(Int)
        case softNewline
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: switchKey) != nil else { return defaultOn }
        return defaults.bool(forKey: switchKey)
    }

    static func isSingleNewline(_ text: String) -> Bool {
        TextInputRules.isSingleNewline(text)
    }

    /// Expands `TextComposition.Output` into `Action`s. When `soft` is true, newly emitted ASCII line
    /// breaks ("\n", "\r", "\r\n") become `.softNewline` (`⇧Return`); literal U+2028 stays Unicode text.
    static func actions(for outputs: [TextComposition.Output], soft: Bool) -> [Action] {
        var result: [Action] = []
        for output in outputs {
            switch output {
            case .backspaces(let n):
                if n > 0 { result.append(.backspaces(n)) }
            case .text(let s):
                guard !s.isEmpty else { continue }
                guard soft else {
                    result.append(.text(s))
                    continue
                }
                var run = ""
                for ch in s {
                    if ch == "\n" || ch == "\r" || ch == "\r\n" {
                        if !run.isEmpty {
                            result.append(.text(run))
                            run = ""
                        }
                        result.append(.softNewline)
                    } else {
                        run.append(ch)
                    }
                }
                if !run.isEmpty {
                    result.append(.text(run))
                }
            }
        }
        return result
    }

    struct Gate: Equatable {
        var enabled: Bool = SoftNewlines.defaultOn
        private(set) var pendingReturnAt: Double?

        var hasPendingReturn: Bool { pendingReturnAt != nil }

        private mutating func settlePending(forFollowUpAt now: Double,
                                            in composition: inout TextComposition) -> (actions: [Action], promoted: Bool) {
            guard let armedAt = pendingReturnAt else { return ([], false) }
            pendingReturnAt = nil
            if enabled && now - armedAt <= SoftNewlines.coalesceWindow {
                let out = composition.insert("\n", softNewlines: true)
                return (SoftNewlines.actions(for: out, soft: true), true)
            }
            let out = composition.insert("\n", softNewlines: false)
            return (SoftNewlines.actions(for: out, soft: false), false)
        }

        mutating func insert(_ text: String, into composition: inout TextComposition, at now: Double) -> [Action] {
            guard enabled else {
                let flushed = flushPendingAsHard(in: &composition)
                return flushed + SoftNewlines.actions(for: composition.insert(text, softNewlines: false), soft: false)
            }

            let settled = settlePending(forFollowUpAt: now, in: &composition)
            let effective: String
            if composition.marked == nil, composition.selection == nil,
               !composition.retype.isEmpty, text.hasPrefix(composition.retype) {
                effective = String(text.dropFirst(composition.retype.count))
            } else {
                effective = text
            }

            if SoftNewlines.isSingleNewline(effective), !composition.isComposing, composition.selection == nil {
                if settled.promoted {
                    // Consecutive standalone "\n" tokens inside an active streamed paragraph break ("\n", "\n"):
                    let out = composition.insert(text, softNewlines: true)
                    return settled.actions + SoftNewlines.actions(for: out, soft: true)
                }
                pendingReturnAt = now
                return settled.actions
            }

            let soft = !SoftNewlines.isSingleNewline(effective)
            let out = composition.insert(text, softNewlines: soft)
            return settled.actions + SoftNewlines.actions(for: out, soft: soft)
        }

        mutating func replace(_ range: NSRange, with text: String, taken: Int?,
                              in composition: inout TextComposition, at now: Double) -> [Action] {
            var prefix: [Action] = []
            if let armedAt = pendingReturnAt {
                if now - armedAt > SoftNewlines.coalesceWindow {
                    prefix = flushPendingAsHard(in: &composition)
                } else {
                    guard composition.refusal(range, with: text, taken: taken) == nil else { return [] }
                    pendingReturnAt = nil
                    let soft = enabled
                    prefix = SoftNewlines.actions(for: composition.insert("\n", softNewlines: soft), soft: soft)
                }
            }
            let out = composition.replace(range, with: text, taken: taken, softNewlines: enabled)
            return prefix + SoftNewlines.actions(for: out, soft: enabled)
        }

        mutating func willSelect(in composition: inout TextComposition) -> [Action] {
            flushPendingAsHard(in: &composition)
        }

        mutating func setMarked(_ text: String?, selected: NSRange,
                                in composition: inout TextComposition, at now: Double) -> [Action] {
            var prefix: [Action] = []
            if let text, !text.isEmpty {
                prefix = settlePending(forFollowUpAt: now, in: &composition).actions
            }
            return prefix + SoftNewlines.actions(for: composition.setMarked(text, selected: selected), soft: false)
        }

        mutating func unmark(in composition: inout TextComposition, at now: Double) -> [Action] {
            var prefix: [Action] = []
            if composition.isComposing {
                prefix = settlePending(forFollowUpAt: now, in: &composition).actions
            }
            let soft = enabled && !(composition.marked.map(SoftNewlines.isSingleNewline) ?? true)
            let out = composition.unmark(softNewlines: soft)
            return prefix + SoftNewlines.actions(for: out, soft: soft)
        }

        mutating func deleteBackward(in composition: inout TextComposition) -> [Action] {
            if pendingReturnAt != nil {
                pendingReturnAt = nil
                return []
            }
            return SoftNewlines.actions(for: composition.deleteBackward(), soft: false)
        }

        mutating func flushPendingAsHard(in composition: inout TextComposition) -> [Action] {
            guard pendingReturnAt != nil else { return [] }
            pendingReturnAt = nil
            return SoftNewlines.actions(for: composition.insert("\n", softNewlines: false), soft: false)
        }
    }
}
