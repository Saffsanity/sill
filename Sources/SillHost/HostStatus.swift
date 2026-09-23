import Foundation
import Observation

/// What the host is doing, as plain values for the menu bar app: the menu, the status item and
/// Settings read it; nothing in the host reads it back. The coordinator pushes a change at the
/// moment it happens (listener state, a device in or out, its once-a-second stats, a pipeline
/// started or stopped, an encoder or virtual display fallback), so nothing polls and an idle host
/// stays idle.
///
/// Not Sendable on purpose: it lives on the main actor with `HostStatus`, and marking these
/// structs Sendable only produced warnings.
package struct HostStatusSnapshot: Equatable {
    /// The listener and its Bonjour registration.
    package enum Network: Equatable {
        case starting
        /// Listening; Bonjour has not confirmed a name yet.
        case registering
        /// The name devices see. Bonjour renames on a clash ("Noah’s MacBook Pro (2)").
        case advertising(String)
        /// --synthetic: listening but deliberately off Bonjour; test clients use this port.
        case notAdvertised(port: Int)
        /// The listener waits for a usable network (no Wi-Fi or Ethernet, Local Network denied).
        case waiting(String)
        /// The listener failed; devices cannot reach this host until Sill restarts.
        case failed(String)
    }

    /// One connected device. The name and numbers come from its ClientStats, about once a second;
    /// nil until the first report.
    package struct Device: Equatable, Identifiable {
        package let id: ObjectIdentifier
        package var endpoint: String
        /// The device's own description, such as "iPad (iPad14,1)".
        package var name: String?
        package var fps: Int?
        /// What the device measured over its last second (a current client sends the medians);
        /// -1 when that second had no sample (no frame arrived, no pong came back).
        package var frameAgeMs: Int?
        package var rttMs: Int?

        package init(id: ObjectIdentifier, endpoint: String, name: String? = nil, fps: Int? = nil,
                     frameAgeMs: Int? = nil, rttMs: Int? = nil) {
            self.id = id; self.endpoint = endpoint; self.name = name
            self.fps = fps; self.frameAgeMs = frameAgeMs; self.rttMs = rttMs
        }
    }

    /// The running pipeline, as it was last started.
    package struct Stream: Equatable {
        package enum Kind: Equatable { case window, desktop, testPattern }
        package var kind: Kind
        /// "Safari — Apple Developer", "Whole Desktop" or "Test Pattern".
        package var title: String
        package var width: Int
        package var height: Int
        package var fps: Int
        package var mbps: Int
        /// Captured from the virtual display (the window was staged there).
        package var onVirtualDisplay: Bool
        package var softwareEncoder: Bool

        package init(kind: Kind, title: String, width: Int, height: Int, fps: Int, mbps: Int,
                     onVirtualDisplay: Bool, softwareEncoder: Bool) {
            self.kind = kind; self.title = title; self.width = width; self.height = height
            self.fps = fps; self.mbps = mbps; self.onVirtualDisplay = onVirtualDisplay
            self.softwareEncoder = softwareEncoder
        }
    }

    package var network: Network = .starting
    package var devices: [Device] = []
    package var stream: Stream?
    /// Frames the encoder put out in the last stats second (the stats line's `enc.out`).
    package var encodedFPS = 0
    /// The hardware encoder did not answer (launch probe or a hang): the software encoder carries
    /// every stream until the host restarts.
    package var softwareEncoder = false
    /// The virtual display setting as the host runs it.
    package var virtualDisplayOn = false
    /// Why the virtual display is off for this run: the private API is missing, or the system took
    /// the display away too often. Nil when it is available.
    package var virtualDisplayProblem: String?
    /// `virtualDisplayProblem` is the private API check (nothing to retry until macOS changes).
    package var virtualDisplayAPIMissing = false
    /// Why the last pick streamed the real window instead of the virtual display; cleared by the
    /// next successful stage.
    package var lastStageFailure: String?
    /// --synthetic: the Desktop is a test pattern and the host is not advertised.
    package var synthetic = false

    package init() {}
}

/// The observable holder of the snapshot. The coordinator writes it (main actor, only when a value
/// actually changes); SwiftUI and the app's observation loop read it.
@MainActor @Observable
package final class HostStatus {
    package internal(set) var snapshot = HostStatusSnapshot()

    init() {}

    /// Applies `change` to a copy and stores it only if something differs, so observers wake for
    /// real changes and not for every once-a-second stats report that says the same thing.
    func update(_ change: (inout HostStatusSnapshot) -> Void) {
        var next = snapshot
        change(&next)
        if next != snapshot { snapshot = next }
    }
}
