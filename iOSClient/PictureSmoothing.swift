import Foundation

/// How the picture is scaled to the screen (Windows App's graphics interpolation level), a setting
/// of this device's own, never sent. Automatic is the system's video layer, as Sill has always drawn
/// it; every other level decodes the stream itself and draws it with Metal (MetalStreamRenderer),
/// scaled with that level's filter. Pure: the levels, which renderer draws each, the shader's
/// filters and the weights it uses (so a check can hold the shader to them).
enum PictureSmoothing: String, CaseIterable {
    case automatic, none, low, medium, high

    static let defaultsKey = "Sill.pictureSmoothing"

    /// The stored value, Automatic for nothing or a value this build does not know.
    static func stored(_ raw: String?) -> PictureSmoothing { raw.flatMap(PictureSmoothing.init(rawValue:)) ?? .automatic }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    static let footnote = "How the picture is scaled to fit. Automatic is the system’s own; the others "
        + "sharpen (None) or smooth it more, and use a little more battery."

    var usesOwnRenderer: Bool { self != .automatic }

    enum Filter: Equatable {
        case nearest, bilinear, bicubic, lanczos
        /// The fragment shader's `mode`, in order of cost.
        var shaderMode: Int32 {
            switch self {
            case .nearest: return 0
            case .bilinear: return 1
            case .bicubic: return 2
            case .lanczos: return 3
            }
        }
    }

    var filter: Filter? {
        switch self {
        case .automatic: return nil
        case .none: return .nearest
        case .low: return .bilinear
        case .medium: return .bicubic
        case .high: return .lanczos
        }
    }

}

extension PictureSmoothing.Filter {
    /// How far the filter reaches, in source pixels, when it does not shrink.
    var support: Double {
        switch self {
        case .nearest: return 0.5
        case .bilinear: return 1
        case .bicubic: return 2
        case .lanczos: return 3
        }
    }
}

extension PictureSmoothing {
    /// A filter's weight at a distance `x` from a sample, in source pixels: a tent (bilinear),
    /// Catmull-Rom (bicubic) and Lanczos-3, as StreamShader computes them.
    static func kernel(_ filter: Filter, _ x: Double) -> Double {
        let x = abs(x)
        switch filter {
        case .nearest: return x < 0.5 ? 1 : 0
        case .bilinear: return max(0, 1 - x)
        case .bicubic:
            if x < 1 { return 1.5 * x * x * x - 2.5 * x * x + 1 }
            if x < 2 { return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2 }
            return 0
        case .lanczos:
            guard x < 3 else { return 0 }
            guard x > 0 else { return 1 }
            let px = Double.pi * x
            return 3 * sin(px) * sin(px / 3) / (px * px)
        }
    }

    /// One row resampled to `n` pixels as one pass of the shader does it: the output pixel's centre
    /// in source pixels, then nearest takes the source pixel under it; the others weigh the source
    /// pixels within the filter's reach, widened by the shrink when the row gets shorter (so finer
    /// detail than the output averages out instead of aliasing), the edges clamped and the weights
    /// normalized. The reference the GPU check holds the shader to.
    static func resample(_ row: [Double], to n: Int, filter: Filter) -> [Double] {
        let m = row.count
        guard m > 0, n > 0 else { return [] }
        let scale = Double(n) / Double(m)
        return (0..<n).map { i in
            if filter == .nearest { return row[min(m - 1, Int((Double(i) + 0.5) / scale))] }
            let c = (Double(i) + 0.5) / scale - 0.5
            let s = min(scale, 1), r = filter.support / s
            var acc = 0.0, sum = 0.0
            var k = Int((c - r).rounded(.down)) + 1
            while Double(k) <= c + r {
                let w = kernel(filter, (Double(k) - c) * s)
                acc += row[min(m - 1, max(0, k))] * w
                sum += w
                k += 1
            }
            return sum == 0 ? row[min(m - 1, max(0, Int(c.rounded())))] : acc / sum
        }
    }
}
