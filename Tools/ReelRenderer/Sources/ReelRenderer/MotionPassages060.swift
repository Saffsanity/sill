// MotionPassages060.swift — the passages `motion` measures (Motion060.swift): each probe's edge, where to look for it
// (from the shot's own geometry and one measured place), and its path (the functions of time its place is a sum of,
// from the shot's own code). Times are the film's; a shifted scene's paths read its builder's own time through the time map
// (`inScene`, Cut060.builder: S13's, S14–S16's and the close's, v4's).
import Foundation

@MainActor enum MotionPassages060 {
    // MARK: Paths

    /// S01–S02: the icon's px per icon unit, its centre's y, the lockup's hold.
    static func openK(_ t: Double) -> Double {
        if t < Open060.rise { return Double(Open060.iconSize(t)) / 1024 }
        let rise = ease(t, Open060.rise, 0.6, .appleOut)
        return lerp(Double(Open060.iconSize(Open060.rise)), Double(Close060.iconSize), rise) / 1024
    }
    static func openCY(_ t: Double) -> Double {
        t < Open060.rise ? Double(Open060.centre.y) : lerp(Double(Open060.centre.y), Double(Close060.iconCentre.y), ease(t, Open060.rise, 0.6, .appleOut))
    }
    static func openHold(_ t: Double) -> Double { 1 + 0.012 * ramp(t, Open060.version + 0.30, Open060.cut) }
    /// S21–S22: the icon's rise as it fades in, and the card's hold (v4's times).
    static func closeIn(_ t: Double) -> Double { ease(Cut060.builder(t), Close060.iconIn, 0.5, .appleOut) }
    static func closeHold(_ t: Double) -> Double { 1 + 0.012 * ramp(Cut060.builder(t), Close060.holdFrom, Close060.fade) }
    static let lockupK = Double(Close060.iconSize) / 1024

    /// A push: 1 + amount · ramp(t, a, b).
    static func pushScale(_ a: Double, _ b: Double, _ amount: Double) -> (Double) -> Double { { t in 1 + amount * ramp(t, a, b) } }
    static func basis(_ f: @escaping (Double) -> Double) -> (Double) -> [Double] { { [f($0)] } }
    /// A path in a builder's own time, read at the film's (Cut060.builder).
    static func inScene(_ f: @escaping (Double) -> Double) -> (Double) -> Double { { f(Cut060.builder($0)) } }
    static func inScene(_ f: @escaping (Double) -> [Double]) -> (Double) -> [Double] { { f(Cut060.builder($0)) } }
    /// Where a point measured at `x0` at `t0` is at t under a scale `s(t)` about `c`.
    static func scaled(_ x0: Double, at t0: Double, about c: Double, _ s: @escaping (Double) -> Double) -> (Double) -> Double {
        { t in c + (x0 - c) * s(t) / s(t0) }
    }

    // MARK: S05's camera (11.6–14.4): the push to 1.14 and the drift, `camera(s · drift, from:, to:)`

    static var s05From: CGPoint { Pad060.canvas(CGPoint(x: (193 + 2235) / 2, y: 330)) }
    static func s05P(_ t: Double) -> Double { ease(t, Clip060.push, Clip060.pushEnd - Clip060.push, .appleOut) }
    static func s05Scale(_ t: Double) -> Double {
        (1 + (Double(Clip060.pushTo) - 1) * s05P(t)) * (1 + 0.012 * ramp(t, Clip060.pushEnd, 14.4))
    }
    static func s05To(_ t: Double) -> CGPoint {
        let f = s05From, p = s05P(t)
        return CGPoint(x: lerp(Double(f.x), 1490, p), y: lerp(Double(f.y), 430, p))
    }

    // MARK: S07's push about the picture's centre

    static var s07About: CGPoint {
        let pic = Lock060.picture
        return onCanvas(Lock060.spec, center: Lock060.centre, CGPoint(x: pic.midX, y: pic.midY))
    }

    // MARK: S08's camera about the iPad's lower left corner

    static func s08Scale(_ t: Double) -> Double {
        let L = Lock060.self
        let back = CubicBezier.inOut(ramp(t, L.pullBack, L.pullBackEnd))
        let close = Double(L.close) + 0.04 * ramp(t, 24.0, L.pullBack)
        return lerp(close, 1.0, back) * (1 + 0.01 * ramp(t, L.pullBackEnd, 28.8))
    }

    /// S10's keyboard: its offset below its place (interior px; the phone's interior is about the canvas's size).
    static func s10Keyboard(_ t: Double) -> Double {
        Double(SoftKeyboard060.offset(t, height: Larger060.keyboard.height * Larger060.spec.interior.width / Larger060.source.width,
                                      rise: Larger060.keyboardRise))
    }

    // MARK: S12's camera, S11's push

    /// v5's S12, the iPad upright: a still px (y) → the canvas, under its push about its left edge.
    static func s12Y(_ yStill: Double, _ t: Double) -> Double {
        let S = Scroll060.self
        let top = Double(S.uprightCentre.y - S.upright.interior.height / 2)
        return Double(S.uprightAbout.y) + (top + yStill * Double(S.ku) - Double(S.uprightAbout.y)) * Double(S.uprightPush(t))
    }
    static func s12Push(_ t: Double) -> Double { Double(Scroll060.uprightPush(t)) }
    static var s13About: CGPoint { onCanvas(Large060.spec, center: Large060.centre, CGPoint(x: 240 * Large060.k, y: 480 * Large060.k)) }
    static func s13Scale(_ t: Double) -> Double { 1 + 0.07 * CubicBezier.inOut(ramp(t, 44.0, 48.8)) }

    static var all: [MotionPassage] {
        let k = { (t: Double) in openK(t) }
        let p04 = pushScale(6.4, 10.4, 0.02), p06 = pushScale(14.4, 19.2, 0.02), p07 = pushScale(19.2, 24.0, 0.04)
        let p09 = pushScale(28.8, 32.8, 0.02), p10 = pushScale(32.8, 36.8, 0.02), p11 = pushScale(36.8, 40.8, 0.02)
        let p16 = pushScale(56.0, 59.2, 0.02)
        let a07 = s07About
        let w15 = { (t: Double) in ease(t, 54.4, 0.3, .appleOut) }
        return [
            // The open and the close: the icon (a Canvas).
            MotionPassage(name: "S01-push", from: 1.5, to: 2.4, probes: [
                MotionProbe(name: "iMac left edge", axis: .x, across: 380...420, guess: { 958.7 - 336 * k($0) }, path: basis(k), window: 6),
                MotionProbe(name: "iMac top edge", axis: .y, across: 825...855, guess: { 420 - 280 * k($0) }, path: basis(k), window: 6),
            ], note: "the icon pushing in 3 %"),
            MotionPassage(name: "S02-rise", from: 2.4, to: 3.05, probes: [
                MotionProbe(name: "foot bottom edge", axis: .y, across: 925...995, guess: { openCY($0) + 256 * k($0) }, path: { [openCY($0), k($0)] }, window: 6),
            ], note: "the icon rising into the lockup"),
            MotionPassage(name: "S02-hold", from: 3.8, to: 4.8, probes: [
                MotionProbe(name: "foot left edge", axis: .x, across: 405...412, guess: { 960 - 40.94 * openHold($0) }, path: basis(openHold), window: 6),
                MotionProbe(name: "foot bottom edge", axis: .y, across: 925...995, guess: { 540 + (340 + 256 * lockupK - 540) * openHold($0) }, path: basis(openHold), window: 6),
            ], note: "the lockup's +1.2 % hold"),
            // Act II: the iPad mini beside the words (turned 4°), and S06's (frontal).
            MotionPassage(name: "S04-push", from: 8.5, to: 10.4, probes: [
                MotionProbe(name: "screen right edge", axis: .x, across: 300...700, guess: scaled(1873.3, at: 7.95, about: 1031, p04), path: basis(p04)),
                MotionProbe(name: "screen top edge", axis: .y, across: 1300...1500, guess: scaled(299.2, at: 7.95, about: 560, p04), path: basis(p04)),
            ], note: "the turned iPad, a 2 % push"),
            MotionPassage(name: "S05-camera", from: 11.55, to: 14.4, probes: [
                MotionProbe(name: "iPad top rim", axis: .y, across: 1500...1600,
                            guess: { t in Double(s05To(t).y) + (275.6 - Double(s05From.y)) * s05Scale(t) },
                            path: { t in [s05Scale(t), Double(s05To(t).y)] }, window: 7, centroid: true),
            ], note: "the turned iPad's push to the chip and its drift"),
            MotionPassage(name: "S05-chip", from: 11.64, to: 12.1, probes: [
                MotionProbe(name: "chip's top edge", axis: .y, across: 1500...1800,
                            guess: { t in 64.5 + 12 * (1 - ease(t, ChipInset060.appear, 0.25, .appleOut)) },
                            path: { t in [ease(t, ChipInset060.appear, 0.25, .appleOut)] }, window: 5, centroid: true),
            ], note: "the chip's inset rising 12 px"),
            MotionPassage(name: "S06-push", from: 14.45, to: 17.55, probes: [
                MotionProbe(name: "iPad left rim", axis: .x, across: 500...700, guess: scaled(430.4, at: 14.5, about: 960, p06), path: basis(p06), window: 7, centroid: true),
                MotionProbe(name: "iPad top rim", axis: .y, across: 800...1100, guess: scaled(296.6, at: 14.5, about: 654, p06), path: basis(p06), window: 7, centroid: true),
            ], note: "the frontal iPad, a 2 % push"),
            MotionPassage(name: "S07-push", from: 19.65, to: 24.0, probes: [
                MotionProbe(name: "iPad left rim", axis: .x, across: 450...650, guess: scaled(1051.6, at: 19.65, about: Double(a07.x), p07), path: basis(p07), window: 7, centroid: true),
                MotionProbe(name: "screen top edge", axis: .y, across: 1300...1500, guess: scaled(296.0, at: 21.0, about: Double(a07.y), p07), path: basis(p07)),
            ], note: "the turned iPad with the lock screen, a 4 % push"),
            MotionPassage(name: "S07-cover", from: 19.9, to: 24.0, probes: [
                MotionProbe(name: "lock screen right edge", axis: .x, across: 450...650, guess: scaled(1837.0, at: 21.0, about: Double(a07.x), p07), path: basis(p07)),
                MotionProbe(name: "lock screen bottom edge", axis: .y, across: 1300...1500, guess: scaled(818.2, at: 21.0, about: Double(a07.y), p07), path: basis(p07), window: 3, tolerance: 0.2),
            ], note: "the lock screen's edges, the lock screen up; its bottom read in the 6 px of black above the bezel (0.2 px)"),
            MotionPassage(name: "S08-camera", from: 24.0, to: 28.8, probes: [
                MotionProbe(name: "iPad top rim", axis: .y, across: 1200...1400,
                            guess: { t in Double(Lock060.anchor.y) + (44.6 - Double(Lock060.anchor.y)) * s08Scale(t) / s08Scale(24.1) },
                            path: basis(s08Scale), window: 7, centroid: true, tolerance: 0.15),
            ], note: "the frontal iPad, close, back and a push; read at up to 6 px a frame in the pull-back (0.15 px)"),
            // Act III.
            MotionPassage(name: "S09-push", from: 29.25, to: 30.9, probes: [
                MotionProbe(name: "iPad top rim", axis: .y, across: 1000...1400, guess: scaled(101.5, at: 29.25, about: 565, p09), path: basis(p09), window: 7, centroid: true),
            ], note: "the frontal iPad's 2 % push while the sheet zooms"),
            MotionPassage(name: "S10-push", from: 32.85, to: 36.8, probes: [
                MotionProbe(name: "phone right rim", axis: .x, across: 400...700, guess: scaled(1609.0, at: 36.0, about: 1390, p10), path: basis(p10), window: 7, centroid: true),
                MotionProbe(name: "phone left rim", axis: .x, across: 400...700, guess: scaled(1167.0, at: 36.0, about: 1390, p10), path: basis(p10), window: 7, centroid: true),
            ], note: "the turned iPhone, a 2 % push"),
            MotionPassage(name: "S10-keyboard", from: 34.68, to: 35.25, probes: [
                MotionProbe(name: "a key's top edge", axis: .y, across: 1400...1418,
                            guess: { t in 1036 + (705.91 + s10Keyboard(t) - 1036) * p10(t) / p10(36.0) },
                            path: { t in [p10(t), p10(t) * s10Keyboard(t)] }, window: 6),
            ], note: "v5: iOS's keyboard rising inside the turned iPhone onto the trackpad's footprint (0.30 s appleOut), with its 2 % push; read on its first row's sixth key (the keyboard's own top edge crosses the trackpad's), from 23 px a frame (its first three frames, 75, 51 and 35 px a frame, measure within 0.6 px)"),
            MotionPassage(name: "S12-fingers", from: 41.05, to: 41.3, probes: [
                MotionProbe(name: "a finger's dot", axis: .y, across: 1474...1498,
                            guess: { t in s12Y(Double(Scroll060.fingersFrom[0].y - Scroll060.fingerTravel(t, Scroll060.flingA)), t) },
                            path: { t in [s12Push(t), s12Push(t) * Double(Scroll060.fingerTravel(t, Scroll060.flingA))] }, window: 34, centroid: true, tolerance: 0.25),
            ], note: "v5: two fingers on the upright iPad's trackpad, scrolling (smoothstep in over 0.1 s, then steady), with its push; a touch dot is a dim disc between a dark and a bright ring, whose centroid reads within 0.25 px at 4.6 px a frame (it moves by a render transform, exact in `motion primitives`)"),
            MotionPassage(name: "S12-scroll", from: 41.05, to: 41.3, probes: [
                MotionProbe(name: "the scroller's top", axis: .y, across: 1807...1807,
                            guess: { t in s12Y(112 + (208 + Scroll060.uprightOffset(t) / 4200 * 1612) * 0.505556, t) },
                            path: { t in [s12Push(t), s12Push(t) * Scroll060.uprightOffset(t)] }, window: 5, tolerance: 0.12),
            ], note: "v5: the document scrolled by the fingers, read on its scroller (a shape on the page's offset) while they are down; the scroller is 2.8 px wide and drifts right with the push across the probe's column, its rounded top read within 0.12 px"),
            MotionPassage(name: "S11-push", from: 36.85, to: 40.8, probes: [
                MotionProbe(name: "screen right edge", axis: .x, across: 250...400, guess: scaled(1815.0, at: 37.0, about: 1030, p11), path: basis(p11), window: 4),
                MotionProbe(name: "iPad top rim", axis: .y, across: 1500...1700, guess: scaled(129.0, at: 37.0, about: 520, p11), path: basis(p11), window: 7, centroid: true),
            ], note: "the iPad and its keyboard (laid back 58°), a 2 % push"),
            MotionPassage(name: "S13-push", from: Cut060.film(44.05, .s13), to: Cut060.film(48.8, .s13), probes: [
                MotionProbe(name: "iPad top rim", axis: .y, across: 1000...1400, guess: inScene(scaled(102.6, at: 44.0, about: Double(s13About.y), s13Scale)), path: inScene(basis(s13Scale)), window: 7, centroid: true),
                MotionProbe(name: "iPad left rim", axis: .x, across: 400...700, guess: inScene(scaled(862.6, at: 44.0, about: Double(s13About.x), s13Scale)), path: inScene(basis(s13Scale)), window: 7, centroid: true),
            ], note: "the frontal iPad, a 7 % push (inOut)"),
            MotionPassage(name: "S14-drift", from: Cut060.film(48.85, .s14s15), to: Cut060.film(50.35, .s14s15), probes: [
                MotionProbe(name: "tile's edge", axis: .x, across: 290...310,
                            guess: inScene { t in 1400 + (1404.5 + 6 * 0.2 - 1400 - 6 * (t - 48.8)) * (1 + 0.02 * ramp(t, 48.8, 52.8)) },
                            path: inScene { t in let s = 1 + 0.02 * ramp(t, 48.8, 52.8); return [s, s * (t - 48.8)] }, window: 6),
            ], note: "the tiles drifting 6 px a second and pushing in 2 %"),
            MotionPassage(name: "S16-push", from: Cut060.film(57.6, .s16), to: Cut060.film(59.2, .s16), probes: [
                MotionProbe(name: "thumbnail's edge", axis: .x, across: 380...390, guess: inScene(scaled(670.6, at: 57.5, about: 525.7, p16)), path: inScene(basis(p16)), window: 3),
            ], note: "the bar's thumbnails, a 2 % push"),
            MotionPassage(name: "S16-row", from: Cut060.film(58.05, .s16), to: Cut060.film(59.2, .s16), probes: [
                MotionProbe(name: "row's bottom edge", axis: .y, across: 300...700,
                            guess: inScene { t in 873 + 40 * (1 - ease(t, Hold060.row, 0.35, .appleOut)) },
                            path: inScene { t in [ease(t, Hold060.row, 0.35, .appleOut)] }, window: 5),
            ], note: "the Settings row sliding in 40 px"),
            MotionPassage(name: "S15-window", from: Cut060.film(54.4, .s14s15), to: Cut060.film(56.0, .s14s15), probes: [
                MotionProbe(name: "window left edge", axis: .x, across: 560...650, guess: inScene { 294.66 + 49.88 * w15($0) }, path: inScene(basis(w15)), window: 6),
                MotionProbe(name: "window top edge", axis: .y, across: 420...540, guess: inScene { 490.36 + 37.84 * w15($0) }, path: inScene(basis(w15)), window: 6, tolerance: 0.25),
            ], note: "the Mac's window shrinking back to its own size; its top edge is two shapes' (the strip over the body), whose anti-aliasing adds up differently at each phase (0.25 px), its left edge one's"),
            MotionPassage(name: "S20-bug", from: Cut060.film(70.4, .close), to: Cut060.film(71.1, .close), probes: [
                MotionProbe(name: "bug's dot", axis: .y, across: 955...965,
                            guess: { Double(Fixes060.screenY(Fixes060.bugBase, Cut060.builder($0))) - 54 },
                            path: { [Fixes060.scroll(Cut060.builder($0))] }, window: 5, centroid: true),
            ], note: "the bug riding in with the column"),
            MotionPassage(name: "S21-icon", from: Cut060.film(72.05, .close), to: Cut060.film(72.7, .close), probes: [
                MotionProbe(name: "foot bottom edge", axis: .y, across: 925...995, guess: { 340 + 12 * (1 - closeIn($0)) + 256 * lockupK },
                            path: basis(closeIn), window: 6),
            ], note: "the icon rising 12 px as it fades in"),
            MotionPassage(name: "S22-hold", from: Cut060.film(73.4, .close), to: Cut060.film(77.6, .close), probes: [
                MotionProbe(name: "foot left edge", axis: .x, across: 405...412, guess: { 960 - 40.94 * closeHold($0) }, path: basis(closeHold), window: 6),
                MotionProbe(name: "foot bottom edge", axis: .y, across: 925...995, guess: { 540 + (340 + 256 * lockupK - 540) * closeHold($0) }, path: basis(closeHold), window: 6),
            ], note: "the end card's +1.2 % hold"),
        ]
    }
}

/// `motion seal [--from s] [--to s] [--every n] [--mp4 movie]`: S07–S08 while the lock screen is up (19.85–26.0): does any
/// of the stream picture under it (Weather, brighter than the lock screen and the black round it) show at its edges? Each
/// edge is followed frame by frame (where the lock screen's level falls to the panel's black, or rises to the bar's grey
/// over its top), and across it, row by row (or column by column), the brightest pixel within 4 px of it is compared with
/// the levels on both sides: a seal shows nothing above both (the anti-aliased edge only blends the two); the picture
/// peeking out shows as a bright line, the excess. Reports each edge's worst and mean excess, and the frames with any
/// over 3 levels.
@MainActor func sealCommand(_ args: [String]) throws {
    var from = 19.85, to = 26.0, every = 1, movieStart = 0.0
    var movie: URL?
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--from": from = Double(args[i + 1])!; i += 2
        case "--to": to = Double(args[i + 1])!; i += 2
        case "--every": every = max(1, Int(args[i + 1])!); i += 2
        case "--mp4": movie = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--mp4-from": movieStart = Double(args[i + 1])!; i += 2
        default: i += 1
        }
    }
    let frames = try MotionFrames(movie: movie, startingAt: Int((movieStart * 60).rounded()))
    let f0 = Int((from * 60).rounded()), f1 = Int((to * 60).rounded()) - 1
    try frames.prepare(f0...f1)
    // The lock screen's corners on the canvas for the unturned iPad at rest; the push or camera moves them, and the search
    // follows each edge from frame to frame.
    let pic = Lock060.picture
    let tl = onCanvas(Lock060.spec, center: Lock060.centre, pic.origin), br = onCanvas(Lock060.spec, center: Lock060.centre, CGPoint(x: pic.maxX, y: pic.maxY))
    enum Side: String, CaseIterable { case right, bottom, left, top }
    var pos: [Side: Double] = [:]
    var worst: [Side: Double] = [:], sum: [Side: Double] = [:], count: [Side: Int] = [:], over3: [Side: Int] = [:]
    var worstFrame: [Side: Int] = [:]
    print("seal: \(movie.map { "decoded from \($0.lastPathComponent)" } ?? "rendered without the finish"), \(String(format: "%.2f–%.2f s", from, to))")
    for f in stride(from: f0, through: f1, by: every) {
        let t = Double(f) / 60
        let lum = try frames.luma(f)
        // Where the unturned, unmoved corners land under this frame's move (S07's push, S08's camera), for a first look.
        let s07 = CGAffineTransform.scaling(1 + 0.04 * CGFloat(ramp(t, 19.2, 24.0)), about: MotionPassages060.s07About)
        let s08 = CGAffineTransform.scaling(CGFloat(MotionPassages060.s08Scale(t)), about: Lock060.anchor)
        let m = t < 24.0 ? s07 : s08
        let a = tl.applying(m), b = br.applying(m)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), half = CGSize(width: (b.x - a.x) / 2, height: (b.y - a.y) / 2)
        for side in Side.allCases {
            let horizontal = side == .right || side == .left            // the edge runs down: rows across it
            let sign: Double = side == .right || side == .bottom ? 1 : -1  // outward
            let guess = pos[side] ?? Double(horizontal ? (side == .right ? b.x : a.x) : (side == .bottom ? b.y : a.y))
            // The middle 60 % of the edge's length (clear of the corners, and of the field and the clock's glyphs); from 24.0
            // the sides' upper part only (S08's keyboard covers the picture's lower 44 %, and its keys reach the edges).
            let lo = horizontal ? mid.y - half.height * 0.6 : mid.x - half.width * 0.6
            let hi = horizontal ? (t >= 24.0 ? mid.y - half.height * 0.05 : mid.y + half.height * 0.6) : mid.x + half.width * 0.6
            let lines = Array(Int(lo)...Int(hi)).filter { $0 >= 0 && $0 < (horizontal ? lum.height : lum.width) }
            guard lines.count > 10 else { continue }
            // The edge: where the profile (averaged along the edge) crosses halfway between the levels 12–8 px inside and
            // 8–12 px outside, searched within ±12 px of the last frame's.
            func P(_ along: Int, _ across: Double) -> Double {
                let x = Int(across.rounded(.down))
                guard x >= 0, x < (horizontal ? lum.width : lum.height) else { return .nan }
                return horizontal ? lum.at(x, along) : lum.at(along, x)
            }
            var prof: [Double] = []
            let start = guess - 16 * sign
            for k in 0..<33 { let c = start + Double(k) * sign; prof.append(lines.map { P($0, c) }.reduce(0, +) / Double(lines.count)) }
            guard !prof.contains(where: { $0.isNaN }) else { continue }
            let inside = (prof[0] + prof[1] + prof[2]) / 3, outside = (prof[30] + prof[31] + prof[32]) / 3
            // Where the two levels are too close to find the edge by them (the top: the lock screen's dark blue against the
            // bar's grey), it is where the iPad's move puts it, and the band round it is wider.
            var edge = guess, band = 6
            if abs(inside - outside) > 3 {
                var e = 0.0
                for v in prof { e += 1 - (v - inside) / (outside - inside) }       // area: px from the start to the edge
                edge = start + sign * (e - 0.5)
                pos[side] = edge
                band = 4
            }
            // Across the edge, line by line: the brightest pixel within 4 px of it, over both sides' levels there.
            var excessMax = 0.0, excessSum = 0.0
            for l in lines {
                let d = Double(band + 5)
                let inner = (P(l, edge - d * sign) + P(l, edge - (d + 1) * sign) + P(l, edge - (d + 2) * sign)) / 3
                let outer = (P(l, edge + d * sign) + P(l, edge + (d + 1) * sign) + P(l, edge + (d + 2) * sign)) / 3
                var peak = -Double.infinity
                for k in -band...band { peak = max(peak, P(l, edge + Double(k))) }
                let ex = max(0, peak - max(inner, outer))
                excessMax = max(excessMax, ex); excessSum += ex
            }
            let mean = excessSum / Double(lines.count)
            if excessMax > worst[side] ?? -1 { worst[side] = excessMax; worstFrame[side] = f }
            sum[side, default: 0] += mean; count[side, default: 0] += 1
            if excessMax > 3 { over3[side, default: 0] += 1 }
        }
    }
    var leaked = false
    for side in Side.allCases {
        guard let n = count[side], n > 0 else { print("  \(side.rawValue): no edge found"); continue }
        let w = worst[side] ?? 0
        if (over3[side] ?? 0) > 0 { leaked = true }
        print(String(format: "  %-6@ %3d frames  brightest over both sides: worst %.1f levels (frame %d, %.3f s), mean of each frame's mean %.2f  frames over 3 levels: %d",
                     side.rawValue as NSString, n, w, worstFrame[side] ?? 0, Double(worstFrame[side] ?? 0) / 60, (sum[side] ?? 0) / Double(n), over3[side] ?? 0))
    }
    print(leaked ? "seal: the picture shows at an edge" : "seal: no edge shows the picture")
    if leaked { exit(1) }
}
