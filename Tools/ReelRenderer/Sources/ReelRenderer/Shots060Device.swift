// Shots060Device.swift — Act III, on iPhone and iPad (28.8–62.4): pinch to zoom (S09), Larger Picture (S10), a
// keyboard and scrolling (S11–S12), composing in Chinese, Japanese and Korean (S13), tiles (S14), Aa at Off (S15),
// the thumbnail hold (S16), the tour (S17). Harness stills of Sill 0.6.0 and the drawn Mac pictures they show; what a
// still cannot show is drawn: fingers, the zoom, the Mac's reactions (typing, the Save sheet, a scroll, a selected
// cell), the Settings panel's own transition, the hold ring. S09–S13 stand in for Noah's takes C–F.
import AppKit
import CoreText
import SwiftUI

/// A rect of a Mac picture (2880×1800 px, as tools/draw.swift drew them) → an iPad still's px.
func picRect(_ r: CGRect) -> CGRect {
    let s = Mini060.picture.width / 2880
    return CGRect(x: Mini060.picture.minX + r.minX * s, y: Mini060.picture.minY + r.minY * s, width: r.width * s, height: r.height * s)
}
func picPoint(_ p: CGPoint) -> CGPoint { let r = picRect(CGRect(origin: p, size: .zero)); return r.origin }

/// The large iPad of S09 and S13: 1280×841 interior, its right edge past the frame (v3's large device, cropped), its left
/// edge 80 px or more from the words (the review; `clearance`).
enum Large060 {
    static let spec = DeviceSpec.miniH
    static let centre = CGPoint(x: 1540, y: 560)
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
}

// MARK: S09 · Pinch to zoom (28.8–32.8)

enum Pinch060 {
    /// The zoom (z) and the visible window's centre (v, as a fraction of the picture) over the shot: two fingers spread
    /// about the sheet's row 3 to 3×, hold, move it (two fingers), a tap selects a cell, a pinch all the way out.
    static let anchor = CGPoint(x: 0.45, y: 0.44)
    static let spread = (28.25 + 1.0, 29.9), move = (30.3, 30.9), tap = 31.1, pinchIn = (31.55, 32.25)
    static let zMax: CGFloat = 3
    static let pan = CGPoint(x: 0.06, y: 0.04)
    /// The tapped cell: Arrives on row 5 (15:55), in the sheet's px (tools/draw.swift's table).
    static let cell = CGRect(x: 1460, y: 978, width: 220, height: 104)

    static func z(_ t: Double) -> CGFloat {
        if t < spread.0 { return 1 }
        if t < pinchIn.0 { return 1 + (zMax - 1) * CGFloat(CubicBezier.inOut(ramp(t, spread.0, spread.1))) }
        return zMax - (zMax - 1) * CGFloat(CubicBezier.inOut(ramp(t, pinchIn.0, pinchIn.1)))
    }
    static func v(_ t: Double) -> CGPoint {
        let z = Pinch060.z(t)
        if t < pinchIn.0 {
            // The point under the fingers stays under them: v = a − (a − ½)/z, then the two-finger move.
            let base = CGPoint(x: anchor.x - (anchor.x - 0.5) / z, y: anchor.y - (anchor.y - 0.5) / z)
            let m = CGFloat(CubicBezier.inOut(ramp(t, move.0, move.1)))
            return CGPoint(x: base.x + pan.x * m, y: base.y + pan.y * m)
        }
        // Pinched all the way out, the picture is whole again: v returns to the middle as z returns to 1.
        let start = CGPoint(x: anchor.x - (anchor.x - 0.5) / zMax + pan.x, y: anchor.y - (anchor.y - 0.5) / zMax + pan.y)
        let f = (zMax - z) / (zMax - 1)
        return CGPoint(x: lerp(start.x, 0.5, Double(f)), y: lerp(start.y, 0.5, Double(f)))
    }
    /// A point of the picture (fraction) → the still's px at time t.
    static func screen(_ u: CGPoint, _ t: Double) -> CGPoint {
        let P = Mini060.picture, z = Pinch060.z(t), c = v(t)
        return CGPoint(x: P.minX + P.width * (0.5 + (u.x - c.x) * z), y: P.minY + P.height * (0.5 + (u.y - c.y) * z))
    }
    /// The fingers (still px): two for each pinch and the move, one for the tap.
    static func dots() -> [TouchDotSpec] {
        let a = screen(anchor, 0)
        func pair(_ d0: CGVector, _ window: (Double, Double), centre: @escaping (Double) -> CGPoint, scale: @escaping (Double) -> CGFloat) -> [TouchDotSpec] {
            [1.0, -1.0].map { sgn in
                TouchDotSpec(at: window.0, point: .zero, interiorWidth: Mini060.source.width,
                             drag: (window.0, window.1, { t in
                                 let c = centre(t), s = scale(t)
                                 return CGPoint(x: c.x + CGFloat(sgn) * d0.dx * s, y: c.y + CGFloat(sgn) * d0.dy * s)
                             }))
            }
        }
        let spreadDots = pair(CGVector(dx: 62, dy: 40), (spread.0, spread.1 + 0.05), centre: { _ in a }, scale: { z($0) })
        let moveStart = CGPoint(x: 1150, y: 800)
        let moveBy = CGPoint(x: -pan.x * zMax * Mini060.picture.width, y: -pan.y * zMax * Mini060.picture.height)
        let moveDots = pair(CGVector(dx: 110, dy: 30), (move.0 - 0.05, move.1 + 0.05), centre: { t in
            let m = CGFloat(CubicBezier.inOut(ramp(t, move.0, move.1)))
            return CGPoint(x: moveStart.x + moveBy.x * m, y: moveStart.y + moveBy.y * m)
        }, scale: { _ in 1 })
        let inDots = pair(CGVector(dx: 62, dy: 40), (pinchIn.0 - 0.05, pinchIn.1), centre: { _ in CGPoint(x: 1150, y: 900) }, scale: { z($0) })
        let cellCentre = CGPoint(x: (cell.midX) / 2880, y: cell.midY / 1800)
        let tapDot = TouchDotSpec(at: tap, point: screen(cellCentre, tap), interiorWidth: Mini060.source.width)
        return spreadDots + moveDots + [tapDot] + inDots
    }
}

/// The spreadsheet's picture zoomed and moved as Sill draws a pinched picture, in the iPad's interior px, with the
/// cell the tap selected.
struct ZoomedSheet060: View {
    let sheet: CGImage
    let k: CGFloat
    let t: Double
    var body: some View {
        let P = scaledRect(Mini060.picture, k)
        let z = Pinch060.z(t), v = Pinch060.v(t)
        let w = P.width * z, h = P.height * z
        let x = P.minX + P.width / 2 - v.x * w, y = P.minY + P.height / 2 - v.y * h
        let cell = Pinch060.cell
        let sel = CGRect(x: x + cell.minX / 2880 * w, y: y + cell.minY / 1800 * h, width: cell.width / 2880 * w, height: cell.height / 1800 * h)
        return ZStack(alignment: .topLeading) {
            // The picture scaled and moved by one render transform, so the zoom glides (a frame and an offset are rounded
            // to whole pixels).
            Image(decorative: sheet, scale: 1).resizable().interpolation(.high)
                .frame(width: P.width, height: P.height)
                .transformEffect(CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: x, ty: y))
            if t >= Pinch060.tap + 0.05 {
                Path(roundedRect: sel, cornerRadius: 2 * z * k).stroke(Color(hex: 0x007AFF), lineWidth: 3 * z * k * 1.4)
            }
        }
        .frame(width: P.maxX, height: P.maxY, alignment: .topLeading)
        .clipShape(Path(P))
    }
}

// SWAP-IN (S09, take C): replace with Noah's clip C if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-C.mov, inside Large060's iPad in place of
// C0 and the drawn zoom (Pinch060). Marks: the spread 29.25–29.9 (to about 3×), the two-finger move 30.3–30.9, the
// tap 31.1, the pinch all the way out 31.55–32.25. Keep or drop the drawn touch dots to match the take's fingers.
@MainActor func s060_09(_ t: Double, _ e: Env) throws -> FrameLayers {
    let L = Large060.self
    let sheet = try e.f.image("pictures/sheet")
    let overlay = ZoomedSheet060(sheet: sheet, k: L.k, t: t)
    let device = try padDevice(e, spec: L.spec, centre: L.centre, yaw: 0, t: t, fetch: 1.03,
                               layers: [MiniLayer(name: "stills/C0-sheet")], dots: Pinch060.dots(), overlay: any(overlay))
    let lines = [leftLine(Copy060.pinch, .T1c, baseline: 450, snap: 28.85, end: 32.8),
                 leftLine(Copy060.upTo5, .T4, baseline: 536, snap: 29.65, end: 32.8),
                 leftLine(Copy060.pinchSub, .T2, baseline: 612, snap: 30.85, end: 32.8)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1440, y: 560))
        device.canvas().scaled(1 + 0.02 * CGFloat(ramp(t, 28.8, 32.8)), about: CGPoint(x: 1482, y: 565))
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S10 · Larger Picture (32.8–36.8)

enum Larger060 {
    static let spec = DeviceSpec.phoneH
    static let centre = CGPoint(x: 1390, y: 556)
    static let source = CGSize(width: 786, height: 1704)
    static let settingsTap = 33.15, panel = 33.2, switchTap = 33.75, doneTap = 34.15, larger = 34.3, fitted = 35.3
    static let settingsPoint = CGPoint(x: 685, y: 700), switchPoint = CGPoint(x: 643, y: 997), donePoint = CGPoint(x: 680, y: 817)
    /// D4's switch box and D5's (on), and the "This iPad" header the harness's iPad simulator printed (patched: an iPhone
    /// says "This iPhone").
    static let switchOff = CGRect(x: 578, y: 966, width: 132, height: 62)
    static let switchOn = CGRect(x: 565, y: 1174, width: 132, height: 62)
    static let header = CGRect(x: 78, y: 902, width: 220, height: 44)
}

extension Footage060 {
    /// `larger(on:)` scaled to `width` px, cached.
    func larger(on: Bool, width: CGFloat) throws -> CGImage {
        let key = "\(on)|\(Int(width.rounded()))"
        if let hit = derivedLarger[key] { return hit }
        let img = scale(try larger(on: on), width.rounded() / Larger060.source.width)
        derivedLarger[key] = img
        return img
    }

    /// D4 with the switch on (D5's), its header reading "This iPhone" and row 1's Aa "1×" (Retouch060.iphone; the
    /// review: the header's ink had been taken from the panel's background, so it drew nearly invisible).
    func larger(on: Bool) throws -> CGImage {
        let name = on ? "derived/D4on" : "derived/D4p"
        if let hit = derivedLarger[name] { return hit }
        let d4 = try image("stills/D4-iphone-settings-off"), d5 = try image("stills/D5-iphone-settings-on")
        let ctx = CGContext(data: nil, width: d4.width, height: d4.height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(d4.height)); ctx.scaleBy(x: 1, y: -1)
        Footage060.put(ctx, d4, in: CGRect(x: 0, y: 0, width: d4.width, height: d4.height))
        if on, let sw = d5.cropping(to: Larger060.switchOn) {
            Footage060.put(ctx, sw, in: Larger060.switchOff)
        }
        let img = Retouch060.iphone(ctx.makeImage()!, larger: false, header: true)
        derivedLarger[name] = img
        return img
    }
}
@MainActor private var derivedLarger: [String: CGImage] = [:]

/// The iPhone's screen: `layers` (each an image and its opacity) filling it, the status strip masked, touch dots.
struct PhoneLayers060: View {
    let spec: DeviceSpec
    let layers: [(CGImage, Double)]
    var dots: [TouchDotSpec] = []
    var t: Double
    var body: some View {
        let size = spec.interior
        let k = size.width / Device060.phonePoints.width
        ZStack(alignment: .topLeading) {
            Color.black
            ForEach(0..<layers.count, id: \.self) { i in
                if layers[i].1 > 0.001 {
                    Image(decorative: layers[i].0, scale: 1).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height).opacity(layers[i].1)
                }
            }
            ForEach(0..<dots.count, id: \.self) { i in
                TouchDot(spec: dots[i], t: t, clipScale: size.width / dots[i].interiorWidth)
            }
            Color.black.frame(width: size.width, height: Device060.phoneStatusStrip * k)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// SWAP-IN (S10, take D): replace with Noah's clip D if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-D.mov (the iPhone, upright), inside
// PhoneLayers060 in place of D1, D4/D5, D2 and D3. Marks: Settings tapped 33.15, the Larger Picture switch 33.75, Done
// 34.15, the larger layout 34.3 (A5), the Mac's fit 35.3 (C♯6). Mask the take's status strip black, as the phone's
// stills are.
@MainActor func s060_10(_ t: Double, _ e: Env) throws -> FrameLayers {
    let L = Larger060.self
    let w = L.spec.interior.width * 1.03
    func still(_ n: String) throws -> CGImage { try e.f.scaled(n, width: w) }
    let d4p = try e.f.larger(on: false, width: w)
    let d4on = try e.f.larger(on: true, width: w)
    var layers: [(CGImage, Double)] = [(try still("derived/D1x"), 1)]
    layers.append((d4p, ramp(t, L.panel, L.panel + 0.2)))
    layers.append((d4on, ramp(t, L.switchTap + 0.04, L.switchTap + 0.16)))
    layers.append((try still("derived/D2x"), CubicBezier.inOut(ramp(t, L.larger, L.larger + 0.28))))
    layers.append((try still("derived/D3x"), CubicBezier.inOut(ramp(t, L.fitted, L.fitted + 0.22))))
    // Drop the layers a later one covers whole.
    if let top = layers.lastIndex(where: { $0.1 >= 0.999 }) { layers = Array(layers[top...]) }
    let dots = [Device060.dot(at: L.settingsTap, L.settingsPoint, source: L.source), Device060.dot(at: L.switchTap, L.switchPoint, source: L.source),
                Device060.dot(at: L.doneTap, L.donePoint, source: L.source)]
    let phone = PlacedDevice(spec: L.spec, center: L.centre, yaw: -4) {
        PhoneLayers060(spec: L.spec, layers: layers, dots: dots, t: t)
    }
    var lines = [leftLine(Copy060.larger, .T1c, baseline: 400, snap: 32.85, end: 36.8),
                 leftLine(Copy060.upright, .T4, baseline: 486, snap: 33.65, end: 36.8)]
    lines += capped([leftLine(Copy060.largerSub[0], .T2, baseline: 566, snap: 34.85, end: 36.8),
                     leftLine(Copy060.largerSub[1], .T2, baseline: 608, snap: 35.10, end: 36.8)])
    lines.append(leftLine(Copy060.largerFoot, .T3, baseline: 660, snap: 32.90, end: 36.8, cascade: false))
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: L.centre)
        SillLine(y: 1036, length: 900, centerX: L.centre.x)
        phone.canvas().scaled(1 + 0.02 * CGFloat(ramp(t, 32.8, 36.8)), about: CGPoint(x: L.centre.x, y: 1036))
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S11–S12 · a keyboard, and scrolling (36.8–44.0)

enum Keys060 {
    static let spec = DeviceSpec(interior: CGSize(width: 820, height: 538), bezel: 28, innerRadius: 22, outerRadius: 50)
    static let centre = CGPoint(x: 1430, y: 392)
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    static let slabWidth: CGFloat = 960
    static let slabOffset = CGSize(width: 1430 - 960, height: 238)
    static let typed = "Typing right away."
    /// The keystrokes: a quick typist (about 15 a second), the times varying a little, from 37.2.
    static let strokes: [Double] = {
        let gaps = [0.0, 0.07, 0.06, 0.065, 0.055, 0.07, 0.09, 0.06, 0.055, 0.065, 0.06, 0.07, 0.085, 0.06, 0.065, 0.055, 0.07, 0.075]
        var t = 37.2, out: [Double] = []
        for g in gaps { t += g; out.append(t) }
        return out
    }()
    /// The keys under each character (KeyboardSlab060's rows): T is ⇧ and t.
    static let keys: [[(row: Int, key: Int)]] = [
        [(4, 0), (2, 5)], [(2, 6)], [(2, 10)], [(2, 8)], [(4, 6)], [(3, 5)], [(5, 4)], [(2, 4)], [(2, 8)], [(3, 5)], [(3, 6)], [(2, 5)],
        [(5, 4)], [(3, 1)], [(2, 2)], [(3, 1)], [(2, 6)], [(4, 9)],
    ]
    static let cmdS = 38.35, sheetIn = 38.40, esc = 39.2
    /// The line's characters' left edges in TextEdit's picture px (Helvetica 64 from x 120, tools/draw.swift).
    static let edges: [CGFloat] = {
        let font = NSFont(name: "Helvetica", size: 64) ?? NSFont.systemFont(ofSize: 64)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: typed, attributes: [.font: font]))
        return (0...typed.count).map { 120 + CTLineGetOffsetForStringIndex(line, $0, nil) }
    }()
    static func typedCount(_ t: Double) -> Int { strokes.filter { t >= $0 + 0.03 }.count }
    /// The Save sheet in the picture's px (tools/draw.swift: 1120×560 at (880, 110), its shadow under it).
    static let sheet = CGRect(x: 850, y: 110, width: 1180, height: 620)
    static func sheetDown(_ t: Double) -> Double {
        if t < sheetIn { return 0 }
        if t < esc { return ease(t, sheetIn, 0.25, .appleOut) }
        return 1 - ease(t, esc + 0.02, 0.15, .appleIn)
    }
    static var pressed: [(row: Int, key: Int, at: Double)] {
        var p: [(row: Int, key: Int, at: Double)] = []
        for (i, ks) in keys.enumerated() { for k in ks { p.append((k.row, k.key, strokes[i] - (ks.count > 1 && k.row == 4 && k.key == 0 ? 0.05 : 0))) } }
        p.append((5, 3, cmdS - 0.05)); p.append((3, 2, cmdS))
        return p
    }
}

/// TextEdit as the keystrokes reach it (S11): E0, with E1's line revealed character by character and its title once
/// edited, a caret at the typing point, then the Save sheet sliding down from under the title bar (⌘S) and back (Esc).
struct Typing060: View {
    let e0: CGImage, e1: CGImage, sheet: CGImage
    let size: CGSize
    let t: Double
    var body: some View {
        let k = size.width / Mini060.source.width
        let n = Keys060.typedCount(t)
        let all = n >= Keys060.typed.count
        let edge = Keys060.edges[min(n, Keys060.typed.count)]
        let band = scaledRect(picRect(CGRect(x: 0, y: 236, width: edge + (all ? 40 : 0), height: 120)), k)
        let title = scaledRect(picRect(CGRect(x: 0, y: 0, width: 2880, height: 104)), k)
        let caret = scaledRect(picRect(CGRect(x: edge + 4, y: 256, width: 4, height: 82)), k)
        let down = Keys060.sheetDown(t)
        let content = scaledRect(picRect(CGRect(x: 0, y: 104, width: 2880, height: 1696)), k)
        let s = scaledRect(picRect(Keys060.sheet), k)
        return ZStack(alignment: .topLeading) {
            if n > 0 {
                Image(decorative: e1, scale: 1).resizable().interpolation(.high).frame(width: size.width, height: size.height)
                    .mask(Path { p in p.addRect(band); p.addRect(title) }.fill(Color.white).frame(width: size.width, height: size.height))
            }
            if n > 0 && !all && t < Keys060.sheetIn {
                Path(caret).fill(Color(hex: 0x1D1D1F))
            }
            if down > 0.001 {
                Path(content).fill(Color.black.opacity(0.10 * down))
                Image(decorative: sheet, scale: 1).resizable().interpolation(.high)
                    .frame(width: s.width, height: s.height)
                    .transformEffect(CGAffineTransform(translationX: s.minX, y: s.minY - s.height * CGFloat(1 - down)))
                    .mask(Path(content).fill(Color.white).frame(width: size.width, height: size.height))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The iPad over the drawn keyboard (S11, and S12 closer): the slab laid back 58° in front, the iPad standing behind it.
@MainActor func keysGroup(_ e: Env, t: Double, screen: AnyView, base: String, fetch: CGFloat, escPress: KeyPress060? = nil,
                          pressed: [(row: Int, key: Int, at: Double)] = []) throws -> some View {
    let K = Keys060.self
    let h = KeyboardSlab060.height(width: K.slabWidth)
    let slab = KeyboardSlab060(width: K.slabWidth, origin: CGPoint(x: 960 - K.slabWidth / 2, y: 540 - h / 2), t: t, esc: escPress, pressed: pressed)
        .modifier(Tilt(yaw: 0, pitch: 58))
        .offset(x: K.slabOffset.width, y: K.slabOffset.height)
    let device = try padDevice(e, spec: K.spec, centre: K.centre, yaw: 0, t: t, fetch: fetch,
                               layers: [MiniLayer(name: base)], overlay: screen)
    return ZStack {
        slab
        device
    }.canvas()
}

// SWAP-IN (S11, take E part 1): replace with Noah's clip E if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-E.mov, inside Keys060's iPad in
// place of E0, the typing reveal over E1 and the E2 sheet. Marks: the first keystroke 37.2 (the picture must show by
// then), "Typing right away." typed by 38.33, ⌘S 38.35, the sheet 38.40, Esc 39.2 (the drawn slab's esc lights and
// "Esc" buzzes 39.30). Retime Keys060.strokes to the take's keystrokes so the slab and the clicks keep with it.
@MainActor func s060_11(_ t: Double, _ e: Env) throws -> FrameLayers {
    let K = Keys060.self
    let size = K.spec.interior
    let w = size.width * 1.03
    let screen = Typing060(e0: try e.f.scaled("stills/E0-te-empty", width: w), e1: try e.f.scaled("stills/E1-te-typed", width: w),
                           sheet: try e.f.crop("stills/E2-te-save", picRect(K.sheet), scale: K.k * 1.03), size: size, t: t)
    let group = try keysGroup(e, t: t, screen: any(screen), base: "stills/E0-te-empty", fetch: 1.03,
                              escPress: KeyPress060(down: K.esc, up: K.esc + 0.3), pressed: K.pressed)
    var esc = LineSpec(words: Copy060.esc, .T4, x: 128, baseline: 588, align: .leading, snap: 39.25, holdEnd: 40.8)
    // v3's "haptic" buzz on "Esc" as the key goes down (0.3 s).
    esc.jitter = (word: 0, start: 39.30, duration: 0.3, amplitude: 3)
    let lines = [leftLine(Copy060.attach, .T1c, baseline: 400, snap: 36.85, end: 40.8),
                 leftLine(Copy060.justType, .T1c, baseline: 504, snap: 37.65, end: 40.8),
                 esc,
                 leftLine(Copy060.escFoot, .T3, baseline: 640, snap: 36.90, end: 40.8, cascade: false)]
    // The iPad and its keyboard 5 % smaller toward the frame's right edge, then a 2 % push about the iPad's left edge, so
    // it keeps 80 px or more from "Attach a keyboard." (the review; `clearance`) and drifts away from it.
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1450, y: 520))
        group.scaled(0.95, about: CGPoint(x: 1900, y: 520))
            .scaled(1 + 0.02 * CGFloat(ramp(t, 36.8, 40.8)), about: CGPoint(x: 1030, y: 520))
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

enum Scroll060 {
    /// One scroll on the trackpad, in the document's px: the two fingers' speed rises over 0.1 s (smoothstep) to `v0` and
    /// holds until they lift; the content then coasts, its speed falling by e every 0.12 s, and stops once it is under
    /// the cutoff (20 px/s on the canvas), with no sub-pixel creep (the review: the first cut started at full speed in one
    /// frame and stair-stepped at its ends).
    struct Fling { let start: Double; let lift: Double; let v0: Double }
    static let rise = 0.1, tau = 0.12
    /// 20 canvas px/s in document px: a document px is 0.713 still px × 0.362 interior px × the camera's 1.15.
    static let cutoff = 20 / (0.7132 * 0.3619 * 1.15)
    static func distance(_ f: Fling, _ t: Double) -> Double {
        guard t > f.start else { return 0 }
        func fingers(_ u: Double) -> Double {
            if u < rise { let x = u / rise; return f.v0 * rise * (x * x * x - x * x * x * x / 2) }
            return f.v0 * (rise / 2 + (u - rise))
        }
        if t <= f.lift { return fingers(t - f.start) }
        let atLift = fingers(f.lift - f.start)
        let stop = tau * log(f.v0 / cutoff)
        let u = min(t - f.lift, stop)
        return atLift + f.v0 * tau * (1 - exp(-u / tau))
    }
    /// Down 520 px (40.95–41.55), then back up 200 (41.56–42.04): v0 2,110 and 902 px/s.
    static let down = Fling(start: 40.95, lift: 41.13, v0: 2110), up = Fling(start: 41.56, lift: 41.72, v0: 902)
    /// After Reverse Scrolling, a finger on the picture: up 180 still px (43.30–43.82, inOut), and the document goes the
    /// other way, down by as much (252 document px).
    static let drag = (43.30, 43.82)
    static let dragFrom = CGPoint(x: 1000, y: 1120), dragUp: CGFloat = 180
    static func dragProgress(_ t: Double) -> CGFloat { CGFloat(CubicBezier.inOut(ramp(t, drag.0, drag.1))) }
    static func offset(_ t: Double) -> CGFloat {
        CGFloat(distance(down, t) - distance(up, t)) - dragUp / 0.7132 * dragProgress(t)
    }
    /// iPadOS's round pointer: it comes to rest over the text by 40.95 and stays there while two fingers scroll (a
    /// trackpad's scroll moves no pointer); it fades as a finger touches the screen (42.0), as iPadOS hides it.
    static func pointer(_ t: Double) -> CGPoint {
        let p = CGFloat(CubicBezier.inOut(ramp(t, 40.8, 40.95)))
        return CGPoint(x: 1180 + 80 * p, y: 900 - 80 * p)
    }
    static func pointerAlpha(_ t: Double) -> Double { 1 - ramp(t, panel, panel + 0.15) }
    /// Settings in at 42.0 (a beat before the subline), Reverse Scrolling on at 42.8, Done at 43.05 (the panel out by 43.25).
    static let panel = 42.0, flip = 42.8, done = 43.05
    static let flipPoint = CGPoint(x: 2106, y: 431), donePoint = CGPoint(x: 2143, y: 237)
}

/// The long document scrolled in TextEdit (E3's chrome over longdoc-page), its scroller, and the pointer, in the
/// iPad's interior px. The page moves by a render transform, on its exact fractional offset.
struct ScrollDoc060: View {
    let page: CGImage
    let k: CGFloat
    let t: Double
    var body: some View {
        let off = Scroll060.offset(t)
        // The document's area in the picture: below the format bar (y 188), the page drawn from y 188 − off.
        let doc = scaledRect(picRect(CGRect(x: 0, y: 188, width: 2880, height: 1612)), k)
        let s = doc.width / 2880
        let pageH = CGFloat(page.height) * s
        let bar = scaledRect(picRect(CGRect(x: 2880 - 26, y: 188 + 20 + off / 4200 * 1612, width: 14, height: 1612 * 1612 / 4200)), k)
        let p = Scroll060.pointer(t)
        let pc = scaledRect(picRect(CGRect(x: p.x, y: p.y, width: 0, height: 0)), k).origin
        let d = 38 * k * 1.4
        return ZStack(alignment: .topLeading) {
            Image(decorative: page, scale: 1).resizable().interpolation(.high)
                .frame(width: doc.width, height: pageH)
                .transformEffect(CGAffineTransform(translationX: doc.minX, y: doc.minY - off * s))
                .mask(Path(doc).fill(Color.white))
            Path(roundedRect: bar, cornerRadius: bar.width / 2).fill(Color.black.opacity(0.35))
            if Scroll060.pointerAlpha(t) > 0.002 {
                Circle().fill(Color(white: 0.32, opacity: 0.55))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: max(1, 0.6 * k * 1.4)))
                    .frame(width: d, height: d)
                    .opacity(Scroll060.pointerAlpha(t))
                    .transformEffect(CGAffineTransform(translationX: pc.x - d / 2, y: pc.y - d / 2))
            }
        }
        .frame(width: doc.maxX, height: doc.maxY + 40, alignment: .topLeading)
    }
}

// SWAP-IN (S12, take E part 2): replace with Noah's clip E if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-E.mov (its scrolling part), inside
// the iPad in place of ScrollDoc060 (E3 and longdoc-page). Marks: the scroll down 40.95–41.55, back up 41.56–42.04; the
// Settings panel (E6, then E7 at 42.8, Done at 43.05) stays the harness's stills; then a finger dragged up over the
// picture (43.30–43.82) with Reverse Scrolling on, the document going down: the take's, if it has one, else keep the
// drawn drag over the take's last frame.
@MainActor func s060_12(_ t: Double, _ e: Env) throws -> FrameLayers {
    let K = Keys060.self, S = Scroll060.self
    let k = K.k * 1.25
    let page = try e.f.image("pictures/longdoc-page")
    // The Settings panel: E6's (Reverse Scrolling off), then E7's (on), in with the app's transition, out after Done.
    let panelRect = scaledRect(Sound060.panel, K.k)
    let off = try e.f.crop("stills/E6-reverse-off", Sound060.panel, scale: k), on = try e.f.crop("stills/E7-reverse-on", Sound060.panel, scale: k)
    let button = try e.f.crop("stills/E6-reverse-off", Sound060.settingsButton, scale: k)
    let panelIn = ease(t, S.panel, 0.25, .appleOut) * (1 - ease(t, S.done + 0.02, 0.2, .appleIn))
    let size = K.spec.interior
    let screen = ZStack(alignment: .topLeading) {
        ScrollDoc060(page: page, k: K.k, t: t)
        if t >= S.panel && panelIn > 0.002 {
            image(button, in: scaledRect(Sound060.settingsButton, K.k))
            ZStack(alignment: .topLeading) {
                image(off, in: panelRect)
                image(on, in: panelRect).opacity(ramp(t, S.flip + 0.03, S.flip + 0.15))
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .scaleEffect(0.94 + 0.06 * CGFloat(panelIn), anchor: UnitPoint(x: panelRect.maxX / size.width, y: panelRect.minY / size.height))
            .opacity(panelIn)
        }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    let finger = TouchDotSpec(at: S.drag.0, point: .zero, interiorWidth: Mini060.source.width, drag: (S.drag.0, S.drag.1, { t in
        CGPoint(x: S.dragFrom.x, y: S.dragFrom.y - S.dragUp * S.dragProgress(t))
    }))
    let dots = [Device060.dot(at: S.panel, Sound060.settingsPoint), Device060.dot(at: S.flip, S.flipPoint),
                Device060.dot(at: S.done, S.donePoint), finger]
    let base = try e.f.scaled("stills/E3-longdoc0", width: size.width * 1.3)
    let device = PlacedDevice(spec: K.spec, center: K.centre, yaw: 0) {
        MiniScreen(size: size, layers: [(base, MiniLayer(name: "stills/E3-longdoc0"))], dots: dots, t: t) { screen }
    }
    let h = KeyboardSlab060.height(width: K.slabWidth)
    let slab = KeyboardSlab060(width: K.slabWidth, origin: CGPoint(x: 960 - K.slabWidth / 2, y: 540 - h / 2), t: t)
        .modifier(Tilt(yaw: 0, pitch: 58)).offset(x: K.slabOffset.width, y: K.slabOffset.height)
    // Closer than S11: the iPad's screen fills the right half, the Settings panel whole inside the frame (its Done and its
    // switch are tapped), its left edge fading out 80 px or more from the words.
    let camera = 1.15 + 0.02 * CGFloat(ramp(t, 40.8, 44.0))
    let edge = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 945 / 1920),
                                      .init(color: .white, location: 1025 / 1920), .init(color: .white, location: 1)],
                              startPoint: .leading, endPoint: .trailing).canvas()
    // The footnote with the first statement; the subline whole, a beat before Reverse Scrolling flips on (the review:
    // they had been readable for about 0.7 s).
    let lines = [leftLine(Copy060.scroll, .T1c, baseline: 400, snap: 40.85, end: 44.0),
                 leftLine(Copy060.wheel, .T4, baseline: 486, snap: 41.25, end: 44.0),
                 leftLine(Copy060.reverseSub, .T2, baseline: 566, snap: 42.45, end: 44.0, cascade: false),
                 leftLine(Copy060.reverseFoot, .T3, baseline: 616, snap: 40.90, end: 44.0, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1490, y: 520))
        ZStack { slab; device }.canvas()
            .camera(camera, from: K.centre, to: CGPoint(x: 1435, y: 470))
            .mask(edge)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S13 · Chinese, Japanese, Korean, dictation (44.0–48.8)

enum Compose060 {
    /// Each greeting arrives on the Mac 0.05 s before its line snaps; the dictated sentence at 47.3.
    static let arrive = [44.40, 45.20, 46.00, 47.30]
    static let stills = ["stills/F1-cjk1", "stills/F2-cjk2", "stills/F3-cjk3", "stills/F4-cjk4"]
    /// The composition on the iPad before each arrives (a stand-in for iPadOS's own candidates, drawn simply, as S08's
    /// keyboard is): what is typed, underlined, and the candidates, the first chosen. Korean composes as it is typed,
    /// with no candidates; dictation shows the listening bars.
    static let compose: [(from: Double, typed: String, candidates: [String])] = [
        (43.85, "ni hao", ["\u{4F60}\u{597D}", "\u{4F60}", "\u{5C3C}", "\u{60A8}\u{597D}"]),
        (44.70, "\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}", ["\u{3053}\u{3093}\u{306B}\u{3061}\u{306F}", "\u{4ECA}\u{65E5}\u{306F}", "\u{30B3}\u{30F3}\u{30CB}\u{30C1}\u{30CF}"]),
        (45.55, "\u{C548}\u{B155}\u{D558}\u{C138}\u{C694}", []),
    ]
    static let dictation = (46.55, 47.30)
}

/// The composition as Sill 0.6.0 shows it (InputOverlay.swift's composition label): the marked text in a label at the
/// top middle of the picture, 16 pt under its top edge (Title 3, white, on #1C1C1E at 92 %, 12 pt by 6 pt of padding,
/// 8 pt corners), and iPadOS's candidates for a hardware keyboard beside it, under the label (drawn simply, the first
/// chosen); dictation's listening bars at the same place, where Sill's caret is (the review: the first cut drew them at
/// the bottom of the picture, far from both). Interior px; glyph outlines, part of the picture.
struct ComposeStrip060: View {
    let size: CGSize
    let t: Double
    var body: some View {
        Canvas { ctx, _ in
            let C = Compose060.self
            let k = size.width / Mini060.source.width          // interior px per still px (2 still px a point)
            let anchor = CGPoint(x: (Mini060.picture.midX) * k, y: (Mini060.picture.minY + 32) * k)
            for (i, c) in C.compose.enumerated() {
                let end = C.arrive[i]
                guard t >= c.from - 0.001, t < end + 0.12 else { continue }
                let a = ramp(t, c.from, c.from + 0.12) * (1 - ramp(t, end, end + 0.12))
                draw(&ctx, typed: c.typed, candidates: c.candidates, k: k, anchor: anchor, alpha: a, chosen: t >= end - 0.25)
            }
            let (d0, d1) = C.dictation
            if t >= d0 && t < d1 + 0.12 {
                let a = ramp(t, d0, d0 + 0.12) * (1 - ramp(t, d1, d1 + 0.12))
                var c = ctx
                c.opacity = a
                let w = 150 * 2 * k, h = 46 * 2 * k
                let r = CGRect(x: anchor.x - w / 2, y: anchor.y, width: w, height: h)
                c.fill(Path(roundedRect: r, cornerRadius: h / 2, style: .continuous), with: .color(Color(hex: 0x1C1C1E, alpha: 0.92)))
                for j in 0..<7 {
                    let phase = Double(j) * 0.9 + t * 11
                    let bh = (8 + 22 * abs(sin(phase))) * 2 * k
                    let x = r.midX + CGFloat(j - 3) * 13 * 2 * k
                    c.fill(Path(roundedRect: CGRect(x: x - 2.5 * 2 * k, y: r.midY - bh / 2, width: 5 * 2 * k, height: bh), cornerRadius: 2.5 * 2 * k),
                           with: .color(Color(hex: Palette.accent)))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func draw(_ ctx: inout GraphicsContext, typed: String, candidates: [String], k: CGFloat, anchor: CGPoint, alpha: Double, chosen: Bool) {
        var c = ctx
        c.opacity = alpha
        let pt = 2 * k                                          // interior px per point
        // The label: Title 3 (20 pt), its line 25 pt tall.
        let fs = 20 * pt
        let label = Outline060.line(typed, size: fs, weight: .regular)
        let lw = label.width + 24 * pt, lh = 25 * pt + 12 * pt
        let lr = CGRect(x: anchor.x - lw / 2, y: anchor.y, width: lw, height: lh)
        c.fill(Path(roundedRect: lr, cornerRadius: 8 * pt, style: .continuous), with: .color(Color(hex: 0x1C1C1E, alpha: 0.92)))
        Outline060.fill(label, in: &c, at: CGPoint(x: lr.minX + 12 * pt, y: lr.midY + fs * 0.36), color: .white)
        guard !candidates.isEmpty else { return }
        // iPadOS's candidates, beside the label (under it, its left edge with the label's).
        let cs = 18 * pt, ch = 40 * pt, pad = 12 * pt, gap = 20 * pt
        let cands = candidates.map { Outline060.line($0, size: cs, weight: .regular) }
        let cw = pad * 2 + cands.reduce(0) { $0 + $1.width + gap } - gap
        let cr = CGRect(x: lr.minX, y: lr.maxY + 6 * pt, width: cw, height: ch)
        c.drawLayer { g in
            g.addFilter(.blur(radius: 8 * pt))
            g.fill(Path(roundedRect: cr.offsetBy(dx: 0, dy: 3 * pt), cornerRadius: 10 * pt, style: .continuous), with: .color(.black.opacity(0.35)))
        }
        c.fill(Path(roundedRect: cr, cornerRadius: 10 * pt, style: .continuous), with: .color(Color(hex: 0x2C2C2E, alpha: 0.97)))
        let base = cr.midY + cs * 0.36
        var x = cr.minX + pad
        for (j, l) in cands.enumerated() {
            if j == 0 {
                let hl = CGRect(x: x - 7 * pt, y: cr.minY + 5 * pt, width: l.width + 14 * pt, height: ch - 10 * pt)
                c.fill(Path(roundedRect: hl, cornerRadius: 7 * pt, style: .continuous),
                       with: .color(chosen ? Color(hex: Palette.accent, alpha: 0.9) : Color.white.opacity(0.16)))
            }
            Outline060.fill(l, in: &c, at: CGPoint(x: x, y: base), color: j == 0 && chosen ? Color(hex: Palette.deviceBody) : .white)
            x += l.width + gap
        }
    }
}

// SWAP-IN (S13, take F): replace with Noah's clip F if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-F.mov, inside the iPad in place of F0–F4
// and ComposeStrip060. Marks: 你好 arriving on the Mac 44.40, こんにちは 45.20, 안녕하세요 46.00, the dictated sentence
// 47.30 (each a pluck; the greetings snap 0.05 s after). Drop the drawn composition strip: the take shows iPadOS's own.
@MainActor func s060_13(_ t: Double, _ e: Env) throws -> FrameLayers {
    let L = Large060.self, C = Compose060.self
    var layers = [MiniLayer(name: "stills/F0-cjk0")]
    for (i, at) in C.arrive.enumerated() where t >= at {
        layers.append(MiniLayer(name: C.stills[i], opacity: ramp(t, at, at + (i == 3 ? 0.25 : 0.06))))
    }
    if let top = layers.lastIndex(where: { $0.opacity >= 0.999 }) { layers = Array(layers[top...]) }
    let device = try padDevice(e, spec: L.spec, centre: L.centre, yaw: 0, t: t, fetch: 1.08, layers: layers,
                               overlay: any(ComposeStrip060(size: L.spec.interior, t: t)))
    var lines: [LineSpec] = []
    for i in 0..<3 {
        var l = leftLine(Copy060.greetings[i], .T1c, baseline: CGFloat(330 + 108 * i), snap: [44.45, 45.25, 46.05][i], end: 48.8)
        l.language = Copy060.greetingLanguages[i]
        lines.append(l)
    }
    lines.append(leftLine(Copy060.composeSub, .T2, baseline: 638, snap: 46.85, end: 48.8))
    lines.append(leftLine(Copy060.composeFoot, .T3, baseline: 688, snap: 44.50, end: 48.8, cascade: false))
    // A slow push on TextEdit's lines, where the words arrive.
    let about = onCanvas(L.spec, center: L.centre, CGPoint(x: 240 * L.k, y: 480 * L.k))
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1400, y: 560))
        device.canvas().scaled(1 + 0.07 * CGFloat(CubicBezier.inOut(ramp(t, 44.0, 48.8))), about: about)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: S14 · Every Mac, a tile (48.8–52.8)

enum Tiles060 {
    /// The connect screen's column on the upright iPad's still (1488×2266 px), shown as v3 showed its connect screen:
    /// a hard-edged crop on black, drifting.
    static let crop = CGRect(x: 370, y: 360, width: 750, height: 1530)
    static let scale: CGFloat = 0.64
    static let centre = CGPoint(x: 1400, y: 548)
    static let toList = 50.4, toTiles = 51.2
}

@MainActor func s060_14(_ t: Double, _ e: Env) throws -> FrameLayers {
    let T = Tiles060.self
    // N1x: N1 with Noah’s MacBook Pro’s tile showing QuickTime as S06 left it (Reel060.swift; the review: its picture
    // had been v3.1's Weather frame, with Noah's saved places).
    let name = t >= T.toList && t < T.toTiles ? "stills/N2-list" : "derived/N1x"
    // Soft edges all round: the stills' background is the connect screen's near-black, which a hard edge would show.
    let m = MacroSpec(crop: T.crop, scale: T.scale, center: T.centre, feather: 50, hardEdges: [], interior: CGSize(width: 1488, height: 2266))
    let img = try e.f.crop(name, m.fetchRect, scale: m.scale)
    var lines = [leftLine(Copy060.tiles, .T1c, baseline: 430, snap: 48.85, end: 52.8)]
    lines += capped([leftLine(Copy060.tilesSub[0], .T2, baseline: 512, snap: 49.65, end: 52.8),
                     leftLine(Copy060.tilesSub[1], .T2, baseline: 554, snap: 49.90, end: 52.8)])
    lines.append(leftLine(Copy060.tilesFoot, .T3, baseline: 610, snap: 51.25, end: 52.8, cascade: false))
    // The drift (6 px a second to the left) is a render transform, so it glides (a macro's place is rounded to whole px).
    let v = ZStack {
        Backdrop(glow: 0.05, glowCenter: T.centre)
        MacroView(spec: m, image: img) { EmptyView() }
            .transformEffect(CGAffineTransform(translationX: -6 * CGFloat(t - 48.8), y: 0))
            .scaled(1 + 0.02 * CGFloat(ramp(t, 48.8, 52.8)), about: T.centre)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S15 · Aa starts at Off (52.8–56.0)

enum Aa060 {
    static let off = 54.4
    /// The bar's Aa ruler (H1 at 1.25×, H2 at Off), cropped close.
    static let crop = CGRect(x: 1380, y: 0, width: 640, height: 172)
    static let scale: CGFloat = 1.32
    static let centre = CGPoint(x: 1400, y: 610)
}

@MainActor func s060_15(_ t: Double, _ e: Env) throws -> FrameLayers {
    let A = Aa060.self
    let name = t >= A.off ? "stills/H2-scaleoff-open" : "stills/H1-scale125-open"
    let m = macro(crop: A.crop, scale: A.scale, center: A.centre, snap: 40, feather: 60, interior: Mini060.source)
    let img = try e.f.crop(name, m.fetchRect, scale: m.scale)
    // The subline a beat before Aa goes to Off (it says what that does), the footnote with the first statement.
    var lines = [LineSpec(Copy060.aaOff, .T1s, baseline: 150, snap: 52.85, holdEnd: 56.0)]
    lines += capped([LineSpec(Copy060.aaSub, .T2, baseline: 214, snap: 54.05, holdEnd: 56.0)])
    lines.append(LineSpec(Copy060.aaFoot, .T3, baseline: 258, snap: 52.90, holdEnd: 56.0, cascade: false))
    let v = ZStack {
        Backdrop(glow: 0.05, glowCenter: CGPoint(x: 960, y: 600))
        AaMac060(k: 0.86, center: CGPoint(x: 520, y: 640), t: t, shrink: A.off)
        MacroView(spec: m, image: img) { EmptyView() }
            .scaled(1 + 0.015 * CGFloat(ramp(t, 52.8, 56.0)), about: A.centre)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S16 · Hold a thumbnail (56.0–59.2)

enum Hold060 {
    static let down = 56.4, open = 56.9, lift = 57.3, row = 58.0
    /// The bar, close: the first thumbnails and the lights under the first (J1), 1.32 px per still px.
    static let crop = CGRect(x: 0, y: 0, width: 600, height: 330)
    static let scale: CGFloat = 1.32
    static let centre = CGPoint(x: 500, y: 470)
    /// J2's row "Hold to Show Window Controls 0.5 s".
    static let rowRect = CGRect(x: 1526, y: 395, width: 654, height: 106)
    static let rowCentre = CGPoint(x: 520, y: 820)
}

@MainActor func s060_16(_ t: Double, _ e: Env) throws -> FrameLayers {
    let H = Hold060.self
    let name = t >= H.open ? "stills/J1-windowmenu" : "stills/L0-unlocked"
    let m = macro(crop: H.crop, scale: H.scale, center: H.centre, snap: 40, feather: 70, interior: Mini060.source)
    let img = try e.f.crop(name, m.fetchRect, scale: m.scale)
    let o = m.screenOrigin
    let thumb = CGPoint(x: o.x + (Device060.miniFirstThumbnail.x - m.crop.minX) * m.scale, y: o.y + (Device060.miniFirstThumbnail.y - m.crop.minY) * m.scale)
    // v3's touch dot, 64 pt on the iPad (128 still px), at the macro's scale.
    let ring = HoldRing060(center: thumb, diameter: 128 * m.scale, down: H.down, duration: 0.5, lift: H.lift, t: t)
    // The Settings row slides in under the bar at 58.0 (0.35 s appleOut, 40 px up, fading in).
    let row = try e.f.crop("stills/J2-hold-row", H.rowRect, scale: 1.0)
    let p = ease(t, H.row, 0.35, .appleOut)
    let rowView = ZStack(alignment: .topLeading) {
        Color.clear.canvas()
        Image(decorative: row, scale: 1).resizable().interpolation(.high)
            .frame(width: H.rowRect.width, height: H.rowRect.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(p)
            .transformEffect(CGAffineTransform(translationX: H.rowCentre.x - H.rowRect.width / 2,
                                               y: H.rowCentre.y - H.rowRect.height / 2 + 40 * CGFloat(1 - p)))
    }.frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    let lines = [LineSpec(Copy060.hold, .T1c, x: 1060, baseline: 470, align: .leading, snap: 56.05, holdEnd: 59.2),
                 LineSpec(Copy060.halfSecond, .T4, x: 1060, baseline: 556, align: .leading, snap: 56.95, holdEnd: 59.2),
                 LineSpec(Copy060.holdFoot, .T3, x: 1060, baseline: 616, align: .leading, snap: 58.05, holdEnd: 59.2, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.05, glowCenter: H.centre)
        ZStack {
            MacroView(spec: m, image: img) { EmptyView() }
            ring
        }
        .canvas()
        .scaled(1 + 0.02 * CGFloat(ramp(t, 56.0, 59.2)), about: thumb)
        if t >= H.row { rowView }
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

// MARK: S17 · The tour (59.2–62.4)

enum Tour060 {
    /// S17's iPad: the first cut's (Pad060 became S04–S08's smaller one), its push onto the card's row 101 px clear of the
    /// words (`clearance`).
    static let spec = DeviceSpec(interior: CGSize(width: 820, height: 538), bezel: 28, innerRadius: 22, outerRadius: 50)
    static let centre = CGPoint(x: 1426, y: 560)
    static var k: CGFloat { spec.interior.width / Mini060.source.width }
    /// The tour's card on K1; its row "New: Pinch to zoom the picture here, up to 5×…" (x 809–1461, y 800–950).
    static let row = CGPoint(x: 1050, y: 836)
    static let push: (Double, Double) = (59.6, 62.4)
    static let to: CGFloat = 1.6
}

@MainActor func s060_17(_ t: Double, _ e: Env) throws -> FrameLayers {
    let T = Tour060.self
    let device = try padDevice(e, spec: T.spec, centre: T.centre, yaw: 0, t: t, fetch: T.to,
                               layers: [MiniLayer(name: "stills/K1-tour-touch")])
    let p = CGFloat(CubicBezier.inOut(ramp(t, T.push.0, T.push.1)))
    let s = 1 + (T.to - 1) * p
    let from = onCanvas(T.spec, center: T.centre, CGPoint(x: T.row.x * T.k, y: T.row.y * T.k))
    let to = CGPoint(x: lerp(from.x, 1380, Double(p)), y: lerp(from.y, 560, Double(p)))
    let edge = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 880 / 1920),
                                      .init(color: .white, location: 960 / 1920), .init(color: .white, location: 1)],
                              startPoint: .leading, endPoint: .trailing).canvas()
    var lines = [leftLine(Copy060.tourLines[0], .T1c, baseline: 400, snap: 59.25, end: 62.4),
                 leftLine(Copy060.tourLines[1], .T1c, baseline: 504, snap: 59.40, end: 62.4)]
    lines += capped([leftLine(Copy060.tourSubLines[0], .T2, baseline: 588, snap: 60.45, end: 62.4),
                     leftLine(Copy060.tourSubLines[1], .T2, baseline: 630, snap: 60.75, end: 62.4)])
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: T.centre)
        device.canvas().camera(s, from: from, to: to).mask(edge)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

extension Copy060 {
    /// "The tour marks what’s new." on two lines beside the iPad (T1c: one line would be 1,170 px).
    static let tourLines = ["The tour marks", "what\u{2019}s new."]
    /// "It shows once after the update, and any time from Settings." on two lines.
    static let tourSubLines = ["It shows once after the update,", "and any time from Settings."]
}
