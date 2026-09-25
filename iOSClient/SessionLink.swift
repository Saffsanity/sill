import Foundation
import Network

/// The session's connection to the Mac as StreamClient uses it: the connection it reads, and the
/// one door every message to the Mac goes out of (pings aside: each connection sends its own).
/// Thread-safe: the network queue reads and sends, the main thread connects, hands over and
/// disconnects, and every send takes the lock, so messages leave in the order of the calls.
///
/// It also hands a session from one connection to another (the move from peer-to-peer Wi-Fi to
/// the network, StreamClient.finishMove) without reordering what the device sends. The Mac reads
/// each connection in arrival order and never orders one against another, and the old connection
/// is the slow one (over AWDL the round trip was ~75 ms typical and up to 2.4 s on 2026-09-24,
/// against ~10 ms on the network), so a message sent on the new connection could overtake one
/// still in flight on the old: a click's release before its press (the button then stays down and
/// every later move is a drag), keystrokes swapped, an older pick landing after a newer one. So the
/// new connection is read at once, but nothing goes out to the Mac until a fence ping, sent on the
/// old connection after everything else sent there, comes back: the Mac echoes a ping only once it
/// has read all that came before it on that connection. Meanwhile messages wait here, in order, and
/// then go out on the new connection ahead of anything later. The wait is one round trip of the
/// old connection, once per move.
///
/// A session whose connection has lost its path (the cable pulled: StreamClient.followBestPath)
/// moves without a fence, since nothing sent on that connection comes back: from the moment the
/// move starts, what the device sends waits here (`hold`), in order, instead of going into a
/// connection that cannot deliver it, and goes out on the new connection first once it takes the
/// session (`adopt`), or back on the old one should the move not complete (`unhold`).
///
/// Foundation and Network only: it is checked on its own with swiftc against a local stand-in for
/// the Mac whose old connection is slow (docs/direct-wireless-plan.md, the review fixes).
final class SessionLink {
    /// What a fence held when it ended: how many messages, and how long it stood.
    struct Released: Equatable {
        let held: Int
        let seconds: Double
    }

    private struct Fence {
        let old: NWConnection
        /// The fence ping's payload, echoed unchanged in its pong: random, so no other ping's pong
        /// can pass for it. Nil for a hold, which sends no ping.
        let nonce: Data?
        let since = ProcessInfo.processInfo.systemUptime
        var held: [Data] = []
    }

    private let lock = NSLock()
    private var current: NWConnection?
    private var fence: Fence?

    /// The session's connection: the one read, and the one sent on outside a hand-over. Setting it
    /// leaves a hand-over under way alone; `dropHandOver` ends one.
    var connection: NWConnection? {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }

    /// One message to the Mac: on the session's connection, or held, in order, while a hand-over
    /// waits for its fence.
    func send(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if fence != nil {
            fence?.held.append(data)
            return
        }
        current?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Whether `c` is still read: the session's connection, or the old one of a hand-over until its
    /// fence has come back (its pong sits behind whatever the Mac had queued on it).
    func reads(_ c: NWConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return current === c || fence?.old === c
    }

    /// Makes `new` the session's connection, read from now on, and fences what goes to the Mac:
    /// `fencePing`, a ping whose payload is `nonce`, goes on `old` after everything sent there, and
    /// `send` holds until its pong is back (`fenceReturned`) or the hand-over is released.
    func handOver(from old: NWConnection, to new: NWConnection, fencePing: Data, nonce: Data) {
        lock.lock(); defer { lock.unlock() }
        current = new
        fence = Fence(old: old, nonce: nonce)
        // Under the lock, as every send is: nothing can go out on `old` after this ping.
        old.send(content: fencePing, completion: .contentProcessed { _ in })
    }

    /// A pong read on `old`. When it is the fence's, the Mac has read everything sent on `old`, and
    /// the held messages go out on the session's connection. Nil when it ended no fence.
    func fenceReturned(_ payload: Data, on old: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let f = fence, f.old === old, let nonce = f.nonce, payload == nonce else { return nil }
        return releaseLocked()
    }

    /// Ends `old`'s fence without its pong: `old` closed (what it had not delivered never will be),
    /// or the pong is taking too long. The held messages go out on the session's connection now.
    /// Nil when `old` had no fence. A hold is not a fence: its connection closing leaves what it
    /// holds waiting for `adopt`.
    func release(_ old: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let f = fence, f.old === old, f.nonce != nil else { return nil }
        return releaseLocked()
    }

    /// The session's connection, `c`, has lost its path and a move to another begins: what goes to
    /// the Mac waits here, in order, until `adopt` or `unhold`. False when `c` is not the session's
    /// connection or a hand-over is already under way (whose fence then holds it, `adopt` ending
    /// that too).
    @discardableResult
    func hold(_ c: NWConnection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current === c, fence == nil else { return false }
        fence = Fence(old: c, nonce: nil)
        return true
    }

    /// Makes `new` the session's connection with no fence of its own: the old one's path is gone,
    /// or the old one is, so a fence ping could never come back. What a hold kept goes out on `new`
    /// first, in order; nil when there was none. A fence still up from an earlier hand-over stays up
    /// (its old connection may still be delivering), and what it holds goes out on `new` when it ends.
    func adopt(_ new: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        current = new
        guard let f = fence, f.nonce == nil else { return nil }
        return releaseLocked()
    }

    /// Ends the hold on `c` without a move: what waited goes out on it after all, in order (its
    /// path came back, or the move did not complete). Nil when `c` had no hold.
    func unhold(_ c: NWConnection) -> Released? {
        lock.lock(); defer { lock.unlock() }
        guard let f = fence, f.old === c, f.nonce == nil else { return nil }
        return releaseLocked()
    }

    private func releaseLocked() -> Released? {
        guard let f = fence else { return nil }
        fence = nil
        for data in f.held { current?.send(content: data, completion: .contentProcessed { _ in }) }
        return Released(held: f.held.count, seconds: ProcessInfo.processInfo.systemUptime - f.since)
    }

    /// The session ended during a hand-over or a hold: what was held goes nowhere. Returns the old
    /// connection, for the caller to close.
    func dropHandOver() -> NWConnection? {
        lock.lock(); defer { lock.unlock() }
        let old = fence?.old
        fence = nil
        return old
    }
}
