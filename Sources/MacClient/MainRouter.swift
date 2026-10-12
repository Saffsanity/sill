import Foundation
import StreamProtocol

/// What draws a stream: a window's layer (HEVCSampleFeed), or a check's stand-in.
protocol FrameSink: AnyObject {
    func apply(_ ps: ParameterSets)
    func enqueue(_ data: Data, isKeyframe: Bool)
}

/// The main stream's frames (kinds 0, 1) to the window of the source the host streams. Decided on the
/// network queue alone, in the stream's order: the host's window list names its source (`listed`)
/// ahead of that stream's first parameter sets, so the first sets after a list naming another source
/// begin that source's stream and go to its window; until then the old stream's frames (still on
/// their way) stay with the old window, whose last picture is its own. A stream's parameter sets
/// precede each of its keyframes, so a window's first picture is its own keyframe.
///
/// Which window is focused here plays no part: the main thread's view of the switch can lag the wire
/// by a list or two, and when it chose the window, one app's picture went into another's (a focus
/// expected while the host's list still named the old source, or a host switch followed late into a
/// window after the next one had begun: 2026-10-12, twice).
///
/// A window's side stream (kinds 30, 31) goes through here too, so the two never mix in one window:
/// a side frame is drawn only into a window whose last parameter sets were its side stream's. The host
/// starts a window's side stream as the main stream leaves it, so its first sets come while the main
/// stream still draws there and are dropped; drawn after the main stream's sets, its frames (another
/// size) came out wrong, a quarter of the window, until the window was focused again (2026-10-12).
/// Such a window keeps its last picture until its side stream's next keyframe.
///
/// Windows register their feed by source (`register`, main thread). A stream whose window is not open
/// yet (the host picked a window this Mac has not shown) goes into it once it registers, from the
/// stream's last keyframe if it has had one since the host's word.
final class MainRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var feeds: [StreamSource: FrameSink] = [:]
    /// The windows whose last parameter sets were their side stream's.
    private var sideOwned: Set<ObjectIdentifier> = []
    private var target: FrameSink?
    /// The source the host last listed, and whether its stream has begun since (its first sets after
    /// the list): until it has, frames are the old stream's.
    private var listedSource: StreamSource?
    private var begun = false
    /// The stream's latest sets and its frames since its last keyframe, to replay into a window that
    /// registers after its stream began; nil once more than `gopLimit` bytes would be kept.
    private var lastPS: ParameterSets?
    private var gop: [(Data, Bool)]? = []
    private var gopBytes = 0
    static let gopLimit = 24 << 20

    /// `feed` draws `source` (nil: the window closed). Main thread.
    func register(_ source: StreamSource, _ feed: FrameSink?) {
        lock.lock(); defer { lock.unlock() }
        if let old = feeds[source] {
            if old === target { target = nil }
            sideOwned.remove(ObjectIdentifier(old))   // a new window's feed can take the closed one's address
        }
        feeds[source] = feed
        // The stream already running for this source: the new window takes it now.
        guard let feed, source == listedSource, begun, target == nil, let ps = lastPS, let frames = gop else { return }
        target = feed
        sideOwned.remove(ObjectIdentifier(feed))
        feed.apply(ps)
        for (data, key) in frames { feed.enqueue(data, isKeyframe: key) }
    }

    /// The session ended: no window, no stream.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        feeds = [:]; sideOwned = []; target = nil; listedSource = nil; begun = false
        lastPS = nil; gop = []; gopBytes = 0
    }

    /// A window list naming `active`, on the network queue in the stream's order.
    func listed(active: StreamSource) {
        lock.lock(); defer { lock.unlock() }
        guard active != listedSource else { return }
        listedSource = active
        begun = false
    }

    /// Whether the main stream draws into `feed` now (the check's view of the routing).
    func draws(into feed: FrameSink) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return feed === target
    }

    func parameterSets(_ ps: ParameterSets) {
        lock.lock()
        // The listed source's window, if open, takes the stream from its sets: its first after the
        // list, or the next once a window opened too late for a replay (`gopLimit`).
        begun = true
        target = listedSource.flatMap { feeds[$0] }
        if let t = target { sideOwned.remove(ObjectIdentifier(t)) }
        lastPS = ps
        let t = target
        lock.unlock()
        t?.apply(ps)
    }

    /// A side stream's parameter sets for `feed`: applied unless the main stream draws there.
    func sideParameterSets(_ ps: ParameterSets, into feed: FrameSink) {
        lock.lock()
        let mine = feed !== target
        if mine { sideOwned.insert(ObjectIdentifier(feed)) }
        lock.unlock()
        if mine { feed.apply(ps) }
    }

    /// A side stream's frame for `feed`: drawn only after its own parameter sets.
    func sideFrame(_ data: Data, isKeyframe: Bool, into feed: FrameSink) {
        lock.lock()
        let mine = feed !== target && sideOwned.contains(ObjectIdentifier(feed))
        lock.unlock()
        if mine { feed.enqueue(data, isKeyframe: isKeyframe) }
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
