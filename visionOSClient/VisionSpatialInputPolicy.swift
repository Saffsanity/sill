import Foundation
import CoreGraphics
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// Hand hold: stationary lift is secondary click; travel after arming becomes a left drag.
struct VisionSpatialHold {
    enum Action: Equatable { case move(CGPoint), down(CGPoint), up(CGPoint), rightClick(CGPoint) }
    private(set) var origin: CGPoint?
    private(set) var dragging = false
    mutating func begin(_ point: CGPoint) { origin = point; dragging = false }
    mutating func move(_ point: CGPoint) -> [Action] {
        guard let origin else { return [] }
        var actions: [Action] = []
        if !dragging, hypot(point.x - origin.x, point.y - origin.y) > 8 {
            dragging = true
            actions = [.move(origin), .down(origin)]
        }
        if dragging { actions.append(.move(point)) }
        return actions
    }
    mutating func end(_ point: CGPoint, cancelled: Bool = false) -> [Action] {
        guard let origin else { return [] }
        defer { self.origin = nil; dragging = false }
        if dragging { return cancelled ? [.up(point)] : [.move(point), .up(point)] }
        return cancelled ? [] : [.rightClick(origin)]
    }
}

enum VisionSurfaceInputPolicy {
    static func showsCursor(mouseMode: Bool, streamReady: Bool) -> Bool { mouseMode && streamReady }
    /// Pointer feedback follows an accepted event on an attached live surface. visionOS can
    /// deliver hand/pointer events to a window that does not own keyboard focus. Key-window
    /// ownership still gates keyboard capture, but must not discard this event's marker.
    static func showsPointer(source: StreamSource?, allowed: Bool, attached: Bool, foreground: Bool) -> Bool {
        guard let source, source != .none else { return false }
        return allowed && attached && foreground
    }

    static func isRelease(_ event: InputEvent) -> Bool {
        switch event {
        case .key(_, false, _), .pointer(.leftUp, _, _), .pointer(.rightUp, _, _),
             .scrollGesture(.ended, _, _), .scrollGesture(.momentumEnded, _, _): return true
        default: return false
        }
    }
    static func accepts(_ event: InputEvent, allowed: Bool, session: Date?, currentSession: Date?,
                        connected: Bool, source: StreamSource, currentSource: StreamSource) -> Bool {
        guard connected, session == currentSession else { return false }
        return (allowed && source == currentSource) || isRelease(event)
    }
}

/// Necessary local keyboard prerequisites, separate from pointer delivery. A key window
/// belongs to its own scene; these flags do not identify system-wide keyboard ownership.
enum VisionKeyboardFocusPolicy {
    static func canActivate(allowed: Bool, keyWindow: Bool, sceneActive: Bool) -> Bool {
        allowed && keyWindow && sceneActive
    }
}

/// A host AX reply may request typing only after a recent local completed primary tap.
/// One use; resignation, context loss and teardown invalidate it. This is intent evidence,
/// not a claim that our scene's key window identifies the system-wide keyboard owner.
struct VisionKeyboardInteractionPolicy {
    private var tappedAt: Double?
    mutating func tap(now: Double) { tappedAt = now }
    mutating func cancel() { tappedAt = nil }
    mutating func consume(now: Double) -> Bool {
        defer { tappedAt = nil }
        guard let tappedAt else { return false }
        return now >= tappedAt && now - tappedAt <= 1.5
    }
}

/// Relative hand motion shares the portrait trackpad's anchor and clamping rules. Unknown and
/// off-stream positions are intentionally unavailable: Mouse mode never invents a centre click.
struct VisionRelativePointer {
    private var pad = PadCursor()
    private var last: CGPoint?
    mutating func begin(at location: CGPoint, feed: PointerFeedState) -> CGPoint? {
        guard let anchor = Self.anchor(feed) else { last = nil; return nil }
        pad.adopt(anchor: anchor, reseeds: feed.reseeds)
        last = location
        return pad.cursor
    }
    mutating func current(feed: PointerFeedState) -> CGPoint? {
        guard Self.anchor(feed) != nil else { return nil }
        pad.adopt(anchor: Self.anchor(feed), reseeds: feed.reseeds)
        return pad.cursor
    }
    mutating func move(to location: CGPoint, span: CGSize, feed: PointerFeedState) -> CGPoint? {
        guard let previous = last, span.width > 0, span.height > 0,
              Self.anchor(feed) != nil else { return nil }
        pad.catchUp(anchor: Self.anchor(feed), reseeds: feed.reseeds)
        pad.move(dx: Double((location.x - previous.x) / span.width),
                 dy: Double((location.y - previous.y) / span.height))
        last = location
        return pad.cursor
    }
    mutating func cancel() { last = nil }
    private static func anchor(_ feed: PointerFeedState) -> CGPoint? {
        feed.control == .elsewhere && !feed.macInside ? nil : feed.anchor
    }
}
/// One centre per source activation that occurred while Mouse mode was selected.
struct VisionMouseCenterPolicy {
    struct Ticket: Equatable {
        let session: Date
        let source: StreamSource
        let activation: Int
    }
    private var generation = 0
    private var pending: Ticket?
    private var inFlight = false
    mutating func activate(session: Date?, source: StreamSource, mouseMode: Bool) {
        generation += 1
        inFlight = false
        pending = session.flatMap { mouseMode && source != .none ? Ticket(session: $0, source: source, activation: generation) : nil }
    }
    mutating func cancel() { generation += 1; pending = nil; inFlight = false }
    mutating func claim(session: Date?, source: StreamSource, readySource: StreamSource,
                        mouseMode: Bool, pictureReady: Bool) -> Ticket? {
        guard !inFlight, let pending, pending.session == session, pending.source == source,
              readySource == source, mouseMode, pictureReady else { return nil }
        inFlight = true
        return pending
    }
    static func acceptsGeometry(expected: Int, current: Int) -> Bool { expected == current }
    /// `committed` means the remote move was sent, even if its later visual completion is stale.
    mutating func finish(_ ticket: Ticket, committed: Bool) {
        guard pending == ticket else { return }
        inFlight = false
        if committed { pending = nil }
    }
}

/// A bounded, capability-gated confirmation of the latest delivered primary tap. An old focused
/// field, a drag, or a late reply after any newer input must never open the keyboard.
struct VisionEditableFocusPolicy {
    private var down: CGPoint?
    private var pending: (request: EditableFocus, session: Date, mode: UUID, at: Double)?
    private var acceptedToken: String?
    mutating func cancel() { down = nil; pending = nil; acceptedToken = nil }
    mutating func input(_ event: InputEvent, capability: Int?, session: Date?, source: StreamSource,
                        mode: UUID, enabled: Bool, now: Double) -> EditableFocus? {
        pending = nil; acceptedToken = nil
        guard capability == EditableFocus.generation, enabled, let session, source != .none else {
            down = nil; return nil
        }
        switch event {
        case .pointer(.leftDown, let x, let y): down = CGPoint(x: x, y: y)
        case .pointer(.leftUp, let x, let y):
            let matched = down == CGPoint(x: x, y: y)
            down = nil
            guard matched else { return nil }
            let request = EditableFocus(token: UUID().uuidString, source: source, x: x, y: y)
            guard request.isValidRequest else { return nil }
            pending = (request, session, mode, now)
            return request
        default: down = nil
        }
        return nil
    }
    mutating func receive(_ reply: EditableFocus, session: Date?, source: StreamSource,
                          mode: UUID, enabled: Bool, now: Double) -> Bool {
        guard let pending, reply.token == pending.request.token else { return false }
        self.pending = nil
        guard reply.editable == true, enabled, session == pending.session,
              source == pending.request.source, reply.source == source, mode == pending.mode,
              reply.x == pending.request.x, reply.y == pending.request.y,
              now >= pending.at, now - pending.at <= 1.5 else { return false }
        acceptedToken = reply.token
        return true
    }
    func acceptsActivation(_ token: String) -> Bool { acceptedToken == token }
}

#if os(visionOS)
import SwiftUI
struct VisionMouseModeButton: View {
    @ObservedObject var client: StreamClient
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 16
    var iconSize: CGFloat = 22
    var spacing: CGFloat = 4
    var iconBox: CGFloat? = nil
    var body: some View {
        BarButton(open: client.visionMouseMode, width: width, height: height, radius: radius,
                  accessibilityLabel: "Mouse mode", action: { client.visionMouseMode.toggle() }) {
            VStack(spacing: spacing) {
                Image(systemName: "computermouse")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.white)
                    .frame(height: iconBox)
            }
        }
        .accessibilityValue(client.visionMouseMode ? "On" : "Off, Touch mode")
        .accessibilityAddTraits(client.visionMouseMode ? .isSelected : [])
        .accessibilityHint(client.visionMouseMode
                            ? "Switch to Touch mode. Instructions are in Settings."
                            : "Switch to Mouse mode. Instructions are in Settings.")
    }
}
#endif
