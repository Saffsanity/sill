import Foundation
import CoreGraphics
// H2 of docs/first-run-walkthrough-plan.md: TourPolicy (iOSClient/TourPolicy.swift) on its own. The
// steps and targets per layout, what is owed, the rule of the automatic tour at every boundary,
// memory, runs, a rotation mid-run, the crease, the card's width and place (pinned at the Duo's four
// sizes and the iPhone SE's two, against an oracle written from the plan's words, and properties
// over a grid of screens and card heights), and every string. Compiled with the file as it is:
//   swiftc -O iOSClient/TourPolicy.swift Tests/checks/tour/main.swift -o .build/checks/tour/check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

let L = TourLayout.landscape, P = TourLayout.portrait
let all: [TourTopic] = [.touch, .bar, .settings, .laptop]

// MARK: - Steps and targets

check(TourTopic.allCases == all, "the tour's order")
check(TourTopic.touch < .bar && TourTopic.bar < .settings && TourTopic.settings < .laptop && !(TourTopic.laptop < .touch), "Comparable follows the order")
check(TourPolicy.steps(L, voiceOver: false) == [.touch, .bar, .settings], "landscape: three cards")
check(TourPolicy.steps(P, voiceOver: false) == [.touch, .bar, .settings, .laptop], "portrait: four cards")
check(TourPolicy.steps(L, voiceOver: true) == [.bar, .settings], "landscape under VoiceOver: no touch")
check(TourPolicy.steps(P, voiceOver: true) == [.bar, .settings, .laptop], "portrait under VoiceOver: no touch, laptop kept")
check(TourPolicy.only(P) == [.laptop] && TourPolicy.only(L) == [], "only(): the laptop half is portrait's alone")
check(TourPolicy.targets(.touch, L) == [.stream] && TourPolicy.targets(.touch, P) == [.stream], "touch lights the picture")
check(TourPolicy.targets(.bar, L) == [.strip, .textSize, .keyboard], "landscape bar: the strip, Aa and Keyboard")
check(TourPolicy.targets(.bar, P) == [.strip, .textSize], "portrait bar: the strip and Aa (the keyboard is a cap)")
check(TourPolicy.targets(.settings, L) == [.settings] && TourPolicy.targets(.settings, P) == [.settings], "settings lights its button")
check(TourPolicy.targets(.laptop, P) == [.keys, .trackpad], "laptop: the keys, then the trackpad")
check(TourTarget.allCases.count == 7, "seven targets")

// MARK: - Memory and what is owed

let fresh = TourMemory()
let sideways = TourMemory(seen: [.touch, .bar, .settings])
let everything = TourMemory(seen: Set(all))
let skipped = TourMemory(skipped: true)
check(TourPolicy.owed(L, voiceOver: false, fresh) == [.touch, .bar, .settings], "fresh, landscape")
check(TourPolicy.owed(P, voiceOver: false, fresh) == all, "fresh, portrait")
check(TourPolicy.owed(P, voiceOver: false, sideways) == [.laptop], "a tour taken sideways leaves laptop owed")
check(TourPolicy.owed(L, voiceOver: false, sideways) == [], "nothing new sideways after it")
check(TourPolicy.owed(P, voiceOver: false, everything) == [] && TourPolicy.owed(L, voiceOver: false, everything) == [], "all seen")
check(TourPolicy.owed(P, voiceOver: false, skipped) == [] && TourPolicy.owed(L, voiceOver: true, skipped) == [], "skipped: nothing, ever")
check(TourPolicy.owed(L, voiceOver: false, TourMemory(seen: [.touch])) == [.bar, .settings], "a session that ended after touch")
check(TourPolicy.owed(P, voiceOver: true, fresh) == [.bar, .settings, .laptop], "VoiceOver: touch not owed here")
check(TourPolicy.owed(L, voiceOver: false, TourMemory(seen: [.bar, .settings])) == [.touch], "touch stays owed after a VoiceOver tour")
check(TourMemory(names: ["touch", "settings", "gestures", ""], skipped: false) == TourMemory(seen: [.touch, .settings]), "unknown names ignored")
check(TourMemory(seen: [.laptop, .touch, .settings]).names == ["touch", "settings", "laptop"], "saved in the tour's order")
check(TourMemory(names: [], skipped: true).skipped && TourMemory(names: [], skipped: true).seen.isEmpty, "skipped read back")
check(TourPolicy.passed(.bar, fresh) == TourMemory(seen: [.bar]), "Next saves the step it leaves")
check(TourPolicy.passed(.bar, TourMemory(seen: [.bar])) == TourMemory(seen: [.bar]), "passing again changes nothing")
check(TourPolicy.passed(.laptop, sideways) == everything, "the upright card completes it")
check(TourPolicy.skipped(sideways) == TourMemory(seen: [.touch, .bar, .settings], skipped: true), "Skip keeps what was seen")
check(!TourPolicy.skipped(fresh).seen.contains(.touch) && TourPolicy.skipped(fresh).skipped, "Skip saves no step")
// Skip in the automatic tour turns it off; in Take the Tour it only closes the run.
let automaticRun = TourRun(steps: [.touch, .bar, .settings], at: .touch, replay: false)
let replayRun = TourRun(steps: [.touch, .bar, .settings], at: .touch, replay: true)
check(TourPolicy.skip(automaticRun, fresh) == TourMemory(skipped: true), "Skip in the automatic tour: off for good")
check(TourPolicy.skip(automaticRun, sideways) == TourMemory(seen: [.touch, .bar, .settings], skipped: true), "…keeping what was seen")
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
check(decide(moment(now: 11.0)) == .show([.touch, .bar, .settings]), "1.0 s: the tour")
check(decide(moment(now: 11.0), P) == .show(all), "portrait: all four")
check(decide(moment(now: 30)) == .show([.touch, .bar, .settings]), "a late look at a quiet session still shows it")
check(decide(moment(now: 11, activity: 9.99)) == .show([.touch, .bar, .settings]), "a touch before the picture does not count")
check(decide(moment(now: 11, activity: 10)) == .pass(.used), "a touch at the picture counts")
check(decide(moment(now: 10.5, activity: 10.4)) == .pass(.used), "used during the beat: not this session, at once")
check(decide(moment(now: 11, down: 1)) == .pass(.busy), "a touch still down")
check(decide(moment(now: 10.5, down: 1)) == .wait(until: 11), "a touch down is judged at the decision, not before")
check(decide(moment(now: 11, busy: true)) == .pass(.busy), "something open")
check(decide(moment(now: 11), L, sideways) == .pass(.nothingOwed), "seen: nothing owed")
check(decide(moment(now: 11), L, skipped) == .pass(.nothingOwed), "skipped: nothing owed")
check(decide(moment(now: 11), L, skipped) == decide(moment(now: 11, enabled: false), L, fresh), "skipped as good as off")
check(decide(moment(now: 11), P, sideways) == .show([.laptop]), "a later session upright: the laptop card")
check(decide(moment(now: 11, voiceOver: true)) == .show([.bar, .settings]), "VoiceOver: without touch")
check(decide(moment(now: 11, voiceOver: true), L, TourMemory(seen: [.bar, .settings])) == .pass(.nothingOwed), "VoiceOver: touch never owed there")
// A rotation during the beat starts it again, with every step owed in the new layout.
check(decide(moment(now: 11, layoutAt: 10.6), P) == .wait(until: 11.6), "turned in the beat: a beat from the turn")
check(decide(moment(now: 11.6, layoutAt: 10.6), P) == .show(all), "then all four")
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

// MARK: - Runs

let replayL = TourPolicy.replay(L, voiceOver: false)!
check(replayL == TourRun(steps: [.touch, .bar, .settings], at: .touch, replay: true), "Take the Tour sideways")
check(TourPolicy.replay(P, voiceOver: false, from: .settings) == TourRun(steps: all, at: .settings, replay: true), "-SillTour settings upright")
check(TourPolicy.replay(L, voiceOver: false, from: .laptop)?.at == .touch, "a step the layout lacks starts at the first")
check(TourPolicy.replay(L, voiceOver: true, from: .touch)?.at == .bar, "under VoiceOver touch is not there")
check(TourPolicy.replay(P, voiceOver: true)?.steps == [.bar, .settings, .laptop], "Take the Tour under VoiceOver")
check(TourPolicy.run(owed: []) == nil, "nothing owed: no run")
check(TourPolicy.run(owed: [.settings]) == TourRun(steps: [.settings], at: .settings, replay: false), "one card owed")
let r2 = TourPolicy.next(replayL)!
check(r2.at == .bar && r2.passed == [.touch] && r2.index == 1 && r2.count == 3, "Next: the second card")
let r3 = TourPolicy.next(r2)!
check(r3.at == .settings && r3.isLast && r3.passed == [.touch, .bar], "the last card")
check(TourPolicy.next(r3) == nil, "Done ends it")
check(!replayL.isLast && replayL.firstOfRun && !r2.firstOfRun, "first and last")
// A session that ends mid-tour: steps passed stay passed; the next session starts at the first owed.
var memory = fresh
var walk = TourPolicy.run(owed: TourPolicy.owed(L, voiceOver: false, memory))!
memory = TourPolicy.passed(walk.at, memory); walk = TourPolicy.next(walk)!
memory = TourPolicy.passed(walk.at, memory); walk = TourPolicy.next(walk)!
check(walk.at == .settings && memory.seen == [.touch, .bar], "two passed, the Mac quits at the third")
check(TourPolicy.run(owed: TourPolicy.owed(L, voiceOver: false, memory)) == TourRun(steps: [.settings], at: .settings, replay: false), "the next session: settings alone")
check(TourPolicy.run(owed: TourPolicy.owed(P, voiceOver: false, memory))?.steps == [.settings, .laptop], "or upright: settings, then laptop")

// A rotation mid-run: every step both ways, with and without VoiceOver, replay and automatic.
func run(_ steps: [TourTopic], at: TourTopic, passed: Set<TourTopic> = [], replay: Bool = false) -> TourRun {
    TourRun(steps: steps, at: at, passed: passed, replay: replay)
}
let autoL = run([.touch, .bar, .settings], at: .touch)
check(TourPolicy.carry(autoL, to: P, voiceOver: false, memory: fresh) == run(all, at: .touch), "touch, landscape → portrait: 1 of 4")
check(TourPolicy.carry(run([.touch, .bar, .settings], at: .bar, passed: [.touch]), to: P, voiceOver: false, memory: TourMemory(seen: [.touch]))
      == run(all, at: .bar, passed: [.touch]), "bar → portrait: 2 of 4, the count goes on")
check(TourPolicy.carry(run([.touch, .bar, .settings], at: .settings, passed: [.touch, .bar]), to: P, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run(all, at: .settings, passed: [.touch, .bar]), "settings → portrait: 3 of 4, laptop after it")
check(TourPolicy.carry(run(all, at: .touch), to: L, voiceOver: false, memory: fresh) == run([.touch, .bar, .settings], at: .touch), "touch, portrait → landscape")
check(TourPolicy.carry(run(all, at: .bar, passed: [.touch]), to: L, voiceOver: false, memory: TourMemory(seen: [.touch]))
      == run([.touch, .bar, .settings], at: .bar, passed: [.touch]), "bar, portrait → landscape")
check(TourPolicy.carry(run(all, at: .settings, passed: [.touch, .bar]), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run([.touch, .bar, .settings], at: .settings, passed: [.touch, .bar]), "settings, portrait → landscape: now the last")
check(TourPolicy.carry(run(all, at: .laptop, passed: [.touch, .bar, .settings]), to: L, voiceOver: false, memory: sideways) == nil,
      "laptop turned sideways: nothing left, the tour ends")
check(TourPolicy.carry(run([.laptop], at: .laptop), to: L, voiceOver: false, memory: fresh) == nil,
      "the turn's laptop card turned back: ends, nothing owed there counts after it")
check(TourPolicy.carry(run(all, at: .laptop, replay: true), to: L, voiceOver: false, memory: fresh) == nil,
      "-SillTour laptop turned sideways: nothing after laptop, it ends (not back to touch)")
check(TourPolicy.carry(run([.settings, .laptop], at: .settings), to: L, voiceOver: false, memory: TourMemory(seen: [.touch, .bar]))
      == run([.settings], at: .settings), "an owed run sideways keeps only what is owed there")
check(TourPolicy.carry(run([.touch, .bar, .settings], at: .bar, passed: [.touch], replay: true), to: P, voiceOver: false, memory: everything)
      == run(all, at: .bar, passed: [.touch], replay: true), "Take the Tour: every step of the new layout, whatever was seen")
check(TourPolicy.carry(run([.touch, .bar, .settings], at: .touch), to: L, voiceOver: true, memory: fresh) == run([.bar, .settings], at: .bar),
      "VoiceOver on during touch: on to the next step, bar")
check(TourPolicy.carry(run([.bar, .settings, .laptop], at: .laptop, passed: [.bar, .settings]), to: L, voiceOver: true, memory: TourMemory(seen: [.bar, .settings])) == nil,
      "VoiceOver, laptop turned sideways: ends")
check(TourPolicy.carry(run([.bar, .settings], at: .bar, replay: true), to: P, voiceOver: true, memory: fresh) == run([.bar, .settings, .laptop], at: .bar, replay: true),
      "VoiceOver replay turned upright")
for layout in [L, P] {
    for voiceOver in [false, true] {
        for step in TourPolicy.steps(layout, voiceOver: voiceOver) {
            let before = TourPolicy.replay(layout, voiceOver: voiceOver, from: step)!
            let other: TourLayout = layout == L ? P : L
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
check(TourPolicy.radius(.touch) == 16 && TourPolicy.radius(.bar) == 20 && TourPolicy.radius(.settings) == 20 && TourPolicy.radius(.laptop) == 20, "radii")

// MARK: - The layouts' targets, as the stream screen reports them (BarMetrics, PortraitMetrics)

struct Screen {
    let size: CGSize
    let layout: TourLayout
    let stream: CGRect
    let targets: [TourTarget: CGRect]
    func union(_ topic: TourTopic) -> CGRect? {
        let rects = TourPolicy.targets(topic, layout).compactMap { targets[$0] }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}
/// The stream screen at a size: DuoLayout's choice and the frames each target reports. The strip is
/// reported as its thumbnails' band with their halo (5 pt) above and badge (6 pt) below.
func model(_ w: CGFloat, _ h: CGFloat) -> Screen {
    let size = CGSize(width: w, height: h)
    if h > w && w < 600 || !(w > h) {
        let regular = !(h > w && w < 600)
        let half = (h / 2).rounded()
        let (padTop, padSide, padBottom, gap, barH, bw, bh, thumbPad, capH, split): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool) =
            regular ? (12, 14, 22, 10, 78, 64, 58, 10, 48, false) : (10, 14, 16, 10, 62, 56, 50, 6, 44, true)
        let barY = half + padTop
        let settingsX = w - padSide - bw
        let aaX = settingsX - 2 * (12 + bw)
        let stripX = padSide + bw + 12
        let by = barY + (barH - bh) / 2
        let keysY = barY + barH + gap
        let keysH = split ? capH * 2 + 8 : capH
        let padY = keysY + keysH + gap
        return Screen(size: size, layout: P, stream: CGRect(x: 8, y: 8, width: w - 16, height: half - 16), targets: [
            .stream: CGRect(x: 8, y: 8, width: w - 16, height: half - 16),
            .strip: CGRect(x: stripX, y: barY + thumbPad - 5, width: aaX - 12 - stripX, height: barH - (thumbPad - 5) - (thumbPad - 6)),
            .textSize: CGRect(x: aaX, y: by, width: bw, height: bh),
            .settings: CGRect(x: settingsX, y: by, width: bw, height: bh),
            .keys: CGRect(x: padSide, y: keysY, width: w - 2 * padSide, height: keysH),
            .trackpad: CGRect(x: padSide, y: padY, width: w - 2 * padSide, height: h - padBottom - padY)])
    }
    let compact = h < 560
    let (barH, pad, bw, bh): (CGFloat, CGFloat, CGFloat, CGFloat) = compact ? (78, 14, 64, 58) : (86, 22, 66, 66)
    let settingsX = w - pad - bw
    let keyboardX = settingsX - 2 * (12 + bw)
    let aaX = keyboardX - 12 - bw
    let stripX = pad + bw + 12
    let by = (barH - bh) / 2
    let stream = CGRect(x: 8, y: barH + 8, width: w - 16, height: h - barH - 16)
    return Screen(size: size, layout: L, stream: stream, targets: [
        .stream: stream,
        .strip: CGRect(x: stripX, y: 5, width: aaX - 12 - stripX, height: barH - 9),
        .textSize: CGRect(x: aaX, y: by, width: bw, height: bh),
        .keyboard: CGRect(x: keyboardX, y: by, width: bw, height: bh),
        .settings: CGRect(x: settingsX, y: by, width: bw, height: bh)])
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

// MARK: - Where the card goes: an oracle from the plan's words

/// §6.3 in its own words, to hold `place` to them.
func oracle(_ s: Screen, _ topic: TourTopic, height h: CGFloat, width w: CGFloat, inset: CGFloat = 0) -> TourPlacement {
    let top: CGFloat = 16, bottom = s.size.height - 16 - inset
    let crease: CGFloat? = topHalf(s.size) ? (s.size.height / 2).rounded() : nil
    func centred(_ mid: CGFloat) -> CGFloat { max(16, min(mid - w / 2, s.size.width - 16 - w)) }
    let halfBottom = min(s.stream.maxY - 12, (crease ?? 10_000) - 16)
    if topic == .touch {
        let lowest = s.layout == L ? bottom : halfBottom
        if h <= lowest - top { return TourPlacement(card: CGRect(x: centred(s.stream.midX), y: max(top, min(s.stream.midY - h / 2, lowest - h)), width: w, height: h), tail: nil) }
        let reach = s.layout == P && crease == nil ? bottom : lowest
        return TourPlacement(card: CGRect(x: centred(s.stream.midX), y: top, width: w, height: min(h, reach - top)), tail: nil)
    }
    let t = s.union(topic)!
    let x = centred(t.midX)
    let tip = max(x + 28, min(t.midX, x + w - 28))
    if s.layout == L {
        if t.maxY + 12 + h <= bottom { return TourPlacement(card: CGRect(x: x, y: t.maxY + 12, width: w, height: h), tail: TourTail(edge: .up, x: tip)) }
        let y = max(top, bottom - h)
        return TourPlacement(card: CGRect(x: x, y: y, width: w, height: min(h, bottom - y)), tail: nil)
    }
    if halfBottom - h >= top {
        let near = t.minY - halfBottom <= 48 && t.minY >= halfBottom
        let across = crease.map { halfBottom <= $0 && $0 <= t.minY } ?? false
        return TourPlacement(card: CGRect(x: x, y: halfBottom - h, width: w, height: h), tail: near && !across ? TourTail(edge: .down, x: tip) : nil)
    }
    return TourPlacement(card: CGRect(x: x, y: top, width: w, height: min(h, (crease == nil ? bottom : halfBottom) - top)), tail: nil)
}
func place(_ s: Screen, _ topic: TourTopic, height h: CGFloat, width w: CGFloat, inset: CGFloat = 0) -> TourPlacement {
    TourPolicy.place(card: CGSize(width: w, height: h), targets: s.union(topic), isStream: topic == .touch, screen: s.size,
                     layout: s.layout, stream: s.stream, bottomInset: inset)
}
func pinned(_ s: Screen, _ topic: TourTopic, _ h: CGFloat, _ expected: CGRect, tail: TourTail?, line: Int = #line) {
    let w = TourPolicy.width(screen: s.size, layout: s.layout, accessibilityText: false)
    let p = place(s, topic, height: h, width: w)
    check(p == TourPlacement(card: expected, tail: tail), "\(s.size) \(topic) h \(h): \(p.card) tail \(String(describing: p.tail)), expected \(expected) \(String(describing: tail))", line: line)
    check(p == oracle(s, topic, height: h, width: w), "\(s.size) \(topic) h \(h) against the oracle", line: line)
}
// 1000×710, the Duo flat: 360 pt; the bar's card 12 pt under the strip's band (82), tail up.
pinned(duoInner, .touch, 262, CGRect(x: 320, y: 267, width: 360, height: 262), tail: nil)
pinned(duoInner, .bar, 230, CGRect(x: 281, y: 94, width: 360, height: 230), tail: TourTail(edge: .up, x: 461))
pinned(duoInner, .settings, 200, CGRect(x: 624, y: 88, width: 360, height: 200), tail: TourTail(edge: .up, x: 945))
pinned(duoInner, .bar, 640, CGRect(x: 281, y: 54, width: 360, height: 640), tail: nil)      // grows over the bar
pinned(duoInner, .touch, 900, CGRect(x: 320, y: 16, width: 360, height: 678), tail: nil)    // the screen less its margins: scrolls
// 710×500, the outer display on its side: 480 pt wide, below the compact bar (74).
pinned(duoOuter, .touch, 230, CGRect(x: 115, y: 174, width: 480, height: 230), tail: nil)
pinned(duoOuter, .bar, 230, CGRect(x: 77, y: 86, width: 480, height: 230), tail: TourTail(edge: .up, x: 317))
pinned(duoOuter, .settings, 230, CGRect(x: 214, y: 80, width: 480, height: 230), tail: TourTail(edge: .up, x: 664))
pinned(duoOuter, .settings, 420, CGRect(x: 214, y: 64, width: 480, height: 420), tail: nil)
pinned(duoOuter, .bar, 520, CGRect(x: 77, y: 16, width: 480, height: 468), tail: nil)
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
pinned(duoOuterUp, .bar, 800, CGRect(x: 36, y: 16, width: 360, height: 678), tail: nil)
// 667×375, the iPhone SE sideways: 480 pt wide; the bar card fits under the bar at 230.
pinned(seSide, .touch, 200, CGRect(x: 93.5, y: 126.5, width: 480, height: 200), tail: nil)
pinned(seSide, .bar, 230, CGRect(x: 55.5, y: 86, width: 480, height: 230), tail: TourTail(edge: .up, x: 295.5))
pinned(seSide, .settings, 230, CGRect(x: 171, y: 80, width: 480, height: 230), tail: TourTail(edge: .up, x: 621))
pinned(seSide, .bar, 300, CGRect(x: 55.5, y: 59, width: 480, height: 300), tail: nil)
pinned(seSide, .settings, 500, CGRect(x: 171, y: 16, width: 480, height: 343), tail: nil)
// 375×667, the iPhone SE upright: 343 pt, down to the window bar; laptop grows over it.
pinned(seUp, .touch, 262, CGRect(x: 16, y: 36, width: 343, height: 262), tail: nil)
pinned(seUp, .bar, 230, CGRect(x: 16, y: 84, width: 343, height: 230), tail: TourTail(edge: .down, x: 153.5))
pinned(seUp, .settings, 200, CGRect(x: 16, y: 114, width: 343, height: 200), tail: TourTail(edge: .down, x: 331))
pinned(seUp, .laptop, 330, CGRect(x: 16, y: 16, width: 343, height: 330), tail: nil)
pinned(seUp, .laptop, 700, CGRect(x: 16, y: 16, width: 343, height: 635), tail: nil)
// The home indicator's inset is the bottom margin's floor.
let phoneSide = model(832, 440)
let insetPlaced = place(phoneSide, .bar, height: 330, width: 480, inset: 20)
check(insetPlaced == TourPlacement(card: CGRect(x: 138, y: 74, width: 480, height: 330), tail: nil), "832×440 less 20: the card grows up, above the home indicator: \(insetPlaced)")
check(place(phoneSide, .bar, height: 300, width: 480, inset: 20).tail != nil, "and one that fits keeps its tail")
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
for w0 in widths {
    for h0 in heights {
        let s = model(w0, h0)
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
                            if s.layout == P && (tail.edge != .down || t.minY - c.maxY > 48 || t.minY < c.maxY) { check(false, "\(label): a portrait tail too far"); continue }
                        }
                        if topic != .touch && s.layout == L {
                            let fits = t.maxY + 12 + h <= bottom
                            // Beside its targets whenever it fits there, never above them.
                            if fits && (c.minY != t.maxY + 12 || p.tail == nil) { check(false, "\(label): fits below, placed at \(c)"); continue }
                            // Else it grows toward the top, over its targets only then.
                            if !fits && (c.maxY != bottom || p.tail != nil) { check(false, "\(label): grew wrongly to \(c)"); continue }
                            if c.intersects(lit) && fits { check(false, "\(label): over its targets while it fits"); continue }
                        }
                        if topic != .touch && s.layout == P {
                            let halfBottom = min(s.stream.maxY - 12, (crease ?? 10_000) - 16)
                            // In the picture's half while it fits; over the laptop half only without a crease.
                            if h <= halfBottom - 16 && c.maxY != halfBottom { check(false, "\(label): not at the picture's bottom"); continue }
                            if c.maxY > halfBottom + 0.001 && crease != nil { check(false, "\(label): past the picture's half with a crease"); continue }
                            if h > halfBottom - 16 && c.minY != 16 { check(false, "\(label): grew, but not from the top"); continue }
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
}
check(grid >= 400, "the grid covers \(grid) placements")

// MARK: - The words

func words(_ t: TourTopic, _ layout: TourLayout, mac: String = "Mac mini", device: String = "iPad", voiceOver: Bool = false,
           first: Bool = false) -> TourCopy {
    TourPolicy.copy(t, layout, mac: mac, device: device, voiceOver: voiceOver, firstOfRun: first)
}
func texts(_ c: TourCopy) -> [String] { c.rows.map(\.text) }
let touchPad = words(.touch, L, first: true)
check(touchPad.title == "Tap, Hold and Drag" && touchPad.subtitle == "What you do here happens on Mac mini.", "touch: title and subtitle")
check(texts(touchPad) == ["Tap to click.", "Touch and hold to right-click.", "Drag to scroll.", "Apple Pencil works as a mouse."], "touch on iPad: \(texts(touchPad))")
check(touchPad.rows.map(\.symbol) == ["hand.tap", "contextualmenu.and.cursorarrow", "hand.draw", "applepencil"], "touch's symbols")
check(touchPad.rows[0].spans == [TourSpan(text: "Tap", strong: true), TourSpan(text: " to click.", strong: false)], "the control's name semibold")
check(touchPad.hint == "The picture of Mac mini fills the screen below the bar.", "touch's hint sideways")
check(words(.touch, P).hint == "The picture of Mac mini fills the top half of the screen.", "touch's hint upright")
check(texts(words(.touch, L, device: "iPhone")) == ["Tap to click.", "Touch and hold to right-click.", "Drag to scroll."], "no Pencil row on iPhone")
check(words(.touch, L, mac: "").subtitle == "What you do here happens on your Mac." && words(.touch, P, mac: "").hint == "The picture of your Mac fills the top half of the screen.",
      "the “your Mac” fallback")
let barL = words(.bar, L)
check(barL.title == "Windows and Text Size" && barL.subtitle == nil, "bar: title, no subtitle")
check(texts(barL) == ["Touch and hold a window to close, minimize or go full screen. Keep holding and drag to move it.",
                      "Aa: touch it and slide to make text larger or smaller.",
                      "Keyboard types on Mac mini, on screen or with a hardware keyboard."], "bar sideways: \(texts(barL))")
check(barL.rows.map(\.symbol) == ["hand.point.up.left", "textformat.size", "keyboard"], "bar's symbols")
check(texts(words(.bar, P)) == Array(texts(barL).prefix(2)), "bar upright: no Keyboard row (it is a cap)")
check(barL.hint == "In the bar at the top, after Apps." && words(.bar, P).hint == "In the bar below the picture, after Apps.", "bar's hints")
check(texts(words(.bar, L, mac: "Studio")).last == "Keyboard types on Studio, on screen or with a hardware keyboard.", "the Mac's name in the Keyboard row")
let settingsL = words(.settings, L)
check(settingsL.title == "Settings" && settingsL.subtitle == nil && settingsL.hint == "The last button in the bar.", "settings: title, hint")
check(texts(settingsL) == ["Disconnect is at the bottom of Settings.", "Take the Tour is there too, to see this again.",
                           "Hold your iPad upright for a trackpad and keys."], "settings sideways on iPad")
check(settingsL.rows.map(\.symbol) == ["xmark.circle", "questionmark.circle", "ipad"], "settings' symbols on iPad")
check(texts(words(.settings, L, device: "iPhone")).last == "Hold your iPhone upright for a trackpad and keys."
      && words(.settings, L, device: "iPhone").rows.last?.symbol == "iphone", "the upright row on iPhone")
check(texts(words(.settings, P)) == Array(texts(settingsL).prefix(2)), "no upright row when upright")
let laptopFirst = words(.laptop, P, first: true)
check(laptopFirst.title == "Keys and Trackpad" && laptopFirst.subtitle == "Upright, Sill adds keys and a trackpad.", "laptop as a run's first card")
check(words(.laptop, P, first: false).subtitle == nil, "laptop's subtitle only as a run's first")
check(texts(laptopFirst) == ["cmd, opt, ctrl and shift stay on for the next key or trackpad click: tap cmd, then C, to copy.",
                             "The keyboard key types on Mac mini, on screen or with a hardware keyboard.",
                             "Tap with two fingers on the trackpad to right-click.",
                             "Touch and hold the trackpad, then drag, to move a window or select text."], "laptop: \(texts(laptopFirst))")
check(laptopFirst.rows[0].spoken == "Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.", "the caps spoken by name")
check(laptopFirst.rows[3].spans.filter(\.strong).map(\.text) == ["Touch and hold", "then drag"], "two names in the drag row")
check(laptopFirst.rows.map(\.symbol) == ["command", "keyboard", "cursorarrow.click.2", "hand.draw"], "laptop's symbols")
check(laptopFirst.hint == "Below the bar: the row of keys, then the trackpad.", "laptop's hint")
check(touchPad.rows[1].spoken == "Touch and hold to right-click.", "a row is spoken as it reads")
// Under VoiceOver: no touch card, no trackpad rows, and no gesture VoiceOver cannot make.
let barVO = words(.bar, L, voiceOver: true)
check(texts(barVO) == ["Each window has actions: close, minimize, full screen, and move left or right. Swipe up or down to hear them.",
                       "Text size makes the text on Mac mini larger or smaller. Swipe up or down on it.",
                       "Keyboard types on Mac mini, on screen or with a hardware keyboard."], "bar under VoiceOver: \(texts(barVO))")
let laptopVO = words(.laptop, P, voiceOver: true, first: true)
check(laptopVO.rows.count == 2 && laptopVO.rows[0].spoken == "Command, Option, Control and Shift stay on for the next key: Command, then C, copies."
      && laptopVO.rows[1].text == "The keyboard key types on Mac mini, on screen or with a hardware keyboard.", "laptop under VoiceOver: the keys' rows")
for layout in [L, P] {
    for step in TourPolicy.steps(layout, voiceOver: true) {
        for device in ["iPad", "iPhone"] {
            for row in words(step, layout, device: device, voiceOver: true, first: true).rows {
                let spoken = row.spoken.lowercased()
                check(!spoken.contains("tap") && !spoken.contains("touch and hold") && !spoken.contains("slide") && !spoken.contains("drag"),
                      "a gesture in a VoiceOver row (\(step), \(layout)): \(row.spoken)")
            }
        }
    }
}
// Every row is read whole, never its symbol's name.
for layout in [L, P] {
    for step in TourPolicy.steps(layout, voiceOver: false) {
        for row in words(step, layout, first: true).rows {
            // Read as its words (the key row's caps by name), never with the symbol's name before them.
            check(!row.spoken.isEmpty && !row.spoken.hasPrefix(row.symbol) && !(row.symbol.contains(".") && row.spoken.contains(row.symbol))
                  && (row.spoken == row.text || row.symbol == "command") && row.spoken.hasSuffix("."), "\(step): a row read whole: \(row.spoken)")
        }
    }
}
check(TourPolicy.spokenTitle(barL, index: 1, count: 3) == "Windows and Text Size, step 2 of 3", "VoiceOver hears the count")
check(TourPolicy.spokenTitle(laptopFirst, index: 0, count: 1) == "Keys and Trackpad", "a one-card run has no count")
check(TourPolicy.skipTitle == "Skip" && TourPolicy.nextTitle == "Next" && TourPolicy.doneTitle == "Done", "the buttons")
check(TourPolicy.skipHint == "Ends the tour. Take the Tour in Settings shows it again.", "Skip's hint")
check(TourPolicy.takeTourTitle == "Take the Tour", "the Settings row")
check(TourPolicy.takeTourFootnote(device: "iPad") == "A short tour of Sill’s controls on this iPad.", "its footnote")
check(TourPolicy.takeTourHint(device: "iPhone") == "Shows how to use Sill on this iPhone.", "its hint")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
