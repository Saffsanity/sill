// Shots060Clip.swift — Act II, the big three (v4's 6.4–28.8; film 11.2–46.4): the clipboard both ways (S04–S05), sound
// (S06), a locked Mac and unlocking it (S07–S08). The times here are v4's; the film plays them through Retime060's maps,
// and the devices' drifts, S06's movie and arcs and S08's spinner run on film time (`Env.glide`, `Env.filmTime`). The iPad mini's screens are harness stills and drawn pictures (Reel060.swift),
// stand-ins for Noah's takes A and B (swap-in points in SHOTLIST-0.6.0.md); what the stills cannot show is drawn:
// touch dots, the iPadOS app switch and edit menus, the app's own transitions (the chip's and the Settings panel's), the
// movie QuickTime plays (v3.1's own frames) and its window, the sound arcs, the lock screen, the keyboard and the dots
// in the field.
//
// The review of 2026-11-02, here: the iPad beside the words keeps 80 px or more from them (v2 S23's rule; `clearance`
// measures it) and drifts away from them; footnotes snap with their shot's first statement and long sublines land within
// about 0.25 s (`capped`); the edit menus are opaque, with their tail, and a hold's finger lifts before the tap after it;
// S05's chip and note are shown large above the iPad (`ChipInset060`); S06's Mute cuts on the beat, the arcs folding
// with it; S08's keyboard rises inside the iPad's screen and the camera never crosses the words.
import AppKit
import SwiftUI

// MARK: - The iPad beside the words

enum Pad060 {
    /// The iPad mini beside a left column of words (x 128, T1c lines up to 951 px with their hold): a 790×519 interior
    /// (the first cut's 820 made 3.7 % smaller, so it clears the words by 80 px and still fits the frame), turned 4° (its
    /// inner edge toward the lens, as v3's devices beside words): its outer edge at about x 1031–1891, 1909 at the end of
    /// S04's drift (11 px from the frame's edge).
    static let spec = DeviceSpec(interior: CGSize(width: 790, height: 519), bezel: 27, innerRadius: 21, outerRadius: 48)
    static let centre = CGPoint(x: 1478, y: 560)
    static let yaw: Double = -4
    /// A drift's anchor: the turned iPad's left edge, so it grows away from the words, never toward them.
    static let leftEdge = CGPoint(x: 1031, y: 560)
    /// Interior px per still px.
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    /// A still point (px) on the canvas, for this iPad unturned at `centre`.
    static func canvas(_ p: CGPoint, centre: CGPoint = centre) -> CGPoint { onCanvas(spec, center: centre, CGPoint(x: p.x * k, y: p.y * k)) }
}

/// The left column's words: T1c statements at x 128, sublines and footnotes under them.
func leftLine(_ text: String, _ style: TypeStyle, baseline: CGFloat, snap: Double, end: Double, cascade: Bool = true) -> LineSpec {
    LineSpec(text, style, x: 128, baseline: baseline, align: .leading, snap: snap, holdEnd: end, cascade: cascade)
}

/// A subline of more than 8 words lands within `span` (the review: 0.25 s), its words' cascade shortened; set on two
/// lines (or more), it counts as one: the next line's words follow the last word of the line before on the same step.
func capped(_ lines: [LineSpec], span: Double = 0.25) -> [LineSpec] {
    let n = lines.reduce(0) { $0 + $1.words.count }
    guard n > 8, let first = lines.first else { return lines }
    let step = span / Double(n - 1)
    var out: [LineSpec] = []
    var before = 0
    for var l in lines {
        l.step = step
        l.snap = first.snap + step * Double(before)
        before += l.words.count
        out.append(l)
    }
    return out
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

/// A still that fades in over `from` (a crossfade where only part of the screen changes: a selection, a chip).
func fadeIn(_ t: Double, _ name: String, at: Double, over d: Double = 0.12) -> MiniLayer? {
    t >= at ? MiniLayer(name: name, opacity: ramp(t, at, at + d)) : nil
}

// MARK: - iPadOS's edit menu (drawn, for the Notes stand-in)

/// iPadOS's edit menu with one command, drawn: an opaque #2C2C2E rounded box, its label in white (17 pt), a tail under it
/// pointing at the text it acts on, a soft shadow. It pops in (0.10 s, from 90 % about its tail) as the finger lifts and
/// fades (0.08 s) when its command is tapped. Geometry in the iPad still's px (2266×1488, 2 px a point), drawn in the
/// iPad's interior px (`k` per still px).
struct EditMenu060: View {
    let label: String
    /// The menu's centre x, its bottom edge, and the tail's tip, in still px.
    let centreX: CGFloat, bottom: CGFloat, tip: CGFloat
    let appear: Double, dismiss: Double
    let k: CGFloat
    let size: CGSize
    let t: Double

    var body: some View {
        Canvas { ctx, _ in
            guard t >= appear else { return }
            let pin = ease(t, appear, 0.10, .appleOut)
            let alpha = pin * (1 - ramp(t, dismiss, dismiss + 0.08))
            guard alpha > 0.002 else { return }
            let font: CGFloat = 34 * k, h: CGFloat = 76 * k, pad: CGFloat = 30 * k
            let line = Outline060.line(label, size: font, weight: .regular)
            let w = line.width + 2 * pad
            let box = CGRect(x: centreX * k - w / 2, y: bottom * k - h, width: w, height: h)
            var shape = Path(roundedRect: box, cornerRadius: 16 * k, style: .continuous)
            let tw = 28 * k
            var tail = Path()
            tail.move(to: CGPoint(x: centreX * k - tw / 2, y: box.maxY - 1))
            tail.addLine(to: CGPoint(x: centreX * k, y: tip * k))
            tail.addLine(to: CGPoint(x: centreX * k + tw / 2, y: box.maxY - 1))
            tail.closeSubpath()
            shape.addPath(tail)
            var c = ctx
            c.opacity = alpha
            let s = 0.9 + 0.1 * CGFloat(pin)
            c.concatenate(CGAffineTransform.scaling(s, about: CGPoint(x: centreX * k, y: tip * k)))
            c.drawLayer { g in
                g.addFilter(.blur(radius: 10 * k))
                g.fill(shape.offsetBy(dx: 0, dy: 4 * k), with: .color(.black.opacity(0.28)))
            }
            c.fill(shape, with: .color(Color(hex: 0x2C2C2E)))
            Outline060.fill(line, in: &c, at: CGPoint(x: box.midX - line.width / 2, y: box.midY + font * 0.36), color: .white)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: S04 · Copy on your Mac, paste on your iPad (6.4–10.4)

enum Clip060 {
    // S04 (take A part 1): TextEdit's line selected, ⌘C at the Mac, then Notes on the iPad: touch and hold the empty line,
    // lift (the edit menu shows Paste above it), Paste, the line lands.
    static let cmdDown = 7.10, cDown = 7.20, keysUp = 7.42
    static let toNotes = 7.6
    static let hold4 = (7.95, 8.15), holdPoint4 = CGPoint(x: 300, y: 460)
    static let pasteMenu = 8.17, pasteTap = 8.32, pastePoint = CGPoint(x: 300, y: 366)
    static let lands = 8.40
    // S05 (take A part 2): touch and hold the reply (it is selected), Copy, back to Sill, the chip, the push, Paste, the note.
    static let hold5 = (10.55, 10.78), holdPoint5 = CGPoint(x: 480, y: 368)
    static let selected = 10.76, copyMenu = 10.82, copyTap = 11.05, copyPoint = CGPoint(x: 480, y: 284)
    static let toSill = 11.2, chip = 11.55
    /// The storyboard's push is 1.0 → 1.3; at 1.3 the strip (TextEdit's line to the chip's end) is wider than the room
    /// beside the words, so it pushes to 1.14, the strip from about x 1090 to 1895, and the chip is shown large above
    /// the iPad (`ChipInset060`).
    static let push = 11.6, pushEnd = 12.15, pushTo: CGFloat = 1.14
    static let pasteChipTap = 12.0, chipPastePoint = CGPoint(x: 2051, y: 250)
    static let note = 12.15
    /// The column's words end at about x 951 (with their hold): the iPad's far edge is faded out from 1080 down to 1020.
    static let fadeFrom: CGFloat = 1020, fadeTo: CGFloat = 1080
}

// SWAP-IN (S04, take A part 1): replace with Noah's clip A if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-A.mov, inside Pad060's picture in
// place of the MiniScreen layers (A1, notes-plain, the drawn edit menu, ipad-notes-pasted). Marks to align the take to: ⌘C
// pressed at the Mac 7.20 (the drawn keycaps stay and press then), Notes on the iPad 7.6, the touch and hold 7.95,
// Paste 8.32, the line landing in Notes 8.40 (the A5 pluck). SHOTLIST-0.6.0.md §7 has the steps.
// v4.1: the marks above are v4's (this builder's own) times; the film plays the scene through its time map, so a take
// runs on film time (`e.filmTime(t)`), its marks at the film times in design/reel/v4.1/SHOTLIST-0.6.md §7.
@MainActor func s060_04(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = Clip060.self
    var layers = appSwitch(t, at: c.toNotes, from: "stills/A1-te-select", to: "derived/notes-plain")
    if let l = fadeIn(t, "pictures/ipad-notes-pasted", at: c.lands, over: 0.10) { layers.append(l) }
    let dots = [Device060.dot(at: c.hold4.0, c.holdPoint4, hold: c.hold4, liftFade: 0.04), Device060.dot(at: c.pasteTap, c.pastePoint)]
    let menu = EditMenu060(label: "Paste", centreX: c.holdPoint4.x, bottom: 404, tip: 420, appear: c.pasteMenu, dismiss: c.pasteTap + 0.02,
                           k: Pad060.k, size: Pad060.spec.interior, t: t)
    let device = try padDevice(e, spec: Pad060.spec, centre: Pad060.centre, yaw: Pad060.yaw, t: t, fetch: 1.03, layers: layers, dots: dots,
                               overlay: any(menu))
    // The keycaps: in under the words (0.25 s, 10 px up), ⌘ and C pressed for ⌘C on the beat at 7.2.
    let rise = ease(t, 6.80, 0.25, .appleOut)
    let keys = KeycapRow060(keys: [.command, .letter("C")], unit: 96, origin: CGPoint(x: 128, y: 452 + 10 * CGFloat(1 - rise)), t: t,
                            presses: [0: KeyPress060(down: c.cmdDown, up: c.keysUp), 1: KeyPress060(down: c.cDown, up: c.keysUp)])
    let lines = [leftLine(Copy060.copyMac, .T1c, baseline: 400, snap: 6.45, end: 10.4),
                 leftLine(Copy060.pasteIPad, .T1c, baseline: 664, snap: 8.45, end: 10.4),
                 leftLine(Copy060.needsMac, .T3, baseline: 726, snap: 6.50, end: 10.4, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Pad060.centre)
        // Drifting: a 2 % push about the iPad's left edge (a render transform, so it glides), away from the words.
        device.canvas().scaled(1 + 0.02 * CGFloat(e.glide(t, 6.4, 10.4)), about: Pad060.leftEdge)
        keys.opacity(rise)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S05 · Copy on your iPad, paste on your Mac (10.4–14.4)

/// S05's inset (the review: the chip's words were about 7 px tall in the iPad): the app's chip "Paste on Noah’s MacBook
/// Pro" (still A3p), then its note "Pasted on Noah’s MacBook Pro." (A4), cut from the stills to their capsules and shown
/// 1.8 times a still's px (their words 34 px tall), right-aligned above the iPad, over the place the chip has in it. In
/// with the chip (0.25 s, rising 12 px); the note takes the chip's place as the app's does (0.2 s).
struct ChipInset060: View {
    static let scale: CGFloat = 1.8
    /// The capsules in the stills (px, measured), and the inset's right edge and top on the canvas.
    static let chip = CGRect(x: 1489, y: 205, width: 745, height: 91)
    static let noteRect = CGRect(x: 1746, y: 205, width: 488, height: 67)
    static let right: CGFloat = 1890, top: CGFloat = 64
    static let appear = 11.62

    let chipImage: CGImage, noteImage: CGImage
    let t: Double

    static func fetch(_ r: CGRect) -> CGRect { r.insetBy(dx: -2, dy: -2) }

    private func capsule(_ img: CGImage, _ r: CGRect, alpha: Double, rise: CGFloat) -> some View {
        let s = ChipInset060.scale
        let f = ChipInset060.fetch(r)
        let origin = CGPoint(x: ChipInset060.right - (r.maxX - f.minX) * s, y: ChipInset060.top - (r.minY - f.minY) * s + rise)
        let shape = RoundedRectangle(cornerRadius: r.height * s / 2, style: .continuous)
            .frame(width: r.width * s, height: r.height * s)
            .offset(x: (r.minX - f.minX) * s, y: (r.minY - f.minY) * s)
        return Image(decorative: img, scale: 1).resizable().interpolation(.high)
            .frame(width: f.width * s, height: f.height * s)
            .mask(shape.frame(width: f.width * s, height: f.height * s, alignment: .topLeading))
            .opacity(alpha)
            .transformEffect(CGAffineTransform(translationX: origin.x, y: origin.y))
    }

    var body: some View {
        let inP = ease(t, ChipInset060.appear, 0.25, .appleOut)
        let rise = 12 * CGFloat(1 - inP)
        let toNote = ease(t, Clip060.note, 0.2, .appleOut)
        return ZStack(alignment: .topLeading) {
            Color.clear.canvas()
            if t >= ChipInset060.appear {
                capsule(chipImage, ChipInset060.chip, alpha: inP * (1 - toNote), rise: rise)
                if t >= Clip060.note { capsule(noteImage, ChipInset060.noteRect, alpha: inP * toNote, rise: rise) }
            }
        }
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
}

// SWAP-IN (S05, take A part 2): replace with Noah's clip A if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-A.mov (its second half). Marks: the
// touch and hold on the reply 10.55, Copy 11.05, back in Sill 11.2, the chip risen 11.55 (E5), Paste on the chip 12.0
// (C♯6), the note "Pasted on Noah’s MacBook Pro." from 12.15. The push (11.6–12.15, to 1.14 on the chip) stays a render
// move over the take, and so does the inset (`ChipInset060`: crop it from the take's frames, at the chip's place).
// v4.1: the marks above are v4's (this builder's own) times; the film plays the scene through its time map, so a take
// runs on film time (`e.filmTime(t)`), its marks at the film times in design/reel/v4.1/SHOTLIST-0.6.md §7.
@MainActor func s060_05(_ t: Double, _ e: Env) throws -> FrameLayers {
    let c = Clip060.self
    var layers: [MiniLayer]
    var overlay: AnyView? = nil
    if t < c.toSill {
        layers = [MiniLayer(name: "pictures/ipad-notes-pasted")]
        if let l = fadeIn(t, "derived/notes-selected", at: c.selected, over: 0.06) { layers.append(l) }
        overlay = any(EditMenu060(label: "Copy", centreX: c.holdPoint5.x, bottom: 322, tip: 338, appear: c.copyMenu, dismiss: c.copyTap + 0.02,
                                  k: Pad060.k, size: Pad060.spec.interior, t: t))
    } else {
        layers = appSwitch(t, at: c.toSill, from: "derived/notes-selected", to: "stills/A2-te-cursor", fromRight: false)
        // The chip and the note fade as the app fades them (0.2 s, easeOut).
        if let l = fadeIn(t, "stills/A3p-chip", at: c.chip, over: 0.2) { layers.append(l) }
        if let l = fadeIn(t, "stills/A4-note-pasted", at: c.note, over: 0.2) { layers.append(l) }
    }
    let dots = [Device060.dot(at: c.hold5.0, c.holdPoint5, hold: c.hold5, liftFade: 0.04), Device060.dot(at: c.copyTap, c.copyPoint),
                Device060.dot(at: c.pasteChipTap, c.chipPastePoint)]
    let device = try padDevice(e, spec: Pad060.spec, centre: Pad060.centre, yaw: Pad060.yaw, t: t, fetch: c.pushTo,
                               layers: layers, dots: dots, overlay: overlay)
    // The push (storyboard: 1.0 → 1.3 on the chip): into the screen's top strip, from TextEdit's line (x 193) to the
    // chip's end (x 2235), so the chip and where the text lands both stay in view. The iPad's far edge, pushed toward
    // the words, fades out (v3's macro edge) 80 px clear of them.
    // v4.1, the review: the chip is held still half a bar before Paste (Retime060.s05's dwell, v4's 11.87–11.91), so the
    // push runs on film time, its 0.55 s 1.25× slower (0.6875 s) from v4's 11.6, settling inside that held moment instead of
    // stalling in it; the drift starts as it settles. Without a clock (asset previews) both are v4's.
    let p: CGFloat, drift: CGFloat
    if e.clock != nil {
        let a = e.film(c.push), d = 1.25 * (c.pushEnd - c.push)
        p = CGFloat(ease(e.filmTime(t), a, d, .appleOut))
        drift = 1 + 0.012 * CGFloat(ramp(e.filmTime(t), a + d, e.film(14.4)))
    } else {
        p = CGFloat(ease(t, c.push, c.pushEnd - c.push, .appleOut))
        drift = 1 + 0.012 * CGFloat(e.glide(t, c.pushEnd, 14.4))
    }
    let s = 1 + (c.pushTo - 1) * p
    let from = Pad060.canvas(CGPoint(x: (193 + 2235) / 2, y: 330))
    let to = CGPoint(x: lerp(from.x, 1490, Double(p)), y: lerp(from.y, 430, Double(p)))
    let edge = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: c.fadeFrom / 1920),
                                      .init(color: .white, location: c.fadeTo / 1920), .init(color: .white, location: 1)],
                              startPoint: .leading, endPoint: .trailing).canvas()
    var lines = [leftLine(Copy060.copyIPad, .T1c, baseline: 400, snap: 10.45, end: 14.4),
                 leftLine(Copy060.pasteMac, .T1c, baseline: 504, snap: 12.05, end: 14.4)]
    lines += capped([leftLine(Copy060.pasteSub, .T2, baseline: 588, snap: 12.85, end: 14.4)])
    lines.append(leftLine(Copy060.pasteFoot, .T3, baseline: 638, snap: 10.50, end: 14.4, cascade: false))
    let inset = ChipInset060(chipImage: try e.f.crop("stills/A3p-chip", ChipInset060.fetch(ChipInset060.chip), scale: ChipInset060.scale),
                             noteImage: try e.f.crop("stills/A4-note-pasted", ChipInset060.fetch(ChipInset060.noteRect), scale: ChipInset060.scale),
                             t: t)
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Pad060.centre)
        device.canvas().camera(s * drift, from: from, to: to).mask(edge)
        inset
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S06 · Sound from your Mac (14.4–19.2)

enum Sound060 {
    static let spec = DeviceSpec.miniM
    static let centre = CGPoint(x: 960, y: 654)
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    /// The movie: v3.1's own opening from 1.6 s (the icon assembling, the dolly into the Mac), inside the one stretch of
    /// v3.1 with no type in it (1.6–6.4), so no line of the old reel competes with this one's. v4 played 1.6–6.4 1:1 in its
    /// 4.8 s. v4.1's S06 is 8.4 s: its first cut played the 4.8 s evenly over it (0.57×), which advanced v3.1's frames 2, 2,
    /// 2, 1 film frames apart, a judder in the dolly (the review of v4.1); now it plays at exactly half speed, each of
    /// v3.1's frames on two of the film's (an even 30 fps): 252 frames, 1.6–5.783 s, over the shot's 504.
    static func movieTime(progress p: Double) -> Double { 1.6 + 4.8 * p }
    static let movieFirstFrame = 96, movieFrames = 252
    /// v3.1's time for film frame `n` of a shot whose first frame is `n0`: frame 96 + (n − n0) / 2, a tenth of a
    /// millisecond past its own time so the reader's "latest sample at or before" takes it whatever the rounding.
    static func movieTime(filmFrame n: Int, sceneStart n0: Int) -> Double {
        Double(movieFirstFrame + min(movieFrames - 1, max(0, n - n0) / 2)) / 60 + 0.0001
    }
    /// QuickTime's picture (2880×1800) in the still's picture rect: the film letterboxed at y 90–1710, its title bar
    /// (y 0–104) and its controls drawn over it (QuickTime060, as tools/draw.swift drew them, titled "Sill.mp4").
    static let qt = QuickTime060.size
    static let movie = QuickTime060.movie
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
// B1x with v3.1's film and QuickTime's drawn window, the lit Settings button and the B4/B5 panel. Marks: Settings opened
// 16.8, Mute on 17.6, Mute off 18.4 (the score cuts the Mac's sound between them). The take's own audio is never used;
// the arcs stay drawn.
// v4.1: the marks above are v4's (this builder's own) times; the film plays the scene through its time map, so a take
// runs on film time (`e.filmTime(t)`), its marks at the film times in design/reel/v4.1/SHOTLIST-0.6.md §7.
@MainActor func s060_06(_ t: Double, _ e: Env) throws -> FrameLayers {
    let S = Sound060.self
    let k = S.k
    let size = S.spec.interior
    // The movie playing: v3.1's frame, with QuickTime's title bar and controls drawn over it (its time and progress the
    // movie's own).
    let movieRect = scaledRect(qtToStill(S.movie), k)
    // At half speed on film frames (each of v3.1's frames twice); without a clock (asset previews) v4's 1:1.
    let mt: Double
    if let c = e.clock {
        mt = S.movieTime(filmFrame: Int((c.T * 60).rounded()), sceneStart: Int((e.film(14.4) * 60).rounded()))
    } else {
        mt = S.movieTime(progress: ramp(t, 14.4, 19.2))
    }
    let film = try e.f.film(mt, scale: movieRect.width / 1920)
    let qs = Mini060.picture.width / S.qt.width * k
    let chrome = Canvas { ctx, _ in
        ctx.withCGContext { cg in
            cg.translateBy(x: Mini060.picture.minX * k, y: Mini060.picture.minY * k)
            cg.scaleBy(x: qs, y: qs)
            QuickTime060.drawChrome(cg, movieTime: mt)
        }
    }.frame(width: size.width, height: size.height)
    // The panel: B4's (Mute off) or B5's (Mute on), in with the app's own transition (0.94 → 1 about its top-trailing
    // corner, with opacity, a 0.25 s spring), the Settings button lit from the tap. Mute cuts on the beat, 17.6 and 18.4.
    let panelIn = ease(t, S.settingsTap, 0.25, .appleOut)
    let muted = t >= S.mute && t < S.unmute
    let panelRect = scaledRect(S.panel, k)
    let panelImage = try e.f.crop(muted ? "derived/B5-muted" : "stills/B4-sound-sendaudio", S.panel, scale: k)
    let button = try e.f.crop("stills/B4-sound-sendaudio", S.settingsButton, scale: k)
    let buttonRect = scaledRect(S.settingsButton, k)
    let pScale = 0.94 + 0.06 * CGFloat(panelIn)
    let pictureRect = scaledRect(Mini060.picture, k)
    let overlay = ZStack(alignment: .topLeading) {
        // QuickTime's whole window black first (B1x's own window, under the drawn one's translucent bars, never shows).
        Path(pictureRect).fill(Color.black)
        Image(decorative: film, scale: 1).resizable().interpolation(.high)
            .frame(width: movieRect.width, height: movieRect.height).offset(x: movieRect.minX, y: movieRect.minY)
        chrome
        if t >= S.settingsTap {
            image(button, in: buttonRect)
            ZStack(alignment: .topLeading) {
                image(panelImage, in: panelRect)
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
                               layers: [MiniLayer(name: "derived/B1x")], dots: dots, overlay: any(overlay))
    var lines = [LineSpec(Copy060.sound, .T1s, baseline: 150, snap: 14.45, holdEnd: 19.2)]
    lines += capped([LineSpec(Copy060.soundSub, .T2, baseline: 214, snap: 15.25, holdEnd: 19.2)])
    lines.append(LineSpec(Copy060.soundFoot, .T3, baseline: 258, snap: 17.65, holdEnd: 19.2, cascade: false))
    // The arcs keep the score's beat (film time): every beat of the shot, folded from Mute to its end.
    let arcs = SoundArcs060(origin: SoundArcs060.origin(beside: S.spec, center: S.centre), t: e.filmTime(t),
                            beats: SoundArcs060.beats(from: e.film(14.4), to: e.film(19.2)), muted: [e.film(S.mute)...e.film(S.unmute)])
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: S.centre)
        device.canvas().scaled(1 + 0.02 * CGFloat(e.glide(t, 14.4, 19.2)), about: S.centre)
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
        // The keyboard rises inside the iPad's screen at 24.0 and covers the bottom of the picture, the password field
        // with it, as iPadOS's keyboard does over Sill's stream screen (which leaves the keyboard over the picture). Return
        // at 25.2; it goes down from 25.25, and the field shows its eight dots and its spinner; the unlock is on the beat
        // at 26.0, while the camera pulls back (25.6–26.35).
        s.unlock = 26.0
        s.keyboardLower = 25.25
        // 0.6.0 shows no cover while this session's own screen is locked: the Mac streams its lock screen, and after the
        // password the picture simply comes back (LockedMac.shade; the app's "Unlocking…" follows another user's
        // session only). So no "Unlocking…" here: the field's own spinner, then the window.
        s.appCover = false
        return s
    }()
    static let spec = Pad060.spec
    static let centre = Pad060.centre
    static var k: CGFloat { Pad060.k }
    /// The picture in the iPad's interior (px).
    static var picture: CGRect { scaledRect(Mini060.picture, k) }
    /// iPadOS's keyboard in the interior, docked: 44 % of the screen's height (an iPad mini's in landscape).
    static var keyboard: CGRect {
        let s = spec.interior
        return CGRect(x: 0, y: s.height * 0.56, width: s.width, height: s.height * 0.44)
    }
    // S08's camera: close (1.40 → 1.44) and back to the iPad at the unlock, then a slow push (1.01), always about the
    // iPad's lower left corner, so it grows up and away from the words and its left edge never moves (the review: the
    // pull-back had swept the bezel through "Unlock it from here.").
    static let close: CGFloat = 1.40
    static let pullBack = 25.6, pullBackEnd = 26.35
    static var anchor: CGPoint { CGPoint(x: centre.x - spec.outer.width / 2, y: centre.y + spec.outer.height / 2) }
}

/// The lock screen (and the dots in its field, the spinner after Return) over the picture, and S08's keyboard rising
/// inside the screen, in the iPad's interior px.
struct LockPicture060: View {
    let t: Double
    var keyboard = false
    /// The field's spinner's clock (film time: it spins on through S08's held moment).
    var spin: Double? = nil
    var body: some View {
        Canvas { ctx, _ in
            let pic = Lock060.picture
            // The stream panel around the picture is black, as on L0 (the cover L1 shows is not 0.6.0's here).
            Lock060.seq.drawPicture(&ctx, rect: pic, pt: Lock060.spec.interior.width / Device060.miniPoints.width, t: t, spin: spin)
            if keyboard {
                let kb = Lock060.keyboard
                let drop = SoftKeyboard060.offset(t, height: kb.height, rise: Lock060.seq.keyboardRise, lower: Lock060.seq.keyboardLower)
                if drop < kb.height + 23 {
                    SoftKeyboard060.draw(&ctx, rect: kb.offsetBy(dx: 0, dy: drop), t: t, flash: Lock060.seq.flash, floating: false)
                }
            }
        }
        .frame(width: Lock060.spec.interior.width, height: Lock060.spec.interior.height)
    }
}

@MainActor func lockDevice(_ e: Env, t: Double, yaw: Double, fetch: CGFloat, keyboard: Bool = false, dots: [TouchDotSpec] = []) throws -> some View {
    let seq = Lock060.seq
    // The bar: L0w's thumbnails until the lock, L1x's (none) while locked, L0w's again from the unlock.
    let locked = t >= seq.lock && t < seq.unlock
    let base = locked ? "derived/L1x" : "derived/L0w"
    return try padDevice(e, spec: Lock060.spec, centre: Lock060.centre, yaw: yaw, t: t, fetch: fetch,
                         layers: [MiniLayer(name: base)], dots: dots, overlay: any(LockPicture060(t: t, keyboard: keyboard, spin: e.filmTime(t))))
}

@MainActor func s060_07(_ t: Double, _ e: Env) throws -> FrameLayers {
    let device = try lockDevice(e, t: t, yaw: Pad060.yaw, fetch: 1.05)
    let pic = Lock060.picture
    let about = onCanvas(Lock060.spec, center: Lock060.centre, CGPoint(x: pic.midX, y: pic.midY))
    var lines = [leftLine(Copy060.locked, .T1c, baseline: 430, snap: 19.25, end: 24.0),
                 leftLine(Copy060.lockScreen, .T4, baseline: 520, snap: 19.65, end: 24.0)]
    lines += capped([leftLine(Copy060.lockSub[0], .T2, baseline: 600, snap: 20.85, end: 24.0),
                     leftLine(Copy060.lockSub[1], .T2, baseline: 644, snap: 21.10, end: 24.0)])
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Lock060.centre)
        device.canvas().scaled(1 + 0.04 * CGFloat(e.glide(t, 19.2, 24.0)), about: about)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

@MainActor func s060_08(_ t: Double, _ e: Env) throws -> FrameLayers {
    let L = Lock060.self, seq = L.seq
    // The taps land on the keyboard's keys inside the screen (the interior's px → the still's, for the dots).
    let dots = seq.dots(keyboard: L.keyboard).map { Device060.dot(at: $0.time, CGPoint(x: $0.point.x / L.k, y: $0.point.y / L.k)) }
    let device = try lockDevice(e, t: t, yaw: 0, fetch: 1.5, keyboard: true, dots: dots)
    // The camera: close from the cut (1.40 → 1.44), back to the iPad from 25.6 (inOut), then a slow push to 1.01, all
    // about the iPad's lower left corner.
    let back = CubicBezier.inOut(ramp(t, L.pullBack, L.pullBackEnd))
    let closeScale = L.close + 0.04 * CGFloat(e.glide(t, 24.0, L.pullBack))
    let s = lerp(closeScale, 1.0, back) * (1 + 0.01 * CGFloat(e.glide(t, L.pullBackEnd, 28.8)))
    var lines = [leftLine(Copy060.unlock, .T1c, baseline: 430, snap: 24.05, end: 28.8)]
    lines += capped([leftLine(Copy060.unlockSub, .T2, baseline: 512, snap: 26.05, end: 28.8)])
    lines.append(leftLine(Copy060.unlockFoot, .T3, baseline: 562, snap: 24.10, end: 28.8, cascade: false))
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: Lock060.centre)
        device.canvas().camera(s, from: L.anchor, to: L.anchor)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}
