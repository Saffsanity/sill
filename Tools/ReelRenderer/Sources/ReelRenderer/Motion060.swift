// Motion060.swift — `motion`: whether the 0.6 cut's moving layers glide (Noah's note on v4.2: "Many of the moving objects
// don't seem like they move uniformly"). Each passage's frames are rendered without the finish (no grain, vignette or
// dither), or decoded from a movie (`--mp4`, its luma plane), and one edge per probe is followed frame by frame to a
// small fraction of a pixel: the area under its luma profile between the two sides' levels, which is exact for an
// anti-aliased or resampled step wherever it falls in its pixel. The positions are fitted to the path the shot's own
// code gives the edge (an affine map of that path, `a + b·path(t)`, so neither the edge's own offset nor, for a turned
// device, its projected size need be known; `exact` fits the offset alone). A layer placed on whole pixels shows as
// plateaus (a frame that does not move while its path does) and jumps (a step a whole pixel off its path's step), and
// as a residual up to half a pixel; a layer on its exact path shows none, and a residual of a few hundredths.
//
//   ReelRenderer motion [--mp4 movie.mp4] [--only S04,S07…] [--tsv dir] [--every n]
//   ReelRenderer motion profile <t> x|y <across a-b> <along a-b>     one frame's luma profile (to find an edge)
//   ReelRenderer motion seal [--from s] [--to s] [--every n]         S07–S08: the stream picture behind the lock screen
import AVFoundation
import CoreImage
import Foundation

/// A frame's luma (0…255, BT.709 weights over the sRGB values, as the encoder takes it), from a rendered RGBA image or
/// a decoded luma plane.
struct Luma {
    let width: Int, height: Int
    private let bytes: [UInt8]
    private let stride: Int, bpr: Int, rgba: Bool

    init(image: CGImage) {
        width = image.width; height = image.height
        let data = image.dataProvider!.data! as Data
        bytes = [UInt8](data)
        bpr = image.bytesPerRow; stride = 4; rgba = true
    }
    init(plane: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        self.width = width; self.height = height
        bytes = [UInt8](UnsafeRawBufferPointer(start: plane, count: bytesPerRow * height))
        bpr = bytesPerRow; stride = 1; rgba = false
    }
    @inline(__always) func at(_ x: Int, _ y: Int) -> Double {
        let i = y * bpr + x * stride
        if !rgba { return Double(bytes[i]) }
        return 0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])
    }
    /// RGB at a pixel (rendered frames only).
    func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        let i = y * bpr + x * stride
        return (Double(bytes[i]), Double(bytes[i + 1]), Double(bytes[i + 2]))
    }
    /// The mean along `across` at each position of `along` (axis x: columns `along`, rows `across`).
    func profile(_ axis: MotionProbe.Axis, across: ClosedRange<Int>, along: ClosedRange<Int>) -> [Double] {
        along.map { p in
            var s = 0.0
            for q in across { s += axis == .x ? at(p, q) : at(q, p) }
            return s / Double(across.count)
        }
    }
}

struct MotionProbe {
    /// x: a vertical edge's x (columns are searched, rows averaged); y: a horizontal edge's y.
    enum Axis: String { case x, y }
    let name: String
    let axis: Axis
    /// The rows (axis x) or columns (axis y) averaged across.
    let across: ClosedRange<Int>
    /// Where the edge is at t (canvas px), roughly (within a couple of px): the search window's centre.
    let guess: (Double) -> Double
    /// The edge's path from the shot's own code: the functions of time its place is a sum of (with a constant), fitted;
    /// or, `exact`, its place in canvas px (only the edge's own constant offset fitted).
    let path: (Double) -> [Double]
    var window = 8
    var exact = false
    /// Measure the centroid of a bright feature (a dot) along the axis instead of a step edge.
    var centroid = false
    /// How far from its path it may measure (px): 0.1, or more where the measurement itself cannot do better (its note).
    var tolerance = 0.1
}

struct MotionPassage {
    let name: String
    let from: Double, to: Double
    let probes: [MotionProbe]
    var note = ""
}

/// The edge in `profile` (pixels `a…`), by area: with n the profile normalised from its first two pixels' level (0) to its
/// last two's (1), the edge is at a + Σ(1 − n). Nil when the two sides differ by less than `minContrast` levels.
func areaEdge(_ p: [Double], from a: Int, minContrast: Double = 6) -> Double? {
    guard p.count >= 6 else { return nil }
    let lo = (p[0] + p[1]) / 2, hi = (p[p.count - 1] + p[p.count - 2]) / 2
    let d = hi - lo
    guard abs(d) >= minContrast else { return nil }
    var s = 0.0
    for v in p { s += 1 - (v - lo) / d }
    return Double(a) + s
}

/// The centroid of a bright line on a step (a device's rim, between the backdrop and its bezel; or a dot, with the same
/// level both sides), at a + the weighted mean of (i + ½). Each pixel's weight is what it has over the level of its own
/// side (the left end's level up to the pixel boundary inside the line, the right end's after it), so a pixel the line
/// only partly covers weighs exactly its share, wherever the line falls, and the window's ends weigh nothing.
func brightCentroid(_ p: [Double], from a: Int, minContrast: Double = 6) -> Double? {
    guard p.count >= 6 else { return nil }
    let lo = (p[0] + p[1]) / 2, hi = (p[p.count - 1] + p[p.count - 2]) / 2
    guard let peak = p.indices.max(by: { p[$0] < p[$1] }), p[peak] - max(lo, hi) >= minContrast else { return nil }
    // The boundary between the two sides' levels: the pixel boundary nearest the line's centre (found by iterating).
    var split = Double(peak) + 0.5
    var c = split
    for _ in 0..<4 {
        let b = Int(split.rounded())             // pixels i < b take the left level
        var w = 0.0, wx = 0.0
        for (i, v) in p.enumerated() { let e = v - (i < b ? lo : hi); w += e; wx += e * (Double(i) + 0.5) }
        guard w > 0 else { return nil }
        c = wx / w
        split = c
    }
    return Double(a) + c
}

/// One probe's record over a passage.
struct ProbeTrack {
    var frames: [Int] = []
    var measured: [Double?] = []
    var path: [[Double]] = []
}

struct ProbeVerdict {
    /// The fitted place at each frame (nil where no edge was found).
    let fitted: [Double]
    let coefficients: [Double]
    let maxResidual: Double, rmsResidual: Double
    let plateaus: Int, jumps: Int, worstStep: Double
    let moving: Int, valid: Int
    let meanStep: Double
}

/// `scale`: the output px per drawing px the track was measured in (the 4K pass: 2), so the thresholds below, the drawing's
/// px, are taken in the track's own.
func judge(_ tr: ProbeTrack, exact: Bool, scale: Double = 1) -> ProbeVerdict? {
    let idx = tr.measured.indices.filter { tr.measured[$0] != nil }
    guard idx.count >= 3, tr.path.first != nil else { return nil }
    // The least-squares fit of the measured places on [1, path…] (on [1] for an exact path, after taking the path away):
    // the projection onto the columns' span, by modified Gram–Schmidt (a column that does not vary drops out).
    let cols: [[Double]] = exact ? [idx.map { _ in 1 }] : [idx.map { _ in 1 }] + (0..<tr.path[0].count).map { j in idx.map { tr.path[$0][j] } }
    let y = idx.map { exact ? tr.measured[$0]! - tr.path[$0][0] : tr.measured[$0]! }
    var q: [[Double]] = []
    for var c in cols {
        let norm0 = (c.map { $0 * $0 }.reduce(0, +)).squareRoot()
        for b in q { let d = zip(b, c).map { $0 * $1 }.reduce(0, +); c = zip(c, b).map { $0 - d * $1 } }
        let norm = (c.map { $0 * $0 }.reduce(0, +)).squareRoot()
        if norm > 1e-9 * max(norm0, 1e-12) { q.append(c.map { $0 / norm }) }
    }
    var proj = [Double](repeating: 0, count: y.count)
    for b in q { let d = zip(b, y).map { $0 * $1 }.reduce(0, +); proj = zip(proj, b).map { $0 + d * $1 } }
    var fitted = [Double](repeating: .nan, count: tr.measured.count)
    for (i, k) in idx.enumerated() { fitted[k] = exact ? proj[i] + tr.path[k][0] : proj[i] }
    var maxR = 0.0, sumR2 = 0.0
    for k in idx { let r = tr.measured[k]! - fitted[k]; maxR = max(maxR, abs(r)); sumR2 += r * r }
    // A frame holds (a plateau) when, over the three frames to it, its path moves 0.1 px or more and it moves less than a
    // third of that (a layer on whole pixels at 0.07 px a frame holds about 13 frames in 14; on a quarter-pixel grid, two
    // in three; the measurement's own noise is a few hundredths). It jumps when its step is half a pixel or more off its
    // path's step.
    var plateaus = 0, jumps = 0, moving = 0, worst = 0.0, stepSum = 0.0
    for k in 1..<tr.frames.count {
        guard let m1 = tr.measured[k], let m0 = tr.measured[k - 1] else { continue }
        let dm = m1 - m0, dp = fitted[k] - fitted[k - 1]
        if abs(dp) >= 0.01 * scale { moving += 1; stepSum += abs(dp) }
        if abs(dm - dp) >= 0.5 * scale { jumps += 1 }
        worst = max(worst, abs(dm - dp))
        if k >= 3, let m3 = tr.measured[k - 3] {
            let dp3 = fitted[k] - fitted[k - 3], dm3 = m1 - m3
            if abs(dp3) >= 0.1 * scale && abs(dm3) < abs(dp3) / 3 { plateaus += 1 }
        }
    }
    return ProbeVerdict(fitted: fitted, coefficients: [], maxResidual: maxR, rmsResidual: (sumR2 / Double(idx.count)).squareRoot(),
                        plateaus: plateaus, jumps: jumps, worstStep: worst, moving: moving, valid: idx.count,
                        meanStep: moving > 0 ? stepSum / Double(moving) : 0)
}

/// Frames to measure: rendered without the finish, or decoded from a movie's luma plane.
@MainActor final class MotionFrames {
    private var comp: Compositor?
    private var env: Env?
    private let movie: URL?
    /// The film's frame the movie starts at (a `render --from` part of the film).
    private let offset: Int
    private var decoded: [Int: Luma] = [:]

    init(movie: URL?, startingAt offset: Int = 0) throws {
        self.movie = movie
        self.offset = offset
        if movie == nil {
            let c = Compositor()
            c.dither = false
            comp = c
            env = try makeEnv(c)
        }
    }

    /// Decodes frames `range` of the movie (all of them, kept until the next call).
    func prepare(_ range: ClosedRange<Int>) throws {
        guard let movie else { return }
        decoded = [:]
        let asset = AVURLAsset(url: movie)
        let sem = DispatchSemaphore(value: 0)
        var tracks: [AVAssetTrack] = []
        var loadError: Error?
        Task.detached {
            do { tracks = try await asset.loadTracks(withMediaType: .video) } catch { loadError = error }
            sem.signal()
        }
        sem.wait()
        if let loadError { throw loadError }
        guard let track = tracks.first else { throw NSError(domain: "motion", code: 1, userInfo: [NSLocalizedDescriptionKey: "no video track"]) }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        out.alwaysCopiesSampleData = false
        reader.add(out)
        reader.timeRange = CMTimeRange(start: CMTime(value: CMTimeValue(max(0, range.lowerBound - offset)), timescale: 60),
                                       end: CMTime(value: CMTimeValue(range.upperBound + 1 - offset), timescale: 60))
        guard reader.startReading() else { throw reader.error ?? NSError(domain: "motion", code: 2) }
        while let sb = out.copyNextSampleBuffer() {
            let f = Int((CMSampleBufferGetPresentationTimeStamp(sb).seconds * 60).rounded()) + offset
            guard range.contains(f), let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            decoded[f] = Luma(plane: CVPixelBufferGetBaseAddressOfPlane(pb, 0)!, width: CVPixelBufferGetWidthOfPlane(pb, 0),
                              height: CVPixelBufferGetHeightOfPlane(pb, 0), bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pb, 0))
            CVPixelBufferUnlockBaseAddress(pb, .readOnly)
        }
    }

    func luma(_ f: Int) throws -> Luma {
        if movie != nil {
            guard let l = decoded[f] else { throw NSError(domain: "motion", code: 3, userInfo: [NSLocalizedDescriptionKey: "frame \(f) not decoded"]) }
            return l
        }
        return Luma(image: try image(f))
    }

    func image(_ f: Int) throws -> CGImage {
        guard let comp, let env else { throw NSError(domain: "motion", code: 4) }
        var l = try layers(frame: f, env: env)
        l.grain = false; l.vignette = false
        return comp.still(l, frame: finishFrame(f))
    }
}

@MainActor func motionCommand(args: [String]) throws {
    if args.first == "profile" { try motionProfile(Array(args.dropFirst())); return }
    if args.first == "seal" { try sealCommand(Array(args.dropFirst())); return }
    if args.first == "primitives" { try motionPrimitives(Array(args.dropFirst())); return }
    var movie: URL?
    var movieStart = 0.0
    var only: Set<String>?
    var tsvDir: URL?
    var every = 1
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--mp4": movie = URL(fileURLWithPath: args[i + 1]); i += 2
        case "--mp4-from": movieStart = Double(args[i + 1])!; i += 2
        case "--only": only = Set(args[i + 1].split(separator: ",").map(String.init)); i += 2
        case "--tsv": tsvDir = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 2
        case "--every": every = max(1, Int(args[i + 1])!); i += 2
        default: i += 1
        }
    }
    let frames = try MotionFrames(movie: movie, startingAt: Int((movieStart * 60).rounded()))
    if let tsvDir { try FileManager.default.createDirectory(at: tsvDir, withIntermediateDirectories: true) }
    var failed = 0
    print("motion: \(movie.map { "decoded from \($0.lastPathComponent)" } ?? "rendered without the finish"); a probe passes within its tolerance of its path (0.1 px unless noted) and with no jump (a step ≥ 0.5 px off its path's); a plateau is a frame that has moved less than a third of its path over the last three (where that is ≥ 0.1 px)")
    // The 4K pass: at an output scale the probes are read in the frame's own pixels, their places, windows, rows and
    // tolerances × scale (and their paths, so an exact path's offset is in the same px); every number printed is in output px.
    let k = Double(Stage.scale), ki = Int(Stage.scale)
    if Stage.scaled {
        print(String(format: "motion at the output scale %.0f (%d×%d): each probe's place, window, rows, path and tolerance × %.0f; every px below is an output px (÷ %.0f for the drawing's)",
                     k, Stage.pixelWidth, Stage.pixelHeight, k, k))
    }
    for passage in MotionPassages060.all where only == nil || only!.contains(passage.name) || only!.contains(where: { passage.name.hasPrefix($0) }) {
        // The passage's frames, up to the one before `to` (a cut).
        let f0 = Int((passage.from * 60).rounded()), f1 = Int((passage.to * 60).rounded()) - 1
        try frames.prepare(f0...f1)
        var tracks = [ProbeTrack](repeating: ProbeTrack(), count: passage.probes.count)
        // A probe that travels less than 6 px over the passage is read through one fixed window that spans its travel (so
        // the window's ends, where the two levels are read, never move across the picture); one that travels further,
        // through a window centred on where its path puts it on each frame.
        let fixedWindows: [ClosedRange<Int>?] = passage.probes.map { probe in
            let g = stride(from: f0, through: f1, by: every).map { probe.guess(Double($0) / 60) * k }
            guard let lo = g.min(), let hi = g.max(), hi - lo < 6 * k else { return nil }
            return (Int(lo.rounded(.down)) - probe.window * ki)...(Int(hi.rounded(.up)) + probe.window * ki)
        }
        // The rows (or columns) averaged across, in output px: each drawing px's k.
        let acrosses: [ClosedRange<Int>] = passage.probes.map { (($0.across.lowerBound * ki)...($0.across.upperBound * ki + ki - 1)) }
        let started = Date()
        for f in stride(from: f0, through: f1, by: every) {
            let t = Double(f) / 60
            let lum = try frames.luma(f)
            for (j, probe) in passage.probes.enumerated() {
                let along = fixedWindows[j] ?? {
                    let a = Int((probe.guess(t) * k).rounded(.down)) - probe.window * ki
                    return a...(a + 2 * probe.window * ki + 1)
                }()
                let a = along.lowerBound
                var m: Double? = nil
                let lim = probe.axis == .x ? lum.width : lum.height
                if along.lowerBound >= 0, along.upperBound < lim {
                    let prof = lum.profile(probe.axis, across: Stage.scaled ? acrosses[j] : probe.across, along: along)
                    m = probe.centroid ? brightCentroid(prof, from: a) : areaEdge(prof, from: a)
                }
                tracks[j].frames.append(f)
                tracks[j].measured.append(m)
                tracks[j].path.append(Stage.scaled ? probe.path(t).map { $0 * k } : probe.path(t))
            }
        }
        let secs = Date().timeIntervalSince(started)
        print(String(format: "%@ %.3f–%.3f s (%d frames, %.1f s)%@", passage.name, passage.from, passage.to, (f1 - f0) / every + 1, secs,
                     passage.note.isEmpty ? "" : " · " + passage.note))
        var rows: [String] = ["probe\tframe\tt\tpath\tfitted\tmeasured\tresidual\tstep\tpathStep"]
        for (j, probe) in passage.probes.enumerated() {
            let tr = tracks[j]
            guard let v = judge(tr, exact: probe.exact, scale: k) else {
                print("  \(probe.name): no edge found (\(tr.measured.compactMap { $0 }.count) of \(tr.frames.count) frames)")
                failed += 1
                continue
            }
            let first = tr.measured.compactMap { $0 }.first ?? 0, last = tr.measured.compactMap { $0 }.last ?? 0
            // On its path (within the probe's tolerance) and never a step half a pixel off. Plateaus are counted, not judged:
            // a layer that holds strays from its path (a quarter-pixel grid at 0.07 px a frame: 0.19 px), and a probe's
            // window moving a whole pixel can read as one.
            let ok = v.maxResidual <= probe.tolerance * k && v.jumps == 0
            if !ok { failed += 1 }
            print(String(format: "  %@ %@  %@%.2f → %.2f px (%.3f px a moving frame, %d of %d frames moving)  residual max %.3f rms %.3f px  plateaus %d  jumps %d  worst step error %.3f px%@",
                         ok ? "ok  " : "FAIL", probe.name.padding(toLength: 22, withPad: " ", startingAt: 0), probe.axis.rawValue == "x" ? "x " : "y ",
                         first, last, v.meanStep, v.moving, max(0, v.valid - 1), v.maxResidual, v.rmsResidual, v.plateaus, v.jumps, v.worstStep, ""))
            for k in 0..<tr.frames.count {
                let fit = v.fitted[k]
                let m = tr.measured[k]
                let step = k > 0 && m != nil && tr.measured[k - 1] != nil ? m! - tr.measured[k - 1]! : .nan
                let pstep = k > 0 ? fit - v.fitted[k - 1] : .nan
                rows.append(String(format: "%@\t%d\t%.4f\t%.4f\t%.4f\t%@\t%@\t%.4f\t%.4f", probe.name, tr.frames[k], Double(tr.frames[k]) / 60, tr.path[k].first ?? .nan, fit,
                                   m.map { String(format: "%.4f", $0) } ?? "nan", m.map { String(format: "%.4f", $0 - fit) } ?? "nan", step, pstep))
            }
        }
        if let tsvDir {
            try rows.joined(separator: "\n").write(to: tsvDir.appendingPathComponent("\(passage.name).tsv"), atomically: true, encoding: .utf8)
        }
    }
    print(failed == 0 ? "motion: every probe glides" : "motion: \(failed) probe(s) failed")
    if failed > 0 { exit(1) }
}

/// One frame's luma profile, to find an edge: `profile <t> x <rows a-b> <columns a-b>` (or y, columns across, rows along).
@MainActor func motionProfile(_ args: [String]) throws {
    guard args.count >= 4, let t = Double(args[0]), let axis = MotionProbe.Axis(rawValue: args[1]) else {
        print("usage: motion profile <t> x|y <across a-b> <along a-b>"); return
    }
    func range(_ s: String) -> ClosedRange<Int> { let p = s.split(separator: "-").map { Int($0)! }; return p[0]...p[1] }
    let frames = try MotionFrames(movie: nil)
    let f = Int((t * 60).rounded())
    let lum = try frames.luma(f)
    let along = range(args[3])
    let p = lum.profile(axis, across: range(args[2]), along: along)
    print("frame \(f) (\(String(format: "%.4f", Double(f) / 60)) s), \(axis.rawValue) profile over \(args[2]):")
    for (i, v) in p.enumerated() { print(String(format: "  %d\t%.2f", along.lowerBound + i, v)) }
    if let e = areaEdge(p, from: along.lowerBound) { print(String(format: "area edge %.3f", e)) }
}
