import Foundation
import CoreGraphics

/// Kept independent of SwiftUI so letterboxing/rejected taps can be checked without a device.
enum VisionInputGeometry {
    static func normalized(_ point: CGPoint, bounds: CGRect, videoSize: CGSize) -> CGPoint? {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let width = videoSize.width * scale, height = videoSize.height * scale
        let rect = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        guard rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / width, y: (point.y - rect.minY) / height)
    }
}
