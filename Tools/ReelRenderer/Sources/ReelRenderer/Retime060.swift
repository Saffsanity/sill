// Retime060.swift — v4.1, Noah's notes of 2026-11-02 on the 0.6.0 video: "Transitions need to be like 25% slower, can't
// read the text that fast." The film keeps every scene's choreography (its builder, written in v4's times) and plays it
// through a time map: film time T (this cut) → the builder's time t (v4's). Everything a builder moves runs 1.25 times
// slower (a rate of 0.8 v4 seconds per film second) but where the plan holds a quiet moment longer (a dwell: the words
// read, nothing but slow drift in the picture), so that
// - every transition is at least 25 % slower than in v4 (no segment runs faster than 0.8; S16's hold ring, a timer the
//   words call "half a second", runs in real time, rate 1.0, and is the one exception);
// - every line of words holds at least 0.22 s a word plus 0.9 s after its last word is in, never under 2.0 s (sublines
//   and footnotes from their own arrival): the `holds` command measures it on the film's frames;
// - statements still snap on the beat of the 150 BPM grid (a dwell before them makes up the quarter beats 1.25 leaves),
//   every cut is on a beat and the acts start on bar lines.
// Continuous camera motion (drifts, pushes over a shot) runs on film time instead (`Env.glide`), so it glides evenly
// through the dwells; so do S06's movie and its sound arcs and S08's spinner. The cutaway (S19–S20) is timed natively in
// film time (Assets060Fixes.swift). The plan, scene by scene, with its reasons, is in design/reel/v4.1/SHOTLIST-0.6.md §12.
import Foundation

/// A time map for one scene (or a run of shots that are one continuous take: S01–S02, S21–S23).
///
/// Its segments run at 0.8 v4 s per film s (1.25× slower), exactly, but for the dwells (held moments) and S16's
/// real-time ring. A dwell eases its speed down from its neighbours' and back up to it inside itself (cosine ramps of up
/// to 0.12 s), holding a plateau between, so the map is smooth (no motion changes speed from one frame to the next) and
/// every 1.25× segment and every knot is exact: an anchor at a dwell's edge lands where the plan puts it.
struct SceneMap060 {
    let ids: [String]
    let oldStart: Double
    let newStart: Double
    /// Old (v4) times at the segments' ends and the new (film) times at the same points.
    let knotsOld: [Double]
    let knotsNew: [Double]
    /// Each segment's mean rate (v4 seconds per film second), its edge rates, ramp widths (film s) and plateau.
    let rates: [Double]
    let edges: [Double]
    let rampsL: [Double], rampsR: [Double], plateaus: [Double]

    var oldEnd: Double { knotsOld.last! }
    var newEnd: Double { knotsNew.last! }

    /// `segments`: each segment's old end and the film seconds it gets beyond 1.25 × its old length (a dwell; negative
    /// for a segment that runs faster than the rest, S16's real-time ring).
    init(_ ids: [String], old a: Double, new A: Double, _ segments: [(Double, Double)]) {
        self.ids = ids
        oldStart = a; newStart = A
        var ko = [a], kn = [A], r: [Double] = []
        for (end, extra) in segments {
            let span = end - ko.last!
            let d = 1.25 * span + extra
            precondition(span > 0 && d > 0, "Retime060 \(ids): bad segment ending \(end)")
            ko.append(end); kn.append(kn.last! + d); r.append(span / d)
        }
        knotsOld = ko; knotsNew = kn; rates = r
        // The speed at each knot: the 1.25× side's when one side runs at 1.25× (it stays exact), the shared rate of two
        // segments at the same rate, else their mean; a scene's ends keep their segment's own.
        func active(_ x: Double) -> Bool { abs(x - 0.8) < 1e-9 }
        var e = [Double](repeating: 0, count: ko.count)
        e[0] = r[0]; e[ko.count - 1] = r[r.count - 1]
        for k in 1..<(ko.count - 1) {
            let l = r[k - 1], rr = r[k]
            e[k] = (active(l) || active(rr)) ? 0.8 : (abs(l - rr) < 1e-9 ? rr : (l + rr) / 2)
        }
        edges = e
        var wl: [Double] = [], wr: [Double] = [], pl: [Double] = []
        for i in 0..<r.count {
            let S = ko[i + 1] - ko[i], D = kn[i + 1] - kn[i]
            let eL = e[i], eR = e[i + 1]
            var w = min(0.12, D / 3)
            var wL = abs(eL - r[i]) < 1e-9 ? 0 : w, wR = abs(eR - r[i]) < 1e-9 ? 0 : w
            func plateau() -> Double { (S - (eL * wL + eR * wR) / 2) / (D - (wL + wR) / 2) }
            var p = plateau()
            while p < 0.004 && w > 1e-4 {                 // a short dwell holds nearly still: narrower ramps
                w *= 0.8
                if wL > 0 { wL = w }
                if wR > 0 { wR = w }
                p = plateau()
            }
            wl.append(wL); wr.append(wR); pl.append(p)
        }
        rampsL = wl; rampsR = wr; plateaus = pl
    }

    /// v4 seconds elapsed `x` film seconds into segment `i`.
    private func integral(_ i: Int, _ x: Double) -> Double {
        let D = knotsNew[i + 1] - knotsNew[i]
        let eL = edges[i], eR = edges[i + 1], wL = rampsL[i], wR = rampsR[i], p = plateaus[i]
        func S(_ u: Double) -> Double { u / 2 - sin(.pi * u) / (2 * .pi) }
        if wL > 0 && x < wL { return eL * x + (p - eL) * wL * S(x / wL) }
        let head = wL > 0 ? (eL + p) * wL / 2 : 0
        if x <= D - wR || wR == 0 { return head + p * (x - wL) }
        let y = x - (D - wR)
        return head + p * (D - wR - wL) + p * y + (eR - p) * wR * S(y / wR)
    }

    /// The builder's (v4) time at film time `T`.
    func old(_ T: Double) -> Double {
        if T <= newStart { return oldStart + rates[0] * (T - newStart) }
        if T >= newEnd { return oldEnd + rates[rates.count - 1] * (T - newEnd) }
        var i = 0
        while i < rates.count - 1 && T >= knotsNew[i + 1] { i += 1 }
        return knotsOld[i] + integral(i, T - knotsNew[i])
    }

    /// The film time of a v4 time inside this scene (the map's inverse, by bisection).
    func new(_ t: Double) -> Double {
        if t <= oldStart { return newStart + (t - oldStart) / rates[0] }
        if t >= oldEnd { return newEnd + (t - oldEnd) / rates[rates.count - 1] }
        var lo = newStart, hi = newEnd
        for _ in 0..<64 {
            let m = (lo + hi) / 2
            if old(m) < t { lo = m } else { hi = m }
        }
        return (lo + hi) / 2
    }

    /// The rate (v4 s per film s) at film time `T`.
    func rate(_ T: Double) -> Double { (old(T + 0.0005) - old(T - 0.0005)) / 0.001 }

    func contains(old t: Double) -> Bool { t >= oldStart - 1e-9 && t < oldEnd - 1e-9 }
}

/// What a builder needs to know of film time: the shot's map and where in it the frame is.
struct ShotClock {
    let T: Double
    let map: SceneMap060
}

extension Env {
    /// 0 → 1 over v4's `a … b`, in film time when the shot runs on a map (continuous camera motion: it glides evenly
    /// through a dwell), else over the builder's own time (asset previews).
    func glide(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard let c = clock else { return ramp(t, a, b) }
        return ramp(c.T, c.map.new(a), c.map.new(b))
    }
    /// Film time, or the builder's own time without a clock.
    func filmTime(_ t: Double) -> Double { clock?.T ?? t }
    /// A v4 time in film time (itself without a clock).
    func film(_ old: Double) -> Double { clock?.map.new(old) ?? old }
}

enum Retime060 {
    /// The film: 139.2 s, 8,352 frames, 87 bars of 150 BPM. Act I 0–11.2 (7 bars), Act II 11.2–46.4 (22), Act III
    /// 46.4–105.6 (37), Act IV 105.6–139.2 (21): S18 105.6–112.0, the cutaway 112.0–123.2, the close 123.2–139.2.
    static let duration = 139.2
    static let frames = 8352

    // MARK: The plan (old v4 segment ends, and the film seconds each gets beyond 1.25 × its length)

    /// S01–S02, one take: the glint and the lit icon 1.25× slower; a beat more on the lit icon so the rise starts on a
    /// beat (3.2); the wordmark lands on beat 10, a held breath and the version on beat 12; the lockup held 2.8 s.
    static let open = SceneMap060(["S01", "S02"], old: 0.0, new: 0.0, [
        (1.5, 0), (2.4, 0.2), (3.35, 0), (3.45, 0.3), (3.75, 0), (4.8, 1.5)])
    /// S03: "What’s new." held 2.45 s, its ease-out (0.25 s) ending on the cut to Act II.
    static let s03 = SceneMap060(["S03"], old: 4.8, new: 8.0, [(5.2, 0), (6.2, 1.2), (6.4, 0)])
    /// S04: a breath after the keycaps rise (⌘C on beat 3), one after ⌘C (the second statement on beat 7), the tail held.
    static let s04 = SceneMap060(["S04"], old: 6.4, new: 11.2, [
        (7.05, 0), (7.10, 0.2), (7.45, 0), (7.60, 0.1), (8.90, 0), (10.4, 0.7)])
    /// S05: a breath before the subline (beat 8), the pasted note held while the subline reads (3.25 s).
    static let s05 = SceneMap060(["S05"], old: 10.4, new: 17.2, [(12.50, 0), (12.85, 0.2), (13.40, 0), (14.4, 2.0)])
    /// S06: the subline on beat 3, Settings on beat 8, Mute on beat 11, unmuted on beat 16: muted 2.0 s and 2.0 s of sound
    /// after, so the footnote (Mute's) reads.
    static let s06 = SceneMap060(["S06"], old: 14.4, new: 24.4, [
        (14.90, 0), (15.25, 0.2), (17.09, 0), (17.60, 0.2), (17.95, 0), (18.32, 1.0), (18.69, 0), (19.2, 1.0)])
    /// S07: "Mac locked?" lands, a beat's pause, the lock on beat 2; the subline on beat 6.
    static let s07 = SceneMap060(["S07"], old: 19.2, new: 32.8, [
        (19.52, 0), (19.60, 0.3), (20.15, 0), (20.85, 0.1), (21.40, 0), (24.0, 0.4)])
    /// S08: the field's spinner a moment longer after Return (it spins on film time), the unlock on beat 7.
    static let s08 = SceneMap060(["S08"], old: 24.0, new: 39.6, [(25.55, 0), (25.60, 0.3), (26.60, 0), (28.8, 0.5)])
    /// S09: "Up to 5×." on beat 3 (the headline and the spread's start a little slower), a breath at 3× before the move,
    /// the full sheet held at the end.
    static let s09 = SceneMap060(["S09"], old: 28.8, new: 46.4, [
        (28.85, 0), (29.65, 0.2), (30.05, 0), (30.22, 0.1), (32.5, 0), (32.8, 1.1)])
    /// S10: the panel open a beat longer before the switch; the larger layout a moment before the subline; the fitted
    /// window held.
    static let s10 = SceneMap060(["S10"], old: 32.8, new: 52.8, [
        (33.44, 0), (33.65, 0.2), (34.58, 0), (34.85, 0.1), (35.52, 0), (36.8, 1.5)])
    /// S11: the sentence typed evenly a little slower (about 8.9 keys a second), so "Just type." lands on beat 3 inside
    /// it; the Save sheet down a moment longer, Esc on beat 9.
    static let s11: SceneMap060 = {
        let r = 0.45 / (1.25 * 0.45 + 0.2)              // the typing's rate, kept through 37.2–38.27
        let typed = 0.62 / r - 1.25 * 0.62
        return SceneMap060(["S11"], old: 36.8, new: 59.6, [
            (37.2, 0), (37.65, 0.2), (38.27, typed), (38.65, 0), (39.2, 0.6 - 0.2 - typed), (39.8, 0), (40.8, 0.8)])
    }()
    /// S12: "Or a mouse wheel." on the half beat with the scroll; a breath before the subline (beat 6); the finger rests
    /// after its drag.
    static let s12 = SceneMap060(["S12"], old: 40.8, new: 66.0, [
        (40.85, 0), (41.25, 0.1), (42.29, 0), (42.45, 0.3), (43.80, 0), (43.84, 1.2), (44.0, 0)])
    /// S13: each greeting's composition held a moment with its candidate chosen, so each arrives on a beat (2, 5, 8);
    /// the dictation, then the line held.
    static let s13 = SceneMap060(["S13"], old: 44.0, new: 71.6, [
        (44.20, 0), (44.38, 0.3), (44.96, 0), (45.18, 0.2), (45.67, 0), (45.98, 0.2), (46.36, 0), (46.53, 0.2),
        (47.55, 0), (48.8, 1.1)])
    /// S14: the subline on beat 3, the list on beat 6 and held, tiles on beat 9, the footnote held.
    static let s14 = SceneMap060(["S14"], old: 48.8, new: 79.6, [
        (49.30, 0), (49.65, 0.2), (50.20, 0), (50.40, 0.2), (51.18, 0.2), (51.55, 0), (52.8, 1.6)])
    /// S15: the subline on beat 4, Aa at Off on beat 6 (Aa060.off, moved to 54.64 so it does), the subline held.
    static let s15 = SceneMap060(["S15"], old: 52.8, new: 86.8, [(53.30, 0), (54.05, 0.1), (54.95, 0), (56.0, 2.3)])
    /// S16: the touch on beat 2 (Hold060's times moved 0.24 s later); the ring from down to open in real time, exactly
    /// 0.5 s ("Controls in half a second."); the row on beat 7; the footnote held.
    static let s16 = SceneMap060(["S16"], old: 56.0, new: 93.2, [
        (56.64, 0), (57.14, -0.125), (57.79, 0), (58.24, 0.125), (58.6, 0), (59.2, 2.4)])
    /// S17: a beat more for the headline; the push on film time to the cut; the subline held.
    static let s17 = SceneMap060(["S17"], old: 59.2, new: 99.6, [(59.75, 0), (60.45, 0.1), (61.0, 0), (62.4, 1.9)])
    /// S18: the headline alone a bar longer (the glint on beat 4), the subline held.
    static let s18 = SceneMap060(["S18"], old: 62.4, new: 105.6, [(63.05, 0), (63.2, 0.6), (64.1, 0), (65.6, 1.8)])
    /// S21–S23, one take: each line of the card on its beat, the legal line held 7.6 s (its 25 words), the fade 1.25×.
    static let close = SceneMap060(["S21", "S22", "S23"], old: 72.0, new: 123.2, [
        (73.0, 0), (73.05, 0.3), (73.35, 0), (74.45, 0.3), (74.85, 0), (75.25, 0.2), (75.55, 0), (75.65, 0.3),
        (75.95, 0), (76.05, 0.3), (76.35, 0), (78.8, 4.5), (79.7, 0), (80.0, 0.1)])

    static let maps: [SceneMap060] = [open, s03, s04, s05, s06, s07, s08, s09, s10, s11, s12, s13, s14, s15, s16, s17, s18, close]

    /// The cutaway (S19–S20) in v4's times and here: it is timed natively (Fixes060), so a v4 cue inside it is moved by
    /// its offset from the squash.
    static let oldCutaway = (start: 65.6, end: 72.0, tap: 71.2)

    /// The film time of a v4 time (a cue of the score, a contact-sheet time): the map whose v4 span holds it.
    static func film(_ old: Double) -> Double {
        if old >= oldCutaway.start - 1e-9 && old < oldCutaway.end - 1e-9 {
            return Fixes060.tap + (old - oldCutaway.tap)
        }
        if let m = maps.first(where: { $0.contains(old: old) }) { return m.new(old) }
        if old >= close.oldEnd - 1e-9 { return close.new(old) }
        return open.new(old)
    }

    // MARK: The report (`retime`)

    /// Each map's segments and the beats its events land on: a statement's snap at a beat + 0.0625 s (v4's 0.05,
    /// 1.25× slower) or + 0.0125 (the lockup's), an event on the beat.
    static func report() {
        let anchors: [String: [(String, Double)]] = [
            "S01": [("the rise", 2.4), ("wordmark", 3.05), ("version", 3.45)],
            "S03": [("What’s new.", 4.85), ("ease-out", 6.2)],
            "S04": [("Copy on your Mac.", 6.45), ("C down", 7.20), ("to Notes", 7.6), ("Paste on your iPad.", 8.45), ("lands", 8.40)],
            "S05": [("Copy on your iPad.", 10.45), ("Paste tap", 12.0), ("Paste on your Mac.", 12.05), ("subline", 12.85)],
            "S06": [("Sound from your Mac.", 14.45), ("subline", 15.25), ("Settings", 16.8), ("Mute", 17.6), ("footnote", 17.65), ("unmute", 18.4)],
            "S07": [("Mac locked?", 19.25), ("lock", 19.6), ("Sill shows its lock screen.", 19.65), ("subline", 20.85)],
            "S08": [("Unlock it from here.", 24.05), ("Return", 25.2), ("unlock", 26.0), ("subline", 26.05)],
            "S09": [("Pinch to zoom.", 28.85), ("Up to 5×.", 29.65), ("subline", 30.85), ("tap", 31.1)],
            "S10": [("Larger Picture.", 32.85), ("On iPhone, held upright.", 33.65), ("subline", 34.85), ("larger", 34.3), ("fitted", 35.3)],
            "S11": [("Attach a keyboard.", 36.85), ("Just type.", 37.65), ("Esc", 39.2), ("Esc included.", 39.25)],
            "S12": [("Two-finger scroll.", 40.85), ("Or a mouse wheel.", 41.25), ("subline", 42.45), ("flip", 42.8)],
            "S13": [("你好 arrives", 44.40), ("你好", 44.45), ("こんにちは", 45.25), ("안녕하세요", 46.05), ("subline", 46.85), ("dictated", 47.30)],
            "S14": [("Every Mac, a tile.", 48.85), ("subline", 49.65), ("list", 50.4), ("tiles", 51.2), ("footnote", 51.25)],
            "S15": [("Aa starts at Off.", 52.85), ("subline", 54.05), ("Off", 54.64)],
            "S16": [("Hold a thumbnail.", 56.05), ("down", 56.64), ("open", 57.14), ("Controls…", 57.19), ("row", 58.24), ("footnote", 58.29)],
            "S17": [("The tour marks", 59.25), ("subline", 60.45)],
            "S18": [("Sill for Mac now runs on Intel.", 62.45), ("glint", 63.2), ("subline", 63.25)],
            "S21": [("wordmark", 72.65), ("version", 73.05), ("Free. Open source.", 74.45), ("App Store", 75.25), ("download", 75.65),
                    ("legal", 76.05), ("fade", 78.8)],
        ]
        for m in maps {
            print(String(format: "%@  v4 %.2f–%.2f → film %.3f–%.3f (%.3f s, %.2f beats; v4 %.2f s)", m.ids.joined(separator: "–"),
                         m.oldStart, m.oldEnd, m.newStart, m.newEnd, m.newEnd - m.newStart, (m.newEnd - m.newStart) / 0.4, m.oldEnd - m.oldStart))
            for i in 0..<m.rates.count {
                let held = abs(m.rates[i] - 0.8) < 1e-9 ? "" : String(format: "  (%@, plateau %.3f, ramps %.3f/%.3f s)",
                    m.rates[i] > 0.8 + 1e-9 ? "real time" : "held", m.plateaus[i], m.rampsL[i], m.rampsR[i])
                print(String(format: "    v4 %.3f–%.3f → %.4f–%.4f  rate %.3f%@", m.knotsOld[i], m.knotsOld[i + 1], m.knotsNew[i], m.knotsNew[i + 1],
                             m.rates[i], held))
            }
            for (name, t) in anchors[m.ids[0]] ?? [] {
                let T = m.new(t)
                let beat = T / 0.4
                print(String(format: "    %@ v4 %.3f → %.4f (beat %.3f, +%.4f s past beat %d)", name, t, T, beat, T - 0.4 * floor(beat + 1e-9), Int(floor(beat + 1e-9))))
            }
        }
        print(String(format: "the film: %.1f s, %d frames, %.2f bars", duration, frames, duration / 1.6))
    }
}
