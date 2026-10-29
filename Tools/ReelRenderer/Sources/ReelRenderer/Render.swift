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
        renderer.proposedSize = ProposedViewSize(Stage.size)
        bufA = makeBuffer(); bufB = makeBuffer(); bufC = makeBuffer()
        buildVignette()
        buildGrain()
    }

    private func makeBuffer() -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, Stage.width, Stage.height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ] as CFDictionary, &pb)
        return pb!
    }

    /// Radial darkening, 0 % at the centre to 18 % at the corners (quadratic).
    private func buildVignette() {
        let w = Stage.width, h = Stage.height
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
    private func buildGrain() {
        grainTiles = []
        ditherTiles = []
        var drng = SplitMix64(seed: 0xD17E)
        for _ in 0..<8 {
            var px = [Float](repeating: 1, count: 512 * 512 * 4)
            for i in 0..<(512 * 512) {
                for c in 0..<3 {
                    let u = Double(drng.next() % 100_000) / 100_000, v = Double(drng.next() % 100_000) / 100_000
                    px[i * 4 + c] = Float(0.5 + (u + v - 1) * 1.5 / 255)
                }
            }
            let data = Data(bytes: px, count: px.count * 4)
            ditherTiles.append(CIImage(bitmapData: data, bytesPerRow: 512 * 16, size: CGSize(width: 512, height: 512),
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
            let provider = CGDataProvider(data: Data(px) as CFData)!
            let cg = CGImage(width: 512, height: 512, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 512 * 4, space: sRGB,
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            grainTiles.append(CIImage(cgImage: cg))
        }
    }

    /// Renders a SwiftUI view into a buffer (cleared to transparent, or black when `opaque`).
    func draw(_ view: AnyView, into pb: CVPixelBuffer, opaque: Bool) {
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Stage.width, height: Stage.height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if opaque {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: Stage.size))
        } else {
            ctx.clear(CGRect(origin: .zero, size: Stage.size))
        }
        ctx.interpolationQuality = .high
        renderer.content = view
        renderer.render { _, render in render(ctx) }
        CVPixelBufferUnlockBaseAddress(pb, [])
    }

    /// Composes one frame into `out` (a writer pool buffer).
    func compose(_ layers: FrameLayers, frame index: Int, into out: CVPixelBuffer) {
        let img = composeImage(layers, frame: index)
        let canvas = CGRect(origin: .zero, size: Stage.size)
        ci.render(img, to: out, bounds: canvas, colorSpace: sRGB)
    }

    /// The finished frame as a Core Image graph (SwiftUI layers already drawn into buffers).
    func composeImage(_ layers: FrameLayers, frame index: Int) -> CIImage {
        draw(layers.base, into: bufA, opaque: true)
        var img = CIImage(cvPixelBuffer: bufA, options: [.colorSpace: sRGB])
        let canvas = CGRect(origin: .zero, size: Stage.size)
        if let (other, w) = layers.mix, w > 0.001 {
            draw(other, into: bufC, opaque: true)
            let b = CIImage(cvPixelBuffer: bufC, options: [.colorSpace: sRGB])
            img = CIFilter(name: "CIDissolveTransition", parameters: [kCIInputImageKey: img, kCIInputTargetImageKey: b,
                                                                      kCIInputTimeKey: w])!.outputImage!.cropped(to: canvas)
        }
        if layers.baseBlur > 0.05 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: layers.baseBlur).cropped(to: canvas)
        }
        if let r = layers.rack, r.blur > 0.01 || r.scale < 0.9999 || r.brightness < 0.9999 {
            if abs(r.scale - 1) > 1e-5 {
                let s = CGFloat(r.scale)
                img = img.transformed(by: CGAffineTransform(translationX: 960, y: 540).scaledBy(x: s, y: s).translatedBy(x: -960, y: -540))
                    .composited(over: CIImage(color: .black).cropped(to: canvas))
            }
            if r.blur > 0.01 {
                img = img.clampedToExtent().applyingGaussianBlur(sigma: r.blur).cropped(to: canvas)
            }
            let b = CGFloat(r.brightness)
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: b, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: b, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        }
        if let overlay = layers.overlay {
            draw(overlay, into: bufB, opaque: false)
            let o = CIImage(cvPixelBuffer: bufB, options: [.colorSpace: sRGB])
            img = o.composited(over: img)
        }
        if layers.vignette { img = vignette.composited(over: img) }
        if layers.grain {
            var rng = SplitMix64(seed: UInt64(index) &* 0x9E3779B97F4A7C15 &+ 7)
            let ox = CGFloat(rng.next() % 512), oy = CGFloat(rng.next() % 512)
            let tile = grainTiles[index % 8]
            // Tile the 512² noise across the canvas from a random offset.
            var tiled = CIImage.empty()
            var ty: CGFloat = -oy
            while ty < CGFloat(Stage.height) {
                var tx: CGFloat = -ox
                while tx < CGFloat(Stage.width) {
                    tiled = tile.transformed(by: CGAffineTransform(translationX: tx, y: ty)).composited(over: tiled)
                    tx += 512
                }
                ty += 512
            }
            tiled = tiled.cropped(to: canvas)
            img = tiled.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: canvas)
        }
        if dither, let k = ditherKernel {
            var rng = SplitMix64(seed: UInt64(index) &* 0xA24BAED4963EE407 &+ 3)
            let ox = CGFloat(rng.next() % 512), oy = CGFloat(rng.next() % 512)
            var noise = CIImage.empty()
            var ty: CGFloat = -oy
            while ty < CGFloat(Stage.height) {
                var tx: CGFloat = -ox
                while tx < CGFloat(Stage.width) {
                    noise = ditherTiles[(index + 3) % 8].transformed(by: CGAffineTransform(translationX: tx, y: ty)).composited(over: noise)
                    tx += 512
                }
                ty += 512
            }
            if let d = k.apply(extent: canvas, arguments: [img, noise.cropped(to: canvas)]) { img = d }
        }
        return img.cropped(to: canvas)
    }

    /// Renders layers to a CGImage (for stills and checks), with the same finish.
    func still(_ layers: FrameLayers, frame index: Int) -> CGImage {
        let img = composeImage(layers, frame: index)
        return ci.createCGImage(img, from: CGRect(origin: .zero, size: Stage.size), format: .RGBA8, colorSpace: sRGB)!
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

// MARK: - Writer (§1: H.264 High, 24 Mbps, keyframe every 120, no reordering, BT.709)

final class VideoWriter {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    /// v2 final: Apple's software H.264 encoder by default, so a render never competes with Sill.app (which
    /// shares the Mac's hardware encoder, and whose hardware session hung twice during the captures).
    /// `SILL_HW_ENCODER=1` goes back to VideoToolbox's default (hardware) choice.
    static let software = ProcessInfo.processInfo.environment["SILL_HW_ENCODER"] == nil
    static let softwareEncoderID = "com.apple.videotoolbox.videoencoder.h264"

    init(url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Stage.width,
            AVVideoHeightKey: Stage.height,
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
        print("video encoder: \(VideoWriter.software ? "software H.264 (\(VideoWriter.softwareEncoderID))" : "VideoToolbox default (hardware H.264)")")
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Stage.width,
            kCVPixelBufferHeightKey as String: Stage.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Writer", code: 1) }
        writer.startSession(atSourceTime: .zero)
    }

    func append(frame index: Int, fill: (CVPixelBuffer) -> Void) throws {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.001) }
        var pb: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else {
            throw NSError(domain: "Writer", code: 2, userInfo: [NSLocalizedDescriptionKey: "no pixel buffer"])
        }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        fill(buffer)
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: 60)) else {
            throw writer.error ?? NSError(domain: "Writer", code: 3)
        }
    }

    func finish() throws {
        input.markAsFinished()
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
