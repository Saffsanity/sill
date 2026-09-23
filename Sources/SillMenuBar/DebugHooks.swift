import AppKit
import SwiftUI
import SillHostCore

/// Test hooks, read from the launch arguments like the iOS app's -SillLayout harness. Each does
/// nothing unless it is passed, so they stay in release builds, where the tests run.
///
///     --synthetic                              the Desktop is a test pattern and nothing is
///                                              advertised, as with the CLI (test clients connect
///                                              to the port in the "Status: Test Pattern Mode" line)
///     -SillLogFile <path>                      log file instead of ~/Library/Logs/Sill/Sill.log
///     -SillSetAfter '<s> key=value[,key=value][; <s> …]'
///                                              change settings s seconds after launch, exactly as
///                                              a control would (maxFPS, captureScale, bitrate,
///                                              prioritizeSpeed, virtualDisplay). Saved like any
///                                              change: run it on the bare binary, whose defaults
///                                              domain is "SillMenuBar", not on Sill.app.
///     -SillQuitAfter <s>                       Quit (NSApp.terminate) s seconds after launch
///     -SillRenderPreviews <dir>                write the Settings panes, status cards, glyphs and
///                                              menu.txt to <dir>, then exit (no Screen Recording
///                                              needed: views render offscreen)
///
/// The timers are run-loop Timers, never Tasks: NSApp.terminate may run a modal loop, which from
/// a Task would stall the main queue (see AppDelegate).
@MainActor
enum DebugHooks {
    /// Where the log file goes. Read before the app starts (main.swift).
    nonisolated static var logFileURL: URL {
        if let path = UserDefaults.standard.string(forKey: "SillLogFile"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/Sill/Sill.log")
    }

    /// -SillSetAfter and -SillQuitAfter, counted from now (launch).
    static func schedule(model: AppModel) {
        let defaults = UserDefaults.standard
        if let spec = defaults.string(forKey: "SillSetAfter") {
            for step in spec.split(separator: ";") {
                let parts = step.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let delay = Double(parts[0]) else {
                    print("SillSetAfter: can’t read “\(step)”; expected '<seconds> key=value[,key=value]'")
                    continue
                }
                let changes = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let timer = Timer(timeInterval: delay, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        var config = model.settings.config
                        for change in changes { apply(change, to: &config) }
                        print("SillSetAfter \(parts[0]) s: \(changes.joined(separator: ", "))")
                        model.settings.config = config    // one assignment: several keys, one apply
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        let quitAfter = defaults.double(forKey: "SillQuitAfter")
        if quitAfter > 0 {
            let timer = Timer(timeInterval: quitAfter, repeats: false) { _ in
                MainActor.assumeIsolated {
                    print("SillQuitAfter \(quitAfter) s: quitting")
                    NSApp.terminate(nil)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func apply(_ change: String, to config: inout HostConfig) {
        let kv = change.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2 else { print("SillSetAfter: can’t read “\(change)”"); return }
        let (key, value) = (kv[0], kv[1])
        let flag = ["1", "true", "yes", "on"].contains(value.lowercased())
        switch key {
        case "maxFPS": if let v = Int(value) { config.maxFPS = v }
        case "captureScale": if let v = Double(value) { config.captureScale = CGFloat(v) }
        case "bitrate": if let v = Int(value) { config.bitrate = v }
        case "prioritizeSpeed": config.prioritizeSpeed = flag
        case "virtualDisplay": config.virtualDisplay = flag
        default: print("SillSetAfter: no setting called \(key)")
        }
    }

    // MARK: Previews

    /// -SillRenderPreviews <dir>: renders and exits. Called before anything else starts.
    static func renderPreviewsIfAsked(model: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "SillRenderPreviews"), !dir.isEmpty else { return }
        let out = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        for tab in SettingsTab.allCases {
            for (name, appearance) in appearances {
                render(SettingsPane(tab: tab, model: model).background(Color(nsColor: .windowBackgroundColor)),
                       appearance: appearance, to: out.appendingPathComponent("pane-\(tab.rawValue)-\(name).png"))
            }
        }

        var menuText = ""
        let login = LoginState(available: true, on: false, needsApproval: false, error: nil)
        for sample in samples() {
            let p = StatusText.present(snapshot: sample.snapshot, permissions: sample.permissions,
                                       startupError: sample.startupError, hasCoordinator: true)
            for (name, appearance) in appearances {
                render(StatusCard(presentation: p).padding(.vertical, 4).background(Color(nsColor: .windowBackgroundColor)),
                       appearance: appearance, to: out.appendingPathComponent("card-\(sample.name)-\(name).png"))
            }
            var config = model.settings.config
            config.virtualDisplay = sample.snapshot.virtualDisplayOn     // the checkmark matches the sample
            let entries = MenuBuilder.entries(presentation: p, config: config, login: login, permissions: sample.permissions)
            menuText += "=== \(sample.name) (glyph: \(p.glyph), tooltip: \(p.tooltip))\n"
            menuText += MenuBuilder.dump(entries, card: p) + "\n"
        }
        try? menuText.write(to: out.appendingPathComponent("menu.txt"), atomically: true, encoding: .utf8)
        renderGlyphSheet(to: out.appendingPathComponent("glyphs.png"))
        print("Previews written to \(out.path)")
        exit(0)
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard host.bounds.width > 0, host.bounds.height > 0,
              let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("Preview \(url.lastPathComponent): nothing to render")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// Every glyph state on a light and a dark menu bar at real size, then 6× for review, and the
    /// SF Symbol fallback for comparison.
    private static func renderGlyphSheet(to url: URL) {
        let states = StatusGlyph.State.allCases
        let zoom: CGFloat = 6
        let zoomed = CGFloat(states.count) * (StatusGlyph.size.width * zoom + 10) + 10
        let size = NSSize(width: max(60 * CGFloat(states.count + 1) + 20, zoomed), height: 100 + StatusGlyph.size.height * zoom + 20)
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        func tinted(_ image: NSImage, _ ink: NSColor) -> NSImage {
            NSImage(size: image.size, flipped: false) { r in
                image.draw(in: r)
                ink.set()
                r.fill(using: .sourceAtop)
                return true
            }
        }
        for (row, dark) in [false, true].enumerated() {
            let bar = NSRect(x: 0, y: size.height - 40 - CGFloat(row) * 40, width: size.width, height: 30)
            (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
            bar.fill()
            let ink: NSColor = dark ? .white : .black
            let images = states.map { StatusGlyph.image($0) } + [StatusGlyph.symbolFallback].compactMap { $0 }
            for (i, image) in images.enumerated() {
                let s = image.size.height > 0 ? image.size : StatusGlyph.size
                tinted(image, ink).draw(in: NSRect(x: 20 + CGFloat(i) * 60, y: bar.minY + (30 - s.height) / 2, width: s.width, height: s.height))
            }
        }
        for (i, state) in states.enumerated() {
            let g = StatusGlyph.size
            StatusGlyph.image(state).draw(in: NSRect(x: 10 + CGFloat(i) * (g.width * zoom + 10), y: 10,
                                                     width: g.width * zoom, height: g.height * zoom))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: Canned states

    /// Stand-ins for connections: a device's id is its connection's ObjectIdentifier.
    private static let tokens = [NSObject(), NSObject()]

    private struct Sample {
        var name: String
        var snapshot: HostStatusSnapshot
        var permissions = PermissionState(screenRecording: true, accessibility: true)
        var startupError: String?
    }

    private static func samples() -> [Sample] {
        let ipad = HostStatusSnapshot.Device(id: ObjectIdentifier(tokens[0]), endpoint: "192.168.1.23:52344",
                                             name: "iPad (iPad14,1)", fps: 118, frameAgeMs: 9, rttMs: 7)
        let iphone = HostStatusSnapshot.Device(id: ObjectIdentifier(tokens[1]), endpoint: "192.168.1.31:50112",
                                               name: "iPhone (iPhone17,1)", fps: 60, frameAgeMs: 11, rttMs: 8)
        let window = HostStatusSnapshot.Stream(kind: .window, title: "Safari — Apple Developer Documentation: ScreenCaptureKit",
                                               width: 3024, height: 1898, fps: 120, mbps: 30,
                                               onVirtualDisplay: true, softwareEncoder: false)
        var idle = HostStatusSnapshot()
        idle.network = .advertising("Noah’s MacBook Pro")
        var registering = HostStatusSnapshot()
        registering.network = .registering
        var connected = idle
        connected.devices = [ipad]
        var streaming = connected
        streaming.stream = window
        streaming.encodedFPS = 118
        streaming.virtualDisplayOn = true
        var two = streaming
        two.devices = [ipad, iphone]
        var software = connected
        software.softwareEncoder = true
        software.stream = HostStatusSnapshot.Stream(kind: .desktop, title: "Whole Desktop", width: 1512, height: 982, fps: 60,
                                                    mbps: 15, onVirtualDisplay: false, softwareEncoder: true)
        software.encodedFPS = 0
        var fallback = streaming
        fallback.stream?.onVirtualDisplay = false
        fallback.lastStageFailure = "needs Accessibility"
        var test = HostStatusSnapshot()
        test.synthetic = true
        test.network = .notAdvertised(port: 56192)
        test.devices = [HostStatusSnapshot.Device(id: ObjectIdentifier(tokens[0]), endpoint: "127.0.0.1:49538")]
        test.stream = HostStatusSnapshot.Stream(kind: .testPattern, title: "Test Pattern", width: 3024, height: 1898, fps: 60,
                                                mbps: 15, onVirtualDisplay: false, softwareEncoder: false)
        test.encodedFPS = 60
        var waiting = HostStatusSnapshot()
        waiting.network = .waiting("POSIXErrorCode(rawValue: 50): Network is down")
        var failed = HostStatusSnapshot()
        failed.network = .failed("POSIXErrorCode(rawValue: 48): Address already in use")
        return [
            Sample(name: "idle", snapshot: idle),
            Sample(name: "registering", snapshot: registering),
            Sample(name: "connected", snapshot: connected),
            Sample(name: "streaming", snapshot: streaming),
            Sample(name: "two-devices", snapshot: two),
            Sample(name: "software-encoder", snapshot: software),
            Sample(name: "virtual-display-fallback", snapshot: fallback),
            Sample(name: "permissions-missing", snapshot: idle,
                   permissions: PermissionState(screenRecording: false, accessibility: false)),
            Sample(name: "test-pattern", snapshot: test,
                   permissions: PermissionState(screenRecording: false, accessibility: true)),
            Sample(name: "waiting", snapshot: waiting),
            Sample(name: "failed", snapshot: failed),
            Sample(name: "startup-error", snapshot: HostStatusSnapshot(), startupError: "POSIXErrorCode(rawValue: 22): Invalid argument"),
        ]
    }
}
