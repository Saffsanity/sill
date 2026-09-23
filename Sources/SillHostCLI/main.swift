import Foundation
import AppKit
import CoreGraphics
import StreamProtocol
import SillHostCore

// Line-buffer stdout so the log reads live when piped or redirected (Swift's print is fully
// buffered off a terminal, which hides the stats line until exit).
setvbuf(stdout, nil, _IOLBF, 0)

// Knobs for the spike: maxFPS, captureScale, bitrate (per 60 fps), prioritizeSpeed. They live in
// Sources/SillHost/HostConfig.swift now (`HostConfig.standard`), which is also where the menu bar
// app's Settings start. Change, rebuild, measure.
var config = HostConfig.standard

// Optional. Streams the first window whose app name or title matches, before any client asks.
// Normally left off: the client picks a window from its bar.
let preselect = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("--") }

// `SillHost --synthetic`: the Desktop source streams a moving test pattern instead of the screen,
// so the encoder, its software fallback and the network can be checked without Screen Recording.
let synthetic = CommandLine.arguments.contains("--synthetic")

// `SillHost --virtual-display`: a picked window is moved onto its own HiDPI virtual display and
// that display is captured, so the window keeps repainting whatever covers its old spot on the
// Mac. Off by default until Noah has tried it. Needs the AppKit event loop below: without it this
// process never sees the display's modes (VirtualDisplay.swift, "Event loop").
let virtualDisplay = CommandLine.arguments.contains("--virtual-display")
config.virtualDisplay = virtualDisplay

// `SillHost --encoder-selftest`: no capture, no network. Pushes synthetic frames through the real
// HEVCEncoder (hardware, then software) and reports what came back, so the watchdog and the
// fallback can be exercised without Screen Recording. Exits when done.
if CommandLine.arguments.contains("--encoder-selftest") {
    EncoderSelfTest.run()
}

// ScreenCaptureKit talks to the window server through CoreGraphics, which must be
// initialized on the main thread before any other thread touches it. In a CLI tool
// nothing does that for us, so prime it here and keep stream setup on the main actor.
// Otherwise SCStream aborts with "Assertion failed: (did_initialize), CGS_REQUIRE_INIT".
_ = CGMainDisplayID()

// `SillHost --virtual-display-selftest`: creates one 1000×700 pt @2× virtual display, reports
// whether this process, CoreGraphics and ScreenCaptureKit see it, destroys it and exits. Needs
// no permission for the display itself (SCShareableContent needs Screen Recording; it says so).
// Runs under the AppKit loop like the real thing.
if CommandLine.arguments.contains("--virtual-display-selftest") {
    VirtualDisplaySelfTest.run()
}

// Lives as long as the process. A local inside the Task would be released when setup finished.
var coordinator: StreamCoordinator?

func startHost() {
    Task { @MainActor in
        do {
            let c = try StreamCoordinator(config: config, synthetic: synthetic, appKitLoop: virtualDisplay)
            coordinator = c
            await c.start(preselect: preselect)
            if synthetic { print("Synthetic mode: pick Desktop on the device (or from a test client) to stream a test pattern.") }
            if virtualDisplay { print("Virtual display mode: a picked window streams from its own HiDPI display; Ctrl-C puts it back.") }
            print("\(c.windowCount) windows on screen. Advertising _sill._tcp on the local network.")
            if c.active == .none { print("Nothing is streaming yet: pick a window from the iOS app. Ctrl-C to stop.") }
            Stats.shared.startPrinting()
        } catch {
            print("Error: \(error)")
            print("If this is a permissions error: System Settings › Privacy & Security › Screen Recording, enable Terminal, then run again.")
            exit(1)
        }
    }
}

if virtualDisplay {
    // The window server delivers display reconfiguration through the app's event port, which
    // dispatchMain() never drains; only under NSApplication.run() does this process learn the
    // virtual display's modes. The main dispatch queue (Task { @MainActor }, Stats' timer, the
    // signal sources) is serviced by the app's run loop, so nothing else changes.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)   // no Dock icon, no app switcher, can never be activated
    HostShutdown.install { coordinator }    // Ctrl-C / kill: put the window back before exiting
    startHost()
    app.run()
} else {
    startHost()
    dispatchMain()   // today, byte for byte
}
