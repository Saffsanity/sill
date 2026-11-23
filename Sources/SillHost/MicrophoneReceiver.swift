import Foundation
import Network
import os
import SillAudio
import StreamProtocol

/// The Mac's receiving side of the devices' microphones (kind 48, docs/microphone-plan.md §3.3, §3.4, §6): every
/// kind 48 comes here from StreamServer's network queue, in arrival order, with the lock's reading as it arrived,
/// never through the main actor; MicrophonePolicy.Host decides on this queue, `sill.mic`; the holder's packets go
/// through SillAudio's decoder (mono) and its playout in the microphone's mode, and on to the output, the seam
/// where Sill Microphone takes the sound (MicrophoneOutput). Kind 16's microphone per connection and what the
/// window list says reach the main actor only when they change, never per packet. Nothing here touches AppKit or
/// any audio device; the output alone would (Sill Microphone's feed, the plan's next part; a test host's sink now).
///
/// Threads: `received` on the network queue (it never waits: past `maxBacklog` bytes not yet dealt with, packets
/// are dropped before they are queued); the coordinator's calls (sessions, the trust list, the switch, the lock)
/// on the main actor, each hopping here; the output's readiness and apps here.
final class MicrophoneReceiver: @unchecked Sendable {
    /// `sill.mic`: the policy, the decoder, the playout, the output; every member below is touched only on it.
    let queue: DispatchQueue
    private var policy = MicrophonePolicy.Host()
    private let output: MicrophoneOutput
    private let gate: LockGate
    private let testLog: Bool
    private var ids: [ObjectIdentifier: Int] = [:]
    private var oids: [Int: ObjectIdentifier] = [:]
    private var names: [Int: String] = [:]
    private var keys: [Int: String] = [:]
    private var paired: [Int: Bool] = [:]
    private var away: [Int: Bool] = [:]
    private var nextID = 1
    private var advertised: Int?
    private var inUse: String?
    private var timer: DispatchSourceTimer?
    // The playout: the device (by key) whose sound it times, the session and epoch it takes packets of.
    private var model = AudioPlayout(mode: .microphone)
    private var decoder: AudioDecoder?
    private var playingKey: String?
    private var source: (session: Int, epoch: Int, framesPerPacket: Int)?
    private var kept: [Int: [Float]] = [:]
    private var deadlineTimer: DispatchSourceTimer?
    /// When the playout last lost its source; the output stops `idleAfter` later.
    private var idleSince: Double?
    static let idleAfter = 10.0
    /// Bytes of kind 48 handed over by the network queue and not yet dealt with here; past it packets are dropped
    /// before they are queued (latency beats quality): about 30 s of sound at 64 kbps.
    private let backlog = OSAllocatedUnfairLock(initialState: 0)
    static let maxBacklog = 256 << 10
    /// How far a packet's stamp may be from this Mac's wall clock.
    static let maxClockSkew: Double = 86_400

    /// Each connection's kind 16 microphone when it changes (nil: none), the window list's `microphone` (1 or
    /// 0) when it changes, and the device whose sound is Sill Microphone's (nil: none). Called on `sill.mic`; the
    /// coordinator hops to the main actor.
    var onStates: (([ObjectIdentifier: MicrophoneState?]) -> Void)?
    var onAdvertised: ((Int) -> Void)?
    var onInUse: ((String?) -> Void)?

    /// `queue` is `sill.mic`, made by the caller before the output, which runs on it too.
    init(queue: DispatchQueue, output: MicrophoneOutput, gate: LockGate, testLog: Bool) {
        self.queue = queue
        self.output = output
        self.gate = gate
        self.testLog = testLog
    }

    /// Starts: the switch, Sill Microphone's readiness, the apps and the lock's reading pushed in, the output's
    /// callbacks set, the policy's second.
    func start(switchOn: Bool) {
        let unlocked = gate.reading == .unlocked
        queue.async { [self] in
            output.onReady = { [weak self] ready in self?.handle(.readyChanged(ready)) }
            output.onApp = { [weak self] uses in self?.handle(.appChanged(uses)) }
            handle(.switchChanged(switchOn))
            handle(.readyChanged(output.ready))
            handle(.appChanged(output.appUses))
            handle(.unlockedChanged(unlocked))
            output.watch()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.second() }
            t.resume()
            timer = t
        }
    }

    // MARK: From the coordinator (the main actor): sessions, the trust list, the lock, the switch

    /// A session joined, before its catalog goes: its key (nil at a plain door), whether that key is on the
    /// trust list now, its name for the lines, and whether it is away (the playout's cover).
    func joined(_ connection: NWConnection, key: Data?, paired isPaired: Bool, name: String, away isAway: Bool) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            let id = nextID
            nextID += 1
            ids[oid] = id
            oids[id] = oid
            names[id] = name
            keys[id] = key.map { Base64URL.encode($0) }
            paired[id] = isPaired
            away[id] = isAway
            handle(.joined(id, key: keys[id], paired: isPaired, name: name))
        }
    }

    func left(_ connection: NWConnection) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            guard let id = ids.removeValue(forKey: oid) else { return }
            handle(.left(id))
            oids[id] = nil; names[id] = nil; keys[id] = nil; paired[id] = nil; away[id] = nil
        }
    }

    /// The Mac no longer serves the session (cut off): its microphone ends now.
    func revoked(_ connection: NWConnection) {
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            guard let id = ids[oid] else { return }
            paired[id] = false
            handle(.paired(id, false))
        }
    }

    /// Each session's key as the trust list has it now (the status snapshot, on every change): one that left
    /// the list is the device's removal (its microphone freed at once), one that joined it counts from now.
    func syncPaired(_ now: [ObjectIdentifier: Bool]) {
        queue.async { [self] in
            for (oid, isPaired) in now {
                guard let id = ids[oid], let was = paired[id], was != isPaired else { continue }
                paired[id] = isPaired
                if !isPaired, let key = keys[id] { handle(.removed(key: key)) } else { handle(.paired(id, isPaired)) }
            }
        }
    }

    func setSwitch(_ on: Bool) { queue.async { [self] in handle(.switchChanged(on)) } }

    /// This user on the console with its screen unlocked (LockPolicy's reading, as the coordinator acts on it).
    func setUnlocked(_ unlocked: Bool) { queue.async { [self] in handle(.unlockedChanged(unlocked)) } }

    // MARK: From the network queue: kind 48

    /// A kind 48 from `connection`, with the lock's reading as it arrived. Never waits: past `maxBacklog` bytes
    /// not yet dealt with, a packets message is dropped here and counted.
    func received(_ message: StreamMessage, from connection: NWConnection, arrived: LockPolicy.Reading) {
        let size = message.payload.count
        let isPackets = message.payload.first == MicrophoneMessage.typePackets
        let taken = backlog.withLock { pending -> Bool in
            guard pending + size <= Self.maxBacklog || !isPackets else { return false }
            pending += size
            return true
        }
        guard taken else { Stats.shared.bump("mic.dropped.backlog"); return }
        let oid = ObjectIdentifier(connection)
        queue.async { [self] in
            defer { backlog.withLock { $0 -= size } }
            take(message, from: oid, arrived: arrived)
        }
    }

    // MARK: Inside, on `sill.mic`

    private var now: Double { MicrophoneClock.now() }

    private func handle(_ event: MicrophonePolicy.Host.Event) {
        apply(policy.handle(event, at: now))
    }

    private func take(_ message: StreamMessage, from oid: ObjectIdentifier, arrived: LockPolicy.Reading) {
        guard let id = ids[oid] else { Stats.shared.bump("mic.refused.unknown"); return }
        // Judged at the more restrictive of the reading as it arrived and the reading now (LockPolicy): what a
        // device sent while this Mac was locked never acts after the unlock.
        let reading = LockPolicy.restrictive(arrived, gate.reading)
        if case .refuse = LockPolicy.decide(.microphone, arrived: arrived, now: gate.reading, paired: paired[id] ?? false) {
            apply(policy.lockedArrival(id, offConsole: reading == .offConsole, at: now))
            return
        }
        guard let m = MicrophoneMessage.parse(message.payload) else { Stats.shared.bump("mic.dropped.malformed"); return }
        switch m {
        case .format(let f):
            if testLog, f.isEpoch {
                print("Test microphone: epoch \(f.format.epoch ?? -1) from \(names[id] ?? "?"), \(f.format.framesPerPacket ?? 0) frames a packet, priming \(f.format.primingFrames ?? 0)")
            }
            handle(.format(id, f))
        case .end:
            handle(.end(id))
        case .packets(let p):
            packets(p, from: id, stamp: message.timestamp)
        }
    }

    private func packets(_ p: AudioPackets, from id: Int, stamp: Double) {
        let fpp = source?.session == id ? source!.framesPerPacket : MicrophoneCodec.framesPerPacket
        let r = policy.takesPackets(id, epoch: p.epoch, packets: p.packets.count, framesPerPacket: fpp, at: now)
        apply(r.effects)
        guard r.take, let src = source, src.session == id, src.epoch == p.epoch, let decoder else { return }
        // A stamp more than a day from this Mac's clock is no capture time (a device's clock is seconds or minutes off at
        // most): dropped, so no placement the playout makes of it can leave the timeline's range.
        guard stamp.isFinite, abs(stamp - Date().timeIntervalSince1970) < Self.maxClockSkew else {
            Stats.shared.bump("mic.dropped.stamp")
            return
        }
        let t = now
        feedReading(t)
        // The message's ten packets came together: they count for the floor and the cover before the first is
        // placed (AudioPlayout's microphone mode), each then placed in turn. Taken now, as the device's playout
        // takes the Mac's sound: the hop from the network queue is part of what the cover covers.
        model.message(epoch: p.epoch, seq: p.seq, count: p.packets.count, stamp: stamp, arrival: t)
        for (i, data) in p.packets.enumerated() {
            let plan = model.packet(epoch: p.epoch, seq: p.seq &+ UInt32(i), stamp: stamp + Double(i * src.framesPerPacket) / AudioPlayout.rate,
                                    segmentStart: p.segmentStart && i == 0, arrival: t, recorded: true, now: t)
            if plan.decode {
                if plan.resetFirst { decoder.reset() }
                let decoded = decoder.decode(data)?.left
                if let pid = plan.id {
                    let keep = src.framesPerPacket - plan.dropFront
                    if let pcm = decoded, pcm.count == src.framesPerPacket {
                        kept[pid] = Array(pcm.suffix(keep))
                    } else {
                        // Silence in its place; the decoder starts afresh at the next packet.
                        model.decodeFailed()
                        kept[pid] = [Float](repeating: 0, count: keep)
                        Stats.shared.bump("mic.decodeFailed")
                    }
                }
            }
            apply(plan.output)
        }
        armDeadline()
    }

    /// What the policy says: kind 16 and the list to the coordinator, the playout's source, lines and counts.
    private func apply(_ effects: [MicrophonePolicy.Host.Effect]) {
        var states: [ObjectIdentifier: MicrophoneState?] = [:]
        for e in effects {
            switch e {
            case .state(let id, let s):
                if let oid = oids[id] { states[oid] = s }
            case .playout(let key, let session, let format):
                startPlayout(key: key, session: session, format: format)
            case .noPlayout:
                stopPlayout()
            case .line(let l):
                print(l)
            case .count(let k):
                Stats.shared.bump(k)
            }
        }
        if !states.isEmpty { onStates?(states) }
        let a = policy.advertised
        if a != advertised { advertised = a; onAdvertised?(a) }
        let user = policy.inUse(at: now)
        if user != inUse { inUse = user; onInUse?(user) }
    }

    /// The holder's session records, and this is its epoch's format: the decoder and the playout follow it. A
    /// new device starts the playout afresh (its epochs and seqs are its own); the same device's new epoch is
    /// a new decoder; a move's new session of the same epoch changes nothing but where packets come from.
    private func startPlayout(key: String, session: Int, format f: MicrophoneFormat) {
        guard let epoch = f.format.epoch, let fpp = f.format.framesPerPacket else { return }
        if key != playingKey {
            apply(model.reset(.session))
            model = AudioPlayout(mode: .microphone)
            kept = [:]
            decoder = nil
            playingKey = key
        }
        model.away(away[session] ?? false)
        if model.format(epoch: epoch, framesPerPacket: fpp, primingFrames: f.format.primingFrames ?? 0, cookie: f.format.cookie ?? Data()) || decoder == nil {
            do {
                decoder = try AudioDecoder(framesPerPacket: fpp, cookie: f.format.cookie ?? Data(), channels: MicrophoneCodec.channels)
            } catch {
                decoder = nil
                print("Microphone: could not decode \(names[session] ?? "a device")’s sound: \(error).")
            }
        }
        source = (session, epoch, fpp)
        idleSince = nil
        if !output.running {
            guard output.start() else {
                print("Microphone: could not play into Sill Microphone.")
                return
            }
            apply(model.reset(.playback))
        }
        model.latency(output: output.outputLatency, io: output.ioBuffer, refresh: 1.0 / 60, streamFPS: 60)
    }

    /// No source: no packet is taken; what is in hand plays out and fades at its deadline (the playout's rule
    /// 10), then Sill Microphone hears silence, and the output stops `idleAfter` later.
    private func stopPlayout() {
        source = nil
        if idleSince == nil { idleSince = now }
    }

    private func schedule(_ s: AudioPlayout.Schedule) {
        guard let pcm = kept[s.id] else { return }
        defer { if s.part == .tail { kept[s.id] = nil } }
        let end = min(s.offset + s.count, pcm.count)
        guard s.offset < end else { return }
        var mono = Array(pcm[s.offset..<end])
        if s.change != 0 {
            var other = mono
            AudioPlayout.change(&mono, &other, by: s.change)
        }
        if s.fadeIn { AudioPlayout.fade(&mono, in: true) }
        if s.fadeOut { AudioPlayout.fade(&mono, in: false) }
        output.schedule(mono, at: s.at)
    }

    private func applyOutput(_ out: AudioPlayout.Output) {
        for id in out.discards { kept[id] = nil }
        for s in out.schedules { schedule(s) }
        if testLog, let j = model.takeJump() {
            print("Test microphone: jump \(String(format: "%+.0f", j.by * 1000)) ms (\(j.cause.rawValue))")
        }
    }

    private func apply(_ out: AudioPlayout.Output) { applyOutput(out) }

    /// The player's timeline as the output last rendered it.
    private func feedReading(_ t: Double) {
        guard output.running, let (sample, time) = output.reading() else { return }
        apply(model.played(sample: sample, at: time, now: t))
    }

    /// The tail in hand goes out at its deadline (the playout's rule 10).
    private func armDeadline() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        guard let d = model.deadline else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + max(0, d - now), leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let t = self.now
            self.feedReading(t)
            self.apply(self.model.tick(now: max(t, self.model.deadline ?? t)))
            self.armDeadline()
        }
        t.resume()
        deadlineTimer = t
    }

    /// Once a second: the policy's time (the grace, the silence, a refusal's end), the output's idle stop, and
    /// a test host's line of the playout's numbers.
    private func second() {
        handle(.tick)
        let t = now
        let s = model.takeSecond(now: t)
        if testLog, source != nil || s.placed > 0 {
            print("Test microphone: delay \(Int((s.delay * 1000).rounded())) ms (cover \(Int((s.cover * 1000).rounded())) ms), placed \(s.placed), late \(s.late), "
                  + "jumps \(s.jumps), frames +\(s.framesAdded) -\(s.framesDropped), joins \(s.joins), duplicates \(s.duplicates)")
        }
        Stats.shared.bump("mic.late", by: s.late)
        if let since = idleSince, t - since >= Self.idleAfter, output.running {
            output.stop()
            apply(model.reset(.playback))
            deadlineTimer?.cancel()
            deadlineTimer = nil
            idleSince = nil
        }
    }
}
