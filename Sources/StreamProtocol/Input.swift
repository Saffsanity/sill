import Foundation

/// Client → host input. Positions are fractions of the streamed video frame (0…1 across its width
/// and height), whatever size the client draws it at; the host maps them onto the source's screen
/// rectangle. That keeps the client ignorant of Mac geometry and survives window moves.
public enum PointerAction: String, Codable {
    case move       // cursor only (Pencil hover, finger position)
    case leftDown
    case leftUp
    case rightDown
    case rightUp
}

public enum InputEvent: Codable, Hashable {
    case pointer(PointerAction, x: Double, y: Double)

    /// Scroll with the cursor at (x, y). dx/dy are fractions of the frame the content should move,
    /// natural-scrolling sign: positive dy means the content moves down (finger dragged down, or up
    /// while the device's Reverse Scrolling turns its fingers' scrolls around: `ScrollDirection`).
    case scroll(x: Double, y: Double, dx: Double, dy: Double)

    /// Text from the software keyboard. "\n", "\t" and "\u{8}" (backspace) are delivered as the
    /// matching keys; everything else is typed as Unicode.
    case text(String)

    /// Scroll gesture boundaries, so the Mac sees a trackpad-like gesture (rubber-banding, and
    /// momentum after the fingers lift) rather than a bare wheel. Sent around `.scroll` deltas:
    /// began → deltas… → ended, then optionally momentumBegan → deltas… → momentumEnded, with the
    /// client generating the decaying momentum deltas itself.
    case scrollGesture(ScrollPhase, x: Double, y: Double)

    /// A key by USB HID usage (UIKeyboardHIDUsage.rawValue on iOS) with UIKeyModifierFlags bits,
    /// which are the same bit positions as CGEventFlags for shift/control/option/command.
    case key(hidUsage: UInt16, down: Bool, modifiers: UInt64)

    /// A two-finger pinch on the glass, as the Mac's trackpad makes one (the magnify gesture that
    /// zooms Maps, Preview, Safari, Photos). `began` → `changed`… → `ended`, at the point between the
    /// fingers. `amount` is the change since the last event as a fraction of the size (+0.05 spreads
    /// the content 5 % larger, -0.05 pinches it 5 % smaller), the unit of `NSEvent.magnification`.
    /// A device sends it only to a host whose window list says `magnify` 1 or more (`Magnify.generation`);
    /// an older host cannot decode the case and would drop the message.
    case magnify(MagnifyPhase, x: Double, y: Double, amount: Double)
}

public enum MagnifyPhase: String, Codable {
    case began, changed, ended
}

public enum Magnify {
    /// `WindowList.magnify` from a host that takes `InputEvent.magnify`.
    public static let generation = 1
}

public enum ScrollPhase: String, Codable {
    case began, ended, momentumBegan, momentumEnded
}
