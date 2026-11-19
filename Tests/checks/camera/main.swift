import Foundation

// The device's rules for Share Camera (CameraPolicy, CameraPacing; docs/camera-plan.md §6.1, §6.2 with §0's
// settlement), compiled with Sources/StreamProtocol as one module (module.txt): the row, offering and
// capturing over every combination of their inputs, the pause's order, the format, the heat, the bitrate and
// its steps, the keyframes, the chip, every word; then the send budget on a virtual clock: a link of 1, 2, 5,
// 20 and 100 Mbit/s carrying the camera and a person's taps, against the budget's promises.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = CameraPolicy
typealias C = CameraPolicy.Copy
func st(_ s: String, holder: String? = nil, app: String? = nil) -> CameraState { CameraState(state: s, holder: holder, app: app) }
let inUse = st(CameraState.inUse, app: "FaceTime")
let all: (Int, Int, Int) -> Bool = { _, _, _ in true }

// MARK: - The row

check(P.row(hostCamera: 1, hostVersion: "0.7.0", locked: false) == .enabled, "a Mac that takes the camera: the switch")
check(P.row(hostCamera: 2, hostVersion: "0.9.0", locked: false) == .enabled, "a later generation too (it takes generation 1 still)")
check(P.row(hostCamera: 0, hostVersion: "0.7.0", locked: false) == .disabled, "camera 0 (the Mac's switch off, Sill Camera not ready): disabled")
check(P.row(hostCamera: nil, hostVersion: "0.6.3", locked: false) == .updateMac, "a Sill.app from before the camera: Update Sill")
check(P.row(hostCamera: nil, hostVersion: nil, locked: false) == .hidden, "the CLI (no version, no camera): nothing")
check(P.row(hostCamera: 1, hostVersion: "0.7.0", locked: true) == .hidden && P.row(hostCamera: nil, hostVersion: "0.7.0", locked: true) == .hidden,
      "a locked Mac: hidden (the header says why)")

// MARK: - Offering, capturing and the pause, every combination

check(P.offers(switchOn: true, hostCamera: 1, connected: true), "offers: on, a Mac that takes it, connected")
for (on, cam, conn) in [(false, 1, true), (true, 0, true), (true, nil, true), (true, 1, false)] as [(Bool, Int?, Bool)] {
    check(!P.offers(switchOn: on, hostCamera: cam, connected: conn), "no offer: switch \(on), camera \(String(describing: cam)), connected \(conn)")
}
let states: [CameraState?] = [nil, st("off"), st("notReady"), st("unpaired"), st("idle"), st("another", holder: "iPhone"), inUse, st("later")]
var combos = 0, captured = 0
for offering in [false, true] { for state in states { for bits in 0..<(1 << 6) { for pressure in P.Pressure.allCases {
    let d = P.Device(denied: bits & 1 != 0, hasCamera: bits & 2 == 0, front: bits & 4 == 0, multitasking: bits & 8 != 0,
                     busy: bits & 16 != 0, scanner: bits & 32 != 0, pressure: pressure)
    combos += 1
    let runs = P.captures(offering: offering, state: state, device: d)
    let clear = !d.denied && d.hasCamera && d.front && !d.multitasking && !d.busy && !d.scanner && pressure != .shutdown
    let want = offering && state?.state == CameraState.inUse && clear
    if runs != want { check(false, "captures(offering \(offering), \(String(describing: state?.state)), \(d)) is \(want)") }
    if runs { captured += 1 }
    let pause = P.pause(state: state, device: d)
    // The order: denied, no camera, too warm, not in front, multitasking, the scanner, busy, then waiting.
    let expected: String? = d.denied ? "denied" : !d.hasCamera ? "unavailable" : pressure == .shutdown ? "thermal" : !d.front ? "background"
        : d.multitasking ? "multitasking" : d.scanner ? "scanner" : d.busy ? "busy" : state?.state == "inUse" ? nil : "waiting"
    if pause != expected { check(false, "pause(\(String(describing: state?.state)), \(d)) is \(String(describing: expected)), got \(String(describing: pause))") }
    if runs != (offering && pause == nil) { check(false, "captures exactly when it offers and nothing pauses it") }
    if P.countsAsUse(capturing: runs) != runs { check(false, "counts as use exactly while capturing") }
} } } }
check(combos == 2 * 8 * 64 * 5 && captured == 4, "every combination judged (\(combos)), the camera running in \(captured): in use, all clear, four pressures under shutdown")
check(Set(CameraFormat.pauses).isSuperset(of: ["denied", "unavailable", "thermal", "background", "multitasking", "scanner", "busy", "waiting"]),
      "every pause said is one of the wire's")

// MARK: - The format

func fmt(_ d: CameraDemand?, upright: Bool = false, away: Bool = false, p: P.Pressure = .nominal,
         supports: @escaping (Int, Int, Int) -> Bool = all) -> String {
    let f = P.format(demand: d, upright: upright, away: away, pressure: p, supports: supports)
    return "\(f.width)x\(f.height)@\(f.fps)"
}
check(fmt(CameraDemand(width: 1280, height: 720, fps: 30)) == "1280x720@30", "the demand's size and rate")
check(fmt(nil) == "1280x720@30", "no demand yet: 1280×720 at 30")
check(fmt(CameraDemand(width: 1920, height: 1080, fps: 30)) == "1920x1080@30", "1080p at home")
check(fmt(CameraDemand(width: 1920, height: 1080, fps: 30), away: true) == "1280x720@30", "away: 1280×720 at most")
check(fmt(CameraDemand(width: 640, height: 360, fps: 30), away: true) == "640x360@30", "away, smaller: as asked")
check(fmt(CameraDemand(width: 1280, height: 720, fps: 30), upright: true) == "720x1280@30", "a phone held upright: the picture upright inside it")
check(fmt(CameraDemand(width: 720, height: 1280, fps: 30)) == "1280x720@30" && fmt(CameraDemand(width: 720, height: 1280, fps: 30), upright: true) == "720x1280@30",
      "a tall demand read in the camera's own terms, then turned as the device stands")
check(fmt(CameraDemand(width: 1024, height: 768, fps: 24), supports: { w, _, _ in w != 1024 }) == "1280x720@24", "no format at that size: 1280×720, the rate kept")
check(fmt(CameraDemand(width: 1280, height: 720, fps: 60)) == "1280x720@30", "never over 30 fps")
check(fmt(CameraDemand(width: 1920, height: 1080, fps: 60), supports: { _, _, fps in fps <= 30 }) == "1920x1080@30",
      "a 60 fps demand: the camera's format asked for at 30 fps, so 1080p is kept")
check(fmt(CameraDemand(width: 1280, height: 720, fps: 30), p: .fair) == "1280x720@30", "fair: as asked")
check(fmt(CameraDemand(width: 1920, height: 1080, fps: 30), p: .serious) == "1920x1080@20", "serious: 20 fps")
check(fmt(CameraDemand(width: 1920, height: 1080, fps: 30), p: .critical) == "1280x720@15", "critical: 15 fps and 1280×720 at most")
check(fmt(CameraDemand(width: 640, height: 360, fps: 10), p: .critical) == "640x360@10", "a slower demand stays slower")
check(P.maxRate(.nominal) == 30 && P.maxRate(.serious) == 20 && P.maxRate(.critical) == 15 && P.thermalRecovery == 30, "the heat's steps")

// MARK: - The bitrate and its steps

check(P.bitrate(width: 1280, height: 720, fps: 30, away: false, ceiling: nil) == 2_500_000, "720p30 at home: 2.5 Mbit/s")
check(P.bitrate(width: 1280, height: 720, fps: 30, away: true, ceiling: nil) == 1_200_000, "720p30 away: 1.2")
check(P.bitrate(width: 1920, height: 1080, fps: 30, away: false, ceiling: nil) == 4_000_000, "1080p30 at home: 4")
check(P.bitrate(width: 720, height: 1280, fps: 30, away: false, ceiling: nil) == 2_500_000, "upright, the same pixels")
check(P.bitrate(width: 1280, height: 720, fps: 15, away: false, ceiling: nil) == 1_250_000, "half the rate, half")
check(P.bitrate(width: 1920, height: 1080, fps: 30, away: false, ceiling: 3_000_000) == 3_000_000, "never over the demand's ceiling")
check(P.bitrate(width: 160, height: 90, fps: 5, away: false, ceiling: 100_000) == 300_000, "at least 300 kbit/s")
check(P.bitrate(width: 1920, height: 1920, fps: 30, away: false, ceiling: nil) == 4_000_000, "4 at most")
do {
    var b = P.BitrateStep(target: 2_400_000, at: 0)
    b.second(dropped: true, at: 1)
    check(b.current == 1_600_000, "a drop: a third down (\(b.current))")
    b.second(dropped: true, at: 2); b.second(dropped: true, at: 3); b.second(dropped: true, at: 4); b.second(dropped: true, at: 5)
    check(b.current == 480_000, "never under a fifth of the target (\(b.current))")
    b.second(dropped: false, at: 9)
    check(b.current == 480_000, "4 s without a drop: no step yet")
    b.second(dropped: false, at: 10)
    check(b.current == 720_000, "5 s: a tenth of the target back (\(b.current))")
    for t in stride(from: 15.0, through: 100, by: 5) { b.second(dropped: false, at: t) }
    check(b.current == 2_400_000, "back to the target, never over it")
    b.retarget(1_200_000, at: 101)
    check(b.current == 1_200_000 && b.target == 1_200_000, "a new target taken at once")
    var small = P.BitrateStep(target: 600_000, at: 0)
    for t in 1...10 { small.second(dropped: true, at: Double(t)) }
    check(small.current == 300_000, "a small target's floor is 300 kbit/s (\(small.current))")
}

// MARK: - Keyframes

check(P.keyframe(newEpoch: true, demanded: false, lastDemandedAt: nil, droppedSince: false, at: 5), "a new epoch starts with one")
check(P.keyframe(newEpoch: false, demanded: false, lastDemandedAt: nil, droppedSince: true, at: 5), "after a drop")
check(P.keyframe(newEpoch: false, demanded: true, lastDemandedAt: nil, droppedSince: false, at: 5), "a demand's")
check(!P.keyframe(newEpoch: false, demanded: true, lastDemandedAt: 4.5, droppedSince: false, at: 5), "a demand's within a second of the last: no")
check(P.keyframe(newEpoch: false, demanded: true, lastDemandedAt: 4, droppedSince: false, at: 5), "a second later: yes")
check(!P.keyframe(newEpoch: false, demanded: false, lastDemandedAt: nil, droppedSince: false, at: 5), "otherwise never (an infinite GOP)")

// MARK: - The chip

check(P.chip(offering: true, state: inUse, capturing: true) == .on(app: "FaceTime"), "frames going: Camera, FaceTime")
check(P.chip(offering: true, state: st("inUse"), capturing: true) == .on(app: nil), "an app Sill Camera cannot name")
check(P.chip(offering: true, state: inUse, capturing: false) == .paused, "wanted but paused: Camera Paused")
for s in states where s?.state != "inUse" {
    check(P.chip(offering: true, state: s, capturing: false) == .none, "\(String(describing: s?.state)): no chip")
}
check(P.chip(offering: false, state: inUse, capturing: false) == .none, "not offering: no chip")

// MARK: - The words

let mac = "Mac mini", dev = "iPad"
func note(_ s: CameraState? = st("idle"), row: P.Row = .enabled, on: Bool = true, pause: String? = nil) -> String {
    C.footnote(row: row, switchOn: on, state: s, pause: pause, mac: mac, device: dev)
}
check(note(row: .hidden) == "", "hidden: no words")
check(note(row: .updateMac) == "Update Sill on Mac mini to share this iPad’s camera with it.", "an older Mac")
check(note(nil, row: .disabled) == "Turn on Use iPhone and iPad cameras in Sill’s Settings on Mac mini to share this iPad’s camera with it." && note(st("off")) == note(nil, row: .disabled),
      "the Mac's switch off, from the list's 0 or kind 16")
check(note(st("notReady")) == "Sill Camera isn’t ready on Mac mini. In Sill’s Settings there, Streaming shows what it needs.", "not ready")
check(note(st("notReady"), row: .disabled) == note(st("notReady")),
      "not ready with the list's 0, which disables the row: kind 16's words, never the switch's")
check(note(st("unpaired")) == "Pair this iPad with Mac mini to share its camera.", "unpaired")
check(note(on: false) == "Lets apps on Mac mini, such as FaceTime or Zoom, use this iPad’s camera as “Sill Camera”. The camera turns on only while one of them uses it, and Sill shows when it’s on.",
      "the switch off: what it does")
check(note(st("idle")) == "Apps on Mac mini can choose “Sill Camera”. The camera turns on only while one of them uses it.", "on, nothing using it")
check(note(inUse) == "FaceTime on Mac mini is using this iPad’s camera." && note(st("inUse")) == "An app on Mac mini is using this iPad’s camera.", "in use, named or not")
check(note(st("another", holder: "iPhone")) == "iPhone is Mac mini’s camera now. Turn Share Camera off and on to use this iPad instead.", "another device")
check(note(st("another")) == "Another device is Mac mini’s camera now. Turn Share Camera off and on to use this iPad instead.", "another, unnamed")
check(note(st("another", holder: "")) == "Another device is Mac mini’s camera now. Turn Share Camera off and on to use this iPad instead.",
      "another, its name empty (a name SafeText left nothing of)")
check(note(pause: "denied") == "Sill isn’t allowed to use the camera. Open Settings and turn on Camera for Sill." && C.showsOpenSettings(pause: "denied")
      && !C.showsOpenSettings(pause: "busy") && C.openSettings == "Open Settings", "denied: the words and Open Settings")
check(note(pause: "unavailable") == "This iPad has no camera Sill can use.", "no camera")
check(note(inUse, pause: "thermal") == "The camera is paused while this iPad cools down.", "too warm")
check(note(inUse, pause: "multitasking") == "The camera pauses while another app shares the screen with Sill.", "multitasking")
check(note(inUse, pause: "busy") == "Another app is using the camera. Sill’s comes back when it’s done.", "busy")
check(note(inUse, pause: "background") == note(inUse) && note(inUse, pause: "scanner") == note(inUse), "Sill away or its scanner up: the Mac's word stands")
check(note(st("later")) == note(st("idle")), "a later state never captures, and its words are the switch's own")
check(C.row == "Share Camera" && C.beta == "Beta" && C.position == "Camera" && C.front == "Front" && C.back == "Back", "the row's words")
check(C.chipTitle == "Camera" && C.chipPaused == "Camera Paused" && C.chipStop == "Stop" && C.chipStopLabel == "Stop sharing the camera"
      && C.chipFullScreenLabel == "Camera on" && C.chipPausedLabel == "Camera paused.", "the chip's words")
check(C.chipDetail(app: "FaceTime", mac: mac) == "FaceTime on Mac mini" && C.chipDetail(app: nil, mac: mac) == "On", "the chip's second line")
check(C.chipLabel(app: "FaceTime", mac: mac) == "Camera on. FaceTime on Mac mini is using it."
      && C.chipLabel(app: nil, mac: mac) == "Camera on. An app on Mac mini is using it.", "VoiceOver's")

// MARK: - The send budget

check(CameraPacing.minimumBudget == 16_384 && CameraPacing.budgetSeconds == 0.040, "16 KB, or 40 ms of what the link takes")
check(CameraPacing.budget(takenLastSecond: 0) == 16_384 && CameraPacing.budget(takenLastSecond: 1_000_000) == 40_000, "the budget")
do {
    var p = CameraPacing()
    check(p.encodes(fenced: false, unsent: 0, takenLastSecond: 0), "an empty link: encode")
    check(p.encodes(fenced: false, unsent: 16_384, takenLastSecond: 0), "at the budget: encode")
    check(!p.encodes(fenced: false, unsent: 16_385, takenLastSecond: 0) && p.skipped == 1, "over it: skipped before the encoder, counted")
    check(p.encodes(fenced: false, unsent: 30_000, takenLastSecond: 1_000_000), "a fast link's larger budget (40 KB)")
    check(!p.encodes(fenced: true, unsent: 0, takenLastSecond: 0) && p.skipped == 2, "a fence: skipped")
    check(!p.needsKeyframe, "a skip forces no keyframe (the encoder never made that frame)")
    check(p.sends(keyframe: false, fenced: false), "an encoded frame goes")
    check(!p.sends(keyframe: false, fenced: true) && p.dropped == 1 && p.needsKeyframe, "a fence after encoding: dropped, a keyframe next")
    check(!p.sends(keyframe: false, fenced: false) && p.dropped == 2, "never a frame that needs a dropped one")
    check(p.sends(keyframe: true, fenced: false) && !p.needsKeyframe, "the keyframe goes, and frames after it")
    check(p.sends(keyframe: false, fenced: false), "a P-frame again")
}

// The model: one TCP connection at `mbps`; pictures at 30 fps, each encoded only as CameraPacing allows, by an
// encoder at the stepped bitrate (a keyframe five P-frames' size: at the start and after a move); a tap every
// 0.37 s, which goes at once whatever is queued; a move's fence for 0.3 s at 20 s (its new epoch starts with a
// keyframe). Promised: a tap never waits behind more than the budget and one frame; nothing sent that needs a
// dropped frame; on a link with room for the stream, nothing skipped but around a keyframe; on any link, the
// picture keeps coming, and once the bitrate has stepped down a tap waits under 0.3 s.
struct Model { var worstTapMs = 0.0, worstLateTapMs = 0.0, boundExceeded = 0, sent = 0, skipped = 0, dropped = 0, brokenChain = 0 }
func model(mbps: Double, seconds: Double = 60) -> Model {
    let bytesPerMs = mbps * 1_000_000 / 8 / 1000
    var queue: [(bytes: Double, isTap: Bool, at: Double, bound: Double)] = []
    var pacing = CameraPacing()
    var step = P.BitrateStep(target: P.bitrate(width: 1280, height: 720, fps: 30, away: false, ceiling: nil), at: 0)
    var taken: [(t: Double, bytes: Double)] = []
    var m = Model()
    var forceKey = true, lostSinceKey = false, skippedThisSecond = false
    var nextPicture = 0.0, nextTap = 185.0, nextSecond = 1000.0
    var t = 0.0
    while t < seconds * 1000 {
        var room = bytesPerMs
        while room > 0, !queue.isEmpty {
            let take = min(room, queue[0].bytes)
            queue[0].bytes -= take; room -= take
            taken.append((t, take))
            if queue[0].bytes <= 0.0001 {
                let done = queue.removeFirst()
                if done.isTap {
                    let wait = t + 1 - done.at
                    m.worstTapMs = max(m.worstTapMs, wait)
                    if done.at > seconds * 1000 / 2 { m.worstLateTapMs = max(m.worstLateTapMs, wait) }
                    if wait > done.bound { m.boundExceeded += 1 }
                }
            }
        }
        if let first = taken.first, first.t < t - 1000 { taken.removeAll { $0.t < t - 1000 } }
        let unsent = Int(queue.reduce(0) { $0 + $1.bytes })
        let tookLastSecond = Int(taken.reduce(0) { $0 + $1.bytes })
        let fenced = t >= 20_000 && t < 20_300
        if t >= nextPicture {
            if pacing.encodes(fenced: fenced, unsent: unsent, takenLastSecond: tookLastSecond) {
                let pBytes = Double(step.current) / 8 / 30
                let key = forceKey
                if pacing.sends(keyframe: key, fenced: fenced) {
                    if lostSinceKey && !key { m.brokenChain += 1 }
                    if key { lostSinceKey = false }
                    queue.append((key ? pBytes * 5 : pBytes, false, t, 0)); m.sent += 1; forceKey = false
                } else {
                    m.dropped += 1; lostSinceKey = true; forceKey = true
                }
            } else {
                m.skipped += 1; skippedThisSecond = true
                if fenced { forceKey = true }      // the move's new epoch
            }
            nextPicture += 1000.0 / 30
        }
        if t >= nextTap {
            // Its bound: the budget it was sent under, one frame at the target's keyframe size, and itself.
            let maxFrame = Double(step.target) / 8 / 30 * 5
            queue.append((200, true, t, (Double(CameraPacing.budget(takenLastSecond: tookLastSecond)) + maxFrame + 200) / bytesPerMs + 2))
            nextTap += 370
        }
        if t >= nextSecond {
            step.second(dropped: skippedThisSecond, at: t / 1000); skippedThisSecond = false
            nextSecond += 1000
        }
        t += 1
    }
    m.skipped = pacing.skipped; m.dropped = pacing.dropped
    return m
}
for mbps in [1.0, 2, 5, 20, 100] {
    let m = model(mbps: mbps)
    print("model \(mbps) Mbit/s: \(m.sent) frames sent, \(m.skipped) skipped, \(m.dropped) dropped; a tap's worst wait \(Int(m.worstTapMs)) ms, \(Int(m.worstLateTapMs)) ms once settled")
    check(m.boundExceeded == 0, "\(mbps) Mbit/s: no tap waits past the budget and one frame (\(m.boundExceeded) did; worst \(Int(m.worstTapMs)) ms)")
    check(m.brokenChain == 0, "\(mbps) Mbit/s: nothing sent that needs a dropped frame")
    check(m.sent > 30 * 60 / 4, "\(mbps) Mbit/s: the picture keeps coming (\(m.sent) frames sent, \(m.skipped) skipped, \(m.dropped) dropped)")
    check(m.dropped <= 10, "\(mbps) Mbit/s: frames dropped only at the move's fence (\(m.dropped))")
    if mbps >= 5 { check(m.skipped <= 30, "\(mbps) Mbit/s: room for the stream, a picture skipped only around a keyframe or the fence (\(m.skipped))") }
    check(m.worstLateTapMs < 300, "\(mbps) Mbit/s: once the bitrate has settled, a tap waits under 0.3 s (\(Int(m.worstLateTapMs)) ms)")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
