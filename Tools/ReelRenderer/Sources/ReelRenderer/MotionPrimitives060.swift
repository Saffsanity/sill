// MotionPrimitives060.swift — `motion primitives`: how the compositor (ImageRenderer into the frame's CGContext) places
// each kind of moving layer: a shape or a picture, moved by an offset, a render transform, a scale, inside a clip, a
// mask, a 3D turn, or drawn in a Canvas. Each case moves a 400×300 white rectangle (a filled shape, or a picture of
// one) on black by a known path for 48 frames, and its left edge is measured as `motion` measures (area under the
// profile); a case on its exact path stays within a few hundredths of a pixel of it.
import SwiftUI

@MainActor func motionPrimitives(_ args: [String]) throws {
    let comp = Compositor()
    comp.dither = false
    let w: CGFloat = 400, h: CGFloat = 300
    // The picture: a white 400×300 rectangle with a 1 px grey frame inside its edge, as a bitmap.
    let pic: CGImage = {
        let ctx = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        return ctx.makeImage()!
    }()
    let pic2: CGImage = {
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        return ctx.makeImage()!
    }()
    // A white 400×300 rectangle inside a 20 px grey (#202020) frame, at 1 and 2 px a point, and in BGRA as Flat060's pictures.
    func framed(_ k: Int, bgra: Bool = false) -> CGImage {
        let ctx = CGContext(data: nil, width: 440 * k, height: 340 * k, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: bgra ? CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.125, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 440 * k, height: 340 * k))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 20 * k, y: 20 * k, width: 400 * k, height: 300 * k))
        return ctx.makeImage()!
    }
    let framed1 = framed(1), framed2 = framed(2), framed2b = framed(2, bgra: true)
    let x0: CGFloat = 700.0, y0: CGFloat = 390
    typealias Case = (name: String, step: CGFloat, view: (CGFloat) -> AnyView, edge: (CGFloat) -> Double)
    func image() -> some View { Image(decorative: pic, scale: 1).resizable().interpolation(.high).frame(width: w, height: h) }
    let about = CGPoint(x: 1300, y: 540)
    let cases: [Case] = [
        ("shape, .offset", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Rectangle().fill(.white).frame(width: w, height: h).offset(x: x0 + d, y: y0) }.canvas()) }, { Double(x0 + $0) }),
        ("shape, .position", 0.07, { d in any(ZStack { Color.black; Rectangle().fill(.white).frame(width: w, height: h).position(x: x0 + d + w / 2, y: y0 + h / 2) }.canvas()) }, { Double(x0 + $0) }),
        ("shape, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Rectangle().fill(.white).frame(width: w, height: h).transformEffect(CGAffineTransform(translationX: x0 + d, y: y0)) }.canvas()) }, { Double(x0 + $0) }),
        ("picture, .offset", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; image().offset(x: x0 + d, y: y0) }.canvas()) }, { Double(x0 + $0) }),
        ("picture, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; image().transformEffect(CGAffineTransform(translationX: x0 + d, y: y0)) }.canvas()) }, { Double(x0 + $0) }),
        ("picture, fractional frame", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: pic, scale: 1).resizable().interpolation(.high).frame(width: w + d, height: h).transformEffect(CGAffineTransform(translationX: x0 - d, y: y0)) }.canvas()) }, { Double(x0 - $0) }),
        ("picture, clipShape + transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; image().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).transformEffect(CGAffineTransform(translationX: x0 + d, y: y0)) }.canvas()) }, { Double(x0 + $0) }),
        ("picture, scaleEffect about a point", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; image().offset(x: x0, y: y0) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("shape, scaleEffect about a point", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; Rectangle().fill(.white).frame(width: w, height: h).offset(x: x0, y: y0) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("picture, clipShape, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; image().clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).offset(x: x0, y: y0) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("picture, 3D turn, scaleEffect", 0.0004, { s in any(ZStack { Color.black; image().modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + w / 2, y: y0 + h / 2) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("shape, 3D turn, scaleEffect", 0.0004, { s in any(ZStack { Color.black; Rectangle().fill(.white).frame(width: w, height: h).modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + w / 2, y: y0 + h / 2) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("3D turn + transformEffect move", 0.07, { d in any(ZStack { Color.black; image().modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + w / 2, y: y0 + h / 2) }.canvas().transformEffect(CGAffineTransform(translationX: d, y: 0))) }, { Double(x0 + $0) }),
        ("3D turn inside, scale inside", 0.0004, { s in any(ZStack { Color.black; image().scaleEffect(1 + s).modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + w / 2, y: y0 + h / 2) }.canvas()) }, { Double(x0 + w / 2 - w / 2 * (1 + $0)) }),
        ("3D turn, drawingGroup, scaleEffect", 0.0004, { s in any(ZStack { Color.black; image().modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + w / 2, y: y0 + h / 2) }.canvas().drawingGroup().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("3D turn big (900 px), scaleEffect", 0.0004, { s in any(ZStack { Color.black; Image(decorative: pic, scale: 1).resizable().frame(width: 900, height: 600).modifier(Tilt(yaw: -4, pitch: 0)).position(x: x0 + 450, y: y0 + 150) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("2x picture, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: pic2, scale: 2).resizable().interpolation(.high).frame(width: w, height: h).offset(x: x0, y: y0) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("2x picture, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: pic2, scale: 2).resizable().interpolation(.high).frame(width: w, height: h).transformEffect(CGAffineTransform(translationX: x0 + d, y: y0)) }.canvas()) }, { Double(x0 + $0) }),
        ("2x picture, Canvas draw", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.draw(Image(decorative: pic2, scale: 2), in: CGRect(x: x0 + d, y: y0, width: w, height: h)) }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("2x picture, CGContext draw", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.withCGContext { cg in
            cg.interpolationQuality = .high
            cg.saveGState(); cg.translateBy(x: x0 + d, y: y0 + h); cg.scaleBy(x: 1, y: -1); cg.draw(pic2, in: CGRect(x: 0, y: 0, width: w, height: h)); cg.restoreGState()
        } }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed1, scale: 1).resizable().interpolation(.high).frame(width: w + 40, height: h + 40).transformEffect(CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed1, scale: 1).resizable().interpolation(.high).frame(width: w + 40, height: h + 40).offset(x: x0 - 20, y: y0 - 20) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("inner edge 2x, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed2, scale: 2).resizable().interpolation(.high).frame(width: w + 40, height: h + 40).transformEffect(CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 2x, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed2, scale: 2).resizable().interpolation(.high).frame(width: w + 40, height: h + 40).offset(x: x0 - 20, y: y0 - 20) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("inner edge 2x BGRA, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed2b, scale: 2).resizable().interpolation(.high).frame(width: w + 40, height: h + 40).offset(x: x0 - 20, y: y0 - 20) }.canvas().scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("inner edge 2x, CGContext draw", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.withCGContext { cg in
            cg.interpolationQuality = .high
            cg.saveGState(); cg.translateBy(x: x0 - 20 + d, y: y0 - 20 + h + 40); cg.scaleBy(x: 1, y: -1); cg.draw(framed2, in: CGRect(x: 0, y: 0, width: w + 40, height: h + 40)); cg.restoreGState()
        } }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 2x .medium, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed2, scale: 2).resizable().interpolation(.medium).frame(width: w + 40, height: h + 40).transformEffect(CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 2x .low, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed2, scale: 2).resizable().interpolation(.low).frame(width: w + 40, height: h + 40).transformEffect(CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x .low, transformEffect", 0.07, { d in any(ZStack(alignment: .topLeading) { Color.black; Image(decorative: framed1, scale: 1).resizable().interpolation(.low).frame(width: w + 40, height: h + 40).transformEffect(CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x CG .default", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.withCGContext { cg in
            cg.interpolationQuality = .default
            cg.saveGState(); cg.translateBy(x: x0 - 20 + d, y: y0 - 20 + h + 40); cg.scaleBy(x: 1, y: -1); cg.draw(framed1, in: CGRect(x: 0, y: 0, width: w + 40, height: h + 40)); cg.restoreGState()
        } }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x CG .low", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.withCGContext { cg in
            cg.interpolationQuality = .low
            cg.saveGState(); cg.translateBy(x: x0 - 20 + d, y: y0 - 20 + h + 40); cg.scaleBy(x: 1, y: -1); cg.draw(framed1, in: CGRect(x: 0, y: 0, width: w + 40, height: h + 40)); cg.restoreGState()
        } }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x, exact warp", 0.07, { d in
            any(ZStack(alignment: .topLeading) { Color.black; ExactPicture060(image: framed1, transform: CGAffineTransform(translationX: x0 - 20 + d, y: y0 - 20)) }.canvas()) }, { Double(x0 + $0) }),
        ("inner edge 1x, exact scale", 0.0004, { s in
            any(ZStack(alignment: .topLeading) { Color.black; ExactPicture060(image: framed1, transform: CGAffineTransform(translationX: x0 - 20, y: y0 - 20).concatenating(CGAffineTransform.scaling(1 + s, about: about))) }.canvas()) },
         { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("inner edge 2x, exact scale", 0.0004, { s in
            any(ZStack(alignment: .topLeading) { Color.black; ExactPicture060(image: framed2, transform: CGAffineTransform(scaleX: 0.5, y: 0.5).concatenating(CGAffineTransform(translationX: x0 - 20, y: y0 - 20)).concatenating(CGAffineTransform.scaling(1 + s, about: about))) }.canvas()) },
         { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("picture, mask, scaleEffect", 0.0004, { s in any(ZStack(alignment: .topLeading) { Color.black; image().offset(x: x0, y: y0) }.canvas().mask(Color.white.canvas()).scaled(1 + s, about: about)) }, { Double(about.x + (x0 - about.x) * (1 + $0)) }),
        ("Canvas, draw(Image, in:)", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.draw(Image(decorative: pic, scale: 1), in: CGRect(x: x0 + d, y: y0, width: w, height: h)) }.canvas() }.canvas()) }, { Double(x0 + $0) }),
        ("Canvas, CGContext draw(CGImage)", 0.07, { d in any(ZStack { Color.black; Canvas { ctx, _ in ctx.withCGContext { cg in
            cg.interpolationQuality = .high
            cg.saveGState(); cg.translateBy(x: x0 + d, y: y0 + h); cg.scaleBy(x: 1, y: -1); cg.draw(pic, in: CGRect(x: 0, y: 0, width: w, height: h)); cg.restoreGState()
        } }.canvas() }.canvas()) }, { Double(x0 + $0) }),
    ]
    let only = args.first
    for c in cases where only == nil || c.name.contains(only!) {
        var steps: [Double] = [], res: [Double] = [], widths: [Double] = []
        var last: Double?
        for i in 0..<48 {
            let d = c.step * CGFloat(i)
            let img = comp.still(FrameLayers(base: c.view(d), grain: false, vignette: false), frame: i)
            let lum = Luma(image: img)
            let expect = c.edge(d)
            let a = Int(expect.rounded(.down)) - 8
            let prof = lum.profile(.x, across: 480...600, along: a...(a + 17))
            guard let m = areaEdge(prof, from: a) else { continue }
            // The edge's width: how many px its profile spends between 10 % and 90 % of the way (a sum of fractions).
            let lo = (prof[0] + prof[1]) / 2, hi = (prof[16] + prof[17]) / 2
            widths.append(prof.map { v -> Double in let n = (v - lo) / (hi - lo); return n > 0.1 && n < 0.9 ? 1 : 0 }.reduce(0, +))
            res.append(m - expect)
            if let last { steps.append(m - last) }
            last = m
        }
        let mean = res.reduce(0, +) / Double(max(1, res.count))
        let dev = res.map { abs($0 - mean) }.max() ?? .nan
        let pathStep = c.edge(c.step) - c.edge(0)
        let zero = steps.filter { abs($0) < 0.2 * abs(pathStep) }.count
        if args.count > 1 && args[1] == "v" { print(res.map { String(format: "%.3f", $0 - mean) }.joined(separator: " ")) }
        print(String(format: "%-40@ path step %.4f px  steps %.3f…%.3f  held %2d of %d  offset %.3f  worst off its path %.3f px  edge px 10–90 %%: %.0f…%.0f",
                     c.name as NSString, pathStep, steps.min() ?? .nan, steps.max() ?? .nan, zero, steps.count, mean, dev, widths.min() ?? .nan, widths.max() ?? .nan))
    }
}

