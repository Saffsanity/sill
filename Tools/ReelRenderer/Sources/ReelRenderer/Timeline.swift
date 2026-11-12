// Timeline.swift — SHOTLIST-v2 §2 as data, and its shots as frame builders.
// Mapping for real clips and takes: clip_t = in + (reel_t − shot_start), always 1×.
import SwiftUI

struct Shot {
    let id: String
    let start: Double
    let end: Double
    let source: String                      // for the sheet and SHOTLIST notes
    let clip: (ClipID, Double)?             // (clip, in-point) when the shot plays footage
    let build: @MainActor (Double, Env) throws -> FrameLayers
    var frames: ClosedRange<Int> { Int((start * 60).rounded())...(Int((end * 60).rounded()) - 1) }
}

// MARK: - Event alignment (measured on the takes; §8.2 "align by the event frame")
//
// v2 keeps every take's measured event and moves only its reel time; each in-point is recomputed so the
// event lands on its new beat.

enum Events {
    static let htB_unfold = 3.118              // HT-B: the ruler unfolds
    static let htB_detents = [3.533, 3.957, 4.377, 4.798, 5.218]
    static let htD_lights = 2.758              // HT-D: the lights pop (the take runs to 6.695 s)
    static let htE_rows = [2.190, 2.583, 3.008] // HT-E: Wi‑Fi, Wired, Direct rows (sample PTS; the take runs to 6.543 s)
    static let htE_jump: CGFloat = 56           // HT-E: the column re-centres 56 interior px up per row
    // Reel times of the events (v2 timeline, SHOTLIST-v2 §2).
    static let unfoldReel = 28.85               // S15 starts 28.8
    static let lightsReel = 40.02               // S19 starts 40.0
    static let row1Reel = 54.00                 // S24 starts 53.6
    // In-points so each event lands on its reel time.
    static let inB = htB_unfold - (unfoldReel - 28.8)
    static let inD = htD_lights - (lightsReel - 40.0)
    static let inE = htE_rows[0] - (row1Reel - 53.6)
    /// Reel times of take events.
    static var detentReel: [Double] { htB_detents.map { 28.8 + ($0 - inB) } }
    static var rowsReel: [Double] { htE_rows.map { 53.6 + ($0 - inE) } }
    // R05's hero (S10, 17.6–19.6): the tap at clip 0.98, the halo jump at 1.035, one black restart frame,
    // Blender from 1.115.
    static let heroStart = 17.6
    static var heroTap: Double { heroStart + 0.98 }
    static var heroHalo: Double { heroStart + 1.035 }
    // R02's drawer (S14, 26.4–28.8): the Apps touch at clip 3.50, the drawer at 3.62.
    static let drawerStart = 26.4, drawerIn = 3.36
    static var drawerTap: Double { drawerStart + (3.50 - drawerIn) }
    static var drawerOpen: Double { drawerStart + (3.62 - drawerIn) }
}

// MARK: - Privacy treatments (§7.2), as functions of clip time
//
// v2 (Noah's note 3, "don't blur any of the apps; Weather is fine, Blender is fine", and the 2026-09-25
// clearance of Weather's home location in noah-notes.md): Weather and Blender are no longer blurred. What
// stays blurred is what the README's privacy list still forbids, none of it an app Noah cleared:
// - VS Code's private file (R05 before the pick, clip < 1.095): σ 16 on the stream;
// - Blender's Recent Files list (Noah's .blend names): a tight σ 12 on the names only;
// - the strip's private thumbnails in R04 before the swipe settles (Claude's conversation, a Messages photo
//   and a Chrome video with faces): σ 12, easing to 0 over 22.45–22.75 as in v1;
// - R02's Desktop around the drawer (P5) and R08's footnote bands (P7), unchanged.
// Every mask is at full strength on its rect's edge; the feather lies outside (Clip.swift `mask`).

enum P {
    static let strip = Region.edges(190, 10, 1340, 165, sigma: 12, feather: 16)
    /// The stream area below the bar, to the interior's foot.
    static func stream(_ sigma: Double) -> Region { Region.edges(0, 184, 2000, 1420, sigma: sigma, feather: 16) }
    /// Blender's Recent Files names (the header "Recent Files" and the New File column stay sharp).
    static let recentFiles = Region.edges(1015, 842, 1290, 1060, sigma: 12, feather: 16)
    /// P2 (R04, S07–S09): the stream (Weather) sharp; the strip σ 12 until 22.45, then 0 by 22.75.
    static func p2(_ c: Double) -> Treatment {
        let s = 12 * (1 - CubicBezier.inOut(ramp(c, 22.45, 22.75)))
        return Treatment(regions: s > 0.05 ? [Region.edges(190, 10, 1340, 165, sigma: s, feather: 16)] : [])
    }
    /// P3 (R04, S23): Weather sharp; the strip σ 12 (it still shows the private thumbnails before 21 s).
    static let p3 = Treatment(regions: [strip])
    /// P4 (R05): the stream σ 16 while VS Code's private file shows (clip < 1.095); then Blender sharp with
    /// only the Recent Files names at σ 12.
    static func p4(_ c: Double) -> Treatment {
        Treatment(regions: c < 1.095 ? [stream(16)] : [recentFiles])
    }
    /// P5 (R02): below the bar σ 24 at 60 % until 3.62; then the drawer ramps σ 24 → 0 (3.62–3.78);
    /// right of the drawer σ 24 at 60 % always; the strip σ 12 always.
    static func p5(_ c: Double) -> Treatment {
        if c < 3.62 {
            return Treatment(regions: [Region.edges(0, 172, 2000, 1420, sigma: 24, brightness: 0.6, feather: 16), strip])
        }
        let k = ramp(c, 3.62, 3.78)
        var r = [Region.edges(804, 172, 2000, 1420, sigma: 24, brightness: 0.6, feather: 4), strip]
        if k < 1 {
            r.insert(Region.edges(45, 190, 803, 1390, sigma: 24 * (1 - k), brightness: 0.6 + 0.4 * k, feather: 16), at: 0)
        }
        return Treatment(regions: r)
    }
    /// P7 (R08, S21's background): the footnote bands; x < 1265 σ 16. σ 14 with a 16 px feather over
    /// rects that cover the measured text rows (807–865, 999–1057).
    static let p7 = Treatment(regions: [Region.edges(1240, 792, 2000, 880, sigma: 14, feather: 16),
                                        Region.edges(1240, 984, 2000, 1072, sigma: 14, feather: 16),
                                        Region.edges(0, 172, 1265, 1420, sigma: 16)])
    /// N1 (clip 11, S13; README.md "Approved (round 4)"): on the Desktop, Blender's splash lists Noah's Recent
    /// Files names (his project files). A tight σ 8 on the five names only: their icons, the
    /// "Recent Files" header, "Donate" and the splash art stay sharp, so the splash still reads as a splash. The
    /// menu bar's account name and clock may stay (cleared). Weather, before the switch, is untouched (note 3).
    static let n1Names = Region.edges(1038, 891, 1268, 1025, sigma: 8, feather: 10)
    static func n1(samplePTS pts: Double) -> Treatment {
        Treatment(regions: pts >= N1Switch.desktop - 0.002 ? [n1Names] : [])
    }
}

// MARK: - The timeline (v3: 83.2 s, 52 bars; acts on bar lines at 0, 9.6, 28.8 and 65.6 s)

@MainActor
enum Timeline {
    static let shots: [Shot] = [
        // Act I · darkness and the promise (0–9.6, 6 bars)
        Shot(id: "S01", start: 0.0, end: 2.4, source: "drawn", clip: nil, build: s01),
        Shot(id: "S02", start: 2.4, end: 4.4, source: "drawn", clip: nil, build: s02),
        Shot(id: "S03", start: 4.4, end: 6.4, source: "drawn", clip: nil, build: s03),
        Shot(id: "S04", start: 6.4, end: 8.0, source: "type", clip: nil, build: s04),
        Shot(id: "S05", start: 8.0, end: 9.6, source: "type", clip: nil, build: s05),
        // Act II · any window (9.6–28.8, 12 bars)
        Shot(id: "S06", start: 9.6, end: 12.0, source: "R01 2.30→4.70", clip: (.r01, 2.30), build: s06),
        Shot(id: "S07", start: 12.0, end: 13.6, source: "R04 19.00→20.60 (rack in)", clip: (.r04, 19.00), build: s07),
        Shot(id: "S08", start: 13.6, end: 16.0, source: "R04 20.60→23.00", clip: (.r04, 20.60), build: s08),
        Shot(id: "S09", start: 16.0, end: 17.6, source: "R04 hold 23.00", clip: nil, build: s09),
        Shot(id: "S10", start: 17.6, end: 19.6, source: "R05 0.00→2.00", clip: (.r05, 0.00), build: s10),
        Shot(id: "S11", start: 19.6, end: 21.6, source: "R05 2.00→4.00", clip: (.r05, 2.00), build: s11),
        // Fourth cut: S12 lends S13 one beat (1.6 → 1.2 s), so N1 opens on 0.4 s of Weather before the tap.
        Shot(id: "S12", start: 21.6, end: 22.8, source: "R05 4.00→5.20", clip: (.r05, 4.00), build: s12),
        Shot(id: "S13", start: 22.8, end: 26.4, source: "N1 clip 11 1.245→4.845 (window → Desktop)", clip: (.n1, N1Switch.inPoint), build: s13),
        Shot(id: "S14", start: 26.4, end: 28.8, source: "R02 3.36→5.76", clip: (.r02, 3.36), build: s14),
        // Act III · it feels local (28.8–65.6, 23 bars; v2's 18 plus the 5 of the remote beats)
        Shot(id: "S15", start: 28.8, end: 31.2, source: "HT-B", clip: (.htB, Events.inB), build: s15),
        Shot(id: "S16", start: 31.2, end: 34.4, source: AaResize.reverse ? "N2 clip 12 10.06→13.26 (Aa 0.75× → 1×)" : "N2 clip 12 2.29→5.49 (Aa 1× → 0.75×)",
             clip: (.n2, AaResize.inPoint), build: s16),
        Shot(id: "S17", start: 34.4, end: 37.6, source: "HT-C", clip: nil, build: s17),
        Shot(id: "S18", start: 37.6, end: 40.0, source: "N3 clip 13 2.95→5.35 (trackpad pointer, push-in)", clip: (.n3, Pointer.inPoint), build: s18),
        Shot(id: "S19", start: 40.0, end: 42.4, source: "HT-D", clip: (.htD, Events.inD), build: s19),
        Shot(id: "S20", start: 42.4, end: 45.6, source: "drawn", clip: nil, build: s20),
        Shot(id: "S21", start: 45.6, end: 48.8, source: "R08 1.50→4.70", clip: (.r08, 1.50), build: s21),
        Shot(id: "S22", start: 48.8, end: 50.4, source: "drawn", clip: nil, build: s22),
        Shot(id: "S23", start: 50.4, end: 53.6, source: "R04 5.00→8.20", clip: (.r04, 5.00), build: s23),
        // v3: the connection-methods beat on the current client (stills, V3.swift), then the remote beats.
        Shot(id: "S24", start: 53.6, end: 57.6, source: "harness stills c0–c3 (8b0d418)", clip: nil, build: s24),
        Shot(id: "S25", start: 57.6, end: 60.8, source: "harness still c4 (8b0d418): the Remote row", clip: nil, build: s25r),
        Shot(id: "S26", start: 60.8, end: 63.2, source: "Mac pairing window (previews) + harness stills addmac/paired", clip: nil, build: s26p),
        Shot(id: "S27", start: 63.2, end: 65.6, source: "harness still s-remote (8b0d418): the panel's route line", clip: nil, build: s27t),
        // Act IV · silence and the close (65.6–83.2, 11 bars): v2's S25–S32, 8.0 s (5 bars) later. Each builder
        // is v2's own, handed v2's time, so every event inside keeps its place relative to the act.
        Shot(id: "S28", start: 65.6, end: 67.2, source: "type", clip: nil, build: { t, e in try s25(t - ActIV.shift, e) }),
        Shot(id: "S29", start: 67.2, end: 68.8, source: "type", clip: nil, build: { t, e in try s26(t - ActIV.shift, e) }),
        Shot(id: "S30", start: 68.8, end: 71.2, source: "drawn", clip: nil, build: { t, e in try s27(t - ActIV.shift, e) }),
        Shot(id: "S31", start: 71.2, end: 73.6, source: "drawn + type", clip: nil, build: { t, e in try s28(t - ActIV.shift, e) }),
        Shot(id: "S32", start: 73.6, end: 76.0, source: "type", clip: nil, build: { t, e in try s29(t - ActIV.shift, e) }),
        Shot(id: "S33", start: 76.0, end: 78.4, source: "type", clip: nil, build: { t, e in try s30(t - ActIV.shift, e) }),
        Shot(id: "S34", start: 78.4, end: 82.0, source: "drawn + type", clip: nil, build: { t, e in try s31(t - ActIV.shift, e) }),
        Shot(id: "S35", start: 82.0, end: 83.2, source: "—", clip: nil, build: { t, e in try s32(t - ActIV.shift, e) }),
    ]

    static func shot(at frame: Int) -> Shot {
        shots.first { $0.frames.contains(frame) } ?? shots.last!
    }
}

/// Clip time for a shot with an in-point.
@inline(__always) func ct(_ t: Double, _ start: Double, _ inPoint: Double) -> Double { inPoint + (t - start) }
