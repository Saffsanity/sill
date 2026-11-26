import Foundation
import CoreGraphics

/// The windows Sill moves off the Virtual Desktop when it goes, and back when it returns (docs/virtual-desktop-plan.md §7
/// as revised 2026-11-18, the plan's §6 kept; phase 2b). Noah, 2026-11-12, about #355: "Windows should return to the
/// display, size and position they were in before windowed mode": this file's test.
///
/// - **Out**, just before the Virtual Desktop goes (its grace, its switch, off console, never the main display, Quit): each
///   window on it (`isOn`), out of full screen first (`Access.leaveFullScreen`, at most 2 s; one that will not leave is
///   left to macOS), moved to the main display through Accessibility: the same place relative to the visible area
///   (`place`: the share of the room it has to move in, each way), its size kept, inside the area when it fits. What it
///   was and where it went is kept (`Book`). Synchronous, as the stage's moves, so Quit and the CLI's signals run them.
/// - **Back**, when the Virtual Desktop is made again in the same run of Sill: each window still open and still where Sill
///   put it, within WindowRestore's 2 points, goes back to its place on it, scaled into its new area when that changed (a
///   turned device, another device's size). One the person moved or resized on the Mac meanwhile is theirs and stays (a
///   window macOS moved by itself counts as moved: no fight); a closed one is forgotten; one in full screen now stays.
/// - **Memory only**, as WindowRestore's ledger: nothing after Quit, a crash or `kill -9` (after a crash the display goes
///   with the process and macOS moves its windows itself).
/// - Without Accessibility nothing is moved: the Virtual Desktop still works, and its windows go where macOS puts them.
///
/// Frames are global CG points with a top-left origin, as Accessibility and the window server give them. Pure: the moves
/// go through `Access` (WindowSizer.AXWindows on the Mac, a stand-in Mac in the check); Tests/checks/virtual-desktop.
enum DesktopWindowLedger {
    /// Where a window at `frame` in the visible area `from` goes in the visible area `to`: the same share of the room it
    /// has to move in, each way (flush right stays flush right, the middle the middle), in whole points, its size kept;
    /// inside `to` when it fits, else with its top-left corner at `to`'s (the title bar reachable, as WindowRestore.keep).
    /// The same area gives the frame back as it was.
    static func place(_ frame: CGRect, from: CGRect, to: CGRect) -> CGRect {
        if from == to { return frame }
        func axis(_ p: CGFloat, _ len: CGFloat, _ a0: CGFloat, _ alen: CGFloat, _ b0: CGFloat, _ blen: CGFloat) -> CGFloat {
            let room = alen - len
            let share = room > 0 ? min(max((p - a0) / room, 0), 1) : 0
            return (b0 + share * max(blen - len, 0)).rounded()
        }
        return CGRect(x: axis(frame.minX, frame.width, from.minX, from.width, to.minX, to.width),
                      y: axis(frame.minY, frame.height, from.minY, from.height, to.minY, to.height),
                      width: frame.width, height: frame.height)
    }

    /// Whether `frame` is on `display`: more of it there than on any of `displays` (each display's bounds), the window
    /// server's own sense of which display a window is on; nothing of it there, no.
    static func isOn(_ frame: CGRect, _ display: CGRect, among displays: [CGRect]) -> Bool {
        func share(_ d: CGRect) -> CGFloat {
            let i = d.intersection(frame)
            return i.isNull ? 0 : i.width * i.height
        }
        let mine = share(display)
        return mine > 0 && displays.allSatisfy { share($0) <= mine }
    }

    /// One window Sill moved off the Virtual Desktop.
    struct Entry: Equatable {
        /// Its frame on the Virtual Desktop as it went (out of full screen).
        var was: CGRect
        /// The Virtual Desktop's visible area then.
        var area: CGRect
        /// Where Sill put it on the main display, as the app took it (read back: an app keeps itself on screen, snaps).
        var put: CGRect
    }

    /// What becomes of a window Sill moved off when the Virtual Desktop returns.
    enum Back: Equatable {
        /// Closed meanwhile: forgotten.
        case gone
        /// In full screen now: the person's, left.
        case fullScreen
        /// Not at Sill's size now: resized on the Mac, left.
        case resized
        /// At Sill's size, elsewhere: moved on the Mac (or by macOS), left.
        case moved
        /// Back to this frame on the Virtual Desktop: its own, scaled into the area it has now.
        case put(CGRect)
    }

    /// The window `e` describes, at `current` now (nil: gone), and the Virtual Desktop's visible area now.
    static func back(_ e: Entry, current: CGRect?, fullScreen: Bool, area: CGRect) -> Back {
        guard let current else { return .gone }
        if fullScreen { return .fullScreen }
        if !WindowRestore.same(current.size, e.put.size) { return .resized }
        if !WindowRestore.same(current.origin, e.put.origin) { return .moved }
        return .put(place(e.was, from: e.area, to: area))
    }

    /// The windows Sill moved off, by window ID, each with what moves it (`Handle`: a WindowSizer.Placement on the Mac,
    /// anything in the check). In memory only.
    struct Book<Handle> {
        struct Item {
            var entry: Entry
            let handle: Handle
        }
        private(set) var items: [CGWindowID: Item] = [:]

        var isEmpty: Bool { items.isEmpty }
        var count: Int { items.count }

        /// Window `id` was moved off (a later move of the same window replaces the earlier).
        mutating func movedOut(_ id: CGWindowID, handle: Handle, entry: Entry) {
            items[id] = Item(entry: entry, handle: handle)
        }

        /// Every window it holds, in window ID order, taken out: each is brought back or forgotten.
        mutating func takeAll() -> [(id: CGWindowID, item: Item)] {
            let out = items.keys.sorted().compactMap { id in items[id].map { (id: id, item: $0) } }
            items = [:]
            return out
        }
    }

    /// WindowRestore's reads and writes (Accessibility on the Mac, a stand-in in the check), and one more.
    protocol Access: WindowRestore.Access {
        /// Takes the window out of full screen (Accessibility's AXFullScreen), waiting at most 2 s for it, as the stage's
        /// `leaveFullScreenIfNeeded`: true once it is out.
        mutating func leaveFullScreen(_ w: W) -> Bool
    }

    /// What became of one window as it went.
    enum Went: Equatable {
        /// Moved to the main display, at this frame as the app took it.
        case moved(CGRect)
        /// It stayed in full screen: left to macOS.
        case fullScreen
        /// Accessibility did not move it (the app refused, or did not answer): left to macOS.
        case refused
        /// No frame: closed meanwhile, or its app does not answer.
        case gone
    }

    /// One window on the Virtual Desktop, whose visible area is `area`, out to the main display's `mainArea`: out of full
    /// screen first, its frame read then, moved by `place`, read back, and kept in `book` once it moved.
    static func moveOut<A: Access>(_ id: CGWindowID, _ w: A.W, area: CGRect, mainArea: CGRect, on a: inout A,
                                   into book: inout Book<A.W>) -> Went {
        if a.isFullScreen(w), !a.leaveFullScreen(w) { return .fullScreen }
        guard let frame = a.frame(w) else { return .gone }
        let target = place(frame, from: area, to: mainArea)
        guard a.put(w, at: target) else { return .refused }
        let took = a.frame(w) ?? target
        book.movedOut(id, handle: w, entry: Entry(was: frame, area: area, put: took))
        return .moved(took)
    }

    /// Every window on the Virtual Desktop out (`moveOut`, in the order given): how many moved, of how many, for the
    /// removal's line (VirtualDesktopLife.removedLine).
    static func moveAllOut<A: Access>(_ windows: [(id: CGWindowID, w: A.W)], area: CGRect, mainArea: CGRect, on a: inout A,
                                      into book: inout Book<A.W>) -> (moved: Int, of: Int) {
        var moved = 0
        for (id, w) in windows {
            if case .moved = moveOut(id, w, area: area, mainArea: mainArea, on: &a, into: &book) { moved += 1 }
        }
        return (moved, windows.count)
    }

    /// What `bringBack` did, for its line.
    struct BackCount: Equatable {
        var of = 0
        var back = 0
        var moved = 0
        var resized = 0
        var closed = 0
        var fullScreen = 0
        /// Not moved: its app did not answer, or refused.
        var failed = 0
    }

    /// The Virtual Desktop is back, its visible area `area`: every window `book` holds goes back (`back`) or is left, and
    /// the book is emptied either way. A window the window server still lists whose app gives no frame (a beach ball) is
    /// left where it is.
    static func bringBack<A: Access>(_ book: inout Book<A.W>, area: CGRect, on a: inout A) -> BackCount {
        var n = BackCount()
        for (_, item) in book.takeAll() {
            n.of += 1
            let w = item.handle
            let current = a.frame(w)
            if current == nil, a.isListed(w) { n.failed += 1; continue }
            switch back(item.entry, current: current, fullScreen: current != nil && a.isFullScreen(w), area: area) {
            case .gone: n.closed += 1
            case .fullScreen: n.fullScreen += 1
            case .resized: n.resized += 1
            case .moved: n.moved += 1
            case .put(let frame): if a.put(w, at: frame) { n.back += 1 } else { n.failed += 1 }
            }
        }
        return n
    }

    /// "Virtual Desktop: 2 of 3 windows back in their places (1 was moved on the Mac)."; nil when the book was empty.
    static func backLine(_ n: BackCount) -> String? {
        guard n.of > 0 else { return nil }
        var notes: [String] = []
        let changed = n.moved + n.resized
        if changed > 0 {
            let how = n.resized == 0 ? "moved" : n.moved == 0 ? "resized" : "moved or resized"
            notes.append("\(changed) \(changed == 1 ? "was" : "were") \(how) on the Mac")
        }
        if n.closed > 0 { notes.append("\(n.closed) \(n.closed == 1 ? "was" : "were") closed") }
        if n.fullScreen > 0 { notes.append("\(n.fullScreen) \(n.fullScreen == 1 ? "is" : "are") in full screen") }
        if n.failed > 0 { notes.append("\(n.failed) could not be moved") }
        let head = n.back == n.of
            ? (n.of == 1 ? "1 window back in its place" : "\(n.of) windows back in their places")
            : "\(n.back) of \(n.of) windows back in their places"
        return "Virtual Desktop: \(head)" + (notes.isEmpty ? "." : " (\(notes.joined(separator: ", "))).")
    }
}
