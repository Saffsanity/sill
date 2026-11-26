// TEST ONLY. Probe P2b ("probe2"), vd-2b's sharper modes probe, 2026-11-23: can Sill's Desktop display take a device's
// turn, or a second device's shape, IN PLACE, by giving the live display a new list of modes (applySettings: sent
// again, VirtualDisplay.applyModes) and letting macOS take it, with no switchMode before the look? The answer chooses
// VirtualDesktopSize.followWay (PR #408). A copy of Scripts/display-modes-probe/probe.swift (wt-vd-2b at b7339612) with
// new steps, built with that branch's Sources/SillHost/VirtualDisplay.swift copied unchanged into src/ (NOTES.md has its
// sha256). run.sh builds it once and runs it; NOTES.md says what each verdict line means.
//
// Without --make (the dry run, what an agent runs): nothing is made, shown, moved or posted. It checks the private API's
// surface and lists the private classes' methods (lookups only: no display), and prints the case, its modes, the
// backing, the steps and what each measures. Exit 0 when the surface is there, 1 when not, 2 for a bad argument.
//
// With --make (Noah's, from run.sh, on a Mac at rest: Sill quit, no device connected): it makes one display, "Sill
// Probe" (vendor 0x5111, product 0x0002, serial 0xF00D: Sill's Desktop identity with a serial of its own, as the old
// probe, so macOS remembers nothing for Sill's own display), with the room both ways as its modes (as
// VirtualDesktopSize.otherModes makes it for a way in place, so its backing holds a turn), at 2x and the rate given;
// waits until AppKit's screen list has it where CoreGraphics has it (the old probe's window landed on display 1 because
// the screen frame it read was not yet the display's: NOTES.md), then puts two windows of its own on it, set after they
// are ordered in and verified with the window server (a small one, and a large one that does not fit the turn); then,
// each change looked at every 10 ms, timed, with every reconfiguration callback and its flags, and NO switchMode before
// the look (the old probe's switchMode answered false only because it looked for the new mode before macOS had applied
// the list):
//   0. the turn listed at creation, switched by CoreGraphics (VirtualDisplay.switchMode's calls, with their codes);
//   a. applySettings: with the turn alone; macOS's list 300 ms later; back by the room alone (the same means);
//   b. with [the room, the turn]; then f: a switch by CoreGraphics to the other of the two, and back, once listed;
//   c. with [the turn, the room];                          b, c, g and h tell which mode macOS takes from a new
//   g. with [90 % of the room, the room];                  list: the first, the last, the current one, the
//   h. with [the room, 60 % of the room];                  smallest or the largest; each is followed by the room
//   e. another shape, a second device's room (the iPhone's 1496x800 on an iPad mini's display, the iPad mini's 1218x800
//      on an iPhone's): alone when it fits the backing, else listed after the room (as P2's step 3, so the list always
//      holds a mode the display can take);                 alone again when the display is not at it
// then removes the display. After each: what the display is at (bounds, backing, rate, mode), when it got there, the
// same ID or not, the callbacks, and where each window is and its size (a window found off the display is put back on
// it, or hidden). It ends with one verdict line for each question, from what was SEEN (the display's size after the
// wait), never from what a call answered. It never moves the pointer, posts no event, never activates (an accessory
// app), touches no other app's window, and links no VideoToolbox or ScreenCaptureKit. The display goes at the end, on
// every early stop, on Ctrl-C (SIGINT, SIGTERM, SIGHUP), and at --limit seconds (24) the process ends itself; macOS
// removes a process's display when the process exits. Exit 0 when it ran to the end, whatever macOS did; 1 when the
// display could not be made or was lost; 2 for a bad argument; 3 at the time limit; 130 when stopped.
import AppKit
import CoreGraphics
import Foundation
import ObjectiveC

setvbuf(stdout, nil, _IOLBF, 0)
let probeVersion = "probe2 r1 (vd-2b, 2026-11-23)"

// MARK: Output: the terminal and, with --log, run.sh's out-<date>-<time>.txt

final class Out: @unchecked Sendable {
    static let shared = Out()
    private let lock = NSLock()
    var file: FileHandle?
    func say(_ s: String) {
        lock.lock(); defer { lock.unlock() }
        print(s)
        if let file, let data = (s + "\n").data(using: .utf8) { try? file.write(contentsOf: data) }
    }
}
func say(_ s: String) { Out.shared.say(s) }

// MARK: Arguments

typealias Size = VirtualDisplay.ModeSize

func sizeArg(_ s: String) -> Size? {
    let p = s.lowercased().split(separator: "x")
    guard p.count == 2, let w = Int(p[0]), let h = Int(p[1]), w > 0, h > 0 else { return nil }
    return Size(width: w, height: h)
}

func usage(_ why: String) -> Never {
    print("probe2: \(why) (usage: probe2 [--make] [WxH] [HZ] [--other WxH] [--label TEXT] [--log FILE] [--limit SECONDS])")
    exit(2)
}

var make = false
var logPath: String? = nil
var otherGiven: Size? = nil
var labelGiven: String? = nil
var limit = 24.0
var positional: [String] = []
let cliArgs = Array(CommandLine.arguments.dropFirst())
var argIndex = 0
func argValue() -> String {
    argIndex += 1
    guard argIndex < cliArgs.count else { usage("\(cliArgs[argIndex - 1]) needs a value") }
    return cliArgs[argIndex]
}
while argIndex < cliArgs.count {
    switch cliArgs[argIndex] {
    case "--make": make = true
    case "--log": logPath = argValue()
    case "--other":
        guard let s = sizeArg(argValue()) else { usage("--other takes WxH") }
        otherGiven = s
    case "--label": labelGiven = argValue()
    case "--limit":
        guard let v = Double(argValue()), v >= 5, v <= 120 else { usage("--limit takes 5 to 120 seconds") }
        limit = v
    default: positional.append(cliArgs[argIndex])
    }
    argIndex += 1
}
for p in positional where sizeArg(p) == nil && Int(p) == nil { usage("unknown argument \(p)") }
let room = positional.lazy.compactMap(sizeArg).first ?? Size(width: 1218, height: 800)
let hz = Double(positional.lazy.compactMap { Int($0) }.first ?? 60)
if room.width < 320 || room.height < 320 || room.width > 4096 || room.height > 4096 || hz < 24 || hz > 240 {
    usage("the room must be 320 to 4096 points a side and the rate 24 to 240 Hz")
}

// MARK: The case: its modes, its backing, its other shape, its windows

let landscape = room.width >= room.height
let turned = room.turned
func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
func scaled(_ s: Size, _ f: Double) -> Size { Size(width: even(Double(s.width) * f), height: even(Double(s.height) * f)) }
let smaller = scaled(room, 0.9)
let tiny = scaled(room, 0.6)
let tinyOK = tiny.width >= 320 && tiny.height >= 240
/// VirtualDesktopSize.device for an iPhone 15 Pro's room clear of the Dynamic Island (735×393) and an iPad mini's
/// (1133×744): Tests/checks/virtual-desktop's table.
let iPhoneRoom = Size(width: 1496, height: 800)
let iPadMiniRoom = Size(width: 1218, height: 800)
func heldLikeRoom(_ s: Size) -> Size { (s.width >= s.height) == landscape ? s : s.turned }
/// A second device's room, held the way the room is: the iPhone's beside an iPad mini, the iPad mini's beside an iPhone.
let other = otherGiven ?? heldLikeRoom(room == iPhoneRoom || room == iPhoneRoom.turned ? iPadMiniRoom : iPhoneRoom)
let madeWith = VirtualDisplay.modeList(asked: room, others: [turned])
let backing = VirtualDisplay.maxPixels(madeWith, scale: 2)
func fits(_ s: Size) -> Bool { s.width * 2 <= backing.wide && s.height * 2 <= backing.high }
let otherFits = fits(other)
let otherList = otherFits ? [other] : [room, other]
let caseName = labelGiven ?? "\(room) at \(Int(hz)) Hz"
let tag = "P2b [\(caseName)]"
let smallContent = NSSize(width: 480, height: 320)
/// Larger than the turn along the room's long side, so the turn shows what macOS does with a window that no longer fits.
let largeContent = landscape
    ? NSSize(width: even(Double(room.width) * 0.8), height: even(Double(room.height) * 0.5))
    : NSSize(width: even(Double(room.width) * 0.5), height: even(Double(room.height) * 0.8))

func listWords(_ l: [Size]) -> String { "[" + l.map(\.description).joined(separator: ", ") + "]" }
func ms(_ t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
func rectWords(_ r: NSRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))" }

func selectorNames(_ className: String) -> [String] {
    guard let c = NSClassFromString(className) else { return ["(class not found)"] }
    var n: UInt32 = 0
    guard let list = class_copyMethodList(c, &n) else { return [] }
    defer { free(list) }
    return (0..<Int(n)).map { NSStringFromSelector(method_getName(list[$0])) }.sorted()
}

// MARK: The plan (both runs print it)

if let logPath, make {
    if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
    if let f = FileHandle(forWritingAtPath: logPath) { _ = try? f.seekToEnd(); Out.shared.file = f }
}
say("Display modes probe P2b, \(probeVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\(make ? "" : ": the dry run, nothing made")")
let problems = VirtualDisplay.checkPrivateAPI()
if problems.isEmpty {
    say("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present (looked up only)")
} else {
    for p in problems { say("  FAIL \(p)") }
}
if !make {
    for c in ["CGVirtualDisplaySettings", "CGVirtualDisplayMode", "CGVirtualDisplayDescriptor", "CGVirtualDisplay"] {
        say("  \(c)'s methods (looked up only): \(selectorNames(c).joined(separator: " "))")
    }
}
say("  the case: \(caseName): the room \(room) pt at \(Int(hz)) Hz, on \"Sill Probe\" (vendor 0x5111, product 0x0002, serial 0xF00D, not Sill's own), 2x")
say("  made with \(madeWith.count) modes, \(listWords(madeWith)) pt (the room both ways, as VirtualDesktopSize.otherModes for a way in place); backing \(backing.wide)×\(backing.high) px")
say("  windows of its own on it: small \(Int(smallContent.width))×\(Int(smallContent.height)) and large \(Int(largeContent.width))×\(Int(largeContent.height)) pt of content, centered, set after they are ordered in and checked with the window server")
say("  step 0: the turn \(turned), listed at creation, switched by CoreGraphics (VirtualDisplay.switchMode's calls, with their codes)")
say("  step a: applySettings: with \(listWords([turned])) alone, no switch; macOS's list 300 ms later; back by \(listWords([room])) alone")
say("  step b: applySettings: with \(listWords([room, turned])); step f: macOS's list 300 ms later, then a switch by CoreGraphics to the other of the two, and back")
say("  step c: applySettings: with \(listWords([turned, room]))")
say("  step g: applySettings: with \(listWords([smaller, room]))")
say("  step h: \(tinyOK ? "applySettings: with \(listWords([room, tiny]))" : "skipped: 60 % of the room is under 320×240")")
say("  step e: another shape, \(other) (\(otherFits ? "inside the backing" : "beyond the backing: \(other.width * 2)×\(other.height * 2) px"), \(other == room ? "the room itself: skipped" : "applySettings: with \(listWords(otherList))")")
say("  each of a to h and e is followed by \(listWords([room])) alone when the display is not at \(room)")
say("  after each: what the display is at (bounds, backing, rate, mode), when, the same ID or not, the callbacks' flags, where each window is and its size")
guard make else {
    say("  dry run: nothing made. Noah, from Terminal.app, with Sill quit and no device connected: zsh ~/Downloads/sill-handoff/next/vd-2b/probe2/run.sh")
    exit(problems.isEmpty ? 0 : 1)
}
guard problems.isEmpty else { exit(1) }

// MARK: The real run (--make)

/// The reconfiguration callback's records, as they come (main thread, through the AppKit event port).
final class Changes: @unchecked Sendable {
    struct Record { var at: Date; var id: CGDirectDisplayID; var flags: CGDisplayChangeSummaryFlags }
    private let lock = NSLock()
    private var records: [Record] = []
    func add(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
        lock.lock(); records.append(Record(at: Date(), id: id, flags: flags)); lock.unlock()
    }
    /// Every record since `t`, the begin-configuration ones left out.
    func since(_ t: Date) -> [Record] {
        lock.lock(); defer { lock.unlock() }
        return records.filter { $0.at >= t && $0.flags != .beginConfigurationFlag }
    }
}
let changes = Changes()
CGDisplayRegisterReconfigurationCallback({ id, flags, context in
    guard let context else { return }
    Unmanaged<Changes>.fromOpaque(context).takeUnretainedValue().add(id, flags)
}, Unmanaged.passUnretained(changes).toOpaque())

func flagWords(_ flags: CGDisplayChangeSummaryFlags) -> String {
    let named: [(CGDisplayChangeSummaryFlags, String)] = [
        (.movedFlag, "moved"), (.setMainFlag, "setMain"), (.setModeFlag, "setMode"), (.addFlag, "add"),
        (.removeFlag, "remove"), (.enabledFlag, "enabled"), (.disabledFlag, "disabled"), (.mirrorFlag, "mirror"),
        (.unMirrorFlag, "unMirror"), (.desktopShapeChangedFlag, "desktopShapeChanged"),
    ]
    let words = named.filter { flags.contains($0.0) }.map { $0.1 }
    return words.isEmpty ? "(no flags)" : words.joined(separator: ",")
}

func onlineIDs() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(n, 1)) + 4)
    CGGetOnlineDisplayList(UInt32(ids.count), &ids, &n)
    return Array(ids.prefix(Int(n)))
}

/// What the display is at, as this process's CoreGraphics reads it.
struct Look: Equatable {
    var online = false
    var x = 0, y = 0, w = 0, h = 0
    var pw = 0, ph = 0, hz = 0
    var modeID: Int32 = 0
    var size: Size { Size(width: w, height: h) }
    var scale: Int { w > 0 && pw > 0 ? Int((Double(pw) / Double(w)).rounded()) : 0 }
    var words: String { online ? "\(w)×\(h) pt, \(pw)×\(ph) px @\(scale)×, \(hz) Hz, at \(x),\(y), mode \(modeID)" : "not online" }
    var short: String {
        guard online else { return "offline" }
        return scale == 2 ? "\(w)×\(h)" : "\(w)×\(h) @\(scale)×"
    }
}

func look(_ id: CGDirectDisplayID) -> Look {
    var l = Look()
    l.online = onlineIDs().contains(id)
    guard l.online else { return l }
    let b = CGDisplayBounds(id)
    l.x = Int(b.minX); l.y = Int(b.minY); l.w = Int(b.width); l.h = Int(b.height)
    if let m = CGDisplayCopyDisplayMode(id) {
        l.pw = m.pixelWidth; l.ph = m.pixelHeight; l.hz = Int(m.refreshRate.rounded()); l.modeID = m.ioDisplayModeID
    }
    return l
}

func allModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    return (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
}

/// macOS's modes for the display at 2x (the 1x ones only counted), the current one and the unusable ones marked.
func hiDPIModes(_ id: CGDirectDisplayID) -> String {
    let modes = allModes(id)
    let current = CGDisplayCopyDisplayMode(id)?.ioDisplayModeID
    let twice = modes.filter { $0.pixelWidth == $0.width * 2 }
    return "\(modes.count) modes, \(twice.count) at 2×: " + twice.map { m in
        "\(m.width)×\(m.height)\(m.ioDisplayModeID == current ? " (current)" : "")\(m.isUsableForDesktopGUI() ? "" : " (not usable)")"
    }.joined(separator: ", ")
}

/// Whether macOS lists `s` at 2x for the display, and whether it is usable for the desktop.
func listedWords(_ id: CGDirectDisplayID, _ s: Size) -> String {
    guard let m = allModes(id).first(where: { $0.width == s.width && $0.height == s.height && $0.pixelWidth == s.width * 2 }) else {
        return "\(s) at 2× NOT listed"
    }
    return "\(s) at 2× listed, \(m.isUsableForDesktopGUI() ? "usable" : "NOT usable") for the desktop (mode \(m.ioDisplayModeID), flags 0x\(String(m.ioFlags, radix: 16)))"
}

func cgErrorWords(_ e: CGError) -> String {
    let words: [Int32: String] = [0: "success", 1000: "failure", 1001: "illegal argument", 1002: "invalid connection",
                                  1003: "invalid context", 1004: "cannot complete", 1006: "not implemented",
                                  1007: "range check", 1008: "type check", 1010: "invalid operation", 1011: "none available"]
    return "\(e.rawValue)\(words[e.rawValue].map { " " + $0 } ?? "")"
}

/// VirtualDisplay.switchMode's calls (selectRequestedMode: the 2x mode of that size in macOS's list,
/// CGConfigureDisplayWithDisplayMode, CGCompleteDisplayConfiguration for the session), with every code said.
func explicitSwitch(_ id: CGDirectDisplayID, to s: Size) -> (words: String, asked: Bool) {
    let modes = allModes(id)
    guard let want = modes.first(where: { $0.width == s.width && $0.height == s.height && $0.pixelWidth == s.width * 2 }) else {
        return ("\(s) at 2× not in macOS's list of \(modes.count): nothing asked", false)
    }
    let mode = "mode \(want.ioDisplayModeID), flags 0x\(String(want.ioFlags, radix: 16)), usable for the desktop: \(want.isUsableForDesktopGUI() ? "yes" : "no")"
    var config: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&config)
    guard begin == .success else { return ("begin \(cgErrorWords(begin)): nothing asked (\(mode))", false) }
    let configure = CGConfigureDisplayWithDisplayMode(config, id, want, nil)
    let complete = CGCompleteDisplayConfiguration(config, .forSession)
    return ("configure \(cgErrorWords(configure)), complete \(cgErrorWords(complete)) (\(mode))", configure == .success && complete == .success)
}

/// A display's frame in AppKit's global coordinates, from CoreGraphics' bounds (the main display's height flips y).
func appKitRect(_ b: CGRect) -> NSRect {
    let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
    return NSRect(x: b.minX, y: mainHeight - b.maxY, width: b.width, height: b.height)
}

@MainActor func screenID(_ s: NSScreen) -> CGDirectDisplayID? {
    (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}

@MainActor func nsScreen(_ id: CGDirectDisplayID) -> NSScreen? { NSScreen.screens.first { screenID($0) == id } }

/// The window as the window server has it (CoreGraphics coordinates): our own window's bounds only.
@MainActor func serverRect(_ w: NSWindow) -> CGRect? {
    guard w.windowNumber > 0,
          let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(w.windowNumber)) as? [[String: Any]],
          let first = info.first, let dict = first[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
    return r
}

func displayAt(_ p: CGPoint) -> CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    guard CGGetDisplaysWithPoint(p, 8, &ids, &n) == .success, n > 0 else { return nil }
    return ids[0]
}

struct Seen {
    var end: Look
    var path: [(ms: Int, look: Look)]
    var ours: [(ms: Int, words: String)]
    var others: [String]
    var removedOrAdded: Bool
    var newIDs: [CGDirectDisplayID]
    func landedMs(at s: Size) -> Int? { path.first { $0.look.online && $0.look.size == s }?.ms }
}

struct WindowSeen {
    var on: Bool
    var inside: Bool
    var resized: Bool
    var words: String
}

struct StepResult {
    var key: String
    var list: [Size]?
    var start: Look
    var answered: String
    var seen: Seen
    var windows: [WindowSeen]
}

struct Rule {
    let name: String
    let predict: (Size, [Size]) -> [Size]?
}

@MainActor final class ProbeWindow {
    let name: String
    let content: NSSize
    let window: NSWindow
    var placedSize = NSSize.zero
    var hidden = false
    init(name: String, content: NSSize, window: NSWindow) { self.name = name; self.content = content; self.window = window }
}

@MainActor final class Probe {
    static var current: Probe?
    let d: VirtualDisplay
    let id: CGDirectDisplayID
    let before: [CGDirectDisplayID]
    var windows: [ProbeWindow] = []
    var results: [String: StepResult] = [:]
    var order: [String] = []
    var lastEnd: Look?
    var ending = false
    var listedAfterA = "not reached"
    var listedBeforeF = "not reached"
    var fTo: Size = turned
    var fBack: Size = room

    init(d: VirtualDisplay, before: [CGDirectDisplayID]) { self.d = d; self.id = d.displayID; self.before = before }

    // MARK: Looking

    /// Looks every 10 ms from `t0` until the display has been quiet `settle` after its last change or callback (and at
    /// least half a second has passed), or `quiet` with nothing at all, or `cap`. Selects nothing: what macOS does alone.
    func observe(_ t0: Date, from start: Look, quiet: Double, settle: Double = 0.4, cap: Double = 3) async -> Seen {
        var last = start
        var path: [(ms: Int, look: Look)] = []
        while true {
            try? await Task.sleep(for: .milliseconds(10))
            let now = Date().timeIntervalSince(t0)
            let l = look(id)
            if l != last { path.append((ms: Int(now * 1000), look: l)); last = l }
            let ours = changes.since(t0).filter { $0.id == id }
            let times: [Double?] = [path.last.map { Double($0.ms) / 1000 }, ours.last.map { $0.at.timeIntervalSince(t0) }]
            let activity = times.compactMap { $0 }.max()
            if now >= cap { break }
            if let activity {
                if now >= max(activity + settle, 0.5) { break }
            } else if now >= quiet {
                break
            }
        }
        let all = changes.since(t0)
        let ours = all.filter { $0.id == id }.map { (ms: Int($0.at.timeIntervalSince(t0) * 1000), words: flagWords($0.flags)) }
        var others: [String] = []
        for r in all where r.id != id {
            let s = "\(r.id) \(flagWords(r.flags))"
            if !others.contains(s) { others.append(s) }
        }
        let removed = all.contains { $0.id == id && ($0.flags.contains(.removeFlag) || $0.flags.contains(.addFlag)) }
        let newIDs = onlineIDs().filter { !before.contains($0) && $0 != id }
        return Seen(end: last, path: path, ours: ours, others: others, removedOrAdded: removed, newIDs: newIDs)
    }

    /// One change: the call, then the looks, then the windows.
    func step(_ key: String, _ what: String, list: [Size]? = nil, quietIfRefused: Bool = false,
              _ call: () -> (words: String, asked: Bool)) async -> StepResult {
        let start = look(id)
        if let lastEnd, lastEnd != start { say("    (between steps the display changed: \(lastEnd.words) → \(start.words))") }
        say("  step \(key): \(what); from \(start.short)")
        let t0 = Date()
        let answer = call()
        let callMs = ms(t0)
        let seen = await observe(t0, from: start, quiet: quietIfRefused && !answer.asked ? 0.6 : 1.2)
        lastEnd = seen.end
        say("    answered \(answer.words), in \(callMs) ms")
        let change: String
        if seen.end.size != start.size || !seen.end.online {
            let landed: String = seen.landedMs(at: seen.end.size).map { "\($0) ms" } ?? "?"
            change = "it went to \(seen.end.short) at \(landed)"
        } else if seen.end != start {
            change = "the same size, its mode changed"
        } else {
            change = "nothing changed"
        }
        let idWords = seen.removedOrAdded || !seen.newIDs.isEmpty
            ? "NOT the same display (removed or added; new IDs \(seen.newIDs))"
            : "the same ID \(id), never removed or added"
        say("    seen after \(ms(t0)) ms: \(seen.end.words): \(change); \(idWords)")
        if !seen.path.isEmpty { say("    on the way: " + seen.path.map { "+\($0.ms) ms \($0.look.short) (mode \($0.look.modeID))" }.joined(separator: " → ")) }
        let oursWords: String = seen.ours.isEmpty ? "none for \(id)" : seen.ours.map { "+\($0.ms) ms \($0.words)" }.joined(separator: "; ")
        let othersWords: String = seen.others.isEmpty ? "" : "; others: \(seen.others.joined(separator: "; "))"
        say("    callbacks: \(oursWords)\(othersWords)")
        if let s = nsScreen(id), !s.frame.equalTo(appKitRect(CGDisplayBounds(id))) {
            say("    AppKit's screen still reads \(rectWords(s.frame)), CoreGraphics \(rectWords(appKitRect(CGDisplayBounds(id))))")
        }
        let ws = await reportWindows()
        let r = StepResult(key: key, list: list, start: start, answered: answer.words, seen: seen, windows: ws)
        results[key] = r
        order.append(key)
        if !seen.end.online { stopEarly("the display went offline at step \(key)", code: 1) }
        return r
    }

    func apply(_ key: String, _ list: [Size], _ what: String) async -> StepResult {
        await step(key, "applySettings: with \(listWords(list)), \(what)", list: list) {
            do {
                let ok = try d.applyModes(list)
                return (ok ? "YES" : "NO", true)
            } catch {
                return ("threw \(error)", false)
            }
        }
    }

    /// Back to the room by applySettings: with it alone, when the display is not at it.
    func back(_ key: String) async {
        let l = look(id)
        if l.online, l.size != room { _ = await apply("\(key) back", [room], "back: the room alone") }
        if look(id).size == room { await restoreWindows() }
    }

    /// The windows back to their own size, centred, when macOS or a put-back changed them, so each turn starts alike.
    func restoreWindows() async {
        for pw in windows where !pw.hidden && pw.window.isVisible {
            let full = pw.window.frameRect(forContentRect: NSRect(origin: .zero, size: pw.content)).size
            guard abs(pw.window.frame.width - full.width) > 1 || abs(pw.window.frame.height - full.height) > 1 else { continue }
            if await place(pw) {
                say("    \(pw.name) window: back to its own size, \(Int(pw.window.frame.width))×\(Int(pw.window.frame.height)), centred")
            } else {
                pw.window.orderOut(nil)
                pw.hidden = true
                say("    \(pw.name) window: hidden, it would not go back inside the probe's display")
            }
        }
    }

    // MARK: Windows

    /// Centred on the display, its content size, held to the display's size (so no part of it reaches another screen).
    func targetFrame(_ pw: ProbeWindow) -> NSRect {
        let display = appKitRect(CGDisplayBounds(id))
        let frame = pw.window.frameRect(forContentRect: NSRect(origin: .zero, size: pw.content))
        let w = min(frame.width, display.width), h = min(frame.height, display.height)
        return NSRect(x: (display.midX - w / 2).rounded(), y: (display.midY - h / 2).rounded(), width: w, height: h)
    }

    func whereIs(_ pw: ProbeWindow) -> WindowSeen {
        let w = pw.window
        if pw.hidden { return WindowSeen(on: false, inside: false, resized: false, words: "\(pw.name) window: hidden since an earlier step") }
        if !w.isVisible { return WindowSeen(on: false, inside: false, resized: false, words: "\(pw.name) window: closed") }
        let f = w.frame
        let server = serverRect(w)
        let at = server.flatMap { displayAt(CGPoint(x: $0.midX, y: $0.midY)) }
        let appKitScreen = w.screen.flatMap { screenID($0) }
        let on = (at ?? appKitScreen) == id
        let inside = appKitRect(CGDisplayBounds(id)).insetBy(dx: -1, dy: -1).contains(f)
        let resized = abs(f.width - pw.placedSize.width) > 1 || abs(f.height - pw.placedSize.height) > 1
        var words = "\(pw.name) window: \(Int(f.width))×\(Int(f.height)) at \(Int(f.minX)),\(Int(f.minY)) (AppKit)"
        if let server { words += ", the window server's \(Int(server.minX)),\(Int(server.minY)) \(Int(server.width))×\(Int(server.height))" }
        if on {
            words += ": on the probe's display \(id), \(inside ? "inside it" : "PAST ITS EDGE")"
        } else {
            words += ": OFF the probe's display, on display \(at.map { String($0) } ?? appKitScreen.map { String($0) } ?? "none")"
        }
        if resized { words += ", resized from \(Int(pw.placedSize.width))×\(Int(pw.placedSize.height))" }
        return WindowSeen(on: on, inside: inside, resized: resized, words: words)
    }

    /// Sets the window's frame centered on the display, after it is ordered in, and checks it with the window server.
    func place(_ pw: ProbeWindow) async -> Bool {
        for attempt in 1...3 {
            let target = targetFrame(pw)
            if !pw.window.isVisible { pw.window.orderFrontRegardless() }
            pw.window.setFrame(target, display: true)
            try? await Task.sleep(for: .milliseconds(200))
            let seen = whereIs(pw)
            if seen.on && seen.inside {
                pw.placedSize = pw.window.frame.size
                return true
            }
            say("    \(pw.name) window, try \(attempt): asked \(rectWords(target)) (AppKit); \(seen.words)")
        }
        return false
    }

    func addWindow(_ name: String, _ content: NSSize) async {
        let display = appKitRect(CGDisplayBounds(id))
        let rect = NSRect(x: (display.midX - content.width / 2).rounded(), y: (display.midY - content.height / 2).rounded(),
                          width: content.width, height: content.height)
        let w = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Sill modes probe: \(name) window (TEST ONLY)"
        w.isReleasedWhenClosed = false
        w.tabbingMode = .disallowed   // never a tab of the other window, whatever the Mac's tab preference
        let text = NSTextField(wrappingLabelWithString: "Sill's modes probe P2b (TEST ONLY). This window and its display, Sill Probe, go away by themselves within a minute.")
        text.frame = NSRect(x: 16, y: 16, width: content.width - 32, height: content.height - 32)
        w.contentView?.addSubview(text)
        let pw = ProbeWindow(name: name, content: content, window: w)
        windows.append(pw)
        let t = Date()
        let placed = await place(pw)
        say("  the \(name) window (\(Int(content.width))×\(Int(content.height)) pt of content): \(placed ? "on the probe's display" : "NOT on the probe's display after 3 tries") after \(ms(t)) ms; \(whereIs(pw).words)")
        if !placed {
            w.orderOut(nil)
            pw.hidden = true
            say("    hidden: no window of the probe's stays on another screen")
        }
    }

    /// Where each window is now; once said, one found off the display or past its edge is put back inside it (held to
    /// its size), or hidden, so no window of the probe's stays on another screen.
    func reportWindows() async -> [WindowSeen] {
        let seen = windows.map { whereIs($0) }
        for s in seen { say("    \(s.words)") }
        for (pw, s) in zip(windows, seen) where !(s.on && s.inside) && !pw.hidden && pw.window.isVisible {
            if await place(pw) {
                say("    \(pw.name) window: put back inside the probe's display, \(Int(pw.window.frame.width))×\(Int(pw.window.frame.height))")
            } else {
                pw.window.orderOut(nil)
                pw.hidden = true
                say("    \(pw.name) window: hidden, it would not stay on the probe's display")
            }
        }
        return seen
    }

    /// Waits until AppKit's screen list has the display where CoreGraphics has it, and says what it read first.
    func waitForAppKit() async {
        let t = Date()
        var first: NSRect?
        var agreed = false
        while Date().timeIntervalSince(t) < 2 {
            if let s = nsScreen(id) {
                if first == nil { first = s.frame }
                if s.frame.equalTo(appKitRect(CGDisplayBounds(id))) { agreed = true; break }
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let cg = appKitRect(CGDisplayBounds(id))
        var firstWords = "nothing"
        if let first { firstWords = first.equalTo(cg) ? rectWords(first) : "\(rectWords(first)) (NOT where CoreGraphics has it)" }
        let agreedWords: String = agreed
            ? "where CoreGraphics has it, \(rectWords(cg)), after \(ms(t)) ms"
            : "still not where CoreGraphics has it (\(rectWords(cg))) after 2 s: the windows go by CoreGraphics' frame"
        say("  AppKit's screen for it: first read \(firstWords); \(agreedWords)")
    }

    // MARK: The steps

    func steps() async {
        _ = await step("0", "the turn \(turned), listed at creation, switched by CoreGraphics (switchMode's calls, with their codes)",
                       quietIfRefused: true) { explicitSwitch(id, to: turned) }
        if look(id).size != room {
            _ = await step("0 back", "back to \(room) by CoreGraphics", quietIfRefused: true) { explicitSwitch(id, to: room) }
            await back("0")
        }

        _ = await apply("a", [turned], "the turn alone, no switch")
        try? await Task.sleep(for: .milliseconds(300))
        listedAfterA = listedWords(id, turned)
        say("    macOS's list 300 ms later: \(hiDPIModes(id)); \(listedAfterA)")
        await back("a")

        let rb = await apply("b", [room, turned], "the room, then the turn, no switch")
        try? await Task.sleep(for: .milliseconds(300))
        fBack = rb.seen.end.size == turned ? turned : room
        fTo = fBack == turned ? room : turned
        listedBeforeF = listedWords(id, fTo) + "; " + listedWords(id, fBack)
        say("    macOS's list 300 ms later: \(hiDPIModes(id)); \(listedBeforeF)")
        let to = fTo, from = fBack
        _ = await step("f", "switch to \(to) by CoreGraphics (switchMode's calls), now that applySettings: has listed it",
                       quietIfRefused: true) { explicitSwitch(id, to: to) }
        if look(id).size != from {
            _ = await step("f back", "switch back to \(from) by CoreGraphics", quietIfRefused: true) { explicitSwitch(id, to: from) }
        }
        await back("f")

        _ = await apply("c", [turned, room], "the turn, then the room")
        await back("c")
        _ = await apply("g", [smaller, room], "90 %, then the room")
        await back("g")
        if tinyOK {
            _ = await apply("h", [room, tiny], "the room, then 60 %")
            await back("h")
        }
        if other != room {
            _ = await apply("e", otherList, otherFits ? "another shape alone, inside the backing" : "another shape, beyond the backing, after the room (as P2's step 3)")
            if !otherFits, look(id).size != other {
                // Beyond the backing and not taken beside the room: say whether it is taken alone too only when it fits.
                say("    (another shape beyond the backing is not asked alone: the list keeps a mode the display can take)")
            }
            await back("e")
        }
    }

    func finish() async {
        ending = true
        for pw in windows { pw.window.orderOut(nil); pw.window.close() }
        let t = Date()
        d.destroy()
        while onlineIDs().contains(id), Date().timeIntervalSince(t) < 3 { try? await Task.sleep(for: .milliseconds(20)) }
        say("  removed: gone from the online list after \(ms(t)) ms: \(!onlineIDs().contains(id)); displays after: \(onlineIDs())")
        printVerdicts()
    }

    // MARK: Verdicts (what was seen)

    func verdict(_ r: StepResult?, want: Size) -> String {
        guard let r else { return "not reached" }
        let e = r.seen.end
        if !e.online { return "no: the display went offline" }
        let same = !(r.seen.removedOrAdded || !r.seen.newIDs.isEmpty)
        let idw: String = same ? "same ID \(id)" : "NOT the same display (removed or added)"
        if e.size == want {
            if r.start.size == want { return "it was at \(want) already" }
            let at: String = r.seen.landedMs(at: want).map { "\($0) ms" } ?? "?"
            let retina: String = e.scale == 2 ? "" : " (NOT at 2x)"
            return "yes, \(at), \(idw), \(e.words)\(retina)"
        }
        if e.size == r.start.size {
            let calls: String = r.seen.ours.isEmpty ? " (no callback)" : " (callbacks: \(r.seen.ours.map { $0.words }.joined(separator: "; ")))"
            return "no, it stayed \(e.short)\(calls)"
        }
        let at: String = r.seen.landedMs(at: e.size).map { "\($0) ms" } ?? "?"
        return "no: it went to \(e.short) instead, \(at), \(idw)"
    }

    func ruleWords() -> String {
        let keys = ["b", "c", "g", "h"].filter { results[$0]?.list != nil }
        guard !keys.isEmpty else { return "not reached" }
        let area = { (s: Size) in s.width * s.height }
        let rules = [
            Rule(name: "the first listed") { _, l in [l[0]] },
            Rule(name: "the last listed") { _, l in [l[l.count - 1]] },
            Rule(name: "the current one kept") { s, l in l.contains(s) ? [s] : nil },
            Rule(name: "the smallest") { _, l in let m = l.map(area).min() ?? 0; return l.filter { area($0) == m } },
            Rule(name: "the largest") { _, l in let m = l.map(area).max() ?? 0; return l.filter { area($0) == m } },
        ]
        let parts = keys.compactMap { k in results[k].map { "\(k) \(listWords($0.list ?? [])) from \($0.start.short) → \($0.seen.end.short)" } }
        let held = rules.filter { rule in
            keys.allSatisfy { k in
                guard let r = results[k], let l = r.list, let p = rule.predict(r.start.size, l) else { return true }
                return p.contains(r.seen.end.size)
            }
        }.map(\.name)
        let rule: String = held.isEmpty
            ? "none of the first, the last, the current one, the smallest, the largest"
            : "consistent with \(held.joined(separator: ", "))"
        return "\(parts.joined(separator: "; ")): \(rule)"
    }

    func idWords() -> String {
        let all = order.compactMap { results[$0] }
        let bad = all.filter { $0.seen.removedOrAdded || !$0.seen.newIDs.isEmpty }
        return bad.isEmpty
            ? "the same ID \(id) through all \(all.count) steps, never removed or added"
            : "removed or added at step \(bad.map(\.key).joined(separator: ", "))"
    }

    /// The first step that turned the display from the room.
    func turnKey() -> String? {
        order.first { k in results[k].map { $0.start.size == room && $0.seen.end.size == turned } ?? false }
    }

    func windowWords(_ i: Int) -> String {
        let pw = windows[i]
        let seen: [(String, WindowSeen)] = order.compactMap { k -> (String, WindowSeen)? in
            guard let r = results[k], i < r.windows.count else { return nil }
            return (k, r.windows[i])
        }
        let off = seen.filter { !$0.1.on }.map { $0.0 }
        let past = seen.filter { $0.1.on && !$0.1.inside }.map { $0.0 }
        let resized = seen.filter { $0.1.resized }.map { $0.0 }
        var words = off.isEmpty ? "stayed on it through all \(seen.count) steps" : "OFF it after step \(off.joined(separator: ", "))"
        if !past.isEmpty { words += ", past its edge after step \(past.joined(separator: ", "))" }
        words += resized.isEmpty ? ", its size kept" : ", resized at step \(resized.joined(separator: ", "))"
        if let k = turnKey(), let r = results[k], i < r.windows.count {
            words += "; at the turn (step \(k)): \(r.windows[i].words)"
        } else {
            words += "; the display never turned"
        }
        if pw.hidden { words += "; hidden by the probe" }
        return words
    }

    func printVerdicts() {
        let r0 = results["0"]
        let r0Answer: String = r0.map { " (\($0.answered))" } ?? ""
        say("\(tag) the turn listed at creation, switched by CoreGraphics (switchMode's way): \(verdict(r0, want: turned))\(r0Answer)")
        say("\(tag) turned in place by applySettings: with the turn alone: \(verdict(results["a"], want: turned))")
        let backWords: String
        if let rb = results["a back"] {
            backWords = verdict(rb, want: room)
        } else if let ra = results["a"] {
            backWords = "not needed: the turn alone left it at \(ra.seen.end.short)"
        } else {
            backWords = "not reached"
        }
        say("\(tag) back to \(room) by applySettings: with it alone: \(backWords)")
        say("\(tag) the mode macOS takes from a new list: \(ruleWords())")
        say("\(tag) in macOS's list 300 ms after applySettings: gave it: after a, \(listedAfterA); after b, \(listedBeforeF)")
        let rf = results["f"], rfb = results["f back"]
        let fAnswer: String = rf.map { " (\($0.answered))" } ?? ""
        let fBackWords: String
        if let rfb {
            fBackWords = "\(verdict(rfb, want: fBack)) (\(rfb.answered))"
        } else {
            fBackWords = rf == nil ? "not reached" : "not needed"
        }
        say("\(tag) switched by CoreGraphics to a mode applySettings: gave: to \(fTo): \(verdict(rf, want: fTo))\(fAnswer); back to \(fBack): \(fBackWords)")
        let eWhere: String = otherFits ? "inside" : "beyond"
        let eHow: String = otherFits ? "alone" : "after \(room)"
        let eSeen: String = other == room ? "skipped" : verdict(results["e"], want: other)
        say("\(tag) another shape, \(other) (\(eWhere) the backing \(backing.wide)×\(backing.high) px), in place by applySettings: \(eHow): \(eSeen)")
        if let reb = results["e back"] { say("\(tag) back from \(other) to \(room) by applySettings: with it alone: \(verdict(reb, want: room))") }
        say("\(tag) the display through every change: \(idWords())")
        for (i, pw) in windows.enumerated() {
            say("\(tag) a window on the display, \(pw.name) (\(Int(pw.content.width))×\(Int(pw.content.height)) pt of content): \(windowWords(i))")
        }
    }
}

/// Ends the run at once: the windows closed, the display removed, the verdicts so far, and the exit.
@MainActor func stopEarly(_ why: String, code: Int32) -> Never {
    say("  STOPPED EARLY: \(why)")
    if let p = Probe.current, !p.ending {
        p.ending = true
        for pw in p.windows { pw.window.orderOut(nil); pw.window.close() }
        p.d.destroy()
        say("  the display removed; displays now: \(onlineIDs())")
        p.printVerdicts()
    }
    exit(code)
}

@MainActor
func run() async -> Int32 {
    let before = onlineIDs()
    say("  displays before: \(before); the main display \(CGMainDisplayID())")
    let t0 = Date()
    let d: VirtualDisplay
    do {
        d = try VirtualDisplay(name: "Sill Probe", widthPt: room.width, heightPt: room.height, scale: 2, refreshHz: hz,
                               vendorID: 0x5111, productID: 0x0002, serialNum: 0xF00D, otherModes: [turned])
    } catch {
        say("  FAIL make: \(error)")
        return 1
    }
    let p = Probe(d: d, before: before)
    Probe.current = p
    d.onTerminated = {
        Task { @MainActor in
            if let p = Probe.current, !p.ending { stopEarly("macOS ended the display on its own (its termination handler)", code: 1) }
        }
    }
    let up = await d.waitUntilOnline(timeout: 3)
    say("  made id \(p.id) in \(ms(t0)) ms; at \(room) @2×: \(up); \(look(p.id).words)")
    say("  macOS lists \(hiDPIModes(p.id))")
    say("    \(listedWords(p.id, room)); \(listedWords(p.id, turned))")
    let made = changes.since(t0)
    if !made.isEmpty { say("    callbacks: " + made.map { "+\(Int($0.at.timeIntervalSince(t0) * 1000)) ms \($0.id) \(flagWords($0.flags))" }.joined(separator: "; ")) }
    await p.waitForAppKit()
    p.lastEnd = look(p.id)
    await p.addWindow("small", smallContent)
    await p.addWindow("large", largeContent)
    await p.steps()
    await p.finish()
    return 0
}

// Ctrl-C and the like: the windows closed, the display removed, the verdicts so far (kqueue sees a signal even when the
// shell started this process with it ignored, as a background job).
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        Task { @MainActor () -> Void in stopEarly(sig == SIGINT ? "Ctrl-C" : "signal \(sig)", code: 130) }
    }
    source.resume()
    signalSources.append(source)
}
// The time limit: the run ends itself; if the main thread does not answer, the process ends at once (its display with it).
DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
    Task { @MainActor () -> Void in stopEarly("the time limit, \(Int(limit)) s", code: 3) }
    Thread.sleep(forTimeInterval: 1.5)
    Out.shared.say("  the main thread did not answer in 1.5 s: the probe ends at once, and its display with it")
    _exit(3)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
NSWindow.allowsAutomaticWindowTabbing = false
Task { @MainActor in
    let code = await run()
    exit(code)
}
app.run()
