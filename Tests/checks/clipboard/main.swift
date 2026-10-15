import Foundation

// The clipboard's wire and rules (docs/clipboard-plan.md), against Sources/StreamProtocol compiled
// into this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/clipboard/main.swift -o check
// Kind 32 and Clipboard's JSON both ways, the caps, what a device's message asks of the host, which
// change of the Mac's pasteboard the host sends (a password manager's never read), who a device's
// text goes to, the rate, the device's subscription, which text from the Mac it writes, the chip,
// every word; then two models: the device's subscription against a host's view of it, and a host
// with several devices against what each must receive.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = ClipboardPolicy
typealias C = ClipboardPolicy.Copy
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
func data(_ s: String) -> Data { Data(s.utf8) }
func text(of d: Data?) -> String? { d.flatMap { Wire.decode(Clipboard.self, from: $0)?.text } }

// MARK: - The kind and the window list

func header(_ kind: UInt8) -> StreamHeader? {
    StreamMessage.parseHeader(Data([kind]) + Data(count: 9) + Data([0, 0, 0, 2]))
}
check(StreamMessageKind.clipboard.rawValue == 32 && StreamMessageKind(rawValue: 32) == .clipboard, "kind 32 is clipboard")
check(header(32)?.kind == .clipboard && header(32)?.payloadLength == 2, "a kind 32 header parses")
check([29, 30, 31, 33].allSatisfy { StreamMessageKind(rawValue: $0) == nil && header($0)?.kind == .unknown },
      "29 (the audio plan's), 30 and 31 (#66's side streams) and 33 are not this build's")
check(StreamMessageKind(rawValue: 28) == .gesture, "28 is still the gesture")
let message = StreamMessage(kind: .clipboard, timestamp: 1, isKeyframe: false, payload: P.subscription).serialized()
check(message.first == 32 && StreamMessage.parseHeader(message)?.kind == .clipboard && message.count == StreamMessage.headerLength + 2,
      "a subscription is a header and {}")

let takes = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.6", protocol: 1,
                       gestures: TrackpadGesture.generation, clipboard: P.generation)
check(json(takes).contains(#""clipboard":1"#), "a list from a host that shares the clipboard says clipboard 1: \(json(takes))")
check(Wire.decode(WindowList.self, from: Wire.encode(takes))?.clipboard == 1, "clipboard round-trips")
let off = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", gestures: 1)
check(!json(off).contains("clipboard"), "a host with it off leaves the key out: \(json(off))")
let older = #"{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"L","gestures":1}"#
check(Wire.decode(WindowList.self, from: data(older)).map { $0.clipboard == nil && $0.gestures == 1 } == true, "an older host's list decodes, clipboard nil")
check(Wire.decode(WindowList.self, from: data(#"{"macName":"M","windows":[],"active":{"none":{}},"clipboard":2}"#))?.clipboard == 2,
      "a later generation decodes")
check(Wire.decode(WindowList.self, from: data(#"{"macName":"M","windows":[],"active":{"none":{}},"clipboard":true}"#)) == nil,
      "#66's Bool does not decode as this Int (why #66 changes it as it rebases)")
check(P.generation == 1, "generation 1: text")

// MARK: - Clipboard's JSON

check(json(Clipboard()) == "{}", "an empty Clipboard is {}: \(json(Clipboard()))")
check(String(decoding: P.subscription, as: UTF8.self) == "{}", "the subscription is {}")
check(String(decoding: P.stopping, as: UTF8.self) == #"{"stop":true}"#, "stopping is {\"stop\":true}")
check(json(Clipboard(text: "hi")) == #"{"text":"hi"}"#, "text alone: \(json(Clipboard(text: "hi")))")
check(json(Clipboard(text: "a", image: Data([1, 2, 3]))) == #"{"image":"AQID","text":"a"}"#, "an image is base64, as #66 sends it")
check(Wire.decode(Clipboard.self, from: data(#"{"text":"a","image":"iVBORw==","later":[1]}"#)) == Clipboard(text: "a", image: Data([0x89, 0x50, 0x4E, 0x47])),
      "#66's shape decodes, unknown keys skipped")
check(Wire.decode(Clipboard.self, from: data("{}")) == Clipboard(), "{} decodes")
check(Wire.decode(Clipboard.self, from: data(#"{"text":5}"#)) == nil, "a number as the text does not decode")
check(Wire.decode(Clipboard.self, from: data("[]")) == nil, "not an object")
check(Clipboard.maxTextBytes == 262_144, "the text cap: 256 KB")
check(P.maxPayload == 1_048_576 && P.maxPayload == StreamMessage.maxClientPayload && P.maxPayload <= StreamMessage.maxOtherHostPayload,
      "the JSON cap: the host's on a device's message, within a device's on a host's")

// MARK: - payload(text:)

check(P.payload(text: "") == nil, "empty text: nothing to send")
check(text(of: P.payload(text: "Hello, Mac")) == "Hello, Mac", "text round-trips")
check(text(of: P.payload(text: "line 1\nline\t2 \u{202E} “é” 😀")) == "line 1\nline\t2 \u{202E} “é” 😀", "newlines, tabs, bidi and emoji kept as they are")
let atCap = String(repeating: "a", count: Clipboard.maxTextBytes)
check(P.payload(text: atCap).map { $0.count == Clipboard.maxTextBytes + 11 } == true, "exactly 256 KB goes (11 bytes of JSON around it)")
check(P.payload(text: atCap + "a") == nil, "one byte more does not")
let euros = String(repeating: "€", count: Clipboard.maxTextBytes / 3)   // 3 bytes each: 262,143
check(P.payload(text: euros) != nil && P.payload(text: euros + "€") == nil, "counted in UTF-8 bytes, not characters (€ is 3)")
let emoji = String(repeating: "😀", count: Clipboard.maxTextBytes / 4)  // 4 bytes each: exactly the cap
check(P.payload(text: emoji) != nil && P.payload(text: emoji + "😀") == nil, "😀 is 4 bytes")
// A control character is six bytes of JSON ("\u0001"): within 256 KB of text, over 1 MiB of JSON.
let controls = String(repeating: "\u{1}", count: 200_000)
check(Wire.encode(Clipboard(text: controls)).count > P.maxPayload && P.payload(text: controls) == nil,
      "text within the cap whose JSON is over 1 MiB is not sent")
let fits = String(repeating: "\u{1}", count: (P.maxPayload - 11) / 6)
check(Wire.encode(Clipboard(text: fits)).count <= P.maxPayload && text(of: P.payload(text: fits)) == fits, "its largest that fits goes")
let oneOver = String(repeating: "\u{1}", count: (P.maxPayload - 11) / 6 + 1)
check(oneOver.utf8.count <= Clipboard.maxTextBytes && P.payload(text: oneOver) == nil, "one control character more does not")

// MARK: - The host: a change of its pasteboard

let plain = ["public.utf8-plain-text", "public.utf16-external-plain-text"]
final class Reads { var marker = 0; var text = 0 }
func decide(_ types: [String], count: Int = 7, own: Int? = nil, launch: String = "L1", marker: String? = nil, text t: String? = "x",
            reads: Reads = Reads()) -> P.HostDecision {
    P.hostDecides(types: types, changeCount: count, ownChangeCount: own, launchID: launch,
                  ownMarker: { reads.marker += 1; return marker }, text: { reads.text += 1; return t })
}
check(decide(plain, text: "hello") == .send(P.payload(text: "hello")!), "a copy with text: sent as {\"text\":…}")
var r = Reads()
check(decide(plain, count: 9, own: 9, reads: r) == .skip(.own) && r.text == 0 && r.marker == 0, "the count after its own write: its own, nothing read")
check(decide(plain, count: 10, own: 9) == .send(P.payload(text: "x")!), "a later count is not its own")
check(decide(plain, count: 9, own: nil) == .send(P.payload(text: "x")!), "no write of its own yet")
check(P.markerTypes.count == 5 && P.markerTypes.contains(P.concealedType) && P.markerTypes.contains(P.transientType)
      && P.markerTypes.contains("org.nspasteboard.AutoGeneratedType") && P.markerTypes.contains("de.petermaurer.TransientPasteboardType")
      && P.markerTypes.contains("com.agilebits.onepassword"), "the five markers")
check(P.concealedType == "org.nspasteboard.ConcealedType" && P.transientType == "org.nspasteboard.TransientType", "nspasteboard.org's names")
for m in P.markerTypes {
    let reads = Reads()
    check(decide(plain + [m], text: "hunter2", reads: reads) == .skip(.marked) && reads.text == 0, "\(m): not sent, its text never read")
    let first = Reads()
    check(decide([m] + plain, reads: first) == .skip(.marked) && first.text == 0, "\(m) first among the types too")
}
check(P.remoteClipboardType == "com.apple.is-remote-clipboard", "Universal Clipboard's type")
r = Reads()
check(decide(plain + [P.remoteClipboardType], reads: r) == .skip(.remote) && r.text == 0 && r.marker == 0,
      "from another device through Universal Clipboard: not sent, never read (it would be fetched from that device)")
check(decide(plain + [P.remoteClipboardType, P.concealedType]) == .skip(.marked), "a password from another device: marked first")
r = Reads()
check(decide(plain + [P.ownType], marker: "L1", reads: r) == .skip(.own) && r.marker == 1 && r.text == 0, "its marker naming this launch: its own, the text never read")
check(decide(plain + [P.ownType], marker: "L0") == .send(P.payload(text: "x")!), "another launch's marker (another host on this Mac): a copy like any other")
check(decide(plain + [P.ownType], marker: nil) == .send(P.payload(text: "x")!), "its type without a value")
r = Reads()
check(decide(plain, marker: "L1", reads: r) != .skip(.own) && r.marker == 0, "the marker is read only when its type is there")
check(decide(plain + [P.ownType, P.concealedType], marker: "L0") == .skip(.marked), "a marker wins over another launch's own type")
check(decide(["public.png"], text: nil) == .skip(.noText), "no text: nothing")
check(decide(plain, text: "") == .skip(.empty), "empty text: nothing")
check(decide(plain, text: atCap + "!") == .skip(.tooLong), "over 256 KB: stays on the Mac")
check(decide(plain, text: controls) == .skip(.tooLong), "JSON over 1 MiB: stays on the Mac")
check(decide(plain, text: atCap) == .send(P.payload(text: atCap)!), "at the cap: sent")

// A change whose pasteboard is still empty: an app cleared it and has not written yet.
check(P.hostWaits(types: [], firstLook: 10, now: 10) && P.hostWaits(types: [], firstLook: 10, now: 10.99),
      "an empty pasteboard: the host looks again, for up to a second")
check(!P.hostWaits(types: [], firstLook: 10, now: 11), "after a second: decided (left empty)")
check(!P.hostWaits(types: plain, firstLook: 10, now: 10), "items there: decided at once")
check(!P.hostWaits(types: [P.concealedType], firstLook: 10, now: 10), "a marker alone is an item too: decided at once")
check(P.settleWindow == 1, "the settle window: a second")

// macOS's paste privacy (NSPasteboard.AccessBehavior, macOS 15.4 and later). The review's finding: the
// host read the clipboard at every copy whatever macOS said; asked, each read would bring macOS's alert.
check(P.macAccess(raw: nil) == .allowed, "before macOS 15.4 (no such setting): every read allowed")
check(P.macAccess(raw: 0) == .notAsked && P.macAccess(raw: 1) == .asks && P.macAccess(raw: 2) == .allowed && P.macAccess(raw: 3) == .denied,
      "0 default (not asked yet), 1 ask, 2 always allow, 3 always deny")
check(P.macAccess(raw: 4) == .asks && P.macAccess(raw: -1) == .asks, "a value this build does not know: as asking, nothing read in the background")
check(P.hostLooks(.allowed) && !P.hostLooks(.notAsked) && !P.hostLooks(.asks) && !P.hostLooks(.denied), "the host reads only while every read is allowed")
for was in [nil, .allowed, .notAsked, .asks, .denied] as [P.MacAccess?] {
    for now in [.allowed, .notAsked, .asks, .denied] as [P.MacAccess] {
        let want: P.AccessStep = now != .allowed ? .wait : (was == nil || was == .allowed ? .look : .takeAsSeen)
        check(P.accessStep(was: was, now: now) == want, "a look after \(was.map(\.rawValue) ?? "none") now \(now.rawValue): \(P.accessStep(was: was, now: now))")
    }
}
check(P.accessLine(was: nil, now: .allowed) == nil && P.accessLine(was: .allowed, now: .allowed) == nil,
      "no line while macOS allows every read from the start")
check(P.accessLine(was: nil, now: .denied) == C.macAccessLine(.denied) && P.accessLine(was: .allowed, now: .asks) == C.macAccessLine(.asks),
      "a line when copies start staying on the Mac")
check(P.accessLine(was: .asks, now: .allowed) == C.macAccessLine(.allowed) && P.accessLine(was: .denied, now: .allowed) == C.macAccessLine(.allowed),
      "a line when they go again")
check(P.accessLine(was: .notAsked, now: .asks) == nil && P.accessLine(was: .asks, now: .notAsked) == nil,
      "none for a change that keeps the words (asked and not yet asked read the same)")
check(P.accessLine(was: .asks, now: .denied) == C.macAccessLine(.denied), "a line from asking to denied")
check(C.macAccessWarning(.allowed) == nil && C.macAccessHint(.allowed) == nil, "Settings says nothing while every read is allowed")
check(C.macAccessWarning(.notAsked) == "macOS asks before Sill reads the clipboard, so what you copy here stays on this Mac."
      && C.macAccessWarning(.asks) == C.macAccessWarning(.notAsked), "asked: the warning")
check(C.macAccessWarning(.denied) == "macOS doesn’t let Sill read the clipboard, so what you copy here stays on this Mac.", "denied: the warning")
check(C.macAccessHint(.notAsked)!.hasPrefix("Click Allow in System Settings: macOS asks about Sill once")
      && C.macAccessHint(.asks) == C.macAccessHint(.denied) && C.macAccessHint(.asks)!.contains("Paste from Other Apps"),
      "the way to allow it: asked once first while macOS has not asked about Sill (it is not listed until then)")
check(C.macAccessButton == "Allow in System Settings…", "the button")
check(C.macFootnote == "Text you copy here can be pasted on a connected iPhone or iPad, and text sent from one with Paste becomes this Mac’s. Copies a password manager marks as concealed stay on this Mac.",
      "Settings › General's footnote: only what a password manager marks stays, and a device's text comes with Paste")
check(C.macAccessLine(.allowed).hasPrefix("Clipboard: macOS lets Sill read the clipboard again")
      && C.macAccessLine(.asks).hasPrefix("Clipboard: macOS asks before Sill reads the clipboard")
      && C.macAccessLine(.notAsked) == C.macAccessLine(.asks)
      && C.macAccessLine(.denied).hasPrefix("Clipboard: macOS does not let Sill read the clipboard"), "the host's lines")

// MARK: - The host: a device's message

check(P.fromDevice(data("{}")) == .subscribe, "{} subscribes")
check(P.fromDevice(data(#"{"text":"abc"}"#)) == .set("abc"), "text sets (and subscribes)")
check(P.fromDevice(data(#"{"text":""}"#)) == .subscribe, "empty text: subscribes, sets nothing")
check(P.fromDevice(data(#"{"stop":true}"#)) == .stop, "stop")
check(P.fromDevice(data(#"{"stop":true,"text":"abc"}"#)) == .stop, "stop wins over text")
check(P.fromDevice(data(#"{"stop":false}"#)) == .subscribe, "stop false is no stop")
check(P.fromDevice(data(#"{"image":"AQID"}"#)) == .subscribe, "an image alone: subscribes, this generation takes none")
check(P.fromDevice(data(#"{"text":"t","image":"AQID"}"#)) == .set("t"), "text and an image: the text")
check(P.fromDevice(Wire.encode(Clipboard(text: atCap))) == .set(atCap), "at the cap: set")
check(P.fromDevice(Wire.encode(Clipboard(text: atCap + "a"))) == .refuse(.tooLong), "over it: refused, nothing subscribed")
check(P.fromDevice(data("not json")) == .refuse(.undecodable) && P.fromDevice(data(#"{"text":7}"#)) == .refuse(.undecodable)
      && P.fromDevice(Data()) == .refuse(.undecodable), "what does not decode: refused")
check(P.fromDevice(data(#"{"text":"x","later":{"a":1}}"#)) == .set("x"), "a later field is skipped")

check(P.forward(to: [1, 2, 3], from: 2) == [1, 3], "a device's text goes to every other subscriber")
check(P.forward(to: [1, 2, 3], from: 4) == [1, 2, 3], "from a connection not subscribed (yet): to all")
check(P.forward(to: [Int](), from: 1).isEmpty && P.forward(to: [1], from: 1).isEmpty, "alone: to nobody")
check(P.forward(to: [3, 1, 2], from: 1) == [3, 2], "in the order given")

var arrivals: [Double] = []
var taken: [Bool] = []
for t in [0.0, 0.1, 0.2, 0.3, 0.4, 0.99, 1.05, 1.11] {
    let a = P.admits(arrivals: arrivals, now: t)
    taken.append(a.taken); arrivals = a.kept
}
check(taken == [true, true, true, true, false, false, true, true], "4 a second, then again a second after the first: \(taken)")
check(P.admits(arrivals: [0, 0.5, 0.9, 0.95], now: 1.0) == (taken: true, kept: [0.5, 0.9, 0.95, 1.0]), "the one exactly a second old has left the window")
check(P.admits(arrivals: [0.2, 0.5, 0.9, 0.95], now: 1.0).taken == false, "four within the second: refused")
check(P.admits(arrivals: [0.2, 0.5, 0.9, 0.95], now: 1.0).kept == [0.2, 0.5, 0.9, 0.95], "a refusal keeps what was there")
check(P.perSecond == 4, "4 a second, as settings and gestures")

// hostReceives: what a device's message asks first, then the rate, which only subscriptions and texts
// meet. The review's finding: a stop that was the fifth kind 32 in a second was refused by the rate, so
// the device whose switch had gone off stayed subscribed and the Mac's next copy still went to it.
func receives(_ messages: [(Double, String)]) -> [P.FromDevice] {
    var kept: [Double] = []
    return messages.map { (t, json) in
        let got = P.hostReceives(data(json), arrivals: kept, now: t)
        kept = got.kept
        return got.ask
    }
}
let stopJSON = #"{"stop":true}"#
check(receives([(0, "{}"), (2.0, stopJSON), (2.1, "{}"), (2.2, stopJSON), (2.3, "{}"), (2.4, stopJSON)])
      == [.subscribe, .stop, .subscribe, .stop, .subscribe, .stop],
      "the review's sequence (on, then off, on, off, on, off within a second): every stop taken")
check(receives([(3.0, "{}"), (3.1, "{}"), (3.2, "{}"), (3.3, "{}"), (3.4, stopJSON)]).last == .stop,
      "a stop after four subscriptions in the second: taken")
check(receives([(3.0, "{}"), (3.1, "{}"), (3.2, "{}"), (3.3, "{}"), (3.4, "{}")]).last == .refuse(.rate),
      "a fifth subscription in the second: refused by the rate")
check(receives([(0, #"{"text":"a"}"#), (0.1, #"{"text":"b"}"#), (0.2, #"{"text":"c"}"#), (0.3, #"{"text":"d"}"#), (0.4, #"{"text":"e"}"#)])
      == [.set("a"), .set("b"), .set("c"), .set("d"), .refuse(.rate)], "a fifth text in the second: refused, the Mac's clipboard kept")
check(receives([(0, stopJSON), (0.1, stopJSON), (0.2, stopJSON), (0.3, stopJSON), (0.4, stopJSON), (0.5, "{}"), (0.6, "{}"), (0.7, "{}"), (0.8, "{}")])
      .suffix(4) == [.subscribe, .subscribe, .subscribe, .subscribe], "stops count nothing: four subscriptions after five stops are taken")
check(receives([(0, "junk"), (0.1, "junk"), (0.2, "junk"), (0.3, "junk"), (0.4, "{}")]).last == .subscribe,
      "refusals count nothing: a subscription after four undecodable messages is taken")
check(receives([(0, "{}"), (0.1, "{}"), (0.2, "{}"), (0.3, "{}"), (0.4, "{}"), (0.5, "{}")]).suffix(2) == [.refuse(.rate), .refuse(.rate)],
      "after a refusal the second's arrivals are kept: a sixth is refused too")
check(receives([(0, "{}"), (0.1, "{}"), (0.2, "{}"), (0.3, "{}"), (1.05, "{}")]).last == .subscribe, "a second after the first: taken again")
check(P.hostReceives(data("junk"), arrivals: [0.5], now: 1).ask == .refuse(.undecodable)
      && P.hostReceives(Wire.encode(Clipboard(text: atCap + "a")), arrivals: [], now: 0).ask == .refuse(.tooLong),
      "a refusal says why")
check(P.Refusal.rate.rawValue == "rate" && P.Refusal.tooLong.rawValue == "tooLong" && P.Refusal.undecodable.rawValue == "undecodable",
      "the refusals' names are the ignored line's counts")

// MARK: - The device: its subscription

check(!P.hostTakes(nil) && !P.hostTakes(0) && P.hostTakes(1) && P.hostTakes(2), "a host takes it from generation 1")
for host in [nil, 0, 1, 2] as [Int?] {
    for on in [false, true] {
        for subscribed in [false, true] {
            let got = P.deviceSubscription(hostClipboard: host, switchOn: on, subscribed: subscribed)
            let takesIt = (host ?? 0) >= 1
            let want: (P.Subscription, Bool) = !takesIt ? (.none, false)
                : on && !subscribed ? (.subscribe, true) : !on && subscribed ? (.stop, false) : (.none, subscribed)
            check(got.send == want.0 && got.subscribed == want.1, "host \(host.map(String.init) ?? "nil"), switch \(on), subscribed \(subscribed): \(got)")
        }
    }
}

// MARK: - The device: the Mac's text

let fromMac = Wire.encode(Clipboard(text: "from the Mac"))
check(P.deviceWrites(fromMac, switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == "from the Mac", "written")
check(P.deviceWrites(fromMac, switchOn: false, hostClipboard: 1, lastSent: nil, changeCount: 3) == nil, "the switch off: never")
check(P.deviceWrites(fromMac, switchOn: true, hostClipboard: nil, lastSent: nil, changeCount: 3) == nil, "from a Mac that does not say it: never")
check(P.deviceWrites(data(#"{"text":""}"#), switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == nil, "empty: nothing")
check(P.deviceWrites(data(#"{"stop":true}"#), switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == nil, "no text: nothing")
check(P.deviceWrites(data("garbage"), switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == nil, "undecodable: nothing")
check(P.deviceWrites(Wire.encode(Clipboard(text: atCap + "a")), switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == nil, "over the cap: nothing")
check(P.deviceWrites(Wire.encode(Clipboard(text: atCap)), switchOn: true, hostClipboard: 1, lastSent: nil, changeCount: 3) == atCap, "at the cap: written")
let sent = P.Sent(text: "mine", changeCount: 41)
let echo = Wire.encode(Clipboard(text: "mine"))
check(P.deviceWrites(echo, switchOn: true, hostClipboard: 1, lastSent: sent, changeCount: 41) == nil, "the Mac's echo of what it holds: not written again")
check(P.deviceWrites(echo, switchOn: true, hostClipboard: 1, lastSent: sent, changeCount: 42) == "mine", "the same text after the clipboard changed: written")
check(P.deviceWrites(fromMac, switchOn: true, hostClipboard: 1, lastSent: sent, changeCount: 41) == "from the Mac", "other text: written")

// MARK: - The device: the chip

for connected in [false, true] {
    for host in [nil, 1] as [Int?] {
        for on in [false, true] {
            for has in [false, true] {
                for handled in [nil, 5, 6] as [Int?] {
                    let got = P.offersChip(connected: connected, hostClipboard: host, switchOn: on, hasStrings: has, changeCount: 6, handled: handled)
                    let want = connected && host != nil && on && has && handled != 6
                    check(got == want, "chip: connected \(connected), host \(host as Any), switch \(on), text \(has), handled \(handled as Any): \(got)")
                }
            }
        }
    }
}
// The chip's 20 s run only while it is on screen, Sill active and VoiceOver off (the review's finding:
// it ran out unseen under the tour or the Settings panel, and for VoiceOver in 20 s, and the copy then
// counted as dealt with).
for onScreen in [false, true] {
    for active in [false, true] {
        for voiceOver in [false, true] {
            check(P.chipCounts(onScreen: onScreen, active: active, voiceOver: voiceOver) == (onScreen && active && !voiceOver),
                  "the chip's time: on screen \(onScreen), active \(active), VoiceOver \(voiceOver)")
        }
    }
}
check(C.chipAnnouncement(mac: "Mac mini") == "Paste on Mac mini is available, near the bar.", "VoiceOver told when the chip shows")
check(P.looksAtSessionStart(activatedAt: nil, now: 100) == false, "no activation: no look")
check(P.looksAtSessionStart(activatedAt: 100, now: 100) && P.looksAtSessionStart(activatedAt: 100, now: 115), "within 15 s: the look")
check(!P.looksAtSessionStart(activatedAt: 100, now: 115.01), "after 15 s: none")
check(!P.looksAtSessionStart(activatedAt: 100, now: 99.9), "before the activation (a clock that went back): none")
check(P.activationWindow == 15 && P.chipLifetime == 20 && P.noteLifetime == 3 && P.deviceExpiry == 600 && P.lookInterval == 0.25,
      "the times: 15 s, 20 s, 3 s, 10 minutes, four looks a second")

check(P.deviceSends(["abc"], connected: true, hostClipboard: 1, switchOn: true) == .send(P.payload(text: "abc")!), "Paste sends the text")
check(P.deviceSends(["", "b", "c"], connected: true, hostClipboard: 1, switchOn: true) == .send(P.payload(text: "b")!), "the first that is not empty")
check(P.deviceSends([], connected: true, hostClipboard: 1, switchOn: true) == .nothing && P.deviceSends([""], connected: true, hostClipboard: 1, switchOn: true) == .nothing,
      "nothing to send")
check(P.deviceSends([atCap + "a"], connected: true, hostClipboard: 1, switchOn: true) == .tooLong, "over 256 KB: too long, nothing sent")
check(P.deviceSends([controls], connected: true, hostClipboard: 1, switchOn: true) == .tooLong, "JSON over 1 MiB: too long")
check(P.deviceSends(["abc"], connected: false, hostClipboard: 1, switchOn: true) == .nothing, "not connected: nothing")
check(P.deviceSends(["abc"], connected: true, hostClipboard: nil, switchOn: true) == .nothing, "a Mac that does not take it: nothing")
check(P.deviceSends(["abc"], connected: true, hostClipboard: 1, switchOn: false) == .nothing, "the switch off: nothing")

// A Paste's receipt: a ping after the text whose pong says the Mac has read it. The review's finding:
// "Sent" came as the text was handed over, and a dead connection lost it while the copy counted as dealt
// with. Its payload must never pass for an ordinary ping's (8 bytes: the time it went) or a move's fence
// ping's (8 bytes), nor they for it.
check(P.receiptLength == 16 && P.receiptLength != 8, "a receipt's payload: 16 bytes, never a ping's 8")
check(P.receiptWait(worstRttMs: nil) == 4 && P.receiptWait(worstRttMs: 0) == 4 && P.receiptWait(worstRttMs: 1000) == 4,
      "it waits 4 s while the round trip is a second or less")
check(P.receiptWait(worstRttMs: 2500) == 10 && P.receiptWait(worstRttMs: 1001) > 4, "and four times the worst round trip above that")
check(C.notSent(mac: "Mac mini") == "Didn’t reach Mac mini. Try Paste again.", "no receipt in time: the note")

check(P.chipCorner(landscape: true, linkLineShown: false) == .topTrailing, "sideways: under the bar")
check(P.chipCorner(landscape: true, linkLineShown: true) == .bottomTrailing, "sideways with the link's line at the top: the bottom corner")
check(P.chipCorner(landscape: false, linkLineShown: false) == .bottomTrailing && P.chipCorner(landscape: false, linkLineShown: true) == .bottomTrailing,
      "upright: above the window bar or row 1")

// MARK: - Words

check(C.cap == "256 KB", "the cap in words: \(C.cap)")
check(C.chipTitle(mac: "Mac mini") == "Paste on Mac mini", "the chip's title")
check(C.chipSubtitle == "Then press ⌘V there.", "its subtitle")
check(C.chipSpoken(mac: "Mac mini", device: "iPad") == "Paste on Mac mini. Sends the text you copied on this iPad to Mac mini’s clipboard. Then press Command-V there.",
      "its spoken label")
check(C.pasteHint(mac: "Mac mini", device: "iPhone") == "Sends the text you copied on this iPhone to Mac mini’s clipboard.", "the Paste button's hint")
check(C.sent(mac: "Mac mini") == "Sent to Mac mini’s clipboard. Press ⌘V there." && C.sentSpoken(mac: "Mac mini") == "Sent to Mac mini’s clipboard. Press Command-V there.",
      "the confirmation, written and spoken")
check(C.tooLong(mac: "Mac mini") == "Too long to send: Mac mini takes up to 256 KB of text.", "too long")
check(C.switchTitle == "Share Clipboard" && C.rowTitle(mac: "Mac mini") == "Paste on Mac mini" && C.dismiss == "Dismiss", "the switch, the row, Dismiss")
check(C.footnote(on: true, mac: "Mac mini", device: "iPad") == "Text you copy on Mac mini is ready to paste on this iPad. To paste on Mac mini, copy text here, tap Paste, then press ⌘V there.",
      "the footnote, on")
check(C.footnote(on: false, mac: "Mac mini", device: "iPhone") == "Nothing you copy goes between this iPhone and Mac mini while this is off.", "the footnote, off")
check(C.sharesLine(device: "iPad (iPad14,1)") == "Clipboard: iPad (iPad14,1) shares the clipboard.", "the host's line on a subscription")
check(C.stoppedLine(device: "iPad (iPad14,1)") == "Clipboard: iPad (iPad14,1) stopped sharing the clipboard.", "…and on a stop")
check(C.ignoredLine(rate: 3, tooLong: 1, undecodable: 0) == "Clipboard from devices ignored in a minute: 3 from devices sending more than 4 a second, 1 longer than 256 KB.",
      "the ignored line")
check(C.ignoredLine(rate: 0, tooLong: 0, undecodable: 2) == "Clipboard from devices ignored in a minute: 2 that did not decode.", "…with one count")
let words = [C.chipTitle(mac: "M"), C.chipSubtitle, C.chipSpoken(mac: "M", device: "iPad"), C.pasteHint(mac: "M", device: "iPad"), C.sent(mac: "M"),
             C.sentSpoken(mac: "M"), C.tooLong(mac: "M"), C.switchTitle, C.rowTitle(mac: "M"), C.footnote(on: true, mac: "M", device: "iPad"),
             C.footnote(on: false, mac: "M", device: "iPad"), C.sharesLine(device: "d"), C.stoppedLine(device: "d"), C.ignoredLine(rate: 1, tooLong: 1, undecodable: 1),
             C.macFootnote, C.macAccessButton, C.notSent(mac: "M"), C.chipAnnouncement(mac: "M")]
    + [P.MacAccess.allowed, .notAsked, .asks, .denied].flatMap { [C.macAccessWarning($0), C.macAccessHint($0), C.macAccessLine($0)].compactMap { $0 } }
check(words.allSatisfy { !$0.contains("—") && !$0.contains("–") }, "no dashes in the words")

// MARK: - Model 1: the device's subscription against the host's view of it

// Random sessions: the Mac's setting on and off (its list says 1 or nothing), the device's switch on
// and off. The device follows deviceSubscription; a model host subscribes it on any kind 32, drops
// it on stop, and forgets every subscription when its setting goes off. After every step the two
// agree, the device is subscribed exactly while both are on, and nothing went to a host that did
// not take it.
var rng = SystemRandomNumberGenerator()
var modelFailures = 0
for _ in 0..<5_000 {
    var hostOn = Bool.random(using: &rng), switchOn = Bool.random(using: &rng)
    var deviceSubscribed = false, hostSubscribed = false
    for _ in 0..<Int.random(in: 1...30, using: &rng) {
        if Bool.random(using: &rng) {
            hostOn.toggle()
            if !hostOn { hostSubscribed = false }        // the host forgets them all
        } else {
            switchOn.toggle()
        }
        let step = P.deviceSubscription(hostClipboard: hostOn ? P.generation : nil, switchOn: switchOn, subscribed: deviceSubscribed)
        if step.send != .none {
            if !hostOn { modelFailures += 1; break }    // a kind 32 to a host that did not say it takes it
            let payload = step.send == .subscribe ? P.subscription : P.stopping
            switch P.fromDevice(payload) {
            case .subscribe, .set: hostSubscribed = true
            case .stop: hostSubscribed = false
            case .refuse: modelFailures += 1
            }
        }
        deviceSubscribed = step.subscribed
        if deviceSubscribed != hostSubscribed || deviceSubscribed != (hostOn && switchOn) { modelFailures += 1; break }
    }
}
check(modelFailures == 0, "5,000 random sessions: the device's subscription and the host's agree (\(modelFailures) wrong)")

// MARK: - Model 1b: the same, quickly, with the rate

// The switch flipped several times a second, a Paste now and then while it is on, the Mac's setting
// going off and on. The host takes each message by hostReceives, as HostClipboard does. Whatever the
// timing, the host never has the device subscribed while its switch is off: a stop is never lost to
// the rate (the review's finding). A subscription past the rate may be refused (the device then gets
// nothing until it subscribes again: it fails closed).
var quickFailures = 0
var refusedSubscriptions = 0
for _ in 0..<5_000 {
    var hostOn = true, switchOn = Bool.random(using: &rng)
    var deviceSubscribed = false, hostSubscribed = false
    var arrivals: [Double] = [], now = 0.0
    for _ in 0..<Int.random(in: 1...40, using: &rng) {
        now += Double.random(in: 0...0.4, using: &rng)
        var payload: Data? = nil
        switch Int.random(in: 0..<8, using: &rng) {
        case 0:
            hostOn.toggle()
            if !hostOn { hostSubscribed = false; arrivals = [] }     // setEnabled(false) forgets them all
        case 1:
            // A Paste: only with the switch on, to a Mac that takes the clipboard (deviceSends).
            if case .send(let p) = P.deviceSends(["pasted"], connected: true, hostClipboard: hostOn ? P.generation : nil, switchOn: switchOn) { payload = p }
        default:
            switchOn.toggle()
        }
        let step = P.deviceSubscription(hostClipboard: hostOn ? P.generation : nil, switchOn: switchOn, subscribed: deviceSubscribed)
        deviceSubscribed = step.subscribed
        if step.send != .none { payload = step.send == .subscribe ? P.subscription : P.stopping }
        if let payload {
            if !hostOn { quickFailures += 1; break }               // a kind 32 to a host that did not say it takes it
            let got = P.hostReceives(payload, arrivals: arrivals, now: now)
            arrivals = got.kept
            switch got.ask {
            case .subscribe, .set: hostSubscribed = true
            case .stop: hostSubscribed = false
            case .refuse(.rate): if step.send == .subscribe { refusedSubscriptions += 1 }
            case .refuse: quickFailures += 1
            }
        }
        if hostSubscribed && !(hostOn && switchOn) { quickFailures += 1; break }   // copies to a device whose switch is off
    }
}
check(quickFailures == 0, "5,000 quick sessions: never subscribed at the host while the device's switch is off (\(quickFailures) wrong)")
check(refusedSubscriptions > 0, "…and the model reached the rate (\(refusedSubscriptions) subscriptions refused)")

// MARK: - Model 2: a host with several devices

// Three devices subscribe; the Mac's pasteboard changes (plain copies, password managers' copies, the
// host's own writes) and devices send text, and macOS's answer on reads changes, in random order. The
// host follows hostDecides, fromDevice, forward and accessStep, as HostClipboard does. Every subscriber
// must get every plain Mac copy made while it subscribed and macOS allowed every read, and every other
// device's text; never its own text, never a marked copy, never a copy made while macOS asked or
// denied, and the host must never send its own write again.
var hostFailures = 0
var accessWaits = 0
for run in 0..<2_000 {
    let devices = 3
    var subscribed = Set<Int>()
    var received = [[String]](repeating: [], count: devices)
    var expected = [[String]](repeating: [], count: devices)
    var count = 100, own: Int? = nil, launch = "launch-\(run)"
    var board: (types: [String], text: String?, marker: String?) = (plain, "before", nil)
    var seen = count
    var access = P.MacAccess.allowed
    var lastAccess: P.MacAccess? = .allowed      // the count was taken as seen while macOS allowed it
    // A copy goes while macOS allows every read and the host has looked since it began to: the first
    // look after it allows again takes the count as seen, and a copy made in that moment with it
    // (a quarter of a second at most) stays on the Mac.
    func goes() -> Bool { access == .allowed && lastAccess.map(P.hostLooks) != false }
    func look() {
        let step = P.accessStep(was: lastAccess, now: access)
        lastAccess = access
        switch step {
        case .wait: accessWaits += 1; return    // nothing read
        case .takeAsSeen: seen = count; return  // what was copied meanwhile is never sent
        case .look: break
        }
        guard count != seen else { return }
        seen = count
        let b = board
        if case .send(let payload) = P.hostDecides(types: b.types, changeCount: count, ownChangeCount: own, launchID: launch,
                                                   ownMarker: { b.marker }, text: { b.text }) {
            let t = text(of: payload)!
            for d in subscribed.sorted() { received[d].append(t) }
        }
    }
    for step in 0..<Int.random(in: 1...40, using: &rng) {
        switch Int.random(in: 0..<8, using: &rng) {
        case 0:   // a device subscribes
            let d = Int.random(in: 0..<devices, using: &rng)
            if case .subscribe = P.fromDevice(P.subscription) { subscribed.insert(d) }
        case 1:   // a device stops
            let d = Int.random(in: 0..<devices, using: &rng)
            if case .stop = P.fromDevice(P.stopping) { subscribed.remove(d) }
        case 2:   // a plain copy on the Mac: it goes only while macOS allows every read
            count += 1
            let t = "copy \(step)"
            board = (plain, t, nil)
            if goes() { for d in subscribed { expected[d].append(t) } }
            look()
        case 3:   // a password manager's copy, or one from another device through Universal Clipboard
            count += 1
            board = (plain + [(P.markerTypes + [P.remoteClipboardType]).randomElement(using: &rng)!], "secret \(step)", nil)
            look()
        case 4:   // a device sends text: the Mac's clipboard is set (marked as the host's own), the others told
            let d = Int.random(in: 0..<devices, using: &rng)
            let t = "from \(d) at \(step)"
            guard case .set(let got) = P.fromDevice(P.payload(text: t)!) else { hostFailures += 1; continue }
            subscribed.insert(d)
            count += 1
            board = (plain + [P.ownType], got, launch)
            own = count
            if Bool.random(using: &rng) { seen = count }  // HostClipboard records its own write; without it, its count says so
            for other in P.forward(to: subscribed.sorted(), from: d) {
                received[other].append(got); expected[other].append(got)
            }
        case 5:   // an app clears the pasteboard, the host looks before it writes, then the write
            count += 1
            board = ([], nil, nil)
            let t0 = Double(step)
            if !P.hostWaits(types: board.types, firstLook: t0, now: t0) { look() }   // it waits: no look taken
            let t = "slow copy \(step)"
            board = (plain, t, nil)
            if goes() { for d in subscribed { expected[d].append(t) } }
            look()
        case 6:   // macOS's answer on reads changes (System Settings, or its first alert)
            access = [.allowed, .notAsked, .asks, .denied].randomElement(using: &rng)!
        default:  // the host looks (again)
            look()
        }
    }
    look()
    for d in 0..<devices where received[d] != expected[d]
        || received[d].contains(where: { $0.hasPrefix("secret") || $0.hasPrefix("from \(d) ") }) {
        hostFailures += 1
    }
}
check(hostFailures == 0, "2,000 random runs of three devices: each got exactly the Mac's plain copies made while macOS allowed reads, and the others' text (\(hostFailures) wrong)")
check(accessWaits > 0, "…and macOS asked or denied in some (\(accessWaits) looks read nothing)")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
