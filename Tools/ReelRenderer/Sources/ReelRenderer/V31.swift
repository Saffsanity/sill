// V31.swift — v3.1: S18's pointer drawn smooth (Noah, 2026-09-27: "in the sizzle reel, the cursor section the cursor
// stutters as it pans left to right. We want it to look as smooth as possible!").
//
// Why it stuttered: clip 13 is an `xcrun simctl io recordVideo` capture, which writes a sample only when the screen
// changes, with timestamps that jitter (sd 2.5 ms) and two holes of 90–143 ms inside the crossing. The client moved
// its arrow once per injected touch (every 17.56 ms, in 0.5 pt finger steps). Shown at the latest sample at or
// before each frame (the renderer's rule for every clip), the arrow held on 33 of S18's 144 frames and jumped on 6
// (W/v3/cursor-diag).
//
// What v3.1 does, in S18 only: every clip 13 sample the shot reads gets its recorded arrow painted out with the
// arrow-free plate of its row (the per-pixel median of the sweep's samples, the arrow's box left out), and the same
// arrow, the 2× bitmap of AppKit's arrow cursor that the host streams (CursorShapeWatcher: the representation
// nearest 2×) and the client draws 1:1, is drawn where the injected stroke put it at the frame's own time. The
// stroke is analytic (v3tools/pointer-path.txt is a sampling of it, to 0.013 pt), so the arrow's velocity is
// continuous on every frame, easing in and out of the pan. The picture under it is the recording's, and the shot's
// clip image is scaled to an exact pixel size (the rounded size moved the picture by up to ±0.35 px from frame to
// frame under the push-in). The finger dot, the device, the push, the type, the timing and the way the frame is drawn
// are v3's. What is left is Core Graphics' own placement of an image drawn at a fractional position, within about
// ±0.2 px (W/v31/tools/cgprobe), which every shot has; drawing S18 through RenderBox's rasterizer
// (`ImageRenderer.cgImage`) removes it for the picture and the arrow but snaps the finger dot's `.offset` to whole
// points, so v3.1 keeps v3's way (SHOTLIST-v3.md §11.5, D45).
//
// TEST ONLY switches, for the checks in SHOTLIST-v3.md §11 (the delivery pipeline refuses them): REEL_V31_NO_ARROW=1
// (the painted-out picture without the drawn arrow), REEL_V31_FLAT=1 (S18's picture flat grey) and
// REEL_V31_NO_GRAIN=1 (no grain, so two renders' difference is the arrow alone).
//
// Assets (W/v31/s18, made by W/v31/tools/cursorrep, s18prep and subpx from AppKit and clip 13):
//   arrow-56x80.png             NSCursor.arrow's 56×80 representation, PNG-encoded as the host encodes it
//   plate-band.png              interior rows 440–599, all 1420 columns, the arrow's row with the arrow removed
//   recorded-arrow-subpx.csv    per sample of the sweep: the recorded arrow's bitmap left edge, sub-pixel (the bitmap
//                               shifted bilinearly, as Core Animation draws a layer at a fractional position, over the
//                               plate matches the 199 samples to 1.7 levels rms on average, 4.3 at worst)
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum PointerArrow {
    static let dir = reelDir.appendingPathComponent("v31/s18")
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The injected stroke's x in simulator points at path time u (clip time − `Pointer.fingerDown`): a sine ease out
    /// of the first sweep left, then the crossing, 352 → 679 pt over 1.30–3.60 s, a cosine ease in and out, then the
    /// start of the sweep back. v3tools/pointer-path.txt samples exactly this (to its 0.01 pt print precision).
    static func strokeX(_ u: Double) -> Double {
        if u <= 0 { return 516 }
        if u <= 1.3 { return 516 - 164 * sin(Double.pi / 2 * u / 1.3) }
        if u <= 3.6 { return 352 + 327 * (1 - cos(Double.pi * (u - 1.3) / 2.3)) / 2 }
        if u <= 4.5 { return 679 - 82 * (1 - cos(Double.pi * (u - 3.6) / 0.9)) / 2 }
        return 597
    }

    /// The arrow bitmap's left edge in portrait interior px at clip time c: a + b · strokeX(c − 1.700), fitted to the
    /// recorded arrow's sub-pixel positions (the 95 clean updates of the crossing: rms 0.84 px, which is the
    /// recording's own timing jitter; the best time offset is 0.0005 s, so none is applied). Its top edge is row 490
    /// in every sample.
    static let a = -613.275, b = 2.54513
    static let top: CGFloat = 490
    static func left(clip c: Double) -> Double { a + b * strokeX(c - Pointer.fingerDown) }

    /// The 2× arrow bitmap, premultiplied RGBA 0…255, rows top-down.
    static let bitmap: (w: Int, h: Int, p: [Float])? = {
        guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("arrow-56x80.png") as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, buf.map { Float($0) })
    }()

    /// Interior rows 440–599 without the arrow (a CI image with its origin at the band's bottom-left).
    static let plate: CIImage? = {
        guard let src = CGImageSourceCreateWithURL(dir.appendingPathComponent("plate-band.png") as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil), img.width == 1420, img.height == 160 else { return nil }
        return CIImage(cgImage: img, options: [.colorSpace: srgb])
    }()
    static let plateTop: CGFloat = 440, plateRows: CGFloat = 160

    /// Sample PTS (%.4f) → the recorded arrow's bitmap left edge (interior px, sub-pixel).
    static let recorded: [String: Double] = {
        var d: [String: Double] = [:]
        guard let text = try? String(contentsOf: dir.appendingPathComponent("recorded-arrow-subpx.csv"), encoding: .utf8) else { return d }
        for l in text.split(separator: "\n").dropFirst() {
            let f = l.split(separator: ",", omittingEmptySubsequences: false)
            if f.count > 2, let t = Double(f[0]), let x = Double(f[2]) { d[String(format: "%.4f", t)] = x }
        }
        return d
    }()

    static let noArrow = ProcessInfo.processInfo.environment["REEL_V31_NO_ARROW"] == "1"
    /// TEST ONLY: REEL_V31_FLAT=1 replaces S18's picture with flat grey (the arrow alone on it). Never for delivery.
    static let flat = ProcessInfo.processInfo.environment["REEL_V31_FLAT"] == "1"
    /// TEST ONLY: REEL_V31_NO_GRAIN=1 renders without the film grain (a soft-light blend, so it does not cancel in a
    /// difference of two renders), for measuring positions. Never for delivery.
    static let noGrain = ProcessInfo.processInfo.environment["REEL_V31_NO_GRAIN"] == "1"

    static func missing(_ what: String) -> NSError {
        NSError(domain: "Reel", code: 31, userInfo: [NSLocalizedDescriptionKey: "S18 pointer: \(what) (\(dir.path))"])
    }

    /// The interior (CI space: origin bottom-left, height H) with the recorded arrow of the sample at `pts` replaced
    /// by the plate: a box around the arrow's whole footprint (the bitmap's alpha > 0 area, columns 4–32 and rows
    /// 5–47, one more column for the bilinear shift) plus 6 px for the recording's codec spread, feathered by a
    /// Gaussian of σ 1.5 px, so the plate is at full strength 3 px before the box's edge.
    static func paintOut(_ img: CIImage, pts: Double, interiorHeight H: CGFloat) throws -> CIImage {
        guard let plate else { throw missing("plate-band.png missing or not 1420×160") }
        guard let xr = recorded[String(format: "%.4f", pts)] else { throw missing(String(format: "no recorded arrow for the sample at %.4f s", pts)) }
        let x0 = floor(xr)
        // Top-left rows 489…543 and columns x0 − 2 … x0 + 39, inclusive.
        let box = CGRect(x: x0 - 2, y: H - 544, width: 42, height: 55)
        let mask = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: box)
            .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: img.extent))
            .clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: img.extent)
        let band = plate.transformed(by: CGAffineTransform(translationX: 0, y: H - plateTop - plateRows))
        return band.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: mask])
            .cropped(to: img.extent)
    }

    /// Lanczos-3, the kernel for the sprite's sub-pixel shift (it copies the bitmap exactly at a whole-pixel offset).
    static func lanczos3(_ x: Double) -> Double {
        let ax = abs(x)
        if ax < 1e-12 { return 1 }
        if ax >= 3 { return 0 }
        return 3 * sin(Double.pi * ax) * sin(Double.pi * ax / 3) / (Double.pi * Double.pi * ax * ax)
    }

    /// The arrow with its bitmap's left edge at interior x `left` (sub-pixel) and its top at row `top`, in the
    /// interior's CI space. The bitmap is resampled horizontally (Lanczos-3, weights normalised, clamped to a valid
    /// premultiplied pixel) and placed at a whole pixel, so compositing it resamples nothing. Premultiplied sRGB,
    /// composited in the renderer's sRGB working space, as Core Animation composites it on the device.
    static func sprite(left: Double, interiorHeight H: CGFloat) throws -> CIImage {
        guard let bm = bitmap else { throw missing("arrow-56x80.png missing") }
        // TEST ONLY: REEL_V31_NO_ARROW=1 leaves the arrow out (the painted-out picture alone), for the checks in
        // SHOTLIST-v3.md §11. Never set for a delivered render.
        if noArrow { return CIImage.empty() }
        let x0 = floor(left), frac = left - x0
        let pad = 3, w = bm.w + 2 * pad, h = bm.h
        // Output column j is interior x0 − pad + j, which is bitmap x j − pad − frac.
        var taps: [[(Int, Double)]] = []
        for j in 0..<w {
            let sx = Double(j - pad) - frac
            let k0 = Int(floor(sx))
            var row: [(Int, Double)] = []
            var sum = 0.0
            for k in (k0 - 2)...(k0 + 3) { let wt = lanczos3(Double(k) - sx); sum += wt; row.append((k, wt)) }
            taps.append(row.map { ($0.0, $0.1 / sum) })
        }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for j in 0..<w {
                var acc = (0.0, 0.0, 0.0, 0.0)
                for (k, wt) in taps[j] where k >= 0 && k < bm.w {
                    let i = (y * bm.w + k) * 4
                    acc.0 += wt * Double(bm.p[i]); acc.1 += wt * Double(bm.p[i + 1])
                    acc.2 += wt * Double(bm.p[i + 2]); acc.3 += wt * Double(bm.p[i + 3])
                }
                let al = min(255, max(0, acc.3))
                let o = (y * w + j) * 4
                out[o] = UInt8(min(al, max(0, acc.0)).rounded())
                out[o + 1] = UInt8(min(al, max(0, acc.1)).rounded())
                out[o + 2] = UInt8(min(al, max(0, acc.2)).rounded())
                out[o + 3] = UInt8(al.rounded())
            }
        }
        guard let ctx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: srgb,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else { throw missing("sprite render failed") }
        return CIImage(cgImage: cg, options: [.colorSpace: srgb])
            .transformed(by: CGAffineTransform(translationX: x0 - CGFloat(pad), y: H - top - CGFloat(h)))
    }
}
