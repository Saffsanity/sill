// Assets060Marks.swift — the marks of Noah's notes on v4.2 (2026-11-02): the "Download on the App Store" badge, the GitHub
// mark and the Homebrew logo for the end card (S22, 1:13: "Add the Download on the App Store icon and the GitHub logo and
// Homebrew logo and make it look aesthetic"), and a glyph in the style of the Intel Inside badge for S18's iMac (1:00:
// "Reveal a glyph of the Intel Inside logo on the Mac as you pan the light across it").
//
// The reel draws its own artwork (README, "The rules every cut keeps"); a mark is its owner's, so these keep the owners' forms:
// - The App Store badge is drawn here from the geometry of Apple's US English badge (119.66407 × 40 units; a 0.875-unit
//   #A6A6A6 border; continuous corners; the Apple logo from the cap top of "Download on the" to the baseline of "App
//   Store", its left 9.972 in; the words in SF Pro Medium, their ink lefts, cap heights and baselines Apple's), with the
//   Apple logo as SF Pro's own glyph (U+F8FF: the drawing of the SF Symbol apple.logo) and the words as SF Pro's outlines,
//   fitted to Apple's artwork in this repository (site/app-store-badge.svg): every letter within 0.23 px of it on a 44 px
//   badge. No artwork downloaded. Apple's App Store marketing guidelines ask for the artwork Apple provides and forbid
//   modifying, angling or animating the badge: `AppStoreBadge.artwork(_:)` draws that file itself, in vector.
// - The GitHub mark is primer/octicons' icons/mark-github-24.svg (MIT, © GitHub Inc.; commit ea8e6bb7 of 2026-03-18), its
//   path data verbatim, filled in one colour (GitHub's logo rules: unaltered, black or white).
// - The Homebrew logo is Homebrew/brew.sh's assets/img/homebrew.svg (BSD-2-Clause, © Homebrew contributors; commit 7dad89c2
//   of 2025-09-04), its paths, colours, strokes and painting order verbatim.
// - The Intel glyph is an evocation of the Intel Inside badge (a rounded square, "intel" over "inside", in SF Pro), drawn
//   here: not Intel's artwork, which Intel licenses through its Intel Inside program, and not its letterforms.
//
// Every mark draws in vector into a y-down CGContext (the renderer's canvases, or a GraphicsContext's withCGContext), its
// box's top-left at a point and its box `height` px tall, so the card's +1.2 % hold and S18's push keep it sharp and a
// moving edge lands between pixels; `image(…)` makes a CGImage with alpha at a scale (the PNGs are at 2×). AppKit, Core Text
// and Core Graphics only; every name is inside `Marks060`, so nothing here meets the module's other names.
import AppKit
import CoreText

enum Marks060 {
    // MARK: - Helpers (y-down, as the renderer's canvases)

    /// An sRGB colour from 0xRRGGBB, Palette's form.
    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// An image of `size` pt at `scale` px a point, with alpha, drawn by `draw` into a y-down sRGB context whose origin is
    /// the image's top-left and whose unit is a point (its pixel size `size × scale`, rounded up).
    static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * scale - 1e-6).rounded(.up))), h = max(1, Int((size.height * scale - 1e-6).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()!
    }

    /// A rounded rect with continuous corners (UIKit's and SwiftUI's `.continuous`: each corner three cubics reaching
    /// 1.52866 × `radius` along its edges), clockwise from its top edge in a y-down space.
    static func continuousRect(_ r: CGRect, radius: CGFloat) -> CGPath {
        let reach: CGFloat = 1.52866483
        let c = max(0, min(radius, min(r.width, r.height) / 2 / reach))
        let p = CGMutablePath()
        // One corner from the incoming edge to the outgoing one: canonical points (u along the outgoing edge, v back along
        // the incoming one) in units of c.
        let segments: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: 1.08849323), CGPoint(x: 0.02215976, y: 0.86840701), CGPoint(x: 0.07491100, y: 0.63149376)),
            (CGPoint(x: 0.16905899, y: 0.37282391), CGPoint(x: 0.37282392, y: 0.16905899), CGPoint(x: 0.63149379, y: 0.07491100)),
            (CGPoint(x: 0.86840701, y: 0.02215976), CGPoint(x: 1.08849323, y: 0), CGPoint(x: reach, y: 0))]
        func corner(_ at: CGPoint, out ex: CGVector, back ey: CGVector) {
            func m(_ q: CGPoint) -> CGPoint { CGPoint(x: at.x + c * (q.x * ex.dx + q.y * ey.dx), y: at.y + c * (q.x * ex.dy + q.y * ey.dy)) }
            for (c1, c2, e) in segments { p.addCurve(to: m(e), control1: m(c1), control2: m(c2)) }
        }
        p.move(to: CGPoint(x: r.minX + reach * c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - reach * c, y: r.minY))
        corner(CGPoint(x: r.maxX, y: r.minY), out: CGVector(dx: 0, dy: 1), back: CGVector(dx: -1, dy: 0))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - reach * c))
        corner(CGPoint(x: r.maxX, y: r.maxY), out: CGVector(dx: -1, dy: 0), back: CGVector(dx: 0, dy: -1))
        p.addLine(to: CGPoint(x: r.minX + reach * c, y: r.maxY))
        corner(CGPoint(x: r.minX, y: r.maxY), out: CGVector(dx: 0, dy: -1), back: CGVector(dx: 1, dy: 0))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + reach * c))
        corner(CGPoint(x: r.minX, y: r.minY), out: CGVector(dx: 1, dy: 0), back: CGVector(dx: 0, dy: 1))
        p.closeSubpath()
        return p
    }

    /// `s`'s glyph outlines in a y-down space, its baseline at y 0 and its pen at x 0 (Core Text's layout, each run in its
    /// own font), as GlyphText.swift lays a line out (without its stem smoothing: these are marks, not the reel's type).
    static func textOutline(_ s: String, font: NSFont, kern: CGFloat = 0) -> CGPath {
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if kern != 0 { attrs[.kern] = kern }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let out = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let runAttrs = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
            let runFont: CTFont = (runAttrs[.font] as? NSFont).map { $0 as CTFont } ?? (font as CTFont)
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<n {
                guard let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil), !g.isEmpty else { continue }
                out.addPath(g, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: -positions[i].y))
            }
        }
        return out
    }

    // MARK: - SVG path data

    /// SVG path data read into a CGPath in the SVG's own user space (y down): M L H V C S Q T A Z, absolute and relative,
    /// implicit repeats, numbers run together ("1.123.404", "-.36", "1e-3") and arcs' flags run together ("0 01").
    enum SVG {
        static func path(_ d: String) -> CGPath {
            var r = Reader(Array(d.utf8))
            let p = CGMutablePath()
            var cur = CGPoint.zero, start = CGPoint.zero
            var lastCubic: CGPoint? = nil, lastQuad: CGPoint? = nil
            var cmd: UInt8 = 0
            while true {
                if let c = r.command() { cmd = c } else if !r.hasNumber() || cmd == 0 || cmd == 0x5A || cmd == 0x7A { break }
                let rel = cmd >= 0x61
                let o = rel ? cur : .zero
                var nextCubic: CGPoint? = nil, nextQuad: CGPoint? = nil
                switch cmd | 0x20 {
                case 0x6D: // m
                    let x = r.number(), y = r.number()
                    cur = CGPoint(x: o.x + x, y: o.y + y); p.move(to: cur); start = cur
                    cmd = rel ? 0x6C : 0x4C    // further pairs are lines
                case 0x6C: // l
                    let x = r.number(), y = r.number()
                    cur = CGPoint(x: o.x + x, y: o.y + y); p.addLine(to: cur)
                case 0x68: // h
                    let x = r.number()
                    cur = CGPoint(x: (rel ? cur.x : 0) + x, y: cur.y); p.addLine(to: cur)
                case 0x76: // v
                    let y = r.number()
                    cur = CGPoint(x: cur.x, y: (rel ? cur.y : 0) + y); p.addLine(to: cur)
                case 0x63: // c
                    let x1 = r.number(), y1 = r.number(), x2 = r.number(), y2 = r.number(), x = r.number(), y = r.number()
                    let c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                    cur = CGPoint(x: o.x + x, y: o.y + y)
                    p.addCurve(to: cur, control1: CGPoint(x: o.x + x1, y: o.y + y1), control2: c2); nextCubic = c2
                case 0x73: // s
                    let x2 = r.number(), y2 = r.number(), x = r.number(), y = r.number()
                    let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                    let c2 = CGPoint(x: o.x + x2, y: o.y + y2)
                    cur = CGPoint(x: o.x + x, y: o.y + y)
                    p.addCurve(to: cur, control1: c1, control2: c2); nextCubic = c2
                case 0x71: // q
                    let x1 = r.number(), y1 = r.number(), x = r.number(), y = r.number()
                    let q = CGPoint(x: o.x + x1, y: o.y + y1)
                    cur = CGPoint(x: o.x + x, y: o.y + y)
                    p.addQuadCurve(to: cur, control: q); nextQuad = q
                case 0x74: // t
                    let x = r.number(), y = r.number()
                    let q = lastQuad.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                    cur = CGPoint(x: o.x + x, y: o.y + y)
                    p.addQuadCurve(to: cur, control: q); nextQuad = q
                case 0x61: // a
                    let rx = r.number(), ry = r.number(), rot = r.number(), large = r.flag(), sweep = r.flag()
                    let x = r.number(), y = r.number()
                    let end = CGPoint(x: o.x + x, y: o.y + y)
                    arc(p, from: cur, to: end, rx: rx, ry: ry, degrees: rot, large: large, sweep: sweep)
                    cur = end
                case 0x7A: // z
                    p.closeSubpath(); cur = start
                default:
                    return p
                }
                lastCubic = nextCubic; lastQuad = nextQuad
            }
            return p
        }

        /// An SVG elliptical arc (endpoint form) as cubics of at most 90°, by the SVG specification's conversion to the
        /// centre form (F.6.5–F.6.6), radii scaled up when too small.
        static func arc(_ p: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx: CGFloat, ry: CGFloat, degrees: CGFloat,
                        large: Bool, sweep: Bool) {
            if p0 == p1 { return }
            var rx = abs(rx), ry = abs(ry)
            if rx == 0 || ry == 0 { p.addLine(to: p1); return }
            let phi = degrees * .pi / 180, cp = cos(phi), sp = sin(phi)
            let hx = (p0.x - p1.x) / 2, hy = (p0.y - p1.y) / 2
            let x1 = cp * hx + sp * hy, y1 = -sp * hx + cp * hy
            let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
            if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
            let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
            var f = den > 0 ? max(0, num / den).squareRoot() : 0
            if large == sweep { f = -f }
            let cxp = f * rx * y1 / ry, cyp = -f * ry * x1 / rx
            let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2, cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2
            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat { atan2(ux * vy - uy * vx, ux * vx + uy * vy) }
            let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry, vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
            let theta = angle(1, 0, ux, uy)
            var delta = angle(ux, uy, vx, vy)
            if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
            let n = max(1, Int((abs(delta) / (.pi / 2) - 1e-9).rounded(.up)))
            let step = delta / CGFloat(n), k = 4 / 3 * tan(step / 4)
            func m(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + rx * x * cp - ry * y * sp, y: cy + rx * x * sp + ry * y * cp) }
            var t = theta
            for i in 0..<n {
                let c0 = cos(t), s0 = sin(t), c1 = cos(t + step), s1 = sin(t + step)
                p.addCurve(to: i == n - 1 ? p1 : m(c1, s1), control1: m(c0 - k * s0, s0 + k * c0), control2: m(c1 + k * s1, s1 - k * c1))
                t += step
            }
        }

        struct Reader {
            let s: [UInt8]
            var i = 0
            init(_ s: [UInt8]) { self.s = s }
            static let commands = Set("MmZzLlHhVvCcSsQqTtAa".utf8)
            mutating func skip() { while i < s.count, s[i] == 0x20 || s[i] == 0x2C || s[i] == 0x09 || s[i] == 0x0A || s[i] == 0x0D || s[i] == 0x0C { i += 1 } }
            mutating func command() -> UInt8? {
                skip()
                guard i < s.count, Reader.commands.contains(s[i]) else { return nil }
                i += 1
                return s[i - 1]
            }
            mutating func hasNumber() -> Bool {
                skip()
                guard i < s.count else { return false }
                let c = s[i]
                return (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E
            }
            mutating func number() -> CGFloat {
                skip()
                let from = i
                if i < s.count, s[i] == 0x2B || s[i] == 0x2D { i += 1 }
                var dot = false
                while i < s.count {
                    if s[i] >= 0x30 && s[i] <= 0x39 { i += 1 } else if s[i] == 0x2E && !dot { dot = true; i += 1 } else { break }
                }
                if i < s.count, s[i] == 0x65 || s[i] == 0x45 {
                    var j = i + 1
                    if j < s.count, s[j] == 0x2B || s[j] == 0x2D { j += 1 }
                    if j < s.count, s[j] >= 0x30 && s[j] <= 0x39 {
                        i = j
                        while i < s.count, s[i] >= 0x30 && s[i] <= 0x39 { i += 1 }
                    }
                }
                return CGFloat(Double(String(decoding: s[from..<i], as: UTF8.self)) ?? 0)
            }
            mutating func flag() -> Bool {
                skip()
                guard i < s.count else { return false }
                i += 1
                return s[i - 1] == 0x31
            }
        }
    }
}

// MARK: - The App Store badge

extension Marks060 {
    enum AppStoreBadge {
        enum Style { case black, white }
        /// Apple's badge in its own units (the US English artwork's 119.66407 × 40), and its parts there.
        static let size = CGSize(width: 119.66407, height: 40)
        static let border: CGFloat = 0.875, borderColor: UInt32 = 0xA6A6A6
        /// Continuous corners of radius 6.8 (the inner face's 5.925), the radius that fits the artwork's corners best: 2.5 units²
        /// off over all four outer corners, 1.8 over the face's.
        static let radius: CGFloat = 6.8
        /// The Apple logo: from the top of "Download on the"'s capitals (8.72, the leaf's tip) to the baseline of "App Store"
        /// (30.496), its ink's left 9.972 in, as the artwork's.
        static let logoBox = (left: CGFloat(9.972), top: CGFloat(8.72), height: CGFloat(21.776))
        /// The words: SF Pro Medium (stem 0.1506 of the cap height; Apple's 0.149–0.150), each set at the optical size whose
        /// width is Apple's (Text at 10 pt for the small line, Display at 72 pt for "App Store"), scaled to Apple's cap heights,
        /// with a kern (pt at that size) fitted to Apple's letters: every letter's left and right within 0.056 units of the
        /// artwork's in the small line and 0.131 in "App Store" (0.06 and 0.14 px on a 44 px badge).
        static let small = (text: "Download on the", setAt: CGFloat(10), cap: CGFloat(5.967), inkLeft: CGFloat(35.671), baseline: CGFloat(14.698), kern: CGFloat(0.029))
        static let large = (text: "App Store", setAt: CGFloat(72), cap: CGFloat(12.418), inkLeft: CGFloat(34.427), baseline: CGFloat(30.496), kern: CGFloat(-0.02))

        static func width(height: CGFloat) -> CGFloat { size.width * height / size.height }
        /// Apple's minimum clear space round the badge: a quarter of its height.
        static func clearSpace(height: CGFloat) -> CGFloat { height / 4 }

        /// The Apple logo in badge units (SF Pro's U+F8FF), or nil where the system font has no such glyph.
        static let logo: CGPath? = {
            let f = NSFont.systemFont(ofSize: 100, weight: .regular) as CTFont
            var ch: [UniChar] = [0xF8FF], g: [CGGlyph] = [0]
            guard CTFontGetGlyphsForCharacters(f, &ch, &g, 1), g[0] != 0, let glyph = CTFontCreatePathForGlyph(f, g[0], nil),
                  !glyph.isEmpty else { return nil }
            let b = glyph.boundingBoxOfPath                      // glyph space, y up
            let k = logoBox.height / b.height
            var t = CGAffineTransform(a: k, b: 0, c: 0, d: -k, tx: logoBox.left - k * b.minX, ty: logoBox.top + k * b.maxY)
            return glyph.copy(using: &t)
        }()

        /// The two lines in badge units.
        static let words: CGPath = {
            let p = CGMutablePath()
            for w in [small, large] {
                let f = NSFont.systemFont(ofSize: w.setAt, weight: .medium)
                let k = w.cap / f.capHeight
                let o = Marks060.textOutline(w.text, font: f, kern: w.kern)
                let b = o.boundingBoxOfPath
                p.addPath(o, transform: CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: w.inkLeft - k * b.minX, ty: w.baseline))
            }
            return p
        }()

        /// The badge `height` px tall, its top-left at `origin`: the grey border, the black (or white) face, the Apple logo
        /// and the words in white (or black).
        static func draw(_ ctx: CGContext, at origin: CGPoint, height: CGFloat, style: Style = .black, opacity: CGFloat = 1) {
            let k = height / size.height
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: k, y: k)
            if opacity < 1 { ctx.setAlpha(opacity); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
            let whole = CGRect(origin: .zero, size: size)
            ctx.addPath(Marks060.continuousRect(whole, radius: radius))
            ctx.setFillColor(Marks060.color(borderColor))
            ctx.fillPath()
            ctx.addPath(Marks060.continuousRect(whole.insetBy(dx: border, dy: border), radius: radius - border))
            ctx.setFillColor(Marks060.color(style == .black ? 0x000000 : 0xFFFFFF))
            ctx.fillPath()
            let ink = Marks060.color(style == .black ? 0xFFFFFF : 0x000000)
            ctx.setFillColor(ink)
            if let logo { ctx.addPath(logo); ctx.fillPath() } else { drawLogoSymbol(ctx, ink: ink) }
            ctx.addPath(words)
            ctx.fillPath()
            if opacity < 1 { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }

        /// Where the system font has no U+F8FF: the SF Symbol apple.logo itself, in the logo's box (its image's own margins
        /// make it a little smaller there).
        private static func drawLogoSymbol(_ ctx: CGContext, ink: CGColor) {
            let box = CGRect(x: logoBox.left, y: logoBox.top, width: logoBox.height * 0.813, height: logoBox.height)
            let config = NSImage.SymbolConfiguration(pointSize: 100, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: ink) ?? .white]))
            guard let sym = NSImage(systemSymbolName: "apple.logo", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            sym.draw(in: box)
            NSGraphicsContext.restoreGraphicsState()
        }

        static func image(height: CGFloat, style: Style = .black, scale: CGFloat = 2) -> CGImage {
            Marks060.image(size: CGSize(width: width(height: height), height: height), scale: scale) { draw($0, at: .zero, height: height, style: style) }
        }

        /// Apple's own artwork, for the letter of its rule ("Use only the badge artwork provided"): the repository's
        /// site/app-store-badge.svg (Apple's US English black badge, 119.66407 × 40, the site's since e4ffc4ba) read as vector
        /// paths with their fills, in order; nil if the file is missing or has no paths. The artwork's groups carry no
        /// transforms. The drawn badge above lies within 0.23 px of it on a 44 px badge (assets/marks/README.md).
        static func artwork(_ url: URL) -> [(path: CGPath, fill: CGColor)]? {
            guard let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var out: [(path: CGPath, fill: CGColor)] = []
            var rest = s[...]
            while let open = rest.range(of: "<path") {
                let tail = rest[open.upperBound...]
                guard let close = tail.range(of: ">") else { break }
                let tag = tail[..<close.lowerBound]
                if let d = tag.range(of: " d=\"") {
                    var hex = "000000"
                    if let f = tag.range(of: "fill:") {
                        hex = String(tag[f.upperBound...].drop(while: { $0 == " " || $0 == "#" }).prefix(while: { $0.isHexDigit }))
                        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
                    }
                    out.append((SVG.path(String(tag[d.upperBound...].prefix(while: { $0 != "\"" }))), Marks060.color(UInt32(hex, radix: 16) ?? 0)))
                }
                rest = tail[close.upperBound...]
            }
            return out.isEmpty ? nil : out
        }

        /// That artwork `height` px tall, its top-left at `origin`.
        static func drawArtwork(_ ctx: CGContext, _ art: [(path: CGPath, fill: CGColor)], at origin: CGPoint, height: CGFloat, opacity: CGFloat = 1) {
            let k = height / size.height
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: k, y: k)
            if opacity < 1 { ctx.setAlpha(opacity); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
            for part in art { ctx.addPath(part.path); ctx.setFillColor(part.fill); ctx.fillPath(using: .winding) }
            if opacity < 1 { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }
    }
}

// MARK: - The GitHub mark

extension Marks060 {
    enum GitHubMark {
        /// primer/octicons, icons/mark-github-24.svg (viewBox 0 0 24 24, MIT), verbatim.
        static let d = "M10.226 17.284c-2.965-.36-5.054-2.493-5.054-5.256 0-1.123.404-2.336 1.078-3.144-.292-.741-.247-2.314.09-2.965.898-.112 2.111.36 2.83 1.01.853-.269 1.752-.404 2.853-.404 1.1 0 1.999.135 2.807.382.696-.629 1.932-1.1 2.83-.988.315.606.36 2.179.067 2.942.72.854 1.101 2 1.101 3.167 0 2.763-2.089 4.852-5.098 5.234.763.494 1.28 1.572 1.28 2.807v2.336c0 .674.561 1.056 1.235.786 4.066-1.55 7.255-5.615 7.255-10.646C23.5 6.188 18.334 1 11.978 1 5.62 1 .5 6.188.5 12.545c0 4.986 3.167 9.12 7.435 10.669.606.225 1.19-.18 1.19-.786V20.63a2.9 2.9 0 0 1-1.078.224c-1.483 0-2.359-.808-2.987-2.313-.247-.607-.517-.966-1.034-1.033-.27-.023-.359-.135-.359-.27 0-.27.45-.471.898-.471.652 0 1.213.404 1.797 1.235.45.651.921.943 1.483.943.561 0 .92-.202 1.437-.719.382-.381.674-.718.944-.943"
        static let path: CGPath = SVG.path(d)
        /// Its ink in the icon's units (the box `height` measures): x 0.5–23.5, y 1.0–23.28 (the path's exact bounds; its foot
        /// is open, so it is 23 wide and 22.28 tall).
        static let ink: CGRect = path.boundingBoxOfPath

        static func width(height: CGFloat) -> CGFloat { ink.width * height / ink.height }

        /// The mark's ink `height` px tall, its top-left at `origin`, in `color` (white on the stage: GitHub's rules allow white
        /// or black, and in a few cases grey or green, unaltered and with no effects).
        static func draw(_ ctx: CGContext, at origin: CGPoint, height: CGFloat, color: CGColor) {
            let k = height / ink.height
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -ink.minX, y: -ink.minY)
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }

        static func image(height: CGFloat, color: CGColor = Marks060.color(0xFFFFFF), scale: CGFloat = 2) -> CGImage {
            Marks060.image(size: CGSize(width: width(height: height), height: height), scale: scale) { draw($0, at: .zero, height: height, color: color) }
        }
    }
}

// MARK: - The Homebrew logo

extension Marks060 {
    enum Homebrew {
        /// `.color`: its own colours (its black outlines vanish on the black stage, where they part its shapes); `.white`: one
        /// colour, the outlines cut out of it; `.silhouette`: one colour, outlines and all.
        enum Style { case color, white, silhouette }
        struct Part {
            let d: String
            let fill: UInt32?
            let stroke: UInt32?
            var width: CGFloat = 4.79
            var cap: CGLineCap = .butt
            var join: CGLineJoin = .round
            var evenOdd = true
            var transform: CGAffineTransform = .identity
        }
        /// brew.sh, assets/img/homebrew.svg (viewBox 0 0 180 271; fill-rule evenodd, stroke-linejoin round), in its painting
        /// order: the hop leaf, the hop cone and the glass (the outlined group), the beer, its highlight, the foam.
        static let parts: [Part] = [
            Part(d: "m74.54 50.33c.74-23.487-7.172-37.334-29.917-46.481-6.465 22.614 20.225 43.465 29.917 46.481z", fill: 0xD1D3D4, stroke: 0x000000),
            Part(d: "m136.223 90.134c.74-19.286-4.131-27.07-7.787-32.636-3.709-5.192-12.609-13.352-23.544-13.694-10.341-.324-12.828 5.392-22.368 5.737-1.564-17.372 11.547-26.905 11.547-26.905s-3.585-5.067-6.551-6.305c-4.266 3.791-16.008 16.436-13.291 32.708-8.778-1.678-14.974-6.702-24.195-4.888-12.562 2.472-22.917 10.067-28.819 26.733-5.901 16.667 2.083 36.111 3.819 41.664 1.737 5.558 14.584 29.164 24.653 32.638 10.067 3.475 10.07 1.909 15.452-.173 5.383-2.083 13.54-5.902 25.522-1.561 11.975 4.339 13.537 5.379 21 .519 7.469-4.859 17.188-19.962 19.443-24.303 2.257-4.339 3.473-6.597 4.17-8.853 7.256-3.621.283-3.397.949-20.681z", fill: 0xD1D3D4, stroke: 0x000000),
            Part(d: "m155.714 231.084a18 18 0 0 0 18.064-17.998c.002-18.273.002-46.51.002-64.833a18 18 0 0 0 -18-18h-14.838a4 4 0 0 1 -4-4v-9.43h-117.03l.295 138.213a4.001 4.001 0 0 0 1.85 3.365c5.212 3.018 21.921 8.75 57.004 8.75 35.825 0 51.839-7.674 56.424-11.139a3.979 3.979 0 0 0 1.438-3.062c.019-3.825.019-12.688.019-17.924a3.999 3.999 0 0 1 4.083-3.999c4.401.062 9.674.071 14.689.057zm-18.772-79.806c0-1.326.527-2.598 1.464-3.536a5.004 5.004 0 0 1 3.536-1.464h12.738c1.326 0 2.598.527 3.536 1.464a5.004 5.004 0 0 1 1.464 3.536v58.185a5.004 5.004 0 0 1 -1.464 3.536 5.004 5.004 0 0 1 -3.536 1.464h-12.738a5.004 5.004 0 0 1 -3.536-1.464 5.004 5.004 0 0 1 -1.464-3.536z", fill: 0xFFFFFF, stroke: 0x000000, evenOdd: false),
            Part(d: "m31.449 115.663v123.986c0 1.431.764 2.753 2.003 3.467 5.061 2.412 19.743 8.169 45.484 8.169 25.912 0 40.158-6.995 44.928-9.878a3.987 3.987 0 0 0 1.827-3.351c.011-16.441.011-122.393.011-122.393z", fill: 0xFBB040, stroke: nil),
            Part(d: "m35.521.249v112.816", fill: nil, stroke: 0xFFDB96, width: 11.96, cap: .round, join: .miter,
                 transform: CGAffineTransform(a: 1, b: 0, c: 0, d: 0.84931, tx: 9.782, ty: 136.452)),
            Part(d: "m98.555 141.106c0-2-1.177-4.388-3.11-5.587a16.734 16.734 0 0 1 -6.942-8.3c-25.591.861-48.949-3.633-60.716-6.806a98.218 98.218 0 0 0 -9.171-2.13c-7.043-1.397-12.396-7.582-12.396-15.018 0-8.185 6.494-14.836 14.608-15.127 1.565-8.657 9.121-15.229 18.229-15.229 10.242 0 18.544 8.304 18.544 18.545 0 2.155-.389 4.218-1.064 6.144l.055.009c2.287-7.153 8.983-12.336 16.896-12.336 7.862 0 14.522 5.122 16.848 12.208a18.673 18.673 0 0 1 -.101-1.947c0-10.652 8.634-19.286 19.284-19.286 8.622 0 15.919 5.659 18.388 13.462l1.681-.438a15.083 15.083 0 0 1 7.432-1.955c8.369 0 15.154 6.785 15.151 15.152 0 7.666-5.691 14.001-13.079 15.012a22.339 22.339 0 0 0 -4.891 1.27c-4.391 1.655-8.881 3.027-13.417 4.159a16.66 16.66 0 0 1 -1.909 6.231 20.723 20.723 0 0 0 -2.38 11.257c-.002.236.007 1.472.007 1.71 0 4.956-4.016 7.972-8.976 7.972a8.971 8.971 0 0 1 -8.971-8.972z", fill: 0xFFFFFF, stroke: 0x000000, cap: .round)]
        static let viewBox = CGSize(width: 180, height: 271)
        static let paths: [CGPath] = parts.map { SVG.path($0.d) }
        /// The logo's ink in its own units: every fill, and every stroke's outline, its own transform applied.
        static let ink: CGRect = {
            var box = CGRect.null
            for (part, path) in zip(parts, paths) {
                var t = part.transform
                if part.fill != nil, let f = path.copy(using: &t) { box = box.union(f.boundingBoxOfPath) }
                if part.stroke != nil {
                    let s = path.copy(strokingWithWidth: part.width, lineCap: part.cap, lineJoin: part.join, miterLimit: 4, transform: t)
                    box = box.union(s.boundingBoxOfPath)
                }
            }
            return box
        }()

        static func width(height: CGFloat) -> CGFloat { ink.width * height / ink.height }

        /// The logo's ink `height` px tall, its top-left at `origin`; `color` is the one colour of `.white` and `.silhouette`.
        static func draw(_ ctx: CGContext, at origin: CGPoint, height: CGFloat, style: Style = .color,
                         color: CGColor = Marks060.color(0xFFFFFF), opacity: CGFloat = 1) {
            let k = height / ink.height
            ctx.saveGState()
            ctx.translateBy(x: origin.x, y: origin.y)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -ink.minX, y: -ink.minY)
            ctx.setAlpha(opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setMiterLimit(4)
            for (part, path) in zip(parts, paths) {
                ctx.saveGState()
                ctx.concatenate(part.transform)
                if let fill = part.fill {
                    ctx.addPath(path)
                    ctx.setFillColor(style == .color ? Marks060.color(fill) : color)
                    ctx.fillPath(using: part.evenOdd ? .evenOdd : .winding)
                }
                if let stroke = part.stroke {
                    ctx.addPath(path)
                    ctx.setLineWidth(part.width); ctx.setLineCap(part.cap); ctx.setLineJoin(part.join)
                    switch style {
                    case .color: ctx.setStrokeColor(Marks060.color(stroke))
                    case .white:
                        // The outlines cut out; the beer's highlight, a colour of the glass, stays the one colour.
                        if stroke == 0x000000 { ctx.setBlendMode(.clear) }
                        ctx.setStrokeColor(color)
                    case .silhouette: ctx.setStrokeColor(color)
                    }
                    ctx.strokePath()
                }
                ctx.restoreGState()
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        static func image(height: CGFloat, style: Style = .color, color: CGColor = Marks060.color(0xFFFFFF), scale: CGFloat = 2) -> CGImage {
            Marks060.image(size: CGSize(width: width(height: height), height: height), scale: scale) {
                draw($0, at: .zero, height: height, style: style, color: color)
            }
        }
    }
}

// MARK: - The Intel glyph (an evocation of the Intel Inside badge)

extension Marks060 {
    enum IntelGlyph {
        /// The glyph in its own 100 × 100 units (the box `height` measures): a rounded square whose outer edge is the box,
        /// its stroke 5 wide, its corners continuous (radius 20 outside); "intel" in SF Pro Bold, its ink 60 wide, centred,
        /// its baseline at 51; "inside" in SF Pro Medium, its ink 39 wide, centred, its baseline at 75.
        static let unit: CGFloat = 100
        static let stroke: CGFloat = 5, radius: CGFloat = 20
        static let intel = (text: "intel", weight: NSFont.Weight.bold, inkWidth: CGFloat(60), baseline: CGFloat(51))
        static let inside = (text: "inside", weight: NSFont.Weight.medium, inkWidth: CGFloat(39), baseline: CGFloat(75))

        /// The whole glyph in its units as one outline to fill (nonzero): the square's stroke, outlined, and the two words.
        static let unitShape: CGPath = {
            let p = CGMutablePath()
            let ring = Marks060.continuousRect(CGRect(x: stroke / 2, y: stroke / 2, width: unit - stroke, height: unit - stroke),
                                               radius: radius - stroke / 2)
            p.addPath(ring.copy(strokingWithWidth: stroke, lineCap: .butt, lineJoin: .miter, miterLimit: 10))
            for w in [intel, inside] {
                let f = NSFont.systemFont(ofSize: 48, weight: w.weight)
                let o = Marks060.textOutline(w.text, font: f)
                let b = o.boundingBoxOfPath
                let k = w.inkWidth / b.width
                p.addPath(o, transform: CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: unit / 2 - k * b.midX, ty: w.baseline))
            }
            return p
        }()

        /// The glyph `height` px tall with its top-left at `origin`, in the canvas.
        static func path(at origin: CGPoint, height: CGFloat) -> CGPath {
            let k = height / unit
            var t = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: origin.x, ty: origin.y)
            return unitShape.copy(using: &t) ?? unitShape
        }

        /// Flat, in one colour.
        static func draw(_ ctx: CGContext, at origin: CGPoint, height: CGFloat, color: CGColor) {
            ctx.saveGState()
            ctx.addPath(path(at: origin, height: height))
            ctx.setFillColor(color)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }

        /// The light that reveals it: a band `band` px wide whose core is the line through `core` leaning `lean` from the
        /// vertical (its top to the right, as the glint's), travelling along (cos lean, sin lean); `highlight` the core's
        /// strength (the glint's fade, 0…1).
        struct Light {
            var core: CGPoint
            var lean: CGFloat
            var band: CGFloat
            var highlight: CGFloat
            /// Signed distance of a canvas point from the core, positive ahead of it (not yet reached).
            func ahead(_ p: CGPoint) -> CGFloat { (p.x - core.x) * cos(lean) + (p.y - core.y) * sin(lean) }
            func point(_ s: CGFloat) -> CGPoint { CGPoint(x: core.x + s * cos(lean), y: core.y + s * sin(lean)) }

            /// The glint of DrawnIMac060 on the glass `screen` (canvas px) at `u` = (t − start) / duration: drawSheen's own
            /// band (20° lean, 0.30 of the glass wide, sine-eased from wholly left of the glass to wholly right of it, faded by
            /// sin πu), its core given at the glass's bottom edge. Clamped: before the run nothing is lit, after it all is.
            static func glass(screen sr: CGRect, u: Double) -> Light {
                let uu = min(max(u, 0), 1)
                let e = CGFloat((1 - cos(Double.pi * uu)) / 2)
                let lean = 20 * CGFloat.pi / 180
                let dx = tan(lean) * sr.height, band = 0.30 * sr.width
                let x = sr.minX - band / 2 - dx + (sr.width + band + dx) * e
                return Light(core: CGPoint(x: x, y: sr.maxY), lean: lean, band: band, highlight: CGFloat(sin(Double.pi * uu)))
            }
        }

        /// The chrome a passing light leaves: cool greys with a darker horizon just under the middle (a vertical gradient over
        /// the glyph's box).
        static let chrome: CGGradient = {
            let stops: [(CGFloat, UInt32)] = [(0, 0xF2F4F8), (0.36, 0xC4C8D0), (0.50, 0x6C717B), (0.58, 0x9297A0), (1, 0xDCE0E6)]
            return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { Marks060.color($0.1) } as CFArray,
                              locations: stops.map { $0.0 })!
        }()

        /// Revealed by `light`: `unlit` until the light reaches it, chrome at `lit` once the core has passed (rising from 5 % of
        /// the band ahead of the core to 35 % of it behind, smoothstep), and under the core a highlight: a soft white and
        /// accent (#9BB7FF, as the glint's own core) of σ 7 % of the band and a sharp white of σ 3.5 px, times
        /// `light.highlight` (the glint's fade).
        static func drawLit(_ ctx: CGContext, at origin: CGPoint, height: CGFloat, light: Light,
                            unlit: CGColor = Marks060.color(0x000000, 0.30), lit: CGFloat = 0.95) {
            let glyph = path(at: origin, height: height)
            let box = glyph.boundingBoxOfPath
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            ctx.saveGState()
            ctx.addPath(glyph)
            ctx.clip(using: .winding)
            ctx.setFillColor(unlit)
            ctx.fill(box)
            // The chrome, kept where the band has passed: a layer masked by the reveal along the light's travel.
            let ahead = light.band * 0.05, behind = light.band * 0.35
            let ramp = (0...8).map { CGFloat($0) / 8 }
            let mask = CGGradient(colorsSpace: srgb, colors: ramp.map { v in Marks060.color(0xFFFFFF, lit * v * v * (3 - 2 * v)) } as CFArray,
                                  locations: ramp)!
            ctx.beginTransparencyLayer(in: box, auxiliaryInfo: nil)
            ctx.drawLinearGradient(chrome, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.setBlendMode(.destinationIn)
            ctx.drawLinearGradient(mask, start: light.point(ahead), end: light.point(-behind),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.endTransparencyLayer()
            // The highlight under the core.
            if light.highlight > 0.002 {
                for (sigma, strength, hex) in [(light.band * 0.07, 0.45 * light.highlight, UInt32(0x9BB7FF)),
                                               (light.band * 0.07, 0.55 * light.highlight, UInt32(0xFFFFFF)),
                                               (CGFloat(3.5), 0.95 * light.highlight, UInt32(0xFFFFFF))] {
                    // A gaussian across ±3 σ, less its value there, so it meets nothing at its ends.
                    let xs = (0...16).map { CGFloat($0) / 8 - 1 }
                    let edge = exp(-4.5)
                    let g = CGGradient(colorsSpace: srgb, colors: xs.map { x in
                        Marks060.color(hex, strength * CGFloat(max(0, (exp(-Double(9 * x * x) / 2) - edge) / (1 - edge))))
                    } as CFArray, locations: xs.map { ($0 + 1) / 2 })!
                    ctx.drawLinearGradient(g, start: light.point(-3 * sigma), end: light.point(3 * sigma), options: [])
                }
            }
            ctx.restoreGState()
        }

        static func width(height: CGFloat) -> CGFloat { height }

        static func image(height: CGFloat, color: CGColor = Marks060.color(0xFFFFFF), scale: CGFloat = 2) -> CGImage {
            Marks060.image(size: CGSize(width: height, height: height), scale: scale) { draw($0, at: .zero, height: height, color: color) }
        }

        /// Wholly revealed, the light gone: the chrome at `lit`, nothing unlit.
        static func litImage(height: CGFloat, scale: CGFloat = 2) -> CGImage {
            Marks060.image(size: CGSize(width: height, height: height), scale: scale) {
                let far = Light(core: CGPoint(x: height * 10, y: height), lean: 20 * .pi / 180, band: height, highlight: 0)
                drawLit($0, at: .zero, height: height, light: far, unlit: Marks060.color(0xFFFFFF, 0))
            }
        }
    }
}

// MARK: - The proposals (assets/marks/README.md, preview-endcard.png, preview-intel.png)

extension Marks060 {
    /// S22's end card: one row under "Free. Open source." in Close060's card space (its numbers before the +1.2 % hold):
    /// the badge, "For iPhone and iPad on the App Store.", the GitHub mark and the Homebrew logo, "For Mac at
    /// getsill.app/download", 18 · 64 · 12 · 18 px apart, the row centred on x 960 by its ink (427.0–1492.3 with Core Text's
    /// widths: re-centre it on the renderer's own), its marks centred on y 876 and its two T5 lines' baselines at 885 (their
    /// caps centred on the marks; v4.2's lines were at 866 and 900). Apple's rules for the badge (the App Store marketing
    /// guidelines): the black badge, first in the lineup, one per video, at least 40 px tall, a quarter of its height clear
    /// round it, never modified, angled or animated; so the row stays out of the card's hold (as the sill line does), its marks
    /// only fade in, with their lines' snaps (snapState's 0.12 s opacity ramp: the badge at 72.05, the GitHub mark and the
    /// Homebrew logo at 72.45, film time), and out with the card.
    enum EndCardRow {
        static let centreY: CGFloat = 876, baseline: CGFloat = 885
        static let badge = CGRect(x: 427, y: 854, width: 131.630, height: 44)
        static let iPhoneLineInkLeft: CGFloat = 576.630
        static let gitHub = CGRect(x: 1056.664, y: 861, width: 30.972, height: 30)
        static let homebrew = CGRect(x: 1099.636, y: 858, width: 23.143, height: 36)
        static let macLineInkLeft: CGFloat = 1140.780
        static let gaps = (badgeToLine: CGFloat(18), betweenGroups: CGFloat(64), markToMark: CGFloat(12), markToLine: CGFloat(18))
    }

    /// S18's glyph on the iMac's glass: centred on the screen's centre (icon point (512, 380)), 140 icon units square, so
    /// DrawnIMac060's r(442, 310, 140, 140) (150.1 px at the glint's k 1.0724), drawn in the glass's clip before the sheen with
    /// `IntelGlyph.drawLit(cg, at: rect.origin, height: rect.height, light: .glass(screen: screenRect, u: (t − start) /
    /// duration))` (the sheen's own start and duration, v4's 63.2 and 0.9 s): dark until 60.385 (film), the core over its
    /// centre at 60.451, wholly lit by 60.554, lit to the cut at 62.4.
    enum IntelOnGlass {
        static let unitRect = CGRect(x: 442, y: 310, width: 140, height: 140)
    }
}
