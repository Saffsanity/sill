// ExactWarp060.swift — 0.6.0: pictures resampled on their exact fractional path.
//
// Core Graphics draws a picture through a fractional transform on a quarter-pixel grid: measured (`motion primitives`), an
// edge inside a picture moved 0.07 px a frame holds still on 28 frames of 47 and then jumps 0.25 px, whatever the
// interpolation quality, in a SwiftUI Image, under a render transform or a scale effect, or drawn into a CGContext (vImage's
// affine warp strays ±0.09 px with each pixel; Core Image's high-quality downsampling holds too). Only a shape's or a
// picture's own outline is placed exactly. So a picture that moves is resampled here, by Core Image on the GPU with
// Catmull–Rom weights at its exact place (measured: within 0.04 px at an edge to white, where the cubic's overshoot is
// clipped; a hundredth elsewhere), into a bitmap on whole pixels, and that bitmap is drawn with no resampling at all.
// Catmull–Rom interpolates: at a whole-pixel place it copies the picture, so a layer at rest is exactly as Core Graphics
// drew it.
import CoreGraphics
import CoreImage
import Metal
import SwiftUI

enum ExactWarp060 {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let ci = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [
        .workingColorSpace: srgb, .outputColorSpace: srgb, .cacheIntermediates: false])

    /// Catmull–Rom sampling through an affine map: the destination pixel at d (working space, y up) takes the source at
    /// (m.x d.x + m.z d.y + o.x, m.y d.x + m.w d.y + o.y), sixteen texels weighted by the cubic (a = −0.5) in each axis.
    static let kernel: CIKernel? = CIKernel(source: """
        vec4 crw(float t) {
            float t2 = t * t, t3 = t2 * t;
            return vec4(-0.5 * t3 + t2 - 0.5 * t, 1.5 * t3 - 2.5 * t2 + 1.0, -1.5 * t3 + 2.0 * t2 + 0.5 * t, 0.5 * t3 - 0.5 * t2);
        }
        kernel vec4 sillCubicWarp(sampler src, vec4 m, vec2 o) {
            vec2 d = destCoord();
            vec2 p = vec2(m.x * d.x + m.z * d.y + o.x, m.y * d.x + m.w * d.y + o.y) - 0.5;
            vec2 i = floor(p);
            vec2 f = p - i;
            vec4 wx = crw(f.x), wy = crw(f.y);
            vec2 c = i + 0.5;
            vec4 r0 = wx.x * sample(src, samplerTransform(src, c + vec2(-1.0, -1.0))) + wx.y * sample(src, samplerTransform(src, c + vec2(0.0, -1.0)))
                    + wx.z * sample(src, samplerTransform(src, c + vec2(1.0, -1.0))) + wx.w * sample(src, samplerTransform(src, c + vec2(2.0, -1.0)));
            vec4 r1 = wx.x * sample(src, samplerTransform(src, c + vec2(-1.0, 0.0))) + wx.y * sample(src, samplerTransform(src, c + vec2(0.0, 0.0)))
                    + wx.z * sample(src, samplerTransform(src, c + vec2(1.0, 0.0))) + wx.w * sample(src, samplerTransform(src, c + vec2(2.0, 0.0)));
            vec4 r2 = wx.x * sample(src, samplerTransform(src, c + vec2(-1.0, 1.0))) + wx.y * sample(src, samplerTransform(src, c + vec2(0.0, 1.0)))
                    + wx.z * sample(src, samplerTransform(src, c + vec2(1.0, 1.0))) + wx.w * sample(src, samplerTransform(src, c + vec2(2.0, 1.0)));
            vec4 r3 = wx.x * sample(src, samplerTransform(src, c + vec2(-1.0, 2.0))) + wx.y * sample(src, samplerTransform(src, c + vec2(0.0, 2.0)))
                    + wx.z * sample(src, samplerTransform(src, c + vec2(1.0, 2.0))) + wx.w * sample(src, samplerTransform(src, c + vec2(2.0, 2.0)));
            vec4 s = wy.x * r0 + wy.y * r1 + wy.z * r2 + wy.w * r3;
            // The cubic overshoots a little at sharp edges: keep the result a valid premultiplied colour.
            s.a = clamp(s.a, 0.0, 1.0);
            s.rgb = clamp(s.rgb, vec3(0.0), vec3(s.a));
            return s;
        }
        """)

    /// `image` through `transform` (its px, y down → the destination's px, y down), into a bitmap of the destination's
    /// region `bounds` (whole px), premultiplied, transparent outside the picture. A transform that shrinks the picture
    /// below 0.9 (S09's sheet, S12's page) is a scale and a move (no turn): the scale is Core Image's Lanczos (which
    /// filters what it drops, and keeps its exact size), and the move, the cubic's.
    /// `extend`: the picture's edge pixels carry on past it (for a picture a shape clips at its own edge, so the shape's
    /// anti-aliased edge is the only one there; a picture's own resampled edge under it would show through it).
    static func warp(_ image: CGImage, _ transform: CGAffineTransform, bounds: CGRect, extend: Bool = false) -> CGImage? {
        let b = bounds.integral
        guard b.width >= 1, b.height >= 1, let kernel else { return nil }
        var src = CIImage(cgImage: image)
        var t = transform
        let H = CGFloat(image.height)
        // The picture's y-up px → y-down px.
        var flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H)
        let sx = abs(t.a), sy = abs(t.d)
        if abs(t.b) < 1e-9, abs(t.c) < 1e-9, min(sx, sy) < 0.9, sx > 0, sy > 0 {
            src = src.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy])
            // Now `src` is the picture at the transform's size, its origin at 0: what is left is the move (and any flip).
            t = CGAffineTransform(a: t.a / sx, b: 0, c: 0, d: t.d / sy, tx: t.tx, ty: t.ty)
            flipIn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H * sy)
        }
        let toBitmap = t.concatenating(CGAffineTransform(translationX: -b.minX, y: -b.minY))
        // The bitmap's y-down px → Core Image's y-up px.
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: b.height)
        let inv = flipIn.concatenating(toBitmap).concatenating(flipOut).inverted()
        // A transparent border, so the cubic's taps beyond the picture's edge read nothing (or its edge pixels, `extend`).
        let e = src.extent
        let border = CIImage(color: .clear).cropped(to: e.insetBy(dx: -4, dy: -4))
        let input = extend ? src.clampedToExtent().samplingNearest().cropped(to: e.insetBy(dx: -4, dy: -4))
                           : src.samplingNearest().composited(over: border)
        let extent = CGRect(x: 0, y: 0, width: b.width, height: b.height)
        let out = kernel.apply(extent: extent, roiCallback: { _, r in
            r.applying(inv).insetBy(dx: -3, dy: -3)
        }, arguments: [input, CIVector(x: inv.a, y: inv.b, z: inv.c, w: inv.d), CIVector(x: inv.tx, y: inv.ty)])
        guard let out else { return nil }
        return ci.createCGImage(out, from: extent, format: .BGRA8, colorSpace: srgb)
    }

    /// The region of a parent of `size` a picture of `pictureSize` covers through `transform`, to whole px, with two px
    /// of margin for the cubic.
    static func bounds(_ pictureSize: CGSize, _ transform: CGAffineTransform, in size: CGSize = Stage.size) -> CGRect {
        CGRect(origin: .zero, size: pictureSize).applying(transform).insetBy(dx: -2, dy: -2).integral
            .intersection(CGRect(origin: .zero, size: size).insetBy(dx: -2, dy: -2).integral)
    }
}

/// A picture drawn through `transform` (its px → its parent's px) on its exact path: resampled by ExactWarp060 into a
/// bitmap on whole px and placed there unscaled (a whole-px render transform resamples nothing). A view the size of its
/// parent, `size` (the canvas, by default), in the parent's coordinates, so masks and clips in them apply as they are.
struct ExactPicture060: View {
    let image: CGImage
    let transform: CGAffineTransform
    var size: CGSize = Stage.size
    /// The picture's edge pixels carry on 2 px past it: for a picture a shape clips at its own edge (ExactWarp060.warp).
    var extend = false

    var body: some View {
        let b = ExactWarp060.bounds(CGSize(width: image.width, height: image.height), transform, in: size)
        ZStack(alignment: .topLeading) {
            Color.clear.frame(width: size.width, height: size.height)
            if !b.isEmpty, b.width >= 1, b.height >= 1, let warped = ExactWarp060.warp(image, transform, bounds: b, extend: extend) {
                Image(decorative: warped, scale: 1)
                    .frame(width: b.width, height: b.height)
                    .transformEffect(CGAffineTransform(translationX: b.minX, y: b.minY))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
