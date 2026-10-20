import Foundation

/// Which way a finger's drag scrolls the Mac's content (issue #143). `InputEvent.scroll` carries the
/// natural direction: the content follows the finger. A device that is set to Reverse Scrolling sends
/// the opposite for a finger's drag, and nothing else: a trackpad's and a mouse wheel's scroll events
/// already follow the direction the device's own system setting gives them.
///
/// Pure: the device reads its switch (`StreamClient.reverseScrollKey`) and asks here, once per scroll
/// gesture, so a flick's coast keeps the direction its drag had. Nothing is sent to the Mac.
public enum ScrollDirection {
    /// What a scroll's deltas, and the velocity its lift coasts at, are multiplied by: -1 for a
    /// finger's drag while the switch is on, 1 for everything else.
    public static func factor(reversed: Bool, finger: Bool) -> Double {
        reversed && finger ? -1 : 1
    }
}
