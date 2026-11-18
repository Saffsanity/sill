// HardwareKeyboardPolicy (iOSClient/HardwareKeyboardPolicy.swift) on its own: when the stream's input
// view holds the keyboard for a hardware keyboard, when the person's own keyboard is up, and what each
// event does (docs/hardware-keyboard-plan.md §2). Put through a model of what InputOverlayProxy and
// UIKit do with its answers (`Sim`: the current view's first responder, confirmations, another
// responder taking the keyboard, UIKit giving it back), scenario by scenario with the exact actions,
// then 20,000 random sessions against the plan's invariants:
//   I1 a hardware keyboard's hold only with a keyboard attached, a view in a window and nothing open;
//   I2 what the rule says is held is what UIKit has;
//   I3 the person's own keyboard comes only from the person (the button, a restore) or UIKit giving
//      back the person's own;
//   I4 every moment that should take it takes it (a view joining, a keyboard attaching, the last
//      taker closing, the button);
//   I5 another responder's keyboard is not fought until the next moment;
//   I6 the rule never takes the person's own away (a keyboard coming or going, a taker opening).
// And PointerScroll (#130, PR #217): a trackpad's or a wheel's scroll, every event of it at the pointer, its
// readings added up, as measured in the simulator, then 10,000 random scrolls in that model.
//   swiftc -O iOSClient/HardwareKeyboardPolicy.swift Tests/checks/hardware-keyboard/main.swift -o check && ./check
import CoreGraphics
import Foundation

typealias P = HardwareKeyboardPolicy
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}

// MARK: - The proxy and UIKit, as a model

/// What can happen to the stream screen and its input view.
enum Event: CustomStringConvertible, Equatable {
    case join            // a view joins a window: a session's start, a rotation, a reconnect
    case leave           // the current view leaves its window
    case attach(Bool)    // GameController: a keyboard attached, or the last one went
    case takers(Set<P.Taker>)   // what is open now (the stream screen sends it on every change, and the rule sees repeats too)
    case toggle          // the Keyboard button
    case show(Bool)      // setKeyboard(shown:): a restore of the person's keyboard, or a taker taking it down
    case otherTakes      // another responder (a text field the rule does not know) takes the keyboard
    case givesBack       // UIKit makes the view first responder by itself

    var description: String {
        switch self {
        case .join: return "join"
        case .leave: return "leave"
        case .attach(let a): return a ? "attach" : "detach"
        case .takers(let t): return "takers{\(t.map(\.rawValue).sorted().joined(separator: ","))}"
        case .toggle: return "toggle"
        case .show(let s): return "show(\(s))"
        case .otherTakes: return "otherTakes"
        case .givesBack: return "givesBack"
        }
    }
}

struct Sim {
    var policy: P
    // The truth, as UIKit and the stream screen have it.
    var attached: Bool
    var takers: Set<P.Taker> = []
    var inWindow = false
    /// The current view's first responder and its input views: none, the hardware keyboard's, the person's.
    var responder: P.Hold = .none
    /// Every action, in order, for the scenarios.
    var actions: [P.Action] = []
    var problems: [String] = []
    /// The event under way, and whether it issued a take.
    var event: Event = .join
    var took = false

    init(attached: Bool) {
        self.attached = attached
        policy = P(attached: attached)
    }

    /// The proxy: each action done as UIKit does it, its confirmation told back at once.
    mutating func perform(_ list: [P.Action]) {
        for action in list {
            actions.append(action)
            switch action {
            case .take(let automatic):
                took = true
                guard inWindow else { problems.append("\(event): take with no view in a window"); continue }
                responder = automatic ? .automatic : .own
                perform(policy.became(automatic: automatic))
            case .makeOwn:
                guard responder != .none else { problems.append("\(event): makeOwn with nothing held"); continue }
                responder = .own
            case .makeAutomatic:
                guard responder != .none else { problems.append("\(event): makeAutomatic with nothing held"); continue }
                responder = .automatic
            case .letGo:
                guard responder != .none else { continue }
                responder = .none
                policy.resigned()
            }
        }
    }

    mutating func apply(_ e: Event) {
        event = e
        took = false
        switch e {
        case .join:
            inWindow = true
            responder = .none   // a new view; the old one's resignation is the old view's (the proxy drops it)
            perform(policy.joined())
        case .leave:
            inWindow = false
            responder = .none
            policy.left()
        case .attach(let a):
            attached = a
            perform(policy.keyboard(attached: a))
        case .takers(let t):
            takers = t
            perform(policy.takers(t))
        case .toggle:
            perform(policy.toggled())
        case .show(let s):
            perform(policy.shown(s))
        case .otherTakes:
            guard responder != .none else { return }
            responder = .none
            policy.resigned()
        case .givesBack:
            guard inWindow, responder == .none else { return }
            // The view asks the rule for the kind before it becomes first responder (its input view).
            responder = policy.unpromptedKind
            perform(policy.became(automatic: nil))
        }
    }

    var wanted: Bool { inWindow && attached && takers.isEmpty }
}

/// A scenario: events from a fresh rule, then the actions they made and the state.
func run(_ events: [Event], attached: Bool = true) -> Sim {
    var sim = Sim(attached: attached)
    for e in events { sim.apply(e) }
    return sim
}

let none: Set<P.Taker> = []

// MARK: - Scenarios

// A session's start: with a keyboard the view takes it for the keyboard, not as the person's.
do {
    let s = run([.join])
    check("start with a keyboard: the hardware keyboard's hold", s.actions == [.take(automatic: true)] && s.policy.hold == .automatic && !s.policy.isOwn)
    let n = run([.join], attached: false)
    check("start with no keyboard: nothing", n.actions.isEmpty && n.policy.hold == .none)
    check("wantsAutomatic: on screen, attached, nothing open", s.policy.wantsAutomatic && !n.policy.wantsAutomatic)
}
// A keyboard attaching and going mid-session.
do {
    var s = run([.join], attached: false)
    s.apply(.attach(true))
    check("a keyboard attaching: taken", s.actions == [.take(automatic: true)] && s.policy.hold == .automatic)
    s.actions = []
    s.apply(.attach(false))
    check("the keyboard going: let go", s.actions == [.letGo] && s.policy.hold == .none)
    s.actions = []
    s.apply(.attach(false))
    check("a second detach: nothing", s.actions.isEmpty)
}
// The person's own keyboard stays when the keyboard goes (they asked for it).
do {
    var s = run([.join, .toggle])
    check("the button over the hardware keyboard's hold: the person's", s.actions == [.take(automatic: true), .makeOwn] && s.policy.isOwn)
    s.actions = []
    s.apply(.attach(false))
    check("the keyboard going with the person's up: it stays", s.actions.isEmpty && s.policy.isOwn)
}
// The Settings panel, as StreamScreen does it: taken down, then the taker; closed: the taker goes.
do {
    var s = run([.join])
    s.actions = []
    s.apply(.show(false)); s.apply(.takers([.settings]))
    check("Settings opening: let go", s.actions == [.letGo] && s.policy.hold == .none)
    s.actions = []
    s.apply(.takers(none))
    check("Settings closing: taken again for the keyboard", s.actions == [.take(automatic: true)] && s.policy.hold == .automatic && !s.policy.isOwn)
}
// The Settings panel over the person's own keyboard: put back as theirs, not taken for the keyboard.
do {
    var s = run([.join, .toggle])
    s.actions = []
    s.apply(.show(false)); s.apply(.takers([.settings]))
    check("Settings over the person's: let go", s.actions == [.letGo])
    s.actions = []
    s.apply(.show(true)); s.apply(.takers(none))
    check("Settings closing: the person's back, nothing more", s.actions == [.take(automatic: false)] && s.policy.isOwn)
}
// The drawer and the Menus pull-down never took the person's own keyboard, and still do not; the
// hardware keyboard's hold lets go while they are open and comes back after.
for taker in [P.Taker.drawer, .menus] {
    var s = run([.join])
    s.actions = []
    s.apply(.takers([taker]))
    check("\(taker) opening: the keyboard's hold lets go", s.actions == [.letGo])
    s.actions = []
    s.apply(.takers(none))
    check("\(taker) closing: taken again", s.actions == [.take(automatic: true)])
    var own = run([.join, .toggle])
    own.actions = []
    own.apply(.takers([taker]))
    check("\(taker) opening over the person's: it stays", own.actions.isEmpty && own.policy.isOwn)
    own.apply(.takers(none))
    check("\(taker) closing over the person's: still theirs", own.actions.isEmpty && own.policy.isOwn)
}
// The tour and the pairing overlay: put away first (StreamScreen's putAwayForOverlay), then open.
for taker in [P.Taker.tour, .pairing] {
    var s = run([.join])
    s.actions = []
    s.apply(.show(false)); s.apply(.takers([taker]))
    check("\(taker): let go", s.actions == [.letGo] && s.policy.hold == .none)
    s.actions = []
    s.apply(.takers(none))
    check("\(taker) ending: taken again for the keyboard", s.actions == [.take(automatic: true)] && !s.policy.isOwn)
}
// One taker giving way to another (the Apps button closes Settings and opens the drawer): nothing.
do {
    var s = run([.join, .show(false), .takers([.settings])])
    s.actions = []
    s.apply(.takers([.drawer]))
    check("Settings giving way to the drawer: nothing taken", s.actions.isEmpty && s.policy.hold == .none)
}
// A keyboard attaching while something is open: taken only when it closes.
do {
    var s = run([.join, .takers([.drawer])], attached: false)
    s.actions = []
    s.apply(.attach(true))
    check("a keyboard attaching with the drawer open: nothing yet", s.actions.isEmpty)
    s.apply(.takers(none))
    check("then the drawer closing: taken", s.actions == [.take(automatic: true)])
}
// The Keyboard button in each state.
do {
    var s = run([.join], attached: false)
    s.actions = []
    s.apply(.toggle)
    check("the button with nothing held and no keyboard: the person's (the software keyboard)", s.actions == [.take(automatic: false)] && s.policy.isOwn)
    s.actions = []
    s.apply(.toggle)
    check("again, no keyboard: let go", s.actions == [.letGo] && s.policy.hold == .none)
    var k = run([.join])
    k.actions = []
    k.apply(.toggle)
    check("the button over the keyboard's hold: the person's, in place", k.actions == [.makeOwn] && k.policy.isOwn)
    k.actions = []
    k.apply(.toggle)
    check("again with the keyboard: back to the keyboard's, in place (the software keyboard goes, keys go on)",
          k.actions == [.makeAutomatic] && k.policy.hold == .automatic && !k.policy.isOwn)
    var t = run([.join, .takers([.drawer])])
    t.actions = []
    t.apply(.toggle)
    check("the button with the drawer open: the person's", t.actions == [.take(automatic: false)] && t.policy.isOwn)
    t.actions = []
    t.apply(.toggle)
    check("again with the drawer still open: let go (the keyboard's hold waits for it to close)", t.actions == [.letGo])
}
// setKeyboard(shown: true) over the keyboard's hold (DEBUG -SillKeyboard 1, a restore): the person's.
do {
    var s = run([.join])
    s.actions = []
    s.apply(.show(true))
    check("show over the keyboard's hold: the person's, in place", s.actions == [.makeOwn] && s.policy.isOwn)
    s.actions = []
    s.apply(.show(true))
    check("show over the person's: nothing", s.actions.isEmpty)
    var n = run([.join], attached: false)
    n.actions = []
    n.apply(.show(false))
    check("taken down with nothing held: nothing", n.actions.isEmpty)
}
// Another responder takes the keyboard: not fought, not even by a repeat of what is already so.
do {
    var s = run([.join, .otherTakes])
    s.actions = []
    s.apply(.attach(true)); s.apply(.takers(none)); s.apply(.show(false))
    check("after another responder took it: no take on repeats", s.actions.isEmpty && s.policy.hold == .none)
    s.apply(.takers([.drawer])); s.apply(.takers(none))
    check("then a taker closing: taken back", s.actions == [.take(automatic: true)])
}
// UIKit gives the keyboard back by itself (after a presentation): what the view held.
do {
    var s = run([.join, .takers([.menus])])
    s.actions = []
    s.apply(.givesBack)
    check("given back while the menus are open: counted as the keyboard's, and let go", s.actions == [.letGo] && s.policy.hold == .none)
    s.apply(.takers(none))
    s.actions = []
    s.apply(.otherTakes)
    s.apply(.givesBack)
    check("given back with nothing open: the keyboard's again", s.actions.isEmpty && s.policy.hold == .automatic && !s.policy.isOwn)
    var o = run([.join, .toggle, .otherTakes])
    o.actions = []
    o.apply(.givesBack)
    check("the person's given back: theirs", o.actions.isEmpty && o.policy.isOwn)
    check("unpromptedKind: what the view last held", o.policy.unpromptedKind == .own)
}
// A new view knows nothing of the old one's: given the keyboard by UIKit with no keyboard attached, it
// is the person's, whatever the old view held.
do {
    var s = run([.join, .otherTakes])   // the old view held the keyboard's, then lost it
    s.apply(.attach(false))
    s.apply(.join)                      // a rotation's new view
    s.actions = []
    s.apply(.givesBack)
    check("a new view given the keyboard with none attached: the person's", s.actions.isEmpty && s.policy.isOwn)
}
// A rotation: the new view joins and takes it (the old one's resignation is dropped by the proxy).
do {
    var s = run([.join])
    s.actions = []
    s.apply(.join)
    check("a rotation: the new view takes it", s.actions == [.take(automatic: true)] && s.policy.hold == .automatic)
    var o = run([.join, .toggle])
    o.actions = []
    o.apply(.join)
    check("a rotation over the person's: the new view takes it for the keyboard (the person's goes, as before)",
          o.actions == [.take(automatic: true)] && !o.policy.isOwn)
    var n = run([.join, .toggle], attached: false)
    n.apply(.join)
    check("a rotation over the person's with no keyboard: nothing held (as before)", n.policy.hold == .none)
}
// The view leaving: nothing held, and nothing taken while none is in a window.
do {
    var s = run([.join, .leave])
    check("the view leaving: nothing held", s.policy.hold == .none && !s.policy.onScreen)
    s.actions = []
    s.apply(.attach(false)); s.apply(.attach(true)); s.apply(.takers([.drawer])); s.apply(.takers(none))
    check("no view in a window: nothing taken", s.actions.isEmpty)
    s.apply(.join)
    check("a view again: taken", s.actions == [.take(automatic: true)])
}
// The descriptions the console prints.
check("actions read", P.Action.take(automatic: true).description == "take (hardware keyboard)"
      && P.Action.take(automatic: false).description == "take (the person's)" && P.Action.letGo.description == "let go")

// MARK: - Random sessions

struct Rng {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
        return z ^ (z >> 33)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
}

var rng = Rng(state: 0x6B65_7962_6F61_7264)
var violations: [String: Int] = [:]
var firstViolation: [String: String] = [:]
func violated(_ what: String, _ detail: @autoclosure () -> String) {
    violations[what, default: 0] += 1
    if firstViolation[what] == nil { firstViolation[what] = detail() }
}
var events = 0, automaticHolds = 0, ownHolds = 0, fights = 0
for session in 0..<20_000 {
    var sim = Sim(attached: rng.chance(70))
    var history: [Event] = []
    /// Another responder has the keyboard and no moment has come since.
    var otherHolds = false
    if rng.chance(85) { sim.apply(.join); history.append(.join) }
    for _ in 0..<(10 + rng.below(50)) {
        let e: Event
        switch rng.below(13) {
        case 0: e = .join
        case 1: e = rng.chance(30) ? .leave : .join
        case 2, 3: e = .attach(rng.chance(55))
        case 4, 5:
            var t = sim.takers
            let taker = P.Taker.allCases[rng.below(P.Taker.allCases.count)]
            if t.contains(taker) { t.remove(taker) } else { t.insert(taker) }
            e = .takers(t)
        case 6: e = .takers(rng.chance(50) ? none : sim.takers)   // a close of everything, or a repeat
        case 7, 8: e = .toggle
        case 9: e = .show(rng.chance(50))
        case 10: e = .otherTakes
        case 11: e = .givesBack
        default: e = .takers(sim.takers.isEmpty ? [.drawer] : none)
        }
        let before = sim.responder
        let wasOwn = sim.policy.isOwn
        let lastHeld = sim.policy.lastHeld
        let wantedBefore = sim.wanted
        let attachedBefore = sim.attached
        let takersBefore = sim.takers
        sim.apply(e)
        history.append(e)
        events += 1
        let trail = { history.suffix(12).map(\.description).joined(separator: " ") }
        if sim.responder == .automatic { automaticHolds += 1 }
        if sim.responder == .own { ownHolds += 1 }
        for p in sim.problems { violated("the proxy asked for the impossible", "session \(session): \(p): \(trail())") }
        sim.problems = []
        // I1
        if sim.responder == .automatic, !(sim.attached && sim.inWindow && sim.takers.isEmpty) {
            violated("I1 a keyboard's hold without its conditions", "session \(session): attached \(sim.attached), in a window \(sim.inWindow), open \(sim.takers): \(trail())")
        }
        // I2
        if sim.policy.hold != sim.responder {
            violated("I2 the rule and UIKit disagree", "session \(session): rule \(sim.policy.hold), UIKit \(sim.responder): \(trail())")
        }
        // I3
        if sim.responder == .own, before != .own {
            let fromPerson: Bool
            switch e {
            case .toggle, .show(true): fromPerson = true
            case .givesBack: fromPerson = lastHeld == .own || (lastHeld == .none && !wantedBefore)
            default: fromPerson = false
            }
            if !fromPerson { violated("I3 the person's own made by the rule", "session \(session): \(e) made it the person's: \(trail())") }
        }
        // I4: the moments
        let moment: Bool
        switch e {
        case .join: moment = true
        case .attach(let a): moment = a && !attachedBefore
        case .takers(let t): moment = t.isEmpty && !takersBefore.isEmpty
        case .toggle: moment = before == .own
        default: moment = false
        }
        if moment, sim.wanted, sim.responder == .none {
            violated("I4 a moment that did not take it", "session \(session): \(e) left it untaken: \(trail())")
        }
        // I5
        if case .otherTakes = e, before != .none { otherHolds = true }
        if moment || e == .toggle || e == .show(true) || e == .givesBack || e == .leave { otherHolds = false }
        if otherHolds, sim.took {
            fights += 1
            violated("I5 another responder's keyboard fought", "session \(session): \(e) took it back: \(trail())")
        }
        // I6
        if wasOwn {
            let mayEnd: Bool
            switch e {
            case .toggle, .show(false), .otherTakes, .leave, .join: mayEnd = true
            default: mayEnd = false
            }
            if !mayEnd, !sim.policy.isOwn {
                violated("I6 the person's own taken away by the rule", "session \(session): \(e) ended it: \(trail())")
            }
        }
    }
}
for (what, count) in violations.sorted(by: { $0.key < $1.key }) {
    check("\(what): \(count) times; first: \(firstViolation[what] ?? "")", false)
}
check("20,000 random sessions, \(events) events (\(automaticHolds) after-states with the keyboard's hold, \(ownHolds) with the person's): every invariant",
      violations.isEmpty && automaticHolds > 10_000 && ownHolds > 10_000)

// MARK: - PointerScroll (#130, PR #217): a trackpad's or a wheel's scroll goes where the pointer was

func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.000_1) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}
/// What the scroll path sends for a run of totals (InputOverlayView's `scrolled(to:at:)`, which diffs each
/// against the last one it sent, starting from nothing as a pan begins): one delta per total.
func sent(_ totals: [CGPoint]) -> [CGPoint] {
    var last = CGPoint.zero
    return totals.map { t in defer { last = t }; return CGPoint(x: t.x - last.x, y: t.y - last.y) }
}
/// A scroll through the rule: the pan's first location and reading, then the later readings. The place
/// after each event, and the totals.
func run(_ location: CGPoint, _ first: CGPoint, _ later: [CGPoint], into scroll: inout PointerScroll) -> (places: [CGPoint], totals: [CGPoint]) {
    scroll.began(at: location, reading: first)
    var places = [scroll.at], totals = [scroll.total]
    for r in later { scroll.moved(r); places.append(scroll.at); totals.append(scroll.total) }
    return (places, totals)
}
do {
    // The simulator (iOS 27.0, keyrig): three notches of a wheel over a pointer at 458.79,308.79. UIKit's
    // pan began at y 311.79 with 3 pt in its translation, then changed at 314.79 and 317.79 (6 and 9 pt), and
    // ended 0.2 s later where it was; zeroed after every reading, its readings were 3, 3, 3 and 0.
    var s = PointerScroll()
    let (places, totals) = run(CGPoint(x: 458.79, y: 311.79), CGPoint(x: 0, y: 3), [CGPoint(x: 0, y: 3), CGPoint(x: 0, y: 3), .zero], into: &s)
    check("three notches: every event at the pointer (458.79,308.79), not where the pan ran to",
          places.allSatisfy { near($0, CGPoint(x: 458.79, y: 308.79)) })
    check("three notches: 3, 6, 9 and 9 pt so far", zip(totals, [3.0, 6, 9, 9]).allSatisfy { near($0, CGPoint(x: 0, y: $1)) })
    check("three notches: the scroll path sends 3, 3, 3 pt and nothing at the end",
          zip(sent(totals), [3.0, 3, 3, 0]).allSatisfy { near($0, CGPoint(x: 0, y: $1)) })
}
do {
    // A lone notch: the pan began with the notch already in it and ended with no change (the plan's
    // lone-notch fix): the notch goes out, at the pointer.
    var s = PointerScroll()
    let (places, totals) = run(CGPoint(x: 200, y: 103), CGPoint(x: 0, y: 3), [.zero], into: &s)
    check("a lone notch: 3 pt, at the pointer", near(totals.last!, CGPoint(x: 0, y: 3)) && places.allSatisfy { near($0, CGPoint(x: 200, y: 100)) })
}
do {
    // Phased scroll events through the same pan in the simulator, zeroed after each reading: 7.10, 7.90,
    // 10.00, 5.88, 7.09, 7.03 and 0 (UIKit's own translation 7.10, 15.00, 25.00, 30.88, 37.97, 45.00, 45.00),
    // the pan beginning at y 315.89 over the pointer at 308.79.
    var s = PointerScroll()
    let readings: [CGFloat] = [7.90, 10.00, 5.88, 7.09, 7.03, 0]
    let (places, totals) = run(CGPoint(x: 458.79, y: 315.89), CGPoint(x: 0, y: 7.10), readings.map { CGPoint(x: 0, y: $0) }, into: &s)
    check("a phased scroll: at the pointer throughout", places.allSatisfy { near($0, CGPoint(x: 458.79, y: 308.79)) })
    check("a phased scroll: 45 pt in all, as UIKit's own translation had it", near(totals.last!, CGPoint(x: 0, y: 45), 0.001))
    check("a phased scroll: the scroll path sends each reading as it came",
          zip(sent(totals), [7.10] + readings).allSatisfy { near($0, CGPoint(x: 0, y: $1), 0.001) })
}
do {
    // Both ways at once, and a second scroll: it starts afresh from where the pointer is then.
    var s = PointerScroll()
    let first = run(CGPoint(x: 100, y: 200), CGPoint(x: -4, y: 2), [CGPoint(x: -6, y: 3), CGPoint(x: -1, y: -0.5)], into: &s)
    check("a diagonal scroll: at 104,198 throughout", first.places.allSatisfy { near($0, CGPoint(x: 104, y: 198)) })
    check("a diagonal scroll: -11, 4.5 in all", near(first.totals.last!, CGPoint(x: -11, y: 4.5)))
    let second = run(CGPoint(x: 300, y: 50), CGPoint(x: 0, y: -5), [CGPoint(x: 0, y: -5)], into: &s)
    check("the next scroll: from its own pointer (300,55) with nothing of the last one",
          second.places.allSatisfy { near($0, CGPoint(x: 300, y: 55)) } && near(second.totals.last!, CGPoint(x: 0, y: -10)))
}
do {
    // 10,000 random scrolls in the simulator's model (the pan's location = the pointer + UIKit's own running
    // translation; the readings, zeroed each time, whatever moved since the last): the place is the pointer
    // throughout, the total UIKit's own translation, and what the scroll path sends is each reading.
    var rng = SystemRandomNumberGenerator()
    var s = PointerScroll()
    var bad = 0, events = 0
    for _ in 0..<10_000 {
        let pointer = CGPoint(x: CGFloat.random(in: 0...1400, using: &rng), y: CGFloat.random(in: 0...1000, using: &rng))
        let n = Int.random(in: 1...40, using: &rng)
        let readings = (0..<n).map { _ in CGPoint(x: CGFloat.random(in: -30...30, using: &rng), y: CGFloat.random(in: -60...60, using: &rng)) }
        var uikit = readings[0]
        s.began(at: CGPoint(x: pointer.x + uikit.x, y: pointer.y + uikit.y), reading: readings[0])
        var totals = [s.total]
        if !near(s.at, pointer, 0.001) { bad += 1 }
        for r in readings.dropFirst() {
            uikit = CGPoint(x: uikit.x + r.x, y: uikit.y + r.y)
            s.moved(r)
            events += 1
            totals.append(s.total)
            if !near(s.at, pointer, 0.001) || !near(s.total, uikit, 0.001) { bad += 1 }
        }
        if !zip(sent(totals), readings).allSatisfy({ near($0, $1, 0.001) }) { bad += 1 }
    }
    check("10,000 random scrolls (\(events) later events): at the pointer, UIKit's own total, each reading sent as it came", bad == 0)
}

print(fails == 0 ? "ok: \(passes) checks" : "FAILED: \(fails) of \(passes + fails) checks")
exit(fails == 0 ? 0 : 1)
