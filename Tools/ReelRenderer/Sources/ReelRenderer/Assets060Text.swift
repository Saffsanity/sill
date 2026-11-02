// Assets060Text.swift — the 0.6.0 reel's drawn assets: type as glyph outlines at exact fractional positions.
//
// The storyboard's §1.1 fix, for the type the assets draw themselves (the lock screen's clock, the keycaps'
// legends, the fixes cutaway's column): every line is shaped once by Core Text, each run in its own font (so a
// fallback font keeps its glyphs), and its glyph outlines are filled with anti-aliasing wherever the frame puts
// them, so a line that moves glides instead of jumping a pixel at a time. Nothing here is rasterised and then
// moved. The words' snap is v3's §3.5 recipe (TypeViews.swift's `snapState`), redrawn on the outlines. The outlines
// are grown as Core Graphics' font smoothing grows the strokes of text it draws itself (`smoothing`, the 0.6.0
// type fix's measurement of v3.1's own type), so this type keeps the weight of the film's other lines.
import AppKit
import CoreText
import SwiftUI

enum Outline060 {
    /// A shaped line: its glyph outlines with the origin on the baseline at the line's left edge, y down.
    struct Line {
        let path: Path
        /// The typographic advance (Core Text's), trailing tracking included.
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        let capHeight: CGFloat
        let xHeight: CGFloat
    }

    private static var cache: [String: Line] = [:]
    private static var order: [String] = []

    /// How far font smoothing grows a stroke at `size` px: 0.21 px at 24 px, 0.25 at 28, 0.32 from 34 px up (the
    /// 0.6.0 type fix's fit to v3.1's SwiftUI Text, GlyphText.swift `ShapedText.smoothing`).
    static func smoothing(_ size: CGFloat) -> CGFloat { 0.32 * min(1, max(0, (size - 4) / 30)) }

    static func font(size: CGFloat, weight: NSFont.Weight, monoDigits: Bool = false) -> NSFont {
        monoDigits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// The line `s` in SF Pro at `size` px, `weight`, with `tracking` px after every glyph (as SwiftUI's
    /// `.tracking` and v3's `measure`). Cached by its arguments (tracking to 1/1000 px).
    static func line(_ s: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0, monoDigits: Bool = false) -> Line {
        let key = "\(s)|\(size)|\(weight.rawValue)|\(String(format: "%.3f", tracking))|\(monoDigits)"
        if let hit = cache[key] { return hit }
        let nsFont = font(size: size, weight: weight, monoDigits: monoDigits)
        var attrs: [NSAttributedString.Key: Any] = [.font: nsFont]
        if abs(tracking) > 1e-6 { attrs[.kern] = tracking }
        let ct = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(ct, &ascent, &descent, &leading))
        let outlines = CGMutablePath()
        for run in CTLineGetGlyphRuns(ct) as! [CTRun] {
            let runAttrs = CTRunGetAttributes(run) as! [NSAttributedString.Key: Any]
            let runFont: CTFont = (runAttrs[.font] as? NSFont).map { $0 as CTFont } ?? (nsFont as CTFont)
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let grow = smoothing(size)
            for i in 0..<n {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil), !glyph.isEmpty else { continue }
                // Grown by `grow` px on every side (its union with a stroke twice that wide along it).
                let grown = grow > 0.0005 ? glyph.union(glyph.copy(strokingWithWidth: 2 * grow, lineCap: .round, lineJoin: .round, miterLimit: 4),
                                                        using: .winding) : glyph
                // Glyph space is y up from the baseline; the canvas is y down.
                outlines.addPath(grown, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: -positions[i].y))
            }
        }
        let laid = Line(path: Path(outlines), width: width, ascent: ascent, descent: descent,
                        capHeight: nsFont.capHeight, xHeight: nsFont.xHeight)
        cache[key] = laid
        order.append(key)
        if order.count > 600 { cache[order.removeFirst()] = nil }
        return laid
    }

    /// Fills `line` with its baseline-left at `origin` (any fractional point), scaled by `scale` about it.
    static func fill(_ line: Line, in ctx: inout GraphicsContext, at origin: CGPoint, scale: CGFloat = 1, color: Color) {
        let tr = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
        ctx.fill(line.path.applying(tr), with: .color(color))
    }

    /// Fills `s` centred on `centerX` (or from `x` when `leading`), its baseline at `baseline`.
    static func draw(_ s: String, in ctx: inout GraphicsContext, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0,
                     x: CGFloat, baseline: CGFloat, leading: Bool = false, color: Color, monoDigits: Bool = false) {
        let l = line(s, size: size, weight: weight, tracking: tracking, monoDigits: monoDigits)
        fill(l, in: &ctx, at: CGPoint(x: leading ? x : x - l.width / 2, y: baseline), color: color)
    }

    // MARK: The §3.5 snap, on outlines

    /// v3's snap in (TypeViews.swift `snapState`): 0.30 s appleOut; opacity over the first 0.12 s; scale 1.08 → 1,
    /// blur 14 → 0, y +18 → 0, tracking +0.06 em → final.
    struct Snap { var opacity: Double; var scale: CGFloat; var blur: CGFloat; var dy: CGFloat; var trackingExtra: CGFloat }
    static func snap(_ t: Double, start: Double) -> Snap {
        guard t >= start else { return Snap(opacity: 0, scale: 1.08, blur: 14, dy: 18, trackingExtra: 0.06) }
        let p = CGFloat(ease(t, start, 0.30, .appleOut))
        return Snap(opacity: ramp(t, start, start + 0.12), scale: 1.08 - 0.08 * p, blur: 14 * (1 - p), dy: 18 * (1 - p),
                    trackingExtra: 0.06 * (1 - p))
    }

    /// A statement snapped in word by word (0.05 s apart, as v3's `TypeLine` with `cascade`), drawn on the
    /// outlines. `leading`: the line starts at `x`; else it is centred on `x`. `hold`: the whole line's scale (v3's
    /// +1.2 % hold), about its leading edge or centre. The words keep their own snap, scale about their own centre,
    /// blur and rise, as SwiftUI drew them; the layout advances by each word's width at its tracking of the frame.
    static func snapLine(_ words: [String], in ctx: inout GraphicsContext, t: Double, snap start: Double,
                         size: CGFloat, weight: NSFont.Weight, tracking: CGFloat, color: Color,
                         x: CGFloat, baseline: CGFloat, leading: Bool, hold: CGFloat = 1, cascade: Bool = true, opacity: Double = 1) {
        guard opacity > 0.001, !words.isEmpty else { return }
        let last = words.count - 1
        let states = words.indices.map { snap(t, start: start + (cascade ? 0.05 * Double($0) : 0)) }
        let laid = words.indices.map { i in
            line(words[i] + (i < last ? " " : ""), size: size, weight: weight, tracking: tracking + states[i].trackingExtra * size)
        }
        let total = laid.reduce(0) { $0 + $1.width }
        let x0 = leading ? x : x - total / 2
        let anchor = CGPoint(x: leading ? x0 : x0 + total / 2, y: baseline - (laid[0].ascent - laid[0].descent) / 2)
        var c = ctx
        c.opacity = opacity
        c.concatenate(CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: hold, y: hold).translatedBy(x: -anchor.x, y: -anchor.y))
        var cursor = x0
        for i in words.indices {
            let s = states[i], l = laid[i]
            defer { cursor += l.width }
            guard s.opacity > 0.001 else { continue }
            // The word's own frame centre (its glyphs' box without the trailing space).
            let wordWidth = i < last ? line(words[i], size: size, weight: weight, tracking: tracking + s.trackingExtra * size).width : l.width
            let centre = CGPoint(x: cursor + wordWidth / 2, y: baseline - (l.ascent - l.descent) / 2)
            // As SwiftUI drew a word: its scale about its own centre, then its rise.
            let tr = CGAffineTransform(translationX: -centre.x, y: -centre.y)
                .concatenating(CGAffineTransform(scaleX: s.scale, y: s.scale))
                .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y + s.dy))
            let path = l.path.applying(CGAffineTransform(translationX: cursor, y: baseline)).applying(tr)
            c.drawLayer { g in
                g.opacity = s.opacity
                if s.blur > 0.05 { g.addFilter(.blur(radius: s.blur)) }
                g.fill(path, with: .color(color))
            }
        }
    }
}
