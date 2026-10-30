import Foundation

/// Who a two-finger pinch on the stream's picture belongs to: the picture on this device (StreamZoom)
/// or the Mac's own pinch (`InputEvent.magnify`). One rule for the three places that ask
/// (`InputOverlayView.zoomTouch`, `gestureRecognizerShouldBegin` and `handlePinch`), so they cannot
/// disagree: the picture zooming while the Mac also gets a pinch, or neither moving at all.
///
/// Pinch Behavior (Settings › This iPad) is the person's choice, Zoom Stream or Zoom App, stored on the
/// device and never sent. It only counts for a Mac that takes the pinch (`WindowList.magnify`): the
/// choice is kept, and a Mac before it offers no control to change it back, so it must not take the
/// picture's zoom away there.
enum PinchRouting {
    enum Owner: Equatable {
        /// The picture on this device zooms (StreamZoom); nothing is sent to the Mac.
        case picture
        /// The Mac gets a `.magnify` pinch; the picture is left as it is.
        case mac
        /// Nothing: a trackpad's pinch for a Mac that cannot take it.
        case none
    }

    /// - Parameters:
    ///   - fingersOnGlass: the pinch is made by fingers on the screen. A pinch on the iPad's trackpad
    ///     arrives with no touches and is never the picture's (the picture's rule reads touches).
    ///   - zoomApp: the stored choice, Zoom App (true) or Zoom Stream (false, the default).
    ///   - macTakesPinch: the session's Mac says `WindowList.magnify`.
    static func owner(fingersOnGlass: Bool, zoomApp: Bool, macTakesPinch: Bool) -> Owner {
        if !fingersOnGlass { return macTakesPinch ? .mac : .none }
        return zoomApp && macTakesPinch ? .mac : .picture
    }
}
