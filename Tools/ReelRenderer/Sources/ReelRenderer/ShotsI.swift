// ShotsI.swift — Act I (S01–S05) and the close (S25–S32): the icon, the glint, statements, the lockup, the
// iPhone Duo tease.
import SwiftUI

private let k0: CGFloat = 560.0 / 1024
private let target = CGPoint(x: 512, y: 436)

// MARK: S01 · darkness, one glint

@MainActor func s01(_ t: Double, _ e: Env) throws -> FrameLayers {
    let v = ZStack {
        Color.black
        GlintView(path: glintPath(.resting()), t: t, start: 0.8, duration: 1.2)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S02 · the icon assembles

private func s02Camera(_ t: Double) -> IconCamera {
    let push = 1 + 0.04 * CGFloat(ramp(t, 2.4, 4.4))
    return IconCamera(k: k0 * push, anchorIcon: CGPoint(x: 512, y: 512), anchorScreen: CGPoint(x: 960, y: 540))
}

@MainActor func s02(_ t: Double, _ e: Env) throws -> FrameLayers {
    var st = IconState()
    st.camera = s02Camera(t)
    func layer(_ start: Double) -> IconLayerState {
        let p = ease(t, start, 0.6, .appleOut)
        return IconLayerState(opacity: clamp01(p), scale: 1.04 - 0.04 * CGFloat(p), dy: -12 * CGFloat(1 - p))
    }
    // v2, note 1: the icon's dark tile (layer 1) is not drawn and there is no glow: the background stays
    // uniform black. The three remaining layers keep the 0.12 s cascade, starting at 2.45.
    st.background.opacity = 0
    st.imac = layer(2.45); st.ipad = layer(2.57); st.window = layer(2.69)
    let yawBack = 3 * ramp(t, 2.4, 4.4), yawFront = 4.5 * ramp(t, 2.4, 4.4)
    let v = ZStack {
        Color.black
        IconCanvas(s: st, part: .back).modifier(Tilt(yaw: yawBack, pitch: 0))
        IconCanvas(s: st, part: .front).modifier(Tilt(yaw: yawFront, pitch: 0))
        // S01's trail finishes fading here (continuous).
        GlintView(path: glintPath(st.camera), t: t, start: 0.8, duration: 1.2)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S03 · into the Mac

private func dollyZ(_ t: Double) -> CGFloat { lerp(1.04, 12.0, CubicBezier.push(clamp01((t - 4.4) / 2.0))) }
private func dollyAnchor(_ t: Double) -> CGPoint {
    let y0 = 540 + (target.y - 512) * k0 * 1.04          // where the S02 camera puts the target at 4.4
    return CGPoint(x: 960, y: lerp(y0, 540, CubicBezier.push(clamp01((t - 4.4) / 2.0))))
}

@MainActor func s03(_ t: Double, _ e: Env) throws -> FrameLayers {
    var st = IconState()
    st.background.opacity = 0            // v2, note 1: no tile behind the iMac
    st.camera = IconCamera(k: k0 * dollyZ(t), anchorIcon: target, anchorScreen: dollyAnchor(t))
    // The iPad and window scale 1.25× faster and leave lower right; five sub-frame samples, t − 4/300 … t.
    st.ipadCameras = (0..<5).map { j in
        let tt = t - Double(4 - j) / 300
        let zi = 1.04 + 1.25 * (dollyZ(tt) - 1.04)
        let d = (zi - 1.04)
        let a = dollyAnchor(tt)
        return IconCamera(k: k0 * zi, anchorIcon: target, anchorScreen: CGPoint(x: a.x + 300 * d, y: a.y + 200 * d))
    }
    st.imacGloss = 1 - CubicBezier.inOut(ramp(t, 5.6, 6.2))
    st.screenOpacity = 0.97 + 0.03 * ramp(t, 5.6, 6.2)
    // S02's yaw straightens as the camera dollies in (so the zoomed screen fills the frame edge to edge).
    let straighten = 1 - CubicBezier.inOut(ramp(t, 4.4, 5.4))
    let v = ZStack {
        Color.black                      // uniform black (no glow) around the iMac
        IconCanvas(s: st, part: .back).modifier(Tilt(yaw: 3 * straighten, pitch: 0))
        IconCanvas(s: st, part: .front).modifier(Tilt(yaw: 4.5 * straighten, pitch: 0))
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S04 · "Your Mac apps."

@MainActor func s04(_ t: Double, _ e: Env) throws -> FrameLayers {
    let p = ease(t, 6.4, 0.8, .appleOut)
    let bg = Color(.sRGB, red: 7 / 255 * (1 - p), green: 8 / 255 * (1 - p), blue: 10 / 255 * (1 - p))
    let line = LineSpec(Copy.yourMacApps, .T0, baseline: 575, snap: 6.45, holdEnd: 8.0)
    let v = ZStack {
        Backdrop(color: bg, glow: 0.05)
        TypeLayer(lines: [line], t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S05 · "On the window sill."

@MainActor func s05(_ t: Double, _ e: Env) throws -> FrameLayers {
    var line = LineSpec(words: Copy.windowSill, .T0, baseline: 575, snap: 8.05, holdEnd: 9.2)
    line.colors = [3: Palette.accent]         // "sill." in accent, as "sit." was; the sill line draws under it
    let lift = ease(t, 9.20, 0.35, .appleIn)
    let draw = ease(t, 9.20, 0.35, .appleOut)
    let v = ZStack {
        Backdrop(glow: 0.05)
        SillLine(y: 930, length: 1200 * CGFloat(draw))
        TypeLayer(lines: [line], t: t)
            .offset(y: -40 * CGFloat(lift))
            .opacity(1 - lift)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S25–S26 · black, silence, two statements ("Just a tip jar." is gone, note 16)

@MainActor private func blackStatement(_ t: Double, _ text: String, snap: Double, end: Double, easeOut: Double? = nil) -> FrameLayers {
    let line = LineSpec(text, .T1, baseline: 585, snap: snap, holdEnd: easeOut ?? end, easeOut: easeOut)
    let v = ZStack {
        Color.black
        TypeLayer(lines: [line], t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

/// 0.4 s of true black and digital silence (57.6–58.0), then "No subscription."
@MainActor func s25(_ t: Double, _ e: Env) throws -> FrameLayers { blackStatement(t, Copy.noSubscription, snap: 58.00, end: 59.2) }
/// The last statement eases out before the glint returns.
@MainActor func s26(_ t: Double, _ e: Env) throws -> FrameLayers { blackStatement(t, Copy.noServers, snap: 59.25, end: 60.8, easeOut: 60.50) }

// MARK: S27 · the glint returns

/// The close starts at 60.8 (v1: 59.2); every close time below is v1's + 1.6 s.
let closeStart = 60.8

/// S27's hold drift: the lit icon pushes in 3 % over the shot (linear), and S28's rise starts from there.
/// The close keeps the icon's tile: it is the app icon itself here (note 1 concerns the intro).
let s34Push: CGFloat = 0.03
func s34Size(_ t: Double) -> CGFloat { 560 * (1 + s34Push * CGFloat(ramp(t, closeStart, closeStart + 2.4))) }

@MainActor func s27(_ t: Double, _ e: Env) throws -> FrameLayers {
    var st = IconState()
    st.opacity = ease(t, closeStart, 0.5, .appleOut)
    let cam = IconCamera.resting(size: s34Size(t))
    st.camera = cam
    let v = ZStack {
        Backdrop(glow: 0.06 * st.opacity)
        IconCanvas(s: st, part: .all)
        GlintView(path: glintPath(cam), t: t, start: closeStart + 0.1, duration: 0.9)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S28–S30 · the lockup

/// The lockup at time t (S28 onward): the icon at the top, the wordmark on the sill line, the lines. From
/// 70.4 it fades (0.4 s) into the Duo card, and its sill line stays for the Duo to stand on.
@MainActor private func lockup(_ t: Double) -> AnyView {
    let t0 = closeStart + 2.4                                       // 63.2: the rise
    let rise = ease(t, t0, 0.6, .appleOut)
    let size: CGFloat = lerp(s34Size(t0), 300, rise)
    let centre = CGPoint(x: 960, y: lerp(CGFloat(540), 340, rise))
    var st = IconState()
    st.camera = IconCamera.resting(size: size, centre: centre)
    let fade = 1 - CubicBezier.inOut(ramp(t, 70.4, 70.8))           // into the Duo card
    let hold = 1 + 0.012 * CGFloat(ramp(t, t0 + 0.9, 70.4))         // §3.5 hold, on the whole end card
    var lines: [LineSpec] = [LineSpec(Copy.wordmark, .W, baseline: 650, snap: t0 + 0.60, holdEnd: t0 + 0.6, cascade: false)]
    if t >= 65.6 - 1e-6 { lines.append(LineSpec(Copy.freeOpen, .T4, baseline: 770, snap: 65.65, holdEnd: 65.65)) }
    if t >= 68.0 - 1e-6 {
        lines.append(LineSpec(Copy.small, .T5, baseline: 830, snap: 68.05, holdEnd: 68.05, cascade: false))
        // Two lines at 24 px. With the card's +1.2 % hold about y 540 the lower baseline ends at 1013.6 and its
        // descenders at 1019, inside title-safe (y 1026).
        lines.append(LineSpec(Copy.legal[0], .T6, baseline: 978, snap: 68.45, holdEnd: 68.45, cascade: false))
        lines.append(LineSpec(Copy.legal[1], .T6, baseline: 1008, snap: 68.45, holdEnd: 68.45, cascade: false))
    }
    for i in lines.indices { lines[i].holdScale = false }
    let v = ZStack {
        Backdrop(glow: 0.06 * fade, glowCenter: centre)
        ZStack {
            IconCanvas(s: st, part: .all)
            TypeLayer(lines: lines, t: t)
        }
        .opacity(fade)
    }
    .canvas()
    .scaled(hold, about: CGPoint(x: 960, y: 540))
    return any(v)
}

/// The lockup's sill line (y 666 under the wordmark): it draws with the wordmark, then stays through the Duo
/// card, growing to 900 px for the device to stand on, and retracts in the fade.
func closeSillLength(_ t: Double) -> CGFloat {
    let draw = ease(t, closeStart + 2.7, 0.35, .appleOut)           // 63.5–63.85
    let grow = ease(t, 70.4, 0.5, .appleOut)                        // 520 → 900 px as the Duo arrives
    let retract = 1 - CubicBezier.inOut(ramp(t, 74.3, 74.9))
    return (520 + 380 * CGFloat(grow)) * CGFloat(draw * retract)
}

@MainActor private func lockupFrame(_ t: Double) -> FrameLayers {
    let v = ZStack {
        lockup(t)
        // The line is not part of the lockup's hold scale, so it does not jump when the lockup hands over.
        SillLine(y: 666, length: closeSillLength(t))
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

@MainActor func s28(_ t: Double, _ e: Env) throws -> FrameLayers { lockupFrame(t) }
@MainActor func s29(_ t: Double, _ e: Env) throws -> FrameLayers { lockupFrame(t) }
@MainActor func s30(_ t: Double, _ e: Env) throws -> FrameLayers { lockupFrame(t) }

// MARK: S31–S32 · one more card: the iPhone Duo tease (note 17), then the fade

@MainActor func s31(_ t: Double, _ e: Env) throws -> FrameLayers {
    let v = ZStack {
        if t < 70.8 { lockup(t) }                                   // the lockup's last 0.4 s, fading
        DuoCard(t: t)
        SillLine(y: 666, length: closeSillLength(t))
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

/// Everything but the sill line fades to black over 74.0–74.6; the line retracts by 74.9; black to 75.2.
@MainActor func s32(_ t: Double, _ e: Env) throws -> FrameLayers { try s31(t, e) }
