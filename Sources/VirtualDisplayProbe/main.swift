// VirtualDisplayProbe: milestone 3 feasibility spike.
//
// Question: can Sill create a virtual display, move a real Mac window onto it, capture that
// display with ScreenCaptureKit, and does the window keep repainting there?
//
//   swift build -c release
//   .build/release/VirtualDisplayProbe --probe-only
//   .build/release/VirtualDisplayProbe "<app name or window title substring>" [--width 1600 --height 1000 --scale 2 --seconds 5]
//
// The full run needs Screen Recording and Accessibility for the app that launched it
// (Terminal, iTerm, ...). --probe-only needs neither.
//
// VirtualDisplay.swift is a symlink to Sources/SillHost/VirtualDisplay.swift so the probe
// exercises exactly the code the host will adopt.

import AppKit
import ApplicationServices
import CoreGraphics
import CoreMedia
import Darwin
import ScreenCaptureKit

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Arguments

struct Options {
    var target: String?
    var probeOnly = false
    var widthPt = 1600
    var heightPt = 1000
    var scale = 2
    var seconds = 5.0
}

func usage() -> Never {
    print("""
    usage: VirtualDisplayProbe --probe-only [--width W --height H --scale S]
           VirtualDisplayProbe <app name or window title substring> [--width 1600 --height 1000 --scale 2 --seconds 5]
    """)
    exit(64)
}

func parseOptions() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    func value<T>(_ parse: (String) -> T?) -> T {
        guard !args.isEmpty, let v = parse(args.removeFirst()) else { usage() }
        return v
    }
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--probe-only": o.probeOnly = true
        case "--width": o.widthPt = value { Int($0) }
        case "--height": o.heightPt = value { Int($0) }
        case "--scale": o.scale = value { Int($0) }
        case "--seconds": o.seconds = value { Double($0) }
        case "-h", "--help": usage()
        default:
            if a.hasPrefix("--") || o.target != nil { usage() }
            o.target = a
        }
    }
    if !o.probeOnly && o.target == nil { usage() }
    return o
}

let options = parseOptions()

// MARK: - Output helpers

var stepNumber = 0
func step(_ title: String) {
    stepNumber += 1
    print("\n[\(stepNumber)] \(title)")
}
func info(_ s: String) { print("    \(s)") }
func good(_ s: String) { print("    OK   \(s)") }
func bad(_ s: String) { print("    FAIL \(s)") }
func note(_ s: String) { print("    NOTE \(s)") }

func fmt(_ r: CGRect) -> String {
    String(format: "x %.0f, y %.0f, %.0f×%.0f pt", r.minX, r.minY, r.width, r.height)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func describeDisplays(_ label: String) {
    let ids = onlineDisplays()
    info("\(label): \(ids.count) online display(s)")
    for id in ids {
        let mode = CGDisplayCopyDisplayMode(id)
        let px = mode.map { "\($0.pixelWidth)×\($0.pixelHeight) px" } ?? "mode unknown"
        let flags = [CGDisplayIsMain(id) != 0 ? "main" : nil,
                     CGDisplayIsBuiltin(id) != 0 ? "built-in" : nil,
                     CGDisplayIsActive(id) != 0 ? "active" : "inactive",
                     CGDisplayMirrorsDisplay(id) != 0 ? "mirroring \(CGDisplayMirrorsDisplay(id))" : nil]
            .compactMap { $0 }.joined(separator: ", ")
        info("  id \(id): \(fmt(CGDisplayBounds(id))), \(px) (\(flags))")
    }
}

/// The .app that TCC will attribute this process to: the nearest ancestor inside an app bundle.
func responsibleApp() -> String {
    var pid = getpid()
    for _ in 0..<32 {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            let path = String(cString: buf)
            if let r = path.range(of: ".app/") { return String(path[..<r.lowerBound]) + ".app" }
        }
        var kp = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { break }
        let parent = kp.kp_eproc.e_ppid
        if parent <= 1 || parent == pid { break }
        pid = parent
    }
    return "the app that launched this tool (probably Terminal)"
}

// MARK: - Accessibility

struct AXWindow {
    let element: AXUIElement
    let title: String
    let frame: CGRect
}

func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p = axAttr(el, kAXPositionAttribute), let s = axAttr(el, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

@discardableResult
func axSetPosition(_ el: AXUIElement, _ point: CGPoint) -> AXError {
    var p = point
    guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
    return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
}

@discardableResult
func axSetSize(_ el: AXUIElement, _ size: CGSize) -> AXError {
    var s = size
    guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
    return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
}

func axWindows(pid: pid_t) -> [AXWindow] {
    let app = AXUIElementCreateApplication(pid)
    guard let list = axAttr(app, kAXWindowsAttribute) as? [AXUIElement] else { return [] }
    return list.compactMap { el in
        guard let frame = axFrame(el) else { return nil }
        return AXWindow(element: el, title: (axAttr(el, kAXTitleAttribute) as? String) ?? "", frame: frame)
    }
}

/// Title and frame together, then title alone, then frame alone.
func matchAXWindow(_ candidates: [AXWindow], title: String?, frame: CGRect) -> AXWindow? {
    func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 2 && abs(a.minY - b.minY) < 2 && abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
    let t = title ?? ""
    if let w = candidates.first(where: { $0.title == t && close($0.frame, frame) }) { return w }
    if !t.isEmpty, let w = candidates.first(where: { $0.title == t }) { return w }
    return candidates.first(where: { close($0.frame, frame) })
}

func axErrorName(_ e: AXError) -> String {
    switch e {
    case .success: return "success"
    case .apiDisabled: return "apiDisabled (Accessibility not granted)"
    case .cannotComplete: return "cannotComplete"
    case .attributeUnsupported: return "attributeUnsupported"
    case .illegalArgument: return "illegalArgument"
    case .invalidUIElement: return "invalidUIElement"
    case .notImplemented: return "notImplemented"
    default: return "AXError \(e.rawValue)"
    }
}

// MARK: - Window server view

struct CGWindowState {
    let bounds: CGRect
    let isOnscreen: Bool
}

func cgWindowState(_ id: CGWindowID) -> CGWindowState? {
    guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
          let d = list.first,
          let bd = d[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: bd) else { return nil }
    return CGWindowState(bounds: rect, isOnscreen: (d[kCGWindowIsOnscreen as String] as? Bool) ?? false)
}

// MARK: - Frame counting

/// Counts ScreenCaptureKit frames by status for one stream.
final class FrameCounter: NSObject, SCStreamOutput, SCStreamDelegate {
    let label: String
    private let lock = NSLock()
    private var complete = 0, idle = 0, other = 0
    private var firstSize: (Int, Int)?
    private(set) var stopError: Error?
    let queue: DispatchQueue

    init(label: String) {
        self.label = label
        self.queue = DispatchQueue(label: "probe.\(label)", qos: .userInteractive)
    }

    func reset() { lock.lock(); complete = 0; idle = 0; other = 0; lock.unlock() }

    var counts: (complete: Int, idle: Int, other: Int, size: (Int, Int)?) {
        lock.lock(); defer { lock.unlock() }
        return (complete, idle, other, firstSize)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        let raw = attachments?.first?[.status] as? Int
        let status = raw.flatMap(SCFrameStatus.init(rawValue:))
        lock.lock(); defer { lock.unlock() }
        switch status {
        case .complete?:
            complete += 1
            if firstSize == nil, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                firstSize = (CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb))
            }
        case .idle?: idle += 1
        default: other += 1
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); stopError = error; lock.unlock()
    }
}

func makeStream(filter: SCContentFilter, width: Int, height: Int, counter: FrameCounter) throws -> SCStream {
    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.queueDepth = 3
    config.showsCursor = false
    let stream = SCStream(filter: filter, configuration: config, delegate: counter)
    try stream.addStreamOutput(counter, type: .screen, sampleHandlerQueue: counter.queue)
    return stream
}

func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }

func sleep(seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

// MARK: - Cleanup (normal exit and Ctrl-C)

/// Everything that has to be undone, in the order it was done. Main thread only.
enum Cleanup {
    static var display: VirtualDisplay?
    static var moved: (element: AXUIElement, original: CGRect)?

    static func restoreWindow() {
        guard let m = moved else { return }
        moved = nil
        // Position first so the size fits on the original display, then again in case
        // the size change nudged it.
        axSetPosition(m.element, m.original.origin)
        axSetSize(m.element, m.original.size)
        axSetPosition(m.element, m.original.origin)
    }

    static func destroyDisplay() {
        display?.destroy()
        display = nil
    }

    static func all() {
        restoreWindow()
        destroyDisplay()
    }
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler {
    print("\n^C: restoring the window and removing the virtual display before exiting.")
    Cleanup.all()
    exit(130)
}
sigint.resume()

// MARK: - The experiment

func createDisplay() async throws -> VirtualDisplay {
    step("Create a \(options.widthPt)×\(options.heightPt) pt virtual display at \(options.scale)× (private CGVirtualDisplay API)")
    let problems = VirtualDisplay.checkPrivateAPI()
    if problems.isEmpty {
        good("all \(VirtualDisplay.privateAPISurface.count) private selectors present with expected signatures")
    } else {
        for p in problems { bad(p) }
        throw VirtualDisplay.Failure.classMissing("private API check failed; see above")
    }
    let before = Set(onlineDisplays())
    let t0 = Date()
    // Probe identity: its own serial so it doesn't disturb what macOS remembers for Sill.
    let vd = try VirtualDisplay(name: "Sill Probe", widthPt: options.widthPt, heightPt: options.heightPt,
                                scale: options.scale, vendorID: 0x5111, productID: 0x0001, serialNum: 0xF00D)
    Cleanup.display = vd
    let created = Date().timeIntervalSince(t0)
    let ok = await vd.waitUntilOnline(timeout: 3)
    let px = vd.pixelSize
    info(String(format: "displayID %u, created in %.0f ms, online after %.0f ms", vd.displayID,
                created * 1000, Date().timeIntervalSince(t0) * 1000))
    info("bounds \(fmt(vd.bounds)), backing \(px.width)×\(px.height) px")
    info("CGDisplayIsActive \(CGDisplayIsActive(vd.displayID) != 0), CGDisplayIsOnline \(CGDisplayIsOnline(vd.displayID) != 0), in CGGetOnlineDisplayList \(!before.contains(vd.displayID) && onlineDisplays().contains(vd.displayID))")
    if ok { good("requested mode is current") } else { bad("requested mode not current after 3 s (see modes below)") }
    if !ok {
        for m in vd.availableModes() { info("  mode: \(m)") }
    }
    return vd
}

func probeOnly() async -> Int32 {
    print("VirtualDisplayProbe --probe-only (no Screen Recording or Accessibility needed)")
    info("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    info("Screen Recording granted (preflight): \(CGPreflightScreenCaptureAccess()), Accessibility trusted: \(AXIsProcessTrusted())  [informational]")
    step("Displays before")
    describeDisplays("before")
    let vd: VirtualDisplay
    do { vd = try await createDisplay() } catch {
        bad("\(error)")
        note("The private API is unavailable here: Sill must fall back to streaming real windows.")
        return 1
    }
    let id = vd.displayID
    step("Displays with the virtual display")
    describeDisplays("with virtual")
    step("Destroy the virtual display")
    Cleanup.destroyDisplay()
    let t0 = Date()
    while onlineDisplays().contains(id) && Date().timeIntervalSince(t0) < 3 { await sleep(seconds: 0.05) }
    if onlineDisplays().contains(id) { bad("display \(id) still online after 3 s") }
    else { good(String(format: "display %u gone after %.0f ms", id, Date().timeIntervalSince(t0) * 1000)) }
    describeDisplays("after")
    print("\nResult: the private virtual-display API is callable on this Mac.")
    return 0
}

func fullRun(target: String) async -> Int32 {
    print("VirtualDisplayProbe: can a real window live on a virtual display and be captured there?")
    info("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), target \"\(target)\"")
    let grantee = responsibleApp()

    step("Check permissions")
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        good("Screen Recording: SCShareableContent lists \(content.displays.count) display(s), \(content.windows.count) window(s)")
    } catch {
        bad("Screen Recording is missing: SCShareableContent failed (\(error.localizedDescription))")
        info("Grant it to \(grantee):")
        info("System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen it and run again.")
        return 2
    }
    if content.windows.isEmpty {
        bad("Screen Recording looks missing: SCShareableContent returned 0 windows")
        info("Grant it to \(grantee) in System Settings › Privacy & Security › Screen & System Audio Recording.")
        return 2
    }
    let promptKey = "AXTrustedCheckOptionPrompt" as CFString
    if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
        bad("Accessibility is missing (needed to move the window onto the virtual display)")
        info("Grant it to \(grantee): System Settings › Privacy & Security › Accessibility, then run again.")
        return 3
    }
    good("Accessibility: trusted")

    step("Find the target window")
    let needle = target.lowercased()
    let normal = content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 50 && $0.frame.height > 50 }
    let matches = normal.filter {
        ($0.owningApplication?.applicationName.lowercased().contains(needle) ?? false) ||
        ($0.title?.lowercased().contains(needle) ?? false)
    }
    guard let window = matches.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
        bad("no on-screen window matches \"\(target)\". Windows available:")
        for w in normal { info("  \(w.owningApplication?.applicationName ?? "?") — \"\(w.title ?? "")\"") }
        return 4
    }
    guard let app = window.owningApplication else { bad("window has no owning application"); return 4 }
    let windowID = window.windowID
    let originalFrame = window.frame
    info("picked \(app.applicationName) — \"\(window.title ?? "")\", windowID \(windowID), pid \(app.processID), \(fmt(originalFrame))")
    if matches.count > 1 { info("(\(matches.count) matched; took the largest)") }
    if let s = cgWindowState(windowID) { info("kCGWindowIsOnscreen before: \(s.isOnscreen)") }

    step("Baseline: capture the window where it is now, \(Int(options.seconds)) s")
    note("Pick a window that changes on its own (a Terminal running `top -s 1`, Activity Monitor, a playing video), or the counts mean nothing.")
    let scaleF = CGFloat(options.scale)
    let baseline = FrameCounter(label: "baseline")
    do {
        let s = try makeStream(filter: SCContentFilter(desktopIndependentWindow: window),
                               width: evenPixels(originalFrame.width * scaleF), height: evenPixels(originalFrame.height * scaleF),
                               counter: baseline)
        try await s.startCapture()
        await sleep(seconds: 0.5); baseline.reset()
        await sleep(seconds: options.seconds)
        let c = baseline.counts
        try? await s.stopCapture()
        info(String(format: "window stream on its real display: %d complete (%.1f fps), %d idle, %d other",
                    c.complete, Double(c.complete) / options.seconds, c.idle, c.other))
    } catch {
        bad("baseline stream failed: \(error.localizedDescription)")
    }

    let vd: VirtualDisplay
    do { vd = try await createDisplay() } catch {
        bad("\(error)")
        note("The private API is unavailable here: Sill must fall back to streaming real windows.")
        return 5
    }
    let vb = vd.bounds

    step("Wait for ScreenCaptureKit to list the virtual display")
    var scDisplay: SCDisplay?
    let t0 = Date()
    while Date().timeIntervalSince(t0) < 3 {
        if let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
           let d = c.displays.first(where: { $0.displayID == vd.displayID }) { scDisplay = d; break }
        await sleep(seconds: 0.1)
    }
    guard let scDisplay else {
        bad("SCShareableContent never listed displayID \(vd.displayID) within 3 s")
        Cleanup.all()
        return 6
    }
    good(String(format: "listed after %.0f ms: ", Date().timeIntervalSince(t0) * 1000)
         + "SCDisplay \(scDisplay.displayID), frame \(fmt(scDisplay.frame)), \(scDisplay.width)×\(scDisplay.height)")
    info("CGDisplayIsActive \(CGDisplayIsActive(vd.displayID) != 0), CGDisplayIsOnline \(CGDisplayIsOnline(vd.displayID) != 0)")

    step("Move the window onto the virtual display (Accessibility)")
    let axList = axWindows(pid: app.processID)
    guard let ax = matchAXWindow(axList, title: window.title, frame: originalFrame) else {
        bad("could not find the window among \(axList.count) AX window(s) of \(app.applicationName)")
        Cleanup.all()
        return 7
    }
    let axOriginal = ax.frame
    Cleanup.moved = (ax.element, axOriginal)
    let margin: CGFloat = 20
    let dest = CGPoint(x: vb.minX + margin, y: vb.minY + margin)
    let fit = CGSize(width: min(axOriginal.width, vb.width - 2 * margin), height: min(axOriginal.height, vb.height - 2 * margin))
    var e = axSetPosition(ax.element, dest)
    info("set position \(Int(dest.x)), \(Int(dest.y)): \(axErrorName(e))")
    if fit != axOriginal.size {
        e = axSetSize(ax.element, fit)
        info("set size \(Int(fit.width))×\(Int(fit.height)) (window was larger than the display): \(axErrorName(e))")
        axSetPosition(ax.element, dest)
    }
    await sleep(seconds: 0.5)
    guard let moved = cgWindowState(windowID) else {
        bad("window \(windowID) vanished from CGWindowListCopyWindowInfo")
        Cleanup.all()
        return 7
    }
    info("window now \(fmt(moved.bounds)); virtual display \(fmt(vb))")
    let inside = vb.insetBy(dx: -1, dy: -1).contains(moved.bounds)
    let overlap = moved.bounds.intersection(vb)
    let fraction = overlap.isNull ? 0 : (overlap.width * overlap.height) / max(1, moved.bounds.width * moved.bounds.height)
    if inside { good("window is entirely inside the virtual display") }
    else { bad(String(format: "window is not inside the virtual display (%.0f%% overlap); the app may clamp its position", fraction * 100)) }
    info("kCGWindowIsOnscreen on the virtual display: \(moved.isOnscreen)")

    step("Capture for \(Int(options.seconds)) s: virtual display stream and window stream in parallel")
    guard let fresh = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false),
          let freshWindow = fresh.windows.first(where: { $0.windowID == windowID }),
          let freshDisplay = fresh.displays.first(where: { $0.displayID == vd.displayID }) else {
        bad("window or display missing from a fresh SCShareableContent")
        Cleanup.all()
        return 8
    }
    info("SCWindow.isOnScreen \(freshWindow.isOnScreen), frame \(fmt(freshWindow.frame))")
    let px = vd.pixelSize
    let dispW = px.width > 0 ? px.width : options.widthPt * options.scale
    let dispH = px.height > 0 ? px.height : options.heightPt * options.scale
    let displayCounter = FrameCounter(label: "display")
    let windowCounter = FrameCounter(label: "window")
    var streams: [SCStream] = []
    do {
        let a = try makeStream(filter: SCContentFilter(display: freshDisplay, including: [freshWindow]),
                               width: dispW, height: dispH, counter: displayCounter)
        let b = try makeStream(filter: SCContentFilter(desktopIndependentWindow: freshWindow),
                               width: evenPixels(freshWindow.frame.width * scaleF), height: evenPixels(freshWindow.frame.height * scaleF),
                               counter: windowCounter)
        try await a.startCapture(); streams.append(a)
        try await b.startCapture(); streams.append(b)
    } catch {
        bad("could not start capture: \(error.localizedDescription)")
    }
    if streams.count == 2 {
        await sleep(seconds: 0.5)
        displayCounter.reset(); windowCounter.reset()
        await sleep(seconds: options.seconds)
        for (label, counter) in [("display(virtual, including window)", displayCounter), ("desktopIndependentWindow", windowCounter)] {
            let c = counter.counts
            let size = c.size.map { "\($0.0)×\($0.1)" } ?? "no frame"
            info(String(format: "%@: %d complete (%.1f fps), %d idle, %d other, buffer %@", label,
                        c.complete, Double(c.complete) / options.seconds, c.idle, c.other, size))
            if let err = counter.stopError { bad("\(label) stopped: \(err.localizedDescription)") }
        }
        let d = displayCounter.counts.complete, w = windowCounter.counts.complete
        if d > 0 { good("the window repaints on the virtual display and the display stream delivers it") }
        else if w > 0 { bad("window stream gets frames but the virtual display stream does not") }
        else { note("no complete frames on either stream: the window did not change (pick one that animates), or it is not being drawn") }
    }
    for s in streams { try? await s.stopCapture() }

    step("Restore")
    Cleanup.restoreWindow()
    await sleep(seconds: 0.3)
    if let back = cgWindowState(windowID) {
        let ok = abs(back.bounds.minX - originalFrame.minX) < 2 && abs(back.bounds.minY - originalFrame.minY) < 2
            && abs(back.bounds.width - originalFrame.width) < 2 && abs(back.bounds.height - originalFrame.height) < 2
        if ok { good("window back at \(fmt(back.bounds))") } else { bad("window at \(fmt(back.bounds)), expected \(fmt(originalFrame))") }
    }
    let id = vd.displayID
    Cleanup.destroyDisplay()
    let t1 = Date()
    var gone = false
    while Date().timeIntervalSince(t1) < 3 {
        if let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
           !c.displays.contains(where: { $0.displayID == id }) { gone = true; break }
        await sleep(seconds: 0.1)
    }
    if gone { good(String(format: "display %u gone from SCShareableContent after %.0f ms", id, Date().timeIntervalSince(t1) * 1000)) }
    else { bad("display \(id) still listed by SCShareableContent after 3 s") }
    describeDisplays("after")
    return 0
}

// MARK: - Main

// An AppKit event loop is required, not optional: without it this process never receives
// display reconfiguration, so CoreGraphics can't see the new display's modes (see
// VirtualDisplay.swift). `.prohibited` keeps the probe out of the Dock and app switcher.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
_ = CGMainDisplayID()

Task { @MainActor in
    let code: Int32
    if options.probeOnly {
        code = await probeOnly()
    } else {
        code = await fullRun(target: options.target!)
    }
    Cleanup.all()
    exit(code)
}
app.run()
