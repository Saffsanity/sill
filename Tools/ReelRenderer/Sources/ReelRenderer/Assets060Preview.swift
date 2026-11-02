// Assets060Preview.swift — `ReelRenderer assets <dir> [name-prefix …]`: PNG stills of the 0.6.0 reel's drawn
// assets and device frames, each at the storyboard's key times, finished as the film's frames are (grain, the
// dither, the vignette where the shot has one), plus an index sheet. It needs no input from `work/`: the
// screens in the devices here are the PREVIEW ONLY stand-in (`PreviewStreamScreen060`), never the film's.
import AppKit
import CoreText
import SwiftUI

@MainActor enum Preview060 {
    struct Still { let name: String; let t: Double; let layers: FrameLayers; let note: String }

    /// The footage stand-ins (`REEL060_FOOTAGE`, a folder with `stills/`, as the 0.6.0 footage agent made them):
    /// when set, the previews put the assets over those stills, as the film will; else over the drawn stand-in.
    static let footageDir: URL? = ProcessInfo.processInfo.environment["REEL060_FOOTAGE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    private static var loaded: [String: CGImage] = [:]
    static func footage(_ name: String) -> CGImage? {
        if let hit = loaded[name] { return hit }
        guard let dir = footageDir,
              let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("stills/\(name).png") as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        loaded[name] = img
        return img
    }
    /// An iPad mini screen: the still `name` if the footage is there, else the drawn stand-in.
    static func miniScreen(_ name: String, _ size: CGSize, locked: Bool = false) -> AnyView {
        if let img = footage(name) {
            return any(Image(decorative: img, scale: 1).resizable().interpolation(.high).frame(width: size.width, height: size.height))
        }
        return any(PreviewStreamScreen060(size: size, locked: locked))
    }

    /// A device standing in the frame with a screen built from its interior size.
    static func device<C: View>(_ spec: DeviceSpec, center: CGPoint, yaw: Double = 0, pitch: Double = 0,
                                @ViewBuilder _ content: () -> C) -> some View {
        let screen = content()
        return PlacedDevice(spec: spec, center: center, yaw: yaw, pitch: pitch) {
            ZStack(alignment: .topLeading) { screen }
                .frame(width: spec.interior.width, height: spec.interior.height, alignment: .topLeading)
        }
    }

    /// Context type for a still (Outline060, so the previews never depend on the timeline's type).
    static func words(_ lines: [(String, CGFloat, NSFont.Weight, UInt32, CGFloat, CGFloat, Bool)]) -> some View {
        Canvas { ctx, _ in
            for (s, size, w, color, x, baseline, leading) in lines {
                Outline060.draw(s, in: &ctx, size: size, weight: w, tracking: size >= 100 ? -0.022 * size : (size >= 50 ? -0.014 * size : 0),
                                x: x, baseline: baseline, leading: leading, color: Color(hex: color))
            }
        }.canvas()
    }

    /// The portrait stand-in for the iPhone: a picture at the top, rows, a dark well. PREVIEW ONLY.
    struct PhoneStandIn: View {
        let size: CGSize
        var body: some View {
            Canvas { ctx, _ in
                let k = size.width / Device060.phonePoints.width
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x101215)))
                let pic = CGRect(x: 8 * k, y: 62 * k, width: size.width - 16 * k, height: (size.width - 16 * k) / 1.6 * 1.55)
                ctx.fill(Path(pic), with: .linearGradient(Gradient(colors: [Color(hex: 0x2B3550), Color(hex: 0x12151E)]),
                                                         startPoint: CGPoint(x: pic.minX, y: pic.minY), endPoint: CGPoint(x: pic.maxX, y: pic.maxY)))
                let w = pic.insetBy(dx: pic.width * 0.12, dy: pic.height * 0.14)
                MacWindow060.draw(&ctx, w, k: w.width / 304)
                for i in 0..<5 {
                    ctx.fill(Path(roundedRect: CGRect(x: (12 + 76 * CGFloat(i)) * k, y: pic.maxY + 18 * k, width: 68 * k, height: 50 * k), cornerRadius: 10 * k, style: .continuous),
                             with: .color(Color(hex: 0x23262C)))
                }
                ctx.fill(Path(roundedRect: CGRect(x: 8 * k, y: pic.maxY + 84 * k, width: size.width - 16 * k, height: size.height - pic.maxY - 110 * k),
                              cornerRadius: 16 * k, style: .continuous), with: .color(Color(hex: 0x16181C)))
            }
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: The stills

    static func stills() -> [Still] {
        var out: [Still] = []
        func add(_ name: String, _ t: Double, _ note: String, vignette: Bool = true, _ v: some View) {
            out.append(Still(name: name, t: t, layers: FrameLayers(base: any(ZStack { Color.black; v }.canvas()), vignette: vignette), note: note))
        }

        // Devices.
        for (name, spec, centre, yaw) in [("devices-ipad-mini-H", DeviceSpec.miniH, CGPoint(x: 960, y: 540), 0.0),
                                          ("devices-ipad-mini-M45-right-4deg", DeviceSpec.miniM45, CGPoint(x: 1340, y: 560), -4.0),
                                          ("devices-ipad-mini-M-centre", DeviceSpec.miniM, CGPoint(x: 960, y: 600), 0.0)] {
            add(name, 10.0, "iPad mini \(Int(spec.interior.width))×\(Int(spec.interior.height)) interior, plain bezel",
                ZStack { Backdrop(glow: 0.06, glowCenter: centre); device(spec, center: centre, yaw: yaw) { PreviewStreamScreen060(size: spec.interior) } })
        }
        add("devices-iphone-H-masked", 33.0, "iPhone phoneH 406×880, status strip (54 pt) masked, no island",
            ZStack {
                Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1260, y: 520))
                SillLine(y: 1000, length: 900, centerX: 1260)
                device(.phoneH, center: CGPoint(x: 1260, y: 1000 - DeviceSpec.phoneH.outer.height / 2), yaw: -6) {
                    ZStack(alignment: .topLeading) {
                        PhoneStandIn(size: DeviceSpec.phoneH.interior)
                        Color.black.frame(width: DeviceSpec.phoneH.interior.width, height: Device060.phoneStatusStrip * DeviceSpec.phoneH.interior.width / 393)
                    }
                }
                words([("Larger Picture.", 128, .bold, Palette.text1, 128, 470, true), ("On iPhone, held upright.", 56, .medium, Palette.text1, 128, 560, true)])
            })
        add("devices-iphone-sizes", 33.0, "phoneH, phoneM, phoneS side by side",
            ZStack {
                Backdrop(glow: 0.05)
                ForEach(Array([(DeviceSpec.phoneH, 560.0), (DeviceSpec.phoneM, 1040.0), (DeviceSpec.phoneS, 1440.0)].enumerated()), id: \.offset) { _, e in
                    device(e.0, center: CGPoint(x: e.1, y: 540)) {
                        ZStack(alignment: .topLeading) {
                            PhoneStandIn(size: e.0.interior)
                            Color.black.frame(width: e.0.interior.width, height: Device060.phoneStatusStrip * e.0.interior.width / 393)
                        }
                    }
                }
            })

        // Keycaps (S04 ⌘C at 7.2; ⌘V for S05 if a timeline wants it: the approved S05 has none).
        let unit: CGFloat = 112
        let keysCV = [Keycap060.command, .letter("C")]
        let rowX: CGFloat = 128
        for (name, t) in [("keycaps-cmd-c-rest", 7.0), ("keycaps-cmd-c-down", 7.24), ("keycaps-cmd-c-up", 7.6)] {
            add(name, t, "S04: ⌘ down at 7.15, C at 7.20, both up at 7.45 (\(unit) px keys)",
                ZStack {
                    Backdrop(glow: 0.05, glowCenter: CGPoint(x: 1340, y: 560))
                    device(.miniM45, center: CGPoint(x: 1360, y: 560), yaw: -4) { miniScreen("A1-te-select", DeviceSpec.miniM45.interior) }
                    words([("Copy on your Mac.", 100, .bold, Palette.text1, rowX, 470, true)])
                    KeycapRow060(keys: keysCV, unit: unit, origin: CGPoint(x: rowX, y: 560), t: t,
                                 presses: [0: KeyPress060(down: 7.15, up: 7.45), 1: KeyPress060(down: 7.20, up: 7.45)])
                })
        }
        add("keycaps-cmd-v-down", 7.24, "⌘V, available (the approved S05 shows none)",
            ZStack {
                Backdrop(glow: 0.05)
                KeycapRow060(keys: [.command, .letter("V")], unit: unit, origin: CGPoint(x: 960 - KeycapRow060.width([.command, .letter("V")], unit: unit) / 2, y: 480),
                             t: 7.24, presses: [0: KeyPress060(down: 7.15, up: 7.45), 1: KeyPress060(down: 7.20, up: 7.45)])
            })
        add("keycaps-esc-lit", 39.3, "esc lit in the accent (S11, pressed at 39.2)",
            ZStack {
                Backdrop(glow: 0.05)
                KeycapRow060(keys: [.esc], unit: unit, origin: CGPoint(x: 960 - 0.625 * unit, y: 480), t: 39.3,
                             presses: [0: KeyPress060(down: 39.2, up: 39.5)], lights: [0: KeyPress060(down: 39.2, up: 39.5)])
            })

        // S06's arcs.
        let s06 = DeviceSpec.miniM
        let s06c = CGPoint(x: 960, y: 620)
        let arcsAt = SoundArcs060.origin(beside: s06, center: s06c)
        for (name, t, note) in [("sound-arcs-1440-beat", 14.43, "a beat: the inner arc lit"), ("sound-arcs-1450", 14.50, "the pulse at the outer arc"),
                                ("sound-arcs-1530-rest", 15.30, "between beats (30 %)"), ("sound-arcs-1768-folding", 17.68, "Mute at 17.6: folding, outer first"),
                                ("sound-arcs-1800-folded", 18.0, "muted: gone"), ("sound-arcs-1846-back", 18.46, "Mute off at 18.4: open again, on the beat")] {
            add(name, t, "S06 " + note,
                ZStack {
                    Backdrop(glow: 0.06, glowCenter: s06c)
                    device(s06, center: s06c) { miniScreen("B1-qt", s06.interior) }
                    SoundArcs060(origin: arcsAt, t: t)
                    words([("Sound from your Mac.", 112, .bold, Palette.text1, 960, 170, false)])
                })
        }

        // S07: the lock, in the iPad (right), the lock screen over the stream's picture.
        let s07 = DeviceSpec.miniM45
        let s07c = CGPoint(x: 1300, y: 580)
        let seq = LockSequence060()
        func lockedPad(_ t: Double, keyboard: Bool) -> some View {
            let size = s07.interior
            let k = size.width / Device060.miniPoints.width
            let pic = MacPicture060.inMini(s07)
            let kb = CGRect(x: 0, y: size.height * 0.60, width: size.width, height: size.height * 0.40)
            let rise = SoftKeyboard060.offset(t, height: kb.height, rise: seq.keyboardRise, lower: seq.keyboardLower)
            return ZStack(alignment: .topLeading) {
                miniScreen(t >= seq.lock && t < seq.unlock ? "L1-locked" : "L0-unlocked", size, locked: t >= seq.lock && t < seq.unlock + 0.1)
                Canvas { ctx, _ in
                    seq.drawPicture(&ctx, rect: pic, pt: k, t: t)
                    if keyboard { SoftKeyboard060.draw(&ctx, rect: kb.offsetBy(dx: 0, dy: rise), t: t, flash: seq.flash) }
                }
                .frame(width: size.width, height: size.height)
                if keyboard {
                    ForEach(Array(seq.dots(keyboard: kb).enumerated()), id: \.offset) { _, d in
                        TouchDot(spec: TouchDotSpec(at: d.time, point: CGPoint(x: d.point.x / k * 2, y: d.point.y / k * 2), interiorWidth: Device060.miniSource.width),
                                 t: t, clipScale: size.width / Device060.miniSource.width)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        for (name, t, note) in [("lock-s07-1950-window", 19.50, "before the lock: the window"), ("lock-s07-1972-dissolve", 19.72, "the dissolve (0.25 s from 19.6)"),
                                ("lock-s07-2200-locked", 22.0, "locked: the lock screen streams")] {
            add(name, t, "S07 " + note,
                ZStack {
                    Backdrop(glow: 0.06, glowCenter: s07c)
                    device(s07, center: s07c, yaw: -4) { lockedPad(t, keyboard: false) }
                    words([("Mac locked?", 100, .bold, Palette.text1, 128, 430, true), ("Sill shows its lock screen.", 56, .medium, Palette.text1, 128, 520, true)])
                })
        }
        // S08 in the iPad as it would be (the keyboard over the screen's lower 40 %: the field is under it).
        for (name, t) in [("lock-s08-ipad-2480-typing", 24.80), ("lock-s08-ipad-2532-unlocking", 25.32)] {
            add(name, t, "S08 inside the iPad: the keyboard covers the field (why the close-up floats it)",
                ZStack {
                    Backdrop(glow: 0.06, glowCenter: s07c)
                    device(s07, center: s07c, yaw: -4) { lockedPad(t, keyboard: true) }
                })
        }
        // S08 closer: the lock screen large, the keyboard as a panel rising from the frame's foot.
        func closeUp(_ t: Double) -> some View {
            let pic = CGRect(x: 960 - 1640 / 2, y: -1040 * 0.835 + 520 + 18, width: 1640, height: 1640 / MacPicture060.display.width * MacPicture060.display.height)
            let kb = CGRect(x: 960 - 1240 / 2, y: 690, width: 1240, height: 360)
            let rise = SoftKeyboard060.offset(t, height: kb.height + 60, rise: seq.keyboardRise, lower: seq.keyboardLower)
            let pt = pic.width / 1013                       // iPad points across the picture (the stream panel's)
            return ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.fill(Path(pic), with: .linearGradient(Gradient(colors: [Color(hex: 0x2B3550), Color(hex: 0x12151E)]),
                                                             startPoint: CGPoint(x: pic.minX, y: pic.minY), endPoint: CGPoint(x: pic.maxX, y: pic.maxY)))
                    MacWindow060.draw(&ctx, pic.insetBy(dx: pic.width * 0.2, dy: pic.height * 0.18), k: pic.width * 0.6 / 304)
                    seq.drawPicture(&ctx, rect: pic, pt: pt, t: t)
                    SoftKeyboard060.draw(&ctx, rect: kb.offsetBy(dx: 0, dy: rise), t: t, flash: seq.flash, floating: true)
                }
                .canvas()
                // TouchDot multiplies its point by clipScale: hand it the canvas point divided by it.
                let cs = 64 * pt / 128
                ForEach(Array(seq.dots(keyboard: kb).enumerated()), id: \.offset) { _, d in
                    TouchDot(spec: TouchDotSpec(at: d.time, point: CGPoint(x: d.point.x / cs, y: d.point.y / cs), interiorWidth: 1920), t: t, clipScale: cs)
                }
            }
            .canvas()
        }
        for (name, t, note) in [("lock-s08-2420-rising", 24.20, "the keyboard rising (24.0, 0.3 s)"), ("lock-s08-2462-typing", 24.62, "three taps in, three dots"),
                                ("lock-s08-2512-eight", 25.12, "the eighth tap: eight dots"), ("lock-s08-2522-return", 25.22, "Return: the field's spinner"),
                                ("lock-s08-2540-unlocking", 25.40, "the app's \u{201C}Unlocking\u{2026}\u{201D} (see the note in UnlockingCover060)"),
                                ("lock-s08-2575-back", 25.75, "the dissolve back to the window (25.6), the keyboard lowering")] {
            add(name, t, "S08 close: " + note, closeUp(t))
        }
        var noCover = seq
        noCover.appCover = false
        add("lock-s08-2540-no-cover", 25.40, "S08 with appCover false: macOS's own spinner, no app cover",
            ZStack {
                Canvas { ctx, _ in
                    let pic = CGRect(x: 960 - 1640 / 2, y: -1040 * 0.835 + 520 + 18, width: 1640, height: 1640 / MacPicture060.display.width * MacPicture060.display.height)
                    noCover.drawPicture(&ctx, rect: pic, pt: pic.width / 1013, t: 25.40)
                }.canvas()
            })

        // S15: the drawn Mac (left) whose window goes back to its own size on the beat (54.4, 0.3 s).
        for (name, t) in [("aa-mac-5420-sill-size", 54.2), ("aa-mac-5448-shrinking", 54.48), ("aa-mac-5480-own-frame", 54.8)] {
            add(name, t, "S15 left half: the window as Sill sized it → its own frame",
                ZStack {
                    Backdrop(glow: 0.05, glowCenter: CGPoint(x: 560, y: 560))
                    AaMac060(k: 0.82, center: CGPoint(x: 470, y: 600), t: t)
                    // The right half as the storyboard has it: the bar's Aa ruler at 1.25×, cut to Off on the beat.
                    device(.miniS, center: CGPoint(x: 1420, y: 600), yaw: -4) {
                        miniScreen(t < 54.4 ? "H1-scale125-open" : "H2-scaleoff-open", DeviceSpec.miniS.interior)
                    }
                    words([("Aa starts at Off.", 112, .bold, Palette.text1, 960, 170, false)])
                })
        }

        // S16: the hold ring on a thumbnail, close (1 pt = 2.6 px, as v3's S19 macro at 1.3).
        let pt16: CGFloat = 2.6
        func barClose(_ t: Double) -> some View {
            // With the footage: the bar of L0 (before the controls open at 56.9) and J1 (after), 1.3 px per still px,
            // the hold on the first thumbnail (Device060.miniFirstThumbnail).
            let k: CGFloat = 1.3, origin = CGPoint(x: 120, y: 260)
            if let img = footage(t < 56.9 ? "L0-unlocked" : "J1-windowmenu"), let bar = img.cropping(to: CGRect(x: 0, y: 0, width: 1340, height: 520)) {
                return any(ZStack(alignment: .topLeading) {
                    Image(decorative: bar, scale: 1).resizable().interpolation(.high)
                        .frame(width: 1340 * k, height: 520 * k).offset(x: origin.x, y: origin.y)
                        .mask(LinearGradient(colors: [.white, .white, .clear], startPoint: .top, endPoint: .bottom).frame(width: 1340 * k, height: 520 * k).offset(x: origin.x, y: origin.y))
                    HoldRing060(center: CGPoint(x: origin.x + Device060.miniFirstThumbnail.x * k, y: origin.y + Device060.miniFirstThumbnail.y * k),
                                diameter: 128 * k, t: t)
                }.canvas())
            }
            return any(ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let k = pt16
                    ctx.fill(Path(CGRect(x: 0, y: 300, width: 1920, height: 86 * k)), with: .color(Color(hex: 0x16181C)))
                    for i in 0..<4 {
                        let r = CGRect(x: (40 + 120 * CGFloat(i)) * k, y: 300 + 10 * k, width: 104 * k, height: 66 * k)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 10 * k, style: .continuous), with: .color(Color(hex: 0x26282D)))
                        ctx.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: 14 * k), cornerRadius: 6 * k, style: .continuous),
                                 with: .color(Color(hex: 0x34373D)))
                    }
                }.canvas()
                HoldRing060(center: CGPoint(x: (40 + 120 + 52) * pt16, y: 300 + 43 * pt16), diameter: 64 * pt16, t: t)
            }.canvas())
        }
        for (name, t, note) in [("hold-5640-down", 56.40, "the touch lands"), ("hold-5665-half", 56.65, "the ring half drawn (linear: 0.25 s)"),
                                ("hold-5688-done", 56.88, "a frame before done (56.9)"), ("hold-5698-pop", 56.98, "done: the ring's pop as the controls open")] {
            add(name, t, "S16 " + note, vignette: false, barClose(t))
        }

        // S18: the icon's iMac, the glint across its screen at 63.2.
        for (name, t, note) in [("intel-6250", 62.5, "S18 the iMac, pushing in"), ("intel-6330-glint", 63.30, "the glint entering"),
                                ("intel-6365-glint", 63.65, "the glint mid-screen"), ("intel-6400-glint", 64.0, "the glint leaving"),
                                ("intel-6550-end", 65.5, "the end of the push (+3 %)")] {
            add(name, t, note,
                ZStack {
                    Backdrop(glow: 0.06, glowCenter: CGPoint(x: 960, y: 620))
                    IntelIMac060(t: t)
                    words([("Sill for Mac now runs on Intel.", 100, .bold, Palette.text1, 960, 150, false)])
                })
        }
        add("intel-line-style-6365", 63.65, "the alternative: v3's line iMac with v3's glint round its screen",
            ZStack {
                Backdrop(glow: 0.06, glowCenter: CGPoint(x: 960, y: 620))
                DrawnIMac060(style: .line, k: 1.18, center: CGPoint(x: 960, y: 620), edgeGlint: (63.2, 0.9), t: 63.65)
            })

        // S11: an iPad over the keyboard slab, esc lit at 39.2.
        for (name, t) in [("slab-s11-3900-rest", 39.0), ("slab-s11-3930-esc", 39.30)] {
            let w: CGFloat = 1180
            let h = KeyboardSlab060.height(width: w)
            add(name, t, "S11: the slab (\(Int(w)) px, laid back 58°), esc pressed 39.2–39.5",
                ZStack {
                    Backdrop(glow: 0.06, glowCenter: CGPoint(x: 960, y: 560))
                    // Drawn centred on the stage so the tilt pivots about its own middle, then set down in front.
                    KeyboardSlab060(width: w, origin: CGPoint(x: 960 - w / 2, y: 540 - h / 2), t: t, esc: KeyPress060(down: 39.2, up: 39.5))
                        .modifier(Tilt(yaw: 0, pitch: 58))
                        .offset(y: 330)
                    device(.miniM45, center: CGPoint(x: 960, y: 400)) { miniScreen("E1-te-typed", DeviceSpec.miniM45.interior) }
                })
            add(name + "-flat", t, "S11: the slab flat, its esc",
                ZStack {
                    Backdrop(glow: 0.05)
                    KeyboardSlab060(width: 1600, origin: CGPoint(x: 160, y: 540 - KeyboardSlab060.height(width: 1600) / 2), t: t, esc: KeyPress060(down: 39.2, up: 39.5))
                })
        }

        // S19–S20: the cutaway, beat by beat (v4.1's film times: the cutaway from 116.8, the squash at 126.8; times as
        // offsets from its start, as Fixes060's).
        let H = Fixes060.tap, C = Fixes060.start
        let beats: [(Double, String)] = [
            (C + 0.20, "1 the title snapping"), (C + 1.60, "1 the title alone"), (C + 3.40, "2 the scroll under way"), (C + 5.00, "2 the first line on the middle"),
            (C + 6.00, "2 the Mac's group"), (C + 7.20, "2 the Mac's group, the security header"), (C + 8.40, "2 the security group; the bug below"),
            (Fixes060.brakeStart, "3 the brake from 300 px/s"), (H - 0.5, "3 the bug riding in"), (H - 0.15, "3 the bug, walking"),
            (H - 0.08, "4 the touch dot appears"), (H - 0.03, "5 stretched tall"), (H, "6 the squash, frame \(Int((H * 60).rounded())): the flash, the specks, the dot pressed"),
            (H + 2.0 / 60, "6 the specks smeared, the puddle spreading"), (H + 0.1, "7 the puddle, buzzing; the lines back to 45 %"),
            (H + 0.2, "7 the puddle settling, the specks at rest"), (H + 0.3, "7 settled"), (H + 0.42, "8 turning accent, thinning"),
            (H + 0.55, "8 the stretch"), (H + 0.75, "8 the stretch, the glow"), (Fixes060.lineAlone, "8 the line at 520 px"),
            (H + 1.1, "9 black and the sill line alone"),
        ]
        for (t, note) in beats {
            out.append(Still(name: String(format: "fixes-%05.0f", t * 100), t: t, layers: Fixes060.frame(t), note: "S19–S20 " + note))
        }

        // The bug, close: its gait and its squash at 3×.
        out.append(Still(name: "bug-sheet", t: C + 8.0, layers: FrameLayers(base: any(BugSheet060()), grain: false, vignette: false), note: "the bug at 3×"))
        return out
    }

    // MARK: The command

    static func run(args: [String]) throws {
        if args.first == "--report" { report(); return }
        if args.first == "--motion" { try motion(); return }
        if args.first == "--splat" { try splat(dir: URL(fileURLWithPath: args.count > 1 ? args[1] : ".", isDirectory: true)); return }
        guard let dirArg = args.first else { print("usage: ReelRenderer assets <dir> [name-prefix …] | assets --report"); return }
        let dir = URL(fileURLWithPath: dirArg, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let comp = Compositor()
        ShadowCache.shared.ci = comp.ci
        IconShadows.shared.build(ci: comp.ci)
        let filters = Array(args.dropFirst())
        var made: [(String, String, CGImage)] = []
        for s in stills() where filters.isEmpty || filters.contains(where: { s.name.hasPrefix($0) }) {
            let started = Date()
            let img = comp.still(s.layers, frame: Int((s.t * 60).rounded()))
            writePNG(img, to: dir.appendingPathComponent(s.name + ".png"))
            made.append((s.name, String(format: "%.3f s · ", s.t) + s.note, img))
            print(String(format: "%@.png  t %.3f  %.0f ms  %@", s.name, s.t, Date().timeIntervalSince(started) * 1000, s.note))
        }
        if filters.isEmpty, let sheet = indexSheet(made) { writePNG(sheet, to: dir.appendingPathComponent("index.png")); print("index.png") }
    }

    /// v4.1, for the review of Noah's third note: `splat.png`, the film's frame 3 frames after the hit, whole; and
    /// `splat-strip.png`, 12 consecutive frames from 2 before the hit (frame 7606) to 9 after (7617), each cropped about the
    /// bug (x 580–1340, y 560–700) and shown at 1.5×, labelled. The frames are the film's own (s060_19, finished as the
    /// film's: grain, dither).
    static func splat(dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let comp = Compositor()
        ShadowCache.shared.ci = comp.ci
        IconShadows.shared.build(ci: comp.ci)
        let env = Env(clips: ClipLibrary(ci: comp.ci), portrait: nil, v3: nil)
        let H = Int((Fixes060.tap * 60).rounded())
        func frame(_ f: Int) throws -> CGImage { comp.still(try s060_19(Double(f) / 60, env), frame: f) }
        writePNG(try frame(H + 3), to: dir.appendingPathComponent("splat.png"))
        print("splat.png  frame \(H + 3) (\(String(format: "%.4f", Double(H + 3) / 60)) s)")
        let crop = CGRect(x: 580, y: 560, width: 760, height: 140), k: CGFloat = 1.5
        let cw = Int(crop.width * k), ch = Int(crop.height * k), label = 34, pad = 10, cols = 3
        let frames = Array((H - 2)...(H + 9))
        let rows = (frames.count + cols - 1) / cols
        let W = cols * cw + (cols + 1) * pad, Ht = rows * (ch + label) + (rows + 1) * pad
        guard let ctx = CGContext(data: nil, width: W, height: Ht, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: Ht))
        ctx.interpolationQuality = .high
        for (i, f) in frames.enumerated() {
            let img = try frame(f)
            guard let part = img.cropping(to: crop) else { continue }
            let c = i % cols, r = i / cols
            let x = pad + c * (cw + pad), y = Ht - pad - (r + 1) * (ch + label + pad) + pad
            ctx.draw(part, in: CGRect(x: x, y: y, width: cw, height: ch))
            let u = Double(f) / 60 - Fixes060.tap
            let text = f == H ? "frame \(f) · the beat (the squash, the flash)" : String(format: "frame %d · %@%.3f s", f, u < 0 ? "−" : "+", abs(u))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: f == H ? .semibold : .regular),
                                                        .foregroundColor: NSColor(white: f == H ? 0.95 : 0.7, alpha: 1)]
            ctx.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(y + ch + 9))
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs)), ctx)
            print("  strip: frame \(f)")
        }
        if let strip = ctx.makeImage() { writePNG(strip, to: dir.appendingPathComponent("splat-strip.png")); print("splat-strip.png") }
    }

    /// The cutaway's numbers, for the shot list and the score: the scroll, where the bug is, the ticks, the splat.
    static func report() {
        let F = Fixes060.self
        let H = F.tap
        print("Fixes060 (S19–S20, \(F.start)–\(F.end)): column x \(F.columnX), title baseline \(F.titleBaseline), line pitch \(F.linePitch), header→line \(F.headerToLine), group step \(F.groupStep)")
        print(String(format: "  first line %.1f px under the title's baseline; bug base %.1f px; last line → bug base %.1f px",
                     F.firstLine, F.bugBase, F.bugBase - (F.placed.last?.y ?? 0)))
        func v(_ t: Double) -> Double { (F.scroll(t + 0.0005) - F.scroll(t - 0.0005)) / 0.001 }
        for t in [F.scrollStart, F.accelEnd, F.start + 6.0, F.brakeStart, H - 0.1, H, H + 0.15, F.settleEnd] {
            let b = F.bugState(t)
            print(String(format: "  t %.3f  scroll %8.2f px  bug base y %7.2f  speed %6.1f px/s", t, F.scroll(t), b.base.y, v(t)))
        }
        print(String(format: "  slowing from %.4f s (%.4f s, appleOut from %.0f px/s); %.1f px/s 0.1 s before the tap, %.2f at it; overshoot %.2f px, back by %.3f s",
                     F.brakeStart, F.brakeDuration, F.speed, v(H - 0.1), v(H - 0.0006), F.scroll(H) - F.scroll(F.settleEnd), F.settleEnd))
        var worstStep = 0.0
        for f in Int((F.brakeStart - 0.5) * 60)...Int(F.end * 60) {
            let a = F.scroll(Double(f - 1) / 60), b = F.scroll(Double(f) / 60), c = F.scroll(Double(f + 1) / 60)
            worstStep = max(worstStep, abs((c - b) - (b - a)))
        }
        print(String(format: "  the column's largest change of step from one frame to the next, from the slowing to the end: %.3f px", worstStep))
        let fH = Int((H * 60).rounded())
        let bH = F.bugState(Double(fH) / 60)
        print(String(format: "  frame %d (the beat): the squash %.0f %%, the puddle %.1f × %.1f px; flare %.2f; frame %d flare %.2f",
                     fH, 100 * Double(bH.squash), Double(bH.puddleWidth), Double(bH.puddleHeight), bH.flare, fH + 1, F.bugState(Double(fH + 1) / 60).flare))
        for u in [0.0, 0.06, 0.12, 0.18, 0.24, 0.30, 0.35] {
            let b = F.bugState(H + u)
            print(String(format: "  puddle at +%.2f s: %.1f × %.2f px, edge ±%.2f px", u, Double(b.puddleWidth), Double(b.puddleHeight), Double(b.wobble)))
        }
        let reach = Splat060.specks.map { $0.reach }
        print(String(format: "  specks: %d (%d accent), reach %.0f–%.0f px, radius %.1f–%.1f px; launched %.4f; at rest (99 %%) by +%.2f s",
                     Splat060.specks.count, Splat060.specks.filter(\.accent).count, reach.min() ?? 0, reach.max() ?? 0,
                     Double(Splat060.specks.map(\.radius).min() ?? 0), Double(Splat060.specks.map(\.radius).max() ?? 0), Splat060.launch,
                     Splat060.launch + Splat060.tau * log(100) - H))
        print(String(format: "  the line: %.1f px at %.3f, %.1f px a frame later, %.1f px at %.4f; resting at y %.1f (the lockup's: %.0f px at y %.0f)",
                     F.bugState(F.morph + F.morphDuration).length, F.morph + F.morphDuration, F.bugState(F.morph + F.morphDuration + 1.0 / 60).length,
                     F.bugState(F.lineAlone).length, F.lineAlone, F.bugState(F.end).base.y - 1, Open060.sillLength, Open060.sillY))
        let ticks = F.crossings
        print("  ticks (each line crossing y 540, its x-height's middle): " + ticks.map { String(format: "%.3f", $0) }.joined(separator: " "))
        print("  on the eighths' grid from the scroll's start (steps): " + ticks.map { String(format: "%.3f", ($0 - F.scrollStart) * 5) }.joined(separator: " "))
        print(String(format: "  in view (y 0–1080) per line at %.0f px/s: %.2f s", F.speed, 1080 / F.speed))
    }

    /// The cutaway's type in motion, measured: frames rendered without grain, dither or vignette at 60 fps through
    /// the cruise (the cutaway's 6.0–6.5 s: 122.8–123.3), the brightness-weighted centroid of one line followed frame to frame. On outlines it
    /// moves exactly 5 px every frame (300 px/s).
    static func motion() throws {
        let comp = Compositor()
        comp.dither = false
        ShadowCache.shared.ci = comp.ci
        var last: Double?
        var worst = 0.0
        let F = Fixes060.self
        guard let line = F.placed.first(where: { if case .line = $0.item { return true }; return false }) else { return }
        let f0 = Int(((Fixes060.start + 6.0) * 60).rounded())
        for f in f0...(f0 + 30) {
            let t = Double(f) / 60
            var l = Fixes060.frame(t)
            l.grain = false; l.vignette = false
            let img = comp.still(l, frame: f)
            let expected = Double(F.screenY(line.y, t))
            // Rows expected − 40 … expected + 14 (the line's ascenders to its descenders), columns 480–1500.
            let y0 = Int(expected) - 40, y1 = Int(expected) + 14
            guard y0 > 0, y1 < Stage.height, let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { continue }
            let bpr = img.bytesPerRow
            var sum = 0.0, wy = 0.0
            for y in y0..<y1 { for x in 480..<1500 { let v = Double(p[y * bpr + x * 4 + 1]); sum += v; wy += v * (Double(y) + 0.5) } }
            let cy = wy / max(sum, 1)
            if let last {
                let d = last - cy
                worst = max(worst, abs(d - F.speed / 60))
                print(String(format: "  frame %d  t %.4f  centroid %.3f  moved %.3f px", f, t, cy, d))
            }
            last = cy
        }
        print(String(format: "worst departure from %.1f px a frame: %.3f px", F.speed / 60, worst))
    }

    /// Every still at 384×216 with its name and note under it, six across.
    static func indexSheet(_ items: [(String, String, CGImage)]) -> CGImage? {
        let cols = 6, tw = 384, th = 216, lh = 44, pad = 12
        let rows = (items.count + cols - 1) / cols
        let w = cols * (tw + pad) + pad, h = rows * (th + lh + pad) + pad
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.09, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        for (i, item) in items.enumerated() {
            let c = i % cols, r = i / cols
            let x = pad + c * (tw + pad), y = h - pad - (r + 1) * (th + lh + pad) + pad + lh
            ctx.draw(item.2, in: CGRect(x: x, y: y, width: tw, height: th))
            for (j, (text, size, grey)) in [(item.0, 13.0, 0.95), (item.1, 10.0, 0.62)].enumerated() {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: j == 0 ? .semibold : .regular),
                                                            .foregroundColor: NSColor(white: grey, alpha: 1)]
                let line = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs)), Double(tw), .end,
                                                     CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attrs)))
                ctx.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(y) - 16 - CGFloat(j) * 16)
                if let line { CTLineDraw(line, ctx) }
            }
        }
        return ctx.makeImage()
    }
}

/// The bug at 3× on black: its gait over one 6 Hz cycle, the anticipation, the squash and the morph.
struct BugSheet060: View {
    var body: some View {
        Canvas { ctx, _ in
            let F = Fixes060.self
            var rows: [(String, [(Double, Fixes060.BugState)])] = []
            let gait = (0..<6).map { i -> (Double, Fixes060.BugState) in
                let t = F.start + 8.0 + Double(i) / 36
                var s = F.bugState(F.start + 8.0)
                s.gaitTime = t
                return (t, s)
            }
            rows.append(("gait, a sixth of a cycle apart (6 Hz)", gait))
            let H = F.tap
            let times = [H - 0.08, H - 0.03, H, H + 0.03, H + 0.12, H + 0.30]
            rows.append(("the tap −0.08 · −0.03 · the beat · +0.03 · +0.12 · +0.30 s", times.map { ($0, F.bugState($0)) }))
            for (r, row) in rows.enumerated() {
                let y = CGFloat(430 + 470 * r)
                Outline060.draw(row.0, in: &ctx, size: 26, weight: .regular, x: 80, baseline: y - 360, leading: true, color: Color(hex: Palette.text2))
                for (i, item) in row.1.enumerated() {
                    var s = item.1
                    s.base = .zero
                    s.jitter = (0, 0, 0)
                    var c = ctx
                    c.translateBy(x: CGFloat(200 + 300 * i), y: y)
                    c.scaleBy(x: 3, y: 3)
                    Bug060.draw(&c, s, t: item.0)
                }
            }
        }
        .canvas()
    }
}

@MainActor func assetPreviews060(args: [String]) throws { try Preview060.run(args: args) }
