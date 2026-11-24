// Clip.swift — captured footage: VFR readers, the interior crop, privacy treatments (§7.2) and caching.
//
// Every recording is the simulator's whole portrait screen (2064×2752). The landscape Duo frame's
// interior is file x 32, y 666, 2000×1420 (2 px = 1 pt); the portrait one x 322, y 376, 1420×2000.
// All rectangles below are interior px with a top-left origin. The renderer shows the latest sample at
// or before the clip time; nothing is retimed.
import AVFoundation
import CoreImage
import CoreVideo
import Foundation

/// The reel's inputs (clips, stills, previews, S18's assets) and its default output folder: `REEL_DIR` when it is
/// set, else `work/` beside Package.swift (ignored by git: real footage never goes in the repository).
/// Recovered: v3.1 named the session scratchpad that held it here (Tools/ReelRenderer/README.md).
let reelDir: URL = {
    if let dir = ProcessInfo.processInfo.environment["REEL_DIR"], !dir.isEmpty {
        return URL(fileURLWithPath: dir, isDirectory: true)
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("work", isDirectory: true)
}()

enum ClipID: String, CaseIterable {
    case r01, r02, r04, r05, r07, r08, htA, htB, htD, htE
    // Round-3 real captures (real-captures/README-3.md): N2, the Aa ruler resizing Weather (S16), and N3, the
    // trackpad moving the client-drawn pointer, portrait (S18). Round 4: N1, window → Desktop (S13), take 1.
    case n1, n2, n3

    var url: URL {
        switch self {
        case .r01: return reelDir.appendingPathComponent("real-captures/01-connect-desktop.mov")
        case .r02: return reelDir.appendingPathComponent("real-captures/02-drawer-launch.mov")
        case .r04: return reelDir.appendingPathComponent("real-captures/04-pick-vscode.mov")
        case .r05: return reelDir.appendingPathComponent("real-captures/05-pick-blender.mov")
        case .r07: return reelDir.appendingPathComponent("real-captures/07-aa-ruler.mov")
        case .r08: return reelDir.appendingPathComponent("real-captures/08-settings-panel.mov")
        case .htA: return reelDir.appendingPathComponent("capture/final-desktop.mov")
        case .htB: return reelDir.appendingPathComponent("capture/final-aa.mov")
        case .htD: return reelDir.appendingPathComponent("capture/final-lights.mov")
        case .htE: return reelDir.appendingPathComponent("capture/final-rows.mov")
        case .n1: return reelDir.appendingPathComponent("real-captures/11-window-to-desktop.mov")
        case .n2: return reelDir.appendingPathComponent("real-captures/12-aa-resize-weather.mov")
        case .n3: return reelDir.appendingPathComponent("real-captures/13-trackpad-pointer.mov")
        }
    }
    /// The only segments any shot may read (SHOTLIST §2.1 and §8.2). Reads outside them are a bug.
    var approved: [ClosedRange<Double>] {
        switch self {
        case .r01: return [0...4.70]
        case .r02: return [3.0...20.0]
        case .r04: return [0...23.0]
        case .r05: return [0...40.2]
        case .r07: return [0...10.3]
        case .r08: return [0...24.0]
        case .htA, .htB, .htD, .htE: return [0...8.1]
        // Only the segments the cut plays (plus a few frames either side). Clip 11 (take 1, README.md "Approved
        // (round 4)"): Weather streaming, the Desktop tap, the Desktop (Blender's Recent Files names blurred, P.n1).
        // Clip 12 (approved as recorded): the second gesture, 0.75× → 1×, and the 1× layout. Clip 13: the
        // left-to-right sweep. Weather's places are cleared (noah-notes.md); the strips' thumbnails were checked at
        // reel size (SHOTLIST-v2 §11, §12).
        case .n1: return [1.15...4.95]
        case .n2: return AaResize.reverse ? [9.95...13.35] : [2.20...5.55]
        case .n3: return [2.85...5.40]
        }
    }
}

/// Landscape interior in file px (top-left origin).
let interiorRect = CGRect(x: 32, y: 666, width: 2000, height: 1420)
/// Portrait interior (the 710×1000 pt harness) in file px.
let portraitRect = CGRect(x: 322, y: 376, width: 1420, height: 2000)
let fileHeight: CGFloat = 2752

/// A region of the interior with a Gaussian of σ (clip px) and a brightness multiplier, inside a mask
/// feathered 60 px (less where the region meets UI that must stay sharp).
struct Region: Hashable {
    var rect: CGRect
    var sigma: Double
    var brightness: Double = 1
    var feather: CGFloat = 60          // the mask's soft edge, lying outside the rect (full strength on its edge)
    init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, sigma: Double, brightness: Double = 1, feather: CGFloat = 60) {
        rect = CGRect(x: x, y: y, width: w, height: h); self.sigma = sigma; self.brightness = brightness; self.feather = feather
    }
    /// From edge coordinates (x0, y0)–(x1, y1) as the shot list writes them.
    static func edges(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, sigma: Double, brightness: Double = 1,
                      feather: CGFloat = 60) -> Region {
        Region(x0, y0, x1 - x0, y1 - y0, sigma: sigma, brightness: brightness, feather: feather)
    }
}

struct Treatment: Hashable {
    var regions: [Region] = []
    static let none = Treatment()
    /// Quantised so cache keys stay stable while a ramp is flat.
    var key: String {
        regions.map { r in
            String(format: "%.0f,%.0f,%.0f,%.0f:%.2f:%.3f:%.0f", r.rect.minX, r.rect.minY, r.rect.width, r.rect.height, r.sigma, r.brightness, r.feather)
        }.joined(separator: "|")
    }
}

// MARK: - A VFR reader that holds the last sample

final class ClipSource {
    let id: ClipID
    let asset: AVURLAsset
    private let track: AVAssetTrack
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pending: CMSampleBuffer?
    private(set) var current: (pts: Double, buffer: CVPixelBuffer)?
    private var exhausted = false

    init(_ id: ClipID) throws {
        self.id = id
        asset = AVURLAsset(url: id.url)
        let sem = DispatchSemaphore(value: 0)
        var found: AVAssetTrack?
        var failure: Error?
        Task.detached { [asset] in
            do { found = try await asset.loadTracks(withMediaType: .video).first } catch { failure = error }
            sem.signal()
        }
        sem.wait()
        guard let found else { throw failure ?? NSError(domain: "Clip", code: 1, userInfo: [NSLocalizedDescriptionKey: "no video in \(id)"]) }
        track = found
    }

    private func restart(at t: Double) throws {
        reader?.cancelReading()
        let r = try AVAssetReader(asset: asset)
        let start = max(0, t - 6)
        r.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: .positiveInfinity)
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        o.alwaysCopiesSampleData = false
        r.add(o)
        guard r.startReading() else { throw r.error ?? NSError(domain: "Clip", code: 2) }
        reader = r; output = o
        pending = nextSample()
        current = nil
        exhausted = false
    }

    private func nextSample() -> CMSampleBuffer? {
        while let s = output?.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(s) > 0, CMSampleBufferGetImageBuffer(s) != nil { return s }
        }
        exhausted = true
        return nil
    }

    /// The sample on screen at clip time `t`: the last one at or before it.
    func sample(at t: Double) throws -> (pts: Double, buffer: CVPixelBuffer) {
        guard id.approved.contains(where: { $0.contains(t) }) else {
            throw NSError(domain: "Clip", code: 9, userInfo: [NSLocalizedDescriptionKey: "\(id) read at \(t) s is outside its approved segments"])
        }
        let needRestart: Bool
        if reader == nil { needRestart = true }
        else if let c = current, t < c.pts - 1e-6 { needRestart = true }
        else if current == nil, let p = pending, CMSampleBufferGetPresentationTimeStamp(p).seconds > t + 1e-4 { needRestart = true }
        else if let c = current, t > c.pts + 8, let p = pending, CMSampleBufferGetPresentationTimeStamp(p).seconds < t - 8 { needRestart = true }
        else { needRestart = false }
        if needRestart { try restart(at: t) }
        while let p = pending, CMSampleBufferGetPresentationTimeStamp(p).seconds <= t + 1e-4 {
            if let pb = CMSampleBufferGetImageBuffer(p) {
                current = (CMSampleBufferGetPresentationTimeStamp(p).seconds, pb)
            }
            pending = nextSample()
        }
        guard let c = current else {
            throw NSError(domain: "Clip", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(id): no sample at or before \(t)"])
        }
        return c
    }
}

// MARK: - Library: crop, treat, scale, cache

final class ClipLibrary {
    let ci: CIContext
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    private var sources: [ClipID: ClipSource] = [:]
    private var cache: [String: CGImage] = [:]
    private var cacheOrder: [String] = []
    private var masks: [String: CIImage] = [:]
    private(set) var reads: [ClipID: [Double]] = [:]      // every clip time read, for the speed check

    init(ci: CIContext) { self.ci = ci }

    func source(_ id: ClipID) throws -> ClipSource {
        if let s = sources[id] { return s }
        let s = try ClipSource(id)
        sources[id] = s
        return s
    }

    /// A feathered mask in the interior's CI space: full strength on and inside `rect`, with the soft edge
    /// outside it. The white area is `rect` grown by feather/2 and blurred with σ = feather/4, so the mask
    /// is ≥ 0.977 on the rect's edge (2σ in from the white edge), 1 a few px inside, and ≤ 0.02 at
    /// `feather` px outside. (It used to be centred on the edge, which left the rect's outer ~30 px at
    /// half strength: VS Code's title and the Desktop's letters by the drawer read through.)
    func mask(_ rect: CGRect, size: CGSize, feather: CGFloat = 60) -> CIImage {
        let key = "\(rect)@\(size)@\(feather)"
        if let m = masks[key] { return m }
        let grown = feather > 0 ? rect.insetBy(dx: -feather / 2, dy: -feather / 2) : rect
        let flipped = CGRect(x: grown.minX, y: size.height - grown.maxY, width: grown.width, height: grown.height)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: flipped)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let base = white.composited(over: black).clampedToExtent()
        let soft = (feather > 0 ? base.applyingGaussianBlur(sigma: Double(feather) / 4) : base)
            .cropped(to: CGRect(origin: .zero, size: size))
        // Bake it once so every frame reuses the pixels instead of re-blurring.
        let cg = ci.createCGImage(soft, from: soft.extent, format: .RGBA8, colorSpace: srgb)!
        let m = CIImage(cgImage: cg)
        masks[key] = m
        return m
    }

    /// Crops the interior of a recording frame and applies a treatment. Result: interior-sized CIImage.
    func treat(_ pixels: CVPixelBuffer, crop: CGRect, treatment: Treatment) -> CIImage {
        var img = CIImage(cvPixelBuffer: pixels, options: [.colorSpace: srgb])
        let h = CGFloat(CVPixelBufferGetHeight(pixels))
        let flipped = CGRect(x: crop.minX, y: h - crop.maxY, width: crop.width, height: crop.height)
        img = img.cropped(to: flipped).transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        let size = crop.size
        for r in treatment.regions where r.sigma > 0.05 || r.brightness < 0.999 {
            var treated = img
            if r.sigma > 0.05 {
                treated = img.clampedToExtent().applyingGaussianBlur(sigma: r.sigma).cropped(to: img.extent)
            }
            if r.brightness < 0.999 {
                let b = CGFloat(r.brightness)
                treated = treated.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            }
            img = treated.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: mask(r.rect, size: size, feather: r.feather)])
        }
        return img.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// The treated interior of `id` at clip time `t`, scaled by `scale` (Lanczos) and rendered to pixels.
    /// Cached per source sample, treatment and scale, so VFR holds cost nothing.
    func image(_ id: ClipID, at t: Double, treatment: Treatment = .none, scale: CGFloat = 1,
               crop: CGRect = interiorRect, sub: CGRect? = nil) throws -> (image: CGImage, pts: Double) {
        let s = try source(id).sample(at: t)
        reads[id, default: []].append(t)
        let key = "\(id.rawValue)@\(String(format: "%.4f", s.pts))|\(treatment.key)|\(String(format: "%.4f", scale))|\(crop)|\(String(describing: sub))"
        if let hit = cache[key] { return (hit, s.pts) }
        var img = treat(s.buffer, crop: crop, treatment: treatment)
        var outSize = crop.size
        if let sub {
            // A sub-rect of the interior (top-left origin) moved to the origin.
            let r = CGRect(x: sub.minX, y: crop.height - sub.maxY, width: sub.width, height: sub.height)
            img = img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
            outSize = sub.size
        }
        if abs(scale - 1) > 1e-4 {
            img = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
        }
        let extent = CGRect(x: 0, y: 0, width: (outSize.width * scale).rounded(), height: (outSize.height * scale).rounded())
        guard let cg = ci.createCGImage(img, from: extent, format: .BGRA8, colorSpace: srgb) else {
            throw NSError(domain: "Clip", code: 4, userInfo: [NSLocalizedDescriptionKey: "render failed \(id) \(t)"])
        }
        cache[key] = cg
        cacheOrder.append(key)
        if cacheOrder.count > 48 { cache[cacheOrder.removeFirst()] = nil }
        return (cg, s.pts)
    }

    /// Sample PTS only (no pixels), for event alignment checks.
    func pts(_ id: ClipID, at t: Double) throws -> Double { try source(id).sample(at: t).pts }
}

// MARK: - v3.1: S18's clip image (V31.swift)

extension ClipLibrary {
    /// Clip 13's portrait interior at clip time `t` (the latest sample at or before it, as `image`), with the recorded
    /// arrow painted out and the arrow drawn with its bitmap's left edge at interior x `arrowLeft` (this frame's own
    /// place on the stroke), scaled to exactly round(1420 · scale) × round(2000 · scale) px: x and y are scaled apart
    /// so no fractional edge is left, and the view's stretch of the image to the interior's frame puts every interior
    /// px where it belongs on every frame (with one uniform scale, the rounding moved the picture by up to ±0.35 px from
    /// frame to frame during the push-in). Not cached: the arrow moves on every frame.
    func pointerImage(at t: Double, arrowLeft: Double, scale: CGFloat) throws -> CGImage {
        let id = ClipID.n3
        let s = try source(id).sample(at: t)
        reads[id, default: []].append(t)
        let crop = portraitRect
        var img = treat(s.buffer, crop: crop, treatment: .none)
        img = try PointerArrow.paintOut(img, pts: s.pts, interiorHeight: crop.height)
        if PointerArrow.flat {   // TEST ONLY (REEL_V31_FLAT=1): a flat grey picture, to measure the drawn arrow alone
            img = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: img.extent)
        }
        img = try PointerArrow.sprite(left: arrowLeft, interiorHeight: crop.height).composited(over: img)
        let outW = (crop.width * scale).rounded(), outH = (crop.height * scale).rounded()
        let sx = outW / crop.width, sy = outH / crop.height
        img = img.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy])
        guard let cg = ci.createCGImage(img, from: CGRect(x: 0, y: 0, width: outW, height: outH), format: .BGRA8, colorSpace: srgb) else {
            throw NSError(domain: "Clip", code: 4, userInfo: [NSLocalizedDescriptionKey: "render failed \(id) \(t) (pointer)"])
        }
        return cg
    }
}

/// A still (the portrait harness screenshot), cropped to its interior once.
func loadStill(_ url: URL, crop: CGRect, ci: CIContext) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return full.cropping(to: crop)
}
