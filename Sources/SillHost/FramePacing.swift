import Foundation

/// The frames each device is sent, at home and away: which frame goes to which device, when a keyframe is asked for on
/// a device's behalf, and when a device is so far behind that it is dropped (docs/steps/2026-11-24-home-backlog.md).
/// StreamServer keeps the counts (what each connection has not taken yet, the clocks) and does what this says;
/// everything a decision is made from is here. Pure (Foundation only), checked with swiftc (Tests/checks/frame-pacing),
/// with a model of a connection's queue on links from 6 Mbit/s to a cable's 600.
///
/// What a device "has not taken" is Network.framework's own queue, in Sill's memory: `.contentProcessed` comes once the
/// kernel has a message's last byte, so the kernel's send buffer (up to 4 MB here, `net.inet.tcp.autosndbufmax`) and
/// the network's queues come on top, unseen. The encoder is shared: a keyframe asked for on one device's behalf goes to
/// every device, and at Retina size each one is a 50–100 ms hitch on a device that did not need it (the trackpad
/// stutter's cause 2, docs/steps/2026-09-22-trackpad-stutter.md).
///
/// Home and away share:
/// - A device that lost a frame waits for a keyframe (every later delta references the one it lost). The keyframe that
///   ends its wait goes with the parameter sets: at once when it is the device's first since it was admitted or the
///   stream changed, otherwise only while its queue is within its route's budget; else that keyframe is withheld too,
///   and one is asked for again once the queue has drained to `idleBytes`, so that it leads the queue.
/// - A frame that comes while the queue is over the budget is dropped, keyframe or not: latency beats quality.
/// - A device that keeps losing frames asks for its keyframe only once its queue has drained, at most every
///   `keyframeSpacing` for all such devices of its route together, and beside a device at home that is not losing
///   frames only once `keyframeSpacingBeside` has passed since the last such request and since the last keyframe of
///   any kind, the encoder's own interval (`keyframeDue`). So one slow link never makes the shared stream keyframes
///   for everyone. The sweep asks on the same terms once a second, for a window that went still (`asksAtSweep`).
/// - The ceiling (`eviction`): a device whose connection holds more than `ceilingBytes`, or whose oldest frame not
///   taken has waited past its route's limit, is dropped once, with one line, and nothing more is queued for it; it
///   reconnects as every dropped device does. Beside it the drain backstop, as before: no frame taken for `deadAfter`
///   at home, `remoteDeadAfter` away, each after its grace.
///
/// Where they differ, and why:
/// - The budget. Away it is bytes (`remoteBacklogBudget` and the rest, docs/remote-bundle-plan.md §3), tuned on uplinks
///   of a few Mbit/s. At home it is time: a frame that has waited `homeLate` in the queue is late, and so is every frame
///   behind it. Home streams run from Low's 4 Mbit/s to Extreme's 300 at 120 fps, over anything from a weak Wi-Fi to a
///   cable of hundreds of megabits, so no one byte count fits both ends; a link that carries the stream never holds a
///   frame for a second, and a second of waiting is latency whatever the sizes.
/// - At home a delta is also dropped while more than `homeDeltaMessages` messages wait, the rule since the first
///   commit: on a fast link that is a passing jam, and a single loss costs about three frames.
/// - A loss at home after `homeCalmAfter` without one asks for its keyframe at once, as it always did: a one-off on a
///   link that carries the stream. Away never asks at once: there a slow uplink is the normal case.
/// - Each route keeps its own clock of spaced requests: away's `beside` is any device at home (as since PR #34), home's
///   a device at home that is not losing frames.
enum FramePacing {
    // MARK: The numbers (the step file has the measurements behind them)

    /// Home: a frame that has waited longer than this in its connection is late, and so is every frame behind it. A link
    /// that carries the stream takes each message within milliseconds (on loopback a 2 MB keyframe leaves for a 600
    /// Mbit/s path within 30 ms); Wi-Fi's dozes and AWDL's off-channel spells hold one for 0.1–0.3 s. A link that holds a
    /// frame for a whole second cannot carry the stream: what is sent after it only adds to the wait.
    static let homeLate: TimeInterval = 1
    /// Home: a delta is dropped while more than this many messages wait (frames and control messages, not the sound).
    static let homeDeltaMessages = 2
    /// Home: a loss this long after the device's last one is a one-off, whose keyframe is asked for at once; a loss
    /// sooner is a link that cannot carry the stream, and its keyframe waits for the drain and the spacing.
    static let homeCalmAfter: TimeInterval = 2
    /// A queue this short holds nothing but control messages (pongs, a settings reply): a keyframe asked for now leads
    /// it.
    static let idleBytes = 16 * 1024
    /// Away: a backlog that never drops a frame, about a quarter second at 8 Mbit/s, 30 frames of the Low preset.
    static let remoteBacklogBudget = 256 * 1024
    /// Away: growth over what a keyframe left behind that still counts as noise (a thumbnail pass is 11 small JPEGs).
    static let remoteBacklogSlack = 128 * 1024
    /// Away: how much may queue behind a keyframe the connection is still taking: about a second of the Low preset's
    /// deltas (60 × ~8 KB), what piles up while a large keyframe crosses a hotspot; past it the stream is more than the
    /// link carries.
    static let remoteHoldCap = 512 * 1024
    /// A spaced request (`keyframeDue`): at most one this often for every device of a route that keeps losing frames.
    static let keyframeSpacing: TimeInterval = 2
    /// The same beside a device at home that is not losing frames, and as long since the last keyframe of any kind: the
    /// encoder's own interval (HEVCEncoder's `fps * 4` frames).
    static let keyframeSpacingBeside: TimeInterval = 4
    /// The drain backstop at home: no frame taken for this long, once `graceAfterConnect` has passed since the device was
    /// admitted (the catalog and the first keyframe), is a device that stopped reading (app killed, device asleep).
    static let deadAfter: TimeInterval = 4
    static let graceAfterConnect: TimeInterval = 8
    /// The same away, where a keyframe takes seconds on a slow uplink (1.5 MB at 2 Mbit/s: 6 s).
    static let remoteDeadAfter: TimeInterval = 15
    static let remoteGrace: TimeInterval = 15
    /// The ceiling on what any device's connection may hold: twice the largest frame a device takes
    /// (StreamMessage.maxFramePayload, 32 MiB). The rules above keep a queue to a few megabytes; this is the backstop.
    static let ceilingBytes = 64 << 20
    /// The ceiling on how long its oldest frame may wait, after the grace: at home ten times `homeLate` and past the
    /// drain backstop; away twice `remoteDeadAfter`, and above the most remote pacing holds on a 0.3 Mbit/s link
    /// (256 KB, the 512 KB hold cap and a keyframe: about 24 s, issue #427).
    static let ceilingWait: TimeInterval = 10
    static let remoteCeilingWait: TimeInterval = 30

    // MARK: What a decision is made from

    /// What the pacing keeps for one device between frames (StreamServer's `Client.pacing`).
    struct State: Equatable {
        /// It waits for a keyframe: it lost a frame, or has had none since it was admitted or the stream changed.
        var needsKeyframe = true
        /// No keyframe has reached it since it was admitted or the stream changed: the next one goes out whatever its
        /// queue holds, and the frames skipped meanwhile do not count against its link (LinkJudge: that wait is the
        /// connect or a restart, not the link).
        var awaitingFirstKeyframe = true
        /// A keyframe is to be asked for on its behalf once its queue has drained and a request is due.
        var keyframeWanted = false
        /// Home: when it last lost a frame (dropped, or withheld while it waited), not counting the wait for its first
        /// keyframe; nil while it has lost none. Read by `calm`.
        var lastLossAt: TimeInterval?
        /// Away: the smallest backlog since the keyframes it was taking were all taken, which starts at what they left
        /// behind them (the frames that queued while they were).
        var backlogFloor = 0
    }

    /// What a device's connection has not taken yet, when a frame comes.
    struct Queue: Equatable {
        /// Bytes handed to it and not taken (`pendingBytes`): every message's, the sound's too, not the ticks'.
        var bytes = 0
        /// Messages handed to it and not taken (`inflight`): frames and control messages, not the sound.
        var messages = 0
        /// How long the oldest frame it has not taken has waited (`FrameTimes`); 0 with none.
        var oldestFrameWait: TimeInterval = 0
        /// Away: the keyframes it is still taking, and their bytes (`keyframesInFlight`).
        var keyframesTaking = 0
        var keyframeBytesTaking = 0
    }

    /// What happens to one frame for one device.
    struct Outcome: Equatable {
        enum Verdict: Equatable {
            /// It goes (`net.sent`), after the stream's parameter sets when `parameterSets`.
            case sent
            /// Dropped (`net.dropped`): the device waits for a keyframe from now on.
            case dropped
            /// Withheld while the device waits for a keyframe (`net.waitKey`).
            case waiting
        }
        /// A keyframe asked for on the device's behalf now: `atOnce`, a home device's one-off loss, as it always was;
        /// `spaced`, a request its route's clock counts (`keyframeDue`).
        enum Ask: Equatable { case atOnce, spaced }
        var verdict: Verdict
        /// This keyframe ends the device's wait: the parameter sets go first.
        var parameterSets = false
        /// It counts against the device's link this second (LinkJudge's `withheld`): every frame not sent but those
        /// before its first keyframe.
        var withheld = false
        var ask: Ask?
    }

    // MARK: The rule for one frame

    /// One frame for one device, by its route, updating `state`. `parameterSets`: the stream's are known (always, once
    /// a keyframe has been encoded). `due`: a spaced request may be made now on this device's behalf (`keyframeDue`
    /// with its route's clock), read only when one would be.
    static func frame(away: Bool, keyframe: Bool, parameterSets: Bool, state: inout State, queue: Queue,
                      now: TimeInterval, due: @autoclosure () -> Bool) -> Outcome {
        away ? awayFrame(keyframe: keyframe, parameterSets: parameterSets, state: &state, queue: queue, due: due)
             : homeFrame(keyframe: keyframe, parameterSets: parameterSets, state: &state, queue: queue, now: now, due: due)
    }

    /// At home (the plain door, and every TLS session at the home door, the cable's included).
    private static func homeFrame(keyframe: Bool, parameterSets: Bool, state s: inout State, queue q: Queue,
                                  now: TimeInterval, due: () -> Bool) -> Outcome {
        let late = q.oldestFrameWait > homeLate
        if s.needsKeyframe {
            if keyframe, parameterSets {
                if s.awaitingFirstKeyframe || !late {
                    s.needsKeyframe = false
                    s.awaitingFirstKeyframe = false
                    return Outcome(verdict: .sent, parameterSets: true)
                }
                // The keyframe it waits for, and late too: withheld, and asked for again once the queue has drained.
                s.lastLossAt = now
                s.keyframeWanted = true
                return Outcome(verdict: .waiting, withheld: true)
            }
            let counted = !s.awaitingFirstKeyframe
            if counted { s.lastLossAt = now }
            var ask: Outcome.Ask?
            if s.keyframeWanted, !s.awaitingFirstKeyframe, q.bytes <= idleBytes, due() {
                s.keyframeWanted = false
                ask = .spaced
            }
            return Outcome(verdict: .waiting, withheld: counted, ask: ask)
        }
        guard late || (!keyframe && q.messages > homeDeltaMessages) else { return Outcome(verdict: .sent) }
        // Dropped. Every later delta references it, so the device waits for a keyframe (deltas sent anyway showed as
        // flicker on the iPad). A one-off asks at once; anything else once the queue has drained and one is due.
        let oneOff = !late && calm(s, now: now)
        s.needsKeyframe = true
        s.lastLossAt = now
        s.keyframeWanted = !oneOff
        return Outcome(verdict: .dropped, withheld: true, ask: oneOff ? .atOnce : nil)
    }

    /// Away (docs/remote-bundle-plan.md §3): StreamServer's `paceRemote` until 2026-11-24, unchanged.
    /// - Behind a keyframe the connection is still taking, frames go out up to `remoteHoldCap`: every delta references
    ///   that keyframe, so dropping them for its sake wasted it and looped (drop, a keyframe 2 s later, the next delta
    ///   dropped behind it: 2026-09-25, 0–3 fps and rtt up to 12 s at 150 Mbps on a phone's hotspot). What counts
    ///   against the cap is what waits beyond every keyframe still being taken: a restarted stream's first keyframe goes
    ///   out at once, behind the old stream's if that one is still crossing, and its deltas reference it alone.
    /// - Otherwise a frame is dropped only when the backlog exceeds both `remoteBacklogBudget` and what the last keyframe
    ///   left behind it (`backlogFloor`, following the backlog down) plus `remoteBacklogSlack`: a backlog that shrinks is
    ///   a link catching up, one that grows is a stream the link cannot carry.
    /// - A device that lost a frame asks for a keyframe only once its connection holds `idleBytes` or less, so the
    ///   keyframe leads the queue instead of queueing behind the backlog that caused the drop, when a later frame comes
    ///   or, once the window has gone still and none does, at the sweep.
    /// - The keyframe it waits for goes out when the backlog fits the budget, or at once when it has had none since it
    ///   was admitted or the stream changed.
    private static func awayFrame(keyframe: Bool, parameterSets: Bool, state s: inout State, queue q: Queue,
                                  due: () -> Bool) -> Outcome {
        s.backlogFloor = min(s.backlogFloor, q.bytes)
        if s.needsKeyframe {
            guard keyframe else {
                var ask: Outcome.Ask?
                if s.keyframeWanted, q.bytes <= idleBytes, due() {
                    s.keyframeWanted = false
                    ask = .spaced
                }
                return Outcome(verdict: .waiting, withheld: !s.awaitingFirstKeyframe, ask: ask)
            }
            guard s.awaitingFirstKeyframe || q.bytes <= remoteBacklogBudget, parameterSets else {
                // Its queue is still full: this keyframe is lost to it too. Asked for again once it has drained
                // (within the spacing) rather than waiting for the encoder's own.
                s.keyframeWanted = true
                return Outcome(verdict: .waiting, withheld: true)
            }
            s.needsKeyframe = false
            s.awaitingFirstKeyframe = false
            return Outcome(verdict: .sent, parameterSets: true)
        }
        let tooMuch = q.keyframesTaking > 0 ? q.bytes - q.keyframeBytesTaking > remoteHoldCap
                                            : q.bytes > max(remoteBacklogBudget, s.backlogFloor + remoteBacklogSlack)
        guard tooMuch else { return Outcome(verdict: .sent) }
        s.needsKeyframe = true
        s.keyframeWanted = true
        return Outcome(verdict: .dropped, withheld: true)
    }

    /// A home device that has lost no frame for `homeCalmAfter`: its next loss is a one-off. Also what makes a device
    /// at home one that home requests are spaced beside.
    static func calm(_ s: State, now: TimeInterval) -> Bool {
        s.lastLossAt.map { now - $0 >= homeCalmAfter } ?? true
    }

    /// The sweep, once a second: a device whose window went still right after it lost a frame gets no later frame to
    /// ask with, and would keep the picture from before the loss until the window changes (the end of a scroll, the
    /// last letters typed). So it is asked for here, on the frame's terms (it waits, wants one, has had its first, and
    /// its queue has drained), when a request is due; the encoder then encodes the still window's last frame again.
    static func asksAtSweep(_ s: State, _ q: Queue) -> Bool {
        s.needsKeyframe && s.keyframeWanted && !s.awaitingFirstKeyframe && q.bytes <= idleBytes
    }

    /// Whether a spaced request may be made now, by a route's clock (`lastRequest`): alone, `keyframeSpacing` after the
    /// last such request. A keyframe is encoded once and goes to every device, though, so `beside` a device at home that
    /// is not losing frames the request also waits until `keyframeSpacingBeside` has passed since it and since the last
    /// keyframe of any kind (`lastKeyframeAt`): the encoder's own is due by then, so a slow link gives that device no
    /// more keyframes than the encoder's interval would. It only brings one forward when frames come slower than the
    /// stream's rate; the slow device waits longer after a drop in exchange.
    static func keyframeDue(now: TimeInterval, lastRequest: TimeInterval, lastKeyframeAt: TimeInterval, beside: Bool) -> Bool {
        guard beside else { return now - lastRequest >= keyframeSpacing }
        return now - lastRequest >= keyframeSpacingBeside && now - lastKeyframeAt >= keyframeSpacingBeside
    }

    // MARK: Too far behind

    enum Eviction: Equatable {
        /// No frame taken for this many seconds: a device that stopped reading (the drain backstop).
        case notDraining(seconds: Int)
        /// Past the ceiling: its connection holds `bytes`, its oldest frame waiting `wait` seconds.
        case tooFarBehind(bytes: Int, wait: TimeInterval)
    }

    /// Whether a device is dropped now, and why: its connection holds more than `ceilingBytes` (at any time); or, once
    /// its grace has passed since it was admitted, no frame was taken for longer than its route's drain backstop
    /// (`noFrameTakenFor`: since one was last taken, or queued with none waiting; nil with none waiting), or its oldest
    /// frame has waited longer than its route's ceiling. `connectedFor`: since it was admitted.
    static func eviction(away: Bool, connectedFor: TimeInterval, noFrameTakenFor: TimeInterval?, queue q: Queue) -> Eviction? {
        if q.bytes > ceilingBytes { return .tooFarBehind(bytes: q.bytes, wait: q.oldestFrameWait) }
        guard connectedFor > (away ? remoteGrace : graceAfterConnect) else { return nil }
        if let quiet = noFrameTakenFor, quiet > (away ? remoteDeadAfter : deadAfter) { return .notDraining(seconds: Int(quiet)) }
        if q.oldestFrameWait > (away ? remoteCeilingWait : ceilingWait) { return .tooFarBehind(bytes: q.bytes, wait: q.oldestFrameWait) }
        return nil
    }

    /// The one line a dropped device gets: "Client not draining for 4 s, dropping: 192.168.1.20:52114", as since the
    /// first commit, or "Client too far behind (64.1 MB queued for it, its oldest frame waiting 3 s), dropping: …".
    static func line(_ e: Eviction, endpoint: String) -> String {
        switch e {
        case .notDraining(let seconds):
            return "Client not draining for \(seconds) s, dropping: \(endpoint)"
        case .tooFarBehind(let bytes, let wait):
            return "Client too far behind (\(megabytes(bytes)) queued for it, its oldest frame waiting \(Int(wait)) s), dropping: \(endpoint)"
        }
    }

    /// 67_200_000 → "67.2 MB" (10^6 bytes, as LinkJudge's lines count them), 900_000 → "0.9 MB".
    static func megabytes(_ n: Int) -> String {
        let tenths = Int((Double(n) / 100_000).rounded())
        return "\(tenths / 10).\(tenths % 10) MB"
    }

    // MARK: The frames a connection has not taken

    /// When each frame a connection has not taken yet was handed to it, oldest first. A connection takes its messages
    /// in order, so the frame taken is always the oldest one still there.
    struct FrameTimes: Equatable {
        private var times: [TimeInterval] = []
        private var head = 0
        /// Frames handed over and not taken.
        var count: Int { times.count - head }
        /// A frame was handed to the connection at `t`.
        mutating func handed(at t: TimeInterval) { times.append(t) }
        /// The oldest was taken (its `.contentProcessed`, or the connection's end).
        mutating func taken() {
            guard head < times.count else { return }
            head += 1
            if head == times.count {
                times.removeAll(keepingCapacity: true)
                head = 0
            } else if head >= 1024 {
                times.removeFirst(head)
                head = 0
            }
        }
        /// How long the oldest frame not taken has waited at `now`; 0 with none.
        func oldestWait(now: TimeInterval) -> TimeInterval {
            head < times.count ? max(0, now - times[head]) : 0
        }
    }
}
