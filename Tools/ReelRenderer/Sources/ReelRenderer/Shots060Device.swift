// Shots060Device.swift — Act III, on iPhone and iPad (28.8–59.2): pinch to zoom (S09), Larger Picture (S10), a
// keyboard and scrolling (S11–S12), composing in Chinese, Japanese and Korean (S13), tiles (S14), Aa at Off (S15),
// the thumbnail hold (S16); v4's tour (S17) is cut in v4.2 (Cut060). Harness stills of Sill 0.6.0 and the drawn Mac pictures they show; what a
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
            // The picture scaled and moved on its exact path (ExactPicture060: a picture under a render transform is placed on
            // a quarter-pixel grid).
            ExactPicture060(image: sheet, transform: CGAffineTransform(scaleX: P.width / CGFloat(sheet.width), y: P.height / CGFloat(sheet.height))
                .concatenating(CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: x, ty: y)), size: CGSize(width: P.maxX, height: P.maxY), extend: true)
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
        Flat060.moving(device, .push(1 + 0.02 * CGFloat(ramp(t, 28.8, 32.8)), about: CGPoint(x: 1482, y: 565)), region: Flat060.region(L.spec, center: L.centre))
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
    /// v5, Noah: the line about the keyboard "should trigger the virtual keyboard coming up showing how it perfectly covers the
    /// trackpad". As its second half is written, row 1's Keyboard button is tapped (its centre in D2, x 401–508, y 862–961),
    /// lights (D2k, D3k), and iOS's keyboard rises inside the screen to rest on the trackpad's footprint exactly: its top
    /// edge on the trackpad's top edge (y 1102 of 1704 px, 551 pt: the footage's own iPhone said "keyboard: up, 301 pt
    /// tall, its top at 492 pt in the stream screen; the key row ends 10 pt above it"), the key row and the picture above it
    /// unmoved; it stays up to the cut.
    static let keyboardTap = 34.55, keyboardRise = 34.6
    static let keyboardPoint = CGPoint(x: 454.5, y: 911.5)
    static let keyboard = CGRect(x: 0, y: 1102, width: 786, height: 602)
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

/// The iPhone's screen: `layers` (each an image and its opacity) filling it, iOS's keyboard rising from `keyboardRise` (v5),
/// the status strip masked, touch dots.
struct PhoneLayers060: View {
    let spec: DeviceSpec
    let layers: [(CGImage, Double)]
    var dots: [TouchDotSpec] = []
    var t: Double
    var keyboardRise: Double? = nil
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
            if let rise = keyboardRise, t >= rise {
                // The keyboard slides up inside the screen (a shape at its exact place: SoftKeyboard060.offset's 0.30 s
                // appleOut from below the screen's bottom edge), to rest on the trackpad's footprint.
                Canvas { ctx, _ in
                    let k = size.width / Larger060.source.width
                    let h = Larger060.keyboard.height * k
                    let y = Larger060.keyboard.minY * k + SoftKeyboard060.offset(t, height: h, rise: rise)
                    SoftKeyboard060.drawPhone(&ctx, rect: CGRect(x: 0, y: y, width: size.width, height: h))
                }
                .frame(width: size.width, height: size.height)
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
    // The Keyboard button lit from the tap (D2k), and the Mac's fit with it lit (D3k).
    layers.append((try still("derived/D2kx"), ramp(t, L.keyboardTap + 0.04, L.keyboardTap + 0.12)))
    layers.append((try still("derived/D3kx"), CubicBezier.inOut(ramp(t, L.fitted, L.fitted + 0.22))))
    // Drop the layers a later one covers whole.
    if let top = layers.lastIndex(where: { $0.1 >= 0.999 }) { layers = Array(layers[top...]) }
    let dots = [Device060.dot(at: L.settingsTap, L.settingsPoint, source: L.source), Device060.dot(at: L.switchTap, L.switchPoint, source: L.source),
                Device060.dot(at: L.doneTap, L.donePoint, source: L.source), Device060.dot(at: L.keyboardTap, L.keyboardPoint, source: L.source)]
    let phone = PlacedDevice(spec: L.spec, center: L.centre, yaw: -4) {
        PhoneLayers060(spec: L.spec, layers: layers, dots: dots, t: t, keyboardRise: L.keyboardRise)
    }
    var lines = [leftLine(Copy060.larger, .T1c, baseline: 400, snap: 32.85, end: 36.8),
                 leftLine(Copy060.upright, .T4, baseline: 486, snap: 33.65, end: 36.8)]
    // v5: the subline a beat earlier (34.45, 2.35 s before the cut), its second half written as the keyboard rises.
    lines += capped([leftLine(Copy060.largerSub[0], .T2, baseline: 566, snap: 34.45, end: 36.8),
                     leftLine(Copy060.largerSub[1], .T2, baseline: 608, snap: 34.70, end: 36.8)])
    lines.append(leftLine(Copy060.largerFoot, .T3, baseline: 660, snap: 32.90, end: 36.8, cascade: false))
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: L.centre)
        SillLine(y: 1036, length: 900, centerX: L.centre.x)
        Flat060.moving(phone, .push(1 + 0.02 * CGFloat(ramp(t, 32.8, 36.8)), about: CGPoint(x: L.centre.x, y: 1036)), region: Flat060.region(L.spec, center: L.centre))
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
    /// What the iPad (its shadow included) and the laid-back slab cover on the canvas at rest (Flat060's picture).
    static let region = CGRect(x: 700, y: -160, width: 1460, height: 1280)
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
    /// The Save sheet in the picture's px: v5's te-save (tools/draw.swift, redrawn for Noah's note on v4.2 at 0:39, "The save
    /// as dialog is cut off on the right side"): 1120×560 at (880, 104), centred on the window and hanging from the bottom of
    /// its title bar, its corners 28 px, its shadow under it; the window behind it not dimmed.
    static let sheetBox = CGRect(x: 880, y: 104, width: 1120, height: 560)
    /// Where E2 differs from E1 (the sheet and its shadow), in the still's px: x 705–1560, y 262–697 (the footage's
    /// measurement), the matte `derived/E2sheet` covers.
    static let sheetRegion = CGRect(x: 705, y: 262, width: 856, height: 436)
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
        let s = scaledRect(Keys060.sheetRegion, k)
        return ZStack(alignment: .topLeading) {
            if n > 0 {
                Image(decorative: e1, scale: 1).resizable().interpolation(.high).frame(width: size.width, height: size.height)
                    .mask(Path { p in p.addRect(band); p.addRect(title) }.fill(Color.white).frame(width: size.width, height: size.height))
            }
            if n > 0 && !all && t < Keys060.sheetIn {
                Path(caret).fill(Color(hex: 0x1D1D1F))
            }
            if down > 0.001 {
                // v5: the sheet and its shadow alone (the matte), sliding down from under the title bar on its exact path
                // (ExactPicture060), the window behind it as it is (macOS dims nothing behind a sheet; v4's 10 % dim and
                // its crop's box are gone with the new E2).
                ExactPicture060(image: sheet, transform: placing(sheet, in: s).concatenating(CGAffineTransform(translationX: 0, y: -s.height * CGFloat(1 - down))), size: size)
                    .mask(Path(content).fill(Color.white).frame(width: size.width, height: size.height))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The iPad over the drawn keyboard (S11, and S12 closer): the slab laid back 58° in front, the iPad standing behind it.
@MainActor func keysGroup(_ e: Env, t: Double, screen: AnyView, base: String, fetch: CGFloat, escPress: KeyPress060? = nil,
                          pressed: [(row: Int, key: Int, at: Double)] = []) throws -> AnyView {
    let K = Keys060.self
    let h = KeyboardSlab060.height(width: K.slabWidth)
    let slab = KeyboardSlab060(width: K.slabWidth, origin: CGPoint(x: 960 - K.slabWidth / 2, y: 540 - h / 2), t: t, esc: escPress, pressed: pressed)
        .modifier(Tilt(yaw: 0, pitch: 58))
        .offset(x: K.slabOffset.width, y: K.slabOffset.height)
    let device = try padDevice(e, spec: K.spec, centre: K.centre, yaw: 0, t: t, fetch: fetch,
                               layers: [MiniLayer(name: base)], overlay: screen)
    return AnyView(ZStack {
        slab
        device
    }.canvas())
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
                           sheet: try e.f.crop("derived/E2sheet", CGRect(origin: .zero, size: K.sheetRegion.size), scale: K.k * 1.03), size: size, t: t)
    let group = try keysGroup(e, t: t, screen: any(screen), base: "stills/E0-te-empty", fetch: 1.03,
                              escPress: KeyPress060(down: K.esc, up: K.esc + 0.3), pressed: K.pressed)
    var esc = LineSpec(words: Copy060.esc, .T4, x: 128, baseline: 588, align: .leading, snap: 39.25, holdEnd: 40.8)
    // v3's "haptic" buzz on "Esc" as the key goes down (0.3 s).
    esc.jitter = (word: 0, start: 39.30, duration: 0.3, amplitude: 3)
    let lines = [leftLine(Copy060.attach, .T1c, baseline: 400, snap: 36.85, end: 40.8),
                 leftLine(Copy060.justType, .T1c, baseline: 504, snap: 37.65, end: 40.8),
                 esc,
                 leftLine(Copy060.escFoot, .T3, baseline: 640, snap: 36.90, end: 40.8, cascade: false)]
    // The iPad and its keyboard 8 % smaller about x 1517, which keeps the iPad's left edge where the review's fix put it
    // (x 1034, 80 px or more from "Attach a keyboard.": `clearance`), then a 2 % push about that edge, so it drifts away
    // from the words and the slab's near right corner stays inside the frame to the end (0.95 about x 1900 left that
    // corner on the frame's edge at 36.8 and about 18 px past it by 40.8).
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: CGPoint(x: 1450, y: 520))
        Flat060.moving(group, rest: .scaling(0.92, about: CGPoint(x: 1517, y: 520)), CGAffineTransform.scaling(0.92, about: CGPoint(x: 1517, y: 520))
            .concatenating(.push(1 + 0.02 * CGFloat(ramp(t, 36.8, 40.8)), about: CGPoint(x: 1030, y: 520))), region: Keys060.region)
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

enum Scroll060 {
    /// One scroll, in the document's px: the two fingers' speed rises over 0.1 s (smoothstep) to `v0` and holds until they
    /// lift; the content then coasts, its speed falling by e every 0.12 s, and stops once it is under `cutoff` (20 px/s on
    /// the canvas, in document px), with no sub-pixel creep.
    struct Fling { let start: Double; let lift: Double; let v0: Double; let cutoff: Double }
    static let rise = 0.1, tau = 0.12
    /// While the fingers are down: how far the content has gone.
    static func fingers(_ f: Fling, _ t: Double) -> Double {
        let u = min(max(t, f.start), f.lift) - f.start
        if u < rise { let x = u / rise; return f.v0 * rise * (x * x * x - x * x * x * x / 2) }
        return f.v0 * (rise / 2 + (u - rise))
    }
    static func distance(_ f: Fling, _ t: Double) -> Double {
        guard t > f.start else { return 0 }
        if t <= f.lift { return fingers(f, t) }
        let stop = tau * log(f.v0 / f.cutoff)
        let u = min(t - f.lift, stop)
        return fingers(f, f.lift) + f.v0 * tau * (1 - exp(-u / tau))
    }

    // v5, Noah on v4.2 at 0:41: "Needs to be reshot with the scrolling happening on the trackpad in portrait mode. The text
    // should read - "Two-finger scroll. Or use a mouse wheel." as the trackpad is touched to show scrolling. Next line -
    // "Hardware mouse and trackpad support including Magic Keyboard for iPad." cutting to a magic keyboard like object and
    // highlighting the trackpad, with 2 finger indicators to show the scrolling motion. Next line - "And choose your
    // direction with Reverse Scrolling."" Three parts, two cuts on beats: the iPad upright (40.8–42.4), the keyboard (42.4–44.4),
    // the iPad upright again with Reverse Scrolling (44.4–47.2).
    static let partB = 42.4, partC = 44.4, end = 47.2

    // MARK: The iPad upright (A, C): the footage's E3u–E7u (1488×2266 px, the portrait halves, `-SillLayout 744x1133`)

    static let upright = DeviceSpec.miniM45.turnedUpright
    /// Its centre: its outer left edge at x 1194.5, 83 px or more from "Or use a mouse wheel." (T1c, x 128).
    static let uprightCentre = CGPoint(x: 1520, y: 540)
    static let uprightSource = CGSize(width: 1488, height: 2266)
    static var ku: CGFloat { upright.interior.width / uprightSource.width }
    /// The streamed window (2880×1800) in the still: (16, 112, 1456, 910), 0.505556 still px a picture px.
    static let uprightPicture = CGRect(x: 16, y: 112, width: 1456, height: 910)
    /// 20 canvas px/s in document px (0.505556 still px × ku a document px).
    static var uprightCutoff: Double { 20 / Double(0.505556 * ku) }
    /// Two fingers on the on-screen trackpad (x 28–1459, y 1450–2221), 170 px apart: up, the content up with them
    /// (natural, as Sill's trackpad scrolls by default), 518 px of the document with its coast.
    static var flingA: Fling { Fling(start: 41.0, lift: 41.3, v0: 1400, cutoff: uprightCutoff) }
    /// After Reverse Scrolling: the same stroke, the content the other way, 380 px back.
    static var flingC: Fling { Fling(start: 45.9, lift: 46.15, v0: 1150, cutoff: uprightCutoff) }
    static func uprightOffset(_ t: Double) -> Double { distance(flingA, t) - distance(flingC, t) }
    static let fingersFrom = [CGPoint(x: 659, y: 1960), CGPoint(x: 829, y: 1960)]
    /// The fingers move as far on the pad as the content does in the picture, up, both strokes.
    static func fingerTravel(_ t: Double, _ f: Fling) -> CGFloat { CGFloat(fingers(f, t)) * 0.505556 }
    /// Sill's own pointer: the trackpad's scroll shows this device's arrow where its cursor is (the footage's E3u-pointer: the
    /// frame's middle, its tip at (744, 567)); it comes with the first touch and stays.
    static let arrowTip = CGPoint(x: 744, y: 567)
    static func arrowAlpha(_ t: Double) -> Double { ramp(t, flingA.start - 0.06, flingA.start) }
    /// Settings, Reverse Scrolling and Done (C): the bar's Settings button (x 1342–1449, y 1178–1293), the panel (E6u, E7u:
    /// (740, 1334, 720, 888)), the switch (centre (1344.5, 1572.5)), Done (1382, 1380).
    static let settingsTap = 44.55, panel = 44.6, flip = 45.05, done = 45.45
    static let settingsButton = CGRect(x: 1338, y: 1174, width: 116, height: 124)
    static let uprightPanel = CGRect(x: 740, y: 1334, width: 720, height: 888)
    static let settingsPoint = CGPoint(x: 1395.5, y: 1235.5), flipPoint = CGPoint(x: 1344.5, y: 1572.5), donePoint = CGPoint(x: 1382, y: 1380)
    /// The iPad's push in each part, 2 % about its left edge, so it grows away from the words.
    static func uprightPush(_ t: Double) -> CGFloat {
        t < partB ? 1 + 0.02 * CGFloat(ramp(t, 40.8, partB)) : 1 + 0.02 * CGFloat(ramp(t, partC, end))
    }
    static let uprightAbout = CGPoint(x: 1194.5, y: 540)

    // MARK: The keyboard (B): the iPad (landscape, E3 over longdoc-page) standing behind the slab, its trackpad lit

    /// The group drawn as S11's (Keys060), at 0.70 about its middle and 120 px right, so it stays clear of the words.
    static let keysRest = CGAffineTransform.scaling(0.70, about: CGPoint(x: 1430, y: 540)).concatenating(CGAffineTransform(translationX: 122, y: 18))
    static let keysPitch = 50.0
    /// The trackpad lights from 42.5 (0.2 s); two fingers land at 42.75 and scroll up (the document up with them: a
    /// trackpad's own Natural Scrolling), lift, land again and scroll back down.
    static let highlight = 42.5
    static var flingB1: Fling { Fling(start: 42.8, lift: 43.05, v0: 1500, cutoff: 20 / Double(0.7132 * Keys060.k * 0.70)) }
    static var flingB2: Fling { Fling(start: 43.45, lift: 43.65, v0: 900, cutoff: 20 / Double(0.7132 * Keys060.k * 0.70)) }
    static func keysOffset(_ t: Double) -> Double { distance(flingB1, t) - distance(flingB2, t) }
    /// The fingers on the trackpad (its unit square): 0.36 apart, from 0.72 down; up by a fifth of the content's travel
    /// over the trackpad's height of 1,000 document px, down again.
    static func keysFingers(_ t: Double) -> [(point: CGPoint, opacity: Double, scale: CGFloat)] {
        func finger(_ f: Fling, _ y0: CGFloat, _ sign: CGFloat) -> CGFloat { y0 - sign * CGFloat(fingers(f, t)) / 1000 * 0.62 }
        var out: [(point: CGPoint, opacity: Double, scale: CGFloat)] = []
        for (f, y0, sign) in [(flingB1, CGFloat(0.74), CGFloat(1)), (flingB2, CGFloat(0.30), CGFloat(-1))] {
            let appear = f.start - 0.08
            guard t >= appear, t < f.lift + 0.25 else { continue }
            let a = t <= f.lift ? ramp(t, appear, appear + 0.12) : 1 - ramp(t, f.lift, f.lift + 0.25)
            let s = 0.7 + 0.3 * CGFloat(ease(t, appear, 0.12, .appleOut))
            let y = finger(f, y0, sign)
            out.append((CGPoint(x: 0.32, y: y), a, s)); out.append((CGPoint(x: 0.68, y: y), a, s))
        }
        return out
    }
    /// iPadOS's round pointer over the text: a trackpad's two-finger scroll moves no pointer.
    static let roundPointer = CGPoint(x: 1260, y: 820)
}

/// The upright stills' px for a rect of the streamed window (2880×1800).
func uprightPicRect(_ r: CGRect) -> CGRect {
    let s = Scroll060.uprightPicture.width / 2880, o = Scroll060.uprightPicture.origin
    return CGRect(x: o.x + r.minX * s, y: o.y + r.minY * s, width: r.width * s, height: r.height * s)
}

/// The long document scrolled in TextEdit (its chrome is the still's; the page, longdoc-page, drawn over the document's
/// area), its scroller, and a pointer, in a screen's interior px: `pic` maps the window's px to the still's, `k` is
/// interior px per still px, `off` the document's offset (document px). The page moves on its exact path (ExactPicture060).
struct ScrollDoc060: View {
    enum Pointer { case none, round(CGPoint, Double), arrow(CGPoint, Double) }
    let page: CGImage
    let k: CGFloat
    let off: Double
    var pic: (CGRect) -> CGRect = picRect
    var pointer: Pointer = .none
    var body: some View {
        let off = CGFloat(self.off)
        // The document's area in the picture: below the format bar (y 188), the page drawn from y 188 − off.
        let doc = scaledRect(pic(CGRect(x: 0, y: 188, width: 2880, height: 1612)), k)
        let s = doc.width / 2880
        let pageH = CGFloat(page.height) * s
        let bar = scaledRect(pic(CGRect(x: 2880 - 26, y: 188 + 20 + off / 4200 * 1612, width: 14, height: 1612 * 1612 / 4200)), k)
        return ZStack(alignment: .topLeading) {
            ExactPicture060(image: page, transform: CGAffineTransform(scaleX: doc.width / CGFloat(page.width), y: pageH / CGFloat(page.height))
                .concatenating(CGAffineTransform(translationX: doc.minX, y: doc.minY - off * s)), size: CGSize(width: doc.maxX, height: doc.maxY + 40), extend: true)
                .mask(Path(doc).fill(Color.white))
            Path(roundedRect: bar, cornerRadius: bar.width / 2).fill(Color.black.opacity(0.35))
            switch pointer {
            case .none: EmptyView()
            case .round(let p, let alpha) where alpha > 0.002:
                let pc = scaledRect(pic(CGRect(x: p.x, y: p.y, width: 0, height: 0)), k).origin
                let d = 38 * k * 1.4
                Circle().fill(Color(white: 0.32, opacity: 0.55))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: max(1, 0.6 * k * 1.4)))
                    .frame(width: d, height: d)
                    .opacity(alpha)
                    .transformEffect(CGAffineTransform(translationX: pc.x - d / 2, y: pc.y - d / 2))
            case .arrow(let tip, let alpha) where alpha > 0.002:
                SillArrow060(tip: CGPoint(x: tip.x * k, y: tip.y * k), height: 44 * k).opacity(alpha)
            default: EmptyView()
            }
        }
        .frame(width: doc.maxX, height: doc.maxY + 40, alignment: .topLeading)
    }
}

/// Sill's own pointer, as the upright layouts draw it over the picture for the trackpad (the footage's E3u-pointer: the
/// Mac's arrow, white with a dark edge): a shape, at its exact place.
struct SillArrow060: View {
    let tip: CGPoint
    let height: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let u = height / 25
            var p = Path()
            let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 20.2), (4.6, 15.8), (7.6, 22.8), (10.6, 21.5), (7.7, 14.7), (14.2, 14.7)]
            for (i, q) in pts.enumerated() {
                let pt = CGPoint(x: tip.x + q.0 * u, y: tip.y + q.1 * u)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            ctx.stroke(p, with: .color(Color.black.opacity(0.92)), style: StrokeStyle(lineWidth: 2.4 * u, lineJoin: .round))
            ctx.fill(p, with: .color(.white))
        }
    }
}

// SWAP-IN (S12, take E part 2): replace with Noah's clip E if provided at /Users/noah/Downloads/sill-handoff/release-060/captures/take-E.mov (its scrolling parts), in place of the
// upright iPad's ScrollDoc060 (E3u and longdoc-page) and the keyboard's iPad. Marks: two fingers on the on-screen trackpad
// 41.0–41.3 (the document up 518 px with its coast); the keyboard 42.4–44.4, fingers 42.8–43.05 and 43.45–43.65; Settings
// 44.55, Reverse Scrolling on 45.05, Done 45.45; the fingers again 45.9–46.15, the document the other way.
@MainActor func s060_12(_ t: Double, _ e: Env) throws -> FrameLayers {
    let S = Scroll060.self
    let page = try e.f.image("pictures/longdoc-page")
    var lines = [leftLine(Copy060.scroll, .T1c, baseline: 400, snap: 40.85, end: S.end),
                 leftLine(Copy060.wheel, .T1c, baseline: 504, snap: 41.25, end: S.end)]
    lines += capped([leftLine(Copy060.hardware[0], .T2, baseline: 578, snap: 42.45, end: S.end),
                     leftLine(Copy060.hardware[1], .T2, baseline: 620, snap: 42.70, end: S.end)])
    lines.append(leftLine(Copy060.reverse, .T2, baseline: 688, snap: 44.45, end: S.end))
    let picture: AnyView
    var glow = CGPoint(x: 1520, y: 540)
    if t < S.partB || t >= S.partC {
        // The iPad upright: E3u's chrome, the document scrolled over its picture, Sill's arrow, the fingers on the trackpad;
        // Settings over the key row and trackpad in C.
        let spec = S.upright, size = spec.interior, k = S.ku
        let off = S.uprightOffset(t)
        var screen = AnyView(ScrollDoc060(page: page, k: k, off: off, pic: uprightPicRect, pointer: .arrow(S.arrowTip, S.arrowAlpha(t))))
        if t >= S.partC {
            let panelIn = ease(t, S.panel, 0.25, .appleOut) * (1 - ease(t, S.done + 0.02, 0.2, .appleIn))
            let panelRect = scaledRect(S.uprightPanel, k)
            let off6 = try e.f.crop("stills/E6u-reverse-off-upright", S.uprightPanel, scale: k * 1.03)
            let on7 = try e.f.crop("stills/E7u-reverse-on-upright", S.uprightPanel, scale: k * 1.03)
            let button = try e.f.crop("stills/E6u-reverse-off-upright", S.settingsButton, scale: k * 1.03)
            let move = CGAffineTransform.scaling(0.94 + 0.06 * CGFloat(panelIn), about: CGPoint(x: panelRect.maxX, y: panelRect.minY))
            screen = AnyView(ZStack(alignment: .topLeading) {
                screen
                if t >= S.settingsTap && panelIn > 0.002 {
                    image(button, in: scaledRect(S.settingsButton, k)).opacity(min(1, 4 * panelIn))
                    ZStack(alignment: .topLeading) {
                        ExactPicture060(image: off6, transform: placing(off6, in: panelRect).concatenating(move), size: size)
                        ExactPicture060(image: on7, transform: placing(on7, in: panelRect).concatenating(move), size: size)
                            .opacity(ramp(t, S.flip + 0.03, S.flip + 0.15))
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .opacity(panelIn)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading))
        }
        // The two fingers on the on-screen trackpad (touch dots in the still's px), up with each stroke.
        let fling = t < S.partB ? S.flingA : S.flingC
        var dots = (0..<2).map { i in
            TouchDotSpec(at: fling.start, point: .zero, interiorWidth: S.uprightSource.width, drag: (fling.start, fling.lift, { t in
                CGPoint(x: S.fingersFrom[i].x, y: S.fingersFrom[i].y - S.fingerTravel(t, fling))
            }))
        }
        if t >= S.partC {
            dots += [Device060.dot(at: S.settingsTap, S.settingsPoint, source: S.uprightSource), Device060.dot(at: S.flip, S.flipPoint, source: S.uprightSource),
                     Device060.dot(at: S.done, S.donePoint, source: S.uprightSource)]
        }
        let base = try e.f.scaled("stills/E3u-longdoc0-upright", width: size.width * 1.03)
        let device = PlacedDevice(spec: spec, center: S.uprightCentre, yaw: 0) {
            MiniScreen(size: size, layers: [(base, MiniLayer(name: "stills/E3u-longdoc0-upright"))], dots: dots, t: t) { screen }
        }
        picture = Flat060.moving(device, .push(S.uprightPush(t), about: S.uprightAbout), region: Flat060.region(spec, center: S.uprightCentre))
    } else {
        // The keyboard: S11's iPad (E3 over longdoc-page, iPadOS's round pointer over the text) standing behind the slab, now
        // with its palm rest and trackpad, lit in the accent; two fingers scroll on it, the document with them.
        let K = Keys060.self
        let size = K.spec.interior
        let screen = ScrollDoc060(page: page, k: K.k, off: S.keysOffset(t), pointer: .round(S.roundPointer, 1))
        let base = try e.f.scaled("stills/E3-longdoc0", width: size.width * 1.3)
        let device = PlacedDevice(spec: K.spec, center: K.centre, yaw: 0) {
            MiniScreen(size: size, layers: [(base, MiniLayer(name: "stills/E3-longdoc0"))], t: t) { screen }
        }
        let h = KeyboardSlab060.height(width: K.slabWidth, trackpad: true)
        let slab = KeyboardSlab060(width: K.slabWidth, origin: CGPoint(x: 960 - K.slabWidth / 2, y: 540 - h / 2), t: t,
                                   trackpad: SlabTrackpad060(highlight: ease(t, S.highlight, 0.2, .appleOut), fingers: S.keysFingers(t)))
            .modifier(Tilt(yaw: 0, pitch: S.keysPitch)).offset(x: K.slabOffset.width, y: K.slabOffset.height + 60)
        let group = ZStack { slab; device }.canvas()
        let push = CGAffineTransform.scaling(1 + 0.02 * CGFloat(ramp(t, S.partB, S.partC)), about: CGPoint(x: 1240, y: 540))
        picture = Flat060.moving(group, rest: S.keysRest, S.keysRest.concatenating(push), region: CGRect(x: 700, y: -160, width: 1460, height: 1400))
        glow = CGPoint(x: 1545, y: 520)
    }
    let v = ZStack {
        Backdrop(glow: 0.06, glowCenter: glow)
        picture
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
        Flat060.moving(device, .push(1 + 0.07 * CGFloat(CubicBezier.inOut(ramp(t, 44.0, 48.8))), about: about), region: Flat060.region(L.spec, center: L.centre))
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
        Flat060.moving(MacroView(spec: m, image: img) { EmptyView() }, CGAffineTransform(translationX: -6 * CGFloat(t - 48.8), y: 0)
            .concatenating(.push(1 + 0.02 * CGFloat(ramp(t, 48.8, 52.8)), about: T.centre)), region: Flat060.region(m))
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
        Flat060.moving(MacroView(spec: m, image: img) { EmptyView() }, .push(1 + 0.015 * CGFloat(ramp(t, 52.8, 56.0)), about: A.centre),
                       region: Flat060.region(m))
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
    // The row on its exact path (ExactPicture060), inside its corners (a shape at its fractional place).
    let rowRect = CGRect(x: H.rowCentre.x - H.rowRect.width / 2, y: H.rowCentre.y - H.rowRect.height / 2 + 40 * CGFloat(1 - p),
                         width: H.rowRect.width, height: H.rowRect.height)
    let rowView = ExactPicture060(image: row, transform: placing(row, in: rowRect), extend: true)
        .mask(Path(roundedRect: rowRect, cornerRadius: 22, style: .continuous).fill(Color.white).canvas())
        .opacity(p)
    let push = 1 + 0.02 * CGFloat(ramp(t, 56.0, 59.2))
    let lines = [LineSpec(Copy060.hold, .T1c, x: 1060, baseline: 470, align: .leading, snap: 56.05, holdEnd: 59.2),
                 LineSpec(Copy060.halfSecond, .T4, x: 1060, baseline: 556, align: .leading, snap: 56.95, holdEnd: 59.2),
                 LineSpec(Copy060.holdFoot, .T3, x: 1060, baseline: 616, align: .leading, snap: 58.05, holdEnd: 59.2, cascade: false)]
    let v = ZStack {
        Backdrop(glow: 0.05, glowCenter: H.centre)
        // The macro on its exact path (Flat060); the ring, a shape, under the same push.
        Flat060.moving(MacroView(spec: m, image: img) { EmptyView() }, .push(push, about: thumb), region: Flat060.region(m))
        ring.canvas().scaled(push, about: thumb)
        if t >= H.row { rowView }
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}
