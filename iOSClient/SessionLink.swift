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
/// It also keeps the uplink ledger (UplinkLedger; the overview's §2.3, docs/files-plan.md §6.3): every
/// message handed to the session's connection is counted until the connection has taken it
/// (`contentProcessed`), by lane. Everything `send` hands goes at once, as before; a file's messages go
/// only through `sendFile`, and only into what the rest leaves: while no fence or hold stands (files pause
/// then, and nothing of a file ever waits in `waiting`) and the connection holds nothing it was handed, so
/// the person's input, pings and stats never queue behind a file in Sill's own queue. What a file may
/// have on its way beyond that is its acknowledgement window's (FileFlow, DeviceFiles).
///
/// Foundation and Network only: it is checked on its own with swiftc against a local stand-in for
/// the Mac whose old connection is slow (docs/direct-wireless-plan.md, the review fixes), and with
/// DeviceFiles against the Mac's own FileHub (Tests/checks/device-files).
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
    /// What the session's connection was handed and has not taken yet, by lane (UplinkLedger).
    private var ledger = UplinkLedger()
    /// When an input message (kind 8) was last handed to `send` (systemUptime): the person using the
    /// stream, which narrows a file's window (FileFlow.active).
    private var lastInput: Double?
    /// Called once the session's connection has taken everything it was handed after a file's message
    /// found no room (`sendFile` said `.later`), on the connection's queue: the sender may try again. A
    /// fence or a hold ending calls nothing; the sender's own clock tries again then (DeviceFiles).
    var onRoom: (() -> Void)?

    /// What became of a file's message (`sendFile`).
    enum FileSend: Equatable {
        /// Handed to the connection.
        case sent
        /// Not now: a fence or the hold stands, or the connection still holds what it was handed.
        case later
        /// The connection is no longer the session's: the transfer on it is over.
        case gone
    }

    /// When an input message was last handed to `send` (systemUptime), nil before any.
    var lastInputAt: Double? {
        lock.lock(); defer { lock.unlock() }
        return lastInput
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
        if Self.isInput(data) { lastInput = ProcessInfo.processInfo.systemUptime }
        if !fences.isEmpty || holding != nil {
            waiting.append(data)
            if Self.isInput(data) { inputs += 1 }
            return
        }
        if let c = current { handLocked(data, .first, to: c) }
        if current != nil, Self.isInput(data) { inputs += 1 }
    }

    /// A message of a file transfer (kind 34 or 49) to the Mac on `c`, the connection its transfer was
    /// offered on, only into what the rest leaves (UplinkLedger.filesMayGo): handed only while `c` is the
    /// session's connection, no fence or hold stands, and `c` has taken everything it was handed. Never
    /// kept in `waiting`. `.later`: try again once `onRoom` says so, or on the sender's clock.
    func sendFile(_ data: Data, on c: NWConnection) -> FileSend {
        lock.lock(); defer { lock.unlock() }
        guard current === c else { return .gone }
        guard UplinkLedger.filesMayGo(pending: ledger.pending(for: ObjectIdentifier(c)), fenced: !fences.isEmpty,
                                      held: holding != nil) else {
            ledger.wantRoom()
            return .later
        }
        handLocked(data, .files, to: c)
        return .sent
    }

    /// Hands `data` to `c`, counted in `lane` until `c` has taken it. Under the lock.
    private func handLocked(_ data: Data, _ lane: UplinkLedger.Lane, to c: NWConnection) {
        let bytes = data.count
        let epoch = ledger.handed(bytes, lane, to: ObjectIdentifier(c))
        c.send(content: data, completion: .contentProcessed { [weak self] _ in self?.taken(bytes, lane, epoch: epoch) })
    }

    /// A connection took what it was handed (or failed with it, which ends it): the ledger counts it
    /// off, and a file waiting for room is told once nothing is left. On the connection's queue.
    private func taken(_ bytes: Int, _ lane: UplinkLedger.Lane, epoch: Int) {
        lock.lock()
        let room = ledger.taken(bytes, lane, epoch: epoch)
        let call = room ? onRoom : nil
        lock.unlock()
        call?()
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

/// The uplink ledger (the overview's §2.3; docs/files-plan.md §6.3): what the device has handed its
/// session's connection and the connection has not taken yet (`contentProcessed`), by lane, for one
/// connection at a time. The person's input, pings, stats and every other message (`first`) go at once,
/// always; a file's messages (`files`) only into what they leave (`filesMayGo`). The microphone and the
/// camera are to join with lanes of their own. Pure: SessionLink keeps one under its lock; the fence and
/// device-files checks hold it.
struct UplinkLedger: Equatable {
    enum Lane: Int, CaseIterable, Hashable {
        case first, files
    }

    /// The connection counted, and its generation: handing to another starts the counts again, and a
    /// completion of what an earlier one was handed counts nothing.
    private(set) var connection: ObjectIdentifier?
    private(set) var epoch = 0
    private(set) var pending = [Int](repeating: 0, count: Lane.allCases.count)
    /// A file's message found no room: the completion that leaves the connection holding nothing says so.
    private(set) var roomWanted = false

    /// What the counted connection holds in all.
    var total: Int { pending.reduce(0, +) }

    /// What `c` holds that it was handed and has not taken: nothing for a connection not counted (nothing
    /// was handed to it yet).
    func pending(for c: ObjectIdentifier) -> Int { connection == c ? total : 0 }
    func pending(_ lane: Lane, for c: ObjectIdentifier) -> Int { connection == c ? pending[lane.rawValue] : 0 }

    /// `bytes` handed to `c` in `lane`; returns the epoch its completion names.
    mutating func handed(_ bytes: Int, _ lane: Lane, to c: ObjectIdentifier) -> Int {
        if connection != c {
            connection = c
            epoch += 1
            pending = [Int](repeating: 0, count: Lane.allCases.count)
            roomWanted = false
        }
        pending[lane.rawValue] += bytes
        return epoch
    }

    /// The connection took `bytes` of `lane` it was handed at `epoch`. True once a file's message waited
    /// for room and the connection now holds nothing (said once).
    mutating func taken(_ bytes: Int, _ lane: Lane, epoch: Int) -> Bool {
        guard epoch == self.epoch else { return false }
        pending[lane.rawValue] = max(0, pending[lane.rawValue] - bytes)
        guard roomWanted, total == 0 else { return false }
        roomWanted = false
        return true
    }

    mutating func wantRoom() { roomWanted = true }

    /// Whether a file's message may be handed now: no fence or hold stands (files pause then, and never
    /// wait in SessionLink's `waiting`) and the connection holds nothing it was handed, so at most one
    /// file's message is ever ahead of the person's next input in Sill's own queue.
    static func filesMayGo(pending: Int, fenced: Bool, held: Bool) -> Bool {
        !fenced && !held && pending == 0
    }
}
