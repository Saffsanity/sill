// ShotsII.swift — Acts II and III (S06–S24, v2): real footage in devices and macros, harness takes, type,
// and the three pending captures (Pending.swift).
import AppKit
import SwiftUI

// MARK: - Helpers

/// Screen point of an interior point for an unrotated device centred at `center`.
func screenPoint(_ spec: DeviceSpec, center: CGPoint, interior p: CGPoint) -> CGPoint {
    let s = spec.clipScale
    return CGPoint(x: center.x - spec.interior.width / 2 + p.x * s, y: center.y - spec.interior.height / 2 + p.y * s)
}

@MainActor func clipImage(_ e: Env, _ id: ClipID, _ c: Double, _ tr: Treatment, scale: CGFloat, sub: CGRect? = nil) throws -> CGImage {
    try e.clips.image(id, at: c, treatment: tr, scale: scale, sub: sub).image
}

/// A device shot (stack D): glow with parallax, optional sill line, the device, type on top.
@MainActor func deviceShot(spec: DeviceSpec, center: CGPoint, yaw: Double = 0, pitch: Double = 0,
                           push: CGFloat = 1, pushAbout: CGPoint? = nil, postPush: (scale: CGFloat, about: CGPoint)? = nil,
                           drift: CGSize = .zero,
                           image: CGImage?, dots: [TouchDotSpec] = [], t: Double,
                           sill: (y: CGFloat, length: CGFloat, x: CGFloat)? = nil, glow: Double = 0.06,
                           glowCenter: CGPoint? = nil, screenOverlay: AnyView? = nil,
                           lines: [LineSpec] = [], typeAboveDevice: Bool = true) -> AnyView {
    let c = CGPoint(x: center.x + drift.width, y: center.y + drift.height)
    let gc = glowCenter ?? center
    let group = ZStack {
        if let sill { SillLine(y: sill.y + 0.5 * drift.height, length: sill.length, centerX: sill.x + 0.5 * drift.width) }
        PlacedDevice(spec: spec, center: c, yaw: yaw, pitch: pitch) {
            ZStack(alignment: .topLeading) {
                ClipScreen(image: image, size: spec.interior, dots: dots, t: t)
                if let screenOverlay { screenOverlay }
            }
        }
    }
    .canvas()
    .scaled(push, about: pushAbout ?? c)
    let v = ZStack {
        Backdrop(glow: glow, glowCenter: CGPoint(x: gc.x - 0.25 * drift.width, y: gc.y - 0.25 * drift.height))
        // Fourth cut: a second push about its own anchor (S18's push-in), a render transform like the first.
        if let pp = postPush { group.scaled(pp.scale, about: pp.about) } else { group }
        if typeAboveDevice { TypeLayer(lines: lines, t: t) }
    }.canvas()
    return any(v)
}

/// A macro shot (stack M): partial device, the crop, type.
@MainActor func macroShot(_ m: MacroSpec, image: CGImage?, dots: [TouchDotSpec] = [], t: Double,
                          scale: CGFloat = 1, drift: CGSize = .zero, lines: [LineSpec] = [],
                          cardRadius: CGFloat? = nil) -> AnyView {
    let o = m.screenOrigin
    let cropCentre = CGPoint(x: o.x + m.crop.width * m.scale / 2, y: o.y + m.crop.height * m.scale / 2)
    let macro = MacroView(spec: m, image: image) {
        ZStack(alignment: .topLeading) {
            ForEach(0..<dots.count, id: \.self) { i in TouchDot(spec: dots[i], t: t, clipScale: m.scale) }
        }
    }
    let v = ZStack {
        Color.black
        Group {
            if let r = cardRadius {
                macro.mask(RoundedRectangle(cornerRadius: r, style: .continuous)
                    .frame(width: m.crop.width * m.scale, height: m.crop.height * m.scale)
                    .position(x: cropCentre.x, y: cropCentre.y).canvas())
            } else {
                macro
            }
        }
        .offset(x: drift.width, y: drift.height)
        .scaled(scale, about: CGPoint(x: cropCentre.x + drift.width, y: cropCentre.y + drift.height))
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return any(v)
}

/// A macro spec whose crop edges within `snap` interior px of the device's edge are pushed to it, so
/// the bezel (and its rounded corner) is drawn there; the screen position of the specified crop is kept.
func macro(crop: CGRect, scale: CGFloat, center: CGPoint? = nil, origin: CGPoint? = nil, snap: CGFloat = 40,
           feather: CGFloat = 70, hard: Set<Edge> = [], interior: CGSize = CGSize(width: 2000, height: 1420)) -> MacroSpec {
    let o0: CGPoint = origin ?? CGPoint(x: (center?.x ?? 960) - crop.width * scale / 2, y: (center?.y ?? 540) - crop.height * scale / 2)
    var c = crop
    var o = o0
    if c.minX > 0 && c.minX <= snap { o.x -= c.minX * scale; c.size.width += c.minX; c.origin.x = 0 }
    if c.minY > 0 && c.minY <= snap { o.y -= c.minY * scale; c.size.height += c.minY; c.origin.y = 0 }
    if c.maxX < interior.width && interior.width - c.maxX <= snap { c.size.width = interior.width - c.minX }
    if c.maxY < interior.height && interior.height - c.maxY <= snap { c.size.height = interior.height - c.minY }
    return MacroSpec(crop: c, scale: scale, origin: o, feather: feather, hardEdges: hard, interior: interior)
}

@MainActor func macroImage(_ e: Env, _ id: ClipID, _ c: Double, _ tr: Treatment, _ m: MacroSpec) throws -> CGImage {
    try clipImage(e, id, c, tr, scale: m.scale, sub: m.fetchRect)
}

// MARK: S06 · the Mac shows up (R01 2.30→4.70) — unchanged

@MainActor func s06(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = ct(t, 9.6, 2.30)
    let spec = DeviceSpec.M
    let rise = ease(t, 9.6, 0.9, .appleOut)
    let rest = CGPoint(x: 960, y: 930 - spec.outer.height / 2)
    let center = CGPoint(x: rest.x, y: rest.y + 420 * CGFloat(1 - rise))
    let yaw = lerp(12, 4, rise) - max(0, t - 10.5) * 1.0
    let pitch = lerp(-6, -2, rise)
    let push = 1 + 0.32 * CGFloat(ramp(t, 10.5, 12.0))
    let anchor = screenPoint(spec, center: rest, interior: CGPoint(x: 870, y: 762))
    let img = try clipImage(e, .r01, c, .none, scale: 0.5 * 1.32)
    let dots = [TouchDotSpec(at: 11.90, point: CGPoint(x: 840, y: 762))]
    let v = deviceShot(spec: spec, center: center, yaw: yaw, pitch: pitch, push: push, pushAbout: anchor,
                       image: img, dots: dots, t: t, sill: (930, 1200, 960), glow: 0.06)
    return FrameLayers(base: v)
}

// MARK: S07–S09 · "Any Mac window." → the strip swipes → "One tap to switch." (R04, one continuous device)
//
// Note 4: the statement comes right after the Mac is picked and before the bar scrolls. S07 opens on R04 at
// 19.00 (Weather live, the bar at rest) under the rack, the type snaps, eases out, and the rack pulls back
// into focus by 13.60, when S08 plays the swipe (clip 21.02 →, settled by 23.00) sharp. S09 racks out again
// over the disclosed hold on 23.00 for "One tap to switch.", then cuts to the tap. Weather is sharp (note 3);
// only the strip's private thumbnails are soft until the swipe settles (P2).
//
// Fourth cut: note 3 ("do not blur any of the apps in the app shots, the S07–S12 region") is read as covering
// the racks too, so the three racks under type in S07, S09 and S12 no longer blur: they dim and step back
// (brightness → Dim.floor, scale → 0.97, 0.30 s appleOut), and the app stays sharp and legible under the type.
// The §3.5 rack recipe (blur 28) is unchanged elsewhere; S21's defocused Frame Rate row is Sill's own panel.

enum Dim {
    /// The dim's floor. The rack's 0.32 was set for a blurred picture; a sharp one needs less darkening to
    /// keep the type clear, and this keeps the app legible behind it.
    static let floor = ProcessInfo.processInfo.environment["SILL_DIM"].flatMap(Double.init) ?? 0.36
}

/// Dim out (the rack recipe without its blur): brightness 1 → Dim.floor, scale 1 → 0.97 over 0.30 s appleOut.
func dimState(_ t: Double, start: Double) -> Rack {
    let p = ease(t, start, 0.30, .appleOut)
    return Rack(blur: 0, brightness: 1 - (1 - Dim.floor) * p, scale: 1 - 0.03 * p)
}

/// Dim in (reversed): brightness Dim.floor → 1, scale 0.97 → 1 over 0.30 s appleOut.
func dimInState(_ t: Double, start: Double) -> Rack {
    let p = ease(t, start, 0.30, .appleOut)
    return Rack(blur: 0, brightness: Dim.floor + (1 - Dim.floor) * p, scale: 0.97 + 0.03 * p)
}

@MainActor private func weatherDevice(_ t: Double, _ e: Env, clipTime c: Double) throws -> AnyView {
    let spec = DeviceSpec.H
    let yaw = 3 * (1 - ease(t, 12.0, 0.8, .appleOut))
    let dx = -10 * CGFloat(t - 12.0)
    let s = 1 + 0.007 * CGFloat(t - 12.0)          // 1.000 → 1.039 over 12.0–17.6
    let img = try clipImage(e, .r04, c, P.p2(c), scale: 0.64 * 1.04)
    return deviceShot(spec: spec, center: CGPoint(x: 960, y: 540), yaw: yaw, push: s, drift: CGSize(width: dx, height: 0),
                      image: img, t: t, glow: 0.06)
}

@MainActor func s07(_ t: Double, _ e: Env) throws -> FrameLayers {
    let base = try weatherDevice(t, e, clipTime: ct(t, 12.0, 19.00))
    let line = LineSpec(Copy.anyWindow, .T1, baseline: 585, snap: 12.10, holdEnd: 13.20, easeOut: 13.20)
    return FrameLayers(base: base, rack: dimInState(t, start: 13.30), overlay: any(TypeLayer(lines: [line], t: t)))
}

@MainActor func s08(_ t: Double, _ e: Env) throws -> FrameLayers {
    FrameLayers(base: try weatherDevice(t, e, clipTime: ct(t, 13.6, 20.60)))
}

@MainActor func s09(_ t: Double, _ e: Env) throws -> FrameLayers {
    let base = try weatherDevice(t, e, clipTime: 23.00)       // the disclosed hold (§7.1)
    let line = LineSpec(Copy.oneTap, .T1, baseline: 585, snap: 16.10, holdEnd: 17.6)
    return FrameLayers(base: base, rack: dimState(t, start: 16.0), overlay: any(TypeLayer(lines: [line], t: t)), vignette: false)
}

// MARK: S10 · the tap (hero macro, R05 0.00→2.00)

@MainActor func s10(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = ct(t, Events.heroStart, 0.00)
    let m = macro(crop: CGRect(x: 0, y: 0, width: 1400, height: 620), scale: 1.0, origin: CGPoint(x: 260, y: 230))
    // VS Code's private file stays soft until the pick; Blender arrives sharp (note 3).
    let img = try macroImage(e, .r05, c, P.p4(c), m)
    let dots = [TouchDotSpec(at: Events.heroTap, point: CGPoint(x: 280, y: 85))]
    let v = macroShot(m, image: img, dots: dots, t: t, scale: 1 + 0.03 * CGFloat(ramp(t, 17.6, 19.6)),
                      drift: CGSize(width: 18 * CGFloat(t - 17.6), height: 0))
    return FrameLayers(base: v, vignette: false)
}

// MARK: S11 / S12 · Blender edge to edge; "Or the whole desktop."

@MainActor private func blenderDevice(_ t: Double, _ e: Env, clipTime c: Double) throws -> AnyView {
    let spec = DeviceSpec.H
    let center = CGPoint(x: 960, y: 540)
    let push = 1 + 0.025 * CGFloat(t - 19.6)                 // 1.00 → 1.09 over S11 and S12 (≤ 0.70× of the recording)
    let yaw = -1.5 * (t - 19.6)                               // 0° → −3° over S11, continuing under S12
    let anchor = screenPoint(spec, center: center, interior: CGPoint(x: 420, y: 760))
    let img = try clipImage(e, .r05, c, P.p4(c), scale: 0.64 * 1.09)
    return deviceShot(spec: spec, center: center, yaw: yaw, push: push, pushAbout: anchor, image: img, t: t, glow: 0.06)
}

@MainActor func s11(_ t: Double, _ e: Env) throws -> FrameLayers {
    FrameLayers(base: try blenderDevice(t, e, clipTime: ct(t, 19.6, 2.00)))
}

/// Fourth cut: S12 is 1.2 s (21.6–22.8); it lends S13 one beat so N1 opens on Weather before the tap. The
/// statement still snaps on the pulse at 21.6 and reads for 1.1 s (as v1's "One tap to switch." did).
@MainActor func s12(_ t: Double, _ e: Env) throws -> FrameLayers {
    let base = try blenderDevice(t, e, clipTime: ct(t, 21.6, 4.00))
    let line = LineSpec(Copy.wholeDesktop, .T1, baseline: 585, snap: 21.70, holdEnd: N1Switch.start)
    return FrameLayers(base: base, rack: dimState(t, start: 21.6), overlay: any(TypeLayer(lines: [line], t: t)), vignette: false)
}

// MARK: S13 · window → Desktop (clip 11, N1: real footage, take 1)
//
// Clip 11 as recorded (real-captures/README-3.md "Round 4" and the take's notes): Weather streams from the virtual
// display with the halo on its thumbnail; one tap on Desktop (finger down ≈ 1.66 s, the first pressed frame
// 1.668); the halo moves and Desktop lights at 2.233; one black sample at 2.417 (3 ms) and Weather's last
// picture re-fitted to the Desktop's shape (2.420–2.432); the first Desktop frame at 2.445, which holds to the
// end. The Desktop is the Mac's main display: the menu bar and Blender, zoomed to fill it, splash open.
// In-point 1.245 puts the tap 0.415 s into the shot (23.215) and the first Desktop frame on bar 15 (24.000,
// frame 1440); the black sample falls between reel frames, and the Desktop holds 2.4 s (the approval's minimum).
// Take 1, not take 2: take 2's tap comes 1.12 s before its Desktop, which leaves < 2.4 s of Desktop in 3.6 s.

enum N1Switch {
    static let start = 22.8, end = 26.4
    static let inPoint = 1.245
    static let tap = 1.660                    // finger down (±0.03 s); the first pressed frame is 1.668
    static let halo = 2.233                   // the halo leaves Weather's thumbnail; Desktop lights
    static let black = 2.417                  // the one black sample (3 ms)
    static let desktop = 2.445                // the first Desktop frame
    /// The Desktop button, interior px (simulator (882, 375) pt = layout (866, 42)).
    static let button = CGPoint(x: 1732, y: 84)
    static var tapReel: Double { start + (tap - inPoint) }            // 23.215 (C8)
    static var haloReel: Double { start + (halo - inPoint) }          // 23.788
    static var desktopReel: Double { start + (desktop - inPoint) }    // 24.000, frame 1440 (C9)
}

@MainActor func s13(_ t: Double, _ e: Env) throws -> FrameLayers {
    let spec = DeviceSpec.H60
    let c = ct(t, N1Switch.start, N1Switch.inPoint)
    let k = ramp(t, N1Switch.start, N1Switch.end)
    // Software-encoded (the Desktop at 1512×982 px), so H60, as S16: 66 % of the width, 69 % at the end of a 4 %
    // push about a point 600 px right of centre (the device eases 24 px left; a render transform, so no stepping).
    // Yaw −2.5° → 0°, continuing S12's direction, frontal by the Desktop's arrival. Stream pixels ≤ 0.63×.
    let pts = try e.clips.pts(.n1, at: c)
    let img = try clipImage(e, .n1, c, P.n1(samplePTS: pts), scale: 0.60 * 1.04)
    let dots = [TouchDotSpec(at: N1Switch.tapReel, point: N1Switch.button)]
    let v = deviceShot(spec: spec, center: CGPoint(x: 960, y: 540), yaw: -2.5 * (1 - ease(t, N1Switch.start, 1.2, .inOut)),
                       push: 1 + 0.04 * CGFloat(k), pushAbout: CGPoint(x: 1560, y: 540),
                       image: img, dots: dots, t: t, glow: 0.06)
    return FrameLayers(base: v)
}

// MARK: S14 · "App drawer from afar." (R02 3.36→5.76)

@MainActor func s14(_ t: Double, _ e: Env) throws -> FrameLayers {
    let t0 = Events.drawerStart
    let c = ct(t, t0, Events.drawerIn)
    let m = macro(crop: CGRect(x: 0, y: 0, width: 800, height: 1380), scale: 0.78, origin: CGPoint(x: 120, y: 2), hard: [.trailing, .bottom])
    let img = try macroImage(e, .r02, c, P.p5(c), m)
    let dots = [TouchDotSpec(at: Events.drawerTap, point: CGPoint(x: 110, y: 85))]
    let lines = [LineSpec(Copy.appDrawer, .T1c, x: 860, baseline: 520, align: .leading, snap: t0 + 0.10, holdEnd: t0 + 2.4),
                 LineSpec(Copy.fromAfar, .T1c, x: 860, baseline: 624, align: .leading, snap: t0 + 0.50, holdEnd: t0 + 2.4)]
    let v = macroShot(m, image: img, dots: dots, t: t, scale: 1 + 0.02 * CGFloat(ramp(t, t0, t0 + 2.4)),
                      drift: CGSize(width: 0, height: -10 * CGFloat(t - t0)), lines: lines)
    return FrameLayers(base: v, vignette: false)
}

// MARK: S15 · "Text at the size you choose." (HT-B)

@MainActor func s15(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = ct(t, 28.8, Events.inB)
    let m = macro(crop: CGRect(x: 900, y: 0, width: 1100, height: 300), scale: 1.2, center: CGPoint(x: 960, y: 620))
    let img = try macroImage(e, .htB, c, .none, m)
    // Baseline 320 (not 360): at 360 the descenders sit ~20 px from the top bezel this crop draws.
    let line = LineSpec(Copy.textSize, .T1s, baseline: 320, snap: 28.90, holdEnd: 31.2)
    let v = macroShot(m, image: img, t: t, lines: [line])
    return FrameLayers(base: v, vignette: false)
}

// MARK: S16 · the Aa ruler resizes a Mac window (clip 12, N2: real footage)
//
// Clip 12 (real-captures/README-3.md) holds two gestures on Weather.
// - First (the third cut's): Weather at 1× (the Mac window 1048×640 pt); the ruler unfolds under the finger at
//   2.455, the value changes 1× → 0.75× on the sample at 2.718, it folds on release (3.54–3.80); the Mac window
//   grows to 1312×811 pt and the stream re-fits at 4.282 (black sample 4.262, then two old-layout samples).
// - Second (the fourth cut's): Weather at 0.75× (1312×811 pt, Aa reads 0.75×); the ruler unfolds at 10.303 with
//   the thumb on 0.75, the value changes 0.75× → 1× on the sample at 10.592 (the ruler slides under the thumb
//   until ≈ 10.64), it folds on release (11.405–11.553); the Mac window shrinks to 1048×640 pt and the stream
//   re-fits at 12.057 (black sample 12.047, one old-layout sample 12.052): bigger text, less of the window.
//   Weather then cross-fades its cards into the new layout (12.07–12.19, its own animation).
// The fourth cut plays the second: S15's harness ruler ends on 0.75×, so the first gesture (1× → 0.75× again)
// read as a rewind; the second continues from 0.75× and ends on the 1× layout of S07–S09 and S23.
// Either way the black sample and the old-layout samples fall between reel frames (the frame before 33.200
// shows the old layout). No touch dot: the finger went down about 0.8 s before the ruler opened (the injected
// press did not register until it slid), and a dot over the thumb would hide the ruler's own labels.

enum AaResize {
    static let start = 31.2, end = 34.4
    /// `SILL_S16_FORWARD=1` plays the third cut's first gesture (1× → 0.75×) instead.
    static let reverse = ProcessInfo.processInfo.environment["SILL_S16_FORWARD"] == nil
    static var inPoint: Double { reverse ? 10.060 : 2.290 }
    // clip 12 sample PTS
    static var unfold: Double { reverse ? 10.303 : 2.455 }
    static var detent: Double { reverse ? 10.592 : 2.718 }
    static var refit: Double { reverse ? 12.057 : 4.282 }
    static var detentReel: Double { start + (detent - inPoint) }             // 31.732 (C11); forward 31.628
    static var refitReel: Double { start + (refit - inPoint) }               // 33.197, first shown on frame 1992 (C9)
}

@MainActor func s16(_ t: Double, _ e: Env) throws -> FrameLayers {
    let spec = DeviceSpec.H60
    let c = ct(t, AaResize.start, AaResize.inPoint)
    let k = ramp(t, AaResize.start, AaResize.end)
    // Software-encoded, so smaller than H (66–68 % of the width) and always moving: yaw 2.5° → 0° (frontal by
    // 33.0, before the re-fit at 33.2) and a 3 % push about a point 600 px right of centre, so the device also
    // eases left by 18 px. (No `drift:`: deviceShot's drift moves the device by layout position, which lands
    // on whole pixels, 1 px every 7.5 frames at 8 px/s; the push is a render transform and stays smooth.)
    // Stream pixels stay at 0.62× of the recording.
    let img = try clipImage(e, .n2, c, .none, scale: 0.60 * 1.03)
    let v = deviceShot(spec: spec, center: CGPoint(x: 960, y: 540), yaw: 2.5 * (1 - ease(t, AaResize.start, 1.8, .inOut)),
                       push: 1 + 0.03 * CGFloat(k), pushAbout: CGPoint(x: 1560, y: 540),
                       image: img, t: t, glow: 0.06)
    return FrameLayers(base: v)
}

// MARK: S17 · "Click. Scroll. Type. with haptic trackpad" (HT-C, portrait)
//
// Note 7: a fourth line in T4 hangs off "Type.", and its word "haptic" buzzes: a 3 px, 18 Hz jitter for 0.6 s
// (36.05–36.65, on the beat after the line settles), then still. The footnote qualifies it: the trackpad's
// haptics fire on iPhone only (CLAUDE.md L672–673: iPads have no Taptic Engine).

enum Haptic {
    static let lineSnap = 35.65
    static let jitterStart = 36.05, jitterDuration = 0.6
}

@MainActor func s17(_ t: Double, _ e: Env) throws -> FrameLayers {
    let spec = DeviceSpec.P
    let rise = 14 * CGFloat(t - 34.4)
    let center = CGPoint(x: 1290, y: 1010 - spec.outer.height / 2)
    let yaw = lerp(-12, -9, ramp(t, 34.4, 37.6))
    // The mock's black stream area (interior y < 1000 of 2000) reads as dark glass.
    let glass = LinearGradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
        .frame(width: spec.interior.width, height: spec.interior.height * 0.5)
    var haptic = LineSpec(words: Copy.haptic, .T4, x: 128, baseline: 776, align: .leading, snap: Haptic.lineSnap, holdEnd: 37.6)
    haptic.jitter = (word: 1, start: Haptic.jitterStart, duration: Haptic.jitterDuration, amplitude: 3)
    let lines = [LineSpec(Copy.click, .T1, x: 128, baseline: 400, align: .leading, snap: 34.45, holdEnd: 37.6),
                 LineSpec(Copy.scroll, .T1, x: 128, baseline: 533, align: .leading, snap: 34.85, holdEnd: 37.6),
                 LineSpec(Copy.type, .T1, x: 128, baseline: 666, align: .leading, snap: 35.25, holdEnd: 37.6),
                 haptic,
                 LineSpec(Copy.hapticFootnote, .T3, x: 128, baseline: 836, align: .leading, snap: Haptic.lineSnap, holdEnd: 37.6, cascade: false)]
    let v = deviceShot(spec: spec, center: center, yaw: yaw, drift: CGSize(width: 0, height: -rise), image: e.portrait, t: t,
                       sill: (1010, 1200, 1290), glow: 0.06, glowCenter: CGPoint(x: 1290, y: 520),
                       screenOverlay: any(glass), lines: lines)
    return FrameLayers(base: v)
}

// MARK: S18 · the trackpad moves the pointer (clip 13, N3: real footage, portrait)
//
// Clip 13 as recorded: one continuous one-finger stroke on the trackpad, no clicks (the host log counts only
// pointer moves). The shot plays its left-to-right sweep: the client-drawn arrow rests at the window's left
// (≈ 21 %, 2.928–3.112), crosses to ≈ 80 % (5.212) and rests. The finger dot follows the injector's logged path
// (v3tools/pointer-path.txt, sim points) on the trackpad, whose own picture shows no touch feedback. Its time
// base is measured on the footage: the path's t = 0 is clip 1.700 (the arrow's first sample is 1.713; the
// velocity of the arrow matches the path's best 1.7175 s after it, r = 0.991; 1.700 keeps the finger a frame
// ahead of the arrow it drives). The finger is down from clip 1.70 to 9.20, so for the whole shot.
//
// v3.1: the recorded arrow stuttered (the capture's holes and jitter), so it is painted out and the same arrow is
// drawn where the stroke put it at each frame's own time (PointerArrow, V31.swift), and the picture is scaled to an
// exact pixel size. The finger dot is v3's.

enum Pointer {
    static let start = 37.6, end = 40.0
    static let inPoint = 2.95
    static let fingerDown = 1.700                  // clip time of the path's t = 0
    /// The interior's origin in simulator points (portrait harness), and 2 interior px per point.
    static let origin = CGPoint(x: 161, y: 188)
    static let path: [(t: Double, x: Double, y: Double)] = {
        let url = reelDir.appendingPathComponent("v3tools/pointer-path.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ").compactMap { Double($0) }
            return f.count == 3 ? (f[0], f[1], f[2]) : nil
        }
    }()
    /// Reel time → clip time → path time.
    static func clip(_ t: Double) -> Double { ct(t, start, inPoint) }
    static var downReel: Double { start + (fingerDown - inPoint) }
    static var upReel: Double { downReel + (path.last?.t ?? 0) }
    /// The finger in portrait interior px at reel time t (linear between logged samples).
    static func finger(_ t: Double) -> CGPoint {
        guard let first = path.first, let last = path.last else { return CGPoint(x: 710, y: 1636) }
        let u = clip(t) - fingerDown
        var p = (x: first.x, y: first.y)
        if u >= last.t { p = (last.x, last.y) }
        else if u > first.t {
            var lo = 0, hi = path.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if path[m].t <= u { lo = m } else { hi = m } }
            let a = path[lo], b = path[hi]
            let w = (u - a.t) / max(1e-9, b.t - a.t)
            p = (a.x + (b.x - a.x) * w, a.y + (b.y - a.y) * w)
        }
        return CGPoint(x: (p.x - origin.x) * 2, y: (p.y - origin.y) * 2)
    }
}

extension Pointer {
    /// Fourth cut: the push-in during the crossing (finding: the arrow, the shot's subject, was ≈ 15 px tall).
    /// 1 → pushEnd over pushFrom…pushTo (inOut) about `pushAnchor`, on top of the 0.82 → 0.836 base. At the end the
    /// frame holds the Weather window's top edge (interior y 76, screen ≈ 30) down to the finger dot's foot
    /// (interior y 1700, screen ≈ 1050); stream pixels reach 0.63× of the recording (cap 0.70), the arrow ≈ 20 px.
    static let pushFrom = 37.6, pushTo = 39.9
    static let pushEnd: CGFloat = 1.34
    static let pushAnchor = CGPoint(x: 960, y: 333)
    static func push(_ t: Double) -> CGFloat { 1 + (pushEnd - 1) * CGFloat(CubicBezier.inOut(ramp(t, pushFrom, pushTo))) }
}

@MainActor func s18(_ t: Double, _ e: Env) throws -> FrameLayers {
    let spec = DeviceSpec.P
    let k = ramp(t, Pointer.start, Pointer.end)
    let centre = CGPoint(x: 960, y: 540)
    // Device P whole at 0.82 → 0.836, standing on the sill line (y 1130 lands on 1024 at 0.82), so the stream
    // with the arrow and the trackpad with the finger are both in frame; then the push-in above.
    let s: CGFloat = 0.82 * (1 + 0.02 * CGFloat(k))
    let push = Pointer.push(t)
    // The clip is fetched at the on-screen size of this frame (Lanczos), so the push never upsamples it.
    // v3.1: with the recorded arrow painted out and the arrow drawn at this frame's own place on the stroke, at an
    // exact pixel size (PointerArrow, V31.swift). v3 read `e.clips.image(.n3, …, crop: portraitRect)` here.
    let c = Pointer.clip(t)
    let img = try e.clips.pointerImage(at: c, arrowLeft: PointerArrow.left(clip: c), scale: spec.interior.width / 1420 * s * push)
    guard !Pointer.path.isEmpty else { throw NSError(domain: "Reel", code: 7, userInfo: [NSLocalizedDescriptionKey: "pointer path missing"]) }
    let dot = TouchDotSpec(at: Pointer.downReel, point: .zero, interiorWidth: 1420,
                           drag: (Pointer.downReel, Pointer.upReel, Pointer.finger))
    let v = deviceShot(spec: spec, center: centre, yaw: lerp(-4, -2, k), push: s, pushAbout: centre,
                       postPush: (push, Pointer.pushAnchor),
                       image: img, dots: [dot], t: t, sill: (1130, 1400, 960), glow: 0.06)
    return FrameLayers(base: v)
}

// MARK: S19 · "Close. Minimize. Full Screen." (HT-D), 0.8 s longer than v1 (note 9)

@MainActor func s19(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = ct(t, 40.0, Events.inD)
    let m = macro(crop: CGRect(x: 60, y: 0, width: 800, height: 420), scale: 1.3, center: CGPoint(x: 600, y: 540))
    let img = try macroImage(e, .htD, c, .none, m)
    let lines = [LineSpec(Copy.close, .T1c, x: 1200, baseline: 440, align: .leading, snap: 40.05, holdEnd: 42.4),
                 LineSpec(Copy.minimize, .T1c, x: 1200, baseline: 544, align: .leading, snap: 40.45, holdEnd: 42.4),
                 LineSpec(Copy.fullScreen, .T1c, x: 1200, baseline: 648, align: .leading, snap: 40.85, holdEnd: 42.4)]
    let v = macroShot(m, image: img, t: t, lines: lines)
    return FrameLayers(base: v, vignette: false)
}

// MARK: S20 · "Latency you don’t notice." (drawn), 0.8 s longer than v1 (note 10)

enum Latency {
    static let start = 42.4
    static let streak = 42.45, travel = 0.28
    static let sub = 43.30
    static let easeOut = 45.38            // done on S20's last frame (45.583); S21's headline snaps at 45.65
}

struct Streak: View {
    let t: Double
    /// y 430: 31 px above the headline's cap tops (baseline 540, cap height 79), so neither the core nor
    /// the glow nor the flare touches a letter while the trail decays (at y 520 it read as a strike-through).
    static let start = Latency.streak, travel = Latency.travel, y: CGFloat = 430
    static func headX(_ t: Double) -> CGFloat { lerp(-200, 2120, CubicBezier.inOut((t - start) / travel)) }

    var body: some View {
        Canvas { ctx, _ in
            let t = self.t
            guard t >= Streak.start else { return }
            let head = Streak.headX(t)
            let y = Streak.y
            // Trail: x was passed at tp(x); it decays over 1.2 s.
            func passTime(_ x: CGFloat) -> Double {
                let s = Double((x + 200) / 2320)
                var lo = 0.0, hi = 1.0
                for _ in 0..<30 { let m = (lo + hi) / 2; if CubicBezier.inOut(m) < s { lo = m } else { hi = m } }
                return Streak.start + Streak.travel * (lo + hi) / 2
            }
            let n = 120
            let x0: CGFloat = -200
            for i in 0..<n {
                let xa = x0 + (head - x0) * CGFloat(i) / CGFloat(n), xb = x0 + (head - x0) * CGFloat(i + 1) / CGFloat(n)
                guard xb > -10 && xa < 1930 else { continue }
                let age = t - passTime((xa + xb) / 2)
                let a = max(0, 1 - age / 1.2)
                let alpha = a * a
                guard alpha > 0.003 else { continue }
                var seg = Path(); seg.move(to: CGPoint(x: xa, y: y)); seg.addLine(to: CGPoint(x: xb, y: y))
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: 4))
                    g.stroke(seg, with: .color(Color(hex: Palette.accent, alpha: 0.5 * alpha)), lineWidth: 10)
                }
                ctx.stroke(seg, with: .color(.white.opacity(0.9 * alpha)), lineWidth: 2)
            }
            // Head and its 600 px horizontal flare at 12 %, while the head is on screen.
            if head > -200 && head < 2120 && t <= Streak.start + Streak.travel + 0.001 {
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: 10))
                    g.fill(Path(ellipseIn: CGRect(x: head - 300, y: y - 7, width: 600, height: 14)),
                           with: .color(Color(hex: Palette.accent, alpha: 0.12)))
                }
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: 6))
                    g.fill(Path(ellipseIn: CGRect(x: head - 14, y: y - 6, width: 28, height: 12)), with: .color(.white.opacity(0.8)))
                }
            }
        }
        .canvas()
    }
}

@MainActor func s20Type(_ t: Double) -> AnyView {
    let head = Streak.headX(t)
    // "Latency you don’t notice." is revealed left to right by a wipe keyed to the streak's x.
    let title = Text(Copy.latency).font(TypeStyle.T1s.font).tracking(TypeStyle.T1s.tracking)
        .foregroundStyle(Color(hex: Palette.text1)).fixedSize()
        .placed(x: 960, baseline: 540, align: .center)
    let wipe = LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: max(0, min(1, (head - 30) / 1920))),
                                      .init(color: .white.opacity(0), location: max(0.0001, min(1, (head + 10) / 1920)))],
                              startPoint: .leading, endPoint: .trailing).canvas()
    var sub = LineSpec(Copy.latencySub, .T2, baseline: 630, snap: Latency.sub, holdEnd: 45.6)
    sub.holdScale = false                 // the whole card carries the hold below
    // §3.5 ease out, 0.20 s appleIn, done on S20's last frame: S21's headline snaps onto an empty frame.
    let out = ease(t, Latency.easeOut, 0.20, .appleIn)
    // v2: the card now holds 0.8 s longer (note 10), so the title and subline share the §3.5 hold drift
    // (+1.2 % from the moment the subline has settled) instead of standing still for 1.5 s.
    let hold = 1 + 0.012 * CGFloat(ramp(t, Latency.sub + 0.30, Latency.easeOut + 0.20))
    let v = ZStack {
        title.mask(wipe)
        TypeLayer(lines: [sub], t: t)
    }
    .canvas()
    .scaleEffect(hold, anchor: UnitPoint(x: 0.5, y: 0.5))
    .blur(radius: 8 * CGFloat(out))
    .offset(y: -12 * CGFloat(out))
    .opacity(1 - out)
    return any(v)
}

@MainActor func s20(_ t: Double, _ e: Env) throws -> FrameLayers {
    let v = ZStack {
        Backdrop(glow: 0.05)
        Streak(t: t)          // stack G: drawn elements under the type
        s20Type(t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S21 · "Up to 60 → 120 fps." over the defocused Frame Rate row (R08 1.50→4.70)
//
// Note 11: the headline snaps reading "Up to 60 fps." and holds it for 0.80 s before the number rolls (v1
// rolled 0.05 s after the snap), and the shot runs 1.6 s longer than v1, so the tail after the subline grows
// from 1.10 s to 1.95 s.

enum Rate {
    static let start = 45.6
    static let snap = 45.65, roll = 46.45, rollDur = 0.32, sub = 46.85, end = 48.8
}

struct RollingFPS: View {
    let t: Double
    var body: some View {
        let style = TypeStyle.T0r
        let p = ease(t, Rate.roll, Rate.rollDur, .appleOut)
        let snap = snapState(t, start: Rate.snap)
        let w60 = measure("60", style), w120 = measure("120", style)
        let numberWidth = lerp(w60, w120, p)
        let text = { (s: String) in Text(s).font(style.font).tracking(style.tracking + snap.trackingExtra * style.size)
            .foregroundStyle(Color(hex: style.color)).fixedSize() }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            text(Copy.upTo)
            ZStack(alignment: .bottom) {
                text("60").offset(y: -60 * CGFloat(p)).opacity(1 - p)
                text("120").offset(y: 60 * CGFloat(1 - p)).opacity(p)
            }
            .frame(width: numberWidth)
            text(Copy.fps)
        }
        .fixedSize()
        .scaleEffect(snap.scale * (1 + 0.012 * CGFloat(ramp(t, Rate.snap + 0.30, Rate.end))))
        .blur(radius: snap.blur)
        .offset(y: snap.dy)
        .opacity(snap.opacity)
        .placed(x: 960, baseline: 575, align: .center)
    }
}

func measure(_ s: String, _ style: TypeStyle) -> CGFloat {
    var font = NSFont.systemFont(ofSize: style.size, weight: nsWeight(style.weight))
    if style.monoDigits { font = NSFont.monospacedDigitSystemFont(ofSize: style.size, weight: nsWeight(style.weight)) }
    let a = NSAttributedString(string: s, attributes: [.font: font, .kern: style.tracking])
    return ceil(a.size().width)
}

func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
    switch w {
    case .bold: return .bold
    case .semibold: return .semibold
    case .medium: return .medium
    default: return .regular
    }
}

@MainActor func s21(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = ct(t, Rate.start, 1.50)
    let crop = CGRect(x: 1240, y: 680, width: 711, height: 120)
    let img = try clipImage(e, .r08, c, P.p7, scale: 2.2, sub: crop)
    let bg = ZStack {
        Backdrop(glow: 0.05)
        Image(decorative: img, scale: 1).resizable().interpolation(.high)
            .frame(width: crop.width * 2.2, height: crop.height * 2.2)
            .colorMultiply(Color(white: 0.3))
            .position(x: 1180, y: 540)
    }.canvas()
    let sub = LineSpec(Copy.proMotion, .T2, baseline: 660, snap: Rate.sub, holdEnd: Rate.end)
    // The background fades up from S20's black over the first 0.2 s; S20's type has already eased out.
    let x = ramp(t, Rate.start, Rate.start + 0.2)
    let overlay = ZStack {
        RollingFPS(t: t)
        TypeLayer(lines: [sub], t: t)
    }.canvas()
    return FrameLayers(base: any(bg), rack: x < 1 ? Rack(blur: 0, brightness: x, scale: 1) : nil,
                       overlay: any(overlay), baseBlur: 18)
}

// MARK: S22 · "Hidden on your Mac." (drawn)

/// 1.6 s (v1: 2.0): the headline, the covering window 0.3 s later, the thud as it lands, 0.5 s covered, the wipe.
enum Hidden {
    static let start = 48.8
    static let snap = 48.90, slide = 49.20, thud = 49.65
    static let wipe = 50.15, end = 50.4
}

struct CoveredMac: View {
    let t: Double
    var reveal: AnyView? = nil     // S23's first frame, revealed by the wipe

    static let k: CGFloat = 1.6
    /// Body centre (icon (512, 404)) at (960, 600).
    static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 960 + (x - 512) * k, y: 600 + (y - 404) * k) }
    static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        let o = p(x, y); return CGRect(x: o.x, y: o.y, width: w * k, height: h * k)
    }
    static var windowRect: CGRect {    // the light window, 486×288, centred in the screen
        let screen = r(204, 204, 616, 352)
        return CGRect(x: screen.midX - 243, y: screen.midY - 144, width: 486, height: 288)
    }

    var body: some View {
        let lineColor = Color(hex: Palette.text1, alpha: 0.55)
        let win = CoveredMac.windowRect
        let slide = ease(t, Hidden.slide, 0.45, .appleOut)
        let darkX = lerp(1920 + 40, win.minX, slide)
        let wipe = CubicBezier.inOut(ramp(t, Hidden.wipe, Hidden.end))
        let darkRect = CGRect(x: lerp(darkX, -80, wipe), y: lerp(win.minY, -80, wipe),
                              width: lerp(win.width, 2080, wipe), height: lerp(win.height, 1240, wipe))
        let radius = lerp(18, 0, wipe)
        return Canvas { ctx, _ in
            // The iMac as a line drawing: body, neck, foot (3 px, text.1 at 55 %), its screen dark.
            let body = Path(roundedRect: CoveredMac.r(176, 176, 672, 456), cornerRadius: 60 * CoveredMac.k, style: .circular)
            let screen = Path(roundedRect: CoveredMac.r(204, 204, 616, 352), cornerRadius: 36 * CoveredMac.k, style: .circular)
            let neck = Path(CoveredMac.r(480, 632, 64, 40))
            let foot = Path(roundedRect: CoveredMac.r(372, 672, 280, 40), cornerRadius: 20 * CoveredMac.k, style: .circular)
            ctx.fill(screen, with: .color(Color(hex: 0x07080A)))
            ctx.stroke(body, with: .color(lineColor), lineWidth: 3)
            ctx.stroke(screen, with: .color(Color(hex: Palette.text1, alpha: 0.18)), lineWidth: 1.5)
            ctx.stroke(neck, with: .color(lineColor), lineWidth: 3)
            ctx.stroke(foot, with: .color(lineColor), lineWidth: 3)
            // The light window (the icon's, at 1.6 px per unit).
            drawWindow(&ctx, win, body: Color(hex: Palette.winLightBody), strip: Color(hex: Palette.accent),
                       bars: Color(hex: Palette.winLightBars), dots: .white)
            // The covering window slides in from the right.
            if slide > 0 {
                if wipe <= 0 {
                    drawWindow(&ctx, CGRect(x: darkX, y: win.minY, width: win.width, height: win.height),
                               body: Color(hex: Palette.winDarkBody), strip: Color(hex: Palette.winDarkStrip),
                               bars: Color.white.opacity(0.10), dots: Color.white.opacity(0.9))
                } else {
                    ctx.fill(Path(roundedRect: darkRect, cornerRadius: radius, style: .continuous), with: .color(Color(hex: Palette.winDarkBody)))
                }
            }
        }
        .overlay {
            if let reveal, wipe > 0 {
                reveal
                    .opacity(CubicBezier.inOut(ramp(t, Hidden.wipe + 0.07, Hidden.end)))
                    .mask(Path(roundedRect: darkRect, cornerRadius: radius, style: .continuous).fill(Color.white).canvas())
            }
        }
        .canvas()
    }

    private func drawWindow(_ ctx: inout GraphicsContext, _ r: CGRect, body: Color, strip: Color, bars: Color, dots: Color) {
        let k = CoveredMac.k
        let shape = Path(roundedRect: r, cornerRadius: 20 * k, style: .circular)
        ctx.fill(shape, with: .color(body))
        var c = ctx
        c.clip(to: shape)
        c.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 40 * k)), with: .color(strip))
        for (i, a) in [0.7, 0.5, 0.35].enumerated() {
            c.fill(Path(ellipseIn: CGRect(x: r.minX + (19 + 22 * CGFloat(i)) * k, y: r.minY + 13 * k, width: 14 * k, height: 14 * k)),
                   with: .color(dots.opacity(a)))
        }
        for (i, (w, a)) in [(150.0, 0.9), (210.0, 0.55), (110.0, 0.55)].enumerated() {
            c.fill(Path(roundedRect: CGRect(x: r.minX + 26 * k, y: r.minY + (66 + 30 * CGFloat(i)) * k, width: CGFloat(w) * k, height: 14 * k),
                        cornerRadius: 7 * k, style: .circular), with: .color(bars.opacity(a)))
        }
    }
}

@MainActor func s22(_ t: Double, _ e: Env) throws -> FrameLayers {
    let line = LineSpec(Copy.hidden, .T1s, baseline: 150, snap: Hidden.snap, holdEnd: Hidden.end)
    var reveal: AnyView? = nil
    if t >= Hidden.wipe { reveal = try s23(Hidden.end, e).base }
    let v = ZStack {
        Backdrop(glow: 0.05)
        CoveredMac(t: t, reveal: reveal)
        // The title rides above the covering window and leaves as the wipe fills the frame.
        TypeLayer(lines: [line], t: t).opacity(1 - CubicBezier.inOut(ramp(t, Hidden.wipe, Hidden.wipe + 0.17)))
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S23 · "Still live on your iPad." (R04 5.00→8.20, from the virtual display)
//
// Note 12: the footnote is the first cut's sentence with "invisible virtual display.", on two lines so it
// clears the device, and the shot runs 0.8 s longer than the second cut (3.2 s). Weather is sharp (note 3);
// only the strip's private thumbnails stay soft (P3).

@MainActor func s23(_ t: Double, _ e: Env) throws -> FrameLayers {
    let t0 = 50.4, t1 = 53.6
    let c = ct(t, t0, 5.00)
    let spec = DeviceSpec.M45
    let center = CGPoint(x: 1380, y: 930 - spec.outer.height / 2)
    let img = try clipImage(e, .r04, c, P.p3, scale: 0.45)
    let lines = [LineSpec(Copy.stillLive, .T1c, x: 128, baseline: 470, align: .leading, snap: t0 + 0.10, holdEnd: t1),
                 LineSpec(Copy.onYourIPad, .T1c, x: 128, baseline: 574, align: .leading, snap: t0 + 0.50, holdEnd: t1),
                 LineSpec(Copy.vdFootnote[0], .T3, x: 128, baseline: 662, align: .leading, snap: t0 + 0.10, holdEnd: t1, cascade: false),
                 LineSpec(Copy.vdFootnote[1], .T3, x: 128, baseline: 698, align: .leading, snap: t0 + 0.10, holdEnd: t1, cascade: false)]
    let v = deviceShot(spec: spec, center: center, yaw: lerp(-12, -10, ramp(t, t0, t1)),
                       drift: CGSize(width: -12 * CGFloat(t - t0), height: 0), image: img, t: t,
                       sill: (930, 1200, 1300), glow: 0.06, lines: lines)
    return FrameLayers(base: v)
}

// MARK: S24 · "Wi‑Fi. Wired. Direct." (HT-E), 0.8 s longer than v1 (note 14)

/// v2's S24 (HT-E, b5594d9's client). Unused in v3: `s24` in V3.swift re-shoots the beat on 8b0d418's client.
@MainActor func s24v2(_ t: Double, _ e: Env) throws -> FrameLayers {
    let t0 = 53.6, t1 = 57.6
    let c = ct(t, t0, Events.inE)
    // The app inserts rows without animation and re-centres the column 56 interior px up per row. The crop
    // tracks it on the same sample, so the heading holds still and each row lands in its final place (the
    // last state is the crop as drawn: y 430–960).
    let pts = try e.clips.pts(.htE, at: c)
    let landed = Events.htE_rows.filter { $0 <= pts + 1e-3 }.count
    let cropY = 430 + Events.htE_jump * CGFloat(Events.htE_rows.count - landed)
    let m = MacroSpec(crop: CGRect(x: 600, y: cropY, width: 800, height: 530), scale: 1.0, center: CGPoint(x: 1480, y: 540),
                      feather: 0, hardEdges: [.leading, .trailing, .top, .bottom])
    let img = try macroImage(e, .htE, c, .none, m)
    // The words snap with their rows (54.05, 54.45, 54.85); the footnote snaps with the first word and stays
    // up 3.55 s.
    let lines = [LineSpec(Copy.wifi, .T1c, x: 128, baseline: 380, align: .leading, snap: t0 + 0.45, holdEnd: t1),
                 LineSpec(Copy.wired, .T1c, x: 128, baseline: 484, align: .leading, snap: t0 + 0.85, holdEnd: t1),
                 LineSpec(Copy.direct, .T1c, x: 128, baseline: 588, align: .leading, snap: t0 + 1.25, holdEnd: t1),
                 LineSpec(Copy.directSub, .T2, x: 128, baseline: 680, align: .leading, snap: t0 + 1.70, holdEnd: t1),
                 LineSpec(Copy.directFootnote, .T3, x: 128, baseline: 744, align: .leading, snap: t0 + 0.45, holdEnd: t1, cascade: false)]
    let v = macroShot(m, image: img, t: t, drift: CGSize(width: -6 * CGFloat(t - t0), height: 0), lines: lines)
    return FrameLayers(base: v, vignette: false)
}
