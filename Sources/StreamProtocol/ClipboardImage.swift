import Foundation
import ImageIO

/// An image as the clipboard sends it (generation 2), both ends: a PNG or JPEG within the cap as it is,
/// anything else ImageIO reads (macOS's TIFF, the iPhone's HEIC) or anything bigger re-encoded to fit
/// (Noah's call, 2026-11-02: up to 8 MB as is, bigger ones re-encoded). Checked by Tests/checks/clipboard.
public enum ClipboardImage {
    /// `data` ready to send: as it is when a PNG or JPEG within `max`; else a PNG of it when that fits
    /// (a TIFF of a screenshot stays sharp); else a JPEG at 0.85, scaled down until it fits. Nil when
    /// ImageIO cannot read it or nothing fits.
    public static func fitted(_ data: Data, max: Int = Clipboard.maxImageBytes) -> Data? {
        if data.count <= max, Clipboard.imageType(data) != nil { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        if Clipboard.imageType(data) == nil, let png = encode(image, type: "public.png"), png.count <= max { return png }
        var side = CGFloat(Swift.max(image.width, image.height))
        for _ in 0..<8 {
            let fitted = side >= CGFloat(Swift.max(image.width, image.height)) ? image : scaled(image, longerSide: side)
            guard let fitted, let jpeg = encode(fitted, type: "public.jpeg", quality: 0.85) else { return nil }
            if jpeg.count <= max { return jpeg }
            side *= Swift.max(0.5, (Double(max) / Double(jpeg.count)).squareRoot() * 0.9)
            guard side >= 16 else { return nil }
        }
        return nil
    }

    private static func encode(_ image: CGImage, type: String, quality: Double? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type as CFString, 1, nil) else { return nil }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(dest, image, options)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private static func scaled(_ image: CGImage, longerSide: CGFloat) -> CGImage? {
        let s = longerSide / CGFloat(Swift.max(image.width, image.height))
        let w = Swift.max(1, Int(CGFloat(image.width) * s)), h = Swift.max(1, Int(CGFloat(image.height) * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
