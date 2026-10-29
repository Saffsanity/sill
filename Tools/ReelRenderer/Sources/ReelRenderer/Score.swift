// Score.swift — §10: a generated score, synthesised in code. AVAudioEngine offline manual rendering with
// AVAudioSourceNode voices; the pad through an AVAudioUnitEQ low-pass; pad, plucks and tones through
// AVAudioUnitReverb (medium hall, 18 % wet); pulse, ticks and clicks dry; Apple's peak limiter on the
// master. No samples, no downloads.
import AudioToolbox
import AVFoundation
import Foundation

private let SR = 48_000.0
private let END = 83.2                  // v3: 52 bars (v2: 47 bars, 75.2 s)
private let TOTAL = Int(END * SR)
private let CRESC = 63.2                // C15: the short crescendo, now under S27's 1.5 bars (v2: S24's, 55.2)
private let DOUBLE = 64.0               // C15: the pulse doubles
private let STOP = 65.6                 // C16: hard stop to digital silence (the cut to "No subscription.")
private let RESUME = 66.0
private let FINAL = 68.8                // C18: the final chord (the glint returns)
private let RELEASE = 82.0              // C18 releases to silence at END
private let TAIL = 0.15                 // fourth cut: the master fades to zero over the last 150 ms

@inline(__always) private func db(_ d: Double) -> Double { pow(10, d / 20) }
@inline(__always) private func midi(_ n: Double) -> Double { 440 * pow(2, (n - 69) / 12) }
/// Equal-power pan: −1 (left) … +1 (right).
@inline(__always) private func pan(_ p: Double) -> (Double, Double) {
    let a = (p + 1) * .pi / 4
    return (cos(a), sin(a))
}

/// RBJ biquad (band-pass / low-pass), per channel state.
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
    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// Event times the score shares with the picture (v2 timeline).
enum Cues {
    static var taps: [Double] { [11.90, Events.heroTap, N1Switch.tapReel, Events.drawerTap] }   // C8, touch dots only
    static var plucks: [(Double, Double)] {                                          // C9 (time, MIDI)
        let rows = Conn.rows
        // The halo jump, S13's first Desktop frame (D6, the root of the D maj9 under it, on bar 15), the drawer,
        // S16's re-fit (E6, the root of the E6/9 under it), the rows: Wi‑Fi A5, Wired C♯6, Direct E6 and (v3)
        // Remote A6 on the bar line into the F♯m9, which closes the arpeggio; then the pairing done (v3, S26):
        // B5 and E6, 40 ms apart, on the E6/9 that starts under it.
        return [(Events.heroHalo, 81), (N1Switch.desktopReel, 86), (Events.drawerOpen, 81), (AaResize.refitReel, 88),
                (rows[0], 81), (rows[1], 85), (rows[2], 88), (rows[3], 93),
                (Pairing.flip, 83), (Pairing.flip + 0.04, 88)]
    }
    static var bells: [(Double, Double)] {                                           // C9b: C♯7, A6, E6, 40 ms apart
        let t = Events.lightsReel; return [(t, 97), (t + 0.04, 93), (t + 0.08, 88)]
    }
    /// C11, on the measured frames: HT-B's five (S15) and clip 12's value change (S16: 0.75× → 1× in the fourth cut).
    static var detents: [Double] { Events.detentReel + [AaResize.detentReel] }
    static let softClicks = [34.45, 34.85, 35.25, 40.05, 40.45, 40.85]              // S17's words, S19's words
    static var rollPlucks: [(Double, Double)] { [(Rate.roll, 81), (Rate.roll + 0.12, 93)] }  // C13: A5, A6
    /// C17: E5 and A5 on the two statements; the C♯6 that closed the old triad now lands on the Duo card.
    static let tones: [(Double, Double)] = [(58.00 + ActIV.shift, 76), (59.25 + ActIV.shift, 81), (Duo.headSnap + ActIV.shift, 85)]
    static let statementSnaps = [12.10, 16.10, 21.70, 26.50, 26.90, 28.90, 34.45, 34.85, 35.25, Haptic.lineSnap,
                                 40.05, 40.45, 40.85, Latency.streak, Rate.snap, Hidden.snap, 50.50, 50.90, 54.05, 54.45, 54.85,
                                 57.65, 58.05, Pairing.start + 0.05, Pairing.start + 0.45]
    static let shimmers = [0.9, FINAL + 0.1, Duo.glint + ActIV.shift]                 // C2: the glints
}

/// §7.1 (v3): the chord under the pad (MIDI notes); every change on a bar line. v2's E6/9 at 52.8 no longer
/// runs into the silence: at 57.6 it resolves deceptively to F♯m9 under "Or remote,", then D maj9 under the
/// pairing and E6/9 again from its done beat (62.4), the dominant into the silence at 65.6.
private let chords: [(Double, Double, [Double])] = [
    (2.4, 16.0, [45, 52, 59, 61, 64]), (16.0, 22.4, [42, 49, 52, 56, 57]), (22.4, 28.8, [38, 45, 49, 52, 54]),
    (28.8, 35.2, [40, 47, 49, 54, 56]), (35.2, 41.6, [45, 52, 59, 61, 64]), (41.6, 48.0, [42, 49, 52, 56, 57]),
    (48.0, 52.8, [38, 45, 49, 52, 54]), (52.8, 57.6, [40, 47, 49, 54, 56]),
    (57.6, 60.8, [42, 49, 52, 56, 57]), (60.8, 62.4, [38, 45, 49, 52, 54]), (62.4, 65.6, [40, 47, 49, 54, 56]),
]
private let finalChord: [Double] = [45, 52, 57, 59, 61, 64, 69]

// MARK: - Voices

/// The pad (C3, harmony, C4 swell, C15, C18): per note two sines at ±4 cents and a triangle at −12 dB;
/// 1.2 s attack, 0.8 s equal-power crossfades centred on each change, 0.2 Hz tremolo at 8 %.
private final class PadVoice {
    var n = 0
    var phases = [Double](repeating: 0, count: 256)
    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let t = Double(n + i) / SR
            var L = 0.0, R = 0.0
            var k = 0
            // Chord segments with equal-power crossfades.
            if t >= 2.4 && t < STOP {
                let attack = min(1, (t - 2.4) / 1.2)
                // Sustained voices are set by RMS: five notes at amplitude a give ≈ 1.15·a per channel.
                var level = db(-26) / 1.15 * attack
                level *= 1 + 0.08 * sin(2 * .pi * 0.2 * (t - 2.4))                   // tremolo
                level *= 1 + 0.5 * clamp01((t - CRESC) / (STOP - CRESC))              // C15: the crescendo builds
                if t > STOP - 0.015 { level *= max(0, (STOP - t) / 0.015) }           // C16
                for (ci, (a, b, notes)) in chords.enumerated() {
                    var w = 0.0
                    let fadeIn = ci == 0 ? 1.0 : clamp01((t - (a - 0.4)) / 0.8)
                    let fadeOut = ci == chords.count - 1 ? 1.0 : clamp01(((b + 0.4) - t) / 0.8)
                    if t >= a - 0.4 && t < b + 0.4 { w = sin(.pi / 2 * fadeIn) * sin(.pi / 2 * fadeOut) }
                    if w > 0 {
                        for note in notes {
                            let f = midi(note)
                            let (s1, s2, tri) = oscillate(&k, f)
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
            // C18: the final chord, full voicing, 0.25 s attack, a lift as the Duo unfolds, released to silence
            // at the end.
            if t >= FINAL {
                // −18 dBFS read as the chord's peak: about −22 dBFS RMS for seven notes (1.36·a per channel).
                var level = db(-22) / 1.36 * min(1, (t - FINAL) / 0.25)
                if t > RELEASE { level *= pow(max(0, (END - t) / (END - RELEASE)), 2) }
                level *= 1 + 0.08 * sin(2 * .pi * 0.2 * (t - FINAL))
                level *= 1 + 0.3 * max(0, sin(.pi * clamp01((t - (Duo.unfold + ActIV.shift)) / 1.6)))  // C20: the Duo swell
                for note in finalChord {
                    let (s1, s2, tri) = oscillate(&k, midi(note))
                    L += level * (s1 * 0.62 + s2 * 0.38 + tri * 0.25)
                    R += level * (s1 * 0.38 + s2 * 0.62 + tri * 0.25)
                }
            }
            l[i] = Float(L); r[i] = Float(R)
        }
        n += count
    }
    /// Two sines at ±4 cents and a triangle (−12 dB), advancing three phase slots.
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


/// Plucks, bells, tones, shimmer and the Act III arpeggio (all through the reverb).
private final class TonalVoice {
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
        // C2: glint shimmer, 2637 and 3520 Hz, 4 ms attack, 0.9 s decay, panned −0.6 → +0.6 over 1.2 s.
        for t in Cues.shimmers {
            add(t, 2637, db(-30) * 0.5, decay: 0.9 / 4.6, harmonic: 1, hgain: 0, pan: -0.6, to: 0.6, over: 1.2)
            add(t, 3520, db(-30) * 0.5, decay: 0.9 / 4.6, harmonic: 1, hgain: 0, pan: -0.6, to: 0.6, over: 1.2)
        }
        // C9: UI plucks, sine + 2nd harmonic at −12 dB, 250 ms decay.
        for (t, m) in Cues.plucks { add(t, midi(m), db(-26), decay: 0.25 / 4.6) }
        // C9b: the lights' bells, sine + a ×2.76 partial at −14 dB, τ 180 ms.
        for (t, m) in Cues.bells { add(t, midi(m), db(-26), decay: 0.18, harmonic: 2.76, hgain: db(-14)) }
        // C13: the roll plucks.
        for (t, m) in Cues.rollPlucks { add(t, midi(m), db(-28), decay: 0.25 / 4.6) }
        // C17: three tones, sine + 2nd harmonic at −14 dB, 5 ms attack, 1.1 s decay.
        for (t, m) in Cues.tones { add(t, midi(m), db(-24), decay: 1.1 / 4.6, attack: 0.005, hgain: db(-14)) }
        // C10: sine plucks on the current chord's upper notes in eighths, 300 ms decay (Act III, until the
        // pulse doubles).
        var t = 28.8
        var step = 0
        while t < DOUBLE - 1e-6 {
            if let chord = chords.first(where: { t >= $0.0 && t < $0.1 })?.2 {
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
                if t >= STOP && note.start < STOP { continue }                      // C16 cuts everything
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

/// `SILL_NO_BUZZ=1` renders the score without C19, for an A/B difference check.
private let noBuzz = ProcessInfo.processInfo.environment["SILL_NO_BUZZ"] != nil

/// Drone, hits, pulse, ticks, clicks, the zip, the thud, the noise bed and the riser (dry).
private final class DryVoice {
    var n = 0
    var rng = SplitMix64(seed: 0xC0FFEE)
    var bedL = Biquad(), bedR = Biquad()
    var riserL = Biquad(), riserR = Biquad()
    var tickBP = Biquad()
    var dronePh = 0.0, drone2Ph = 0.0
    struct Hit { let t: Double; let level: Double }
    var hits: [Hit] = []
    var pulses: [(Double, Double)] = []
    var offbeats: [Double] = []

    init() {
        hits = [Hit(t: 6.4, level: db(-14)), Hit(t: 8.0, level: db(-18)), Hit(t: Latency.start, level: db(-16))]
        // C7: every 0.8 s from 9.6, +3 dB on statement snaps; C15: every 0.4 s from 56.0 to the stop, rising.
        var t = 9.6
        while t < DOUBLE - 1e-6 {
            let accent = Cues.statementSnaps.contains { abs($0 - t) <= 0.15 }
            pulses.append((t, db(-22) * (accent ? db(3) : 1)))
            t += 0.8
        }
        t = DOUBLE
        while t < STOP - 1e-6 { pulses.append((t, db(-22) * db(1.5 * (t - DOUBLE) / (STOP - DOUBLE)))); t += 0.4 }
        // C10: off-beat ticks, Act III until the pulse doubles.
        t = 29.0
        while t < DOUBLE - 1e-6 { offbeats.append(t); t += 0.4 }
        tickBP.setBandPass(6000, q: 2.5)
    }

    private func noise() -> Double { Double(rng.next() % 2_000_001) / 1_000_000 - 1 }

    func render(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ count: Int) {
        for i in 0..<count {
            let t = Double(n + i) / SR
            var L = 0.0, R = 0.0
            func both(_ v: Double) { L += v; R += v }
            // C1: sub drone, A1 55 Hz + 110 Hz at −12 dB, in from silence over 0–2.4, handing off by 6.4.
            if t < 6.5 {
                dronePh += 55 / SR; if dronePh >= 1 { dronePh -= 1 }
                drone2Ph += 110 / SR; if drone2Ph >= 1 { drone2Ph -= 1 }
                let g = db(-30) * 1.414 * min(1, t / 2.4) * (t > 4.4 ? max(0, (6.4 - t) / 2.0) : 1)
                both(g * (sin(2 * .pi * dronePh) + db(-12) * sin(2 * .pi * drone2Ph)))
            }
            // C4: noise bed, low-pass 300 → 2500 Hz, −44 → −30 dBFS, over 4.4–6.4 (cut at the hit).
            if t >= 4.4 && t < 6.42 {
                let p = clamp01((t - 4.4) / 2.0)
                if (n + i) % 64 == 0 { let f = 300 * pow(2500 / 300, p); bedL.setLowPass(f); bedR.setLowPass(f) }
                let g = db(-44 + 14 * p) * (t > 6.4 ? max(0, (6.42 - t) / 0.02) : 1) * 2.5
                L += g * bedL.process(noise()); R += g * bedR.process(noise())
            }
            // C15: the riser, white noise through a band-pass sweeping 400 → 8000 Hz, −40 → −24 dBFS.
            if t >= CRESC && t < STOP {
                let p = clamp01((t - CRESC) / (STOP - CRESC))
                if (n + i) % 64 == 0 { let f = 400 * pow(20, p); riserL.setBandPass(f, q: 1.2); riserR.setBandPass(f, q: 1.2) }
                var g = db(-40 + 16 * p) * 3
                if t > STOP - 0.015 { g *= max(0, (STOP - t) / 0.015) }
                L += g * riserL.process(noise()); R += g * riserR.process(noise())
            }
            // C5/C6 hits and the S18 hit: sine 90 → 58 Hz in 40 ms, 240 ms decay, plus a 3 kHz click.
            for h in hits where t >= h.t && t < h.t + 1.2 {
                let dt = t - h.t
                let f = 58 + 32 * exp(-dt / 0.012)
                let ph = 2 * .pi * (58 * dt + 32 * 0.012 * (1 - exp(-dt / 0.012)))
                _ = f
                both(h.level * exp(-dt / (0.24 / 4.6)) * sin(ph) + (dt < 0.006 ? db(-30) * sin(2 * .pi * 3000 * dt) * (1 - dt / 0.006) : 0))
            }
            // C7 / C15: the pulse, sine 90 → 52 Hz, 180 ms decay.
            for (pt, lv) in pulses where t >= pt && t < pt + 0.4 {
                let dt = t - pt
                let ph = 2 * .pi * (52 * dt + 38 * 0.02 * (1 - exp(-dt / 0.02)))
                var v = lv * exp(-dt / (0.18 / 4.6)) * sin(ph)
                if t > STOP - 0.015 { v *= max(0, (STOP - t) / 0.015) }
                both(v)
            }
            // C8: tap ticks, 1.2 kHz, 25 ms.
            for tt in Cues.taps where t >= tt && t < tt + 0.025 {
                let dt = t - tt
                both(db(-32) * sin(2 * .pi * 1200 * dt) * sin(.pi * dt / 0.025))
            }
            // C11: detent clicks, 4 kHz, 5 ms (on the measured detent frames).
            for tt in Cues.detents where t >= tt && t < tt + 0.005 {
                let dt = t - tt
                both(db(-34) * sin(2 * .pi * 4000 * dt) * sin(.pi * dt / 0.005))
            }
            // Soft clicks on S15's and S17's words.
            for tt in Cues.softClicks where t >= tt && t < tt + 0.008 {
                let dt = t - tt
                both(db(-36) * sin(2 * .pi * 2500 * dt) * sin(.pi * dt / 0.008))
            }
            // C10: off-beat ticks, noise band-passed at 6 kHz, 20 ms.
            var tickIn = 0.0
            for tt in offbeats where t >= tt && t < tt + 0.02 {
                let dt = t - tt
                tickIn = noise() * sin(.pi * dt / 0.02)
            }
            let tick = tickBP.process(tickIn)
            both(db(-36) * 2.2 * tick)
            // C19: the haptic buzz under "haptic" (S17): Taptic-like ticks at 180 Hz with the 2nd and 3rd
            // harmonics (−6, −12 dB, so laptop speakers carry it), 12 ms decay, 18 per second, in over 0.04 s and
            // settling over the last 0.12 s, like the word's jitter. −22 dBFS peak.
            let hs = Haptic.jitterStart, hd = Haptic.jitterDuration
            if t >= hs && t < hs + hd && !noBuzz {
                let u = t - hs
                let dt = u.truncatingRemainder(dividingBy: 1.0 / 18)
                let env = min(1, u / 0.04) * min(1, (hs + hd - t) / 0.12)
                let ph = 2 * .pi * 180 * dt
                let tone = (sin(ph) + db(-6) * sin(2 * ph) + db(-12) * sin(3 * ph)) / (1 + db(-6) + db(-12))
                both(db(-22) * env * tone * exp(-dt / 0.012))
            }
            // C12: the zip, sine sweep 700 → 3000 Hz over 250 ms, panned L → R.
            if t >= Latency.streak && t < Latency.streak + 0.25 {
                let dt = t - Latency.streak, u = dt / 0.25
                let ph = 2 * .pi * 700 * 0.25 * (pow(3000.0 / 700, u) - 1) / log(3000.0 / 700)
                let v = db(-28) * sin(ph) * sin(.pi * u)
                let (gl, gr) = pan(-0.8 + 1.6 * u)
                L += v * gl * 1.414; R += v * gr * 1.414
            }
            // C14: the cover thud, sine 70 Hz, 160 ms.
            if t >= Hidden.thud && t < Hidden.thud + 0.16 {
                let dt = t - Hidden.thud
                both(db(-20) * sin(2 * .pi * 70 * dt) * exp(-dt / 0.04) * min(1, dt / 0.003))
            }
            if t >= STOP && t < RESUME { L = 0; R = 0 }
            l[i] = Float(L); r[i] = Float(R)
        }
        n += count
    }
}

// MARK: - The engine

enum Score {
    /// Pad low-pass: 900 Hz; opens to 3,800 across C4; 3,800 → 9,000 in C15; the close at 4,500.
    static func padCutoff(_ t: Double) -> Double {
        if t < 4.4 { return 900 }
        if t < 6.4 { return 900 * pow(3800.0 / 900, (t - 4.4) / 2.0) }
        if t < CRESC { return 3800 }
        if t < STOP { return 3800 * pow(9000.0 / 3800, (t - CRESC) / (STOP - CRESC)) }
        return 4500
    }

    static func renderPCM(gain: Double) throws -> (L: [Float], R: [Float]) {
        let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
        let engine = AVAudioEngine()
        let pad = PadVoice(), tonal = TonalVoice(), dry = DryVoice()
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
            if pos < stopFrame && pos + frames > stopFrame { frames = stopFrame - pos }       // land a chunk on the stop
            if pos >= stopFrame && !didReset {
                reverb.reset(); eq.reset(); limiter.reset(); didReset = true                     // C16: clear the tails
            }
            eq.bands[0].frequency = Float(padCutoff(Double(pos) / SR))
            let status = try engine.renderOffline(AVAudioFrameCount(frames), to: buffer)
            guard status == .success else { throw NSError(domain: "Score", code: 1, userInfo: [NSLocalizedDescriptionKey: "render \(status.rawValue)"]) }
            let ch = buffer.floatChannelData!
            L.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
            R.append(contentsOf: UnsafeBufferPointer(start: ch[1], count: Int(buffer.frameLength)))
        }
        engine.stop()
        // The STOP–RESUME window (65.6–66.0 in v3) is digital silence (the film's loudest moment).
        for i in stopFrame..<min(Int(RESUME * SR), L.count) { L[i] = 0; R[i] = 0 }
        // v2's fourth cut: the reverb's tail was still at −44 dBFS in the last 20 ms, so the file ended on a cut, not
        // on silence. A raised-cosine fade to exact zero over the last 150 ms (the chord itself is ≈ −70 dB there).
        let n = L.count, fade = Int(TAIL * SR)
        for j in 0..<min(fade, n) {
            let i = n - 1 - j                                   // j = 0 is the last sample
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
        // Pass 1 at unity to measure; pass 2 at the gain that puts the mix at −20 dBFS RMS.
        let (l1, r1) = try renderPCM(gain: 1)
        let s1 = stats(l1, r1)
        print(String(format: "score pass 1: peak %.2f dBFS, RMS %.2f dBFS", s1.peak, s1.rms))
        let gain = pow(10, (-20 + 1.5 - s1.rms) / 20)
        var (L, R) = try renderPCM(gain: gain)
        // Ceiling: the limiter holds 0 dBFS; −1.5 dB after it leaves headroom for AAC.
        let post = Float(db(-1.5))
        for i in 0..<L.count { L[i] *= post; R[i] *= post }
        let s2 = stats(L, R)
        print(String(format: "score pass 2 (gain %.2f dB): peak %.2f dBFS, RMS %.2f dBFS", 20 * log10(gain), s2.peak, s2.rms))

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
        print("score: \(String(format: "%.2f", Double(L.count) / SR)) s → \(wav.path) and \(m4a.path)")
    }
}
