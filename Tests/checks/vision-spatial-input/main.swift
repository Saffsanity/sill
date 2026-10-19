import Foundation
var checks = 0
func expect(_ value: Bool, _ label: String) { checks += 1; if !value { fatalError(label) } }
let origin = CGPoint(x: 40, y: 50), near = CGPoint(x: 48, y: 50), far = CGPoint(x: 60, y: 50)
var hold = VisionSpatialHold()
expect(hold.move(far).isEmpty, "move before hold")
hold.begin(origin)
expect(hold.move(near).isEmpty, "threshold is not crossed")
expect(hold.end(near) == [.rightClick(origin)], "stationary lift right clicks original point")
expect(hold.end(near).isEmpty, "lift is consumed once")
hold.begin(origin)
expect(hold.end(origin, cancelled: true).isEmpty, "cancelled stationary hold never clicks")
hold.begin(origin)
expect(hold.move(far) == [.move(origin), .down(origin), .move(far)], "drag starts at original point")
expect(hold.move(near) == [.move(near)], "drag down emitted once")
expect(hold.end(far) == [.move(far), .up(far)], "drag lift moves before release")
hold.begin(origin); _ = hold.move(far)
expect(hold.end(near, cancelled: true) == [.up(near)], "cancelled drag releases without click")
expect(hold.end(near, cancelled: true).isEmpty, "cancel releases once")
let session = Date(timeIntervalSince1970: 100), other = Date(timeIntervalSince1970: 101)
let events: [InputEvent] = [.text("x"), .key(hidUsage: 4, down: true, modifiers: 0), .pointer(.leftDown, x: 0.5, y: 0.5), .pointer(.move, x: 0.5, y: 0.5), .scroll(x: 0.5, y: 0.5, dx: 1, dy: 1)]
let releases: [InputEvent] = [.key(hidUsage: 4, down: false, modifiers: 0), .pointer(.leftUp, x: 0.5, y: 0.5), .pointer(.rightUp, x: 0.5, y: 0.5), .scrollGesture(.ended, x: 0.5, y: 0.5), .scrollGesture(.momentumEnded, x: 0.5, y: 0.5)]
for event in events + releases {
    func accepted(_ enabled: Bool, _ current: Date?, _ connected: Bool, _ source: StreamSource) -> Bool {
        VisionSurfaceInputPolicy.accepts(event, allowed: enabled, session: session, currentSession: current, connected: connected, source: .desktop, currentSource: source)
    }
    let release = releases.contains(event)
    expect(accepted(true, session, true, .desktop), "current active source accepts input")
    expect(accepted(false, session, true, .desktop) == release, "local overlay/inactive gate permits only release")
    expect(accepted(true, session, true, .window(1)) == release, "old source permits only cleanup")
    expect(!accepted(true, other, true, .desktop), "old session never reaches replacement")
    expect(!accepted(true, session, false, .desktop), "disconnected never sends")
}
// A visible, active scene is insufficient: remote text requests cannot take the
// shared keyboard until this particular window is key. Pointer policy remains separate.
for allowed in [false, true] {
    for keyWindow in [false, true] {
        for sceneActive in [false, true] {
            expect(VisionKeyboardFocusPolicy.canActivate(allowed: allowed,
                keyWindow: keyWindow, sceneActive: sceneActive) == (allowed && keyWindow && sceneActive),
                "keyboard activation requires local input permission, own key window and active scene")
        }
    }
}
expect(!VisionKeyboardFocusPolicy.canActivate(allowed: true, keyWindow: false, sceneActive: true),
       "non-key scene windows cannot acquire even while active")
expect(VisionSurfaceInputPolicy.showsPointer(source: .desktop, allowed: true, attached: true, foreground: true),
       "keyboard focus exclusion does not remove accepted non-key spatial pointer feedback")

var interaction = VisionKeyboardInteractionPolicy()
expect(!interaction.consume(now: 10), "host focus without a local tap cannot acquire")
interaction.tap(now: 10)
expect(interaction.consume(now: 10.2), "recent local tap authorizes one correlated AX activation")
expect(!interaction.consume(now: 10.3), "local intent consumed once even if a positive host token survives")
interaction.tap(now: 10)
interaction.cancel()
expect(!interaction.consume(now: 10.2), "resignation/source change/teardown revoke local tap intent")
interaction.tap(now: 10)
expect(!interaction.consume(now: 12), "late AX reply cannot revive old local intent")
interaction.tap(now: 10)
expect(!interaction.consume(now: 9), "clock discontinuity is unknown")
interaction.tap(now: 10)
interaction.tap(now: 11)
expect(interaction.consume(now: 12), "latest deliberate interaction replaces old intent")

for source: StreamSource in [.desktop, .window(42), .none] {
    let active = source != .none
    expect(VisionSurfaceInputPolicy.showsPointer(source: source, allowed: true, attached: true, foreground: true) == active, "marker available for Desktop and individual windows on attached surfaces regardless of keyboard focus")
    expect(!VisionSurfaceInputPolicy.showsPointer(source: source, allowed: false, attached: true, foreground: true), "paused overlay cannot show marker")
    expect(!VisionSurfaceInputPolicy.showsPointer(source: source, allowed: true, attached: false, foreground: true), "detached surface cannot show marker")
    expect(!VisionSurfaceInputPolicy.showsPointer(source: source, allowed: true, attached: true, foreground: false), "background cannot show marker")
}
expect(!VisionSurfaceInputPolicy.showsPointer(source: nil, allowed: true, attached: true, foreground: true), "missing context cannot show marker")
var relative = VisionRelativePointer()
var feed = PointerFeedState()
let gaze = CGPoint(x: 900, y: 700), span = CGSize(width: 1000, height: 500)
expect(relative.begin(at: gaze, feed: feed) == nil, "unknown anchor never creates a centre click")
expect(relative.current(feed: feed) == nil, "tap before host position is unavailable")
_ = feed.report(at: CGPoint(x: 0.2, y: 0.3), seen: 0, sentOnSession: 0, movePending: false, now: 0)
expect(relative.begin(at: gaze, feed: feed) == CGPoint(x: 0.2, y: 0.3), "pinch begins at host anchor regardless of gaze")
let moved = relative.move(to: CGPoint(x: 910, y: 710), span: span, feed: feed)!
expect(abs(moved.x - 0.21) < 0.0001 && abs(moved.y - 0.32) < 0.0001, "hand travel is relative in picture coordinates")
_ = feed.sent(.pointer(moved), now: 1)
expect(relative.current(feed: feed) == moved, "tap uses latest accepted pointer")
_ = feed.report(at: CGPoint(x: 0.8, y: 0.7), seen: 1, sentOnSession: 1, movePending: false, now: 2)
let caught = relative.move(to: CGPoint(x: 920, y: 710), span: span, feed: feed)!
expect(abs(caught.x - 0.81) < 0.0001 && caught.y == 0.7, "Mac movement midstroke reseeds relative position")
let edge = relative.move(to: CGPoint(x: 9000, y: -5000), span: span, feed: feed)
expect(edge == CGPoint(x: 1, y: 0), "relative travel clamps at picture edges")
relative.cancel()
expect(relative.move(to: gaze, span: span, feed: feed) == nil, "cancelled stroke cannot resume from stale last point")
_ = feed.report(at: nil, seen: 1, sentOnSession: 1, movePending: false, now: 3)
expect(relative.current(feed: feed) == nil, "offstream report suppresses old retained anchor")
expect(relative.begin(at: gaze, feed: feed) == nil, "offstream pointer cannot silently teleport into stream")
feed.reset()
expect(relative.current(feed: feed) == nil, "source or session reset rejects prior anchor")
// Mouse source activation is consumed once, after a matching stream frame is ready.
var centring = VisionMouseCenterPolicy()
centring.activate(session: session, source: .window(1), mouseMode: true)
expect(centring.claim(session: session, source: .window(1), readySource: .desktop, mouseMode: true, pictureReady: true) == nil, "source switch waits for a frame after the new catalog, even at same size")
expect(centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: false) == nil, "no picture or paused/background readiness retains pending centre")
let centreA = centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true)!
expect(centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true) == nil, "inflight centre cannot be duplicated by another frame")
centring.finish(centreA, committed: true)
expect(centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true) == nil, "routine catalogs, keyframes and geometry callbacks cannot recenter after completion")
centring.activate(session: session, source: .window(2), mouseMode: true)
centring.activate(session: session, source: .window(1), mouseMode: true)
let centreA2 = centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true)!
expect(centreA2 != centreA, "rapid A to B to A is a new source activation")
expect(!VisionMouseCenterPolicy.acceptsGeometry(expected: 1, current: 3), "queued A commit rejected after A to B to A network revisions")
centring.finish(centreA, committed: true)
centring.finish(centreA2, committed: false)
expect(centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true) == centreA2, "stale geometry commit can retry on the next ready frame")
centring.cancel()
expect(centring.claim(session: session, source: .window(1), readySource: .window(1), mouseMode: true, pictureReady: true) == nil, "Touch mode invalidates queued centring")
for source: StreamSource in [.none, .desktop, .window(3)] {
    centring.activate(session: session, source: source, mouseMode: false)
    expect(centring.claim(session: session, source: source, readySource: source, mouseMode: true, pictureReady: true) == nil, "Touch source changes never queue a centre")
}
centring.activate(session: session, source: .none, mouseMode: true)
expect(centring.claim(session: session, source: .none, readySource: .none, mouseMode: true, pictureReady: true) == nil, "source none cannot move remote pointer")
centring.activate(session: nil, source: .desktop, mouseMode: true)
expect(centring.claim(session: nil, source: .desktop, readySource: .desktop, mouseMode: true, pictureReady: true) == nil, "disconnected session cannot queue centre")
centring.activate(session: session, source: .desktop, mouseMode: true)
expect(centring.claim(session: other, source: .desktop, readySource: .desktop, mouseMode: true, pictureReady: true) == nil, "replacement session cannot consume old source ticket")
expect(centring.claim(session: session, source: .desktop, readySource: .desktop, mouseMode: false, pictureReady: true) == nil, "Touch gate blocks pending centre")
let resumed = centring.claim(session: session, source: .desktop, readySource: .desktop, mouseMode: true, pictureReady: true)
expect(resumed != nil, "foreground/unpaused readiness resumes pending source centre")
for mode in [false, true] {
    for ready in [false, true] {
        expect(VisionSurfaceInputPolicy.showsCursor(mouseMode: mode, streamReady: ready) == (mode && ready), "Touch hides local and Mac-reported sprites; Mouse needs a valid picture")
    }
}
// Only a current, host-confirmed editable click can request software keyboard capture.
var editable = VisionEditableFocusPolicy()
let editableMode = UUID(), nextMode = UUID()
func clickRequest(_ capability: Int? = 1, at: Double = 10) -> EditableFocus? {
    _ = editable.input(.pointer(.leftDown, x: 0.3, y: 0.4), capability: capability,
        session: session, source: .desktop, mode: editableMode, enabled: true, now: at)
    return editable.input(.pointer(.leftUp, x: 0.3, y: 0.4), capability: capability,
        session: session, source: .desktop, mode: editableMode, enabled: true, now: at)
}
func focusReply(_ request: EditableFocus, _ value: Bool = true) -> EditableFocus {
    var reply = request; reply.editable = value; return reply
}
expect(clickRequest(nil) == nil, "legacy host never receives editable focus requests")
expect(clickRequest(2) == nil, "unsupported focus generation stays manual")
let firstFocus = clickRequest()!
expect(!editable.receive(focusReply(firstFocus, false), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.1), "noneditable/unknown target never opens keyboard")
let acceptedFocus = clickRequest()!
expect(editable.receive(focusReply(acceptedFocus), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.1), "current positive exact clicked target can open keyboard")
expect(editable.acceptsActivation(acceptedFocus.token), "confirmed activation is usable for the deferred UI request")
expect(!editable.receive(focusReply(acceptedFocus), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.2), "confirmation consumed once")
_ = editable.input(.pointer(.move, x: 0.5, y: 0.5), capability: 1, session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.2)
expect(!editable.acceptsActivation(acceptedFocus.token), "newer pointer input cancels already accepted but deferred UI capture")
let obsolete = clickRequest()!, newer = clickRequest()!
expect(!editable.receive(focusReply(obsolete), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.1), "older click reply cannot override newer Photos/control click")
expect(editable.receive(focusReply(newer), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.1), "ignored old reply does not consume latest pending request")
for change in 0..<6 {
    let request = clickRequest()!
    var reply = focusReply(request)
    if change == 4 { reply.x = 0.8 }
    expect(!editable.receive(reply, session: change == 0 ? other : session,
        source: change == 1 ? .window(3) : .desktop,
        mode: change == 2 ? nextMode : editableMode,
        enabled: change != 3, now: change == 5 ? 12 : 10.1),
        "changed session/source/mode/gate/coordinates or timeout rejects late confirmation")
}
_ = editable.input(.pointer(.leftDown, x: 0.3, y: 0.4), capability: 1, session: session, source: .desktop, mode: editableMode, enabled: true, now: 10)
_ = editable.input(.pointer(.move, x: 0.4, y: 0.4), capability: 1, session: session, source: .desktop, mode: editableMode, enabled: true, now: 10)
expect(editable.input(.pointer(.leftUp, x: 0.4, y: 0.4), capability: 1, session: session, source: .desktop, mode: editableMode, enabled: true, now: 10) == nil, "drag release never becomes an automatic keyboard click")
let cancelled = clickRequest()!
editable.cancel()
expect(!editable.receive(focusReply(cancelled), session: session, source: .desktop, mode: editableMode, enabled: true, now: 10.1), "manual toggle/focus loss/local UI cancellation rejects queued reply")
print("\(checks) checks, 0 failed")
