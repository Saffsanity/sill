import Foundation

// H3 of docs/update-notice-plan.md (its protocol part): SillVersion and the payloads, against
// Sources/StreamProtocol compiled into this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/compatibility/main.swift -o check
// Given a path, it also writes the payloads that H4 read with an older StreamProtocol (cb0ec55's),
// the trackpad gestures plan's H6 (a kind 28 message, a window list with `gestures`), and the
// clipboard's (a kind 32 message, a window list with `clipboard`).
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func v(_ s: String) -> SillVersion? { SillVersion(s) }

// §3.2's examples.
check(v("v0.4.0")?.components == [0, 4], "v0.4.0")
check(v("V0.4")?.components == [0, 4], "V0.4")
check(v(" 0.4.0 ")?.components == [0, 4], "' 0.4.0 '")
check(v("\t0.4.0\n")?.components == [0, 4], "tab/newline")
check(v("1.2.3-beta.1")?.components == [1, 2, 3], "1.2.3-beta.1")
check(v("01.2")?.components == [1, 2], "01.2")
check(v("1..2") == nil, "1..2")
check(v("1.")?.components == [1], "1.")
check(v("1...")?.components == [1], "1...")
check(v("") == nil, "empty")
check(v("   ") == nil, "spaces")
check(v("dev") == nil, "dev")
check(v("v") == nil, "v")
check(v("vv1.0") == nil, "vv1.0")
check(v(".1") == nil, ".1")
check(v("v.1") == nil, "v.1")
check(v("-1") == nil, "-1")
check(v("+1") == nil, "+1")
check(v("1234567890") == nil, "10 digits")
check(v("123456789")?.components == [123456789], "9 digits")
check(v("1.1234567890") == nil, "a 10-digit part")
check(v("1.2.3.4.5.6.7.8")?.components == [1, 2, 3, 4, 5, 6, 7, 8], "eight parts")
check(v("1.2.3.4.5.6.7.8.9") == nil, "nine parts")
check(v("1.2.3.4.5.6.7.8.")?.components == [1, 2, 3, 4, 5, 6, 7, 8], "eight parts and a dot")
check(v("0") == .zero && v("0.0.0") == .zero && v("v0") == .zero, "zero")
check(v("٣.١") == nil, "Arabic-Indic digits are not ASCII")
check(v("1.٣")?.components == [1], "a non-ASCII digit ends the prefix")
check(v("１.2") == nil, "fullwidth digit")
check(v("0.3.0 (85)") == v("0.3.0") && v("0.3.0 (85)") != nil, "0.3.0 (85) is 0.3.0")
check(!(v("0.3.0 (85)")! > v("0.3.0")!), "0.3.0 (85) is not newer than 0.3.0")
check(v("nightly") == nil, "nightly")
check(v("v0.4.0-rc.1") == v("0.4"), "rc suffix ignored")
check(v("2026.09.25")?.components == [2026, 9, 25], "a date-like tag")
// Comparing.
check(v("0.10")! > v("0.9")!, "0.10 > 0.9")
check(v("1.0.1")! > v("1.0")!, "1.0.1 > 1.0")
check(v("v0.4.0")! == v("0.4")!, "v0.4.0 == 0.4")
check(v("0.4")! > v("0.3.9")!, "0.4 > 0.3.9")
check(v("1")! == v("1.0.0")!, "1 == 1.0.0")
check(v("1.0.0.1")! > v("1")!, "1.0.0.1 > 1")
check(!(v("1.2")! < v("1.2")!), "irreflexive")
check(v("v0.4.0")! > v("0.3.0")!, "tag with v against a bundle version")
check(v("0.4.0")! > v("v0.3.0")!, "bundle with v")
check(SillVersion.zero < v("0.0.1")!, "0 < 0.0.1")
// Showing.
check(v("0.4.0")!.description == "0.4", "0.4.0 shows 0.4")
check(v("1")!.description == "1.0", "1 shows 1.0")
check(v("1.0.1")!.description == "1.0.1", "1.0.1 shows 1.0.1")
check(SillVersion.zero.description == "0.0", "0 shows 0.0")
check(v("99")!.description == "99.0", "99 shows 99.0")
check(v("1.2.0.0")!.description == "1.2", "1.2.0.0 shows 1.2")
check(v("0.0.5")!.description == "0.0.5", "0.0.5 shows 0.0.5")
check(SillVersion(components: [1, 0, 0]).components == [1], "trailing zeros dropped")
check(v("1.2")!.hashValue == v("1.2.0")!.hashValue, "equal versions hash alike")

// 1,000 random pairs against a reference: padded lexicographic comparison of the generated parts,
// written with or without "v", with trailing ".0"s, leading zeros and a suffix.
var rng = SystemRandomNumberGenerator()
func reference(_ a: [Int], _ b: [Int]) -> Int {
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}
func write(_ parts: [Int]) -> String {
    var p = parts.isEmpty ? [0] : parts
    for _ in 0..<Int.random(in: 0...2, using: &rng) where p.count < 8 { p.append(0) }
    var s = p.map { n in Bool.random(using: &rng) && n < 10 ? "0\(n)" : "\(n)" }.joined(separator: ".")
    if Bool.random(using: &rng) { s = (Bool.random(using: &rng) ? "v" : "V") + s }
    if Int.random(in: 0...3, using: &rng) == 0 { s += ["-beta.1", " (85)", "+build.7", "rc1"].randomElement(using: &rng)! }
    if Int.random(in: 0...5, using: &rng) == 0 { s = "  " + s + "\n" }
    return s
}
var randomFailures = 0
for _ in 0..<1000 {
    let a = (0..<Int.random(in: 0...5, using: &rng)).map { _ in Int.random(in: 0...12, using: &rng) }
    let b = Bool.random(using: &rng) ? a : (0..<Int.random(in: 0...5, using: &rng)).map { _ in Int.random(in: 0...12, using: &rng) }
    let sa = write(a), sb = write(b)
    guard let va = v(sa), let vb = v(sb) else { randomFailures += 1; print("no parse: \(sa.debugDescription) \(sb.debugDescription)"); continue }
    let want = reference(a, b)
    let got = va < vb ? -1 : (vb < va ? 1 : 0)
    if want != got || (want == 0) != (va == vb) { randomFailures += 1; print("order: \(sa.debugDescription) vs \(sb.debugDescription): want \(want), got \(got)") }
    // The description round-trips.
    if v(va.description) != va { randomFailures += 1; print("round trip: \(sa.debugDescription) → \(va.description)") }
}
check(randomFailures == 0, "1,000 random pairs: \(randomFailures) wrong")

// The payloads.
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
let hello = Hello(appVersion: "1.0", build: "42", protocol: 1, device: "iPad (iPad14,1)")
check(json(hello) == #"{"appVersion":"1.0","build":"42","device":"iPad (iPad14,1)","protocol":1}"#, "Hello's keys: \(json(hello))")
check(json(Hello()) == "{}", "an empty hello is {}")
check(Wire.decode(Hello.self, from: Data("{}".utf8)) == Hello(), "{} decodes")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":"1.2","protocol":1,"extra":[1,2]}"#.utf8)) == Hello(appVersion: "1.2", protocol: 1),
      "unknown keys are skipped")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":12}"#.utf8)) == nil, "a number as the version does not decode")
check(Wire.decode(Hello.self, from: Data("[]".utf8)) == nil, "not an object")
// The five goodbyes this branch sends, byte for byte, through the host's own encoder (Wire).
for reason in [Goodbye.quit, Goodbye.removed, Goodbye.remoteOff, Goodbye.internetOff, Goodbye.busy] {
    let bytes = String(decoding: Wire.encode(Goodbye(reason: reason)), as: UTF8.self)
    check(bytes == "{\"reason\":\"\(reason)\"}", "goodbye \(reason): \(bytes)")
}
let update = Goodbye(reason: Goodbye.update, message: "Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.",
                     minimumVersion: "1.2", reconnect: false)
check(json(update) == #"{"message":"Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.","minimumVersion":"1.2","reason":"update","reconnect":false}"#,
      "the update goodbye: \(json(update))")
check(Wire.decode(Goodbye.self, from: Data(#"{"reason":"quit"}"#.utf8)) == Goodbye(reason: "quit"), "an old goodbye reads with nil fields")
check(Wire.decode(Goodbye.self, from: Data(#"{"message":"x"}"#.utf8)) == nil, "no reason: no goodbye")
// A reason from a later host ("pairingRequired", this example until pairing at home made it a reason
// the device knows, is Goodbye.pairingRequired now).
let later = #"{"reason":"pairAgain","message":"Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.","reconnect":false}"#
check(Wire.decode(Goodbye.self, from: Data(later.utf8))?.reason == "pairAgain", "a later reason decodes")
check(Goodbye.pairingRequired == "pairingRequired" && Goodbye.update == "update", "pairing at home's reason and the update notice's, as their devices read them")
// The window list with and without the new keys.
let list = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.4.0", protocol: SillProtocol.current)
let listJSON = json(list)
check(listJSON.contains(#""hostVersion":"0.4.0""#) && listJSON.contains(#""protocol":1"#), "the list carries both keys: \(listJSON)")
let bare = json(WindowList(macName: "Mac mini", windows: [], active: .none, launchID: "L"))
check(!bare.contains("hostVersion") && !bare.contains("protocol"), "nil keys are left out: \(bare)")
let oldList = #"{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"L"}"#
let decodedOld = Wire.decode(WindowList.self, from: Data(oldList.utf8))
check(decodedOld != nil && decodedOld?.hostVersion == nil && decodedOld?.protocol == nil, "an older host's list decodes, both nil")
check(StreamMessageKind.hello.rawValue == 23 && StreamMessageKind(rawValue: 23) == .hello, "kind 23 is hello")
let helloMessage = StreamMessage(kind: .hello, timestamp: 1, isKeyframe: false, payload: Wire.encode(hello)).serialized()
check(StreamMessage.parseHeader(helloMessage)?.kind == .hello, "the hello's header parses")
check(SillProtocol.current == 1, "protocol 1")

// Kind 28, the trackpad gesture (docs/trackpad-gestures-plan.md §4), and the window list's
// `gestures`: additive both ways.
check(TrackpadGesture.names == ["swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread"], "the six names, in order: \(TrackpadGesture.names)")
check(Set(TrackpadGesture.names).count == 6, "the six names are distinct")
check(TrackpadGesture.generation == 1, "gestures 1: the six")
let gesture = TrackpadGesture(gesture: TrackpadGesture.swipeUp, fingers: 3)
check(json(gesture) == #"{"fingers":3,"gesture":"swipeUp"}"#, "a gesture's keys: \(json(gesture))")
check(json(TrackpadGesture(gesture: TrackpadGesture.pinch)) == #"{"gesture":"pinch"}"#, "no finger count: left out")
check(Wire.decode(TrackpadGesture.self, from: Data(#"{"gesture":"spread","fingers":4,"phase":"began"}"#.utf8)) == TrackpadGesture(gesture: "spread", fingers: 4),
      "unknown keys are skipped (a later generation's fields)")
check(Wire.decode(TrackpadGesture.self, from: Data(#"{"gesture":"rotate"}"#.utf8))?.gesture == "rotate", "a later name decodes as a string")
check(Wire.decode(TrackpadGesture.self, from: Data(#"{"fingers":3}"#.utf8)) == nil, "no name: no gesture")
check(Wire.decode(TrackpadGesture.self, from: Data(#"{"gesture":3}"#.utf8)) == nil, "a number as the name does not decode")
check(Wire.decode(TrackpadGesture.self, from: Data(#"{"gesture":"swipeUp","fingers":"3"}"#.utf8)) == nil, "a string as the count does not decode")
let takes = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.5", protocol: 1, gestures: TrackpadGesture.generation)
check(json(takes).contains(#""gestures":1"#), "a list from a host that takes them says gestures 1: \(json(takes))")
check(!json(list).contains("gestures"), "a list without them leaves the key out: \(json(list))")
check(decodedOld != nil && decodedOld?.gestures == nil, "an older host's list decodes, gestures nil")
check(Wire.decode(WindowList.self, from: Wire.encode(takes))?.gestures == 1, "gestures round-trips")
check(StreamMessageKind.gesture.rawValue == 28 && StreamMessageKind(rawValue: 28) == .gesture, "kind 28 is gesture")
check(StreamMessageKind(rawValue: 27) == .fetchMenu && StreamMessageKind(rawValue: 43) == .audio, "27 is the menus' fetch, 43 the Mac's sound")
let gestureMessage = StreamMessage(kind: .gesture, timestamp: 1, isKeyframe: false, payload: Wire.encode(gesture)).serialized()
check(StreamMessage.parseHeader(gestureMessage)?.kind == .gesture, "the gesture's header parses")
check(gestureMessage.count == StreamMessage.headerLength + Wire.encode(gesture).count, "one header, then the JSON")
// The Mac's sound (docs/audio-plan.md §3.4, H3's wire cases): the hello's codecs, AudioFormat, Send
// Audio in kinds 16 and 17, the audio note and ClientStats' two fields, every one optional, and the
// older payloads decoding the newer JSON (each `Old…` below is the type as it was before the sound).
struct OldHello: Codable, Equatable { var appVersion: String?; var build: String?; var `protocol`: Int?; var device: String? }
struct OldStreamSettings: Codable, Equatable {
    var maxFPS: Int; var bitrate: Int; var captureScale: Double; var prioritizeSpeed: Bool; var virtualDisplay: Bool; var directWireless: Bool?
}
struct OldClientStats: Codable, Equatable {
    var fps: Int; var frameAgeMs: Int; var rttMs: Int; var device: String; var frameAgeMaxMs: Int?; var rttMaxMs: Int?
}
struct OldChange: Codable, Equatable {
    var token: Int?; var maxFPS: Int?; var bitrate: Int?; var captureScale: Double?; var prioritizeSpeed: Bool?; var virtualDisplay: Bool?; var directWireless: Bool?
}
let soundHello = Hello(appVersion: "0.6", build: "7", protocol: 1, device: "iPad (iPad14,1)", audio: AudioCodec.devicePlays)
check(json(soundHello) == #"{"appVersion":"0.6","audio":["aac-eld"],"build":"7","device":"iPad (iPad14,1)","protocol":1}"#,
      "the hello lists its codecs under \"audio\": \(json(soundHello))")
check(Wire.decode(Hello.self, from: Wire.encode(soundHello)) == soundHello, "a hello with codecs round-trips")
check(json(Hello(appVersion: "1.0")) == #"{"appVersion":"1.0"}"#, "a hello without codecs has no audio key (a device that plays no sound)")
check(Wire.decode(Hello.self, from: Data(#"{"audio":["opus","aac-eld"],"later":1}"#.utf8))?.audio == ["opus", "aac-eld"],
      "the codecs decode in the device's order, unknown keys skipped")
check(Wire.decode(Hello.self, from: Data(#"{"audio":"aac-eld"}"#.utf8)) == nil, "codecs as one string do not decode")
check(Wire.decode(OldHello.self, from: Wire.encode(soundHello)) == OldHello(appVersion: "0.6", build: "7", protocol: 1, device: "iPad (iPad14,1)"),
      "an older host reads the new hello and skips its codecs")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":"1.0","build":"42","protocol":1,"device":"iPad"}"#.utf8))?.audio == nil,
      "an older device's hello: no codecs")
// The host's pick: the first of the device's list (best first) that the host makes.
check(AudioCodec.choose(offered: nil) == nil, "choose: no list (an older device), no sound")
check(AudioCodec.choose(offered: []) == nil, "choose: an empty list, no sound")
check(AudioCodec.choose(offered: ["opus"]) == nil, "choose: nothing this host makes, no sound")
check(AudioCodec.choose(offered: ["aac-eld"]) == "aac-eld", "choose: aac-eld")
check(AudioCodec.choose(offered: ["opus", "aac-eld"]) == "aac-eld", "choose: past a codec this host does not make")
check(AudioCodec.choose(offered: ["AAC-ELD", "aac-eld "]) == nil, "choose: names are exact (no case folding, no trimming)")
check(AudioCodec.choose(offered: ["opus", "aac-eld"], makes: ["aac-eld", "opus"]) == "opus", "choose: the device's order wins over the host's")
check(AudioCodec.choose(offered: ["x", "aac-eld", "opus"], makes: ["opus", "aac-eld"]) == "aac-eld", "choose: the first the host makes, not the host's best")
check(AudioCodec.choose(offered: ["aac-eld"], makes: []) == nil, "choose: a host that makes nothing sends nothing")
check(AudioCodec.hostMakes == ["aac-eld"] && AudioCodec.devicePlays == ["aac-eld"] && AudioCodec.aacELD == "aac-eld", "the codec's name")
// AudioFormat: every field, none, and a later host's.
let format = AudioFormat(codec: "aac-eld", sampleRate: 48000, channels: 2, framesPerPacket: 480, primingFrames: 240, bitrate: 128_000,
                         epoch: 3, cookie: Data([0xF8, 0xF0, 0x21, 0x2C, 0x00]), source: AudioFormat.sourceApp, app: "Safari")
check(json(format) == #"{"app":"Safari","bitrate":128000,"channels":2,"codec":"aac-eld","cookie":"+PAhLAA=","epoch":3,"framesPerPacket":480,"primingFrames":240,"sampleRate":48000,"source":"app"}"#,
      "AudioFormat's keys, the cookie in base64: \(json(format))")
check(Wire.decode(AudioFormat.self, from: Wire.encode(format)) == format, "AudioFormat round-trips")
check(Wire.decode(AudioFormat.self, from: Data("{}".utf8)) == AudioFormat() && json(AudioFormat()) == "{}", "{} is an AudioFormat with nothing in it")
check(Wire.decode(AudioFormat.self, from: Data(#"{"codec":"opus","v":2,"channels":6}"#.utf8)) == AudioFormat(codec: "opus", channels: 6),
      "a later host's format: unknown keys skipped, an unknown codec kept as its string")
check(Wire.decode(AudioFormat.self, from: Data(#"{"cookie":"not base64!"}"#.utf8)) == nil, "a cookie that is not base64 does not decode")
check([AudioFormat.sourceApp, AudioFormat.sourceDesktop, AudioFormat.sourceTest] == ["app", "desktop", "test"], "the source's words")
// Send Audio (kind 16's settings, kind 17's change) and the audio note.
let withSound = StreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false,
                               directWireless: false, sendAudio: true, virtualDesktop: nil)
check(json(withSound).contains(#""sendAudio":true"#) && Wire.decode(StreamSettings.self, from: Wire.encode(withSound)) == withSound,
      "StreamSettings carries sendAudio and round-trips")
let noSound = StreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false,
                             directWireless: false, sendAudio: nil, virtualDesktop: nil)
check(!json(noSound).contains("sendAudio"), "a host without sound leaves sendAudio out")
check(Wire.decode(OldStreamSettings.self, from: Wire.encode(withSound))
      == OldStreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false, directWireless: false),
      "an older device reads the new settings and skips sendAudio")
check(Wire.decode(StreamSettings.self, from: Data(#"{"maxFPS":60,"bitrate":8000000,"captureScale":1,"prioritizeSpeed":true,"virtualDisplay":false,"directWireless":true}"#.utf8))?.sendAudio == nil,
      "an older host's settings: sendAudio nil (no row)")
check(HostSettingsChange(sendAudio: true).isEmpty == false && HostSettingsChange(token: 3).isEmpty && HostSettingsChange(sendAudio: false).isEmpty == false,
      "a change with only sendAudio is not empty")
check(HostSettingsChange(sendAudio: true).applied(to: noSound).sendAudio == true
      && HostSettingsChange(sendAudio: false).applied(to: withSound).sendAudio == false
      && HostSettingsChange(maxFPS: 60).applied(to: withSound).sendAudio == true,
      "applied(to:) lays sendAudio over the settings and keeps it when the change has none")
check(json(HostSettingsChange(token: 4, sendAudio: true)) == #"{"sendAudio":true,"token":4}"#, "kind 17 with Send Audio: \(json(HostSettingsChange(token: 4, sendAudio: true)))")
check(Wire.decode(OldChange.self, from: Wire.encode(HostSettingsChange(token: 4, sendAudio: true))) == OldChange(token: 4),
      "an older host reads a Send Audio change as an empty one")
let noted = HostSettingsState(settings: withSound, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false,
                              audioNote: "Couldn’t capture the sound of Safari: it did not start within 2 s.")
check(Wire.decode(HostSettingsState.self, from: Wire.encode(noted))?.audioNote == "Couldn’t capture the sound of Safari: it did not start within 2 s.",
      "kind 16's audio note round-trips")
check(!json(HostSettingsState(settings: withSound, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false)).contains("audioNote"),
      "no note, no key")
// Kind 16's sessionPaired (2026-10-29, the security scan's finding 8): whether this session's key is on
// the Mac's trust list, the one kind of session a host takes Direct Wireless from. Optional both ways:
// an older host leaves it out (nil: the device's switch works as before), an older device skips it.
struct OldState: Codable, Equatable { var settings: OldStreamSettings; var persistent: Bool; var virtualDisplayAvailable: Bool; var softwareEncoder: Bool }
for paired in [false, true] {
    let state = HostSettingsState(settings: withSound, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false,
                                  sessionPaired: paired)
    check(json(state).contains(#""sessionPaired":\#(paired)"#) && Wire.decode(HostSettingsState.self, from: Wire.encode(state)) == state,
          "kind 16 carries sessionPaired \(paired) and round-trips")
    check(Wire.decode(OldState.self, from: Wire.encode(state))
          == OldState(settings: OldStreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false,
                                                  directWireless: false),
                      persistent: true, virtualDisplayAvailable: true, softwareEncoder: false),
          "an older device reads it and skips sessionPaired \(paired)")
}
check(!json(HostSettingsState(settings: withSound, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false)).contains("sessionPaired"),
      "a state without it has no sessionPaired key")
check(Wire.decode(HostSettingsState.self, from: Data(#"{"settings":{"maxFPS":60,"bitrate":8000000,"captureScale":1,"prioritizeSpeed":true,"virtualDisplay":false,"directWireless":true},"persistent":true,"virtualDisplayAvailable":true,"softwareEncoder":false}"#.utf8))?.sessionPaired == nil,
      "an older host's state: sessionPaired nil")
// ClientStats' two fields.
let heard = ClientStats(fps: 60, frameAgeMs: 9, rttMs: 7, device: "iPad", frameAgeMaxMs: 20, rttMaxMs: 11, audioBehindMs: 42, audioLate: 3)
check(Wire.decode(ClientStats.self, from: Wire.encode(heard)) == heard && json(heard).contains(#""audioBehindMs":42"#) && json(heard).contains(#""audioLate":3"#),
      "ClientStats carries audioBehindMs and audioLate")
check(Wire.decode(OldClientStats.self, from: Wire.encode(heard))
      == OldClientStats(fps: 60, frameAgeMs: 9, rttMs: 7, device: "iPad", frameAgeMaxMs: 20, rttMaxMs: 11),
      "an older host reads the new stats and skips the sound's")
let quiet = ClientStats(fps: 60, frameAgeMs: 9, rttMs: 7, device: "iPad")
check(!json(quiet).contains("audio") && Wire.decode(ClientStats.self, from: Wire.encode(quiet))?.audioLate == nil,
      "a device that played no sound sends neither")
// Kind 43.
check(StreamMessageKind.audio.rawValue == 43 && StreamMessageKind(rawValue: 43) == .audio, "kind 43 is audio")
check(StreamMessageKind(rawValue: 29) == nil && StreamMessageKind(rawValue: 42) == nil && StreamMessageKind(rawValue: 44) == .keyframeRequest,
      "kinds 29 and 42 (#66's) are not this build's, and 44 is the keyframe request (32, #78's, is the clipboard: below)")

// Kind 32, the clipboard (docs/clipboard-plan.md), and the window list's `clipboard`: additive both
// ways. A host says it in its list, a device sends kind 32 only then, and an older peer skips the kind.
let shares = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.6", protocol: 1,
                        gestures: TrackpadGesture.generation, clipboard: ClipboardPolicy.generation)
check(json(shares).contains(#""clipboard":1"#) && json(shares).contains(#""gestures":1"#), "a list from a host that shares the clipboard says clipboard 1: \(json(shares))")
check(!json(takes).contains("clipboard") && !json(list).contains("clipboard"), "a list without it leaves the key out")
check(decodedOld != nil && decodedOld?.clipboard == nil, "an older host's list decodes, clipboard nil")
check(Wire.decode(WindowList.self, from: Wire.encode(shares)).map { $0.clipboard == 1 && $0.gestures == 1 } == true, "clipboard round-trips beside gestures")
check(StreamMessageKind.clipboard.rawValue == 32 && StreamMessageKind(rawValue: 32) == .clipboard, "kind 32 is the clipboard")
check([29, 30, 31, 33].allSatisfy { StreamMessageKind(rawValue: $0) == nil }, "29, 30, 31 and 33 not this build's")
let clip = Clipboard(text: "Hello")
check(json(clip) == #"{"text":"Hello"}"# && json(Clipboard()) == "{}" && json(Clipboard(stop: true)) == #"{"stop":true}"#, "kind 32's keys: \(json(clip))")
check(Wire.decode(Clipboard.self, from: Data(#"{"text":"a","image":"AQID","later":1}"#.utf8)) == Clipboard(text: "a", image: Data([1, 2, 3])),
      "pull request #66's shape decodes here, unknown keys skipped")
let clipboardMessage = StreamMessage(kind: .clipboard, timestamp: 1, isKeyframe: false, payload: Wire.encode(clip)).serialized()
check(StreamMessage.parseHeader(clipboardMessage)?.kind == .clipboard && clipboardMessage.count == StreamMessage.headerLength + Wire.encode(clip).count,
      "the clipboard's header parses, then the JSON")

// The window list's `keyRepeat` (#162's letters): a host that repeats a device's held key says 1 (set after
// the initializer, whose parameters stay as they were), and a device sends it a hardware keyboard's
// characters as keys only then. Additive: an older host's list decodes with it nil, and an older device's
// reader skips the key.
var repeats = shares
repeats.keyRepeat = 1
check(json(repeats).contains(#""keyRepeat":1"#), "a list from a host that repeats held keys says keyRepeat 1: \(json(repeats))")
check(!json(shares).contains("keyRepeat") && !json(list).contains("keyRepeat") && shares.keyRepeat == nil,
      "a list without it (the initializer's) leaves the key out")
check(decodedOld != nil && decodedOld?.keyRepeat == nil, "an older host's list decodes, keyRepeat nil")
check(Wire.decode(WindowList.self, from: Wire.encode(repeats)).map { $0.keyRepeat == 1 && $0.clipboard == 1 && $0.gestures == 1 } == true,
      "keyRepeat round-trips beside clipboard and gestures")
struct ReaderBefore: Decodable { var macName: String; var gestures: Int?; var clipboard: Int? }
check(Wire.decode(ReaderBefore.self, from: Wire.encode(repeats)).map { $0.macName == "Mac mini" && $0.clipboard == 1 } == true,
      "a reader from before it skips keyRepeat")

// The window list's `desktopDisplays` and `desktopDisplay` (#91's tapping method), and kind 47: a host with
// two displays or more says how many and which the Desktop streams, and a device sends kind 47 (empty) for
// the next only then. Additive: an older host's list decodes with both nil, an older reader skips the keys,
// and an older host skips the kind.
var displays = repeats
displays.desktopDisplays = 2
displays.desktopDisplay = 1
check(json(displays).contains(#""desktopDisplays":2"#) && json(displays).contains(#""desktopDisplay":1"#),
      "a list from a host with two displays says desktopDisplays 2 and desktopDisplay 1: \(json(displays))")
check(!json(repeats).contains("desktopDisplay") && repeats.desktopDisplays == nil && repeats.desktopDisplay == nil,
      "a list without them (the initializer's) leaves the keys out")
check(decodedOld != nil && decodedOld?.desktopDisplays == nil && decodedOld?.desktopDisplay == nil, "an older host's list decodes, both nil")
check(Wire.decode(WindowList.self, from: Wire.encode(displays)).map { $0.desktopDisplays == 2 && $0.desktopDisplay == 1 && $0.keyRepeat == 1 } == true,
      "desktopDisplays and desktopDisplay round-trip beside keyRepeat")
check(Wire.decode(ReaderBefore.self, from: Wire.encode(displays)).map { $0.macName == "Mac mini" && $0.clipboard == 1 } == true,
      "a reader from before them skips desktopDisplays and desktopDisplay")
// Their names (docs/virtual-desktop-plan.md phase 1, PR #296's field): VoiceOver's "Display 2 of 3, DELL
// U2723QE". Additive as the two: left out when nil, nil from an older host, skipped by an older reader.
var named = displays
named.desktopDisplayNames = ["Built-in Retina Display", "DELL U2723QE"]
check(json(named).contains(#""desktopDisplayNames":["Built-in Retina Display","DELL U2723QE"]"#),
      "a list with the stops' names says them in order: \(json(named))")
check(!json(displays).contains("desktopDisplayNames") && displays.desktopDisplayNames == nil, "a list without names leaves the key out")
check(decodedOld != nil && decodedOld?.desktopDisplayNames == nil, "an older host's list decodes, the names nil")
check(Wire.decode(WindowList.self, from: Wire.encode(named)).map {
          $0.desktopDisplayNames == ["Built-in Retina Display", "DELL U2723QE"] && $0.desktopDisplays == 2 && $0.desktopDisplay == 1
      } == true, "the names round-trip beside desktopDisplays and desktopDisplay")
struct ReaderOf173: Decodable { var macName: String; var desktopDisplays: Int?; var desktopDisplay: Int? }
check(Wire.decode(ReaderOf173.self, from: Wire.encode(named)).map { $0.desktopDisplays == 2 && $0.desktopDisplay == 1 } == true,
      "a reader of #173's two fields alone skips the names and reads the two")
check(Wire.decode(ReaderBefore.self, from: Wire.encode(named)).map { $0.macName == "Mac mini" && $0.clipboard == 1 } == true,
      "a reader from before them skips all three")
check(StreamMessageKind.nextDisplay.rawValue == 47 && StreamMessageKind(rawValue: 47) == .nextDisplay, "kind 47 is the next display")
check(StreamMessageKind(rawValue: 45) == nil && StreamMessageKind(rawValue: 46) == nil,
      "45 and 46 not this build's (open pull requests' microphone, pen and camera)")
let nextMessage = StreamMessage(kind: .nextDisplay, timestamp: 1, isKeyframe: false, payload: Data()).serialized()
check(StreamMessage.parseHeader(nextMessage).map { $0.kind == .nextDisplay && $0.payloadLength == 0 } == true
      && nextMessage[nextMessage.startIndex] == 47, "kind 47's header parses, its payload empty")

// Phase 2b of docs/virtual-desktop-plan.md (as revised 2026-11-18): the Virtual Desktop's fields, each optional and
// additive. The window list's `desktopVirtual` (its stop's number); kind 16's `settings.virtualDesktop` (the switch)
// and `virtualDesktopState` (the connection's view: available, note, shown, size, hz); kind 17's `virtualDesktop`;
// kind 9's `room`. Each left out when nil, nil from a peer before 2b, and skipped by 0.6.2's readers (the `…Of062`
// types: the fields as v0.6.2 shipped them).
var virtualStop = named
virtualStop.desktopDisplays = 3
virtualStop.desktopDisplay = 3
virtualStop.desktopDisplayNames = ["Built-in Retina Display", "DELL U2723QE", "Sill Desktop"]
virtualStop.desktopVirtual = 3
check(json(virtualStop).contains(#""desktopVirtual":3"#), "a list with the Virtual Desktop's stop says which: \(json(virtualStop))")
check(!json(named).contains("desktopVirtual") && named.desktopVirtual == nil, "a list without it (the initializer's) leaves the key out")
check(decodedOld != nil && decodedOld?.desktopVirtual == nil, "an older host's list decodes, desktopVirtual nil")
check(Wire.decode(WindowList.self, from: Wire.encode(virtualStop)).map { $0.desktopVirtual == 3 && $0.desktopDisplays == 3 && $0.desktopDisplay == 3 } == true,
      "desktopVirtual round-trips beside the stops")
struct ListOf062: Decodable { var macName: String; var desktopDisplays: Int?; var desktopDisplay: Int?; var desktopDisplayNames: [String]? }
check(Wire.decode(ListOf062.self, from: Wire.encode(virtualStop)).map {
          $0.desktopDisplays == 3 && $0.desktopDisplay == 3 && $0.desktopDisplayNames?.last == "Sill Desktop"
      } == true, "a 0.6.2 device skips desktopVirtual and reads the stop as Desktop 3, with its name")
let withVD = StreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: true,
                            directWireless: false, sendAudio: true, virtualDesktop: true)
check(json(withVD).contains(#""virtualDesktop":true"#) && Wire.decode(StreamSettings.self, from: Wire.encode(withVD)) == withVD,
      "kind 16's settings carry virtualDesktop and round-trip")
check(!json(withSound).contains("virtualDesktop") && Wire.decode(StreamSettings.self, from: Wire.encode(withSound))?.virtualDesktop == nil,
      "a host without it leaves the key out, and a device reads nil (no row)")
check(Wire.decode(StreamSettings.self, from: Wire.encode(StreamSettings(maxFPS: 60, bitrate: 1, captureScale: 1, prioritizeSpeed: true,
                                                                          virtualDisplay: false, directWireless: nil, sendAudio: nil,
                                                                          virtualDesktop: false)))?.virtualDesktop == false,
      "off is said, not left out")
struct SettingsOf062: Decodable, Equatable {
    var maxFPS: Int; var bitrate: Int; var captureScale: Double; var prioritizeSpeed: Bool; var virtualDisplay: Bool
    var directWireless: Bool?; var sendAudio: Bool?
}
check(Wire.decode(SettingsOf062.self, from: Wire.encode(withVD))
      == SettingsOf062(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: true, directWireless: false, sendAudio: true),
      "a 0.6.2 device reads the settings and skips virtualDesktop")
var vdState = HostSettingsState(settings: withVD, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false, sessionPaired: true)
vdState.virtualDesktopState = VirtualDesktopState(available: true, shown: true, size: VirtualDesktopState.size(widthPt: 1218, heightPt: 800, scale: 2), hz: 60)
check(json(vdState).contains(#""virtualDesktopState":{"available":true,"hz":60,"shown":true,"size":"1218x800@2"}"#),
      "kind 16 carries the connection's Virtual Desktop: \(json(vdState))")
check(Wire.decode(HostSettingsState.self, from: Wire.encode(vdState)) == vdState, "…and round-trips")
check(Wire.decode(OldState.self, from: Wire.encode(vdState))
      == OldState(settings: OldStreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: true,
                                              directWireless: false),
                  persistent: true, virtualDisplayAvailable: true, softwareEncoder: false),
      "an older device reads it and skips the Virtual Desktop's state and switch")
check(!json(HostSettingsState(settings: withSound, persistent: true, virtualDisplayAvailable: true, softwareEncoder: false)).contains("virtualDesktop"),
      "a host without it: neither key")
let unavailable = VirtualDesktopState(available: false, note: "Needs Screen Recording", shown: false)
check(json(unavailable) == #"{"available":false,"note":"Needs Screen Recording","shown":false}"#, "a state with a note, nothing else: \(json(unavailable))")
check(Wire.decode(VirtualDesktopState.self, from: Data(#"{"available":true,"shown":false,"sizes":["device"],"rates":[60],"later":1}"#.utf8))
      == VirtualDesktopState(available: true, shown: false), "a later host's state decodes, phase 3's sizes and rates skipped")
check(Wire.decode(VirtualDesktopState.self, from: Data(#"{"available":true}"#.utf8)) == nil
      && Wire.decode(VirtualDesktopState.self, from: Data(#"{"shown":true}"#.utf8)) == nil, "available and shown are said by every host that sends it")
check(VirtualDesktopState.size(widthPt: 1218, heightPt: 800, scale: 2) == "1218x800@2" && VirtualDesktopState.size(widthPt: 800, heightPt: 1218, scale: 1) == "800x1218@1",
      "a size's words: points, then the scale")
check(VirtualDesktopState.parse("1218x800@2").map { $0.widthPt == 1218 && $0.heightPt == 800 && $0.scale == 2 } == true
      && VirtualDesktopState.parse(VirtualDesktopState.size(widthPt: 3840, heightPt: 2160, scale: 1)).map { $0.widthPt == 3840 && $0.scale == 1 } == true,
      "a size read back")
check(["", "device", "main", "1218x800", "x800@2", "1218x@2", "1218x800@0", "1218x-800@2", "0x800@2", "1218×800@2", "1218x800@2@2", "1x2x3@2",
       "1218x800@", " 1218x800@2"].allSatisfy { VirtualDesktopState.parse($0) == nil }, "anything else is no size")
check(HostSettingsChange(virtualDesktop: true).isEmpty == false && HostSettingsChange(virtualDesktop: false).isEmpty == false,
      "a change with only virtualDesktop is not empty")
check(HostSettingsChange(virtualDesktop: true).applied(to: withSound).virtualDesktop == true
      && HostSettingsChange(virtualDesktop: false).applied(to: withVD).virtualDesktop == false
      && HostSettingsChange(maxFPS: 60).applied(to: withVD).virtualDesktop == true,
      "applied(to:) lays virtualDesktop over the settings and keeps it when the change has none")
check(json(HostSettingsChange(token: 5, virtualDesktop: true)) == #"{"token":5,"virtualDesktop":true}"#,
      "kind 17 with the Virtual Desktop: \(json(HostSettingsChange(token: 5, virtualDesktop: true)))")
check(Wire.decode(OldChange.self, from: Wire.encode(HostSettingsChange(token: 5, virtualDesktop: true))) == OldChange(token: 5),
      "an older host reads it as an empty change: a device sends it only to a host that reported the switch")
let roomy = Viewport(width: 1376, height: 950, scale: nil, fps: 120, room: ViewportRoom(width: 1376, height: 1032))
check(json(roomy) == #"{"fps":120,"height":950,"room":{"height":1032,"width":1376},"width":1376}"#, "kind 9 with the room: \(json(roomy))")
check(Wire.decode(Viewport.self, from: Wire.encode(roomy)) == roomy, "…round-trips")
check(!json(Viewport(width: 1376, height: 950, scale: nil, fps: 120)).contains("room"), "no room, no key (every device before 2b)")
struct ViewportOf062: Decodable, Equatable { var width: Double; var height: Double; var scale: Double?; var localCursor: Bool?; var fps: Int? }
check(Wire.decode(ViewportOf062.self, from: Wire.encode(roomy)) == ViewportOf062(width: 1376, height: 950, scale: nil, localCursor: nil, fps: 120),
      "a 0.6.2 host reads the viewport and skips the room")
check(Wire.decode(Viewport.self, from: Data(#"{"width":1133,"height":744,"fps":60}"#.utf8)).map { $0.room == nil && $0.width == 1133 } == true,
      "a 0.6.2 device's viewport: no room")

// For H4: what cb0ec55's StreamProtocol must read.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
if let out {
    let payloads: [String: String] = [
        "goodbyeUpdate": String(decoding: Wire.encode(update), as: UTF8.self),
        "goodbyeLater": later,
        "windowList": String(decoding: Wire.encode(list), as: UTF8.self),
        "helloMessage": helloMessage.base64EncodedString(),
        "gestureMessage": gestureMessage.base64EncodedString(),
        "windowListGestures": String(decoding: Wire.encode(takes), as: UTF8.self),
        "windowListClipboard": String(decoding: Wire.encode(shares), as: UTF8.self),
        "windowListKeyRepeat": String(decoding: Wire.encode(repeats), as: UTF8.self),
        "clipboardMessage": clipboardMessage.base64EncodedString(),
        "windowListDesktopStops": String(decoding: Wire.encode(named), as: UTF8.self),
        "nextDisplayMessage": nextMessage.base64EncodedString(),
    ]
    try! JSONSerialization.data(withJSONObject: payloads, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: out))
}
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
