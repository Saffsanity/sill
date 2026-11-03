// Holds060.swift — `holds`: the reading room of every line, measured from the builders' own type on the film's frames.
// v4.1's command (Holds060.swift on reel-0-6-0), brought to v5 with the rules v5 was built to, for Noah's notes on v4.2
// ("the last line comes too late, show it earlier so it can be read more easily"):
// - a scene's last line snaps at least 2.0 s before its cut (the close's: before the card fades);
// - a statement (a line of T4's size or larger) at least 0.8 s before the next one in its scene (a line written on in parts,
//   as S10's subline, S12's first line or S14's "or list.", counts once, from its first part);
// - a T2 or T3 line is in view at least 2.0 s (no line is replaced within a scene in v5: they stack until the cut).
// They gate the scenes v5 changed; the scenes it kept as v4.2 had them are reported as they are (v4.2's pace, Noah's pick).
// v4.1's slower rule (0.22 s a word plus 0.9 s after a line is fully in, never under 2.0 s; each scene read in order) is
// printed beside them for comparison; neither v4.2 nor v5 is built to it.
//
// Each frame's builder is run (no rendering): every TypeLayer it makes records its lines and the time it hands them
// (TypeRecorder). A line is seen on a frame it draws anything on, fully in when every word is at full opacity with no blur
// left from its snap and nothing fades it. S19's column (FixesType060, glyph outlines on the scroll, not a TypeLayer) is
// reported from its own geometry: the title's and each fix line's time in view.
import Foundation
import SwiftUI

@MainActor
enum Holds060 {
    /// Lines written on in parts: one sentence each (Copy060).
    static var sentences: [[String]] {
        [Copy060.lockSub, Copy060.largerSub, Copy060.hardware, [Copy060.scroll, Copy060.wheel], [Copy060.tiles, Copy060.orList],
         [Copy060.wordmark, Copy060.version]]
    }
    /// The scenes whose lines' timing v5 changed (its notes' scenes), which the rules gate. S03 (its period only, a 1.6 s title
    /// card), S18 and S19–S20 keep v4.2's timing (S19's title scrolls: its time in view is reported below).
    static let changed: Set<String> = ["S06", "S10", "S12", "S13", "S14", "S15", "S16", "S21–S23"]

    static func required(words n: Int) -> Double { max(2.0, 0.22 * Double(n) + 0.9) }

    struct Run {
        var text: String, shot: String, words: Int, size: CGFloat
        var firstSeen: Int, lastSeen: Int, firstIn: Int, lastIn: Int
    }

    /// The open's S01–S02 and the close's S21–S23 are one take each.
    static func scene(_ shot: String) -> String {
        switch shot { case "S01", "S02": return "S01–S02"; case "S21", "S22", "S23": return "S21–S23"; default: return shot }
    }
    /// Where a scene's lines must have been read by: its last shot's cut; the close's, the card's fade.
    static func cut(_ scene: String) -> Double {
        if scene == "S21–S23" { return Cut060.film(Close060.fade, .close) }
        let ids = scene == "S01–S02" ? ["S02"] : [scene]
        return Timeline.shots.first { ids.contains($0.id) }.map(\.end) ?? Stage.duration
    }

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
        var open: [String: Run] = [:]
        var done: [Run] = []
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
                    var runs: [PlacedRun] = [], groupOpacity = 1.0, groupBlur: CGFloat = 0
                    if case let .group(kids, o, b) = node {
                        groupOpacity = o; groupBlur = b
                        for k in kids { if case let .run(r) = k { runs.append(r) } }
                    }
                    // Seen once a word draws (a line's node exists, with no run, before its snap).
                    guard !runs.isEmpty, groupOpacity * ext > 0.002 else { continue }
                    seen.insert(text)
                    let fully = runs.count == spec.words.count && runs.allSatisfy { $0.opacity >= 0.999 && $0.blur <= 0.01 }
                        && groupOpacity >= 0.999 && groupBlur <= 0.01 && ext >= 0.999
                    if var r = open[text], r.lastSeen >= f - every {
                        r.lastSeen = f
                        if fully { if r.firstIn < 0 { r.firstIn = f }; r.lastIn = f }
                        open[text] = r
                    } else {
                        if let r = open[text] { done.append(r) }
                        open[text] = Run(text: text, shot: shot, words: spec.words.count, size: spec.style.size,
                                         firstSeen: f, lastSeen: f, firstIn: fully ? f : -1, lastIn: fully ? f : -1)
                    }
                }
            }
            for (text, r) in open where !seen.contains(text) { done.append(r); open[text] = nil }
        }
        done += open.values
        done.sort { $0.firstSeen < $1.firstSeen }
        print(String(format: "holds: frames %d…%d every %d, %.0f s", first, last, every, Date().timeIntervalSince(started)))

        // One entry per sentence: its parts merged (its first part's arrival, its last part's, all its words).
        struct Line { var text: String; var scene: String; var words: Int; var size: CGFloat; var snap: Double; var lastPart: Double
                      var inFrom: Double; var seenTo: Double }
        var lines: [Line] = []
        var used = Set<Int>()
        for (k, r) in done.enumerated() where !used.contains(k) {
            used.insert(k)
            var parts = [r]
            if let sentence = sentences.first(where: { $0.contains(r.text) }) {
                for (j, p) in done.enumerated() where !used.contains(j) && sentence.contains(p.text) && abs(p.firstSeen - r.firstSeen) < 90 {
                    parts.append(p); used.insert(j)
                }
            }
            let text = parts.sorted { $0.firstSeen < $1.firstSeen }.map(\.text).joined(separator: " / ")
            let inFrom = parts.map { $0.firstIn < 0 ? Int.max : $0.firstIn }.max() ?? Int.max
            lines.append(Line(text: text, scene: scene(r.shot), words: parts.reduce(0) { $0 + $1.words }, size: parts.map(\.size).max()!,
                              snap: Double(parts.map(\.firstSeen).min()!) / 60, lastPart: Double(parts.map(\.firstSeen).max()!) / 60,
                              inFrom: inFrom == Int.max ? .nan : Double(inFrom) / 60, seenTo: Double(parts.map(\.lastSeen).min()! + every) / 60))
        }
        var order: [String] = []
        var byScene: [String: [Line]] = [:]
        for l in lines { if byScene[l.scene] == nil { order.append(l.scene) }; byScene[l.scene, default: []].append(l) }

        var failures = 0
        print("v5's rules (the scenes v5 changed are gated; the others are v4.2's, reported):")
        for s in order {
            let ls = byScene[s]!.sorted { $0.snap < $1.snap }
            let gated = changed.contains(s)
            let tag = gated ? "" : " (v4.2's)"
            let cutAt = cut(s)
            let lastLine = ls.max { $0.lastPart < $1.lastPart }!
            let margin = cutAt - lastLine.lastPart
            let okA = margin + 0.5 / 60 >= 2.0
            if gated && !okA { failures += 1 }
            print(String(format: "  %@ %@%@  last line %.2f, cut %.2f: %.2f s before (2.00)  \"%@\"", okA ? "ok  " : (gated ? "FAIL" : "note"),
                         s, tag, lastLine.lastPart, cutAt, margin, lastLine.text))
            let statements = ls.filter { $0.size >= 56 }
            for (a, b) in zip(statements, statements.dropFirst()) {
                let gap = b.snap - a.snap
                let ok = gap + 0.5 / 60 >= 0.8
                if gated && !ok { failures += 1 }
                if !ok || gated {
                    print(String(format: "  %@ %@%@  statement %.2f → next %.2f: %.2f s (0.80)  \"%@\" → \"%@\"", ok ? "ok  " : (gated ? "FAIL" : "note"),
                                 s, tag, a.snap, b.snap, gap, a.text, b.text))
                }
            }
            for l in ls where l.size < 56 {
                let inView = l.seenTo - l.lastPart
                let ok = inView + 0.5 / 60 >= 2.0
                if gated && !ok { failures += 1 }
                if !ok {
                    print(String(format: "  %@ %@%@  T2/T3 in view %.2f s (2.00)  \"%@\"", gated ? "FAIL" : "note", s, tag, inView, l.text))
                }
            }
        }
        print("v4.1's rule, for comparison (each line 0.22 s a word + 0.9 s, never under 2.0, from fully in; each scene in order):")
        var shortLines = 0
        for l in lines {
            let hold = l.seenTo - l.inFrom, need = required(words: l.words)
            if !(hold + 1e-6 >= need) { shortLines += 1 }
            print(String(format: "  %@ %@ %7.3f–%7.3f  in view %5.2f s, v4.1 needs %4.2f (%2d words)  %@", hold + 1e-6 >= need ? "ok  " : "less",
                         l.scene, l.inFrom, l.seenTo, hold, need, l.words, l.text))
        }
        for s in order {
            let ls = byScene[s]!.filter { !Copy060.legal.contains($0.text) }
            guard !ls.isEmpty else { continue }
            let words = ls.reduce(0) { $0 + $1.words }
            let have = ls.map(\.seenTo).max()! - ls.map(\.snap).min()!
            let need = 0.22 * Double(words) + 0.9
            print(String(format: "  in order %@ %@  %5.2f s for %2d words, v4.1 needs %5.2f (%+.2f)", have + 1e-6 >= need ? "ok  " : "less", s, have, words, need, have - need))
        }
        print("  v4.1's rule: \(shortLines) line(s) shorter than it (v4.2's pace, kept)")
        // The cutaway (S19–S20): the column scrolls, so its title and each fix line are read while they pass.
        let F = Fixes060.self
        func when(_ y: CGFloat, _ yOnScreen: CGFloat) -> Double {
            var lo = F.start, hi = F.tap
            for _ in 0..<60 { let m = (lo + hi) / 2; if F.screenY(y, m) > yOnScreen { lo = m } else { hi = m } }
            return (lo + hi) / 2
        }
        // The title: from its capitals' top entering the frame to its baseline leaving it, and clear of the 140 px fades.
        let enter = when(F.titleOffset, Stage.size.height + 80), leave = when(F.titleOffset, 0)
        let tIn = when(F.titleOffset, Stage.size.height - F.fade), tOut = when(F.titleOffset, F.fade + 80)
        print(String(format: "  cutaway: \"%@\" rising (T1s, at the column's 450 px/s): in the frame %.2f–%.2f (film %.2f–%.2f), %.2f s; clear of the fades %.2f s",
                     F.title.joined(separator: " "), enter, leave, Cut060.film(enter, .close), Cut060.film(leave, .close), leave - enter, tOut - tIn))
        var clear: [Double] = []
        for p in F.placed {
            guard case .line = p.item else { continue }
            clear.append(when(p.y, F.fade + 10) - when(p.y, Stage.size.height - F.fade))
        }
        print(String(format: "  cutaway: each fix line clear of the fades %.2f–%.2f s, at %.0f px/s", clear.min() ?? 0, clear.max() ?? 0, F.speed))
        print(failures == 0 ? "holds: every scene v5 changed meets its rules" : "holds: \(failures) rule(s) not met")
        if failures > 0 { throw NSError(domain: "holds", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(failures) reading rule(s) not met"]) }
    }
}
