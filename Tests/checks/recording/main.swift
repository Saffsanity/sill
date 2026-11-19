import Foundation

// The device's rules for recording the stream (#284, docs/recording-plan.md), compiled with RecordingPolicy,
// RecordingClock (and its RecordingTimeline), RecordedSound, KeyframeRecovery and SillDocuments as one module
// (module.txt): each rule's cases, then 20,000 random recordings against the invariants, then the source rules.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = RecordingPolicy
typealias Clock = RecordingClock
typealias Sound = RecordedSound
func near(_ a: Double?, _ b: Double, _ e: Double = 1e-9) -> Bool { a.map { abs($0 - b) <= e } ?? false }

// MARK: - The numbers

check(P.countFrom == 3 && P.askAtCount == 1, "3, 2, 1, the ask at 1")
check(P.hostSpacing == 1, "the Mac takes one ask a second: \(P.hostSpacing)")
check(P.startAsks == 3 && P.startGiveUp == 10, "three asks, then give up 10 s after the light")
check(P.prerollLimit == 32 << 20 && P.pendingLimit == 32 << 20, "the pre-roll and the pending bound, 32 MB each")
check(P.fragmentInterval == 4, "fragments every 4 s")
check(P.startFloor == 1_500_000_000 && P.warnFloor == 3_000_000_000 && P.stopFloor == 1_000_000_000 && P.warnMinutes == 5,
      "decision 11: start from 1.5 GB, warn under 3 GB or 5 minutes, stop under 1 GB")
check(P.spaceEvery == 5 && P.rateWindow == 10 && P.mostMinutes == 999, "a look every 5 s, the rate over 10 s, at most 999 min")
check(P.soundBitrate == 160_000 && P.soundBytesPerSecond == 20_000 && P.containerShare == 0.01, "the light's bytes")
check(Clock.floorWindow == 10 && Clock.stepFrames == 3 && Clock.stepLimit == 1, "the clock's floor and steps")
check(Clock.videoTimescale == 90_000 && Clock.soundRate == 48_000 && near(Clock.tick, 1.0 / 90_000), "the timescales")
check(Sound.rate == 48_000 && Sound.driftLimit == 0.020 && Sound.soundLag == 0.5 && Sound.fadeFrames == 240 && Sound.dedupeCount == 256,
      "the sound's numbers")
check(RecordingTimeline<Int>.sourceBase == 10, "the writer's times start 10 s before 0:00")

// MARK: - 1. Offered

for phase in [P.Phase.idle, .finishing] {
    check(P.row(phase, connected: true, streaming: true, pictureCame: true) == .start, "\(phase): Start")
    check(P.row(phase, connected: false, streaming: true, pictureCame: true) == .startDimmed(.notConnected), "\(phase): no session")
    check(P.row(phase, connected: true, streaming: false, pictureCame: true) == .startDimmed(.nothingStreams), "\(phase): nothing streams")
    check(P.row(phase, connected: true, streaming: true, pictureCame: false) == .startDimmed(.nothingStreams), "\(phase): no picture yet")
}
for connected in [true, false] {
    check(P.row(.counting(2), connected: connected, streaming: true, pictureCame: true) == .cancel, "the count: Cancel")
    check(P.row(.starting, connected: connected, streaming: false, pictureCame: false) == .stop, "Starting…: Stop")
    check(P.row(.recording, connected: connected, streaming: true, pictureCame: true) == .stop, "the light: Stop")
}
check(P.startAllowed(freeBytes: nil), "space unknown: allowed")
check(P.startAllowed(freeBytes: 1_500_000_000) && !P.startAllowed(freeBytes: 1_499_999_999), "the start's floor at 1.5 GB exactly")
check(P.soundRow(macHasSound: false, sendAudio: nil) == .hidden && P.soundRow(macHasSound: false, sendAudio: true) == .hidden,
      "a Mac without sound: no Record Sound")
check(P.soundRow(macHasSound: true, sendAudio: true) == .shown, "Send Audio on: shown")
check(P.soundRow(macHasSound: true, sendAudio: false) == .dimmed && P.soundRow(macHasSound: true, sendAudio: nil) == .dimmed,
      "Send Audio off: dimmed")
check(P.recordsSound(switchOn: true, sendAudio: true), "sound: the switch and Send Audio on")
check(!P.recordsSound(switchOn: true, sendAudio: false) && !P.recordsSound(switchOn: true, sendAudio: nil)
      && !P.recordsSound(switchOn: false, sendAudio: true), "no sound otherwise")

// MARK: - 2. The count and the asks

check(P.count(elapsed: 0) == 3 && P.count(elapsed: 1) == 2 && P.count(elapsed: 2) == 1, "3, 2, 1")
check(P.count(elapsed: 3) == nil && P.count(elapsed: -1) == nil, "then the light")
check(P.keyframeAsk(now: 100, lastAsk: nil, recoveryDueUntil: nil) == .now, "no ask before: now")
check(P.keyframeAsk(now: 100, lastAsk: 99.5, recoveryDueUntil: nil) == .at(100.5), "half a second after another: held to its second")
check(P.keyframeAsk(now: 100, lastAsk: 99.0001, recoveryDueUntil: nil) == .at(100.0001), "just inside the second: held")
check(P.keyframeAsk(now: 100, lastAsk: 99, recoveryDueUntil: nil) == .now, "a second after: now")
check(P.keyframeAsk(now: 100, lastAsk: 100.5, recoveryDueUntil: nil) == .now, "a last ask after now (another clock): now")
let held = 100.3 + P.hostSpacing
check(P.keyframeAsk(now: held, lastAsk: 100.3, recoveryDueUntil: nil) == .now, "an ask held to its time goes then")
// Against a recovery's ask at every age (its wait 4 s): awaited while due, then the spacing.
for tenth in 0...60 {
    let age = Double(tenth) / 10, now = 200.0, asked = now - age
    let open = P.keyframeAsk(now: now, lastAsk: asked, recoveryDueUntil: asked + 4)
    let want: P.Ask = age < 4 ? .awaitRecovery : (age < 1 ? .at(asked + 1) : .now)
    check(open == want, "a recovery's ask \(age) s old, its interruption open: \(open)")
    let closed = P.keyframeAsk(now: now, lastAsk: asked, recoveryDueUntil: nil)
    check(closed == (age < 1 ? .at(asked + 1) : .now), "a recovery's ask \(age) s old, the picture back: \(closed)")
}
check(P.keyframeAsk(now: 300, lastAsk: 299.8, recoveryDueUntil: 300) == .at(300.8), "a recovery due until now: no longer awaited")
// "Starting…": asks at the recovery's wait, at most three, then the give-up 10 s after the light.
check(P.starting(now: 100, lightAt: 100, asks: 1, lastAsk: 99, wait: 4) == .askAt(103), "the second ask 4 s after the first")
check(P.starting(now: 103, lightAt: 100, asks: 2, lastAsk: 103, wait: 4) == .askAt(107), "the third 4 s later")
check(P.starting(now: 107, lightAt: 100, asks: 3, lastAsk: 107, wait: 4) == .giveUpAt(110), "three made: the give-up")
check(P.starting(now: 100, lightAt: 100, asks: 3, lastAsk: 99, wait: 4) == .giveUpAt(110), "never a fourth, whatever time is left")
check(P.starting(now: 110, lightAt: 100, asks: 3, lastAsk: 107, wait: 4) == .giveUp, "at 10 s: give up")
check(P.starting(now: 109.99, lightAt: 100, asks: 1, lastAsk: 99, wait: 4) == .askAt(109.99), "an overdue ask goes now")
check(P.starting(now: 100, lightAt: 100, asks: 1, lastAsk: 99, wait: 8) == .askAt(107), "a slow link's wait")
check(P.starting(now: 107, lightAt: 100, asks: 2, lastAsk: 107, wait: 8) == .giveUpAt(110), "no ask whose wait outlasts the give-up")
check(P.starting(now: 100, lightAt: 100, asks: 0, lastAsk: nil, wait: 4) == .askAt(104), "no ask yet: one a wait from now")
check(P.starting(now: 100, lightAt: 100, asks: 2, lastAsk: 105.9, wait: 4) == .askAt(109.9), "an ask due at 109.9 is made…")
check(P.starting(now: 100, lightAt: 100, asks: 2, lastAsk: 106, wait: 4) == .giveUpAt(110), "…one due at 110 is not")

// MARK: - 3. Where the movie starts, and the pre-roll

check(P.start(keyframeSinceAsk: true, lastKeyframeKept: false, framesSinceKeyframe: 9) == .atLight(.sinceAsk), "a keyframe since the ask")
check(P.start(keyframeSinceAsk: true, lastKeyframeKept: true, framesSinceKeyframe: 0) == .atLight(.sinceAsk), "fresh before kept")
check(P.start(keyframeSinceAsk: false, lastKeyframeKept: true, framesSinceKeyframe: 0) == .atLight(.lastKeyframe), "still: the last keyframe")
check(P.start(keyframeSinceAsk: false, lastKeyframeKept: true, framesSinceKeyframe: 1) == .atNextKeyframe, "a frame since it: the next")
check(P.start(keyframeSinceAsk: false, lastKeyframeKept: false, framesSinceKeyframe: 0) == .atNextKeyframe, "nothing kept: the next")
var pre = P.Preroll<Int>(limit: 100)
pre.take(1, bytes: 10, isKeyframe: false)
check(pre.frames.isEmpty && !pre.holdsKeyframe, "a delta before any keyframe is not kept")
pre.take(2, bytes: 40, isKeyframe: true); pre.take(3, bytes: 10, isKeyframe: false)
check(pre.frames == [2, 3] && pre.bytes == 50 && pre.holdsKeyframe, "a keyframe and what follows")
pre.take(4, bytes: 20, isKeyframe: true); pre.take(5, bytes: 10, isKeyframe: false)
check(pre.frames == [4, 5] && pre.bytes == 30, "a newer keyframe: only its chain")
pre.take(6, bytes: 70, isKeyframe: false)
check(pre.frames == [4, 5, 6] && pre.bytes == 100 && pre.holdsKeyframe, "up to the limit exactly")
pre.take(7, bytes: 1, isKeyframe: false)
check(pre.frames.isEmpty && !pre.holdsKeyframe && pre.waiting, "past it: dropped until the next keyframe")
pre.take(8, bytes: 5, isKeyframe: false)
check(pre.frames.isEmpty, "a delta then is not kept")
pre.take(9, bytes: 101, isKeyframe: true)
check(pre.frames.isEmpty && !pre.holdsKeyframe, "a keyframe alone past the limit")
pre.take(10, bytes: 60, isKeyframe: true)
check(pre.frames == [10] && pre.holdsKeyframe, "the next keyframe starts again")
check(P.Preroll<Int>().limit == P.prerollLimit, "the pre-roll's limit by default")
pre.newSource()
check(pre.frames.isEmpty && pre.waiting && !pre.holdsKeyframe, "new sets: nothing kept is the picture")
pre.take(11, bytes: 5, isKeyframe: false)
check(pre.frames.isEmpty, "a delta then waits")
pre.take(12, bytes: 5, isKeyframe: true)
check(pre.frames == [12], "the new source's keyframe")

// MARK: - 5. The picture's chain

var chain = P.PictureChain()
check(chain.fate(stamp: 1, isKeyframe: false) == .waitForKeyframe, "no keyframe yet: a delta waits")
check(chain.fate(stamp: 2, isKeyframe: true) == .write, "a keyframe is written"); chain.written(stamp: 2)
check(chain.fate(stamp: 3, isKeyframe: false) == .write, "a delta while whole"); chain.written(stamp: 3)
check(chain.fate(stamp: 3, isKeyframe: false) == .duplicate && chain.fate(stamp: 2, isKeyframe: true) == .duplicate,
      "delivered twice: dropped, the chain whole")
check(chain.whole, "duplicates keep the chain")
check(chain.lost(), "a frame not written breaks it: one ask")
check(!chain.lost(), "a second loss asks nothing more")
check(chain.fate(stamp: 4, isKeyframe: false) == .waitForKeyframe, "a delta waits for the next keyframe")
check(chain.fate(stamp: 5, isKeyframe: true) == .write && chain.whole, "the keyframe makes it whole")
chain.written(stamp: 5)
check(chain.dropped == 4, "four counted: the delta before any keyframe, two losses and the delta that waited (\(chain.dropped))")
chain.restart()
check(!chain.whole && chain.dropped == 4, "a part's close: waits for a keyframe, nothing lost")
var many = P.PictureChain(); _ = many.fate(stamp: 0, isKeyframe: true)
for s in 0...P.PictureChain.stampsKept { many.written(stamp: Double(s)) }
check(many.fate(stamp: 0, isKeyframe: false) == .write && many.fate(stamp: 1, isKeyframe: false) == .duplicate,
      "the last \(P.PictureChain.stampsKept) stamps are remembered")

// MARK: - 6. Parts and names

check(!P.endsPart(current: Optional<Int>.none, incoming: 1) && !P.endsPart(current: 1, incoming: 1) && P.endsPart(current: 1, incoming: 2),
      "only different sets end a part")
let utc = TimeZone(identifier: "UTC")!
var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = utc
let moment = gregorian.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 14, minute: 3, second: 12))!
let early = gregorian.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 4, second: 5))!
func none(_ name: String) -> Bool { false }
check(P.fileName(start: moment, part: 1, timeZone: utc, taken: none) == "Sill 2026-11-18 at 14.03.12.mov", "the first part's name")
check(P.fileName(start: moment, part: 2, timeZone: utc, taken: none) == "Sill 2026-11-18 at 14.03.12 (2).mov", "the second's")
check(P.fileName(start: early, part: 1, timeZone: utc, taken: none) == "Sill 2026-01-02 at 00.04.05.mov", "two digits, 24 hours")
check(P.fileName(start: moment, part: 1, timeZone: TimeZone(identifier: "Asia/Tokyo")!, taken: none) == "Sill 2026-11-18 at 23.03.12.mov",
      "the device's own time zone")
check(P.fileName(start: moment, part: 1, timeZone: TimeZone(identifier: "America/Los_Angeles")!, taken: none) == "Sill 2026-11-18 at 06.03.12.mov",
      "in the morning: 06, not 6 AM")
check(P.fileName(start: moment, part: 1, timeZone: utc, taken: { $0 == "Sill 2026-11-18 at 14.03.12.mov" })
      == "Sill 2026-11-18 at 14.03.12 (2).mov", "a name taken: the next number")
check(P.fileName(start: moment, part: 2, timeZone: utc,
                 taken: { ["Sill 2026-11-18 at 14.03.12 (2).mov", "Sill 2026-11-18 at 14.03.12 (3).mov"].contains($0) })
      == "Sill 2026-11-18 at 14.03.12 (4).mov", "two taken: the next free one")
// Whatever this process's calendar and locale: the Gregorian year, POSIX digits.
let buddhist = DateFormatter(); buddhist.calendar = Calendar(identifier: .buddhist); buddhist.dateFormat = "yyyy"; buddhist.timeZone = utc
check(buddhist.string(from: moment) == "2569" && P.fileName(start: moment, part: 1, timeZone: utc, taken: none).contains("2026"),
      "a Buddhist calendar says 2569; the name says 2026")

// MARK: - 8. What ends it

let ends: [(P.Event, P.Ending?)] = [
    (.stopTapped, .stop), (.cancelTapped, .cancel), (.sessionEnded, .sessionEnded), (.appToBackground, .leftScreen),
    (.sceneToBackground, .leftScreen), (.pictureInPicture, .leftScreen), (.deviceLock, .deviceLocked), (.spaceStop, .space),
    (.writerFailed("x"), .writerFailed("x")), (.startGaveUp, .gaveUp),
    (.move, nil), (.macLocked, nil), (.otherUser, nil), (.newSize, nil), (.linkBehind, nil), (.sendAudioOff, nil), (.mute, nil),
    (.settingsOpen, nil),
]
for (event, want) in ends { check(P.ending(event) == want, "\(event): \(String(describing: P.ending(event)))") }

// MARK: - 9. Space

check(P.space(freeBytes: 999_999_999, bytesPerSecond: 0) == .stop, "under 1 GB: stop")
check(P.space(freeBytes: 1_000_000_000, bytesPerSecond: 0) == .low(minutesLeft: 999), "1 GB, still: low, the most minutes")
check(P.space(freeBytes: 2_999_999_999, bytesPerSecond: 1_000_000) == .low(minutesLeft: 33), "under 3 GB: low, 33 minutes")
check(P.space(freeBytes: 3_000_000_000, bytesPerSecond: 0) == .fine, "3 GB, still: fine")
check(P.space(freeBytes: 3_000_000_000, bytesPerSecond: 1_000_000) == .fine, "3 GB at 1 MB/s (33 minutes): fine")
check(P.space(freeBytes: 10_000_000_000, bytesPerSecond: 30_000_000) == .fine, "exactly 5 minutes left: fine")
check(P.space(freeBytes: 10_000_000_000, bytesPerSecond: 30_000_001) == .low(minutesLeft: 4), "just under 5: low, 4")
check(P.space(freeBytes: 1_000_000_001, bytesPerSecond: 1e9) == .low(minutesLeft: 1), "at least 1 minute")
check(P.space(freeBytes: 2_000_000_000, bytesPerSecond: 1) == .low(minutesLeft: 999), "at most 999")
check(P.space(freeBytes: 2_000_000_000, bytesPerSecond: 3_333_333) == .low(minutesLeft: 5), "1 GB of room at 3.3 MB/s: 5 minutes")
check(near(P.rate([(0, 0), (5, 1_000_000), (10, 6_000_000)], now: 10), 1_000_000), "the rate over the last 10 s, the sample 10 s back left out")
check(near(P.rate([(1, 0), (5, 4_000_000), (10, 9_000_000)], now: 10), 1_000_000), "from the window's first sample")
check(P.rate([(9.5, 0), (10, 1_000_000)], now: 10) == 0 && P.rate([(10, 1)], now: 10) == 0, "under a second: nothing")

// MARK: - 10. The light

let times: [(Double, String)] = [(0, "0:00"), (42.9, "0:42"), (59.99, "0:59"), (60, "1:00"), (3599, "59:59"), (3600, "1:00:00"),
                                 (3723, "1:02:03"), (-1, "0:00"), (36_000, "10:00:00")]
for (s, want) in times { check(P.time(s) == want, "\(s) s: \(P.time(s))") }
let sizes: [(Int64, String)] = [(0, "0 MB"), (999_999, "0 MB"), (1_000_000, "1 MB"), (126_400_000, "126 MB"), (999_999_999, "999 MB"),
                                (1_000_000_000, "1.0 GB"), (1_400_000_000, "1.4 GB"), (1_499_999_999, "1.4 GB"), (12_345_678_901, "12.3 GB")]
for (b, want) in sizes { check(P.size(b) == want, "\(b) bytes: \(P.size(b))") }
check(P.bytes(frames: 1_000_000, soundSeconds: 10) == 1_210_000, "frames, 20 kB a second of sound, 1%")
check(P.bytes(frames: 0, soundSeconds: 0) == 0 && P.bytes(frames: 100, soundSeconds: -1) == 101, "nothing yet")
typealias C = P.Copy
check(C.light(seconds: nil, bytes: 0, minutesLeft: nil) == "Starting…", "before the first frame")
check(C.light(seconds: 42, bytes: 126_000_000, minutesLeft: nil) == "0:42 · 126 MB", "the light")
check(C.light(seconds: 3723, bytes: 1_400_000_000, minutesLeft: 4) == "1:02:03 · 1.4 GB · 4 min left", "the light, low")
check(C.lightSpoken(seconds: 42, bytes: 126_000_000, minutesLeft: nil) == "Recording, 42 seconds, 126 megabytes", "spoken")
check(C.lightSpoken(seconds: 102, bytes: 230_000_000, minutesLeft: nil) == "Recording, 1 minute 42 seconds, 230 megabytes", "spoken")
check(C.lightSpoken(seconds: 61, bytes: 1_000_000, minutesLeft: 1)
      == "Recording, 1 minute 1 second, 1 megabyte, space for about 1 minute", "the singulars")
check(C.lightSpoken(seconds: 3723, bytes: 1_400_000_000, minutesLeft: 4)
      == "Recording, 1 hour 2 minutes 3 seconds, 1.4 gigabytes, space for about 4 minutes", "hours, gigabytes")
check(C.spokenTime(3600) == "1 hour" && C.spokenTime(0) == "0 seconds" && C.spokenTime(120) == "2 minutes", "no zero parts")
check(C.lightSpoken(seconds: nil, bytes: 0, minutesLeft: nil) == "Starting the recording", "Starting…, spoken")
check(C.topRow(seconds: 102, bytes: 230_000_000, minutesLeft: nil) == "Recording · 1:42 · 230 MB", "the top row")
check(C.topRow(seconds: nil, bytes: 0, minutesLeft: nil) == "Starting…", "the top row before the first frame")
check(C.topRowSpoken(seconds: 102, bytes: 230_000_000, minutesLeft: nil)
      == "Stop Recording. Recording, 1 minute 42 seconds, 230 megabytes.", "the top row, spoken")
check(C.lowSpoken(4) == "Space for about 4 more minutes of recording." && C.lowSpoken(1) == "Space for about 1 more minute of recording.",
      "low, spoken once")
check(C.countSpoken(3) == "Recording in 3" && C.countSpoken(2) == "2" && C.countSpoken(1) == "1" && C.count(2) == "2", "the count")
check(C.start == "Start Recording" && C.cancel == "Cancel Recording" && C.stop == "Stop Recording" && C.recordSound == "Record Sound"
      && C.dimmedHint == "Pick a window or the Desktop first." && C.startSpoken == "Recording", "the rows' words")

// MARK: - 11. The Mac is told, and the footnote

check(P.recordingField(true) == true && P.recordingField(false) == nil, "true or left out, never false")
check(!P.reports(.idle) && !P.reports(.counting(1)) && P.reports(.starting) && P.reports(.recording) && P.reports(.finishing),
      "from the light until the movie is closed")
let versions: [(String?, Bool)] = [(nil, false), ("0.5.1", false), ("0.5.0", false), ("0.5", false), ("0.4.9", false), ("garbage", false),
                                   ("0.5.2", true), ("0.5.1.1", true), ("0.6", true), ("0.6.3", true), ("1.0", true), ("0.6.3 (1304)", true)]
for (v, want) in versions { check(P.macTakesKeyframeAsks(hostVersion: v) == want, "\(v ?? "no version"): takes asks \(want)") }
check(C.macShowsIt(recordings: 1) && C.macShowsIt(recordings: 2) && !C.macShowsIt(recordings: nil) && !C.macShowsIt(recordings: 0),
      "the Mac shows it from generation 1")
check(C.footnote(mac: "Studio", device: "iPad", macShowsIt: true, soundRow: .shown)
      == "Saves what Studio shows as a movie in Files › On My iPad › Sill › Sill Recordings, without Sill’s controls or Studio’s pointer, "
      + "until you delete it or Sill. Everything on the screen is recorded, its lock screen and what you type included. While it records, "
      + "Sill’s menu on Studio says so.", "the footnote: \(C.footnote(mac: "Studio", device: "iPad", macShowsIt: true, soundRow: .shown))")
check(C.footnote(mac: nil, device: "iPhone", macShowsIt: false, soundRow: .dimmed)
      == "Saves what the Mac shows as a movie in Files › On My iPhone › Sill › Sill Recordings, without Sill’s controls or the Mac’s "
      + "pointer, until you delete it or Sill. Everything on the screen is recorded, its lock screen and what you type included. The Mac "
      + "runs an older Sill, so its menu won’t say that this iPhone is recording. Turn on Send Audio above to record the Mac’s sound.",
      "an older Mac, Send Audio off")
check(!C.footnote(mac: "M", device: "iPad", macShowsIt: true, soundRow: .hidden).contains("Send Audio"), "no Send Audio sentence without sound")
check(C.noSpace(device: "iPad") == "There isn’t enough space on this iPad to record. Free up some space first.", "no space")
check(C.writerReason(domain: "AVFoundationErrorDomain", code: -11807, description: "x", device: "iPad") == "this iPad ran out of space"
      && C.writerReason(domain: "NSCocoaErrorDomain", code: 640, description: "x", device: "iPhone") == "this iPhone ran out of space",
      "out of space")
check(C.writerReason(domain: "X", code: 1, description: "The operation could not be completed.", device: "iPad")
      == "the operation could not be completed", "the writer's own words, lower case, no period")
check(C.writerReason(domain: "X", code: 1, description: " ", device: "iPad") == "the movie couldn’t be written", "no words")
func note(_ e: P.Ending, _ movies: Int = 1, failure: String? = nil, asks: Bool = true) -> String? {
    C.note(e, movies: movies, failure: failure, device: "iPad", mac: "Studio", macTakesAsks: asks)
}
check(note(.stop) == "Saved to Files › Sill Recordings.", "saved")
check(note(.stop, 3) == "Saved 3 movies to Files › Sill Recordings, one for each picture size.", "saved, three parts")
check(note(.stop, 0) == "Nothing was recorded.", "stopped while Starting…")
check(note(.cancel, 0) == nil, "cancelled: nothing to say")
check(note(.leftScreen) == "Your recording was saved when Sill left the screen. It’s in Files › Sill Recordings."
      && note(.deviceLocked) == note(.leftScreen), "left the screen, the device's lock")
check(note(.sessionEnded, 2) == "Your recording was saved when the session ended. It’s in Files › Sill Recordings.", "the session ended")
check(note(.space) == "Recording stopped: this iPad is almost out of space. What was recorded is in Files › Sill Recordings.", "space")
check(note(.writerFailed("this iPad ran out of space")) == "Recording stopped: this iPad ran out of space. What was recorded is in Files › Sill Recordings.",
      "the writer failed with something kept")
check(note(.writerFailed("x"), 0) == "Couldn’t save the recording: x.", "the writer failed with nothing")
check(note(.stop, failure: "y") == "Recording stopped: y. What was recorded is in Files › Sill Recordings.", "a finish that failed")
check(note(.gaveUp, 0) == "Couldn’t start recording: Studio didn’t send a full picture.", "gave up")
check(note(.gaveUp, 0, asks: false) == "Couldn’t start recording: Studio didn’t send a full picture. Update Sill on Studio, then try again.",
      "gave up, an older Mac")
check(C.mac(nil) == "the Mac" && C.mac("") == "the Mac" && C.macFirst(nil) == "The Mac" && C.macs("Studio") == "Studio’s", "the Mac's names")

// MARK: - SillDocuments

check(SillDocuments.name(.recordings) == "Sill Recordings", "the folder's name")
check(SillDocuments.protection(.recordings) == .completeUnlessOpen, "readable only while unlocked, an open movie finished at the lock")
let docs = SillDocuments.url(.recordings)
check(docs.lastPathComponent == "Sill Recordings" && docs.deletingLastPathComponent().lastPathComponent == "Documents", "Documents/Sill Recordings")

// MARK: - The clock

// A steady stream: stamps 1000 + t, arrivals 50 + t + 10 ms; the light at arrival 51.
var clock = Clock()
for i in 0..<60 { clock.seed(stamp: 1000 + Double(i) / 60, arrival: 50.01 + Double(i) / 60) }
check(near(clock.floor, 50.01 - 1000), "the floor: the least arrival − stamp")
check(clock.sound(stamp: 1000) == nil && clock.stop(arrival: 60) == nil, "no times before the anchor")
check(clock.anchorAtLight(arrival: 51), "anchored at the light")
check(near(clock.anchor, 51 - (50.01 - 1000)), "the anchor: the light on the Mac's clock")
var t = clock.picture(stamp: 1001.5, arrival: 51.51)
check(near(t, 1001.5 - 1000.99), "T = S − anchor: \(t)")
clock.written(t)
check(near(clock.sound(stamp: 1001.2), 1001.2 - 1000.99), "the sound through the same anchor")
check(near(clock.stop(arrival: 61.01), 61.01 - (50.01 - 1000) - 1000.99), "the stop at its arrival")
check(near(clock.stop(arrival: 51.0), t + Clock.tick), "never before the last picture: \(clock.stop(arrival: 51.0) ?? -1)")
// The Mac's clock steps forward 5 s: one picture more than 1 s under the floor; T goes on with the arrivals.
let before = t
t = clock.picture(stamp: 1001.5 + 5 + 1.0 / 60, arrival: 51.51 + 1.0 / 60)
check(clock.steps == 1 && near(t, before + 1.0 / 60), "a step forward: no jump (\(t - before))")
clock.written(t)
let after = clock.picture(stamp: 1001.5 + 5 + 2.0 / 60, arrival: 51.51 + 2.0 / 60)
check(near(after, t + 1.0 / 60, 1e-6) && clock.steps == 1, "then by the stamps again: \(after - t)")
clock.written(after)
// It steps back 5 s: two pictures held right after the last, the third is the step.
var last = after
for k in 3...4 {
    let x = clock.picture(stamp: 1001.5 + Double(k) / 60, arrival: 51.51 + Double(k) / 60)
    check(near(x, last + Clock.tick) && clock.steps == 1, "a step back, picture \(k - 2): held right after the last")
    clock.written(x); last = x
}
let third = clock.picture(stamp: 1001.5 + 5.0 / 60, arrival: 51.51 + 5.0 / 60)
check(clock.steps == 2 && near(third, last + 1.0 / 60, 1e-6), "the third is the step: on with the arrivals (\(third - last))")
clock.written(third)
check(near(clock.stop(arrival: 51.51 + 5.0 / 60 + 2), third + 2, 1e-6), "the stop goes on from the step: \(clock.stop(arrival: 51.51 + 5.0 / 60 + 2) ?? -1)")
check(near(clock.sound(stamp: 1001.5 + 5.0 / 60), third, 1e-6), "the sound gets the step's correction too")
// A stall: three pictures 1.5 s late make a step, the next on time another; the times never go back.
var stall = Clock()
for i in 0..<30 { stall.seed(stamp: Double(i) / 30, arrival: 10 + Double(i) / 30) }
_ = stall.anchorAtLight(arrival: 11)
var prev = stall.picture(stamp: 1.0, arrival: 11.0); stall.written(prev)
for (k, late) in [(1, 1.5), (2, 1.5), (3, 1.5), (4, 0.0), (5, 0.0)] {
    let x = stall.picture(stamp: 1.0 + Double(k) / 30, arrival: 11 + Double(k) / 30 + late)
    check(x > prev, "a stall's picture \(k) comes after the last")
    stall.written(x); prev = x
}
check(stall.steps == 2, "the stall made a step and its end another: \(stall.steps)")
// Two late pictures make no step: they keep their stamps.
var two = Clock()
for i in 0..<30 { two.seed(stamp: Double(i) / 30, arrival: 10 + Double(i) / 30) }
_ = two.anchorAtLight(arrival: 11)
let y1 = two.picture(stamp: 1.0, arrival: 12.5), y2 = two.picture(stamp: 1.0 + 1.0 / 30, arrival: 12.5 + 1.0 / 30)
check(two.steps == 0 && near(y1, 0) && near(y2, 1.0 / 30), "two late pictures: no step, their stamps' times")
// The floor's window: a lower floor is forgotten after 10 s; with no picture it keeps its value.
var window = Clock()
window.seed(stamp: 0, arrival: 100.0)            // A − S = 100
window.seed(stamp: 5, arrival: 105.5)            // 100.5
check(near(window.floor, 100), "the least")
window.seed(stamp: 9.5, arrival: 110.0)          // 100.5, at second 110: the bucket of second 100 is gone
check(near(window.floor, 100.5), "10 s later the 100 is forgotten: \(window.floor ?? -1)")
check(near(window.floor, 100.5), "and kept with no picture since")
// Anchored at a keyframe: its T is 0.
var next = Clock()
next.seed(stamp: 1, arrival: 2)
next.anchorAt(stamp: 7)
check(near(next.picture(stamp: 7, arrival: 8), 0), "the keyframe's T is 0:00")
// A step while "Starting…" (the seeds), then the keyframe: still 0:00.
var stepped = Clock()
for i in 0..<10 { stepped.seed(stamp: 100 + Double(i) / 10, arrival: 5 + Double(i) / 10) }
stepped.seed(stamp: 110, arrival: 6.05)
check(stepped.steps == 1 && stepped.correction != 0, "a step among the seeds: \(stepped.correction)")
stepped.anchorAt(stamp: 110.1)
check(near(stepped.picture(stamp: 110.1, arrival: 6.15), 0, 1e-9), "the keyframe after it is still 0:00")
check(Clock.ticks(1) == 90_000 && Clock.ticks(1.0 / 60) == 1500 && Clock.frames(1) == 48_000 && Clock.frames(0.01) == 480, "ticks and frames")
var unanchored = Clock()
check(!unanchored.anchorAtLight(arrival: 5) && unanchored.anchor == nil, "no floor, no anchor at the light")


// MARK: - The sound

let F = Sound.Format(framesPerPacket: 480, primingFrames: 240)
var snd = Sound()
check(snd.packet(epoch: 1, seq: 0, index: 0, segmentStart: true, time: 1).0 == .skip, "no format for the epoch: ignored")
snd.format(epoch: 1, F)
var r = snd.packet(epoch: 1, seq: 0, index: 0, segmentStart: true, time: 1.0)
check(r.0 == .decode(reset: true) && r.1 == [.silence(48_240), .packet(index: 0, from: 240, count: 240, fadeIn: true, hold: 240)],
      "a segment start: priming dropped, by its stamp plus priming, faded in: \(r.1)")
r = snd.packet(epoch: 1, seq: 1, index: 0, segmentStart: false, time: 1.01)
check(r.0 == .decode(reset: false) && r.1 == [.tail(fadeOut: false), .packet(index: 0, from: 0, count: 480, fadeIn: false, hold: 240)],
      "the next seq follows, sample-exact: \(r.1)")
r = snd.packet(epoch: 1, seq: 2, index: 0, segmentStart: false, time: 1.02 + 0.0199)
check(r.1 == [.tail(fadeOut: false), .packet(index: 0, from: 0, count: 480, fadeIn: false, hold: 240)], "19.9 ms off: still follows: \(r.1)")
r = snd.packet(epoch: 1, seq: 3, index: 0, segmentStart: false, time: 1.03 + 0.03)
check(r.1 == [.tail(fadeOut: true), .silence(1440), .packet(index: 0, from: 0, count: 480, fadeIn: true, hold: 240)],
      "30 ms off: by its stamp, the tail faded out, silence, faded in: \(r.1)")
check(snd.packet(epoch: 1, seq: 3, index: 0, segmentStart: false, time: 1.06) == (.skip, []), "a duplicate: ignored")
r = snd.packet(epoch: 1, seq: 5, index: 0, segmentStart: false, time: 1.08)
check(r.0 == .decode(reset: true) && r.1.isEmpty, "a skipped seq: decoded to noise and dropped")
r = snd.packet(epoch: 1, seq: 6, index: 0, segmentStart: false, time: 1.09)
check(r.0 == .decode(reset: false) && r.1 == [.tail(fadeOut: true), .silence(960), .packet(index: 0, from: 0, count: 480, fadeIn: true, hold: 240)],
      "the next by its stamp, faded in: \(r.1)")
var behind = Sound(); behind.format(epoch: 1, F)
_ = behind.packet(epoch: 1, seq: 0, index: 0, segmentStart: true, time: 1.0)
check(behind.follow(picture: 3.0) == [.tail(fadeOut: true), .silence(120_000 - 48_480)], "the picture 3 s in: silence to 2.5 s")
check(behind.packet(epoch: 1, seq: 1, index: 0, segmentStart: false, time: 1.01) == (.decode(reset: false), []),
      "a packet wholly behind the track's end: decoded, dropped")
check(behind.follow(picture: 2.9).isEmpty && behind.end == 120_000, "never ahead of the picture's lag")
var partly = Sound(); partly.format(epoch: 1, F)
_ = partly.packet(epoch: 1, seq: 0, index: 0, segmentStart: true, time: 1.0)
_ = partly.packet(epoch: 1, seq: 5, index: 0, segmentStart: false, time: 2)
r = partly.packet(epoch: 1, seq: 6, index: 0, segmentStart: false, time: Double(48_480 - 100) / 48_000)
check(r.1 == [.tail(fadeOut: true), .packet(index: 0, from: 100, count: 380, fadeIn: true, hold: 240)],
      "100 frames behind the end: those trimmed, faded in: \(r.1)")
let stopW = partly.stop(at: Double(partly.end + 960) / 48_000)
check(stopW == [.tail(fadeOut: true), .silence(960)] && partly.held == 0, "the stop: the tail out, silence to it: \(stopW)")
check(partly.stop(at: 0).isEmpty, "a second stop: nothing")
var join = Sound(); join.format(epoch: 4, F)
check(join.packet(epoch: 4, seq: 77, index: 0, segmentStart: false, time: 3) == (.decode(reset: true), []),
      "the first packet seen mid-segment is a join")
check(join.packet(epoch: 4, seq: 80, index: 1, segmentStart: true, time: 3) == (.decode(reset: true), []),
      "the flag counts only for a message's first packet: a gap, a join")
var early2 = Sound(); early2.format(epoch: 2, F)
check(early2.packet(epoch: 2, seq: 0, index: 0, segmentStart: true, time: nil) == (.decode(reset: true), []), "before the anchor: decoded only")
check(early2.packet(epoch: 2, seq: 1, index: 0, segmentStart: false, time: 0.5)
      == (.decode(reset: false), [.silence(24_000), .packet(index: 0, from: 0, count: 480, fadeIn: true, hold: 240)]), "then by its stamp")
var before0 = Sound(); before0.format(epoch: 3, F)
check(before0.packet(epoch: 3, seq: 0, index: 0, segmentStart: true, time: -0.008)
      == (.decode(reset: true), [.packet(index: 0, from: 384, count: 96, fadeIn: true, hold: 96)]), "before 0:00: trimmed to the track's start")
var epochs = Sound(); epochs.format(epoch: 1, F); epochs.format(epoch: 2, F)
_ = epochs.packet(epoch: 1, seq: 3, index: 0, segmentStart: true, time: 0)
check(epochs.packet(epoch: 2, seq: 3, index: 0, segmentStart: true, time: 1).0 == .decode(reset: true), "another epoch's seq is no duplicate")
var memory = Sound(); memory.format(epoch: 1, F)
for q in 0...256 { _ = memory.packet(epoch: 1, seq: UInt32(q), index: 0, segmentStart: q == 0, time: Double(q) / 100) }
check(memory.packet(epoch: 1, seq: 256, index: 0, segmentStart: false, time: 2.56).0 == .skip, "the last 256 are remembered")
check(memory.packet(epoch: 1, seq: 0, index: 0, segmentStart: false, time: 0).0 != .skip, "the 257th back is forgotten")

// MARK: - The timeline, scripted

typealias TL = RecordingTimeline<Int>
func K(_ id: Int, _ s: Double, _ a: Double, key: Bool = false) -> TL.Kept { TL.Kept(id: id, stamp: s, arrival: a, isKeyframe: key) }
func pictureAt(_ a: TL.Action) -> (id: Int, at: Double)? { if case .picture(let id, let at) = a { return (id, at) } else { return nil } }
func closeAt(_ a: TL.Action) -> (part: Int, at: Double)? { if case .close(let n, let at) = a { return (n, at) } else { return nil } }
var tl = TL(withSound: false)
var acts = tl.begin(.atLight(.sinceAsk), sets: 1, preroll: [K(1, 100.2, 10.2, key: true), K(2, 100.3, 10.3)], lastKeyframe: nil,
                    seeds: [(100.2, 10.2), (100.3, 10.3)], light: 11.0)
check(acts.count == 3 && acts[0] == .open(part: 1, sets: 1) && pictureAt(acts[1]).map { $0.id == 1 && near($0.at, -0.8, 1e-6) } == true
      && pictureAt(acts[2]).map { $0.id == 2 && near($0.at, -0.7, 1e-6) } == true, "the pre-roll written before 0:00: \(acts)")
acts = tl.frame(id: 3, stamp: 101.5, isKeyframe: false, arrival: 11.5)
check(acts.count == 1 && pictureAt(acts[0]).map { $0.id == 3 && near($0.at, 0.5, 1e-6) } == true, "a live frame: \(acts)")
check(tl.parameterSets(1, arrival: 11.6).isEmpty, "the same sets again: nothing")
acts = tl.parameterSets(2, arrival: 12.0)
check(acts.count == 1 && closeAt(acts[0]).map { $0.part == 1 && near($0.at, 1.0, 1e-6) } == true, "new sets close the part at their arrival: \(acts)")
check(tl.frame(id: 4, stamp: 102.05, isKeyframe: false, arrival: 12.05).isEmpty, "a delta between parts: dropped")
acts = tl.frame(id: 5, stamp: 102.1, isKeyframe: true, arrival: 12.1)
check(acts.count == 2 && acts[0] == .open(part: 2, sets: 2) && pictureAt(acts[1]).map { $0.id == 5 && $0.at == 0 } == true,
      "the next keyframe opens part 2 at its 0:00: \(acts)")
check(tl.notWritten() == [.askKeyframe], "a picture not written: ask")
check(tl.frame(id: 6, stamp: 102.2, isKeyframe: false, arrival: 12.2).isEmpty, "the next delta waits")
check(tl.lost().isEmpty, "a second loss asks nothing more")
acts = tl.stop(arrival: 15.0)
check(acts.count == 1 && closeAt(acts[0]).map { $0.part == 2 && near($0.at, 2.9, 1e-6) } == true, "the stop closes part 2 at its time: \(acts)")
check(tl.stop(arrival: 16).isEmpty && tl.frame(id: 7, stamp: 103, isKeyframe: true, arrival: 13).isEmpty, "nothing after the stop")
var stillTL = TL(withSound: false)
acts = stillTL.begin(.atLight(.lastKeyframe), sets: 1, preroll: [], lastKeyframe: K(9, 50, 5, key: true), seeds: [(50, 5)], light: 65)
check(acts == [.open(part: 1, sets: 1), .picture(id: 9, at: 0)], "a still picture: the last keyframe at 0:00: \(acts)")
acts = stillTL.stop(arrival: 95)
check(acts.count == 1 && closeAt(acts[0]).map { $0.part == 1 && near($0.at, 30, 1e-6) } == true, "and it lasts until the stop, 30 s: \(acts)")
var waits = TL(withSound: false)
check(waits.begin(.atNextKeyframe, sets: 1, preroll: [], lastKeyframe: nil, seeds: [], light: 5).isEmpty && waits.waitingForStart, "Starting…")
check(waits.frame(id: 1, stamp: 10, isKeyframe: false, arrival: 6).isEmpty, "a delta while Starting…: a seed")
check(waits.frame(id: 2, stamp: 10.5, isKeyframe: true, arrival: 6.5) == [.open(part: 1, sets: 1), .picture(id: 2, at: 0)], "the keyframe is 0:00")
var nothing = TL(withSound: false)
_ = nothing.begin(.atNextKeyframe, sets: 1, preroll: [], lastKeyframe: nil, seeds: [], light: 5)
check(nothing.stop(arrival: 10).isEmpty && nothing.parts == 0, "stopped while Starting…: no movie")
var noPreroll = TL(withSound: false)
_ = noPreroll.begin(.atLight(.sinceAsk), sets: 1, preroll: [K(1, 10, 1)], lastKeyframe: nil, seeds: [(10, 1)], light: 2)
check(noPreroll.waitingForStart && noPreroll.parts == 0, "a pre-roll that does not begin with a keyframe: Starting…")
var withSound = TL(withSound: true)
withSound.audioFormat(epoch: 1, F)
_ = withSound.begin(.atLight(.lastKeyframe), sets: 1, preroll: [], lastKeyframe: K(1, 100, 10, key: true), seeds: [(100, 10)], light: 11)
check(withSound.audio(epoch: 1, seq: 0, index: 0, segmentStart: true, stamp: 101.5)
      == (.decode(reset: true), [.silence(24_240), .packet(index: 0, from: 240, count: 240, fadeIn: true, hold: 240)]),
      "the sound placed on the part's track")
acts = withSound.stop(arrival: 13)
check(acts.count == 2 && acts[0] == .sound([.tail(fadeOut: true), .silence(71_520)]) && closeAt(acts[1]).map { $0.part == 1 && $0.at == 2 } == true,
      "the stop: the sound to its end, then the close: \(acts)")
var noSound = TL(withSound: false)
noSound.audioFormat(epoch: 1, F)
_ = noSound.begin(.atLight(.lastKeyframe), sets: 1, preroll: [], lastKeyframe: K(1, 100, 10, key: true), seeds: [(100, 10)], light: 11)
check(noSound.audio(epoch: 1, seq: 0, index: 0, segmentStart: true, stamp: 101.5) == (.skip, []), "no sound track: nothing decoded")

// MARK: - 20,000 random recordings

// The mutants (mutants.py) stop here when a case above already failed: the random recordings take most of the run.
if failures > 0, ProcessInfo.processInfo.environment["SILL_CHECK_STOP_EARLY"] != nil {
    print("\(checks) checks, \(failures) failed (stopped before the random recordings)")
    exit(1)
}

struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() % UInt64(xs.count))] }
}

/// What the Mac sends.
enum Message {
    case sets(Int)
    case frame(id: Int, stamp: Double, key: Bool)
    case format(epoch: Int)
    case packets(epoch: Int, seq: UInt32, start: Bool, count: Int, stamp: Double)
}

var broken = 0
func broke(_ what: String) { broken += 1; if broken <= 12 { print("FAIL random: \(what)") } }
struct Seen {
    var recordings = 0, sinceAsk = 0, lastKeyframe = 0, nextKeyframe = 0, gaveUp = 0, olderGaveUp = 0, steps = 0, parts = 0,
        duplicates = 0, breaks = 0, joins = 0, trims = 0, follows = 0, byStamp = 0, awaited = 0, stills = 0
}
var seen = Seen()

/// One session of a Mac and this device, and one recording in it: the Mac's stream generated ahead (its answers
/// to the asks added as they are made), the device's side as StreamClient and StreamRecorder do it, the movie as
/// the timeline's actions build it, checked as it goes.
final class Sim {
    var rng: Rng
    let run: Int
    let fps, stillFrom, macBase, devBase, stepAt, stepBy, baseDelay, jitter, stallAt, stallFor: Double
    let older, withSound: Bool
    let tStart, tOne, tLight, tStop, partAt, recoveryAt, epochAt: Double
    let spread: Double
    /// The Mac's messages in their order on the connection: when sent, when they arrive (never before the one
    /// before: one connection), what.
    var queue: [(sent: Double, at: Double, what: Message)] = []
    var keyOf: [Int: Bool] = [:], setsOf: [Int: Int] = [:], arrivedAt: [Int: Double] = [:]
    var nextID = 0
    var macLastTaken = -Double.infinity
    // The device.
    var lastKeyframe: TL.Kept?, lastKeyframeSets = 0, framesSinceKey = 0, currentSets: Int?
    var asks: [Double] = [], recordingAsks: [Double] = []
    var preroll: P.Preroll<TL.Kept>?
    var seeds: [(stamp: Double, arrival: Double)] = []
    var tl: TL?
    var phase = "count"
    var startAsks = 0, lastStartAsk: Double?
    var recoveryAskedAt: Double?, recoveryOpen = false
    var formatsSeen = Set<Int>()
    var timers: [(at: Double, what: String)] = []
    /// An ask the Mac's second holds back is due: one at a time, as StreamClient keeps one.
    var heldAsk = false
    // The movie.
    struct Part {
        var sets: Int
        var lastAt: Double?, lastArrival: Double?, closed: Double?
        var pos: Int64 = 0, held = 0
        var needKey = true
    }
    var parts: [Part] = []

    init(run: Int, rng: Rng) {
        self.run = run
        var g = rng
        fps = g.pick([24.0, 30, 30, 60, 60, 60, 120])
        stillFrom = g.chance(0.15) ? 0 : (g.chance(0.35) ? g.range(0, 10) : .infinity)   // 0: only the first keyframe
        macBase = g.range(1_000, 2_000); devBase = g.range(10, 500)
        stepAt = g.chance(0.2) ? g.range(2, 25) : .infinity
        stepBy = (g.chance(0.5) ? 1 : -1) * g.range(1.5, 8)
        baseDelay = g.range(0.002, 0.06); jitter = g.range(0, 0.02)
        stallAt = g.chance(0.2) ? g.range(2, 25) : .infinity; stallFor = g.range(0.2, 2.5)
        older = g.chance(0.2); withSound = g.chance(0.7)
        tStart = g.range(1, 6); tOne = tStart + 2; tLight = tStart + 3; tStop = tLight + g.range(0.5, 20)
        partAt = g.chance(0.2) ? g.range(tStart, tStop) : .infinity
        recoveryAt = g.chance(0.25) ? g.range(tStart, tLight) : .infinity
        epochAt = g.chance(0.15) ? g.range(tStart, tStop) : .infinity
        spread = 3 * jitter + (stallAt.isFinite ? stallFor : 0) + 1e-6
        self.rng = g
    }

    func mac(_ t: Double) -> Double { macBase + t + (t >= stepAt ? stepBy : 0) }
    func dev(_ t: Double) -> Double { devBase + t }
    func macSets(_ t: Double) -> Int { t >= partAt ? 2 : 1 }
    /// When a message sent at `t` would arrive by itself: the delay, its jitter, a stall holding it to its end.
    func travel(_ t: Double) -> Double {
        if t >= stallAt && t < stallAt + stallFor { return stallAt + stallFor + baseDelay + jitter * rng.unit() }
        return t + baseDelay + jitter * rng.unit()
    }

    func generate() {
        var sends: [(Double, Message)] = []
        let end = tStop + 1
        func frame(_ t: Double, key: Bool) {
            nextID += 1
            keyOf[nextID] = key; setsOf[nextID] = macSets(t)
            if key { sends.append((t, .sets(macSets(t)))) }
            sends.append((t, .frame(id: nextID, stamp: mac(t), key: key)))
            if rng.chance(0.01) { sends.append((t + 0.0001, .frame(id: nextID, stamp: mac(t), key: key))) }   // a move's hand-over
        }
        var k = 0, t = 0.0, changed = false
        while t < end {
            if t >= partAt, !changed { changed = true; frame(t, key: true); k = 1; t += 1 / fps; continue }   // another source
            if t < stillFrom || k == 0 { frame(t, key: k % Int(4 * fps) == 0) }   // the stream's first keyframe always
            k += 1; t += 1 / fps
        }
        if withSound {
            // 10 ms packets in segments, 1 to 3 to a message; the stamp is the first decoded frame's (a segment's
            // priming before its first captured one); now and then one lost or delivered twice; maybe a new epoch.
            sends.append((0, .format(epoch: 1)))
            var epoch = 1, seq: UInt32 = 0, capture = 0.0, segBase = -0.005, inSeg = 0
            while capture < end {
                if capture >= epochAt, epoch == 1 {
                    epoch = 2; seq = 0; inSeg = 0; segBase = capture - 0.005
                    sends.append((capture, .format(epoch: 2)))
                }
                if rng.chance(0.004) { capture += rng.range(0.2, 1.5); inSeg = 0; segBase = capture - 0.005; continue }   // silence
                let n = 1 + Int(rng.next() % 3)
                let stamp = mac(segBase + Double(inSeg) * 0.01)
                let sent = segBase + Double(inSeg + n) * 0.01 + 0.005
                if !rng.chance(0.01) {
                    sends.append((sent, .packets(epoch: epoch, seq: seq, start: inSeg == 0, count: n, stamp: stamp)))
                    if rng.chance(0.01) { sends.append((sent + 0.0001, .packets(epoch: epoch, seq: seq, start: inSeg == 0, count: n, stamp: stamp))) }
                }
                seq &+= UInt32(n); inSeg += n; capture = segBase + 0.005 + Double(inSeg) * 0.01
            }
        }
        sends.sort { $0.0 < $1.0 }
        var last = -Double.infinity
        for (sent, what) in sends {
            let at = max(travel(sent), last)
            last = at
            queue.append((sent, at, what))
        }
    }

    /// The device asks the Mac for a keyframe; the Mac takes one a second (none from before kind 44) and
    /// answers with its picture encoded again, which joins the stream in its order.
    func ask(_ now: Double, recording: Bool) {
        asks.append(now)
        if recording { recordingAsks.append(now) }
        let onMac = now - devBase + baseDelay
        guard !older, onMac - macLastTaken >= 1 else { return }
        macLastTaken = onMac
        let sent = onMac + 0.002
        nextID += 1
        keyOf[nextID] = true; setsOf[nextID] = macSets(sent)
        let i = queue.firstIndex { $0.sent > sent } ?? queue.count
        let at = max(travel(sent), i > 0 ? queue[i - 1].at : -.infinity)
        queue.insert((sent, at, .sets(macSets(sent))), at: i)
        queue.insert((sent, at, .frame(id: nextID, stamp: mac(sent), key: true)), at: i + 1)
        var j = i + 2
        while j < queue.count, queue[j].at < at { queue[j].at = at; j += 1 }
    }

    /// The recording's ask (rule 2): now, at its second, or the recovery's awaited.
    func recordingAsk(_ now: Double, forStart: Bool) {
        let due = recoveryOpen ? recoveryAskedAt.map { $0 + 4 } : nil
        switch P.keyframeAsk(now: now, lastAsk: asks.last, recoveryDueUntil: due) {
        case .now:
            ask(now, recording: true)
            if forStart { startAsks += 1; lastStartAsk = now }
        case .at(let t):
            guard !heldAsk else { return }
            heldAsk = true
            timers.append((t, forStart ? "startask-held" : "ask-held"))
        case .awaitRecovery:
            if forStart { startAsks += 1; lastStartAsk = recoveryAskedAt }
            seen.awaited += 1
        }
    }

    func apply(_ actions: [TL.Action], _ now: Double) {
        var skipping = false
        defer {
            // The track follows the picture: never more than soundLag behind the last picture written.
            if withSound, let p = parts.last, p.closed == nil, let at = p.lastAt, p.pos < Clock.frames(at - Sound.soundLag) {
                broke("run \(run): the sound at \(p.pos) is more than \(Sound.soundLag) s behind the picture at \(at)")
            }
        }
        for a in actions {
            switch a {
            case .open(let n, let s):
                if n != parts.count + 1 { broke("run \(run): part \(n) opened after \(parts.count)") }
                if let p = parts.last, p.closed == nil { broke("run \(run): part \(n) opened before \(parts.count) closed") }
                parts.append(Part(sets: s))
                skipping = false
            case .picture(let id, let at):
                guard !skipping else { continue }   // the rest of a batch after a picture not written
                guard var p = parts.last, p.closed == nil else { broke("run \(run): a picture with no part open"); continue }
                guard let key = keyOf[id], let sets = setsOf[id], let arrival = arrivedAt[id] else { broke("run \(run): an unknown frame"); continue }
                if sets != p.sets { broke("run \(run): frame \(id) of sets \(sets) in a part of \(p.sets)") }
                if p.needKey && !key { broke("run \(run): a delta (\(id)) after an unwritten frame or a part's start") }
                if let prev = p.lastAt {
                    if at < prev + Clock.tick * 0.5 { broke("run \(run): picture times go back: \(prev) then \(at)") }
                    if let pa = p.lastArrival, at - prev > (arrival - pa) + spread + 2 * Clock.tick {
                        broke("run \(run): a jump of \(at - prev) s for \(arrival - pa) s of arrivals (spread \(spread))")
                    }
                }
                p.lastAt = at; p.lastArrival = arrival
                p.needKey = false
                // The writer is not always ready: the chain then waits for a keyframe.
                if rng.chance(0.003), tl != nil {
                    let more = tl!.notWritten()
                    p.needKey = true; seen.breaks += 1; skipping = true
                    parts[parts.count - 1] = p
                    for m in more where m == .askKeyframe { recordingAsk(now, forStart: false) }
                    continue
                }
                parts[parts.count - 1] = p
            case .sound(let writes):
                guard var p = parts.last, p.closed == nil else { broke("run \(run): sound with no part open"); continue }
                for w in writes {
                    switch w {
                    case .silence(let n):
                        if n <= 0 || p.held > 0 { broke("run \(run): silence \(n) with \(p.held) held") }
                        p.pos += Int64(n)
                    case .tail:
                        if p.held <= 0 { broke("run \(run): a tail with nothing held") }
                        p.held = 0
                    case .packet(_, let from, let count, _, let hold):
                        if count <= 0 || from < 0 || from + count > 480 || p.held > 0 || hold > count || hold > Sound.fadeFrames {
                            broke("run \(run): packet from \(from) count \(count) hold \(hold) with \(p.held) held")
                        }
                        p.pos += Int64(count); p.held = hold
                    }
                }
                parts[parts.count - 1] = p
            case .close(let n, let at):
                guard var p = parts.last, n == parts.count, p.closed == nil else { broke("run \(run): close \(n) of \(parts.count)"); continue }
                if let prev = p.lastAt, at < prev + Clock.tick * 0.5 { broke("run \(run): part \(n) closed at \(at), before its last picture \(prev)") }
                if withSound {
                    if p.held != 0 { broke("run \(run): part \(n) closed with \(p.held) frames held") }
                    if p.pos < Clock.frames(at) { broke("run \(run): the sound ends at \(p.pos), before the close's \(Clock.frames(at))") }
                    if !stepAt.isFinite && !stallAt.isFinite && p.pos > Clock.frames(at) + 2_000 {
                        broke("run \(run): the sound runs \(p.pos - Clock.frames(at)) frames past the close")
                    }
                }
                p.closed = at
                parts[parts.count - 1] = p
            case .askKeyframe:
                recordingAsk(now, forStart: false)
            }
        }
    }

    func light(_ now: Double) {
        let start = P.start(keyframeSinceAsk: preroll?.holdsKeyframe ?? false, lastKeyframeKept: lastKeyframe != nil,
                            framesSinceKeyframe: framesSinceKey)
        var t = TL(withSound: withSound)
        for e in formatsSeen.sorted() { t.audioFormat(epoch: e, F) }
        let actions = t.begin(start, sets: currentSets, preroll: preroll?.frames ?? [], lastKeyframe: lastKeyframe, seeds: seeds, light: now)
        tl = t
        preroll = nil
        switch start {
        case .atLight(.sinceAsk): seen.sinceAsk += 1
        case .atLight(.lastKeyframe): seen.lastKeyframe += 1
        case .atNextKeyframe: seen.nextKeyframe += 1
        }
        if t.waitingForStart {
            phase = "starting"
            schedule(now)
        } else {
            phase = "recording"
        }
        apply(actions, now)
    }

    /// While "Starting…": the next ask or the give-up; something is always due.
    func schedule(_ now: Double) {
        switch P.starting(now: now, lightAt: dev(tLight), asks: startAsks, lastAsk: lastStartAsk, wait: 4) {
        case .askAt(let at):
            if at < now - 1e-9 { broke("run \(run): an ask due before now") }
            timers.append((at, "startask"))
        case .giveUpAt(let at):
            timers.append((at, "giveup"))
        case .giveUp:
            timers.append((now, "giveup"))
        }
    }

    func timer(_ what: String, _ now: Double) {
        switch what {
        case "recovery":
            // The picture's recovery asks, as KeyframeRecovery does after an interruption (2 s from any ask).
            if asks.last.map({ now - $0 >= 2 }) ?? true { ask(now, recording: false); recoveryAskedAt = now; recoveryOpen = true }
        case "one":
            preroll = P.Preroll()
            seeds = lastKeyframe.map { [($0.stamp, $0.arrival)] } ?? []
            recordingAsk(now, forStart: true)
        case "ask-held":
            heldAsk = false
            if phase == "recording" { recordingAsk(now, forStart: false) }
        case "startask-held":
            heldAsk = false
            if phase == "count" || (phase == "starting" && tl?.waitingForStart == true) { recordingAsk(now, forStart: true) }
        case "light":
            light(now)
        case "startask":
            guard phase == "starting", tl?.waitingForStart == true else { return }
            recordingAsk(now, forStart: true)
            schedule(now + 1e-6)
        case "giveup":
            guard phase == "starting", tl?.waitingForStart == true else { return }
            if now < dev(tLight) + P.startGiveUp - 1e-6 { broke("run \(run): gave up \(now - dev(tLight)) s after the light") }
            if startAsks > P.startAsks { broke("run \(run): \(startAsks) asks for the start") }
            apply(tl!.stop(arrival: now), now)
            phase = "gaveUp"; seen.gaveUp += 1
            if older { seen.olderGaveUp += 1 } else { broke("run \(run): gave up with a Mac that answers (\(startAsks) asks)") }
        case "stop":
            if phase == "recording" || phase == "starting" { apply(tl!.stop(arrival: now), now) }
            phase = "stopped"
        default:
            break
        }
    }

    func deliver(_ m: Message, _ now: Double) {
        let live = tl != nil && (phase == "recording" || phase == "starting")
        switch m {
        case .sets(let s):
            if s != currentSets {
                framesSinceKey += 1    // new sets: neither the kept keyframe nor the pre-roll is the picture any more
                preroll?.newSource()
            }
            currentSets = s
            if live { apply(tl!.parameterSets(s, arrival: now), now) }
        case .frame(let id, let stamp, let key):
            if arrivedAt[id] == nil { arrivedAt[id] = now }
            if key {
                lastKeyframe = TL.Kept(id: id, stamp: stamp, arrival: now, isKeyframe: true)
                lastKeyframeSets = setsOf[id] ?? 0; framesSinceKey = 0; recoveryOpen = false
            } else {
                framesSinceKey += 1
            }
            if preroll != nil {
                preroll!.take(TL.Kept(id: id, stamp: stamp, arrival: now, isKeyframe: key), bytes: 10_000, isKeyframe: key)
                seeds.append((stamp, now))
            }
            guard live else { return }
            let waiting = tl!.waitingForStart
            if !waiting, rng.chance(0.002) {
                // Dropped before the recorder's queue (the pending bound): the chain waits for a keyframe.
                if var p = parts.last, p.closed == nil, tl!.chain.whole { p.needKey = true; parts[parts.count - 1] = p }
                apply(tl!.lost(), now)
                return
            }
            if tl!.chain.recentStamps.contains(stamp) { seen.duplicates += 1 }
            let actions = tl!.frame(id: id, stamp: stamp, isKeyframe: key, arrival: now)
            if waiting && !tl!.waitingForStart { phase = "recording" }
            apply(actions, now)
        case .format(let e):
            formatsSeen.insert(e)
            if tl != nil { tl!.audioFormat(epoch: e, F) }
        case .packets(let e, let sq, let start, let n, let stamp):
            guard live else { return }
            for i in 0..<n {
                let st = stamp + Double(i) * 0.01
                let before = tl!.sound?.end ?? 0
                let partStart = tl!.partStart
                let (decode, writes) = tl!.audio(epoch: e, seq: sq &+ UInt32(i), index: i, segmentStart: start, stamp: st)
                if decode == .decode(reset: true) && writes.isEmpty && !(start && i == 0) { seen.joins += 1 }
                if let time = tl!.clock.sound(stamp: st).map({ $0 - partStart }) {
                    // Sync: every packet written lands within the drift limit of where its stamp puts it.
                    var placed = before
                    for w in writes {
                        switch w {
                        case .silence(let s): placed += Int64(s)
                        case .tail: break
                        case .packet(_, let from, _, let fadeIn, _):
                            let expected = Clock.frames(time) + Int64(from)
                            if abs(placed - expected) > Int64(Sound.driftLimit * 48_000) + 1 {
                                broke("run \(run): a packet placed at \(placed), its stamp says \(expected)")
                            }
                            if fadeIn { seen.byStamp += 1 } else { seen.follows += 1 }
                            if from > (start && i == 0 ? 240 : 0) { seen.trims += 1 }
                        }
                    }
                }
                if !writes.isEmpty { apply([.sound(writes)], now) }
            }
        }
    }

    func go() {
        generate()
        // Timers on the device's clock, as StreamClient keeps them (an ask held to `last + 1` is due exactly then).
        timers = [(dev(tOne), "one"), (dev(tLight), "light"), (dev(tStop), "stop")]
        if recoveryAt.isFinite { timers.append((dev(recoveryAt), "recovery")) }
        var qi = 0, steps = 0
        while true {
            steps += 1
            if steps > 2_000_000 { broke("run \(run): more than 2,000,000 steps"); break }
            let ti = timers.indices.min { timers[$0].at < timers[$1].at }
            let nextTimer = ti.map { timers[$0].at } ?? .infinity
            let nextArrival = qi < queue.count ? dev(queue[qi].at) : .infinity
            if nextTimer == .infinity && nextArrival == .infinity { break }
            if nextTimer <= nextArrival, let ti {
                let tm = timers.remove(at: ti)
                timer(tm.what, tm.at)
            } else {
                let d = queue[qi]; qi += 1
                deliver(d.what, dev(d.at))
            }
        }
        if !parts.isEmpty { seen.recordings += 1 }
        if let t = tl {
            if t.clock.steps > 0 { seen.steps += 1 }
            if t.parts > 1 { seen.parts += 1 }
        }
        if stillFrom < tOne { seen.stills += 1 }
        if let p = parts.last, p.closed == nil { broke("run \(run): the last part never closed") }
        // Every ask the recording made kept the Mac's second from the ask before it on the connection.
        for (i, a) in asks.enumerated() where i > 0 && recordingAsks.contains(a) && a - asks[i - 1] < P.hostSpacing - 1e-9 {
            broke("run \(run): the recording asked \(a - asks[i - 1]) s after another ask")
        }
    }
}

var dice = Rng(s: 0x5111_2840)
for run in 0..<20_000 {
    let sim = Sim(run: run, rng: Rng(s: dice.next()))
    sim.go()
}
check(broken == 0, "20,000 random recordings: \(broken) broke an invariant")
print("random recordings: \(seen)")
check(seen.recordings > 15_000 && seen.sinceAsk > 3_000 && seen.lastKeyframe > 300 && seen.nextKeyframe > 300 && seen.olderGaveUp > 20
      && seen.steps > 300 && seen.parts > 300 && seen.duplicates > 300 && seen.breaks > 300 && seen.joins > 1_000 && seen.trims > 100
      && seen.follows > 100_000 && seen.byStamp > 10_000 && seen.awaited > 100 && seen.stills > 2_000,
      "the random recordings reach every rule")

// MARK: - The source rules

let root = ProcessInfo.processInfo.environment["SILL_CHECK_ROOT"] ?? FileManager.default.currentDirectoryPath
func source(_ path: String) -> String { (try? String(contentsOfFile: root + "/" + path, encoding: .utf8)) ?? "" }
let iosFiles = ((try? FileManager.default.contentsOfDirectory(atPath: root + "/iOSClient")) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
check(iosFiles.count > 50, "the iOS app's sources read: \(iosFiles.count) in \(root)/iOSClient")
/// The files that name the Documents directory.
func namesDocuments(_ files: [(name: String, text: String)]) -> [String] {
    files.filter { $0.text.contains("documentsDirectory") || $0.text.contains(".documentDirectory") || $0.text.contains("NSDocumentDirectory") }
        .map(\.name)
}
check(namesDocuments([("A.swift", "let u = URL.documentsDirectory"), ("B.swift", "fm.urls(for: .documentDirectory, in: .userDomainMask)"),
                      ("C.swift", "NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)"),
                      ("D.swift", "NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, …)")]) == ["A.swift", "B.swift", "D.swift"],
      "the rule finds each way of naming Documents")
let namers = namesDocuments(iosFiles.map { ($0, source("iOSClient/" + $0)) })
check(namers == ["SillDocuments.swift"], "only SillDocuments names the Documents directory: \(namers)")
for f in ["RecordingPolicy.swift", "RecordingClock.swift", "RecordedSound.swift", "SillDocuments.swift"] {
    let imports = source("iOSClient/" + f).split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
    check(imports == ["import Foundation"], "\(f) imports Foundation alone: \(imports)")
}
// The recorder never UIKit or SwiftUI: the rig (Scripts/recording-check) compiles it on the Mac, with its folder,
// protection and free space from its caller.
let recorderImports = Set(source("iOSClient/StreamRecorder.swift").split(separator: "\n").filter { $0.hasPrefix("import ") }
    .map { String($0.dropFirst("import ".count)) })
check(!recorderImports.isEmpty && recorderImports.isSubset(of: ["AudioToolbox", "AVFoundation", "CoreMedia", "Foundation", "SillAudio", "StreamProtocol"]),
      "StreamRecorder imports AVFoundation, CoreMedia and AudioToolbox, never UIKit: \(recorderImports.sorted())")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
