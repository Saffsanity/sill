import Foundation
import CoreGraphics

/// Scene and picture have the same ratio. Both toolbars are ornaments, and the picture
/// has no additive padding: uniform native resizing therefore preserves the source aspect.
/// Window selections use their frozen source snapshot; Desktop uses source-bound HEVC
/// dimensions because Desktop capture does not follow the scene viewport.
enum VisionWindowSizePolicy {
    static let login = CGSize(width: 580, height: 480)
    static let minimum = CGSize(width: 440, height: 360)
    // Scene sizes are UI points, independent of decoded video pixels. Keep the existing
    // opening footprint while allowing deliberate native resizing to a larger picture.
    static let openingMaximum = CGSize(width: 1400, height: 1050)
    // A finite app policy, not a claimed visionOS limit: accommodates a 3840-point-wide
    // landscape scene or a 2880-point-tall portrait scene without forcing either at launch.
    static let streamMaximum = CGSize(width: 3840, height: 2880)

    struct WindowGeometry {
        let preferred: CGSize
        let minimum: CGSize
        let maximum: CGSize
    }

    /// Native scene dimensions can be rounded to points; allow at most one point
    /// of fitted-picture slack on either axis before capturing the ratio lock.
    static func matchesAspect(_ actual: CGSize, source: CGSize) -> Bool {
        guard actual.width.isFinite, actual.height.isFinite,
              actual.width > 0, actual.height > 0,
              source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else { return false }
        let scale = min(actual.width / source.width, actual.height / source.height)
        return actual.width - source.width * scale <= 1
            && actual.height - source.height * scale <= 1
    }

    static func restoredSize(_ remembered: CGSize, source: CGSize) -> CGSize? {
        guard let geometry = geometry(source: source), remembered.width.isFinite, remembered.height.isFinite,
              remembered.width > 0, remembered.height > 0 else { return nil }
        let wanted = min(remembered.width / source.width, remembered.height / source.height)
        let lower = geometry.minimum.width / source.width
        let upper = geometry.maximum.width / source.width
        let scale = min(upper, max(lower, wanted))
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    static func geometry(source: CGSize) -> WindowGeometry? {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else { return nil }
        // Fit both envelopes uniformly. Independent per-axis clamping would change the ratio,
        // especially for tiny, very wide, or very tall windows. The minimum envelope is soft:
        // its shorter dimension may be below the login/Desktop minimum for unusual ratios.
        let minimumScale = min(minimum.width / source.width, minimum.height / source.height)
        let openingScale = min(openingMaximum.width / source.width, openingMaximum.height / source.height)
        let maximumScale = min(streamMaximum.width / source.width, streamMaximum.height / source.height)
        func scaled(_ scale: CGFloat) -> CGSize {
            CGSize(width: source.width * scale, height: source.height * scale)
        }
        return WindowGeometry(preferred: scaled(min(openingScale, max(minimumScale, 1))),
                              minimum: scaled(minimumScale), maximum: scaled(maximumScale))
    }
}
