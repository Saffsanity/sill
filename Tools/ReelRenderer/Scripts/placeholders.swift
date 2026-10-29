// placeholders.swift — stand-in inputs for ReelRenderer, so any shot can be rendered without real footage.
//
//   swift Scripts/placeholders.swift work [--clips all|none|r01,n3,…] [--fps 4]
//
// Writes, under the folder given (the renderer's `reelDir`: `REEL_DIR`, else `work/` beside Package.swift):
//   capture/final-portrait.png, v3/shots/*.png             2064×2752 test patterns (the iPad simulator's portrait screen)
//   v3/mac-previews/pairing-{waiting,paired}-dark.png      a dark stand-in for the Mac's pairing window
//   real-captures/*.mov, capture/final-*.mov               2064×2752 test-pattern clips covering each clip's approved
//                                                          segment, with the clip's name and clip time burned in
//   v31/s18/{arrow-56x80.png, plate-band.png, recorded-arrow-subpx.csv}   S18's assets (the arrow is AppKit's own)
// Every file says PLACEHOLDER on it. Clips are H.264 from Apple's software encoder (never the hardware encoder, which
// Sill.app shares). Apple frameworks only.
import AppKit
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import VideoToolbox

let W = 2064, H = 2752
let landscape = CGRect(x: 32, y: 666, width: 2000, height: 1420)   // top-left origin, as the renderer's interiorRect
let portrait = CGRect(x: 322, y: 376, width: 1420, height: 2000)   // the renderer's portraitRect
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

var args = Array(CommandLine.arguments.dropFirst())
guard let dirArg = args.first else {
    print("usage: swift placeholders.swift <reel-dir> [--clips all|none|r01,n3,…] [--fps 4]"); exit(2)
}
let root = URL(fileURLWithPath: dirArg, isDirectory: true)
var clipChoice = "all"
var fps = 4.0
if let i = args.firstIndex(of: "--clips"), i + 1 < args.count { clipChoice = args[i + 1] }
if let i = args.firstIndex(of: "--fps"), i + 1 < args.count, let v = Double(args[i + 1]) { fps = v }

/// Each clip: file, the end of its last approved segment (s), and its hue.
let clips: [(id: String, file: String, end: Double, hue: CGFloat)] = [
    ("r01", "real-captures/01-connect-desktop.mov", 4.70, 0.58),
    ("r02", "real-captures/02-drawer-launch.mov", 20.0, 0.08),
    ("r04", "real-captures/04-pick-vscode.mov", 23.0, 0.66),
    ("r05", "real-captures/05-pick-blender.mov", 40.2, 0.05),
    ("r07", "real-captures/07-aa-ruler.mov", 10.3, 0.33),
    ("r08", "real-captures/08-settings-panel.mov", 24.0, 0.75),
    ("htA", "capture/final-desktop.mov", 8.1, 0.50),
    ("htB", "capture/final-aa.mov", 8.1, 0.15),
    ("htD", "capture/final-lights.mov", 8.1, 0.95),
    ("htE", "capture/final-rows.mov", 8.1, 0.40),
    ("n1", "real-captures/11-window-to-desktop.mov", 4.95, 0.62),
    ("n2", "real-captures/12-aa-resize-weather.mov", 13.35, 0.28),
    ("n3", "real-captures/13-trackpad-pointer.mov", 5.40, 0.85),
]

func ctx(_ w: Int, _ h: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    CGContext(data: data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: srgb,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// Text centred on a point (top-left coordinates), in a CG context whose origin is bottom-left.
func text(_ c: CGContext, _ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .semibold, alpha: CGFloat = 0.92) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 1, alpha: alpha)]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let b = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let hgt = CGFloat(c.height)
    c.textPosition = CGPoint(x: p.x - b.width / 2 - b.minX, y: hgt - p.y - (b.height / 2 + b.minY))
    CTLineDraw(line, c)
}

/// The test pattern: a dark frame, a grid every 100 px, both interiors outlined, colour bars and a label.
func pattern(_ c: CGContext, hue: CGFloat, title: String, subtitle: String, phase: Double) {
    let w = CGFloat(c.width), h = CGFloat(c.height)
    func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
    c.setFillColor(NSColor(calibratedHue: hue, saturation: 0.35, brightness: 0.16, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    c.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); c.setLineWidth(2)
    var x: CGFloat = 0
    while x <= w { c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: h)); x += 100 }
    var y: CGFloat = 0
    while y <= h { c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)); y += 100 }
    c.strokePath()
    // Colour bars across the landscape interior's top third.
    let bars = 8
    for i in 0..<bars {
        let r = CGRect(x: landscape.minX + CGFloat(i) * landscape.width / CGFloat(bars), y: landscape.minY + 120,
                       width: landscape.width / CGFloat(bars), height: 180)
        c.setFillColor(NSColor(calibratedHue: (hue + CGFloat(i) / CGFloat(bars)).truncatingRemainder(dividingBy: 1),
                               saturation: 0.55, brightness: 0.75, alpha: 1).cgColor)
        c.fill(flip(r))
    }
    // A bar that sweeps across, so motion and clip time read on screen.
    let sweep = CGFloat(phase.truncatingRemainder(dividingBy: 4) / 4)
    c.setFillColor(CGColor(gray: 1, alpha: 0.55))
    c.fill(flip(CGRect(x: landscape.minX + sweep * (landscape.width - 40), y: landscape.maxY - 260, width: 40, height: 200)))
    c.setStrokeColor(CGColor(srgbRed: 1, green: 0.8, blue: 0.2, alpha: 0.8)); c.setLineWidth(6); c.stroke(flip(landscape))
    c.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.9, blue: 1, alpha: 0.6)); c.setLineWidth(4); c.stroke(flip(portrait))
    text(c, "PLACEHOLDER", at: CGPoint(x: w / 2, y: 1100), size: 150, weight: .heavy, alpha: 0.85)
    text(c, title, at: CGPoint(x: w / 2, y: 1330), size: 120, weight: .bold)
    text(c, subtitle, at: CGPoint(x: w / 2, y: 1520), size: 70, weight: .medium, alpha: 0.75)
}

func writePNG(_ img: CGImage, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw NSError(domain: "png", code: 1) }
    CGImageDestinationAddImage(d, img, nil)
    guard CGImageDestinationFinalize(d) else { throw NSError(domain: "png", code: 2) }
}

func still(_ rel: String, title: String, subtitle: String, hue: CGFloat, w: Int = W, h: Int = H) throws {
    let c = ctx(w, h)
    if w == W && h == H {
        pattern(c, hue: hue, title: title, subtitle: subtitle, phase: 0)
    } else {
        c.setFillColor(CGColor(gray: 0.17, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
        text(c, "PLACEHOLDER", at: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) * 0.42), size: CGFloat(w) / 9, weight: .heavy, alpha: 0.85)
        text(c, title, at: CGPoint(x: CGFloat(w) / 2, y: CGFloat(h) * 0.55), size: CGFloat(w) / 16)
    }
    try writePNG(c.makeImage()!, root.appendingPathComponent(rel))
    print("still \(rel)")
}

// MARK: - Stills

try still("capture/final-portrait.png", title: "HT-C · portrait harness still", subtitle: "capture/final-portrait.png", hue: 0.55)
for (name, label) in [("c0", "connect screen, no rows"), ("c1", "MacBook Pro · Wi-Fi"), ("c2", "+ Mac Studio · Wired"),
                      ("c3", "+ MacBook Air · Direct"), ("c4", "+ Mac mini · Remote"), ("p-addmac", "Add a Mac"),
                      ("p-paired", "paired"), ("s-remote", "Settings: through Tailscale")] {
    try still("v3/shots/\(name).png", title: "\(name) · \(label)", subtitle: "v3/shots/\(name).png", hue: 0.6)
}
for name in ["pairing-waiting-dark", "pairing-paired-dark"] {
    try still("v3/mac-previews/\(name).png", title: name, subtitle: "", hue: 0, w: 840, h: 1040)
}

// MARK: - S18's assets: AppKit's own arrow, a flat plate, and a recorded-arrow table for the placeholder clip

do {
    let dir = root.appendingPathComponent("v31/s18")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let image = NSCursor.arrow.image
    // The representation nearest 2× (56×80 on current macOS), as the host streams it.
    let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
    let rep = reps.min { abs($0.pixelsWide - 56) < abs($1.pixelsWide - 56) }
    var arrow: CGImage? = rep?.cgImage
    if arrow == nil || arrow!.width != 56 || arrow!.height != 80 {
        // Draw the cursor image at 56×80 when no bitmap representation of that size exists.
        let c = CGContext(data: nil, width: 56, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: 56, height: 80))
        NSGraphicsContext.restoreGraphicsState()
        arrow = c.makeImage()
    }
    try writePNG(arrow!, dir.appendingPathComponent("arrow-56x80.png"))
    let plate = ctx(1420, 160)
    plate.setFillColor(CGColor(gray: 0.2, alpha: 1)); plate.fill(CGRect(x: 0, y: 0, width: 1420, height: 160))
    try writePNG(plate.makeImage()!, dir.appendingPathComponent("plate-band.png"))
    // One row per sample of the placeholder clip 13 (pts at 1/fps steps): the recorded arrow's left edge.
    var csv = "pts,top,left\n"
    var t = 0.0
    while t <= 5.40 + 1e-9 { csv += String(format: "%.4f,490,%.3f\n", t, 400 + 100 * t); t += 1 / fps }
    try csv.write(to: dir.appendingPathComponent("recorded-arrow-subpx.csv"), atomically: true, encoding: .utf8)
    print("s18 assets in \(dir.path)")
}

// MARK: - Clips

func writeClip(_ c: (id: String, file: String, end: Double, hue: CGFloat)) throws {
    let url = root.appendingPathComponent(c.file)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoAllowFrameReorderingKey: false],
        AVVideoEncoderSpecificationKey: [
            kVTVideoEncoderSpecification_EncoderID as String: "com.apple.videotoolbox.videoencoder.h264",
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false,
        ] as [String: Any],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "clip", code: 1) }
    writer.startSession(atSourceTime: .zero)
    let n = Int((c.end * fps).rounded(.up)) + 2
    for i in 0..<n {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        guard let buf = pb else { throw NSError(domain: "clip", code: 2) }
        CVPixelBufferLockBaseAddress(buf, [])
        let g = ctx(W, H, data: CVPixelBufferGetBaseAddress(buf), bytesPerRow: CVPixelBufferGetBytesPerRow(buf))
        let t = Double(i) / fps
        pattern(g, hue: c.hue, title: "clip \(c.id) · \(String(format: "%.2f", t)) s", subtitle: c.file, phase: t)
        CVPixelBufferUnlockBaseAddress(buf, [])
        guard adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i * 1000), timescale: CMTimeScale(fps * 1000))) else {
            throw writer.error ?? NSError(domain: "clip", code: 3)
        }
    }
    input.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "clip", code: 4) }
    print("clip \(c.id) \(c.file): \(n) frames at \(fps) fps")
}

let chosen: [String]
switch clipChoice {
case "all": chosen = clips.map { $0.id }
case "none": chosen = []
default: chosen = clipChoice.split(separator: ",").map(String.init)
}
for c in clips where chosen.contains(c.id) { try writeClip(c) }
print("placeholders written under \(root.path)")
