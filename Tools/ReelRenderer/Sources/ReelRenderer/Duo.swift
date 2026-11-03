// Duo.swift — S31–S32: one more ending card, the iPhone Duo tease (Noah's note 17).
//
// A generic book-style foldable, drawn like the reel's other devices (never Apple artwork): two panels of
// 500×710 layout points, the sizes of the harness's outer (500×710) and inner (1000×710) Duo layouts. It
// settles closed onto the lockup's sill line with its outer display lit by the icon's window, unfolds (the
// cover swings open about the hinge, toward the lens), the inner display lights, a glint runs round it and
// the type snaps below the sill: "Designed for iPhone Duo." / "Both screens. Coming soon." Nothing claims
// that Sill runs on an iPhone Duo today (CLAUDE.md L3 "designed for iPhone Duo first"; BRIEF L9–10, L82).
import SwiftUI

enum Duo {
    static let k: CGFloat = 0.6                                      // px per layout point
    static let bezel: CGFloat = 14
    static let outerRadius: CGFloat = 46
    static let innerRadius: CGFloat = 32
    static let hingeRadius: CGFloat = 4
    static var panel: CGSize { CGSize(width: 500 * k, height: 710 * k) }                          // 300×426
    static var half: CGSize { CGSize(width: panel.width + bezel, height: panel.height + 2 * bezel) } // 314×454
    static let sillY: CGFloat = 666                                  // the lockup's sill line
    // Times (reel s).
    static let settle = 70.8, unfold = 71.4, unfoldDur = 0.8
    static let headSnap = 72.05, subSnap = 72.45, glint = 72.25
    static let fadeStart = 74.0
}

/// One half of the device. `freeRight`: the free (non-hinge) edge is on the right.
private func halfPath(_ size: CGSize, freeRight: Bool, inset: CGFloat = 0) -> Path {
    let r = max(0, Duo.outerRadius - inset), h = max(0, Duo.hingeRadius - inset)
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    return UnevenRoundedRectangle(topLeadingRadius: freeRight ? h : r, bottomLeadingRadius: freeRight ? h : r,
                                  bottomTrailingRadius: freeRight ? r : h, topTrailingRadius: freeRight ? r : h,
                                  style: .continuous).path(in: rect)
}

/// The icon's light window (§8.4 layer 4) as a screen glyph: body, accent title strip, three dots, three bars.
private func drawGlyph(_ ctx: inout GraphicsContext, center: CGPoint, width: CGFloat, light: Double) {
    guard light > 0.002 else { return }
    let s = width / 304
    let r = CGRect(x: center.x - 152 * s, y: center.y - 90 * s, width: 304 * s, height: 180 * s)
    ctx.drawLayer { g in
        g.addFilter(.blur(radius: 46 * s))
        g.fill(Path(roundedRect: r.insetBy(dx: -18 * s, dy: -18 * s), cornerRadius: 40 * s),
               with: .color(Color(hex: Palette.accent, alpha: 0.22 * light)))
    }
    var c = ctx
    c.opacity = light
    let body = Path(roundedRect: r, cornerRadius: 20 * s, style: .circular)
    c.fill(body, with: .color(.white))
    var cc = c
    cc.clip(to: body)
    cc.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: 40 * s)), with: .color(Color(hex: Palette.accent)))
    for (i, a) in [0.7, 0.5, 0.35].enumerated() {
        cc.fill(Path(ellipseIn: CGRect(x: r.minX + (19 + 22 * CGFloat(i)) * s, y: r.minY + 13 * s, width: 14 * s, height: 14 * s)),
                with: .color(.white.opacity(a)))
    }
    for (i, (w, a)) in [(150.0, 0.9), (210.0, 0.55), (110.0, 0.55)].enumerated() {
        cc.fill(Path(roundedRect: CGRect(x: r.minX + 26 * s, y: r.minY + (66 + 30 * CGFloat(i)) * s, width: CGFloat(w) * s, height: 14 * s),
                     cornerRadius: 7 * s, style: .circular), with: .color(Color(hex: Palette.winLightBars, alpha: a)))
    }
}

/// The inner display's picture in its own coordinates (both panels: 600×426 px): one window, centred.
private func drawInner(_ ctx: inout GraphicsContext, light: Double) {
    let w = 2 * Duo.panel.width, h = Duo.panel.height
    ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(hex: Palette.bg1)))
    drawGlyph(&ctx, center: CGPoint(x: w / 2, y: h / 2), width: 0.56 * w, light: light)
}

private let rim = LinearGradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)

/// A half seen from inside (the open device): `freeRight` true is the base (right half of the inner
/// display), false the cover (left half). The display runs to the hinge edge, so the halves meet at a seam.
private struct InnerHalf: View {
    let freeRight: Bool
    let light: Double
    var body: some View {
        let size = Duo.half
        Canvas { ctx, _ in
            let bodyPath = halfPath(size, freeRight: freeRight)
            ctx.fill(bodyPath, with: .color(Color(hex: Palette.deviceBody)))
            let b = Duo.bezel, pw = Duo.panel.width, ph = Duo.panel.height
            let display = CGRect(x: freeRight ? 0 : b, y: b, width: pw, height: ph)
            let ir = Duo.innerRadius
            let dPath = UnevenRoundedRectangle(topLeadingRadius: freeRight ? 0 : ir, bottomLeadingRadius: freeRight ? 0 : ir,
                                               bottomTrailingRadius: freeRight ? ir : 0, topTrailingRadius: freeRight ? ir : 0,
                                               style: .continuous).path(in: display)
            var c = ctx
            c.clip(to: dPath)
            c.translateBy(x: display.minX - (freeRight ? pw : 0), y: display.minY)
            drawInner(&c, light: light)
            // The fold: a faint crease where the halves meet.
            let seamX = freeRight ? 0.5 : size.width - 0.5
            ctx.stroke(Path { p in p.move(to: CGPoint(x: seamX, y: b)); p.addLine(to: CGPoint(x: seamX, y: b + ph)) },
                       with: .color(.white.opacity(0.05 * light)), lineWidth: 1)
            ctx.stroke(bodyPath, with: .linearGradient(Gradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)]),
                                                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The cover seen from outside (the closed device): its outer display, inset on all sides. v3: no camera dot
/// (Noah, 2026-09-26: plain bezels on every device).
private struct OuterFace: View {
    let light: Double
    var body: some View {
        let size = Duo.half
        Canvas { ctx, _ in
            let bodyPath = halfPath(size, freeRight: true)
            ctx.fill(bodyPath, with: .color(Color(hex: Palette.deviceBody)))
            let b = Duo.bezel
            let display = CGRect(x: b, y: b, width: size.width - 2 * b, height: size.height - 2 * b)
            let dPath = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10,
                                               bottomTrailingRadius: Duo.innerRadius, topTrailingRadius: Duo.innerRadius,
                                               style: .continuous).path(in: display)
            ctx.fill(dPath, with: .color(Color(hex: Palette.bg1)))
            var c = ctx
            c.clip(to: dPath)
            drawGlyph(&c, center: CGPoint(x: display.midX, y: display.midY), width: 0.72 * display.width, light: light)
            ctx.stroke(bodyPath, with: .linearGradient(Gradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)]),
                                                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The device in a local frame of 2·W × H with the hinge at x = W. `open` 0 (closed, the cover lying over the
/// base on the right) … 1 (flat, the cover on the left).
struct DuoDevice: View {
    let open: Double
    let outerLight: Double
    let innerLight: Double
    var body: some View {
        let W = Duo.half.width, H = Duo.half.height
        let theta = 180 * open
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: 2 * W, height: H)
            InnerHalf(freeRight: true, light: innerLight).offset(x: W)
            Group {
                if theta < 90 {
                    OuterFace(light: outerLight)
                } else {
                    // Past 90° the back of the cover faces the lens: draw its inner face pre-mirrored so the
                    // rotation reads it the right way round.
                    InnerHalf(freeRight: false, light: innerLight).scaleEffect(x: -1, y: 1)
                }
            }
            .frame(width: W, height: H)
            // The free edge comes toward the lens and swings left about the hinge (Stacks.swift: a negative
            // angle brings a view's right side toward the lens).
            .rotation3DEffect(.degrees(-theta), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.3)
            .offset(x: W)
        }
        .frame(width: 2 * W, height: H, alignment: .topLeading)
    }
}

/// The open device's outline on screen, from its top-left corner, clockwise (for the glint).
private func duoOutline(hingeX: CGFloat, bottom: CGFloat) -> Path {
    let W = Duo.half.width, H = Duo.half.height
    let rect = CGRect(x: hingeX - W, y: bottom - H, width: 2 * W, height: H)
    let r = Duo.outerRadius
    var p = Path()
    p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(225), endAngle: .degrees(270), clockwise: false)
    p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(225), clockwise: false)
    return p
}

/// S31–S32's card: the device on the sill line, its glow and glint, the two lines below the sill.
struct DuoCard: View {
    let t: Double
    var body: some View {
        let W = Duo.half.width, H = Duo.half.height
        let settle = ease(t, Duo.settle, 0.6, .appleOut)
        let appear = ramp(t, Duo.settle, Duo.settle + 0.25)
        let open = CubicBezier.inOut(ramp(t, Duo.unfold, Duo.unfold + Duo.unfoldDur))
        let fade = 1 - CubicBezier.inOut(ramp(t, Duo.fadeStart, Duo.fadeStart + 0.6))
        // The hinge moves right as the cover opens, so the device stays centred on x 960 throughout.
        let hingeX = 960 - W / 2 * CGFloat(1 - open)
        let bottom = Duo.sillY - 30 * CGFloat(1 - settle)
        let outerLight = ease(t, Duo.settle + 0.25, 0.35, .appleOut)
        let innerLight = CubicBezier.inOut(ramp(open, 0.45, 1.0))
        let lines = [LineSpec(Copy.duo, .T1s, baseline: 830, snap: Duo.headSnap, holdEnd: Duo.fadeStart),
                     LineSpec(Copy.duoSub, .T2, baseline: 900, snap: Duo.subSnap, holdEnd: Duo.fadeStart)]
        return ZStack(alignment: .topLeading) {
            Color.clear.canvas()
            if appear > 0 {
                Glow(center: CGPoint(x: 960, y: Duo.sillY - H / 2), opacity: 0.06 * appear)
                DuoDevice(open: open, outerLight: outerLight, innerLight: innerLight)
                    .opacity(appear)
                    .position(x: hingeX, y: bottom - H / 2)
                    .frame(width: Stage.size.width, height: Stage.size.height)
                GlintView(path: duoOutline(hingeX: 960, bottom: Duo.sillY), t: t, start: Duo.glint, duration: 0.9)
                TypeLayer(lines: lines, t: t)
            }
        }
        .canvas()
        .opacity(fade)
    }
}
