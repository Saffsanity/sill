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
//
// The review of v4.1 added a second measure, per scene: a viewer who reads every line in order, from the first line fully
// in to the last frame any is (the cut), needs 0.22 s a word for all of them plus 0.9 s. The close's legal small print is
// exempt from both (it is there to be there, not to be read in the film's time): the report gives the close with and
// without it. And S05's chip, shown large above the iPad (an image, not a line): the time it is whole and still before
// Paste turns it into the note.
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
        // Each scene read in order: from its first line fully in to the last frame any of its lines is, every word at
        // 0.22 s plus 0.9 s. The open's S01–S02 and the close's S21–S23 are one take each.
        func scene(_ shot: String) -> String {
            switch shot { case "S01", "S02": return "S01–S02"; case "S21", "S22", "S23": return "S21–S23"; default: return shot }
        }
        var order: [String] = []
        var groups: [String: [Run]] = [:]
        for r in done where r.firstIn >= 0 {
            let k = scene(r.shot)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(r)
        }
        var shortScenes = 0
        for k in order {
            let runs = groups[k]!
            func measure(_ rs: [Run]) -> (words: Int, from: Double, to: Double) {
                var seenText = Set<String>(), words = 0
                for r in rs where !seenText.contains(r.text) { seenText.insert(r.text); words += r.words }
                return (words, Double(rs.map(\.firstIn).min()!) / 60, Double(rs.map { $0.lastIn + every }.max()!) / 60)
            }
            let m = measure(runs)
            let need = 0.22 * Double(m.words) + 0.9, have = m.to - m.from
            let legal = runs.filter { Copy060.legal.contains($0.text) }
            if legal.isEmpty {
                let ok = have + 1e-6 >= need
                if !ok { shortScenes += 1 }
                print(String(format: "  in order %@ %@ %7.3f–%7.3f  %5.2f s for %2d words, needs %5.2f (%+.2f)", ok ? "ok  " : "SHORT", k,
                             m.from, m.to, have, m.words, need, have - need))
            } else {
                let rest = measure(runs.filter { !Copy060.legal.contains($0.text) })
                let needRest = 0.22 * Double(rest.words) + 0.9
                let ok = (rest.to - rest.from) + 1e-6 >= needRest
                if !ok { shortScenes += 1 }
                print(String(format: "  in order %@ %@ %7.3f–%7.3f  %5.2f s for %2d words, needs %5.2f (%+.2f); with the legal small print (exempt) %2d words, needs %5.2f (%+.2f)",
                             ok ? "ok  " : "SHORT", k, rest.from, rest.to, rest.to - rest.from, rest.words, needRest, rest.to - rest.from - needRest,
                             m.words, need, have - need))
            }
        }
        // S05's chip, shown large: whole from the end of its rise to the note (film times through S05's map).
        let m5 = Retime060.s05
        let whole = m5.new(ChipInset060.appear + 0.25), note = m5.new(Clip060.note)
        print(String(format: "  S05's chip, large above the iPad: whole and still %.3f–%.3f, %.2f s (from its first frame, %.3f: %.2f s)",
                     whole, note, note - whole, m5.new(ChipInset060.appear), note - m5.new(ChipInset060.appear)))
        print(shortScenes == 0 ? "holds: every scene reads in order" : "holds: \(shortScenes) scene(s) short read in order")
        print(failures == 0 ? "holds: every line meets the rule" : "holds: \(failures) line(s) under the rule")
        if failures > 0 { throw NSError(domain: "holds", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(failures) line(s) under the reading rule"]) }
    }
}
