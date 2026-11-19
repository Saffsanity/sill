import Foundation

/// The stream recorded on this device (#284, docs/recording-plan.md): every rule of it but the clock's
/// (RecordingClock, rule 4) and the sound's (RecordedSound, rule 7), and every sentence a person sees of it
/// (`Copy`). Started only by the person at the device (Start Recording in Settings, a 3, 2, 1 count, then the
/// light); nothing the Mac or the network sends starts or stops one.
///
/// 1. Offered: Start while the session is connected and its picture has come; Record Sound shown while the
///    Mac has sound, dimmed and off while Send Audio is off; the movie has sound when both are on at the light.
/// 2. The count, and the keyframe ask at "1", kept a second from any other ask on the connection (the Mac
///    takes one a second and drops the rest), or the picture recovery's ask awaited while its keyframe is due.
/// 3. Where the movie starts: at the light, from a keyframe that came since "1" (the pre-roll) or from the
///    session's last keyframe when nothing has come since it (a still picture); else "Starting…" until the
///    next keyframe, asked again at the recovery's wait, given up after 10 s.
/// 5. The picture's samples: a keyframe or a delta while the chain is whole is written; after any frame not
///    written every delta waits for the next keyframe; a frame delivered twice is dropped.
/// 6. Parts: new parameter sets end a part; the next starts at the next keyframe; names by the light's moment.
/// 8. What ends it (`Ending`), and what never does.
/// 9. Space: a look every 5 s; low under 3 GB or 5 minutes, a stop under 1 GB, no start under 1.5 GB.
/// 10. The light's words. 11. What the device tells the Mac (`recordingField`), and what it says of it.
///
/// Pure: Foundation only, checked with RecordingClock and RecordedSound by Tests/checks/recording, with
/// mutants. Device times are seconds of one monotonic clock per caller (`systemUptime` on the main thread),
/// compared only with each other. Bytes are decimal: 1 MB is 1,000,000 bytes, as Files counts them.
enum RecordingPolicy {
    // MARK: - The numbers

    /// Rule 2: the count, a second each: 3, 2, 1, then the light.
    static let countFrom = 3
    /// Rule 2: the Mac takes one keyframe ask (kind 44) a second per connection and drops the rest silently
    /// (StreamCoordinator), so an ask keeps this from the last one anybody on the connection made.
    static let hostSpacing: TimeInterval = 1
    /// Rule 3: asks for the start's keyframe in all, the one at "1" counted, while "Starting…" shows.
    static let startAsks = 3
    /// Rule 3: "Starting…" gives up this long after the light when no keyframe came.
    static let startGiveUp: TimeInterval = 10
    /// Rule 3: the pre-roll kept on the network queue between "1" and the light, at most (bytes).
    static let prerollLimit = 32 << 20
    /// Rule 5: frames handed to the recorder's queue and not yet taken there, at most (bytes): latency before
    /// quality, a frame is dropped before it queues without bound.
    static let pendingLimit = 32 << 20
    /// Rule 8: every movie is written in fragments this long, so a crash, a force quit or a full disk loses at
    /// most the last seconds of it.
    static let fragmentInterval: TimeInterval = 4
    /// Rule 9 (decision 11): no start under 1.5 GB free, a warning under 3 GB or 5 minutes, a stop under 1 GB.
    static let startFloor: Int64 = 1_500_000_000
    static let warnFloor: Int64 = 3_000_000_000
    static let stopFloor: Int64 = 1_000_000_000
    static let warnMinutes = 5.0
    /// Rule 9: how often space is looked at, and over how long the rate of writing is taken.
    static let spaceEvery: TimeInterval = 5
    static let rateWindow: TimeInterval = 10
    /// Rule 9: the most minutes the light says are left.
    static let mostMinutes = 999
    /// Rule 10: the sound's bytes a second (AAC at 160 kbps), and the container's share of the frames' bytes.
    static let soundBitrate = 160_000
    static let soundBytesPerSecond = 20_000
    static let containerShare = 0.01

    // MARK: - 1. Offered

    /// Why Start is dimmed (its hint): no session, or no picture yet (nothing streams, or its first frame
    /// has not come).
    enum Dimmed: Equatable { case notConnected, nothingStreams }

    /// Where a window's recording is: nothing, the count, "Starting…" (the light shows, waiting for a
    /// keyframe), the light on, or its last movie being finished.
    enum Phase: Equatable { case idle, counting(Int), starting, recording, finishing }

    /// The first row of This iPad (This iPhone).
    enum Row: Equatable {
        case start
        case startDimmed(Dimmed)
        /// During the count.
        case cancel
        /// "Starting…" and the light: Stop, also pinned at the top of Settings.
        case stop
    }

    /// The row for a window in `phase`. A movie still being finished leaves Start free: the next recording
    /// writes other files.
    static func row(_ phase: Phase, connected: Bool, streaming: Bool, pictureCame: Bool) -> Row {
        switch phase {
        case .counting: return .cancel
        case .starting, .recording: return .stop
        case .idle, .finishing:
            guard connected else { return .startDimmed(.notConnected) }
            guard streaming, pictureCame else { return .startDimmed(.nothingStreams) }
            return .start
        }
    }

    /// A tap on Start: the count, or the space note under `startFloor`. Space that cannot be read counts as
    /// enough: the space rule then never stops it, and a full disk fails the writer, whose fragments keep
    /// what was written.
    static func startAllowed(freeBytes: Int64?) -> Bool {
        guard let free = freeBytes else { return true }
        return free >= startFloor
    }

    /// Record Sound's row.
    enum SoundRow: Equatable {
        /// Working: its stored value.
        case shown
        /// Send Audio is off: dimmed, showing off whatever is stored, the footnote saying why.
        case dimmed
        /// A Mac without sound (no Send Audio in its settings): no row.
        case hidden
    }

    /// `sendAudio`: the Mac's Send Audio as its settings say (nil from a Mac without sound).
    static func soundRow(macHasSound: Bool, sendAudio: Bool?) -> SoundRow {
        guard macHasSound else { return .hidden }
        return sendAudio == true ? .shown : .dimmed
    }

    /// Whether the movie gets a sound track: fixed at the light, the switch on and Send Audio on.
    static func recordsSound(switchOn: Bool, sendAudio: Bool?) -> Bool {
        switchOn && sendAudio == true
    }

    // MARK: - 2. The count and the keyframe ask

    /// The count's number `elapsed` whole seconds after Start (3, 2, 1); nil from `countFrom` on: the light.
    static func count(elapsed: Int) -> Int? {
        guard elapsed >= 0, elapsed < countFrom else { return nil }
        return countFrom - elapsed
    }

    /// The count's number at which the keyframe is asked for: "1", a second before the light.
    static let askAtCount = 1

    /// When the recording's keyframe ask goes out.
    enum Ask: Equatable {
        case now
        /// Held by the Mac's spacing: at this time.
        case at(TimeInterval)
        /// The picture recovery's ask is out and its keyframe due: it serves both, as Disconnect's fresh
        /// picture waits for it (ConnectionList.freshPicture).
        case awaitRecovery
    }

    /// `lastAsk`: when anybody on this connection last sent kind 44 (the recovery, the fresh picture, the
    /// recording itself), nil for never; `recoveryDueUntil`: while the picture recovery's ask is out and its
    /// interruption open, when its keyframe stops being due (KeyframeRecovery's ask + `answerWait`), else nil.
    /// Against the time the ask is due, not `now - last < spacing`, so an ask held until then goes then.
    static func keyframeAsk(now: TimeInterval, lastAsk: TimeInterval?, recoveryDueUntil: TimeInterval?) -> Ask {
        if let due = recoveryDueUntil, now < due { return .awaitRecovery }
        if let last = lastAsk, now >= last, now < last + hostSpacing { return .at(last + hostSpacing) }
        return .now
    }

    // MARK: - 3. Where the movie starts

    /// What the picture at the light is decoded from.
    enum From: Equatable {
        /// A keyframe that came since "1", kept with every frame after it (the pre-roll).
        case sinceAsk
        /// The session's last keyframe, nothing having come since it: the picture is still, and it is it.
        case lastKeyframe
    }

    enum StartPoint: Equatable {
        /// The movie's 0:00 is the light.
        case atLight(From)
        /// "Starting…" until the next keyframe, whose time is the movie's 0:00.
        case atNextKeyframe
    }

    /// At the light. `keyframeSinceAsk`: the pre-roll holds a keyframe and its chain whole since;
    /// `lastKeyframeKept`: the session keeps its last keyframe with its parameter sets; `framesSinceKeyframe`:
    /// frames that came after that keyframe.
    static func start(keyframeSinceAsk: Bool, lastKeyframeKept: Bool, framesSinceKeyframe: Int) -> StartPoint {
        if keyframeSinceAsk { return .atLight(.sinceAsk) }
        if lastKeyframeKept, framesSinceKeyframe == 0 { return .atLight(.lastKeyframe) }
        return .atNextKeyframe
    }

    /// While "Starting…": what to do next.
    enum Waiting: Equatable {
        /// Ask again (through `keyframeAsk`) at this time.
        case askAt(TimeInterval)
        /// No ask is left before the end: give up at this time.
        case giveUpAt(TimeInterval)
        /// Give up now.
        case giveUp
    }

    /// `lightAt`: when "Starting…" came; `asks`: asks made (or awaited) for the start, the one at "1" counted;
    /// `lastAsk`: when the last of them went (or the awaited one had gone); `wait`: how long an ask waits for
    /// its keyframe (KeyframeRecovery.answerWait). An ask whose wait ends at or after the give-up is not made.
    static func starting(now: TimeInterval, lightAt: TimeInterval, asks: Int, lastAsk: TimeInterval?,
                         wait: TimeInterval) -> Waiting {
        let end = lightAt + startGiveUp
        guard now < end else { return .giveUp }
        if asks < startAsks {
            let due = max((lastAsk ?? now) + wait, now)
            if due < end { return .askAt(due) }
        }
        return .giveUpAt(end)
    }

    /// The frames kept on the network queue from "1" until the light: the newest keyframe since and every
    /// frame after it, at most `prerollLimit` bytes. Past the limit only the newest keyframe and what follows
    /// it are kept; a chain that alone outgrows it is dropped until the next keyframe. On `sill.net`.
    struct Preroll<Frame> {
        private(set) var frames: [Frame] = []
        private(set) var bytes = 0
        /// Frames dropped since the last keyframe (the chain broke), or none came yet: deltas wait.
        private(set) var waiting = true
        let limit: Int

        init(limit: Int = RecordingPolicy.prerollLimit) { self.limit = limit }

        /// Whether `frames` begins with a keyframe whose chain is whole.
        var holdsKeyframe: Bool { !frames.isEmpty && !waiting }

        /// New parameter sets (a new source, a new size): what is kept is not the picture any more; the new
        /// source's keyframe follows them.
        mutating func newSource() {
            frames = []
            bytes = 0
            waiting = true
        }

        mutating func take(_ frame: Frame, bytes size: Int, isKeyframe: Bool) {
            if isKeyframe {
                // Only the newest keyframe's chain is of use: the light's picture is decoded from it.
                frames = []
                bytes = 0
                waiting = false
            } else if waiting {
                return
            }
            guard bytes + size <= limit else {
                frames = []
                bytes = 0
                waiting = true
                return
            }
            frames.append(frame)
            bytes += size
        }
    }

    // MARK: - 5. The picture's samples

    /// What happens to one frame on the recorder's queue.
    enum FrameFate: Equatable {
        /// Written: a keyframe, or a delta while the chain is whole.
        case write
        /// Dropped: a delta after a frame that was not written, until the next keyframe.
        case waitForKeyframe
        /// Dropped: delivered twice (a move's hand-over); it was written already, so the chain stays whole.
        case duplicate
    }

    /// The decode chain of the frames written: whole from a keyframe until a frame is not written.
    struct PictureChain: Equatable {
        /// False until the first keyframe, and after a frame not written until the next.
        private(set) var whole = false
        /// The stamps of the last frames written (the Mac's, unique per frame): a stamp seen again is the same
        /// frame delivered twice.
        private(set) var recentStamps: [Double] = []
        /// Frames lost since the recording began (not written, or dropped waiting for a keyframe).
        private(set) var dropped = 0
        static let stampsKept = 8

        init() {}

        /// A frame came: its fate. The caller then writes it and says whether that worked (`written` or `lost`).
        mutating func fate(stamp: Double, isKeyframe: Bool) -> FrameFate {
            if recentStamps.contains(stamp) { return .duplicate }
            if isKeyframe { whole = true; return .write }
            guard whole else { dropped += 1; return .waitForKeyframe }
            return .write
        }

        mutating func written(stamp: Double) {
            recentStamps.append(stamp)
            if recentStamps.count > Self.stampsKept { recentStamps.removeFirst() }
        }

        /// A frame that was not written (the writer not ready, the pending bound, a sample that could not be
        /// made): every delta waits for the next keyframe. True when this broke a whole chain: one keyframe
        /// ask then goes out (rule 2).
        mutating func lost() -> Bool {
            dropped += 1
            defer { whole = false }
            return whole
        }

        /// A part closed: the next part's first picture is a keyframe. Nothing was lost, so nothing is asked.
        mutating func restart() {
            whole = false
        }
    }

    // MARK: - 6. Parts

    /// New parameter sets (a kind 0 the display would also take as new) end the part they arrive in.
    static func endsPart<Sets: Equatable>(current: Sets?, incoming: Sets) -> Bool {
        guard let current else { return false }
        return current != incoming
    }

    /// A part's file name: "Sill 2026-11-18 at 14.03.12.mov" from the light's moment on this device's clock
    /// (Gregorian, POSIX digits, 24 hours, in `timeZone`, whatever the person's calendar and clock settings),
    /// its later parts " (2)", " (3)" and so on, so they sort together; a name already `taken` gets the next
    /// free number after its own.
    static func fileName(start: Date, part: Int, timeZone: TimeZone, taken: (String) -> Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        func two(_ n: Int?) -> String { let v = n ?? 0; return v < 10 ? "0\(v)" : "\(v)" }
        let stem = "Sill \(c.year ?? 0)-\(two(c.month))-\(two(c.day)) at \(two(c.hour)).\(two(c.minute)).\(two(c.second))"
        var n = max(part, 1)
        while true {
            let name = n == 1 ? "\(stem).mov" : "\(stem) (\(n)).mov"
            if !taken(name) { return name }
            n += 1
        }
    }

    // MARK: - 8. What ends it

    /// What ends a recording, and the words after it.
    enum Ending: Equatable {
        /// Stop, at the top of Settings.
        case stop
        /// Cancel during the count: nothing was recorded.
        case cancel
        /// The session ended (Disconnect, a goodbye, a loss no move carries).
        case sessionEnded
        /// Sill left the screen: the app or this window's scene to the background, Picture in Picture or not
        /// (decision 4); the device's lock reaches Sill this way too.
        case leftScreen
        /// The device's lock (`protectedDataWillBecomeUnavailable`), when it comes first.
        case deviceLocked
        /// Space under `stopFloor`.
        case space
        /// The writer failed; its reason.
        case writerFailed(String)
        /// "Starting…" gave up: no keyframe within `startGiveUp`.
        case gaveUp
    }

    /// Everything that might happen to a session while a window records.
    enum Event: Equatable {
        case stopTapped, cancelTapped, sessionEnded, appToBackground, sceneToBackground, pictureInPicture,
             deviceLock, spaceStop, writerFailed(String), startGaveUp
        /// Never an end: a move to another path, a locked Mac or another user on it, a new picture size, the
        /// link falling behind, Send Audio turned off, Mute, the Settings pane over the picture.
        case move, macLocked, otherUser, newSize, linkBehind, sendAudioOff, mute, settingsOpen
    }

    /// Whether `event` ends the recording, and how.
    static func ending(_ event: Event) -> Ending? {
        switch event {
        case .stopTapped: return .stop
        case .cancelTapped: return .cancel
        case .sessionEnded: return .sessionEnded
        case .appToBackground, .sceneToBackground, .pictureInPicture: return .leftScreen
        case .deviceLock: return .deviceLocked
        case .spaceStop: return .space
        case .writerFailed(let why): return .writerFailed(why)
        case .startGaveUp: return .gaveUp
        case .move, .macLocked, .otherUser, .newSize, .linkBehind, .sendAudioOff, .mute, .settingsOpen: return nil
        }
    }

    // MARK: - 9. Space

    enum Space: Equatable {
        case fine
        /// The light adds "· N min left".
        case low(minutesLeft: Int)
        case stop
    }

    /// `freeBytes`: the folder's volume's available capacity for important usage; `bytesPerSecond`: the
    /// recording's rate over the last `rateWindow`. Minutes left count down to `stopFloor`, at least 1 and at
    /// most `mostMinutes`; a rate of nothing (a still window without sound) leaves the floor's warning alone.
    static func space(freeBytes: Int64, bytesPerSecond: Double) -> Space {
        guard freeBytes >= stopFloor else { return .stop }
        let room = Double(freeBytes - stopFloor)
        let minutes = bytesPerSecond > 0 ? room / bytesPerSecond / 60 : .infinity
        guard freeBytes < warnFloor || minutes < warnMinutes else { return .fine }
        let shown = minutes.isFinite ? Int(minutes.rounded(.down)) : mostMinutes
        return .low(minutesLeft: min(max(shown, 1), mostMinutes))
    }

    /// The rate the space rule reads: the bytes counted over the samples (time, total bytes so far) of the
    /// last `rateWindow` before `now`, per second; nothing with fewer than two samples a second apart.
    static func rate(_ samples: [(time: TimeInterval, bytes: Int64)], now: TimeInterval) -> Double {
        let recent = samples.filter { $0.time > now - rateWindow && $0.time <= now }
        guard let first = recent.first, let last = recent.last, last.time - first.time >= 1 else { return 0 }
        return Double(last.bytes - first.bytes) / (last.time - first.time)
    }

    // MARK: - 10. The light

    /// The bytes the light says: the frames' bytes written, the sound's at its bitrate, and the container's
    /// share of the frames'.
    static func bytes(frames: Int64, soundSeconds: Double) -> Int64 {
        let sound = soundSeconds > 0 ? Int64(soundSeconds * Double(soundBytesPerSecond)) : 0
        return frames + sound + Int64(Double(frames) * containerShare)
    }

    /// "0:42", "12:05", "1:02:03".
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return s >= 3600 ? "\(s / 3600):\(two(s / 60 % 60)):\(two(s % 60))" : "\(s / 60):\(two(s % 60))"
    }

    /// "126 MB" below 1,000 MB, "1.4 GB" above: each rounded down, so the number only grows.
    static func size(_ bytes: Int64) -> String {
        let mb = max(0, bytes) / 1_000_000
        if mb < 1000 { return "\(mb) MB" }
        let tenths = max(0, bytes) / 100_000_000
        return "\(tenths / 10).\(tenths % 10) GB"
    }

    // MARK: - 11. The Mac is told

    /// `ClientStats.recording`: true from the light ("Starting…" included) until the movie is closed, and
    /// left out otherwise, never false.
    static func recordingField(_ reports: Bool) -> Bool? { reports ? true : nil }

    /// Whether the window's reports say it records: from the light until its last movie is closed.
    static func reports(_ phase: Phase) -> Bool {
        switch phase {
        case .starting, .recording, .finishing: return true
        case .idle, .counting: return false
        }
    }

    /// Whether a Mac takes kind 44 (Sill for Mac 0.5.1 and before skip it, and a host that names no version is
    /// counted among them): the give-up's words then ask for an update.
    static func macTakesKeyframeAsks(hostVersion: String?) -> Bool {
        guard let v = hostVersion else { return false }
        let parts = v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let older = [0, 5, 1]
        for i in 0..<max(parts.count, older.count) {
            let a = i < parts.count ? parts[i] : 0, b = i < older.count ? older[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Every sentence

    /// Every sentence a person sees or hears of a recording on the device. `device` is "iPad" or "iPhone";
    /// `mac` the Mac's name, or nil for "the Mac".
    enum Copy {
        static let start = "Start Recording"
        static let cancel = "Cancel Recording"
        static let stop = "Stop Recording"
        static let recordSound = "Record Sound"
        static let dimmedHint = "Pick a window or the Desktop first."
        static let starting = "Starting…"
        static let startingSpoken = "Starting the recording"
        static let startSpoken = "Recording"
        static let folder = "Files › Sill Recordings"

        /// "Noah’s MacBook Pro", or "the Mac".
        static func mac(_ name: String?) -> String {
            guard let name, !name.isEmpty else { return "the Mac" }
            return name
        }

        /// The same at the start of a sentence: "The Mac".
        static func macFirst(_ name: String?) -> String {
            guard let name, !name.isEmpty else { return "The Mac" }
            return name
        }

        /// "the Mac’s", "Noah’s MacBook Pro’s".
        static func macs(_ name: String?) -> String { mac(name) + "’s" }

        /// The count over the picture, and what VoiceOver says of it.
        static func count(_ n: Int) -> String { "\(n)" }
        static func countSpoken(_ n: Int) -> String { n == countFrom ? "Recording in \(n)" : "\(n)" }

        /// Settings' footnote under the rows: what is recorded, where it goes and for how long, what the Mac
        /// says (`recordings` from its window list), and what turns the sound on.
        static func footnote(mac: String?, device: String, macShowsIt: Bool, soundRow: SoundRow) -> String {
            var s = "Saves what \(Copy.mac(mac)) shows as a movie in Files › On My \(device) › Sill › Sill Recordings, "
                + "without Sill’s controls or \(macs(mac)) pointer, until you delete it or Sill. Everything on the screen is "
                + "recorded, its lock screen and what you type included."
            s += macShowsIt ? " While it records, Sill’s menu on \(Copy.mac(mac)) says so."
                            : " \(macFirst(mac)) runs an older Sill, so its menu won’t say that this \(device) is recording."
            if soundRow == .dimmed { s += " Turn on Send Audio above to record \(macs(mac)) sound." }
            return s
        }

        /// Whether the Mac's lists say it shows a recording: `WindowList.recordings`, 1 from a host that does.
        static func macShowsIt(recordings: Int?) -> Bool { (recordings ?? 0) >= 1 }

        /// The light: "Starting…" before the first frame, then "0:42 · 126 MB", "· 4 min left" while low.
        static func light(seconds: Double?, bytes: Int64, minutesLeft: Int?) -> String {
            guard let seconds else { return starting }
            var s = "\(time(seconds)) · \(size(bytes))"
            if let m = minutesLeft { s += " · \(m) min left" }
            return s
        }

        /// What VoiceOver says of the light: "Recording, 42 seconds, 126 megabytes", ", space for about 4
        /// minutes" while low.
        static func lightSpoken(seconds: Double?, bytes: Int64, minutesLeft: Int?) -> String {
            guard let seconds else { return startingSpoken }
            var s = "Recording, \(spokenTime(seconds)), \(spokenSize(bytes))"
            if let m = minutesLeft { s += ", space for about \(plural(m, "minute"))" }
            return s
        }

        /// The row at the top of Settings while it records: "Recording · 1:42 · 230 MB", and its spoken words.
        static func topRow(seconds: Double?, bytes: Int64, minutesLeft: Int?) -> String {
            guard seconds != nil else { return starting }
            return "Recording · " + light(seconds: seconds, bytes: bytes, minutesLeft: minutesLeft)
        }

        static func topRowSpoken(seconds: Double?, bytes: Int64, minutesLeft: Int?) -> String {
            "\(stop). \(lightSpoken(seconds: seconds, bytes: bytes, minutesLeft: minutesLeft))."
        }

        /// Spoken once when space first runs low.
        static func lowSpoken(_ minutes: Int) -> String {
            "Space for about \(minutes) more \(minutes == 1 ? "minute" : "minutes") of recording."
        }

        /// "1 minute 42 seconds", "1 hour 2 minutes 3 seconds", "1 hour", "0 seconds": the parts that are not 0.
        static func spokenTime(_ seconds: Double) -> String {
            let s = max(0, Int(seconds.isFinite ? seconds.rounded(.down) : 0))
            var parts: [String] = []
            if s / 3600 > 0 { parts.append(plural(s / 3600, "hour")) }
            if s / 60 % 60 > 0 { parts.append(plural(s / 60 % 60, "minute")) }
            if s % 60 > 0 || parts.isEmpty { parts.append(plural(s % 60, "second")) }
            return parts.joined(separator: " ")
        }

        /// "126 megabytes", "1.4 gigabytes".
        static func spokenSize(_ bytes: Int64) -> String {
            let mb = max(0, bytes) / 1_000_000
            if mb < 1000 { return plural(Int(mb), "megabyte") }
            let tenths = max(0, bytes) / 100_000_000
            return "\(tenths / 10).\(tenths % 10) gigabytes"
        }

        static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

        /// Under Start when there is too little space for it.
        static func noSpace(device: String) -> String {
            "There isn’t enough space on this \(device) to record. Free up some space first."
        }

        /// The writer's reason in words: out of space, or its own description without the final period.
        static func writerReason(domain: String, code: Int, description: String, device: String) -> String {
            // AVError.diskFull (-11807) and Cocoa's NSFileWriteOutOfSpaceError (640).
            if (domain == "AVFoundationErrorDomain" && code == -11807) || (domain == "NSCocoaErrorDomain" && code == 640) {
                return "this \(device) ran out of space"
            }
            var s = description.trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix(".") { s.removeLast() }
            if s.isEmpty { return "the movie couldn’t be written" }
            return s.prefix(1).lowercased() + s.dropFirst()
        }

        /// The note after a recording ends: `movies`, the movies kept (finished or not); `finished`, whether the
        /// writer finished them; `failure`, the writer's reason; `macTakesAsks` for the give-up's words.
        static func note(_ ending: Ending, movies: Int, failure: String?, device: String, mac: String?,
                         macTakesAsks: Bool) -> String? {
            switch ending {
            case .cancel:
                return nil
            case .gaveUp:
                var s = "Couldn’t start recording: \(Copy.mac(mac)) didn’t send a full picture."
                if !macTakesAsks { s += " Update Sill on \(Copy.mac(mac)), then try again." }
                return s
            case .writerFailed(let why):
                return movies > 0 ? "Recording stopped: \(why). What was recorded is in \(folder)."
                                  : "Couldn’t save the recording: \(why)."
            default:
                break
            }
            if let failure {
                return movies > 0 ? "Recording stopped: \(failure). What was recorded is in \(folder)."
                                  : "Couldn’t save the recording: \(failure)."
            }
            guard movies > 0 else { return "Nothing was recorded." }
            switch ending {
            case .space:
                return "Recording stopped: this \(device) is almost out of space. What was recorded is in \(folder)."
            case .leftScreen, .deviceLocked:
                return "Your recording was saved when Sill left the screen. It’s in \(folder)."
            case .sessionEnded:
                return "Your recording was saved when the session ended. It’s in \(folder)."
            default:
                return movies == 1 ? "Saved to \(folder)."
                                   : "Saved \(movies) movies to \(folder), one for each picture size."
            }
        }
    }
}
