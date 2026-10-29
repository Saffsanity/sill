// TypeViews.swift — statements, the snap-in / hold / ease-out recipes (§3.5) placed by baseline.
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
    var holdEnd: Double               // the hold's scale runs to here (usually the shot's end)
    var easeOut: Double? = nil        // start of the 0.20 s ease-out, if the shot asks for one
    var colors: [Int: UInt32] = [:]   // per-word colour overrides ("sit." in accent)
    var holdScale = true              // false: no +1.2 % hold (the lockup holds as one card)
    /// v2, note 7: one word vibrates like a Taptic buzz (word index, start, duration, amplitude in px).
    var jitter: (word: Int, start: Double, duration: Double, amplitude: CGFloat)? = nil

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

struct TypeLine: View {
    let spec: LineSpec
    let t: Double

    var body: some View {
        let last = spec.words.count - 1
        // Hold: +1.2 % linear from the end of the last word's snap to holdEnd.
        let snapEnd = spec.snap + (spec.cascade ? 0.05 * Double(last) : 0) + 0.30
        let hold = spec.holdScale ? 1 + 0.012 * CGFloat(ramp(t, snapEnd, max(spec.holdEnd, snapEnd + 0.01))) : 1
        // Ease out: 0.20 s appleIn: opacity → 0, y −12, blur 0 → 8.
        var outOpacity = 1.0, outDy: CGFloat = 0, outBlur: CGFloat = 0
        if let e = spec.easeOut, t >= e {
            let p = ease(t, e, 0.20, .appleIn)
            outOpacity = 1 - p; outDy = -12 * CGFloat(p); outBlur = 8 * CGFloat(p)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(0...max(last, 0), id: \.self) { i in
                let s = snapState(t, start: spec.snap + (spec.cascade ? 0.05 * Double(i) : 0))
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

/// A plain (non-animated) line, for static layers like the lockup's small lines when they fade as a group.
struct StaticLine: View {
    let text: String
    let style: TypeStyle
    let x: CGFloat
    let baseline: CGFloat
    var align: LineAlign = .center
    var body: some View {
        Text(text).font(style.font).tracking(style.tracking).foregroundStyle(Color(hex: style.color))
            .fixedSize()
            .placed(x: x, baseline: baseline, align: align)
    }
}
