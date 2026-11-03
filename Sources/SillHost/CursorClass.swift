import Foundation

/// Whether the Mac's current cursor is one of macOS's standard cursors or an app's own (kind 46,
/// CursorKind): a device shows a hovering Apple Pencil's pointer only over an app's own, a drawing
/// app's brush outline, and never an arrow under the Pencil (docs/pencil-pressure-plan.md, Q1).
/// Pure: CursorShapeWatcher reads the cursor and fingerprints it, this decides.
///
/// Recorded on macOS 27 (2026-10-14): the cursor the window server shows matched AppKit's own
/// standard cursor pixel for pixel for the arrow, the I-beam, the pointing hand and the window
/// edges' resize cursors, and Affinity's brush outline (68×68, one 1× image) and another app's tool
/// cursor (25×25) matched none.
package enum CursorClass {
    /// `fingerprint`: the cursor's, as CursorShapeWatcher makes it (its hotspot, its point size and
    /// its smallest bitmap's pixels); `standards`: the same of AppKit's standard cursors, made in this
    /// process (a Hasher's values differ between processes). `bitmapWidths` and `pointWidth`: the
    /// cursor's images in pixels and its width in points.
    ///
    /// A cursor whose fingerprint is a standard one's is standard. So is one with four images or more
    /// whose widest is 10× its width: the window server's own arrow and I-beam carry 1×, 2×, 5× and
    /// 10×, and in a process without an NSApplication (the CLI) AppKit's copies of those two have no
    /// image to fingerprint. Anything else is an app's own; when unsure, so: the pointer then shows,
    /// as it did before kind 46.
    package static func isStandard(fingerprint: Int, standards: Set<Int>, bitmapWidths: [Int], pointWidth: Double) -> Bool {
        if standards.contains(fingerprint) { return true }
        guard pointWidth > 0, bitmapWidths.count >= 4, let widest = bitmapWidths.max() else { return false }
        return Double(widest) >= 9.5 * pointWidth
    }
}
