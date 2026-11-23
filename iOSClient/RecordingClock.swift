import Foundation

/// The recording's timeline (#284, docs/recording-plan.md, rule 4): where each picture and each sound packet
/// goes in the movie, from the Mac's stamps, so the two tracks keep the sync they had on the Mac (the picture's
/// stamp is taken as its encoder hands a frame over, the sound's at its first sample's capture: the picture
/// trails by its encode time, a few ms).
///
/// 1. The floor: O is the smallest arrival − stamp (A − S) of the pictures of the last `floorWindow` seconds,
///    in 1 s buckets; with none for that long it keeps its last value.
/// 2. The anchor, on the Mac's clock: the light's moment (A_light − O) when the movie starts at the light, else
///    the first keyframe's stamp.
/// 3. Movie time is T = S + correction − anchor, for the pictures and the sound alike.
/// 4. A step of the Mac's clock: `stepFrames` pictures in a row more than `stepLimit` above the floor, or one
///    more than `stepLimit` below it. The correction then changes so that T goes on where the arrivals say,
///    without a jump, and the floor starts again from that picture. A picture before a step is seen (the
///    first of a step back) is held right after the last one written, never before it.
/// 5. A picture whose stamp was written already is the same frame delivered twice (RecordingPolicy's
///    PictureChain drops it); every other picture's T comes after the last one written.
/// 6. The stop: A_stop − O + correction − anchor, never before the last picture written: a still window's last
///    picture lasts until Stop. The light reads the same, at now, so the light and the movie agree.
/// 7. Timescales: 90,000 for the picture; 48,000, sample-exact, for the sound.
///
/// Only pictures feed the floor and the steps: the sound comes every 10 ms and would take any stall for a
/// step. Pure: Foundation only, checked by Tests/checks/recording. Arrivals are the device's monotonic clock
/// (CACurrentMediaTime), stamps the Mac's wall clock (the header's), both in seconds.
struct RecordingClock {
    static let floorWindow = 10
    static let stepFrames = 3
    static let stepLimit: Double = 1
    static let videoTimescale: Int32 = 90_000
    static let soundRate = 48_000
    /// The least gap between two pictures written: one tick of the picture's timescale.
    static let tick = 1.0 / Double(videoTimescale)

    /// The floor's 1 s buckets: the second of arrival and the least A − S in it.
    private var buckets: [(second: Int, least: Double)] = []
    /// O, nil before any picture.
    private(set) var floor: Double?
    /// Added to every stamp: the Mac's clock as the recording keeps it (`S + correction`, "Mac time" below).
    private(set) var correction: Double = 0
    /// The movie's 0:00 in Mac time; nil until the movie's start is known.
    private(set) var anchor: Double?
    /// Pictures in a row more than `stepLimit` above the floor.
    private(set) var above = 0
    /// The last picture seen (or the light): its arrival and its Mac time as placed, which a step goes on from.
    private var last: (arrival: Double, mac: Double)?
    /// The last picture written's movie time.
    private(set) var lastWritten: Double?
    /// Steps taken, for the console.
    private(set) var steps = 0

    init() {}

    /// A picture that came before the anchor (the pre-roll, the session's last keyframe, the frames dropped
    /// while "Starting…"), in its order: the floor and the steps see it. Its Mac time, which `place` turns into
    /// a movie time once the anchor is known.
    @discardableResult
    mutating func seed(stamp: Double, arrival: Double) -> Double {
        let mac = observe(stamp: stamp, arrival: arrival)
        last = (arrival, mac)
        return mac
    }

    /// The movie starts at the light, `arrival`: its moment in Mac time. False without a floor (no picture ever
    /// came), when nothing is set.
    mutating func anchorAtLight(arrival: Double) -> Bool {
        guard let floor else { return false }
        let at = arrival - floor + correction
        anchor = at
        last = (arrival, at)
        return true
    }

    /// The movie starts at this keyframe's stamp.
    mutating func anchorAt(stamp: Double) {
        anchor = stamp + correction
    }

    /// A picture's movie time (the anchor set first, at this picture if it was not): the floor and the steps
    /// (rules 1 and 4) run first, then T comes after the last picture written.
    mutating func picture(stamp: Double, arrival: Double) -> Double {
        if anchor == nil { anchor = stamp + correction }
        return place(observe(stamp: stamp, arrival: arrival), arrival: arrival)
    }

    /// The movie time of a picture whose Mac time `seed` gave (a pre-roll frame's), after the last picture
    /// written.
    mutating func place(_ mac: Double, arrival: Double) -> Double {
        let anchor = self.anchor ?? mac
        var t = mac - anchor
        if let written = lastWritten, t < written + Self.tick { t = written + Self.tick }
        last = (arrival, t + anchor)
        return t
    }

    /// The picture at `time` was written.
    mutating func written(_ time: Double) {
        if lastWritten.map({ time > $0 }) ?? true { lastWritten = time }
    }

    /// A sound packet's movie time: its stamp through the pictures' correction and anchor; nil before the anchor.
    func sound(stamp: Double) -> Double? {
        guard let anchor else { return nil }
        return stamp + correction - anchor
    }

    /// The stop's movie time at `arrival` (and the light's, at now): never before the last picture written,
    /// and a tick after it. Nil before the anchor.
    func stop(arrival: Double) -> Double? {
        guard let anchor else { return nil }
        let mac: Double
        if let floor {
            mac = arrival - floor + correction
        } else if let last {
            mac = last.mac + max(0, arrival - last.arrival)
        } else {
            mac = anchor
        }
        let at = mac - anchor
        guard let written = lastWritten else { return max(at, 0) }
        return max(at, written + Self.tick)
    }

    /// Ticks of the picture's timescale for `seconds`, rounded.
    static func ticks(_ seconds: Double) -> Int64 { Int64((seconds * Double(videoTimescale)).rounded()) }

    /// Frames of the sound's rate for `seconds`, rounded: sample-exact.
    static func frames(_ seconds: Double) -> Int64 { Int64((seconds * Double(soundRate)).rounded()) }

    /// Rules 1 and 4: the floor, and a step of the Mac's clock, which moves the correction so that the Mac time
    /// goes on from the last picture as far as the arrivals say. The picture's Mac time.
    private mutating func observe(stamp: Double, arrival: Double) -> Double {
        let d = arrival - stamp
        if let floor {
            if d - floor > Self.stepLimit { above += 1 } else { above = 0 }
            if above >= Self.stepFrames || floor - d > Self.stepLimit, let last {
                correction = last.mac + max(0, arrival - last.arrival) - stamp
                buckets = []
                self.floor = nil
                above = 0
                steps += 1
            }
        }
        let second = Int(arrival.rounded(.down))
        if let i = buckets.lastIndex(where: { $0.second == second }) {
            buckets[i].least = min(buckets[i].least, d)
        } else {
            buckets.append((second, d))
        }
        buckets.removeAll { $0.second <= second - Self.floorWindow }
        floor = buckets.map(\.least).min() ?? floor
        return stamp + correction
    }
}

/// The recorder's order of things (rules 3 to 7 together): what StreamRecorder writes where, as it takes the
/// stream's messages in their order on its queue. Pure, so the random recordings of Tests/checks/recording run
/// the very decisions the recorder carries out; StreamRecorder only does what the actions say (AVAssetWriter,
/// the decoder, the samples). `Sets` stands for the parameter sets (anything Equatable), `id` for a frame the
/// caller keeps until its action is done.
///
/// - The movie's first part opens at the light (the pre-roll's keyframe, or the session's last keyframe written
///   at 0:00), or at the next keyframe after "Starting…".
/// - New parameter sets close the open part at their arrival (its end the stop's time then); the next part opens
///   at the next keyframe, its 0:00, with a sound track of its own.
/// - Every picture goes through the chain (rule 5) and the clock (rule 4); each one written moves the sound
///   along behind it (rule 7, `follow`).
/// - Part times are seconds from the part's 0:00 (the pre-roll's are below 0); the recorder adds `sourceBase`
///   so the writer only ever sees positive times.
struct RecordingTimeline<Sets: Equatable> {
    /// Seconds added to every part time for the writer: the pre-roll lies before 0:00.
    static var sourceBase: Double { 10 }

    enum Action: Equatable {
        /// A new movie for these parameter sets: part `part`, from 1.
        case open(part: Int, sets: Sets)
        /// Write frame `id` at part time `at`.
        case picture(id: Int, at: Double)
        /// Write these onto the open part's sound track (packets of the message being taken, if any).
        case sound([RecordedSound.Write])
        /// Close part `part`: its end at part time `at`.
        case close(part: Int, at: Double)
        /// The chain broke: ask the Mac for a keyframe (rule 2's spacing applies).
        case askKeyframe
    }

    /// A frame the light found kept: the pre-roll's, or the session's last keyframe.
    struct Kept: Equatable {
        var id: Int
        var stamp: Double
        var arrival: Double
        var isKeyframe: Bool
    }

    let withSound: Bool
    private(set) var clock = RecordingClock()
    private(set) var chain = RecordingPolicy.PictureChain()
    /// The open part's sound track (nil without sound, or with no part open).
    private(set) var sound: RecordedSound?
    private(set) var formats: [Int: RecordedSound.Format] = [:]
    /// Parts opened so far.
    private(set) var parts = 0
    /// The open part's parameter sets, nil while none is open.
    private(set) var partSets: Sets?
    /// The open part's 0:00 on the recording's clock.
    private(set) var partStart: Double = 0
    /// The newest parameter sets (a kind 0): the next part's.
    private(set) var sets: Sets?
    /// The light has come (`begin`).
    private(set) var begun = false
    /// "Starting…": no picture is written until a keyframe comes.
    private(set) var waitingForStart = false
    /// The recording ended (`stop`): nothing more is taken.
    private(set) var stopped = false

    init(withSound: Bool) { self.withSound = withSound }

    /// The light. `start`: RecordingPolicy.start's answer; `sets`: the newest parameter sets (the pre-roll's and
    /// the last keyframe's: new sets empty the pre-roll and make the kept keyframe stale); `preroll`: the
    /// pre-roll's frames, a keyframe first (`.atLight(.sinceAsk)`); `lastKeyframe`: the session's
    /// (`.atLight(.lastKeyframe)`); `seeds`: the stamp and arrival of every frame kept since "1" and of the last
    /// keyframe, in their order (the pre-roll's among them), for the floor and the steps; `light`: the light's
    /// arrival-clock moment.
    mutating func begin(_ start: RecordingPolicy.StartPoint, sets: Sets?, preroll: [Kept], lastKeyframe: Kept?,
                        seeds: [(stamp: Double, arrival: Double)], light: Double) -> [Action] {
        guard !begun, !stopped else { return [] }
        begun = true
        if let sets { self.sets = sets }
        var macOf: [Double: Double] = [:]
        for s in seeds { macOf[s.stamp] = clock.seed(stamp: s.stamp, arrival: s.arrival) }
        switch start {
        case .atLight(.sinceAsk):
            guard let first = preroll.first, first.isKeyframe, self.sets != nil,
                  clock.anchorAtLight(arrival: light) else { break }
            var actions = openPart(at: 0)
            for f in preroll {
                // Each where the clock had it as it came: a step inside the pre-roll makes no jump.
                let mac = macOf[f.stamp] ?? clock.seed(stamp: f.stamp, arrival: f.arrival)
                actions += take(f.id, stamp: f.stamp, isKeyframe: f.isKeyframe, arrival: f.arrival, mac: mac)
            }
            return actions
        case .atLight(.lastKeyframe):
            guard let k = lastKeyframe, self.sets != nil, clock.anchorAtLight(arrival: light) else { break }
            // The picture is still: the keyframe is it, at the light.
            var actions = openPart(at: 0)
            _ = chain.fate(stamp: k.stamp, isKeyframe: true)
            chain.written(stamp: k.stamp)
            clock.written(0)
            actions.append(.picture(id: k.id, at: 0))
            return actions
        case .atNextKeyframe:
            break
        }
        waitingForStart = true
        return []
    }

    /// A kind 0 (the Mac sends them before every keyframe): sets that differ from the open part's close it at
    /// their arrival.
    mutating func parameterSets(_ s: Sets, arrival: Double) -> [Action] {
        sets = s
        guard begun, !stopped, RecordingPolicy.endsPart(current: partSets, incoming: s) else { return [] }
        return closePart(arrival: arrival)
    }

    /// A kind 1, in its order. `id`: the caller's for the frame, kept until its `.picture` is done.
    mutating func frame(id: Int, stamp: Double, isKeyframe: Bool, arrival: Double) -> [Action] {
        guard begun, !stopped else { return [] }
        if waitingForStart {
            guard isKeyframe, sets != nil else {
                clock.seed(stamp: stamp, arrival: arrival)
                return []
            }
            clock.anchorAt(stamp: stamp)
            waitingForStart = false
        }
        return take(id, stamp: stamp, isKeyframe: isKeyframe, arrival: arrival)
    }

    /// The last `.picture` could not be written (the writer not ready, a sample that could not be made): every
    /// delta now waits for a keyframe, and one is asked for when this broke a whole chain.
    mutating func notWritten() -> [Action] {
        chain.lost() ? [.askKeyframe] : []
    }

    /// A frame dropped before it reached the recorder's queue (`pendingLimit`): the same, in its place.
    mutating func lost() -> [Action] {
        guard begun, !stopped, !waitingForStart else { return [] }
        return notWritten()
    }

    /// A kind 43 format.
    mutating func audioFormat(epoch: Int, _ format: RecordedSound.Format) {
        formats[epoch] = format
        sound?.format(epoch: epoch, format)
    }

    /// One codec packet of a kind 43 message: packet `index`, its seq, the message's segment flag, and the
    /// message's stamp moved on to this packet's first frame. Nothing to decode without sound or an open part.
    mutating func audio(epoch: Int, seq: UInt32, index: Int, segmentStart: Bool, stamp: Double) -> (RecordedSound.Decode, [RecordedSound.Write]) {
        guard withSound, !stopped, sound != nil else { return (.skip, []) }
        let time = clock.sound(stamp: stamp).map { $0 - partStart }
        // In place (`sound!`): a copy would copy its memory of the packets seen at every packet.
        return sound!.packet(epoch: epoch, seq: seq, index: index, segmentStart: segmentStart, time: time)
    }

    /// The recording's elapsed time at `arrival` (the light's, and the stop's): nil before the movie's start.
    func elapsed(arrival: Double) -> Double? {
        clock.stop(arrival: arrival)
    }

    /// The end, at `arrival`: the open part closes at the stop's time.
    mutating func stop(arrival: Double) -> [Action] {
        guard !stopped else { return [] }
        stopped = true
        return partSets == nil ? [] : closePart(arrival: arrival)
    }

    // MARK: - Inside

    /// One frame through the chain and the clock (`mac`: its Mac time, seeded already).
    private mutating func take(_ id: Int, stamp: Double, isKeyframe: Bool, arrival: Double, mac: Double? = nil) -> [Action] {
        switch chain.fate(stamp: stamp, isKeyframe: isKeyframe) {
        case .duplicate:
            return []
        case .waitForKeyframe:
            if mac == nil { _ = clock.picture(stamp: stamp, arrival: arrival) }   // the floor and the steps still see it
            return []
        case .write:
            break
        }
        let t = mac.map { clock.place($0, arrival: arrival) } ?? clock.picture(stamp: stamp, arrival: arrival)
        var actions: [Action] = []
        if partSets == nil {
            // Only a keyframe opens a part (the chain waits for one after every close).
            guard isKeyframe, sets != nil else { return [] }
            actions += openPart(at: t)
        }
        clock.written(t)
        chain.written(stamp: stamp)
        actions.append(.picture(id: id, at: t - partStart))
        if sound != nil {
            let writes = sound!.follow(picture: t - partStart)
            if !writes.isEmpty { actions.append(.sound(writes)) }
        }
        return actions
    }

    private mutating func openPart(at start: Double) -> [Action] {
        guard let sets else { return [] }
        parts += 1
        partSets = sets
        partStart = start
        if withSound {
            var s = RecordedSound()
            for (epoch, f) in formats { s.format(epoch: epoch, f) }
            sound = s
        }
        return [.open(part: parts, sets: sets)]
    }

    private mutating func closePart(arrival: Double) -> [Action] {
        let end = (clock.stop(arrival: arrival) ?? partStart) - partStart
        var actions: [Action] = []
        if sound != nil {
            let writes = sound!.stop(at: end)
            if !writes.isEmpty { actions.append(.sound(writes)) }
        }
        actions.append(.close(part: parts, at: end))
        partSets = nil
        sound = nil
        chain.restart()
        return actions
    }
}
