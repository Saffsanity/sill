import CoreVideo
import Foundation

/// A moving test pattern for the camera where there is none (docs/camera-plan.md §8): diagonal colour bands
/// that move a step each frame, and the frame's number along the top as 16 blocks (white 1, black 0, most
/// significant first), so a decoded picture says which frame it is, as Scripts/camera/make-fixture.swift's
/// fixture does. DEBUG `-SillCameraSource pattern` sends it instead of the camera (CameraCapture's
/// PatternSource: the simulator has no camera), and Scripts/camera-check/encoder.swift encodes it on the Mac
/// with this app's CameraEncoder. CoreVideo and Foundation only, so it builds for macOS too.
enum CameraPattern {
    /// The rows the number's blocks take at the top.
    static let numberRows = 24

    private static let bands: [(r: UInt8, g: UInt8, b: UInt8)] = [
        (220, 40, 40), (40, 200, 60), (40, 70, 220), (230, 210, 40), (200, 60, 200), (60, 200, 210),
    ]

    /// Frame `n` (its low 16 bits in the blocks) as a `width`×`height` BGRA picture, IOSurface-backed; nil when
    /// CoreVideo makes no buffer.
    static func picture(_ n: Int, width: Int, height: Int) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &made) == kCVReturnSuccess,
              let buffer = made else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let block = max(1, width / 16)
        let shift = n * 6
        for y in 0..<height {
            let line = base + y * row
            for x in 0..<width {
                let p = line + x * 4
                var c = bands[((x + y + shift) / 40) % bands.count]
                if y < numberRows {
                    let bit = x / block < 16 ? (n >> (15 - x / block)) & 1 : 0
                    c = bit == 1 ? (255, 255, 255) : (0, 0, 0)
                }
                p[0] = c.b; p[1] = c.g; p[2] = c.r; p[3] = 255
            }
        }
        return buffer
    }

    /// The number a decoded BGRA picture of the pattern shows (its blocks' middles on row 12), nil for a picture
    /// that is not BGRA or too small to hold the blocks.
    static func number(in image: CVPixelBuffer) -> Int? {
        guard CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        guard width >= 16, height > numberRows else { return nil }
        CVPixelBufferLockBaseAddress(image, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(image)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let row = CVPixelBufferGetBytesPerRow(image)
        let block = max(1, width / 16)
        return (0..<16).reduce(0) { n, b in
            let p = base + 12 * row + (b * block + block / 2) * 4
            return n << 1 | (Int(p[0]) + Int(p[1]) + Int(p[2]) > 3 * 128 ? 1 : 0)
        }
    }
}
