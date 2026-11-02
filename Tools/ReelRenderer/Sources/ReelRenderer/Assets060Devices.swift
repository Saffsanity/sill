// Assets060Devices.swift — the 0.6.0 reel's drawn devices (storyboard §6, step 2): the iPad mini and the
// iPhone in v3's drawn-frame style, the keyboard slab of S11 and the keycaps of S04, S05 and S11.
//
// Every device here is v3's `DeviceView` (Device.swift): a rounded body in the device black, the 1.5 px rim
// gradient, the glass gloss over the top-left third, its shadow, and a plain bezel: no camera, lens, notch or
// island (Noah, 2026-09-26). Only the shapes are new: the iPad mini's screen is 1133×744 pt (its recordings
// 2266×1488 px), the iPhone 15 Pro's 393×852 pt (1179×2556 px). Never Apple's artwork.
import SwiftUI

enum Device060 {
    /// The iPad mini's screen, landscape, in points, and its screen recordings' (and simulator screenshots') pixels.
    static let miniPoints = CGSize(width: 1133, height: 744)
    static let miniSource = CGSize(width: 2266, height: 1488)
    /// The iPhone 15 Pro's screen, upright, in points and in its screen recordings' pixels.
    static let phonePoints = CGSize(width: 393, height: 852)
    static let phoneSource = CGSize(width: 1179, height: 2556)
    /// The first thumbnail's centre in an iPad mini still (2266×1488 px): its selection ring spans x 206–433,
    /// y 10–161 (measured on the footage stand-ins L0 and J1). S16's hold lands there.
    static let miniFirstThumbnail = CGPoint(x: 319.5, y: 85.5)
    /// The iPhone's status strip, the status bar's 54 pt, which `PhoneScreen060` masks black: no island is drawn,
    /// and no clock, carrier or battery from a recording shows (storyboard S10).
    static let phoneStatusStrip: CGFloat = 54

    /// Screen px per recording px for a device spec showing a recording of `source` px (v3's `clipScale` assumes
    /// the iPad Pro 13" simulator's 2000/1420 px interiors; these devices show their own).
    static func scale(_ spec: DeviceSpec, source: CGSize) -> CGFloat { spec.interior.width / source.width }
    /// A touch dot for a recording of `source` px (64 pt on the device, as every v3 dot): `point` in its pixels.
    static func dot(at time: Double, _ point: CGPoint, source: CGSize = miniSource, hold: (start: Double, end: Double)? = nil) -> TouchDotSpec {
        TouchDotSpec(at: time, point: point, hold: hold, interiorWidth: source.width)
    }
}

extension DeviceSpec {
    // The iPad mini, landscape (1133×744 pt): interior widths as v3's H, M45 and S, plus L and M between them,
    // heights at 744/1133 rounded; v3's bezels and radii at those widths (outer = inner + bezel, as v3's).
    static let miniH = DeviceSpec(interior: CGSize(width: 1280, height: 841), bezel: 38, innerRadius: 30, outerRadius: 68)
    static let miniL = DeviceSpec(interior: CGSize(width: 1100, height: 722), bezel: 33, innerRadius: 26, outerRadius: 59)
    static let miniM = DeviceSpec(interior: CGSize(width: 1000, height: 657), bezel: 30, innerRadius: 24, outerRadius: 54)
    static let miniM45 = DeviceSpec(interior: CGSize(width: 900, height: 591), bezel: 30, innerRadius: 24, outerRadius: 54)
    static let miniS = DeviceSpec(interior: CGSize(width: 600, height: 394), bezel: 18, innerRadius: 14, outerRadius: 32)
    /// The iPad mini upright: any of the above turned a quarter (interior w ↔ h), bezels and radii unchanged.
    var turnedUpright: DeviceSpec {
        DeviceSpec(interior: CGSize(width: interior.height, height: interior.width), bezel: bezel,
                   innerRadius: innerRadius, outerRadius: outerRadius, portrait: true)
    }

    // The iPhone 15 Pro upright (393×852 pt): the screen's corners at 55 pt of 393 (14 %), a thin bezel at 4 % of
    // the width, as v3 draws an iPad's at 3 %. phoneH stands 952 px tall outside, phoneM 852, phoneS 640.
    static let phoneH = DeviceSpec(interior: CGSize(width: 406, height: 880), bezel: 16, innerRadius: 57, outerRadius: 73, portrait: true)
    static let phoneM = DeviceSpec(interior: CGSize(width: 360, height: 780), bezel: 14, innerRadius: 50, outerRadius: 64, portrait: true)
    static let phoneS = DeviceSpec(interior: CGSize(width: 271, height: 588), bezel: 11, innerRadius: 38, outerRadius: 49, portrait: true)
}

// MARK: - The iPhone's screen: a recording with its status strip masked

/// The iPhone's interior: `image` (a recording of 1179×2556 px, or any picture) fills it, its status strip is
/// black, and the touch dots are drawn in the recording's pixels. Hand it to `DeviceView`/`PlacedDevice` as the
/// content of a `phoneH`/`phoneM`/`phoneS` spec.
struct PhoneScreen060: View {
    let spec: DeviceSpec
    var image: CGImage? = nil
    var dots: [TouchDotSpec] = []
    var t: Double = 0
    /// The masked strip in the screen's points (54: the status bar; 0: nothing masked).
    var strip: CGFloat = Device060.phoneStatusStrip
    var body: some View {
        let size = spec.interior
        let k = size.width / Device060.phonePoints.width
        ZStack(alignment: .topLeading) {
            ClipScreen(image: image, size: size, dots: dots, t: t)
            if strip > 0 { Color.black.frame(width: size.width, height: strip * k) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Keycaps (S04 ⌘C, S05 ⌘V, S11 esc)

struct Keycap060: Hashable {
    var legend: String
    /// Width in key units (1u is the key's height).
    var units: CGFloat = 1
    static let command = Keycap060(legend: "\u{2318}", units: 1.25)
    static let esc = Keycap060(legend: "esc", units: 1.25)
    static func letter(_ s: String) -> Keycap060 { Keycap060(legend: s) }
    /// The legend's size as a fraction of the unit: a letter 0.42, ⌘ 0.46, a word ("esc") 0.27.
    var legendSize: CGFloat { legend == "\u{2318}" ? 0.46 : (legend.count > 1 ? 0.27 : 0.42) }
}

/// A key's press (down, then up) or its light, in reel time.
struct KeyPress060 {
    var down: Double
    var up: Double
    /// How far down: 0 at rest, 1 fully pressed (0.07 s appleOut down, 0.12 s appleOut up).
    func travel(_ t: Double) -> Double {
        if t < down { return 0 }
        if t < up { return ease(t, down, 0.07, .appleOut) }
        return ease(t, down, 0.07, .appleOut) * (1 - ease(t, up, 0.12, .appleOut))
    }
    /// The accent light: on with the press (0.06 s), off over 0.30 s from the release.
    func light(_ t: Double) -> Double {
        if t < down { return 0 }
        if t < up { return ease(t, down, 0.06, .appleOut) }
        return 1 - CubicBezier.inOut(ramp(t, up, up + 0.30))
    }
}

/// Large drawn keycaps in a row, drawn at their size on the canvas (so a push stays sharp): a dark face with a
/// soft top-lit gradient, v3's rim gradient, the legend in white. A press sinks the key 0.06u and darkens it; a
/// light fills it with the accent, its legend in the device black, and an accent glow round it.
struct KeycapRow060: View {
    var keys: [Keycap060]
    /// Px of 1u (a key's height).
    var unit: CGFloat
    /// The row's top-left on the canvas, keys at rest.
    var origin: CGPoint
    var t: Double
    var presses: [Int: KeyPress060] = [:]
    var lights: [Int: KeyPress060] = [:]
    /// The gap between keys, in units.
    var gap: CGFloat = 0.16

    static func width(_ keys: [Keycap060], unit: CGFloat, gap: CGFloat = 0.16) -> CGFloat {
        keys.reduce(0) { $0 + $1.units * unit } + CGFloat(max(0, keys.count - 1)) * gap * unit
    }

    var body: some View {
        Canvas { ctx, _ in
            var x = origin.x
            for (i, key) in keys.enumerated() {
                let w = key.units * unit
                let rect = CGRect(x: x, y: origin.y, width: w, height: unit)
                Keycap060Painter.draw(&ctx, key: key, rect: rect, unit: unit,
                                      travel: presses[i]?.travel(t) ?? 0, light: lights[i]?.light(t) ?? 0)
                x += w + gap * unit
            }
        }
        .canvas()
    }
}

enum Keycap060Painter {
    /// One keycap at rest in `rect`, pressed `travel` (0…1) and lit `light` (0…1). `plain`: the slab's flat key.
    static func draw(_ ctx: inout GraphicsContext, key: Keycap060, rect r0: CGRect, unit: CGFloat,
                     travel: Double, light: Double, plain: Bool = false, legendColor: UInt32 = Palette.text1, legendAlpha: Double = 0.95) {
        let p = CGFloat(travel), l = light
        let r = r0.offsetBy(dx: 0, dy: (plain ? 0.03 : 0.06) * unit * p)
        let radius = (plain ? 0.14 : 0.17) * unit
        let shape = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        if l > 0.002 {
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: 0.22 * unit))
                g.fill(Path(roundedRect: r.insetBy(dx: -0.06 * unit, dy: -0.06 * unit), cornerRadius: radius * 1.3, style: .continuous),
                       with: .color(Color(hex: Palette.accent, alpha: 0.45 * l)))
            }
        }
        // The key's side: the face's shape 0.07u lower, darker, at rest; a press sinks the face over it.
        if !plain {
            let side = Path(roundedRect: r0.offsetBy(dx: 0, dy: 0.07 * unit), cornerRadius: radius, style: .continuous)
            ctx.fill(side, with: .color(Color(hex: Keycap060Painter.lerpColor(0x0B0C0F, 0x31406A, l))))
            ctx.stroke(Path(roundedRect: r0.offsetBy(dx: 0, dy: 0.07 * unit).insetBy(dx: 0.75, dy: 0.75), cornerRadius: max(0, radius - 0.75), style: .continuous),
                       with: .color(Color(hex: Palette.rimDark)), lineWidth: 1.5)
        }
        // The face: top-lit dark grey, darker as it sinks; the accent blended in by the light.
        let dim = 1 - 0.22 * Double(p)
        func grey(_ v: Double) -> Color { Color(.sRGB, red: v * dim, green: v * dim, blue: v * dim * 1.04) }
        let top = plain ? 0.085 : 0.170, bottom = plain ? 0.060 : 0.108
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [grey(top), grey(bottom)]),
                                              startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        if l > 0.002 {
            var lit = ctx
            lit.opacity = l
            lit.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0xB9CBFF), Color(hex: 0x8DA9F5)]),
                                                  startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        // A hairline of light along the top inside edge.
        var hi = ctx
        hi.clip(to: shape)
        hi.stroke(Path { q in q.move(to: CGPoint(x: r.minX + radius, y: r.minY + 1)); q.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY + 1)) },
                  with: .color(.white.opacity((plain ? 0.05 : 0.10) * (1 - 0.5 * Double(p)))), lineWidth: 1)
        // v3's rim.
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), cornerRadius: max(0, radius - 0.75), style: .continuous),
                   with: .linearGradient(Gradient(colors: [Color(hex: Palette.rimLight, alpha: plain ? 0.55 : 1 - 0.3 * Double(p)),
                                                           Color(hex: Palette.rimDark)]),
                                         startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)),
                   lineWidth: 1.5)
        // The legend.
        guard !key.legend.isEmpty else { return }
        let size = key.legendSize * unit
        let weight: NSFont.Weight = key.legend.count > 1 ? .medium : .regular
        let laid = Outline060.line(key.legend, size: size, weight: weight)
        let bounds = laid.path.boundingRect
        // Centre the glyphs' own box (a symbol's ink, not its advance) in the face.
        let origin = CGPoint(x: r.midX - bounds.midX, y: r.midY - bounds.midY)
        let c = lerpColor(legendColor, Palette.deviceBody, l)
        Outline060.fill(laid, in: &ctx, at: origin, color: Color(hex: c, alpha: legendAlpha + (1 - legendAlpha) * l))
    }

    static func lerpColor(_ a: UInt32, _ b: UInt32, _ p: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func mix(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) + (ch(b, s) - ch(a, s)) * clamp01(p)).rounded()) << s }
        return mix(16) | mix(8) | mix(0)
    }
}

// MARK: - S11's keyboard slab

/// "A plain slab of keys, no logo" (S11): a Mac-layout keyboard in v3's device style, seen from above, keys
/// without legends but esc's ("esc", so the key that lights reads). `esc` presses and lights it in the accent.
/// Drawn flat at its size on the canvas; tilt it with v3's `Tilt` (a pitch of about +58° lays it back, its far
/// edge narrower) to stand an iPad over it, drawn centred on the stage so the tilt pivots about its own middle
/// (see `Assets060Preview`'s S11 composition).
struct KeyboardSlab060: View {
    var width: CGFloat
    /// The slab's top-left on the canvas.
    var origin: CGPoint
    var t: Double
    var esc: KeyPress060? = nil
    /// Other keys pressed (the 0.6.0 timeline's typing and ⌘S): a key's row and index in `rows`, and when it goes down
    /// (0.07 s down, then up).
    var pressed: [(row: Int, key: Int, at: Double)] = []

    /// The rows, each key's width in units of the key pitch (every row 14.5u). Row 0 is the function row, 0.6u
    /// tall; the last row ends in the arrows: ← and → half height, ↑ over ↓ in one key's place.
    static let rows: [[CGFloat]] = [
        [1.5] + Array(repeating: 1, count: 12) + [1],
        Array(repeating: 1, count: 13) + [1.5],
        [1.5] + Array(repeating: 1, count: 13),
        [1.75] + Array(repeating: 1, count: 11) + [1.75],
        [2.25] + Array(repeating: 1, count: 10) + [2.25],
        [1, 1, 1, 1.25, 5, 1.25, 1, 1, 1, 1],          // fn ctrl opt cmd space cmd opt ← ↑↓ →
    ]
    static func margin(_ w: CGFloat) -> CGFloat { 0.032 * w }
    static func pitch(_ w: CGFloat) -> CGFloat { (w - 2 * margin(w)) / 14.5 }
    static func height(width w: CGFloat) -> CGFloat { 2 * margin(w) + 5.6 * pitch(w) }
    /// The esc key's rect on the canvas (for a touch, a glow or a callout).
    static func escRect(width w: CGFloat, origin: CGPoint) -> CGRect {
        let m = margin(w), u = pitch(w), g = 0.12 * u
        return CGRect(x: origin.x + m + g / 2, y: origin.y + m + g / 2, width: 1.5 * u - g, height: 0.6 * u - g)
    }

    var body: some View {
        Canvas { ctx, _ in
            let w = width, h = KeyboardSlab060.height(width: w)
            let m = KeyboardSlab060.margin(w), u = KeyboardSlab060.pitch(w), g = 0.12 * u
            let slab = CGRect(x: origin.x, y: origin.y, width: w, height: h)
            let shape = Path(roundedRect: slab, cornerRadius: 0.028 * w, style: .continuous)
            ctx.fill(shape, with: .color(Color(hex: Palette.deviceBody)))
            var gloss = ctx
            gloss.clip(to: shape)
            gloss.fill(Path(slab), with: .linearGradient(Gradient(colors: [.white.opacity(0.06), .white.opacity(0)]),
                                                         startPoint: CGPoint(x: slab.minX, y: slab.minY),
                                                         endPoint: CGPoint(x: slab.minX + slab.width / 3, y: slab.minY + slab.height / 3)))
            var y = origin.y + m
            for (ri, row) in KeyboardSlab060.rows.enumerated() {
                let rowH: CGFloat = ri == 0 ? 0.6 * u : u
                var x = origin.x + m
                for (ki, units) in row.enumerated() {
                    let kw = units * u
                    let isEsc = ri == 0 && ki == 0
                    let arrows = ri == 5 && ki >= 7
                    if arrows {
                        // ← and → the lower half; ↑ over ↓ in the middle key's place, half a gap between them.
                        let half = (rowH - 1.5 * g) / 2
                        let upper = CGRect(x: x + g / 2, y: y + g / 2, width: kw - g, height: half)
                        let lower = upper.offsetBy(dx: 0, dy: half + g / 2)
                        for rect in ki == 8 ? [upper, lower] : [lower] {
                            Keycap060Painter.draw(&ctx, key: Keycap060(legend: ""), rect: rect, unit: u, travel: 0, light: 0, plain: true)
                        }
                    } else {
                        let rect = CGRect(x: x + g / 2, y: y + g / 2, width: kw - g, height: rowH - g)
                        var travel = isEsc ? esc?.travel(t) ?? 0 : 0
                        for p in pressed where p.row == ri && p.key == ki { travel = max(travel, KeyPress060(down: p.at, up: p.at + 0.07).travel(t)) }
                        Keycap060Painter.draw(&ctx, key: Keycap060(legend: isEsc ? "esc" : ""), rect: rect, unit: u,
                                              travel: travel, light: isEsc ? esc?.light(t) ?? 0 : 0,
                                              plain: true, legendColor: Palette.text2, legendAlpha: 0.8)
                    }
                    x += kw
                }
                y += rowH
            }
            ctx.stroke(Path(roundedRect: slab.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 0.028 * w - 0.75, style: .continuous),
                       with: .linearGradient(Gradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)]),
                                             startPoint: CGPoint(x: slab.minX, y: slab.minY), endPoint: CGPoint(x: slab.maxX, y: slab.maxY)),
                       lineWidth: 1.5)
        }
        .canvas()
    }
}

// MARK: - A stand-in stream screen, for the asset previews only

/// PREVIEW ONLY, never in a delivered shot: a rough drawing of Sill's landscape stream screen (the bar, a few
/// thumbnails, the stream panel and a Mac picture with one light window) so the frames and overlays can be
/// judged in place. The film's screens are the harness stills and the takes.
struct PreviewStreamScreen060: View {
    let size: CGSize
    /// A Mac picture (where the stills have theirs, `MacPicture060.inMiniSource`) with one light window.
    var showWindow = true
    /// The bar without thumbnails, as a locked Mac's.
    var locked = false
    var body: some View {
        Canvas { ctx, _ in
            let k = size.width / Device060.miniPoints.width
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x1F2126)))
            let bar = CGRect(x: 0, y: 0, width: size.width, height: 86 * k)
            ctx.fill(Path(bar), with: .color(Color(hex: 0x16181C)))
            func button(_ x: CGFloat, lit: Bool = false) {
                ctx.fill(Path(roundedRect: CGRect(x: x * k, y: 10 * k, width: 66 * k, height: 66 * k), cornerRadius: 12 * k, style: .continuous),
                         with: .color(Color(hex: lit ? 0x2C3550 : 0x23262C)))
            }
            button(22)
            if !locked {
                for i in 0..<4 {
                    let r = CGRect(x: (110 + 120 * CGFloat(i)) * k, y: 10 * k, width: 104 * k, height: 66 * k)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 10 * k, style: .continuous), with: .color(Color(hex: 0x26282D)))
                    ctx.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: 14 * k), cornerRadius: 6 * k, style: .continuous),
                             with: .color(Color(hex: 0x34373D)))
                    if i == 0 {
                        ctx.stroke(Path(roundedRect: r.insetBy(dx: -3 * k, dy: -3 * k), cornerRadius: 12 * k, style: .continuous),
                                   with: .color(Color(hex: Palette.accent)), lineWidth: 2.5 * k)
                    }
                }
            }
            for x in [855.0, 931.0, 1007.0] { button(CGFloat(x)) }
            button(1083 - 16)
            if showWindow {
                let s = size.width / Device060.miniSource.width, src = MacPicture060.inMiniSource
                let pic = CGRect(x: src.minX * s, y: src.minY * s, width: src.width * s, height: src.height * s)
                ctx.fill(Path(pic), with: .linearGradient(Gradient(colors: [Color(hex: 0x2B3550), Color(hex: 0x12151E)]),
                                                         startPoint: CGPoint(x: pic.minX, y: pic.minY), endPoint: CGPoint(x: pic.maxX, y: pic.maxY)))
                let w = CGRect(x: pic.minX + pic.width * 0.18, y: pic.minY + pic.height * 0.16, width: pic.width * 0.64, height: pic.height * 0.62)
                MacWindow060.draw(&ctx, w, k: w.width / 304)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
