import SwiftUI
import UIKit

// TEST ONLY (Tests/touchrig): stand-ins for what TrackpadView.swift and InputOverlay.swift use from the
// app's other files. HIDKey is the app's own, cut from PortraitStreamScreen.swift by run.sh (with
// KeyModifiers, where the sources keep it there); StreamProtocol's Input.swift, PointerPresence.swift,
// TrackpadGestures.swift and KeyChords.swift are compiled in whole where the sources have them.

enum Palette {
    static let trackpad = Color(red: 0.06, green: 0.07, blue: 0.08)
    static let muted = Color.gray
}

enum HEVCDisplayView {
    /// Aspect-fit, as the real one draws the video.
    static func videoRect(in bounds: CGRect, videoSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let w = videoSize.width * scale, h = videoSize.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }
}
