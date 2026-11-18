import AppKit
import ApplicationServices
import CoreMedia
import Darwin
import ScreenCaptureKit

// TEST ONLY. The privacy probe, G0 of docs/privacy-mode-plan.md: what Sill's black windows would do on this Mac, for
// Noah to run himself (Scripts/privacy-probe/run.sh runs every command below in order, each spell under a hard 12 s kill
// from the shell). It darkens this Mac's screens in spells of at most 10 s: never run by an agent. It never uses the
// video encoder (ScreenCaptureKit hands it raw frames it only counts), never posts input but step 4's two pointer
// moves and two Shift presses, never changes a display's brightness, gamma or sleep, makes no virtual display and
// prints no window title, key or character.
//
// The black windows are the recipe Sill would use (#184's, docs/privacy-mode-plan.md "Files", PrivacyScreen): one
// borderless black window per screen (never Sill's own displays, vendor 0x5111, nor a zero-size one), no shadow,
// ignoring the mouse, on every Space, stationary, beside full-screen windows, out of the window cycle; ordered in
// without activating this process (an accessory app, as Sill.app is). Only the level and the opacity are the
// candidates':
//   S1  opaque, at .screenSaver (1000): #184's
//   S2  not opaque (isOpaque false, black content), at .screenSaver: may not count as covering what is under it
//   S3  opaque, at the shielding level (CGShieldingWindowLevel())
//   S4  opaque, at 1500
//
// Commands (each exits by itself before its deadline; the black windows go with the process whatever happens):
//   probe check                          what this Mac is, and whether the probe can run (exit 2 if not)
//   probe cover S1|S2|S3|S4 WINDOW-LOG   step 1: the test window (window.swift, its log), Safari and an Electron app
//                                        captured 2 s uncovered, 4 s under the candidate, 1.5 s after it lifts
//   probe levels TAG [--notify] [--text LINE]... [--candidate S1] [--seconds 9]
//                                        step 2: the black windows up with the prompt on them; the window server's
//                                        list every quarter second: what shows in front of them, at which layer
//   probe hold SECONDS [--candidate S1]  step 3: the black windows up until the shell kills or stops this process
//   probe gone PID [--present]           step 3: how long until the window server lists no window of PID (or, with
//                                        --present, that its windows are still listed)
//   probe events                         step 4: a tagged and an untagged posted event, and Noah's own, as NSEvent's
//                                        global monitor sees them
//   probe black SECONDS [--candidate S1] step 5: the black windows alone on every screen, for Noah to look at

setvbuf(stdout, nil, _IOLBF, 0)

/// The tag every event Sill posts will carry (DarkenPolicy.eventTag, CGEventSource.userData): the same value here.
let eventTag: Int64 = 0x5349_4C4C_5052_5631

func say(_ s: String) { print(s) }
func fail(_ s: String, _ code: Int32 = 2) -> Never { print(s); fflush(stdout); exit(code) }

// MARK: The deadline

/// Ends the process after `seconds` whatever the main thread is doing (its windows go with it), from a queue of its own.
var deadlineSource: DispatchSourceTimer?
func armDeadline(_ seconds: Double) {
    let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "probe.deadline"))
    t.schedule(deadline: .now() + seconds)
    t.setEventHandler {
        print("deadline: \(seconds) s are up; the probe ends itself, and its black windows with it")
        fflush(stdout)
        _exit(3)
    }
    t.resume()
    deadlineSource = t
}

// MARK: Arguments

var argv = Array(CommandLine.arguments.dropFirst())
guard let command = argv.first else { fail("usage: probe check|cover|levels|hold|gone|events|black …") }
argv.removeFirst()

func option(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}
func options(_ name: String) -> [String] {
    var out: [String] = []
    for (i, a) in argv.enumerated() where a == name && i + 1 < argv.count { out.append(argv[i + 1]) }
    return out
}
func flag(_ name: String) -> Bool { argv.contains(name) }

// MARK: The candidates and the black windows

enum Candidate: String, CaseIterable {
    case S1, S2, S3, S4

    var level: NSWindow.Level {
        switch self {
        case .S1, .S2: return .screenSaver
        case .S3: return NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        case .S4: return NSWindow.Level(rawValue: 1500)
        }
    }
    var opaque: Bool { self != .S2 }
    var words: String {
        switch self {
        case .S1: return "S1: opaque, at .screenSaver (\(NSWindow.Level.screenSaver.rawValue)), #184's"
        case .S2: return "S2: not opaque (black content), at .screenSaver (\(NSWindow.Level.screenSaver.rawValue))"
        case .S3: return "S3: opaque, at the shielding level (\(CGShieldingWindowLevel()))"
        case .S4: return "S4: opaque, at 1500"
        }
    }
}

func candidate(_ raw: String?) -> Candidate {
    guard let raw else { return .S1 }
    guard let c = Candidate(rawValue: raw) else { fail("unknown candidate \(raw): S1, S2, S3 or S4") }
    return c
}

/// A screen the black windows cover: every screen AppKit lists but Sill's own displays and zero-size ones.
struct Screen {
    let screen: NSScreen
    let id: CGDirectDisplayID
    var sill: Bool { CGDisplayVendorNumber(id) == 0x5111 }
}

@MainActor
func screens() -> [Screen] {
    NSScreen.screens.compactMap { s in
        guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return Screen(screen: s, id: CGDirectDisplayID(n.uint32Value))
    }
}

@MainActor
func covered() -> [Screen] { screens().filter { !$0.sill && $0.screen.frame.width > 0 && $0.screen.frame.height > 0 } }

/// The black windows, one per covered screen, made ordered out; `raise` orders them in, `lift` out.
@MainActor
final class Curtain {
    let candidate: Candidate
    private(set) var windows: [NSWindow] = []

    init(_ c: Candidate, text: [String] = []) {
        candidate = c
        for s in covered() {
            let w = NSWindow(contentRect: s.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.backgroundColor = .black
            w.isOpaque = c.opaque
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = c.level
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.setFrame(s.screen.frame, display: false)
            if !text.isEmpty {
                // The prompt, as Sill's hint would show (two centred lines, 15 pt, 35 % white on black).
                let label = NSTextField(wrappingLabelWithString: text.joined(separator: "\n"))
                label.font = .systemFont(ofSize: 15)
                label.textColor = NSColor(calibratedWhite: 1, alpha: 0.35)
                label.alignment = .center
                label.backgroundColor = .clear
                label.drawsBackground = false
                let size = NSSize(width: min(640, s.screen.frame.width - 40), height: 120)
                label.frame = NSRect(x: (s.screen.frame.width - size.width) / 2, y: (s.screen.frame.height - size.height) / 2,
                                     width: size.width, height: size.height)
                w.contentView?.addSubview(label)
            }
            windows.append(w)
        }
    }

    func raise() { for w in windows { w.orderFrontRegardless() } }
    func lift() { for w in windows { w.orderOut(nil) } }
    var numbers: Set<Int> { Set(windows.map(\.windowNumber)) }
}

// MARK: The window server's list

struct Listed {
    let number: Int
    let pid: Int32
    let owner: String
    let layer: Int
    let size: CGSize
    let alpha: Double
    /// Its place in the list, front to back.
    let index: Int
}

func windowList(onScreenOnly: Bool = true) -> [Listed] {
    let opts: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly] : [.optionAll]
    guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.enumerated().map { i, d in
        let b = d[kCGWindowBounds as String] as? [String: Any]
        let w = (b?["Width"] as? NSNumber)?.doubleValue ?? 0, h = (b?["Height"] as? NSNumber)?.doubleValue ?? 0
        return Listed(number: (d[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
                      pid: (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0,
                      owner: d[kCGWindowOwnerName as String] as? String ?? "?",
                      layer: (d[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                      size: CGSize(width: w, height: h),
                      alpha: (d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                      index: i)
    }
}

// MARK: ScreenCaptureKit, counted

/// One capture: the time of every complete frame (a frame ScreenCaptureKit sends because something changed).
final class Counted: NSObject, SCStreamOutput, SCStreamDelegate {
    let name: String
    private let lock = NSLock()
    private var stamps: [Double] = []
    var stream: SCStream?

    init(_ name: String) { self.name = name }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = atts.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let now = Date().timeIntervalSince1970
        lock.lock(); stamps.append(now); lock.unlock()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("  (the capture of \(name) stopped: \(error.localizedDescription))")
    }

    /// Frames per second between two times.
    func rate(_ a: Double, _ b: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard b > a else { return 0 }
        return Double(stamps.filter { $0 >= a && $0 < b }.count) / (b - a)
    }

    func start(_ filter: SCContentFilter, width: Int, height: Int) async throws {
        let c = SCStreamConfiguration()
        c.width = max(64, width)
        c.height = max(64, height)
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.queueDepth = 5
        c.showsCursor = false
        let s = SCStream(filter: filter, configuration: c, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "probe.capture.\(name)"))
        try await s.startCapture()
        stream = s
    }

    func stop() async { try? await stream?.stopCapture() }
}

/// The apps whose windows step 1 watches besides its own: Safari playing a video, and the first Electron (or Chromium)
/// app found.
let electron = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss",
                "com.todesktop.230313mzl4w4u92", "com.tinyspeck.slackmacgap", "com.hnc.Discord", "notion.id",
                "com.figma.Desktop", "com.github.GitHubClient", "md.obsidian", "com.google.Chrome", "com.brave.Browser",
                "com.microsoft.edgemac"]

/// The largest window on screen of `bundle` at the normal layer (no title read).
func largestWindow(_ content: SCShareableContent, _ bundle: String) -> SCWindow? {
    content.windows
        .filter { $0.owningApplication?.bundleIdentifier == bundle && $0.isOnScreen && $0.windowLayer == 0
                  && $0.frame.width >= 200 && $0.frame.height >= 150 }
        .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}

func rateText(_ r: Double) -> String { String(format: "%.1f", r) }

// MARK: check

@MainActor
func check() -> Never {
    let v = ProcessInfo.processInfo.operatingSystemVersionString
    var model = [CChar](repeating: 0, count: 64), size = 64
    sysctlbyname("hw.model", &model, &size, nil, 0)
    say("This Mac: \(String(cString: model)), macOS \(v).")
    for s in screens() {
        let builtIn = CGDisplayIsBuiltin(s.id) != 0
        let mirror = CGDisplayMirrorsDisplay(s.id)
        say(String(format: "Screen %u: %@, %.0f×%.0f pt at %.0fx, vendor 0x%X model 0x%X%@%@, EDR headroom %.2f now, %.2f possible%@",
                   s.id, s.screen.localizedName, s.screen.frame.width, s.screen.frame.height, s.screen.backingScaleFactor,
                   CGDisplayVendorNumber(s.id), CGDisplayModelNumber(s.id), builtIn ? ", built in" : "",
                   mirror != kCGNullDirectDisplay ? ", mirrors \(mirror)" : "",
                   s.screen.maximumExtendedDynamicRangeColorComponentValue,
                   s.screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
                   s.sill ? " (Sill's own: never covered)" : ""))
    }
    say("The black windows' levels: .screenSaver \(NSWindow.Level.screenSaver.rawValue), shielding \(CGShieldingWindowLevel()), maximum \(CGWindowLevelForKey(.maximumWindow)).")
    var ok = true
    if !CGPreflightScreenCaptureAccess() {
        say("MISSING: Screen Recording for the app this runs in (System Settings › Privacy & Security › Screen & System Audio Recording).")
        ok = false
    }
    if !AXIsProcessTrusted() {
        say("MISSING: Accessibility for the app this runs in (System Settings › Privacy & Security › Accessibility).")
        ok = false
    }
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    if (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true || (session[kCGSessionOnConsoleKey as String] as? NSNumber)?.boolValue == false {
        say("MISSING: an unlocked screen with this account on it.")
        ok = false
    }
    let sill = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "me.saffer.sill.mac" }
    if !sill.isEmpty {
        say("NOTE: Sill is running. Make sure no iPhone or iPad is connected to it during the probe (a device watching the Desktop would see the probe's black windows); quitting Sill is simplest.")
    }
    if covered().isEmpty {
        say("MISSING: a screen to cover.")
        ok = false
    }
    say(ok ? "Ready." : "Not ready: fix what is MISSING above and run again.")
    exit(ok ? 0 : 2)
}

// MARK: cover (step 1)

/// The test window's quarter-second lines: (epoch, visible, draws, display-link callbacks).
func windowQuarters(_ path: String) -> (pid: Int32, number: Int, quarters: [(Double, Bool, Int, Int)])? {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    var pid: Int32 = 0, number = 0
    var q: [(Double, Bool, Int, Int)] = []
    for line in text.split(separator: "\n") {
        let p = line.split(separator: " ")
        if p.first == "ready", p.count == 3 { pid = Int32(p[1]) ?? 0; number = Int(p[2]) ?? 0 }
        if p.first == "q", p.count == 6, let t = Double(p[1]) {
            func v(_ s: Substring) -> Int { Int(s.split(separator: "=").last ?? "") ?? 0 }
            q.append((t, v(p[2]) == 1, v(p[4]), v(p[5])))
        }
    }
    return pid == 0 ? nil : (pid, number, q)
}

@MainActor
func cover(_ c: Candidate, windowLog: String) async {
    let setupStarted = Date().timeIntervalSince1970
    guard let owner = windowQuarters(windowLog) else { fail("cover: no test window in \(windowLog) (run.sh starts it)") }
    let curtain = Curtain(c)
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    } catch {
        fail("cover: ScreenCaptureKit gave no content (\(error.localizedDescription)): Screen Recording for this terminal?")
    }
    var subjects: [(Counted, String)] = []
    func add(_ window: SCWindow?, _ label: String) async {
        guard let window else { say("  \(label): none on screen"); return }
        let counted = Counted(label)
        do {
            try await counted.start(SCContentFilter(desktopIndependentWindow: window),
                                    width: Int(window.frame.width), height: Int(window.frame.height))
            subjects.append((counted, label + String(format: " (%.0f×%.0f pt)", window.frame.width, window.frame.height)))
        } catch {
            say("  \(label): its capture did not start (\(error.localizedDescription))")
        }
    }
    await add(content.windows.first { Int($0.windowID) == owner.number }, "the test window")
    await add(largestWindow(content, "com.apple.Safari"), "Safari")
    var electronApp: String?
    let wanted = option("--electron").map { [$0] } ?? electron
    for b in wanted {
        if let w = largestWindow(content, b) { electronApp = w.owningApplication?.applicationName ?? b; await add(w, electronApp!); break }
    }
    if electronApp == nil { say("  an Electron or Chromium app: none on screen") }
    // The Desktop as Sill's capture takes it: the main display, the probe's own windows (the black ones) left out.
    let display = Counted("the display without the black windows")
    if let d = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) {
        let me = content.applications.first { $0.processID == getpid() }
        let filter: SCContentFilter
        if let me {
            filter = SCContentFilter(display: d, excludingApplications: [me], exceptingWindows: [])
        } else {
            let mine = content.windows.filter { curtain.numbers.contains(Int($0.windowID)) }
            say("  (the probe's app is not listed: its \(mine.count) black windows are left out one by one)")
            filter = SCContentFilter(display: d, excludingWindows: mine)
        }
        do {
            try await display.start(filter, width: d.width / 2, height: d.height / 2)
            subjects.append((display, "the main display, black windows left out"))
        } catch {
            say("  the display: its capture did not start (\(error.localizedDescription))")
        }
    }
    let setup = Date().timeIntervalSince1970 - setupStarted
    guard setup <= 3.5 else {
        for (s, _) in subjects { await s.stop() }
        fail("cover \(c.rawValue): setting up took \(String(format: "%.1f", setup)) s; nothing was darkened. Run it again.", 4)
    }
    let t0 = Date().timeIntervalSince1970
    try? await Task.sleep(for: .seconds(2))
    curtain.raise()
    let t1 = Date().timeIntervalSince1970
    try? await Task.sleep(for: .seconds(4))
    curtain.lift()
    let t2 = Date().timeIntervalSince1970
    try? await Task.sleep(for: .seconds(1.5))
    let t3 = Date().timeIntervalSince1970
    for (s, _) in subjects { await s.stop() }

    // Each phase skips its first half second (the change itself).
    let phases = [(t0 + 0.5, t1), (t1 + 0.5, t2), (t2 + 0.5, t3)]
    say("cover \(c.words): \(curtain.windows.count) black window\(curtain.windows.count == 1 ? "" : "s"); uncovered → covered → lifted")
    let quarters = windowQuarters(windowLog)?.quarters ?? []
    func q(_ a: Double, _ b: Double) -> (visible: Double, draws: Double, link: Double) {
        let inside = quarters.filter { $0.0 > a && $0.0 <= b }
        guard !inside.isEmpty else { return (0, 0, 0) }
        let span = Double(inside.count) * 0.25
        return (Double(inside.filter(\.1).count) / Double(inside.count) * 100,
                Double(inside.map(\.2).reduce(0, +)) / span, Double(inside.map(\.3).reduce(0, +)) / span)
    }
    let w = phases.map { q($0.0, $0.1) }
    say("  the test window: macOS calls it visible \(w.map { String(format: "%.0f%%", $0.visible) }.joined(separator: " → ")); "
        + "draws \(w.map { rateText($0.draws) }.joined(separator: " → ")) a second; "
        + "display link \(w.map { rateText($0.link) }.joined(separator: " → ")) a second")
    var verdicts: [String] = []
    for (s, label) in subjects {
        let r = phases.map { s.rate($0.0, $0.1) }
        say("  \(label): captured \(r.map(rateText).joined(separator: " → ")) frames a second")
        if s !== display, r[0] >= 2 {
            let kept = r[1] / r[0]
            verdicts.append("\(s.name) \(kept >= 0.5 ? "keeps drawing" : kept < 0.1 ? "STOPS" : "slows") (\(Int((kept * 100).rounded())) %)")
        }
    }
    if w[0].draws >= 10 {
        let kept = w[1].draws / w[0].draws
        verdicts.insert("the test window's own drawing \(kept >= 0.5 ? "goes on" : kept < 0.1 ? "STOPS" : "slows") (\(Int((kept * 100).rounded())) %)", at: 0)
    }
    say("  verdict \(c.rawValue): " + (verdicts.isEmpty ? "nothing drew before the black windows came, so nothing to judge" : verdicts.joined(separator: "; ")))
    exit(0)
}

// MARK: levels (step 2)

@MainActor
func levels(tag: String, notify: Bool, text: [String], c: Candidate, seconds: Double) async {
    let before = Set(windowList().map(\.number))
    let curtain = Curtain(c, text: text)
    curtain.raise()
    let started = Date().timeIntervalSince1970
    if notify {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "display notification \"A test notification from Sill's privacy probe\" with title \"Sill\""]
            try? p.run()
        }
    }
    struct Seen { var first: Double; var last: Double; var layer: Int; var owner: String; var size: CGSize; var front: Bool; var alpha: Double }
    var seen: [Int: Seen] = [:]
    var curtainLayer: Int?
    var curtainListed = 0
    while Date().timeIntervalSince1970 - started < seconds {
        let list = windowList()
        let ours = list.filter { curtain.numbers.contains($0.number) }
        curtainListed = max(curtainListed, ours.count)
        if let l = ours.first?.layer { curtainLayer = l }
        let frontmost = ours.map(\.index).min() ?? Int.max
        let t = Date().timeIntervalSince1970 - started
        for w in list where !curtain.numbers.contains(w.number) {
            // What matters: anything in front of the black windows, and anything new above the normal layer.
            let front = w.index < frontmost
            guard front || (!before.contains(w.number) && w.layer > 0) else { continue }
            if var s = seen[w.number] {
                s.last = t; s.front = s.front || front; s.layer = w.layer
                seen[w.number] = s
            } else {
                seen[w.number] = Seen(first: t, last: t, layer: w.layer, owner: w.owner, size: w.size, front: front, alpha: w.alpha)
            }
        }
        try? await Task.sleep(for: .milliseconds(250))
    }
    curtain.lift()
    say("levels \(tag) under \(c.words): the black windows listed \(curtainListed) of \(curtain.windows.count), at layer \(curtainLayer.map(String.init) ?? "?")")
    if seen.isEmpty { say("  nothing in front of them, and nothing new above the normal layer") }
    for (n, s) in seen.sorted(by: { $0.value.first < $1.value.first }) {
        say(String(format: "  %@ %@ (window %d) at layer %d, %.0f×%.0f, alpha %.2f, from %.1f s to %.1f s",
                   s.front ? "IN FRONT:" : "behind:  ", s.owner, n, s.layer, s.size.width, s.size.height, s.alpha, s.first, s.last))
    }
    exit(0)
}

// MARK: hold, gone (step 3)

@MainActor
func hold(_ c: Candidate) {
    let curtain = Curtain(c)
    curtain.raise()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let listed = windowList().filter { curtain.numbers.contains($0.number) }.count
        say("up \(getpid()): \(listed) of \(curtain.windows.count) black windows listed")
    }
}

func gone(pid: Int32, present: Bool) -> Never {
    let start = Date()
    if present {
        let n = windowList(onScreenOnly: false).filter { $0.pid == pid }.count
        say("windows of \(pid) still listed: \(n)")
        exit(0)
    }
    while Date().timeIntervalSince(start) < 3 {
        if !windowList(onScreenOnly: false).contains(where: { $0.pid == pid }) {
            say(String(format: "windows of %d gone after %.0f ms", pid, Date().timeIntervalSince(start) * 1000))
            exit(0)
        }
        usleep(10_000)
    }
    say("windows of \(pid) STILL LISTED after 3 s")
    exit(1)
}

// MARK: events (step 4)

@MainActor
func events() async {
    guard AXIsProcessTrusted() else { fail("events: needs Accessibility for the app this runs in") }
    struct Got { let at: Double; let type: String; let userData: Int64; let pid: Int64; let state: Int64 }
    var got: [Got] = []
    let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .flagsChanged, .keyDown, .leftMouseDown]) { e in
        guard let cg = e.cgEvent else { return }
        got.append(Got(at: Date().timeIntervalSince1970, type: "\(e.type)",
                       userData: cg.getIntegerValueField(.eventSourceUserData),
                       pid: cg.getIntegerValueField(.eventSourceUnixProcessID),
                       state: cg.getIntegerValueField(.eventSourceStateID)))
    }
    defer { if let monitor { NSEvent.removeMonitor(monitor) } }
    // Posted as InputInjector posts (a .hidSystemState source, the HID tap): first tagged, then untagged.
    func post(tagged: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        if tagged { src?.userData = eventTag }
        let at = CGEvent(source: nil)?.location ?? .zero
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        for down in [true, false] {
            guard let k = CGEvent(keyboardEventSource: src, virtualKey: 56, keyDown: down) else { continue }   // Shift
            k.type = .flagsChanged
            k.flags = down ? .maskShift : []
            k.post(tap: .cghidEventTap)
        }
    }
    let t0 = Date().timeIntervalSince1970
    post(tagged: true)
    try? await Task.sleep(for: .milliseconds(400))
    let t1 = Date().timeIntervalSince1970
    post(tagged: false)
    try? await Task.sleep(for: .milliseconds(400))
    let t2 = Date().timeIntervalSince1970
    say("events: now move the mouse a little and press Shift once (5 seconds).")
    try? await Task.sleep(for: .seconds(5))
    let t3 = Date().timeIntervalSince1970
    func show(_ label: String, _ a: Double, _ b: Double) {
        let these = got.filter { $0.at >= a && $0.at < b }
        if these.isEmpty { say("  \(label): none seen"); return }
        var kinds: [String: Got] = [:]
        for g in these where kinds[g.type] == nil { kinds[g.type] = g }
        for (k, g) in kinds.sorted(by: { $0.key < $1.key }) {
            say(String(format: "  %@ %@: userData 0x%llX, source pid %lld, source state %lld", label, k, g.userData, g.pid, g.state))
        }
    }
    show("tagged, posted:", t0, t1)
    show("untagged, posted:", t1, t2)
    show("Noah's own:", t2, t3)
    let tagged = got.filter { $0.at >= t0 && $0.at < t1 }
    let rest = got.filter { $0.at >= t1 && $0.at < t3 }
    let tagSurvives = !tagged.isEmpty && tagged.allSatisfy { $0.userData == eventTag } && rest.allSatisfy { $0.userData != eventTag }
    let pidTells = !tagged.isEmpty && tagged.allSatisfy { $0.pid == Int64(getpid()) }
        && got.filter { $0.at >= t2 && $0.at < t3 }.allSatisfy { $0.pid != Int64(getpid()) }
    say("  verdict: the tag \(tagSurvives ? "survives" : "is LOST") in the global monitor; the source pid \(pidTells ? "also tells Sill's own events apart" : "does not tell them apart")")
    exit(0)
}

// MARK: black (step 5)

@MainActor
func black(_ c: Candidate, seconds: Double) async {
    let curtain = Curtain(c)
    curtain.raise()
    say("black: \(curtain.windows.count) screen\(curtain.windows.count == 1 ? "" : "s") under \(c.words) for \(Int(seconds)) s")
    try? await Task.sleep(for: .seconds(seconds))
    curtain.lift()
    exit(0)
}

// MARK: Main

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

switch command {
case "check":
    Task { @MainActor in check() }
case "gone":
    guard let p = argv.first.flatMap({ Int32($0) }) else { fail("usage: probe gone PID [--present]") }
    gone(pid: p, present: flag("--present"))
case "cover":
    guard argv.count >= 2 else { fail("usage: probe cover S1|S2|S3|S4 WINDOW-LOG") }
    let c = candidate(argv[0]), log = argv[1]
    armDeadline(11.5)
    Task { @MainActor in await cover(c, windowLog: log) }
case "levels":
    guard let tag = argv.first else { fail("usage: probe levels TAG [--notify] [--text LINE]… [--candidate S1] [--seconds 9]") }
    let seconds = min(10, Double(option("--seconds") ?? "9") ?? 9)
    armDeadline(seconds + 1.5)
    let c = candidate(option("--candidate")), text = options("--text"), notify = flag("--notify")
    Task { @MainActor in await levels(tag: tag, notify: notify, text: text, c: c, seconds: seconds) }
case "hold":
    let seconds = min(10, Double(argv.first ?? "10") ?? 10)
    armDeadline(seconds)
    let c = candidate(option("--candidate"))
    Task { @MainActor in hold(c) }
case "events":
    armDeadline(10)
    Task { @MainActor in await events() }
case "black":
    let seconds = min(10, Double(argv.first ?? "10") ?? 10)
    armDeadline(seconds + 1.5)
    let c = candidate(option("--candidate"))
    Task { @MainActor in await black(c, seconds: seconds) }
default:
    fail("unknown command \(command): check, cover, levels, hold, gone, events or black")
}
app.run()
