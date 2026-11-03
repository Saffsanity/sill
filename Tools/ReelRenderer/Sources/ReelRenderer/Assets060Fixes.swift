// Assets060Fixes.swift — S19–S20 (65.6–72.0), the one cutaway, "Fixed in 0.6." (storyboard §3): the fixes
// scroll up in a column, the last thing in it is a bug drawn like the reel's devices, a touch squashes it on the
// beat at 71.20 (frame 4272), and it flattens into the 2 px accent sill line the close stands on (y 666).
//
// Every time and size is the storyboard's (§3's nine beats); the few it leaves open are named below with the
// reason. The column's type is drawn as glyph outlines at its exact scroll position (Assets060Text.swift), so it
// glides at 7.5 px a frame without a whole-pixel step. `Fixes060.frame(t)` is the whole shot; the column, the bug
// and the line are separate views for a timeline that composes them otherwise.
// These are v4's times: v4.2 (v4 without the tour) plays the cutaway 3.2 s earlier (62.4–68.8, the squash at 68.00,
// frame 4080), handing it v4's time (Timeline060, Cut060); the score maps its crossings with Cut060.film.
import AppKit
import SwiftUI

enum Fixes060 {
    // MARK: The beats (reel s)

    static let start = 65.6, end = 72.0
    /// 1. v4.2: the title snapped (T1s) on the hard cut to black. v5 (Noah on v4.2 at 1:03: "Change the title to "Issues Fixed
    /// in 0.6." and have it come up from the bottom with the rest of the text instead of fading in"): the column is already
    /// moving at the cut, at the cruise's speed, and the title leads it up from under the frame (`titleOffset`).
    static let titleSnap = 65.65
    /// 2. The scroll: v4.2 waited for 66.4 and came up to speed over 0.3 s; v5 runs at 450 px/s from the cut, its cruise
    /// carried back to it, so from 66.7 on every place, crossing and the tap are v4.2's.
    static let scrollStart = 66.4, accelEnd = 66.7
    /// 3. The bug rides in: the scroll slows (appleOut) to rest at the tap. The review: the first cut slowed to 25 px/s by
    /// 71.12 and then lurched into its 18 px settle at about 256 px/s; now the slowing itself carries the last 18 px and the
    /// 6 px overshoot, so the column comes to rest exactly at the tap (the impact frame still but for the bug), and only
    /// the overshoot's return follows it. The cruise runs on 0.094 s past 70.4 so the appleOut, from the cruise's speed,
    /// covers just that (`brakeStart`).
    static let cruiseEnd = 70.4, rideEnd = 71.12
    /// 4. The touch dot appears over the bug, 0.08 s before the tap (v3's recipe); 5. the anticipation stretch.
    static let dotAppears = 71.12, stretchEnd = 71.18
    /// 6. The squash: on the beat (frame 4272) it is already three quarters flat: its 0.08 s appleOut starts a frame
    /// before (frame 4271), so the picture lands with the thud; the legs splay and fade in 0.12 s.
    static let tap = 71.20, squashStart = 71.20 - 1.0 / 60, squashDuration = 0.08, legsGone = 0.12
    /// 7. The jitter (v3's haptic, 18 Hz, 3 px, 0.30 s) and the column's 6 px return from its overshoot, at rest at both ends.
    static let settleEnd = 71.50
    /// 8. The line: the flattened shell turns accent and thins to 2 px (71.40–71.52), then stretches (ease in and out) to
    /// the lockup's sill line, 520 px (71.52–71.85).
    static let morph = 71.40, morphDuration = 0.12, lineStretch = 0.33
    /// 9. Black and the sill line alone.
    static let lineAlone = 71.85

    static let speed = 450.0, rideSpeed = 25.0
    static let settle: CGFloat = 18, overshoot: CGFloat = 6

    // MARK: The column

    static let columnX: CGFloat = 480
    /// The column's origin: v4.2's title's baseline while it was alone (v3's T1s statement line); every place down the column
    /// is measured from it.
    static let titleBaseline: CGFloat = 540
    /// v5: the title's place down the column, 192 px under the origin, so at the cut (the scroll at −427.5 px) its capitals'
    /// top is the frame's bottom edge and it rises from there, 348 px over the first header.
    static let titleOffset: CGFloat = 192
    static let linePitch: CGFloat = 60
    /// Open in the storyboard: a header 64 px over its group's first line, and 180 px (three line pitches, a beat at
    /// 450 px/s) from a group's last line to the next group's first, so every line crosses the middle on the
    /// 7.5-a-second grid (an eighth-note triplet at 150 BPM: the score's ticks fall in time).
    static let headerToLine: CGFloat = 64, groupStep: CGFloat = 180
    /// The top and bottom 140 px fade the column out.
    static let fade: CGFloat = 140
    static let lineSize: CGFloat = 44, lineTracking: CGFloat = -0.5
    static let headerSize: CGFloat = 28
    /// The first line crosses the middle on the grid's 11th step (67.867): the first header then starts just below
    /// the frame, so the title snaps in alone, and the bug ends 203 px under the last line.
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
    /// v4.1 (carried into v4.2): "0.6", not "0.6.0" (Noah).
    static let title = ["Issues", "Fixed", "in", "0.6."]

    // MARK: The sill line it ends on (the lockup's, S21)

    /// The lockup's own sill line: S01–S02's (Open060), y 666, 520 px (its ink 493 px: the faded ends). The review: the
    /// storyboard's "1,200 px" contradicted its own "the lockup's own sill line", and the close showed a line 2.26 times the
    /// open's.
    static let sillY: CGFloat = 666, sillLength: CGFloat = 520, sillX: CGFloat = 960
    /// The bug walks up the column's middle, and flattens there.
    static let bugX: CGFloat = 960
    /// The flattened bug's foot comes to rest on the sill line's lower edge.
    static var restingBase: CGFloat { sillY + 1 }

    // MARK: The scroll

    /// appleOut's slope at 0 (its first control point is (0.16, 1)).
    private static let appleOutSlope = 1 / 0.16

    /// The scroll at 70.4, where the cruise would have begun to slow.
    private static var cruiseScroll: Double {
        let a = accelEnd - scrollStart
        return speed * a / 2 + speed * (cruiseEnd - accelEnd)
    }
    /// Where the column comes to rest (after its overshoot's return): the first cut's, so every place below is as it was
    /// (its 25 px/s ride to 71.12 and on to the tap, and its 18 px settle, from 70.4: 86.96 px).
    static var restScroll: Double {
        let d = rideEnd - cruiseEnd
        return cruiseScroll + rideSpeed * d + (speed - rideSpeed) * d / appleOutSlope + rideSpeed * (tap - rideEnd) + Double(settle)
    }
    /// The slowing's start: the cruise runs on until an appleOut from its speed, ending at rest at the tap, covers what is
    /// left to the overshoot's peak: 450 c + 450 (t − c)/6.25 = rest + 6 − scroll(70.4), t = 0.8 s.
    static var brakeStart: Double {
        let left = restScroll + Double(overshoot) - cruiseScroll, total = tap - cruiseEnd
        return cruiseEnd + (left - speed * total / appleOutSlope) / (speed - speed / appleOutSlope)
    }

    /// How far the column has scrolled up at `t`, in px. Smooth (continuous speed) from rest through the cruise and the
    /// slowing, at rest at the tap 6 px past where it settles, then back by those 6 px (71.2–71.5), at rest at both ends.
    static func scroll(_ t: Double) -> Double {
        let a = accelEnd - scrollStart
        let s0 = speed * a / 2
        // v5: the cruise from the cut (it was still until 66.4 and came up to speed by 66.7), so the title rises with the column.
        if t < accelEnd { return s0 + speed * (t - accelEnd) }
        let b = brakeStart
        if t < b { return s0 + speed * (t - accelEnd) }
        let s1 = s0 + speed * (b - accelEnd)
        let d = tap - b
        let brake = speed * d / appleOutSlope      // so the speed at the brake's start is still 450 px/s
        if t < tap { return s1 + brake * CubicBezier.appleOut((t - b) / d) }
        let peak = s1 + brake
        let u = clamp01((t - tap) / (settleEnd - tap))
        return peak - Double(overshoot) * (1 - cos(Double.pi * u)) / 2
    }

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

    /// The lines' opacity: whole, then back to 45 % with the squash (0.30 s appleOut), then out (0.3 s from 71.40).
    static func columnOpacity(_ t: Double) -> Double {
        let back = 1 - 0.55 * ease(t, tap, 0.30, .appleOut)
        return back * (1 - CubicBezier.inOut(ramp(t, morph, morph + 0.30)))
    }

    // MARK: The bug's state

    struct BugState {
        var base: CGPoint
        /// The whole bug's scale about its base: (1, 1) walking, (0.94, 1.10) stretched, (1.80, 0.14) squashed.
        var sx: CGFloat = 1, sy: CGFloat = 1
        /// The squash's progress (0 … 1): the shell spreads to the bug's whole footprint × sx, the legs splay flat.
        var squash: CGFloat = 0
        var legAlpha: Double = 1
        /// The gait's clock (frozen at the touch) and the sway's amplitude.
        var gaitTime: Double
        var sway: Double = 1
        var jitter: (dx: CGFloat, dy: CGFloat, degrees: Double) = (0, 0, 0)
        /// The accent dot: its flare (0 … 1) and its alpha.
        var flare: Double = 0, dotAlpha: Double = 1
        /// 0 the bug … 1 the 2 px accent line (its fill, its thickness; the head, rim and gloss fade).
        var morph: Double = 0
        /// The line's length while it stretches (px).
        var length: CGFloat = 0
        /// 0 the bug's own accent line … 1 handed over to `SillLine`'s look (71.52–71.85).
        var look: Double = 0
    }

    static func bugState(_ t: Double) -> BugState {
        var s = BugState(base: CGPoint(x: bugX, y: screenY(bugBase, t)), gaitTime: min(t, dotAppears))
        s.sway = 1 - ramp(t, dotAppears - 0.16, dotAppears)
        // 5. Anticipation: tall and narrow.
        let a = CGFloat(ease(t, dotAppears, stretchEnd - dotAppears, .appleOut))
        s.sx = 1 - 0.06 * a; s.sy = 1 + 0.10 * a
        // 6. The squash, pinned at the base: three quarters flat on the beat's frame.
        let q = CGFloat(ease(t, squashStart, squashDuration, .appleOut))
        s.squash = q
        s.sx = lerp(s.sx, 1.80, Double(q)); s.sy = lerp(s.sy, 0.14, Double(q))
        s.legAlpha = 1 - ramp(t, squashStart, squashStart + legsGone)
        // The accent dot flares with the flattening it marks, from the frame after the beat's (4273), not before it.
        s.flare = t >= tap + 1.0 / 120 ? 1 - ramp(t, tap + 0.03, tap + 0.20) : 0
        s.dotAlpha = 1 - ramp(t, tap + 0.06, tap + 0.20)
        // 7. The jitter.
        s.jitter = buzz(t, start: tap, duration: settleEnd - tap, amplitude: 3)
        // 8. The line: the shell itself turns accent and thin (71.40–71.52), then stretches, easing in and out, from its
        // own 172.8 px (1.80 × 96) to the lockup's line (71.52–71.85): under 2 px on its first frame, none of it a pop.
        s.morph = ease(t, morph, morphDuration, .inOut)
        s.length = lerp(Bug060.footprint.width * 1.80, sillLength, CubicBezier.inOut(ramp(t, morph + morphDuration, morph + morphDuration + lineStretch)))
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

    /// The touch dot: v3's tap dot (0.7 → 1 over 0.12 s from 71.12), pinned where the finger lands, on the bug's upper back
    /// (its head and the top of its shell, at x 960, y 604), 72 px and light, so the stretch under it and the shell's lower
    /// half beside it read (the review: at 96 px on the bug's middle it covered the whole bug and followed it down 38 px as
    /// it flattened); it fades from 71.40 (0.25 s).
    static let dotDiameter: CGFloat = 72
    static let dotCentre = CGPoint(x: 960, y: 604)
    static func dot(_ t: Double, _ bug: BugState) -> (center: CGPoint, scale: CGFloat, alpha: Double)? {
        guard t >= dotAppears, t < morph + 0.25 else { return nil }
        let scale = CGFloat(0.7 + 0.3 * ease(t, dotAppears, 0.12, .appleOut))
        return (dotCentre, scale, 1 - ramp(t, morph, morph + 0.25))
    }

    // MARK: The shot

    /// S19–S20 at `t` (65.6–72.0): black, the column (title, headers, lines, bug) inside the 140 px fades, the touch
    /// dot, the line. From 71.85 black and the sill line alone (exactly `SillLine(y: 666, length: 520)`, the lockup's).
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
/// dot over it), before the fades' mask.
struct FixesColumn060: View {
    let t: Double
    /// False in the film: its type is FixesType060's (Shots060Mac.swift), glyph outlines on the scroll's path that
    /// typecheck measures; this view then draws the bug and its touch dot. True for the asset previews.
    var drawsType = true
    var body: some View {
        Canvas { ctx, _ in
            let F = Fixes060.self
            // The title: v5, the column's first line, rising with it from under the frame.
            let ty = F.screenY(F.titleOffset, t)
            if drawsType && ty > -60 && ty < Stage.size.height + 120 {
                Outline060.draw(F.title.joined(separator: " "), in: &ctx, size: TypeStyle.T1s.size, weight: .bold,
                                tracking: TypeStyle.T1s.tracking, x: F.columnX, baseline: ty, leading: true, color: Color(hex: Palette.text1))
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
            if bug.base.y < Stage.size.height + 140 && t < F.lineAlone {
                Bug060.draw(&ctx, bug, t: t)
            }
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
                    .linePlaced(x: centerX - length / 2, y: y - 3)
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
        // The shell spreads to the bug's whole footprint as it squashes (1.80 × 96 px, not 1.80 × its own 56); from
        // the morph it is the line, thinning to 2 px and stretching (its length starts at that same 172.8 px).
        let shellSX = s.morph > 0 ? s.length / shell.width : s.sx * (1 + (footprint.width / shell.width - 1) * s.squash)
        let shellT = whole(shellSX, s.sy * CGFloat(1 - s.morph) + (2 / shell.height) * CGFloat(s.morph))
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
                    // The root rides the shell's edge as it spreads (body scales x by sx; the shell by shellSX).
                    let spread = shellSX / max(s.sx, 0.001)
                    func pt(_ p: CGPoint) -> CGPoint {
                        let root = CGPoint(x: leg.attach.x * side * spread, y: leg.attach.y)
                        let q = CGPoint(x: root.x + (p.x - leg.attach.x) * side, y: p.y)
                        // The walking pose, rotated about the root…
                        let dx = q.x - root.x, dy = q.y - root.y
                        let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
                        let walk = CGPoint(x: root.x + dx * ca - dy * sa, y: root.y + dx * sa + dy * ca)
                        // …and laid flat outward (the same reach, level with the root) as it squashes.
                        let reach = hypot(dx, dy)
                        let outward: CGFloat = root.x < 0 ? -1 : 1     // away from the body, on either side
                        let flat = CGPoint(x: root.x + outward * reach * (p == leg.knee ? 0.55 : 1), y: root.y)
                        return CGPoint(x: lerp(walk.x, flat.x, Double(s.squash)), y: lerp(walk.y, flat.y, Double(s.squash))).applying(body)
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
        // The head.
        if fadeParts > 0.002 {
            var hc = ctx
            hc.opacity = fadeParts
            let headPath = Path(ellipseIn: CGRect(x: head.x - headRadius, y: head.y - headRadius, width: 2 * headRadius, height: 2 * headRadius)).applying(body)
            hc.fill(headPath, with: .color(Color(hex: Palette.deviceBody)))
            let hb = headPath.boundingRect
            hc.stroke(headPath, with: .linearGradient(rim, startPoint: CGPoint(x: hb.minX, y: hb.minY), endPoint: CGPoint(x: hb.maxX, y: hb.maxY)), lineWidth: 1.5)
        }
        // The shell: device black, the gloss, the seam, the rim; its fill turns to the accent as it becomes the line.
        let shellPath = Path(roundedRect: shell, cornerRadius: shellRadius, style: .continuous).applying(shellT)
        let sb = shellPath.boundingRect
        var fill = ctx
        fill.opacity = 1 - s.look
        fill.fill(shellPath, with: .color(Color(hex: Keycap060Painter.lerpColor(Palette.deviceBody, Palette.accent, s.morph))))
        if fadeParts > 0.002 {
            var g = ctx
            g.opacity = fadeParts
            var gl = g
            gl.clip(to: shellPath)
            gl.fill(Path(sb), with: .linearGradient(Gradient(colors: [.white.opacity(0.10), .white.opacity(0)]),
                                                    startPoint: CGPoint(x: sb.minX, y: sb.minY),
                                                    endPoint: CGPoint(x: sb.minX + sb.width / 2.2, y: sb.minY + sb.height / 2.2)))
            var seam = Path()
            seam.move(to: CGPoint(x: 0, y: -47).applying(shellT)); seam.addLine(to: CGPoint(x: 0, y: -6).applying(shellT))
            g.stroke(seam, with: .color(Color(hex: 0x30333A)), lineWidth: 1.2)
            g.stroke(shellPath, with: .linearGradient(rim, startPoint: CGPoint(x: sb.minX, y: sb.minY), endPoint: CGPoint(x: sb.maxX, y: sb.maxY)), lineWidth: 1.5)
        }
        // The accent dot, round whatever the squash, flaring once as the shell flattens.
        if s.dotAlpha > 0.002 || s.flare > 0.002 {
            let c = dotCentre.applying(shellT)
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
