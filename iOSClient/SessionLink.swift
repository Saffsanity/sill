import Foundation
import Network

/// The session's connection to the Mac as StreamClient uses it: the connection it reads, and the
/// one door every message to the Mac goes out of (pings and the hello aside: each connection sends
/// its own, the hello first of all, straight to it).
/// Thread-safe: the network queue reads and sends, the main thread connects, hands over and
/// disconnects, and every send takes the lock, so messages leave in the order of the calls.
///
/// It also hands a session from one connection to another (a move: from peer-to-peer Wi-Fi to the
/// network, from Wi-Fi to the cable, StreamClient.finishMove) without reordering what the device
/// sends. The Mac reads each connection in arrival order and never orders one against another, and
/// the old connection can be the slow one (over AWDL the round trip was ~75 ms typical and up to
/// 2.4 s on 2026-09-24, against ~10 ms on the network), so a message sent on the new connection
/// could overtake one still in flight on the old: a click's release before its press (the button
/// then stays down and every later move is a drag), keystrokes swapped, an older pick landing after
/// a newer one. So the new connection is read at once, but nothing goes out to the Mac until a fence
/// ping, sent on the old connection after everything else sent there, comes back: the Mac echoes a
/// ping only once it has read all that came before it on that connection. Meanwhile messages wait
/// here, in order, and then go out on the session's connection ahead of anything later. The wait is
/// one round trip of the old connection, once per move. A hand-over while an earlier one's fence is
/// still up (two moves in a row: from AWDL to Wi-Fi, then at once to the cable) adds its fence to
/// that one: what waits goes out only once every fence is down, and each old connection is read
/// until its own pong, so nothing overtakes what the first old connection still carries. An old
/// connection whose fence is down is handed back for closing only once what waited has gone out
/// (`Released.close`): the viewport goes first, and the Mac must not be left without a connection
/// that sent one, or the stream's rate falls back to the default.
///
/// A session whose connection has lost its path (the cable pulled: StreamClient.followBestPath), or
/// has gone, moves without a fence of its own, since nothing sent on that connection comes back:
/// from the moment the move starts, what the device sends waits here (`hold`), in order, instead of
/// going into a connection that cannot deliver it, and goes out first on the new connection once it
/// takes the session (`adopt`), or back on the old one should the move not complete (`unhold`). A
/// hold and the fences stand apart, and what waits goes out only when neither does: a hold taken
/// while a hand-over's fence is up outlasts that fence, and a fence still up at `adopt` or `unhold`
/// keeps what waits until its pong, its connection closing or its timeout.
///
/// It also counts the input messages (kind 8) meant for the session's connection
/// (`inputsOnSession`), which the Mac's pointer reports are judged by (docs/pointer-visibility-plan.md
/// §3.3): each report (kind 26) says how many the Mac had read on the connection, and one built before
/// it read this device's latest input is dropped.
///
/// It also keeps the uplink ledger (UplinkLedger; the overview's §2.3, docs/camera-plan.md §6.2): every
/// message handed to the session's connection is counted until the connection has taken it
/// (`contentProcessed`), by lane, and what it took in the last second. Everything `send` hands goes at
/// once, as before; a camera frame (kind 46 type 2) goes only through `sendCamera`, never into `waiting`:
/// refused while a fence or a hold stands, so the camera never queues in front of the person's input in
/// Sill's own queue, and the camera's pacing (CameraPacing) reads `uplink` before each picture it encodes.
///
/// Foundation and Network only: it is checked on its own with swiftc against a local stand-in for
/// the Mac whose old connection is slow (docs/direct-wireless-plan.md, the review fixes).
final class SessionLink {
    /// What a fence or a hold let go of when it ended: how many messages went out, how many still
    /// wait (for another fence, or the hold), whether nothing stands any more (`clear`: what waited,
    /// if anything, has gone out), how long it stood, and, once clear, the old connections of the
    /// hand-overs whose fences are down, for the caller to close (the viewport has gone out ahead).
    struct Released {
        let held: Int
        let waiting: Int
        let clear: Bool
        let seconds: Double
        let close: [NWConnection]
    }

    private struct Fence {
        let old: NWConnection
        /// The fence ping's payload, echoed unchanged in its pong: random, so no other ping's pong
        /// can pass for it.
        let nonce: Data
        let since = ProcessInfo.processInfo.systemUptime
    }

    private struct Hold {
        let connection: NWConnection
        let since = ProcessInfo.processInfo.systemUptime
    }

    private let lock = NSLock()
    private var current: NWConnection?
    /// Hand-overs whose fence is still up, oldest first.
    private var fences: [Fence] = []
    /// The session's connection has lost its path, and a move to another is under way.
    private var holding: Hold?
    /// What waits for the fences and the hold, in the order sent.
    private var waiting: [Data] = []
    /// The old connections of hand-overs whose fence is down, until what waited has gone out.
    private var fencedOff: [NWConnection] = []
    /// Input messages counted for the session's connection: those handed to it since it became the
    /// session's, and those waiting to go out on it (see `inputsOnSession`).
    private var inputs = 0
    /// What the session's connection was handed and has not taken yet, by lane, and what it took in the
    /// last second (UplinkLedger).
    private var ledger = UplinkLedger()

    /// The uplink as the camera's pacing reads it (CameraPacing.encodes): whether a fence or a hold stands,
    /// the bytes the session's connection was handed and has not taken yet, every lane's, and what it took in
    /// the last second.
    struct Uplink: Equatable {
        let fenced: Bool
        let unsent: Int
        let takenLastSecond: Int
    }

    var uplink: Uplink {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let id = current.map(ObjectIdentifier.init)
        return Uplink(fenced: !fences.isEmpty || holding != nil, unsent: id.map { ledger.pending(for: $0) } ?? 0,
                      takenLastSecond: id.map { ledger.takenLastSecond(for: $0, at: now) } ?? 0)
    }

    /// The bytes the session's connection was handed and has not taken yet, by lane (for the checks).
    var pendingBytes: [UplinkLedger.Lane: Int] {
        lock.lock(); defer { lock.unlock() }
        var out: [UplinkLedger.Lane: Int] = [:]
        for lane in UplinkLedger.Lane.allCases {
            out[lane] = current.map { ledger.pending(lane, for: ObjectIdentifier($0)) } ?? 0
        }
        return out
    }

    /// The number of input messages (kind 8) counted for the session's connection: those `send` handed
    /// to it since it became the session's, and those waiting to go out on it once the fences and the
    /// hold are down, which is how many the Mac will have read on it once it has read everything this
    /// device sent (TCP keeps the order). It restarts whenever the session's connection changes (the
    /// setter, `handOver`, `adopt`) at the number still waiting, since those go out on the new one;
    /// `unhold`, `fenceReturned` and `release` leave it, as what waited was counted for the connection
    /// it goes out on; `dropHandOver` takes back what it drops, which never goes out.
    var inputsOnSession: Int {
        lock.lock(); defer { lock.unlock() }
        return inputs
    }

    /// A serialized message's first byte is its kind; 8 is `.input` (StreamMessageKind, which this file
    /// does not import).
    private static func isInput(_ data: Data) -> Bool { data.first == 8 }

    /// The input messages among those waiting. Under the lock.
    private var waitingInputs: Int { waiting.reduce(0) { $0 + (Self.isInput($1) ? 1 : 0) } }

    /// The session's connection: the one read, and the one sent on outside a hand-over or a hold.
    /// Setting it leaves the fences and the hold alone; `dropHandOver` ends them.
    var connection: NWConnection? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; inputs = waitingInputs; lock.unlock() }
    }

    /// One message to the Mac: on the session's connection, or kept, in order, while a fence or a
    /// hold stands.
    func send(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if !fences.isEmpty || holding != nil {
            waiting.append(data)
            if Self.isInput(data) { inputs += 1 }
            return
        }
        if let c = current { handLocked(data, .first, to: c) }
        if current != nil, Self.isInput(data) { inputs += 1 }
    }

    /// A camera frame (kind 46 type 2, DeviceCamera) to the Mac: handed to the session's connection at once,
    /// counted in the camera's lane until it is taken, or refused (false) while a fence or a hold stands or
    /// there is no connection. Never kept in `waiting`: a frame that cannot go now is dropped by its sender,
    /// whose next frame is then a keyframe (CameraPacing.sends), so the camera never waits in front of input.
    func sendCamera(_ data: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard fences.isEmpty, holding == nil, let c = current else { return false }
        handLocked(data, .camera, to: c)
        return true
    }

    /// Hands `data` to `c`, counted in `lane` until `c` has taken it. Under the lock.
    private func handLocked(_ data: Data, _ lane: UplinkLedger.Lane, to c: NWConnection) {
        let bytes = data.count
        let epoch = ledger.handed(bytes, lane, to: ObjectIdentifier(c))
        c.send(content: data, completion: .contentProcessed { [weak self] _ in self?.taken(bytes, lane, epoch: epoch) })
    }

    /// A connection took what it was handed (or failed with it, which ends it): the ledger counts it off and
    /// into the last second's. On the connection's queue.
    private func taken(_ bytes: Int, _ lane: UplinkLedger.Lane, epoch: Int) {
        lock.lock(); defer { lock.unlock() }
        ledger.taken(bytes, lane, epoch: epoch, at: ProcessInfo.processInfo.systemUptime)
    }

    /// Whether `c` is still read: the session's connection, or the old one of a hand-over until its
    /// fence has come back (its pong sits behind whatever the Mac had queued on it).
    func reads(_ c: NWConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return current === c || fences.contains { $0.old === c }
    }

    /// Makes `new` the session's connection, read from now on, and fences what goes to the Mac:
    /// `fencePing`, a ping whose payload is `nonce`, goes on `old` after everything sent there, and
    /// what is sent from now on waits until its pong is back (`fenceReturned`) or the fence is
    /// released, and until every earlier fence still up is down too.
    func handOver(from old: NWConnection, to new: NWConnection, fencePing: Data, nonce: Data) {
        lock.lock(); defer { lock.unlock() }
        current = new
        inputs = waitingInputs
        fences.append(Fence(old: old, nonce: nonce))
        // Under the lock, as every send is: nothing can go out on `old` after this ping.
        old.send(content: fencePing, completion: .contentProcessed { _ in })
    }

    /// A pong read on `old`. When it is the pong of `old`'s fence, the Mac has read everything sent
    /// on `old`, and the fence is down: what waits goes out on the session's connection unless
    /// another fence or the hold still stands. Nil when it ended no fence.
    func fenceReturned(_ payload: Data, on old: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let i = fences.firstIndex(where: { $0.old === old && $0.nonce == payload }) else { return nil }
        return fenceEndedLocked(at: i)
    }

    /// Ends `old`'s fence without its pong: `old` closed (what it had not delivered never will be),
    /// or the pong is taking too long. What waits goes out as in `fenceReturned`. Nil when `old` had
    /// no fence. It never ends a hold: a held connection closing leaves what waits for `adopt`.
    func release(_ old: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let i = fences.firstIndex(where: { $0.old === old }) else { return nil }
        return fenceEndedLocked(at: i)
    }

    private func fenceEndedLocked(at i: Int) -> Released {
        let f = fences.remove(at: i)
        fencedOff.append(f.old)
        return endedLocked(since: f.since)
    }

    /// The session's connection, `c`, has lost its path, or has gone, and a move to another begins:
    /// what goes to the Mac waits here, in order, until `adopt` or `unhold`, also once a fence still
    /// up from an earlier hand-over is down. True when what is sent from now on waits (a hold that
    /// already stands keeps it too); false only when `c` is not the session's connection, which
    /// then carries none of it anyway.
    @discardableResult
    func hold(_ c: NWConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current === c else { return false }
        if holding == nil { holding = Hold(connection: c) }
        return true
    }

    /// Makes `new` the session's connection with no fence of its own: the old one's path is gone,
    /// or the old one is, so a fence ping could never come back. What waits goes out on `new`
    /// first, in order, unless a fence from an earlier hand-over is still up: `adopt` leaves that
    /// fence up (its old connection may still be delivering), and what waits goes out on `new` once
    /// it is down. Nil when nothing was held.
    func adopt(_ new: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        current = new
        inputs = waitingInputs
        guard let h = holding else { return nil }
        holding = nil
        return endedLocked(since: h.since)
    }

    /// Ends the hold on `c` without a move: what waited goes out on it after all, in order (its
    /// path came back, or the move did not complete), once no fence stands. Nil when `c` had no hold.
    func unhold(_ c: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let h = holding, h.connection === c else { return nil }
        holding = nil
        return endedLocked(since: h.since)
    }

    /// A fence or the hold has just ended: when nothing else stands, what waits goes out on the
    /// session's connection, in order, and the old connections whose fences are down go back to the
    /// caller for closing.
    private func endedLocked(since: Double) -> Released {
        let seconds = ProcessInfo.processInfo.systemUptime - since
        guard fences.isEmpty, holding == nil else {
            return Released(held: 0, waiting: waiting.count, clear: false, seconds: seconds, close: [])
        }
        let out = waiting
        waiting = []
        if let c = current { for data in out { handLocked(data, .first, to: c) } }
        let close = fencedOff
        fencedOff = []
        return Released(held: out.count, waiting: 0, clear: true, seconds: seconds, close: close)
    }

    /// The session ended during a hand-over or a hold: what waited goes nowhere. Returns the
    /// connections the fences and the hold were on, and the old ones whose fences are down, for the
    /// caller to close.
    func dropHandOver() -> [NWConnection] {
        lock.lock(); defer { lock.unlock() }
        let connections = fences.map(\.old) + (holding.map { [$0.connection] } ?? []) + fencedOff
        inputs -= waitingInputs
        fences = []
        holding = nil
        waiting = []
        fencedOff = []
        return connections
    }
}

/// The uplink ledger (the overview's §2.3; docs/camera-plan.md §6.2): what the device has handed its
/// session's connection and the connection has not taken yet (`contentProcessed`), by lane, for one
/// connection at a time, and what that connection took in the last second. The person's input, pings, stats
/// and every other message (`first`) go at once, always; the camera's frames (`camera`) only while no fence
/// or hold stands (`SessionLink.sendCamera`), and their pacing reads the ledger (CameraPacing: the bytes not
/// taken, every lane's, within the budget the last second's rate gives). Files' and the microphone's lanes
/// join it when their work lands (the files branch keeps the same ledger with a `files` lane). Pure:
/// SessionLink keeps one under its lock; the fence check holds it.
struct UplinkLedger: Equatable {
    enum Lane: Int, CaseIterable, Hashable {
        case first, camera
    }

    /// The connection counted, and its generation: handing to another starts the counts again, and a
    /// completion of what an earlier one was handed counts nothing.
    private(set) var connection: ObjectIdentifier?
    private(set) var epoch = 0
    private(set) var pending = [Int](repeating: 0, count: Lane.allCases.count)
    /// What the counted connection took, each completion's time and bytes, the last second's only.
    private(set) var recent: [(at: Double, bytes: Int)] = []

    static let window: Double = 1

    /// What the counted connection holds in all.
    var total: Int { pending.reduce(0, +) }

    /// What `c` holds that it was handed and has not taken: nothing for a connection not counted (nothing
    /// was handed to it yet).
    func pending(for c: ObjectIdentifier) -> Int { connection == c ? total : 0 }
    func pending(_ lane: Lane, for c: ObjectIdentifier) -> Int { connection == c ? pending[lane.rawValue] : 0 }

    /// What `c` took in the second before `now`: nothing for a connection not counted.
    func takenLastSecond(for c: ObjectIdentifier, at now: Double) -> Int {
        guard connection == c else { return 0 }
        return recent.reduce(0) { $0 + (now - $1.at < Self.window ? $1.bytes : 0) }
    }

    /// `bytes` handed to `c` in `lane`; returns the epoch its completion names.
    mutating func handed(_ bytes: Int, _ lane: Lane, to c: ObjectIdentifier) -> Int {
        if connection != c {
            connection = c
            epoch += 1
            pending = [Int](repeating: 0, count: Lane.allCases.count)
            recent = []
        }
        pending[lane.rawValue] += bytes
        return epoch
    }

    /// The connection took `bytes` of `lane` it was handed at `epoch`, at `now`.
    mutating func taken(_ bytes: Int, _ lane: Lane, epoch: Int, at now: Double) {
        guard epoch == self.epoch else { return }
        pending[lane.rawValue] = max(0, pending[lane.rawValue] - bytes)
        recent.removeAll { now - $0.at >= Self.window }
        recent.append((now, bytes))
    }

    static func == (a: UplinkLedger, b: UplinkLedger) -> Bool {
        a.connection == b.connection && a.epoch == b.epoch && a.pending == b.pending
            && a.recent.map(\.at) == b.recent.map(\.at) && a.recent.map(\.bytes) == b.recent.map(\.bytes)
    }
}
