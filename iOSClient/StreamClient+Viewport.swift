import Foundation
import StreamProtocol

// Viewport reporting: the stream panel's size in points and the text scale the user picked with
// the Aa button. The host resizes the Mac window to match (milestone 3's fallback path; see
// `Viewport` for what the scale means). `StreamScreen` decides when to call this.
extension StreamClient {
    /// Tell the host how big the stream panel is and how the Mac window should be sized to it.
    /// A no-op without a connection. Main thread.
    func sendViewport(_ v: Viewport) {
        send(.viewport, payload: Wire.encode(v))
    }
}
