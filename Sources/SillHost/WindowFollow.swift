import StreamProtocol

/// When the stream follows a window the streamed app opens by itself (File › New Window, ⌘N, a
/// "Check for Updates…" dialog): in regular mode only the picked window is captured, so a new
/// window the app put in front of it was never seen on the device, which went on showing the old
/// one. On the virtual display the app's other windows already show over the picked one (the
/// capture takes the whole app on that display), so the stream does not follow there. Pure:
/// checked by `Tests/checks/window-follow`.
package enum WindowFollow {
    /// The `defaults` key that turns following off (it is on unless set to false).
    package static let defaultsKey = "followNewWindows"

    /// The window to move the stream to, or nil: the frontmost window on the Mac (`topmost`) when
    /// it is new, listed now, and of the same app as the window streaming (`activeID`). New means
    /// never listed before in this run of the catalog (`seen`, every window ID an earlier catalog
    /// listed): a window back from the Dock, from a hidden app or from another Space was listed
    /// before, so it is not followed. `previous` is the last catalog (nil before the first one,
    /// which follows nothing).
    package static func next(previous: [WindowInfo]?, seen: Set<UInt32>, current: [WindowInfo], activeID: UInt32, topmost: UInt32?) -> UInt32? {
        guard let previous, let topmost, topmost != activeID else { return nil }
        guard !seen.contains(topmost), !previous.contains(where: { $0.id == topmost }),
              let new = current.first(where: { $0.id == topmost }) else { return nil }
        let app = (current.first { $0.id == activeID } ?? previous.first { $0.id == activeID })?.bundleID ?? ""
        guard !app.isEmpty, new.bundleID == app else { return nil }
        return topmost
    }

    /// Where the stream goes back to when the window it followed closes: the most recent window it
    /// followed from that is still listed (a dialog over a dialog over the main window unwinds one
    /// at a time), and the stack without it and anything above it.
    package static func back(_ stack: [UInt32], current: [WindowInfo]) -> (window: UInt32, rest: [UInt32])? {
        var rest = stack
        while let last = rest.popLast() {
            if current.contains(where: { $0.id == last }) { return (last, rest) }
        }
        return nil
    }
}
