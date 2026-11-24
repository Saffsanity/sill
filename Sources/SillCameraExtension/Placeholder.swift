#if os(macOS)
import CameraFeed
import CoreGraphics
import CoreText
import CoreVideo
import Foundation

/// Sill Camera's still while no frame is live (docs/camera-plan.md §6.4, §11): "Sill Camera" over one line of
/// CameraFeedPolicy's words, light grey on dark grey, drawn once per words and size into an NV12 buffer backed by an
/// IOSurface (apps in other processes read it without a copy). The brightness is drawn straight into the luma plane
/// with CoreGraphics and the chroma plane is left neutral, so the still needs no colour conversion.
enum Placeholder {
    /// Luma levels inside NV12's video range (16 to 235).
    static let background: CGFloat = 0.14
    static let text: CGFloat = 0.9

    static func draw(_ p: CameraFeedPolicy.Placeholder) -> CVPixelBuffer? {
        let w = p.format.width, h = p.format.height
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferWidthKey: w,
            kCVPixelBufferHeightKey: h,
            kCVPixelBufferPixelFormatTypeKey: CameraFeedPolicy.pixelFormat,
        ]
        var made: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, OSType(CameraFeedPolicy.pixelFormat),
                                  attributes as CFDictionary, &made) == kCVReturnSuccess, let buffer = made,
              CVPixelBufferGetPlaneCount(buffer) == 2 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        memset(chroma, 0x80, CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * CVPixelBufferGetHeightOfPlane(buffer, 1))
        guard let context = CGContext(data: luma, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let height = CGFloat(h), width = CGFloat(w)
        line(p.title, size: height * 0.075, weight: true, centerY: height * 0.55, width: width, in: context)
        line(p.line, size: height * 0.04, weight: false, centerY: height * 0.42, width: width, in: context)
        return buffer
    }

    /// One line of text, centred, shrunk to fit nine tenths of the width.
    private static func line(_ text: String, size: CGFloat, weight bold: Bool, centerY: CGFloat, width: CGFloat,
                             in context: CGContext) {
        var size = size
        var made = make(text, size: size, bold: bold)
        var bounds = CTLineGetBoundsWithOptions(made, .useOpticalBounds)
        if bounds.width > width * 0.9, bounds.width > 0 {
            size *= width * 0.9 / bounds.width
            made = make(text, size: size, bold: bold)
            bounds = CTLineGetBoundsWithOptions(made, .useOpticalBounds)
        }
        context.textPosition = CGPoint(x: (width - bounds.width) / 2 - bounds.minX,
                                       y: centerY - (bounds.height / 2 + bounds.minY))
        CTLineDraw(made, context)
    }

    private static func make(_ text: String, size: CGFloat, bold: Bool) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: Placeholder.text, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
#endif
