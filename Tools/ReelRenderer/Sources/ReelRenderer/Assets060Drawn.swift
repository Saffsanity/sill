// Assets060Drawn.swift — the 0.6.0 reel's drawn elements (storyboard §2, §6 step 5): the sound arcs (S06), the
// Mac's lock screen, the iPad's keyboard and the app's "Unlocking…" (S07–S08), the drawn Mac whose window goes
// back to its own size (S15), the hold ring (S16) and the iMac of S18.
//
// Each is drawn in vector at its size on the canvas (a Canvas, a GraphicsContext), never a bitmap moved or
// scaled, so a push or a close-up stays sharp and a moving edge lands where it is, between pixels. Times are
// reel seconds; each type's defaults are the storyboard's, and every number can be handed in.
import AppKit
import SwiftUI

// MARK: - The Mac's picture and the icon's window

enum MacPicture060 {
    /// The Mac's picture as the 0.6.0 stills stream it: 16:10 (a 1440×900 pt display or window at 2×).
    static let display = CGSize(width: 1440, height: 900)
    /// Where that picture sits in an iPad mini still or recording (2266×1488 px, the Settings panel closed): x 106–2158,
    /// y 188–1471 (the footage stand-ins' README); the bar is y 0–~170.
    static let inMiniSource = CGRect(x: 106, y: 188, width: 2052, height: 1283)
    /// That rect in a device's interior (screen px, the interior's top-left at the origin).
    static func inMini(_ spec: DeviceSpec) -> CGRect {
        let k = spec.interior.width / Device060.miniSource.width
        return CGRect(x: inMiniSource.minX * k, y: inMiniSource.minY * k, width: inMiniSource.width * k, height: inMiniSource.height * k)
    }
    /// The Mac's picture fitted (aspect-fit, centred) in the stream panel `panel`, as the stream screen shows it.
    static func rect(in panel: CGRect, display: CGSize = display) -> CGRect {
        let s = min(panel.width / display.width, panel.height / display.height)
        let w = display.width * s, h = display.height * s
        return CGRect(x: panel.midX - w / 2, y: panel.midY - h / 2, width: w, height: h)
    }
}

enum MacWindow060 {
    /// The icon's light window (§8.4 layer 4, as v3's CoveredMac draws it) in `r`: the body, the accent title
    /// strip, three dots and three bars, its parts at `k` px per icon unit (the strip 40 units, the bars 14), so a
    /// window resized on the Mac keeps its content's size and only its frame changes. `dark`: the covering window.
    static func draw(_ ctx: inout GraphicsContext, _ r: CGRect, k: CGFloat, opacity: Double = 1, dark: Bool = false) {
        guard opacity > 0.002, r.width > 1, r.height > 1 else { return }
        var c0 = ctx
        c0.opacity = opacity
        let shape = Path(roundedRect: r, cornerRadius: min(20 * k, r.height / 2), style: .circular)
        c0.fill(shape, with: .color(Color(hex: dark ? Palette.winDarkBody : Palette.winLightBody)))
        var c = c0
        c.clip(to: shape)
        c.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 40 * k)), with: .color(Color(hex: dark ? Palette.winDarkStrip : Palette.accent)))
        let dots: Color = dark ? .white.opacity(0.9) : .white
        for (i, a) in [0.7, 0.5, 0.35].enumerated() {
            c.fill(Path(ellipseIn: CGRect(x: r.minX + (19 + 22 * CGFloat(i)) * k, y: r.minY + 13 * k, width: 14 * k, height: 14 * k)),
                   with: .color(dots.opacity(a)))
        }
        let bars: Color = dark ? .white.opacity(0.10) : Color(hex: Palette.winLightBars)
        for (i, (w, a)) in [(150.0, 0.9), (210.0, 0.55), (110.0, 0.55)].enumerated() {
            c.fill(Path(roundedRect: CGRect(x: r.minX + 26 * k, y: r.minY + (66 + 30 * CGFloat(i)) * k, width: min(CGFloat(w) * k, r.width - 52 * k), height: 14 * k),
                        cornerRadius: 7 * k, style: .circular), with: .color(bars.opacity(a)))
        }
    }
}

// MARK: - S06 · the sound arcs

/// Three thin accent arcs beside a device, pulsing out on every beat while the Mac's sound plays (S06): each
/// beat lights the inner arc, then the middle and the outer 0.05 s apart (a 0.03 s attack, a 0.18 s decay, the
/// arc easing 5 px outward at its peak). A mute folds them away with the sound's cut, all three at once: the fold
/// starts a frame before the beat, so the beat's own frame already shows most of it (0.08 s appleOut: each arc's
/// sweep closes onto the facing line and its radius draws in), and its end opens them again the same way (0.12 s) on
/// that beat's pulse (the review: they had trailed the sound by a beat's tenth).
struct SoundArcs060: View {
    /// The arcs' centre: on the device's side, at its middle, just outside the bezel.
    var origin: CGPoint
    /// The direction they open toward: 0 to the right, .pi to the left.
    var facing: Double = 0
    var radii: [CGFloat] = [40, 72, 104]
    /// Half the sweep of each arc, degrees either side of `facing`.
    var halfAngle: Double = 36
    var lineWidth: CGFloat = 3.5
    var t: Double
    /// The beats that pulse (the storyboard: every beat of S06, 14.4 … 18.8).
    var beats: [Double] = SoundArcs060.beats(from: 14.4, to: 19.2)
    /// Folded over each range (S06: Mute on at 17.6, off at 18.4).
    var muted: [ClosedRange<Double>] = [17.6...18.4]
    /// The arcs' resting opacity between pulses.
    var rest: Double = 0.35

    static func beats(from a: Double, to b: Double, every step: Double = 0.4) -> [Double] {
        stride(from: a, to: b - 1e-9, by: step).map { $0 }
    }

    /// The arcs' centre beside a device placed at `center` (unturned): `gap` px out from its right side (or its
    /// left, with `facing: .pi`), at its middle.
    static func origin(beside spec: DeviceSpec, center: CGPoint, left: Bool = false, gap: CGFloat = 18) -> CGPoint {
        CGPoint(x: center.x + (left ? -1 : 1) * (spec.outer.width / 2 + gap), y: center.y)
    }

    /// 1 open … 0 folded, for arc `i` (0 the inner).
    func open(_ i: Int) -> Double {
        var f = 1.0
        let frame = 1.0 / 60
        for m in muted {
            if t >= m.lowerBound - frame && t < m.upperBound - frame {
                f = min(f, 1 - ease(t, m.lowerBound - frame, 0.08, .appleOut))
            } else if t >= m.upperBound - frame && t < m.upperBound + 0.4 {
                f = min(f, ease(t, m.upperBound - frame, 0.12, .appleOut))
            }
        }
        return f
    }

    /// The pulse on arc `i`: 0 … 1 (beats inside a mute are silent).
    func pulse(_ i: Int) -> Double {
        var v = 0.0
        for b in beats where !muted.contains(where: { b >= $0.lowerBound && b < $0.upperBound }) {
            let u = t - (b + 0.05 * Double(i))
            guard u >= 0, u < 1.2 else { continue }
            v = max(v, u < 0.03 ? u / 0.03 : exp(-(u - 0.03) / 0.18))
        }
        return v
    }

    var body: some View {
        Canvas { ctx, _ in
            for (i, r0) in radii.enumerated() {
                let f = open(i)
                guard f > 0.002 else { continue }
                let p = pulse(i)
                let r = r0 * CGFloat(0.55 + 0.45 * f) + 5 * CGFloat(p)
                let half = halfAngle * f
                var arc = Path()
                arc.addArc(center: origin, radius: r, startAngle: .radians(facing - half * .pi / 180),
                           endAngle: .radians(facing + half * .pi / 180), clockwise: false)
                let alpha = f * (rest + (1 - rest) * p)
                if p > 0.01 {
                    ctx.drawLayer { g in
                        g.addFilter(.blur(radius: 5))
                        g.stroke(arc, with: .color(Color(hex: Palette.accent, alpha: 0.55 * p * f)),
                                 style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round))
                    }
                }
                ctx.stroke(arc, with: .color(Color(hex: Palette.accent, alpha: alpha)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .canvas()
    }
}

// MARK: - S07–S08 · the Mac's lock screen

/// A Mac's lock screen, drawn so that no real name, photo or wallpaper shows (S07): an abstract dark wallpaper,
/// the date and the time 9:41 at the top, a grey avatar circle and the password field low in the middle, as
/// macOS lays them out. `dots` fill the field as a password is typed (S08); with any, the field shows macOS's
/// arrow, and `verifying` (0 … 1) turns it into a spinner after Return.
struct MacLockScreen060 {
    var time = "9:41"
    var date = "Monday, November 2"
    var placeholder = "Enter Password"
    /// The avatar's and the field's centres, as fractions of the picture's height.
    var avatarY: CGFloat = 0.735
    var fieldY: CGFloat = 0.835

    /// The field's rect for a picture `rect` (for a camera that frames it).
    func fieldRect(_ rect: CGRect) -> CGRect {
        let H = rect.height
        let w = 0.205 * H, h = 0.033 * H
        return CGRect(x: rect.midX - w / 2, y: rect.minY + fieldY * H - h / 2, width: w, height: h)
    }

    func draw(_ ctx: inout GraphicsContext, rect: CGRect, dots: Int = 0, verifying: Double = 0, t: Double = 0, opacity: Double = 1) {
        guard opacity > 0.002 else { return }
        var c = ctx
        c.opacity = opacity
        c.clip(to: Path(rect))
        let W = rect.width, H = rect.height
        // The wallpaper: deep blue-black, with two soft glows (the accent low left, a violet high right).
        c.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: 0x0E1324), Color(hex: 0x05060A)]),
                                                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        c.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: Palette.accent, alpha: 0.16), Color(hex: Palette.accent, alpha: 0)]),
                                                center: CGPoint(x: rect.minX + 0.16 * W, y: rect.minY + 0.95 * H), startRadius: 0, endRadius: 0.62 * W))
        c.fill(Path(rect), with: .radialGradient(Gradient(colors: [Color(hex: 0x4A3F8C, alpha: 0.30), Color(hex: 0x4A3F8C, alpha: 0)]),
                                                center: CGPoint(x: rect.minX + 0.86 * W, y: rect.minY + 0.06 * H), startRadius: 0, endRadius: 0.58 * W))
        // The date, then the time.
        Outline060.draw(date, in: &c, size: 0.026 * H, weight: .semibold, x: rect.midX, baseline: rect.minY + 0.118 * H,
                        color: Color(white: 1, opacity: 0.86))
        Outline060.draw(time, in: &c, size: 0.170 * H, weight: .bold, tracking: -0.004 * H, x: rect.midX, baseline: rect.minY + 0.285 * H,
                        color: Color(white: 1, opacity: 0.93))
        // The avatar: a grey circle with a plain silhouette.
        let d = 0.082 * H
        let a = CGRect(x: rect.midX - d / 2, y: rect.minY + avatarY * H - d / 2, width: d, height: d)
        c.fill(Path(ellipseIn: a), with: .linearGradient(Gradient(colors: [Color(hex: 0xA2A2A8), Color(hex: 0x6A6A70)]),
                                                         startPoint: CGPoint(x: a.midX, y: a.minY), endPoint: CGPoint(x: a.midX, y: a.maxY)))
        var sil = c
        sil.clip(to: Path(ellipseIn: a))
        let head = CGRect(x: a.midX - 0.19 * d, y: a.minY + 0.20 * d, width: 0.38 * d, height: 0.38 * d)
        sil.fill(Path(ellipseIn: head), with: .color(Color(hex: 0xE5E5EA, alpha: 0.72)))
        sil.fill(Path(ellipseIn: CGRect(x: a.midX - 0.36 * d, y: a.minY + 0.64 * d, width: 0.72 * d, height: 0.62 * d)),
                 with: .color(Color(hex: 0xE5E5EA, alpha: 0.72)))
        // The field.
        let f = fieldRect(rect)
        let capsule = Path(roundedRect: f, cornerRadius: f.height / 2, style: .continuous)
        c.fill(capsule, with: .color(.white.opacity(0.17)))
        c.stroke(capsule, with: .color(.white.opacity(0.22)), lineWidth: max(1, 0.0011 * H))
        if dots == 0 {
            Outline060.draw(placeholder, in: &c, size: 0.0145 * H, weight: .regular, x: f.midX, baseline: f.midY + 0.0052 * H,
                            color: .white.opacity(0.55))
        } else {
            let dd = 0.0072 * H, step = 0.0128 * H
            for i in 0..<min(dots, 24) {
                c.fill(Path(ellipseIn: CGRect(x: f.minX + 0.0155 * H + CGFloat(i) * step, y: f.midY - dd / 2, width: dd, height: dd)),
                       with: .color(.white.opacity(0.92)))
            }
            // macOS's arrow at the field's end, and the spinner that takes its place after Return.
            let bd = 0.78 * f.height
            let b = CGRect(x: f.maxX - bd - 0.11 * f.height, y: f.midY - bd / 2, width: bd, height: bd)
            if verifying < 0.999 {
                var arrow = c
                arrow.opacity = 1 - verifying
                arrow.fill(Path(ellipseIn: b), with: .color(.white.opacity(0.24)))
                var shaft = Path()
                shaft.move(to: CGPoint(x: b.minX + 0.27 * bd, y: b.midY)); shaft.addLine(to: CGPoint(x: b.maxX - 0.27 * bd, y: b.midY))
                shaft.move(to: CGPoint(x: b.maxX - 0.45 * bd, y: b.midY - 0.18 * bd)); shaft.addLine(to: CGPoint(x: b.maxX - 0.27 * bd, y: b.midY))
                shaft.addLine(to: CGPoint(x: b.maxX - 0.45 * bd, y: b.midY + 0.18 * bd))
                arrow.stroke(shaft, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, 0.085 * bd), lineCap: .round, lineJoin: .round))
            }
            if verifying > 0.001 {
                var sp = c
                sp.opacity = verifying
                Spinner060.draw(&sp, center: CGPoint(x: b.midX, y: b.midY), radius: 0.46 * bd, t: t, color: .white)
            }
        }
    }
}

/// The classic activity indicator: eight rounded spokes, the lit one stepping round every 0.1 s.
enum Spinner060 {
    static func draw(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, t: Double, color: Color, spokes: Int = 8) {
        let lit = Int(floor(max(0, t) / 0.1)) % spokes
        for i in 0..<spokes {
            let angle = Double(i) / Double(spokes) * 2 * .pi - .pi / 2
            let age = (lit - i + spokes) % spokes
            let alpha = 1 - 0.85 * Double(age) / Double(spokes - 1)
            let inner = 0.48 * radius, outer = radius
            var p = Path()
            p.move(to: CGPoint(x: center.x + inner * CGFloat(cos(angle)), y: center.y + inner * CGFloat(sin(angle))))
            p.addLine(to: CGPoint(x: center.x + outer * CGFloat(cos(angle)), y: center.y + outer * CGFloat(sin(angle))))
            ctx.stroke(p, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: 0.24 * radius, lineCap: .round))
        }
    }
}

/// The app's own cover after an unlock (LockedMacShade, docs/locked-mac-plan.md): the stream panel's colour
/// (#1F2126) over the picture, a spinner in the muted grey and "Unlocking…" (17 pt semibold) under it, centred.
/// `pt`: screen px per iPad point. NB: in 0.6.0's client a cover, and so "Unlocking…", follows another user's
/// session (LockedMac.shade); a screen locked in this session streams its lock screen with no cover.
enum UnlockingCover060 {
    static let title = "Unlocking\u{2026}"
    static func draw(_ ctx: inout GraphicsContext, rect: CGRect, pt: CGFloat, t: Double, opacity: Double = 1) {
        guard opacity > 0.002 else { return }
        var c = ctx
        c.opacity = opacity
        c.fill(Path(rect), with: .color(Color(hex: 0x1F2126)))
        let spinner: CGFloat = 20 * pt, gap: CGFloat = 10 * pt, text: CGFloat = 17 * pt
        let top = rect.midY - (spinner + gap + text * 1.2) / 2
        Spinner060.draw(&c, center: CGPoint(x: rect.midX, y: top + spinner / 2), radius: spinner / 2, t: t, color: Color(hex: 0xA4ABB5))
        Outline060.draw(title, in: &c, size: text, weight: .semibold, x: rect.midX, baseline: top + spinner + gap + text * 0.95,
                        color: Color(hex: 0xEEF0F3))
    }
}

// MARK: - S08 · the iPad's keyboard

/// iPadOS's keyboard, dark and simplified (no legible letters, S08): four rows of plain keys, letters lighter
/// than the special keys, in `rect` (the iPad's keyboard area, or a floating panel). A tapped key flashes
/// lighter for 0.1 s. `Key` names the keys a touch dot can land on; `center` says where.
enum SoftKeyboard060 {
    enum Key: Hashable { case letter(row: Int, index: Int), ret, delete, shiftLeft, shiftRight, space }

    /// Key units per row (each 11.45): row 0 ten letters and delete, row 1 an indent, nine letters and return,
    /// row 2 shift, nine keys and shift, row 3 the bottom row with the space bar.
    private static func layout(_ r: CGRect) -> [(Key?, CGRect, Bool)] {
        let top = 0.045 * r.height, bottom = 0.06 * r.height, side = 0.006 * r.width
        let rowGap = 0.035 * r.height
        let rowH = (r.height - top - bottom - 3 * rowGap) / 4
        let pitch = (r.width - 2 * side) / 11.45, gap = 0.075 * pitch
        var out: [(Key?, CGRect, Bool)] = []
        func row(_ i: Int, _ keys: [(Key?, CGFloat, Bool)], indent: CGFloat = 0) {
            var x = r.minX + side + indent * pitch
            let y = r.minY + top + CGFloat(i) * (rowH + rowGap)
            for (k, u, special) in keys {
                out.append((k, CGRect(x: x + gap / 2, y: y, width: u * pitch - gap, height: rowH), special))
                x += u * pitch
            }
        }
        row(0, (0..<10).map { (.letter(row: 0, index: $0), 1, false) } + [(.delete, 1.45, true)])
        row(1, (0..<9).map { (.letter(row: 1, index: $0), 1, false) } + [(.ret, 1.95, true)], indent: 0.5)
        row(2, [(.shiftLeft, 1.45, true)] + (0..<9).map { (.letter(row: 2, index: $0), 1, false) } + [(.shiftRight, 1.0, true)])
        row(3, [(nil, 1.45, true), (nil, 1, true), (nil, 1, true), (.space, 5.55, false), (nil, 1.45, true), (nil, 1, true)])
        return out
    }

    static func keyRect(_ key: Key, in rect: CGRect) -> CGRect? { layout(rect).first { $0.0 == key }?.1 }
    static func center(_ key: Key, in rect: CGRect) -> CGPoint {
        let k = keyRect(key, in: rect) ?? rect
        return CGPoint(x: k.midX, y: k.midY)
    }

    /// The keyboard in `rect`. `flash`: each key's tap times (a key flashes lighter for 0.1 s from each).
    /// `floating`: rounded corners all round (a panel), else square to the screen's edges with a hairline on top.
    static func draw(_ ctx: inout GraphicsContext, rect: CGRect, t: Double, flash: [Key: [Double]] = [:], floating: Bool = false) {
        let corner = floating ? 0.05 * rect.height : 0
        let shape = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        ctx.fill(shape, with: .color(Color(hex: 0x1F1F21)))
        if !floating {
            ctx.stroke(Path { p in p.move(to: CGPoint(x: rect.minX, y: rect.minY + 0.5)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 0.5)) },
                       with: .color(Color(hex: 0x3A3A3C)), lineWidth: 1)
        } else {
            ctx.stroke(shape, with: .color(Color(hex: 0x3A3A3C)), lineWidth: 1)
        }
        for (key, r, special) in layout(rect) {
            var lit = 0.0
            if let key, let times = flash[key] {
                for tap in times where t >= tap { lit = max(lit, 1 - ramp(t, tap + 0.10, tap + 0.18)) }
            }
            let base = special ? 0x3A3A3D : 0x5A5A5E
            let face = Keycap060Painter.lerpColor(UInt32(base), 0x9A9AA0, lit)
            let kr = Path(roundedRect: r, cornerRadius: 0.13 * r.height, style: .continuous)
            // A key's shadow edge under it, as iPadOS draws one.
            ctx.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: max(1, 0.035 * r.height)), cornerRadius: 0.13 * r.height, style: .continuous),
                     with: .color(Color.black.opacity(0.55)))
            ctx.fill(kr, with: .color(Color(hex: face)))
        }
    }

    /// v5 (S10): the iPhone's keyboard, in S08's style (no legible keys) on the iPhone 15 Pro's own layout, measured on iOS
    /// 27's keyboard in the footage (D8, 786×602 px at 2×: its rows' keys 65 px on a 77 px pitch, 86 px tall on a 108 px
    /// pitch from y 50; shift and delete 87 px, 123 and return 179, the space bar 372; the bottom 142 px holding only the
    /// emoji and dictation keys' glyphs, left empty here; the top corners 55 px round). `rect` is the keyboard's whole rect.
    static func drawPhone(_ ctx: inout GraphicsContext, rect: CGRect) {
        let u = rect.width / 786
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * u, y: rect.minY + y * u, width: w * u, height: h * u)
        }
        let shape = UnevenRoundedRectangle(topLeadingRadius: 55 * u, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                           topTrailingRadius: 55 * u, style: .continuous).path(in: rect)
        ctx.fill(shape, with: .color(Color(hex: 0x1F1F21)))
        var keys: [(CGRect, Bool)] = []
        for i in 0..<10 { keys.append((r(14 + 77 * CGFloat(i), 50, 65, 86), false)) }
        for i in 0..<9 { keys.append((r(52.5 + 77 * CGFloat(i), 158, 65, 86), false)) }
        keys.append((r(14, 266, 87, 86), true))
        for i in 0..<7 { keys.append((r(129 + 77 * CGFloat(i), 266, 65, 86), false)) }
        keys.append((r(685, 266, 87, 86), true))
        keys.append((r(14, 374, 179, 86), true)); keys.append((r(207, 374, 372, 86), false)); keys.append((r(593, 374, 179, 86), true))
        for (k, special) in keys {
            let radius = 0.13 * k.height
            ctx.fill(Path(roundedRect: k.offsetBy(dx: 0, dy: max(0.5, 0.035 * k.height)), cornerRadius: radius, style: .continuous),
                     with: .color(Color.black.opacity(0.55)))
            ctx.fill(Path(roundedRect: k, cornerRadius: radius, style: .continuous), with: .color(Color(hex: special ? 0x3A3A3D : 0x5A5A5E)))
        }
    }

    /// The keyboard's offset below its place while it rises (0.30 s appleOut from `rise`) and after `lower`
    /// (0.30 s appleIn): 0 in place, `height + 24` gone.
    static func offset(_ t: Double, height: CGFloat, rise: Double, lower: Double? = nil) -> CGFloat {
        var gone = 1 - ease(t, rise, 0.30, .appleOut)
        if let lower, t >= lower { gone = max(gone, ease(t, lower, 0.30, .appleIn)) }
        return (height + 24) * CGFloat(gone)
    }
}

/// S07–S08's timing, as the storyboard has it: the lock at 19.6 (the picture dissolves to the lock screen in
/// 0.25 s), the keyboard rising at 24.0, eight taps 0.1 s apart from 24.4, Return at 25.2, then "Unlocking…",
/// and the lock screen dissolving back to the window at 25.6 (0.25 s) as the keyboard goes down.
struct LockSequence060 {
    var lock = 19.6
    var dissolve = 0.25
    var keyboardRise = 24.0
    var taps: [Double] = (0..<8).map { 24.4 + 0.1 * Double($0) }
    /// The letter keys the eight taps land on (spread over the rows; no word).
    var tapKeys: [SoftKeyboard060.Key] = [.letter(row: 0, index: 2), .letter(row: 1, index: 5), .letter(row: 0, index: 7), .letter(row: 2, index: 3),
                                          .letter(row: 1, index: 1), .letter(row: 0, index: 4), .letter(row: 2, index: 7), .letter(row: 1, index: 8)]
    var returnAt = 25.2
    var unlock = 25.6
    /// The keyboard goes down with the unlock's dissolve (the unlocked still has none); nil keeps it up.
    var keyboardLower: Double? = 25.6
    /// The app's "Unlocking…" cover from just after Return until the unlock's dissolve ends. See
    /// `UnlockingCover060`: 0.6.0's client shows it after another user's session, not after a lock in this one.
    var appCover = true
    var screen = MacLockScreen060()

    /// The lock screen's opacity over the window: in at the lock, out at the unlock.
    func lockOpacity(_ t: Double) -> Double {
        CubicBezier.inOut(ramp(t, lock, lock + dissolve)) * (1 - CubicBezier.inOut(ramp(t, unlock, unlock + dissolve)))
    }
    /// How many dots the field holds (one per tap, 0.02 s after the finger lands).
    func dots(_ t: Double) -> Int { taps.filter { t >= $0 + 0.02 }.count }
    /// The field's spinner after Return (0.12 s in).
    func verifying(_ t: Double) -> Double { ramp(t, returnAt + 0.04, returnAt + 0.16) }
    func coverOpacity(_ t: Double) -> Double {
        guard appCover else { return 0 }
        return ramp(t, returnAt + 0.10, returnAt + 0.22) * (1 - CubicBezier.inOut(ramp(t, unlock, unlock + dissolve)))
    }
    /// The keys' flash times.
    var flash: [SoftKeyboard060.Key: [Double]] {
        var f: [SoftKeyboard060.Key: [Double]] = [:]
        for (k, tap) in zip(tapKeys, taps) { f[k, default: []].append(tap) }
        f[.ret, default: []].append(returnAt)
        return f
    }
    /// The touch dots for the taps and Return: each tap's time and its key's centre in the canvas's px
    /// (`keyboard`: the keyboard's rect on the canvas at rest), for v3's tap dots (`TouchDot`, 64 pt on the device).
    func dots(keyboard: CGRect) -> [(time: Double, point: CGPoint)] {
        zip(taps, tapKeys).map { ($0, SoftKeyboard060.center($1, in: keyboard)) } + [(returnAt, SoftKeyboard060.center(.ret, in: keyboard))]
    }

    /// The stream picture's overlay at `t`: the lock screen (with the field's dots) and, after Return, the
    /// app's cover. `rect`: the Mac's picture on the canvas; `pt`: screen px per iPad point (for the cover).
    func drawPicture(_ ctx: inout GraphicsContext, rect: CGRect, pt: CGFloat, t: Double) {
        screen.draw(&ctx, rect: rect, dots: dots(t), verifying: verifying(t), t: t, opacity: lockOpacity(t))
        UnlockingCover060.draw(&ctx, rect: rect, pt: pt, t: t, opacity: coverOpacity(t))
    }
}

// MARK: - S15 and S18 · the drawn iMac

/// The iMac of v3: `.line` is S22's line drawing (CoveredMac: 3 px strokes in text.1 at 55 %, its screen dark),
/// `.solid` the app icon's own iMac (S02–S03: the grey gradient body, the screen, the gloss and the white
/// stroke). Drawn at `k` px per icon unit with the icon point (512, 404), the body's centre, at `center`, so a push
/// (a growing `k`) stays sharp. On its screen: an optional light window (`window`, in screen units: x 0…616,
/// y 0…352 from the screen's top-left), the glint crossing the glass (`sheen`), and v3's glint round the screen's
/// edge (`edgeGlint`, GlintView).
struct DrawnIMac060: View {
    enum Style { case line, solid }
    var style: Style
    var k: CGFloat
    var center: CGPoint
    var window: CGRect? = nil
    var windowOpacity: Double = 1
    var sheen: (start: Double, duration: Double)? = nil
    var edgeGlint: (start: Double, duration: Double)? = nil
    var t: Double = 0
    var opacity: Double = 1

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + (x - 512) * k, y: center.y + (y - 404) * k) }
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { let o = p(x, y); return CGRect(x: o.x, y: o.y, width: w * k, height: h * k) }
    var screenRect: CGRect { r(204, 204, 616, 352) }
    var bodyRect: CGRect { r(176, 176, 672, 456) }
    /// A rect in screen units → the canvas.
    func onScreen(_ u: CGRect) -> CGRect {
        let s = screenRect
        return CGRect(x: s.minX + u.minX * k, y: s.minY + u.minY * k, width: u.width * k, height: u.height * k)
    }
    /// The screen's outline from its top-left corner, clockwise (for the edge glint).
    var screenOutline: Path {
        let s = screenRect, rad = 36 * k
        var path = Path()
        path.addArc(center: CGPoint(x: s.minX + rad, y: s.minY + rad), radius: rad, startAngle: .degrees(225), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: s.maxX - rad, y: s.minY))
        path.addArc(center: CGPoint(x: s.maxX - rad, y: s.minY + rad), radius: rad, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: s.maxX, y: s.maxY - rad))
        path.addArc(center: CGPoint(x: s.maxX - rad, y: s.maxY - rad), radius: rad, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: s.minX + rad, y: s.maxY))
        path.addArc(center: CGPoint(x: s.minX + rad, y: s.maxY - rad), radius: rad, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: s.minX, y: s.minY + rad))
        path.addArc(center: CGPoint(x: s.minX + rad, y: s.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(225), clockwise: false)
        return path
    }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                var c = ctx
                c.opacity = opacity
                switch style {
                case .line: drawLine(&c)
                case .solid: drawSolid(&c)
                }
                let screen = Path(roundedRect: screenRect, cornerRadius: 36 * k, style: .circular)
                var glass = c
                glass.clip(to: screen)
                if let window { MacWindow060.draw(&glass, onScreen(window), k: k, opacity: windowOpacity) }
                if let sheen { drawSheen(&glass, sheen) }
            }
            .canvas()
            if let g = edgeGlint {
                GlintView(path: screenOutline, t: t, start: g.start, duration: g.duration).opacity(opacity)
            }
        }
        .canvas()
    }

    private func drawLine(_ c: inout GraphicsContext) {
        let lw = max(2, 3 * k / 1.6)
        let line = Color(hex: Palette.text1, alpha: 0.55)
        c.fill(Path(roundedRect: screenRect, cornerRadius: 36 * k, style: .circular), with: .color(Color(hex: Palette.bg1)))
        c.stroke(Path(roundedRect: bodyRect, cornerRadius: 60 * k, style: .circular), with: .color(line), lineWidth: lw)
        c.stroke(Path(roundedRect: screenRect, cornerRadius: 36 * k, style: .circular), with: .color(Color(hex: Palette.text1, alpha: 0.18)), lineWidth: max(1, 1.5 * k / 1.6))
        c.stroke(Path(r(480, 632, 64, 40)), with: .color(line), lineWidth: lw)
        c.stroke(Path(roundedRect: r(372, 672, 280, 40), cornerRadius: 20 * k, style: .circular), with: .color(line), lineWidth: lw)
    }

    private func fillBox(_ c: inout GraphicsContext, _ path: Path, _ g: Gradient, _ from: CGPoint, _ to: CGPoint) {
        let box = path.boundingRect
        var cc = c
        cc.clip(to: path)
        cc.fill(Path(box), with: .linearGradient(g, startPoint: CGPoint(x: box.minX + from.x * box.width, y: box.minY + from.y * box.height),
                                                 endPoint: CGPoint(x: box.minX + to.x * box.width, y: box.minY + to.y * box.height)))
    }

    /// The icon's iMac (Icon.swift `drawIMac`: §8.4 layer 2), at this k and centre.
    private func drawSolid(_ c: inout GraphicsContext) {
        let grey = Gradient(stops: [.init(color: Color(hex: 0x7C7E86, alpha: 0.98), location: 0), .init(color: Color(hex: 0x4C4E56, alpha: 0.96), location: 1)])
        let gloss = Gradient(stops: [.init(color: .white.opacity(0.6), location: 0), .init(color: .white.opacity(0.1), location: 0.4),
                                     .init(color: .white.opacity(0), location: 1)])
        let body = Path(roundedRect: bodyRect, cornerRadius: 60 * k, style: .circular)
        for path in [Path(roundedRect: r(372, 672, 280, 40), cornerRadius: 20 * k, style: .circular), Path(r(480, 630, 64, 50)), body] {
            fillBox(&c, path, grey, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        }
        c.fill(Path(roundedRect: screenRect, cornerRadius: 36 * k, style: .circular), with: .color(Color(hex: Palette.bg1, alpha: 0.97)))
        var g = c
        g.opacity = 0.5
        fillBox(&g, body, gloss, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1))
        c.stroke(Path(roundedRect: r(177.5, 177.5, 669, 453), cornerRadius: 59 * k, style: .circular), with: .color(.white.opacity(0.5)), lineWidth: 3 * k)
    }

    /// The glint crossing the glass: a soft white band leaning 20°, a 2 px white core with v3's accent glow at its
    /// middle, from wholly left of the screen to wholly right of it in `duration` (a sine ease in and out), fading
    /// in and out at the ends of its run.
    private func drawSheen(_ c: inout GraphicsContext, _ s: (start: Double, duration: Double)) {
        guard t >= s.start, t <= s.start + s.duration else { return }
        let u = clamp01((t - s.start) / s.duration)
        // A sine ease in and out: the band crosses at an even, visible pace (v3's inOut is asymmetric, and its
        // steep middle took the band across the glass in a fifth of the run).
        let e = CGFloat((1 - cos(Double.pi * u)) / 2)
        let sr = screenRect
        let lean = tan(20 * Double.pi / 180)
        let dx = CGFloat(lean) * sr.height
        let band = 0.30 * sr.width
        // From wholly left of the glass (the band's top right corner on its left edge) to wholly right of it.
        let x = sr.minX - band / 2 - dx + (sr.width + band + dx) * e
        let fade = sin(Double.pi * u)
        // The band: a parallelogram, its gradient across its width.
        var shape = Path()
        shape.move(to: CGPoint(x: x - band / 2 + dx, y: sr.minY)); shape.addLine(to: CGPoint(x: x + band / 2 + dx, y: sr.minY))
        shape.addLine(to: CGPoint(x: x + band / 2, y: sr.maxY)); shape.addLine(to: CGPoint(x: x - band / 2, y: sr.maxY)); shape.closeSubpath()
        c.fill(shape, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0), location: 0),
                                                            .init(color: .white.opacity(0.11 * fade), location: 0.5),
                                                            .init(color: .white.opacity(0), location: 1)]),
                                            startPoint: CGPoint(x: x - band / 2 + dx / 2, y: sr.midY), endPoint: CGPoint(x: x + band / 2 + dx / 2, y: sr.midY)))
        var core = Path()
        core.move(to: CGPoint(x: x + dx, y: sr.minY)); core.addLine(to: CGPoint(x: x, y: sr.maxY))
        c.drawLayer { g in
            g.addFilter(.blur(radius: 5))
            g.stroke(core, with: .color(Color(hex: Palette.accent, alpha: 0.42 * fade)), lineWidth: 10)
        }
        c.stroke(core, with: .color(.white.opacity(0.55 * fade)), lineWidth: 2)
    }
}

/// S15's drawn Mac: v3's line-drawn iMac with the stand-in window at the size Sill gave it, shrinking back to its
/// own frame (and place) on the beat (0.3 s appleOut). Frames in screen units (the screen is 616×352).
struct AaMac060: View {
    var k: CGFloat = 0.95
    var center = CGPoint(x: 560, y: 560)
    var t: Double
    var shrink = 54.4
    var duration = 0.3
    /// The window as Sill sized it (Aa at 1.25×: bigger than its own), and its own frame.
    var sillFrame = CGRect(x: 46, y: 26, width: 524, height: 300)
    var ownFrame = CGRect(x: 104, y: 70, width: 304, height: 180)
    var frame: CGRect {
        let e = CGFloat(ease(t, shrink, duration, .appleOut))
        return CGRect(x: lerp(sillFrame.minX, ownFrame.minX, Double(e)), y: lerp(sillFrame.minY, ownFrame.minY, Double(e)),
                      width: lerp(sillFrame.width, ownFrame.width, Double(e)), height: lerp(sillFrame.height, ownFrame.height, Double(e)))
    }
    var body: some View { DrawnIMac060(style: .line, k: k, center: center, window: frame, t: t) }
}

/// S18's iMac: the icon's own iMac, centred, pushing in 3 % over the shot (linear, so its edges glide), the glint
/// crossing its screen at 63.2 (0.9 s, as v3's close glint).
struct IntelIMac060: View {
    var t: Double
    var start = 62.4, end = 65.6
    var k: CGFloat = 1.18
    var center = CGPoint(x: 960, y: 620)
    var glint = 63.2
    var glintDuration = 0.9
    var push: CGFloat = 0.03
    var body: some View {
        let s = 1 + push * CGFloat(ramp(t, start, end))
        // The push is about the body's centre: k grows and the centre stays.
        DrawnIMac060(style: .solid, k: k * s, center: center, sheen: (glint, glintDuration), t: t)
    }
}

// MARK: - S16 · the hold ring

/// A touch held on a thumbnail (S16): v3's touch dot (white 18 % fill, its 45 % ring), and the accent ring drawing
/// clockwise from 12 o'clock in exactly `duration` (linear: it is the hold's timer, 0.5 s), done the instant the
/// controls open; then a copy of the ring swells 1 → 1.18 and fades (0.25 s). The finger lifts at `lift` (the dot
/// fades 0.25 s). Drawn at its size: `diameter` is the dot's (64 pt on the device × the shot's scale).
struct HoldRing060: View {
    var center: CGPoint
    var diameter: CGFloat
    var down = 56.4
    var duration = 0.5
    var lift = 57.4
    var t: Double
    var linear = true
    var popOnDone = true

    /// The ring's progress (0 … 1).
    var progress: Double { linear ? ramp(t, down, down + duration) : ease(t, down, duration, .inOut) }

    var body: some View {
        Canvas { ctx, _ in
            let appear = down - 0.08
            guard t >= appear else { return }
            let s = 0.7 + 0.3 * ease(t, appear, 0.12, .appleOut)
            let alpha = t <= lift ? 1 : 1 - ramp(t, lift, lift + 0.25)
            guard alpha > 0.002 else { return }
            let w = max(1, diameter / 64)              // stroke scale: v3's 1.5 and 3 at a 64 px dot
            var c = ctx
            c.opacity = alpha
            let d = diameter * CGFloat(s)
            let dot = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
            if TouchDot.rimmed { c.fill(Path(ellipseIn: dot), with: .color(.black.opacity(0.12))) }
            c.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.18)))
            c.stroke(Path(ellipseIn: dot.insetBy(dx: 0.75 * w, dy: 0.75 * w)), with: .color(.white.opacity(0.45)), lineWidth: 1.5 * w)
            if TouchDot.rimmed { c.stroke(Path(ellipseIn: dot), with: .color(.black.opacity(0.30)), lineWidth: 1.5 * w) }
            let ringR = d / 2 + 4 * w
            let p = progress
            if p > 0 {
                var ring = Path()
                ring.addArc(center: center, radius: ringR, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * p), clockwise: false)
                c.stroke(ring, with: .color(Color(hex: Palette.accent)), style: StrokeStyle(lineWidth: 3 * w, lineCap: .round))
            }
            if popOnDone {
                let done = down + duration
                let q = ramp(t, done, done + 0.25)
                if q > 0 && q < 1 {
                    let rr = ringR * CGFloat(1 + 0.18 * CubicBezier.appleOut(q))
                    c.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: 2 * rr, height: 2 * rr)),
                             with: .color(Color(hex: Palette.accent, alpha: 0.7 * (1 - q))), lineWidth: 2 * w)
                }
            }
        }
        .canvas()
    }
}
