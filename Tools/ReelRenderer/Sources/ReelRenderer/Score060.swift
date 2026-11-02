// Score060.swift — the 0.6 update video's score (REEL=060), synthesised in code by v3's engine (Score.swift): the
// same voices, mix, reverb, limiter and two-pass level, with this cut's cue sheet. 150 BPM: a beat 0.4 s, a bar 1.6 s,
// every chord change on a bar line. No samples, no downloads.
//
// The cue sheet (storyboard §2–§3): the A add9 pad swells under the open's glint; the lockup's tones; a hit at the
// cut to "What’s new." and at Act II; the pulse from Act II; plucks on landings (the line pasted on the iPad, the Paste,
// the unlock, the greetings, the tiles); the Mac's own sound in S06 (v3's pluck figure through a small-speaker
// filter, panned to the iPad), cut dead at Mute and back after it; F♯m9 darkened and low-passed while the Mac is
// locked; key ticks for the password; Act III's arpeggio and off-beat ticks; typing clicks and a haptic buzz under
// "Esc"; the lights' bells; the cutaway's E6/9 with the riser, a quiet tick on every line crossing the middle, the
// pulse doubling a bar before the squash and the hard stop at the squash into digital silence but for the thud; the
// final chord from the close, the end card's tones, the release and the master's last 150 ms to zero.
//
// v4.1 (Noah's notes of 2026-11-02): the film is 139.2 s (87 bars). Every cue written to a picture event is that event's
// film time (Retime060.film of v4's time, through the scene's time map), so it lands with the picture; the chords change
// on the bar lines nearest v4's (the dark F♯m9 on the lock's bar); the pulse, the arpeggio, the off-beat ticks and the
// Mac's sound keep the 150 BPM grid from the acts' bar lines; the riser starts with the cutaway (its bar line, 25 beats
// before the squash), the pulse doubles 4 beats before it, everything stops dead on it but the thud, and the silence
// runs from 0.2 s after it to the close, 1.2 s after it (3 beats), all as in v4 relative to the squash.
import AudioToolbox
import AVFoundation
import Foundation

private let SR = 48_000.0
private let END = Retime060.duration    // 139.2
private let TOTAL = Int(END * SR)
private let CRESC = Fixes060.start      // 112.0: the cutaway: the pad opens, the riser rises
private let STOP = Fixes060.tap         // 122.0: the squash: everything stops dead but the thud
private let DOUBLE = STOP - 1.6         // 120.4: the pulse doubles, 4 beats before the squash
private let SILENT = STOP + 0.2         // digital silence from here (the thud's tail is under −50 dB by then)…
private let RESUME = Fixes060.closeStart // …until the final chord blooms, 123.2
private let FINAL = Fixes060.closeStart
private let RELEASE = Retime060.film(78.8) // 137.6: the chord releases with the picture's fade
private let TAIL = 0.15
/// The acts' first bar lines (film s).
private let ACT2 = 11.2, ACT3 = 46.4

@inline(__always) private func db(_ d: Double) -> Double { pow(10, d / 20) }
@inline(__always) private func midi(_ n: Double) -> Double { 440 * pow(2, (n - 69) / 12) }
@inline(__always) private func pan(_ p: Double) -> (Double, Double) {
    let a = (p + 1) * .pi / 4
    return (cos(a), sin(a))
}

private struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
    mutating func setBandPass(_ f: Double, q: Double) {
        let w = 2 * .pi * f / SR, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        b0 = alpha / a0; b1 = 0; b2 = -alpha / a0; a1 = -2 * cw / a0; a2 = (1 - alpha) / a0
    }
    mutating func setLowPass(_ f: Double, q: Double = 0.707) {
        let w = 2 * .pi * f / SR, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = (1 - cw) / 2 / a0; a1 = -2 * cw / a0; a2 = (1 - alpha) / a0
    }
    mutating func setHighPass(_ f: Double, q: Double = 0.707) {
        let w = 2 * .pi * f / SR, alpha = sin(w) / (2 * q), cw = cos(w), a0 = 1 + alpha
        b0 = (1 + cw) / 2 / a0; b1 = -(1 + cw) / a0; b2 = (1 + cw) / 2 / a0; a1 = -2 * cw / a0; a2 = (1 - alpha) / a0
    }
    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

// MARK: - The cue sheet

enum Cues060 {
    static let aAdd9: [Double] = [45, 52, 59, 61, 64]
    static let fsm9: [Double] = [42, 49, 52, 56, 57]
    static let dMaj9: [Double] = [38, 45, 49, 52, 54]
    static let e69: [Double] = [40, 47, 49, 54, 56]
    /// The pad's chords, on bar lines: v4's, each change on the bar line nearest its film time (v4's 9.6 → 16.0, 14.4 →
    /// 24.0, 25.6 → 41.6, 28.8 → 46.4, 35.2 → 56.0, 41.6 → 67.2, 48.0 → 78.4, 54.4 → 89.6, 60.8 → 102.4, 65.6 → 112.0),
    /// the dark F♯m9 on the lock's bar (33.6): the open and S04 on A add9, then F♯m9 (S05), D maj9 (S06), F♯m9 darkened while
    /// the Mac is locked (S07–S08), A add9 again at the unlock; Act III round the cycle; E6/9 under the cutaway.
    static let chords: [(Double, Double, [Double])] = [
        (0.0, 16.0, aAdd9), (16.0, 24.0, fsm9), (24.0, 33.6, dMaj9), (33.6, 41.6, fsm9), (41.6, 46.4, aAdd9),
        (46.4, 56.0, e69), (56.0, 67.2, aAdd9), (67.2, 78.4, fsm9), (78.4, 89.6, dMaj9), (89.6, 102.4, e69),
        (102.4, 112.0, dMaj9), (112.0, STOP, e69),
    ]
    static let finalChord: [Double] = [45, 52, 57, 59, 61, 64, 69]

    /// A picture event's film time: its v4 time through the scene's map.
    private static func f(_ t: Double) -> Double { Retime060.film(t) }

    /// Touch ticks (1.2 kHz, 25 ms): every touch dot's landing.
    static let taps: [Double] = [Clip060.hold4.0, Clip060.pasteTap, Clip060.hold5.0, Clip060.copyTap, Clip060.pasteChipTap,
         Sound060.settingsTap, Sound060.mute, Sound060.unmute, Pinch060.spread.0, Pinch060.move.0, Pinch060.tap, Pinch060.pinchIn.0,
         Larger060.settingsTap, Larger060.switchTap, Larger060.doneTap, Scroll060.panel, Scroll060.flip, Scroll060.done,
         Scroll060.drag.0, Hold060.down].map(f)
    /// Plucks (sine + its 2nd harmonic, 250 ms) on landings.
    static let plucks: [(Double, Double)] = [
         (Clip060.lands, 81),                                   // the Mac's line lands in Notes: A5
         (Clip060.chip, 76),                                    // the chip offers the paste: E5
         (Clip060.pasteChipTap, 85),                            // Paste: C♯6
         (Lock060.seq.lock, 73),                                // the Mac locks: C♯5
         (Lock060.seq.unlock, 83), (Lock060.seq.unlock + 0.04, 88),   // unlocked: B5, E6
         (Pinch060.tap + 0.02, 81),                             // the tap selects a cell
         (Larger060.larger, 81), (Larger060.fitted, 85),        // Larger Picture, then the Mac fits the window
         (Scroll060.flip + 0.02, 88),                           // Reverse Scrolling on
         (Compose060.arrive[0], 81), (Compose060.arrive[1], 85), (Compose060.arrive[2], 88), (Compose060.arrive[3], 93),
         (Tiles060.toList, 88), (Tiles060.toTiles, 81),
         (Aa060.off, 76),                                       // back to Off: the window goes back
         (Hold060.row, 81)].map { (f($0.0), $0.1) }
    /// The lights open on the held thumbnail: v3's bells, C♯7, A6, E6, 40 ms apart.
    static let bells: [(Double, Double)] = { let t = f(Hold060.open); return [(t, 97), (t + 0.04, 93), (t + 0.08, 88)] }()
    /// Soft clicks (2.5 kHz, 8 ms): ⌘C, the typing, ⌘S, Esc.
    static let softClicks: [Double] = ([Clip060.cmdDown, Clip060.cDown] + Keys060.strokes + [Keys060.cmdS - 0.05, Keys060.cmdS, Keys060.esc]).map(f)
    /// Key ticks for the password (soft, 3.2 kHz, 6 ms): eight taps and Return.
    static let keyTicks: [Double] = (Lock060.seq.taps + [Lock060.seq.returnAt]).map(f)
    /// The detent click when Aa lands on Off.
    static let detents: [Double] = [f(Aa060.off)]
    /// Glint shimmers: the open's glint, S18's glint across the iMac, the close's glint round the icon.
    static let shimmers: [Double] = [f(Open060.glint + 0.1), f(63.2), f(Close060.glint)]
    /// Tones (sine + 2nd harmonic at −14 dB, 1.1 s): the lockup's words, open and close, and "Free. Open source."
    static let tones: [(Double, Double)] = [(f(Open060.wordmark), 76), (f(Open060.version), 81),
                                            (f(Close060.wordmark), 76), (f(Close060.version), 81), (f(Close060.freeOpen), 85)]
    /// Hits (v3's: sine 90 → 58 Hz and a 3 kHz click): the cut to "What’s new." and Act II's first frame.
    static let hits: [(Double, Double)] = [(f(Open060.cut), -18), (ACT2, -14)]
    /// Statement snaps (the pulse is +3 dB on them): v4's, through the maps (S16's second statement moved with its hold),
    /// and the cutaway's title.
    static let statementSnaps: [Double] = [6.45, 8.45, 10.45, 12.05, 14.45, 19.25, 19.65, 24.05, 28.85, 29.65, 32.85, 33.65,
                                           36.85, 37.65, 39.25, 40.85, 41.25, 44.45, 45.25, 46.05, 48.85, 52.85, 56.05, Hold060.open + 0.05,
                                           59.25, 62.45].map(f) + [Fixes060.titleSnap]
    /// The cutaway's quiet ticks: each fix line crossing the middle (Fixes060.crossings, on the eighths' grid).
    static let crossings: [Double] = Fixes060.crossings
    /// S06: the Mac's sound plays through the shot (24.4–32.8), Mute cuts it dead (28.8), it is back at 30.8.
    static let macSound = (f(14.4), f(19.2)), mute = (f(Sound060.mute), f(Sound060.unmute))
    /// "Esc" buzzes (v3's haptic, C19) as the key goes down, 0.375 s (its 0.3, 1.25× as the picture's).
    static let buzz = (f(39.30), 0.375)
}

// MARK: - Voices

/// The pad: per note two sines at ±4 cents and a triangle at −12 dB; equal-power crossfades 0.8 s wide on each bar
/// line; 0.2 Hz tremolo at 8 %. It swells from silence over the open (2.5 s, v4's 2.0 1.25× as the open), builds through
/// the cutaway, stops dead at the squash; the final chord from the close, released to silence at the end.
private final class PadVoice060 {
    var n = 0
    var phases = [Double](repeating: 0, count: 256)
    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        let chords = Cues060.chords
        for i in 0..<count {
            let t = Double(n + i) / SR
            var L = 0.0, R = 0.0
            var k = 0
            if t >= 0.25 && t < STOP {
                let attack = min(1, (t - 0.25) / 2.5)
                var level = db(-26) / 1.15 * attack * attack
                level *= 1 + 0.08 * sin(2 * .pi * 0.2 * t)
                level *= 1 + 0.5 * clamp01((t - CRESC) / (STOP - CRESC))
                // S06: the pad steps back 3 dB under the Mac's sound, so its figure, and Mute's cut, read.
                let (ma, mb) = Cues060.macSound
                level *= 1 - 0.29 * clamp01((t - (ma - 0.4)) / 0.4) * clamp01((mb + 0.4 - t) / 0.4)
                if t > STOP - 0.015 { level *= max(0, (STOP - t) / 0.015) }
                for (ci, (a, b, notes)) in chords.enumerated() {
                    var w = 0.0
                    let fadeIn = ci == 0 ? 1.0 : clamp01((t - (a - 0.4)) / 0.8)
                    let fadeOut = ci == chords.count - 1 ? 1.0 : clamp01(((b + 0.4) - t) / 0.8)
                    if t >= a - 0.4 && t < b + 0.4 { w = sin(.pi / 2 * fadeIn) * sin(.pi / 2 * fadeOut) }
                    if w > 0 {
                        for note in notes {
                            let (s1, s2, tri) = oscillate(&k, midi(note))
                            let v = level * w
                            L += v * (s1 * 0.62 + s2 * 0.38 + tri * 0.25)
                            R += v * (s1 * 0.38 + s2 * 0.62 + tri * 0.25)
                        }
                    } else {
                        k += 3 * notes.count
                    }
                }
            } else {
                k += 3 * chords.reduce(0) { $0 + $1.2.count }
            }
            if t >= FINAL {
                var level = db(-22) / 1.36 * min(1, (t - FINAL) / 0.25)
                if t > RELEASE { level *= pow(max(0, (END - t) / (END - RELEASE)), 2) }
                level *= 1 + 0.08 * sin(2 * .pi * 0.2 * (t - FINAL))
                for note in Cues060.finalChord {
                    let (s1, s2, tri) = oscillate(&k, midi(note))
                    L += level * (s1 * 0.62 + s2 * 0.38 + tri * 0.25)
                    R += level * (s1 * 0.38 + s2 * 0.62 + tri * 0.25)
                }
            }
            l[i] = Float(L); r[i] = Float(R)
        }
        n += count
    }
    private func oscillate(_ k: inout Int, _ f: Double) -> (Double, Double, Double) {
        let fa = f * pow(2, 4.0 / 1200), fb = f * pow(2, -4.0 / 1200)
        phases[k] += fa / SR; if phases[k] >= 1 { phases[k] -= 1 }
        phases[k + 1] += fb / SR; if phases[k + 1] >= 1 { phases[k + 1] -= 1 }
        phases[k + 2] += f / SR; if phases[k + 2] >= 1 { phases[k + 2] -= 1 }
        let tri = 4 * abs(phases[k + 2] - 0.5) - 1
        let out = (sin(2 * .pi * phases[k]), sin(2 * .pi * phases[k + 1]), tri * db(-12))
        k += 3
        return out
    }
}

/// Plucks, bells, tones, shimmers and Act III's arpeggio, through the reverb.
private final class TonalVoice060 {
    var n = 0
    struct Note { let start: Double; let f: Double; let level: Double; let decay: Double; let attack: Double
        let harmonic: Double; let harmonicGain: Double; let panFrom: Double; let panTo: Double; let panTime: Double }
    var notes: [Note] = []

    init() {
        func add(_ t: Double, _ f: Double, _ level: Double, decay: Double, attack: Double = 0.004, harmonic: Double = 2,
                 hgain: Double = db(-12), pan p0: Double = 0, to p1: Double = 0, over: Double = 1) {
            notes.append(Note(start: t, f: f, level: level, decay: decay, attack: attack, harmonic: harmonic,
                              harmonicGain: hgain, panFrom: p0, panTo: p1, panTime: over))
        }
        for t in Cues060.shimmers {
            add(t, 2637, db(-30) * 0.5, decay: 0.9 / 4.6, harmonic: 1, hgain: 0, pan: -0.6, to: 0.6, over: 1.2)
            add(t, 3520, db(-30) * 0.5, decay: 0.9 / 4.6, harmonic: 1, hgain: 0, pan: -0.6, to: 0.6, over: 1.2)
        }
        for (t, m) in Cues060.plucks { add(t, midi(m), db(-26), decay: 0.25 / 4.6) }
        for (t, m) in Cues060.bells { add(t, midi(m), db(-26), decay: 0.18, harmonic: 2.76, hgain: db(-14)) }
        for (t, m) in Cues060.tones { add(t, midi(m), db(-24), decay: 1.1 / 4.6, attack: 0.005, hgain: db(-14)) }
        // Act III's arpeggio: the chord's upper notes in eighths (0.2 s), 300 ms decay, from Act III's bar line until the
        // cutaway.
        var t = ACT3
        var step = 0
        while t < CRESC - 1e-6 {
            if let chord = Cues060.chords.first(where: { t >= $0.0 && t < $0.1 })?.2 {
                let upper = Array(chord.suffix(3)).map { $0 + 12 }
                let pattern = [0, 1, 2, 1]
                add(t, midi(upper[pattern[step % 4]]), db(-32), decay: 0.3 / 4.6, pan: step % 2 == 0 ? -0.25 : 0.25,
                    to: step % 2 == 0 ? -0.25 : 0.25)
            }
            t += 0.2; step += 1
        }
    }

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count { l[i] = 0; r[i] = 0 }
        let t0 = Double(n) / SR, t1 = Double(n + count) / SR
        for note in notes where note.start < t1 && t0 < note.start + note.decay * 12 + note.attack {
            for i in 0..<count {
                let t = Double(n + i) / SR
                let dt = t - note.start
                guard dt >= 0 else { continue }
                if t >= STOP && note.start < STOP { continue }
                var env = dt < note.attack ? dt / note.attack : exp(-(dt - note.attack) / note.decay)
                if note.start < STOP && t > STOP - 0.015 { env *= max(0, (STOP - t) / 0.015) }
                if env < 1e-5 { continue }
                let ph = 2 * .pi * note.f * dt
                let v = note.level * env * (sin(ph) + note.harmonicGain * sin(ph * note.harmonic)) / (1 + note.harmonicGain)
                let p = note.panFrom + (note.panTo - note.panFrom) * clamp01(dt / note.panTime)
                let (gl, gr) = pan(p)
                l[i] += Float(v * gl * 1.414); r[i] += Float(v * gr * 1.414)
            }
        }
        n += count
    }
}

/// `SILL_NO_MACSOUND=1` renders the score without S06's Mac sound, for an A/B check of its level.
private let noMacSound = ProcessInfo.processInfo.environment["SILL_NO_MACSOUND"] != nil

/// Drone, hits, the pulse, ticks, clicks, the Mac's sound, the buzz, the noise bed, the riser and the thud (dry).
private final class DryVoice060 {
    var n = 0
    var rng = SplitMix64(seed: 0x060C0FFEE)
    var bedL = Biquad(), bedR = Biquad()
    var riserL = Biquad(), riserR = Biquad()
    var tickBP = Biquad(), crossBP = Biquad()
    var macLP = Biquad(), macHP = Biquad(), clickLP = Biquad()
    var dronePh = 0.0, drone2Ph = 0.0
    var pulses: [(Double, Double)] = []
    var offbeats: [Double] = []
    /// The Mac's sound: the pluck figure's notes (time, MIDI), eighths on the chord's upper notes.
    var macNotes: [(Double, Double)] = []

    init() {
        var t = ACT2
        while t < DOUBLE - 1e-6 {
            let accent = Cues060.statementSnaps.contains { abs($0 - t) <= 0.15 }
            pulses.append((t, db(-22) * (accent ? db(3) : 1)))
            t += 0.8
        }
        t = DOUBLE
        while t < STOP - 1e-6 { pulses.append((t, db(-22) * db(1.5 * (t - DOUBLE) / (STOP - DOUBLE)))); t += 0.4 }
        t = ACT3 + 0.2
        while t < CRESC - 1e-6 { offbeats.append(t); t += 0.4 }
        tickBP.setBandPass(6000, q: 2.5)
        crossBP.setBandPass(4200, q: 3)
        // The small speaker: 700 Hz high-pass, 4.5 kHz low-pass.
        macHP.setHighPass(700); macLP.setLowPass(4500)
        clickLP.setLowPass(900)
        let (a, b) = Cues060.macSound
        t = a
        var step = 0
        while t < b - 1e-6 {
            if let chord = Cues060.chords.first(where: { t >= $0.0 && t < $0.1 })?.2 {
                let upper = Array(chord.suffix(3)).map { $0 + 12 }
                macNotes.append((t, upper[[0, 1, 2, 1, 2, 1, 0, 1][step % 8]]))
            }
            t += 0.2; step += 1
        }
    }

    private func noise() -> Double { Double(rng.next() % 2_000_001) / 1_000_000 - 1 }

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let t = Double(n + i) / SR
            var L = 0.0, R = 0.0
            func both(_ v: Double) { L += v; R += v }
            // The sub drone (A1 and A2) under the open, handing off by Act II (v4's 2.4 s rise and 2.0 s fade, 1.25×).
            if t < ACT2 + 0.1 {
                dronePh += 55 / SR; if dronePh >= 1 { dronePh -= 1 }
                drone2Ph += 110 / SR; if drone2Ph >= 1 { drone2Ph -= 1 }
                let g = db(-30) * 1.414 * min(1, t / 3.0) * (t > ACT2 - 2.5 ? max(0, (ACT2 - t) / 2.5) : 1)
                both(g * (sin(2 * .pi * dronePh) + db(-12) * sin(2 * .pi * drone2Ph)))
            }
            // The noise bed into Act II: low-passed 300 → 2500 Hz, −44 → −30 dBFS over its last 1.5 s (v4's 1.2, 1.25×), cut
            // at the hit.
            if t >= ACT2 - 1.5 && t < ACT2 + 0.02 {
                let p = clamp01((t - (ACT2 - 1.5)) / 1.5)
                if (n + i) % 64 == 0 { let f = 300 * pow(2500 / 300, p); bedL.setLowPass(f); bedR.setLowPass(f) }
                let g = db(-44 + 14 * p) * (t > ACT2 ? max(0, (ACT2 + 0.02 - t) / 0.02) : 1) * 2.5
                L += g * bedL.process(noise()); R += g * bedR.process(noise())
            }
            // The cutaway's riser: white noise through a band-pass sweeping 400 → 8000 Hz, −40 → −24 dBFS, to the stop.
            if t >= CRESC && t < STOP {
                let p = clamp01((t - CRESC) / (STOP - CRESC))
                if (n + i) % 64 == 0 { let f = 400 * pow(20, p * p); riserL.setBandPass(f, q: 1.2); riserR.setBandPass(f, q: 1.2) }
                var g = db(-40 + 16 * p * p) * 3
                if t > STOP - 0.015 { g *= max(0, (STOP - t) / 0.015) }
                L += g * riserL.process(noise()); R += g * riserR.process(noise())
            }
            // Hits: sine 90 → 58 Hz in 40 ms, 240 ms decay, and a 3 kHz click.
            for (ht, lv) in Cues060.hits where t >= ht && t < ht + 1.2 {
                let dt = t - ht
                let ph = 2 * .pi * (58 * dt + 32 * 0.012 * (1 - exp(-dt / 0.012)))
                both(db(lv) * exp(-dt / (0.24 / 4.6)) * sin(ph) + (dt < 0.006 ? db(-30) * sin(2 * .pi * 3000 * dt) * (1 - dt / 0.006) : 0))
            }
            // The pulse: sine 90 → 52 Hz, 180 ms decay.
            for (pt, lv) in pulses where t >= pt && t < pt + 0.4 {
                let dt = t - pt
                let ph = 2 * .pi * (52 * dt + 38 * 0.02 * (1 - exp(-dt / 0.02)))
                var v = lv * exp(-dt / (0.18 / 4.6)) * sin(ph)
                if t > STOP - 0.015 { v *= max(0, (STOP - t) / 0.015) }
                both(v)
            }
            // Touch ticks, 1.2 kHz, 25 ms.
            for tt in Cues060.taps where t >= tt && t < tt + 0.025 {
                let dt = t - tt
                both(db(-32) * sin(2 * .pi * 1200 * dt) * sin(.pi * dt / 0.025))
            }
            // Key ticks for the password, 3.2 kHz, 6 ms.
            for tt in Cues060.keyTicks where t >= tt && t < tt + 0.006 {
                let dt = t - tt
                both(db(-33) * sin(2 * .pi * 3200 * dt) * sin(.pi * dt / 0.006))
            }
            // The detent, 4 kHz, 5 ms.
            for tt in Cues060.detents where t >= tt && t < tt + 0.005 {
                let dt = t - tt
                both(db(-34) * sin(2 * .pi * 4000 * dt) * sin(.pi * dt / 0.005))
            }
            // Soft clicks: keycaps and the typing, 2.5 kHz, 8 ms.
            for tt in Cues060.softClicks where t >= tt && t < tt + 0.008 {
                let dt = t - tt
                both(db(-37) * sin(2 * .pi * 2500 * dt) * sin(.pi * dt / 0.008))
            }
            // Off-beat ticks in Act III, noise band-passed at 6 kHz, 20 ms.
            var tickIn = 0.0
            for tt in offbeats where t >= tt && t < tt + 0.02 { tickIn = noise() * sin(.pi * (t - tt) / 0.02) }
            both(db(-36) * 2.2 * tickBP.process(tickIn))
            // The cutaway's quiet ticks, one per line crossing the middle: noise at 4.2 kHz, 14 ms.
            var crossIn = 0.0
            for tt in Cues060.crossings where t >= tt && t < tt + 0.014 { crossIn = noise() * sin(.pi * (t - tt) / 0.014) }
            both(db(-34) * 2.4 * crossBP.process(crossIn))
            // S06: the Mac's sound, the pluck figure through a small speaker (700 Hz – 4.5 kHz), panned to the iPad's
            // side; Mute cuts it dead (5 ms) and it comes back with the next note.
            var mac = 0.0
            let (ma, mb) = Cues060.macSound
            if t >= ma - 0.01 && t < mb + 0.4 && !noMacSound {
                for (nt, m) in macNotes where t >= nt && t < nt + 0.5 {
                    let dt = t - nt
                    let f = midi(m)
                    let ph = 2 * .pi * f * dt
                    mac += db(-12) * exp(-dt / 0.065) * min(1, dt / 0.003) * (sin(ph) + 0.35 * sin(2 * ph) + 0.15 * sin(3 * ph))
                }
                let (m0, m1) = Cues060.mute
                if t >= m0 && t < m1 { mac *= t < m0 + 0.005 ? (m0 + 0.005 - t) / 0.005 : 0 }
                if t >= mb { mac *= max(0, 1 - (t - mb) / 0.05) }
            }
            let speaker = macLP.process(macHP.process(mac))
            let (gl, gr) = pan(0.3)
            L += speaker * gl * 1.414; R += speaker * gr * 1.414
            // The haptic buzz under "Esc": Taptic-like ticks at 180 Hz (2nd and 3rd harmonics), 18 a second.
            let (hs, hd) = Cues060.buzz
            if t >= hs && t < hs + hd {
                let u = t - hs
                let dt = u.truncatingRemainder(dividingBy: 1.0 / 18)
                let env = min(1, u / 0.04) * min(1, (hs + hd - t) / 0.12)
                let ph = 2 * .pi * 180 * dt
                let tone = (sin(ph) + db(-6) * sin(2 * ph) + db(-12) * sin(3 * ph)) / (1 + db(-6) + db(-12))
                both(db(-22) * env * tone * exp(-dt / 0.012))
            }
            // Everything above stops dead at the squash…
            if t >= STOP { L = 0; R = 0 }
            // …but the thud: a 58 Hz sine, 3 ms attack, 150 ms decay, over a low-passed click.
            if t >= STOP && t < STOP + 0.3 {
                let dt = t - STOP
                let env = min(1, dt / 0.003) * exp(-dt / (0.15 / 4.6))
                both(db(-14) * env * sin(2 * .pi * 58 * dt))
                let click = dt < 0.004 ? noise() * (1 - dt / 0.004) : 0
                both(db(-20) * clickLP.process(click))
            }
            l[i] = Float(L); r[i] = Float(R)
        }
        n += count
    }
}

// MARK: - The engine (Score.swift's)

enum Score060 {
    /// The pad's low-pass: dark under the open, opening into Act II; darkened while the Mac is locked; opening through
    /// the cutaway; the close at 4.5 kHz.
    static func padCutoff(_ t: Double) -> Double {
        // v4's, at the film's times: dark until the rise (3.2), opening to Act II (11.2); closing over 0.75 s on the lock's
        // bar (33.6) and opening again on the unlock's (41.6); opening through the cutaway; the close at 4.5 kHz.
        if t < 3.2 { return 900 }
        if t < ACT2 { return 900 * pow(3800.0 / 900, (t - 3.2) / (ACT2 - 3.2)) }
        if t < 33.6 { return 3800 }
        if t < 34.35 { return 3800 * pow(1400.0 / 3800, (t - 33.6) / 0.75) }
        if t < 41.6 { return 1400 }
        if t < 42.35 { return 1400 * pow(3800.0 / 1400, (t - 41.6) / 0.75) }
        if t < CRESC { return 3800 }
        if t < STOP { return 3800 * pow(9000.0 / 3800, (t - CRESC) / (STOP - CRESC)) }
        return 4500
    }

    static func renderPCM(gain: Double) throws -> (L: [Float], R: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
        let engine = AVAudioEngine()
        let pad = PadVoice060(), tonal = TonalVoice060(), dry = DryVoice060()
        func node(_ draw: @escaping (UnsafeMutablePointer<Float>, UnsafeMutablePointer<Float>, Int) -> Void) -> AVAudioSourceNode {
            AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
                let b = UnsafeMutableAudioBufferListPointer(abl)
                draw(b[0].mData!.assumingMemoryBound(to: Float.self), b[1].mData!.assumingMemoryBound(to: Float.self), Int(frameCount))
                return noErr
            }
        }
        let padNode = node { pad.render($0, $1, $2) }
        let tonalNode = node { tonal.render($0, $1, $2) }
        let dryNode = node { dry.render($0, $1, $2) }
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        eq.bands[0].filterType = .lowPass
        eq.bands[0].frequency = 900
        eq.bands[0].bypass = false
        let wet = AVAudioMixerNode()
        let reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 18
        let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let master = AVAudioMixerNode()
        for n in [padNode, tonalNode, dryNode, eq, wet, reverb, limiter, master] as [AVAudioNode] { engine.attach(n) }
        engine.connect(padNode, to: eq, format: format)
        engine.connect(eq, to: wet, format: format)
        engine.connect(tonalNode, to: wet, format: format)
        engine.connect(wet, to: reverb, format: format)
        engine.connect(reverb, to: master, format: format)
        engine.connect(dryNode, to: master, format: format)
        engine.connect(master, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        master.outputVolume = Float(gain)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
        var L = [Float](), R = [Float]()
        L.reserveCapacity(TOTAL); R.reserveCapacity(TOTAL)
        let stopFrame = Int(STOP * SR)
        var didReset = false
        while Int(engine.manualRenderingSampleTime) < TOTAL {
            let pos = Int(engine.manualRenderingSampleTime)
            var frames = min(256, TOTAL - pos)
            if pos < stopFrame && pos + frames > stopFrame { frames = stopFrame - pos }
            if pos >= stopFrame && !didReset {
                reverb.reset(); eq.reset(); limiter.reset(); didReset = true          // the stop clears the tails
            }
            eq.bands[0].frequency = Float(padCutoff(Double(pos) / SR))
            let status = try engine.renderOffline(AVAudioFrameCount(frames), to: buffer)
            guard status == .success else { throw NSError(domain: "Score060", code: 1, userInfo: [NSLocalizedDescriptionKey: "render \(status.rawValue)"]) }
            let ch = buffer.floatChannelData!
            L.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
            R.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: Int(buffer.frameLength)))
        }
        engine.stop()
        // From 0.2 s after the squash to the close: digital silence (the thud's tail is under −50 dB by then), black and the
        // sill line alone.
        for i in Int(SILENT * SR)..<min(Int(RESUME * SR), L.count) { L[i] = 0; R[i] = 0 }
        let n = L.count, fade = Int(TAIL * SR)
        for j in 0..<min(fade, n) {
            let i = n - 1 - j
            let g = Float(0.5 - 0.5 * cos(.pi * Double(j) / Double(fade)))
            L[i] *= g; R[i] *= g
        }
        return (L, R)
    }

    static func stats(_ L: [Float], _ R: [Float]) -> (peak: Double, rms: Double) {
        var peak: Float = 0, sum = 0.0, n = 0.0
        let s0 = Int(STOP * SR), s1 = Int(RESUME * SR)
        for i in 0..<L.count {
            peak = max(peak, abs(L[i]), abs(R[i]))
            if i >= s0 && i < s1 { continue }
            sum += Double(L[i] * L[i] + R[i] * R[i]); n += 2
        }
        return (20 * log10(Double(peak)), 10 * log10(sum / max(n, 1)))
    }

    static func render(args: [String]) throws {
        let m4a = URL(fileURLWithPath: args[0])
        var wav = m4a.deletingPathExtension().appendingPathExtension("wav")
        if let i = args.firstIndex(of: "--wav"), i + 1 < args.count { wav = URL(fileURLWithPath: args[i + 1]) }
        let (l1, r1) = try renderPCM(gain: 1)
        let s1 = stats(l1, r1)
        print(String(format: "score (0.6) pass 1: peak %.2f dBFS, RMS %.2f dBFS", s1.peak, s1.rms))
        let gain = pow(10, (-20 + 1.5 - s1.rms) / 20)
        var (L, R) = try renderPCM(gain: gain)
        let post = Float(db(-1.5))
        for i in 0..<L.count { L[i] *= post; R[i] *= post }
        let s2 = stats(L, R)
        print(String(format: "score (0.6) pass 2 (gain %.2f dB): peak %.2f dBFS, RMS %.2f dBFS", 20 * log10(gain), s2.peak, s2.rms))
        let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(L.count))!
        pcm.frameLength = AVAudioFrameCount(L.count)
        L.withUnsafeBufferPointer { pcm.floatChannelData![0].update(from: $0.baseAddress!, count: L.count) }
        R.withUnsafeBufferPointer { pcm.floatChannelData![1].update(from: $0.baseAddress!, count: R.count) }
        try? FileManager.default.removeItem(at: wav)
        let wf = try AVAudioFile(forWriting: wav, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: SR,
                                                             AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
                                                             AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false],
                                 commonFormat: .pcmFormatFloat32, interleaved: false)
        try wf.write(from: pcm)
        try? FileManager.default.removeItem(at: m4a)
        let af = try AVAudioFile(forWriting: m4a, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: SR,
                                                             AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 256_000],
                                 commonFormat: .pcmFormatFloat32, interleaved: false)
        try af.write(from: pcm)
        print("score (0.6): \(String(format: "%.2f", Double(L.count) / SR)) s → \(wav.path) and \(m4a.path)")
    }
}
