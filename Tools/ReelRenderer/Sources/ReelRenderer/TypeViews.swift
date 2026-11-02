// TypeViews.swift — statements, the snap-in / hold / ease-out recipes (§3.5) placed by baseline. 0.6.0: every line is
// laid out here in floating point and drawn as glyph outlines (GlyphText.swift), not as SwiftUI Text.
import SwiftUI

enum LineAlign { case center, leading }

/// One line of copy. Words cascade 0.05 s apart on the snap; the line holds with +1.2 % scale.
struct LineSpec {
    var words: [String]
    var style: TypeStyle
    var x: CGFloat                    // centre x (center) or left x (leading)
    var baseline: CGFloat
    var align: LineAlign = .center
    var snap: Double                  // reel time the snap starts
    var cascade = true                // words 0.05 s apart (false: the whole line at once)
    /// 0.6.0: the time between two words' snaps in a cascade (v3's 0.05 s; `capped` shortens it for long sublines).
    var step = 0.05
    var holdEnd: Double               // the hold's scale runs to here (usually the shot's end)
    var easeOut: Double? = nil        // start of the 0.20 s ease-out, if the shot asks for one
    var colors: [Int: UInt32] = [:]   // per-word colour overrides ("sit." in accent)
    var holdScale = true              // false: no +1.2 % hold (the lockup holds as one card)
    /// v2, note 7: one word vibrates like a Taptic buzz (word index, start, duration, amplitude in px).
    var jitter: (word: Int, start: Double, duration: Double, amplitude: CGFloat)? = nil
    /// 0.6.0: the line's language (BCP 47), for its fallback fonts: "ja" sets こんにちは in Hiragino (ShapedText.shape).
    var language: String? = nil

    init(_ text: String, _ style: TypeStyle, x: CGFloat = 960, baseline: CGFloat, align: LineAlign = .center,
         snap: Double, holdEnd: Double, cascade: Bool = true, easeOut: Double? = nil) {
        words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        self.style = style; self.x = x; self.baseline = baseline; self.align = align
        self.snap = snap; self.holdEnd = holdEnd; self.cascade = cascade; self.easeOut = easeOut
    }
    init(words: [String], _ style: TypeStyle, x: CGFloat = 960, baseline: CGFloat, align: LineAlign = .center,
         snap: Double, holdEnd: Double, cascade: Bool = true, easeOut: Double? = nil) {
        self.words = words; self.style = style; self.x = x; self.baseline = baseline; self.align = align
        self.snap = snap; self.holdEnd = holdEnd; self.cascade = cascade; self.easeOut = easeOut
    }
}

/// Note 7: "haptic" vibrates like the trackpad's Taptic tick: an ~18 Hz jitter of `amplitude` px (x), half
/// that (y) and ±1° of twist for `duration` s, in over 0.04 s and settling over the last 0.12 s, then still.
/// At 60 fps each frame lands 108° further round the cycle, so the word visibly buzzes rather than drifting.
func hapticJitter(_ t: Double, start: Double, duration: Double = 0.6, amplitude: CGFloat = 3) -> (dx: CGFloat, dy: CGFloat, degrees: Double) {
    guard t >= start, t <= start + duration else { return (0, 0, 0) }
    let u = t - start
    let env = min(1, u / 0.04) * min(1, (start + duration - t) / 0.12)
    let w = 2 * Double.pi * 18
    return (amplitude * CGFloat(sin(w * u) * env), amplitude * 0.5 * CGFloat(sin(w * u * 1.5 + 1.1) * env),
            1.0 * sin(w * u * 0.75 + 2.0) * env)
}

struct SnapState {
    var opacity: Double = 0
    var scale: CGFloat = 1
    var blur: CGFloat = 0
    var dy: CGFloat = 0
    var trackingExtra: CGFloat = 0     // em fraction on top of the final tracking
}

/// §3.5 snap in: 0.30 s appleOut; opacity over the first 0.12 s; scale 1.08→1, blur 14→0, y +18→0,
/// tracking +0.06 em → final.
func snapState(_ t: Double, start: Double) -> SnapState {
    guard t >= start else { return SnapState(opacity: 0, scale: 1.08, blur: 14, dy: 18, trackingExtra: 0.06) }
    let p = ease(t, start, 0.30, .appleOut)
    return SnapState(opacity: ramp(t, start, start + 0.12), scale: 1.08 - 0.08 * CGFloat(p), blur: 14 * CGFloat(1 - p),
                     dy: 18 * CGFloat(1 - p), trackingExtra: 0.06 * CGFloat(1 - p))
}

/// One line of copy at time t: v3's snap, hold and ease-out (§3.5), drawn as glyph outlines (GlyphText.swift).
struct TypeLine: View {
    let spec: LineSpec
    let t: Double

    var body: some View {
        if TypeProbe.legacy {
            // REEL_TYPE_LEGACY=1: v3.1's SwiftUI drawing, for comparison only, over a canvas that records the
            // path the line should take (typecheck measures the old drawing against it).
            ZStack {
                LegacyTypeLine(spec: spec, t: t)
                GlyphCanvas(nodes: TypeLine.node(spec, t).map { [$0] } ?? [])
            }
        } else {
            GlyphCanvas(nodes: TypeLine.node(spec, t).map { [$0] } ?? [])
        }
    }

    /// The line's runs at time t, in canvas coordinates and floating point: every transform v3's view tree
    /// applied (TypeLine below, now LegacyTypeLine), composed by hand, so nothing is rounded on the way.
    ///
    /// Each word is shaped on its own, with its trailing space, as v3 set each word as its own Text, and takes
    /// the width of v3's Text frame (rounded up to a whole pixel), so a line at rest spaces its words as v3.1 did.
    /// Words sit side by side on the baseline (an HStack with no spacing); the snap adds 0.06 em of tracking that
    /// eases to 0, so the words' widths, and a centred line's left edge, move with it. At rest the line's left
    /// edge (or centre), each word's origin and the baseline are whole pixels: the place it lands is rounded, and
    /// every motion is computed from there, so a line comes to rest on the pixel grid without a jump.
    ///
    /// Per word (inside out): its scale about its frame's centre (1.08 → 1), its blur, its turn about the same
    /// centre (the haptic jitter), its offset (the snap's y, the jitter's x and y), its opacity. Per line: the
    /// +1.2 % hold about the line frame's centre (or its leading edge, at mid-height), the ease-out's blur, y and
    /// opacity. The frame is SwiftUI's Text frame: the font's ascent, descent and leading.
    static func node(_ spec: LineSpec, _ t: Double) -> TypeNode? {
        let last = spec.words.count - 1
        guard last >= 0 else { return nil }
        let style = spec.style
        let snapEnd = spec.snap + (spec.cascade ? spec.step * Double(last) : 0) + 0.30
        let hold = spec.holdScale ? 1 + 0.012 * CGFloat(ramp(t, snapEnd, max(spec.holdEnd, snapEnd + 0.01))) : 1
        var outOpacity = 1.0, outDy: CGFloat = 0, outBlur: CGFloat = 0
        if let e = spec.easeOut, t >= e {
            let p = ease(t, e, 0.20, .appleIn)
            outOpacity = 1 - p; outDy = -12 * CGFloat(p); outBlur = 8 * CGFloat(p)
        }
        guard outOpacity > 0.0005 else { return nil }
        let shapes = (0...last).map { ShapedText.shape(spec.words[$0] + ($0 < last ? " " : ""), style, language: spec.language) }
        let states = (0...last).map { snapState(t, start: spec.snap + (spec.cascade ? spec.step * Double($0) : 0)) }
        let extras = states.map { $0.trackingExtra * style.size }
        let widths = (0...last).map { shapes[$0].frameWidth(extra: extras[$0]) }
        let width = widths.reduce(0, +)
        let restWidth = shapes.reduce(0) { $0 + $1.frameWidth }
        let ascent = shapes.map(\.ascent).max() ?? 0
        let height = shapes.map(\.height).max() ?? 0
        // Where the line lands, on whole pixels; while the snap's tracking widens it, a centred line stays centred.
        let baseline = spec.baseline.rounded()
        let restLeft = spec.align == .center ? (spec.x - restWidth / 2).rounded() : spec.x.rounded()
        let left = spec.align == .center ? restLeft - (width - restWidth) / 2 : restLeft
        let midY = baseline - ascent + height / 2
        let anchor = CGPoint(x: spec.align == .center ? left + width / 2 : left, y: midY)
        let lineT = CGAffineTransform.scaling(hold, about: anchor).concatenating(CGAffineTransform(translationX: 0, y: outDy))
        let name = spec.words.joined(separator: " ")
        var runs: [TypeNode] = []
        var x = left
        for i in 0...last {
            let wordLeft = x
            x += widths[i]
            let s = states[i]
            guard s.opacity > 0.0005 else { continue }
            let j: (dx: CGFloat, dy: CGFloat, degrees: Double) = spec.jitter.map {
                $0.word == i ? hapticJitter(t, start: $0.start, duration: $0.duration, amplitude: $0.amplitude) : (0, 0, 0)
            } ?? (0, 0, 0)
            let c = CGPoint(x: wordLeft + widths[i] / 2, y: midY)
            let word = CGAffineTransform(translationX: wordLeft, y: baseline)
                .concatenating(.scaling(s.scale, about: c))
                .concatenating(.rotation(degrees: j.degrees, about: c))
                .concatenating(CGAffineTransform(translationX: j.dx, y: s.dy + j.dy))
            runs.append(.run(PlacedRun(shape: shapes[i], extra: extras[i], transform: word.concatenating(lineT),
                                       color: spec.colors[i] ?? style.color, opacity: s.opacity, blur: s.blur,
                                       tag: "\(name)#\(i)")))
        }
        return .group(runs, opacity: outOpacity, blur: outBlur)
    }
}

/// v3.1's TypeLine, as it was: SwiftUI Text, which Core Graphics puts on whole pixels. Only REEL_TYPE_LEGACY=1
/// draws it, to show what the outlines fixed (typecheck fails it).
struct LegacyTypeLine: View {
    let spec: LineSpec
    let t: Double

    var body: some View {
        if TypeProbe.shared.state.hidden {
            Color.clear.frame(width: 1, height: 1)
        } else {
            legacy
        }
    }

    private var legacy: some View {
        let last = spec.words.count - 1
        // Hold: +1.2 % linear from the end of the last word's snap to holdEnd.
        let snapEnd = spec.snap + (spec.cascade ? spec.step * Double(last) : 0) + 0.30
        let hold = spec.holdScale ? 1 + 0.012 * CGFloat(ramp(t, snapEnd, max(spec.holdEnd, snapEnd + 0.01))) : 1
        // Ease out: 0.20 s appleIn: opacity → 0, y −12, blur 0 → 8.
        var outOpacity = 1.0, outDy: CGFloat = 0, outBlur: CGFloat = 0
        if let e = spec.easeOut, t >= e {
            let p = ease(t, e, 0.20, .appleIn)
            outOpacity = 1 - p; outDy = -12 * CGFloat(p); outBlur = 8 * CGFloat(p)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(0...max(last, 0), id: \.self) { i in
                let s = snapState(t, start: spec.snap + (spec.cascade ? spec.step * Double(i) : 0))
                let j = spec.jitter.map { $0.word == i ? hapticJitter(t, start: $0.start, duration: $0.duration, amplitude: $0.amplitude) : (0, 0, 0) } ?? (0, 0, 0)
                Text(spec.words[i] + (i < last ? " " : ""))
                    .font(spec.style.font)
                    .tracking(spec.style.tracking + s.trackingExtra * spec.style.size)
                    .foregroundStyle(Color(hex: spec.colors[i] ?? spec.style.color))
                    .fixedSize()
                    .scaleEffect(s.scale)
                    .blur(radius: s.blur)
                    .rotationEffect(.degrees(j.2))
                    .offset(x: j.0, y: s.dy + j.1)
                    .opacity(s.opacity)
            }
        }
        .fixedSize()
        .scaleEffect(hold, anchor: spec.align == .center ? .center : .leading)
        .blur(radius: outBlur)
        .offset(y: outDy)
        .opacity(outOpacity)
        .placed(x: spec.x, baseline: spec.baseline, align: spec.align)
    }
}

extension View {
    /// Puts the view's first baseline at `baseline` and its centre (or leading edge) at `x`, in a
    /// full-canvas top-leading frame.
    func placed(x: CGFloat, baseline: CGFloat, align: LineAlign) -> some View {
        // An overlay never grows its base, so guides that put the text at negative coordinates don't
        // shift the canvas (a ZStack would).
        Color.clear
            .frame(width: Stage.size.width, height: Stage.size.height)
            .overlay(alignment: .topLeading) {
                self
                    .alignmentGuide(.leading) { d in align == .center ? d[HorizontalAlignment.center] : d[.leading] }
                    .alignmentGuide(.top) { d in d[.firstTextBaseline] }
                    .offset(x: x, y: baseline)
            }
    }
}

/// A plain (non-animated) line, for static layers like the lockup's small lines when they fade as a group. It
/// sits on whole pixels: its left edge (or centre) and its baseline are rounded.
struct StaticLine: View {
    let text: String
    let style: TypeStyle
    let x: CGFloat
    let baseline: CGFloat
    var align: LineAlign = .center
    var language: String? = nil
    var body: some View {
        GlyphCanvas(nodes: [StaticLine.node(text, style, x: x, baseline: baseline, align: align, language: language)])
    }

    static func node(_ text: String, _ style: TypeStyle, x: CGFloat, baseline: CGFloat, align: LineAlign = .center,
                     language: String? = nil) -> TypeNode {
        let shape = ShapedText.shape(text, style, language: language)
        let left = align == .center ? (x - shape.frameWidth / 2).rounded() : x.rounded()
        return .run(PlacedRun(shape: shape, transform: CGAffineTransform(translationX: left, y: baseline.rounded()),
                              color: style.color, tag: text))
    }
}
