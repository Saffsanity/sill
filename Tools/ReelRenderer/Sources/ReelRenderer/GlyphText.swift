// GlyphText.swift — the reel's type as glyph outlines, filled at the exact fractional positions its motion gives
// them (0.6.0: Noah's "floating point issues with the text").
//
// v3.1 drew each line as SwiftUI Text, which ImageRenderer replayed into the frame's 8-bit Core Graphics context,
// and there every glyph landed on a whole pixel: under the +1.2 % hold a glyph held still, then jumped a pixel,
// each glyph on its own frame (v3.1's "No subscription.", 66.35–67.2 s: 42 whole-pixel jumps and 705 held steps of
// 750, up to 0.99 px off its path; the legal line's baseline stepped a pixel down and back up). The context's
// subpixel flags (Render.swift sets them too) fix the large lines but not the small ones, and SwiftUI's layout
// still rounds each word's place. So here Core Text shapes a string once (each run in its own font, so fallback
// fonts carry Chinese, Japanese and Korean), the glyphs' outlines are filled with anti-aliasing where the motion
// puts them, in floating point up to the fill, and a line at rest sits on whole pixels: its layout origin and
// baseline are rounded, and every motion ends exactly there, so nothing jumps when it stops.
//
// It keeps v3.1's look: each word takes the width of v3.1's Text frame (rounded up to a whole pixel), and the
// outlines are grown by the stem thickening Core Graphics' font smoothing gave v3.1's text (`smoothing`).
//
// TypeCheck.swift measures every glyph of a rendered frame against the path recorded here (`typecheck`,
// `render --typecheck`). The rules for shots (README.md, The type):
// - draw type only through TypeLayer, TypeLine, StaticLine or GlyphCanvas, never as SwiftUI `Text`;
// - move a whole type layer with its `transform:` (fade it with `.opacity`), never with `.offset`, `.scaleEffect`,
//   `.rotationEffect` or a device's tilt around it, so the path recorded is the path drawn;
// - declare where a shot masks or covers type (`covered:`), and mark text that belongs to a picture, such as words
//   on a drawn device's screen, `checked: false`;
// - every number on screen is a fixed string in `Copy`, never a computed value printed (`typecheck` flags one).
import AppKit
import CoreText
import SwiftUI

// MARK: - Shaping

/// A string shaped by Core Text in one of the reel's type styles: its glyphs' outlines and origins in the run's
/// own space (origin at the start of the baseline, x to the right, y down), with the style's tracking after every
/// glyph, as SwiftUI's `.tracking` sets it.
final class ShapedText {
    struct Glyph {
        /// The outline in glyph space (points, y down, origin at the glyph's origin); nil for a glyph with none
        /// (a space, or a bitmap glyph such as an emoji, which is drawn by Core Text instead).
        let outline: CGPath?
        /// The glyph's origin in the run's space, with the style's tracking.
        let position: CGPoint
        /// Its place in visual order: extra tracking (the snap's +0.06 em) moves it by `order` × the extra.
        let order: Int
        let font: CTFont
        let glyph: CGGlyph
    }

    let text: String
    let size: CGFloat
    let glyphs: [Glyph]
    /// Typographic width with the style's tracking after every glyph, the last included (Core Text's, and SwiftUI's).
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat
    /// The height of SwiftUI's Text frame for one line: ascent + descent + leading.
    var height: CGFloat { ascent + descent + leading }

    /// The width with `extra` points of tracking added after every glyph.
    func width(extra: CGFloat) -> CGFloat { width + extra * CGFloat(glyphs.count) }
    /// The width of SwiftUI's Text frame for it, as v3.1 laid its words side by side: the typographic width
    /// rounded up to a whole pixel. Layouts here add that rounding as a constant, so a line at rest spaces its
    /// words exactly as v3.1 did, while the snap's tracking still widens it smoothly.
    var frameWidth: CGFloat { (width - 1e-6).rounded(.up) }
    func frameWidth(extra: CGFloat) -> CGFloat { width(extra: extra) + frameWidth - width }

    private init(text: String, size: CGFloat, glyphs: [Glyph], width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        self.text = text; self.size = size; self.glyphs = glyphs; self.width = width
        self.ascent = ascent; self.descent = descent; self.leading = leading
    }

    private static let lock = NSLock()
    private static var cache: [String: ShapedText] = [:]
    private var dilated: [Int: [CGPath?]] = [:]

    /// How far Core Graphics' font smoothing grows the strokes of text it draws itself, in px, by type size,
    /// measured on v3.1's own type (its SwiftUI Text against these outlines, the fit's gain and residual,
    /// 2026-11-02): 0.21 px at 24 px, 0.235 at 26, 0.25 at 28, and 0.30 to 0.34 from 34 px up to 168. The
    /// outlines are grown by as much, so the type keeps v3.1's weight (without it, 24 px type drew 11 % lighter).
    static func smoothing(_ size: CGFloat) -> CGFloat { 0.32 * min(1, max(0, (size - 4) / 30)) }

    /// The glyphs' outlines grown by `d` px on every side (their union with a 2d-wide stroke along them), as Core
    /// Graphics' font smoothing thickens the strokes of text it draws itself; cached per amount.
    func outlines(dilatedBy d: CGFloat) -> [CGPath?] {
        guard d > 0.0005 else { return glyphs.map(\.outline) }
        let key = Int((d * 10_000).rounded())
        ShapedText.lock.lock()
        if let o = dilated[key] { ShapedText.lock.unlock(); return o }
        ShapedText.lock.unlock()
        let o: [CGPath?] = glyphs.map { g in
            guard let path = g.outline else { return nil }
            let stroke = path.copy(strokingWithWidth: 2 * d, lineCap: .round, lineJoin: .round, miterLimit: 4)
            return path.union(stroke, using: .winding)
        }
        ShapedText.lock.lock(); dilated[key] = o; ShapedText.lock.unlock()
        return o
    }

    /// The style's font: the system font (SF Pro, at its automatic optical size), as `Font.system(size:weight:)`.
    static func font(_ style: TypeStyle) -> CTFont {
        let w = appKitWeight(style.weight)
        let f = style.monoDigits ? NSFont.monospacedDigitSystemFont(ofSize: style.size, weight: w)
                                 : NSFont.systemFont(ofSize: style.size, weight: w)
        return f as CTFont
    }

    static func appKitWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }

    /// `text` shaped in `style` (cached: a line keeps one shape, and only its transform moves). `language` (a BCP 47
    /// tag) picks the fallback fonts for its script as that language sets it: "ja" gives Japanese Hiragino, where
    /// untagged kana fall to a Chinese font; "zh-Hans" PingFang SC; "ko" Apple SD Gothic Neo.
    static func shape(_ text: String, _ style: TypeStyle, language: String? = nil) -> ShapedText {
        let key = "\(text)\u{1F}\(style.size)\u{1F}\(appKitWeight(style.weight).rawValue)\u{1F}\(style.tracking)\u{1F}\(style.monoDigits)\u{1F}\(language ?? "")"
        lock.lock()
        if let s = cache[key] { lock.unlock(); return s }
        lock.unlock()
        let font = font(style)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .tracking: style.tracking]
        if let language { attrs[NSAttributedString.Key(kCTLanguageAttributeName as String)] = language }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var glyphs: [Glyph] = []
        var flip = CGAffineTransform(scaleX: 1, y: -1)        // glyph space is y up; the canvas is y down
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName as NSString] as! CTFont?) ?? font
            var ids = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
            for k in 0..<n {
                var outline = CTFontCreatePathForGlyph(runFont, ids[k], &flip)
                if let o = outline, o.isEmpty { outline = nil }
                glyphs.append(Glyph(outline: outline, position: CGPoint(x: pos[k].x, y: -pos[k].y), order: glyphs.count,
                                    font: runFont, glyph: ids[k]))
            }
        }
        let s = ShapedText(text: text, size: style.size, glyphs: glyphs, width: width, ascent: ascent, descent: descent, leading: leading)
        lock.lock(); cache[key] = s; lock.unlock()
        return s
    }
}

// MARK: - What a type canvas draws

/// One shaped run placed on the canvas.
struct PlacedRun {
    let shape: ShapedText
    /// Points of tracking added after every glyph, on top of the style's (the snap's).
    var extra: CGFloat = 0
    /// From the run's space (origin at its start on its baseline, y down) to the canvas, in floating point.
    var transform: CGAffineTransform
    var color: UInt32
    var opacity: Double = 1
    /// A Gaussian blur, as SwiftUI's `.blur(radius:)` on the word.
    var blur: CGFloat = 0
    /// Names the run in typecheck's report.
    var tag: String = ""
}

/// Runs, in groups that fade and blur together (a line's ease-out over its words' snaps).
indirect enum TypeNode {
    case run(PlacedRun)
    case group([TypeNode], opacity: Double, blur: CGFloat)
}

extension CGAffineTransform {
    /// A uniform scale about a canvas point.
    static func scaling(_ s: CGFloat, about p: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -p.x, y: -p.y).concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }
    /// A rotation about a canvas point; positive degrees turn clockwise on screen, as `.rotationEffect`.
    static func rotation(degrees: Double, about p: CGPoint) -> CGAffineTransform {
        guard degrees != 0 else { return .identity }
        return CGAffineTransform(translationX: -p.x, y: -p.y).concatenating(CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180)))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }
}

/// A full-canvas layer of type: `nodes` drawn as glyph outlines, all moved by `transform` (canvas → canvas: a
/// card's hold or lift), faded by `opacity` and blurred by `blur` as one. `covered` names the canvas rectangles
/// where the shot masks or covers this type (a wipe's soft edge, a fade band, a device in front): typecheck
/// fits the glyphs there but does not judge them, since a mask's edge across a thin glyph looks like a shift.
/// `checked: false` is for type that belongs to a picture rather than to the film's type layer (the clock on a
/// drawn lock screen inside a tilted device): SwiftUI's effects move it with the picture, so it has no path of
/// its own to check.
struct GlyphCanvas: View {
    let nodes: [TypeNode]
    var transform: CGAffineTransform = .identity
    var opacity: Double = 1
    var blur: CGFloat = 0
    var covered: [CGRect] = []
    var checked = true

    var body: some View {
        let root = TypeNode.group(nodes, opacity: opacity, blur: blur)
        let t = transform
        let c = covered
        let k = checked
        return Canvas { ctx, _ in GlyphDraw.draw(root, in: &ctx, transform: t, covered: c, checked: k) }
            .frame(width: Stage.size.width, height: Stage.size.height)
            .allowsHitTesting(false)
    }
}

enum GlyphDraw {
    /// Draws a node tree, recording every glyph's path for typecheck (TypeProbe) as it goes.
    static func draw(_ root: TypeNode, in ctx: inout GraphicsContext, transform: CGAffineTransform, covered: [CGRect] = [],
                     checked: Bool = true) {
        let probe = TypeProbe.shared
        var state = probe.state
        if state.hidden { return }
        if !checked { state.unchecked = true }
        draw(root, in: &ctx, transform: transform, opacity: 1, blur: 0, probe: probe, state: state, covered: covered)
    }

    private static func draw(_ node: TypeNode, in ctx: inout GraphicsContext, transform: CGAffineTransform,
                             opacity: Double, blur: CGFloat, probe: TypeProbe, state: TypeProbe.State, covered: [CGRect]) {
        switch node {
        case let .group(kids, o, b):
            let op = opacity * o
            guard op > 0.0005 else { return }
            if b > 0.01 && !state.recordOnly {
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: b))
                    for k in kids { draw(k, in: &g, transform: transform, opacity: op, blur: (blur * blur + b * b).squareRoot(), probe: probe, state: state, covered: covered) }
                }
            } else {
                for k in kids { draw(k, in: &ctx, transform: transform, opacity: op, blur: (blur * blur + b * b).squareRoot(), probe: probe, state: state, covered: covered) }
            }
        case let .run(r):
            let op = opacity * r.opacity
            guard op > 0.0005 else { return }
            let t = r.transform.concatenating(transform)
            let totalBlur = (blur * blur + r.blur * r.blur).squareRoot()
            let path = CGMutablePath()
            var bitmapGlyphs: [ShapedText.Glyph] = []
            let outlines = r.shape.outlines(dilatedBy: ShapedText.smoothing(r.shape.size))
            for (k, g) in r.shape.glyphs.enumerated() {
                let place = CGAffineTransform(translationX: g.position.x + r.extra * CGFloat(g.order), y: g.position.y)
                let glyphToCanvas = place.concatenating(t)
                guard g.outline != nil, let outline = outlines[k] else {
                    if !g.font.isSpace(g.glyph) { bitmapGlyphs.append(g) }
                    continue
                }
                if state.recording {
                    let box = outline.boundingBoxOfPath.applying(glyphToCanvas)
                    probe.record(TypeProbe.Glyph(tag: r.tag, text: r.shape.text, order: g.order, outline: outline,
                                                 transform: glyphToCanvas, color: r.color, opacity: op, blur: totalBlur,
                                                 layer: state.layer, covered: covered.contains { $0.intersects(box) },
                                                 picture: state.unchecked))
                }
                // TEST ONLY (REEL_TYPE_OFFSET): the glyph drawn away from the path recorded, so typecheck's own
                // detection can be shown to work. Never set for a delivered render (`pipeline.sh` refuses it).
                let drawn = state.offset == .zero ? glyphToCanvas
                    : glyphToCanvas.concatenating(CGAffineTransform(translationX: state.offset.width, y: state.offset.height))
                path.addPath(outline, transform: drawn)
            }
            if state.recording { probe.noteString(r.shape.text) }
            if state.recordOnly { return }
            let shading = GraphicsContext.Shading.color(Color(hex: r.color, alpha: op))
            if r.blur > 0.01 {
                ctx.drawLayer { g in
                    g.addFilter(.blur(radius: r.blur))
                    g.fill(Path(path), with: shading)
                    drawBitmapGlyphs(bitmapGlyphs, transform: t, extra: r.extra, color: r.color, opacity: op, in: &g)
                }
            } else {
                ctx.fill(Path(path), with: shading)
                drawBitmapGlyphs(bitmapGlyphs, transform: t, extra: r.extra, color: r.color, opacity: op, in: &ctx)
            }
        }
    }

    /// Glyphs without an outline (an emoji's bitmap): drawn by Core Text at their exact origin, with subpixel
    /// positioning on. typecheck can't measure them (it reports them); the reel's copy has none.
    private static func drawBitmapGlyphs(_ glyphs: [ShapedText.Glyph], transform: CGAffineTransform, extra: CGFloat,
                                         color: UInt32, opacity: Double, in ctx: inout GraphicsContext) {
        guard !glyphs.isEmpty else { return }
        TypeProbe.shared.noteBitmapGlyphs(glyphs.count)
        ctx.withCGContext { cg in
            cg.setAllowsFontSubpixelPositioning(true); cg.setShouldSubpixelPositionFonts(true)
            cg.setAllowsFontSubpixelQuantization(false); cg.setShouldSubpixelQuantizeFonts(false)
            cg.setFillColor(CGColor.hex(color, CGFloat(opacity)))
            for g in glyphs {
                cg.saveGState()
                let place = CGAffineTransform(translationX: g.position.x + extra * CGFloat(g.order), y: g.position.y)
                cg.concatenate(place.concatenating(transform))
                cg.scaleBy(x: 1, y: -1)                       // Core Text draws y up
                var id = g.glyph
                var origin = CGPoint.zero
                CTFontDrawGlyphs(g.font, &id, &origin, 1, cg)
                cg.restoreGState()
            }
        }
    }
}

private extension CTFont {
    /// True for a glyph that draws nothing (a space): no outline and no bitmap.
    func isSpace(_ glyph: CGGlyph) -> Bool {
        var g = glyph
        var r = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(self, .default, &g, &r, 1)
        return r.isEmpty || r.width == 0 || r.height == 0
    }
}

// MARK: - The probe: what the canvases drew, for typecheck

/// What the type canvases drew while a frame was being checked: every glyph with the path its motion gave it.
/// Canvas closures run during ImageRenderer's render, so this is a plain locked class, not actor-bound.
final class TypeProbe {
    static let shared = TypeProbe()

    enum Layer: String { case base, mix, overlay }

    struct Glyph {
        let tag: String
        let text: String
        let order: Int
        let outline: CGPath
        /// Glyph space → canvas, as drawn (before any rack the compositor applies to the base).
        let transform: CGAffineTransform
        let color: UInt32
        let opacity: Double
        let blur: CGFloat
        let layer: Layer
        /// The shot masks or covers it in part (GlyphCanvas's `covered`): fitted, not judged.
        let covered: Bool
        /// Part of a picture (GlyphCanvas's `checked: false`): fitted, not judged.
        let picture: Bool
    }

    struct State {
        var recording = false
        /// The canvases draw nothing (typecheck's render without type).
        var hidden = false
        /// The canvases record but draw nothing (REEL_TYPE_LEGACY: v3.1's SwiftUI Text draws instead).
        var recordOnly = false
        var layer: Layer = .base
        /// TEST ONLY: every glyph drawn this far from its recorded path (REEL_TYPE_OFFSET="dx,dy").
        var offset = CGSize.zero
        /// Set per canvas: its type belongs to a picture (`checked: false`).
        var unchecked = false
    }

    private let lock = NSLock()
    private var _state = State()
    private var _glyphs: [Glyph] = []
    private var _strings: [String: Int] = [:]
    private var _bitmapGlyphs = 0

    /// v3.1's drawing, SwiftUI Text, for comparison only (REEL_TYPE_LEGACY=1). Never a delivered render.
    static let legacy = ProcessInfo.processInfo.environment["REEL_TYPE_LEGACY"] != nil
    static let testOffset: CGSize = {
        guard let v = ProcessInfo.processInfo.environment["REEL_TYPE_OFFSET"] else { return .zero }
        let p = v.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return CGSize(width: p.first ?? 0, height: p.count > 1 ? p[1] : 0)
    }()

    private init() {
        _state.offset = TypeProbe.testOffset
        _state.recordOnly = TypeProbe.legacy
    }


    var state: State { lock.lock(); defer { lock.unlock() }; return _state }

    func set(_ change: (inout State) -> Void) { lock.lock(); change(&_state); lock.unlock() }

    /// Clears the record and starts recording.
    func begin() {
        lock.lock(); _glyphs.removeAll(keepingCapacity: true); _state.recording = true; lock.unlock()
    }

    /// Stops recording and hands over what was drawn, each glyph once.
    func end() -> [Glyph] {
        lock.lock(); defer { lock.unlock() }
        _state.recording = false
        var seen = Set<String>()
        var out: [Glyph] = []
        for g in _glyphs {
            let k = "\(g.tag)|\(g.order)|\(g.transform.tx)|\(g.transform.ty)|\(g.transform.a)|\(g.transform.d)|\(g.layer.rawValue)"
            if seen.insert(k).inserted { out.append(g) }
        }
        return out
    }

    func record(_ g: Glyph) { lock.lock(); _glyphs.append(g); lock.unlock() }

    func noteString(_ s: String) { lock.lock(); _strings[s, default: 0] += 1; lock.unlock() }

    func noteBitmapGlyphs(_ n: Int) { lock.lock(); _bitmapGlyphs += n; lock.unlock() }

    /// Every string drawn while recording, with how many times.
    var strings: [String: Int] { lock.lock(); defer { lock.unlock() }; return _strings }
    var bitmapGlyphs: Int { lock.lock(); defer { lock.unlock() }; return _bitmapGlyphs }
}
