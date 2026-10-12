import Foundation
import StreamProtocol

/// What draws a stream: a window's layer (HEVCSampleFeed), or a check's stand-in.
protocol FrameSink: AnyObject {
    func apply(_ ps: ParameterSets)
    func enqueue(_ data: Data, isKeyframe: Bool)
}

/// The main stream's frames (kinds 0, 1) to the window they belong to. Focusing a window expects its
/// stream: the old stream's frames keep going to the old window until the new one's parameter sets
/// come, told apart by differing from the old stream's or, for a window of the same size (whose
/// sets can be identical), by coming after the host has said it switched (its window list). A
/// stream's parameter sets precede each of its keyframes, so the new window's first picture is its
/// own keyframe and the old window keeps its last frame of its own.
///
/// A window the host switched to by itself (an app opened, a window it picked) is followed
/// (`follow`): if a new stream began just before (its sets differ from the last stream's, within
/// `followWindow`), the window takes it at once with what it has had since its last keyframe, so it
/// shows now rather than at the next keyframe; else at the next sets. On the network queue, but
/// `expect`, `hostSwitched` and `follow` (main).
final class MainRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var target: FrameSink?
    private var next: FrameSink?
    private var switched = false
    private var lastSets: Data?
    /// The stream's latest sets and its frames since its last keyframe, to replay into a window that
    /// follows it; nil once more than `gopLimit` bytes would be kept (it waits for the next sets then).
    private var lastPS: ParameterSets?
    private var gop: [(Data, Bool)]? = []
    private var gopBytes = 0
    /// When the latest new stream began (sets differing from the last).
    private var newStreamAt: Double?
    static let gopLimit = 24 << 20
    static let followWindow = 1.5
    /// The clock, for the check.
    var now: () -> Double = { ProcessInfo.processInfo.systemUptime }

    func expect(_ feed: FrameSink?) {
        lock.lock(); defer { lock.unlock() }
        next = feed
        switched = false
    }

    /// The session ended: the next session's first window takes its stream's first sets.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        target = nil; next = nil; switched = false; lastSets = nil
        lastPS = nil; gop = []; gopBytes = 0; newStreamAt = nil
    }

    /// The host switched to `feed`'s window by itself: draw it now if its stream has begun, else at
    /// its next sets.
    func follow(_ feed: FrameSink) {
        lock.lock(); defer { lock.unlock() }
        guard feed !== target else { next = nil; return }
        if let began = newStreamAt, now() - began < Self.followWindow, let ps = lastPS, let frames = gop {
            target = feed
            next = nil
            feed.apply(ps)
            for (data, key) in frames { feed.enqueue(data, isKeyframe: key) }
        } else {
            next = feed
            switched = true
        }
    }

    func hostSwitched() { lock.lock(); switched = true; lock.unlock() }

    /// Whether the main stream draws into `feed` now or is about to (expected).
    func draws(into feed: FrameSink) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return feed === target || feed === next
    }

    func parameterSets(_ ps: ParameterSets) {
        let encoded = ps.encoded()
        lock.lock()
        if encoded != lastSets { newStreamAt = now() }
        if let n = next, encoded != lastSets || switched {
            target = n
            next = nil
        }
        lastSets = encoded
        lastPS = ps
        let t = target
        lock.unlock()
        t?.apply(ps)
    }

    func frame(_ data: Data, isKeyframe: Bool) {
        lock.lock()
        if isKeyframe { gop = []; gopBytes = 0 }
        if gop != nil {
            gopBytes += data.count
            if gopBytes > Self.gopLimit { gop = nil } else { gop?.append((data, isKeyframe)) }
        }
        let t = target
        lock.unlock()
        t?.enqueue(data, isKeyframe: isKeyframe)
    }
}
