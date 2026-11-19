// Compares two pictures pixel by pixel (harness-photos' compare): each is decoded with ImageIO and
// drawn into an 8-bit RGBA bitmap in sRGB at its own pixel size, and every pixel's four channels are
// compared. Prints one JSON object: the sizes, how many pixels differ (any channel by more than the
// tolerance, 0 by default), the largest channel difference, the mean over the differing pixels, and the
// box that holds them. With a third path, writes a picture of the differences there: the new picture
// at a quarter of its brightness, each differing pixel red.
//
//   swiftc -O pixeldiff.swift -o pixeldiff
//   pixeldiff BASE.png NEW.png [DIFF.png] [--tolerance N]
//   pixeldiff --uniform FILE.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("pixeldiff: " + message + "\n").data(using: .utf8)!)
    exit(2)
}

struct Bitmap {
    let width: Int, height: Int
    var bytes: [UInt8]
}

func load(_ path: String) -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("cannot read \(path)") }
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    if !ok { fail("cannot draw \(path)") }
    return Bitmap(width: w, height: h, bytes: bytes)
}

var args = Array(CommandLine.arguments.dropFirst())
// `pixeldiff --uniform FILE`: whether every pixel of one picture is the same colour (a photo of a
// display the app was not on, or had not drawn yet): exit 0 and {"uniform":true}, else exit 1.
if args.count == 2 && args[0] == "--uniform" {
    let p = load(args[1])
    var uniform = true
    var o = 4
    while o < p.bytes.count {
        if p.bytes[o] != p.bytes[0] || p.bytes[o + 1] != p.bytes[1] || p.bytes[o + 2] != p.bytes[2] || p.bytes[o + 3] != p.bytes[3] {
            uniform = false
            break
        }
        o += 4
    }
    print("{\"uniform\":\(uniform),\"width\":\(p.width),\"height\":\(p.height)}")
    exit(uniform ? 0 : 1)
}
var tolerance = 0
if let i = args.firstIndex(of: "--tolerance"), i + 1 < args.count, let t = Int(args[i + 1]) {
    tolerance = t
    args.removeSubrange(i...(i + 1))
}
guard args.count == 2 || args.count == 3 else { fail("usage: pixeldiff BASE.png NEW.png [DIFF.png] [--tolerance N]") }
let a = load(args[0]), b = load(args[1])
var result: [String: Any] = ["base": ["width": a.width, "height": a.height], "new": ["width": b.width, "height": b.height],
                             "tolerance": tolerance]
guard a.width == b.width && a.height == b.height else {
    result["sameSize"] = false
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
    exit(1)
}
result["sameSize"] = true
var differing = 0, maxDelta = 0, sumDelta = 0
var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
var diff = b
for y in 0..<a.height {
    for x in 0..<a.width {
        let o = (y * a.width + x) * 4
        var d = 0
        for c in 0..<4 { d = max(d, abs(Int(a.bytes[o + c]) - Int(b.bytes[o + c]))) }
        if d > tolerance {
            differing += 1
            maxDelta = max(maxDelta, d)
            sumDelta += d
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            diff.bytes[o] = 255; diff.bytes[o + 1] = 0; diff.bytes[o + 2] = 0; diff.bytes[o + 3] = 255
        } else {
            for c in 0..<3 { diff.bytes[o + c] = diff.bytes[o + c] / 4 }
        }
    }
}
result["differingPixels"] = differing
result["totalPixels"] = a.width * a.height
result["maxChannelDelta"] = maxDelta
result["meanChannelDelta"] = differing > 0 ? Double(sumDelta) / Double(differing) : 0
if differing > 0 { result["box"] = ["x": minX, "y": minY, "width": maxX - minX + 1, "height": maxY - minY + 1] }
if args.count == 3 && differing > 0 {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    var bytes = diff.bytes
    let image: CGImage? = bytes.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: diff.width, height: diff.height, bitsPerComponent: 8,
                  bytesPerRow: diff.width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    if let image, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                              UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, image, nil)
        if CGImageDestinationFinalize(dest) { result["diffPicture"] = args[2] }
    }
}
let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
exit(differing == 0 ? 0 : 1)
