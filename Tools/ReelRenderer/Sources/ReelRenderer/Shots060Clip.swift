// Shots060Clip.swift — Act II, the big three (6.4–28.8): the clipboard both ways (S04–S05), sound (S06), a locked
// Mac and unlocking it (S07–S08). The iPad mini's screens are harness stills and drawn pictures (Reel060.swift),
// stand-ins for Noah's takes A and B (swap-in points in SHOTLIST-0.6.0.md); what the stills cannot show is drawn:
// touch dots, the iPadOS app switch, the app's own transitions (the chip's and the Settings panel's), the movie
// QuickTime plays (v3.1's own frames), the sound arcs, the lock screen, the keyboard and the dots in the field.
import SwiftUI

// MARK: - The iPad beside the words

enum Pad060 {
    /// The iPad mini beside a left column of words (x 128, T1c lines up to 811 px): 820×538 interior, its outer edge
    /// at x 988–1864, turned 4° (its inner edge toward the lens, as v3's devices beside words).
    static let spec = DeviceSpec(interior: CGSize(width: 820, height: 538), bezel: 28, innerRadius: 22, outerRadius: 50)
    static let centre = CGPoint(x: 1426, y: 560)
    static let yaw: Double = -4
    /// Interior px per still px.
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    /// A still point (px) on the canvas, for this iPad unturned at `centre`.
    static func canvas(_ p: CGPoint, centre: CGPoint = centre) -> CGPoint { onCanvas(spec, center: centre, CGPoint(x: p.x * k, y: p.y * k)) }
}

/// The left column's words: T1c statements at x 128, sublines and footnotes under them.
func leftLine(_ text: String, _ style: TypeStyle, baseline: CGFloat, snap: Double, end: Double, cascade: Bool = true) -> LineSpec {
    LineSpec(text, style, x: 128, baseline: baseline, align: .leading, snap: snap, holdEnd: end, cascade: cascade)
}

/// An iPad mini showing `layers` (stills by name, faded and slid), an overlay in its interior's px, and touch dots
/// (in the stills' px), placed at `centre` and turned by `yaw`.
@MainActor func padDevice(_ e: Env, spec: DeviceSpec, centre: CGPoint, yaw: Double, t: Double, fetch: CGFloat = 1,
                          layers: [MiniLayer], dots: [TouchDotSpec] = [], overlay: AnyView? = nil) throws -> some View {
    let imgs = try layers.map { (try e.f.screen($0.name, width: spec.interior.width, fetch: fetch), $0) }
    return PlacedDevice(spec: spec, center: centre, yaw: yaw) {
        MiniScreen(size: spec.interior, layers: imgs, dots: dots, t: t) { overlay ?? AnyView(Color.clear) }
    }
}

/// An app switch on the iPad: the screen `from` slides out and `to` slides in (from the right, or the left), 0.32 s.
func appSwitch(_ t: Double, at: Double, from: String, to: String, fromRight: Bool = true) -> [MiniLayer] {
    let p = CGFloat(ease(t, at, 0.32, .appleOut))
    let s: CGFloat = fromRight ? 1 : -1
    if t < at { return [MiniLayer(name: from)] }
    if p >= 1 { return [MiniLayer(name: to)] }
    return [MiniLayer(name: from, slide: -s * p), MiniLayer(name: to, slide: s * (1 - p))]
}

/// A still that fades in over `from` (a crossfade where only part of the screen changes: a callout, a chip).
func fadeIn(_ t: Double, _ name: String, at: Double, over d: Double = 0.12) -> MiniLayer? {
    t >= at ? MiniLayer(name: name, opacity: ramp(t, at, at + d)) : nil
}

// MARK: S04 · Copy on your Mac, paste on your iPad (6.4–10.4)

enum Clip060 {
    // S04 (take A part 1): TextEdit's line selected, ⌘C at the Mac, then Notes on the iPad: hold, Paste, the line lands.
    static let cmdDown = 7.10, cDown = 7.20, keysUp = 7.42
    static let toNotes = 7.6
    static let hold4 = (7.95, 8.35), holdPoint4 = CGPoint(x: 300, y: 460)
    static let pasteMenu = 8.20, pasteTap = 8.32, pastePoint = CGPoint(x: 245, y: 361)
    static let lands = 8.40
    // S05 (take A part 2): select the reply in Notes, Copy, back to Sill, the chip, the push, Paste, the note.
    static let hold5 = (10.55, 10.95), holdPoint5 = CGPoint(x: 480, y: 368)
    static let copyMenu = 10.85, copyTap = 11.05, copyPoint = CGPoint(x: 245, y: 270)
    static let toSill = 11.2, chip = 11.55
    /// The storyboard's push is 1.0 → 1.3; at 1.3 the strip (TextEdit's line to the chip's end) is wider than the room
    /// beside the words, so it pushes to 1.16 (1.174 with the drift after it), the iPad's screen from x 964 to the chip's
    /// end at 1909.
    static let push = 11.6, pushEnd = 12.15, pushTo: CGFloat = 1.16
    static let pasteChipTap = 12.0, chipPastePoint = CGPoint(x: 2051, y: 250)
    static let note = 12.15
}

// SWAP-IN (S04, take A part 1): replace with Noah's clip A if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-A.mov, inside Pad060's picture in
// place of the MiniScreen layers (A1, notes-plain, the Paste callout, ipad-notes-pasted). Marks to align the take to: ⌘C
// pressed at the Mac 7.20 (the drawn keycaps stay and press then), Notes on the iPad 7.6, the touch and hold 7.95,
// Paste 8.32, the line landing in Notes 8.40 (the A5 pluck). SHOTLIST-0.6.0.md §7 has the steps.
@MainActor func s060_04(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = Clip060.self
    var layers = appSwitch(t, at: c.toNotes, from: "stills/A1-te-select", to: "derived/notes-plain")
    if let l = fadeIn(t, "pictures/ipad-notes-paste", at: c.pasteMenu) { layers.append(l) }
    if let l = fadeIn(t, "pictures/ipad-notes-pasted", at: c.lands, over: 0.10) { layers.append(l) }
    let dots = [Device060.dot(at: c.hold4.0, c.holdPoint4, hold: c.hold4), Device060.dot(at: c.pasteTap, c.pastePoint)]
    let device = try padDevice(e, spec: Pad060.spec, centre: Pad060.centre, yaw: Pad060.yaw, t: t, fetch: 1.03, layers: layers, dots: dots)
    // The keycaps: in under the words (0.25 s, 10 px up), ⌘ and C pressed for ⌘C on the beat at 7.2.
    let rise = ease(t, 6.80, 0.25, .appleOut)
    let keys = KeycapRow060(keys: [.command, .letter("C")], unit: 96, origin: CGPoint(x: 128, y: 452 + 10 * CGFloat(1 - rise)), t: t,
                            presses: [0: KeyPress060(down: c.cmdDown, up: c.keysUp), 1: KeyPress060(down: c.cDown, up: c.keysUp)])
    let lines = [leftLine(Copy060.copyMac, .T1c, baseline: 400, snap: 6.45, end: 10.4),
                 leftLine(Copy060.pasteIPad, .T1c, baseline: 664, snap: 8.45, end: 10.4),
                 leftLine(Copy060.needsMac, .T3, baseline: 726, snap: 8.85, end: 10.4, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Pad060.centre)
        // Drifting: a 2.5 % push about a point right of the iPad (a render transform, so it glides).
        device.canvas().scaled(1 + 0.025 * CGFloat(ramp(t, 6.4, 10.4)), about: CGPoint(x: 1926, y: 560))
        keys.opacity(rise)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S05 · Copy on your iPad, paste on your Mac (10.4–14.4)

// SWAP-IN (S05, take A part 2): replace with Noah's clip A if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-A.mov (its second half). Marks: the
// touch and hold on the reply 10.55, Copy 11.05, back in Sill 11.2, the chip risen 11.55 (E5), Paste on the chip 12.0
// (C♯6), the note "Pasted on Noah’s MacBook Pro." from 12.15. The push (11.6–12.15, to 1.16 on the chip) stays a render
// move over the take.
@MainActor func s060_05(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = Clip060.self
    var layers: [MiniLayer]
    if t < c.toSill {
        layers = [MiniLayer(name: "pictures/ipad-notes-pasted")]
        if let l = fadeIn(t, "pictures/ipad-notes-copy", at: c.copyMenu) { layers.append(l) }
    } else {
        layers = appSwitch(t, at: c.toSill, from: "pictures/ipad-notes-copy", to: "stills/A2-te-cursor", fromRight: false)
        // The chip and the note fade as the app fades them (0.2 s, easeOut).
        if let l = fadeIn(t, "stills/A3p-chip", at: c.chip, over: 0.2) { layers.append(l) }
        if let l = fadeIn(t, "stills/A4-note-pasted", at: c.note, over: 0.2) { layers.append(l) }
    }
    let dots = [Device060.dot(at: c.hold5.0, c.holdPoint5, hold: c.hold5), Device060.dot(at: c.copyTap, c.copyPoint),
                Device060.dot(at: c.pasteChipTap, c.chipPastePoint)]
    let device = try padDevice(e, spec: Pad060.spec, centre: Pad060.centre, yaw: Pad060.yaw, t: t, fetch: c.pushTo,
                               layers: layers, dots: dots)
    // The push (storyboard: 1.0 → 1.3 on the chip): into the screen's top strip, from TextEdit's line (x 193) to the
    // chip's end (x 2235), so the chip and where the text lands both stay in view, the strip filling the right half.
    // The iPad's left edge, pushed under the words, fades out (v3's macro edge).
    let p = CGFloat(ease(t, c.push, c.pushEnd - c.push, .appleOut))
    let s = 1 + (c.pushTo - 1) * p
    let from = Pad060.canvas(CGPoint(x: (193 + 2235) / 2, y: 330))
    let to = CGPoint(x: lerp(from.x, 1480, Double(p)), y: lerp(from.y, 430, Double(p)))
    let drift = 1 + 0.012 * CGFloat(ramp(t, c.pushEnd, 14.4))
    let edge = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 945 / 1920),
                                      .init(color: .white, location: 1005 / 1920), .init(color: .white, location: 1)],
                              startPoint: .leading, endPoint: .trailing).canvas()
    let lines = [leftLine(Copy060.copyIPad, .T1c, baseline: 400, snap: 10.45, end: 14.4),
                 leftLine(Copy060.pasteMac, .T1c, baseline: 504, snap: 12.05, end: 14.4),
                 leftLine(Copy060.pasteSub, .T2, baseline: 588, snap: 12.85, end: 14.4),
                 leftLine(Copy060.pasteFoot, .T3, baseline: 638, snap: 13.25, end: 14.4, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Pad060.centre)
        device.canvas().camera(s * drift, from: from, to: to).mask(edge)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S06 · Sound from your Mac (14.4–19.2)

enum Sound060 {
    static let spec = DeviceSpec.miniM
    static let centre = CGPoint(x: 960, y: 654)
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    /// The movie: v3.1's own opening, 1.6–6.4 s (the icon assembling, the dolly into the Mac), 1:1 in time: the one
    /// 4.8 s of v3.1 with no type in it, so no line of the old reel competes with this one's.
    static func movieTime(_ t: Double) -> Double { 1.6 + (t - 14.4) }
    /// QuickTime's picture (2880×1800) in the still's picture rect: the film letterboxed at y 90–1710, its title bar
    /// (y 0–104) and its controls (740, 1580, 1400×150) drawn over it (tools/draw.swift).
    static let qt = CGSize(width: 2880, height: 1800)
    static let movie = CGRect(x: 0, y: 90, width: 2880, height: 1620)
    static let titleBar = CGRect(x: 0, y: 0, width: 2880, height: 104)
    static let controls = CGRect(x: 740, y: 1580, width: 1400, height: 150)
    /// The Settings panel (B4's, x 1502–2221) and the bar's Settings button, lit while it is open.
    static let panel = CGRect(x: 1498, y: 184, width: 728, height: 1280)
    static let settingsButton = CGRect(x: 2080, y: 0, width: 186, height: 172)
    static let settingsTap = 16.8, mute = 17.6, unmute = 18.4
    static let settingsPoint = CGPoint(x: 2172, y: 86), mutePoint = CGPoint(x: 2160, y: 450)
}

/// A rect of QuickTime's picture (2880×1800 px) → the still's px.
func qtToStill(_ r: CGRect) -> CGRect {
    let s = Mini060.picture.width / Sound060.qt.width
    return CGRect(x: Mini060.picture.minX + r.minX * s, y: Mini060.picture.minY + r.minY * s, width: r.width * s, height: r.height * s)
}

// SWAP-IN (S06, take B): replace with Noah's clip B if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-B.mov, inside Sound060's iPad in place of
// B1 with v3.1's film, the lit Settings button and the B4/B5 panel. Marks: Settings opened 16.8, Mute on 17.6, Mute off
// 18.4 (the score cuts the Mac's sound between them). The take's own audio is never used; the arcs stay drawn.
@MainActor func s060_06(_ t: Double, _ e: Env) throws -> FrameLayers {
    let S = Sound060.self
    let k = S.k
    let size = S.spec.interior
    // The movie playing: v3.1's frame, with QuickTime's title bar and controls over it (cropped from its picture).
    let movieRect = scaledRect(qtToStill(S.movie), k)
    let film = try e.f.film(S.movieTime(t), scale: movieRect.width / 1920)
    let qs = Mini060.picture.width / S.qt.width * k
    let bar = try e.f.crop("pictures/qt-play", S.titleBar, scale: qs), controls = try e.f.crop("pictures/qt-play", S.controls, scale: qs)
    // The panel: B4's (Mute off) or B5's (Mute on), in with the app's own transition (0.94 → 1 about its top-trailing
    // corner, with opacity, a 0.25 s spring), the Settings button lit from the tap.
    let panelIn = ease(t, S.settingsTap, 0.25, .appleOut)
    let muted = ramp(t, S.mute, S.mute + 0.12) * (1 - ramp(t, S.unmute, S.unmute + 0.12))
    let panelRect = scaledRect(S.panel, k)
    let panelOff = try e.f.crop("stills/B4-sound-sendaudio", S.panel, scale: k)
    let panelOn = try e.f.crop("derived/B5-muted", S.panel, scale: k)
    let button = try e.f.crop("stills/B4-sound-sendaudio", S.settingsButton, scale: k)
    let buttonRect = scaledRect(S.settingsButton, k)
    let pScale = 0.94 + 0.06 * CGFloat(panelIn)
    let overlay = ZStack(alignment: .topLeading) {
        Image(decorative: film, scale: 1).resizable().interpolation(.high)
            .frame(width: movieRect.width, height: movieRect.height).offset(x: movieRect.minX, y: movieRect.minY)
        image(bar, in: scaledRect(qtToStill(S.titleBar), k))
        image(controls, in: scaledRect(qtToStill(S.controls), k))
        if t >= S.settingsTap {
            image(button, in: buttonRect)
            ZStack(alignment: .topLeading) {
                image(panelOff, in: panelRect)
                image(panelOn, in: panelRect).opacity(muted)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(pScale, anchor: UnitPoint(x: panelRect.maxX / size.width, y: panelRect.minY / size.height))
            .opacity(panelIn)
        }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    let dots = [Device060.dot(at: S.settingsTap, S.settingsPoint), Device060.dot(at: S.mute, S.mutePoint),
                Device060.dot(at: S.unmute, S.mutePoint)]
    let device = try padDevice(e, spec: S.spec, centre: S.centre, yaw: 0, t: t, fetch: 1.03,
                               layers: [MiniLayer(name: "stills/B1-qt")], dots: dots, overlay: any(overlay))
    let lines = [LineSpec(Copy060.sound, .T1s, baseline: 150, snap: 14.45, holdEnd: 19.2),
                 LineSpec(Copy060.soundSub, .T2, baseline: 214, snap: 15.25, holdEnd: 19.2),
                 LineSpec(Copy060.soundFoot, .T3, baseline: 258, snap: 17.65, holdEnd: 19.2, cascade: false)]
    let arcs = SoundArcs060(origin: SoundArcs060.origin(beside: S.spec, center: S.centre), t: t,
                            beats: SoundArcs060.beats(from: 14.4, to: 19.2), muted: [S.mute...S.unmute])
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: S.centre)
        device.canvas().scaled(1 + 0.02 * CGFloat(ramp(t, 14.4, 19.2)), about: S.centre)
        arcs
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

/// A CGImage drawn into `r` (interior px, top-left origin).
func image(_ img: CGImage, in r: CGRect) -> some View {
    Image(decorative: img, scale: 1).resizable().interpolation(.high).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
}

// MARK: S07–S08 · a locked Mac, and unlocking it (19.2–28.8)

enum Lock060 {
    static let seq: LockSequence060 = {
        var s = LockSequence060()
        // The unlock on the beat at 26.0, not 25.6: the camera pulls back out of the close-up first (25.6–26.3), and the
        // keyboard, which floats in front of it, goes down at 25.55, so the window comes back in the iPad, not bright
        // behind the words; the field's own spinner turns meanwhile.
        s.unlock = 26.0
        s.keyboardLower = 25.55
        // 0.6.0 shows no cover while this session's own screen is locked: the Mac streams its lock screen, and after the
        // password the picture simply comes back (LockedMac.shade; the app's "Unlocking…" follows another user's
        // session only). So no "Unlocking…" here: the field's own spinner, then the window.
        s.appCover = false
        return s
    }()
    static let spec = Pad060.spec
    static let centre = Pad060.centre
    static var k: CGFloat { Pad060.k }
    /// The picture in the iPad's interior (px), and the password field's centre on the canvas (the iPad unturned).
    static var picture: CGRect { scaledRect(Mini060.picture, k) }
    static var field: CGPoint {
        let f = seq.screen.fieldRect(picture)
        return onCanvas(spec, center: centre, CGPoint(x: f.midX, y: f.midY))
    }
    // S08's camera: close on the field (2.6 → 2.7), then back to the iPad at the unlock.
    static let close: CGFloat = 2.6
    static let fieldOnScreen = CGPoint(x: 1300, y: 600)
    static let pullBack = 25.6, pullBackEnd = 26.35
    /// The keyboard: a floating panel under the field, in screen space (the iPad's own would cover the field).
    static let keyboard = CGRect(x: 1300 - 560, y: 700, width: 1120, height: 330)
}

/// The lock screen (and the dots in its field, the spinner after Return) over the picture, in the iPad's interior px.
struct LockPicture060: View {
    let t: Double
    var body: some View {
        Canvas { ctx, _ in
            let pic = Lock060.picture
            // The stream panel around the picture is black, as on L0 (the cover L1 shows is not 0.6.0's here).
            Lock060.seq.drawPicture(&ctx, rect: pic, pt: Lock060.spec.interior.width / Device060.miniPoints.width, t: t)
        }
        .frame(width: Lock060.spec.interior.width, height: Lock060.spec.interior.height)
    }
}

@MainActor func lockDevice(_ e: Env, t: Double, yaw: Double, fetch: CGFloat) throws -> some View {
    let seq = Lock060.seq
    // The bar: L0w's thumbnails until the lock, L1x's (none) while locked, L0w's again from the unlock.
    let locked = t >= seq.lock && t < seq.unlock
    let base = locked ? "derived/L1x" : "derived/L0w"
    return try padDevice(e, spec: Lock060.spec, centre: Lock060.centre, yaw: yaw, t: t, fetch: fetch,
                         layers: [MiniLayer(name: base)], overlay: any(LockPicture060(t: t)))
}

@MainActor func s060_07(_ t: Double, _ e: Env) throws -> FrameLayers {
    let device = try lockDevice(e, t: t, yaw: Pad060.yaw, fetch: 1.05)
    let pic = Lock060.picture
    let about = onCanvas(Lock060.spec, center: Lock060.centre, CGPoint(x: pic.midX, y: pic.midY))
    let lines = [leftLine(Copy060.locked, .T1c, baseline: 430, snap: 19.25, end: 24.0),
                 leftLine(Copy060.lockScreen, .T4, baseline: 520, snap: 19.65, end: 24.0),
                 leftLine(Copy060.lockSub[0], .T2, baseline: 600, snap: 20.85, end: 24.0),
                 leftLine(Copy060.lockSub[1], .T2, baseline: 644, snap: 21.10, end: 24.0)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Lock060.centre)
        device.canvas().scaled(1 + 0.04 * CGFloat(ramp(t, 19.2, 24.0)), about: about)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

@MainActor func s060_08(_ t: Double, _ e: Env) throws -> FrameLayers {
    let L = Lock060.self, seq = L.seq
    let device = try lockDevice(e, t: t, yaw: 0, fetch: 2.7)
    // The camera: close on the field from the cut (2.6 → 2.7), back to the iPad at the unlock (inOut), then a slow push.
    let back = CubicBezier.inOut(ramp(t, L.pullBack, L.pullBackEnd))
    let closeScale = L.close + 0.1 * CGFloat(ramp(t, 24.0, L.pullBack))
    let s = lerp(closeScale, 1.0, back) * (1 + 0.025 * CGFloat(ramp(t, L.pullBackEnd, 28.8)))
    let to = CGPoint(x: lerp(L.fieldOnScreen.x, L.field.x, back), y: lerp(L.fieldOnScreen.y, L.field.y, back))
    // The keyboard rises at 24.0 and goes down at the unlock; its keys flash under the taps.
    let kb = L.keyboard
    let drop = SoftKeyboard060.offset(t, height: kb.height + 80, rise: seq.keyboardRise, lower: seq.keyboardLower)
    let keyboard = Canvas { ctx, _ in
        SoftKeyboard060.draw(&ctx, rect: kb.offsetBy(dx: 0, dy: drop), t: t, flash: seq.flash, floating: true)
    }.canvas()
    let dots = seq.dots(keyboard: kb).map { CanvasDot(at: $0.time, point: $0.point, d: 78, t: t) }
    let lines = [leftLine(Copy060.unlock, .T1c, baseline: 430, snap: 24.05, end: 28.8),
                 leftLine(Copy060.unlockSub, .T2, baseline: 512, snap: 26.05, end: 28.8),
                 leftLine(Copy060.unlockFoot, .T3, baseline: 562, snap: 26.45, end: 28.8, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Lock060.centre)
        device.canvas().camera(s, from: L.field, to: to)
        keyboard
        ForEach(0..<dots.count, id: \.self) { dots[$0] }
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}
