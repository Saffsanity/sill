// check.swift — reads movies and images with AVFoundation / ImageIO (never writes a movie). Run with
// `swift Scripts/check.swift …`, or compile it once with `swiftc -O Scripts/check.swift -o .build/check`.
//   check info <movie>…                       duration, size, nominal rate, frames, sync frames, codec, first/last PTS
//   check ends <movie> <out-dir>              decodes every frame; writes the first and the last as PNG
//   check grab <movie> <out-dir> <t>…         decodes the frames at reel times t (exact, no tolerance) to PNG
//   check psnr <a.png> <b.png> [x,y,w,h]      PSNR and mean |Δ| over RGB (optionally inside a rect, top-left px)
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

func loadSync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    var result: Result<T, Error>!
    Task.detached { do { result = .success(try await body()) } catch { result = .failure(error) }; sem.signal() }
    sem.wait()
    return try result.get()
}

func writePNG(_ img: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

func image(from pb: CVPixelBuffer) -> CGImage {
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let img = ctx.makeImage()!
    CVPixelBufferUnlockBaseAddress(pb, .readOnly)
    return img
}

func fourcc(_ v: FourCharCode) -> String {
    String(bytes: [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)], encoding: .ascii) ?? "?"
}

let a = Array(CommandLine.arguments.dropFirst())
switch a.first {
case "info":
    for path in a.dropFirst() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let (track, duration) = try loadSync { () -> (AVAssetTrack, CMTime) in
            (try await asset.loadTracks(withMediaType: .video).first!, try await asset.load(.duration)) }
        let (size, rate, formats) = try loadSync { () -> (CGSize, Float, [CMFormatDescription]) in
            (try await track.load(.naturalSize), try await track.load(.nominalFrameRate), try await track.load(.formatDescriptions)) }
        let audio = try loadSync { try await asset.loadTracks(withMediaType: .audio).count }
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(out); reader.startReading()
        var n = 0, sync = 0
        var first = -1.0, last = -1.0
        while let s = out.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(s) > 0 else { continue }
            n += 1
            let t = CMSampleBufferGetPresentationTimeStamp(s).seconds
            if first < 0 { first = t }; last = max(last, t)
            let att = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: false) as? [[CFString: Any]]
            if att?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true { sync += 1 }
        }
        let codec = formats.first.map { fourcc(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        print(String(format: "%@: %.3f s, %dx%d, %.2f fps nominal, %d frames (%d sync), codec %@, PTS %.4f…%.4f s, audio tracks %d, %.1f Mbps, %d bytes",
                     (path as NSString).lastPathComponent, duration.seconds, Int(size.width), Int(size.height), rate, n, sync, codec,
                     first, last, audio, Double(bytes) * 8 / max(duration.seconds, 1e-9) / 1e6, bytes))
    }
case "ends":
    let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
    let track = try loadSync { try await asset.loadTracks(withMediaType: .video).first! }
    let reader = try AVAssetReader(asset: asset)
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(out); reader.startReading()
    var firstImg: CGImage?, lastImg: CGImage?
    var n = 0
    var lastT = 0.0
    while let s = out.copyNextSampleBuffer() {
        guard let pb = CMSampleBufferGetImageBuffer(s) else { continue }
        n += 1
        lastT = CMSampleBufferGetPresentationTimeStamp(s).seconds
        if firstImg == nil { firstImg = image(from: pb) }
        lastImg = image(from: pb)
    }
    let base = ((a[1] as NSString).lastPathComponent as NSString).deletingPathExtension
    writePNG(firstImg!, "\(a[2])/\(base)-first.png"); writePNG(lastImg!, "\(a[2])/\(base)-last.png")
    print(String(format: "%@: decoded %d frames; first and last (PTS %.4f s) written, %dx%d", base, n, lastT, lastImg!.width, lastImg!.height))
case "grab":
    let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
    let gen = AVAssetImageGenerator(asset: asset)
    gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
    let base = ((a[1] as NSString).lastPathComponent as NSString).deletingPathExtension
    for ts in a.dropFirst(3) {
        let t = Double(ts)!
        var actual = CMTime.zero
        let cg = try gen.copyCGImage(at: CMTime(value: CMTimeValue((t * 60).rounded()), timescale: 60), actualTime: &actual)
        writePNG(cg, "\(a[2])/\(base)-\(ts).png")
        print(String(format: "%@ at %.4f (asked %@)", base, actual.seconds, ts))
    }
case "psnr":
    func load(_ p: String) -> (Int, Int, [UInt8]) {
        let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil)!
        let img = CGImageSourceCreateImageAtIndex(s, 0, nil)!
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (w, h, buf)
    }
    let (w, h, p) = load(a[1]); let (w2, h2, q) = load(a[2])
    guard w == w2, h == h2 else { print("size differs: \(w)x\(h) vs \(w2)x\(h2)"); exit(1) }
    var rect = CGRect(x: 0, y: 0, width: w, height: h)
    if a.count > 3 { let f = a[3].split(separator: ",").map { Double($0)! }; rect = CGRect(x: f[0], y: f[1], width: f[2], height: f[3]) }
    var se = 0.0, sa = 0.0, n = 0.0, worst = 0, over8 = 0
    for y in Int(rect.minY)..<Int(rect.maxY) {
        let row = h - 1 - y   // CG buffers run bottom-up
        for x in Int(rect.minX)..<Int(rect.maxX) {
            let i = (row * w + x) * 4
            var px = 0
            for c in 0..<3 {
                let d = Int(p[i + c]) - Int(q[i + c])
                se += Double(d * d); sa += Double(abs(d)); n += 1; worst = max(worst, abs(d)); px = max(px, abs(d))
            }
            if px > 8 { over8 += 1 }
        }
    }
    let mse = se / n
    print(String(format: "PSNR %.2f dB, mean |Δ| %.3f, worst %d, pixels off by more than 8: %d of %d",
                 mse == 0 ? 99.0 : 10 * log10(255 * 255 / mse), sa / n, worst, over8, Int(rect.width * rect.height)))
default:
    print("usage: check info|ends|grab|psnr …"); exit(2)
}
