// H3 (step 1): the protocol's new values, compiled with StreamProtocol's sources as one module.
// HomeDoorTXT (build, parse, an unknown value → required; the dictionary and NWTXTRecord forms);
// kinds 19, 20 and 22 as docs/home-pairing-plan.md §3.1's examples show them on the wire; the
// RemoteTLS parameters overload for the home door.
import Foundation
import Network
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
typealias X = HomeDoorTXT
func json<T: Encodable>(_ v: T) -> String { String(data: Wire.encode(v), encoding: .utf8)! }
// JSONEncoder (Wire.encode) writes keys in no fixed order (it varies with the process's hash seed),
// so an encoding is compared with the plan's example as JSON: the same keys, the same values.
func canonical(_ text: String) -> String? {
    guard let o = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
          let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return nil }
    return String(data: d, encoding: .utf8)
}
func same(_ got: String, _ want: String) -> Bool {
    guard let a = canonical(got), let b = canonical(want) else { return false }
    return a == b          // sorted keys; true stays true, never 1
}
check("canonical JSON tells true from 1 and ignores key order", !same(#"{"a":true}"#, #"{"a":1}"#) && same(#"{"a":1,"b":2}"#, #"{"b":2,"a":1}"#))

// MARK: HomeDoorTXT

check("the key is p", X.key == "p")
check("build: 1 with Require pairing on, 0 with it off", X.value(requirePairing: true) == "1" && X.value(requirePairing: false) == "0")
check("parse: no p is a plain door (Sill.app before this change, SillHost without --pairing)", X.door([:]) == .plain && X.door(["r": "oaKjpKWmL4V47Ctm"]) == .plain)
check("parse: p=1 requires pairing, p=0 is open", X.door(["r": "t", "p": "1"]) == .pairingRequired && X.door(["r": "t", "p": "0"]) == .open)
check("parse: any other value reads as 1, the safe side", ["", "2", "yes", "true", "no", "false", " 0", "0 ", "00", "O", "-0", "0x0", "\u{0660}"].allSatisfy { X.door(["p": $0]) == .pairingRequired })
check("parse: keys are case-insensitive (P)", X.door(["P": "0"]) == .open && X.door(["P": "1"]) == .pairingRequired)
check("parse: p before P", X.door(["p": "1", "P": "0"]) == .pairingRequired && X.door(["p": "0", "P": "1"]) == .open)
check("parse: other keys never matter", X.door(["q": "0", "pp": "0", "r": "0"]) == .plain)
check("round trip: the value built for each setting reads back as that door",
      X.door([X.key: X.value(requirePairing: true)]) == .pairingRequired && X.door([X.key: X.value(requirePairing: false)]) == .open)

// The record a device receives (NWTXTRecord), entry by entry.
check("NWTXTRecord: r and p=1", X.door(NWTXTRecord(["r": "oaKjpKWmL4V47Ctm", "p": "1"])) == .pairingRequired)
check("NWTXTRecord: p=0", X.door(NWTXTRecord(["r": "oaKjpKWmL4V47Ctm", "p": "0"])) == .open)
check("NWTXTRecord: r alone is plain", X.door(NWTXTRecord(["r": "oaKjpKWmL4V47Ctm"])) == .plain && X.door(NWTXTRecord([String: String]())) == .plain)
var valueless = NWTXTRecord(["r": "x"]); _ = valueless.setEntry(.none, for: "p")
check("NWTXTRecord: a p without a value (which `dictionary` leaves out) reads as 1, not plain",
      X.door(valueless) == .pairingRequired && valueless.dictionary["p"] == nil)
var empty = NWTXTRecord(["r": "x"]); _ = empty.setEntry(.empty, for: "p")
check("NWTXTRecord: p= (empty) reads as 1", X.door(empty) == .pairingRequired)
check("NWTXTRecord: P=0 (keys case-insensitive)", X.door(NWTXTRecord(["P": "0"])) == .open)
let wire = NWTXTRecord(Data([3]) + Data("p=0".utf8) + Data([16]) + Data("r=oaKjpKWmL4V47C".utf8))
check("NWTXTRecord from the wire's bytes (p=0, r=…)", X.door(wire) == .open)
let wireBool = NWTXTRecord(Data([1]) + Data("p".utf8))
check("NWTXTRecord from the wire's bytes: a bare p reads as 1", X.door(wireBool) == .pairingRequired)
check("NWTXTRecord: another value reads as 1", X.door(NWTXTRecord(["p": "2"])) == .pairingRequired)

// MARK: Kinds 19, 20, 22: the plan's examples, byte for byte

let ask = PairRequest(method: PairRequest.ask, proof: "", name: "iPad", model: "iPad14,1")
check("kind 19 ask: " + json(ask), same(json(ask), #"{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1"}"#))
let askCable = PairRequest(method: PairRequest.ask, proof: "", name: "iPad", model: "iPad14,1", cable: true)
check("kind 19 ask on the cable: " + json(askCable), same(json(askCable), #"{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1","cable":true}"#))
let qr = PairRequest(method: PairRequest.qr, proof: "AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo", name: "iPad", model: "iPad14,1")
check("kind 19 qr, as today: " + json(qr), same(json(qr), #"{"v":1,"method":"qr","proof":"AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo","name":"iPad","model":"iPad14,1"}"#))
let rk = Base64URL.encode(Data(repeating: 0x11, count: 32))
let cableOK = PairResult(ok: true, macID: "A3C5HR4RBV67YR21", name: "Mac mini", recognitionKey: rk, method: PairResult.cable)
check("kind 20 over the cable: " + json(cableOK),
      same(json(cableOK), #"{"ok":true,"method":"cable","macID":"A3C5HR4RBV67YR21","name":"Mac mini","recognitionKey":"ERERERERERERERERERERERERERERERERERERERERERE"}"#))
check("kind 20 shown, openOnMac, locked", same(json(PairResult(ok: false, reason: PairResult.shown)), #"{"ok":false,"reason":"shown"}"#)
      && same(json(PairResult(ok: false, reason: PairResult.openOnMac)), #"{"ok":false,"reason":"openOnMac"}"#)
      && same(json(PairResult(ok: false, reason: PairResult.locked)), #"{"ok":false,"reason":"locked"}"#))
check("kind 22 pairingRequired: " + json(Goodbye(reason: Goodbye.pairingRequired)), same(json(Goodbye(reason: Goodbye.pairingRequired)), #"{"reason":"pairingRequired"}"#))
check("the new values", PairRequest.ask == "ask" && PairResult.cable == "cable" && PairResult.shown == "shown" && PairResult.openOnMac == "openOnMac"
      && PairResult.locked == "locked" && Goodbye.pairingRequired == "pairingRequired")

// Decoding them.
let dCable = Wire.decode(PairRequest.self, from: Data(#"{"v":1,"method":"ask","proof":"","name":"iPad","model":"iPad14,1","cable":true}"#.utf8))
check("decode kind 19: cable true", dCable?.cable == true && dCable?.method == "ask" && dCable?.proof == "")
check("decode kind 19: no cable is nil; cable false is false",
      Wire.decode(PairRequest.self, from: Data(#"{"v":1,"method":"ask","proof":"","name":"iPad"}"#.utf8))?.cable == nil
      && Wire.decode(PairRequest.self, from: Data(#"{"v":1,"method":"ask","proof":"","name":"iPad","cable":false}"#.utf8))?.cable == false)
check("decode kind 19: a cable that is not a Bool fails the decode (never retyped)",
      Wire.decode(PairRequest.self, from: Data(#"{"v":1,"method":"ask","proof":"","name":"iPad","cable":"yes"}"#.utf8)) == nil)
let dOK = Wire.decode(PairResult.self, from: Data(#"{"ok":true,"method":"cable","macID":"A3C5HR4RBV67YR21","name":"Mac mini","recognitionKey":"x"}"#.utf8))
check("decode kind 20: method cable, no proof", dOK?.method == "cable" && dOK?.ok == true && dOK?.proof == nil)
check("decode kind 20: no method is nil (every ok until now)", Wire.decode(PairResult.self, from: Data(#"{"ok":true,"proof":"p","macID":"m"}"#.utf8))?.method == nil)
check("decode kind 20: an unknown method is a string, not a failure", Wire.decode(PairResult.self, from: Data(#"{"ok":true,"method":"icloud"}"#.utf8))?.method == "icloud")
check("decode kind 22: pairingRequired", Wire.decode(Goodbye.self, from: Data(#"{"reason":"pairingRequired"}"#.utf8))?.reason == Goodbye.pairingRequired)
check("the old inits compile and leave the new fields nil", PairRequest(method: "qr", proof: "", name: "iPad", model: nil).cable == nil
      && PairResult(ok: false, reason: PairResult.code, triesLeft: 4).method == nil
      && PairResult(ok: false, reason: PairResult.code, triesLeft: 4).message == nil)

// MARK: What the first public build freezes of pairing (the compatibility floor, CLAUDE.md)

// A later host adds a reason only with its own words (`message`); every kind 20 of this build
// carries none, so each is byte for byte what it was.
check("kind 20 without a message has no message key: shown, stopped, code",
      !json(PairResult(ok: false, reason: PairResult.shown)).contains("message")
      && !json(PairResult(ok: false, reason: PairResult.stopped)).contains("message")
      && same(json(PairResult(ok: false, reason: PairResult.code, triesLeft: 4)), #"{"ok":false,"reason":"code","triesLeft":4}"#))
let later = PairResult(ok: false, reason: "approvalNeeded", message: "Approve this iPad on Mac mini, then tap it again.")
check("kind 20 with a message: " + json(later),
      same(json(later), #"{"ok":false,"reason":"approvalNeeded","message":"Approve this iPad on Mac mini, then tap it again."}"#))
check("decode kind 20: a message is kept; none is nil",
      Wire.decode(PairResult.self, from: Data(#"{"ok":false,"reason":"approvalNeeded","message":"Approve it."}"#.utf8))?.message == "Approve it."
      && Wire.decode(PairResult.self, from: Data(#"{"ok":false,"reason":"shown"}"#.utf8))?.message == nil)
check("the reasons this build words itself: code, closed, expired, stopped, busy, shown, openOnMac, locked",
      PairResult.knownReasons == ["code", "closed", "expired", "stopped", "busy", "shown", "openOnMac", "locked"])
check("a reason this build does not know: the Mac's words, as they are", later.unknownReasonMessage == "Approve this iPad on Mac mini, then tap it again.")
check("a known reason never shows the Mac's message, whatever it says",
      PairResult.knownReasons.allSatisfy { PairResult(ok: false, reason: $0, message: "Something else.").unknownReasonMessage == nil })
check("an unknown reason without a message, or with nothing printable: nil (the device's own words)",
      PairResult(ok: false, reason: "approvalNeeded").unknownReasonMessage == nil
      && PairResult(ok: false, reason: "approvalNeeded", message: " \u{202E}\u{0007}\n ").unknownReasonMessage == nil)
check("no reason at all is unknown too", PairResult(ok: false, message: "Try again later.").unknownReasonMessage == "Try again later.")
check("an ok never shows a message", PairResult(ok: true, method: PairResult.cable, message: "Hi.").unknownReasonMessage == nil)
check("the Mac's words are cleaned as a goodbye's: one line, no controls or bidi overrides, at most 300 characters",
      PairResult(ok: false, reason: "later", message: "Line one\nline\u{202E} two\u{0007}.").unknownReasonMessage == "Line one line two."
      && PairResult(ok: false, reason: "later", message: String(repeating: "a", count: 400)).unknownReasonMessage?.count == 300)

// MARK: RemoteTLS parameters for the home door

func tcp(_ p: NWParameters) -> NWProtocolTCP.Options? { p.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options }
let homeTCP = NWProtocolTCP.Options()
homeTCP.noDelay = true; homeTCP.enableKeepalive = true; homeTCP.keepaliveIdle = 5; homeTCP.keepaliveInterval = 2; homeTCP.keepaliveCount = 3
let homeMac = RemoteTLS.parameters(tls: NWProtocolTLS.Options(), tcp: homeTCP, peerToPeer: true)
check("home door (Direct Wireless on): peer-to-peer, the video class, TLS", homeMac.includePeerToPeer && homeMac.serviceClass == .interactiveVideo
      && homeMac.defaultProtocolStack.applicationProtocols.contains { $0 is NWProtocolTLS.Options })
check("home door: the caller's TCP options, no connectionDropTime (home clients keep their 4 s drain)",
      tcp(homeMac).map { $0.noDelay && $0.enableKeepalive && $0.keepaliveIdle == 5 && $0.keepaliveInterval == 2 && $0.keepaliveCount == 3 && $0.connectionDropTime == 0 } == true)
let deviceTCP = NWProtocolTCP.Options(); deviceTCP.noDelay = true
let device = RemoteTLS.parameters(tls: NWProtocolTLS.Options(), tcp: deviceTCP, peerToPeer: false)
check("a device's network row: no peer-to-peer, the video class, no Nagle", !device.includePeerToPeer && device.serviceClass == .interactiveVideo && tcp(device)?.noDelay == true)
let remote = RemoteTLS.parameters(tls: NWProtocolTLS.Options(), dialing: false)
let remoteDial = RemoteTLS.parameters(tls: NWProtocolTLS.Options(), dialing: true)
check("the remote door's parameters as before: never peer-to-peer, the video class, drop after 15 s, keepalive 5/2/3",
      !remote.includePeerToPeer && remote.serviceClass == .interactiveVideo
      && tcp(remote).map { $0.noDelay && $0.connectionDropTime == 15 && $0.keepaliveIdle == 5 && $0.keepaliveInterval == 2 && $0.keepaliveCount == 3 && $0.connectionTimeout == 0 } == true)
check("the remote door's dialing parameters as before: a 10 s connect timeout", tcp(remoteDial)?.connectionTimeout == 10 && !remoteDial.includePeerToPeer)

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
