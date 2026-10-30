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

    // MARK: The Mac's own goodbye (issue #105): asleep, shut down or restarting

    check("asleepWait: the wait after the third dial that did not connect, 20 s",
          P.asleepWait == 20 && P.asleepWait == P.reconnectRetry[P.reconnectQuietAfter - 1])
    func start(_ since: Double?, _ asleepAt: Double?, renewed: Bool = false) -> (Int, Double?) {
        let r = P.listingStart(listedSince: since, asleepAt: asleepAt, renewed: renewed)
        return (r.failed, r.lastDialAt)
    }
    check("listingStart: no goodbye, no count", [nil, -5, 0, 100, 1e9].allSatisfy { start($0, nil) == (0, nil) && start($0, nil, renewed: true) == (0, nil) })
    check("listingStart: listed when the Mac said it is going to sleep: asleep, three dials, the last at the goodbye",
          start(50, 100) == (3, 100) && start(-1e9, 100) == (3, 100))
    check("listingStart: listed at the goodbye's moment counts as listed then", start(100, 100) == (3, 100))
    check("listingStart: a listing of unknown age counts as listed then", start(nil, 100) == (3, 100))
    check("listingStart: listed afresh since: the Mac awake, no count", start(100.001, 100) == (0, nil) && start(400, 100) == (0, nil))
    check("listingStart: listed by a browser made at a return that counts (renewed): the Mac as it is now, no count",
          start(50, 100, renewed: true) == (0, nil) && start(nil, 100, renewed: true) == (0, nil) && start(100, 100, renewed: true) == (0, nil))
    check("listingStart then redialRow: the first dial 20 s after the goodbye, then every 30 s",
          redial(3, 100, 119.99) == (false, 120) && redial(3, 100, 120) == (true, nil) && redial(4, 120, 149) == (false, 150))
    check("waitingLine: no goodbye, the reconnect's own lines",
          (0...12).allSatisfy { P.waitingLine(mac: mini, failed: $0, lastDialAt: 50, direct: $0 % 2 == 0, wentAt: nil)
              == P.reconnectLine(mac: mini, failed: $0, direct: $0 % 2 == 0) }
          && P.waitingLine(mac: mini, failed: 0, lastDialAt: nil, direct: false, wentAt: nil) == "Reconnecting to Mac mini\u{2026}")
    check("waitingLine: counted asleep, no dial since the goodbye: the end's own words stay (nil)",
          P.waitingLine(mac: mini, failed: 3, lastDialAt: 100, direct: false, wentAt: 100) == nil
          && P.waitingLine(mac: mini, failed: 3, lastDialAt: 100, direct: true, wentAt: 100) == nil)
    check("waitingLine: after a dial since the goodbye, #69's lines", P.waitingLine(mac: mini, failed: 4, lastDialAt: 120, direct: false, wentAt: 100) == quiet
          && P.waitingLine(mac: mini, failed: 12, lastDialAt: 360, direct: true, wentAt: 100) == stopped
          && P.waitingLine(mac: mini, failed: 1, lastDialAt: 100.001, direct: false, wentAt: 100) == "Reconnecting to Mac mini\u{2026}")
    check("waitingLine: a listing with no dial yet after the goodbye (listed afresh, released, renewed): the words stay until its first dial",
          P.waitingLine(mac: mini, failed: 0, lastDialAt: nil, direct: false, wentAt: 100) == nil
          && P.waitingLine(mac: mini, failed: 0, lastDialAt: nil, direct: true, wentAt: 100) == nil)
    check("firstRemoteDial: no wait, or 20 s after the Mac said it went", P.firstRemoteDial(macWentAt: nil) == 0
          && P.firstRemoteDial(macWentAt: 100) == 120 && P.firstRemoteDial(macWentAt: 0) == P.asleepWait)

    // reconnectRow after a goodbye: "quit" holds a row listed before it for quitWait (3 s); "shutdown"
    // and "restart" (offAt) for offHold (10 minutes) at most, until it is listed afresh or renewed by a
    // return (networkRenewed, directRenewed), and a row listed afresh is taken by the usual rules.
    func row(net: Double?, dir: Double? = nil, left: Double? = nil, quit: Double? = nil, off: Double? = nil,
             netRenewed: Bool = false, dirRenewed: Bool = false, _ now: Double) -> (String?, Double?) {
        let r = P.reconnectRow(network: net.map { _ in "network" }, networkSince: net, direct: dir.map { _ in "direct" }, directSince: dir,
                               networkLeftAt: left, quitAt: quit, offAt: off, networkRenewed: netRenewed, directRenewed: dirRenewed, now: now)
        return (r.take, r.recheckAt)
    }
    check("reconnectRow (quit): a row listed before the goodbye is left alone for 3 s, looked at again then",
          row(net: 50, quit: 100, 100.5) == (nil, 103) && row(net: 100, quit: 100, 102.99) == (nil, 103))
    check("reconnectRow (quit): still listed after 3 s (Sill relaunched within the second): taken", row(net: 50, quit: 100, 103) == ("network", nil))
    check("reconnectRow (quit): a row listed afresh since the goodbye is taken at once", row(net: 100.2, quit: 100, 100.3) == ("network", nil))
    check("reconnectRow (quit): a Direct row listed before it waits out the 3 s, then its own 6 s",
          row(net: nil, dir: 50, quit: 100, 101) == (nil, 103) && row(net: nil, dir: 50, quit: 100, 103) == ("direct", nil))
    check("offHold: 10 minutes", P.offHold == 600)
    check("reconnectRow (shut down or restart): a row listed before the goodbye is left alone for 10 minutes, looked at again then",
          [100.5, 103, 400, 699.99].allSatisfy { row(net: 50, off: 100, $0) == (nil, 700) } && row(net: 100, off: 100, 650) == (nil, 700))
    check("reconnectRow (shut down or restart): 10 minutes after the goodbye a row that never left is taken",
          row(net: 50, off: 100, 700) == ("network", nil) && row(net: 100, off: 100, 1e7) == ("network", nil))
    check("reconnectRow (shut down or restart): a Direct row listed before it, for 10 minutes, then its own rules",
          row(net: nil, dir: 50, off: 100, 1e3 - 301) == (nil, 700) && row(net: nil, dir: 50, off: 100, 700) == ("direct", nil))
    check("reconnectRow (shut down or restart): a row listed afresh is taken at once (the Mac back, Sill open again)",
          row(net: 160, off: 100, 160) == ("network", nil) && row(net: 100.001, off: 100, 100.002) == ("network", nil))
    check("reconnectRow (shut down or restart): a row a return renewed is taken at once, its listing as old as it is",
          row(net: 50, off: 100, netRenewed: true, 130) == ("network", nil) && row(net: 100, off: 100, netRenewed: true, 100.1) == ("network", nil))
    check("reconnectRow (shut down or restart): a Direct row a return renewed waits its own 6 s and the network's 10 s",
          row(net: nil, dir: 50, left: 101, off: 100, dirRenewed: true, 105) == (nil, 111)
          && row(net: nil, dir: 50, left: 101, off: 100, dirRenewed: true, 111) == ("direct", nil))
    check("reconnectRow (shut down or restart): one row renewed says nothing of the other",
          row(net: nil, dir: 50, off: 100, netRenewed: true, 130) == (nil, 700) && row(net: 50, off: 100, dirRenewed: true, 130) == (nil, 700))
    check("reconnectRow (shut down or restart): a Direct row listed afresh waits its own 6 s and the network's 10 s",
          row(net: nil, dir: 160, left: 101, off: 100, 160) == (nil, 166) && row(net: nil, dir: 160, left: 101, off: 100, 166) == ("direct", nil)
          && row(net: nil, dir: 160, left: 158, off: 100, 166) == (nil, 168))
    check("reconnectRow (shut down or restart): an old network row beside a fresh Direct one: the Direct rules",
          row(net: 50, dir: 160, off: 100, 170) == ("direct", nil))
    check("reconnectRow: without a goodbye's hold, the rules as before", row(net: 50, 100) == ("network", nil) && row(net: nil, dir: 50, 56) == ("direct", nil)
          && row(net: 50, netRenewed: true, 100) == ("network", nil))
    // A listed row whose listing time is not known (no sighting for its name) counts as listed before
    // the goodbye: held for 10 minutes after a shut down or restart, for quitWait after a quit.
    func unknownSince(quit: Double? = nil, off: Double? = nil, _ now: Double) -> (String?, Double?) {
        let r = P.reconnectRow(network: "network", networkSince: nil, direct: nil as String?, directSince: nil, networkLeftAt: nil,
                               quitAt: quit, offAt: off, now: now)
        return (r.take, r.recheckAt)
    }
    check("reconnectRow: a listed row of unknown age is held after a shut down or restart for 10 minutes",
          unknownSince(off: 100, 101) == (nil, 700) && unknownSince(off: 100, 700) == ("network", nil))
    check("reconnectRow: a listed row of unknown age is held after a quit for its 3 s, then taken",
          unknownSince(quit: 100, 101) == (nil, 103) && unknownSince(quit: 100, 103) == ("network", nil))

    // The return from the background (returnRenews, renewed): what the browser made again at a return lists
    // counts as listed afresh, after "shutdown" or "restart" for any return since the goodbye, after "sleep"
    // only for the return it was read on; for both, a goodbye read within 3 s after a return was read on it
    // when its session was up before that return (`sessionSince`, here 50 unless said).
    func renews(off: Bool, _ wentAt: Double, bg: Bool, back: Double, since: Double = 50) -> Bool {
        P.returnRenews(off: off, wentAt: wentAt, inBackground: bg, returnedAt: back, sessionSince: since)
    }
    check("returnRenews: after shutdown or restart, any return since the goodbye",
          [100, 100.01, 103, 5000].allSatisfy { renews(off: true, 100, bg: false, back: $0) && renews(off: true, 100, bg: true, back: $0) })
    check("returnRenews: after sleep, a goodbye read in the background with the return within 3 s after it (read as the app ran again)",
          renews(off: false, 100, bg: true, back: 100.02) && renews(off: false, 100, bg: true, back: 102.99))
    check("returnRenews: after sleep, a later return keeps the Mac counted as asleep",
          !renews(off: false, 100, bg: true, back: 103) && !renews(off: false, 100, bg: true, back: 400))
    check("returnRenews: after sleep, a goodbye read in the foreground: no return renews",
          !renews(off: false, 100, bg: false, back: 100.02) && !renews(off: false, 100, bg: false, back: 400))
    check("returnRenews: a goodbye read within 3 s after a return was read on it, sleep or not",
          [false, true].allSatisfy { off in [false, true].allSatisfy { bg in
              renews(off: off, 100, bg: bg, back: 99.98) && renews(off: off, 100, bg: bg, back: 97.01) && renews(off: off, 100, bg: bg, back: 100) } })
    check("returnRenews: a goodbye read 3 s or more after a return was not",
          [false, true].allSatisfy { off in [false, true].allSatisfy { bg in
              !renews(off: off, 100, bg: bg, back: 97) && !renews(off: off, 100, bg: bg, back: 10) } })
    check("returnRenews: a goodbye read just after a return on a session dialled since (or at it) was not read on it, sleep or not",
          [false, true].allSatisfy { off in [false, true].allSatisfy { bg in
              !renews(off: off, 100, bg: bg, back: 99.5, since: 99.6) && !renews(off: off, 100, bg: bg, back: 99.5, since: 99.5)
              && renews(off: off, 100, bg: bg, back: 99.5, since: 99.49) && !renews(off: off, 100, bg: bg, back: 99.5, since: .infinity) } })
    check("returnRenews: after a return since the goodbye, when its session began does not matter",
          renews(off: true, 100, bg: false, back: 400, since: .infinity) && renews(off: false, 100, bg: true, back: 101, since: .infinity)
          && renews(off: true, 100, bg: false, back: 400, since: -.infinity))
    check("renewed: listed by the browser now running, made at or after the return that renews",
          P.renewed(listedByBrowser: true, browserMadeAt: 100, renewedFrom: 100) && P.renewed(listedByBrowser: true, browserMadeAt: 130, renewedFrom: 100))
    check("renewed: not by an older browser, nor through the results kept from the one it replaced, nor without a return",
          !P.renewed(listedByBrowser: true, browserMadeAt: 99.99, renewedFrom: 100) && !P.renewed(listedByBrowser: false, browserMadeAt: 130, renewedFrom: 100)
          && !P.renewed(listedByBrowser: true, browserMadeAt: 130, renewedFrom: nil))

    // A model of the reconnect after the Mac's own goodbye read at t = 0, as the glue runs it (reconnectIfListed:
    // the rows' renewal, reconnectRow, listingStart on a listing seen afresh or renewed, redialRow, waitingLine
    // while not dialling and the dial's line when dialling; cameForward: the return's renewal by returnRenews,
    // then listingStart again; lostReconnect: a goodbye read just after a return), every 50 ms; a dial the Mac
    // answers connects, one it does not is let go after 5 s. `listing(t)`: the row's listing by name (its
    // sighting, which a rebuild keeps), nil while not listed. `background`: the app's spells in the background,
    // each return making the browser again; the browser made then lists the row 0.05 s later while the row is
    // listed and `newBrowserLists`. `inBackground`: the goodbye read in the background; `returnedBefore`: read
    // that long after a return (its browser made then), on a session up before that return or, with
    // `dialledSince`, one dialled after it (the reconnect's own dial at the return). Lines: what the status line
    // becomes (nil: the end's own words, kept).
    struct Gone { var dials: [Double] = []; var connectedAt: Double?; var lines: [(at: Double, line: String)] = [] }
    func afterGoodbye(_ went: String, until: Double, answersFrom: Double = .infinity, listing: (Double) -> Double?,
                      background: [ClosedRange<Double>] = [], inBackground: Bool = false, returnedBefore: Double? = nil,
                      dialledSince: Bool = false, newBrowserLists: Bool = true) -> Gone {
        var run = Gone()
        let asleepAt: Double? = went == "sleep" ? 0 : nil, offAt: Double? = went == "off" ? 0 : nil, quitAt: Double? = went == "quit" ? 0 : nil
        let wentAt: Double? = went == "sleep" || went == "off" ? 0 : nil
        var browserMadeAt = -1000.0, renewedFrom: Double?
        if let before = returnedBefore {
            browserMadeAt = -before
            let since = dialledSince ? -before + 0.01 : -1000   // the session's dial: since the return, or long before it
            if let wentAt, P.returnRenews(off: went == "off", wentAt: wentAt, inBackground: inBackground, returnedAt: -before, sessionSince: since) {
                renewedFrom = -before
            }
        }
        var rowListing: Double?, rowRenewed = false, rowDials = 0, lastDial: Double?, inFlightUntil: Double?, wasBackground = inBackground
        var t = 0.0
        while t <= until, run.connectedAt == nil {
            let fg = !background.contains { $0.contains(t) } && !(inBackground && t == 0)
            if !fg { wasBackground = true }
            if fg, wasBackground {
                wasBackground = false
                browserMadeAt = t
                if let wentAt, P.returnRenews(off: went == "off", wentAt: wentAt, inBackground: inBackground, returnedAt: t, sessionSince: -.infinity) {
                    renewedFrom = t
                }
                (rowDials, lastDial) = P.listingStart(listedSince: rowListing, asleepAt: asleepAt, renewed: rowRenewed)
            }
            if let end = inFlightUntil, t >= end { inFlightUntil = nil }
            if let l = listing(t) {
                let byBrowser = newBrowserLists ? t >= browserMadeAt + 0.05 : browserMadeAt < -100
                let renewed = P.renewed(listedByBrowser: byBrowser, browserMadeAt: browserMadeAt, renewedFrom: renewedFrom)
                if inFlightUntil == nil, P.reconnectRow(network: "row", networkSince: l, direct: nil as String?, directSince: nil, networkLeftAt: nil,
                                                        quitAt: quitAt, offAt: offAt, networkRenewed: renewed, now: t).take != nil {
                    if rowListing != l || rowRenewed != renewed {
                        rowListing = l; rowRenewed = renewed
                        (rowDials, lastDial) = P.listingStart(listedSince: l, asleepAt: asleepAt, renewed: renewed)
                    }
                    let line = P.reconnectLine(mac: mini, failed: rowDials, direct: false)
                    if P.redialRow(failed: rowDials, lastDialAt: lastDial, foreground: fg, now: t).dial {
                        run.dials.append(t); rowDials += 1; lastDial = t
                        if t >= answersFrom { run.connectedAt = t } else { inFlightUntil = t + 5 }
                        if run.lines.last?.line != line { run.lines.append((t, line)) }
                    } else if let waiting = P.waitingLine(mac: mini, failed: rowDials, lastDialAt: lastDial, direct: false, wentAt: wentAt),
                              run.lines.last?.line != waiting {
                        run.lines.append((t, waiting))
                    }
                }
            }
            t = (t * 20 + 1).rounded() / 20
        }
        return run
    }
    func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.06 } ?? false }
    let reconnecting = "Reconnecting to Mac mini\u{2026}"
    // Asleep behind a sleep proxy (its record keeps the row listed), never answering: nothing for 20 s and
    // the words of the goodbye meanwhile, then the quiet line and a dial every 30 s, nine in all (the
    // twelve of #69, three of them counted), then stopped.
    let proxy = afterGoodbye("sleep", until: 3600, listing: { _ in -1000 })
    check("goodbye model (sleep, a sleep proxy): no dial for 20 s, then at 20, 50, 80… nine in all",
          proxy.dials == [20, 50, 80, 110, 140, 170, 200, 230, 260])
    check("goodbye model (sleep, a sleep proxy): the goodbye's words until the first dial, the quiet line from it, stopped after the last",
          proxy.lines.map(\.at) == [20, 265] && proxy.lines.map(\.line) == [quiet, stopped])
    check("goodbye model (sleep, a sleep proxy): never two dials closer than 30 s", zip(proxy.dials, proxy.dials.dropFirst()).allSatisfy { $1 - $0 >= 30 })
    // The same Mac woken 100 s in by someone at it, its record not renewed: the next dial (110 s) reaches it.
    check("goodbye model (sleep, a sleep proxy): a Mac woken 100 s in is reached at the next dial, 110 s",
          afterGoodbye("sleep", until: 600, answersFrom: 100, listing: { _ in -1000 }).connectedAt == 110)
    // No sleep proxy: the registration goes about a second after the goodbye; the Mac wakes at 300 s and
    // registers again: dialled at once, the first line Reconnecting.
    let woke = afterGoodbye("sleep", until: 600, answersFrom: 300, listing: { $0 < 1 ? -1000 : ($0 < 300 ? nil : 300) })
    check("goodbye model (sleep, no proxy): nothing dialled while it sleeps; listed afresh at 300 s, dialled at once and reached",
          woke.dials == [300] && woke.connectedAt == 300 && woke.lines.map(\.line) == [reconnecting])
    // The person comes back to Sill within the 20 s (5 to 10 s in the background): the Mac still counts as
    // asleep, its first dial at 20 s; back after it (30 to 200 s away): dialled at once, as #69's return does.
    check("goodbye model (sleep): a return within 20 s keeps the wait",
          afterGoodbye("sleep", until: 60, listing: { _ in -1000 }, background: [5...10]).dials.first == 20)
    let late = afterGoodbye("sleep", until: 400, listing: { _ in -1000 }, background: [30...200])
    check("goodbye model (sleep): a return after it dials at once, then every 30 s",
          late.dials.first == 20 && near(late.dials.dropFirst().first, 200.05) && near(late.dials.dropFirst(2).first, 230.05))
    // Read only on the return (issue #105's review): the goodbye waited in the connection while the app was
    // suspended, the Mac awake again since and still listed by name. Read in the background just before the
    // return (0.05 s), or just after it (0.05 s): the row the browser made at the return lists is dialled at
    // once, not 20 s later.
    let readBefore = afterGoodbye("sleep", until: 60, answersFrom: 0, listing: { _ in -1000 }, inBackground: true)
    check("goodbye model (sleep read in the background as the app ran again): the Mac listed by the new browser, dialled at once",
          near(readBefore.dials.first, 0.1) && near(readBefore.connectedAt, 0.1))
    let readAfter = afterGoodbye("sleep", until: 60, answersFrom: 0, listing: { _ in -1000 }, returnedBefore: 0.05)
    check("goodbye model (sleep read just after the return): dialled at once", readAfter.dials == [0] && readAfter.connectedAt == 0)
    check("goodbye model (sleep read just after the return): only the old browser's kept row, never dialled while it stays (the Mac asleep)",
          afterGoodbye("sleep", until: 60, listing: { $0 < 3 ? -1000 : nil }, returnedBefore: 0.05, newBrowserLists: false).dials.isEmpty)
    check("goodbye model (sleep read in the background long before the return): the return keeps the Mac counted as asleep",
          afterGoodbye("sleep", until: 60, listing: { _ in -1000 }, background: [0...10], inBackground: true).dials.first == 20)
    check("goodbye model (sleep just after the return, on a session dialled since): the Mac's now, counted asleep, its first dial at 20 s",
          afterGoodbye("sleep", until: 60, listing: { _ in -1000 }, returnedBefore: 0.05, dialledSince: true).dials.first == 20)
    // Shut down or restarting: the registration lingers a second, then goes; nothing is dialled until the
    // Mac is listed afresh (120 s: back, and Sill open on it), then at once.
    let backUp = afterGoodbye("off", until: 600, answersFrom: 120, listing: { $0 < 1 ? -1000 : ($0 < 120 ? nil : 120) })
    check("goodbye model (shut down or restart): nothing until listed afresh, then dialled at once",
          backUp.dials == [120] && backUp.connectedAt == 120)
    // A device that missed the registration's removal: the row never leaves, its listing as old as ever.
    let missed = afterGoodbye("off", until: 3600, listing: { _ in -1000 })
    check("goodbye model (shut down or restart, the removal missed): first dialled 10 minutes after the goodbye, the words until then",
          missed.dials.first == 600 && missed.lines.first.map { $0.at == 600 && $0.line == reconnecting } == true)
    check("goodbye model (shut down or restart, the removal missed): the Mac back meanwhile is reached at 600 s",
          afterGoodbye("off", until: 3600, answersFrom: 90, listing: { _ in -1000 }).connectedAt == 600)
    let cameBack = afterGoodbye("off", until: 3600, answersFrom: 90, listing: { _ in -1000 }, background: [30...120])
    check("goodbye model (shut down or restart, the removal missed): the person back at 120 s, the Mac too: dialled at once by the new browser",
          near(cameBack.dials.first, 120.1) && near(cameBack.connectedAt, 120.1) && cameBack.lines.map(\.line) == [reconnecting])
    let awayAtTen = afterGoodbye("off", until: 800, listing: { _ in -1000 }, background: [590...700])
    check("goodbye model (shut down or restart): in the background at its 10 minutes, no dial and the words until the return",
          near(awayAtTen.dials.first, 700.05) && awayAtTen.lines.first.map { abs($0.at - 700.05) < 0.06 && $0.line == reconnecting } == true)
    check("goodbye model (shut down or restart read just after the return): the Mac back long ago, dialled at once",
          afterGoodbye("off", until: 60, answersFrom: 0, listing: { _ in -1000 }, returnedBefore: 0.05).connectedAt == 0)
    check("goodbye model (shut down or restart read as the app ran again): dialled once the new browser lists it",
          near(afterGoodbye("off", until: 60, answersFrom: 0, listing: { _ in -1000 }, inBackground: true).connectedAt, 0.1))
    // The reconnect's own dial at the return reached a Mac that says it is restarting (a Mac going down then, or
    // one whose door refuses each dial so): not read on the return, so its row is held, not dialled at once again.
    let againAfterReturn = afterGoodbye("off", until: 700, listing: { _ in -1000 }, returnedBefore: 0.05, dialledSince: true)
    check("goodbye model (shut down or restart just after the return, on a session dialled since): held, its first dial at 10 minutes",
          againAfterReturn.dials.first == 600 && againAfterReturn.lines.first.map { $0.at == 600 && $0.line == reconnecting } == true)
    // Sill quit: the registration lingers; still listed after 3 s (Sill relaunched within the second), dialled then.
    check("goodbye model (quit): a row listed through the goodbye is dialled at 3 s, not before",
          afterGoodbye("quit", until: 60, answersFrom: 0, listing: { _ in -1000 }).connectedAt == 3)

    // MARK: Liveness after the app ran again (the verifier's review of PR #100, 2026-10-26)

    typealias L = DiscoveryPolicy.Liveness
    func live(_ now: Double, tick: Double?, received: Double, limit: Double = 6, unviable: Double? = nil) -> L {
        P.liveness(now: now, lastTickAt: tick, lastReceivedAt: received, limit: limit, unviableSince: unviable, viabilityLimit: 3)
    }
    check("liveness: the gap is a second, four of the ping's 0.25 s", P.livenessGap == 1)
    check("liveness: a tick 0.25 s after the last, a byte 1 s ago: alive", live(100, tick: 99.75, received: 99) == .alive)
    check("liveness: no byte for 6 s on regular ticks: alive at 6, silent just past it",
          live(106, tick: 105.75, received: 100) == .alive && live(106.01, tick: 105.76, received: 100) == .silent)
    check("liveness: the limit is the caller's (four times a slow round trip)", live(108, tick: 107.75, received: 100, limit: 9) == .alive
          && live(109.5, tick: 109.25, received: 100, limit: 9) == .silent)
    check("liveness: a connection's first tick judges as usual", live(106.5, tick: nil, received: 100) == .silent
          && live(100.25, tick: nil, received: 100) == .alive)
    check("liveness: a tick 600 s after the last (the app suspended), silent all that time: resumed, no verdict",
          live(700, tick: 99.75, received: 99.5) == .resumed)
    check("liveness: a gap of exactly a second is resumed, just under it is judged",
          live(110, tick: 109, received: 100) == .resumed && live(110, tick: 109.01, received: 100) == .silent)
    check("liveness: a gap of 1.5 s after a long silence: resumed", live(201.5, tick: 200, received: 100) == .resumed)
    check("liveness: a remote path not viable for more than 3 s: unviable, at 3 s not yet",
          live(110.01, tick: 109.76, received: 109.9, unviable: 107) == .unviable && live(110, tick: 109.75, received: 109.9, unviable: 107) == .alive)
    check("liveness: silent and unviable together: silent (its line)", live(110, tick: 109.75, received: 100, unviable: 105) == .silent)
    check("liveness: resumed comes before both", live(700, tick: 100, received: 100, unviable: 100) == .resumed)
    check("liveness: no unviable time (viable, or a session at home): never unviable", live(1e6, tick: 1e6 - 0.25, received: 1e6 - 1) == .alive)
    // A model of StreamClient's glue on the session's queue: a ping tick every 0.25 s while the app runs
    // (none while it is suspended, one overdue as it runs again), bytes as they arrive (a pong every tick,
    // and what waited in the connection read once the app runs), the verdict at each tick, a `resumed`
    // counting both afresh from that tick. How the session ends: the goodbye read, or lost by silence.
    enum End: Equatable { case goodbye(Double), lost(Double), on }
    func session(suspended: ClosedRange<Double>?, goodbyeAt: Double?, deadAfter: Double = .infinity, until: Double = 900,
                 resumeHopAfter: Double = 0.02, gapRule: Bool = true) -> End {
        var lastTick: Double? = nil, lastReceived = 0.0, t = 0.25
        var readGoodbyeAt: Double? = nil
        if let g = goodbyeAt {
            // Read as it arrives while the app runs, else the moment it runs again, just after the overdue tick.
            if let s = suspended, s.contains(g) { readGoodbyeAt = s.upperBound + 0.01 } else { readGoodbyeAt = g }
        }
        var resetAt: Double? = suspended.map { $0.upperBound + resumeHopAfter }   // willEnterForeground's hop
        while t <= until {
            if let s = suspended, t > s.lowerBound, t < s.upperBound { t = s.upperBound; continue }  // one overdue tick, at the return
            if let g = readGoodbyeAt, g < t { return .goodbye(g) }
            if let r = resetAt, r <= t { lastReceived = max(lastReceived, r); resetAt = nil }
            let verdict = gapRule ? P.liveness(now: t, lastTickAt: lastTick, lastReceivedAt: lastReceived, limit: 6, unviableSince: nil, viabilityLimit: 3)
                                  : (t - lastReceived > 6 ? .silent : .alive)
            lastTick = t
            switch verdict {
            case .silent, .unviable: return .lost(t)
            case .resumed: lastReceived = t
            case .alive: break
            }
            if t < deadAfter { lastReceived = t }    // the tick's ping, answered at once on a live connection
            t += 0.25
        }
        return .on
    }
    check("liveness model: a goodbye that waited while the iPad was locked 10 minutes is read, not the silence",
          session(suspended: 60...660, goodbyeAt: 100) == .goodbye(660.01))
    check("liveness model: before the rule (the review's race), the same session was lost to the silence at the return",
          session(suspended: 60...660, goodbyeAt: 100, gapRule: false) == .lost(660))
    check("liveness model: the hop landing first changed nothing before (no goodbye lost then)",
          session(suspended: 60...660, goodbyeAt: 100, resumeHopAfter: -0.01, gapRule: false) == .goodbye(660.01))
    check("liveness model: a connection dead across the suspension is still lost, 6 s after the return",
          session(suspended: 60...660, goodbyeAt: nil, deadAfter: 59) == .lost(666.25))
    check("liveness model: a connection that dies while the app runs is lost 6 s later, as before",
          session(suspended: nil, goodbyeAt: nil, deadAfter: 100) == .lost(106)
          && session(suspended: nil, goodbyeAt: nil, deadAfter: 100, gapRule: false) == .lost(106))
    check("liveness model: a live session across a suspension goes on", session(suspended: 60...660, goodbyeAt: nil, until: 700) == .on)
    check("liveness model: a goodbye read while the app runs ends it then", session(suspended: nil, goodbyeAt: 30) == .goodbye(30))

    // MARK: The Desktop after a stop

    typealias W = DiscoveryPolicy.Watched
    let allWatched: [W] = [.nothing, .desktop, .window(listed: false), .window(listed: true)]
    func auto(_ w: W, _ since: Double, chose: Bool = false) -> P.AutoDesktop { P.autoDesktop(watched: w, sinceLastAuto: since, choseSinceLastAuto: chose) }
    check("autoDesktop: nothing watched (a connection's first list): the Desktop at once", auto(.nothing, 1e9) == .ask)
    check("autoDesktop: the Desktop the Mac stopped: asked for again at once", auto(.desktop, 30) == .ask)
    check("autoDesktop: past the spacing, the person's choices since change nothing",
          auto(.nothing, 30, chose: true) == .ask && auto(.desktop, 30, chose: true) == .ask
          && auto(.window(listed: false), 30, chose: true) == .askAfterWait && auto(.window(listed: true), 30, chose: true) == .leave)
    check("autoDesktop: a window that left the list: after the closed window's wait", auto(.window(listed: false), 30) == .askAfterWait)
    check("autoDesktop: a window still listed (a pick that failed): left to the person", auto(.window(listed: true), 30) == .leave)
    check("autoDesktop: never asks at once within 10 s of the last automatic request",
          allWatched.allSatisfy { w in [0.0, 5, 10].allSatisfy { since in [false, true].allSatisfy { chose in
              let a = auto(w, since, chose: chose); return a != .ask && a != .askAfterWait } } })
    check("autoDesktop: a window within the spacing is left as before (no re-check)",
          [true, false].allSatisfy { listed in [0.0, 5, 10].allSatisfy { auto(.window(listed: listed), $0) == .leave && auto(.window(listed: listed), $0, chose: true) == .leave } })
    check("autoDesktop: just past 10 s it asks", auto(.desktop, 10.001) == .ask && auto(.nothing, 10.001) == .ask)

    // MARK: The Desktop that did not start (2026-10-28)

    // Sill.app could not start the Desktop the iPad asked for on its first list (a display gone while no
    // device was connected), and its next lists, 0.18 and 0.25 s after the request, came within the
    // spacing: nothing asked again, and the panel stayed black for the 7.4 s until Noah left. Now each
    // sets one re-check when the spacing ends, unless the person chose something since the request.
    func close(_ a: P.AutoDesktop, _ wait: Double) -> Bool { if case .askIn(let w) = a { return abs(w - wait) < 1e-9 }; return false }
    check("autoDesktop (2026-10-28): the list 0.18 s after the device's request, nothing streaming: again in 9.82 s", close(auto(.nothing, 0.18), 9.82))
    check("autoDesktop (2026-10-28): the fresh look's list at 0.25 s: again in 9.75 s", close(auto(.nothing, 0.25), 9.75))
    check("autoDesktop: the Desktop the Mac stopped within the spacing (issue #69's, 3 s after the request): again in 7 s", close(auto(.desktop, 3), 7))
    check("autoDesktop: the re-check waits out the spacing to the dot", close(auto(.nothing, 0), 10) && close(auto(.nothing, 10), 0)
          && close(auto(.desktop, 9.99), 0.01))
    check("autoDesktop: a clock set back waits the spacing, never longer", close(auto(.nothing, -5), 10) && close(auto(.desktop, -1e9), 10))
    check("autoDesktop: no re-check once the person chose since the request (a pick, a launch, a pick made again after a move)",
          [W.nothing, .desktop].allSatisfy { w in [0.0, 0.18, 5, 10].allSatisfy { auto(w, $0, chose: true) == .leave } })
    check("autoDesktopRecheck: asks only while nothing streams, nobody chose and no other automatic request went out",
          P.autoDesktopRecheck(nothingStreams: true, choseSince: false, askedSince: false)
          && [(true, true, false), (true, false, true), (false, false, false), (false, true, true), (true, true, true),
              (false, true, false), (false, false, true)].allSatisfy { !P.autoDesktopRecheck(nothingStreams: $0.0, choseSince: $0.1, askedSince: $0.2) })

    // A model of the glue (StreamClient's window-list handler, `askForDesktopByItself`, `recheckDesktop`):
    // the session's lists, the Mac's answer to each Desktop request `answer` s later (a list that streams
    // the Desktop, or says nothing streams again), the person's picks, a Desktop the Mac stops, the end.
    // Returns the times the device asked for the Desktop by itself and when the Desktop came.
    enum Src: Equatable { case none, desktop, window }
    struct DesktopRun { var asks: [Double] = []; var streamedAt: Double? }
    func desktopModel(until end: Double, fails: (Int) -> Bool, answer: Double = 0.2, alsoListAt extra: [Double] = [],
                      picks: [(at: Double, streams: Bool)] = [], stopsAt: [Double] = [], recheck: Bool = true) -> DesktopRun {
        enum E { case list(Src), pick(Bool), fire(choices: Int, last: Double), stop }
        var queue: [(at: Double, seq: Int, e: E)] = [], seq = 0
        func add(_ at: Double, _ e: E) { seq += 1; queue.append((at, seq, e)); queue.sort { ($0.at, $0.seq) < ($1.at, $1.seq) } }
        var active = Src.none, lastAuto = -Double.infinity, choices = 0, choicesAtLastAuto = 0, asks = 0
        var pending = false
        var run = DesktopRun()
        func askByItself(_ now: Double) {
            pending = false                       // a re-check of the spacing before is over
            lastAuto = now; choices += 1; choicesAtLastAuto = choices
            run.asks.append(now)
            let failed = fails(asks); asks += 1
            add(now + answer, .list(failed ? .none : .desktop))
        }
        add(0, .list(.none))                      // the connection's first list
        for t in extra { add(t, .list(.none)) }   // a list nothing asked for (the fresh look's 3 → 4 windows)
        for p in picks { add(p.at, .pick(p.streams)) }
        for t in stopsAt { add(t, .stop) }
        while let next = queue.first, next.at <= end {
            queue.removeFirst()
            let now = next.at
            switch next.e {
            case .list(let src):
                let previous = active; active = src
                if src == .desktop, run.streamedAt == nil { run.streamedAt = now }
                guard src == .none else { break }
                let watched: W = previous == .none ? .nothing : (previous == .desktop ? .desktop : .window(listed: true))
                switch P.autoDesktop(watched: watched, sinceLastAuto: now - lastAuto, choseSinceLastAuto: choices != choicesAtLastAuto) {
                case .ask: askByItself(now)
                case .askIn(let wait):
                    if recheck, !pending { pending = true; add(now + wait, .fire(choices: choices, last: lastAuto)) }
                case .askAfterWait, .leave: break
                }
            case .pick(let streams):
                choices += 1
                add(now + answer, .list(streams ? .window : .none))
            case .fire(let c, let last):
                guard pending, last == lastAuto else { break }    // cancelled: a newer request's spacing
                pending = false
                if P.autoDesktopRecheck(nothingStreams: active == .none, choseSince: choices != c, askedSince: lastAuto != last) { askByItself(now) }
            case .stop:
                if active == .desktop { add(now, .list(.none)) }   // ScreenCaptureKit stopped it: the host selects nothing
            }
        }
        return run
    }
    // 2026-10-28, the Mac's first start failing (before its own fix; any later one streams), its lists at
    // 0.2 and 0.25 s: the device asks again 10 s after its first request, and the Desktop comes.
    func at(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-6 } }
    func at(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-6 } ?? false }
    let blackScreen = desktopModel(until: 60, fails: { $0 == 0 }, alsoListAt: [0.25])
    check("Desktop model (2026-10-28): asked at 0 s, and once more at 10 s", at(blackScreen.asks, [0, 10]))
    check("Desktop model (2026-10-28): the Desktop streams 0.2 s after the second ask", at(blackScreen.streamedAt, 10.2))
    let before = desktopModel(until: 600, fails: { $0 == 0 }, alsoListAt: [0.25], recheck: false)
    check("Desktop model, the rule before the re-check: one ask, and nothing streams for good (the black screen)",
          at(before.asks, [0]) && before.streamedAt == nil)
    // The Mac's own fix (it looks again and tries once more): the first request streams; nothing more asked.
    let fixedMac = desktopModel(until: 60, fails: { _ in false }, alsoListAt: [0.1])
    check("Desktop model: a Mac that starts it: one ask, no re-check fires", at(fixedMac.asks, [0]) && at(fixedMac.streamedAt, 0.2))
    // A Mac that cannot start the Desktop at all: asked every 10 s, never faster.
    let neverStarts = desktopModel(until: 95, fails: { _ in true }, alsoListAt: [0.25])
    check("Desktop model: a Mac that keeps failing is asked every 10 s", at(neverStarts.asks, stride(from: 0.0, through: 90, by: 10).map { $0 }))
    check("Desktop model: never two automatic requests closer than 10 s",
          zip(neverStarts.asks, neverStarts.asks.dropFirst()).allSatisfy { $1 - $0 >= 10 - 1e-9 })
    // The person's pick meanwhile, even one that fails, stands the re-check down; one that streams too.
    let pickedFailing = desktopModel(until: 60, fails: { _ in true }, picks: [(5, false)])
    check("Desktop model: a person's pick at 5 s (failing too): no ask at 10 s", at(pickedFailing.asks, [0]))
    let pickedWindow = desktopModel(until: 60, fails: { _ in true }, picks: [(5, true)])
    check("Desktop model: a person's pick at 5 s that streams a window: no ask after", at(pickedWindow.asks, [0]))
    // A list that says nothing streams before the Mac has handled the request (a window change in between),
    // then the Desktop: no ask at 10 s.
    let slowAnswer = desktopModel(until: 60, fails: { _ in false }, answer: 3, alsoListAt: [0.1])
    check("Desktop model: a request answered late (a list in between said nothing streams): no second ask",
          at(slowAnswer.asks, [0]) && at(slowAnswer.streamedAt, 3))
    // The Desktop the device asked for streams, and the Mac stops it 4 s later (issue #69, within the
    // spacing): asked for again 10 s after the request, where the rule before left it stopped.
    let stoppedSoon = desktopModel(until: 60, fails: { _ in false }, stopsAt: [4])
    check("Desktop model: a Desktop the Mac stopped 4 s after the request: asked for again at 10 s", at(stoppedSoon.asks, [0, 10]))
    check("Desktop model: the rule before left a Desktop stopped within the spacing stopped",
          at(desktopModel(until: 60, fails: { _ in false }, stopsAt: [4], recheck: false).asks, [0]))
    let stoppedLate = desktopModel(until: 60, fails: { _ in false }, stopsAt: [30])
    check("Desktop model: one stopped past the spacing is asked for at once, as before", at(stoppedLate.asks, [0, 30]))
    // The session ends at 5 s: nothing after (the tear-down cancels the re-check).
    check("Desktop model: the session's end at 5 s: no ask after", at(desktopModel(until: 5, fails: { _ in true }).asks, [0]))
}
