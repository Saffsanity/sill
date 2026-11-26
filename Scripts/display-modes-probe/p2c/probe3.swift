// TEST ONLY. Probe P2c ("probe3"), vd-2b, 2026-11-23: what P2b (probe2) left open about turning Sill's Desktop display
// in place (VirtualDesktopSize.followWay, PR #408). A copy of ../probe2/src/probe2.swift with new steps, built with
// wt-vd-2b's Sources/SillHost/VirtualDisplay.swift copied into src/ and changed for the probe alone (NOTES.md has the
// diff: a defaulted backing parameter, and an appended extension for the rotation setting and the read-backs). run.sh
// builds it and runs it; NOTES.md says what each verdict line means.
//
// Without --make (the dry run, what an agent runs): no display is made, shown, moved or posted. It checks the private
// API's surface, lists the private classes' methods with their type encodings and their declared properties (lookups
// only), reads the type of the rotation setting from the runtime and asks one CGVirtualDisplaySettings, given to no
// display, what it keeps of a few values (its units), and prints the case, its modes, the backing and the steps. Exit 0
// when the surface is there, 1 when not, 2 for a bad argument.
//
// With --make (Noah's, from run.sh, on a Mac at rest: Sill quit, no device connected): it makes one display, "Sill
// Probe" (vendor 0x5111, product 0x0002, serial 0xF00D: Sill's Desktop identity with a serial of its own, as P2 and P2b),
// at 2x and the rate given, as P2b made it (the room both ways, so its backing is square), or, with --room-alone, with
// the room alone and the same square backing; waits until AppKit has it where CoreGraphics has it; puts two windows of
// its own on it (a small one, and a large one wider than the turn), set after they are ordered in and checked with the
// window server; then, each change looked at every 10 ms, timed, with every reconfiguration callback and its flags:
//   1. the turn in two steps: applySettings: with the turn alone (VirtualDisplay.applyModes); as soon as the display has
//      taken it and macOS lists the turned size at 2x usable for the desktop, a CoreGraphics switch to that mode
//      (VirtualDisplay.switchMode's calls, with their codes); back to the room by applySettings: with it alone;
//   2. applyModes against creation: both send `newSettings` (the list, hiDPI, the rate) and nothing more; the live
//      display's own hiDPI, rotation and physical size read back at creation and after the turn's first step;
//   3. rotation: applySettings: with the room and a quarter turn by `setRotation:`, its type read from the runtime, its
//      value passed only when the class itself says its units (or Noah gives one, --quarter-turn); then rotation 0
//      (none); skipped, with what was read, otherwise;
//   4. (--room-alone) the turn in two steps on a display made with the room alone: is listing the turn at creation what
//      leaves the turn at 1x?
// then removes the display. After each: what the display is at (bounds, pixels, scale, rate, mode, rotation), when it
// got there, the same ID or not, the callbacks, and where each window is and its size (a window found off the display is
// put back on it, or hidden). The verdict lines say what was SEEN (the display after the wait), never what a call
// answered. It never moves the pointer, posts no event, never activates (an accessory app), touches no other app's
// window, and links no VideoToolbox or ScreenCaptureKit. The display goes at the end, on every early stop, on Ctrl-C
// (SIGINT, SIGTERM, SIGHUP), and at --limit seconds (20) the process ends itself; macOS removes a process's display when
// the process exits. Exit 0 when it ran to the end, whatever macOS did; 1 when the display could not be made or was lost;
// 2 for a bad argument; 3 at the time limit; 130 when stopped.
import AppKit
import CoreGraphics
import Foundation
import ObjectiveC

setvbuf(stdout, nil, _IOLBF, 0)
let probeVersion = "probe3 r1 (vd-2b P2c, 2026-11-23)"

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
    print("probe3: \(why) (usage: probe3 [--make] [WxH] [HZ] [--room-alone] [--quarter-turn VALUE] [--label TEXT] [--log FILE] [--limit SECONDS])")
    exit(2)
}

var make = false
var logPath: String? = nil
var labelGiven: String? = nil
var roomAlone = false
var quarterGiven: Double? = nil
var limit = 20.0
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
    case "--label": labelGiven = argValue()
    case "--room-alone": roomAlone = true
    case "--quarter-turn":
        guard let v = Double(argValue()), v.isFinite, v > 0, v <= 360 else { usage("--quarter-turn takes a number above 0 and at most 360") }
        quarterGiven = v
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

// MARK: The case: its modes, its backing, its windows

let landscape = room.width >= room.height
let turned = room.turned
func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
let bothWays = VirtualDisplay.modeList(asked: room, others: [turned])
/// The square backing of the room both ways (VirtualDisplay.maxPixels), as P2b's displays had; a display made with the
/// room alone (--room-alone) gets it through the probe's `probeBackingAtLeast`.
let backing = VirtualDisplay.maxPixels(bothWays, scale: 2)
let madeWith = roomAlone ? [room] : bothWays
let caseName = labelGiven ?? "\(room) at \(Int(hz)) Hz\(roomAlone ? ", made with the room alone" : "")"
let tag = "P2c [\(caseName)]"
let smallContent = NSSize(width: 480, height: 320)
/// Larger than the turn along the room's long side, so the turn shows what macOS does with a window that no longer fits.
let largeContent = landscape
    ? NSSize(width: even(Double(room.width) * 0.8), height: even(Double(room.height) * 0.5))
    : NSSize(width: even(Double(room.width) * 0.5), height: even(Double(room.height) * 0.8))

func listWords(_ l: [Size]) -> String { "[" + l.map(\.description).joined(separator: ", ") + "]" }
func ms(_ t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
func rectWords(_ r: NSRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height))" }
func numberWords(_ v: Double) -> String { v == v.rounded() && abs(v) < 1e15 ? String(Int(v)) : String(v) }

func typeWords(_ t: Character) -> String {
    let words: [Character: String] = ["c": "char (8 bits, signed)", "C": "unsigned char (8 bits)", "s": "short (16 bits)",
                                      "S": "unsigned short (16 bits)", "i": "int (32 bits)", "I": "unsigned int (32 bits)",
                                      "l": "long (32 bits as encoded)", "L": "unsigned long (32 bits as encoded)",
                                      "q": "long long (64 bits)", "Q": "unsigned long long (64 bits)", "f": "float", "d": "double"]
    return "\(t), \(words[t] ?? "?")"
}

// MARK: Rotation's type and units (step 3), read before anything is made

/// What the runtime says of `rotation`, and the value for a quarter turn when its units are known.
struct RotationPlan {
    /// What was read, one line each.
    var read: [String] = []
    /// The one plain number type the setter, the getter and the declared property agree on; nil: not read.
    var type: Character? = nil
    /// The value for a quarter turn; nil: step 3 is skipped.
    var quarter: Double? = nil
    /// Why that value, or why none.
    var why = ""
}

/// The type from the runtime (setRotation:'s argument, rotation's return and the declared property, all one plain
/// number type, or nothing is passed); the units from the class itself: a CGVirtualDisplaySettings given to no display
/// is set to 90, 45, 1 and 0 and read back each time. Only a class that keeps some of those and refuses others says its
/// units; one that keeps them all says nothing, and then no value but 0 is passed unless Noah gives one (--quarter-turn).
func readRotationPlan() -> RotationPlan {
    var p = RotationPlan()
    let set = VirtualDisplay.probeEncoding("CGVirtualDisplaySettings", "setRotation:")
    let get = VirtualDisplay.probeEncoding("CGVirtualDisplaySettings", "rotation")
    let property = VirtualDisplay.probePropertyAttributes("CGVirtualDisplaySettings", "rotation")
    let live = VirtualDisplay.probeEncoding("CGVirtualDisplay", "rotation")
    let liveProperty = VirtualDisplay.probePropertyAttributes("CGVirtualDisplay", "rotation")
    p.read.append("CGVirtualDisplaySettings setRotation: \(set ?? "not there"), rotation \(get ?? "not there"), property \(property ?? "not declared"); CGVirtualDisplay rotation \(live ?? "not there"), property \(liveProperty ?? "not declared")")
    guard let set, set.count == 4, set.hasPrefix("v@:"), let t = set.last, VirtualDisplay.probeNumberTypes.contains(t) else {
        p.why = "setRotation: is not \"v@:\" and one plain number type, so its type is not read: nothing is passed, step 3 is skipped"
        return p
    }
    guard get == "\(t)@:" else {
        p.why = "rotation's getter (\(get ?? "none")) does not read the setter's type \(t): nothing is passed, step 3 is skipped"
        return p
    }
    if let property, !property.hasPrefix("T\(t),"), property != "T\(t)" {
        p.why = "the declared property (\(property)) is not of the setter's type \(t): nothing is passed, step 3 is skipped"
        return p
    }
    p.type = t
    let tries: [Double] = [90, 45, 1, 0]
    do {
        let rt = try VirtualDisplay.probeRotationRoundTrip(tries)
        let pairs = zip(tries, rt.after).map { "\(numberWords($0.0)) reads back \(numberWords($0.1))" }.joined(separator: ", ")
        p.read.append("one CGVirtualDisplaySettings given to no display (no display made or changed): rotation reads \(numberWords(rt.first)) at first; set to \(pairs)")
        let kept = zip(tries, rt.after).map { $0.0 == $0.1 }
        if rt.first != 0 {
            p.why = "a new settings object's rotation reads \(numberWords(rt.first)), not 0, so what none is is not read"
        } else if kept[0] && !kept[1] && !kept[2] && kept[3] {
            p.quarter = 90
            p.why = "the class keeps 90 and 0 and refuses 45 and 1: degrees, a quarter turn is 90 (read from the class itself)"
        } else if !kept[0] && kept[2] && kept[3] {
            p.quarter = 1
            p.why = "the class keeps 1 and 0 and not 90: quarter turns, a quarter turn is 1 (read from the class itself)"
        } else if kept.allSatisfy({ $0 }) {
            p.why = "the setter keeps every value as given (90, 45, 1 and 0) and checks none, so its units (degrees, quarter turns or another code) are not read"
        } else {
            p.why = "the class changes the values in a way that names no unit"
        }
    } catch {
        p.why = "the round trip on a settings object threw (\(error)), so the units are not read"
    }
    if p.quarter == nil {
        if let q = quarterGiven {
            p.quarter = q
            p.why += "; --quarter-turn \(numberWords(q)) was given (Noah's choice, not read from macOS): step 3 runs with it"
        } else {
            p.why += ": step 3 is skipped (a value of unread units is never passed)"
        }
    } else if let q = quarterGiven, q != p.quarter {
        p.why += "; --quarter-turn \(numberWords(q)) was given, but the class says otherwise: its own value is used"
    }
    return p
}

// MARK: The plan (both runs print it)

if let logPath, make {
    if !FileManager.default.fileExists(atPath: logPath) { FileManager.default.createFile(atPath: logPath, contents: nil) }
    if let f = FileHandle(forWritingAtPath: logPath) { _ = try? f.seekToEnd(); Out.shared.file = f }
}
say("Display modes probe P2c, \(probeVersion), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\(make ? "" : ": the dry run, no display made")")
let problems = VirtualDisplay.checkPrivateAPI()
if problems.isEmpty {
    say("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present (looked up only)")
} else {
    for p in problems { say("  FAIL \(p)") }
}
if !make {
    for c in ["CGVirtualDisplaySettings", "CGVirtualDisplayMode", "CGVirtualDisplayDescriptor", "CGVirtualDisplay"] {
        say("  \(c)'s methods and type encodings (looked up only): \(VirtualDisplay.probeMethods(c).joined(separator: "; "))")
        say("  \(c)'s declared properties (looked up only): \(VirtualDisplay.probeProperties(c).joined(separator: "; "))")
    }
}
let rotation = readRotationPlan()
for r in rotation.read { say("  rotation, step 3: \(r)") }
say("  rotation, step 3: \(rotation.type.map { "the type is \(typeWords($0))" } ?? "the type is not read"); \(rotation.why)")
say("  the case: \(caseName): the room \(room) pt at \(Int(hz)) Hz, on \"Sill Probe\" (vendor 0x5111, product 0x0002, serial 0xF00D, not Sill's own), 2x")
say("  made with \(listWords(madeWith)) pt\(roomAlone ? " (the room alone: the turn not listed)" : " (the room both ways, as P2b made it)"); backing \(backing.wide)×\(backing.high) px (square, the room both ways\(roomAlone ? ", given through probeBackingAtLeast" : ""))")
say("  windows of its own on it: small \(Int(smallContent.width))×\(Int(smallContent.height)) and large \(Int(largeContent.width))×\(Int(largeContent.height)) pt of content, centered, set after they are ordered in and checked with the window server")
let twoStepsWords = "applySettings: with \(listWords([turned])) alone (applyModes); as soon as the display has taken it and macOS lists \(turned) at 2× usable for the desktop, a CoreGraphics switch to that mode (switchMode's calls, with their codes); timed from the applySettings: call; back by \(listWords([room])) alone"
if roomAlone {
    say("  step 4: the turn in two steps on this display made with the room alone: \(twoStepsWords)")
} else {
    say("  step 1: the turn in two steps: \(twoStepsWords)")
    say("  step 2: applyModes against creation: both send newSettings (the list, hiDPI 1 for 2x, \(Int(hz)) Hz) and nothing more, so no corrected step; creation's one more call is waitUntilOnline's CoreGraphics select of the 2x mode, which is step 1's second step; the display's own hiDPI, rotation and physical size read back at creation and after the turn's first step")
    say("  step 3: \(rotation.quarter.map { "applySettings: with \(listWords([room])) and rotation \(numberWords($0)) (a quarter turn); then with rotation 0 (none); back by \(listWords([room])) alone if needed" } ?? "skipped: \(rotation.why)")")
}
say("  after each: what the display is at (bounds, pixels, scale, rate, mode, rotation), when, the same ID or not, the callbacks' flags, where each window is and its size")
guard make else {
    say("  dry run: no display made. Noah, from Terminal.app, with Sill quit and no device connected: zsh ~/Downloads/sill-handoff/next/vd-2b/probe3/run.sh")
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

/// What the display is at, as this process's CoreGraphics reads it: its bounds (points), its mode (points, pixels, rate,
/// ID) and its rotation (CGDisplayRotation, degrees). The scale is the mode's pixels over its points.
struct Look: Equatable {
    var online = false
    var x = 0, y = 0, w = 0, h = 0
    var pw = 0, ph = 0, mw = 0, mh = 0, hz = 0
    var modeID: Int32 = 0
    var rot = 0
    var size: Size { Size(width: w, height: h) }
    var scale: Int { mw > 0 && pw > 0 ? Int((Double(max(pw, ph)) / Double(max(mw, mh))).rounded()) : 0 }
    var modeWords: String { mw == w && mh == h ? "" : " (its mode \(mw)×\(mh) pt)" }
    var words: String {
        online ? "\(w)×\(h) pt\(modeWords), \(pw)×\(ph) px @\(scale)×, \(hz) Hz, at \(x),\(y), mode \(modeID)\(rot == 0 ? "" : ", rotated \(rot)°")" : "not online"
    }
    var short: String {
        guard online else { return "offline" }
        return (scale == 2 ? "\(w)×\(h)" : "\(w)×\(h) @\(scale)×") + (rot == 0 ? "" : " rotated \(rot)°")
    }
}

func look(_ id: CGDirectDisplayID) -> Look {
    var l = Look()
    l.online = onlineIDs().contains(id)
    guard l.online else { return l }
    let b = CGDisplayBounds(id)
    l.x = Int(b.minX); l.y = Int(b.minY); l.w = Int(b.width); l.h = Int(b.height)
    if let m = CGDisplayCopyDisplayMode(id) {
        l.pw = m.pixelWidth; l.ph = m.pixelHeight; l.mw = m.width; l.mh = m.height
        l.hz = Int(m.refreshRate.rounded()); l.modeID = m.ioDisplayModeID
    }
    l.rot = Int(CGDisplayRotation(id).rounded())
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

func modeWords(_ m: CGDisplayMode) -> String {
    "mode \(m.ioDisplayModeID), flags 0x\(String(m.ioFlags, radix: 16)), usable for the desktop: \(m.isUsableForDesktopGUI() ? "yes" : "no")"
}

/// Whether macOS lists `s` at 2x for the display, and whether it is usable for the desktop.
func listedWords(_ id: CGDirectDisplayID, _ s: Size) -> String {
    let all = allModes(id).filter { $0.width == s.width && $0.height == s.height && $0.pixelWidth == s.width * 2 }
    guard !all.isEmpty else { return "\(s) at 2× NOT listed" }
    return "\(s) at 2× listed: " + all.map { "\($0.isUsableForDesktopGUI() ? "usable" : "NOT usable") for the desktop (mode \($0.ioDisplayModeID), flags 0x\(String($0.ioFlags, radix: 16)))" }.joined(separator: " and ")
}

/// The turned size at 2x, usable for the desktop, in macOS's list: step 1's lookup.
func usableTwice(_ id: CGDirectDisplayID, _ s: Size) -> CGDisplayMode? {
    allModes(id).first { $0.width == s.width && $0.height == s.height && $0.pixelWidth == s.width * 2 && $0.isUsableForDesktopGUI() }
}

/// VirtualDisplay.selectRequestedMode's own lookup, which switchMode uses: the first mode of that size at 2x, usable or not.
func switchModesPick(_ id: CGDirectDisplayID, _ s: Size) -> CGDisplayMode? {
    allModes(id).first { $0.width == s.width && $0.height == s.height && $0.pixelWidth == s.width * 2 }
}

func cgErrorWords(_ e: CGError) -> String {
    let words: [Int32: String] = [0: "success", 1000: "failure", 1001: "illegal argument", 1002: "invalid connection",
                                  1003: "invalid context", 1004: "cannot complete", 1006: "not implemented",
                                  1007: "range check", 1008: "type check", 1010: "invalid operation", 1011: "none available"]
    return "\(e.rawValue)\(words[e.rawValue].map { " " + $0 } ?? "")"
}

/// VirtualDisplay.switchMode's calls (selectRequestedMode's CGBeginDisplayConfiguration, CGConfigureDisplayWithDisplayMode,
/// CGCompleteDisplayConfiguration for the session, complete sent whatever configure answered), with the mode given and
/// every code said.
func explicitSwitch(_ id: CGDirectDisplayID, to want: CGDisplayMode) -> (words: String, asked: Bool) {
    var config: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&config)
    guard begin == .success else { return ("begin \(cgErrorWords(begin)): nothing asked (\(modeWords(want)))", false) }
    let configure = CGConfigureDisplayWithDisplayMode(config, id, want, nil)
    let complete = CGCompleteDisplayConfiguration(config, .forSession)
    return ("configure \(cgErrorWords(configure)), complete \(cgErrorWords(complete)) (\(modeWords(want)))", configure == .success && complete == .success)
}

/// The live display's own hiDPI, rotation and physical size, as CGVirtualDisplay reads them back, each getter's type
/// encoding read from the runtime first (probeGetNumber, probeGetSize): step 2.
struct ReadBack {
    var words: String
    var hiDPI: Double?
    var rotation: Double?
    var mm: CGSize?
}

func readBack(_ d: VirtualDisplay) -> ReadBack {
    guard let o = d.probeObject else { return ReadBack(words: "the display has gone", hiDPI: nil, rotation: nil, mm: nil) }
    var r = ReadBack(words: "", hiDPI: nil, rotation: nil, mm: nil)
    var parts: [String] = []
    do { let v = try VirtualDisplay.probeGetNumber(o, "hiDPI"); r.hiDPI = v; parts.append("hiDPI \(numberWords(v))") } catch { parts.append("hiDPI not read (\(error))") }
    do { let v = try VirtualDisplay.probeGetNumber(o, "rotation"); r.rotation = v; parts.append("rotation \(numberWords(v))") } catch { parts.append("rotation not read (\(error))") }
    do {
        let v = try VirtualDisplay.probeGetSize(o, "sizeInMillimeters")
        r.mm = v
        parts.append("physical size \(Int(v.width.rounded()))×\(Int(v.height.rounded())) mm")
    } catch { parts.append("physical size not read (\(error))") }
    r.words = parts.joined(separator: ", ")
    return r
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
    /// When the display reached what it ended at (the last change on the way), if it changed.
    var landedMs: Int? { path.last.flatMap { $0.look == end ? $0.ms : nil } }
}

struct WindowSeen {
    var on: Bool
    var inside: Bool
    var resized: Bool
    var words: String
}

/// Step 1's (and 4's) two steps, as they went.
struct TwoStepInfo {
    var applied: String
    var applyMs: Int
    var first: (ms: Int, look: Look)?
    var listed: String
    var switchMs: Int?
    var switchWords: String
    var pickWords: String
}

struct StepResult {
    var key: String
    var start: Look
    var answered: String
    var seen: Seen
    var windows: [WindowSeen]
    var two: TwoStepInfo?
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
    var listedAtMake = "not read"
    var madeRead: ReadBack?
    var turnRead: ReadBack?
    var rotatedRead: ReadBack?

    init(d: VirtualDisplay, before: [CGDirectDisplayID]) { self.d = d; self.id = d.displayID; self.before = before }

    // MARK: Looking

    /// Looks every 10 ms from `t0` until the display has been quiet `settle` after its last change or callback (and at
    /// least `atLeast` has passed), or `quiet` with nothing at all, or `cap`. Selects nothing: what macOS does alone.
    func observe(_ t0: Date, from start: Look, quiet: Double, settle: Double = 0.4, cap: Double = 3, atLeast: Double = 0.5) async -> Seen {
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
                if now >= max(activity + settle, atLeast) { break }
            } else if now >= max(quiet, atLeast) {
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
    func step(_ key: String, _ what: String, quietIfRefused: Bool = false,
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
        return await report(key, start: start, t0: t0, answered: answer.words, seen: seen, two: nil)
    }

    /// What a step saw, said; the windows looked at (and put back); the result kept.
    func report(_ key: String, start: Look, t0: Date, answered: String, seen: Seen, two: TwoStepInfo?) async -> StepResult {
        let change: String
        if !seen.end.online {
            change = "it went offline"
        } else if seen.end.size != start.size || seen.end.scale != start.scale || seen.end.rot != start.rot {
            change = "it went to \(seen.end.short) at \(seen.landedMs.map { "\($0) ms" } ?? "?")"
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
        let r = StepResult(key: key, start: start, answered: answered, seen: seen, windows: ws, two: two)
        results[key] = r
        order.append(key)
        if !seen.end.online { stopEarly("the display went offline at step \(key)", code: 1) }
        return r
    }

    func apply(_ key: String, _ list: [Size], _ what: String) async -> StepResult {
        await step(key, "applySettings: with \(listWords(list)), \(what)") {
            do {
                let ok = try d.applyModes(list)
                return (ok ? "YES" : "NO", true)
            } catch {
                return ("threw \(error)", false)
            }
        }
    }

    func rotate(_ key: String, _ value: Double, _ what: String) async -> StepResult {
        await step(key, "applySettings: with \(listWords([room])) and rotation \(numberWords(value)), \(what)") {
            do {
                let ok = try d.probeApplyModes([room], rotation: value)
                return (ok ? "YES" : "NO", true)
            } catch {
                return ("threw \(error)", false)
            }
        }
    }

    /// Steps 1 and 4: applySettings: with the turn alone; then, once the display has taken it (at whatever scale) and
    /// macOS lists the turned size at 2x usable for the desktop, a CoreGraphics switch to that mode (switchMode's calls).
    /// Timed from the applySettings: call.
    func twoSteps(_ key: String) async -> StepResult {
        let start = look(id)
        if let lastEnd, lastEnd != start { say("    (between steps the display changed: \(lastEnd.words) → \(start.words))") }
        say("  step \(key): the turn in two steps: applySettings: with \(listWords([turned])) alone, then a CoreGraphics switch to \(turned) at 2× once macOS lists it usable; from \(start.short)")
        let t0 = Date()
        var applied: String
        do { applied = try d.applyModes([turned]) ? "YES" : "NO" } catch { applied = "threw \(error)" }
        var info = TwoStepInfo(applied: applied, applyMs: ms(t0), first: nil, listed: "not looked at: applySettings: did not answer YES",
                               switchMs: nil, switchWords: "not asked", pickWords: "")
        var path: [(ms: Int, look: Look)] = []
        var last = start
        if applied == "YES" {
            info.listed = "the display did not change within 2.5 s: no switch asked"
            while Date().timeIntervalSince(t0) < 2.5 {
                try? await Task.sleep(for: .milliseconds(10))
                let now = ms(t0)
                let l = look(id)
                if l != last { path.append((ms: now, look: l)); last = l }
                if !l.online { info.listed = "the display went offline"; break }
                if info.first == nil, l != start {
                    info.first = (ms: now, look: l)
                    turnRead = readBack(d)
                }
                guard let first = info.first else { continue }
                if l.size == turned && l.scale == 2 && l.rot == 0 {
                    info.listed = "no switch needed: the display took \(turned) at 2× by itself"
                    break
                }
                if let m = usableTwice(id, turned) {
                    info.listed = "\(turned) at 2× listed usable for the desktop at +\(now) ms (\(modeWords(m)))"
                    if let pick = switchModesPick(id, turned) {
                        info.pickWords = pick.ioDisplayModeID == m.ioDisplayModeID
                            ? "switchMode's own lookup (the first \(turned) at 2×) picks the same mode"
                            : "switchMode's own lookup (the first \(turned) at 2×) picks \(modeWords(pick)), NOT the usable one"
                    }
                    info.switchMs = now
                    let callStart = Date()
                    let switched = explicitSwitch(id, to: m)
                    info.switchWords = "\(switched.words), the call took \(ms(callStart)) ms"
                    break
                }
                if now - first.ms > 1000 {
                    info.listed = "\(turned) at 2× not listed usable within 1 s of the display taking the turn (\(listedWords(id, turned))): no switch asked"
                    break
                }
            }
            if let first = info.first, info.switchMs == nil, info.listed.hasPrefix("the display did not change") {
                info.listed = "the display changed at +\(first.ms) ms, but \(turned) at 2× was not listed usable by 2.5 s (\(listedWords(id, turned))): no switch asked"
            }
        }
        let after = Double(info.switchMs ?? 0) / 1000
        var seen = await observe(t0, from: last, quiet: max(1.2, after + 1.2), cap: max(3, after + 3),
                                 atLeast: info.switchMs == nil ? 0.5 : after + 0.9)
        seen.path = path + seen.path
        lastEnd = seen.end
        say("    applySettings: answered \(applied), in \(info.applyMs) ms; the display first changed \(info.first.map { "at +\($0.ms) ms, to \($0.look.short)" } ?? "never")")
        if info.first != nil, let r = turnRead { say("    the display reads back then: \(r.words)") }
        say("    \(info.listed)\(info.pickWords.isEmpty ? "" : "; \(info.pickWords)")")
        if let s = info.switchMs { say("    the switch, asked at +\(s) ms: \(info.switchWords)") }
        let answered = "applySettings: \(applied); \(info.listed); the switch: \(info.switchWords)"
        let r = await report(key, start: start, t0: t0, answered: answered, seen: seen, two: info)
        say("    macOS lists now: \(hiDPIModes(id)); \(listedWords(id, turned)); \(listedWords(id, room))")
        return r
    }

    /// Back to the room, unturned and at 2x, when the display is not: rotation 0 first if it reads turned and the
    /// rotation's type is read, then applySettings: with the room alone.
    func back(_ key: String) async {
        var l = look(id)
        if l.online, l.rot != 0, rotation.type != nil {
            _ = await rotate("\(key) unturn", 0, "back: rotation none")
            l = look(id)
        }
        if l.online, l.size != room || l.scale != 2 || l.rot != 0 {
            _ = await apply("\(key) back", [room], "back: the room alone")
        }
        let now = look(id)
        if now.size == room && now.scale == 2 { await restoreWindows() }
    }

    /// The windows back to their own size, centred, when macOS or a put-back changed them, so each step starts alike.
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
        let text = NSTextField(wrappingLabelWithString: "Sill's modes probe P2c (TEST ONLY). This window and its display, Sill Probe, go away by themselves within a minute.")
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
        _ = await twoSteps("1")
        await back("1")
        // Step 2 changes nothing on the display: applyModes sends what init sends (its verdict reads the read-backs).
        if let q = rotation.quarter {
            _ = await rotate("3", q, "a quarter turn")
            let r = readBack(d)
            rotatedRead = r
            say("    the display reads back: \(r.words)")
            _ = await rotate("3 none", 0, "rotation none")
            await back("3")
        } else {
            say("  step 3: skipped: \(rotation.why)")
        }
    }

    func stepsRoomAlone() async {
        _ = await twoSteps("4")
        await back("4")
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

    func idw(_ r: StepResult) -> String {
        r.seen.removedOrAdded || !r.seen.newIDs.isEmpty ? "NOT the same display (removed or added)" : "same ID \(id)"
    }

    func callbackWords(_ r: StepResult) -> String {
        r.seen.ours.isEmpty ? " (no callback)" : " (callbacks: \(r.seen.ours.map { $0.words }.joined(separator: "; ")))"
    }

    /// At `want`, unturned, at 2x, after the step?
    func verdict(_ r: StepResult?, want: Size) -> String {
        guard let r else { return "not reached" }
        let e = r.seen.end
        if !e.online { return "no: the display went offline" }
        if e.size == want && e.scale == 2 && e.rot == 0 {
            if r.start == e { return "it was there already (\(e.words))" }
            return "yes, \(r.seen.landedMs.map { "\($0) ms" } ?? "?"), \(idw(r)), \(e.words)"
        }
        if e == r.start { return "no, nothing changed (\(e.short))\(callbackWords(r))" }
        return "no: it went to \(e.words) instead, \(r.seen.landedMs.map { "\($0) ms" } ?? "?"), \(idw(r))"
    }

    func twoVerdict(_ r: StepResult?) -> String {
        guard let r, let two = r.two else { return "not reached" }
        let e = r.seen.end
        if !e.online { return "no: the display went offline" }
        let firstWords = two.first.map { "the first step took it to \($0.look.short) at +\($0.ms) ms" } ?? "the first step changed nothing"
        let how = two.switchMs.map { "the switch asked at +\($0) ms: \(two.switchWords)" } ?? "no switch asked: \(two.listed)"
        let pick = two.pickWords.isEmpty ? "" : "; \(two.pickWords)"
        let details = "applySettings: answered \(two.applied) in \(two.applyMs) ms; \(firstWords); \(how)\(pick)"
        if e.size == turned && e.scale == 2 && e.rot == 0 {
            let at = r.seen.path.first { $0.look.size == turned && $0.look.scale == 2 }?.ms
            let alone = two.switchMs == nil ? " by applySettings: alone, no switch needed" : ""
            return "yes\(alone), \(at.map { "\($0) ms" } ?? "?") in all, \(idw(r)), \(e.words) (\(details))"
        }
        return "no: it is at \(e.short), \(idw(r)) (\(details))"
    }

    func backVerdict(_ key: String) -> String {
        if let r = results["\(key) back"] { return verdict(r, want: room) }
        guard let r = results[key] else { return "not reached" }
        return "not needed: the step left it at \(r.seen.end.short)"
    }

    func item2Words() -> String {
        let made = madeRead?.words ?? "not read"
        let turn = turnRead?.words ?? "not read (the turn's first step changed nothing)"
        var words = "applyModes and init send the same settings (newSettings: the list, hiDPI 1 for 2x, \(Int(hz)) Hz; neither sets anything else), so no corrected step; the display read back at creation \(made); after the turn's first step \(turn)"
        if let a = madeRead?.hiDPI, let b = turnRead?.hiDPI { words += a == b ? " (hiDPI the same)" : " (hiDPI CHANGED)" }
        if let mm = madeRead?.mm, mm.width > 0 {
            let inch = Double(mm.width) / 25.4
            words += "; across its \(Int(mm.width.rounded())) mm the turn's \(turned.width * 2) px are \(Int((Double(turned.width * 2) / inch).rounded())) px an inch, the room's \(room.width * 2) px \(Int((Double(room.width * 2) / inch).rounded()))"
        }
        words += "; creation's one more call is the CoreGraphics select of the 2x mode, step 1's second step"
        return words
    }

    func rotationVerdict() -> String {
        guard rotation.quarter != nil else { return "skipped: \(rotation.why)" }
        guard let r = results["3"] else { return "not reached" }
        let e = r.seen.end
        if !e.online { return "no: the display went offline" }
        let read = rotatedRead.map { "; the display reads back \($0.words)" } ?? ""
        let what = "\(e.w)×\(e.h) pt\(e.modeWords) @\(e.scale)×, CGDisplayRotation \(e.rot)°, its origin at \(e.x),\(e.y), mode \(e.modeID), \(idw(r))\(r.seen.landedMs.map { ", at \($0) ms" } ?? "")\(read); applySettings: answered \(r.answered)\(callbackWords(r))"
        if e.size == turned && e.scale == 2 && (e.rot == 90 || e.rot == 270) { return "yes: \(what)" }
        if e == r.start { return "no, nothing changed: \(what)" }
        return "no: \(what)"
    }

    func idWords() -> String {
        let all = order.compactMap { results[$0] }
        let bad = all.filter { $0.seen.removedOrAdded || !$0.seen.newIDs.isEmpty }
        return bad.isEmpty
            ? "the same ID \(id) through all \(all.count) steps, never removed or added"
            : "removed or added at step \(bad.map(\.key).joined(separator: ", "))"
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
        let turnedKeys = order.filter { k in results[k].map { $0.seen.end.online && $0.seen.end.size == turned } ?? false }
        if turnedKeys.isEmpty { words += "; the display never took the turn's shape" }
        for k in turnedKeys {
            if let r = results[k], i < r.windows.count { words += "; at the turn's shape (step \(k)): \(r.windows[i].words)" }
        }
        if pw.hidden { words += "; hidden by the probe" }
        return words
    }

    func printVerdicts() {
        if roomAlone {
            say("\(tag) at creation, on a display made with the room alone (backing \(backing.wide)×\(backing.high) px): \(listedAtMake)")
            say("\(tag) the turn finished in place on it (applySettings: with the turn alone, then a CoreGraphics switch to the usable 2x mode): \(twoVerdict(results["4"]))")
            say("\(tag) back to \(room) by applySettings: with it alone: \(backVerdict("4"))")
        } else {
            say("\(tag) the turn finished in place (applySettings: with the turn alone, then a CoreGraphics switch to the usable 2x mode): \(twoVerdict(results["1"]))")
            say("\(tag) back to \(room) by applySettings: with it alone: \(backVerdict("1"))")
            say("\(tag) applyModes against creation: \(item2Words())")
            say("\(tag) rotation's type, read from the runtime: \(rotation.type.map { typeWords($0) } ?? "not read") (\(rotation.read.first ?? "nothing read")); its units: \(rotation.why)")
            say("\(tag) the room turned a quarter by rotation (applySettings: with \(listWords([room])) and rotation \(rotation.quarter.map { numberWords($0) } ?? "-")): \(rotationVerdict())")
            let noneWords: String = rotation.quarter == nil ? "skipped" : verdict(results["3 none"], want: room)
            say("\(tag) rotation back to none (rotation 0): \(noneWords)")
        }
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
                               vendorID: 0x5111, productID: 0x0002, serialNum: 0xF00D, otherModes: roomAlone ? [] : [turned],
                               probeBackingAtLeast: roomAlone ? backing : nil)
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
    p.listedAtMake = "\(listedWords(p.id, room)); \(listedWords(p.id, turned))"
    say("    \(p.listedAtMake)")
    let made = changes.since(t0)
    if !made.isEmpty { say("    callbacks: " + made.map { "+\(Int($0.at.timeIntervalSince(t0) * 1000)) ms \($0.id) \(flagWords($0.flags))" }.joined(separator: "; ")) }
    let r = readBack(d)
    p.madeRead = r
    say("  the display reads back: \(r.words)")
    await p.waitForAppKit()
    p.lastEnd = look(p.id)
    await p.addWindow("small", smallContent)
    await p.addWindow("large", largeContent)
    if roomAlone { await p.stepsRoomAlone() } else { await p.steps() }
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
