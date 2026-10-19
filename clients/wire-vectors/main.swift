// The wire's vectors for the clients that are not Swift (clients/, docs/clients-plan.md): compiled
// with the real Sources/StreamProtocol (generate.sh), so every JSON payload here is the Mac's own
// types' encoding, every binary layout the Mac's own code's, and every rule (versions, SafeText,
// the address parser) the Mac's own answer. Foundation only: it runs on macOS and on Linux.
//
//   main generate OUT.json               write the vectors
//   main decode VECTORS.json IN.json     decode what another implementation wrote (IN: an array of
//                                        {"name", "type", "json"}) with the Mac's types, re-encode it
//                                        sorted and compare with the vector of that name; exit 1 on
//                                        any difference
import Foundation

func sortedJSON<T: Encodable>(_ v: T) -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return String(decoding: try! e.encode(v), as: UTF8.self)
}

func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

// MARK: - Types: each payload a client reads or writes, by name

/// Decodes `json` as the named type and returns it re-encoded with sorted keys; nil when it does not
/// decode (a missing required key, a wrong type, an unknown enum case).
let decoders: [String: (Data) -> String?] = {
    func d<T: Codable>(_ t: T.Type) -> (Data) -> String? {
        { data in (try? JSONDecoder().decode(T.self, from: data)).map { sortedJSON($0) } }
    }
    return [
        "StreamSource": d(StreamSource.self), "WindowList": d(WindowList.self), "AppList": d([AppInfo].self),
        "LaunchApp": d(LaunchApp.self), "WindowCommand": d(WindowCommand.self), "InputEvent": d(InputEvent.self),
        "Viewport": d(Viewport.self), "ClientStats": d(ClientStats.self),
        "HostSettingsState": d(HostSettingsState.self), "HostSettingsChange": d(HostSettingsChange.self),
        "MacMenu": d(MacMenu.self), "FetchMenu": d(FetchMenu.self), "PressMenuItem": d(PressMenuItem.self),
        "MacPointer": d(MacPointer.self), "TrackpadGesture": d(TrackpadGesture.self), "Clipboard": d(Clipboard.self),
        "Hello": d(Hello.self), "Goodbye": d(Goodbye.self), "PairRequest": d(PairRequest.self),
        "PairResult": d(PairResult.self), "MacInfo": d(MacInfo.self), "SignedMacInfo": d(SignedMacInfo.self),
    ]
}()

struct Vector { let name: String; let type: String; let kind: Int; let json: String; let sorted: String }
var vectors: [Vector] = []
func add<T: Codable>(_ name: String, _ type: String, _ kind: StreamMessageKind, _ value: T) {
    precondition(decoders[type] != nil, "no decoder for \(type)")
    vectors.append(Vector(name: name, type: type, kind: Int(kind.rawValue),
                          json: String(decoding: Wire.encode(value), as: UTF8.self), sorted: sortedJSON(value)))
}

let window = WindowInfo(id: 4242, title: "Notes — Shopping “list”", appName: "Notes", bundleID: "com.apple.Notes", width: 1200, height: 800)
add("windowList.full", "WindowList", .windowList, WindowList(
    macName: "Noah's Mac mini", windows: [window, WindowInfo(id: 7, title: "", appName: "Terminal", bundleID: "com.apple.Terminal", width: 640, height: 480)],
    active: .window(4242), launchID: "5D1C2B6A-0F3E-4C55-9A61-2C1D7E8F9A0B", hostVersion: "0.5.1", protocol: 1, gestures: 1, clipboard: 1))
add("windowList.minimal", "WindowList", .windowList, WindowList(macName: "Mac", windows: [], active: .none))
add("windowList.desktop", "WindowList", .windowList, WindowList(macName: "Mac", windows: [window], active: .desktop, protocol: 1))
add("source.none", "StreamSource", .selectSource, StreamSource.none)
add("source.desktop", "StreamSource", .selectSource, StreamSource.desktop)
add("source.window", "StreamSource", .selectSource, StreamSource.window(4294967295))
add("appList", "AppList", .appList, [AppInfo(name: "Safari", bundleID: "com.apple.Safari"), AppInfo(name: "Zed", bundleID: "dev.zed.Zed")])
add("launchApp", "LaunchApp", .launchApp, LaunchApp(bundleID: "com.apple.Safari"))
for a in [WindowCommand.Action.close, .minimize, .fullScreen] {
    add("windowCommand.\(a.rawValue)", "WindowCommand", .windowCommand, WindowCommand(id: 4242, action: a))
}
for a in [PointerAction.move, .leftDown, .leftUp, .rightDown, .rightUp] {
    add("input.pointer.\(a.rawValue)", "InputEvent", .input, InputEvent.pointer(a, x: 0.25, y: 0.75))
}
add("input.scroll", "InputEvent", .input, InputEvent.scroll(x: 0.5, y: 0.5, dx: -0.0125, dy: 0.03))
for p in [ScrollPhase.began, .ended, .momentumBegan, .momentumEnded] {
    add("input.scrollGesture.\(p.rawValue)", "InputEvent", .input, InputEvent.scrollGesture(p, x: 0.1, y: 0.9))
}
add("input.text", "InputEvent", .input, InputEvent.text("héllo \"quoted\"\n\t\u{8}✓😀"))
add("input.key", "InputEvent", .input, InputEvent.key(hidUsage: 44, down: true, modifiers: 1 << 20))
add("input.key.up", "InputEvent", .input, InputEvent.key(hidUsage: 4, down: false, modifiers: (1 << 17) | (1 << 18) | (1 << 19)))
add("viewport.scale", "Viewport", .viewport, Viewport(width: 1180.5, height: 820, scale: 1.25, localCursor: true, fps: 120))
add("viewport.noScale", "Viewport", .viewport, Viewport(width: 800, height: 600, scale: nil, fps: 60))
add("clientStats", "ClientStats", .clientStats, ClientStats(fps: 59, frameAgeMs: 9, rttMs: 7, device: "Windows (DESKTOP-1)", frameAgeMaxMs: 24, rttMaxMs: -1))
add("clientStats.old", "ClientStats", .clientStats, ClientStats(fps: 0, frameAgeMs: -1, rttMs: -1, device: "Pixel 9"))
let settings = StreamSettings(maxFPS: 120, bitrate: 40_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: true, directWireless: false)
add("hostSettings.full", "HostSettingsState", .hostSettings, HostSettingsState(
    settings: settings, persistent: true, virtualDisplayAvailable: true, virtualDisplayNote: "Needs Screen Recording",
    softwareEncoder: false, stream: RunningStream(width: 3024, height: 1964, fps: 60, mbps: 40, onVirtualDisplay: false), answering: 3,
    away: AwayQuality(homeBitrate: 40_000_000, homeCaptureScale: 2, awayBitrate: 4_000_000, awayCaptureScale: 1, thisConnectionAway: true, awayRunning: true),
    link: LinkReport(state: "behind", withheldPerSecond: 52, bitrate: 40_000_000, carriedKbps: 6400, suggestedBitrate: 4_000_000, suggestedCaptureScale: 1)))
add("hostSettings.minimal", "HostSettingsState", .hostSettings, HostSettingsState(
    settings: StreamSettings(maxFPS: 60, bitrate: 15_000_000, captureScale: 1, prioritizeSpeed: true, virtualDisplay: false, directWireless: nil),
    persistent: false, virtualDisplayAvailable: false, softwareEncoder: true))
add("changeSettings", "HostSettingsChange", .changeSettings, HostSettingsChange(token: 7, bitrate: 25_000_000))
add("changeSettings.all", "HostSettingsChange", .changeSettings, HostSettingsChange(token: 8, maxFPS: 60, bitrate: 8_000_000, captureScale: 1, prioritizeSpeed: true, virtualDisplay: false, directWireless: true))
add("macMenu.top", "MacMenu", .macMenu, MacMenu(version: 3, app: "TextEdit", bundleID: "com.apple.TextEdit",
    menus: [MacMenuItem(id: "1", title: "File", submenu: true), MacMenuItem(id: "2", title: "Edit", submenu: true)]))
add("macMenu.items", "MacMenu", .macMenu, MacMenu(version: 3, answering: 9, menu: "1", items: [
    MacMenuItem(id: "1.0", title: "New", enabled: true, key: "⌘N"), MacMenuItem(separator: true),
    MacMenuItem(id: "1.2", title: "Wrap", enabled: false, mark: "✓")], more: 2))
add("macMenu.stale", "MacMenu", .macMenu, MacMenu(version: 4, answering: 10, pressed: false, stale: true, note: "The menus changed. Open them again."))
add("fetchMenu", "FetchMenu", .fetchMenu, FetchMenu(version: 3, id: "1", title: "File", token: 9))
add("fetchMenu.subscribe", "FetchMenu", .fetchMenu, FetchMenu())
add("pressMenuItem", "PressMenuItem", .pressMenuItem, PressMenuItem(version: 3, id: "1.0", title: "New", token: 10))
add("macPointer.inside", "MacPointer", .macPointer, MacPointer(x: 0.4213, y: 0.1873, inside: true, seen: 12))
add("macPointer.outside", "MacPointer", .macPointer, MacPointer(inside: false, seen: 12))
add("gesture", "TrackpadGesture", .gesture, TrackpadGesture(gesture: TrackpadGesture.swipeUp, fingers: 3))
add("clipboard.subscribe", "Clipboard", .clipboard, Clipboard())
add("clipboard.text", "Clipboard", .clipboard, Clipboard(text: "copied ✂︎\nline two"))
add("clipboard.stop", "Clipboard", .clipboard, Clipboard(stop: true))
add("hello", "Hello", .hello, Hello(appVersion: "0.6.0", build: "7", protocol: 1, device: "Android (Pixel 9)"))
add("hello.empty", "Hello", .hello, Hello())
add("goodbye.quit", "Goodbye", .goodbye, Goodbye(reason: Goodbye.quit))
add("goodbye.update", "Goodbye", .goodbye, Goodbye(reason: Goodbye.update, message: "Update Sill on your Pixel to keep using Mac. It needs version 1.2 or later.", minimumVersion: "1.2", reconnect: false))
add("pairRequest.code", "PairRequest", .pairRequest, PairRequest(method: PairRequest.code, proof: "dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8", name: "Pixel", model: "Pixel 9"))
add("pairRequest.ask", "PairRequest", .pairRequest, PairRequest(method: PairRequest.ask, proof: "", name: "DESKTOP-1", model: nil, cable: false))
add("pairResult.ok", "PairResult", .pairResult, PairResult(ok: true, proof: "XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE", macID: "A3C5HR4RBV67YR21", name: "Mac", recognitionKey: "ERERERERERERERERERERERERERERERERERERERERERE"))
add("pairResult.code", "PairResult", .pairResult, PairResult(ok: false, reason: PairResult.code, triesLeft: 4))
add("pairResult.busy", "PairResult", .pairResult, PairResult(ok: false, reason: PairResult.busy, retryAfter: 2.5))
add("pairResult.cable", "PairResult", .pairResult, PairResult(ok: true, macID: "A3C5HR4RBV67YR21", name: "Mac", recognitionKey: "ERERERERERERERERERERERERERERERERERERERERERE", method: PairResult.cable))
add("pairResult.message", "PairResult", .pairResult, PairResult(ok: false, reason: "later", message: "Something new"))
let info = MacInfo(macID: "A3C5HR4RBV67YR21", name: "Mac mini", issuedAt: 1_790_000_000.25, remoteAccess: true, remotePort: 7455, internet: false,
                   addresses: [MacAddress(host: "mac-mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale"),
                               MacAddress(host: "fd7a:115c:a1e0::1234", port: 17455, kind: MacAddress.internet, via: "Router")])
add("macInfo", "MacInfo", .macInfo, info)
add("signedMacInfo", "SignedMacInfo", .macInfo, SignedMacInfo(info: Wire.encode(info).base64EncodedString(), key: "BA==", sig: "MAA="))

// MARK: - Binary layouts

var binary: [[String: Any]] = []
func header(_ name: String, _ kind: StreamMessageKind, _ ts: Double, _ key: Bool, _ payload: Data) {
    let m = StreamMessage(kind: kind, timestamp: ts, isKeyframe: key, payload: payload)
    binary.append(["name": name, "what": "message", "kind": Int(kind.rawValue), "timestamp": ts, "keyframe": key,
                   "payload": hex(payload), "hex": hex(m.serialized())])
}
header("message.ping", .ping, 0, false, Data([0x41, 0xD9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
header("message.frame.key", .frame, 1_790_000_000.123456, true, Data([0, 0, 0, 3, 0x26, 0x01, 0xAF]))
header("message.tick", .tick, 1_790_000_001.5, false, Data())
header("message.hello", .hello, 0, false, Wire.encode(Hello(appVersion: "0.6.0", build: "7", protocol: 1, device: "Pixel")))
let sets = ParameterSets(nalUnitHeaderLength: 4, sets: [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x01, 0x01]), Data([0x44, 0x01, 0xC1])])
binary.append(["name": "parameterSets", "what": "parameterSets", "nalLength": 4,
               "sets": sets.sets.map(hex), "hex": hex(sets.encoded())])
binary.append(["name": "thumbnail", "what": "thumbnail", "windowID": 4242, "image": "ffd8ffe0",
               "hex": hex(ImageBlob.encodeThumbnail(windowID: 4242, jpeg: Data([0xFF, 0xD8, 0xFF, 0xE0])))])
binary.append(["name": "appIcon", "what": "appIcon", "bundleID": "com.apple.Notes", "image": "89504e47",
               "hex": hex(ImageBlob.encodeIcon(bundleID: "com.apple.Notes", png: Data([0x89, 0x50, 0x4E, 0x47])))])
binary.append(["name": "cursorShape", "what": "cursorShape", "hotX": 4.5, "hotY": 2, "width": 16, "height": 24.25, "image": "89504e47",
               "hex": hex(CursorShapeBlob.encode(hotspot: CGPoint(x: 4.5, y: 2), size: CGSize(width: 16, height: 24.25), png: Data([0x89, 0x50, 0x4E, 0x47])))])
var kinds: [[String: Any]] = []
for k in 0...255 { if let kind = StreamMessageKind(rawValue: UInt8(k)), kind != .unknown { kinds.append(["kind": k, "name": "\(kind)"]) } }

// MARK: - Rules

let versionInputs = ["v0.4.0", "0.4.0", "0.4", "V1", "1.2.3-beta.1", "0.3.0 (85)", "  0.10 ", "0.9", "1.0.1", "1.0", "",
                     "v", "beta", ".1", "1..2", "1.2.", "1.2.3.4.5.6.7.8", "1.2.3.4.5.6.7.8.9", "1234567890", "123456789",
                     "١.٢", "0", "0.0.0", "10.0", "1.00"]
var versions: [[String: Any]] = []
for i in versionInputs {
    var row: [String: Any] = ["input": i]
    if let v = SillVersion(i) { row["shown"] = v.description; row["components"] = v.components } else { row["shown"] = NSNull() }
    versions.append(row)
}
var order: [[Any]] = []
let parsed = versionInputs.compactMap { s in SillVersion(s).map { (s, $0) } }
for (a, va) in parsed { for (b, vb) in parsed { order.append([a, b, va < vb ? -1 : (va == vb ? 0 : 1)]) } }

/// SafeText's class of every scalar, as runs: 0 kept, 1 whitespace (one space), 2 removed.
func scalarClass(_ s: Unicode.Scalar) -> Int {
    let label = SafeText.label("a" + String(Character(s)) + "b", limit: 1000)
    if label == "ab" { return 2 }
    if label == "a b" { return 1 }
    return 0
}
var runs: [[Int]] = []
var v: UInt32 = 0
while v <= 0x10FFFF {
    if let s = Unicode.Scalar(v) {
        let c = scalarClass(s)
        if let last = runs.last, last[2] == c, last[1] == Int(v) - 1 { runs[runs.count - 1][1] = Int(v) } else { runs.append([Int(v), Int(v), c]) }
    }
    v += 1
}
let labelInputs: [(String, Int)] = [("iPad (iPad14,1)", 64), ("iPad\n\tPro", 64), ("  iPad \u{00A0}\u{3000}  mini  ", 64),
    ("i\u{0007}P\u{001B}[31ma\u{0085}d\u{009B}", 64), ("iPad\u{202E}dáPi", 64), (String(repeating: "é", count: 70), 64),
    (String(repeating: "👩‍👩‍👧", count: 70), 64), ("e\u{0301}" + String(repeating: "x", count: 70), 10), ("ab cd ef", 5),
    ("\u{202E}\u{0000}\n ", 64), ("Pixel 9 Pro XL", 64), ("Ünïcödé — “quotes”", 300)]
let labels = labelInputs.map { ["input": $0.0, "limit": $0.1, "output": SafeText.label($0.0, limit: $0.1)] as [String: Any] }

/// The protocol check's address cases (Tests/checks/protocol/main.swift), and a few more.
let addressInputs: [String] = [
    " 100.1.1.1 ",
    "\t100.101.102.103\n",
    "100.1 .1.1",
    "mac mini.local",
    "mac\tmini",
    "",
    "   ",
    "[fd7a:115c:a1e0::1234]",
    "[fd7a:115c:a1e0::1234]:7455",
    "[FD7A:115C:A1E0:0:0:0:0:1234]:17455",
    "[::1]:51234",
    "[1.2.3.4]",
    "[::1",
    "[::1]x",
    "[::1]:",
    "[::1]:99999",
    "fd7a::1:7455",
    "::1",
    "2001:db8::20",
    "2001:db8:::20",
    "gg::1",
    "fe80::1%en0",
    "[fe80::1%en0]:7455",
    "fe80::1%25en0",
    "::ffff:1.2.3.4",
    "[::ffff:100.101.102.103]:7455",
    "::ffff:0102:0304",
    "100.101.102.103",
    "100.101.102.103:7455",
    "0.0.0.0",
    "255.255.255.255",
    "1.2.3",
    "100.1",
    "0x64.0x65.1.2",
    "0x7f000001",
    "4294967295",
    "256.1.1.1",
    "01.2.3.4",
    "017.0.0.1",
    "1.2.3.4.5",
    "1.2.3.4.",
    "1.2.3.4:0",
    "mac-mini.tail1234.ts.net",
    "home.example.net:17455",
    "localhost",
    "mac-mini",
    "home.example.net.",
    "1e100.net",
    "123.example",
    "-bad.example",
    "bad-.example",
    "a..b",
    "under_score.example",
    "exämple.com",
    "host:1",
    "host:65535",
    "host:0",
    "host:65536",
    "host:+80",
    "host:80a",
    "host:",
    ":7455",
    "http://1.2.3.4",
    "sill://pair?v=1",
    "SILL://PAIR?v=1",
    "mac-mini.tail1234.ts.net:7455", "[fd7a:115c:a1e0::1234]:17455", "localhost", "sill://pair?v=1",
]
func addressRow(_ input: String) -> [String: Any] {
    switch AddressParser.parse(input) {
    case .success(let a): return ["input": input, "ok": true, "host": a.host, "port": a.port.map { $0 as Any } ?? NSNull(),
                                  "kind": a.kind.rawValue, "text": a.text]
    case .failure(let f): return ["input": input, "ok": false, "failure": "\(f)"]
    }
}

// MARK: - Main

let args = CommandLine.arguments
if args.count == 3 && args[1] == "generate" {
    let root: [String: Any] = [
        "comment": "Generated by clients/wire-vectors/generate.sh from Sources/StreamProtocol; do not edit.",
        "messages": vectors.map { ["name": $0.name, "type": $0.type, "kind": $0.kind, "json": $0.json, "sorted": $0.sorted] },
        "binary": binary, "kinds": kinds,
        "versions": versions, "versionOrder": order,
        "safeTextClasses": runs, "safeTextLabels": labels, "safeTextLimit": SafeText.labelLimit,
        "addresses": addressInputs.map(addressRow),
        "limits": ["header": StreamMessage.headerLength, "maxClientPayload": StreamMessage.maxClientPayload,
                   "maxPairingPayload": StreamMessage.maxPairingPayload, "maxFramePayload": StreamMessage.maxFramePayload,
                   "maxOtherHostPayload": StreamMessage.maxOtherHostPayload, "protocol": SillProtocol.current,
                   "clipboardMaxTextBytes": Clipboard.maxTextBytes, "pairRequestVersion": 1],
        "presets": QualityPreset.allCases.map { ["name": $0.name, "bitrate": $0.rawValue] },
        "gestures": TrackpadGesture.names,
    ]
    let data = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    try! data.write(to: URL(fileURLWithPath: args[2]))
    print("wrote \(vectors.count) messages, \(binary.count) binary layouts, \(versions.count) versions, \(runs.count) SafeText runs, \(addressInputs.count) addresses")
} else if args.count == 4 && args[1] == "decode" {
    let root = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
    var want: [String: (type: String, sorted: String)] = [:]
    for m in root["messages"] as! [[String: Any]] { want[m["name"] as! String] = (m["type"] as! String, m["sorted"] as! String) }
    let theirs = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as! [[String: Any]]
    var fails = 0, seen = Set<String>()
    for t in theirs {
        let name = t["name"] as! String, type = t["type"] as! String, json = t["json"] as! String
        seen.insert(name)
        guard let w = want[name], w.type == type else { print("FAIL \(name): no Swift vector of type \(type)"); fails += 1; continue }
        guard let got = decoders[type]!(Data(json.utf8)) else { print("FAIL \(name): Swift cannot decode \(json)"); fails += 1; continue }
        if got != w.sorted {
            // Numbers can differ in form only (1 against 1.0): compare as decoded objects too.
            let a = try? JSONSerialization.jsonObject(with: Data(got.utf8)) as? NSObject
            let b = try? JSONSerialization.jsonObject(with: Data(w.sorted.utf8)) as? NSObject
            if a == nil || a != b { print("FAIL \(name):\n  swift  \(w.sorted)\n  theirs \(got)"); fails += 1; continue }
        }
        print("pass \(name)")
    }
    for name in want.keys.sorted() where !seen.contains(name) { print("FAIL \(name): not written by the other side"); fails += 1 }
    print(fails == 0 ? "ALL PASS (\(theirs.count))" : "\(fails) FAILED")
    exit(fails == 0 ? 0 : 1)
} else {
    print("usage: main generate OUT.json | main decode VECTORS.json IN.json"); exit(2)
}
