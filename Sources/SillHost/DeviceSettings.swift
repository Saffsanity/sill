import CoreGraphics
import StreamProtocol

// A device's view of the host's settings (kinds 16 and 17): the conversions between the host's
// `HostConfig` and the wire types, and what a device may set. The coordinator's `.changeSettings`
// handler and `settingsState` are the only users, plus the app's hook (`applying`).

extension HostConfig {
    /// As a device sees them.
    var streamSettings: StreamSettings {
        StreamSettings(maxFPS: maxFPS, bitrate: bitrate, captureScale: Double(captureScale),
                       prioritizeSpeed: prioritizeSpeed, virtualDisplay: virtualDisplay)
    }

    /// This config with a device's change laid over it; nil fields keep their value. `package`:
    /// the app's hook lays a change over its own settings with it.
    package func applying(_ change: HostSettingsChange) -> HostConfig {
        var c = self
        if let v = change.maxFPS { c.maxFPS = v }
        if let v = change.bitrate { c.bitrate = v }
        if let v = change.captureScale { c.captureScale = CGFloat(v) }
        if let v = change.prioritizeSpeed { c.prioritizeSpeed = v }
        if let v = change.virtualDisplay { c.virtualDisplay = v }
        return c
    }
}

/// What a device may change on this host. There is no generic "write a default": a device moves
/// these five knobs, to exactly the Mac menu's values, and nothing else.
enum DeviceSettings {
    /// The fields of `c` a device may set: exactly the Mac menu's choices (`SettingsChoices`), and
    /// the virtual display on only where this host can run it (off is always allowed). Refusal is
    /// per field: the rest of the same change still applies. The refused fields are named for the
    /// log; the token is not carried (the handler answers with the request's own).
    static func accepted(_ c: HostSettingsChange, virtualDisplayAvailable: Bool) -> (HostSettingsChange, refused: [String]) {
        var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed)
        var refused: [String] = []
        if let v = c.maxFPS {
            if SettingsChoices.maxFPS.contains(v) { ok.maxFPS = v } else { refused.append("frame rate limit \(v)") }
        }
        if let v = c.bitrate {
            if SettingsChoices.bitrate.contains(v) { ok.bitrate = v } else { refused.append("bitrate \(v)") }
        }
        if let v = c.captureScale {
            if SettingsChoices.captureScale.contains(v) { ok.captureScale = v } else { refused.append("capture scale \(v)") }
        }
        if let v = c.virtualDisplay {
            if !v || virtualDisplayAvailable { ok.virtualDisplay = v } else { refused.append("virtual display (needs SillHost --virtual-display)") }
        }
        return (ok, refused)
    }
}

extension HostStatusSnapshot.Stream {
    /// The running pipeline as a device sees it.
    var wire: RunningStream {
        RunningStream(width: width, height: height, fps: fps, mbps: mbps, onVirtualDisplay: onVirtualDisplay)
    }
}
