// V3.swift — the third reel's new beats (SHOTLIST-v3): the connection-methods beat re-shot on the current
// client (S24), "Or remote, through your own VPN." with a Remote row (S25), the pairing moment (S26) and the
// panel's "Connected through Tailscale" line (S27). Every picture here is a still: harness screenshots of the
// iOS client at 8b0d418 (mock data, private simulator, no network) and the Mac app's own preview renders at
// 8b0d418 (-SillRenderPreviews, no host). The renderer animates between them; nothing is recorded.
import AppKit
import CoreImage
import CoreText
import SwiftUI

let v3Dir = reelDir.appendingPathComponent("v3")

/// Act IV moved 5 bars later: every v2 time from 57.6 on is 8.0 s later in v3.
enum ActIV { static let shift = 8.0 }

/// The harness screenshots (`W/v3/shots`, 2064×2752, the 1000×710 fake screen at file x 32, y 666).
enum V3Still: String, CaseIterable {
    case c0, c1, c2, c3, c4
    case addmac = "p-addmac", paired = "p-paired", panel = "s-remote"
    var url: URL { v3Dir.appendingPathComponent("shots/\(rawValue).png") }
}

/// The Mac's pairing window, as the bare SillMenuBar (8b0d418, recorded SDK 27.0) renders it, dark, 2×.
enum MacPreview: String, CaseIterable {
    case waiting = "pairing-waiting-dark", paired = "pairing-paired-dark"
    var url: URL { v3Dir.appendingPathComponent("mac-previews/\(rawValue).png") }
}

@MainActor final class V3Stills {
    let ci: CIContext
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private var interiors: [V3Still: CGImage] = [:]
    private var previews: [MacPreview: CGImage] = [:]
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []

    init(ci: CIContext) throws {
        self.ci = ci
        for s in V3Still.allCases {
            guard let img = loadStill(s.url, crop: interiorRect, ci: ci) else {
                throw NSError(domain: "V3", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(s.url.path)"])
            }
            interiors[s] = img
        }
        for p in MacPreview.allCases {
            guard let src = CGImageSourceCreateWithURL(p.url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "V3", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing \(p.url.path)"])
            }
            previews[p] = img
        }
    }

    private func remember(_ key: String, _ make: () -> CGImage) -> CGImage {
        if let hit = cache[key] { return hit }
        let img = make()
        cache[key] = img
        order.append(key)
        if order.count > 40 { cache[order.removeFirst()] = nil }
        return img
    }

    /// Lanczos-scales a CGImage (sRGB) by `scale`.
    private func scaled(_ img: CGImage, _ scale: CGFloat) -> CGImage {
        let w = (CGFloat(img.width) * scale).rounded(), h = (CGFloat(img.height) * scale).rounded()
        if abs(scale - 1) < 1e-4 { return img }
        let out = CIImage(cgImage: img).applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        return ci.createCGImage(out, from: CGRect(x: 0, y: 0, width: w, height: h), format: .BGRA8, colorSpace: srgb)!
    }

    /// The still's interior at a macro spec's fetch rect and scale, as `MacroView` expects it.
    func macroImage(_ s: V3Still, _ m: MacroSpec) -> CGImage {
        let f = m.fetchRect
        return remember("\(s.rawValue)|\(f)|\(String(format: "%.5f", m.scale))") {
            scaled(interiors[s]!.cropping(to: f)!, m.scale)
        }
    }

    /// The whole interior at `scale` (a device's screen).
    func interior(_ s: V3Still, scale: CGFloat) -> CGImage {
        remember("\(s.rawValue)|full|\(String(format: "%.5f", scale))") { scaled(interiors[s]!, scale) }
    }

    /// The pairing window as a Mac window at `scale` screen px per preview px: the preview (its content view)
    /// under a drawn title bar ("Pair iPhone or iPad", the window's title; close lit, minimize and zoom
    /// unavailable, as its style mask [.titled, .closable] has them), with rounded corners and a hairline rim.
    func macWindow(_ p: MacPreview, scale: CGFloat) -> CGImage {
        remember("win|\(p.rawValue)|\(String(format: "%.5f", scale))") {
            let content = scaled(previews[p]!, scale)
            let bar = (56 * scale).rounded()                    // 28 pt at 2×
            let w = content.width, h = content.height + Int(bar)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            let r = 24 * scale                                  // 12 pt corners
            let bounds = CGRect(x: 0, y: 0, width: w, height: h)
            ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.clip()
            // The title bar in the content's own background (read back in sRGB, so the two match exactly).
            var px = [UInt8](repeating: 0, count: 4)
            let probe = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            probe.draw(content.cropping(to: CGRect(x: 4, y: 4, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.setFillColor(CGColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1))
            ctx.fill(bounds)
            ctx.draw(content, in: CGRect(x: 0, y: 0, width: content.width, height: content.height))
            // Traffic lights: 12 pt, the first centred 20 pt in, 20 pt apart, centred in the bar.
            let d = 24 * scale, cy = CGFloat(h) - bar / 2
            let colours: [(CGColor, CGColor)] = [
                (CGColor(srgbRed: 1.0, green: 0.373, blue: 0.341, alpha: 1), CGColor(srgbRed: 0.88, green: 0.27, blue: 0.24, alpha: 1)),
                (CGColor(gray: 0.34, alpha: 1), CGColor(gray: 0.30, alpha: 1)),
                (CGColor(gray: 0.34, alpha: 1), CGColor(gray: 0.30, alpha: 1)),
            ]
            for (i, (fill, rim)) in colours.enumerated() {
                let cx = (40 + 40 * CGFloat(i)) * scale
                let circle = CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
                ctx.setFillColor(fill); ctx.fillEllipse(in: circle)
                ctx.setStrokeColor(rim); ctx.setLineWidth(max(1, 1.2 * scale)); ctx.strokeEllipse(in: circle.insetBy(dx: 0.5, dy: 0.5))
            }
            // The title, 13 pt semibold, centred.
            let font = CTFontCreateUIFontForLanguage(.windowTitle, 26 * scale, nil)!
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.9, alpha: 0.9)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Pair iPhone or iPad", attributes: attrs))
            let tb = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            ctx.textPosition = CGPoint(x: (CGFloat(w) - tb.width) / 2 - tb.minX, y: cy - (tb.height / 2 + tb.minY))
            CTLineDraw(line, ctx)
            // A hairline rim, as a dark-mode window has.
            ctx.resetClip()
            ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16)); ctx.setLineWidth(1); ctx.strokePath()
            return ctx.makeImage()!
        }
    }
}

// MARK: - S24–S25 · the connect screen: Wi‑Fi, Wired, Direct, then Remote

/// The connect screen from the current client (8b0d418): the rows land on the beats (the app adds a row
/// without animation, so each landing is a cut between two screenshots). The column re-centres 56 interior px
/// up per row (measured: the title's top at 621, 565, 509, 453, 397); the crop follows the title, so the
/// heading holds still and each row lands in its final place, as v2's S24 did with its take.
enum Conn {
    static let s24 = 53.6, s25 = 57.6, end = 60.8
    /// Wi‑Fi (MacBook Pro), Wired (Mac Studio), Direct (MacBook Air) on the three beats, then Remote (Mac mini)
    /// on the bar line at 57.6.
    static let rows: [Double] = [54.0, 54.4, 54.8, 57.6]
    static let states: [V3Still] = [.c0, .c1, .c2, .c3, .c4]
    static func titleTop(_ n: Int) -> CGFloat { 621 - 56 * CGFloat(n) }
    static func landed(_ t: Double) -> Int { rows.filter { $0 <= t + 1e-6 }.count }
    /// 800×700 interior px at 1.0×, centred at (1480, 540): the title 44 px below the crop's top, and room for
    /// four rows and "Add a Mac…" (600 px) with the footer outside.
    static func macro(_ n: Int) -> MacroSpec {
        MacroSpec(crop: CGRect(x: 600, y: titleTop(n) - 44, width: 800, height: 700), scale: 1.0,
                  center: CGPoint(x: 1480, y: 540), feather: 0, hardEdges: [.leading, .trailing, .top, .bottom])
    }
    /// Each word's cap centre on its row's centre (rows at screen y 382, 494, 606, 718; T1c caps ≈ 70 px).
    static let baselines: [CGFloat] = [417, 529, 641, 753]
    static let dimTo = 0.45
}

@MainActor func connFrame(_ t: Double, _ e: Env) throws -> FrameLayers {
    let n = Conn.landed(t)
    let m = Conn.macro(n)
    let img = e.v3.macroImage(Conn.states[n], m)
    let b = Conn.baselines
    // The three words carry on across the cut into S25, where they step back for "Or remote,".
    let words = [LineSpec(Copy.wifi, .T1c, x: 128, baseline: b[0], align: .leading, snap: 54.05, holdEnd: Conn.end),
                 LineSpec(Copy.wired, .T1c, x: 128, baseline: b[1], align: .leading, snap: 54.45, holdEnd: Conn.end),
                 LineSpec(Copy.direct, .T1c, x: 128, baseline: b[2], align: .leading, snap: 54.85, holdEnd: Conn.end)]
    // S24's subline and footnote leave just before the Remote row lands; S25's lines take the fourth slot.
    let rest = [LineSpec(Copy.directSub, .T2, x: 128, baseline: b[2] + 92, align: .leading, snap: 55.30, holdEnd: 57.15, easeOut: 57.15),
                LineSpec(Copy.directFootnote, .T3, x: 128, baseline: b[2] + 156, align: .leading, snap: 54.05, holdEnd: 57.15,
                         cascade: false, easeOut: 57.15),
                LineSpec(Copy.orRemote, .T1c, x: 128, baseline: b[3], align: .leading, snap: 57.65, holdEnd: Conn.end),
                LineSpec(Copy.throughVPN, .T4, x: 128, baseline: b[3] + 88, align: .leading, snap: 58.05, holdEnd: Conn.end),
                LineSpec(Copy.remoteFootnote, .T3, x: 128, baseline: b[3] + 148, align: .leading, snap: 57.65, holdEnd: Conn.end,
                         cascade: false)]
    let dim = 1 - (1 - Conn.dimTo) * ease(t, Conn.s25, 0.30, .appleOut)
    let v = ZStack {
        macroShot(m, image: img, t: t, drift: CGSize(width: -6 * CGFloat(t - Conn.s24), height: 0))
        TypeLayer(lines: words, t: t).opacity(dim)
        TypeLayer(lines: rest, t: t)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}

@MainActor func s24(_ t: Double, _ e: Env) throws -> FrameLayers { try connFrame(t, e) }
@MainActor func s25r(_ t: Double, _ e: Env) throws -> FrameLayers { try connFrame(t, e) }

// MARK: - S26 · the pairing moment: the Mac's code beside the iPad's Add a Mac card

/// 2.4 s: the Mac's pairing window with its code (the preview's stand-in link: a made-up key and secret, so
/// nothing pairs with it) beside the iPad's Add a Mac card (the harness's drawn viewfinder: the simulator has no
/// camera). On the beat at 62.4 both show the pairing done: "Paired with iPad (iPad14,1)." on the Mac and
/// "Paired with Mac mini." on the iPad, a cut on the beat (the window takes its new content's size, since its
/// hosting controller sizes it to its content, and the reel keeps its top edge in place; the iPad's column
/// re-centres, as the app lays it out).
enum Pairing {
    static let start = 60.8, flip = 62.4, end = 63.2
    static let winScale: CGFloat = 0.6
    static let winTopLeft = CGPoint(x: 166, y: 262)
    static let ipad = DeviceSpec.M45
    static let ipadCenter = CGPoint(x: 1274, y: 612)
}

@MainActor func s26p(_ t: Double, _ e: Env) throws -> FrameLayers {
    // A cut on the beat, as the rows land in S24–S25: each end simply shows its new state.
    let p: Double = t >= Pairing.flip - 1e-6 ? 1 : 0
    let s = Pairing.ipad.clipScale
    let winA = e.v3.macWindow(.waiting, scale: Pairing.winScale)
    let winB = e.v3.macWindow(.paired, scale: Pairing.winScale)
    let padA = e.v3.interior(.addmac, scale: s)
    let padB = e.v3.interior(.paired, scale: s)
    let settle = ease(t, Pairing.start, 0.5, .appleOut)
    let drift = CGFloat(t - Pairing.start)
    let lines = [LineSpec(Copy.pairOnce, .T1s, baseline: 150, snap: Pairing.start + 0.05, holdEnd: Pairing.end),
                 LineSpec(Copy.pairSub, .T2, baseline: 214, snap: Pairing.start + 0.45, holdEnd: Pairing.end)]
    let o = Pairing.winTopLeft
    let shadowPad = ShadowCache.pad
    func window(_ img: CGImage) -> some View {
        let size = CGSize(width: img.width, height: img.height)
        return ZStack(alignment: .topLeading) {
            Image(decorative: ShadowCache.shared.image(outer: size, radius: 24 * Pairing.winScale, opacity: 0.55, blurRadius: 60), scale: 1)
                .frame(width: size.width + 2 * shadowPad, height: size.height + 2 * shadowPad)
                .offset(x: -shadowPad, y: -shadowPad + 30)
            Image(decorative: img, scale: 1).frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: o.x + 4 * drift, y: o.y)
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    }
    let v = ZStack {
        Backdrop(glow: 0.06 * settle, glowCenter: CGPoint(x: 960, y: 600))
        window(winA).opacity(1 - p)
        window(winB).opacity(p)
        PlacedDevice(spec: Pairing.ipad, center: CGPoint(x: Pairing.ipadCenter.x - 4 * drift, y: Pairing.ipadCenter.y),
                     yaw: lerp(7, 5, ramp(t, Pairing.start, Pairing.end))) {
            ZStack(alignment: .topLeading) {
                ClipScreen(image: padA, size: Pairing.ipad.interior)
                ClipScreen(image: padB, size: Pairing.ipad.interior).opacity(p)
            }
        }
        TypeLayer(lines: lines, t: t)
    }.canvas()
    return FrameLayers(base: any(v))
}

// MARK: - S27 · "Connected through Tailscale · 48 ms"

/// The iPad's Settings panel away from home (the harness's `remote` case: a session through Tailscale, the
/// round trip the mock reports), cropped to the panel's header and first group, pushing in on the route line.
/// The one place the reel names Tailscale: it is the app's own words for that connection. No type of ours.
enum Panel {
    static let start = 63.2, end = 65.6
    /// Frame review (2026-09-26): the header alone, so the route line reads at phone size. The first cut held the
    /// header and the first group (to 628), where the route line was the smallest and dimmest line on screen
    /// (30–35 px, secondary gray) under a larger "Balanced — 15 Mbps" (39–46 px, blue, the preset's em-dash) and a
    /// Frame Rate row reading 120 fps under a header reading 60 fps. The panel spans interior x 1237–1956 from
    /// y 188; its header's text ends at 324 ("Mac mini" 222–247, the stream 267–290, the route line 301–324) and
    /// the first group's box starts at 353. The crop keeps 21 px of black either side and 12 above the panel, and
    /// stops at 346, before the group's box.
    static let crop = CGRect(x: 1216, y: 176, width: 760, height: 170)
    /// The route line's centre (interior px: x 1273–1715, y 301–324) and where it sits on screen: the push is
    /// about it. The anchor centres the header block (y 188–346) on the frame at the push's midpoint (1.975).
    static let route = CGPoint(x: 1494, y: 312.5)
    static let anchor = CGPoint(x: 758, y: 630)
    /// The crop's last 40 screen px fade to black (the 22 interior px under the route line), so the panel ends
    /// softly rather than on a cut.
    static let fade: CGFloat = 40
    /// 1.85 → 2.10 (inOut) about the route line: the push builds with the crescendo into the cut to black. The
    /// route line is 45–51 px tall on screen (the first cut: 30–35).
    static func scale(_ t: Double) -> CGFloat { 1.85 + 0.25 * CGFloat(CubicBezier.inOut(ramp(t, start, end))) }
}

@MainActor func s27t(_ t: Double, _ e: Env) throws -> FrameLayers {
    let s = Panel.scale(t)
    let c = Panel.crop
    let origin = CGPoint(x: Panel.anchor.x - (Panel.route.x - c.minX) * s, y: Panel.anchor.y - (Panel.route.y - c.minY) * s)
    let m = MacroSpec(crop: c, scale: s, origin: origin, feather: 0, hardEdges: [.leading, .trailing, .top, .bottom])
    let img = e.v3.macroImage(.panel, m)
    let bottom = origin.y + c.height * s
    // Pure black behind (no glow): the crop's own black margins then meet the frame's black without a seam.
    // Only the panel: its own shape (20 pt continuous corners, interior x 1236–1956 from y 188) masks the crop,
    // which leaves out the stream area's hairline top edge that runs at the panel's top on either side of it.
    let panelMask = RoundedRectangle(cornerRadius: 40 * s, style: .continuous)
        .frame(width: 720 * s, height: (c.maxY + 20 - 188) * s)
        .offset(x: origin.x + (1236 - c.minX) * s, y: origin.y + (188 - c.minY) * s)
        .frame(width: Stage.size.width, height: Stage.size.height, alignment: .topLeading)
    let v = ZStack(alignment: .topLeading) {
        Color.black
        MacroView(spec: m, image: img) { EmptyView() }.mask(panelMask)
        LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
            .frame(width: c.width * s + 4, height: Panel.fade)
            .offset(x: origin.x - 2, y: bottom - Panel.fade)
    }.canvas()
    return FrameLayers(base: any(v), vignette: false)
}
