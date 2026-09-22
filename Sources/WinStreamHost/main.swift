import Foundation
import CoreGraphics
import StreamProtocol

// Knobs for the spike. Change, rebuild, measure.
let fps = 60
let scale: CGFloat = 2.0          // 2 = Retina capture, 1 = points (much cheaper)
let bitrate = 15_000_000          // bits per second
let prioritizeSpeed = false       // Apple: trades quality for encode speed; try after the baseline

// Optional. Streams the first window whose app name or title matches, before any client asks.
// Normally left off: the client picks a window from its bar.
let preselect = CommandLine.arguments.dropFirst().first

// ScreenCaptureKit talks to the window server through CoreGraphics, which must be
// initialized on the main thread before any other thread touches it. In a CLI tool
// nothing does that for us, so prime it here and keep stream setup on the main actor.
// Otherwise SCStream aborts with "Assertion failed: (did_initialize), CGS_REQUIRE_INIT".
_ = CGMainDisplayID()

// Lives as long as the process. A local inside the Task would be released when setup finished.
var coordinator: StreamCoordinator?

Task { @MainActor in
    do {
        let c = try StreamCoordinator(fps: fps, scale: scale, bitrate: bitrate, prioritizeSpeed: prioritizeSpeed)
        coordinator = c
        await c.start(preselect: preselect)
        print("\(c.catalog.infos.count) windows on screen. Advertising _winstream._tcp on the local network.")
        if c.active == .none { print("Nothing is streaming yet: pick a window from the iOS app. Ctrl-C to stop.") }
        Stats.shared.startPrinting()
    } catch {
        print("Error: \(error)")
        print("If this is a permissions error: System Settings › Privacy & Security › Screen Recording, enable Terminal, then run again.")
        exit(1)
    }
}

dispatchMain()
