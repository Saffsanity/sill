import Foundation

/// Which way a scroll on the device moves the Mac's content: Reverse Scrolling (issue #143), the
/// device's own switch (the Settings panel's This iPad or This iPhone group, `Sill.reverseScroll`),
/// off unless turned on and never sent to the Mac.
///
/// `InputEvent.scroll` carries the natural direction: the content follows the fingers (positive dy
/// moves the content down, as a finger dragged down does). With the switch on, a scroll made on the
/// device's glass, one or two fingers dragged over the picture or two fingers on the on-screen
/// trackpad, goes out the other way, and so does the coast after its lift. A trackpad or a mouse
/// connected to the device scrolls with scroll events, which iPadOS has already turned the way its
/// own Natural Scrolling setting says (with the trackpad's and the mouse's settings, under Settings ›
/// General), so the switch leaves them alone: turning them around again would undo that setting.
///
/// Pure: each surface reads the switch when a scroll begins and multiplies that scroll's deltas, and
/// the velocity its coast starts from, by `factor`, so one scroll keeps one direction from its first
/// delta to its coast's last, whatever the switch does meanwhile.
public enum ScrollDirection {
    /// Where a scroll on the device comes from.
    public enum Source: String, CaseIterable, Sendable {
        /// One or two fingers dragged over the picture (the stream's input view, `InputOverlayView`).
        case finger
        /// Two fingers on the on-screen trackpad of the upright layouts (`TrackpadSurface`).
        case pad
        /// A trackpad connected to the device, or a Magic Mouse, over the picture: scroll events.
        case trackpad
        /// A connected mouse's wheel over the picture: scroll events.
        case wheel
    }

    /// Whether Reverse Scrolling turns this source's scroll around: fingers on the glass only.
    public static func reversible(_ source: Source) -> Bool {
        switch source {
        case .finger, .pad: return true
        case .trackpad, .wheel: return false
        }
    }

    /// What a scroll's deltas, and the velocity its coast starts from, are multiplied by: -1 for a
    /// source the switch turns around while it is on, else 1.
    public static func factor(_ source: Source, reversed: Bool) -> Double {
        reversed && reversible(source) ? -1 : 1
    }
}
