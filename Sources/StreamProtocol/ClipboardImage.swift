import Foundation
import ImageIO
import CoreGraphics

/// An image as the clipboard sends it (generation 2), both ends: a PNG or JPEG within the cap as it is,
/// anything else ImageIO reads (macOS's TIFF, the iPhone's HEIC) or anything bigger re-encoded to fit
/// (Clipboard.maxImageBytes at home, ClipboardPolicy.awayImageBytes away). Checked by
/// Tests/checks/clipboard.
///
/// - Upright: every re-encoding is drawn through ImageIO's thumbnail with the source's orientation
///   applied (`kCGImageSourceCreateThumbnailWithTransform`), since what it writes carries no orientation
///   tag (#300's D6: a portrait photo from the camera, its pixels stored sideways with a tag, arrived on
///   its side). A PNG or JPEG that goes as it is keeps its tag.
/// - Photographs (JPEG, HEIC, HEIF) are re-encoded as JPEG at 0.85; anything else (a TIFF of a
///   screenshot, a GIF) as PNG when that fits, its text and edges sharp, else as JPEG (#300's D9: a
///   photo was first encoded as a PNG of tens of MB, thrown away). A PNG over the cap is not encoded as
///   PNG again.
/// - A JPEG of an image with transparency is drawn on white first (D9: transparent areas came out black).
/// - Too big at full size: scaled down, its longer side shrunk by the square root of how far over the cap
///   it came, with a tenth more, and by half at most each time; at most 8 tries, never under 16 pixels.
public enum ClipboardImage {
    /// `data` ready to send within `max` bytes, as above; nil when ImageIO cannot read it or nothing fits.
    public static func fitted(_ data: Data, max: Int = Clipboard.maxImageBytes) -> Data? {
        if data.count <= max, Clipboard.imageType(data) != nil { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let longer = Swift.max(width, height)
        let type = CGImageSourceGetType(source) as String?
        if !isPhotograph(type), type != "public.png", let image = upright(source, longerSide: longer),
           let png = encode(image, type: "public.png"), png.count <= max {
            return png
        }
        var side = Double(longer)
        for _ in 0..<8 {
            guard let image = upright(source, longerSide: Int(side)),
                  let jpeg = encode(flattened(image), type: "public.jpeg", quality: 0.85) else { return nil }
            if jpeg.count <= max { return jpeg }
            side *= Swift.max(0.5, (Double(max) / Double(jpeg.count)).squareRoot() * 0.9)
            guard side >= 16 else { return nil }
        }
        return nil
    }

    /// A photograph's types: re-encoded as JPEG, never tried as PNG first.
    static func isPhotograph(_ type: String?) -> Bool {
        ["public.jpeg", "public.heic", "public.heif"].contains(type ?? "")
    }

    /// The source's first image, upright (its orientation applied), its longer side at most `longerSide`
    /// pixels (never larger than it is).
    static func upright(_ source: CGImageSource, longerSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Swift.max(1, longerSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The image on white when it has transparency (a JPEG has none: its transparent areas would come out
    /// black); else as it is.
    static func flattened(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        return ctx.makeImage() ?? image
    }

    private static func encode(_ image: CGImage, type: String, quality: Double? = nil) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type as CFString, 1, nil) else { return nil }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(dest, image, options)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
