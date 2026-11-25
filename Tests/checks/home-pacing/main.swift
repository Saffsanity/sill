import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var passed = 0
var failures = 0

func check(_ ok: Bool, _ what: String) {
    if ok {
        passed += 1
        print("ok   \(what)")
    } else {
        failures += 1
        print("FAIL \(what)")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))"))
}

// MARK: Constants

eq(HomePacing.maxInflight, 2, "steady-state inflight cap is 2 messages")
eq(HomePacing.backlogBudget, 262_144, "recovery keyframe backlog budget is 256 KB")
eq(HomePacing.holdCap, 524_288, "in-flight keyframe follower hold cap is 512 KB")
eq(HomePacing.backlogSlack, 131_072, "post-keyframe backlog slack is 128 KB")
eq(HomePacing.idleBytes, 32_768, "idle queue mark is 32 KB (above 100 home audio packets)")
eq(HomePacing.keyframeSpacing, 0.25, "home forced-keyframe spacing is 0.25 s")
eq(HomePacing.inFlightKeyframeWait, 4.0, "sibling in-flight keyframe wait matches 4.0 s deadAfter")

// MARK: Requests spacing and sibling in-flight wait

do {
    var req = HomePacing.Requests()
    check(req.due(now: 0), "first keyframe request is immediately due")
    req.recordRequest(now: 10.0)
    check(!req.due(now: 10.249999), "not due just before 0.25 s")
    check(req.due(now: 10.25), "due at exact 0.25 s boundary")

    req.recordKeyframe(now: 20.0)
    check(req.due(now: 20.5, otherHomeKeyframeInFlight: false),
          "single or idle sibling never waits past 0.25 s")
    check(!req.due(now: 23.999999, otherHomeKeyframeInFlight: true),
          "waits while another home client is still taking a keyframe (< 4.0 s)")
    check(req.due(now: 24.0, otherHomeKeyframeInFlight: true),
          "stops waiting at exact 4.0 s so a stalled sibling never starves recovery")
}

// MARK: First keyframe and pre-keyframe accounting

do {
    var p = HomePacing()
    var needs = true
    var first = true
    eq(p.decide(isKeyframe: false, hasParameterSets: false, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true),
       .waitKey(countWithheld: false, askKeyframe: false),
       "delta before first keyframe neither counts as withheld nor asks")
    check(needs && first, "still awaiting first keyframe after skipped delta")

    eq(p.decide(isKeyframe: true, hasParameterSets: false, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true),
       .waitKey(countWithheld: false, askKeyframe: false),
       "first keyframe without parameter sets waits without counting")

    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 230, inflightFrames: 1, pendingBytes: 1_400_000, mayAskKeyframe: false),
       .send(sendParameterSets: true),
       "first keyframe bypasses connect catalog burst and pairs parameter sets")
    check(!needs && !first, "first keyframe clears needsKeyframe and awaitingFirstKeyframe")
}

// MARK: Steady-state 2-message bound, audio-safe idle threshold, and retry if unanswered

do {
    var p = HomePacing()
    var needs = true, first = true
    _ = p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                 inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true)

    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 2, inflightFrames: 2, pendingBytes: 16_000, mayAskKeyframe: true),
       .send(sendParameterSets: false),
       "delta at inflight == 2 is sent without parameter sets")

    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 3, inflightFrames: 3, pendingBytes: 24_000, mayAskKeyframe: true),
       .drop,
       "delta at inflight == 3 is dropped without immediate keyframe request")
    check(needs && !first, "drop sets needsKeyframe while keeping awaitingFirstKeyframe false")

    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 1, pendingBytes: 8_000, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "delta while inflightFrames == 1 waits without asking")

    // Exact 32 KB literal boundaries (and 95 home audio packets = 18,050 B <= 32,768 B).
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 32_769, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "delta at 32,769 B (idleBytes + 1) waits without asking")
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 18_050, mayAskKeyframe: false),
       .waitKey(countWithheld: true, askKeyframe: false),
       "delta with 95 audio packets (18,050 B) waits while spacing is not due")
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 32_768, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: true),
       "delta at exact 32,768 B with inflightFrames == 0 asks")

    // If the encoder drops/refuses the forced keyframe, once spacing is due again (mayAskKeyframe: true)
    // the client asks again rather than staying stale forever.
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 18_050, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: true),
       "unanswered request retries once spacing is due again")
}

// MARK: Recovery and periodic keyframe admission boundaries (fixed byte literals)

do {
    var p = HomePacing()
    var needs = true, first = false

    eq(p.decide(isKeyframe: true, hasParameterSets: false, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "recovery keyframe without parameter sets counts as withheld")

    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 1, pendingBytes: 8_000, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "recovery keyframe rejected while an old frame is still unacked")

    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 0, pendingBytes: 262_145, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "recovery keyframe rejected at 262,145 B (backlogBudget + 1)")

    p.keyframeSent(bytes: 100_000)
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 0, pendingBytes: 100_000, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "recovery keyframe rejected while a keyframe is still in flight")
    p.keyframeTaken(bytes: 100_000, pendingBytes: 0)

    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 11, inflightFrames: 0, pendingBytes: 262_144, mayAskKeyframe: true),
       .send(sendParameterSets: true),
       "recovery keyframe accepted at exact 262,144 B with 11 non-frame thumbnails in flight")
    check(!needs, "accepted recovery keyframe clears needsKeyframe")

    // Periodic keyframe on a synchronized client (`needs == false`) with 2 thumbnails in flight:
    // because parameter sets are paired (`sendParameterSets: true`) rather than sent ahead, inflight == 2 passes!
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 2, inflightFrames: 0, pendingBytes: 262_144, mayAskKeyframe: true),
       .send(sendParameterSets: true),
       "periodic keyframe at inflight == 2 and exact 262,144 B sends with paired parameter sets")

    eq(p.decide(isKeyframe: true, hasParameterSets: false, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true),
       .waitKey(countWithheld: true, askKeyframe: false),
       "keyframe without parameter sets while synchronized transitions cleanly to waitKey")
    check(needs, "missing parameter sets marks needsKeyframe")
}

// MARK: Still-window recovery on sweep (including 95 audio packets and unanswered retry)

do {
    let p = HomePacing()
    check(!p.canAskOnSweep(needsKeyframe: false, awaitingFirstKeyframe: false, inflightFrames: 0, pendingBytes: 0),
          "sweep never asks when needsKeyframe is false")
    check(!p.canAskOnSweep(needsKeyframe: true, awaitingFirstKeyframe: true, inflightFrames: 0, pendingBytes: 0),
          "sweep never asks while awaitingFirstKeyframe")
    check(!p.canAskOnSweep(needsKeyframe: true, awaitingFirstKeyframe: false, inflightFrames: 1, pendingBytes: 0),
          "sweep waits for inflightFrames == 0")
    check(!p.canAskOnSweep(needsKeyframe: true, awaitingFirstKeyframe: false, inflightFrames: 0, pendingBytes: 32_769),
          "sweep waits at 32,769 B")
    check(p.canAskOnSweep(needsKeyframe: true, awaitingFirstKeyframe: false, inflightFrames: 0, pendingBytes: 32_768),
          "sweep asks at exact 32,768 B")
    check(p.canAskOnSweep(needsKeyframe: true, awaitingFirstKeyframe: false, inflightFrames: 0, pendingBytes: 18_050),
          "sweep asks even with 95 home audio packets (18,050 B) in flight")
}

// MARK: In-flight keyframe wave, non-stacking (< 256 KB), stream restart, and bytesTaken floor reset

do {
    var p = HomePacing()
    var needs = false, first = false
    p.keyframeSent(bytes: 1_500_000)

    // Exact 512 KB literal boundary (524,288 vs 524,289).
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 18, inflightFrames: 18, pendingBytes: 1_500_000 + 524_288, mayAskKeyframe: true),
       .send(sendParameterSets: false),
       "follower delta at exact 524,288 B behind in-flight keyframe is sent")
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 19, inflightFrames: 19, pendingBytes: 1_500_000 + 524_289, mayAskKeyframe: true),
       .drop,
       "follower delta at 524,289 B behind in-flight keyframe is dropped")

    // Non-stacking with a small 120 KB in-flight keyframe (below 256 KB budget and inflight == 1 <= 2),
    // proving `keyframesInFlight > 0` itself blocks stacking!
    p = HomePacing(); needs = false; first = false
    p.keyframeSent(bytes: 120_000)
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 1, pendingBytes: 120_000, mayAskKeyframe: true),
       .drop,
       "second non-first 120 KB keyframe is never stacked onto an in-flight keyframe")

    // Stream restart while 120 KB keyframe from old stream is still in flight:
    // new stream's first keyframe (200 KB) passes; taking the first of the two must NOT set backlogFloor
    // (behavioral check: once the second also finishes at 0 B, backlogFloor must be 0, not stale!).
    needs = true; first = true
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 1, inflightFrames: 1, pendingBytes: 120_000, mayAskKeyframe: true),
       .send(sendParameterSets: true),
       "restarted stream's first keyframe passes while previous stream's keyframe is still in flight")
    p.keyframeSent(bytes: 200_000)
    // Suppose old 120 KB keyframe completes while 280 KB (new 200 KB keyframe + 80 KB deltas) remains:
    p.keyframeTaken(bytes: 120_000, pendingBytes: 280_000)
    eq(p.backlogFloor, 0, "backlogFloor stays 0 while second keyframe remains in flight")
    // Now second keyframe completes with 0 B remaining, then 3 thumbnails (24 KB) arrive before next frame:
    // if backlogFloor had been set to 280 KB on the first completion, this delta at inflight == 3 would wrongly pass!
    p.keyframeTaken(bytes: 200_000, pendingBytes: 0)
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 3, inflightFrames: 0, pendingBytes: 24_000, mayAskKeyframe: true),
       .drop,
       "behavioral check: earlier keyframe completion did not leave stale backlogFloor")

    // Exact 128 KB (131,072 B) backlogSlack boundaries after keyframe completion:
    p = HomePacing(); needs = false; first = false
    p.keyframeSent(bytes: 500_000)
    p.keyframeTaken(bytes: 500_000, pendingBytes: 300_000)
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 15, inflightFrames: 15, pendingBytes: 300_000 + 131_072, mayAskKeyframe: true),
       .send(sendParameterSets: false),
       "delta at exact backlogFloor + 131,072 B passes while wave drains")
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 10, inflightFrames: 10, pendingBytes: 200_000, mayAskKeyframe: true),
       .send(sendParameterSets: false),
       "shrinking wave passes")
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 11, inflightFrames: 11, pendingBytes: 200_000 + 131_073, mayAskKeyframe: true),
       .drop,
       "growing backlog at backlogFloor + 131,073 B drops")

    // Non-first keyframe is NOT exempted by backlogFloor > 0, and fails above 262,144 B even at inflight <= 2.
    p = HomePacing(); needs = false; first = false
    p.keyframeSent(bytes: 500_000)
    p.keyframeTaken(bytes: 500_000, pendingBytes: 200_000)
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 3, inflightFrames: 3, pendingBytes: 200_000, mayAskKeyframe: true),
       .drop,
       "non-first keyframe at inflight == 3 drops even when backlogFloor > 0")
    p = HomePacing(); needs = false; first = false
    eq(p.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 2, inflightFrames: 0, pendingBytes: 262_145, mayAskKeyframe: true),
       .drop,
       "non-first keyframe at 262,145 B drops even when inflight == 2")

    // Queue empties completely between video frames (`bytesTaken(pendingBytes: 0)`), then 3 thumbnails
    // (24 KB) arrive before the next delta: steady-state `inflight > 2` MUST drop immediately!
    p = HomePacing(); needs = false; first = false
    p.keyframeSent(bytes: 400_000)
    p.keyframeTaken(bytes: 400_000, pendingBytes: 24_000)
    p.bytesTaken(pendingBytes: 0)
    eq(p.decide(isKeyframe: false, hasParameterSets: true, needsKeyframe: &needs, awaitingFirstKeyframe: &first,
                inflight: 3, inflightFrames: 0, pendingBytes: 24_000, mayAskKeyframe: true),
       .drop,
       "bytesTaken(0) between frames zeroes backlogFloor so fresh thumbnails + stall drop at inflight == 3")
}

// MARK: Two slow home clients on a still window converge without ping-ponging

do {
    final class ClientSim {
        var pacing = HomePacing()
        var needs = false
        var first = false
        var inflight = 0
        var inflightFrames = 0
        var pendingBytes = 0
        var keyFinishAt: Double?
        init(needs: Bool = false, inflight: Int = 0, inflightFrames: Int = 0, pendingBytes: Int = 0) {
            self.needs = needs
            self.inflight = inflight
            self.inflightFrames = inflightFrames
            self.pendingBytes = pendingBytes
        }
    }
    // At t = 0, final repaint is encoded as a keyframe (takes 3.5 s on each client, just under 4 s deadAfter).
    // Client 0 accepts it; Client 1 has 1 older delta until t = 0.2 s so Client 1 withholds it.
    let clients = [
        ClientSim(),
        ClientSim(needs: true, inflight: 1, inflightFrames: 1, pendingBytes: 8_000),
    ]
    var req = HomePacing.Requests()
    req.recordKeyframe(now: 0.0)
    _ = clients[0].pacing.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &clients[0].needs, awaitingFirstKeyframe: &clients[0].first,
                                 inflight: 0, inflightFrames: 0, pendingBytes: 0, mayAskKeyframe: true)
    clients[0].pacing.keyframeSent(bytes: 1_500_000)
    clients[0].inflight = 2; clients[0].inflightFrames = 1; clients[0].pendingBytes = 1_500_086; clients[0].keyFinishAt = 3.5

    _ = clients[1].pacing.decide(isKeyframe: true, hasParameterSets: true, needsKeyframe: &clients[1].needs, awaitingFirstKeyframe: &clients[1].first,
                                 inflight: clients[1].inflight, inflightFrames: clients[1].inflightFrames, pendingBytes: clients[1].pendingBytes, mayAskKeyframe: true)
    // At t = 0.2 s, Client 1's old delta finishes draining.
    clients[1].inflight = 0; clients[1].inflightFrames = 0; clients[1].pendingBytes = 0; clients[1].pacing.bytesTaken(pendingBytes: 0)

    var sweepRequests = 0
    for sec in 1...20 {
        let t = Double(sec)
        for i in clients.indices {
            if let fin = clients[i].keyFinishAt, fin <= t {
                clients[i].keyFinishAt = nil
                clients[i].inflight = 0; clients[i].inflightFrames = 0; clients[i].pendingBytes = 0
                clients[i].pacing.bytesTaken(pendingBytes: 0)
                clients[i].pacing.keyframeTaken(bytes: 1_500_000, pendingBytes: 0)
            }
        }
        let otherInFlight = clients.contains { $0.pacing.keyframesInFlight > 0 }
        let waiting = clients.contains {
            $0.pacing.canAskOnSweep(needsKeyframe: $0.needs, awaitingFirstKeyframe: $0.first,
                                    inflightFrames: $0.inflightFrames, pendingBytes: $0.pendingBytes)
        }
        if waiting, req.due(now: t, otherHomeKeyframeInFlight: otherInFlight) {
            req.recordRequest(now: t)
            sweepRequests += 1
            let kt = t + 0.05
            req.recordKeyframe(now: kt)
            for i in clients.indices {
                if case .send = clients[i].pacing.decide(
                    isKeyframe: true, hasParameterSets: true,
                    needsKeyframe: &clients[i].needs, awaitingFirstKeyframe: &clients[i].first,
                    inflight: clients[i].inflight, inflightFrames: clients[i].inflightFrames,
                    pendingBytes: clients[i].pendingBytes, mayAskKeyframe: false
                ) {
                    clients[i].pacing.keyframeSent(bytes: 1_500_000)
                    clients[i].inflight = 2; clients[i].inflightFrames = 1
                    clients[i].pendingBytes = 1_500_086; clients[i].keyFinishAt = kt + 3.5
                }
            }
        }
    }
    eq(sweepRequests, 1, "two slow home clients on a still window request only 1 recovery keyframe across 20 sweeps")
    check(!clients[0].needs && !clients[1].needs, "both home clients converge on the still window's picture")
}

// MARK: Personal Hotspot livelock reproduction (Sill.log 2026-11-25 17:48 and 17:49)

struct LinkSim {
    struct Item {
        var remaining: Int
        var total: Int
        var isFrame: Bool
        var isKeyframe: Bool
    }
    var queue: [Item] = []
    var inflight = 0
    var inflightFrames = 0
    var pendingBytes = 0

    mutating func enqueue(bytes: Int, isFrame: Bool, isKeyframe: Bool = false) {
        queue.append(Item(remaining: bytes, total: bytes, isFrame: isFrame, isKeyframe: isKeyframe))
        inflight += 1
        if isFrame { inflightFrames += 1 }
        pendingBytes += bytes
    }

    mutating func drain(bytes budget: Int, onDone: (_ total: Int, _ isKeyframe: Bool, _ pending: Int) -> Void) {
        var left = budget
        while left > 0, !queue.isEmpty {
            let take = min(left, queue[0].remaining)
            queue[0].remaining -= take
            left -= take
            if queue[0].remaining == 0 {
                let done = queue.removeFirst()
                inflight -= 1
                pendingBytes -= done.total
                if done.isFrame { inflightFrames -= 1 }
                onDone(done.total, done.isKeyframe, pendingBytes)
            }
        }
    }
}

func simulateHotspot(useNewPacing: Bool) -> (keyframesSent: Int, maxPendingBytes: Int, steadyFPS: Int, steadyDrops: Int) {
    var link = LinkSim()
    for _ in 0..<192 { link.enqueue(bytes: 6_000, isFrame: false) }

    var needs = true, first = true
    var pacing = HomePacing()
    var requests = HomePacing.Requests()
    var forcedNext = true
    var sinceKey = 0
    var keyframesSent = 0
    var maxPending = link.pendingBytes
    var steadySent = 0
    var steadyDrops = 0

    let fps = 60
    let dt = 1.0 / Double(fps)
    for step in 0..<(8 * fps) {
        let t = Double(step) * dt
        let stalled = (t >= 3.0 && t < 3.2)
        link.drain(bytes: stalled ? 0 : Int(2_500_000.0 * dt)) { bytes, isKey, pending in
            pacing.bytesTaken(pendingBytes: pending)
            if isKey { pacing.keyframeTaken(bytes: bytes, pendingBytes: pending) }
        }

        let isKey = forcedNext || sinceKey >= fps * 4
        if isKey { forcedNext = false; sinceKey = 0 } else { sinceKey += 1 }
        let frameBytes = isKey ? 120_000 : 8_000

        if !useNewPacing {
            if isKey { link.enqueue(bytes: 86, isFrame: false) }
            if needs {
                if isKey {
                    link.enqueue(bytes: 86, isFrame: false)
                    link.enqueue(bytes: frameBytes, isFrame: true)
                    needs = false; first = false
                    keyframesSent += 1
                    if t >= 4.0 { steadySent += 1 }
                }
            } else if link.inflight > 2 && !isKey {
                needs = true
                forcedNext = true
                if t >= 4.0 { steadyDrops += 1 }
            } else {
                link.enqueue(bytes: frameBytes, isFrame: true)
                if isKey { keyframesSent += 1 }
                if t >= 4.0 { steadySent += 1 }
            }
        } else {
            if isKey { requests.recordKeyframe(now: t) }
            let mayAsk = requests.due(now: t)
            switch pacing.decide(
                isKeyframe: isKey,
                hasParameterSets: true,
                needsKeyframe: &needs,
                awaitingFirstKeyframe: &first,
                inflight: link.inflight,
                inflightFrames: link.inflightFrames,
                pendingBytes: link.pendingBytes,
                mayAskKeyframe: mayAsk
            ) {
            case .waitKey(_, let ask):
                if ask { requests.recordRequest(now: t); forcedNext = true }
            case .drop:
                if t >= 4.0 { steadyDrops += 1 }
            case .send(let sendPS):
                if sendPS { link.enqueue(bytes: 86, isFrame: false) }
                if isKey { pacing.keyframeSent(bytes: frameBytes); keyframesSent += 1 }
                link.enqueue(bytes: frameBytes, isFrame: true, isKeyframe: isKey)
                if t >= 4.0 { steadySent += 1 }
            }
        }
        maxPending = max(maxPending, link.pendingBytes)
    }
    return (keyframesSent, maxPending, steadySent / 4, steadyDrops)
}

do {
    let oldRun = simulateHotspot(useNewPacing: false)
    let newRun = simulateHotspot(useNewPacing: true)
    check(oldRun.keyframesSent > 150 && oldRun.steadyDrops > 80 && oldRun.maxPendingBytes > 3_000_000,
          "legacy Home rule enters 28-keyframes/s livelock (\(oldRun.keyframesSent) keys, \(oldRun.maxPendingBytes) B max, \(oldRun.steadyDrops) steady drops)")
    check(newRun.keyframesSent <= 6 && newRun.steadyDrops == 0 && newRun.steadyFPS == 60 && newRun.maxPendingBytes < 1_500_000,
          "HomePacing recovers cleanly to 60 fps and 0 steady drops (\(newRun.keyframesSent) keys, \(newRun.maxPendingBytes) B max)")
}

// MARK: Reference model across 20,000 seeded random runs

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func int(_ upper: Int) -> Int { Int(next() % UInt64(upper)) }
    mutating func chance(_ num: Int, _ den: Int) -> Bool { int(den) < num }
}

struct RefModel {
    var inFlight = 0
    var inFlightBytes = 0
    var floor = 0

    mutating func decide(isKey: Bool, hasPS: Bool, needs: inout Bool, first: inout Bool,
                         inflight: Int, frames: Int, pending: Int, mayAsk: Bool) -> HomePacing.Decision {
        floor = min(floor, max(0, pending))
        if needs {
            if !isKey {
                let count = !first
                let ask = !first && frames == 0 && pending <= 32 * 1024 && mayAsk
                return .waitKey(countWithheld: count, askKeyframe: ask)
            }
            if !hasPS { return .waitKey(countWithheld: !first, askKeyframe: false) }
            if first || (inFlight == 0 && frames == 0 && pending <= 256 * 1024) {
                needs = false; first = false
                return .send(sendParameterSets: true)
            }
            return .waitKey(countWithheld: true, askKeyframe: false)
        }
        if isKey && !hasPS {
            needs = true
            return .waitKey(countWithheld: true, askKeyframe: false)
        }
        let drop: Bool
        if isKey {
            drop = inFlight > 0 || inflight > 2 || pending > 256 * 1024
        } else if inFlight > 0 {
            drop = pending - inFlightBytes > 512 * 1024
        } else {
            drop = inflight > 2 && (floor == 0 || pending > floor + 128 * 1024)
        }
        if drop { needs = true; return .drop }
        return .send(sendParameterSets: isKey)
    }
}

do {
    var rng = SplitMix64(state: 0x5111_2026_1126)
    var mismatches = 0
    var invariantViolations = 0
    for _ in 0..<20_000 {
        var real = HomePacing()
        var ref = RefModel()
        var req = HomePacing.Requests()
        var needsReal = true, firstReal = true
        var needsRef = true, firstRef = true
        var hasPS = false
        var now = 0.0
        var activeKeys: [Int] = []
        var frames = 0
        var nonFrameMsgs = 0
        var pending = 0

        for _ in 0..<40 {
            now += Double(rng.int(350)) / 1000.0
            let op = rng.int(10)
            if op == 0 {
                if !activeKeys.isEmpty, rng.chance(1, 2) {
                    let i = rng.int(activeKeys.count)
                    let bytes = activeKeys.remove(at: i)
                    pending = max(0, pending - bytes)
                    frames = max(0, frames - 1)
                    real.bytesTaken(pendingBytes: pending)
                    real.keyframeTaken(bytes: bytes, pendingBytes: pending)
                    ref.floor = min(ref.floor, max(0, pending))
                    ref.inFlight -= 1
                    ref.inFlightBytes = max(0, ref.inFlightBytes - bytes)
                    if ref.inFlight == 0 { ref.floor = max(0, pending) }
                } else {
                    frames = max(0, frames - rng.int(3))
                    nonFrameMsgs = max(0, nonFrameMsgs - rng.int(5))
                    pending = (frames == 0 && nonFrameMsgs == 0) ? 0 : max(0, pending - rng.int(200_000))
                    real.bytesTaken(pendingBytes: pending)
                    ref.floor = min(ref.floor, max(0, pending))
                }
            } else if op == 1 {
                let otherInFlight = rng.chance(1, 4)
                let sReal = real.canAskOnSweep(needsKeyframe: needsReal, awaitingFirstKeyframe: firstReal,
                                               inflightFrames: frames, pendingBytes: pending)
                let sRef = needsRef && !firstRef && frames == 0 && pending <= 32 * 1024
                if sReal != sRef { mismatches += 1 }
                if sReal, req.due(now: now, otherHomeKeyframeInFlight: otherInFlight) {
                    req.recordRequest(now: now)
                }
            } else if op == 2 {
                needsReal = true; firstReal = true; hasPS = rng.chance(1, 2)
                needsRef = true; firstRef = true
            } else if op == 3 {
                let n = 1 + rng.int(12)
                nonFrameMsgs += n
                pending += n * 8_000
            } else {
                let isKey = rng.chance(1, 4)
                if isKey, rng.chance(4, 5) { hasPS = true }
                if isKey { req.recordKeyframe(now: now) }
                let otherInFlight = rng.chance(1, 5)
                let inflight = frames + nonFrameMsgs
                let mayAsk = req.due(now: now, otherHomeKeyframeInFlight: otherInFlight)
                let dReal = real.decide(isKeyframe: isKey, hasParameterSets: hasPS,
                                        needsKeyframe: &needsReal, awaitingFirstKeyframe: &firstReal,
                                        inflight: inflight, inflightFrames: frames, pendingBytes: pending,
                                        mayAskKeyframe: mayAsk)
                let dRef = ref.decide(isKey: isKey, hasPS: hasPS, needs: &needsRef, first: &firstRef,
                                      inflight: inflight, frames: frames, pending: pending, mayAsk: mayAsk)
                if dReal != dRef || needsReal != needsRef || firstReal != firstRef
                    || real.backlogFloor != ref.floor
                    || real.keyframesInFlight != ref.inFlight
                    || real.keyframeBytesInFlight != ref.inFlightBytes {
                    mismatches += 1
                }
                switch dReal {
                case .send(let sendPS):
                    if sendPS != isKey { invariantViolations += 1 }
                    if sendPS { nonFrameMsgs += 1; pending += 86 }
                    let sz = isKey ? (80_000 + rng.int(600_000)) : (4_000 + rng.int(40_000))
                    frames += 1
                    pending += sz
                    if isKey {
                        real.keyframeSent(bytes: sz)
                        ref.inFlight += 1
                        ref.inFlightBytes += sz
                        activeKeys.append(sz)
                    }
                case .waitKey(let countWithheld, let ask):
                    if firstReal && (countWithheld || ask) { invariantViolations += 1 }
                    if ask { req.recordRequest(now: now) }
                case .drop:
                    if !needsReal { invariantViolations += 1 }
                }
            }
        }
    }
    eq(mismatches, 0, "20,000 random runs match the reference model")
    eq(invariantViolations, 0, "20,000 random runs uphold every state invariant")
}

print("\nhome-pacing: \(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
