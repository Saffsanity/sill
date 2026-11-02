// Holds060.swift — `holds`: v4.1's reading rule, measured on the film's frames. Noah, 2026-11-02: "can't read the text
// that fast"; the rule: every line of words holds at least 0.22 s a word plus 0.9 s after its last word is fully in,
// never under 2.0 s, and sublines and footnotes the same from their own arrival.
//
// Each frame's builder is run (no rendering): every TypeLayer it makes records its lines and the time it hands them
// (TypeRecorder). A line is fully in on a frame when every word is drawn at full opacity with no blur left from its snap
// (and nothing fades it: its ease-out, the card's fade); its hold runs from its first frame fully in to the first frame it
// is not (it leaves, it fades, the shot cuts). A line set on two lines (a capped subline, the tour's headline) is one
// sentence: its rule counts all its words and its hold runs from its last line's arrival. The cutaway's lines scroll; the
// report gives the title's still hold and each fix line's time in view.
import Foundation
import SwiftUI

@MainActor
enum Holds060 {
    /// Lines a shot sets on two lines: one sentence each (Copy060).
    static var sentences: [[String]] {
        [Copy060.lockSub, Copy060.largerSub, Copy060.tilesSub, Copy060.tourLines, Copy060.tourSubLines]
    }

    static func required(words n: Int) -> Double { max(2.0, 0.22 * Double(n) + 0.9) }

    struct Run { var text: String; var shot: String; var words: Int; var firstIn: Int; var lastIn: Int; var firstSeen: Int }

    static func run(args: [String]) throws {
        var from = 0.0, to = Stage.duration, every = 1
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--from": from = Double(args[i + 1])!; i += 2
            case "--to": to = Double(args[i + 1])!; i += 2
            case "--every": every = max(1, Int(args[i + 1])!); i += 2
            default: i += 1
            }
        }
        let comp = Compositor()
        let env = try makeEnv(comp)
        let first = Int((from * 60).rounded()), last = min(Stage.frames, Int((to * 60).rounded())) - 1
        // Per line text: the open run (contiguous frames where it is drawn) and the finished ones.
        var open: [String: Run] = [:]
        var done: [Run] = []
        var lastFrameSeen: [String: Int] = [:]
        let started = Date()
        for f in stride(from: first, through: last, by: every) {
            TypeRecorder.layers = []
            TypeRecorder.active = true
            _ = try layers(frame: f, env: env)
            TypeRecorder.active = false
            let shot = Timeline.shot(at: f).id
            var seen = Set<String>()
            for (lines, t, ext) in TypeRecorder.layers {
                for spec in lines {
                    let text = spec.words.joined(separator: " ")
                    guard let node = TypeLine.node(spec, t) else { continue }
                    seen.insert(text)
                    var runs: [PlacedRun] = [], groupOpacity = 1.0, groupBlur: CGFloat = 0
                    if case let .group(kids, o, b) = node {
                        groupOpacity = o; groupBlur = b
                        for k in kids { if case let .run(r) = k { runs.append(r) } }
                    }
                    let fully = runs.count == spec.words.count && runs.allSatisfy { $0.opacity >= 0.999 && $0.blur <= 0.01 }
                        && groupOpacity >= 0.999 && groupBlur <= 0.01 && ext >= 0.999
                    if var r = open[text], lastFrameSeen[text].map({ f - $0 <= every }) ?? false {
                        if fully {
                            if r.firstIn < 0 { r.firstIn = f }
                            if r.lastIn == f - every || r.lastIn < 0 { r.lastIn = f }
                        }
                        open[text] = r
                    } else {
                        if let r = open[text] { done.append(r) }
                        open[text] = Run(text: text, shot: shot, words: spec.words.count, firstIn: fully ? f : -1, lastIn: fully ? f : -1, firstSeen: f)
                    }
                    lastFrameSeen[text] = f
                }
            }
            for (text, r) in open where !seen.contains(text) { done.append(r); open[text] = nil }
        }
        done += open.values
        done.sort { $0.firstSeen < $1.firstSeen }
        print(String(format: "holds: frames %d…%d every %d, %.0f s", first, last, every, Date().timeIntervalSince(started)))
        // Two-line sentences: their rule counts every word, from the last line's arrival.
        var failures = 0
        var reported = Set<String>()
        for r in done {
            guard r.firstIn >= 0, !reported.contains(r.text + "|\(r.firstSeen)") else { continue }
            var words = r.words, firstIn = r.firstIn, lastIn = r.lastIn, text = r.text
            if let sentence = sentences.first(where: { $0.contains(r.text) }) {
                guard sentence.first == r.text else { continue }
                let parts = done.filter { p in sentence.contains(p.text) && abs(p.firstSeen - r.firstSeen) < 60 }
                words = parts.reduce(0) { $0 + $1.words }
                firstIn = parts.map(\.firstIn).max() ?? firstIn
                lastIn = parts.map(\.lastIn).min() ?? lastIn
                text = sentence.joined(separator: " / ")
                for p in parts { reported.insert(p.text + "|\(p.firstSeen)") }
            }
            let hold = Double(lastIn - firstIn + every) / 60
            let need = required(words: words)
            let ok = hold + 1e-6 >= need
            if !ok { failures += 1 }
            print(String(format: "  %@ %@ %7.3f–%7.3f  hold %5.2f s, needs %4.2f (%2d words)  %@", ok ? "ok  " : "FAIL", r.shot,
                         Double(firstIn) / 60, Double(lastIn + every) / 60, hold, need, words, text))
        }
        // The cutaway: the title held still, then each line's time in view between the fades.
        let F = Fixes060.self
        let titleIn = F.titleSnap + 0.0625 * 2 + 0.375
        print(String(format: "  cutaway: \"%@\" in %.3f, still until the scroll at %.3f: %.2f s (needs %.2f)", F.title.joined(separator: " "),
                     titleIn, F.scrollStart, F.scrollStart - titleIn, required(words: F.title.count)))
        var inView: [Double] = [], clear: [Double] = []
        for p in F.placed {
            guard case .line = p.item else { continue }
            func when(_ y: CGFloat) -> Double {
                var lo = F.start, hi = F.tap
                for _ in 0..<60 { let m = (lo + hi) / 2; if F.screenY(p.y, m) > y { lo = m } else { hi = m } }
                return (lo + hi) / 2
            }
            inView.append(when(-10) - when(Stage.size.height + 10))
            clear.append(when(F.fade + 10) - when(Stage.size.height - F.fade))
        }
        print(String(format: "  cutaway: each fix line in view %.2f–%.2f s, clear of the fades %.2f–%.2f s, at %.0f px/s",
                     inView.min() ?? 0, inView.max() ?? 0, clear.min() ?? 0, clear.max() ?? 0, F.speed))
        print(failures == 0 ? "holds: every line meets the rule" : "holds: \(failures) line(s) under the rule")
        if failures > 0 { throw NSError(domain: "holds", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(failures) line(s) under the reading rule"]) }
    }
}
