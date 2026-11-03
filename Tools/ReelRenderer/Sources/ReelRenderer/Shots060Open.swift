// Shots060Open.swift — the 0.6.0 reel's open (S01–S03, 0.0–6.4) and close (S21–S23, 72.0–80.0): the lit icon on
// the sill line, the lockup with the version, "What’s new.", and the end card. v3's close, reused (ShotsI.swift):
// the glint round the icon's iPad, the icon's rise, the wordmark landing on the sill line, the +1.2 % card hold.
// The close's times are v4's: v4.2 (v4 without the tour) plays S21–S23 3.2 s earlier, handing s060_21 v4's time
// (Timeline060, Cut060), and the score maps the close's cues with Cut060.film.
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

    // MARK: v5: the end card's row (Noah on v4.2 at 1:13: "Add the Download on the App Store icon and the GitHub logo and
    // Homebrew logo and make it look aesthetic")

    /// Apple's own "Download on the App Store" badge (black, US), as the site uses it: site/app-store-badge.svg, drawn as its
    /// paths (Marks060.AppStoreBadge.artwork; the marks work measured it identical to the file), never modified, angled or
    /// animated: it only fades in with its line and out with the card.
    static let badgeURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("site/app-store-badge.svg")
    static let badgeArtwork = Marks060.AppStoreBadge.artwork(badgeURL)
    /// One row under "Free. Open source." (the marks work's proposal, Marks060.EndCardRow): the badge (44 px tall, the
    /// guidelines' 40 px and more, a quarter of its height clear round it), "For iPhone and iPad on the App Store.", then the
    /// GitHub mark (30 px, white) and the Homebrew logo (36 px, its own colours), "For Mac at getsill.app/download"; 18, 64,
    /// 12 and 18 px apart by ink, the row centred on x 960 by its ink as TypeLine lays the lines out, the marks centred on
    /// y 876, the lines' baselines at 885. The row is not in the card's hold, so the badge never moves.
    struct Row {
        let badge: CGRect, gitHub: CGRect, homebrew: CGRect
        let appStoreX: CGFloat, downloadX: CGFloat
        static let baseline: CGFloat = 885, centreY: CGFloat = 876
    }
    static let row: Row = {
        func ink(_ text: String) -> (left: CGFloat, right: CGFloat) {
            let words = text.split(separator: " ").map(String.init)
            var x: CGFloat = 0, left = CGFloat.infinity, right = -CGFloat.infinity
            for (i, w) in words.enumerated() {
                let s = ShapedText.shape(w + (i < words.count - 1 ? " " : ""), .T5, language: nil)
                for g in s.glyphs { if let o = g.outline { let b = o.boundingBox; left = min(left, x + g.position.x + b.minX); right = max(right, x + g.position.x + b.maxX) } }
                x += s.frameWidth
            }
            return (left, right)
        }
        let i1 = ink(Copy060.appStore), i2 = ink(Copy060.download)
        let bw = Marks060.AppStoreBadge.width(height: 44), gw = Marks060.GitHubMark.width(height: 30), hw = Marks060.Homebrew.width(height: 36)
        let total = bw + 18 + (i1.right - i1.left) + 64 + gw + 12 + hw + 18 + (i2.right - i2.left)
        let left = 960 - total / 2
        let x1 = (left + bw + 18 - i1.left).rounded()
        let gx = x1 + i1.right + 64, hx = gx + gw + 12
        let x2 = (hx + hw + 18 - i2.left).rounded()
        let c = Row.centreY
        return Row(badge: CGRect(x: left, y: c - 22, width: bw, height: 44), gitHub: CGRect(x: gx, y: c - 15, width: gw, height: 30),
                   homebrew: CGRect(x: hx, y: c - 18, width: hw, height: 36), appStoreX: x1, downloadX: x2)
    }()
}

/// v5: the end card's marks, at their places in the row (Close060.row), faded by their lines' snaps and the card's fade.
struct EndCardMarks060: View {
    let badge: Double, marks: Double
    var body: some View {
        Canvas { ctx, _ in
            let r = Close060.row
            ctx.withCGContext { cg in
                if badge > 0.001, let art = Close060.badgeArtwork {
                    Marks060.AppStoreBadge.drawArtwork(cg, art, at: r.badge.origin, height: r.badge.height, opacity: CGFloat(badge))
                }
                if marks > 0.001 {
                    cg.saveGState(); cg.setAlpha(CGFloat(marks)); cg.beginTransparencyLayer(auxiliaryInfo: nil)
                    Marks060.GitHubMark.draw(cg, at: r.gitHub.origin, height: r.gitHub.height, color: Marks060.color(0xFFFFFF))
                    Marks060.Homebrew.draw(cg, at: r.homebrew.origin, height: r.homebrew.height, style: .color)
                    cg.endTransparencyLayer(); cg.restoreGState()
                }
            }
        }
    }
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

// MARK: S02 · the lockup: "Sill" / "0.6"

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
    // v5: the two small lines in the row with the marks, outside the card's hold.
    var row: [LineSpec] = []
    if t >= c.appStore - 1e-6 {
        row.append(LineSpec(Copy060.appStore, .T5, x: c.row.appStoreX, baseline: Close060.Row.baseline, align: .leading, snap: c.appStore, holdEnd: c.appStore, cascade: false))
    }
    if t >= c.download - 1e-6 {
        row.append(LineSpec(Copy060.download, .T5, x: c.row.downloadX, baseline: Close060.Row.baseline, align: .leading, snap: c.download, holdEnd: c.download, cascade: false))
    }
    for i in row.indices { row[i].holdScale = false }
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
        // v5: the row (the badge, its line, the GitHub mark and the Homebrew logo, their line), not in the hold either.
        EndCardMarks060(badge: ramp(t, c.appStore, c.appStore + 0.12) * fade, marks: ramp(t, c.download, c.download + 0.12) * fade)
        TypeLayer(lines: row, t: t).opacity(fade)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}
