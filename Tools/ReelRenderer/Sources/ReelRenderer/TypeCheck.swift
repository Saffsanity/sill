// TypeCheck.swift — `typecheck`: every glyph of a render measured against the path its motion gave it.
//
// A frame is rendered twice without the film's finish (no grain, vignette or dither, which move nothing): once
// with its type, recording each glyph's outline and transform as the canvases draw it (TypeProbe, GlyphText.swift),
// and once with the type canvases empty. Their luma difference is the type alone, over whatever lies behind it.
// Each glyph's place in it is then measured: the recorded outline is rasterised where its path puts it, and a
// Gauss–Newton fit (Lucas–Kanade, with a gain for its opacity and the background behind it) finds how far the
// drawn glyph sits from there, all the glyphs of a line at once so that touching neighbours share their pixels.
// A glyph more than the threshold (0.1 px) off its path fails the check, and `typecheck` or `render --typecheck`
// exits 1. Glyphs it cannot measure are counted, not failed: blurred (the snap's first frames, a rack), faint
// (below 25 % opacity), cut by the frame's edge, without an outline, or where the fit says something covers them.
//
// It also reads every string drawn and fails a number printed raw (more than two decimals, an exponent, nan, inf,
// Optional(…)): every number on screen is a fixed string in `Copy`.
import CoreImage
import Foundation
import SwiftUI

@MainActor
final class TypeChecker {
    struct Measure {
        let frame: Int
        let tag: String
        let order: Int
        let dx: Double
        let dy: Double
        var off: Double { (dx * dx + dy * dy).squareRoot() }
        let gain: Double
        let fit: Double                 // residual energy over the glyph's own, after the fit
    }

    var threshold = 0.1
    var verbose = false
    /// Every measurement, one per line (frame, glyph, dx, dy, gain, fit), when set (`--dump`).
    var dump: FileHandle?
    private let with: Compositor
    private let without: Compositor
    private(set) var frames = 0
    private(set) var measured = 0
    private(set) var skipped: [String: Int] = [:]
    private(set) var failures: [Measure] = []
    private(set) var worst: Measure?
    private(set) var offs: [Double] = []
    private var perShot: [String: (n: Int, worst: Double)] = [:]
    private var report = ""

    /// `with` renders the frames with their type (in `render --typecheck`, the film's own compositor); a second
    /// compositor renders them with the type canvases empty, so neither SwiftUI graph ever sees the other state.
    init(with: Compositor) {
        self.with = with
        self.without = Compositor()
    }

    private static let W = Stage.width, H = Stage.height

    /// Luma (Rec. 709 weights on the encoded sRGB values, 0…1) of a frame rendered without its finish, top row
    /// first. Compositing happens on encoded values in both Core Graphics and Core Image here, so a glyph of
    /// coverage α and colour c over a background b adds α·(L(c) − L(b)) to it.
    private func lumaRaw(_ layers: FrameLayers, frame: Int, comp: Compositor) -> [Float] {
        var l = layers
        l.grain = false; l.vignette = false
        let dither = comp.dither
        comp.dither = false
        defer { comp.dither = dither }
        let img = comp.composeImage(l, frame: frame)
        let W = TypeChecker.W, H = TypeChecker.H
        var px = [UInt8](repeating: 0, count: W * H * 4)
        comp.ci.render(img, toBitmap: &px, rowBytes: W * 4, bounds: CGRect(x: 0, y: 0, width: W, height: H),
                       format: .RGBA8, colorSpace: comp.sRGB)
        var y = [Float](repeating: 0, count: W * H)
        for i in 0..<(W * H) {
            y[i] = (0.2126 * Float(px[i * 4]) + 0.7152 * Float(px[i * 4 + 1]) + 0.0722 * Float(px[i * 4 + 2])) / 255
        }
        return y
    }

    static func luma(_ hex: UInt32) -> Float {
        (0.2126 * Float((hex >> 16) & 0xFF) + 0.7152 * Float((hex >> 8) & 0xFF) + 0.0722 * Float(hex & 0xFF)) / 255
    }

    /// One glyph to measure: its outline, where it should be on the canvas, and what it is.
    private struct Target {
        let g: TypeProbe.Glyph
        let transform: CGAffineTransform     // glyph space → canvas, the rack's scale included
        let lc: Float                        // the colour's luma
        var box: (x0: Int, y0: Int, w: Int, h: Int)
        var shift = CGVector.zero            // the current estimate of how far the drawn glyph is from its path
        var gain = 1.0
        var slope = (x: 0.0, y: 0.0)         // the gain's slope across the box (X, Y run −1…1)
        var a: [Float] = []                  // coverage at the current estimate, over `box`
        var unmeasured: String?              // why the fit could not place it
        var notJudged: String?               // fitted for its neighbours' sake, but not judged (why)
    }

    /// Checks one frame: renders `build()`'s layers with and without type, measures every glyph. Returns the worst
    /// offset measured (nil when no glyph could be measured).
    @discardableResult
    func check(frame: Int, shot: String, _ build: () throws -> FrameLayers) rethrows -> Double? {
        let probe = TypeProbe.shared
        let layers = try build()
        probe.begin()
        let lw = lumaRaw(layers, frame: frame, comp: with)
        let glyphs = probe.end()
        probe.set { $0.hidden = true }
        let lo = lumaRaw(layers, frame: frame, comp: without)
        probe.set { $0.hidden = false }
        frames += 1
        guard !glyphs.isEmpty else { return nil }
        let W = TypeChecker.W, H = TypeChecker.H
        var d = [Float](repeating: 0, count: W * H)
        for i in 0..<(W * H) { d[i] = lw[i] - lo[i] }
        // The rack scales and blurs the base (and the mix) after the type is drawn into it.
        let rack = layers.rack.flatMap { r -> (scale: CGFloat, blur: Double)? in
            (r.blur > 0.01 || r.scale < 0.9999) ? (CGFloat(r.scale), r.blur) : nil
        }
        // Every glyph that can be modelled is fitted, so its light is accounted for in its neighbours' pixels; only
        // the clear ones are judged. A blurred glyph can't be modelled: its halo is fenced off instead.
        var targets: [Target] = []
        var halos: [CGRect] = []
        for g in glyphs {
            var t = g.transform
            var blur = Double(g.blur)
            if g.layer != .overlay {
                if let r = rack {
                    t = t.concatenating(.scaling(r.scale, about: CGPoint(x: 960, y: 540)))
                    blur = (blur * blur + r.blur * r.blur).squareRoot()
                }
                if layers.baseBlur > 0.05 { blur = (blur * blur + layers.baseBlur * layers.baseBlur).squareRoot() }
            }
            let b = g.outline.boundingBoxOfPath.applying(t)
            if blur > 0.5 {
                skipped["blurred more than 0.5 px", default: 0] += 1
                halos.append(b.insetBy(dx: -CGFloat(3 * blur) - 2, dy: -CGFloat(3 * blur) - 2))
                continue
            }
            let x0 = Int(floor(b.minX)) - 4, y0 = Int(floor(b.minY)) - 4
            let x1 = Int(ceil(b.maxX)) + 4, y1 = Int(ceil(b.maxY)) + 4
            if x0 < 1 || y0 < 1 || x1 > W - 1 || y1 > H - 1 {
                skipped["at the edge of the frame", default: 0] += 1
                halos.append(b.insetBy(dx: -2, dy: -2))
                continue
            }
            var tg = Target(g: g, transform: t, lc: TypeChecker.luma(g.color), box: (x0, y0, x1 - x0, y1 - y0))
            if g.opacity < 0.25 { tg.notJudged = "faint (its own opacity under 25 %)" }
            if g.covered { tg.notJudged = "covered or masked (the shot says so)" }
            if g.picture { tg.notJudged = "part of a picture (checked: false)" }
            targets.append(tg)
        }
        guard !targets.isEmpty else { return nil }
        // Glyphs whose windows touch are fitted together (a line, a word).
        var parent = Array(targets.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        let order = targets.indices.sorted { targets[$0].box.x0 < targets[$1].box.x0 }
        for (n, i) in order.enumerated() {
            let a = targets[i].box
            for j in order[(n + 1)...] {
                let b = targets[j].box
                if b.x0 > a.x0 + a.w { break }
                if b.y0 < a.y0 + a.h && a.y0 < b.y0 + b.h { parent[find(i)] = find(j) }
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in targets.indices { groups[find(i), default: []].append(i) }
        var frameWorst: Double?
        for (_, members) in groups {
            fit(&targets, members, d: d, bg: lo, halos: halos)
            for i in members {
                let tg = targets[i]
                if let why = tg.notJudged {
                    skipped[why, default: 0] += 1
                    continue
                }
                if let why = tg.unmeasured {
                    skipped[why, default: 0] += 1
                    if verbose { report += String(format: "  frame %d %@ glyph %d: not measured, %@\n", frame, tg.g.tag, tg.g.order, why) }
                    continue
                }
                let m = Measure(frame: frame, tag: tg.g.tag, order: tg.g.order, dx: Double(tg.shift.dx), dy: Double(tg.shift.dy),
                                gain: tg.gain, fit: residual(i, d: d, bg: lo, targets: targets, members: members))
                if m.fit > 0.08 {
                    skipped["covered or cut (the fit says so)", default: 0] += 1
                    if verbose { report += String(format: "  frame %d %@ glyph %d: not measured, fit %.3f gain %.2f\n", frame, m.tag, m.order, m.fit, m.gain) }
                    continue
                }
                measured += 1
                offs.append(m.off)
                dump?.write(String(format: "%d\t%@\t%d\t%.4f\t%.4f\t%.4f\t%.5f\n", m.frame, m.tag, m.order, m.dx, m.dy, m.gain, m.fit).data(using: .utf8)!)
                frameWorst = max(frameWorst ?? 0, m.off)
                if worst == nil || m.off > worst!.off { worst = m }
                if m.off > threshold { failures.append(m) }
            }
        }
        if let w = frameWorst {
            let p = perShot[shot] ?? (0, 0)
            perShot[shot] = (p.n + 1, max(p.worst, w))
        }
        return frameWorst
    }

    /// The coverage of the target's outline, moved by its current shift, over its box (top row first).
    private func raster(_ tg: Target) -> [Float] {
        let (x0, y0, w, h) = tg.box
        var px = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        // Canvas (y down) → this bitmap: memory row 0 is the canvas row y0.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -CGFloat(x0) + tg.shift.dx, y: -CGFloat(y0) + tg.shift.dy)
        ctx.addPath(tg.g.outline.copy(using: [tg.transform])!)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath()
        return px.map { Float($0) / 255 }
    }

    /// Gauss–Newton on the glyphs of one group. Per glyph a gain that may vary linearly across it (its opacity, the
    /// background's contrast, a mask's soft edge crossing it) and a shift: the difference image is modelled as
    /// Σ (g + gx·X + gy·Y) · (L(colour) − L(background)) · coverage(x − shift), X and Y running −1…1 across the
    /// glyph's box. Pixels two glyphs' outlines both cover (letters that overlap: their union is not their sum) and
    /// pixels of low contrast are left out; pixels neighbours share at their edges are modelled, so their shifts
    /// are solved together.
    private func fit(_ targets: inout [Target], _ members: [Int], d: [Float], bg: [Float], halos: [CGRect]) {
        let W = TypeChecker.W
        let n = members.count
        let K = 5                                   // g, gx, gy, u = g·dx, v = g·dy
        let m = K * n
        var gx0 = Int.max, gy0 = Int.max, gx1 = Int.min, gy1 = Int.min
        for i in members {
            let b = targets[i].box
            gx0 = min(gx0, b.x0); gy0 = min(gy0, b.y0); gx1 = max(gx1, b.x0 + b.w); gy1 = max(gy1, b.y0 + b.h)
        }
        let gw = gx1 - gx0, gh = gy1 - gy0
        let slots = 4
        var count = [UInt8](repeating: 0, count: gw * gh)
        var who = [Int32](repeating: 0, count: gw * gh * slots)
        var phi = [Float](repeating: 0, count: gw * gh * slots * K)
        var cover = [Float](repeating: 0, count: gw * gh)
        var done = [Bool](repeating: false, count: n)
        // Each run (a word, a number) is filled as one path, so its glyphs' coverage adds up; two runs are blended
        // one over the other, which doesn't (a crossfade's "60" over its "120"). Pixels two runs share are left out.
        var runIDs: [String: Int32] = [:]
        let run = members.map { i -> Int32 in
            let key = "\(targets[i].g.layer.rawValue)|\(targets[i].g.tag)"
            if let r = runIDs[key] { return r }
            let r = Int32(runIDs.count); runIDs[key] = r; return r
        }
        var firstRun = [Int32](repeating: -1, count: gw * gh)
        // Pixels where a blurred glyph's halo, or a glyph cut by the frame's edge, lies: left out.
        var fenced = [Bool](repeating: false, count: gw * gh)
        let groupRect = CGRect(x: gx0, y: gy0, width: gw, height: gh)
        for h in halos where h.intersects(groupRect) {
            let r = h.intersection(groupRect)
            for y in Int(floor(r.minY))..<Int(ceil(r.maxY)) {
                for x in Int(floor(r.minX))..<Int(ceil(r.maxX)) { fenced[(y - gy0) * gw + x - gx0] = true }
            }
        }
        for _ in 0..<10 {
            for i in members { targets[i].a = raster(targets[i]) }
            for q in 0..<count.count { count[q] = 0; cover[q] = 0; firstRun[q] = -1 }
            for (k, i) in members.enumerated() {
                let tg = targets[i]
                let (x0, y0, w, h) = tg.box
                let hx = Float(w) / 2, hy = Float(h) / 2, half = max(hx, hy)
                for r in 1..<(h - 1) {
                    for c in 1..<(w - 1) {
                        let a = tg.a[r * w + c]
                        let ax = (tg.a[r * w + c + 1] - tg.a[r * w + c - 1]) / 2
                        let ay = (tg.a[(r + 1) * w + c] - tg.a[(r - 1) * w + c]) / 2
                        if a == 0 && ax == 0 && ay == 0 { continue }
                        let q = (y0 + r - gy0) * gw + x0 + c - gx0
                        let slot = Int(count[q])
                        guard slot < slots else { continue }
                        let p = (y0 + r) * W + x0 + c
                        let contrast = tg.lc - bg[p]
                        let X = (Float(c) + 0.5 - hx) / half, Y = (Float(r) + 0.5 - hy) / half
                        let f = (q * slots + slot) * K
                        who[q * slots + slot] = Int32(k)
                        phi[f] = a * contrast
                        phi[f + 1] = a * contrast * X
                        phi[f + 2] = a * contrast * Y
                        phi[f + 3] = -ax * contrast
                        phi[f + 4] = -ay * contrast
                        count[q] += 1
                        cover[q] += a
                        if abs(contrast) < 0.08 { cover[q] = .infinity }      // low contrast: left out
                        if firstRun[q] < 0 { firstRun[q] = run[k] } else if firstRun[q] != run[k] { cover[q] = .infinity }
                    }
                }
            }
            var N = [Double](repeating: 0, count: m * m)
            var rhs = [Double](repeating: 0, count: m)
            var vu = [Double](repeating: 0, count: K), vv = [Double](repeating: 0, count: K)
            for r in 0..<gh {
                for c in 0..<gw {
                    let q = r * gw + c
                    let k = Int(count[q])
                    guard k > 0, cover[q] <= 1.02, !fenced[q] else { continue }
                    let target = Double(d[(gy0 + r) * W + gx0 + c])
                    for u in 0..<k {
                        let ia = K * Int(who[q * slots + u])
                        let fu = (q * slots + u) * K
                        for a in 0..<K { vu[a] = Double(phi[fu + a]) }
                        for a in 0..<K { rhs[ia + a] += vu[a] * target }
                        for v in 0..<k {
                            let ib = K * Int(who[q * slots + v])
                            let fv = (q * slots + v) * K
                            for b in 0..<K { vv[b] = Double(phi[fv + b]) }
                            for a in 0..<K {
                                let row = (ia + a) * m + ib
                                for b in 0..<K { N[row + b] += vu[a] * vv[b] }
                            }
                        }
                    }
                }
            }
            // The gain's slope is damped (ridge, 2 % of the glyph's own energy): a wide glyph under a mask's soft edge
            // still fits one, but across a thin stem ("l", "I" at 24 px) a slope and a shift look alike, and there the
            // damping leaves the shift to explain what moved.
            for k in 0..<n {
                let ia = K * k
                let ridge = 0.02 * N[ia * m + ia]
                N[(ia + 1) * m + ia + 1] += ridge
                N[(ia + 2) * m + ia + 2] += ridge
            }
            // A glyph with nothing to fit, or whose shift no edge determines, keeps its estimate and is reported.
            for k in 0..<n where !done[k] {
                let ia = K * k
                let s11 = N[ia * m + ia]
                let sxx = N[(ia + 3) * m + ia + 3], syy = N[(ia + 4) * m + ia + 4], sxy = N[(ia + 3) * m + ia + 4]
                let tr = sxx + syy, det = sxx * syy - sxy * sxy
                let small = tr / 2 - max(0, tr * tr / 4 - det).squareRoot()
                if s11 <= 1e-12 { done[k] = true; targets[members[k]].unmeasured = "nothing of it left to fit" }
                else if small < 1e-3 * s11 { done[k] = true; targets[members[k]].unmeasured = "too few edges to measure" }
            }
            for k in 0..<n where done[k] {
                // Held: its unknowns fixed (identity rows), its model still subtracted through its neighbours' rows.
                let ia = K * k
                for a in 0..<K {
                    for q in 0..<m { N[(ia + a) * m + q] = 0; N[q * m + ia + a] = 0 }
                    N[(ia + a) * m + ia + a] = 1; rhs[ia + a] = 0
                }
            }
            guard let x = TypeChecker.solve(N, rhs, m) else {
                for i in members where targets[i].unmeasured == nil { targets[i].unmeasured = "the fit did not solve" }
                return
            }
            var biggest = 0.0
            for (k, i) in members.enumerated() where !done[k] {
                let g = x[K * k]
                // Hardly there: a parent's opacity, a mask or something drawn over it.
                guard g > 0.2 else { done[k] = true; targets[i].unmeasured = "faint in the frame (a parent's opacity, a mask, a cover)"; continue }
                let ddx = x[K * k + 3] / g, ddy = x[K * k + 4] / g
                let step = (ddx * ddx + ddy * ddy).squareRoot()
                // A step over 1.5 px means the fit has lost the glyph.
                if step > 1.5 { done[k] = true; targets[i].unmeasured = "the fit lost it (a step over 1.5 px)"; continue }
                targets[i].shift.dx += CGFloat(ddx)
                targets[i].shift.dy += CGFloat(ddy)
                targets[i].gain = g
                targets[i].slope = (x[K * k + 1], x[K * k + 2])
                biggest = max(biggest, step)
            }
            if biggest < 2e-4 { break }
        }
        for i in members { targets[i].a = raster(targets[i]) }
    }

    /// Residual energy of one glyph's fit over the pixels only it covers, against its own modelled energy.
    private func residual(_ i: Int, d: [Float], bg: [Float], targets: [Target], members: [Int]) -> Double {
        let tg = targets[i]
        guard !tg.gain.isNaN else { return .infinity }
        let W = TypeChecker.W
        let (x0, y0, w, h) = tg.box
        let hx = Double(w) / 2, hy = Double(h) / 2, half = max(hx, hy)
        var res = 0.0, energy = 0.0
        for r in 0..<h {
            for c in 0..<w {
                let a = tg.a[r * w + c]
                guard a > 0.02 else { continue }
                let gain = tg.gain + tg.slope.x * (Double(c) + 0.5 - hx) / half + tg.slope.y * (Double(r) + 0.5 - hy) / half
                let px = x0 + c, py = y0 + r
                var shared = false
                for j in members where j != i {
                    let o = targets[j]
                    if px >= o.box.x0 && px < o.box.x0 + o.box.w && py >= o.box.y0 && py < o.box.y0 + o.box.h,
                       o.a[(py - o.box.y0) * o.box.w + px - o.box.x0] > 0 { shared = true; break }
                }
                if shared { continue }
                let p = py * W + px
                let model = gain * Double(a) * Double(tg.lc - bg[p])
                let e = Double(d[p]) - model
                res += e * e
                energy += model * model
            }
        }
        return energy > 0 ? res / energy : .infinity
    }

    /// Solves N x = b (symmetric, positive definite in practice) by Gaussian elimination with partial pivoting.
    static func solve(_ a: [Double], _ b: [Double], _ n: Int) -> [Double]? {
        var a = a, b = b
        for k in 0..<n {
            var piv = k
            var best = abs(a[k * n + k])
            for i in (k + 1)..<max(k + 1, n) where abs(a[i * n + k]) > best { best = abs(a[i * n + k]); piv = i }
            if best < 1e-14 { return nil }
            if piv != k {
                for j in 0..<n { a.swapAt(k * n + j, piv * n + j) }
                b.swapAt(k, piv)
            }
            let akk = a[k * n + k]
            for i in (k + 1)..<max(k + 1, n) {
                let f = a[i * n + k] / akk
                if f == 0 { continue }
                for j in k..<n { a[i * n + j] -= f * a[k * n + j] }
                b[i] -= f * b[k]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for k in stride(from: n - 1, through: 0, by: -1) {
            var s = b[k]
            for j in (k + 1)..<max(k + 1, n) { s -= a[k * n + j] * x[j] }
            x[k] = s / a[k * n + k]
        }
        return x
    }

    /// Numbers printed raw rather than set as fixed strings in the copy.
    static func rawNumbers(in strings: [String: Int]) -> [String] {
        let patterns = [#"\d\.\d{3,}"#, #"\d[eE][-+]?\d"#, #"\bnan\b"#, #"\binf\b"#, #"Optional\("#]
        return strings.keys.sorted().filter { s in
            patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
        }
    }

    /// The summary, and whether the check passed.
    func summary() -> (text: String, passed: Bool) {
        var out = report
        let raw = TypeChecker.rawNumbers(in: TypeProbe.shared.strings)
        let sorted = offs.sorted()
        func pct(_ q: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))] }
        out += String(format: "typecheck: %d frames, %d glyph measurements, threshold %.2f px\n", frames, measured, threshold)
        if !sorted.isEmpty {
            out += String(format: "  offset from the path: median %.4f px, 99th percentile %.4f px, worst %.4f px", pct(0.5), pct(0.99), sorted.last!)
            if let w = worst { out += String(format: " (frame %d, %@, glyph %d: dx %+.3f dy %+.3f)", w.frame, w.tag, w.order, w.dx, w.dy) }
            out += "\n"
        }
        for (k, v) in skipped.sorted(by: { $0.key < $1.key }) { out += "  not measured, \(k): \(v)\n" }
        for (shot, s) in perShot.sorted(by: { $0.key < $1.key }) { out += String(format: "  %@: %d frames, worst %.4f px\n", shot, s.n, s.worst) }
        let bitmaps = TypeProbe.shared.bitmapGlyphs
        if bitmaps > 0 { out += "  glyphs without an outline (drawn by Core Text, not measured): \(bitmaps)\n" }
        out += "  strings drawn: \(TypeProbe.shared.strings.count)\n"
        for s in raw { out += "  FAIL: a number printed raw, not a fixed string: \"\(s)\"\n" }
        if !failures.isEmpty {
            out += "  FAIL: \(failures.count) glyph measurements more than \(threshold) px off their path. Is the type moved by a SwiftUI\n"
            out += "  effect around its layer (.offset, .scaleEffect, a device's tilt)? Move it with the layer's `transform:`; mark type\n"
            out += "  that belongs to a picture `checked: false`, and a region a shot masks `covered:` (GlyphText.swift). The first ones:\n"
            for f in failures.prefix(20) {
                out += String(format: "    frame %d (%.3f s) %@ glyph %d: dx %+.3f dy %+.3f (gain %.2f, fit %.4f)\n",
                              f.frame, Double(f.frame) / Double(Stage.fps), f.tag, f.order, f.dx, f.dy, f.gain, f.fit)
            }
        }
        let passed = failures.isEmpty && raw.isEmpty && measured > 0
        if measured == 0 { out += "  FAIL: no glyph could be measured\n" }
        out += passed ? "typecheck: PASSED\n" : "typecheck: FAILED\n"
        return (out, passed)
    }
}

struct TypeCheckFailed: LocalizedError {
    let summary: String
    var errorDescription: String? { "typecheck failed\n" + summary }
}

// MARK: - Commands

/// `typecheck [--from s] [--to s] [--every n] [--threshold px] [--report file] [--dump file.tsv] [--verbose]`: the timeline's frames,
/// rendered (no video) and checked. Exits 1 if any glyph strays.
@MainActor
func typecheckCommand(args: [String]) throws {
    var from = 0.0, to = Stage.duration, every = 1, threshold = 0.1
    var reportURL: URL?
    var verbose = false
    var dump: FileHandle?
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--from": from = Double(args[i + 1])!; i += 2
        case "--to": to = Double(args[i + 1])!; i += 2
        case "--every": every = max(1, Int(args[i + 1])!); i += 2
        case "--threshold": threshold = Double(args[i + 1])!; i += 2
        case "--report": reportURL = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--verbose": verbose = true; i += 1
        case "--dump":
            FileManager.default.createFile(atPath: args[i + 1], contents: Data("frame\tglyph\torder\tdx\tdy\tgain\tfit\n".utf8))
            dump = FileHandle(forWritingAtPath: args[i + 1]); dump?.seekToEndOfFile(); i += 2
        default: i += 1
        }
    }
    let comp = Compositor()
    let env = try makeEnv(comp)
    let checker = TypeChecker(with: comp)
    checker.threshold = threshold
    checker.verbose = verbose
    checker.dump = dump
    if TypeProbe.legacy { print("TEST: REEL_TYPE_LEGACY=1: v3.1's SwiftUI Text is drawn, against the outlines' path (never a delivered render)") }
    if TypeProbe.testOffset != .zero { print("TEST: REEL_TYPE_OFFSET: every glyph drawn \(TypeProbe.testOffset) from its path (never a delivered render)") }
    let first = Int((from * 60).rounded()), last = min(Stage.frames, Int((to * 60).rounded())) - 1
    let started = Date()
    var lastReport = Date()
    for f in stride(from: first, through: last, by: every) {
        let shot = Timeline.shot(at: f).id
        try checker.check(frame: f, shot: shot) { try layers(frame: f, env: env) }
        if Date().timeIntervalSince(lastReport) > 10 {
            lastReport = Date()
            print(String(format: "  frame %d/%d (%@) · %.1f frames/s", f, last, shot, Double(f - first + 1) / Double(every) / Date().timeIntervalSince(started)))
            fflush(stdout)
        }
    }
    let (text, passed) = checker.summary()
    print(text, terminator: "")
    print(String(format: "typecheck took %.0f s (%.1f frames/s)", Date().timeIntervalSince(started),
                 Double(checker.frames) / max(0.001, Date().timeIntervalSince(started))))
    if let reportURL { try text.write(to: reportURL, atomically: true, encoding: .utf8) }
    if !passed { throw TypeCheckFailed(summary: "") }
}

// MARK: - The test scene: two moving lines

/// `typetest [--out f.mp4] [--seconds 3] [--typecheck] [--frames dir] [--no-video]`: a short clip of two moving lines on the
/// reel's stage, rendered with the software encoder and checked. Line A: a T1 statement that snaps in, holds
/// (+1.2 %) and glides right 0.11 px a frame, in the base. Line B: 44 px medium with Chinese, Japanese and Korean
/// (fallback fonts), scrolling up 0.62 px a frame and right 0.02, in the overlay, as the fixes' column will.
enum TypeTest {
    static let lineB = TypeStyle(size: 44, weight: .medium, tracking: -0.3, color: Palette.text1)

    @MainActor static func layers(_ t: Double) -> FrameLayers {
        let a = LineSpec("Pinch to zoom.", .T1, baseline: 470, snap: 0.10, holdEnd: 3.0)
        var b = LineSpec("Compose here: 你好, こんにちは, 안녕하세요.", lineB, baseline: 760, snap: 0.30, holdEnd: 3.0)
        b.language = "ja"                 // the kana in Hiragino; the Han and Hangul fall back as in Japanese
        let glide = CGAffineTransform(translationX: 6.6 * CGFloat(t), y: 0)
        let scroll = CGAffineTransform(translationX: 1.3 * CGFloat(t), y: -37.3 * CGFloat(t))
        let base = ZStack {
            Backdrop(glow: 0.05)
            TypeLayer(lines: [a], t: t, transform: glide)
        }.canvas()
        return FrameLayers(base: any(base), overlay: any(TypeLayer(lines: [b], t: t, transform: scroll)))
    }
}

@MainActor
func typetestCommand(args: [String]) throws {
    var out = URL(fileURLWithPath: "typetest.mp4")
    var seconds = 3.0
    var check = false
    var framesDir: URL?
    var video = true
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--out": out = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--seconds": seconds = Double(args[i + 1])!; i += 2
        case "--typecheck": check = true; i += 1
        case "--frames": framesDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 2
        case "--no-video": video = false; i += 1
        default: i += 1
        }
    }
    let comp = Compositor()
    let checker = check ? TypeChecker(with: comp) : nil
    if let framesDir { try FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true) }
    let writer = video ? try VideoWriter(url: out) : nil
    let n = Int((seconds * Double(Stage.fps)).rounded())
    let started = Date()
    for f in 0..<n {
        let t = Double(f) / Double(Stage.fps)
        let l = TypeTest.layers(t)
        try writer?.append(frame: f) { pb in comp.compose(l, frame: f, into: pb) }
        if let framesDir {
            writePNG(comp.still(l, frame: f), to: framesDir.appendingPathComponent(String(format: "f%04d-typetest-%06.3f.png", f, t)))
        }
        checker?.check(frame: f, shot: "typetest") { TypeTest.layers(t) }
    }
    try writer?.finish()
    print(String(format: "typetest: %d frames in %.1f s%@", n, Date().timeIntervalSince(started), video ? " → \(out.path)" : " (no video)"))
    if let checker {
        let (text, passed) = checker.summary()
        print(text, terminator: "")
        if !passed { throw TypeCheckFailed(summary: "") }
    }
}
