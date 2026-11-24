// Device.swift — generic drawn device frames (§3.3), macro crops, the glow, the sill line, touch dots.
// Never Apple artwork: a rounded rect, a rim, a gloss. No camera dot (Noah, 2026-09-26: plain bezels on every device).
import CoreImage
import SwiftUI

struct DeviceSpec {
    var interior: CGSize
    var bezel: CGFloat
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var portrait = false
    var outer: CGSize { CGSize(width: interior.width + 2 * bezel, height: interior.height + 2 * bezel) }
    /// Screen px per interior (clip) px.
    var clipScale: CGFloat { interior.width / (portrait ? 1420 : 2000) }

    static let H = DeviceSpec(interior: CGSize(width: 1280, height: 909), bezel: 38, innerRadius: 30, outerRadius: 68)
    static let M = DeviceSpec(interior: CGSize(width: 1000, height: 710), bezel: 30, innerRadius: 24, outerRadius: 54)
    static let M45 = DeviceSpec(interior: CGSize(width: 900, height: 639), bezel: 30, innerRadius: 24, outerRadius: 54)
    static let S = DeviceSpec(interior: CGSize(width: 600, height: 426), bezel: 18, innerRadius: 14, outerRadius: 32)
    static let P = DeviceSpec(interior: CGSize(width: 795, height: 1120), bezel: 30, innerRadius: 24, outerRadius: 54, portrait: true)
    /// v2 final: H at 0.60 of the interior (H is 0.64), for the software-encoded clip 12 (S16): 1,272 px wide
    /// outside, 66 % of the frame, 68 % at the end of its 3 % push.
    static let H60 = DeviceSpec(interior: CGSize(width: 1200, height: 852), bezel: 36, innerRadius: 28, outerRadius: 64)
}

// MARK: - Pre-rendered shadows (§3.3: #000 at 60 %, radius 70, y +48)

final class ShadowCache {
    static let shared = ShadowCache()
    var ci: CIContext!
    private var cache: [String: CGImage] = [:]
    static let pad: CGFloat = 200

    /// A blurred rounded rect the size of `outer`, padded by `pad` on every side (offset not applied).
    func image(outer: CGSize, radius: CGFloat, opacity: CGFloat = 0.6, blurRadius: CGFloat = 70) -> CGImage {
        let key = "\(outer)|\(radius)|\(opacity)|\(blurRadius)"
        if let c = cache[key] { return c }
        let pad = ShadowCache.pad
        let w = Int(outer.width + 2 * pad), h = Int(outer.height + 2 * pad)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: pad, y: pad, width: outer.width, height: outer.height)
        ctx.addPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath)
        ctx.setFillColor(CGColor(gray: 0, alpha: opacity))
        ctx.fillPath()
        let img = CIImage(cgImage: ctx.makeImage()!)
        // A layer shadow's radius is about 2σ.
        let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: Double(blurRadius) / 2)
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let cg = ci.createCGImage(blurred, from: blurred.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        cache[key] = cg
        return cg
    }
}

// MARK: - The device

struct DeviceView<Content: View>: View {
    let spec: DeviceSpec
    var shadow = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        let o = spec.outer
        ZStack(alignment: .topLeading) {
            if shadow {
                Image(decorative: ShadowCache.shared.image(outer: o, radius: spec.outerRadius), scale: 1)
                    .frame(width: o.width + 2 * ShadowCache.pad, height: o.height + 2 * ShadowCache.pad)
                    .offset(x: -ShadowCache.pad, y: -ShadowCache.pad + 48)
            }
            RoundedRectangle(cornerRadius: spec.outerRadius, style: .continuous)
                .fill(Color(hex: Palette.deviceBody))
                .frame(width: o.width, height: o.height)
            ZStack(alignment: .topLeading) {
                content()
                // Glass gloss: white 6 % → 0 over the top-left third.
                LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                               startPoint: .topLeading, endPoint: UnitPoint(x: 1.0 / 3, y: 1.0 / 3))
            }
            .frame(width: spec.interior.width, height: spec.interior.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: spec.innerRadius, style: .continuous))
            .offset(x: spec.bezel, y: spec.bezel)
            // v3: no camera dot (Noah, 2026-09-26): the bezel is plain.
            RoundedRectangle(cornerRadius: spec.outerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .frame(width: o.width, height: o.height)
        }
        .frame(width: o.width, height: o.height, alignment: .topLeading)
    }
}

/// The screen content: a clip image filling the interior, plus overlays in interior-px coordinates.
struct ClipScreen: View {
    let image: CGImage?
    let size: CGSize
    var dots: [TouchDotSpec] = []
    var t: Double = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
            }
            ForEach(0..<dots.count, id: \.self) { i in
                TouchDot(spec: dots[i], t: t, clipScale: size.width / dots[i].interiorWidth)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - Touch dots (§3.5, §7.1: only where a finger really touched)

struct TouchDotSpec {
    var at: Double                 // reel time of the touch
    var point: CGPoint             // interior px
    var hold: (start: Double, end: Double)? = nil   // hold variant: finger down over this reel range
    var interiorWidth: CGFloat = 2000
    /// v2 final, drag variant (S18): the finger is down over `down…up` (reel time) and at `point(t)` (interior
    /// px) in between: the logged path of a real stroke. No ring; it fades in and out like a tap.
    var drag: (down: Double, up: Double, point: (Double) -> CGPoint)? = nil
}

struct TouchDot: View {
    let spec: TouchDotSpec
    let t: Double
    let clipScale: CGFloat        // screen px per interior px at the device's base size

    var body: some View {
        if let drag = spec.drag { return AnyView(dragBody(drag)) }
        return AnyView(tapBody)
    }

    /// The drag variant: the same disc and ring, following the finger; in over 0.12 s from 0.08 s before the
    /// touch (as a tap), out over 0.25 s after the lift. Fourth cut: a lighter disc and ring (fill 12 %, ring
    /// 32 %; a tap's are 18 % and 45 %). A drag's dot stays up for the whole shot, and at a tap's weight it drew
    /// the eye away from what it drives (S18: the pointer).
    private func dragBody(_ drag: (down: Double, up: Double, point: (Double) -> CGPoint)) -> some View {
        let d = 128 * clipScale
        let appear = drag.down - 0.08
        let s = t < appear ? 0.7 : 0.7 + 0.3 * ease(t, appear, 0.12, .appleOut)
        let alpha = t < appear ? 0 : (t <= drag.up ? 1 : 1 - ramp(t, drag.up, drag.up + 0.25))
        let p = drag.point(min(max(t, drag.down), drag.up))
        return ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1.5 * max(1, clipScale / 0.5))
        }
        .frame(width: d, height: d)
        .scaleEffect(s)
        .opacity(alpha)
        .offset(x: p.x * clipScale - d / 2, y: p.y * clipScale - d / 2)
    }

    private var tapBody: some View {
        // 64 pt on the device (128 interior px): 64 px at M size, "scaled with the shot".
        let d = 128 * clipScale
        let appear = spec.at - 0.08
        let s = t < appear ? 0.7 : 0.7 + 0.3 * ease(t, appear, 0.12, .appleOut)
        var alpha = t < appear ? 0 : 1.0
        var ring = 0.0
        if let hold = spec.hold {
            ring = ease(t, hold.start, 0.6, .inOut)
            if t > hold.end { alpha = 1 - ramp(t, hold.end, hold.end + 0.25) }
        } else {
            alpha *= 1 - ramp(t, appear + 0.12, appear + 0.12 + 0.25)
        }
        return ZStack {
            Circle().fill(Color.white.opacity(0.18))
            Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5 * max(1, clipScale / 0.5))
            if spec.hold != nil, ring > 0 {
                Circle().trim(from: 0, to: ring)
                    .stroke(Color(hex: Palette.accent), style: StrokeStyle(lineWidth: 3 * max(1, clipScale / 0.5), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-4 * max(1, clipScale / 0.5))
            }
        }
        .frame(width: d, height: d)
        .scaleEffect(s)
        .opacity(alpha)
        .offset(x: spec.point.x * clipScale - d / 2, y: spec.point.y * clipScale - d / 2)
    }
}

// MARK: - Glow and the sill line

struct Glow: View {
    var center: CGPoint = CGPoint(x: 960, y: 540)
    var opacity: Double = 0.06
    var radius: CGFloat = 900
    var body: some View {
        RadialGradient(colors: [Color(hex: Palette.accent, alpha: opacity), Color(hex: Palette.accent, alpha: 0)],
                       center: UnitPoint(x: center.x / Stage.size.width, y: center.y / Stage.size.height),
                       startRadius: 0, endRadius: radius)
            .frame(width: Stage.size.width, height: Stage.size.height)
    }
}

/// §3.4: 2 px, core 35 % over the middle 60 % fading to 0 at both ends, a 14 px Gaussian copy at 12 %.
struct SillLine: View {
    var y: CGFloat
    var length: CGFloat
    var centerX: CGFloat = 960
    var opacity: Double = 1
    var body: some View {
        let stops: [Gradient.Stop] = [
            .init(color: Color(hex: Palette.accent, alpha: 0), location: 0),
            .init(color: Color(hex: Palette.accent, alpha: 1), location: 0.2),
            .init(color: Color(hex: Palette.accent, alpha: 1), location: 0.8),
            .init(color: Color(hex: Palette.accent, alpha: 0), location: 1),
        ]
        let grad = LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Stage.size.width, height: Stage.size.height)
            if length > 0.5 {
                Rectangle().fill(grad).frame(width: length, height: 6).blur(radius: 14).opacity(0.12)
                    .offset(x: centerX - length / 2, y: y - 3)
                Rectangle().fill(grad).frame(width: length, height: 2).opacity(0.35)
                    .offset(x: centerX - length / 2, y: y - 1)
            }
        }
        .opacity(opacity)
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
}

// MARK: - Macro crops (stack M)

struct MacroSpec {
    var crop: CGRect                 // interior px
    var scale: CGFloat               // screen px per interior px
    var center: CGPoint? = nil       // screen centre of the crop, or…
    var origin: CGPoint? = nil       // …screen position of the crop's top-left
    var feather: CGFloat = 70        // screen px, on edges that cut through the interior
    var hardEdges: Set<Edge> = []
    var interior = CGSize(width: 2000, height: 1420)

    var screenOrigin: CGPoint {
        if let origin { return origin }
        let c = center ?? CGPoint(x: 960, y: 540)
        return CGPoint(x: c.x - crop.width * scale / 2, y: c.y - crop.height * scale / 2)
    }
    var bezel: CGFloat { 30 * scale }
    var innerRadius: CGFloat { 48 * scale }
    /// Which crop edges lie on the interior's boundary (there the device's bezel is drawn).
    func onDevice(_ e: Edge) -> Bool {
        switch e {
        case .leading: return crop.minX <= 0.5
        case .top: return crop.minY <= 0.5
        case .trailing: return crop.maxX >= interior.width - 0.5
        case .bottom: return crop.maxY >= interior.height - 0.5
        }
    }
    func featherOf(_ e: Edge) -> CGFloat { onDevice(e) || hardEdges.contains(e) ? 0 : feather }
    /// The interior sub-rect to fetch: the crop plus room for the feathers (clamped to the interior).
    var fetchRect: CGRect {
        let l = featherOf(.leading) / scale, r = featherOf(.trailing) / scale
        let t = featherOf(.top) / scale, b = featherOf(.bottom) / scale
        let x0 = max(0, crop.minX - l), y0 = max(0, crop.minY - t)
        let x1 = min(interior.width, crop.maxX + r), y1 = min(interior.height, crop.maxY + b)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).integral
    }
}

/// A partial device: the crop at scale, the bezel (and its rounded corner) where the crop meets the
/// interior's edge, and soft edges where it cuts through the picture.
struct MacroView<Overlay: View>: View {
    let spec: MacroSpec
    let image: CGImage?              // the interior sub-rect `spec.fetchRect`, already at `spec.scale`
    @ViewBuilder var overlay: () -> Overlay   // drawn in interior-px space scaled by spec.scale, origin = interior (0,0)

    var body: some View {
        let s = spec.scale
        let o = spec.screenOrigin
        // Device-local frame: interior (0,0) at `deviceOrigin` on screen.
        let deviceOrigin = CGPoint(x: o.x - spec.crop.minX * s, y: o.y - spec.crop.minY * s)
        let iw = spec.interior.width * s, ih = spec.interior.height * s
        let bz = spec.bezel
        let f = spec.fetchRect
        // Visible rect in screen coords, with feather bands outside the crop on cut edges.
        let vis = CGRect(x: o.x - (spec.onDevice(.leading) ? bz + 2 : spec.featherOf(.leading)),
                         y: o.y - (spec.onDevice(.top) ? bz + 2 : spec.featherOf(.top)),
                         width: 0, height: 0)
        let visMaxX = o.x + spec.crop.width * s + (spec.onDevice(.trailing) ? bz + 2 : spec.featherOf(.trailing))
        let visMaxY = o.y + spec.crop.height * s + (spec.onDevice(.bottom) ? bz + 2 : spec.featherOf(.bottom))
        let visRect = CGRect(x: vis.minX, y: vis.minY, width: visMaxX - vis.minX, height: visMaxY - vis.minY)

        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Stage.size.width, height: Stage.size.height)
            ZStack(alignment: .topLeading) {
                // Body with its rim, outer rounded corners.
                RoundedRectangle(cornerRadius: spec.innerRadius + bz, style: .continuous)
                    .fill(Color(hex: Palette.deviceBody))
                    .frame(width: iw + 2 * bz, height: ih + 2 * bz)
                ZStack(alignment: .topLeading) {
                    Color.black
                    if let image {
                        Image(decorative: image, scale: 1).resizable().interpolation(.high)
                            .frame(width: f.width * s, height: f.height * s)
                            .offset(x: f.minX * s, y: f.minY * s)
                    }
                    overlay()
                    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                                   startPoint: .topLeading, endPoint: UnitPoint(x: 1.0 / 3, y: 1.0 / 3))
                }
                .frame(width: iw, height: ih, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: spec.innerRadius, style: .continuous))
                .offset(x: bz, y: bz)
                // v3: no camera dot (Noah, 2026-09-26): the bezel is plain.
                RoundedRectangle(cornerRadius: spec.innerRadius + bz, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color(hex: Palette.rimLight), Color(hex: Palette.rimDark)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5 * max(1, s / 0.5))
                    .frame(width: iw + 2 * bz, height: ih + 2 * bz)
            }
            .frame(width: iw + 2 * bz, height: ih + 2 * bz, alignment: .topLeading)
            .offset(x: deviceOrigin.x - bz, y: deviceOrigin.y - bz)
        }
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
        .mask(FeatherMask(rect: visRect, l: spec.featherOf(.leading), t: spec.featherOf(.top),
                          r: spec.featherOf(.trailing), b: spec.featherOf(.bottom)))
    }
}

/// White inside `rect`; each edge fades to 0 over its own width, measured inward from the rect's edge.
struct FeatherMask: View {
    let rect: CGRect
    let l, t, r, b: CGFloat
    var body: some View {
        let w = max(rect.width, 1), h = max(rect.height, 1)
        let hStops: [Gradient.Stop] = [
            .init(color: .white.opacity(l > 0 ? 0 : 1), location: 0),
            .init(color: .white, location: min(0.49, l / w)),
            .init(color: .white, location: max(0.51, 1 - r / w)),
            .init(color: .white.opacity(r > 0 ? 0 : 1), location: 1),
        ]
        let vStops: [Gradient.Stop] = [
            .init(color: .white.opacity(t > 0 ? 0 : 1), location: 0),
            .init(color: .white, location: min(0.49, t / h)),
            .init(color: .white, location: max(0.51, 1 - b / h)),
            .init(color: .white.opacity(b > 0 ? 0 : 1), location: 1),
        ]
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: Stage.size.width, height: Stage.size.height)
            LinearGradient(stops: hStops, startPoint: .leading, endPoint: .trailing)
                .mask(LinearGradient(stops: vStops, startPoint: .top, endPoint: .bottom))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
}
