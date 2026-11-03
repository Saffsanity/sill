// Flat060.swift — 0.6.0: a layer that moves as a whole (a device pushed in, a camera on it, a macro drifting) drawn at rest
// into a picture, which is then resampled on the move's exact path (ExactWarp060) and placed on whole pixels.
//
// Measured (`motion primitives`), SwiftUI and Core Graphics place a moving layer exactly only if it is all shapes and type:
// - every picture in it (a still, a crop, a clip's frame) is drawn on a quarter-pixel grid: a slow push holds still on
//   most frames and then jumps 0.25 px (ExactWarp060);
// - a 3D-turned layer (rotation3DEffect: S04–S07's iPad turned toward the lens, S10's iPhone, S11–S12's keyboard laid
//   back) is placed on whole pixels and the fraction of a move from outside it is applied inside, through its
//   perspective: a turned picture moved 0.07 px a frame travels 0.062 px a frame within each pixel and jumps 0.11 px at
//   each whole one, and a flat layer grouped with a turned one moves the same way (S11's iPad held on 56 of 236 frames).
// Drawn at rest, the layer is the same picture on every frame (its turn too: the same perspective as before, at 1 px a
// point), and the move is one exact resampling of it; at rest (the move's start, a scale of 1, a whole-px place) the
// resampling copies it, so a shot's first frame is the frame it was.
import SwiftUI

@MainActor enum Flat060 {
    private static let renderer: ImageRenderer<AnyView> = {
        let r = ImageRenderer(content: AnyView(EmptyView()))
        r.scale = 1
        r.proposedSize = ProposedViewSize(Stage.scaled ? Stage.pixelSize : Stage.size)
        return r
    }()
    /// The 4K pass's `.context` rasteriser: the drawing at its own size, into a context scaled to the output.
    private static let contextRenderer: ImageRenderer<AnyView> = {
        let r = ImageRenderer(content: AnyView(EmptyView()))
        r.scale = 1
        r.proposedSize = ProposedViewSize(Stage.size)
        return r
    }()
    private static var context: CGContext?

    /// How a layer's rest picture is rasterised at an output scale (the 4K pass; at scale 1 there is one way).
    /// - `view` (the default): as the compositor draws a frame there, the drawing scaled by the view (`Stage.rasterised`):
    ///   every picture and blur at the output resolution, a 3D-turned layer's included, its turn within about 0.6 px of the
    ///   1080p's (SwiftUI rasterises a turned picture, at either scale, up to 0.75 px off its exact projection: measured,
    ///   S04's turned screen 0.58 px wider each side at 4K).
    /// - `context`: the drawing at its own size into a context scaled to the output: SwiftUI turns a layer's vectors exactly
    ///   as at 1080p (within 0.16 px, against 0.6–0.84 px for `view` on S12's keyboard laid back 50°), but rasterises a
    ///   turned layer's pictures at the drawing's 1 px a point and enlarges them, so only for a turned layer that is all
    ///   vectors (S11–S12's keyboard; the iPad standing behind it is unturned, and its pictures are drawn at the output's).
    enum Raster { case view, context }

    /// `view` (a canvas-sized layer) drawn at rest, as the compositor draws a frame (Render.swift: the whole canvas, 1 px
    /// a point, high interpolation, glyphs at their fractional places), and the part of it in `region` (within the canvas).
    /// Only the whole canvas at 1 px a point keeps SwiftUI's turn as the film's (measured: drawn at 2 px a point, or offset
    /// into a frame of another size, the turned iPad's perspective changes and it moves by up to 5 px).
    /// The 4K pass: at an output scale, the whole canvas as the compositor draws it there (`Stage.rasterised`: the drawing
    /// at its points, scaled by the view, which keeps the turn within 0.5 px of the 1080p's, its pictures at the output
    /// resolution), and the region in output pixels: the picture is `region` × scale px.
    static func atRest<V: View>(_ view: V, region: CGRect, raster: Raster = .view) -> CGImage? {
        let w = Stage.pixelWidth, h = Stage.pixelHeight
        if context == nil {
            context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: ExactWarp060.srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        }
        guard let ctx = context else { return nil }
        ctx.saveGState()
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        let canvasSized = view.frame(width: Stage.size.width, height: Stage.size.height)
        if Stage.scaled && raster == .context {
            ctx.scaleBy(x: Stage.scale, y: Stage.scale)
            contextRenderer.content = AnyView(canvasSized)
            contextRenderer.render { _, render in render(ctx) }
        } else {
            renderer.content = Stage.scaled ? AnyView(Stage.rasterised(canvasSized)) : AnyView(canvasSized)
            renderer.render { _, render in render(ctx) }
        }
        ctx.restoreGState()
        // The bitmap's rows run top to bottom, as the canvas's y: the region crops as it is (in output px).
        let r = region.integral.intersection(CGRect(x: 0, y: 0, width: Stage.width, height: Stage.height))
        guard !r.isEmpty, let full = ctx.makeImage() else { return nil }
        if !Stage.scaled { return full.cropping(to: r) }
        let k = Stage.scale
        return full.cropping(to: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k))
    }

    /// `view` (a canvas-sized layer, all of it inside `region` when unmoved) moved by `transform` (canvas → canvas) on its
    /// exact path: drawn at rest under `rest` (a still part of the move, which SwiftUI draws as it always has: S11's 0.92,
    /// S12's camera at 1.15, S08's close-up), then resampled through what is left of the move and shown on whole px.
    /// - Keep what is left a scale of at least 1 about a point in the frame (or a small move): the picture is the canvas,
    ///   and what lies beyond it at rest is not in it.
    /// - Keep a turned layer's `rest` the same through its shot: SwiftUI draws a turned layer under another scale up to
    ///   0.7 px elsewhere (S05's push, drawn at rest at 1.14 from its start, hopped 0.68 px on that frame). A flat layer's
    ///   `rest` may change where the move is fast (S08's pull-back, at its fastest).
    /// `raster`: how the rest picture is rasterised at an output scale (the 4K pass; `Raster`).
    static func moving<V: View>(_ view: V, rest: CGAffineTransform = .identity, _ transform: CGAffineTransform, region: CGRect,
                                raster: Raster = .view) -> AnyView {
        let canvas = CGRect(origin: .zero, size: Stage.size)
        let r = region.applying(rest).integral.intersection(canvas)
        let drawn = rest.isIdentity ? AnyView(view) : AnyView(view.frame(width: Stage.size.width, height: Stage.size.height).transformEffect(rest))
        guard let picture = atRest(drawn, region: r, raster: raster) else { return AnyView(view.transformEffect(transform)) }
        // The picture's px → the canvas at rest → undo the still part → the whole move. At an output scale the picture's
        // px are output px: 1/scale of a point each first.
        let place = Stage.scaled ? CGAffineTransform(scaleX: 1 / Stage.scale, y: 1 / Stage.scale).concatenating(CGAffineTransform(translationX: r.minX, y: r.minY))
                                 : CGAffineTransform(translationX: r.minX, y: r.minY)
        let t = place.concatenating(rest.inverted()).concatenating(transform)
        return AnyView(ExactPicture060(image: picture, transform: t))
    }

    /// The region a device placed by `PlacedDevice` at `center` covers, its shadow and turn included.
    static func region(_ spec: DeviceSpec, center: CGPoint) -> CGRect {
        let o = spec.outer, pad = ShadowCache.pad
        // The shadow image is the outer size plus `pad` all round, 48 px down; a turn of a few degrees widens it by a few
        // percent: 40 px more each side.
        return CGRect(x: center.x - o.width / 2 - pad - 40, y: center.y - o.height / 2 - pad - 40,
                      width: o.width + 2 * pad + 80, height: o.height + 2 * pad + 80 + 48)
    }
}

extension Flat060 {
    /// The region a macro (MacroView) covers: its crop at its scale, with its bezel or feathers round it.
    static func region(_ m: MacroSpec) -> CGRect {
        let o = m.screenOrigin, margin = max(m.bezel, m.feather) + 8
        return CGRect(x: o.x - margin, y: o.y - margin, width: m.crop.width * m.scale + 2 * margin, height: m.crop.height * m.scale + 2 * margin)
    }
}

extension CGAffineTransform {
    /// `scaled(s, about:)`'s move (Stacks.swift) as a transform: a scale by `s` about `p`.
    static func push(_ s: CGFloat, about p: CGPoint) -> CGAffineTransform { .scaling(s, about: p) }
    /// `camera(s, from:, to:)`'s move (Reel060.swift) as a transform.
    static func camera(_ s: CGFloat, from: CGPoint, to: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: -from.x, y: -from.y).concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: to.x, y: to.y))
    }
}
