import Foundation
import ObjectiveC
import UIKit
import StreamProtocol

// Viewport reporting: the stream panel's size in points and the text scale the user picked with
// the Aa button. The host resizes the Mac window to match (milestone 3's fallback path; see
// `Viewport` for what the scale means). `StreamScreen` decides when to call this.
//
// The same message carries the local-cursor flag: whether this client draws its own pointer, so
// the host leaves the Mac cursor out of the video. The display view reports hidden ↔ shown
// through `setLocalCursor`. Everything here is main thread.
extension StreamClient {
    /// Tell the host how big the stream panel is and how the Mac window should be sized to it.
    /// A viewport that leaves `localCursor` nil (StreamScreen measures panels and knows nothing
    /// about pointers) gets the current flag filled in, so a rotation or an Aa change never puts
    /// the Mac cursor back under a client-drawn one. Remembers what went out in `lastViewport`.
    /// A no-op on the wire without a connection. Main thread.
    func sendViewport(_ v: Viewport) {
        var v = v
        if v.localCursor == nil { v.localCursor = localCursorState.wanted }
        lastViewport = v
        send(.viewport, payload: Wire.encode(v))
    }

    /// Say whether this client draws its own pointer: true takes the Mac cursor out of the video,
    /// false puts it back. Re-sends `lastViewport` with the flag, 200 ms after the last call, since
    /// Pencil hover and touch can flip the pointer several times a second and each viewport makes
    /// the host re-check the window. Nothing goes out when the host already has this value, or
    /// before any viewport has been sent (the first `sendViewport` then carries it). Main thread.
    func setLocalCursor(_ wanted: Bool) {
        let state = localCursorState
        state.wanted = wanted
        state.pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.localCursorState.pending = nil
            guard var v = self.lastViewport, (v.localCursor ?? false) != wanted else { return }
            v.localCursor = wanted
            self.sendViewport(v)
        }
        state.pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.localCursorDebounce, execute: work)
    }

    private static let localCursorDebounce: TimeInterval = 0.2

    /// The rate the host should stream at for this device: the panel's ceiling (120 on ProMotion
    /// iPads and iPhones, 60 on the iPad mini and other 60 Hz panels), or 60 while Low Power Mode
    /// is on, which caps the panel at 60 anyway. `StreamScreen` re-sends the viewport when either
    /// changes, and the host restarts its capture and encoder at the new rate.
    static func wantedFPS() -> Int {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // `connectedScenes` is unordered: prefer the scene the user is looking at.
        let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
        let ceiling = max(30, screen?.maximumFramesPerSecond ?? 60)
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? min(60, ceiling) : ceiling
    }
}

/// `setLocalCursor`'s bookkeeping. An extension cannot add stored properties, so it hangs off the
/// client as an associated object. Main thread only.
private final class LocalCursorState {
    /// The latest request, sent or not; what `sendViewport` fills in. nil until the pointer first shows.
    var wanted: Bool?
    /// The debounced re-send, if one is waiting.
    var pending: DispatchWorkItem?
}

private var localCursorStateKey: UInt8 = 0

private extension StreamClient {
    var localCursorState: LocalCursorState {
        if let state = objc_getAssociatedObject(self, &localCursorStateKey) as? LocalCursorState { return state }
        let state = LocalCursorState()
        objc_setAssociatedObject(self, &localCursorStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}
