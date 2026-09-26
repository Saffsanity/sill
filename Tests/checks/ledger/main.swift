// H2: the device ledger (iOSClient/HostSettingsLedger.swift) and the wire types
// (Sources/StreamProtocol/HostSettings.swift), compiled together as one module:
//
//   swiftc -O Sources/StreamProtocol/HostSettings.swift iOSClient/HostSettingsLedger.swift \
//       Tests/checks/ledger/main.swift -o .build/checks/ledger/check && .build/checks/ledger/check [runs]
//
// Ported from the design workflow's d0-protocol-check.swift: deterministic scenarios first, then a
// random model of the host (main actor + one serial network queue, per-connection FIFO TCP) and up
// to three devices with random interleavings — device picks, Mac-menu edits, capability changes,
// disconnects with partially delivered in-flight messages, reconnects, slow hosts that trip the
// device timeout, and a buggy client sending invalid values. Every message crosses a real JSON
// encode/decode. After each run the system is drained and the invariants are checked.
import Foundation

func fail(_ what: String) -> Never { print("FAIL: \(what)"); exit(1) }
func check(_ ok: Bool, _ what: String) { print((ok ? "ok   " : "FAIL ") + what); if !ok { exit(1) } }

let encoder = JSONEncoder()
let decoder = JSONDecoder()
func enc<T: Encodable>(_ v: T) -> Data { try! encoder.encode(v) }
func dec<T: Decodable>(_ t: T.Type, _ d: Data) -> T? { try? decoder.decode(t, from: d) }

/// The host's acceptance rule, as Sources/SillHost/DeviceSettings.swift has it (that file needs
/// SillHostCore, so the model carries a copy).
func accepted(_ c: HostSettingsChange, virtualDisplayAvailable: Bool) -> HostSettingsChange {
    var ok = HostSettingsChange(prioritizeSpeed: c.prioritizeSpeed, directWireless: c.directWireless)
    if let v = c.maxFPS, SettingsChoices.maxFPS.contains(v) { ok.maxFPS = v }
    if let v = c.bitrate, SettingsChoices.bitrate.contains(v) { ok.bitrate = v }
    if let v = c.captureScale, SettingsChoices.captureScale.contains(v) { ok.captureScale = v }
    if let v = c.virtualDisplay, !v || virtualDisplayAvailable { ok.virtualDisplay = v }
    return ok
}

// MARK: - Scenarios (deterministic)

let base = StreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false, directWireless: false)
func st(_ s: StreamSettings, answering: Int? = nil, vd: Bool = true, note: String? = nil) -> HostSettingsState {
    HostSettingsState(settings: s, persistent: true, virtualDisplayAvailable: vd, virtualDisplayNote: note, softwareEncoder: false,
                      stream: RunningStream(width: 3024, height: 1898, fps: 60, mbps: 15, onVirtualDisplay: false), answering: answering)
}

do {   // no state yet (an older Mac, or not arrived): nothing is sent
    var l = SettingsLedger()
    check(l.pick(HostSettingsChange(maxFPS: 60), token: 1, now: 0) == nil && l.pending.isEmpty && l.displayed == nil,
          "no state on this connection: a pick sends nothing and shows nothing")
}
do {   // a pick moves at once and is cleared by its answer
    var l = SettingsLedger(); _ = l.receive(st(base))
    let out = l.pick(HostSettingsChange(bitrate: 25_000_000), token: 1, now: 10)
    check(out == HostSettingsChange(token: 1, bitrate: 25_000_000), "a pick sends exactly its field with its token")
    check(l.displayed?.bitrate == 25_000_000 && l.pendingSince(.bitrate) == 10, "the pick shows at once, pending since it was sent")
    var h = base; h.bitrate = 25_000_000
    check(l.receive(st(h)).isEmpty && l.pending[.bitrate] != nil, "the broadcast of the new target keeps the pick pending")
    check(l.receive(st(h, answering: 1)).isEmpty && l.pending.isEmpty && l.displayed?.bitrate == 25_000_000,
          "its answer clears it and the value stays")
}
do {   // picking what is shown sends nothing
    var l = SettingsLedger(); _ = l.receive(st(base))
    check(l.pick(HostSettingsChange(maxFPS: 120), token: 1, now: 0) == nil && l.pending.isEmpty, "picking the shown value sends nothing")
    let mixed = l.pick(HostSettingsChange(maxFPS: 120, bitrate: 8_000_000), token: 2, now: 0)
    check(mixed == HostSettingsChange(token: 2, bitrate: 8_000_000), "a two-field pick sends only the field that differs")
}
do {   // double tap 60 → 120 → 60 before any answer: never shows 120
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(maxFPS: 60), token: 1, now: 0)
    _ = l.pick(HostSettingsChange(maxFPS: 120), token: 2, now: 0.1)
    _ = l.pick(HostSettingsChange(maxFPS: 60), token: 3, now: 0.2)
    var h = base; h.maxFPS = 60; _ = l.receive(st(h)); _ = l.receive(st(h, answering: 1))
    check(l.displayed?.maxFPS == 60, "60 → 120 → 60: the answer to 1 keeps the latest pick")
    h.maxFPS = 120; _ = l.receive(st(h)); let r2 = l.receive(st(h, answering: 2))
    check(l.displayed?.maxFPS == 60 && r2.isEmpty, "60 → 120 → 60: the answer to 2 (120) does not show 120, and is no refusal")
    h.maxFPS = 60; _ = l.receive(st(h)); _ = l.receive(st(h, answering: 3))
    check(l.pending.isEmpty && l.displayed?.maxFPS == 60, "60 → 120 → 60: the answer to 3 settles on 60")
}
do {   // tapping back to the host's value while a pick is pending sends
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(maxFPS: 60), token: 1, now: 0)
    let back = l.pick(HostSettingsChange(maxFPS: 120), token: 2, now: 0.1)
    check(back == HostSettingsChange(token: 2, maxFPS: 120), "back to the host's value while 60 is pending is sent")
    check(l.pick(HostSettingsChange(maxFPS: 120), token: 3, now: 0.2) == nil, "the same value again sends nothing")
}
do {   // a refused toggle snaps back, is reported, and the note says why
    var l = SettingsLedger(); _ = l.receive(st(base, vd: false, note: "Start SillHost with --virtual-display to use it."))
    _ = l.pick(HostSettingsChange(virtualDisplay: true), token: 1, now: 0)
    check(l.displayed?.virtualDisplay == true, "the toggle moves at once")
    let refused = l.receive(st(base, answering: 1, vd: false, note: "Start SillHost with --virtual-display to use it."))
    check(refused == [.virtualDisplay] && l.displayed?.virtualDisplay == false && l.host?.virtualDisplayNote != nil,
          "the refused toggle returns, is reported, and the host's reason is there")
}
do {   // one refused field of two: only it goes back
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(bitrate: 8_000_000, virtualDisplay: true), token: 1, now: 0)
    var h = base; h.bitrate = 8_000_000
    let refused = l.receive(st(h, answering: 1))
    check(refused == [.virtualDisplay] && l.displayed?.bitrate == 8_000_000 && l.displayed?.virtualDisplay == false,
          "a partial refusal: the accepted field stays, the refused one goes back")
}
do {   // a broadcast from elsewhere keeps a pending pick, a later answer settles
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(captureScale: 1), token: 1, now: 0)
    var other = base; other.bitrate = 40_000_000          // the Mac's menu changed another field
    _ = l.receive(st(other))
    check(l.displayed?.captureScale == 1 && l.displayed?.bitrate == 40_000_000, "a broadcast keeps a pending pick and shows the other change")
}
do {   // expiry at the timeout, and a late answer still applies
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(bitrate: 25_000_000), token: 1, now: 100)
    check(!l.expire(now: 104, timeout: 4) && l.pending[.bitrate] != nil, "not expired at exactly the timeout")
    check(l.expire(now: 104.01, timeout: 4) && l.pending.isEmpty && l.displayed?.bitrate == 15_000_000, "expired just past it: back to the Mac's value")
    var h = base; h.bitrate = 25_000_000
    check(l.receive(st(h, answering: 1)).isEmpty && l.displayed?.bitrate == 25_000_000, "a late answer still applies, and is no refusal")
}
do {   // reset forgets everything
    var l = SettingsLedger(); _ = l.receive(st(base)); _ = l.pick(HostSettingsChange(maxFPS: 60), token: 1, now: 0)
    l.reset()
    check(l == SettingsLedger(), "reset forgets the state and the picks")
}
// Direct Wireless Connection, the sixth field (optional: an older host does not report it).
do {   // a state without the key decodes as nil, and rule 9: nothing about it is ever sent to that host
    let old = #"{"settings":{"maxFPS":120,"bitrate":15000000,"captureScale":2,"prioritizeSpeed":false,"virtualDisplay":false},"persistent":true,"virtualDisplayAvailable":true,"softwareEncoder":false}"#
    guard let s = dec(HostSettingsState.self, Data(old.utf8)) else { fail("an older host's state did not decode") }
    check(s.settings.directWireless == nil, "an older host's state (no directWireless key) decodes with the field nil")
    var l = SettingsLedger(); _ = l.receive(s)
    check(l.pick(HostSettingsChange(directWireless: true), token: 1, now: 0) == nil && l.pending.isEmpty && l.displayed?.directWireless == nil,
          "rule 9: pick(directWireless: true) against an older host sends nothing and shows nothing")
    check(l.pick(HostSettingsChange(directWireless: false), token: 2, now: 0) == nil, "rule 9: nor does false")
    let mixed = l.pick(HostSettingsChange(bitrate: 25_000_000, directWireless: true), token: 3, now: 0)
    check(mixed == HostSettingsChange(token: 3, bitrate: 25_000_000) && l.pending[.directWireless] == nil,
          "rule 9: a two-field pick to an older host sends only the field it reported")
}
do {   // on at once, cleared by its answer; the wire carries only the field
    var l = SettingsLedger(); _ = l.receive(st(base))
    let out = l.pick(HostSettingsChange(directWireless: true), token: 1, now: 0)
    check(out == HostSettingsChange(token: 1, directWireless: true), "a Direct Wireless pick sends exactly its field")
    check(String(data: enc(out!), encoding: .utf8) == #"{"directWireless":true,"token":1}"# || String(data: enc(out!), encoding: .utf8) == #"{"token":1,"directWireless":true}"#,
          "on the wire: {token, directWireless}")
    var h = base; h.directWireless = true
    check(l.receive(st(h, answering: 1)).isEmpty && l.pending.isEmpty && l.displayed?.directWireless == true, "its answer settles it on")
}
do {   // on → off → on before any answer: never shows off after the first answer
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(directWireless: true), token: 1, now: 0)
    _ = l.pick(HostSettingsChange(directWireless: false), token: 2, now: 0.1)
    _ = l.pick(HostSettingsChange(directWireless: true), token: 3, now: 0.2)
    var h = base; h.directWireless = true; _ = l.receive(st(h)); _ = l.receive(st(h, answering: 1))
    check(l.displayed?.directWireless == true, "on → off → on: after the answer to 1 it shows on")
    h.directWireless = false; _ = l.receive(st(h))
    check(l.displayed?.directWireless == true, "on → off → on: the broadcast of off does not show off")
    let r2 = l.receive(st(h, answering: 2))
    check(l.displayed?.directWireless == true && r2.isEmpty, "on → off → on: the answer to 2 (off) does not show off, and is no refusal")
    h.directWireless = true; _ = l.receive(st(h)); _ = l.receive(st(h, answering: 3))
    check(l.pending.isEmpty && l.displayed?.directWireless == true, "on → off → on: the answer to 3 settles on")
}
do {   // refused: the switch goes back and the caller is told
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(directWireless: true), token: 1, now: 0)
    let refused = l.receive(st(base, answering: 1))
    check(refused == [.directWireless] && l.displayed?.directWireless == false, "a refused Direct Wireless pick goes back and is reported")
}
do {   // unanswered: back at the timeout; a late answer still applies
    var l = SettingsLedger(); _ = l.receive(st(base))
    _ = l.pick(HostSettingsChange(directWireless: true), token: 1, now: 100)
    check(!l.expire(now: 104, timeout: 4) && l.displayed?.directWireless == true, "Direct Wireless: not expired at exactly the timeout")
    check(l.expire(now: 104.01, timeout: 4) && l.displayed?.directWireless == false, "Direct Wireless: expired just past it, back to off")
    var h = base; h.directWireless = true
    check(l.receive(st(h, answering: 1)).isEmpty && l.displayed?.directWireless == true, "Direct Wireless: a late answer still applies")
}
do {   // wire shapes and tolerance
    let change = HostSettingsChange(token: 7, bitrate: 25_000_000)
    print("     change: " + String(data: enc(change), encoding: .utf8)!)
    encoder.outputFormatting = [.sortedKeys]
    print("     state:  " + String(data: enc(st(base)), encoding: .utf8)!)
    encoder.outputFormatting = []
    check(String(data: enc(HostSettingsChange(bitrate: 1)), encoding: .utf8) == #"{"bitrate":1}"#, "nil fields are left out of the JSON")
    let newer = #"{"settings":{"maxFPS":60,"bitrate":8000000,"captureScale":1,"prioritizeSpeed":true,"virtualDisplay":false,"hdr":true},"persistent":false,"virtualDisplayAvailable":false,"softwareEncoder":false,"editable":false,"stream":{"width":1,"height":2,"fps":60,"mbps":8,"onVirtualDisplay":false,"codec":"x"},"answering":3}"#
    check(dec(HostSettingsState.self, Data(newer.utf8))?.answering == 3, "a newer host's extra keys are ignored")
    check(dec(HostSettingsChange.self, Data(#"{"bitrate":8000000}"#.utf8))?.token == nil, "a change without a token decodes (test clients)")
    check(dec(HostSettingsChange.self, Data(#"{"token":2,"bitrate":8000000,"sharpen":3}"#.utf8))?.bitrate == 8_000_000, "a newer device's extra keys are ignored")
    check(dec(HostSettingsChange.self, Data(#"{"captureScale":1}"#.utf8))?.captureScale == 1.0, "an integer capture scale decodes as 1.0")
    check(dec(HostSettingsChange.self, Data("{".utf8)) == nil, "a malformed change is dropped")
    check(dec(HostSettingsState.self, Data(#"{"settings":{"maxFPS":60}}"#.utf8)) == nil, "a state missing a required key fails to decode")
    check(QualityPreset.title(forBitrate: 12_000_000) == "Custom — 12 Mbps" && QualityPreset.title(forBitrate: 8_500_000) == "Custom — 8.5 Mbps"
          && QualityPreset.balanced.title == "Balanced — 15 Mbps", "preset titles as the Mac shows them")
}

do {   // the presets (2026-09-24): Maximum is Pro, Ultra and Extreme are new; the raw values are the bitrates.
       // The merge with remote access (2026-09-25) adds Low (4 Mbps) first: seven presets.
    let presets: [(QualityPreset, Int, String)] = [
        (.low, 4_000_000, "Low — 4 Mbps"),
        (.efficient, 8_000_000, "Efficient — 8 Mbps"), (.balanced, 15_000_000, "Balanced — 15 Mbps"),
        (.high, 25_000_000, "High — 25 Mbps"), (.pro, 40_000_000, "Pro — 40 Mbps"),
        (.ultra, 80_000_000, "Ultra — 80 Mbps"), (.extreme, 150_000_000, "Extreme — 150 Mbps")]
    check(QualityPreset.allCases == presets.map(\.0), "seven presets, in ascending order: " + QualityPreset.allCases.map(\.title).joined(separator: ", "))
    check(SettingsChoices.bitrate == presets.map(\.1), "a device may pick exactly the seven bitrates: \(SettingsChoices.bitrate)")
    for (preset, raw, title) in presets {
        check(preset.rawValue == raw && QualityPreset(rawValue: raw) == preset && preset.title == title
              && QualityPreset.title(forBitrate: raw) == title, "\(title): raw value \(raw) and title")
        // The ledger round trip of this raw value, every message through JSON, from a Mac on
        // Balanced (on Efficient for Balanced itself, so the pick changes something).
        var from = base
        if raw == base.bitrate { from.bitrate = 8_000_000 }
        var l = SettingsLedger()
        _ = l.receive(dec(HostSettingsState.self, enc(st(from)))!)
        guard let out = l.pick(HostSettingsChange(bitrate: raw), token: 1, now: 0) else { fail("\(title): the pick sent nothing") }
        let json = String(data: enc(out), encoding: .utf8)!
        let wire = dec(HostSettingsChange.self, Data(json.utf8))
        check(out == HostSettingsChange(token: 1, bitrate: raw) && wire == out && l.displayed?.bitrate == raw,
              "\(title): the pick sends \(json) and shows at once")
        check(accepted(wire!, virtualDisplayAvailable: true) == HostSettingsChange(bitrate: raw), "\(title): the host accepts it")
        var h = from; h.bitrate = raw
        let answer = dec(HostSettingsState.self, enc(st(h, answering: 1)))!
        check(answer.settings.bitrate == raw && l.receive(answer).isEmpty && l.pending.isEmpty && l.displayed == h,
              "\(title): the answer carries \(raw), clears the pick, no refusal")
    }
    check(QualityPreset(rawValue: 40_000_000)?.name == "Pro", "40 Mbps is Pro (a stored 40 Mbps needs no migration)")
    check(QualityPreset.title(forBitrate: 100_000_000) == "Custom — 100 Mbps" && QualityPreset.title(forBitrate: 200_000_000) == "Custom — 200 Mbps",
          "the old cap and the new one are Custom values, set only on the Mac")
    for bad in [12_000_000, 100_000_000, 200_000_000, 250_000_000] {
        check(accepted(HostSettingsChange(bitrate: bad), virtualDisplayAvailable: true).bitrate == nil, "a device's \(bad) is refused: not a preset")
    }
    for raw in [80_000_000, 150_000_000] {   // a host from before this change knows 8, 15, 25 and 40 only
        var l = SettingsLedger(); _ = l.receive(st(base))
        _ = l.pick(HostSettingsChange(bitrate: raw), token: 1, now: 0)
        check(l.receive(st(base, answering: 1)) == [.bitrate] && l.displayed?.bitrate == 15_000_000,
              "an older host refuses \(raw): reported as a refusal, the row goes back to 15 Mbps")
    }
    var fast = base; fast.bitrate = 150_000_000
    var s = st(fast); s.stream = RunningStream(width: 3024, height: 1898, fps: 120, mbps: 300, onVirtualDisplay: false)
    check(dec(HostSettingsState.self, enc(s)) == s, "a state with Extreme at 120 fps (300 Mbps) round-trips")
    check(QualityPreset.fastLinkNote == "Ultra and Extreme need the USB cable or very fast Wi\u{2011}Fi; if the picture lags, step down.",
          "the footer sentence: " + QualityPreset.fastLinkNote)
}

// Remote access's step 7: the Low preset (4 Mbps), first of the presets on both sides.
do {
    check(QualityPreset.allCases.first == .low && QualityPreset.low.title == "Low — 4 Mbps", "Low comes first, titled as the Mac's menu shows it")
    check(SettingsChoices.bitrate == [4_000_000, 8_000_000, 15_000_000, 25_000_000, 40_000_000, 80_000_000, 150_000_000], "a device may pick Low")
    var l = SettingsLedger(); _ = l.receive(st(base))
    check(l.pick(HostSettingsChange(bitrate: 4_000_000), token: 1, now: 0) == HostSettingsChange(token: 1, bitrate: 4_000_000), "a Low pick sends its field")
    var h = base; h.bitrate = 4_000_000
    check(l.receive(st(h, answering: 1)).isEmpty && l.displayed?.bitrate == 4_000_000, "a host with Low applies it")
    var o = SettingsLedger(); _ = o.receive(st(base))
    _ = o.pick(HostSettingsChange(bitrate: 4_000_000), token: 1, now: 0)
    let refused = o.receive(st(base, answering: 1))    // an older host: 4 Mbps is not one of its choices
    check(refused == [.bitrate] && o.displayed?.bitrate == 15_000_000, "an older host refuses Low: the panel goes back and says so")
}

// MARK: - The random model

struct RNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

enum MainEvent { case handle(conn: Int, payload: Data, touched: [SettingsField]), sendCatalog(conn: Int) }
enum NetEvent { case broadcast(Data), send(conn: Int, Data), ready(conn: Int), fromClient(conn: Int, Data, [SettingsField]), closed(conn: Int) }

final class Host {
    var target: StreamSettings
    let virtualDisplayAvailable: Bool
    let persistent: Bool
    /// A host from before Direct Wireless: its state has no such key and it ignores the field.
    let old: Bool
    var softwareEncoder = false
    var note: String?
    var lastPublished: HostSettingsState?
    var ready: Set<Int> = []
    var open: Set<Int> = []
    var mainQ: [MainEvent] = []
    var netQ: [NetEvent] = []
    var intended: [SettingsField: HostSettingsChange] = [:]
    var changesHandled = 0
    var answersQueued = 0
    var broadcasts = 0

    init(target: StreamSettings, app: Bool, old: Bool) {
        self.target = target
        self.old = old
        if old { self.target.directWireless = nil }
        persistent = app
        virtualDisplayAvailable = app   // the CLI in this model runs without --virtual-display
        if !app { self.target.virtualDisplay = false; note = "Start SillHost with --virtual-display to use it." }
    }

    func state(answering: Int? = nil) -> HostSettingsState {
        HostSettingsState(settings: target, persistent: persistent, virtualDisplayAvailable: virtualDisplayAvailable,
                          virtualDisplayNote: note, softwareEncoder: softwareEncoder, answering: answering)
    }

    /// The one publish point: after every change of the target or of the status snapshot.
    func publish() {
        let s = state()
        guard s != lastPublished else { return }
        lastPublished = s
        broadcasts += 1
        netQ.append(.broadcast(enc(s)))
    }

    func setTarget(_ requested: StreamSettings) {
        var n = requested
        if !virtualDisplayAvailable { n.virtualDisplay = false }
        guard n != target else { return }
        target = n
        publish()
    }

    /// `.changeSettings`: synchronous from decode to answer, like the coordinator's handler.
    func handle(conn: Int, payload: Data, touched: [SettingsField]) {
        guard let change = dec(HostSettingsChange.self, payload) else { return }   // undecodable: dropped, no answer
        changesHandled += 1
        var ok = accepted(change, virtualDisplayAvailable: virtualDisplayAvailable)
        if old { ok.directWireless = nil }   // JSONDecoder dropped the unknown key
        // An older host (before Direct Wireless) knows 8, 15, 25 and 40 Mbps only: Low, Ultra and
        // Extreme are not among its choices (the union of the two branches' rules).
        if old, let b = ok.bitrate, [QualityPreset.low, .ultra, .extreme].map(\.rawValue).contains(b) {
            ok.bitrate = nil
            newRefusedByOld += 1
        }
        if let b = ok.bitrate, [QualityPreset.low, .ultra, .extreme].map(\.rawValue).contains(b) { newAccepted += 1 }
        for f in touched where ok.fields.contains(f) { intended[f] = ok.only(f) }
        let before = target
        if !ok.isEmpty { setTarget(ok.applied(to: target)) }
        let named = Set(ok.fields)
        let t = HostSettingsChange(maxFPS: target.maxFPS, bitrate: target.bitrate, captureScale: target.captureScale,
                                   prioritizeSpeed: target.prioritizeSpeed, virtualDisplay: target.virtualDisplay,
                                   directWireless: target.directWireless)
        for f in SettingsField.allCases where !named.contains(f) && t.only(f).applied(to: before) != before {
            fail("field \(f) changed by a change that does not name it")
        }
        answersQueued += 1
        netQ.append(.send(conn: conn, enc(state(answering: change.token))))
    }

    func macMenu(_ change: HostSettingsChange) {   // Sill.app: HostSettings.config → setTarget, synchronously
        var change = change
        if old { change.directWireless = nil }   // an older Mac has no such control
        if old, let b = change.bitrate, [QualityPreset.low, .ultra, .extreme].map(\.rawValue).contains(b) { change.bitrate = nil }   // nor these items
        guard !change.isEmpty else { return }
        for f in change.fields { intended[f] = change.only(f) }
        setTarget(change.applied(to: target))
    }

    func statusChanged(rng: inout RNG) {          // HostStatus.update → onChange → publish
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: softwareEncoder = true
        case 1: if virtualDisplayAvailable { note = ["Off for this session: the system removed the virtual display 3 times. Turn it off and on to try again.",
                                                     "The last window streamed where it is: needs Accessibility", nil].randomElement(using: &rng)! }
        default: break                              // a device's once-a-second stats: nothing devices see
        }
        publish()
    }
}

final class Device {
    let name: Int
    var conn: Int?
    var inbox: [Data] = []
    var outbox: [(Data, [SettingsField])] = []
    var picks: [SettingsField: (value: HostSettingsChange, token: Int, sentAt: Double)] = [:]   // the spec, kept apart from the ledger
    var ledger = SettingsLedger()
    var nextToken = 1
    var lastAnswer = 0
    var sent: [Int] = []
    var answered: [Int] = []
    init(name: Int) { self.name = name }
}

func randomChange(_ rng: inout RNG, validOnly: Bool) -> HostSettingsChange {
    var c = HostSettingsChange()
    switch Int.random(in: 0..<6, using: &rng) {
    case 5: c.directWireless = Bool.random(using: &rng)
    case 0: c.maxFPS = validOnly ? SettingsChoices.maxFPS.randomElement(using: &rng)! : [30, 60, 90, 120, 240].randomElement(using: &rng)!
    case 1: c.bitrate = validOnly ? SettingsChoices.bitrate.randomElement(using: &rng)! : [8_000_000, 12_000_000, 100_000_000, 200_000_000, 250_000_000, 500_000_000].randomElement(using: &rng)!
    case 2: c.captureScale = validOnly ? SettingsChoices.captureScale.randomElement(using: &rng)! : [1, 1.5, 2, 3].randomElement(using: &rng)!
    case 3: c.prioritizeSpeed = Bool.random(using: &rng)
    default: c.virtualDisplay = Bool.random(using: &rng)
    }
    if Int.random(in: 0..<6, using: &rng) == 0 { c = c.adding(randomChange(&rng, validOnly: validOnly)) }
    return c
}

func run(seed: UInt64) -> (steps: Int, answers: Int, broadcasts: Int, expiries: Int, refusals: Int) {
    var rng = RNG(state: seed)
    let app = Bool.random(using: &rng)
    let old = Int.random(in: 0..<4, using: &rng) == 0
    let start = StreamSettings(maxFPS: 120, bitrate: [15_000_000, 12_000_000].randomElement(using: &rng)!,   // 12 = a Mac-side custom value
                               captureScale: 2, prioritizeSpeed: false, virtualDisplay: false,
                               directWireless: Bool.random(using: &rng))
    let host = Host(target: start, app: app, old: old)
    var intentBase = start
    if !app { intentBase.virtualDisplay = false }
    if old { intentBase.directWireless = nil }
    let devices = (0..<Int.random(in: 1...3, using: &rng)).map { Device(name: $0) }
    var nextConn = 1
    var now = 0.0
    let timeout = 4.0
    var expiries = 0
    var refusals = 0

    func connect(_ d: Device) {
        let c = nextConn; nextConn += 1
        d.conn = c; d.inbox = []; d.outbox = []; d.ledger.reset(); d.lastAnswer = 0; d.sent = []; d.answered = []; d.picks = [:]
        host.open.insert(c)
        host.netQ.append(.ready(conn: c))
    }
    func disconnect(_ d: Device, rng: inout RNG) {
        guard let c = d.conn else { return }
        let delivered = Int.random(in: 0...d.outbox.count, using: &rng)   // TCP: some of what was written arrives before the close
        for m in d.outbox.prefix(delivered) { host.netQ.append(.fromClient(conn: c, m.0, m.1)) }
        host.netQ.append(.closed(conn: c))
        d.conn = nil; d.inbox = []; d.outbox = []; d.ledger.reset(); d.picks = [:]
    }
    for d in devices { connect(d) }

    func stepMain() {
        guard !host.mainQ.isEmpty else { return }
        switch host.mainQ.removeFirst() {
        case .handle(let conn, let payload, let touched): host.handle(conn: conn, payload: payload, touched: touched)
        case .sendCatalog(let conn): host.netQ.append(.send(conn: conn, enc(host.state())))
        }
    }
    func stepNet() {
        guard !host.netQ.isEmpty else { return }
        switch host.netQ.removeFirst() {
        case .broadcast(let data):
            for d in devices { if let c = d.conn, host.ready.contains(c) { d.inbox.append(data) } }
        case .send(let conn, let data):
            if host.open.contains(conn), let d = devices.first(where: { $0.conn == conn }) { d.inbox.append(data) }
        case .ready(let conn):
            guard host.open.contains(conn) else { return }
            host.ready.insert(conn)
            host.mainQ.append(.sendCatalog(conn: conn))
        case .fromClient(let conn, let data, let touched):
            host.mainQ.append(.handle(conn: conn, payload: data, touched: touched))   // a Task per message, FIFO on the main actor
        case .closed(let conn):
            host.ready.remove(conn); host.open.remove(conn)
        }
    }
    func deliver(_ d: Device) {
        guard !d.inbox.isEmpty else { return }
        let data = d.inbox.removeFirst()
        guard let s = dec(HostSettingsState.self, data) else { fail("state did not decode") }
        if let t = s.answering {
            guard t > d.lastAnswer else { fail("answers out of order: \(t) after \(d.lastAnswer)") }
            d.lastAnswer = t
            d.answered.append(t)
        }
        refusals += d.ledger.receive(s).count
        if let t = s.answering { d.picks = d.picks.filter { $0.value.token != t } }
        d.picks = d.picks.filter { now - $0.value.sentAt <= timeout }
        if let shown = d.ledger.displayed {
            for (f, p) in d.picks where p.value.applied(to: shown) != shown {
                fail("device \(d.name) shows the host's \(f) while its pick \(p.token) is unanswered (flash; seed \(seed))")
            }
        }
    }
    func devicePick(_ d: Device, rng: inout RNG) {
        guard d.conn != nil else { return }
        let buggy = Int.random(in: 0..<10, using: &rng) == 0
        let want = randomChange(&rng, validOnly: !buggy)
        if buggy {   // a test client: sends whatever it likes, with a token, even without a state
            var c = want; c.token = d.nextToken; d.nextToken += 1
            d.sent.append(c.token!)
            d.outbox.append((enc(c), c.fields))
            return
        }
        // The panel disables the switch only when it is off and unavailable; turning it off is always offered.
        if want.virtualDisplay == true, d.ledger.host?.virtualDisplayAvailable != true { return }
        guard let out = d.ledger.pick(want, token: d.nextToken, now: now) else { return }
        if out.directWireless != nil, d.ledger.host?.settings.directWireless == nil {
            fail("rule 9: device \(d.name) sent directWireless to a host that never reported it (seed \(seed))")
        }
        let touched = out.fields
        for f in touched { d.picks[f] = (out.only(f), out.token!, now) }
        d.nextToken += 1
        d.sent.append(out.token!)
        d.outbox.append((enc(out), touched))
    }
    func deviceWrite(_ d: Device) {
        guard let c = d.conn, !d.outbox.isEmpty else { return }
        let m = d.outbox.removeFirst()
        host.netQ.append(.fromClient(conn: c, m.0, m.1))
    }

    var steps = 0
    let active = Int.random(in: 20...400, using: &rng)
    for _ in 0..<active {
        steps += 1
        now += Double.random(in: 0...0.3, using: &rng)
        for d in devices where d.ledger.expire(now: now, timeout: timeout) { expiries += 1 }
        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<22: stepMain()
        case 22..<44: stepNet()
        case 44..<66: if let d = devices.randomElement(using: &rng) { deliver(d) }
        case 66..<78: if let d = devices.randomElement(using: &rng) { devicePick(d, rng: &rng) }
        case 78..<90: if let d = devices.randomElement(using: &rng) { deviceWrite(d) }
        case 90..<94: if app { host.macMenu(randomChange(&rng, validOnly: true)) }
        case 94..<97: host.statusChanged(rng: &rng)
        case 97: if let d = devices.randomElement(using: &rng) { disconnect(d, rng: &rng) }
        default: if let d = devices.first(where: { $0.conn == nil }) { connect(d) }
        }
    }
    // Quiesce: everyone who was away comes back, then drain every queue in random order.
    for d in devices where d.conn == nil { connect(d) }
    var guardSteps = 0
    while !host.mainQ.isEmpty || !host.netQ.isEmpty || devices.contains(where: { !$0.inbox.isEmpty || !$0.outbox.isEmpty }) {
        guardSteps += 1; if guardSteps > 1_000_000 { fail("did not drain") }
        now += 0.01
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: stepMain()
        case 1: stepNet()
        case 2: if let d = devices.randomElement(using: &rng) { deliver(d) }
        default: if let d = devices.randomElement(using: &rng) { deviceWrite(d) }
        }
    }
    let truth = host.state()
    for d in devices {
        guard let seen = d.ledger.host else { fail("device \(d.name) never received a state (seed \(seed))") }
        if seen != truth { fail("device \(d.name) state \(seen) != host \(truth) (seed \(seed))") }
        if !d.ledger.pending.isEmpty { fail("device \(d.name) still has pending \(d.ledger.pending) (seed \(seed))") }
        if d.ledger.displayed != host.target { fail("device \(d.name) displays \(String(describing: d.ledger.displayed)) != \(host.target) (seed \(seed))") }
        if d.answered != d.sent { fail("device \(d.name) sent \(d.sent) but got answers \(d.answered) (seed \(seed))") }
    }
    if !app, host.target.virtualDisplay { fail("CLI without the AppKit loop ended with the virtual display on") }
    if ![60, 120].contains(host.target.maxFPS) { fail("maxFPS \(host.target.maxFPS) left the menu's choices") }
    if ![4_000_000, 8_000_000, 12_000_000, 15_000_000, 25_000_000, 40_000_000, 80_000_000, 150_000_000].contains(host.target.bitrate) { fail("bitrate \(host.target.bitrate) accepted") }
    if old, [4_000_000, 80_000_000, 150_000_000].contains(host.target.bitrate) { fail("an older host ended at \(host.target.bitrate) (seed \(seed))") }
    for f in SettingsField.allCases {
        let want = host.intended[f]?.applied(to: intentBase) ?? intentBase
        if HostSettingsChange(maxFPS: want.maxFPS, bitrate: want.bitrate, captureScale: want.captureScale, prioritizeSpeed: want.prioritizeSpeed,
                              virtualDisplay: want.virtualDisplay, directWireless: want.directWireless).only(f).applied(to: host.target) != host.target {
            fail("lost update: \(f) is not the last value anyone chose for it (seed \(seed))")
        }
    }
    if host.answersQueued != host.changesHandled { fail("answers \(host.answersQueued) != changes \(host.changesHandled)") }
    if old, host.target.directWireless != nil { fail("an older host ended up reporting directWireless (seed \(seed))") }
    if old { oldHostRuns += 1 }
    return (steps, host.answersQueued, host.broadcasts, expiries, refusals)
}

var oldHostRuns = 0
var newAccepted = 0
var newRefusedByOld = 0
let runs = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 5_000 : 5_000
var totals = (steps: 0, answers: 0, broadcasts: 0, expiries: 0, refusals: 0)
for seed in 1...runs {
    let r = run(seed: UInt64(seed))
    totals.steps += r.steps; totals.answers += r.answers; totals.broadcasts += r.broadcasts
    totals.expiries += r.expiries; totals.refusals += r.refusals
}
print("ok   \(runs) random two-device + Mac-menu runs converged: \(totals.steps) steps, \(totals.answers) answers (one per change, in order), "
      + "\(totals.broadcasts) broadcasts (none duplicate), \(totals.expiries) device timeouts, \(totals.refusals) refusals reported; "
      + "\(oldHostRuns) runs against an older host (no directWireless), where rule 9 held")
print("ok   Low, Ultra or Extreme picked and applied \(newAccepted) times; refused by an older host \(newRefusedByOld) times (never applied there)")
