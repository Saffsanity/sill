// Render.swift — per-frame composition: SwiftUI (ImageRenderer) layers into IOSurface buffers, then a
// GPU Core Image pass for the rack focus, the grain and the vignette (§3.6), into the writer's buffers.
import AVFoundation
import CoreImage
import CoreVideo
import Metal
import SwiftUI
import VideoToolbox

/// What a shot hands the compositor for one frame.
struct FrameLayers {
    var base: AnyView                          // full canvas, opaque (black where empty)
    var rack: Rack? = nil                      // rack focus applied to `base` on the GPU
    var overlay: AnyView? = nil                // sharp layer over the (racked) base: type
    var baseBlur: Double = 0                   // extra GPU blur of the base (S19's background)
    var grain = true
    var vignette = true
    /// A second base to mix in (cross-dissolves), with its weight.
    var mix: (AnyView, Double)? = nil
}

struct Rack { var blur: Double; var brightness: Double; var scale: Double }

/// §3.5 rack focus: blur 0→28, brightness 1→0.32, scale 1→0.97 over 0.30 s appleOut.
func rackState(_ t: Double, start: Double) -> Rack {
    let p = ease(t, start, 0.30, .appleOut)
    return Rack(blur: 28 * p, brightness: 1 - 0.68 * p, scale: 1 - 0.03 * p)
}

@MainActor
final class Compositor {
    let ci: CIContext
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private var bufA: CVPixelBuffer!
    private var bufB: CVPixelBuffer!
    private var bufC: CVPixelBuffer!
    private let renderer = ImageRenderer(content: AnyView(EmptyView()))
    private(set) var vignette: CIImage!
    private var grainTiles: [CIImage] = []
    private var ditherTiles: [CIImage] = []
    var grainAmplitude: Double = 3      // ±n/255 around mid-grey, soft-light
    var dither = true                   // ±1.5/255 before the 8-bit write, faded out toward pure black
    /// Additive dither scaled by the pixel's luma (0 at pure black, full from 12/255), so the glows'
    /// 8-bit steps break up while #000 stays #000.
    private let ditherKernel = CIColorKernel(source: """
        kernel vec4 sillDither(__sample img, __sample noise) {
            float luma = dot(img.rgb, vec3(0.2126, 0.7152, 0.0722));
            float m = clamp(luma * 21.0, 0.0, 1.0);
            return vec4(img.rgb + (noise.rgb - 0.5) * m, img.a);
        }
        """)

    init() {
        let device = MTLCreateSystemDefaultDevice()!
        ci = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false,
        ])
        renderer.scale = 1
        // The 4K pass: at an output scale the content is `Stage.rasterised`, laid out in the drawing's 1920×1080 and drawn
        // into the pixel frame.
        renderer.proposedSize = ProposedViewSize(Stage.scaled ? Stage.pixelSize : Stage.size)
        bufA = makeBuffer(); bufB = makeBuffer(); bufC = makeBuffer()
        buildVignette()
        buildGrain()
    }

    private func makeBuffer() -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, Stage.pixelWidth, Stage.pixelHeight, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ] as CFDictionary, &pb)
        return pb!
    }

    /// Radial darkening, 0 % at the centre to 18 % at the corners (quadratic), over the output frame (the same fall-off, in
    /// fractions of the frame's half-diagonal, at every output scale).
    private func buildVignette() {
        let w = Stage.pixelWidth, h = Stage.pixelHeight
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cx = Double(w) / 2, cy = Double(h) / 2, R = (cx * cx + cy * cy).squareRoot()
        for y in 0..<h {
            for x in 0..<w {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                let r = (dx * dx + dy * dy).squareRoot() / R
                let a = 0.18 * r * r
                px[(y * w + x) * 4 + 3] = UInt8((a * 255).rounded())      // black, premultiplied
            }
        }
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: sRGB,
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        vignette = CIImage(cgImage: cg)
    }

    /// Eight 512×512 monochrome noise tiles around mid-grey (triangular distribution, ±amplitude/255),
    /// and eight RGB dither tiles (±1.5/255, triangular) stored in float so no step is lost.
    /// The 4K pass: at an output scale `k` each tile is the same 512×512 values, each a k×k block of pixels (512k px a
    /// side), so the grain and the dither keep the 1080p's cell size on the drawing (2×2 output px at 4K), not finer.
    private func buildGrain() {
        grainTiles = []
        ditherTiles = []
        let k = Int(Stage.scale), side = 512 * k
        var drng = SplitMix64(seed: 0xD17E)
        for _ in 0..<8 {
            var px = [Float](repeating: 1, count: 512 * 512 * 4)
            for i in 0..<(512 * 512) {
                for c in 0..<3 {
                    let u = Double(drng.next() % 100_000) / 100_000, v = Double(drng.next() % 100_000) / 100_000
                    px[i * 4 + c] = Float(0.5 + (u + v - 1) * 1.5 / 255)
                }
            }
            if k > 1 { px = Compositor.blocks(px, side: 512, k: k) }
            let data = Data(bytes: px, count: px.count * 4)
            ditherTiles.append(CIImage(bitmapData: data, bytesPerRow: side * 16, size: CGSize(width: side, height: side),
                                       format: .RGBAf, colorSpace: nil))
        }
        var rng = SplitMix64(seed: 0x5111)
        for _ in 0..<8 {
            var px = [UInt8](repeating: 255, count: 512 * 512 * 4)
            for i in 0..<(512 * 512) {
                let u = Double(rng.next() % 10_000) / 10_000, v = Double(rng.next() % 10_000) / 10_000
                let n = (u + v - 1) * grainAmplitude           // triangular in [−a, a]
                let g = UInt8(max(0, min(255, (128 + n).rounded())))
                px[i * 4] = g; px[i * 4 + 1] = g; px[i * 4 + 2] = g
            }
            if k > 1 { px = Compositor.blocks(px, side: 512, k: k) }
            let provider = CGDataProvider(data: Data(px) as CFData)!
            let cg = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4, space: sRGB,
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            grainTiles.append(CIImage(cgImage: cg))
        }
    }

    /// A square RGBA tile of `side` px, each pixel made a k×k block (`side`·k px a side).
    private static func blocks<T>(_ px: [T], side: Int, k: Int) -> [T] {
        let out = side * k
        var big = [T](repeating: px[0], count: out * out * 4)
        for y in 0..<out {
            let sy = y / k
            for x in 0..<out {
                let s = (sy * side + x / k) * 4, d = (y * out + x) * 4
                big[d] = px[s]; big[d + 1] = px[s + 1]; big[d + 2] = px[s + 2]; big[d + 3] = px[s + 3]
            }
        }
        return big
    }

    /// Renders a SwiftUI view into a buffer (cleared to transparent, or black when `opaque`). At an output scale the view is
    /// `Stage.rasterised` (the drawing at its 1920×1080 points, scaled into the pixel frame).
    func draw(_ view: AnyView, into pb: CVPixelBuffer, opaque: Bool) {
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Stage.pixelWidth, height: Stage.pixelHeight,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if opaque {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: Stage.pixelSize))
        } else {
            ctx.clear(CGRect(origin: .zero, size: Stage.pixelSize))
        }
        ctx.interpolationQuality = .high
        // 0.6.0: glyphs at their exact fractional positions wherever Core Graphics draws text (the reel's type is
        // glyph outlines, GlyphText.swift; this covers any text Core Text draws itself, such as an emoji's bitmap).
        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false)
        ctx.setShouldSubpixelQuantizeFonts(false)
        renderer.content = Stage.scaled ? AnyView(Stage.rasterised(view)) : view
        renderer.render { _, render in render(ctx) }
        CVPixelBufferUnlockBaseAddress(pb, [])
    }

    /// Composes one frame into `out` (a writer pool buffer).
    func compose(_ layers: FrameLayers, frame index: Int, into out: CVPixelBuffer) {
        let img = composeImage(layers, frame: index)
        let canvas = CGRect(origin: .zero, size: Stage.pixelSize)
        ci.render(img, to: out, bounds: canvas, colorSpace: sRGB)
    }

    /// The finished frame as a Core Image graph (SwiftUI layers already drawn into buffers).
    func composeImage(_ layers: FrameLayers, frame index: Int) -> CIImage {
        TypeProbe.shared.set { $0.layer = .base }              // typecheck: which layer each glyph is drawn in
        draw(layers.base, into: bufA, opaque: true)
        var img = CIImage(cvPixelBuffer: bufA, options: [.colorSpace: sRGB])
        // Core Image works in output pixels: the canvas, the rack's centre and every blur's sigma are the drawing's × scale.
        let canvas = CGRect(origin: .zero, size: Stage.pixelSize)
        let k = Stage.scale
        if let (other, w) = layers.mix, w > 0.001 {
            TypeProbe.shared.set { $0.layer = .mix }
            draw(other, into: bufC, opaque: true)
            let b = CIImage(cvPixelBuffer: bufC, options: [.colorSpace: sRGB])
            img = CIFilter(name: "CIDissolveTransition", parameters: [kCIInputImageKey: img, kCIInputTargetImageKey: b,
                                                                      kCIInputTimeKey: w])!.outputImage!.cropped(to: canvas)
        }
        if layers.baseBlur > 0.05 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: layers.baseBlur * Double(k)).cropped(to: canvas)
        }
        if let r = layers.rack, r.blur > 0.01 || r.scale < 0.9999 || r.brightness < 0.9999 {
            if abs(r.scale - 1) > 1e-5 {
                let s = CGFloat(r.scale)
                let cx = 960 * k, cy = 540 * k
                img = img.transformed(by: CGAffineTransform(translationX: cx, y: cy).scaledBy(x: s, y: s).translatedBy(x: -cx, y: -cy))
                    .composited(over: CIImage(color: .black).cropped(to: canvas))
            }
            if r.blur > 0.01 {
                img = img.clampedToExtent().applyingGaussianBlur(sigma: r.blur * Double(k)).cropped(to: canvas)
            }
            let b = CGFloat(r.brightness)
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        }
        if let overlay = layers.overlay {
            TypeProbe.shared.set { $0.layer = .overlay }
            draw(overlay, into: bufB, opaque: false)
            let o = CIImage(cvPixelBuffer: bufB, options: [.colorSpace: sRGB])
            img = o.composited(over: img)
        }
        if layers.vignette { img = vignette.composited(over: img) }
        if layers.grain {
            var rng = SplitMix64(seed: UInt64(index) &* 0x9E3779B97F4A7C15 &+ 7)
            let ox = CGFloat(rng.next() % 512) * k, oy = CGFloat(rng.next() % 512) * k
            let tile = grainTiles[index % 8]
            // Tile the 512² noise across the canvas from a random offset (in its cells: k px each at an output scale).
            var tiled = CIImage.empty()
            var ty: CGFloat = -oy
            while ty < CGFloat(Stage.pixelHeight) {
                var tx: CGFloat = -ox
                while tx < CGFloat(Stage.pixelWidth) {
                    tiled = tile.transformed(by: CGAffineTransform(translationX: tx, y: ty)).composited(over: tiled)
                    tx += 512 * k
                }
                ty += 512 * k
            }
            tiled = tiled.cropped(to: canvas)
            img = tiled.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: canvas)
        }
        if dither, let kernel = ditherKernel {
            var rng = SplitMix64(seed: UInt64(index) &* 0xA24BAED4963EE407 &+ 3)
            let ox = CGFloat(rng.next() % 512) * k, oy = CGFloat(rng.next() % 512) * k
            var noise = CIImage.empty()
            var ty: CGFloat = -oy
            while ty < CGFloat(Stage.pixelHeight) {
                var tx: CGFloat = -ox
                while tx < CGFloat(Stage.pixelWidth) {
                    noise = ditherTiles[(index + 3) % 8].transformed(by: CGAffineTransform(translationX: tx, y: ty)).composited(over: noise)
                    tx += 512 * k
                }
                ty += 512 * k
            }
            if let d = kernel.apply(extent: canvas, arguments: [img, noise.cropped(to: canvas)]) { img = d }
        }
        return img.cropped(to: canvas)
    }

    /// Renders layers to a CGImage (for stills and checks), with the same finish.
    func still(_ layers: FrameLayers, frame index: Int) -> CGImage {
        let img = composeImage(layers, frame: index)
        return ci.createCGImage(img, from: CGRect(origin: .zero, size: Stage.pixelSize), format: .RGBA8, colorSpace: sRGB)!
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Writer (§1: H.264 High, 24 Mbps asked, keyframe every 120, no reordering, BT.709; the 0.6 film's rate: Cut060.rate)

final class VideoWriter {
    let writer: AVAssetWriter
    /// v2 final: Apple's software H.264 encoder by default, so a render never competes with Sill.app (which
    /// shares the Mac's hardware encoder, and whose hardware session hung twice during the captures).
    /// `SILL_HW_ENCODER=1` goes back to VideoToolbox's default (hardware) choice.
    static let software = ProcessInfo.processInfo.environment["SILL_HW_ENCODER"] == nil
    static let softwareEncoderID = "com.apple.videotoolbox.videoencoder.h264"

    // v3.1's path: AVAssetWriter compresses (no way to ask for a key frame on a given frame).
    private var input: AVAssetWriterInput!
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor!

    // v4.1's path (`keyframes` given): the same software encoder through a VTCompressionSession, with the same settings,
    // its samples written as they are; a key frame is forced on each frame in `keyframes`. The 0.6 film ends on 0.47 s of
    // true black after the sill line retracts: with AVAssetWriter the encoder left the faint glow's last near-black
    // blocks skipped there (luma 15 and 17 where 16 is wanted), and v4 was clean only because a key frame fell in its
    // tail by chance; a key frame on the first all-black frame makes the black exact.
    private var session: VTCompressionSession?
    private var forced: Set<Int> = []
    private let lock = NSLock()
    private var encoded: [CMSampleBuffer] = []
    private var encodeError: OSStatus = noErr
    private var passthrough: AVAssetWriterInput?

    /// The encoder's rate and level: v3.1's (24 Mbps asked, the level the encoder picks) unless a cut says otherwise.
    struct Rate {
        var averageBitRate = 24_000_000
        var profileLevel: CFString = kVTProfileLevel_H264_High_AutoLevel
    }

    /// `keyframes` given, or `session` (the 0.6 film, whose `rate` is its own), the compression session's path; else
    /// v3.1's AVAssetWriter path, at v3.1's rate.
    init(url: URL, keyframes: Set<Int> = [], session useSession: Bool = false, rate: Rate = Rate()) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        print("video encoder: \(VideoWriter.software ? "software H.264 (\(VideoWriter.softwareEncoderID))" : "VideoToolbox default (hardware H.264)")")
        if keyframes.isEmpty && !useSession {
            var settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Stage.pixelWidth,
                AVVideoHeightKey: Stage.pixelHeight,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 24_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                    AVVideoMaxKeyFrameIntervalKey: 120,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ]
            if VideoWriter.software {
                settings[AVVideoEncoderSpecificationKey] = [
                    kVTVideoEncoderSpecification_EncoderID as String: VideoWriter.softwareEncoderID,
                    kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false,
                ] as [String: Any]
            }
            input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Stage.pixelWidth,
                kCVPixelBufferHeightKey as String: Stage.pixelHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Writer", code: 1) }
            writer.startSession(atSourceTime: .zero)
            return
        }
        forced = keyframes
        let spec: [String: Any] = VideoWriter.software ? [
            kVTVideoEncoderSpecification_EncoderID as String: VideoWriter.softwareEncoderID,
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false,
        ] : [:]
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Stage.pixelWidth,
            kCVPixelBufferHeightKey as String: Stage.pixelHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var s: VTCompressionSession?
        let created = VTCompressionSessionCreate(allocator: nil, width: Int32(Stage.pixelWidth), height: Int32(Stage.pixelHeight),
                                                 codecType: kCMVideoCodecType_H264, encoderSpecification: spec as CFDictionary,
                                                 imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil,
                                                 outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard created == noErr, let session = s else {
            throw NSError(domain: "Writer", code: 5, userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionCreate \(created)"])
        }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: false,
            kVTCompressionPropertyKey_ProfileLevel: rate.profileLevel,
            kVTCompressionPropertyKey_H264EntropyMode: kVTH264EntropyMode_CABAC,
            kVTCompressionPropertyKey_AverageBitRate: rate.averageBitRate,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 120,
            kVTCompressionPropertyKey_ExpectedFrameRate: 60,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        for (k, v) in properties {
            let st = VTSessionSetProperty(session, key: k, value: v as CFTypeRef)
            guard st == noErr else { throw NSError(domain: "Writer", code: 6, userInfo: [NSLocalizedDescriptionKey: "VTSessionSetProperty \(k) \(st)"]) }
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        print("video encoder: through a compression session, \(rate.averageBitRate / 1_000_000) Mbps asked, \(rate.profileLevel), key frames forced at "
              + (keyframes.isEmpty ? "none" : keyframes.sorted().map(String.init).joined(separator: ", ")))
    }

    func append(frame index: Int, fill: (CVPixelBuffer) -> Void) throws {
        if let session {
            guard let pool = VTCompressionSessionGetPixelBufferPool(session) else {
                throw NSError(domain: "Writer", code: 2, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer pool"])
            }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else {
                throw NSError(domain: "Writer", code: 2, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer"])
            }
            VideoWriter.tag(buffer)
            fill(buffer)
            let options: CFDictionary? = forced.contains(index) ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
            let st = VTCompressionSessionEncodeFrame(session, imageBuffer: buffer, presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: 60),
                                                     duration: CMTime(value: 1, timescale: 60), frameProperties: options, infoFlagsOut: nil) { [weak self] status, _, sample in
                guard let self else { return }
                self.lock.lock()
                if status != noErr { self.encodeError = status } else if let sample { self.encoded.append(sample) }
                self.lock.unlock()
            }
            guard st == noErr else { throw NSError(domain: "Writer", code: 3, userInfo: [NSLocalizedDescriptionKey: "VTCompressionSessionEncodeFrame \(st)"]) }
            try drain()
            return
        }
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
        var pb: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else {
            throw NSError(domain: "Writer", code: 2, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer"])
        }
        VideoWriter.tag(buffer)
        fill(buffer)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 60)) else {
            throw writer.error ?? NSError(domain: "Writer", code: 3)
        }
    }

    private static func tag(_ buffer: CVPixelBuffer) {
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }

    /// The compression session's path: writes every sample the encoder has finished, in order (it reorders nothing),
    /// starting the file with the first one's format.
    private func drain() throws {
        lock.lock()
        let ready = encoded
        encoded.removeAll(keepingCapacity: true)
        let err = encodeError
        lock.unlock()
        if err != noErr { throw NSError(domain: "Writer", code: 7, userInfo: [NSLocalizedDescriptionKey: "encoder \(err)"]) }
        for sample in ready {
            if passthrough == nil {
                let i = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: CMSampleBufferGetFormatDescription(sample))
                i.expectsMediaDataInRealTime = false
                writer.add(i)
                guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Writer", code: 1) }
                writer.startSession(atSourceTime: .zero)
                passthrough = i
            }
            while !passthrough!.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
            guard passthrough!.append(sample) else { throw writer.error ?? NSError(domain: "Writer", code: 3) }
        }
    }

    func finish() throws {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            try drain()
            VTCompressionSessionInvalidate(session)
            self.session = nil
            passthrough?.markAsFinished()
        } else {
            input.markAsFinished()
        }
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        if writer.status != .completed { throw writer.error ?? NSError(domain: "Writer", code: 4) }
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
