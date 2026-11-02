// Assets060Fixes.swift — S19–S20, the one cutaway, "Fixed in 0.6." (storyboard §3): the fixes scroll up in a column,
// the last thing in it is a bug drawn like the reel's devices, a touch squashes it on the beat, and it splats: specks of
// its ink fly out along the sill line, its body spreads into a puddle that settles and thins into the 2 px accent sill
// line the close stands on (y 666).
//
// v4.1 (Noah's notes of 2026-11-02): the cutaway runs on film time, 112.0–123.2 (v4: 65.6–72.0). Every transition is
// 1.25× v4's (the title's snap, the scroll's start and its slowing, the column's steps, the line's thinning and stretch);
// the title holds still 2.25 s after it is in; the scroll runs at 300 px/s (v4: 450), so each line crosses the middle on
// an eighth of the 150 BPM grid; the squash is on the beat at 122.0 (frame 7320), the close at 123.2. "The bug needs a
// better splat animation when it is smashed": on the squash, 12 ink specks in the device black with grey rims and 3 in
// the accent fly out along the sill line and a little up, decelerating, smeared for their first frames; the body spreads
// into a wider, uneven puddle with a soft edge that settles over 0.35 s, then thins into the line; a one-frame flash of
// the accent under the body at the hit (Splat060). The column's type is drawn as glyph outlines at its exact scroll
// position (Shots060Mac.swift), so it glides at 5 px a frame without a whole-pixel step.
import AppKit
import SwiftUI

enum Fixes060 {
    // MARK: The beats (film s)

    static let start = 112.0, end = 123.2
    /// The close (S21) begins on the line at 123.2, a bar line.
    static let closeStart = 123.2
    /// 1. The title snaps (T1s) on the hard cut to black: v4's snap (its 65.65) played 1.25× slower, from 112.05.
    static let titleSnap = 112.05, titleSnapV4 = 65.65
    /// The title's own clock: v4's time for its snap and cascade, 1.25× slower.
    static func titleClock(_ t: Double) -> Double { titleSnapV4 + 0.8 * (t - titleSnap) }
    /// 2. The scroll: still until 114.8 (the title in by 112.55 and held 2.25 s), up to speed over 0.375 s (v4: 0.3),
    /// then 300 px/s (v4: 450): a line every eighth (0.2 s), its tick on the grid.
    static let scrollStart = 114.8, accelEnd = 115.175
    /// 3. The bug rides in: the scroll slows (appleOut from the cruise's speed) to rest exactly at the tap, over 0.883 s
    /// (v4's 0.7065, 1.25×); the slowing carries the bug onto the sill line and the column's 6 px overshoot.
    static let brakeDuration = 0.7065 * 1.25
    static var brakeStart: Double { tap - brakeDuration }
    /// 4. The touch dot appears over the bug 0.1 s before the tap (v4: 0.08); 5. the anticipation stretch (0.075 s).
    static let dotAppears = 121.9, stretchEnd = 121.975
    /// 6. The squash: on the beat (frame 7320) it is already three quarters flat: its 0.08 s appleOut (an impact, kept
    /// quick) starts a frame before; the legs splay flat and fade (0.15 s).
    static let tap = 122.0, squashStart = 122.0 - 1.0 / 60, squashDuration = 0.08, legsGone = 0.15
    /// 7. The splat (Splat060): the specks fly out from just before the beat's frame; the puddle settles over 0.35 s; the
    /// haptic jitter (v3's: 18 Hz, 3 px, 0.3 s); the column's 6 px return from its overshoot (0.375 s), at rest at both ends.
    static let settleEnd = 122.375, puddleSettle = 0.35, jitterDuration = 0.3
    /// 8. The line: the settled puddle turns accent and thins to 2 px (122.35–122.5), then stretches (ease in and out) to
    /// the lockup's sill line, 520 px (122.5–122.9125).
    static let morph = 122.35, morphDuration = 0.15, lineStretch = 0.33 * 1.25
    /// 9. Black and the sill line alone, to the close.
    static let lineAlone = morph + morphDuration + lineStretch
    /// The touch dot fades from here (0.3125 s).
    static let dotFade = 122.25

    static let speed = 300.0
    static let overshoot: CGFloat = 6

    // MARK: The column

    static let columnX: CGFloat = 480
    /// The title's baseline while it is alone (v3's T1s statement line, as "Latency you don’t notice.").
    static let titleBaseline: CGFloat = 540
    static let linePitch: CGFloat = 60
    /// A header 64 px over its group's first line, and 180 px (three line pitches: three eighths at 300 px/s) from a
    /// group's last line to the next group's first, so every line crosses the middle on the eighths' grid and the score's
    /// ticks fall in time.
    static let headerToLine: CGFloat = 64, groupStep: CGFloat = 180
    /// The top and bottom 140 px fade the column out.
    static let fade: CGFloat = 140
    static let lineSize: CGFloat = 44, lineTracking: CGFloat = -0.5
    static let headerSize: CGFloat = 28
    /// The first line crosses the middle on the grid's 11th step (117.0): the first header then starts just below the
    /// frame, so the title is alone, and the bug ends 247 px under the last line.
    static let firstCrossingStep = 11

    /// The fixes, one line each, under three headers (storyboard §3, verbatim; traced in its §7).
    static let groups: [(header: String, lines: [String])] = [
        ("On iPhone and iPad", [
            "Finds your Mac again after hours in the background.",
            "A saved Mac stays saved after a force quit.",
            "A trackpad\u{2019}s two-finger scroll moves the window.",
        ]),
        ("On the Mac", [
            "A 1x display fills the picture, and Aa works there.",
            "The Desktop no longer stays black when displays change.",
            "The display wakes when a device connects.",
            "Virtual displays come up at Retina scale.",
            "Settings fits a small screen.",
            "Firewall in the way? Settings gives the command to fix it.",
            "Tailscale from the Mac App Store, listed in Remote Access.",
        ]),
        ("Security", [
            "A renamed copy of Sill.app takes no test hook.",
            "A device\u{2019}s viewport can no longer crash Sill for Mac.",
            "Waiting connections can\u{2019}t hold every place.",
            "Direct Wireless changes only from a paired device, at home.",
            "A removed device lands no more input.",
            "Reconnecting to a Mac you never paired accepts only the key it saw.",
        ]),
    ]
    /// v4.1: "0.6", not "0.6.0" (Noah).
    static let title = ["Fixed", "in", "0.6."]

    // MARK: The sill line it ends on (the lockup's, S21)

    /// The lockup's own sill line: S01–S02's (Open060), y 666, 520 px (its ink 493 px: the faded ends).
    static let sillY: CGFloat = 666, sillLength: CGFloat = 520, sillX: CGFloat = 960
    /// The bug walks up the column's middle, and flattens there.
    static let bugX: CGFloat = 960
    /// The flattened bug's foot comes to rest on the sill line's lower edge.
    static var restingBase: CGFloat { sillY + 1 }

    // MARK: The scroll

    /// appleOut's slope at 0 (its first control point is (0.16, 1)).
    private static let appleOutSlope = 1 / 0.16

    /// How far the column has scrolled up at `t`, in px. Smooth (continuous speed) from rest through the cruise and the
    /// slowing, at rest at the tap 6 px past where it settles, then back by those 6 px (122.0–122.375), at rest at both ends.
    static func scroll(_ t: Double) -> Double {
        if t <= scrollStart { return 0 }
        let a = accelEnd - scrollStart
        if t < accelEnd {
            let u = (t - scrollStart) / a          // speed × smoothstep(u), integrated
            return speed * a * (u * u * u - u * u * u * u / 2)
        }
        let s0 = speed * a / 2
        let b = brakeStart
        if t < b { return s0 + speed * (t - accelEnd) }
        let s1 = s0 + speed * (b - accelEnd)
        let d = tap - b
        let brake = speed * d / appleOutSlope      // so the speed at the brake's start is still the cruise's
        if t < tap { return s1 + brake * CubicBezier.appleOut((t - b) / d) }
        let peak = s1 + brake
        let u = clamp01((t - tap) / (settleEnd - tap))
        return peak - Double(overshoot) * (1 - cos(Double.pi * u)) / 2
    }
    /// Where the column comes to rest, after its overshoot's return.
    static var restScroll: Double { scroll(tap) - Double(overshoot) }

    /// Screen y of a point `y` px down the column (the title's baseline is 0) at `t`.
    static func screenY(_ y: CGFloat, _ t: Double) -> CGFloat { titleBaseline + y - CGFloat(scroll(t)) }

    // MARK: The column's layout (y down from the title's baseline)

    enum Item { case header(String), line(String) }
    struct Placed { let item: Item; let y: CGFloat }

    static let xHeight: CGFloat = Outline060.font(size: lineSize, weight: .medium).xHeight

    /// The first line's baseline, so it crosses the middle (its x-height's middle at y 540) on the grid's step.
    static var firstLine: CGFloat {
        let tc = scrollStart + Double(firstCrossingStep) / (speed / Double(linePitch))
        return CGFloat(scroll(tc)) + 540 + xHeight / 2 - titleBaseline
    }

    static let placed: [Placed] = {
        var out: [Placed] = []
        var y = firstLine
        for (g, group) in groups.enumerated() {
            if g > 0 { y += groupStep - linePitch }
            out.append(Placed(item: .header(group.header), y: y - headerToLine))
            for line in group.lines {
                out.append(Placed(item: .line(line), y: y))
                y += linePitch
            }
        }
        return out
    }()

    /// The bug's base down the column: where the settle leaves it on the sill line.
    static var bugBase: CGFloat { restingBase - titleBaseline + CGFloat(restScroll) }

    /// When each line crosses the middle (its x-height's middle at y 540): the score's quiet ticks.
    static var crossings: [Double] {
        placed.compactMap { p in
            guard case .line = p.item else { return nil }
            let target = Double(titleBaseline + p.y - xHeight / 2 - 540)   // the scroll at which it crosses
            var lo = scrollStart, hi = tap
            guard scroll(hi) >= target else { return nil }
            for _ in 0..<60 { let m = (lo + hi) / 2; if scroll(m) < target { lo = m } else { hi = m } }
            return (lo + hi) / 2
        }
    }

    /// The lines' opacity: whole, then back to 45 % with the squash (0.375 s appleOut), then out (0.375 s from the morph).
    static func columnOpacity(_ t: Double) -> Double {
        let back = 1 - 0.55 * ease(t, tap, 0.375, .appleOut)
        return back * (1 - CubicBezier.inOut(ramp(t, morph, morph + 0.375)))
    }

    // MARK: The bug's state

    struct BugState {
        var base: CGPoint
        /// The whole bug's scale about its base: (1, 1) walking, (0.94, 1.10) stretched, (1.80, 0.14) squashed.
        var sx: CGFloat = 1, sy: CGFloat = 1
        /// The squash's progress (0 … 1): the shell spreads into the puddle, the legs splay flat.
        var squash: CGFloat = 0
        var legAlpha: Double = 1
        /// The gait's clock (frozen at the touch) and the sway's amplitude.
        var gaitTime: Double
        var sway: Double = 1
        var jitter: (dx: CGFloat, dy: CGFloat, degrees: Double) = (0, 0, 0)
        /// The accent dot: its flare (0 … 1) and its alpha.
        var flare: Double = 0, dotAlpha: Double = 1
        /// The puddle the body spreads into (px, its own size as it settles) and how uneven its edge is (px).
        var puddleWidth: CGFloat = 0, puddleHeight: CGFloat = 0, wobble: CGFloat = 0, wobblePhase: Double = 0
        /// 0 the puddle … 1 the 2 px accent line (its fill, its thickness; the rim, gloss and seam fade).
        var morph: Double = 0
        /// The line's length while it stretches (px).
        var length: CGFloat = 0
        /// 0 the bug's own accent line … 1 handed over to `SillLine`'s look.
        var look: Double = 0
    }

    /// The puddle at rest: 188 px wide (1.96 × the bug's footprint), 11 px tall.
    static let puddleWidth: CGFloat = 188, puddleHeight: CGFloat = 11

    static func bugState(_ t: Double) -> BugState {
        var s = BugState(base: CGPoint(x: bugX, y: screenY(bugBase, t)), gaitTime: min(t, dotAppears))
        s.sway = 1 - ramp(t, dotAppears - 0.2, dotAppears)
        // 5. Anticipation: tall and narrow.
        let a = CGFloat(ease(t, dotAppears, stretchEnd - dotAppears, .appleOut))
        s.sx = 1 - 0.06 * a; s.sy = 1 + 0.10 * a
        // 6. The squash, pinned at the base: three quarters flat on the beat's frame.
        let q = CGFloat(ease(t, squashStart, squashDuration, .appleOut))
        s.squash = q
        s.sx = lerp(s.sx, 1.80, Double(q)); s.sy = lerp(s.sy, 0.14, Double(q))
        s.legAlpha = 1 - ramp(t, squashStart, squashStart + legsGone)
        // The accent dot flares with the flattening it marks, from the frame after the beat's, not before it.
        s.flare = t >= tap + 1.0 / 120 ? 1 - ramp(t, tap + 0.03, tap + 0.25) : 0
        s.dotAlpha = 1 - ramp(t, tap + 0.06, tap + 0.25)
        // 7. The puddle: from the squash it spreads past its rest and settles, a damped wobble of its width and height and
        // its uneven edge calming, over 0.35 s; the jitter, v3's haptic, buzzes it for 0.3 s.
        let u = max(0, t - tap)
        let swing = exp(-u / 0.09) * cos(2 * Double.pi * u / 0.24)
        s.puddleWidth = puddleWidth * CGFloat(1 + 0.07 * swing)
        s.puddleHeight = puddleHeight * CGFloat(1 - 0.28 * swing)
        s.wobble = CGFloat(1.5 + 2.6 * exp(-u / 0.14))
        s.wobblePhase = 1.6 * (1 - exp(-u / 0.12))
        s.jitter = buzz(t, start: tap, duration: jitterDuration, amplitude: 3)
        // 8. The line: the puddle itself turns accent and thins to 2 px, its edge evening out (0.15 s), then stretches,
        // easing in and out, from its own 188 px to the lockup's line (0.4125 s): none of it a pop.
        s.morph = ease(t, morph, morphDuration, .inOut)
        s.length = lerp(puddleWidth, sillLength, CubicBezier.inOut(ramp(t, morph + morphDuration, morph + morphDuration + lineStretch)))
        s.look = ramp(t, morph + morphDuration, lineAlone)
        return s
    }

    /// v3's "haptic" jitter (TypeViews.swift `hapticJitter`, note 7), kept here so the cutaway does not depend on the
    /// type's file: an 18 Hz buzz of `amplitude` px across, half that down and ±1° of twist, in over 0.04 s and
    /// settling over the last 0.12 s.
    static func buzz(_ t: Double, start: Double, duration: Double, amplitude: CGFloat) -> (dx: CGFloat, dy: CGFloat, degrees: Double) {
        guard t >= start, t <= start + duration else { return (0, 0, 0) }
        let u = t - start
        let env = min(1, u / 0.04) * min(1, (start + duration - t) / 0.12)
        let w = 2 * Double.pi * 18
        return (amplitude * CGFloat(sin(w * u) * env), amplitude * 0.5 * CGFloat(sin(w * u * 1.5 + 1.1) * env),
                1.0 * sin(w * u * 0.75 + 2.0) * env)
    }

    /// The touch dot: v3's tap dot (0.7 → 1 over 0.15 s from 121.9), pinned where the finger lands, on the bug's upper back
    /// (its head and the top of its shell, at x 960, y 604), 72 px and light, so the stretch under it and the shell's lower
    /// half beside it read; it fades from 122.25 (0.3125 s).
    static let dotDiameter: CGFloat = 72
    static let dotCentre = CGPoint(x: 960, y: 604)
    static func dot(_ t: Double, _ bug: BugState) -> (center: CGPoint, scale: CGFloat, alpha: Double)? {
        guard t >= dotAppears, t < dotFade + 0.3125 else { return nil }
        let scale = CGFloat(0.7 + 0.3 * ease(t, dotAppears, 0.15, .appleOut))
        return (dotCentre, scale, 1 - ramp(t, dotFade, dotFade + 0.3125))
    }

    // MARK: The shot

    /// S19–S20 at `t` (112.0–123.2): black, the column (title, headers, lines, bug) inside the 140 px fades, the touch
    /// dot, the splat, the line. From 122.9125 black and the sill line alone (exactly `SillLine(y: 666, length: 520)`).
    @MainActor static func frame(_ t: Double) -> FrameLayers {
        let v = ZStack {
            Color.black
            FixesColumn060(t: t)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fade / Stage.size.height),
                                             .init(color: .white, location: 1 - fade / Stage.size.height), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom).canvas())
            FixesLine060(t: t)
        }.canvas()
        return FrameLayers(base: any(v))
    }
}

// MARK: - The column

/// The title, the headers and the lines at their scroll position, and the bug at the column's end (with the touch
/// dot over it, its splat's flash under it and its specks), before the fades' mask.
struct FixesColumn060: View {
    let t: Double
    /// False in the film: its type is FixesType060's (Shots060Mac.swift), glyph outlines on the scroll's path that
    /// typecheck measures; this view then draws the bug and its touch dot. True for the asset previews.
    var drawsType = true
    var body: some View {
        Canvas { ctx, _ in
            let F = Fixes060.self
            // The title: v3's snap, word by word, then it scrolls with the column.
            let ty = F.screenY(0, t)
            if drawsType && ty > -60 {
                Outline060.snapLine(F.title, in: &ctx, t: F.titleClock(t), snap: F.titleSnapV4, size: TypeStyle.T1s.size, weight: .bold,
                                    tracking: TypeStyle.T1s.tracking, color: Color(hex: Palette.text1),
                                    x: F.columnX, baseline: ty, leading: true)
            }
            let alpha = F.columnOpacity(t)
            if drawsType && alpha > 0.002 {
                var c = ctx
                c.opacity = alpha
                for p in F.placed {
                    let y = F.screenY(p.y, t)
                    guard y > -80, y < Stage.size.height + 80 else { continue }
                    switch p.item {
                    case .header(let s):
                        Outline060.draw(s, in: &c, size: F.headerSize, weight: .regular, x: F.columnX, baseline: y, leading: true,
                                        color: Color(hex: Palette.text3))
                    case .line(let s):
                        Outline060.draw(s, in: &c, size: F.lineSize, weight: .medium, tracking: F.lineTracking, x: F.columnX, baseline: y,
                                        leading: true, color: Color(hex: Palette.text1))
                    }
                }
            }
            let bug = F.bugState(t)
            // The splat: the flash under the body on the beat's frame, the body (the puddle), then the specks over it.
            Splat060.drawFlash(&ctx, base: bug.base, t: t)
            if bug.base.y < Stage.size.height + 140 && t < F.lineAlone {
                Bug060.draw(&ctx, bug, t: t)
            }
            Splat060.draw(&ctx, base: bug.base, t: t)
            if let d = F.dot(t, bug) {
                let dd = F.dotDiameter * d.scale
                var c = ctx
                c.opacity = d.alpha
                let r = CGRect(x: d.center.x - dd / 2, y: d.center.y - dd / 2, width: dd, height: dd)
                c.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.14)))
                c.stroke(Path(ellipseIn: r.insetBy(dx: 1, dy: 1)), with: .color(.white.opacity(0.42)), lineWidth: 2)
            }
        }
        .canvas()
    }
}

/// The sill line taking over from the bug: from the morph its glow fades in under the stretching line (the bug's
/// own shell, drawn by `Bug060`), and over 71.52–71.85 the line hands over to `SillLine`'s own look (its 35 % core
/// with faded ends, its glow), so from 71.85 the frame is exactly `SillLine(y: 666, length: 520)`, the lockup's.
struct FixesLine060: View {
    let t: Double
    var body: some View {
        let F = Fixes060.self
        let bug = F.bugState(t)
        let y = bug.base.y + bug.jitter.dy - 1
        let x = F.sillX + bug.jitter.dx
        return ZStack {
            if t >= F.morph {
                SillLineGlow060(y: y, length: bug.length, centerX: x, opacity: ramp(t, F.morph, F.lineAlone) * (1 - bug.look))
                SillLine(y: y, length: bug.length, centerX: x, opacity: bug.look)
            }
        }
        .canvas()
    }
}

/// SillLine's glow alone (its 6 px, blur 14, 12 % copy), for the stretch.
struct SillLineGlow060: View {
    var y: CGFloat, length: CGFloat, centerX: CGFloat, opacity: Double
    var body: some View {
        let stops: [Gradient.Stop] = [.init(color: Color(hex: Palette.accent, alpha: 0), location: 0), .init(color: Color(hex: Palette.accent, alpha: 1), location: 0.2),
                                      .init(color: Color(hex: Palette.accent, alpha: 1), location: 0.8), .init(color: Color(hex: Palette.accent, alpha: 0), location: 1)]
        ZStack(alignment: .topLeading) {
            Color.clear.canvas()
            if length > 0.5, opacity > 0.002 {
                Rectangle().fill(LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(width: length, height: 6).blur(radius: 14).opacity(0.12 * opacity)
                    .offset(x: centerX - length / 2, y: y - 3)
            }
        }
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
}

// MARK: - The bug

/// The bug, drawn like the reel's devices so it belongs to them: a rounded shell in the device black with v3's
/// 1.5 px rim gradient and glass gloss, a centre seam, a small round head; six legs and two antennae in 2 px grey
/// strokes; one 6 px accent dot, its only colour, like a status light. No eyes, no face. About 96×112 px; it walks
/// up the screen (head first) in a 6 Hz tripod gait (±12°), its shell swaying ±3°.
enum Bug060 {
    // Its parts at scale 1, the origin at its base (the shell's foot, centred), y down.
    static let shell = CGRect(x: -28, y: -66, width: 56, height: 66)
    static let shellRadius: CGFloat = 26
    static let head = CGPoint(x: 0, y: -78), headRadius: CGFloat = 11
    static let dotCentre = CGPoint(x: 0, y: -54), dotDiameter: CGFloat = 6
    static let footprint = CGSize(width: 96, height: 111)
    static let legColour = Color(hex: 0x7A7E87)

    struct Leg { let attach: CGPoint; let knee: CGPoint; let foot: CGPoint; let tripod: Int }
    /// The left side's legs (x < 0), front to back; the right side mirrors them with the other tripod, so each
    /// tripod is the front and back legs of one side with the middle leg of the other.
    static let leftLegs: [Leg] = [
        Leg(attach: CGPoint(x: -22, y: -54), knee: CGPoint(x: -34, y: -62), foot: CGPoint(x: -41, y: -76), tripod: 0),
        Leg(attach: CGPoint(x: -27, y: -36), knee: CGPoint(x: -40, y: -40), foot: CGPoint(x: -47, y: -31), tripod: 1),
        Leg(attach: CGPoint(x: -24, y: -16), knee: CGPoint(x: -36, y: -10), foot: CGPoint(x: -43, y: -2), tripod: 0),
    ]
    static let antenna = (start: CGPoint(x: -4, y: -88), control: CGPoint(x: -7, y: -101), end: CGPoint(x: -16, y: -108))

    /// The gait: ±12° at 6 Hz about each leg's root, the two tripods in opposition (a positive angle swings the
    /// foot forward, up the screen, on either side).
    static func legAngle(_ tripod: Int, _ t: Double) -> Double {
        12 * sin(2 * .pi * 6 * t + (tripod == 0 ? 0 : .pi)) * .pi / 180
    }

    /// The stretched bug's shell at the touch (its width × 0.94, its height × 1.10): where the slab of the squash starts.
    static let stretchedShell = CGSize(width: shell.width * 0.94, height: shell.height * 1.10)

    /// The body's outline from the squash on (its own space, the base at the origin, y down): a fully rounded slab `w` × `h`
    /// sitting on the line, its edge pushed out along its normal by up to `wobble` px of a fixed noise (the top and the ends
    /// uneven; the bottom flat on the line, only ever lifted a little), clockwise from the top's middle.
    static func slab(w: CGFloat, h: CGFloat, wobble: CGFloat, phase: Double, n: Int = 160) -> Path {
        let r = max(0.01, min(w, h) / 2)
        let hx = w / 2
        let arc = CGFloat.pi * r / 2
        let segs: [CGFloat] = [hx - r, arc, max(0, h - 2 * r), arc, max(0, w - 2 * r), arc, max(0, h - 2 * r), arc, hx - r]
        let total = segs.reduce(0, +)
        var path = Path()
        for i in 0..<n {
            var d = total * CGFloat(i) / CGFloat(n)
            var k = 0
            while k < segs.count - 1 && d > segs[k] { d -= segs[k]; k += 1 }
            var p = CGPoint.zero, nx: CGFloat = 0, ny: CGFloat = 0
            func on(_ cx: CGFloat, _ cy: CGFloat, _ phi: CGFloat) { p = CGPoint(x: cx + r * cos(phi), y: cy + r * sin(phi)); nx = cos(phi); ny = sin(phi) }
            switch k {
            case 0: p = CGPoint(x: d, y: -h); ny = -1
            case 1: on(hx - r, -h + r, -.pi / 2 + d / r)
            case 2: p = CGPoint(x: hx, y: -h + r + d); nx = 1
            case 3: on(hx - r, -r, d / r)
            case 4: p = CGPoint(x: hx - r - d, y: 0); ny = 1
            case 5: on(-hx + r, -r, .pi / 2 + d / r)
            case 6: p = CGPoint(x: -hx, y: -r - d); nx = -1
            case 7: on(-hx + r, -h + r, .pi + d / r)
            default: p = CGPoint(x: -hx + r + d, y: -h); ny = -1
            }
            let v = Double(i) / Double(n)
            let noise = 0.55 * sin(2 * .pi * 5 * v + 0.7 + phase) + 0.30 * sin(2 * .pi * 8 * v + 2.1 - 0.6 * phase)
                + 0.15 * sin(2 * .pi * 13 * v + 4.0 + 1.3 * phase)
            var off = wobble * CGFloat(noise)
            if ny > 0.5 { off = min(0, off * 0.25) }              // the bottom stays on the line
            let q = CGPoint(x: p.x + off * nx, y: p.y + off * ny)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }

    static func draw(_ ctx: inout GraphicsContext, _ s: Fixes060.BugState, t: Double) {
        // The whole bug's transform: the sway about the shell's middle, the squash about the base, the jitter.
        let sway = 3 * s.sway * sin(2 * .pi * 6 * s.gaitTime + .pi / 2) * .pi / 180
        let swayT = CGAffineTransform(translationX: 0, y: -33).rotated(by: sway).translatedBy(x: 0, y: 33)
        // The buzz's twist is the bug's alone: on the stretching line it would swing its ends.
        let place = CGAffineTransform(translationX: s.base.x + s.jitter.dx, y: s.base.y + s.jitter.dy)
            .rotated(by: s.jitter.degrees * (1 - s.morph) * .pi / 180)
        func whole(_ sx: CGFloat, _ sy: CGFloat) -> CGAffineTransform {
            swayT.concatenating(CGAffineTransform(scaleX: sx, y: sy)).concatenating(place)
        }
        let body = whole(s.sx, s.sy)
        let q = s.squash
        // From the squash the body is a slab spreading from the stretched shell into the puddle (s.puddleWidth ×
        // s.puddleHeight, settling), then, from the morph, thinning to the 2 px line and stretching (s.length).
        let slabW = lerp(stretchedShell.width, lerp(s.puddleWidth, s.length, s.morph), Double(q))
        let slabH = lerp(stretchedShell.height, lerp(s.puddleHeight, 2, s.morph), Double(q))
        // The shell's spread, for the legs' roots: the slab's width over the shell's own.
        let shellSX = q > 0 ? slabW / shell.width : s.sx
        let shellT = whole(shellSX, s.sy)
        let fadeParts = 1 - s.morph

        // Legs and antennae: 2 px strokes in screen space (never squashed thin), splaying flat as it squashes.
        if s.legAlpha > 0.002 {
            var legs = ctx
            legs.opacity = s.legAlpha
            for mirrored in [false, true] {
                let side: CGFloat = mirrored ? -1 : 1            // the right side is the left one mirrored
                for leg in leftLegs {
                    let tripod = mirrored ? 1 - leg.tripod : leg.tripod
                    let a = legAngle(tripod, s.gaitTime) * Double(side)
                    // The root rides the body's edge as it spreads (body scales x by sx; the slab by shellSX).
                    let spread = shellSX / max(s.sx, 0.001)
                    func pt(_ p: CGPoint) -> CGPoint {
                        let root = CGPoint(x: leg.attach.x * side * spread, y: leg.attach.y)
                        let qq = CGPoint(x: root.x + (p.x - leg.attach.x) * side, y: p.y)
                        // The walking pose, rotated about the root…
                        let dx = qq.x - root.x, dy = qq.y - root.y
                        let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                        let walk = CGPoint(x: root.x + dx * ca - dy * sa, y: root.y + dx * sa + dy * ca)
                        // …and laid flat outward (the same reach, level with the root) as it squashes.
                        let reach = hypot(dx, dy)
                        let outward: CGFloat = root.x < 0 ? -1 : 1     // away from the body, on either side
                        let flat = CGPoint(x: root.x + outward * reach * (p == leg.knee ? 0.55 : 1), y: root.y)
                        return CGPoint(x: lerp(walk.x, flat.x, Double(q)), y: lerp(walk.y, flat.y, Double(q))).applying(body)
                    }
                    var path = Path()
                    path.move(to: pt(leg.attach)); path.addLine(to: pt(leg.knee)); path.addLine(to: pt(leg.foot))
                    legs.stroke(path, with: .color(legColour), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                var ant = Path()
                func ap(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * side, y: p.y).applying(body) }
                ant.move(to: ap(antenna.start)); ant.addQuadCurve(to: ap(antenna.end), control: ap(antenna.control))
                legs.stroke(ant, with: .color(legColour), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        let rim = Gradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)])
        // The head, taken into the puddle as the body flattens.
        let headAlpha = fadeParts * Double(1 - q)
        if headAlpha > 0.002 {
            var hc = ctx
            hc.opacity = headAlpha
            let headPath = Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: 2 * headRadius, height: 2 * headRadius)).applying(body)
            hc.fill(headPath, with: .color(Color(hex: Palette.deviceBody)))
            let hb = headPath.boundingRect
            hc.stroke(headPath, with: .linearGradient(rim, startPoint: CGPoint(x: hb.minX, y: hb.minY), endPoint: CGPoint(x: hb.maxX, y: hb.maxY)), lineWidth: 1.5)
        }
        // The shell: device black, the gloss, the seam, the rim. From the squash it is the slab, then the puddle, uneven
        // and soft-edged (its rim drawn softly), settling; its fill turns to the accent as it thins into the line.
        let shellPath: Path
        if q > 0 {
            shellPath = slab(w: slabW, h: slabH, wobble: s.wobble * q * CGFloat(fadeParts), phase: s.wobblePhase).applying(place)
        } else {
            shellPath = Path(roundedRect: shell, cornerRadius: shellRadius, style: .continuous).applying(shellT)
        }
        let sb = shellPath.boundingRect
        var fill = ctx
        fill.opacity = 1 - s.look
        if q > 0 && s.morph < 1 {
            // The puddle: the device black lit a little from above (Splat060's drops' body), turning to the accent.
            let top = Keycap060Painter.lerpColor(Keycap060Painter.lerpColor(Palette.deviceBody, Splat060.bodyTop, Double(q)), Palette.accent, s.morph)
            let bottom = Keycap060Painter.lerpColor(Palette.deviceBody, Palette.accent, s.morph)
            fill.fill(shellPath, with: .linearGradient(Gradient(colors: [Color(hex: top), Color(hex: bottom)]),
                                                       startPoint: CGPoint(x: sb.midX, y: sb.minY), endPoint: CGPoint(x: sb.midX, y: sb.maxY)))
        } else {
            fill.fill(shellPath, with: .color(Color(hex: Keycap060Painter.lerpColor(Palette.deviceBody, Palette.accent, s.morph))))
        }
        if fadeParts > 0.002 {
            var g = ctx
            g.opacity = fadeParts
            var gl = g
            gl.clip(to: shellPath)
            gl.fill(Path(sb), with: .linearGradient(Gradient(colors: [.white.opacity(0.10 + 0.04 * Double(q)), .white.opacity(0)]),
                                                    startPoint: CGPoint(x: sb.minX, y: sb.minY),
                                                    endPoint: CGPoint(x: sb.minX + sb.width / 2.2, y: sb.minY + sb.height / 2.2)))
            if q < 0.999 {
                var seam = Path()
                seam.move(to: CGPoint(x: 0, y: -47).applying(shellT)); seam.addLine(to: CGPoint(x: 0, y: -6).applying(shellT))
                var sc = g
                sc.opacity = 1 - Double(q)
                sc.stroke(seam, with: .color(Color(hex: 0x30333A)), lineWidth: 1.2)
            }
            let rimStroke = GraphicsContext.Shading.linearGradient(rim, startPoint: CGPoint(x: sb.minX, y: sb.minY), endPoint: CGPoint(x: sb.maxX, y: sb.maxY))
            if q > 0 {
                g.drawLayer { soft in
                    soft.addFilter(.blur(radius: 0.5 + 0.7 * q))
                    soft.stroke(shellPath, with: rimStroke, lineWidth: 1.5)
                }
            } else {
                g.stroke(shellPath, with: rimStroke, lineWidth: 1.5)
            }
        }
        // The accent dot, round whatever the squash, flaring once as the shell flattens (on the slab's top, from the squash).
        if s.dotAlpha > 0.002 || s.flare > 0.002 {
            let c = q > 0 ? CGPoint(x: 0, y: -slabH * 0.55).applying(place) : dotCentre.applying(shellT)
            if s.flare > 0.002 {
                let fr = dotDiameter / 2 * CGFloat(1 + 2.4 * (1 - s.flare))
                ctx.drawLayer { f in
                    f.addFilter(.blur(radius: 6))
                    f.fill(Path(ellipseIn: CGRect(x: c.x - fr * 2, y: c.y - fr * 2, width: fr * 4, height: fr * 4)),
                           with: .color(Color(hex: Palette.accent, alpha: 0.75 * s.flare)))
                }
            }
            if s.dotAlpha > 0.002 {
                let r = dotDiameter / 2 * CGFloat(1 + 0.5 * s.flare)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Color(hex: Palette.accent, alpha: s.dotAlpha)))
            }
        }
    }
}

// MARK: - The splat

/// v4.1, Noah: "The bug needs a better splat animation when it is smashed." Its ink, flying out on the squash: 12 drops in
/// the device black (lit from above, v3's grey rim, a glint on the larger ones) and 3 in the accent leave from along the
/// body's top as it flattens, from half a frame before the beat, and fly out along the sill line and a little up (2° to
/// 12°), decelerating (each covers 1 − e^(−u/0.065 s) of its reach, 50 to 255 px), drawn smeared along their motion for
/// their first three frames; they land as splatter does, rounded heads with a tapering tail pointing back at the hit, then,
/// still, fade as the line forms (the dark ones 122.35–122.65, the accent ones 122.45–122.8). They ride with the column
/// (its 6 px return), not with the puddle's buzz. The flash: on the beat's frame alone (frame 7320), the accent under the
/// body, a soft glow and a bright core along the line. No face, nothing red: the reel's palette.
enum Splat060 {
    struct Speck {
        let origin: CGVector       // from the bug's base, at the launch
        let direction: CGVector    // unit, out along the line and a little up
        let reach: CGFloat         // how far it goes, px
        let radius: CGFloat        // its head's
        let tail: CGFloat          // its tail's length at rest, back toward the hit (× radius)
        let accent: Bool
    }

    static let launch = Fixes060.tap - 0.5 / 60
    static let tau = 0.065
    /// How long a drop is drawn smeared: its first three frames.
    static let smear = 3.0 / 60
    /// The drops' body: the device black, lit a little from above.
    static let bodyTop: UInt32 = 0x2A2D34

    static let specks: [Speck] = {
        var rng = SplitMix64(seed: 0x5711_5B1A7)
        func rand() -> CGFloat { CGFloat(Double(rng.next() % 1_000_001) / 1_000_000) }
        var out: [Speck] = []
        // Each side's dark drops spread along it: their reaches drawn one from each sixth of 50…255 px (in a shuffled
        // order), so they neither clump nor leave a gap; the accent ones two to the right, one to the left.
        var slots: [[Int]] = [[0, 1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 5]]
        for k in 0..<2 { for j in stride(from: 5, to: 0, by: -1) { slots[k].swapAt(j, Int(rng.next() % UInt64(j + 1))) } }
        for i in 0..<15 {
            let accent = i == 3 || i == 8 || i == 12
            // Alternate sides, the right a drop richer; out along the line, 2° to 12° up.
            let side: CGFloat = i % 2 == 0 ? 1 : -1
            let up = (2 + 10 * Double(rand())) * .pi / 180
            let direction = CGVector(dx: side * CGFloat(cos(up)), dy: -CGFloat(sin(up)))
            let origin = CGVector(dx: side * (10 + 50 * rand()), dy: -(3 + 5 * rand()))
            let slot = accent ? 0 : slots[side > 0 ? 0 : 1].removeLast()
            let reach: CGFloat = accent ? 100 + 120 * rand() : 50 + 205 * (CGFloat(slot) + 0.15 + 0.7 * rand()) / 6
            // Big drops land near, small ones far.
            var radius: CGFloat = accent ? 2.6 + 1.6 * rand() : 3.2 + 4.6 * rand()
            if !accent { radius *= 1.15 - 0.45 * (reach - 50) / 205 }
            out.append(Speck(origin: origin, direction: direction, reach: reach, radius: radius,
                             tail: 0.9 + 1.1 * (reach - 50) / 205 + 0.3 * rand(), accent: accent))
        }
        return out
    }()

    /// A drop's offset from the bug's base `u` s after the launch.
    static func offset(_ s: Speck, _ u: Double) -> CGVector {
        let d = s.reach * CGFloat(1 - exp(-max(0, u) / tau))
        return CGVector(dx: s.origin.dx + s.direction.dx * d, dy: s.origin.dy + s.direction.dy * d)
    }

    static func alpha(_ s: Speck, _ t: Double) -> Double {
        let F = Fixes060.self
        return s.accent ? 1 - CubicBezier.inOut(ramp(t, F.morph + 0.10, F.morph + 0.45))
                        : 1 - CubicBezier.inOut(ramp(t, F.morph, F.morph + 0.30))
    }

    /// A drop: a round head of radius `r1` at `head` and a tail tapering to radius `r2` at `tail`, joined by their outer
    /// tangents (a teardrop, as splatter lands).
    static func drop(head: CGPoint, r1: CGFloat, tail: CGPoint, r2: CGFloat) -> Path {
        let dx = head.x - tail.x, dy = head.y - tail.y, d = hypot(dx, dy)
        guard d > abs(r1 - r2) + 0.01 else { return Path(ellipseIn: CGRect(x: head.x - r1, y: head.y - r1, width: 2 * r1, height: 2 * r1)) }
        let base = atan2(dy, dx)
        // The outer tangents touch the head at base ± alpha (past a right angle when the head is the bigger).
        let alpha = acos(min(1, max(-1, (r2 - r1) / d)))
        var p = Path()
        p.addArc(center: head, radius: r1, startAngle: .radians(base - alpha), endAngle: .radians(base + alpha), clockwise: false)
        p.addArc(center: tail, radius: r2, startAngle: .radians(base + alpha), endAngle: .radians(base - alpha + 2 * .pi), clockwise: false)
        p.closeSubpath()
        return p
    }

    /// The flash under the body, on the beat's frame alone.
    static func drawFlash(_ ctx: inout GraphicsContext, base: CGPoint, t: Double) {
        guard abs(t - Fixes060.tap) < 0.5 / 60 else { return }
        ctx.drawLayer { f in
            f.addFilter(.blur(radius: 14))
            f.fill(Path(ellipseIn: CGRect(x: base.x - 130, y: base.y - 24, width: 260, height: 36)),
                   with: .color(Color(hex: Palette.accent, alpha: 0.55)))
        }
        ctx.drawLayer { f in
            f.addFilter(.blur(radius: 2))
            f.fill(Path(roundedRect: CGRect(x: base.x - 84, y: base.y - 3, width: 168, height: 4), cornerRadius: 2),
                   with: .color(Color(hex: Palette.accent, alpha: 0.9)))
        }
    }

    static func draw(_ ctx: inout GraphicsContext, base: CGPoint, t: Double) {
        let u = t - launch
        guard u >= 0, t < Fixes060.lineAlone else { return }
        let rim = Gradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)])
        let body = Gradient(colors: [Color(hex: bodyTop), Color(hex: Palette.deviceBody)])
        for s in specks {
            let a = alpha(s, t)
            guard a > 0.002 else { continue }
            let o = offset(s, u)
            let head = CGPoint(x: base.x + o.dx, y: base.y + o.dy)
            // Its tail: while it flies, back along a frame's travel (the smear, fading out by its third frame); at rest, its
            // own tail toward the hit. The two are blended as the smear goes.
            let back = offset(s, max(0, u - 0.9 / 60))
            let travel = hypot(o.dx - back.dx, o.dy - back.dy)
            let smearing = u < smear ? 1 - ramp(u, smear - 1.2 / 60, smear) : 0
            let restTail = s.tail * s.radius * CGFloat(min(1, u / 0.05))
            let length = max(restTail, travel * CGFloat(smearing))
            let tail = CGPoint(x: head.x - s.direction.dx * length, y: head.y - s.direction.dy * length)
            let r2 = s.radius * (smearing > 0.5 ? 0.8 : 0.42)
            let shape = drop(head: head, r1: s.radius, tail: tail, r2: r2)
            let b = shape.boundingRect
            var c = ctx
            c.opacity = a
            if s.accent {
                c.drawLayer { g in
                    g.addFilter(.blur(radius: 3))
                    g.fill(shape, with: .color(Color(hex: Palette.accent, alpha: 0.45)))
                }
                c.fill(shape, with: .color(Color(hex: Palette.accent)))
            } else {
                c.fill(shape, with: .linearGradient(body, startPoint: CGPoint(x: head.x, y: b.minY), endPoint: CGPoint(x: head.x, y: b.maxY)))
                c.stroke(shape, with: .linearGradient(rim, startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)), lineWidth: 1.1)
                if s.radius >= 3.4 {
                    let r = s.radius
                    c.fill(Path(ellipseIn: CGRect(x: head.x - 0.62 * r, y: head.y - 0.66 * r, width: 0.62 * r, height: 0.46 * r)),
                           with: .color(.white.opacity(0.30)))
                }
            }
        }
    }
}
