// Icon.swift — design/AppIcon.svg rebuilt as vector layers on the 1024 grid (§8.4). Drawn with a
// GraphicsContext at the target scale (so the S03 dolly stays sharp and layers stay canvas-sized);
// shadows are pre-blurred once at 1 px per unit and scaled.
import CoreImage
import SwiftUI

/// Per-layer animation state (S02's assembly).
struct IconLayerState {
    var opacity: Double = 1
    var scale: CGFloat = 1          // about the icon centre (512, 512)
    var dy: CGFloat = 0             // screen px
}

/// Maps icon units to the screen: X = anchorScreen + k · (P − anchorIcon).
struct IconCamera {
    var k: CGFloat
    var anchorIcon: CGPoint
    var anchorScreen: CGPoint
    static func resting(size: CGFloat = 560, centre: CGPoint = CGPoint(x: 960, y: 540)) -> IconCamera {
        IconCamera(k: size / 1024, anchorIcon: CGPoint(x: 512, y: 512), anchorScreen: centre)
    }
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: anchorScreen.x, y: anchorScreen.y).scaledBy(x: k, y: k)
            .translatedBy(x: -anchorIcon.x, y: -anchorIcon.y)
    }
    func screen(_ p: CGPoint) -> CGPoint { p.applying(transform) }
}

struct IconState {
    var camera = IconCamera.resting()
    var background = IconLayerState()
    var imac = IconLayerState()
    var ipad = IconLayerState()
    var window = IconLayerState()
    var imacGloss: Double = 1
    var screenOpacity: Double = 0.97
    /// S03: the iPad group's own camera (scales faster, leaves lower right), sampled at sub-frame times.
    var ipadCameras: [IconCamera]? = nil
    var opacity: Double = 1
}

final class IconShadows {
    static let shared = IconShadows()
    private(set) var imac: CGImage!
    private(set) var ipadSoft: CGImage!
    private(set) var ipadLift: CGImage!

    func build(ci: CIContext) {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        // Rendered 1024×1024 at 1 px per unit, y-down like the SVG. The iPad ones are unrotated.
        func render(_ draw: (CGContext) -> Void, sigma: Double) -> CGImage {
            let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1)
            draw(ctx)
            let img = CIImage(cgImage: ctx.makeImage()!)
            let out = img.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: img.extent)
            return ci.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: sRGB)!
        }
        func rr(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        }
        imac = render({ ctx in   // foot, neck, body at #000 30 %, dy 6, σ 8
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.3))
            rr(ctx, 372, 678, 280, 40, 20); ctx.fillPath()
            rr(ctx, 480, 636, 64, 50, 0); ctx.fillPath()
            rr(ctx, 176, 182, 672, 456, 60); ctx.fillPath()
        }, sigma: 8)
        ipadSoft = render({ ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.5)); rr(ctx, 326, 272, 388, 290, 48); ctx.fillPath()
        }, sigma: 26)
        ipadLift = render({ ctx in
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.35)); rr(ctx, 316, 250, 408, 300, 48); ctx.fillPath()
        }, sigma: 8)
    }
}

private func rrPath(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .circular)
}

private let greyGradient = Gradient(stops: [.init(color: Color(hex: 0x7C7E86, alpha: 0.98), location: 0),
                                            .init(color: Color(hex: 0x4C4E56, alpha: 0.96), location: 1)])
private let glossGradient = Gradient(stops: [
    .init(color: .white.opacity(0.6), location: 0), .init(color: .white.opacity(0.1), location: 0.4),
    .init(color: .white.opacity(0), location: 1)])

/// Fills `path` with an SVG objectBoundingBox gradient from (x1,y1) to (x2,y2) in bbox units.
private func fillBBox(_ ctx: inout GraphicsContext, _ path: Path, _ g: Gradient, _ from: CGPoint, _ to: CGPoint) {
    let box = path.boundingRect
    var c = ctx
    c.clip(to: path)
    c.concatenate(CGAffineTransform(translationX: box.minX, y: box.minY).scaledBy(x: box.width, y: box.height))
    c.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .linearGradient(g, startPoint: from, endPoint: to))
}

enum IconPart { case back, front, all }

/// One canvas-sized drawing of the icon (or part of it). `.back` = background + iMac, `.front` = iPad + window.
struct IconCanvas: View {
    let s: IconState
    let part: IconPart
    var size: CGSize = Stage.size

    var body: some View {
        Canvas { ctx, _ in
            if s.opacity < 0.999 {
                // Fade the whole icon as one layer, so inner opacities stay relative to it.
                ctx.opacity = s.opacity
                ctx.drawLayer { inner in drawAll(&inner) }
            } else {
                drawAll(&ctx)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func drawAll(_ ctx: inout GraphicsContext) {
            if part != .front {
                layer(&ctx, s.background, s.camera) { c in drawBackground(&c) }
                layer(&ctx, s.imac, s.camera) { c in drawIMac(&c) }
            }
            if part != .back {
                if let cams = s.ipadCameras, cams.count > 1 {
                    // Motion blur: the average of sub-frame renders (additive, each at 1/n).
                    ctx.drawLayer { acc in
                        for cam in cams {
                            var c = acc
                            c.opacity = 1 / Double(cams.count)
                            c.blendMode = .plusLighter
                            c.drawLayer { copy in drawFront(&copy, cam) }
                        }
                    }
                } else {
                    drawFront(&ctx, s.ipadCameras?.first ?? s.camera)
                }
            }
    }

    private func drawFront(_ ctx: inout GraphicsContext, _ cam: IconCamera) {
        // The iPad's gloss and stroke are drawn after the window (SVG order) but belong to the iPad's timing.
        layer(&ctx, s.ipad, cam) { c in drawIPadBody(&c) }
        layer(&ctx, s.window, cam) { c in drawWindow(&c) }
        layer(&ctx, s.ipad, cam) { c in drawIPadTop(&c) }
    }

    private func layer(_ ctx: inout GraphicsContext, _ l: IconLayerState, _ cam: IconCamera,
                       _ draw: @escaping (inout GraphicsContext) -> Void) {
        guard l.opacity > 0.001 else { return }
        var c = ctx
        c.opacity = l.opacity
        let m = cam.transform
        // Layer scale about the icon centre and a screen-space dy.
        let centre = CGPoint(x: 512, y: 512).applying(m)
        let t = CGAffineTransform(translationX: centre.x, y: centre.y + l.dy).scaledBy(x: l.scale, y: l.scale)
            .translatedBy(x: -centre.x, y: -centre.y)
        c.concatenate(m.concatenating(t))
        if l.opacity < 0.999 {
            c.drawLayer { inner in draw(&inner) }
        } else {
            draw(&c)
        }
    }

    private func drawBackground(_ c: inout GraphicsContext) {
        let sq = Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 229, style: .continuous)
        c.fill(sq, with: .linearGradient(Gradient(colors: [Color(hex: 0x1A1A1C), Color(hex: 0x000000)]),
                                         startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: 1024)))
    }

    private func drawIMac(_ c: inout GraphicsContext) {
        var c = c
        c.translateBy(x: 0, y: 56)
        c.draw(Image(decorative: IconShadows.shared.imac, scale: 1), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        for p in [rrPath(372, 672, 280, 40, 20), rrPath(480, 630, 64, 50, 0), rrPath(176, 176, 672, 456, 60)] {
            fillBBox(&c, p, greyGradient, CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        }
        c.fill(rrPath(204, 204, 616, 352, 36), with: .color(Color(hex: 0x07080A, alpha: s.screenOpacity)))
        if s.imacGloss > 0.001 {
            var g = c
            g.opacity = 0.5 * s.imacGloss
            fillBBox(&g, rrPath(176, 176, 672, 456, 60), glossGradient, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1))
            var st = c
            st.opacity = s.imacGloss
            st.stroke(rrPath(177.5, 177.5, 669, 453, 59), with: .color(.white.opacity(0.5)), lineWidth: 3)
        }
    }

    private func ipadSpace(_ c: inout GraphicsContext) {
        c.translateBy(x: 0, y: 56)
        c.translateBy(x: 520, y: 392)
        c.rotate(by: .degrees(-5))
        c.translateBy(x: -520, y: -392)
    }

    private func drawIPadBody(_ c: inout GraphicsContext) {
        var c = c
        ipadSpace(&c)
        c.draw(Image(decorative: IconShadows.shared.ipadSoft, scale: 1), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        c.draw(Image(decorative: IconShadows.shared.ipadLift, scale: 1), in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        c.fill(rrPath(316, 240, 408, 300, 48), with: .color(Color(hex: 0x2A2F3A)))
        c.fill(rrPath(342, 266, 356, 248, 28), with: .color(Color(hex: 0xF7F8FA)))
        // Frame review (2026-09-26), Noah's rule (no camera on any iPad or iPhone the reel draws): the icon's iPad
        // leaves the icon in S02–S03 and grows to device size (its dot showed at 5.0–5.8 s), so the reel draws it
        // without design/AppIcon.svg's camera dot (circle at 520, 253, r 5). At icon size it was 4–8 px across.
        // Undo: fill Path(ellipseIn: CGRect(x: 515, y: 248, width: 10, height: 10)) with 0x6B7079 here.
    }

    private func drawWindow(_ c: inout GraphicsContext) {
        var c = c
        ipadSpace(&c)
        c.fill(rrPath(368, 296, 304, 180, 20), with: .color(.white))
        c.fill(rrPath(368, 296, 304, 40, 20), with: .color(Color(hex: 0x9BB7FF)))
        c.fill(Path(CGRect(x: 368, y: 316, width: 304, height: 20)), with: .color(Color(hex: 0x9BB7FF)))
        for (i, a) in [0.7, 0.5, 0.35].enumerated() {
            c.fill(Path(ellipseIn: CGRect(x: 387 + 22 * CGFloat(i), y: 309, width: 14, height: 14)), with: .color(.white.opacity(a)))
        }
        c.fill(rrPath(394, 362, 150, 14, 7), with: .color(Color(hex: 0x5A5F6B, alpha: 0.9)))
        c.fill(rrPath(394, 392, 210, 14, 7), with: .color(Color(hex: 0x5A5F6B, alpha: 0.55)))
        c.fill(rrPath(394, 422, 110, 14, 7), with: .color(Color(hex: 0x5A5F6B, alpha: 0.55)))
    }

    private func drawIPadTop(_ c: inout GraphicsContext) {
        var c = c
        ipadSpace(&c)
        var g = c
        g.opacity = 0.8
        fillBBox(&g, rrPath(316, 240, 408, 300, 48), glossGradient, CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1))
        c.stroke(rrPath(317.5, 241.5, 405, 297, 47), with: .color(.white.opacity(0.85)), lineWidth: 3)
    }
}

// MARK: - The glint (S01, S34)

/// The iPad outline on screen: the stroke rect (317.5, 241.5, 405×297, r 47), rotated −5° about
/// (520, 392), translated +56 y; starts at the top-left corner and runs clockwise.
func glintPath(_ cam: IconCamera) -> Path {
    let r: CGFloat = 47
    let x0: CGFloat = 317.5, y0: CGFloat = 241.5, w: CGFloat = 405, h: CGFloat = 297
    var p = Path()
    // The top-left corner: begin on its arc's midpoint so the corner itself is where the glint starts.
    p.addArc(center: CGPoint(x: x0 + r, y: y0 + r), radius: r, startAngle: .degrees(225), endAngle: .degrees(270), clockwise: false)
    p.addLine(to: CGPoint(x: x0 + w - r, y: y0))
    p.addArc(center: CGPoint(x: x0 + w - r, y: y0 + r), radius: r, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
    p.addLine(to: CGPoint(x: x0 + w, y: y0 + h - r))
    p.addArc(center: CGPoint(x: x0 + w - r, y: y0 + h - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
    p.addLine(to: CGPoint(x: x0 + r, y: y0 + h))
    p.addArc(center: CGPoint(x: x0 + r, y: y0 + h - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
    p.addLine(to: CGPoint(x: x0, y: y0 + r))
    p.addArc(center: CGPoint(x: x0 + r, y: y0 + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(225), clockwise: false)
    let rot = CGAffineTransform(translationX: 520, y: 392).rotated(by: -5 * .pi / 180).translatedBy(x: -520, y: -392)
    let toScreen = rot.concatenating(CGAffineTransform(translationX: 0, y: 56)).concatenating(cam.transform)
    return p.applying(toScreen)
}

/// Head at the inOut-eased position (wrapping across 0/1), 22 % long: a 3 px white core and a 10 px
/// accent glow at 45 %. The passed path keeps white at 12 % for 0.4 s, then fades.
struct GlintView: View {
    let path: Path
    let t: Double
    let start: Double
    let duration: Double

    var body: some View {
        Canvas { ctx, _ in
            guard t >= start - 0.001 else { return }
            let u = clamp01((t - start) / duration)
            let head = CubicBezier.inOut(u)
            // Trail.
            let n = 180
            for i in 0..<n {
                let a = Double(i) / Double(n), b = Double(i + 1) / Double(n)
                let mid = (a + b) / 2
                guard mid <= head else { break }
                let age = t - (start + duration * inverseInOut(mid))
                let alpha = age <= 0.4 ? 0.12 : 0.12 * max(0, 1 - (age - 0.4) / 0.35)
                if alpha <= 0.002 { continue }
                ctx.stroke(path.trimmedPath(from: a, to: b), with: .color(.white.opacity(alpha)), lineWidth: 2)
            }
            // Head: visible while travelling; fades in over its first 0.1 s and out over 0.25 s after arriving.
            let alpha = clamp01((t - start) / 0.1) * (t > start + duration ? max(0, 1 - (t - start - duration) / 0.25) : 1)
            guard alpha > 0.002 else { return }
            let len = 0.22
            let tail = head - len
            var segs: [(Double, Double, Double)] = []      // (from, to, tail-relative start)
            if tail < 0 { segs = [(tail + 1, 1, 0), (0, head, -tail)] } else { segs = [(tail, head, 0)] }
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: 5))
                for (a, b, _) in segs where b > a {
                    glow.stroke(path.trimmedPath(from: a, to: b), with: .color(Color(hex: Palette.accent, alpha: 0.45 * alpha)),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                }
            }
            // Core, tapering from the tail (dim) to the head (full).
            for (a, b, rel0) in segs where b > a {
                let parts = max(2, Int((b - a) / len * 16))
                for j in 0..<parts {
                    let pa = a + (b - a) * Double(j) / Double(parts), pb = a + (b - a) * Double(j + 1) / Double(parts)
                    let along = (rel0 + (pa - a)) / len
                    ctx.stroke(path.trimmedPath(from: pa, to: pb),
                               with: .color(.white.opacity(alpha * (0.15 + 0.85 * along * along))),
                               style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                }
            }
        }
        .frame(width: Stage.size.width, height: Stage.size.height)
    }

    private func inverseInOut(_ s: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<32 {
            let m = (lo + hi) / 2
            if CubicBezier.inOut(m) < s { lo = m } else { hi = m }
        }
        return (lo + hi) / 2
    }
}
