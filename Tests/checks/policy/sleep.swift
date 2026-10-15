// Issue #69 in the policy check (docs/reconnect-after-sleep-plan.md): the browsers made again after
// the background and after a failure, what a browser made again shows while it settles, a working
// cable session across a rebuild (the review's: its pong stamped at the return), the automatic
// reconnect's dials of a row that stays listed (a Mac a Bonjour Sleep Proxy answers for, one stopped)
// and the words that go with them, and the Desktop asked for again once the Mac stopped it. A function
// main.swift calls before pairing at home's.
import Foundation

func afterSleepPolicy() {
    // MARK: The browsers made again

    check("browserRetry: 1, 2, 4, 8, 16, then 30 s after 1, 2, 3… failures in a row",
          (1...9).map { P.browserRetryDelay(afterFailures: $0) } == [1, 2, 4, 8, 16, 30, 30, 30, 30])
    check("browserRetry: a count of 0 or less waits as the first", P.browserRetryDelay(afterFailures: 0) == 1
          && P.browserRetryDelay(afterFailures: -3) == 1)
    check("browserRetry: never more than 30 s", (1...200).allSatisfy { P.browserRetryDelay(afterFailures: $0) <= 30 })
    check("browserFailures: the first failure", P.browserFailures(previous: 0, startedAt: 10, now: 10.5) == 1)
    check("browserFailures: one right after a rebuild counts on", P.browserFailures(previous: 1, startedAt: 10, now: 10.5) == 2
          && P.browserFailures(previous: 5, startedAt: 10, now: 39.99) == 6)
    check("browserFailures: a browser that ran 30 s is the first again", P.browserFailures(previous: 5, startedAt: 10, now: 40) == 1
          && P.browserFailures(previous: 5, startedAt: 10, now: 4000) == 1)
    check("browserFailures: a count below zero counts from zero", P.browserFailures(previous: -2, startedAt: 10, now: 11) == 1)

    func rebuild(_ failedAt: Double?, _ failures: Int, forward: Bool = false, fg: Bool = true, _ now: Double) -> (Bool, Double?) {
        let r = P.rebuildBrowser(failedAt: failedAt, failures: failures, cameForward: forward, foreground: fg, now: now)
        return (r.rebuild, r.recheckAt)
    }
    check("rebuildBrowser: the return from the background makes it again at once, failed or not",
          rebuild(nil, 0, forward: true, 5) == (true, nil) && rebuild(4, 3, forward: true, 5) == (true, nil))
    check("rebuildBrowser: a browser that runs is left alone", rebuild(nil, 0, 5) == (false, nil) && rebuild(nil, 4, 500) == (false, nil))
    check("rebuildBrowser: a failure waits its 1 s", rebuild(10, 1, 10) == (false, 11) && rebuild(10, 1, 10.999) == (false, 11)
          && rebuild(10, 1, 11) == (true, nil))
    check("rebuildBrowser: the third in a row waits 4 s, the sixth and later 30", rebuild(10, 3, 13.9) == (false, 14)
          && rebuild(10, 3, 14) == (true, nil) && rebuild(10, 6, 39) == (false, 40) && rebuild(10, 9, 40) == (true, nil))
    check("rebuildBrowser: never in the background, however long since", rebuild(10, 1, fg: false, 11) == (false, nil)
          && rebuild(10, 1, fg: false, 9999) == (false, nil))
    // `-SillBrowserFail 3`: each of the first three browsers fails half a second after it starts; the
    // rebuilds follow the glue (StreamClient.browserFailed, rebuildIfDue).
    var made = [0.0], failures = 0, started = 0.0
    for _ in 0..<3 {
        let failedAt = started + 0.5
        failures = P.browserFailures(previous: failures, startedAt: started, now: failedAt)
        var t = failedAt
        while !rebuild(failedAt, failures, t).0 { t = rebuild(failedAt, failures, t).1! }
        made.append(t); started = t
    }
    check("rebuildBrowser (-SillBrowserFail 3): made at 0, 1.5, 4 and 8.5 s", made == [0, 1.5, 4, 8.5])

    // What a browser made again shows while it settles.
    typealias R = (name: String, from: String)
    func results(_ kept: [R], _ fresh: [R], ends: Double?, _ now: Double) -> [String] {
        P.browserResults(kept: kept, fresh: fresh, name: { $0.name }, settleEnds: ends, now: now).map { "\($0.name)@\($0.from)" }
    }
    let kept: [R] = [("A", "old"), ("B", "old")]
    check("browserResults: no rebuild, the browser's own", results([], [("A", "new")], ends: nil, 5) == ["A@new"]
          && results(kept, [("A", "new")], ends: nil, 5) == ["A@new"])
    check("browserResults: while it settles, the new browser's, then the old one's it does not list yet",
          results(kept, [("C", "new"), ("A", "new")], ends: 103, 101) == ["C@new", "A@new", "B@old"])
    check("browserResults: before the new browser says anything, the old one's", results(kept, [], ends: 103, 100) == ["A@old", "B@old"])
    check("browserResults: a name in both is the new browser's", results(kept, [("B", "new")], ends: 103, 102.9) == ["B@new", "A@old"])
    check("browserResults: settled at its end, the new browser's alone", results(kept, [("A", "new")], ends: 103, 103) == ["A@new"]
          && results(kept, [], ends: 103, 200) == [])
    check("browserResults: while a failed browser waits to be made again (no end), the rows as they were, and what it still says joins them",
          results(kept, [], ends: .infinity, 1e9) == ["A@old", "B@old"] && results(kept, [("C", "new")], ends: .infinity, 1e9) == ["C@new", "A@old", "B@old"])
    check("rebuildSettle: the network's first word, 3 s", P.rebuildSettle == P.networkFirst && P.rebuildSettle == 3)

    // A model of a rebuild as the glue makes it (StreamClient.rebuildBrowser, showResults,
    // recomputeMacs' sightings): A listed since 5 stays listed throughout and keeps its time; B, gone
    // while the app was suspended, leaves when the new browser has settled; C, new, comes when the new
    // browser lists it. The new browser's first report lists only A, its second A and C.
    var sightings = P.sightings(P.NetworkSightings(), listed: ["A", "B"], now: 5)
    let rebuiltAt = 100.0, ends = rebuiltAt + P.rebuildSettle
    let reports: [(at: Double, fresh: [R])] = [(rebuiltAt, []), (100.05, [("A", "new")]), (100.5, [("A", "new"), ("C", "new")]),
                                              (ends, [("A", "new"), ("C", "new")])]
    var listedThrough = true, cameAt: Double?
    for r in reports {
        let shown = Set(P.browserResults(kept: kept, fresh: r.fresh, name: { $0.name }, settleEnds: ends, now: r.at).map(\.name))
        sightings = P.sightings(sightings, listed: shown, now: r.at)
        if sightings.since["A"] != 5 { listedThrough = false }
        if cameAt == nil, shown.contains("C") { cameAt = r.at }
    }
    check("rebuild model: a Mac that stays listed keeps its time through the rebuild (no leftAt, no new since)",
          listedThrough && sightings.leftAt["A"] == nil)
    check("rebuild model: a Mac that went leaves once the new browser has settled", sightings.since["B"] == nil && sightings.leftAt["B"] == ends)
    check("rebuild model: a Mac that came is listed as the new browser lists it", cameAt == 100.5 && sightings.since["C"] == 100.5)

    // A working session over the cable across a short trip to the background (the review of 2026-10-14):
    // the rows keep a Mac by name, so when the new browser's first report lists it on Wi-Fi alone, the
    // cable leaves the sightings until a later report lists it again. No ping went out while the app was
    // suspended, so the return stamps the pong (StreamClient.resetLiveness) as it resets liveness: the
    // session stays on the cable, looking again at the silence mark, by which time its pongs are back.
    // With the pong from before the trip it would move to Wi-Fi, and back once the cable had settled
    // again: two moves with what is sent held. The cable's settle counts from the later report
    // (`wiredSince`), which only a session on Wi-Fi waiting to move up would feel.
    typealias Listed = (name: String, ifs: [(String, I.Kind)])
    let keptOnCable: [Listed] = [("Mac", [en0, anpi0])]
    let returnedAt = 102.0, firstReport = 102.01, laterReport = 102.3, lastPongBefore = 100.0
    func shown(_ fresh: [Listed], _ now: Double) -> [(String, [(String, I.Kind)])] {
        P.browserResults(kept: keptOnCable, fresh: fresh, name: { $0.name }, settleEnds: returnedAt + P.rebuildSettle, now: now)
            .map { ($0.name, $0.ifs) }
    }
    var cablePaths = sight(S(), [("Mac", [en0, anpi0])], 5)
    cablePaths = sight(cablePaths, shown([("Mac", [en0])], firstReport), firstReport)
    check("cable model: the new browser's first report lists the Mac on Wi-Fi alone: so do the rows, the cable unlisted",
          cablePaths.wired.isEmpty && cablePaths.wiredSince.isEmpty && cablePaths.wifi == ["Mac": "en0"])
    check("cable model: with the pong from before the trip, a working cable session would move to Wi-Fi",
          plan(pin(.wired, now: firstReport, pong: lastPongBefore, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
    check("cable model: with the pong stamped at the return, it stays on the cable and looks again at the silence mark",
          plan(pin(.wired, now: firstReport, pong: returnedAt, wifi: "en0")) == .stay(.cableUnlisted, recheckAt: returnedAt + P.pongSilence))
    check("cable model: a pong 0.25 s after the return keeps it there at that mark",
          plan(pin(.wired, now: returnedAt + P.pongSilence, pong: returnedAt + 0.25, wifi: "en0"))
              == .stay(.cableUnlisted, recheckAt: returnedAt + 0.25 + P.pongSilence))
    cablePaths = sight(cablePaths, shown([("Mac", [en0, anpi0])], laterReport), laterReport)
    check("cable model: a later report lists the cable again: on the cable, its settle counted from that report",
          cablePaths.wired == ["Mac": "anpi0"] && cablePaths.wiredSince == ["Mac": laterReport]
              && plan(pin(.wired, now: laterReport, pong: returnedAt + 0.25, wired: "anpi0", since: laterReport, wifi: "en0"))
                  == .stay(.cable, recheckAt: nil))

    // MARK: The reconnect's dials of a row that stays listed

    func redial(_ failed: Int, _ last: Double?, fg: Bool = true, _ now: Double) -> (Bool, Double?) {
        let r = P.redialRow(failed: failed, lastDialAt: last, foreground: fg, now: now)
        return (r.dial, r.recheckAt)
    }
    check("redialRow: the first dial of a listing at once", redial(0, nil, 0) == (true, nil) && redial(0, 50, 51) == (true, nil))
    check("redialRow: the second 5 s after the first started", redial(1, 10, 12) == (false, 15) && redial(1, 10, 14.999) == (false, 15)
          && redial(1, 10, 15) == (true, nil))
    check("redialRow: then 10, 20 and 30 s after the last started", redial(2, 15, 24) == (false, 25) && redial(2, 15, 25) == (true, nil)
          && redial(3, 25, 44) == (false, 45) && redial(4, 45, 74) == (false, 75) && redial(4, 45, 75) == (true, nil))
    check("redialRow: every 30 s after that", redial(7, 100, 129) == (false, 130) && redial(11, 100, 130) == (true, nil))
    check("redialRow: none after 12 dials of a listing", redial(12, 100, 1000) == (false, nil) && redial(30, 100, 1000) == (false, nil))
    check("redialRow: none in the background, not even the first", redial(0, nil, fg: false, 0) == (false, nil)
          && redial(3, 10, fg: false, 1000) == (false, nil))

    let mini = "Mac mini"
    let quiet = "Mac mini isn\u{2019}t answering. It may be asleep. Sill keeps trying, or tap it to try now."
    let stopped = "Stopped trying to reach Mac mini. Tap it to try again."
    check("reconnectLine: the first three dials say Reconnecting, as before",
          (0...2).allSatisfy { P.reconnectLine(mac: mini, failed: $0, direct: false) == "Reconnecting to Mac mini\u{2026}" })
    check("reconnectLine: a Direct row's say directly, as before",
          (0...2).allSatisfy { P.reconnectLine(mac: mini, failed: $0, direct: true) == "Reconnecting to Mac mini directly\u{2026}" })
    check("reconnectLine: after 3 that did not connect, the Mac may be asleep, through every later dial",
          (3...11).allSatisfy { P.reconnectLine(mac: mini, failed: $0, direct: false) == quiet && P.reconnectLine(mac: mini, failed: $0, direct: true) == quiet })
    check("reconnectLine: after 12, stopped, in the remote path's words", P.reconnectLine(mac: mini, failed: 12, direct: false) == stopped
          && P.reconnectLine(mac: mini, failed: 40, direct: true) == stopped)

    // A model of the reconnect as the glue runs it (StreamClient+Remote's reconnectIfListed, the let-go
    // after 5 s, sessionEnded's dial that did not connect, cameForward): it looks every 50 ms (the
    // browser's events, the retry chain and its own due times together, the worst case: the rule is
    // the same however often it is asked), a dial that the Mac answers connects at once, one it does
    // not is let go after 5 s. `listing(t)`: the row's listing (its `since`), nil while not listed.
    struct Run { var dials: [Double] = []; var connectedAt: Double?; var lines: [(at: Double, line: String)] = [] }
    func reconnect(until: Double, answersFrom: Double = .infinity, listing: (Double) -> Double? = { _ in 0 },
                   background: ClosedRange<Double>? = nil, direct: Bool = false) -> Run {
        var run = Run()
        var rowListing: Double?, rowDials = 0, lastDial: Double?, inFlightUntil: Double?, wasBackground = false
        var t = 0.0
        while t <= until, run.connectedAt == nil {
            let fg = !(background?.contains(t) ?? false)
            if !fg { wasBackground = true }
            if fg, wasBackground { wasBackground = false; rowDials = 0; lastDial = nil }   // cameForward
            if let end = inFlightUntil, t >= end { inFlightUntil = nil }                     // let go
            if inFlightUntil == nil, let l = listing(t) {
                if rowListing != l { rowListing = l; rowDials = 0; lastDial = nil }
                let line = P.reconnectLine(mac: mini, failed: rowDials, direct: direct)
                if P.redialRow(failed: rowDials, lastDialAt: lastDial, foreground: fg, now: t).dial {
                    run.dials.append(t); rowDials += 1; lastDial = t
                    if t >= answersFrom { run.connectedAt = t } else { inFlightUntil = t + 5 }
                }
                if run.lines.last?.line != line { run.lines.append((t, line)) }
            }
            t = (t * 20 + 1).rounded() / 20
        }
        return run
    }
    // The simulator's repro: the host stopped (kill -STOP) 6 s before the loss and continued 20 s after
    // the stop, 14 s after the loss: main's build dialled at 0 and 6 and stopped; this rule dials at 0,
    // 5 and 15, and the third connects.
    let stop = reconnect(until: 600, answersFrom: 14)
    check("reconnect model (a host stopped for 20 s): dials at 0, 5 and 15 s, the third connects",
          stop.dials == [0, 5, 15] && stop.connectedAt == 15)
    check("reconnect model (a host stopped for 20 s): Reconnecting… all the way", stop.lines.map(\.line) == ["Reconnecting to Mac mini\u{2026}"])
    // A Mac a sleep proxy answers for, that never wakes: twelve dials in about 4.6 minutes, the quiet
    // line after the third, then stopped; never two dials closer than 5 s.
    let asleep = reconnect(until: 3600)
    check("reconnect model (a sleep proxy, the Mac never answers): 12 dials, at 0, 5, 15, 35, then every 30 s",
          asleep.dials == [0, 5, 15, 35, 65, 95, 125, 155, 185, 215, 245, 275])
    check("reconnect model (a sleep proxy): the quiet line 20 s after the loss, stopped at 280 s",
          asleep.lines.map(\.at) == [0, 20, 280] && asleep.lines.map(\.line) == ["Reconnecting to Mac mini\u{2026}", quiet, stopped])
    check("reconnect model: never two dials of a listing closer than 5 s",
          zip(asleep.dials, asleep.dials.dropFirst()).allSatisfy { $1 - $0 >= 5 })
    // The Mac wakes 100 s in (opened by someone at it): the next dial, at 125 s, connects.
    check("reconnect model: a Mac that wakes 100 s in is reached at the next dial (125 s)",
          reconnect(until: 600, answersFrom: 100).connectedAt == 125)
    // Its row goes and comes back at 50 s (Sill relaunched on the Mac, its record renewed): dialled at once.
    let relisted = reconnect(until: 600, answersFrom: 50, listing: { $0 < 49 ? 0 : ($0 < 50 ? nil : 50) })
    check("reconnect model: a row listed afresh is dialled at once", relisted.dials.last == 50 && relisted.connectedAt == 50)
    // In the background from 40 to 300 s: no dial there, the count starts again on the return.
    let away = reconnect(until: 3600, background: 40...300)
    check("reconnect model: no dial in the background", !away.dials.contains { (40...300).contains($0) })
    let back = away.dials.filter { $0 > 300 }
    check("reconnect model: the return from the background dials at once and starts the count again (12 more)",
          back.count == 12 && away.dials.count == 4 + 12
          && zip(back.prefix(3), [300.05, 305.05, 315.05]).allSatisfy { abs($0 - $1) < 0.06 })
    // Nothing listed: nothing dialled (the remote path's, unchanged, is not this rule's).
    check("reconnect model: a row that is not listed is never dialled", reconnect(until: 600, listing: { _ in nil }).dials.isEmpty)

    // MARK: The Desktop after a stop

    typealias W = DiscoveryPolicy.Watched
    check("autoDesktop: nothing watched (a connection's first list): the Desktop at once", P.autoDesktop(watched: .nothing, sinceLastAuto: 1e9) == .ask)
    check("autoDesktop: the Desktop the Mac stopped: asked for again at once", P.autoDesktop(watched: .desktop, sinceLastAuto: 30) == .ask)
    check("autoDesktop: a window that left the list: after the closed window's wait",
          P.autoDesktop(watched: .window(listed: false), sinceLastAuto: 30) == .askAfterWait)
    check("autoDesktop: a window still listed (a pick that failed): left to the person",
          P.autoDesktop(watched: .window(listed: true), sinceLastAuto: 30) == .leave)
    check("autoDesktop: never within 10 s of the last automatic request",
          [W.nothing, .desktop, .window(listed: false), .window(listed: true)].allSatisfy {
              P.autoDesktop(watched: $0, sinceLastAuto: 10) == .leave && P.autoDesktop(watched: $0, sinceLastAuto: 0) == .leave })
    check("autoDesktop: just past 10 s it asks", P.autoDesktop(watched: .desktop, sinceLastAuto: 10.001) == .ask)
}
