// Shots060Open.swift — the 0.6.0 reel's open (S01–S03, 0.0–6.4) and close (S21–S23, 72.0–80.0): the lit icon on
// the sill line, the lockup with the version, "What’s new.", and the end card. v3's close, reused (ShotsI.swift):
// the glint round the icon's iPad, the icon's rise, the wordmark landing on the sill line, the +1.2 % card hold.
import SwiftUI

extension TypeStyle {
    /// T4 in text.2: the version under the wordmark.
    static let T4g = TypeStyle(size: 56, weight: .medium, tracking: -0.8, color: Palette.text2)
}

enum Open060 {
    /// S01: the icon lit at (960, 420), 460 px, sitting on the sill line (y 666) with 16 px under its tile, pushing in 3 %.
    static let centre = CGPoint(x: 960, y: 420)
    static let size: CGFloat = 460
    static func iconSize(_ t: Double) -> CGFloat { size * (1 + 0.03 * CGFloat(ramp(t, 0, rise))) }
    /// The glint sweeps the icon's iPad in the dark, the sill line draws, the icon fades up (storyboard S01).
    static let glint = 0.35, glintDuration = 1.0
    static let sillDraw = 1.15, fadeIn = 0.95
    /// S02: the rise into the lockup (v3's: 0.6 s appleOut to 300 px at (960, 340)), the wordmark and the version.
    static let rise = 2.4, wordmark = 3.05, version = 3.45, cut = 4.8
    static let sillY: CGFloat = 666, sillLength: CGFloat = 520
    /// S03: "What’s new." on black.
    static let whatsNew = 4.85, whatsNewOut = 6.2
}

enum Close060 {
    static let start = 72.0
    /// The icon fades in above the line the bug left (y 666, 520 px: the lockup's own, as the open's), the glint round it,
    /// then the lockup's words.
    static let iconIn = 72.0, glint = 72.1, glintDuration = 0.9
    static let wordmark = 72.65, version = 73.05
    static let freeOpen = 74.45, appStore = 75.25, download = 75.65, legal = 76.05
    /// The card holds +1.2 % from the version's landing to the fade; everything but the line fades 78.8–79.4, the line
    /// retracts by 79.7, then black to 80.0.
    static let holdFrom = 73.35, fade = 78.8, fadeEnd = 79.4, retract = 79.1, retractEnd = 79.7
    static let sillLength: CGFloat = Open060.sillLength
    static let iconCentre = CGPoint(x: 960, y: 340), iconSize: CGFloat = 300
    // Baselines: the wordmark on the line (650/666), the version, the lines under it, the legal line in title-safe.
    static let baselines = (wordmark: CGFloat(650), version: CGFloat(736), freeOpen: CGFloat(812), appStore: CGFloat(866),
                            download: CGFloat(900), legal0: CGFloat(978), legal1: CGFloat(1008))
}

// MARK: S01 · black, the glint, the sill line, the icon lit

@MainActor func s060_01(_ t: Double, _ e: Env) throws -> FrameLayers {
    var st = IconState()
    st.opacity = ease(t, Open060.fadeIn, 0.5, .appleOut)
    let cam = IconCamera.resting(size: Open060.iconSize(t), centre: Open060.centre)
    st.camera = cam
    let v = ZStack {
        Backdrop(glow: 0.06 * st.opacity, glowCenter: Open060.centre)
        SillLine(y: Open060.sillY, length: Open060.sillLength * CGFloat(ease(t, Open060.sillDraw, 0.35, .appleOut)))
        if st.opacity > 0.001 { IconCanvas(s: st, part: .all) }
        GlintView(path: glintPath(cam), t: t, start: Open060.glint, duration: Open060.glintDuration)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S02 · the lockup: "Sill" / "0.6.0"

@MainActor func s060_02(_ t: Double, _ e: Env) throws -> FrameLayers {
    let rise = ease(t, Open060.rise, 0.6, .appleOut)
    let size = lerp(Open060.iconSize(Open060.rise), Close060.iconSize, rise)
    let centre = CGPoint(x: 960, y: lerp(Open060.centre.y, Close060.iconCentre.y, rise))
    var st = IconState()
    st.camera = IconCamera.resting(size: size, centre: centre)
    let hold = 1 + 0.012 * CGFloat(ramp(t, Open060.version + 0.30, Open060.cut))
    var lines = [LineSpec(Copy060.wordmark, .W, baseline: Close060.baselines.wordmark, snap: Open060.wordmark, holdEnd: Open060.wordmark, cascade: false),
                 LineSpec(Copy060.version, .T4g, baseline: Close060.baselines.version, snap: Open060.version, holdEnd: Open060.version, cascade: false)]
    for i in lines.indices { lines[i].holdScale = false }
    let card = CGAffineTransform.scaling(hold, about: CGPoint(x: 960, y: 540))
    let v = ZStack {
        ZStack {
            Backdrop(glow: 0.06, glowCenter: centre)
            IconCanvas(s: st, part: .all)
        }
        .canvas()
        .scaled(hold, about: CGPoint(x: 960, y: 540))
        SillLine(y: Open060.sillY, length: Open060.sillLength)
        TypeLayer(lines: lines, t: t, transform: card)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S03 · "What’s new."

@MainActor func s060_03(_ t: Double, _ e: Env) throws -> FrameLayers {
    let line = LineSpec(Copy060.whatsNew, .T1, baseline: 585, snap: Open060.whatsNew, holdEnd: Open060.whatsNewOut, easeOut: Open060.whatsNewOut)
    let v = ZStack {
        Color.black
        TypeLayer(lines: [line], t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S21–S23 · the close: the icon over the bug's line, the lockup, the end card, the fade

@MainActor func s060_21(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = Close060.self
    let fade = 1 - CubicBezier.inOut(ramp(t, c.fade, c.fadeEnd))
    let iconIn = ease(t, c.iconIn, 0.5, .appleOut)
    var st = IconState()
    st.opacity = iconIn * fade
    let cam = IconCamera.resting(size: c.iconSize, centre: CGPoint(x: c.iconCentre.x, y: c.iconCentre.y + 12 * CGFloat(1 - iconIn)))
    st.camera = cam
    let hold = 1 + 0.012 * CGFloat(ramp(t, c.holdFrom, c.fade))
    let b = c.baselines
    var lines = [LineSpec(Copy060.wordmark, .W, baseline: b.wordmark, snap: c.wordmark, holdEnd: c.wordmark, cascade: false),
                 LineSpec(Copy060.version, .T4g, baseline: b.version, snap: c.version, holdEnd: c.version, cascade: false)]
    if t >= c.freeOpen - 1e-6 { lines.append(LineSpec(Copy060.freeOpen, .T4, baseline: b.freeOpen, snap: c.freeOpen, holdEnd: c.freeOpen)) }
    if t >= c.appStore - 1e-6 { lines.append(LineSpec(Copy060.appStore, .T5, baseline: b.appStore, snap: c.appStore, holdEnd: c.appStore, cascade: false)) }
    if t >= c.download - 1e-6 { lines.append(LineSpec(Copy060.download, .T5, baseline: b.download, snap: c.download, holdEnd: c.download, cascade: false)) }
    if t >= c.legal - 1e-6 {
        // Two lines at 24 px. With the card's +1.2 % hold about y 540 the lower baseline ends at 1013.6 and its
        // descenders at 1019, inside title-safe (y 1026), as v3's.
        lines.append(LineSpec(Copy060.legal[0], .T6, baseline: b.legal0, snap: c.legal, holdEnd: c.legal, cascade: false))
        lines.append(LineSpec(Copy060.legal[1], .T6, baseline: b.legal1, snap: c.legal, holdEnd: c.legal, cascade: false))
    }
    for i in lines.indices { lines[i].holdScale = false }
    let card = CGAffineTransform.scaling(hold, about: CGPoint(x: 960, y: 540))
    let length = c.sillLength * CGFloat(1 - CubicBezier.inOut(ramp(t, c.retract, c.retractEnd)))
    let v = ZStack {
        ZStack {
            Backdrop(glow: 0.06 * iconIn * fade, glowCenter: c.iconCentre)
            if st.opacity > 0.001 { IconCanvas(s: st, part: .all) }
            GlintView(path: glintPath(cam), t: t, start: c.glint, duration: c.glintDuration).opacity(fade)
        }
        .canvas()
        .scaled(hold, about: CGPoint(x: 960, y: 540))
        // The line is not in the card's hold, so it does not move when the hold starts (v3's lockup).
        SillLine(y: Open060.sillY, length: length)
        TypeLayer(lines: lines, t: t, transform: card).opacity(fade)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}
