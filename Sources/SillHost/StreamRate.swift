import Foundation

/// The frame rate a hardware stream asks of the encoder at its size. The rate a device asks for (its
/// screen's, 120 on a ProMotion Mac) is kept while its pixel rate fits `hardwareBudget`, else the
/// highest of `rates` that fits (at least `rates.last`). Measured on 2026-10-13 on an M2 Max: a
/// fresh session at 3930×2188 (8.6 MP) returned 65 fps at best (14–17 ms a frame), so at 120 fps half
/// the frames were captured only to be dropped before the encoder, and its slow state came on top;
/// an M2 Pro alone managed about 650 MP/s at 3024×1968 (CLAUDE.md, "The hardware encoder: busy, not
/// stuck"). The software encoder has its own cap (60). Pure: `Tests/checks/stream-rate`.
enum StreamRate {
    /// Pixels a second asked of the hardware encoder at most: about 80–90 % of what a fresh session
    /// managed on both Macs measured.
    static let hardwareBudget: Double = 520_000_000
    /// The rates a capped stream steps down through, highest first.
    static let rates = [120, 90, 60, 48, 30]

    /// The rate to stream `pixels` (width × height) at, for a device that wants `wanted`.
    static func capped(_ wanted: Int, pixels: Int, software: Bool) -> Int {
        guard !software, pixels > 0 else { return wanted }
        let fits = hardwareBudget / Double(pixels)
        if Double(wanted) <= fits { return wanted }
        return rates.first { $0 <= wanted && Double($0) <= fits } ?? min(wanted, rates.last!)
    }
}
