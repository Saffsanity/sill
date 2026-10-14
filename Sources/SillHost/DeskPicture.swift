import CoreGraphics
import CoreVideo

/// Whether the picture a hidden display gives of a window is the window. On macOS 27.0.1, once one of
/// Sill's hidden displays has been removed while others stay, a display made afterwards can stream
/// another display's picture live (a one-off screenshot of it is right, and so is the window captured
/// alone); waiting or resizing it does not mend it, a desk whose displays are all made again from none
/// does. The main stream's crop of such a display leaves out every other app and the wallpaper, so it
/// shows black. The stream's frames are compared with a small screenshot of the window alone, cell by
/// cell, at start and every 10 s (StreamCoordinator's `watchDeskPicture`). Pure.
enum DeskPicture {
    static let columns = 16, rows = 10
    /// How far a cell may be from the window's own (of 255) and still be the same picture: the two
    /// are taken a moment apart and through different paths (the frame's Y plane, the screenshot drawn
    /// in grey), so a playing video or a caret moves a little.
    static let cellTolerance = 48

    /// The picture is not the window: the middle cell difference is over `cellTolerance`. A sheet, a
    /// popover or a menu over part of the window (in the crop, not in the window alone) changes some
    /// cells, never most of them; a picture of something else, or black, changes most.
    static func differs(_ frame: [UInt8], _ window: [UInt8]) -> Bool {
        guard frame.count == window.count, !frame.isEmpty else { return false }
        let diffs = zip(frame, window).map { abs(Int($0) - Int($1)) }.sorted()
        return diffs[diffs.count / 2] > cellTolerance
    }

    /// Each cell's mean luma (0–255) of a 420f frame's Y plane, row by row; nil for another format.
    static func grid(_ px: CVPixelBuffer) -> [UInt8]? {
        guard CVPixelBufferGetPlaneCount(px) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let w = CVPixelBufferGetWidthOfPlane(px, 0), h = CVPixelBufferGetHeightOfPlane(px, 0)
        let bpr = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
        guard w >= columns, h >= rows, let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) else { return nil }
        let y = base.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: columns * rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let x0 = c * w / columns, x1 = (c + 1) * w / columns, y0 = r * h / rows, y1 = (r + 1) * h / rows
                var sum = 0, n = 0
                for yy in stride(from: y0, to: y1, by: 4) {
                    for xx in stride(from: x0, to: x1, by: 4) { sum += Int(y[yy * bpr + xx]); n += 1 }
                }
                out[r * columns + c] = UInt8(sum / max(n, 1))
            }
        }
        return out
    }

    /// The same cells of an image, drawn in grey over black (the frame's background behind a
    /// window's rounded corners): the cells start at 0.
    static func grid(_ image: CGImage) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: columns * rows)
        let drawn: Bool = out.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                                      bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        return drawn ? out : nil
    }
}
