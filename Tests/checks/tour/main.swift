import Foundation
import CoreGraphics
// H2 of docs/first-run-walkthrough-plan.md: TourPolicy (iOSClient/TourPolicy.swift) on its own. The
// steps and targets per layout, what is owed, the rule of the automatic tour at every boundary,
// memory and the tour's version (0.6: the tour once more, "The tour once more, for 0.6"), runs, a
// rotation mid-run, the crease, the card's width and place (pinned at the Duo's four sizes and the
// iPhone SE's two, against an oracle written from the plan's words, and properties over a grid of
// screens and card heights; a phone held upright with PhonePortraitLayout's own rects), and every
// string, with what it depends on (TourFeatures) and which rows start with "New:". Compiled with the
// files as they are:
//   swiftc -O iOSClient/TourPolicy.swift iOSClient/PhonePortraitLayout.swift iOSClient/DuoPosture.swift Tests/checks/tour/main.swift -o .build/checks/tour/check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

let L = TourLayout.landscape, P = TourLayout.portrait, F = TourLayout.phone
let all: [TourTopic] = [.touch, .bar, .sharing, .settings, .laptop]
/// The sideways steps: every one but the laptop half's.
let sidewaysSteps: [TourTopic] = [.touch, .bar, .sharing, .settings]

// MARK: - Steps and targets

check(TourTopic.allCases == all, "the tour's order")
check(TourTopic.touch < .bar && TourTopic.bar < .sharing && TourTopic.sharing < .settings && TourTopic.settings < .laptop
      && !(TourTopic.laptop < .touch) && !(TourTopic.settings < .sharing), "Comparable follows the order")
check(TourTopic.sharing.rawValue == "sharing", "the new card's saved name")
check(TourPolicy.steps(L, voiceOver: false) == sidewaysSteps, "landscape: four cards")
check(TourPolicy.steps(P, voiceOver: false) == all, "portrait: five cards")
check(TourPolicy.steps(L, voiceOver: true) == [.bar, .sharing, .settings], "landscape under VoiceOver: no touch")
check(TourPolicy.steps(P, voiceOver: true) == [.bar, .sharing, .settings, .laptop], "portrait under VoiceOver: no touch, laptop kept")
check(TourPolicy.only(P) == [.laptop] && TourPolicy.only(L) == [], "only(): the laptop half is portrait's alone")
check(TourPolicy.targets(.touch, L) == [.stream] && TourPolicy.targets(.touch, P) == [.stream], "touch lights the picture")
check(TourPolicy.targets(.bar, L) == [.strip, .menus, .textSize, .keyboard], "landscape bar: the strip, Menus, Aa and Keyboard")
check(TourPolicy.targets(.bar, P) == [.strip, .menus, .textSize], "portrait bar: the strip, Menus and Aa (the keyboard is a cap)")
check(TourPolicy.targets(.settings, L) == [.settings] && TourPolicy.targets(.settings, P) == [.settings], "settings lights its button")
// The clipboard and the sound: their switches are behind the Settings button, which their card lights.
check([L, P, F].allSatisfy { TourPolicy.targets(.sharing, $0) == [.settings] } && TourPolicy.targets(.sharing, F, thumbnails: false) == [.settings],
      "the clipboard's and the sound's card lights the Settings button")
check(TourPolicy.targets(.laptop, P) == [.keys, .trackpad], "laptop: the keys, then the trackpad")
check(TourTarget.allCases.count == 9 && TourTarget.allCases.contains(.apps) && TourTarget.allCases.contains(.menus), "nine targets, Apps and Menus among them")
// A phone held upright (PhonePortraitLayout): the halves' five steps; its Keyboard button is in
// row 1, over the thumbnails, so `bar` lights it, as sideways.
check(TourPolicy.steps(F, voiceOver: false) == all && TourPolicy.steps(F, voiceOver: true) == [.bar, .sharing, .settings, .laptop],
      "a phone upright: five cards, four under VoiceOver")
check(TourPolicy.only(F) == [.laptop] && F.upright && P.upright && !L.upright, "only(): the keys and the trackpad are upright's alone")
check(TourPolicy.targets(.bar, F) == [.strip, .menus, .textSize, .keyboard], "a phone's bar: the strip, row 2's Menus, Aa and row 1's Keyboard")
check(TourPolicy.targets(.touch, F) == [.stream] && TourPolicy.targets(.settings, F) == [.settings] && TourPolicy.targets(.laptop, F) == [.keys, .trackpad],
      "a phone's other targets")
// The Menus button lights where it is drawn, in every bar (and nothing reports it when it is not).
check([L, P, F].allSatisfy { TourPolicy.targets(.bar, $0).contains(.menus) } && TourPolicy.targets(.bar, F, thumbnails: false).contains(.menus),
      "every bar card lights the Menus button")
check(TourTopic.allCases.allSatisfy { t in t == .bar || [L, P, F].allSatisfy { !TourPolicy.targets(t, $0).contains(.menus) } },
      "only the bar card lights Menus")
// A phone with Larger Picture (docs/larger-picture-plan.md): no thumbnails, so the bar card lights
// Apps, Menus, Aa and Keyboard in row 1; every other step, and every other layout, as before.
check(TourPolicy.targets(.bar, F, thumbnails: false) == [.apps, .menus, .textSize, .keyboard], "Larger Picture: the bar card lights Apps, Menus, Aa and Keyboard")
check(TourPolicy.targets(.bar, F, thumbnails: true) == TourPolicy.targets(.bar, F), "the thumbnails shown is the default")
check([TourTopic.touch, .sharing, .settings, .laptop].allSatisfy { TourPolicy.targets($0, F, thumbnails: false) == TourPolicy.targets($0, F) },
      "Larger Picture: the other steps light what they did")
check([L, P].allSatisfy { layout in all.allSatisfy { TourPolicy.targets($0, layout, thumbnails: false) == TourPolicy.targets($0, layout) } },
      "no thumbnails changes nothing sideways or in the halves")

// MARK: - Memory and what is owed

let fresh = TourMemory()
let sideways = TourMemory(seen: Set(TourPolicy.steps(L, voiceOver: false)))
let everything = TourMemory(seen: Set(all))
let skipped = TourMemory(skipped: true)
// What version 1 of the tour (0.5, 0.5.1) left: its four cards, or its three sideways, or Skip.
let v1Done = TourMemory(seen: [.touch, .bar, .settings, .laptop])
let v1Sideways = TourMemory(seen: [.touch, .bar, .settings])
let v1Skipped = TourMemory(seen: [.touch], skipped: true)
check(sideways.seen == [.touch, .bar, .sharing, .settings], "a tour taken sideways: its four steps")
check(TourPolicy.owed(L, voiceOver: false, fresh) == sidewaysSteps, "fresh, landscape")
check(TourPolicy.owed(P, voiceOver: false, fresh) == all, "fresh, portrait")
check(TourPolicy.owed(P, voiceOver: false, sideways) == [.laptop], "a tour taken sideways leaves laptop owed")
check(TourPolicy.owed(L, voiceOver: false, sideways) == [], "nothing new sideways after it")
check(TourPolicy.owed(P, voiceOver: false, everything) == [] && TourPolicy.owed(L, voiceOver: false, everything) == [], "all seen")
check(TourPolicy.owed(P, voiceOver: false, skipped) == [] && TourPolicy.owed(L, voiceOver: true, skipped) == [], "skipped: nothing, ever")
check(TourPolicy.owed(L, voiceOver: false, TourMemory(seen: [.touch])) == [.bar, .sharing, .settings], "a session that ended after touch")
check(TourPolicy.owed(P, voiceOver: true, fresh) == [.bar, .sharing, .settings, .laptop], "VoiceOver: touch not owed here")
check(TourPolicy.owed(L, voiceOver: false, TourMemory(seen: [.bar, .sharing, .settings])) == [.touch], "touch stays owed after a VoiceOver tour")
// Version 1's memory as it is (without the upgrade, as a Debug build without -SillTourState reads it):
// only the new card owed. The upgrade clears it (below), so the whole tour shows once more.
check(TourPolicy.owed(P, voiceOver: false, v1Done) == [.sharing] && TourPolicy.owed(L, voiceOver: false, v1Sideways) == [.sharing],
      "a version-1 memory as it is: the new card alone")
check(TourMemory(names: ["touch", "settings", "gestures", ""], skipped: false) == TourMemory(seen: [.touch, .settings]), "unknown names ignored")
check(TourMemory(names: ["sharing", "laptop"], skipped: false) == TourMemory(seen: [.sharing, .laptop]), "sharing is a name this build knows")
check(TourMemory(seen: [.laptop, .touch, .settings, .sharing]).names == ["touch", "sharing", "settings", "laptop"], "saved in the tour's order")
check(TourMemory(names: [], skipped: true).skipped && TourMemory(names: [], skipped: true).seen.isEmpty, "skipped read back")
check(TourPolicy.passed(.bar, fresh) == TourMemory(seen: [.bar]), "Next saves the step it leaves")
check(TourPolicy.passed(.bar, TourMemory(seen: [.bar])) == TourMemory(seen: [.bar]), "passing again changes nothing")
check(TourPolicy.passed(.sharing, TourMemory(seen: [.touch, .bar])) == TourMemory(seen: [.touch, .bar, .sharing]), "Next saves the new card")
check(TourPolicy.passed(.laptop, sideways) == everything, "the upright card completes it")
check(TourPolicy.skipped(sideways) == TourMemory(seen: Set(sidewaysSteps), skipped: true), "Skip keeps what was seen")
check(!TourPolicy.skipped(fresh).seen.contains(.touch) && TourPolicy.skipped(fresh).skipped, "Skip saves no step")
// Skip in the automatic tour turns it off; in Take the Tour it only closes the run.
let automaticRun = TourRun(steps: sidewaysSteps, at: .touch, replay: false)
let replayRun = TourRun(steps: sidewaysSteps, at: .touch, replay: true)
check(TourPolicy.skip(automaticRun, fresh) == TourMemory(skipped: true), "Skip in the automatic tour: off for good")
check(TourPolicy.skip(automaticRun, sideways) == TourMemory(seen: Set(sidewaysSteps), skipped: true), "…keeping what was seen")
check(TourPolicy.skip(replayRun, sideways) == sideways, "Skip in Take the Tour: nothing saved, the tour not turned off")
check(TourPolicy.owed(P, voiceOver: false, TourPolicy.skip(replayRun, sideways)) == [.laptop],
      "after Take the Tour's Skip the upright card is still owed")
check(TourPolicy.skip(TourRun(steps: all, at: .bar, passed: [.touch], replay: true), fresh) == fresh, "a replay upright, the same")

// MARK: - The rule

func moment(now: Double, picture: Double? = 10, layoutAt: Double = 5, decided: Bool = false, activity: Double? = nil,
            down: Int = 0, busy: Bool = false, offered: Bool = false, voiceOver: Bool = false, enabled: Bool = true) -> TourMoment {
    TourMoment(now: now, pictureAt: picture, layoutAt: layoutAt, decided: decided, lastActivityAt: activity,
               touchesDown: down, busy: busy, offered: offered, voiceOver: voiceOver, enabled: enabled)
}
func decide(_ m: TourMoment, _ layout: TourLayout = L, _ memory: TourMemory = fresh) -> TourDecision {
    TourPolicy.automatic(m, layout, memory)
}
check(TourPolicy.beat == 1.0, "the beat is a second")
check(decide(moment(now: 20, enabled: false)) == .pass(.nothingOwed), "Debug without -SillTourState: never")
check(decide(moment(now: 20, offered: true)) == .pass(.nothingOwed), "one decision per session and layout")
check(decide(moment(now: 20, picture: nil)) == .wait(until: nil), "no picture yet: wait for it")
check(decide(moment(now: 10)) == .wait(until: 11), "at the picture: wait a beat")
check(decide(moment(now: 10.99)) == .wait(until: 11), "0.99 s into the beat: still waiting")
check(decide(moment(now: 11.0)) == .show(sidewaysSteps), "1.0 s: the tour")
check(decide(moment(now: 11.0), P) == .show(all), "portrait: all five")
check(decide(moment(now: 30)) == .show(sidewaysSteps), "a late look at a quiet session still shows it")
check(decide(moment(now: 11, activity: 9.99)) == .show(sidewaysSteps), "a touch before the picture does not count")
check(decide(moment(now: 11, activity: 10)) == .pass(.used), "a touch at the picture counts")
check(decide(moment(now: 10.5, activity: 10.4)) == .pass(.used), "used during the beat: not this session, at once")
check(decide(moment(now: 11, down: 1)) == .pass(.busy), "a touch still down")
check(decide(moment(now: 10.5, down: 1)) == .wait(until: 11), "a touch down is judged at the decision, not before")
check(decide(moment(now: 11, busy: true)) == .pass(.busy), "something open")
check(decide(moment(now: 11), L, sideways) == .pass(.nothingOwed), "seen: nothing owed")
check(decide(moment(now: 11), L, skipped) == .pass(.nothingOwed), "skipped: nothing owed")
check(decide(moment(now: 11), L, skipped) == decide(moment(now: 11, enabled: false), L, fresh), "skipped as good as off")
check(decide(moment(now: 11), P, sideways) == .show([.laptop]), "a later session upright: the laptop card")
check(decide(moment(now: 11, voiceOver: true)) == .show([.bar, .sharing, .settings]), "VoiceOver: without touch")
check(decide(moment(now: 11, voiceOver: true), L, TourMemory(seen: [.bar, .sharing, .settings])) == .pass(.nothingOwed), "VoiceOver: touch never owed there")
// A rotation during the beat starts it again, with every step owed in the new layout.
check(decide(moment(now: 11, layoutAt: 10.6), P) == .wait(until: 11.6), "turned in the beat: a beat from the turn")
check(decide(moment(now: 11.6, layoutAt: 10.6), P) == .show(all), "then all five")
check(decide(moment(now: 11.6, layoutAt: 10.6, activity: 10.3), P) == .show(all), "a touch before the turn does not count")
check(decide(moment(now: 11.6, layoutAt: 10.6, activity: 10.6), P) == .pass(.used), "a touch at the turn does")
// After the picture's decision a turn offers only what its layout has alone, from the turn.
check(decide(moment(now: 40, layoutAt: 39, decided: true), P) == .show([.laptop]), "a turn upright: laptop alone")
check(decide(moment(now: 39.5, layoutAt: 39, decided: true), P) == .wait(until: 40), "a beat from the turn")
check(decide(moment(now: 40, layoutAt: 39, decided: true, activity: 38.9), P) == .show([.laptop]), "work before the turn does not count")
check(decide(moment(now: 40, layoutAt: 39, decided: true, activity: 39.2), P) == .pass(.used), "a touch after the turn does")
check(decide(moment(now: 40, layoutAt: 39, decided: true), L) == .pass(.nothingOwed), "a turn sideways offers nothing new")
check(decide(moment(now: 40, layoutAt: 39, decided: true), P, sideways) == .show([.laptop]), "the upright card after a tour sideways")
check(decide(moment(now: 40, layoutAt: 39, decided: true), P, everything) == .pass(.nothingOwed), "laptop seen: nothing")
check(decide(moment(now: 40, layoutAt: 39, decided: true, down: 2), P) == .pass(.busy), "a turn with fingers down")
check(decide(moment(now: 40, layoutAt: 39, decided: true, busy: true), P) == .pass(.busy), "a turn with the keyboard up")
check(decide(moment(now: 40, layoutAt: 39, decided: true, offered: true), P) == .pass(.nothingOwed), "each layout once")
check(decide(moment(now: 40, layoutAt: 39, decided: true, voiceOver: true), P) == .show([.laptop]), "the keys card under VoiceOver")
// A session that went on with an earlier one's decision (the automatic reconnect's): nothing at its
// picture in a layout that one decided in; in another, only what that layout has alone, a beat
// after this session's picture, not after its screen came (layoutAt 5, the picture at 10).
check(decide(moment(now: 11, decided: true, offered: true), L) == .pass(.nothingOwed), "a reconnect sideways after a decision there: nothing")
check(decide(moment(now: 10.5, decided: true), P) == .wait(until: 11), "a reconnect upright: a beat from its picture")
check(decide(moment(now: 11, decided: true), P) == .show([.laptop]), "then the laptop card alone")
check(decide(moment(now: 11, decided: true, activity: 7), P) == .show([.laptop]), "a touch before its picture does not count")
check(decide(moment(now: 11, decided: true, activity: 10.2), P) == .pass(.used), "a touch after it does")
check(decide(moment(now: 11, decided: true), L) == .pass(.nothingOwed), "a reconnect sideways: nothing new")
// A phone held upright follows the same rule as the halves.
check(decide(moment(now: 11), F) == .show(all), "a phone upright: all five")
check(decide(moment(now: 40, layoutAt: 39, decided: true), F) == .show([.laptop]), "a turn upright on a phone: laptop alone")
check(decide(moment(now: 40, layoutAt: 39, decided: true), F, sideways) == .show([.laptop]), "the upright card on a phone after a tour sideways")
check(decide(moment(now: 11), F, everything) == .pass(.nothingOwed), "a phone: all seen")
check(decide(moment(now: 11), F, v1Done) == .show([.sharing]), "version 1's four seen, read as they are: the new card alone")

// MARK: - The tour's version (0.6: once more for everyone who launches it)

/// TourStore's reading of what is saved, as a pair to compare.
func upgrade(_ m: TourMemory, _ v: Int?) -> (memory: TourMemory, write: Bool) { TourPolicy.upgraded(m, savedVersion: v) }
/// Cleared, and this version to be written with it.
func cleared(_ r: (memory: TourMemory, write: Bool)) -> Bool { r.memory == TourMemory() && r.write }
/// Kept as it was, nothing written.
func kept(_ r: (memory: TourMemory, write: Bool), _ m: TourMemory) -> Bool { r.memory == m && !r.write }
check(TourPolicy.version == 2, "the tour's version is 2")
check(cleared(upgrade(fresh, nil)), "a fresh install: nothing saved, cleared (as it was) and the version written")
check(cleared(upgrade(v1Done, nil)), "0.5.x's Done (all four, no version stored): cleared, the version written")
check(cleared(upgrade(v1Sideways, nil)), "0.5.x's tour taken sideways: cleared")
check(cleared(upgrade(v1Skipped, nil)) && cleared(upgrade(skipped, nil)), "0.5.x's Skip: cleared, so the tour shows once more")
check(cleared(upgrade(everything, nil)), "every step of this version's seen, but no version stored: cleared")
for v in [1, 0, -3, Int.min] {
    check(cleared(upgrade(v1Done, v)) && cleared(upgrade(skipped, v)) && cleared(upgrade(everything, v)), "an explicit version \(v): cleared, written")
}
check(kept(upgrade(everything, 2), everything), "this version's Done: kept, nothing written")
check(kept(upgrade(skipped, 2), skipped) && kept(upgrade(TourMemory(seen: [.touch, .sharing], skipped: true), 2), TourMemory(seen: [.touch, .sharing], skipped: true)),
      "this version's Skip: kept")
check(kept(upgrade(fresh, 2), fresh) && kept(upgrade(sideways, 2), sideways) && kept(upgrade(v1Sideways, 2), v1Sideways), "this version's, part seen: kept")
for v in [3, 4, Int.max] {
    check(kept(upgrade(everything, v), everything) && kept(upgrade(skipped, v), skipped) && kept(upgrade(v1Sideways, v), v1Sideways)
          && kept(upgrade(fresh, v), fresh), "a later version \(v) (a downgrade back to this build): kept, the version never lowered")
}
// Idempotent: SwiftUI makes a TourStore at every StreamScreen init, and each reads what the first wrote.
for (m, v) in [(v1Done, nil), (skipped, 1), (fresh, nil), (everything, 0), (v1Skipped, nil)] as [(TourMemory, Int?)] {
    let first = upgrade(m, v)
    check(first.write && kept(upgrade(first.memory, TourPolicy.version), TourMemory()), "upgraded once, then read back at version 2: as it was, nothing written")
}
// After the upgrade the whole tour shows, in every layout, under VoiceOver too; a version-2 Done or
// Skip leaves nothing owed.
for m in [v1Done, v1Sideways, v1Skipped, skipped, fresh] {
    let now = upgrade(m, nil).memory
    check(decide(moment(now: 11), L, now) == .show(TourPolicy.steps(L, voiceOver: false)) && decide(moment(now: 11), P, now) == .show(all)
          && decide(moment(now: 11), F, now) == .show(all), "after the upgrade of \(m): the whole tour, sideways and upright")
    check(decide(moment(now: 11, voiceOver: true), P, now) == .show([.bar, .sharing, .settings, .laptop])
          && decide(moment(now: 11, voiceOver: true), L, now) == .show([.bar, .sharing, .settings]), "…and under VoiceOver")
}
check(decide(moment(now: 11), P, upgrade(everything, 2).memory) == .pass(.nothingOwed) && decide(moment(now: 11), L, upgrade(everything, 2).memory) == .pass(.nothingOwed),
      "a version-2 Done: nothing owed")
check(decide(moment(now: 11), L, upgrade(skipped, 2).memory) == .pass(.nothingOwed) && decide(moment(now: 11), F, upgrade(skipped, 2).memory) == .pass(.nothingOwed),
      "a version-2 Skip: nothing owed")
// Done on version 2's tour sideways: the upright card is all that is owed after it.
check(decide(moment(now: 40, layoutAt: 39, decided: true), P, upgrade(sideways, 2).memory) == .show([.laptop]), "version 2 sideways, then a turn: the laptop card")

// MARK: - Sessions

let decidedHere = TourSession(decided: true, offered: [L], running: false)
check(TourPolicy.nextSession(after: decidedHere, reconnected: true) == decidedHere, "the reconnect goes on with the last decision")
check(TourPolicy.nextSession(after: TourSession(decided: true, offered: [L, P], running: false), reconnected: true)
      == TourSession(decided: true, offered: [L, P], running: false), "…in every layout it had")
check(TourPolicy.nextSession(after: decidedHere, reconnected: false) == TourSession(), "a session the person starts decides afresh")
check(TourPolicy.nextSession(after: TourSession(decided: true, offered: [L], running: true), reconnected: true) == TourSession(),
      "a run cut short comes back at the reconnect's picture")
check(TourPolicy.nextSession(after: TourSession(decided: false, offered: [], running: false), reconnected: true) == TourSession(),
      "a session lost before its decision: the next one decides")
check(TourPolicy.nextSession(after: TourSession(), reconnected: false) == TourSession() && TourSession() == TourSession(decided: false, offered: [], running: false),
      "a first session")
// Two reconnects in a row, the middle one lost before its picture: the first decision still holds.
let middle = TourPolicy.nextSession(after: decidedHere, reconnected: true)
check(TourPolicy.nextSession(after: middle, reconnected: true) == decidedHere, "a decision survives a reconnect that never showed a picture")

// MARK: - Runs

let replayL = TourPolicy.replay(L, voiceOver: false)!
check(replayL == TourRun(steps: sidewaysSteps, at: .touch, replay: true), "Take the Tour sideways")
check(TourPolicy.replay(P, voiceOver: false, from: .settings) == TourRun(steps: all, at: .settings, replay: true), "-SillTour settings upright")
check(TourPolicy.replay(P, voiceOver: false, from: .sharing) == TourRun(steps: all, at: .sharing, replay: true)
      && TourPolicy.replay(L, voiceOver: true, from: .sharing) == TourRun(steps: [.bar, .sharing, .settings], at: .sharing, replay: true),
      "-SillTour sharing, upright and under VoiceOver sideways")
check(TourPolicy.replay(L, voiceOver: false, from: .laptop)?.at == .touch, "a step the layout lacks starts at the first")
check(TourPolicy.replay(L, voiceOver: true, from: .touch)?.at == .bar, "under VoiceOver touch is not there")
check(TourPolicy.replay(P, voiceOver: true)?.steps == [.bar, .sharing, .settings, .laptop], "Take the Tour under VoiceOver")
check(TourPolicy.run(owed: []) == nil, "nothing owed: no run")
check(TourPolicy.run(owed: [.settings]) == TourRun(steps: [.settings], at: .settings, replay: false), "one card owed")
let r2 = TourPolicy.next(replayL)!
check(r2.at == .bar && r2.passed == [.touch] && r2.index == 1 && r2.count == 4, "Next: the second card")
let r3 = TourPolicy.next(r2)!
check(r3.at == .sharing && !r3.isLast && r3.passed == [.touch, .bar] && r3.index == 2, "the third card: the clipboard and the sound")
let r4 = TourPolicy.next(r3)!
check(r4.at == .settings && r4.isLast && r4.passed == [.touch, .bar, .sharing], "the last card")
check(TourPolicy.next(r4) == nil, "Done ends it")
check(!replayL.isLast && replayL.firstOfRun && !r2.firstOfRun, "first and last")
// A session that ends mid-tour: steps passed stay passed; the next session starts at the first owed.
var memory = fresh
var walk = TourPolicy.run(owed: TourPolicy.owed(L, voiceOver: false, memory))!
memory = TourPolicy.passed(walk.at, memory); walk = TourPolicy.next(walk)!
memory = TourPolicy.passed(walk.at, memory); walk = TourPolicy.next(walk)!
check(walk.at == .sharing && memory.seen == [.touch, .bar], "two passed, the Mac quits at the third")
check(TourPolicy.run(owed: TourPolicy.owed(L, voiceOver: false, memory)) == TourRun(steps: [.sharing, .settings], at: .sharing, replay: false),
      "the next session: the clipboard and the sound, then settings")
check(TourPolicy.run(owed: TourPolicy.owed(P, voiceOver: false, memory))?.steps == [.sharing, .settings, .laptop], "or upright: then laptop")
memory = TourPolicy.passed(walk.at, memory); walk = TourPolicy.next(walk)!
check(walk.at == .settings && memory.seen == [.touch, .bar, .sharing], "three passed, the Mac quits at the fourth")
check(TourPolicy.run(owed: TourPolicy.owed(L, voiceOver: false, memory)) == TourRun(steps: [.settings], at: .settings, replay: false), "the next session: settings alone")

// A rotation mid-run: every step both ways, with and without VoiceOver, replay and automatic.
func run(_ steps: [TourTopic], at: TourTopic, passed: Set<TourTopic> = [], replay: Bool = false) -> TourRun {
    TourRun(steps: steps, at: at, passed: passed, replay: replay)
}
let autoL = run(sidewaysSteps, at: .touch)
check(TourPolicy.carry(autoL, to: P, voiceOver: false, memory: fresh) == run(all, at: .touch), "touch, landscape → portrait: 1 of 5")
check(TourPolicy.carry(run(sidewaysSteps, at: .bar, passed: [.touch]), to: P, voiceOver: false, memory: TourMemory(seen: [.touch]))
      == run(all, at: .bar, passed: [.touch]), "bar → portrait: 2 of 5, the count goes on")
check(TourPolicy.carry(run(sidewaysSteps, at: .sharing, passed: [.touch, .bar]), to: P, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run(all, at: .sharing, passed: [.touch, .bar]), "sharing → portrait: 3 of 5")
check(TourPolicy.carry(run(sidewaysSteps, at: .settings, passed: [.touch, .bar, .sharing]), to: P, voiceOver: false, memory: TourMemory(seen: [.touch, .bar, .sharing]))
      == run(all, at: .settings, passed: [.touch, .bar, .sharing]), "settings → portrait: 4 of 5, laptop after it")
check(TourPolicy.carry(run(all, at: .touch), to: L, voiceOver: false, memory: fresh) == run(sidewaysSteps, at: .touch), "touch, portrait → landscape")
check(TourPolicy.carry(run(all, at: .bar, passed: [.touch]), to: L, voiceOver: false, memory: TourMemory(seen: [.touch]))
      == run(sidewaysSteps, at: .bar, passed: [.touch]), "bar, portrait → landscape")
check(TourPolicy.carry(run(all, at: .sharing, passed: [.touch, .bar]), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run(sidewaysSteps, at: .sharing, passed: [.touch, .bar]), "sharing, portrait → landscape")
check(TourPolicy.carry(run(all, at: .settings, passed: [.touch, .bar, .sharing]), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar, .sharing]))
      == run(sidewaysSteps, at: .settings, passed: [.touch, .bar, .sharing]), "settings, portrait → landscape: now the last")
check(TourPolicy.carry(run(all, at: .laptop, passed: [.touch, .bar, .sharing, .settings]), to: L, voiceOver: false, memory: sideways) == nil,
      "laptop turned sideways: nothing left, the tour ends")
check(TourPolicy.carry(run([.laptop], at: .laptop), to: L, voiceOver: false, memory: fresh) == nil,
      "the turn's laptop card turned back: ends, nothing owed there counts after it")
check(TourPolicy.carry(run(all, at: .laptop, replay: true), to: L, voiceOver: false, memory: fresh) == nil,
      "-SillTour laptop turned sideways: nothing after laptop, it ends (not back to touch)")
check(TourPolicy.carry(run([.settings, .laptop], at: .settings), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar, .sharing]))
      == run([.settings], at: .settings), "an owed run sideways keeps only what is owed there")
check(TourPolicy.carry(run([.sharing, .settings, .laptop], at: .sharing), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run([.sharing, .settings], at: .sharing), "an owed run at the new card, turned sideways: it stays, settings after it")
check(TourPolicy.carry(run(sidewaysSteps, at: .bar, passed: [.touch], replay: true), to: P, voiceOver: false, memory: everything)
      == run(all, at: .bar, passed: [.touch], replay: true), "Take the Tour: every step of the new layout, whatever was seen")
check(TourPolicy.carry(run(sidewaysSteps, at: .touch), to: L, voiceOver: true, memory: fresh) == run([.bar, .sharing, .settings], at: .bar),
      "VoiceOver on during touch: on to the next step, bar")
check(TourPolicy.carry(run([.bar, .sharing, .settings, .laptop], at: .laptop, passed: [.bar, .sharing, .settings]), to: L, voiceOver: true,
                       memory: TourMemory(seen: [.bar, .sharing, .settings])) == nil,
      "VoiceOver, laptop turned sideways: ends")
check(TourPolicy.carry(run([.bar, .sharing, .settings], at: .bar, replay: true), to: P, voiceOver: true, memory: fresh) == run([.bar, .sharing, .settings, .laptop], at: .bar, replay: true),
      "VoiceOver replay turned upright")
var sharingCarried: Set<String> = []
for (layout, other) in [(L, P), (P, L), (L, F), (F, L)] {
    for voiceOver in [false, true] {
        for step in TourPolicy.steps(layout, voiceOver: voiceOver) {
            if step == .sharing, TourPolicy.carry(TourPolicy.replay(layout, voiceOver: voiceOver, from: step)!, to: other, voiceOver: voiceOver, memory: fresh)?.at == .sharing {
                sharingCarried.insert("\(layout.rawValue)→\(other.rawValue)")
            }
            let before = TourPolicy.replay(layout, voiceOver: voiceOver, from: step)!
            let after = TourPolicy.carry(before, to: other, voiceOver: voiceOver, memory: fresh)
            if TourPolicy.steps(other, voiceOver: voiceOver).contains(step) {
                check(after?.at == step && after?.steps == TourPolicy.steps(other, voiceOver: voiceOver), "\(step) keeps its card turning \(layout.rawValue) → \(other.rawValue)")
            } else {
                check(after == nil, "\(step) turning \(layout.rawValue) → \(other.rawValue) ends")
            }
            let same = TourPolicy.carry(before, to: layout, voiceOver: voiceOver, memory: fresh)
            check(same == before, "a resize that keeps the layout changes nothing (\(step))")
        }
    }
}
check(sharingCarried == ["landscape→portrait", "portrait→landscape", "landscape→phone", "phone→landscape"], "the new card keeps its place turning either way: \(sharingCarried)")

// MARK: - The crease, the width, the cutout

func topHalf(_ size: CGSize) -> Bool {       // ConnectLayout.topHalf (AddMacCard.swift), copied
    size.height > size.width && size.width >= 600 && size.width < 740 && size.height < 1100
}
let creaseSizes: [CGSize] = [CGSize(width: 710, height: 1000), CGSize(width: 1000, height: 710), CGSize(width: 500, height: 710),
                             CGSize(width: 710, height: 500), CGSize(width: 744, height: 1133), CGSize(width: 600, height: 1000),
                             CGSize(width: 599, height: 1000), CGSize(width: 739, height: 1099), CGSize(width: 740, height: 1000),
                             CGSize(width: 710, height: 1100), CGSize(width: 700, height: 700), CGSize(width: 650, height: 900),
                             CGSize(width: 375, height: 667), CGSize(width: 667, height: 375), CGSize(width: 1032, height: 1376),
                             CGSize(width: 1376, height: 1032), CGSize(width: 440, height: 894), CGSize(width: 832, height: 440),
                             CGSize(width: 710, height: 999), CGSize(width: 620, height: 640)]
for s in creaseSizes {
    check((TourPolicy.crease(s) != nil) == topHalf(s), "crease at \(s) as ConnectLayout.topHalf")
    if let c = TourPolicy.crease(s) { check(c == (s.height / 2).rounded(), "the crease is the portrait split at \(s)") }
}
check(TourPolicy.crease(CGSize(width: 710, height: 1000)) == 500, "the Duo's crease at 500")
func width(_ w: CGFloat, _ h: CGFloat, _ layout: TourLayout, ax: Bool = false) -> CGFloat {
    TourPolicy.width(screen: CGSize(width: w, height: h), layout: layout, accessibilityText: ax)
}
check(width(1000, 710, L) == 360 && width(710, 1000, P) == 360 && width(500, 710, P) == 360, "360 at the Duo's inner sizes and outer upright")
check(width(710, 500, L) == 480, "480 on the Duo's outer display sideways")
check(width(667, 375, L) == 480 && width(832, 440, L) == 480, "480 on a phone sideways")
check(width(375, 667, P) == 343 && width(440, 894, P) == 360, "the phone upright: the screen less 32 at most")
check(width(1376, 1032, L) == 360 && width(1032, 1376, P) == 360, "iPad: 360")
check(width(1000, 710, L, ax: true) == 560 && width(710, 500, L, ax: true) == 560, "560 at accessibility sizes")
check(width(500, 710, P, ax: true) == 468 && width(375, 667, P, ax: true) == 343, "never more than the screen less 32")
check(width(740, 519, L) == 480 && width(740, 520, L) == 360, "short means under 520 pt tall")
check(width(519, 740, P) == 360, "an upright short screen is not held sideways")
check(TourPolicy.cutout([CGRect(x: 100, y: 10, width: 50, height: 60), CGRect(x: 170, y: 20, width: 30, height: 30)], screen: CGSize(width: 1000, height: 710))
      == CGRect(x: 96, y: 6, width: 108, height: 68), "the union, 4 pt larger all round")
check(TourPolicy.cutout([CGRect(x: 1, y: 1, width: 50, height: 50)], screen: CGSize(width: 1000, height: 710)) == CGRect(x: 0, y: 0, width: 55, height: 55),
      "clipped to the screen")
check(TourPolicy.cutout([], screen: CGSize(width: 10, height: 10)) == nil && TourPolicy.cutout([.null], screen: CGSize(width: 10, height: 10)) == nil, "no targets, no cutout")
check(TourPolicy.radius(.touch) == 16 && TourPolicy.radius(.bar) == 20 && TourPolicy.radius(.sharing) == 20 && TourPolicy.radius(.settings) == 20
      && TourPolicy.radius(.laptop) == 20, "radii")

// MARK: - The layouts' targets, as the stream screen reports them (BarMetrics, PortraitMetrics)

struct Screen {
    let size: CGSize
    let layout: TourLayout
    let stream: CGRect
    let targets: [TourTarget: CGRect]
    /// Larger Picture: the picture's room, and no thumbnails.
    var room: CGRect? = nil
    var thumbnails = true
    func union(_ topic: TourTopic) -> CGRect? {
        let rects = TourPolicy.targets(topic, layout, thumbnails: thumbnails).compactMap { targets[$0] }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}
/// The stream screen at a size: DuoLayout's choice and the frames each target reports. The strip is
/// reported as its thumbnails' band with their halo (5 pt) above and badge (6 pt) below. `menus`:
/// the Mac sent menus, and the Menus button sits between the strip and Aa, one button and one gap
/// taken from the strip (TopBar, the halves' window bar), where it reports itself.
func model(_ w: CGFloat, _ h: CGFloat, menus: Bool = false) -> Screen {
    let size = CGSize(width: w, height: h)
    if h > w && w < 600 || !(w > h) {
        let regular = !(h > w && w < 600)
        let half = (h / 2).rounded()
        let (padTop, padSide, padBottom, gap, barH, bw, bh, thumbPad, capH, split): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool) =
            regular ? (12, 14, 22, 10, 78, 64, 58, 10, 48, false) : (10, 14, 16, 10, 62, 56, 50, 6, 44, true)
        let barY = half + padTop
        let settingsX = w - padSide - bw
        let aaX = settingsX - 2 * (12 + bw)
        let menusX = aaX - 12 - bw
        let stripX = padSide + bw + 12
        let by = barY + (barH - bh) / 2
        let keysY = barY + barH + gap
        let keysH = split ? capH * 2 + 8 : capH
        let padY = keysY + keysH + gap
        var targets: [TourTarget: CGRect] = [
            .stream: CGRect(x: 8, y: 8, width: w - 16, height: half - 16),
            .strip: CGRect(x: stripX, y: barY + thumbPad - 5, width: (menus ? menusX : aaX) - 12 - stripX, height: barH - (thumbPad - 5) - (thumbPad - 6)),
            .textSize: CGRect(x: aaX, y: by, width: bw, height: bh),
            .settings: CGRect(x: settingsX, y: by, width: bw, height: bh),
            .keys: CGRect(x: padSide, y: keysY, width: w - 2 * padSide, height: keysH),
            .trackpad: CGRect(x: padSide, y: padY, width: w - 2 * padSide, height: h - padBottom - padY)]
        if menus { targets[.menus] = CGRect(x: menusX, y: by, width: bw, height: bh) }
        return Screen(size: size, layout: P, stream: CGRect(x: 8, y: 8, width: w - 16, height: half - 16), targets: targets)
    }
    let compact = h < 560
    let (barH, pad, bw, bh): (CGFloat, CGFloat, CGFloat, CGFloat) = compact ? (78, 14, 64, 58) : (86, 22, 66, 66)
    let settingsX = w - pad - bw
    let keyboardX = settingsX - 2 * (12 + bw)
    let aaX = keyboardX - 12 - bw
    let menusX = aaX - 12 - bw
    let stripX = pad + bw + 12
    let by = (barH - bh) / 2
    let stream = CGRect(x: 8, y: barH + 8, width: w - 16, height: h - barH - 16)
    var targets: [TourTarget: CGRect] = [
        .stream: stream,
        .strip: CGRect(x: stripX, y: 5, width: (menus ? menusX : aaX) - 12 - stripX, height: barH - 9),
        .textSize: CGRect(x: aaX, y: by, width: bw, height: bh),
        .keyboard: CGRect(x: keyboardX, y: by, width: bw, height: bh),
        .settings: CGRect(x: settingsX, y: by, width: bw, height: bh)]
    if menus { targets[.menus] = CGRect(x: menusX, y: by, width: bw, height: bh) }
    return Screen(size: size, layout: L, stream: stream, targets: targets)
}
// The model against the plan's table (§6.3).
let duoInner = model(1000, 710), duoOuter = model(710, 500), duoUp = model(710, 1000), duoOuterUp = model(500, 710)
let seSide = model(667, 375), seUp = model(375, 667)
check(duoInner.layout == L && duoInner.stream == CGRect(x: 8, y: 94, width: 984, height: 608) && duoInner.targets[.strip]!.width == 566, "1000×710 as the table")
check(duoOuter.layout == L && duoOuter.stream == CGRect(x: 8, y: 86, width: 694, height: 406) && duoOuter.targets[.strip]!.width == 302, "710×500 as the table")
check(duoUp.layout == P && duoUp.stream == CGRect(x: 8, y: 8, width: 694, height: 484) && duoUp.targets[.strip]!.width == 378
      && duoUp.targets[.keys]! == CGRect(x: 14, y: 600, width: 682, height: 48) && duoUp.targets[.trackpad]! == CGRect(x: 14, y: 658, width: 682, height: 320), "710×1000 as the table")
check(duoOuterUp.layout == P && duoOuterUp.stream == CGRect(x: 8, y: 8, width: 484, height: 339) && duoOuterUp.targets[.strip]!.width == 200
      && duoOuterUp.targets[.keys]!.minY == 437 && duoOuterUp.targets[.keys]!.maxY == 533 && duoOuterUp.targets[.trackpad]!.maxY == 694, "500×710 as the table")
check(seSide.layout == L && seSide.stream == CGRect(x: 8, y: 86, width: 651, height: 281) && seSide.targets[.strip]!.width == 259, "667×375 as the table")
check(seUp.layout == P && seUp.stream == CGRect(x: 8, y: 8, width: 359, height: 318) && seUp.targets[.strip]!.width == 75
      && seUp.targets[.keys]!.minY == 416 && seUp.targets[.trackpad]! == CGRect(x: 14, y: 522, width: 347, height: 129), "375×667 as the table")

/// A phone held upright: PhonePortraitLayout's rects, where PortraitStreamScreen places its views and
/// so where they report themselves: the picture's pane, row 1's Aa, Keyboard and Settings, the strip
/// as its thumbnails' band (the halo's 5 pt above, the badge's 6 below: WindowStrip.tourBand at the
/// strip's 6 pt pad), the six caps and the trackpad. `menus`: the Mac sent menus, and the Menus
/// button is at the end of row 2, under Settings (`l.menus`, placed there with an offset), the strip
/// ending a gap before it (`stripBesideMenus`).
func phoneModel(_ w: CGFloat, _ h: CGFloat, menus: Bool = false) -> Screen {
    let l = PhonePortraitLayout(size: CGSize(width: w, height: h))
    let pad = (PhonePortraitLayout.stripHeight - 50) / 2
    let strip = menus ? l.stripBesideMenus : l.strip
    let band = CGRect(x: strip.minX, y: strip.minY + max(0, pad - 5), width: strip.width,
                      height: strip.height - max(0, pad - 5) - max(0, pad - 6))
    var targets: [TourTarget: CGRect] = [
        .stream: l.picture, .strip: band,
        .textSize: l.buttons[PhonePortraitLayout.Button.textSize.rawValue],
        .keyboard: l.buttons[PhonePortraitLayout.Button.keyboard.rawValue],
        .settings: l.buttons[PhonePortraitLayout.Button.settings.rawValue],
        .keys: l.keys, .trackpad: l.trackpad]
    if menus { targets[.menus] = l.menus }
    return Screen(size: l.size, layout: F, stream: l.picture, targets: targets)
}
// The phones' stream screens upright (their screens less the top inset; the iPhone SE's status bar is
// 20 pt), and the Duo's outer display, which an iPhone Duo draws as a phone.
let proMax = phoneModel(440, 894), pro = phoneModel(402, 812), seTall = phoneModel(375, 647), duoPhone = phoneModel(500, 710)
check(proMax.stream == CGRect(x: 8, y: 8, width: 424, height: 265) && proMax.targets[.textSize]! == CGRect(x: 98, y: 297, width: 76, height: 50)
      && proMax.targets[.strip]! == CGRect(x: 6, y: 364, width: 428, height: 61) && proMax.targets[.keys]!.minY == 435
      && proMax.targets[.trackpad]! == CGRect(x: 14, y: 489, width: 412, height: 389), "the 18 Pro Max's rows: \(proMax.targets)")
check(seTall.stream.height == 224 && seTall.targets[.settings]!.minY == 256 && seTall.targets[.keys]!.minY == 394, "the SE's rows")

/// A phone held upright with Larger Picture: PhonePortraitLayout's rects above a keyboard this tall,
/// the picture's frame for a picture of `video`'s shape (PortraitStreamScreen places the pane there,
/// and it reports itself as the stream), the room it sits in, row 1's Apps, Aa and Keyboard (beside the
/// Mac's Menus button, six to the row, the Menus button there too, or five), Settings, the caps and the
/// trackpad; no strip.
func largerModel(_ w: CGFloat, _ h: CGFloat, keyboard: CGFloat, video: CGSize = .zero, menus: Bool = true) -> Screen {
    let l = PhonePortraitLayout(size: CGSize(width: w, height: h), keyboard: keyboard)
    let row = menus ? l.buttonsBesideMenus : l.buttons
    let pane = l.pane(video: video)
    var targets: [TourTarget: CGRect] = [
        .stream: pane,
        .apps: row[PhonePortraitLayout.Button.apps.rawValue],
        .textSize: row[PhonePortraitLayout.Button.textSize.rawValue],
        .keyboard: row[PhonePortraitLayout.Button.keyboard.rawValue],
        .settings: row[PhonePortraitLayout.Button.settings.rawValue],
        .keys: l.keys, .trackpad: l.trackpad]
    if menus { targets[.menus] = l.menus }
    return Screen(size: l.size, layout: F, stream: pane, targets: targets, room: l.picture, thumbnails: false)
}
/// A picture of a 14-inch MacBook Pro's Desktop's shape (3024×1964, 1.54:1): with Larger Picture, a
/// window of that shape (the Desktop itself keeps the standard arrangement since 2026-10-15, below).
let macBook = CGSize(width: 3024, height: 1964)
let largerMacShape = largerModel(440, 894, keyboard: 320, video: macBook), largerFitted = largerModel(440, 894, keyboard: 320, video: CGSize(width: 848, height: 844))
let largerSE = largerModel(375, 647, keyboard: 233, video: macBook), largerFive = largerModel(440, 894, keyboard: 320, video: macBook, menus: false)
check(largerMacShape.stream == CGRect(x: 8, y: 8, width: 424, height: 275) && largerMacShape.room == CGRect(x: 8, y: 8, width: 424, height: 422)
      && largerMacShape.union(.bar)! == CGRect(x: 14, y: 454, width: 272, height: 50) && largerMacShape.targets[.keys]!.minY == 520
      && largerMacShape.targets[.trackpad]! == CGRect(x: 14, y: 574, width: 412, height: 304), "the 18 Pro Max with Larger Picture and a window of the Desktop's shape: \(largerMacShape.targets)")
check(largerFitted.stream == largerFitted.room!, "a window fitted to the room: the picture is the room")
check(largerFive.union(.bar)! == CGRect(x: 14, y: 454, width: 244, height: 50), "before the Mac's menus come: Apps, Aa and Keyboard of five")
do {
    let menus = largerMacShape.targets[.menus]!, apps = largerMacShape.targets[.apps]!
    check(menus.size == apps.size && menus.minY == apps.minY && abs(menus.minX - (apps.maxX + PhonePortraitLayout.gap)) < 0.001,
          "Larger Picture's Menus button: row 1's second of six, a gap after Apps: \(menus)")
}
// The Menus button takes its room from the strip, so where it is drawn the bar card's lit span is the
// same sideways and in the halves; on a phone it ends under Settings, 8 pt short of where the strip's
// band ended (the strip's padding), and with Larger Picture it is between Apps and Aa.
for (w, h) in [(1000, 710), (710, 500), (951, 669), (832, 440), (1376, 1032), (710, 1000), (500, 710), (669, 951), (1032, 1376)] as [(CGFloat, CGFloat)] {
    let plain = model(w, h), withMenus = model(w, h, menus: true)
    check(withMenus.union(.bar) == plain.union(.bar) && withMenus.targets[.menus]!.maxX + 12 == withMenus.targets[.textSize]!.minX
          && withMenus.targets[.strip]!.maxX + 12 == withMenus.targets[.menus]!.minX, "\(w)×\(h): the Menus button between the strip and Aa, the lit span as before")
}
let proMaxMenus = phoneModel(440, 894, menus: true)
check(proMaxMenus.targets[.menus]! == CGRect(x: 350, y: 369, width: 76, height: 50) && proMaxMenus.targets[.strip]! == CGRect(x: 6, y: 364, width: 336, height: 61)
      && proMaxMenus.union(.bar)! == CGRect(x: 6, y: 297, width: 420, height: 128), "the 18 Pro Max with menus: row 2's Menus under Settings: \(proMaxMenus.targets)")
do {
    var noMenus = largerMacShape.targets
    noMenus[.menus] = nil
    let without = Screen(size: largerMacShape.size, layout: F, stream: largerMacShape.stream, targets: noMenus, room: largerMacShape.room, thumbnails: false)
    check(without.union(.bar) == largerMacShape.union(.bar)
          && largerMacShape.targets[.menus]!.minX > largerMacShape.targets[.apps]!.maxX && largerMacShape.targets[.menus]!.maxX < largerMacShape.targets[.textSize]!.minX,
          "Larger Picture: the Menus button between Apps and Aa, inside the lit span")
}

// MARK: - Where the card goes: an oracle from the plan's words

/// §6.3 in its own words, to hold `place` to them.
func oracle(_ s: Screen, _ topic: TourTopic, height h: CGFloat, width w: CGFloat, inset: CGFloat = 0) -> TourPlacement {
    let top: CGFloat = 16, bottom = s.size.height - 16 - inset
    let crease: CGFloat? = topHalf(s.size) ? (s.size.height / 2).rounded() : nil
    func centred(_ mid: CGFloat) -> CGFloat { max(16, min(mid - w / 2, s.size.width - 16 - w)) }
    let halfBottom = min((s.room ?? s.stream).maxY - 12, (crease ?? 10_000) - 16)
    if topic == .touch {
        let lowest = s.layout == L ? bottom : halfBottom
        if h <= lowest - top { return TourPlacement(card: CGRect(x: centred(s.stream.midX), y: max(top, min(s.stream.midY - h / 2, lowest - h)), width: w, height: h), tail: nil) }
        let reach = s.layout != L && crease == nil ? bottom : lowest
        return TourPlacement(card: CGRect(x: centred(s.stream.midX), y: top, width: w, height: min(h, reach - top)), tail: nil)
    }
    let t = s.union(topic)!
    let lit = t.insetBy(dx: -4, dy: -4)
    let x = centred(t.midX)
    let tip = max(x + 28, min(t.midX, x + w - 28))
    // Sideways: under its targets, as tall as its words or as the room to the bottom margin, where
    // its words scroll; over them (toward the top, no tail) only when that room is under 200 pt.
    if s.layout == L {
        let room = bottom - (t.maxY + 12)
        if h <= room || room >= 200 { return TourPlacement(card: CGRect(x: x, y: t.maxY + 12, width: w, height: min(h, room)), tail: TourTail(edge: .up, x: tip)) }
        let y = max(top, bottom - h)
        let card = CGRect(x: x, y: y, width: w, height: min(h, bottom - y))
        return TourPlacement(card: card, tail: nil, coversTargets: card.intersects(lit))
    }
    // Upright: a tail down only within 48 pt of its targets, and never across the crease.
    func down(_ card: CGRect) -> TourTail? {
        let near = t.minY - card.maxY <= 48 && t.minY >= card.maxY
        let across = crease.map { card.maxY <= $0 && $0 <= t.minY } ?? false
        return near && !across ? TourTail(edge: .down, x: tip) : nil
    }
    // In the picture's half; too tall for it, from the top margin down to 12 pt above its targets
    // (with a crease, the half); past that its words scroll. Over its targets, down to the bottom
    // margin, only when the room above them is under 200 pt and there is no crease.
    if halfBottom - h >= top { let card = CGRect(x: x, y: halfBottom - h, width: w, height: h); return TourPlacement(card: card, tail: down(card)) }
    let above = crease == nil ? min(bottom, max(top, t.minY - 12)) : halfBottom
    // A phone's controls sit mid-screen under a short picture: too tall above them, a card goes 12 pt
    // under them if it fits there, or if that room is the larger and holds a card, its tail up.
    if s.layout == F && h > above - top {
        let room = bottom - (t.maxY + 12)
        if h <= room || (room > above - top && room >= 200) {
            return TourPlacement(card: CGRect(x: x, y: t.maxY + 12, width: w, height: min(h, room)), tail: TourTail(edge: .up, x: tip))
        }
    }
    if crease != nil || h <= above - top || above - top >= 200 {
        // A phone's card stands 12 pt over its targets, growing toward the top; the halves' hangs
        // from the top margin.
        let card = CGRect(x: x, y: s.layout == F ? max(top, above - h) : top, width: w, height: min(h, above - top))
        return TourPlacement(card: card, tail: down(card))
    }
    let card = CGRect(x: x, y: top, width: w, height: min(h, bottom - top))
    return TourPlacement(card: card, tail: nil, coversTargets: card.intersects(lit))
}
func place(_ s: Screen, _ topic: TourTopic, height h: CGFloat, width w: CGFloat, inset: CGFloat = 0) -> TourPlacement {
    TourPolicy.place(card: CGSize(width: w, height: h), targets: s.union(topic), isStream: topic == .touch, screen: s.size,
                     layout: s.layout, stream: s.stream, room: s.room, bottomInset: inset)
}
func pinned(_ s: Screen, _ topic: TourTopic, _ h: CGFloat, _ expected: CGRect, tail: TourTail?, covers: Bool = false, line: Int = #line) {
    let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: false)
    let p = place(s, topic, height: h, width: w)
    check(p == TourPlacement(card: expected, tail: tail, coversTargets: covers),
          "\(s.size) \(topic) h \(h): \(p.card) tail \(String(describing: p.tail)) covers \(p.coversTargets), expected \(expected) \(String(describing: tail)) covers \(covers)", line: line)
    check(p == oracle(s, topic, height: h, width: w), "\(s.size) \(topic) h \(h) against the oracle", line: line)
}
// 1000×710, the Duo flat: 360 pt; the bar's card 12 pt under the strip's band (82), tail up.
pinned(duoInner, .touch, 262, CGRect(x: 320, y: 267, width: 360, height: 262), tail: nil)
pinned(duoInner, .bar, 230, CGRect(x: 281, y: 94, width: 360, height: 230), tail: TourTail(edge: .up, x: 461))
pinned(duoInner, .settings, 200, CGRect(x: 624, y: 88, width: 360, height: 200), tail: TourTail(edge: .up, x: 945))
pinned(duoInner, .bar, 640, CGRect(x: 281, y: 94, width: 360, height: 600), tail: TourTail(edge: .up, x: 461))   // under the bar still: its words scroll
pinned(duoInner, .touch, 900, CGRect(x: 320, y: 16, width: 360, height: 678), tail: nil)    // the screen less its margins: scrolls
// 710×500, the outer display on its side: 480 pt wide, below the compact bar (74).
pinned(duoOuter, .touch, 230, CGRect(x: 115, y: 174, width: 480, height: 230), tail: nil)
pinned(duoOuter, .bar, 230, CGRect(x: 77, y: 86, width: 480, height: 230), tail: TourTail(edge: .up, x: 317))
pinned(duoOuter, .settings, 230, CGRect(x: 214, y: 80, width: 480, height: 230), tail: TourTail(edge: .up, x: 664))
pinned(duoOuter, .settings, 420, CGRect(x: 214, y: 80, width: 480, height: 404), tail: TourTail(edge: .up, x: 664))   // scrolls, the button in view
pinned(duoOuter, .bar, 520, CGRect(x: 77, y: 86, width: 480, height: 398), tail: TourTail(edge: .up, x: 317))
// 710×1000, upright or half-folded: in the top half, its bottom at 480, no tail across the crease.
pinned(duoUp, .touch, 262, CGRect(x: 175, y: 119, width: 360, height: 262), tail: nil)
pinned(duoUp, .bar, 230, CGRect(x: 137, y: 250, width: 360, height: 230), tail: nil)
pinned(duoUp, .settings, 200, CGRect(x: 334, y: 280, width: 360, height: 200), tail: nil)
pinned(duoUp, .laptop, 330, CGRect(x: 175, y: 150, width: 360, height: 330), tail: nil)
pinned(duoUp, .laptop, 600, CGRect(x: 175, y: 16, width: 360, height: 464), tail: nil)     // never past the crease: scrolls
pinned(duoUp, .touch, 600, CGRect(x: 175, y: 16, width: 360, height: 464), tail: nil)
// 500×710, the outer display upright: the bar and settings cards point down at the window bar.
pinned(duoOuterUp, .touch, 262, CGRect(x: 70, y: 46.5, width: 360, height: 262), tail: nil)
pinned(duoOuterUp, .bar, 230, CGRect(x: 36, y: 105, width: 360, height: 230), tail: TourTail(edge: .down, x: 216))
pinned(duoOuterUp, .settings, 200, CGRect(x: 124, y: 135, width: 360, height: 200), tail: TourTail(edge: .down, x: 456))
pinned(duoOuterUp, .laptop, 300, CGRect(x: 70, y: 35, width: 360, height: 300), tail: nil)
pinned(duoOuterUp, .laptop, 330, CGRect(x: 70, y: 16, width: 360, height: 330), tail: nil)   // grows down over the window bar
pinned(duoOuterUp, .bar, 800, CGRect(x: 36, y: 16, width: 360, height: 338), tail: TourTail(edge: .down, x: 216))   // down to 12 pt above the bar
// 667×375, the iPhone SE sideways: 480 pt wide; the bar card fits under the bar at 230, and scrolls there when taller.
pinned(seSide, .touch, 200, CGRect(x: 93.5, y: 126.5, width: 480, height: 200), tail: nil)
pinned(seSide, .bar, 230, CGRect(x: 55.5, y: 86, width: 480, height: 230), tail: TourTail(edge: .up, x: 295.5))
pinned(seSide, .settings, 230, CGRect(x: 171, y: 80, width: 480, height: 230), tail: TourTail(edge: .up, x: 621))
pinned(seSide, .bar, 300, CGRect(x: 55.5, y: 86, width: 480, height: 273), tail: TourTail(edge: .up, x: 295.5))   // under the bar, scrolling
pinned(seSide, .settings, 500, CGRect(x: 171, y: 80, width: 480, height: 279), tail: TourTail(edge: .up, x: 621))
// 375×667, the iPhone SE upright: 343 pt, down to the window bar; laptop grows over it, never over the keys.
pinned(seUp, .touch, 262, CGRect(x: 16, y: 36, width: 343, height: 262), tail: nil)
pinned(seUp, .bar, 230, CGRect(x: 16, y: 84, width: 343, height: 230), tail: TourTail(edge: .down, x: 153.5))
pinned(seUp, .settings, 200, CGRect(x: 16, y: 114, width: 343, height: 200), tail: TourTail(edge: .down, x: 331))
pinned(seUp, .laptop, 330, CGRect(x: 16, y: 16, width: 343, height: 330), tail: nil)
pinned(seUp, .laptop, 700, CGRect(x: 16, y: 16, width: 343, height: 388), tail: TourTail(edge: .down, x: 187.5))   // never over the keys
// A phone held upright (the 18 Pro Max's stream screen, 440×894): a card that fits in the picture's
// short pane sits there with its tail down at row 1; the bar card, too tall for the room above the
// rows at the default size (273 pt against 269), goes 12 pt under the thumbnails with its tail up,
// and Settings too once it is taller than the room above it; the laptop card, too tall for the
// picture's pane, stands 12 pt over the keys, over rows 1 and 2 (not half of row 1).
pinned(proMax, .touch, 215, CGRect(x: 40, y: 33, width: 360, height: 215), tail: nil)
pinned(proMax, .bar, 230, CGRect(x: 40, y: 31, width: 360, height: 230), tail: TourTail(edge: .down, x: 220))
pinned(proMax, .bar, 273, CGRect(x: 40, y: 437, width: 360, height: 273), tail: TourTail(edge: .up, x: 220))
pinned(proMax, .bar, 600, CGRect(x: 40, y: 437, width: 360, height: 441), tail: TourTail(edge: .up, x: 220))
pinned(proMax, .settings, 160, CGRect(x: 64, y: 101, width: 360, height: 160), tail: TourTail(edge: .down, x: 388))
pinned(proMax, .settings, 400, CGRect(x: 64, y: 359, width: 360, height: 400), tail: TourTail(edge: .up, x: 388))
pinned(proMax, .laptop, 290, CGRect(x: 40, y: 133, width: 360, height: 290), tail: TourTail(edge: .down, x: 220))
pinned(proMax, .laptop, 500, CGRect(x: 40, y: 16, width: 360, height: 407), tail: TourTail(edge: .down, x: 220))
// The 18 Pro (402×812) and the iPhone SE (375×647): the bar card under the thumbnails, scrolling on
// the SE, where both rooms are short (228 above, 235 under); the laptop card stands over the keys.
pinned(pro, .bar, 273, CGRect(x: 21, y: 413, width: 360, height: 273), tail: TourTail(edge: .up, x: 201))
pinned(seTall, .bar, 230, CGRect(x: 16, y: 396, width: 343, height: 230), tail: TourTail(edge: .up, x: 187.5))
pinned(seTall, .bar, 320, CGRect(x: 16, y: 396, width: 343, height: 235), tail: TourTail(edge: .up, x: 187.5))
pinned(seTall, .settings, 230, CGRect(x: 16, y: 318, width: 343, height: 230), tail: TourTail(edge: .up, x: 329.5))
pinned(seTall, .laptop, 330, CGRect(x: 16, y: 52, width: 343, height: 330), tail: TourTail(edge: .down, x: 187.5))
// The Duo's outer display as a phone (500×710): a taller picture; a bar card too tall for the room
// above the rows (306) but taller still than the 220 under them stays above and scrolls.
// The halves never put a card under their bar, even where the room there is the larger (an
// upright window with its bar high up: only a phone does).
let highBar = TourPolicy.place(card: CGSize(width: 360, height: 300), targets: CGRect(x: 100, y: 150, width: 300, height: 50), isStream: false,
                               screen: CGSize(width: 500, height: 900), layout: P, stream: CGRect(x: 8, y: 8, width: 484, height: 100), bottomInset: 0)
check(highBar == TourPlacement(card: CGRect(x: 70, y: 16, width: 360, height: 300), tail: nil, coversTargets: true), "the halves: never under the bar: \(highBar)")
check(TourPolicy.place(card: CGSize(width: 360, height: 300), targets: CGRect(x: 100, y: 150, width: 300, height: 50), isStream: false,
                       screen: CGSize(width: 500, height: 900), layout: F, stream: CGRect(x: 8, y: 8, width: 484, height: 100), bottomInset: 0)
      == TourPlacement(card: CGRect(x: 70, y: 212, width: 360, height: 300), tail: TourTail(edge: .up, x: 250)), "a phone there: under its targets")
pinned(duoPhone, .bar, 273, CGRect(x: 70, y: 25, width: 360, height: 273), tail: TourTail(edge: .down, x: 250))
// Larger Picture on the 18 Pro Max (the room 424×422 from 8): the picture's card centred on the
// picture itself, a window of the Desktop's shape at 424×275, and free to grow into the room under it; every other card
// against the room, so the bar's and Settings' stand in the black under a short picture with their
// tails at row 1 (from 418, 36 pt over it); the laptop card too (its keys 102 pt under it: no tail).
pinned(largerMacShape, .touch, 230, CGRect(x: 40, y: 30.5, width: 360, height: 230), tail: nil)
pinned(largerMacShape, .touch, 380, CGRect(x: 40, y: 16, width: 360, height: 380), tail: nil)
pinned(largerMacShape, .bar, 230, CGRect(x: 16, y: 188, width: 360, height: 230), tail: TourTail(edge: .down, x: 150))
pinned(largerMacShape, .settings, 200, CGRect(x: 64, y: 218, width: 360, height: 200), tail: TourTail(edge: .down, x: 395))
pinned(largerMacShape, .laptop, 290, CGRect(x: 40, y: 128, width: 360, height: 290), tail: nil)
pinned(largerFitted, .bar, 230, CGRect(x: 16, y: 188, width: 360, height: 230), tail: TourTail(edge: .down, x: 150))
pinned(largerFitted, .touch, 230, CGRect(x: 40, y: 104, width: 360, height: 230), tail: nil)
// Without the room, the same cards stay in the short picture with no tail at row 1, 183 pt below.
check(TourPolicy.place(card: CGSize(width: 360, height: 230), targets: largerMacShape.union(.bar), isStream: false, screen: largerMacShape.size, layout: F,
                       stream: largerMacShape.stream, bottomInset: 0) == TourPlacement(card: CGRect(x: 16, y: 41, width: 360, height: 230), tail: nil),
      "without the room: in the short picture, no tail")
// The SE with Larger Picture (the room 359×262 above its 233 pt keyboard): the bar card in the room,
// its tail at row 1 (294).
pinned(largerSE, .bar, 230, CGRect(x: 16, y: 28, width: 343, height: 230), tail: TourTail(edge: .down, x: largerSE.union(.bar)!.midX))
check(abs(largerSE.union(.bar)!.midX - 385.0 / 3) < 0.001, "the SE's bar targets: Apps to Keyboard of six, centred at 128.3")
pinned(duoPhone, .bar, 320, CGRect(x: 70, y: 16, width: 360, height: 306), tail: TourTail(edge: .down, x: 250))
// A window too small for a card beside its targets (under 200 pt of room): only then over them, with
// no tail, and the dim then has no cutout or ring (coversTargets).
let tinySide = model(600, 290), tinyUp = model(330, 420)
pinned(tinySide, .settings, 190, CGRect(x: 104, y: 80, width: 480, height: 190), tail: TourTail(edge: .up, x: 554))   // fits: under it
pinned(tinySide, .settings, 250, CGRect(x: 104, y: 24, width: 480, height: 250), tail: nil, covers: true)             // 194 pt of room: over it
pinned(tinySide, .touch, 250, CGRect(x: 60, y: 24, width: 480, height: 250), tail: nil)                               // the picture's card: never "covers"
pinned(tinyUp, .bar, 180, CGRect(x: 16, y: 16, width: 298, height: 180), tail: TourTail(edge: .down, x: 131))       // grown, above the bar still
pinned(tinyUp, .bar, 250, CGRect(x: 16, y: 16, width: 298, height: 250), tail: nil, covers: true)                    // 193 pt above it: over it
// The home indicator's inset is the bottom margin's floor.
let phoneSide = model(832, 440)
let insetPlaced = place(phoneSide, .bar, height: 330, width: 480, inset: 20)
check(insetPlaced == TourPlacement(card: CGRect(x: 138, y: 86, width: 480, height: 318), tail: TourTail(edge: .up, x: 378)),
      "832×440 less 20: under the bar, down to the home indicator's margin, its words scrolling: \(insetPlaced)")
check(place(phoneSide, .bar, height: 300, width: 480, inset: 20) == TourPlacement(card: CGRect(x: 138, y: 86, width: 480, height: 300), tail: TourTail(edge: .up, x: 378)),
      "and one that fits is as tall as its words")
check(insetPlaced == oracle(phoneSide, .bar, height: 330, width: 480, inset: 20), "the inset, against the oracle")
// Targets not measured yet: centred in the picture.
check(TourPolicy.place(card: CGSize(width: 360, height: 200), targets: nil, isStream: false, screen: duoInner.size, layout: L,
                       stream: duoInner.stream, bottomInset: 0) == TourPlacement(card: CGRect(x: 320, y: 298, width: 360, height: 200), tail: nil),
      "no targets: centred in the picture")

// MARK: - Where the card goes: a grid of screens and card heights

var grid = 0
let widths: [CGFloat] = [320, 375, 414, 440, 500, 560, 600, 620, 667, 700, 710, 739, 744, 820, 834, 956, 1000, 1133, 1180, 1376]
let heights: [CGFloat] = [320, 375, 440, 500, 519, 520, 559, 560, 600, 667, 710, 744, 820, 894, 956, 999, 1000, 1100, 1133, 1376]
let cardHeights: [CGFloat] = [120, 230, 330, 450, 620, 900]
// Every screen of the grid, and at the sizes a phone has upright (under 600 pt wide, taller than
// wide) its own arrangement too.
var gridScreens: [Screen] = []
for w0 in widths {
    for h0 in heights {
        gridScreens.append(model(w0, h0))
        gridScreens.append(model(w0, h0, menus: true))
        if h0 > w0 && w0 < 600 {
            gridScreens.append(phoneModel(w0, h0))
            gridScreens.append(phoneModel(w0, h0, menus: true))
            // Larger Picture, where the room over the keyboard is 120 pt or more (on every phone it
            // applies to it is 262 or more, the SE's; Display Zoom at 320 pt wide does not take it),
            // above each keyboard measured.
            for keyboard: CGFloat in [233, 301, 310, 320] where h0 - keyboard - 152 >= 120 {
                let fitted = PhonePortraitLayout(size: CGSize(width: w0, height: h0), keyboard: keyboard).picture.size
                gridScreens.append(largerModel(w0, h0, keyboard: keyboard, video: macBook))
                gridScreens.append(largerModel(w0, h0, keyboard: keyboard, video: CGSize(width: fitted.width * 2, height: fitted.height * 2), menus: false))
            }
        }
    }
}
for s in gridScreens {
    for ax in [false, true] {
        let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: ax)
        for topic in TourPolicy.steps(s.layout, voiceOver: false) {
            for h in cardHeights {
                for inset: CGFloat in [0, 21] {
                    grid += 1
                    let p = place(s, topic, height: h, width: w, inset: inset)
                    let o = oracle(s, topic, height: h, width: w, inset: inset)
                    let label = "\(s.size) \(topic) ax \(ax) h \(h) inset \(inset)"
                    guard p == o else { check(false, "\(label): \(p) against the oracle's \(o)"); continue }
                    let c = p.card
                    let bottom = s.size.height - 16 - inset
                    let crease = TourPolicy.crease(s.size)
                    let t = topic == .touch ? s.stream : s.union(topic)!
                    let lit = t.insetBy(dx: -4, dy: -4)
                    // Inside the margins, as tall as it wants or as the room allows.
                    if !(c.minX >= 16 - 0.001 && c.maxX <= s.size.width - 16 + 0.001 && c.minY >= 16 && c.maxY <= bottom + 0.001 && c.height <= h) {
                        check(false, "\(label): \(c) outside the margins"); continue
                    }
                    if let crease, c.maxY > crease || (p.tail?.edge == .down && c.maxY + 7 > crease) {
                        check(false, "\(label): \(c) crosses the crease"); continue
                    }
                    if let tail = p.tail {
                        if c.intersects(lit) { check(false, "\(label): a tail on a card over its targets"); continue }
                        if topic == .touch { check(false, "\(label): a tail on the picture's card"); continue }
                        if tail.x < c.minX + 28 - 0.001 || tail.x > c.maxX - 28 + 0.001 { check(false, "\(label): the tip off the straight edge"); continue }
                        if s.layout == L && (tail.edge != .up || c.minY != t.maxY + 12) { check(false, "\(label): a landscape tail not up from its place"); continue }
                        if s.layout != L && tail.edge == .down && (t.minY - c.maxY > 48 || t.minY < c.maxY) { check(false, "\(label): a portrait tail too far"); continue }
                        // Up, upright, only from a phone's card 12 pt under its targets.
                        if s.layout != L && tail.edge == .up && (s.layout != F || c.minY != t.maxY + 12) { check(false, "\(label): an upright tail up away from its place"); continue }
                    }
                    if topic != .touch {
                        // Never over its own targets while the room beside them holds the card,
                        // or any card (200 pt): the lit control stays in view at every text size.
                        let roomAbove: CGFloat = crease != nil ? .infinity : min(bottom, t.minY - 12) - 16
                        let roomBelow = bottom - (t.maxY + 12)
                        let room = s.layout == L ? roomBelow : s.layout == F ? max(roomAbove, roomBelow) : roomAbove
                        if c.intersects(lit) && (room >= 200 || h <= room) { check(false, "\(label): over its targets with \(room) pt beside them"); continue }
                        if p.coversTargets != c.intersects(lit) { check(false, "\(label): coversTargets \(p.coversTargets) for \(c)"); continue }
                    } else if p.coversTargets {
                        check(false, "\(label): the picture's card hides its ring"); continue
                    }
                    if topic != .touch && s.layout == L {
                        let room = bottom - (t.maxY + 12)
                        let holds = h <= room || room >= 200
                        // Under its targets with a tail up, as tall as its words or as the room.
                        if holds && (c.minY != t.maxY + 12 || c.height != min(h, room) || p.tail?.edge != .up) { check(false, "\(label): not under its targets: \(c)"); continue }
                        // Only a room too small for a card makes it grow toward the top, tail-less.
                        if !holds && (c.maxY != bottom || p.tail != nil) { check(false, "\(label): grew wrongly to \(c)"); continue }
                    }
                    if topic != .touch && s.layout != L {
                        let halfBottom = min((s.room ?? s.stream).maxY - 12, (crease ?? 10_000) - 16)
                        let roomAbove = min(bottom, max(16, t.minY - 12)) - 16
                        // A phone's card 12 pt under its targets, its tail up: only when it did not
                        // fit above them, and it fits under them or has the larger room there.
                        let under = s.layout == F && c.minY == t.maxY + 12
                        if under && (h <= roomAbove || p.tail?.edge != .up) { check(false, "\(label): under its targets while it fits above: \(c)"); continue }
                        // In the picture's half while it fits; past it only down to its targets' top,
                        // and without a crease.
                        if h <= halfBottom - 16 && c.maxY != halfBottom { check(false, "\(label): not at the picture's bottom"); continue }
                        if c.maxY > halfBottom + 0.001 && crease != nil { check(false, "\(label): past the picture's half with a crease"); continue }
                        // Grown: the halves' from the top margin, a phone's standing 12 pt over its targets.
                        let stands = s.layout == F && c.maxY == min(bottom, max(16, t.minY - 12))
                        if h > halfBottom - 16 && c.minY != 16 && !under && !stands { check(false, "\(label): grew, but not from the top"); continue }
                        if !p.coversTargets && !under && c.maxY > t.minY - 12 + 0.001 { check(false, "\(label): closer than 12 pt to its targets: \(c)"); continue }
                        // Only a phone goes under; the halves keep their cards above.
                        if s.layout == P && c.minY > t.minY { check(false, "\(label): the halves' card under its targets"); continue }
                    }
                    if abs(c.width - w) > 0.001 { check(false, "\(label): width \(c.width) not \(w)"); continue }
                    // The card draws its tail from the height it was laid out at: placed again at
                    // that height, it must land where it is, tail and all.
                    let again = place(s, topic, height: c.height, width: w, inset: inset)
                    if again != p { check(false, "\(label): placed again at \(c.height) it moves to \(again)"); continue }
                    check(true, "")
                }
            }
        }
    }
}
check(grid >= 400, "the grid covers \(grid) placements")

// MARK: - The iPhone Duo's real sizes, with its fold (iOS 27.1; docs/iphone-duo-plan.md)

// The stream screen's sizes on the iOS 27.1 simulator (the status bar hidden on the inner display held
// upright, shown sideways: 867 pt, its strip at the side; 951 if it were hidden there too; the cover
// less its camera's strip), and the fold as the device reports it there.
let bookSize = CGSize(width: 951, height: 669), uprightSize = CGSize(width: 669, height: 951)
let bookBand = CGRect(x: 455.5, y: 0, width: 40, height: 669), laptopBand = CGRect(x: 0, y: 455.5, width: 669, height: 40)
let bookInfo = FoldInfo.known(bookBand), laptopInfo = FoldInfo.known(laptopBand), flatInfo = FoldInfo.known(nil)
/// The halves split at `picture` and `controls` (DuoPosture.portraitSplit), the inner display's metrics.
func halvesModel(_ w: CGFloat, _ h: CGFloat, picture: CGFloat, controls: CGFloat) -> Screen {
    let (padTop, padSide, padBottom, gap, barH, bw, bh, thumbPad, capH): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) =
        (12, 14, 22, 10, 78, 64, 58, 10, 48)
    let barY = controls + padTop
    let settingsX = w - padSide - bw
    let aaX = settingsX - 2 * (12 + bw)
    let stripX = padSide + bw + 12
    let by = barY + (barH - bh) / 2
    let keysY = barY + barH + gap
    let padY = keysY + capH + gap
    let stream = CGRect(x: 8, y: 8, width: w - 16, height: picture - 16)
    return Screen(size: CGSize(width: w, height: h), layout: P, stream: stream, targets: [
        .stream: stream,
        .strip: CGRect(x: stripX, y: barY + thumbPad - 5, width: aaX - 12 - stripX, height: barH - (thumbPad - 5) - (thumbPad - 6)),
        .textSize: CGRect(x: aaX, y: by, width: bw, height: bh),
        .settings: CGRect(x: settingsX, y: by, width: bw, height: bh),
        .keys: CGRect(x: padSide, y: keysY, width: w - 2 * padSide, height: capH),
        .trackpad: CGRect(x: padSide, y: padY, width: w - 2 * padSide, height: h - padBottom - padY)])
}
/// The landscape bar at 951 pt, and in the book pose its strip ending 12 pt short of the fold
/// (DuoPosture.bookBar: 343.5 pt; the right group keeps its size, 55.5 pt past the fold).
let flatLandscape = model(951, 669)
let bookScreen: Screen = {
    var targets = flatLandscape.targets
    targets[.strip] = CGRect(x: 100, y: 5, width: 343.5, height: 77)
    return Screen(size: bookSize, layout: L, stream: flatLandscape.stream, targets: targets)
}()
/// The book pose as this build draws it, the status bar's strip shown at the side (867 pt): the bar
/// at DuoPosture.bookBar's compact width and 7 pt gaps (Menus at 497, Aa 568, Keyboard 639, Settings
/// 781), the strip ending 7 pt short of the fold (93 to 448.5); open flat sideways the bar as before.
let book867Size = CGSize(width: 867, height: 669)
let flatLandscape867 = model(867, 669)
let book867: Screen = {
    var targets = flatLandscape867.targets
    targets[.strip] = CGRect(x: 93, y: 5, width: 355.5, height: 77)
    targets[.textSize] = CGRect(x: 568, y: 10, width: 64, height: 66)
    targets[.keyboard] = CGRect(x: 639, y: 10, width: 64, height: 66)
    targets[.settings] = CGRect(x: 781, y: 10, width: 64, height: 66)
    return Screen(size: book867Size, layout: L, stream: flatLandscape867.stream, targets: targets)
}()
let laptop = halvesModel(669, 951, picture: 455, controls: 496), flatUpright = halvesModel(669, 951, picture: 424, controls: 424)
let duoCover = phoneModel(382, 678), duoCoverSide = model(594, 466)
check(flatLandscape.stream == CGRect(x: 8, y: 94, width: 935, height: 567) && flatLandscape.targets[.textSize]!.minX == 629
      && flatLandscape.targets[.settings]!.minX == 863, "951×669 as the stream screen lays it out")
check(laptop.stream == CGRect(x: 8, y: 8, width: 653, height: 439) && laptop.targets[.keys]!.minY == 596 && laptop.targets[.trackpad]!.maxY == 929,
      "669×951 half-folded: the picture above the fold, the controls from 496")
func placeDuo(_ s: Screen, _ topic: TourTopic, height h: CGFloat, fold: FoldInfo, ax: Bool = false, inset: CGFloat = 0) -> TourPlacement {
    let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: ax, fold: fold, targets: s.union(topic))
    return TourPolicy.place(card: CGSize(width: w, height: h), targets: s.union(topic), isStream: topic == .touch, screen: s.size,
                            layout: s.layout, stream: s.stream, bottomInset: inset, fold: fold)
}
func duoPinned(_ s: Screen, _ topic: TourTopic, _ h: CGFloat, _ fold: FoldInfo, _ expected: CGRect, tail: TourTail?, line: Int = #line) {
    let p = placeDuo(s, topic, height: h, fold: fold)
    check(p == TourPlacement(card: expected, tail: tail), "\(s.size) \(topic) h \(h): \(p.card) tail \(String(describing: p.tail)), expected \(expected) \(String(describing: tail))", line: line)
}
// The crease: the fold's real top upright, half-folded; none open flat; as before when unknown.
check(TourPolicy.crease(uprightSize) == 476, "669×951 inferred, as before: the middle, rounded")
check(TourPolicy.crease(uprightSize, laptopInfo) == 455.5, "the laptop pose: the fold's top")
check(TourPolicy.crease(uprightSize, flatInfo) == nil && TourPolicy.crease(bookSize, bookInfo) == nil && TourPolicy.crease(bookSize, flatInfo) == nil,
      "open flat, and the book pose: no crease across")
check(TourPolicy.crease(CGSize(width: 669, height: 869), .known(CGRect(x: 0, y: 373.5, width: 669, height: 40))) == 373.5, "the status bar shown")
// The width: a page holds it in the book pose.
check(TourPolicy.width(screen: bookSize, layout: L, accessibilityText: false, fold: bookInfo) == 360, "the book pose: 360")
check(TourPolicy.width(screen: bookSize, layout: L, accessibilityText: true, fold: bookInfo) == 439.5, "the book pose at accessibility sizes: a page's 439.5")
check(TourPolicy.width(screen: bookSize, layout: L, accessibilityText: true, fold: flatInfo) == 560
      && TourPolicy.width(screen: uprightSize, layout: P, accessibilityText: true, fold: laptopInfo) == 560, "open flat and upright: 560")
check(TourPolicy.width(screen: CGSize(width: 594, height: 466), layout: L, accessibilityText: false, fold: flatInfo) == 480, "the cover on its side: 480")
// With the status bar's strip (867 pt) the trailing page is 355.5: a card about Settings is that wide,
// beside it; one about the strip or the picture keeps the leading page's 360 (439.5 at accessibility
// sizes).
check(TourPolicy.width(screen: book867Size, layout: L, accessibilityText: false, fold: bookInfo, targets: book867.union(.settings)) == 355.5,
      "867, Settings: the trailing page's 355.5")
check(TourPolicy.width(screen: book867Size, layout: L, accessibilityText: true, fold: bookInfo, targets: book867.union(.settings)) == 355.5,
      "867, Settings, accessibility sizes: 355.5")
check(TourPolicy.width(screen: book867Size, layout: L, accessibilityText: false, fold: bookInfo, targets: book867.union(.bar)) == 360
      && TourPolicy.width(screen: book867Size, layout: L, accessibilityText: true, fold: bookInfo, targets: book867.union(.touch)) == 439.5,
      "867, the bar and the picture: the leading page")
check(TourPolicy.width(screen: book867Size, layout: L, accessibilityText: false, fold: bookInfo) == 360, "867, no targets yet: the wider page")
// The book pose: the picture's card on the leading page, against the fold; a bar card that would
// cross it goes onto the page its middle is on; one clear of it stays centred on its targets.
duoPinned(bookScreen, .touch, 262, bookInfo, CGRect(x: 95.5, y: 246.5, width: 360, height: 262), tail: nil)
duoPinned(bookScreen, .bar, 230, bookInfo, CGRect(x: 95.5, y: 94, width: 360, height: 230), tail: TourTail(edge: .up, x: 427.5))
duoPinned(bookScreen, .settings, 200, bookInfo, CGRect(x: 575, y: 88, width: 360, height: 200), tail: TourTail(edge: .up, x: 896))
// The book pose as drawn, 867 pt: the picture's card and the bar's on the leading page against the
// fold; Settings' on the trailing page, beside the button, with its tail at it (the review: at 360 pt
// it went to the far page, its tail clamped at the card's edge).
check(book867.targets[.strip]!.maxX == 448.5 && book867.targets[.settings]!.maxX == 845 && book867.stream == CGRect(x: 8, y: 94, width: 851, height: 567),
      "867×669 as the stream screen lays it out")
duoPinned(book867, .touch, 262, bookInfo, CGRect(x: 95.5, y: 246.5, width: 360, height: 262), tail: nil)
duoPinned(book867, .bar, 230, bookInfo, CGRect(x: 95.5, y: 94, width: 360, height: 230), tail: TourTail(edge: .up, x: 398))
duoPinned(book867, .settings, 200, bookInfo, CGRect(x: 495.5, y: 88, width: 355.5, height: 200), tail: TourTail(edge: .up, x: 813))
duoPinned(flatLandscape867, .settings, 200, flatInfo, CGRect(x: 491, y: 88, width: 360, height: 200), tail: TourTail(edge: .up, x: 812))
// Open flat sideways: as before, across the middle.
duoPinned(flatLandscape, .touch, 262, flatInfo, CGRect(x: 295.5, y: 246.5, width: 360, height: 262), tail: nil)
check(placeDuo(flatLandscape, .bar, height: 230, fold: flatInfo) == placeDuo(flatLandscape, .bar, height: 230, fold: .inferred), "open flat: the fold changes nothing")
// The laptop pose: in the picture above the fold, never across it, no tail across it.
duoPinned(laptop, .touch, 262, laptopInfo, CGRect(x: 154.5, y: 96.5, width: 360, height: 262), tail: nil)
duoPinned(laptop, .laptop, 330, laptopInfo, CGRect(x: 154.5, y: 105, width: 360, height: 330), tail: nil)
duoPinned(laptop, .settings, 200, laptopInfo, CGRect(x: 293, y: 235, width: 360, height: 200), tail: nil)
duoPinned(laptop, .laptop, 600, laptopInfo, CGRect(x: 154.5, y: 16, width: 360, height: 419), tail: nil)   // never past the fold: scrolls
// Open flat upright: no crease, the pane at the picture's shape (16:10 here, 424 pt).
duoPinned(flatUpright, .laptop, 330, flatInfo, CGRect(x: 154.5, y: 74, width: 360, height: 330), tail: nil)
duoPinned(flatUpright, .touch, 600, flatInfo, CGRect(x: 154.5, y: 16, width: 360, height: 600), tail: nil)   // grows past the picture: no fold
duoPinned(flatUpright, .settings, 200, flatInfo, CGRect(x: 293, y: 204, width: 360, height: 200), tail: TourTail(edge: .down, x: 623))
// The cover: no fold; the phone's and the compact sideways placements, as before.
for topic in TourPolicy.steps(F, voiceOver: false) {
    check(placeDuo(duoCover, topic, height: 230, fold: flatInfo) == placeDuo(duoCover, topic, height: 230, fold: .inferred), "the cover upright, \(topic)")
}
for topic in TourPolicy.steps(L, voiceOver: false) {
    check(placeDuo(duoCoverSide, topic, height: 230, fold: flatInfo) == placeDuo(duoCoverSide, topic, height: 230, fold: .inferred), "the cover on its side, \(topic)")
}
// Every card at every height and text size: the book pose's on one page, the laptop pose's above
// the fold; within the margins; a tail only on the card's straight edge.
var duoGrid = 0
for (s, fold) in [(bookScreen, bookInfo), (book867, bookInfo), (laptop, laptopInfo), (flatLandscape, flatInfo), (flatLandscape867, flatInfo),
                  (flatUpright, flatInfo), (duoCover, flatInfo), (duoCoverSide, flatInfo)] {
    for ax in [false, true] {
        for topic in TourPolicy.steps(s.layout, voiceOver: false) {
            for h in stride(from: CGFloat(80), through: 1000, by: 40) {
                for inset: CGFloat in [0, 34] {
                    duoGrid += 1
                    let p = placeDuo(s, topic, height: h, fold: fold, ax: ax, inset: inset)
                    let c = p.card
                    let label = "\(s.size) \(fold) \(topic) ax \(ax) h \(h) inset \(inset)"
                    check(c.minX >= 16 - 0.001 && c.maxX <= s.size.width - 16 + 0.001 && c.minY >= 16 - 0.001
                          && c.maxY <= s.size.height - 16 - inset + 0.001, "\(label): within the margins, \(c)")
                    if let band = fold.verticalBand {
                        check(c.maxX <= band.minX + 0.001 || c.minX >= band.maxX - 0.001, "\(label): on one page, \(c)")
                        // On the page its targets are on (the picture's: the leading one).
                        if let t = s.union(topic), topic != .touch {
                            check(t.midX <= band.midX ? c.maxX <= band.minX + 0.001 : c.minX >= band.maxX - 0.001, "\(label): beside its targets, \(c)")
                        }
                    }
                    if let band = fold.horizontalBand, !p.coversTargets {
                        check(c.maxY <= band.minY - 16 + 0.001, "\(label): above the fold, \(c)")
                        if let tail = p.tail { check(tail.edge != .down || c.maxY + 7 <= band.minY, "\(label): a tail across the fold") }
                    }
                    if let tail = p.tail { check(tail.x >= c.minX + 28 - 0.001 && tail.x <= c.maxX - 28 + 0.001, "\(label): the tip on the straight edge") }
                    check(placeDuo(s, topic, height: c.height, fold: fold, ax: ax, inset: inset) == p, "\(label): placed again where it is")
                }
            }
        }
    }
}
check(duoGrid == 3360, "the Duo's grid: \(duoGrid) placements (five screens of four steps sideways, three of five upright)")

// MARK: - The words

/// Every feature there (an up-to-date Mac with menus, gestures on, Virtual Display on, an iPhone that
/// offers Larger Picture), none of it (an older Mac on a device with gestures off), and all 128 ways.
let allOn = TourFeatures(menus: true, gestures: true, virtualDisplay: true, clipboard: true, pasteRightAway: true, sound: true, largerPicture: true)
let allOff = TourFeatures(menus: false, gestures: false, virtualDisplay: false, clipboard: false, pasteRightAway: false, sound: false, largerPicture: false)
let everyFeatures: [TourFeatures] = (0..<128).map { i in
    TourFeatures(menus: i & 1 != 0, gestures: i & 2 != 0, virtualDisplay: i & 4 != 0, clipboard: i & 8 != 0,
                 pasteRightAway: i & 16 != 0, sound: i & 32 != 0, largerPicture: i & 64 != 0)
}
check(Set(everyFeatures.map { "\($0)" }).count == 128, "the 128 combinations differ")
func with(_ base: TourFeatures = allOn, _ change: (inout TourFeatures) -> Void) -> TourFeatures {
    var f = base
    change(&f)
    return f
}
func words(_ t: TourTopic, _ layout: TourLayout, mac: String = "Mac mini", device: String = "iPad", voiceOver: Bool = false,
           first: Bool = false, onItsSide: Bool = false, thumbnails: Bool = true, features: TourFeatures = allOn) -> TourCopy {
    TourPolicy.copy(t, layout, mac: mac, device: device, voiceOver: voiceOver, firstOfRun: first, keysOnItsSide: onItsSide,
                    thumbnails: thumbnails, features: features)
}
func texts(_ c: TourCopy) -> [String] { c.rows.map(\.text) }

// Every row of every card, as the plan's table has it (docs/first-run-walkthrough-plan.md, "The tour
// once more, for 0.6"), for Mac mini and an iPad unless said.
let T1 = "Tap to click.", T2 = "Touch and hold to right-click.", T3 = "Drag to scroll.", T4 = "Apple Pencil works as a mouse."
let T5 = "New: Pinch to zoom the picture here, up to 5×. Zoomed in, two fingers move it, and one finger still works Mac mini."
let T6 = "New: Swipe with three fingers: up for Mission Control, down for App Exposé, and sideways between Spaces."
let B1 = "Touch and hold a window to close, minimize or go full screen. Keep holding and drag to move it."
let B1VO = "Each window has actions: close, minimize, full screen, and move left or right. Swipe up or down to hear them."
let B1Apps = "Apps lists the apps on Mac mini: tap an open one again for its next window."
let B1AppsVO = "Apps lists the apps on Mac mini. Choose an open one again for its next window."
let B2 = "New: Menus has the menu bar of the app you’re using on Mac mini."
let B3on = "New: Virtual Display is on: a window you pick streams from a display of its own on Mac mini, so it keeps updating when something covers it; Aa then sizes its text."
let B3off = "New: Virtual Display, in Settings, streams a window you pick from a display of its own on Mac mini, so it keeps updating when something covers it; Aa then sizes its text."
let B3onVO = "New: Virtual Display is on: a window you pick streams from a display of its own on Mac mini, so it keeps updating when something covers it; Text size then makes its text larger or smaller: swipe up or down on it."
let B3offVO = "New: Virtual Display, in Settings, streams a window you pick from a display of its own on Mac mini, so it keeps updating when something covers it; Text size then makes its text larger or smaller: swipe up or down on it."
let B4 = "Keyboard brings up the on-screen keyboard to type on Mac mini."
let B5 = "New: A hardware keyboard types on Mac mini by itself, Esc included, and Keyboard then brings up the keyboard bar."
let S1 = "New: With Share Clipboard, text you copy on Mac mini is ready to paste on this iPad."
let S2 = "New: Copy on this iPad, then come back to Sill: Paste on Mac mini, on the note Sill shows then or in Settings, puts it where Mac mini’s cursor is."
let S2off = "New: Copy on this iPad, then come back to Sill: Paste on Mac mini, on the note Sill shows then or in Settings, sends it to Mac mini’s clipboard."
let S3 = "New: Send Audio, a beta, plays Mac mini’s sound here, and Mute silences this iPad alone."
let S4 = "New: Update Sill on Mac mini to copy and paste between it and this iPad, and to hear its sound here."
let G1 = "Disconnect is at the bottom of Settings.", G2 = "Take the Tour is there too, to see this again."
let G3 = "New: Reverse Scrolling turns a finger’s drag and the on-screen trackpad’s two-finger scroll around."
let G4 = "New: Hold to Show Window Controls sets how long you hold a window’s thumbnail before its controls show."
let G5 = "Hold your iPad upright for a trackpad and keys."
let K1 = "cmd, opt, ctrl and shift stay on for the next key or trackpad click: tap cmd, then C, to copy."
let K1VO = "cmd, opt, ctrl and shift stay on for the next key: cmd, then C, copies."
let K2 = "The keyboard key brings up the on-screen keyboard to type on Mac mini."
let K3 = "New: A hardware keyboard types on Mac mini by itself, Esc included, and the keyboard key then brings up the keyboard bar."
let K4 = "Tap with two fingers on the trackpad to right-click.", K5 = "Touch and hold the trackpad, then drag, to move a window or select text."
let K6 = "New: Larger Picture, in Settings: a window’s picture takes the place of the thumbnails and reaches down to where the keyboard comes up."
func onIPhone(_ s: String) -> String { s.replacingOccurrences(of: "this iPad", with: "this iPhone") }

// The picture's card: a fifth row, the pinch, for everyone; the gestures' only while on and taken.
let touchPad = words(.touch, L, first: true)
check(touchPad.title == "Tap, Hold, Drag and Pinch" && touchPad.subtitle == "What you do here happens on Mac mini.", "touch: title and subtitle")
check(texts(touchPad) == [T1, T2, T3, T4, T5, T6], "touch on iPad: \(texts(touchPad))")
check(touchPad.rows.map(\.symbol) == ["hand.tap", "contextualmenu.and.cursorarrow", "hand.draw", "applepencil", "plus.magnifyingglass", "hand.raised.fingers.spread"],
      "touch's symbols")
check(touchPad.rows[0].spans == [TourSpan(text: "Tap", strong: true), TourSpan(text: " to click.", strong: false)], "the control's name semibold")
check(touchPad.hint == "The picture of Mac mini fills the screen below the bar.", "touch's hint sideways")
check(words(.touch, P).hint == "The picture of Mac mini fills the top half of the screen.", "touch's hint upright")
check(texts(words(.touch, L, device: "iPhone")) == [T1, T2, T3, T5, T6], "no Pencil row on iPhone, the pinch's for both")
check(texts(words(.touch, L, features: with { $0.gestures = false })) == [T1, T2, T3, T4, T5], "the gestures off, or a Mac that takes none: no swipe row")
check(texts(words(.touch, F, device: "iPhone", features: allOff)) == [T1, T2, T3, T5], "the pinch row whatever the Mac")
check(texts(words(.touch, P, mac: "Studio")).contains("New: Pinch to zoom the picture here, up to 5×. Zoomed in, two fingers move it, and one finger still works Studio."),
      "the Mac's name in the pinch row")
check(words(.touch, L, mac: "").subtitle == "What you do here happens on your Mac." && words(.touch, P, mac: "").hint == "The picture of your Mac fills the top half of the screen.",
      "the “your Mac” fallback")
for f in everyFeatures {
    check(words(.touch, L, features: f).rows.contains { $0.symbol == "hand.raised.fingers.spread" } == f.gestures, "the swipe row follows the gestures: \(f)")
}

// The bar's card: Windows (and Menus), the Virtual Display row with Aa in it, the Keyboard button and a
// hardware keyboard where the bar has the button.
let barL = words(.bar, L)
check(barL.title == "Windows and Menus" && barL.subtitle == nil, "bar: title, no subtitle")
check(texts(barL) == [B1, B2, B3on, B4, B5], "bar sideways: \(texts(barL))")
check(barL.rows.map(\.symbol) == ["hand.point.up.left", "filemenu.and.selection", "display", "keyboard", "keyboard.badge.ellipsis"], "bar's symbols")
check(texts(words(.bar, P)) == [B1, B2, B3on], "bar upright: no Keyboard rows (it is a cap)")
check(barL.hint == "In the bar at the top, after Apps." && words(.bar, P).hint == "In the bar below the picture, after Apps.", "bar's hints")
check(texts(words(.bar, L, mac: "Studio")).suffix(2) == ["Keyboard brings up the on-screen keyboard to type on Studio.",
                                                          "New: A hardware keyboard types on Studio by itself, Esc included, and Keyboard then brings up the keyboard bar."],
      "the Mac's name in the Keyboard rows")
check(words(.bar, L, features: with { $0.menus = false }).title == "Windows" && texts(words(.bar, L, features: with { $0.menus = false })) == [B1, B3on, B4, B5],
      "no Menus button on screen: no Menus row, and the title Windows")
check(texts(words(.bar, L, features: with { $0.virtualDisplay = false })) == [B1, B2, B3off, B4, B5], "Virtual Display off: where the switch is, New too")
check(texts(words(.bar, P, features: with { $0.virtualDisplay = false; $0.menus = false })) == [B1, B3off], "the halves, an older Mac: two rows")
check(words(.bar, L).rows[2].spans.filter(\.strong).map(\.text) == ["New:", "Virtual Display", "Aa"]
      && words(.bar, L, features: with { $0.virtualDisplay = false }).rows[2].spans.filter(\.strong).map(\.text) == ["New:", "Virtual Display", "Aa"],
      "the Virtual Display row names Virtual Display and Aa")
check(words(.bar, L).rows[4].spans.filter(\.strong).map(\.text) == ["New:", "A hardware keyboard", "Keyboard"], "two names in the hardware keyboard's row")
for f in everyFeatures {
    let bar = words(.bar, L, features: f)
    check(bar.rows.contains { $0.symbol == "filemenu.and.selection" } == f.menus && bar.title == (f.menus ? "Windows and Menus" : "Windows"),
          "the Menus row and the title follow the button: \(f)")
    check(bar.rows.first { $0.symbol == "display" }?.text == (f.virtualDisplay ? B3on : B3off), "Virtual Display's row follows the Mac's setting: \(f)")
    check(words(.bar, P, features: f).rows.allSatisfy { $0.symbol != "keyboard" && $0.symbol != "keyboard.badge.ellipsis" }, "no Keyboard rows in the halves' bar card: \(f)")
}

// The clipboard's and the sound's card: what this Mac has, and the update an older one needs.
let sharingL = words(.sharing, L)
check(sharingL.title == "Clipboard and Sound" && sharingL.subtitle == nil && sharingL.hint == "In Settings, the last button in the bar.", "sharing: title, hint")
check(texts(sharingL) == [S1, S2, S3], "sharing: \(texts(sharingL))")
check(sharingL.rows.map(\.symbol) == ["doc.on.clipboard", "doc.on.doc", "speaker.wave.2"], "sharing's symbols")
check(sharingL.rows.map { $0.spans.filter(\.strong).map(\.text) } == [["New:", "Share Clipboard"], ["New:", "Paste on Mac mini"], ["New:", "Send Audio", "Mute"]],
      "the switches' and the chip's names semibold")
check(texts(words(.sharing, L, features: with { $0.pasteRightAway = false })) == [S1, S2off, S3], "Paste on Mac mini Right Away off: it goes to the clipboard")
let clipboardOnly = words(.sharing, P, features: with { $0.sound = false })
check(clipboardOnly.title == "Clipboard" && texts(clipboardOnly) == [S1, S2], "a Mac with the clipboard but no sound")
let soundOnly = words(.sharing, P, features: with { $0.clipboard = false })
check(soundOnly.title == "Sound" && texts(soundOnly) == [S3], "a Mac with sound but no clipboard")
let older = words(.sharing, L, features: allOff)
check(older.title == "Clipboard and Sound" && texts(older) == [S4] && older.rows[0].symbol == "arrow.down.circle", "an older Mac: the update row alone")
check(texts(words(.sharing, F, device: "iPhone")) == [S1, S2, S3].map(onIPhone) && texts(words(.sharing, F, device: "iPhone", features: allOff)) == [onIPhone(S4)],
      "this iPhone, on an iPhone")
check(words(.sharing, F, device: "iPhone").hint == "In Settings, the last button in the row under the picture." && words(.sharing, P).hint == sharingL.hint,
      "sharing's hints")
check(words(.sharing, L, voiceOver: true) == sharingL && words(.sharing, F, device: "iPhone", voiceOver: true) == words(.sharing, F, device: "iPhone"),
      "the same words under VoiceOver")
check(texts(words(.sharing, L, mac: "Studio")).contains("New: Copy on this iPad, then come back to Sill: Paste on Studio, on the note Sill shows then or in Settings, puts it where Studio’s cursor is."),
      "the Mac's name in Paste's row")
check(texts(words(.sharing, L, mac: "")).contains("New: Copy on this iPad, then come back to Sill: Paste on your Mac, on the note Sill shows then or in Settings, puts it where your Mac’s cursor is."),
      "the “your Mac” fallback in Paste's row")
for f in everyFeatures {
    let s = words(.sharing, L, features: f)
    check(s.rows.contains { $0.symbol == "doc.on.clipboard" } == f.clipboard && s.rows.contains { $0.symbol == "doc.on.doc" } == f.clipboard
          && s.rows.contains { $0.symbol == "speaker.wave.2" } == f.sound && s.rows.contains { $0.symbol == "arrow.down.circle" } == (!f.clipboard && !f.sound)
          && !s.rows.isEmpty, "the card follows the Mac: \(f)")
    check(s.title == (f.clipboard == f.sound ? "Clipboard and Sound" : f.clipboard ? "Clipboard" : "Sound"), "its title: \(f)")
    if f.clipboard { check(s.rows[1].text == (f.pasteRightAway ? S2 : S2off), "Paste's row follows Right Away: \(f)") }
}

// Settings: this device's two new switches (sighted), and sideways the upright row last.
let settingsL = words(.settings, L)
check(settingsL.title == "Settings" && settingsL.subtitle == nil && settingsL.hint == "The last button in the bar.", "settings: title, hint")
check(texts(settingsL) == [G1, G2, G3, G4, G5], "settings sideways on iPad: \(texts(settingsL))")
check(settingsL.rows.map(\.symbol) == ["xmark.circle", "questionmark.circle", "arrow.up.arrow.down", "timer", "ipad"], "settings' symbols on iPad")
check(texts(words(.settings, L, device: "iPhone")).last == "Hold your iPhone upright for a trackpad and keys."
      && words(.settings, L, device: "iPhone").rows.last?.symbol == "iphone", "the upright row on iPhone")
check(texts(words(.settings, P)) == [G1, G2, G3, G4], "no upright row when upright")
check(texts(words(.settings, L, voiceOver: true)) == [G1, G2, G5] && texts(words(.settings, P, voiceOver: true)) == [G1, G2],
      "under VoiceOver no Reverse Scrolling or hold rows (a drag and a hold)")
check(everyFeatures.allSatisfy { words(.settings, L, features: $0) == settingsL && words(.settings, F, device: "iPhone", features: $0) == words(.settings, F, device: "iPhone") },
      "the Settings card is the same for every Mac")

// The laptop half's card.
let laptopFirst = words(.laptop, P, first: true)
check(laptopFirst.title == "Keys and Trackpad" && laptopFirst.subtitle == "Upright, Sill adds keys and a trackpad.", "laptop as a run's first card")
check(words(.laptop, P, first: false).subtitle == nil, "laptop's subtitle only as a run's first")
check(texts(laptopFirst) == [K1, K2, K3, K4, K5], "laptop: \(texts(laptopFirst))")
check(laptopFirst.rows[0].spoken == "Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.", "the caps spoken by name")
check(laptopFirst.rows[4].spans.filter(\.strong).map(\.text) == ["Touch and hold", "then drag"], "two names in the drag row")
check(laptopFirst.rows[2].spans.filter(\.strong).map(\.text) == ["New:", "A hardware keyboard", "the keyboard key"], "two names in the hardware keyboard's row")
check(laptopFirst.rows.map(\.symbol) == ["command", "keyboard", "keyboard.badge.ellipsis", "cursorarrow.click.2", "hand.draw"], "laptop's symbols")
check(laptopFirst.hint == "Below the bar: the row of keys, then the trackpad.", "laptop's hint")
check(everyFeatures.allSatisfy { words(.laptop, P, first: true, features: $0) == laptopFirst }, "the halves' laptop card is the same for every Mac")
check(touchPad.rows[1].spoken == "Touch and hold to right-click.", "a row is spoken as it reads")

// The iPhone Duo open: its keys and trackpad come with the device on its side (the laptop pose, open
// flat upright), so the words say so where an iPhone's and the Duo's cover's say upright.
let duoSettings = words(.settings, L, device: "iPhone", onItsSide: true)
check(texts(duoSettings).last == "Turn your iPhone on its side for a trackpad and keys." && duoSettings.rows.last?.symbol == "iphone"
      && duoSettings.rows.last?.spans.first == TourSpan(text: "Turn your iPhone on its side", strong: true), "the Duo's inner display sideways")
check(texts(duoSettings).prefix(4) == texts(words(.settings, L, device: "iPhone")).prefix(4), "the Duo: the other rows as before")
check(words(.laptop, P, device: "iPhone", first: true, onItsSide: true).subtitle == "On its side, Sill adds keys and a trackpad.", "the Duo's laptop card")
check(words(.laptop, P, device: "iPhone", first: false, onItsSide: true).subtitle == nil, "…only as a run's first")
check(texts(words(.laptop, P, device: "iPhone", onItsSide: true)) == texts(words(.laptop, P, device: "iPhone")), "the Duo's laptop rows as before")
for t in [TourTopic.touch, .bar, .sharing] {
    for layout in [L, P] { check(words(t, layout, onItsSide: true) == words(t, layout), "\(t) \(layout): the same words on the Duo") }
}
// The Duo's cover upright is a phone, with no Larger Picture there (a hinge): three rows on its laptop card.
check(texts(words(.laptop, F, device: "iPhone", first: true, features: with { $0.largerPicture = false })) == [K1, K4, K5], "the Duo's cover: no Larger Picture row")

// A phone held upright: the bar card names row 1's Keyboard, as sideways; the laptop card has no
// keyboard key (that is row 1's button), and Larger Picture's row where the panel offers it.
let barPhone = words(.bar, F, device: "iPhone")
check(texts(barPhone) == texts(words(.bar, L, device: "iPhone")) && texts(barPhone) == [B1, B2, B3on, B4, B5], "a phone's bar card: as sideways, with Keyboard")
check(barPhone.hint == "Under the picture: Aa and Keyboard in the first row, the windows and Menus in the second.", "a phone's bar hint with Menus")
check(words(.bar, F, device: "iPhone", features: with { $0.menus = false }).hint == "Under the picture: Aa and Keyboard in the first row, the windows in the second.",
      "a phone's bar hint without")
check(words(.touch, F, device: "iPhone").hint == "The picture of Mac mini is at the top of the screen.", "a phone's picture hint")
check(words(.settings, F, device: "iPhone").hint == "The last button in the row under the picture."
      && texts(words(.settings, F, device: "iPhone")) == [G1, G2, G3, G4], "a phone's settings card: no upright row")
let laptopPhone = words(.laptop, F, device: "iPhone", first: true)
check(texts(laptopPhone) == [K1, K4, K5, K6], "a phone's laptop card: no keyboard key, Larger Picture's row last: \(texts(laptopPhone))")
check(laptopPhone.rows.map(\.symbol) == ["command", "cursorarrow.click.2", "hand.draw", "rectangle.expand.vertical"], "a phone's laptop symbols")
check(laptopPhone.hint == "Under the windows: the row of keys, then the trackpad." && laptopPhone.subtitle == "Upright, Sill adds keys and a trackpad.",
      "a phone's laptop hint and subtitle")
check(words(.laptop, F, device: "iPhone", voiceOver: true, first: true).rows.map(\.spoken)
      == ["Command, Option, Control and Shift stay on for the next key: Command, then C, copies.", K6], "a phone's laptop card under VoiceOver")
check(words(.laptop, F, device: "iPhone", voiceOver: true, first: true, features: with { $0.largerPicture = false }).rows.map(\.spoken)
      == ["Command, Option, Control and Shift stay on for the next key: Command, then C, copies."], "…and where Larger Picture is not offered")
for f in everyFeatures {
    check(words(.laptop, F, device: "iPhone", features: f).rows.contains { $0.symbol == "rectangle.expand.vertical" } == f.largerPicture,
          "Larger Picture's row only where it is offered: \(f)")
    check(!words(.laptop, P, features: f).rows.contains { $0.symbol == "rectangle.expand.vertical" }, "never in the halves: \(f)")
}

// A phone with Larger Picture: no thumbnails, so the bar card's first row is about Apps, its hint
// names row 1's buttons, and the laptop card's hint says the keys are under the buttons; the rest
// as with the thumbnails.
let barLarger = words(.bar, F, device: "iPhone", thumbnails: false)
check(texts(barLarger) == [B1Apps, B2, B3on, B4, B5], "Larger Picture's bar card: \(texts(barLarger))")
check(barLarger.rows[0].symbol == "magnifyingglass" && barLarger.rows[0].spans.first == TourSpan(text: "Apps", strong: true)
      && barLarger.title == "Windows and Menus" && barLarger.subtitle == nil, "Apps' row: the button's symbol and name")
check(barLarger.hint == "Under the picture, in the row of buttons: Apps, Menus, Aa and Keyboard.", "Larger Picture's bar hint with Menus")
check(words(.bar, F, device: "iPhone", thumbnails: false, features: with { $0.menus = false }).hint == "Under the picture, in the row of buttons: Apps, Aa and Keyboard.",
      "…and without")
check(texts(words(.bar, F, device: "iPhone", voiceOver: true, thumbnails: false)) == [B1AppsVO, B2, B3onVO, B4, B5], "Larger Picture's bar card under VoiceOver")
check(words(.laptop, F, device: "iPhone", first: true, thumbnails: false).hint == "Under the buttons: the row of keys, then the trackpad."
      && texts(words(.laptop, F, device: "iPhone", first: true, thumbnails: false)) == texts(laptopPhone),
      "Larger Picture's laptop card: the keys under the buttons, its rows as before")
check([TourTopic.touch, .sharing, .settings].allSatisfy { words($0, F, device: "iPhone", thumbnails: false) == words($0, F, device: "iPhone") },
      "Larger Picture's other cards as before")
check(texts(words(.bar, F, mac: "Studio", device: "iPhone", thumbnails: false)).first == "Apps lists the apps on Studio: tap an open one again for its next window.",
      "the Mac's name in Apps' row")
check([L, P].allSatisfy { layout in all.allSatisfy { words($0, layout, thumbnails: false) == words($0, layout) } },
      "no thumbnails changes no words sideways or in the halves")

// Under VoiceOver: no touch card, no trackpad rows, and no gesture VoiceOver cannot make.
let barVO = words(.bar, L, voiceOver: true)
check(texts(barVO) == [B1VO, B2, B3onVO, B4, B5], "bar under VoiceOver: \(texts(barVO))")
check(texts(words(.bar, P, voiceOver: true, features: with { $0.virtualDisplay = false })) == [B1VO, B2, B3offVO], "the halves' bar under VoiceOver, Virtual Display off")
check(barVO.rows[2].spans.filter(\.strong).map(\.text) == ["New:", "Virtual Display", "Text size"], "Text size, by its VoiceOver name")
let laptopVO = words(.laptop, P, voiceOver: true, first: true)
check(laptopVO.rows.count == 3 && laptopVO.rows[0].spoken == "Command, Option, Control and Shift stay on for the next key: Command, then C, copies."
      && laptopVO.rows[1].text == K2 && laptopVO.rows[2].text == K3, "laptop under VoiceOver: the keys' rows")

// The rows per card (the plan's §1.5): at most six anywhere, with every feature there.
func counts(_ layout: TourLayout, device: String, voiceOver: Bool = false, features: TourFeatures = allOn) -> [Int] {
    TourPolicy.steps(layout, voiceOver: voiceOver).map { words($0, layout, device: device, voiceOver: voiceOver, features: features).rows.count }
}
check(counts(L, device: "iPad") == [6, 5, 3, 5] && counts(L, device: "iPhone") == [5, 5, 3, 5], "sideways: 6 (5 on iPhone), 5, 3, 5")
check(counts(P, device: "iPad") == [6, 3, 3, 4, 5] && counts(F, device: "iPhone") == [5, 5, 3, 4, 4], "the halves 6, 3, 3, 4, 5; a phone 5, 5, 3, 4, 4")
check(counts(F, device: "iPhone", features: with { $0.largerPicture = false }).last == 3, "the Duo's cover: three on its laptop card")
check(counts(L, device: "iPad", voiceOver: true) == [5, 3, 3] && counts(P, device: "iPad", voiceOver: true) == [3, 3, 2, 3]
      && counts(F, device: "iPhone", voiceOver: true) == [5, 3, 2, 2], "under VoiceOver: bar 5/3/5, sharing 3, settings 3/2/2, laptop 3/2")
var mostRows = 0
for layout in [L, P, F] {
    for voiceOver in [false, true] {
        for device in ["iPad", "iPhone"] {
            for thumbnails in [true, false] {
                for f in everyFeatures {
                    for step in TourPolicy.steps(layout, voiceOver: voiceOver) {
                        mostRows = max(mostRows, words(step, layout, device: device, voiceOver: voiceOver, first: true, thumbnails: thumbnails, features: f).rows.count)
                    }
                }
            }
        }
    }
}
check(mostRows == 6, "at most six rows on any card: \(mostRows)")

// "New:": exactly the rows about what is new since the tour was written (0.6's, and the Menus
// button's, the gestures' and Virtual Display's, in either form, which the old tour never told of),
// first, semibold and marked, then a space, in the words and in what VoiceOver reads; every older
// row carries none.
check(TourPolicy.newPrefix == "New:", "the mark")
func expectedNew(_ row: TourRow, _ f: TourFeatures) -> Bool {
    switch row.symbol {
    case "plus.magnifyingglass", "hand.raised.fingers.spread", "filemenu.and.selection", "display", "keyboard.badge.ellipsis",
         "doc.on.clipboard", "doc.on.doc", "speaker.wave.2", "arrow.down.circle", "arrow.up.arrow.down", "timer",
         "rectangle.expand.vertical": return true
    default: return false
    }
}
var newRows: Set<String> = [], oldRows: Set<String> = []
for layout in [L, P, F] {
    for voiceOver in [false, true] {
        for device in ["iPad", "iPhone"] {
            for thumbnails in [true, false] {
                for onItsSide in [false, true] {
                    for f in everyFeatures {
                        for step in TourPolicy.steps(layout, voiceOver: voiceOver) {
                            let copy = words(step, layout, device: device, voiceOver: voiceOver, first: true, onItsSide: onItsSide, thumbnails: thumbnails, features: f)
                            for row in copy.rows {
                                let label = "\(step) \(layout) \(device) vo \(voiceOver): \(row.text)"
                                if row.isNew {
                                    newRows.insert(row.symbol)
                                    check(row.spans.count >= 3 && row.spans[0] == TourSpan(text: "New:", strong: true, isNew: true)
                                          && row.spans[1] == TourSpan(text: " ", strong: false, isNew: false)
                                          && row.text.hasPrefix("New: ") && row.spoken.hasPrefix("New: ") && !row.text.hasPrefix("New: New:"),
                                          "a New row's mark first, then a space, in its words and VoiceOver's: \(label)")
                                } else {
                                    oldRows.insert(row.symbol)
                                    check(!row.text.hasPrefix("New") && !row.spoken.hasPrefix("New"), "an unmarked row says no New: \(label)")
                                }
                                check(row.isNew == expectedNew(row, f), "New on exactly the new rows: \(label)")
                                check(row.spans.dropFirst().allSatisfy { !$0.isNew }, "only the first span is the mark: \(label)")
                                check(!row.text.lowercased().contains("password") && !row.spoken.lowercased().contains("password"),
                                      "no row speaks of passwords (a password manager's copies go like any other): \(label)")
                                // Aa only in Virtual Display's row, sighted; Text size only there under VoiceOver.
                                check(!row.text.contains("Aa") || (row.symbol == "display" && !voiceOver), "Aa outside the Virtual Display row: \(label)")
                                check(!row.text.contains("Text size") || (row.symbol == "display" && voiceOver), "Text size outside the Virtual Display row: \(label)")
                                if row.symbol == "display" {
                                    check(row.spans.contains(TourSpan(text: voiceOver ? "Text size" : "Aa", strong: true)), "the Virtual Display row names Aa: \(label)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
check(newRows == ["plus.magnifyingglass", "hand.raised.fingers.spread", "filemenu.and.selection", "display", "keyboard.badge.ellipsis",
                  "doc.on.clipboard", "doc.on.doc", "speaker.wave.2", "arrow.down.circle", "arrow.up.arrow.down", "timer",
                  "rectangle.expand.vertical"], "the New rows: T5, T6, B2, B3, B5, S1–S4, G3, G4, K3, K6: \(newRows.sorted())")
check(["keyboard", "hand.tap", "command", "hand.point.up.left", "xmark.circle"].allSatisfy(oldRows.contains) && !oldRows.contains("display"),
      "the Keyboard rows and the old rows unmarked; Virtual Display's never")
check(words(.touch, L).rows.first { $0.symbol == "hand.raised.fingers.spread" }!.isNew && words(.bar, L).rows.first { $0.symbol == "filemenu.and.selection" }!.isNew,
      "the swipe and Menus rows carry New (the old tour never told of them)")
check(words(.bar, L, features: with { $0.virtualDisplay = false }).rows.first { $0.symbol == "display" }!.isNew && words(.bar, L).rows.first { $0.symbol == "display" }!.isNew,
      "Virtual Display's row is New in both forms")
check(T5.hasPrefix("New: ") && texts(touchPad)[4] == T5 && touchPad.rows[4].spoken == T5, "VoiceOver says “New: Pinch to zoom…”")

for layout in [L, P, F] {
    for step in TourPolicy.steps(layout, voiceOver: true) {
        for device in ["iPad", "iPhone"] {
            for thumbnails in [true, false] {
                for f in everyFeatures {
                    for row in words(step, layout, device: device, voiceOver: true, first: true, thumbnails: thumbnails, features: f).rows {
                        let spoken = row.spoken.lowercased()
                        check(!spoken.contains("tap") && !spoken.contains("touch and hold") && !spoken.contains("slide") && !spoken.contains("drag"),
                              "a gesture in a VoiceOver row (\(step), \(layout), thumbnails \(thumbnails), \(f)): \(row.spoken)")
                    }
                }
            }
        }
    }
}
// Every row is read whole, never its symbol's name.
for layout in [L, P, F] {
    for step in TourPolicy.steps(layout, voiceOver: false) {
        for f in everyFeatures {
            for row in words(step, layout, first: true, features: f).rows + words(step, layout, first: true, thumbnails: false, features: f).rows {
                // Read as its words (the key row's caps by name), never with the symbol's name before them.
                check(!row.spoken.isEmpty && !row.spoken.hasPrefix(row.symbol) && !(row.symbol.contains(".") && row.spoken.contains(row.symbol))
                      && (row.spoken == row.text || row.symbol == "command") && row.spoken.hasSuffix("."), "\(step): a row read whole: \(row.spoken)")
            }
        }
    }
}
// MARK: - Larger Picture only while a window streams (Noah, 2026-10-15)
//
// "When in Desktop mode, there is negative space on the bottom": the Desktop, which Aa never resizes,
// and nothing streaming keep the standard arrangement with the switch on. The tour sees what
// StreamScreen hands it: Larger Picture's rule (PhonePortraitLayout.largerPicture(switchOn:streaming:))
// placed by keyboard(for:largerPicture:foldable:), the targets, the room and the thumbnails from that.
// With the switch on, the Desktop's and nothing's tour is the switch off's (the strip lit, its words,
// every card where it was); a window's is Larger Picture's (Apps lit, the room).
func streamScreen(_ w: CGFloat, _ h: CGFloat, switchOn: Bool, streaming: PhonePortraitLayout.Streaming, video: CGSize = macBook,
                  hinge: Bool = false) -> Screen {
    let size = CGSize(width: w, height: h)
    let keyboard = PhonePortraitLayout.keyboard(for: size, largerPicture: PhonePortraitLayout.largerPicture(switchOn: switchOn, streaming: streaming),
                                                foldable: hinge)
    return keyboard.map { largerModel(w, h, keyboard: $0, video: video) } ?? phoneModel(w, h)
}
func same(_ a: Screen, _ b: Screen) -> Bool {
    a.size == b.size && a.layout == b.layout && a.stream == b.stream && a.targets == b.targets && a.room == b.room && a.thumbnails == b.thumbnails
}
/// Every card of the layout, by its words and its place at a few heights, as the tour shows them on `s`.
func tourOf(_ s: Screen, voiceOver: Bool = false) -> [String] {
    let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: false)
    return TourPolicy.steps(s.layout, voiceOver: voiceOver).flatMap { topic -> [String] in
        let copy = words(topic, s.layout, device: "iPhone", voiceOver: voiceOver, first: true, thumbnails: s.thumbnails)
        let lit = TourPolicy.targets(topic, s.layout, thumbnails: s.thumbnails).compactMap { s.targets[$0] }.map { "\($0)" }
        let places = [CGFloat(120), 230, 380].map { "\(place(s, topic, height: $0, width: w))" }
        return ["\(topic)", copy.title, copy.hint, copy.subtitle ?? ""] + texts(copy) + lit + places
    }
}
let uprightPhones: [(String, CGFloat, CGFloat)] = [("18 Pro Max", 440, 894), ("15 Pro", 393, 793), ("18 Pro", 402, 812),
                                                   ("17e", 390, 797), ("13 mini", 375, 762), ("SE", 375, 647)]
for (name, w, h) in uprightPhones {
    let off = phoneModel(w, h)
    for streaming in [PhonePortraitLayout.Streaming.desktop, .nothing] {
        let what = streaming == .desktop ? "the Desktop" : "nothing"
        for video in [macBook, CGSize.zero, CGSize(width: 1512, height: 949)] {
            let on = streamScreen(w, h, switchOn: true, streaming: streaming, video: video)
            check(same(on, off) && on.thumbnails && on.room == nil && on.stream == off.stream,
                  "\(name) (\(Int(w))×\(Int(h))), the switch on while \(what) streams (a \(Int(video.width))×\(Int(video.height)) picture): the switch off's screen, the strip and no room")
            check(tourOf(on) == tourOf(off) && tourOf(on, voiceOver: true) == tourOf(off, voiceOver: true),
                  "\(name), the switch on while \(what) streams: the tour is the switch off's, every card's words, lights and places (under VoiceOver too)")
        }
        check(TourPolicy.targets(.bar, F, thumbnails: streamScreen(w, h, switchOn: true, streaming: streaming).thumbnails) == [.strip, .menus, .textSize, .keyboard],
              "\(name), the switch on while \(what) streams: the bar card lights the thumbnails, Menus, Aa and Keyboard")
    }
    let keyboard = PhonePortraitLayout.keyboardHeight(for: CGSize(width: w, height: h))
    for video in [macBook, CGSize(width: 848, height: 844)] {
        let window = streamScreen(w, h, switchOn: true, streaming: .window, video: video)
        let larger = largerModel(w, h, keyboard: keyboard, video: video)
        check(same(window, larger) && !window.thumbnails && window.room != nil && tourOf(window) == tourOf(larger),
              "\(name), the switch on while a window streams: Larger Picture's tour as before (Apps lit, the cards against the room)")
    }
    check(TourPolicy.targets(.bar, F, thumbnails: streamScreen(w, h, switchOn: true, streaming: .window).thumbnails) == [.apps, .menus, .textSize, .keyboard]
            && tourOf(streamScreen(w, h, switchOn: true, streaming: .window)) != tourOf(off),
          "\(name), a window: the bar card lights Apps, Menus, Aa and Keyboard, so the tour differs from the Desktop's")
    check(tourOf(off).contains("sharing") && tourOf(off).contains("Clipboard and Sound"), "\(name): the tour has the clipboard's and the sound's card")
    check(PhonePortraitLayout.Streaming.allCases.allSatisfy { same(streamScreen(w, h, switchOn: false, streaming: $0), off) },
          "\(name), the switch off: the standard tour whatever streams")
}
check(PhonePortraitLayout.Streaming.allCases.allSatisfy { same(streamScreen(382, 678, switchOn: true, streaming: $0, hinge: true), phoneModel(382, 678)) },
      "the iPhone Duo's cover (a hinge): the standard tour whatever streams, the switch on or off")
// Noah's 15 Pro with the Desktop: the branch's bar card stood in the black under the Desktop's
// 377×244 with its tail at row 1; now it is the standard arrangement's, its tail on the thumbnails.
do {
    let branch = largerModel(393, 793, keyboard: 301, video: macBook), now = streamScreen(393, 793, switchOn: true, streaming: .desktop)
    let w = TourPolicy.width(screen: now.size, layout: F, accessibilityText: false)
    check(branch.stream.size == CGSize(width: 377, height: 244) && branch.room!.size == CGSize(width: 377, height: 340)
            && now.stream.size == CGSize(width: 377, height: 235) && now.room == nil
            && place(now, .bar, height: 230, width: w) == place(phoneModel(393, 793), .bar, height: 230, width: w)
            && place(now, .bar, height: 230, width: w) != place(branch, .bar, height: 230, width: w),
          "the 15 Pro with the Desktop: the 16:10 pane (377×235), the bar card the switch off's, not in the black under a 377×244 Desktop")
}

check(TourPolicy.spokenTitle(barL, index: 1, count: 4) == "Windows and Menus, step 2 of 4", "VoiceOver hears the count")
check(TourPolicy.spokenTitle(sharingL, index: 2, count: 5) == "Clipboard and Sound, step 3 of 5", "…on the new card too")
check(TourPolicy.spokenTitle(laptopFirst, index: 0, count: 1) == "Keys and Trackpad", "a one-card run has no count")
check(TourPolicy.skipTitle == "Skip" && TourPolicy.nextTitle == "Next" && TourPolicy.doneTitle == "Done", "the buttons")
check(TourPolicy.skipHint == "Ends the tour. Take the Tour in Settings shows it again.", "Skip's hint")
check(TourPolicy.takeTourTitle == "Take the Tour", "the Settings row")
check(TourPolicy.takeTourFootnote(device: "iPad") == "A short tour of Sill’s controls on this iPad.", "its footnote")
check(TourPolicy.takeTourHint(device: "iPhone") == "Shows how to use Sill on this iPhone.", "its hint")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
