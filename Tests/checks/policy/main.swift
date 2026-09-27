// integrate-12 (2026-09-25): this branch merged with main after PR #13 (remote access). Everything above
// "// remote (the merge)" is follow-best-path's 277 at 8e1e4e3, unchanged; below, the merge's rule: a
// remote session is no candidate for these moves (PathInput.remote, Keep.remote).
// H13: iOSClient/DiscoveryPolicy.swift on its own (grown for the fixes after Noah's first sessions,
// and for their review: a move reaches the same host, and a listing that is another Mac is not retried;
// then for the connect screen's words, branch connection-method-labels: Wired, Wi-Fi, Direct or none;
// then for the Settings panel's route word, branch connection-route-in-settings; then for the wired
// fix, which readings of the session's path may change that word: sessionRoute, describesFlow; then
// for branch prefer-cable, the interface a row that says Wired is dialled on: dialInterface, wiredWait;
// then for branch follow-best-path, a live session moving to the cable that came or off the one that
// went: wifiInterface, PathSightings, pathGone, pathPlan; then for its review fixes: a connection over
// the cable that dies while the cable is still listed and nothing was said of its path is made again over
// the cable, a listing of the cable that reached another Mac is not tried again, and moves up that do not
// complete are tried less and less often: reconnectNow's method, refusedCable, upFailures, upWait).
// Everything above "// method" is the 111 checks of direct-wireless-fixes, unchanged, and everything
// above "// route" the 138 of connection-method-labels, and everything above "// sessionRoute" the 155 of
// connection-route-in-settings at fa642d2, and everything above "// dialInterface" the 174 of the wired
// fix at 68cbdd6, and everything above "// pathPlan" the 187 of prefer-cable at 9a7e724, and everything
// above "// review fixes" the 253 of follow-best-path at 75e4ff9 (reconnectNow now names its method; the
// grid also spans refused listings and failed moves up, and its rule for reconnectNow is the new one).
import Foundation
//   swiftc -O iOSClient/DiscoveryPolicy.swift Tests/checks/policy/main.swift -o .build/checks/policy/check && .build/checks/policy/check
typealias P = DiscoveryPolicy
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", name) } else { passes += 1; print("ok  ", name) } }
func input(_ now: Double) -> P.Input {
    P.Input(now: now, connected: false, onNetwork: [], remembered: [], searchingSince: 0, askedNearby: false, nearbyRunning: false, listed: 0)
}
func run(_ i: P.Input, from: Double, to: Double, _ body: (P.Output) -> Bool) -> Bool {
    var j = i; var t = from
    while t <= to { j.now = t; if !body(P.decide(j)) { return false }; t += 0.05 }
    return true
}

// decide
var i = input(0); i.onNetwork = ["Studio"]; i.listed = 1
check("home, default: never browses and never hints (0.4–60 s, the Mac listed at 0.4 s)",
      run(i, from: 0.4, to: 60) { !$0.browseNearby && !$0.showHint })
i = input(0); i.remembered = ["Studio"]
check("home, remembered: nothing before the network's 3 s", run(i, from: 0, to: 2.99) { !$0.browseNearby })
i.onNetwork = ["Studio"]; i.listed = 1
check("home, remembered and listed by 3 s: never browses", run(i, from: 0.4, to: 60) { !$0.browseNearby && !$0.showHint })
i = input(0); i.remembered = ["Studio"]
check("remembered Mac missing: not at 2.999 s", !P.decide({ var j = i; j.now = 2.999; return j }()).browseNearby)
check("remembered Mac missing: browses from exactly 3.0 s", P.decide({ var j = i; j.now = 3.0; return j }()).browseNearby)
check("remembered Mac missing: still at 30 s", P.decide({ var j = i; j.now = 30; return j }()).browseNearby)
i = input(0)
check("first use: no hint before 3 s", run(i, from: 0, to: 2.99) { !$0.showHint && !$0.browseNearby })
check("first use: the hint at 3 s", P.decide({ var j = i; j.now = 3.0; return j }()).showHint)
check("first use: never browses by itself", run(i, from: 0, to: 120) { !$0.browseNearby })
i.now = 3.5; i.askedNearby = true
check("Search Nearby: browses at once", P.decide(i).browseNearby)
check("Search Nearby: the hint stays (its button goes, since browsing)", P.decide(i).showHint)
i = input(1); i.askedNearby = true
check("Search Nearby before 3 s (the button is not shown then, but a call browses)", P.decide(i).browseNearby)
i = input(10); i.remembered = ["Studio"]; i.nearbyRunning = true; i.onNetwork = ["Studio"]; i.listed = 1
check("sticky: keeps browsing after the remembered Mac turns up on the network", P.decide(i).browseNearby)
i = input(10); i.nearbyRunning = true; i.listed = 2; i.onNetwork = ["Other"]
check("sticky: another Mac turning up does not stop it", P.decide(i).browseNearby)
i = input(10); i.remembered = ["Studio"]; i.askedNearby = true; i.nearbyRunning = true; i.connected = true
check("connected: never browses, never hints, no recheck", P.decide(i) == P.Output(browseNearby: false, showHint: false, recheckAt: nil))
i = input(3); i.remembered = ["A", "B"]; i.onNetwork = ["A"]; i.listed = 1
check("two remembered Macs, one missing: browses", P.decide(i).browseNearby)
i.onNetwork = ["A", "B"]; i.listed = 2
check("two remembered Macs, both listed: does not", !P.decide(i).browseNearby)
i = input(1)
check("recheckAt: the 3 s mark before it", P.decide(i).recheckAt == 3)
check("recheckAt: nil at it", P.decide({ var j = i; j.now = 3; return j }()).recheckAt == nil)
check("recheckAt: nil after it", P.decide({ var j = i; j.now = 7; return j }()).recheckAt == nil)
i = input(11); i.searchingSince = 10
check("recheckAt: counted from the last connection ending (13 s)", P.decide(i).recheckAt == 13)
i = input(12.9); i.searchingSince = 10; i.remembered = ["Studio"]
check("after a disconnect: the remembered Mac waits the network's 3 s again", !P.decide(i).browseNearby
      && P.decide({ var j = i; j.now = 13; return j }()).browseNearby)

// rows
func same(_ a: [(name: String, direct: Bool)], _ b: [(String, Bool)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.name == $1.0 && $0.direct == $1.1 }
}
check("rows: a network name is never direct, even when the nearby browser sees it on awdl0 only",
      same(P.rows(network: ["Studio"], nearby: [("Studio", ["awdl0"])]), [("Studio", false)]))
check("rows: nearby on [awdl0] is direct", same(P.rows(network: [], nearby: [("Mac mini", ["awdl0"])]), [("Mac mini", true)]))
check("rows: nearby on [llw0] is direct", same(P.rows(network: [], nearby: [("Mac mini", ["llw0"])]), [("Mac mini", true)]))
check("rows: nearby on [en0] is left out", same(P.rows(network: [], nearby: [("Mac mini", ["en0"])]), []))
check("rows: nearby on [en0, awdl0] is left out (the network browser lists it)", same(P.rows(network: [], nearby: [("Mac mini", ["en0", "awdl0"])]), []))
check("rows: nearby with no interface is left out", same(P.rows(network: [], nearby: [("Mac mini", [])]), []))
check("rows: order is the network's, then the nearby ones'",
      same(P.rows(network: ["B", "A"], nearby: [("D", ["awdl0"]), ("A", ["awdl0"]), ("C", ["awdl0"])]), [("B", false), ("A", false), ("D", true), ("C", true)]))
check("rows: a name listed twice appears once", same(P.rows(network: ["A", "A"], nearby: [("B", ["awdl0"]), ("B", ["awdl0"])]), [("A", false), ("B", true)]))
check("rows: \"MacBook Pro\" and \"MacBook Pro (2)\" are two Macs",
      same(P.rows(network: ["MacBook Pro"], nearby: [("MacBook Pro (2)", ["awdl0"])]), [("MacBook Pro", false), ("MacBook Pro (2)", true)]))

// remember
check("remember: true moves it to the front", P.remember(["A", "B"], mac: "B", directWireless: true) == ["B", "A"])
check("remember: true adds a new one at the front", P.remember(["A"], mac: "C", directWireless: true) == ["C", "A"])
check("remember: false removes it", P.remember(["A", "B"], mac: "A", directWireless: false) == ["B"])
check("remember: false for an unknown Mac changes nothing", P.remember(["A"], mac: "Z", directWireless: false) == ["A"])
check("remember: nil (an older host) keeps the list", P.remember(["A", "B"], mac: "A", directWireless: nil) == ["A", "B"])
let sixteen = (1...16).map { "M\($0)" }
let capped = P.remember(sixteen, mac: "New", directWireless: true)
check("remember: capped at 16, the oldest dropped", capped.count == 16 && capped.first == "New" && !capped.contains("M16"))
check("remember: an empty name changes nothing", P.remember(["A"], mac: "", directWireless: true) == ["A"])

// isPeerToPeer
check("isPeerToPeer: awdl0 and llw0", P.isPeerToPeer("awdl0") && P.isPeerToPeer("llw0"))
check("isPeerToPeer: not en0, utun3, lo0, bridge100", !P.isPeerToPeer("en0") && !P.isPeerToPeer("utun3") && !P.isPeerToPeer("lo0") && !P.isPeerToPeer("bridge100"))


// Local Network access denied (review fix): nothing to look for, no hint, no recheck
i = input(10); i.localNetworkDenied = true
check("denied: no hint with nothing listed after 3 s", P.decide(i) == P.Output(browseNearby: false, showHint: false, recheckAt: nil))
i = input(10); i.remembered = ["Studio"]; i.localNetworkDenied = true
check("denied: a remembered Mac missing does not browse", !P.decide(i).browseNearby)
i = input(10); i.askedNearby = true; i.nearbyRunning = true; i.localNetworkDenied = true
check("denied: stops a nearby search that runs (sticky or asked)", !P.decide(i).browseNearby)
i = input(1); i.localNetworkDenied = true
check("denied: no recheck before the 3 s mark either", P.decide(i).recheckAt == nil)
i = input(10); i.localNetworkDenied = false
check("allowed again: the hint as before", P.decide(i).showHint)
check("the memberwise default is not denied", input(10).localNetworkDenied == false)

// directSince (review fix)
check("directSince: a new Direct row starts now", P.directSince([:], rows: [("Mac mini", true)], now: 5) == ["Mac mini": 5])
check("directSince: kept while it stays Direct", P.directSince(["Mac mini": 5], rows: [("Mac mini", true)], now: 9) == ["Mac mini": 5])
check("directSince: dropped when the network lists it", P.directSince(["Mac mini": 5], rows: [("Mac mini", false)], now: 9).isEmpty)
check("directSince: dropped when it is gone", P.directSince(["Mac mini": 5], rows: [], now: 9).isEmpty)
check("directSince: network rows never get one", P.directSince([:], rows: [("Studio", false), ("Mac mini", true)], now: 2) == ["Mac mini": 2])
check("directSince: two Direct rows are timed apart",
      P.directSince(["A": 1], rows: [("A", true), ("B", true)], now: 4) == ["A": 1, "B": 4])

// reconnectRow: the network row at once; a Direct row only after directWait (6 s) and networkGrace
// (10 s) since the network last listed that Mac
func pick(_ network: String?, _ direct: String?, _ since: Double?, _ now: Double, left: Double? = nil) -> (String?, Double?) {
    let r = P.reconnectRow(network: network, direct: direct, directSince: since, networkLeftAt: left, now: now)
    return (r.take, r.recheckAt)
}
check("constants: directWait 6, networkGrace 10, moveAfter 2, moveRetry 10, networkFirst still 3",
      P.directWait == 6 && P.networkGrace == 10 && P.moveAfter == 2 && P.moveRetry == 10 && P.networkFirst == 3)
check("reconnectRow: the network row at once", pick("Studio", nil, nil, 0) == ("Studio", nil))
check("reconnectRow: the network row wins even beside a waiting Direct one", pick("Studio", "Studio", 10, 10) == ("Studio", nil))
check("reconnectRow: the network row wins however recently it left", pick("Studio", "Studio", 10, 10, left: 9.9) == ("Studio", nil))
check("reconnectRow: nothing listed, nothing to wait for", pick(nil, nil, nil, 0) == (nil, nil))
check("reconnectRow: a new Direct row waits, recheck at its 6 s", pick(nil, "Studio", 10, 10) == (nil, 16))
check("reconnectRow: still waits at 5.999 s", pick(nil, "Studio", 10, 15.999) == (nil, 16))
check("reconnectRow: takes it at exactly 6.0 s (never listed on the network)", pick(nil, "Studio", 10, 16) == ("Studio", nil))
check("reconnectRow: and later", pick(nil, "Studio", 10, 40) == ("Studio", nil))
check("reconnectRow: a Direct row without a first-seen time is never taken", pick(nil, "Studio", nil, 99) == (nil, nil))
check("reconnectRow: the network listed it 2 s before: waits for its 10 s", pick(nil, "Studio", 10, 16, left: 8) == (nil, 18))
check("reconnectRow: ...and takes it then", pick(nil, "Studio", 10, 18, left: 8) == ("Studio", nil))
check("reconnectRow: listed long ago: only the Direct row's own 6 s", pick(nil, "Studio", 10, 16, left: -100) == ("Studio", nil))

// sightings
var s = P.NetworkSightings()
s = P.sightings(s, listed: ["A"], now: 1)
check("sightings: a newly listed Mac is listed since now", s.since == ["A": 1] && s.leftAt.isEmpty)
s = P.sightings(s, listed: ["A"], now: 5)
check("sightings: kept while listed", s.since == ["A": 1])
s = P.sightings(s, listed: [], now: 7)
check("sightings: gone: leftAt is the moment it went", s.since.isEmpty && s.leftAt == ["A": 7])
s = P.sightings(s, listed: [], now: 9)
check("sightings: still gone: leftAt kept", s.leftAt == ["A": 7])
s = P.sightings(s, listed: ["A"], now: 9.5)
check("sightings: back: since starts again, leftAt dropped", s.since == ["A": 9.5] && s.leftAt.isEmpty)
s = P.sightings(P.NetworkSightings(since: [:], leftAt: ["A": 0]), listed: [], now: 10)
check("sightings: leftAt forgotten once networkGrace has passed", s.leftAt.isEmpty)
s = P.sightings(P.NetworkSightings(since: [:], leftAt: ["A": 0]), listed: [], now: 9.99)
check("sightings: ...not before", s.leftAt == ["A": 0])
s = P.sightings(P.NetworkSightings(since: ["A": 1, "B": 2], leftAt: [:]), listed: ["B", "C"], now: 4)
check("sightings: several Macs are timed apart", s.since == ["B": 2, "C": 4] && s.leftAt == ["A": 4])

// moveToNetwork
func mv(_ since: Double?, _ last: Double?, _ now: Double, refused: Double? = nil) -> (Bool, Double?) {
    let r = P.moveToNetwork(listedSince: since, lastAttempt: last, refusedListing: refused, now: now); return (r.move, r.recheckAt)
}
check("move: not listed on the network, nothing to do", mv(nil, nil, 5) == (false, nil))
check("move: listed at 5, look again at 7", mv(5, nil, 5) == (false, 7))
check("move: not at 6.999", mv(5, nil, 6.999) == (false, 7))
check("move: at exactly 7.0", mv(5, nil, 7) == (true, nil))
check("move: a try at 7 that did not complete: the next at 17", mv(5, 7, 8) == (false, 17) && mv(5, 7, 17) == (true, nil))
check("move: an old try does not hold a new listing back", mv(30, 7, 32) == (true, nil))
check("move: a listing found to be another Mac is never tried again, and nothing to look again for",
      mv(5, 7, 30, refused: 5) == (false, nil) && mv(5, nil, 7, refused: 5) == (false, nil))
check("move: ...a new listing of that name is: its own 2 s, and 10 s after the refused try",
      mv(20, 7, 22, refused: 5) == (true, nil) && mv(8, 7, 10, refused: 5) == (false, 17) && mv(8, 7, 17, refused: 5) == (true, nil))
check("move: no refusal, as before", mv(5, nil, 7, refused: nil) == (true, nil))

// sameHost (review fix): the window lists' launch IDs, never the Bonjour name
check("sameHost: the same launch ID", P.sameHost("A", "A"))
check("sameHost: another launch ID is another host (another Mac, or another run)", !P.sameHost("A", "B"))
check("sameHost: an ID against none is two hosts, either way round", !P.sameHost("A", nil) && !P.sameHost(nil, "A"))
check("sameHost: two hosts from before the ID are taken at their name, as before", P.sameHost(nil, nil))

// The model: StreamClient's glue (recomputeMacs → reconnectIfListed / moveToNetworkIfListed) over
// time, stepped every 50 ms like its timers, against scripted browser results.
struct Model {
    var directSince: [String: Double] = [:]
    var sightings = P.NetworkSightings()
    var connected = false
    var direct = false
    var wanted: String? = nil          // reconnectTo, or the connected Mac's name (hostName)
    var lastAttempt: Double? = nil
    var failMoves = 0                  // this many moves fail before one completes
    var sessionHost: String? = "A"     // the launch ID in the session's window lists
    var networkHost: (Double) -> String? = { _ in "A" }   // what a move's first window list shows at t
    var refused: Double? = nil         // refusedListing
    var events: [String] = []
    mutating func step(_ now: Double, network: [String], nearby: [(name: String, interfaces: [String])]) {
        let rows = P.rows(network: network, nearby: nearby)
        directSince = P.directSince(directSince, rows: rows, now: now)
        sightings = P.sightings(sightings, listed: Set(network), now: now)
        guard let name = wanted else { return }
        if !connected {
            let net = rows.first { $0.name == name && !$0.direct }.map { _ in "network" }
            let dir = rows.first { $0.name == name && $0.direct }
            let r = P.reconnectRow(network: net, direct: dir.map { _ in "direct" }, directSince: dir.flatMap { directSince[$0.name] },
                                   networkLeftAt: sightings.leftAt[name], now: now)
            if let take = r.take { connected = true; direct = take == "direct"; lastAttempt = nil; events.append(String(format: "%.2f %@", now, take)) }
        } else if direct, rows.contains(where: { $0.name == name && !$0.direct }) {
            let r = P.moveToNetwork(listedSince: sightings.since[name], lastAttempt: lastAttempt, refusedListing: refused, now: now)
            if r.move {
                lastAttempt = now
                if !P.sameHost(sessionHost, networkHost(now)) {
                    refused = sightings.since[name]; events.append(String(format: "%.2f refused", now))
                } else if failMoves > 0 { failMoves -= 1; events.append(String(format: "%.2f move failed", now)) }
                else { direct = false; events.append(String(format: "%.2f moved", now)) }
            }
        }
    }
    mutating func lose(_ now: Double) { connected = false; direct = false; lastAttempt = nil; refused = nil; events.append(String(format: "%.2f lost", now)) }
}
/// Runs `m` from `from` to `to` in 50 ms steps; `script(t)` gives the browsers' results at t.
func simulate(_ m: inout Model, from: Double, to: Double, _ script: (Double) -> (network: [String], nearby: [(name: String, interfaces: [String])])) {
    var i = 0
    while true {
        let t = ((from + Double(i) * 0.05) * 1000).rounded() / 1000   // an exact 50 ms grid
        if t > to + 1e-9 { break }
        let r = script(t)
        m.step(t, network: r.network, nearby: r.nearby)
        i += 1
    }
}
let awdl: [(name: String, interfaces: [String])] = [("Studio", ["awdl0"])]
/// Streaming over the network until 0, when the connection drops; the network row is absent on
/// [0, gap) (a listener swap's blink, a lost announcement) while the nearby browser reports the
/// Mac on awdl0 alone from `directFrom` on.
func blink(_ gap: Double, directFrom: Double = 0) -> Model {
    var m = Model(); m.wanted = "Studio"; m.connected = true; m.direct = false
    simulate(&m, from: -30, to: -0.05) { _ in (["Studio"], []) }
    m.lose(0)
    simulate(&m, from: 0, to: 30) { t in (t < gap ? [] : ["Studio"], t >= directFrom ? awdl : []) }
    return m
}
var m = blink(1.5)
check("model: the network row blinks off for 1.5 s beside a Direct row: back over the network at 1.5 s, never Direct (\(m.events))",
      m.events == ["0.00 lost", "1.50 network"])
m = blink(4)
check("model: ...for 4 s: over the network at 4.0 s, never Direct (\(m.events))", m.events == ["0.00 lost", "4.00 network"])
m = blink(7)
check("model: ...for 7 s (past directWait, inside networkGrace): over the network at 7.0 s (\(m.events))",
      m.events == ["0.00 lost", "7.00 network"])
m = blink(99)
check("model: the network row absent for good: Direct allowed at exactly 10.0 s (\(m.events))", m.events == ["0.00 lost", "10.00 direct"])
m = blink(99, directFrom: 3.5)
check("model: ...with the nearby browser reporting awdl0 only from 3.5 s: still 10.0 s (\(m.events))", m.events == ["0.00 lost", "10.00 direct"])
m = blink(99, directFrom: 5)
check("model: ...from 5 s: its own 6 s decide, 11.0 s (\(m.events))", m.events == ["0.00 lost", "11.00 direct"])

// Connected directly (a café, or a reconnect that landed on AWDL), then the network lists the Mac.
func directThen(_ script: @escaping (Double) -> [String], failMoves: Int = 0) -> Model {
    var m = Model(); m.wanted = "Studio"; m.connected = true; m.direct = true; m.failMoves = failMoves
    simulate(&m, from: 0, to: 40) { t in (script(t), awdl) }
    return m
}
m = directThen { $0 >= 5 ? ["Studio"] : [] }
check("model: connected directly, the network row appears at 5 s: moved at exactly 7.0 s (\(m.events))", m.events == ["7.00 moved"])
m = directThen { ($0 >= 5 && !($0 >= 6 && $0 < 6.3)) ? ["Studio"] : [] }
check("model: ...a blink at 6–6.3 s restarts the 2 s: moved at 8.3 s (\(m.events))", m.events == ["8.30 moved"])
m = directThen({ $0 >= 5 ? ["Studio"] : [] }, failMoves: 1)
check("model: ...the first move fails: the next try 10 s later, at 17.0 s (\(m.events))", m.events == ["7.00 move failed", "17.00 moved"])
m = directThen { _ in ["Other"] }
check("model: connected directly, another Mac on the network: never moves (\(m.events))", m.events.isEmpty)
m = directThen { $0 >= 5 ? ["Studio (2)"] : [] }
check("model: ...a Mac named \"Studio (2)\" is not this one: never moves (\(m.events))", m.events.isEmpty)

// The same name, another Mac (review fix): connected directly to host A, while the network lists a
// "Studio" that is host B (it shares no link with A, so mDNS renamed neither).
func sameName(_ script: @escaping (Double) -> [String], host: @escaping (Double) -> String?, session: String? = "A") -> Model {
    var m = Model(); m.wanted = "Studio"; m.connected = true; m.direct = true
    m.sessionHost = session; m.networkHost = host
    simulate(&m, from: 0, to: 40) { t in (script(t), awdl) }
    return m
}
m = sameName({ $0 >= 5 ? ["Studio"] : [] }, host: { _ in "B" })
check("model: another Mac named Studio on the network from 5 s: one try at 7.0 s, refused, none again to 40 s (\(m.events))",
      m.events == ["7.00 refused"])
m = sameName({ ($0 >= 5 && !($0 >= 20 && $0 < 20.3)) ? ["Studio"] : [] }, host: { _ in "B" })
check("model: ...its row blinks at 20–20.3 s: a new listing, tried at 22.3 s and refused again (\(m.events))",
      m.events == ["7.00 refused", "22.30 refused"])
m = sameName({ ($0 >= 5 && !($0 >= 20 && $0 < 20.3)) ? ["Studio"] : [] }, host: { $0 < 20 ? "B" : "A" })
check("model: ...B leaves at 20 s and this Mac is listed at 20.3 s: moved at 22.3 s (\(m.events))",
      m.events == ["7.00 refused", "22.30 moved"])
m = sameName({ $0 >= 5 ? ["Studio"] : [] }, host: { _ in nil }, session: nil)
check("model: two hosts from before the ID: moved at 7.0 s by name, as before (\(m.events))", m.events == ["7.00 moved"])
m = sameName({ $0 >= 5 ? ["Studio"] : [] }, host: { _ in nil })
check("model: this session's host has an ID and the network's Studio none (an older Sill): refused (\(m.events))",
      m.events == ["7.00 refused"])
m = sameName({ $0 >= 5 ? ["Studio"] : [] }, host: { _ in "A" })
check("model: the same host on the network: moved at exactly 7.0 s, as before (\(m.events))", m.events == ["7.00 moved"])

// The café: no network row ever for this Mac (another Mac listed), the Mac Direct from 3.5 s.
var cafe = Model(); cafe.wanted = "Studio"
simulate(&cafe, from: 0, to: 30) { t in (["Other"], t >= 3.5 ? awdl : []) }
check("model: café, never on the network: Direct at 9.5 s, 6 s after its row appeared (\(cafe.events))", cafe.events == ["9.50 direct"])

// A flapping Direct row starts its 6 s again; another Mac's Direct row never stands in.
var flap = Model(); flap.wanted = "Studio"
simulate(&flap, from: 0, to: 30) { t in (["Other"], (t < 1 || t >= 1.5) ? awdl : []) }
check("model: café, the Direct row gone at 1–1.5 s: taken at 7.5 s (\(flap.events))", flap.events == ["7.50 direct"])
var names = Model(); names.wanted = "Studio"
simulate(&names, from: 0, to: 30) { _ in ([], [("Studio (2)", ["awdl0"])]) }
check("model: names: \"Studio (2)\" Direct is not the wanted Mac (\(names.events))", names.events.isEmpty)

// The home race: Sill relaunched (the Mac away for a minute), awdl0 reported first, the network row later.
func homeRace(_ netAt: Double) -> Model {
    var m = Model(); m.wanted = "Studio"; m.connected = true          // streaming over the network
    simulate(&m, from: -120, to: -60.05) { _ in (["Studio"], []) }
    m.lose(-60)                                                        // Sill quit: the connection and the listing go
    simulate(&m, from: -60, to: -0.05) { _ in ([], []) }
    simulate(&m, from: 0, to: 30) { t in (t >= netAt ? ["Studio"] : [], awdl) }   // relaunched: awdl0 first
    return m
}
for at in [0.8, 2.9, 5.9] {
    m = homeRace(at)
    check("model: home race, the network row \(at) s after awdl0: taken over the network (\(m.events))", m.events == ["-60.00 lost", String(format: "%.2f network", at)])
}
m = homeRace(6.1)
check("model: home race, the network row only at 6.1 s: Direct at 6.0 s, moved to the network at 8.1 s (\(m.events))",
      m.events == ["-60.00 lost", "6.00 direct", "8.10 moved"])

// Noah's 15:43 (inferred): the Wi-Fi connection evicted at 0 while the network browser lost the Mac
// too; nearby reports awdl0 from 3.5 s; the network lists the Mac again at 20 s.
m = Model(); m.wanted = "Studio"; m.connected = true
simulate(&m, from: -30, to: -0.05) { _ in (["Studio"], []) }
m.lose(0)
simulate(&m, from: 0, to: 40) { t in (t >= 20 ? ["Studio"] : [], t >= 3.5 ? awdl : []) }
check("model: 15:43 replay: Direct at 10.0 s, back on the network at 22.0 s (\(m.events))", m.events == ["0.00 lost", "10.00 direct", "22.00 moved"])

// method (connection-method-labels): the word each row ends in, from the interfaces its own browser
// saw its Mac on. Noah, 2026-09-24: "Wi-Fi", "Wired" or "Direct", never the network's name.
typealias I = P.Interface
func ifs(_ list: [(String, I.Kind)]) -> [I] { list.map { I(name: $0.0, type: $0.1) } }
func net(_ list: [(String, I.Kind)]) -> P.Method? { P.method(direct: false, interfaces: ifs(list)) }
let en0: (String, I.Kind) = ("en0", .wifi), en2: (String, I.Kind) = ("en2", .wiredEthernet)
let awdl0: (String, I.Kind) = ("awdl0", .wifi), llw0: (String, I.Kind) = ("llw0", .wifi)
check("method: the words are Wired, Wi\u{2011}Fi and Direct", P.Method.wired.word == "Wired" && P.Method.direct.word == "Direct"
      && P.Method.wifi.word == "Wi\u{2011}Fi")
check("method: Wi-Fi's hyphen is U+2011, which never breaks a line (no U+002D, no U+2010)",
      P.Method.wifi.word.unicodeScalars.map(\.value) == [0x57, 0x69, 0x2011, 0x46, 0x69])
check("method: wired only (the cable, Wi-Fi off): Wired", net([en2]) == .wired)
check("method: Wi-Fi only: Wi-Fi", net([en0]) == .wifi)
check("method: both (the cable plugged in at home): Wired, in either order", net([en0, en2]) == .wired && net([en2, en0]) == .wired)
check("method: several of each: Wired", net([en0, ("en3", .wiredEthernet), en2, ("en1", .wifi)]) == .wired)
check("method: the Mac's own service as the simulator sees it (lo0 loopback, en0 wifi): Wi-Fi", net([("lo0", .loopback), en0]) == .wifi)
check("method: an unknown type alone: no word", net([("anpi0", .other)]) == nil)
check("method: a VPN, cellular or loopback alone: no word",
      net([("utun3", .other)]) == nil && net([("pdp_ip0", .cellular)]) == nil && net([("lo0", .loopback)]) == nil)
check("method: unknown types together: no word", net([("utun3", .other), ("pdp_ip0", .cellular), ("lo0", .loopback)]) == nil)
check("method: an unknown type beside Wi-Fi: Wi-Fi; beside a wired one: Wired",
      net([("anpi0", .other), en0]) == .wifi && net([("anpi0", .other), en2]) == .wired)
check("method: no interface reported: no word", net([]) == nil)
check("method: a network result on awdl0 or llw0 alone (typed wifi): no word, neither Wi-Fi nor Direct",
      net([awdl0]) == nil && net([llw0]) == nil && net([awdl0, llw0]) == nil)
check("method: awdl0 beside en0: Wi-Fi; beside the cable: Wired", net([awdl0, en0]) == .wifi && net([en2, awdl0]) == .wired)
check("method: a Direct row is Direct (awdl0, llw0, both)", P.method(direct: true, interfaces: ifs([awdl0])) == .direct
      && P.method(direct: true, interfaces: ifs([llw0])) == .direct && P.method(direct: true, interfaces: ifs([awdl0, llw0])) == .direct)
check("method: a Direct row is Direct whatever it is handed", P.method(direct: true, interfaces: []) == .direct
      && P.method(direct: true, interfaces: ifs([en0, en2])) == .direct)
let kinds: [I.Kind] = [.wifi, .wiredEthernet, .cellular, .loopback, .other]
let ifNames = ["en0", "en2", "awdl0", "llw0", "lo0", "utun3", "anpi0"]
var neverDirect = true, onlyFromTheirType = true, networkCount = 0
for a in ifNames { for ka in kinds { for b in ifNames { for kb in kinds {
    let list = [I(name: a, type: ka), I(name: b, type: kb)]
    let m = P.method(direct: false, interfaces: list)
    networkCount += 1
    if m == .direct { neverDirect = false }
    let usable = list.filter { !P.isPeerToPeer($0.name) }
    let want: P.Method? = usable.contains { $0.type == .wiredEthernet } ? .wired : usable.contains { $0.type == .wifi } ? .wifi : nil
    if m != want { onlyFromTheirType = false; print("   mismatch:", list, m as Any, want as Any) }
}}}}
check("method: a network row is never Direct (every pair of \(ifNames.count) names × \(kinds.count) types, \(networkCount) lists)", neverDirect)
check("method: every pair: Wired iff a wired interface not peer-to-peer, else Wi-Fi iff a Wi-Fi one, else none", onlyFromTheirType)

// The glue, as StreamClient.recomputeMacs does it: the rows, each with the word from its own
// browser's result (the first with that name, whose endpoint the row connects to).
func labeled(network: [(String, [I])], nearby: [(String, [I])]) -> [(String, P.Method?)] {
    P.rows(network: network.map(\.0), nearby: nearby.map { ($0.0, $0.1.map(\.name)) }).compactMap { row in
        guard let seen = (row.direct ? nearby : network).first(where: { $0.0 == row.name }) else { return nil }
        return (row.name, P.method(direct: row.direct, interfaces: seen.1))
    }
}
func same(_ a: [(String, P.Method?)], _ b: [(String, P.Method?)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
}
check("rows+method: wired + direct (the network on the cable, nearby on awdl0): one network row, Wired",
      same(labeled(network: [("Studio", ifs([en2]))], nearby: [("Studio", ifs([awdl0]))]), [("Studio", .wired)]))
check("rows+method: ...nearby on [en2, awdl0] too: Wired",
      same(labeled(network: [("Studio", ifs([en2]))], nearby: [("Studio", ifs([en2, awdl0]))]), [("Studio", .wired)]))
check("rows+method: Wi-Fi + direct: one network row, Wi-Fi",
      same(labeled(network: [("Studio", ifs([en0]))], nearby: [("Studio", ifs([awdl0]))]), [("Studio", .wifi)]))
check("rows+method: the network on an unknown interface, nearby on awdl0: a network row with no word, never Direct",
      same(labeled(network: [("Studio", ifs([("anpi0", .other)]))], nearby: [("Studio", ifs([awdl0]))]), [("Studio", nil)]))
check("rows+method: the network with no interface, nearby on awdl0: a network row with no word",
      same(labeled(network: [("Studio", [])], nearby: [("Studio", ifs([awdl0]))]), [("Studio", nil)]))
check("rows+method: nearby alone on awdl0: Direct", same(labeled(network: [], nearby: [("Mac mini", ifs([awdl0]))]), [("Mac mini", .direct)]))
check("rows+method: nearby alone on [en0] or []: no row, as before",
      same(labeled(network: [], nearby: [("Mac mini", ifs([en0]))]), []) && same(labeled(network: [], nearby: [("Mac mini", [])]), []))
check("rows+method: a list of every kind, in rows' order",
      same(labeled(network: [("A", ifs([en2, en0])), ("B", ifs([en0])), ("C", [])], nearby: [("D", ifs([awdl0])), ("B", ifs([awdl0])), ("E", ifs([en0]))]),
           [("A", .wired), ("B", .wifi), ("C", nil), ("D", .direct)]))
var words: [P.Method?] = []
for step in [[en0], [en0, en2], [en2], [en0, en2], [en0]] {   // cable in, Wi-Fi off, Wi-Fi on, cable out
    words.append(labeled(network: [("Studio", ifs(step))], nearby: []).first?.1 ?? nil)
}
check("rows+method: the cable in and out, Wi-Fi off and on: Wi-Fi, Wired, Wired, Wired, Wi-Fi (\(words.map { $0?.word ?? "none" }))",
      words == [.wifi, .wired, .wired, .wired, .wifi])


// route (connection-route-in-settings): the word the Settings panel's readout ends in, from the
// session connection's own path: the Mac's scoped address first, else the path's interfaces when
// they all agree, else none. Noah, 2026-09-24: the path the live session uses, next to the bitrate.
func one(_ i: (String, I.Kind)) -> I { I(name: i.0, type: i.1) }
let lo0: (String, I.Kind) = ("lo0", .loopback)
check("route: over the cable, the Mac's address scoped to a wired interface: Wired", P.route(scope: one(en2), path: ifs([en2])) == .wired)
check("route: over AWDL, the Mac's address on awdl0 (typed wifi): Direct", P.route(scope: one(awdl0), path: ifs([awdl0])) == .direct)
check("route: over llw0, with no path: Direct", P.route(scope: one(llw0), path: []) == .direct)
check("route: a Wi-Fi link-local address of the Mac: Wi-Fi", P.route(scope: one(en0), path: ifs([en0])) == .wifi)
check("route: the scope decides over the path",
      P.route(scope: one(en2), path: ifs([en0])) == .wired && P.route(scope: one(en0), path: ifs([en2, awdl0])) == .wifi
      && P.route(scope: one(awdl0), path: ifs([en0, lo0])) == .direct)
check("route: a scope of no known kind: no word, whatever the path says",
      P.route(scope: I(name: "anpi0", type: .other), path: ifs([en0])) == nil && P.route(scope: one(lo0), path: ifs([en0])) == nil)
check("route: no scope, a Wi-Fi path (IPv4 to the Mac): Wi-Fi", P.route(scope: nil, path: ifs([en0])) == .wifi)
check("route: no scope, a wired path: Wired", P.route(scope: nil, path: ifs([en2])) == .wired)
check("route: no scope, the simulator to this Mac's own address (lo0 alone): no word", P.route(scope: nil, path: ifs([lo0])) == nil)
check("route: no scope, a path that says two things: no word",
      P.route(scope: nil, path: ifs([en0, lo0])) == nil && P.route(scope: nil, path: ifs([en0, en2])) == nil
      && P.route(scope: nil, path: ifs([en2, en0])) == nil && P.route(scope: nil, path: ifs([awdl0, en0])) == nil)
check("route: no scope, the same kind twice agrees", P.route(scope: nil, path: ifs([en0, ("en1", .wifi)])) == .wifi
      && P.route(scope: nil, path: ifs([awdl0, llw0])) == .direct)
check("route: no scope, awdl0 alone: Direct", P.route(scope: nil, path: ifs([awdl0])) == .direct)
check("route: no scope, no path: no word", P.route(scope: nil, path: []) == nil)
check("route: no scope, cellular, a VPN or an unknown type: no word",
      P.route(scope: nil, path: ifs([("pdp_ip0", .cellular)])) == nil && P.route(scope: nil, path: ifs([("utun3", .other)])) == nil
      && P.route(scope: nil, path: ifs([("anpi0", .other)])) == nil)
var allOne = true, oneCount = 0
for name in ifNames + ["anri0", "en7"] { for kind in kinds {
    oneCount += 1
    let want: P.Method? = P.isPeerToPeer(name) ? .direct : kind == .wiredEthernet ? .wired : kind == .wifi ? .wifi : nil
    if P.method(of: I(name: name, type: kind)) != want { allOne = false; print("   mismatch:", name, kind) }
    // A scoped address decides alone, and the same interface as the whole path says the same.
    if P.route(scope: I(name: name, type: kind), path: ifs([lo0, en0, en2])) != want { allOne = false; print("   scope mismatch:", name, kind) }
    if P.route(scope: nil, path: [I(name: name, type: kind)]) != want { allOne = false; print("   path mismatch:", name, kind) }
}}
check("route: every name × type (\(oneCount)): Direct by name, else Wired for wired Ethernet, Wi-Fi for Wi-Fi, else none; alone or scoped", allOne)
var agreeAll = true, pairCount = 0
for a in ifNames { for ka in kinds { for b in ifNames { for kb in kinds {
    pairCount += 1
    let x = P.method(of: I(name: a, type: ka)), y = P.method(of: I(name: b, type: kb))
    if P.route(scope: nil, path: [I(name: a, type: ka), I(name: b, type: kb)]) != (x == y ? x : nil) { agreeAll = false }
}}}}
check("route: every unscoped pair (\(pairCount)): their word when both agree, else none", agreeAll)
// The connect screen's word and the panel's may differ for one Mac, and must: a row says where the
// browser saw the Mac (Wired beats Wi-Fi), the panel what the connection runs on.
check("route vs method: seen on the cable and Wi-Fi (row: Wired), connected over Wi-Fi (panel: Wi-Fi)",
      P.method(direct: false, interfaces: ifs([en0, en2])) == .wired && P.route(scope: nil, path: ifs([en0])) == .wifi)

// sessionRoute (wired fix, 2026-09-25): which readings of the session connection's path may change
// the word. Noah's iPad on the cable with Wi-Fi on: the reading at .ready had the Mac's address on
// en2 (wiredEthernet) and said Wired; later path updates without the Mac's address (a Bonjour
// connection's updates name the service, or nothing) listed "en0 (wifi), en0 (wifi)", which made it
// Wi-Fi while the connection stayed on en2 (the Mac saw it on %en14 at 1-3 ms throughout). iPadOS
// names its ends of the cable anpi0 and en2, both wired Ethernet.
let anpi0: (String, I.Kind) = ("anpi0", .wiredEthernet)
/// One reading, as StreamClient.setRoute takes it.
struct Reading { var fresh = false; var address = true; var satisfied = true; var scope: I? = nil; var local: I? = nil; var path: [I] = [] }
func take(_ current: P.Method?, _ r: Reading) -> P.Method? {
    P.sessionRoute(current: current, scope: r.scope, local: r.local, path: r.path,
                   describesFlow: P.describesFlow(fresh: r.fresh, hasAddress: r.address, satisfied: r.satisfied))
}
func replay(_ readings: [Reading]) -> [P.Method?] {
    var word: P.Method? = nil, out: [P.Method?] = []
    for r in readings { word = take(word, r); out.append(word) }
    return out
}
let firstOnCable = Reading(fresh: true, scope: one(en2), path: ifs([en2]))
let defaultRoute = Reading(address: false, path: ifs([en0, en0]))   // what iPadOS sent later (satisfied)
check("session: the cable's first reading (the Mac's address on en2, path en2): Wired", take(nil, firstOnCable) == .wired)
check("session: a later update without the Mac's address listing en0, en0 keeps Wired", take(.wired, defaultRoute) == .wired)
check("session: a later update without the Mac's address and no interfaces keeps Wired (satisfied or not)",
      take(.wired, Reading(address: false, path: [])) == .wired && take(.wired, Reading(address: false, satisfied: false, path: [])) == .wired)
check("session: 2026-09-25 replayed (ready on en2, then en0+en0 updates, an empty one): Wired throughout",
      replay([firstOnCable, defaultRoute, defaultRoute, Reading(address: false, path: []), defaultRoute]) == [.wired, .wired, .wired, .wired, .wired])
check("session: an unsatisfied update keeps the word, even one naming the Mac's address",
      take(.wired, Reading(satisfied: false, scope: one(en0), path: ifs([en0]))) == .wired
      && take(.wifi, Reading(satisfied: false, scope: one(awdl0), path: ifs([awdl0]))) == .wifi)
check("session: over AWDL (the Mac's address on awdl0): Direct, at the first reading or a later update",
      take(nil, Reading(fresh: true, scope: one(awdl0), path: ifs([awdl0]))) == .direct
      && take(.wifi, Reading(scope: one(awdl0), path: ifs([awdl0]))) == .direct)
check("session: over Wi-Fi (the Mac's address on en0): Wi-Fi, at the first reading or a later update",
      take(nil, Reading(fresh: true, scope: one(en0), path: ifs([en0]))) == .wifi
      && take(.wired, Reading(scope: one(en0), path: ifs([en0]))) == .wifi)
check("session: a later update that describes the connection changes the word (Wi-Fi to Wired on en2)",
      take(.wifi, Reading(scope: one(en2), path: ifs([en2]))) == .wired)
check("session: a move's hand-over replaces the direct connection's word: Wi-Fi, Wired, or none",
      take(.direct, Reading(fresh: true, scope: one(en0), path: ifs([en0]))) == .wifi
      && take(.direct, Reading(fresh: true, scope: one(en2), path: ifs([en2]))) == .wired
      && take(.direct, Reading(fresh: true, address: false, path: ifs([lo0]))) == nil)
check("session: a fresh reading counts without an address and unsatisfied (ready and hand-over always describe it)",
      take(.wired, Reading(fresh: true, address: false, satisfied: false, path: ifs([en0]))) == .wifi
      && take(.wifi, Reading(fresh: true, address: false, satisfied: false, path: [])) == nil)
check("session: the synthetic host by 127.0.0.1 (no scope, lo0 alone): no word, as before",
      take(nil, Reading(fresh: true, path: ifs([lo0]))) == nil)
check("session: iPadOS's ends of the cable (anpi0, en2, both wired): Wired, scoped or by path; the row too",
      take(nil, Reading(fresh: true, scope: one(anpi0), path: ifs([anpi0]))) == .wired
      && take(nil, Reading(fresh: true, path: ifs([anpi0, en2]))) == .wired && net([anpi0, en2, en0]) == .wired)
// IPv4: the Mac's address carries no scope, so this device's own address's interface is the witness
// before the path's list.
check("session: IPv4 over the cable (no scope, this device's address on en2): Wired, whatever the path lists",
      take(nil, Reading(fresh: true, local: one(en2), path: ifs([en0, en0]))) == .wired
      && take(nil, Reading(fresh: true, local: one(en2), path: [])) == .wired)
check("session: IPv4 over Wi-Fi (this device's address on en0): Wi-Fi, whatever the path lists",
      take(nil, Reading(fresh: true, local: one(en0), path: ifs([en0]))) == .wifi
      && take(nil, Reading(fresh: true, local: one(en0), path: ifs([en2]))) == .wifi)
check("session: the Mac's scope beats this device's address",
      take(nil, Reading(fresh: true, scope: one(en0), local: one(en2), path: ifs([en2]))) == .wifi
      && take(nil, Reading(fresh: true, scope: one(en2), local: one(en0), path: ifs([en0]))) == .wired)
check("session: neither address names an interface: the path's list, when it agrees",
      take(nil, Reading(fresh: true, path: ifs([en2]))) == .wired && take(nil, Reading(fresh: true, path: ifs([en0, en2]))) == nil)
check("session: an update without the Mac's address keeps the word whatever this device's address says",
      take(.wired, Reading(address: false, local: one(en0), path: ifs([en0]))) == .wired)
// Exhaustive: a reading that does not describe the connection never changes the word, and one that
// does gives route(scope ?? local, path) whatever the word was.
let sessionWords: [P.Method?] = [nil, .wired, .wifi, .direct]
let witnesses: [I?] = [nil, one(en0), one(en2), one(awdl0), one(anpi0), one(lo0), I(name: "utun3", type: .other)]
let pathLists: [[I]] = [[], ifs([en0]), ifs([en0, en0]), ifs([en2]), ifs([anpi0, en2]), ifs([en0, en2]), ifs([awdl0]), ifs([lo0])]
var truthOK = true, readingsOK = true, readingCount = 0
for fresh in [false, true] { for address in [false, true] { for satisfied in [false, true] {
    if P.describesFlow(fresh: fresh, hasAddress: address, satisfied: satisfied) != (fresh || (address && satisfied)) { truthOK = false }
}}}
for w in sessionWords { for s in witnesses { for l in witnesses { for p in pathLists { for d in [false, true] {
    readingCount += 1
    let got = P.sessionRoute(current: w, scope: s, local: l, path: p, describesFlow: d)
    let want = d ? P.route(scope: s ?? l, path: p) : w
    if got != want { readingsOK = false; print("   mismatch:", w as Any, s as Any, l as Any, p, d) }
}}}}}
check("session: describesFlow over its 8 cases: a fresh reading, or the Mac's address and satisfied", truthOK)
check("session: every reading (\(readingCount)): kept unless it describes the connection, else route(scope ?? local, path)", readingsOK)

// dialInterface (prefer-cable, 2026-09-25): the interface a row's Mac is dialled on. Noah's iPad on the
// cable with Wi-Fi on: a tap on the row that said Wired dialled the service unconstrained, and the Mac saw
// it on %en0 (7 ms) one time and on %en14 (1 ms) another. A row that says Wired is now dialled on the first
// wired interface its browser saw the Mac on (anpi0 there: the Mac saw %anri0 at 1-2 ms; en2 gave %en14),
// with the row as listed, unconstrained, after wiredWait; every other row as listed.
func dial(_ list: [(String, I.Kind)], direct: Bool = false) -> String? { P.dialInterface(direct: direct, interfaces: ifs(list)) }
check("dial: the cable's row as iPadOS lists it (anpi0 and en2 wired, en0 Wi-Fi): anpi0, the first wired one",
      dial([anpi0, en2, en0]) == "anpi0")
check("dial: the first wired one in any order, Wi-Fi before it changing nothing",
      dial([en2, anpi0]) == "en2" && dial([en0, en2, anpi0]) == "en2" && dial([en0, anpi0, en2]) == "anpi0")
check("dial: the cable alone (Wi-Fi off): en2; an Ethernet adapter's en3 as well", dial([en2]) == "en2" && dial([("en3", .wiredEthernet), en0]) == "en3")
check("dial: Wi-Fi only: none, the row dialled as listed", dial([en0]) == nil && dial([en0, ("en1", .wifi)]) == nil)
check("dial: no interface reported: none", dial([]) == nil)
check("dial: loopback, cellular, a VPN or an unknown type, alone or beside Wi-Fi: none",
      dial([lo0]) == nil && dial([("pdp_ip0", .cellular)]) == nil && dial([("utun3", .other)]) == nil
      && dial([("anpi0", .other), en0]) == nil && dial([lo0, en0]) == nil)
check("dial: awdl0 or llw0 beside the cable: the cable; alone (typed wifi): none",
      dial([awdl0, en2]) == "en2" && dial([llw0, anpi0]) == "anpi0" && dial([awdl0]) == nil && dial([llw0]) == nil)
check("dial: a Direct row never, whatever it is handed",
      dial([awdl0], direct: true) == nil && dial([en2], direct: true) == nil && dial([anpi0, en2, en0], direct: true) == nil)
check("dial: a peer-to-peer name typed wired Ethernet is skipped, as method skips it",
      dial([("awdl0", .wiredEthernet)]) == nil && dial([("llw0", .wiredEthernet), en2]) == "en2")
var dialAll = true, dialPairs = 0
for a in ifNames + ["en3"] { for ka in kinds { for b in ifNames + ["en3"] { for kb in kinds { for direct in [false, true] {
    dialPairs += 1
    let list = [I(name: a, type: ka), I(name: b, type: kb)]
    let got = P.dialInterface(direct: direct, interfaces: list)
    // Dialled exactly when the row says Wired, on an interface of its list typed wired Ethernet, the first such.
    let wired = P.method(direct: direct, interfaces: list) == .wired
    if (got != nil) != wired { dialAll = false; print("   dial mismatch:", list, direct, got as Any) }
    if let got, list.first(where: { $0.type == .wiredEthernet && !P.isPeerToPeer($0.name) })?.name != got { dialAll = false; print("   not the first wired:", list, got) }
}}}}}
check("dial: every pair (\(dialPairs), network and Direct): dialled exactly when the row says Wired, on its first wired interface", dialAll)
var dials: [String?] = []
for step in [[en0], [en0, en2], [anpi0, en2, en0], [en2], [anpi0, en2, en0], [en0]] {   // cable in, anpi0 up, Wi-Fi off, on, cable out
    dials.append(dial(step))
}
check("dial: the cable in and out, Wi-Fi off and on: none, en2, anpi0, en2, anpi0, none (\(dials.map { $0 ?? "none" }))",
      dials == [nil, "en2", "anpi0", "en2", "anpi0", nil])
check("dial: a wired dial gives way after 2.5 s", P.wiredWait == 2.5)
// The glue, as StreamClient.recomputeMacs makes a row: its word and its dial from the same result.
func rowsDial(network: [(String, [I])], nearby: [(String, [I])]) -> [(String, P.Method?, String?)] {
    P.rows(network: network.map(\.0), nearby: nearby.map { ($0.0, $0.1.map(\.name)) }).compactMap { row in
        guard let seen = (row.direct ? nearby : network).first(where: { $0.0 == row.name }) else { return nil }
        return (row.name, P.method(direct: row.direct, interfaces: seen.1), P.dialInterface(direct: row.direct, interfaces: seen.1))
    }
}
let mixed = rowsDial(network: [("Studio", ifs([anpi0, en2, en0])), ("Mini", ifs([en0])), ("Box", [])],
                     nearby: [("Studio", ifs([awdl0])), ("Air", ifs([awdl0]))])
check("rows+dial: a Wired row dialled on anpi0, a Wi-Fi row and a wordless one as listed, a Direct row never (\(mixed.map { "\($0.0) \($0.1?.word ?? "none") \($0.2 ?? "as listed")" }))",
      mixed.count == 4 && mixed[0] == ("Studio", .wired, "anpi0") && mixed[1] == ("Mini", .wifi, nil)
      && mixed[2] == ("Box", nil, nil) && mixed[3] == ("Air", .direct, nil))

// pathPlan (follow-best-path, 2026-09-25): a live session follows the best path its Mac is reachable
// on, the cable over Wi-Fi over Direct. Noah's tests: a session made over Wi-Fi stayed on Wi-Fi after
// the cable was plugged in (TCP keeps its interface), and one over the cable, unplugged, hung a while,
// fell to the connect screen and came back over Wi-Fi. Now: up to the cable once listed for 2 s, down
// to Wi-Fi at once when the cable's path is gone, a dead connection over the cable reconnected over
// Wi-Fi at once, at most one move per 5 s each way.
check("path: constants: cableSettle 2, pathHysteresis 5, wifiFresh 5, pongSilence 1 (wiredWait still 2.5)",
      P.cableSettle == 2 && P.pathHysteresis == 5 && P.wifiFresh == 5 && P.pongSilence == 1 && P.wiredWait == 2.5)
check("path: the order is the cable over Wi-Fi over Direct",
      P.Method.wired.rank > P.Method.wifi.rank && P.Method.wifi.rank > P.Method.direct.rank)

// wifiInterface: where a session that lost the cable dials its Mac.
func wifiIf(_ list: [(String, I.Kind)], direct: Bool = false) -> String? { P.wifiInterface(direct: direct, interfaces: ifs(list)) }
check("wifiInterface: the cable's row as iPadOS lists it (anpi0, en2, en0): en0", wifiIf([anpi0, en2, en0]) == "en0")
check("wifiInterface: the first Wi-Fi one; awdl0 and llw0 (typed wifi) skipped", wifiIf([awdl0, llw0, ("en1", .wifi), en0]) == "en1")
check("wifiInterface: none for the cable alone, loopback, cellular, a VPN, an unknown type, peer-to-peer or nothing",
      wifiIf([en2]) == nil && wifiIf([anpi0, en2]) == nil && wifiIf([lo0]) == nil && wifiIf([("pdp_ip0", .cellular)]) == nil
      && wifiIf([("utun3", .other)]) == nil && wifiIf([awdl0]) == nil && wifiIf([llw0]) == nil && wifiIf([]) == nil)
check("wifiInterface: a Direct row never", wifiIf([en0], direct: true) == nil && wifiIf([awdl0], direct: true) == nil)
var wifiAll = true, wifiPairs = 0
for a in ifNames + ["en1"] { for ka in kinds { for b in ifNames + ["en1"] { for kb in kinds { for direct in [false, true] {
    wifiPairs += 1
    let list = [I(name: a, type: ka), I(name: b, type: kb)]
    let want = direct ? nil : list.first { $0.type == .wifi && !P.isPeerToPeer($0.name) }?.name
    if P.wifiInterface(direct: direct, interfaces: list) != want { wifiAll = false; print("   wifi mismatch:", list, direct) }
}}}}}
check("wifiInterface: every pair (\(wifiPairs)): the first Wi-Fi interface not peer-to-peer, never for a Direct row", wifiAll)

// PathSightings: the cable listed since when, Wi-Fi listed now or moments ago.
typealias S = P.PathSightings
func sight(_ prev: S, _ entries: [(String, [(String, I.Kind)])], _ now: Double) -> S {
    P.pathSightings(prev, network: entries.map { ($0.0, ifs($0.1)) }, now: now)
}
var ps = sight(S(), [("Studio", [en0])], 1)
check("sightings: on Wi-Fi only: Wi-Fi en0, no cable", ps.wifi == ["Studio": "en0"] && ps.wired.isEmpty && ps.wiredSince.isEmpty && ps.wifiLeft.isEmpty)
ps = sight(ps, [("Studio", [en0, anpi0])], 3)
check("sightings: the cable appears at 3: anpi0 since 3, Wi-Fi still", ps.wired == ["Studio": "anpi0"] && ps.wiredSince == ["Studio": 3] && ps.wifi == ["Studio": "en0"])
ps = sight(ps, [("Studio", [en0, anpi0, en2])], 3.4)
check("sightings: en2 joins at 3.4: still since 3, anpi0 still first", ps.wiredSince == ["Studio": 3] && ps.wired == ["Studio": "anpi0"])
ps = sight(ps, [("Studio", [en0, en2])], 4)
check("sightings: anpi0 goes, en2 stays: since 3 kept (a wired interface without a break), en2 now", ps.wiredSince == ["Studio": 3] && ps.wired == ["Studio": "en2"])
ps = sight(ps, [("Studio", [en0])], 5)
check("sightings: the cable goes at 5: no wired interface, since dropped", ps.wired.isEmpty && ps.wiredSince.isEmpty)
ps = sight(ps, [("Studio", [en0, anpi0])], 6)
check("sightings: back at 6: since 6 (a break starts it again)", ps.wiredSince == ["Studio": 6])
ps = sight(ps, [("Studio", [anpi0])], 7)
check("sightings: Wi-Fi goes at 7: remembered as en0, left at 7", ps.wifi.isEmpty && ps.wifiLeft == ["Studio": S.WifiLeft(interface: "en0", at: 7)])
ps = sight(ps, [], 9)
check("sightings: the Mac gone at 9: the Wi-Fi memory kept (7), the cable dropped", ps.wifiLeft == ["Studio": S.WifiLeft(interface: "en0", at: 7)] && ps.wiredSince.isEmpty)
check("sightings: fresh Wi-Fi at 11.999 (under 5 s since 7), not at 12", P.freshWifi(ps, name: "Studio", now: 11.999) == "en0" && P.freshWifi(ps, name: "Studio", now: 12) == nil)
ps = sight(ps, [], 12)
check("sightings: forgotten once wifiFresh has passed", ps.wifiLeft.isEmpty)
ps = sight(S(), [("Studio", [en0])], 1); ps = sight(ps, [("Studio", [en2])], 2); ps = sight(ps, [("Studio", [en0, en2])], 3)
check("sightings: back on Wi-Fi: listed now, the memory dropped, fresh however late", ps.wifi == ["Studio": "en0"] && ps.wifiLeft.isEmpty && P.freshWifi(ps, name: "Studio", now: 100) == "en0")
ps = sight(S(), [("A", [en0, anpi0]), ("B", [en0]), ("A", [en2])], 1)
check("sightings: several Macs apart; a name's first result counts, as in rows", ps.wired == ["A": "anpi0"] && ps.wifi == ["A": "en0", "B": "en0"])
check("sightings: a Mac never on Wi-Fi has no fresh Wi-Fi", P.freshWifi(sight(S(), [("A", [anpi0])], 1), name: "A", now: 1) == nil)

// pathGone and pathPlan, one moment at a time.
typealias PI = P.PathInput
func pin(_ route: P.Method?, now: Double = 10, dead: Bool = false, reported: Bool = false, hinted: Bool = false, pong: Double? = nil,
         wired: String? = nil, since: Double? = nil, wifi: String? = nil, up: Double? = nil, down: Double? = nil,
         refused: Double? = nil, failures: Int = 0) -> PI {
    PI(now: now, route: route, dead: dead, pathReported: reported, pathHinted: hinted, lastPong: pong ?? now,
       wired: wired, wiredSince: since, wifi: wifi, lastUp: up, lastDown: down, refusedCable: refused, upFailures: failures)
}
func plan(_ i: PI) -> P.PathPlan { P.pathPlan(i) }
// (a) the cable appears while the session runs over Wi-Fi.
check("plan (a): on Wi-Fi, the cable listed since 3: waits for its 2 s, look again at 5",
      plan(pin(.wifi, now: 3, wired: "anpi0", since: 3, wifi: "en0")) == .stay(.cableSettling, recheckAt: 5))
check("plan (a): ...not at 4.999", plan(pin(.wifi, now: 4.999, wired: "anpi0", since: 3, wifi: "en0")) == .stay(.cableSettling, recheckAt: 5))
check("plan (a): ...moves to anpi0 at exactly 5.0", plan(pin(.wifi, now: 5, wired: "anpi0", since: 3, wifi: "en0")) == .moveTo(.wired, interface: "anpi0"))
check("plan (a): ...and later, to the first wired interface listed", plan(pin(.wifi, now: 60, wired: "en2", since: 3)) == .moveTo(.wired, interface: "en2"))
check("plan (a): the cable is better even while Wi-Fi's path is gone", plan(pin(.wifi, now: 6, reported: true, wired: "anpi0", since: 3)) == .moveTo(.wired, interface: "anpi0"))
check("plan (a): a move up 3 s before: waits for its 5 s (at 8), then moves",
      plan(pin(.wifi, now: 6, wired: "anpi0", since: 1, up: 3)) == .stay(.upTooSoon, recheckAt: 8)
      && plan(pin(.wifi, now: 8, wired: "anpi0", since: 1, up: 3)) == .moveTo(.wired, interface: "anpi0"))
check("plan (a): a move down at 4 starts the cable's 2 s again (the browser can lag a cable that went): at 6, not before",
      plan(pin(.wifi, now: 5, wired: "anpi0", since: 0, down: 4)) == .stay(.cableSettling, recheckAt: 6)
      && plan(pin(.wifi, now: 6, wired: "anpi0", since: 0, down: 4)) == .moveTo(.wired, interface: "anpi0"))
check("plan (a): a cable listed after the move down counts from its own listing",
      plan(pin(.wifi, now: 6, wired: "anpi0", since: 5, down: 4)) == .stay(.cableSettling, recheckAt: 7))
check("plan (a): on Wi-Fi with no cable: stays (never Wi-Fi to Wi-Fi)", plan(pin(.wifi, wifi: "en0")) == .stay(.wifi, recheckAt: nil)
      && plan(pin(.wifi, wifi: "en1")) == .stay(.wifi, recheckAt: nil))
check("plan (a): a wired name without a since (not listed) never moves", plan(pin(.wifi, wired: "anpi0", since: nil)) == .stay(.wifi, recheckAt: nil))
// (b) the cable goes while the session runs over it.
check("plan (b): on the cable, iOS reports its path gone, the Mac on Wi-Fi: to Wi-Fi on en0 at once",
      plan(pin(.wired, reported: true, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
check("plan (b): ...even while the browser still lists the cable (iOS's word on the connection counts)",
      plan(pin(.wired, reported: true, wired: "anpi0", since: 1, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
check("plan (b): ...on the Wi-Fi interface freshWifi gives", plan(pin(.wired, reported: true, wifi: "en1")) == .moveTo(.wifi, interface: "en1"))
check("plan (b): no Wi-Fi to go to: stays (the reconnect takes over when the connection ends)", plan(pin(.wired, reported: true)) == .stay(.noWifi, recheckAt: nil))
check("plan (b): a move down 2 s before: waits for its 5 s (at 13), then moves",
      plan(pin(.wired, now: 10, reported: true, wifi: "en0", down: 8)) == .stay(.downTooSoon, recheckAt: 13)
      && plan(pin(.wired, now: 13, reported: true, wifi: "en0", down: 8)) == .moveTo(.wifi, interface: "en0"))
check("plan (b): a move up just before does not hold a move down back (each way apart)",
      plan(pin(.wired, now: 10, reported: true, wifi: "en0", up: 9.9)) == .moveTo(.wifi, interface: "en0"))
check("plan (b): dead over the cable, the Mac on Wi-Fi: reconnect over Wi-Fi now",
      plan(pin(.wired, dead: true, wifi: "en0")) == .reconnectNow(.wifi, interface: "en0"))
check("plan (b): ...even within 5 s of a move down (nothing is left to keep)",
      plan(pin(.wired, now: 10, dead: true, wifi: "en0", down: 9)) == .reconnectNow(.wifi, interface: "en0"))
check("plan (b): dead over the cable with no Wi-Fi: the ordinary reconnect", plan(pin(.wired, dead: true)) == .stay(.noWifi, recheckAt: nil))
check("plan (b): dead over Wi-Fi, the cable listed or not: the ordinary reconnect (which dials a Wired row's cable)",
      plan(pin(.wifi, dead: true, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.lost, recheckAt: nil)
      && plan(pin(.wifi, dead: true, wifi: "en0")) == .stay(.lost, recheckAt: nil))
// Never off a cable that works.
check("plan: on a working cable, the Mac listed on both: stays", plan(pin(.wired, wired: "anpi0", since: 1, wifi: "en0")) == .stay(.cable, recheckAt: nil))
check("plan: on the cable, the browser drops it but pongs come: stays, and looks again at the silence mark",
      plan(pin(.wired, now: 10, pong: 9.75, wifi: "en0")) == .stay(.cableUnlisted, recheckAt: 10.75))
check("plan: ...no pong for 0.999 s: stays; for exactly 1.0 s: to Wi-Fi",
      plan(pin(.wired, now: 10.749, pong: 9.75, wifi: "en0")) == .stay(.cableUnlisted, recheckAt: 10.75)
      && plan(pin(.wired, now: 10.75, pong: 9.75, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
check("plan: silence with the browser still listing the cable: stays (the Mac may be busy)",
      plan(pin(.wired, now: 20, pong: 10, wired: "anpi0", since: 1, wifi: "en0")) == .stay(.cable, recheckAt: nil))
check("plan: an unsatisfied update naming only the service: to Wi-Fi once the browser has dropped the cable, not before",
      plan(pin(.wired, hinted: true, wifi: "en0")) == .moveTo(.wifi, interface: "en0")
      && plan(pin(.wired, hinted: true, wired: "anpi0", since: 1, wifi: "en0")) == .stay(.cable, recheckAt: nil))
// Direct, and a path that says nothing.
check("plan: a Direct session is never moved here, whatever is listed (moveToNetwork moves it)",
      plan(pin(.direct, now: 60, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.direct, recheckAt: nil)
      && plan(pin(.direct, reported: true, wifi: "en0")) == .stay(.direct, recheckAt: nil)
      && plan(pin(.direct, dead: true, wifi: "en0")) == .stay(.direct, recheckAt: nil))
check("plan: a session whose path says nothing (the simulator by 127.0.0.1) never moves",
      plan(pin(nil, now: 60, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.routeUnknown, recheckAt: nil)
      && plan(pin(nil, dead: true, wifi: "en0")) == .stay(.routeUnknown, recheckAt: nil))
check("plan: on Wi-Fi with its path gone and no cable: stays; the reconnect takes over", plan(pin(.wifi, reported: true, wifi: "en0")) == .stay(.lost, recheckAt: nil))
check("plan: the reasons read as the console prints them",
      P.Keep.cable.text == "on the cable" && P.Keep.cableSettling.text == "the cable appeared; waiting for it to settle"
      && P.Keep.noWifi.text == "the cable went away, and the Mac is not on Wi\u{2011}Fi")

var goneOK = true, goneCount = 0
for route in [nil, P.Method.wired, .wifi, .direct] { for dead in [false, true] { for reported in [false, true] { for hinted in [false, true] {
for wired in [nil, "anpi0"] as [String?] { for silent in [0.0, 0.999, 1.0, 5.0] {
    goneCount += 1
    let i = pin(route, now: 10, dead: dead, reported: reported, hinted: hinted, pong: 10 - silent, wired: wired, since: wired == nil ? nil : 0)
    let want = dead || reported || (route == .wired && wired == nil && (hinted || silent >= 1.0))
    if P.pathGone(i) != want { goneOK = false; print("   gone mismatch:", i) }
}}}}}}
check("pathGone: every case (\(goneCount)): dead or reported; else only over a cable the browser dropped, hinted or 1 s without a pong", goneOK)

// Exhaustive over a grid: the rules that must hold whatever the inputs, and a move whenever one may.
// (Review fixes: it also spans a refused listing of the cable and moves up that did not complete, and a
// dead connection over the cable is made again over the cable while the cable is listed and nothing was
// reported, else over Wi-Fi.)
var gridOK = true, gridCount = 0
let waitAfter: [Int: Double] = [0: 5, 1: 10, 3: 40]   // upWait, spelled out
for route in [nil, P.Method.wired, .wifi, .direct] { for dead in [false, true] { for reported in [false, true] { for hinted in [false, true] {
for wired in [nil, "anpi0"] as [String?] { for since in [nil, 0.0, 8.5, 9.0] as [Double?] { for wifi in [nil, "en0"] as [String?] {
for up in [nil, 4.0, 5.0, 6.0] as [Double?] { for down in [nil, 4.0, 5.0, 8.0, 9.0] as [Double?] { for silent in [0.0, 2.0] {
for refused in [nil, 0.0, 8.5] as [Double?] { for failures in [0, 1, 3] {
    gridCount += 1
    let i = pin(route, now: 10, dead: dead, reported: reported, hinted: hinted, pong: 10 - silent, wired: wired, since: since, wifi: wifi,
                up: up, down: down, refused: refused, failures: failures)
    let p = P.pathPlan(i)
    let wait = waitAfter[failures]!
    let overCable = wired != nil && !reported
    func bad(_ why: String) { gridOK = false; print("   \(why):", i, p) }
    switch p {
    case .moveTo(.wired, let name):
        if route != .wifi || dead || name != wired || since == nil { bad("up from the wrong place") }
        if since != nil && since == refused { bad("up to a refused listing") }
        if let s = since, 10 < max(s, down ?? s) + 2 { bad("up before the cable settled") }
        if let u = up, 10 < u + wait { bad("up within \(wait) s of the last move up") }
    case .moveTo(.wifi, let name):
        if route != .wired || dead || !P.pathGone(i) || name != wifi { bad("down from the wrong place") }
        if let d = down, 10 < d + 5 { bad("down within 5 s of the last move down") }
    case .moveTo(.direct, _):
        bad("a move to Direct")
    case .reconnectNow(let method, let name):
        if route != .wired || !dead { bad("reconnectNow from the wrong place") }
        if method == .wired && (!overCable || name != wired) { bad("reconnectNow over the cable when it may not") }
        if method == .wifi && (overCable || name != wifi) { bad("reconnectNow over Wi-Fi when the cable is listed and nothing was reported") }
        if method == .direct { bad("reconnectNow over Direct") }
    case .stay(_, let at):
        if let at, at <= 10 { bad("a look again not in the future") }
    }
    let upDue = since.map { max(max($0, down ?? $0) + 2, (up ?? -1e9) + wait) }
    let mayUp = route == .wifi && !dead && wired != nil && since != refused && (upDue.map { 10 >= $0 } ?? false)
    let mayDown = route == .wired && !dead && wifi != nil && P.pathGone(i) && (down.map { 10 >= $0 + 5 } ?? true)
    let mayReconnect = route == .wired && dead && (overCable || wifi != nil)
    let want: P.PathPlan? = mayUp ? .moveTo(.wired, interface: wired!) : mayDown ? .moveTo(.wifi, interface: wifi!)
        : mayReconnect ? (overCable ? .reconnectNow(.wired, interface: wired!) : .reconnectNow(.wifi, interface: wifi!)) : nil
    if let want { if p != want { bad("did not do what it may") } } else if case .stay = p {} else { bad("moved when it may not") }
}}}}}}}}}}}}
check("plan: every case of a grid (\(gridCount)): up only from Wi-Fi to a settled cable not refused, upWait after the last, down only off a cable whose path is gone 5 s after the last, reconnectNow only dead over the cable (over it while listed and unreported, else over Wi-Fi), never to Direct, looks ahead, and moves whenever it may", gridOK)

// The model: StreamClient.followBestPath over time, stepped every 50 ms, against a scripted world: the
// cable plugged in or not, the browser following it `browserLag` late, iOS reporting a lost path or not,
// and a connection over a cable that went dying `diesAfter` later. A move is taken to hand over in the
// step it starts; a move up to a cable that is gone fails.
struct World {
    var cable: (Double) -> Bool
    var wifiListed: (Double) -> Bool = { _ in true }
    var browserLag = 0.0
    var browserBlink: (Double) -> Bool = { _ in false }   // the browser drops the cable though it works
    var iosReports = true
    var diesAfter: Double? = nil
    var evictAt: Double? = nil   // the Mac closes the connection (an eviction) though the cable works; nothing reported
}
func live(_ w: World, from start: P.Method, to end: Double = 30) -> [String] {
    var s = S(), route: P.Method? = start, lastPong = 0.0, up: Double? = nil, down: Double? = nil
    var goneAt: Double? = nil, events: [String] = [], evicted = false
    var k = 0
    while true {
        let t = (Double(k) * 50).rounded() / 1000; k += 1
        if t > end + 1e-9 { break }
        var list: [(String, I.Kind)] = []
        if w.cable(max(0, t - w.browserLag)) && !w.browserBlink(t) { list += [anpi0, en2] }
        if w.wifiListed(t) { list.append(en0) }
        s = P.pathSightings(s, network: list.isEmpty ? [] : [("Studio", ifs(list))], now: t)
        var reported = false, dead = false
        if route == .wired && !w.cable(t) {
            goneAt = goneAt ?? t
            reported = w.iosReports
            if let d = w.diesAfter, t >= goneAt! + d { dead = true }
        } else {
            goneAt = nil
            lastPong = t
        }
        if let e = w.evictAt, t >= e, !evicted { evicted = true; dead = true }
        let i = PI(now: t, route: route, dead: dead, pathReported: reported, pathHinted: false, lastPong: lastPong,
                   wired: s.wired["Studio"], wiredSince: s.wiredSince["Studio"], wifi: P.freshWifi(s, name: "Studio", now: t),
                   lastUp: up, lastDown: down)
        switch P.pathPlan(i) {
        case .moveTo(.wired, let name):
            up = t
            if w.cable(t) { route = .wired; lastPong = t; events.append(String(format: "%.2f up %@", t, name)) }
            else { events.append(String(format: "%.2f up failed", t)) }
        case .moveTo(.wifi, let name):
            down = t; route = .wifi; goneAt = nil; lastPong = t; events.append(String(format: "%.2f down %@", t, name))
        case .reconnectNow(let method, let name):
            // Over the cable: its dial reaches the Mac while the cable is in; pulled, it cannot go on and
            // the row as listed takes Wi-Fi (StreamClient: the fallback), a move up for the hysteresis.
            var landed = ""
            if method == .wired { up = t; route = w.cable(t) ? .wired : .wifi; if route == .wifi { landed = ", landed on Wi-Fi" } }
            else { down = t; route = .wifi }
            goneAt = nil; lastPong = t; events.append(String(format: "%.2f reconnect %@%@", t, name, landed))
        case .moveTo(.direct, _):
            events.append("Direct?")
        case .stay:
            if dead { events.append(String(format: "%.2f lost", t)); return events }   // the ordinary reconnect's
        }
    }
    return events
}
var ev = live(World(cable: { $0 >= 3 }, browserLag: 0.3), from: .wifi)
check("model (a): on Wi-Fi, the cable plugged in at 3, listed at 3.3: moved to anpi0 at exactly 5.3 (\(ev))", ev == ["5.30 up anpi0"])
ev = live(World(cable: { $0 >= 3 && !($0 >= 4 && $0 < 4.4) }, browserLag: 0.3), from: .wifi)
check("model (a): ...the cable out 4–4.4: its 2 s start again at 4.7, moved at 6.7 (\(ev))", ev == ["6.70 up anpi0"])
ev = live(World(cable: { _ in true }), from: .wired)
check("model: on the cable all along: never moves (\(ev))", ev.isEmpty)
ev = live(World(cable: { _ in false }), from: .wifi)
check("model: on Wi-Fi, no cable ever: never moves (\(ev))", ev.isEmpty)
ev = live(World(cable: { $0 < 10 }), from: .wired)
check("model (b): on the cable, pulled at 10, iOS reports it: to Wi-Fi at 10.0 (\(ev))", ev == ["10.00 down en0"])
ev = live(World(cable: { $0 < 10 }, browserLag: 0.3, iosReports: false), from: .wired)
check("model (b): ...iOS silent, the browser drops the cable at 10.3, the last pong at 9.95: to Wi-Fi at 10.95 (\(ev))", ev == ["10.95 down en0"])
ev = live(World(cable: { $0 < 10 }, iosReports: false, diesAfter: 0.2), from: .wired)
check("model (b): ...iOS silent, the connection dead at 10.2: reconnected over Wi-Fi at 10.2 (\(ev))", ev == ["10.20 reconnect en0"])
ev = live(World(cable: { $0 < 10 }, diesAfter: 0.2), from: .wired)
check("model (b): ...iOS reports it and the connection dies after: moved at 10.0 before it died (\(ev))", ev == ["10.00 down en0"])
ev = live(World(cable: { $0 < 10 }, wifiListed: { _ in false }, diesAfter: 5), from: .wired)
check("model (b): the cable alone (no Wi-Fi), pulled at 10: stays until the connection ends at 15, then the ordinary reconnect (\(ev))", ev == ["15.00 lost"])
ev = live(World(cable: { $0 < 10 }, wifiListed: { $0 < 5.05 }), from: .wired)
check("model (b): the Mac left Wi-Fi at 5.05, the cable pulled at 10: still fresh, to Wi-Fi at 10.0 (\(ev))", ev == ["10.00 down en0"])
ev = live(World(cable: { $0 < 10 }, wifiListed: { $0 < 5 }, diesAfter: 1), from: .wired)
check("model (b): ...left at 5.0: 5 s old at 10, so not; lost when the connection ends at 11 (\(ev))", ev == ["11.00 lost"])
ev = live(World(cable: { _ in true }, browserBlink: { $0 >= 10 && $0 < 10.5 }), from: .wired)
check("model: on a working cable the browser blinks off for 0.5 s: never moves (\(ev))", ev.isEmpty)
ev = live(World(cable: { _ in true }), from: .direct)
check("model: a Direct session with the cable plugged in: never moved here (\(ev))", ev.isEmpty)
// A loose cable: in for 3 s, out for 1 s, from 3 s on; the session starts on Wi-Fi.
ev = live(World(cable: { $0 >= 3 && Int($0 - 3) % 4 != 3 }), from: .wifi, to: 40)
var gapsOK = true, lastOf: [String: Double] = [:]
for e in ev {
    let parts = e.split(separator: " "), t = Double(parts[0])!, way = String(parts[1])
    if let last = lastOf[way], t - last < 5 - 1e-9 { gapsOK = false }
    lastOf[way] = t
}
check("model: a loose cable (in 3 s, out 1 s): each way at most one move per 5 s, and never onto an absent cable (\(ev))",
      gapsOK && !ev.contains { $0.contains("failed") } && ev.count >= 4)
ev = live(World(cable: { $0 >= 3 && Int(($0 - 3) * 2) % 2 == 0 }), from: .wifi)
check("model: a cable flapping every 0.5 s never settles: never moves (\(ev))", ev.isEmpty)

// review fixes (follow-best-path, 2026-09-25). 1: a connection over the cable that dies while the
// browser still lists the cable and iOS said nothing of its path was closed by the Mac (it evicts a
// device that stops reading: the app suspended in the background for 4 s and more), and the cable
// works: it is made again over the cable at once (the Wired row's dial, the row as listed as the
// fallback), not over Wi-Fi, from which the session came back to the cable 2 s later (two hand-overs
// while the cable was up). 4: a listing of the cable a move up found to reach another Mac, or another
// launch of Sill, is not tried again while it lasts, and after moves up that did not complete the next
// waits 10, 20, 40, then 60 s (every 5 s before, for as long as the cable stayed in).
check("review: upWait: 5, 10, 20, 40, then 60 s (the cap), 5 for a count below zero",
      P.upWait(failures: 0) == 5 && P.upWait(failures: 1) == 10 && P.upWait(failures: 2) == 20 && P.upWait(failures: 3) == 40
      && P.upWait(failures: 4) == 60 && P.upWait(failures: 5) == 60 && P.upWait(failures: 1000) == 60 && P.upWait(failures: -1) == 5
      && P.upBackoffCap == 60)
check("review: dead over the cable, the cable still listed, nothing reported: over the cable again now (anpi0), with Wi-Fi or without",
      plan(pin(.wired, dead: true, wired: "anpi0", since: 1, wifi: "en0")) == .reconnectNow(.wired, interface: "anpi0")
      && plan(pin(.wired, dead: true, wired: "anpi0", since: 1)) == .reconnectNow(.wired, interface: "anpi0")
      && plan(pin(.wired, dead: true, wired: "en2", since: 1, wifi: "en0")) == .reconnectNow(.wired, interface: "en2"))
check("review: ...even within 5 s of a move up or down (nothing is left to keep), and with its pongs silent",
      plan(pin(.wired, now: 10, dead: true, pong: 2, wired: "anpi0", since: 1, wifi: "en0", up: 9, down: 9.5)) == .reconnectNow(.wired, interface: "anpi0"))
check("review: ...a hint alone does not count while the browser lists the cable (as in pathGone)",
      plan(pin(.wired, dead: true, hinted: true, wired: "anpi0", since: 1, wifi: "en0")) == .reconnectNow(.wired, interface: "anpi0"))
check("review: ...iOS said the path went before the connection did: over Wi-Fi (en0), or with no Wi-Fi the ordinary reconnect",
      plan(pin(.wired, dead: true, reported: true, wired: "anpi0", since: 1, wifi: "en0")) == .reconnectNow(.wifi, interface: "en0")
      && plan(pin(.wired, dead: true, reported: true, wired: "anpi0", since: 1)) == .stay(.noWifi, recheckAt: nil))
check("review: ...the browser no longer lists the cable: over Wi-Fi, as before",
      plan(pin(.wired, dead: true, wifi: "en0")) == .reconnectNow(.wifi, interface: "en0")
      && plan(pin(.wired, dead: true, hinted: true, wifi: "en1")) == .reconnectNow(.wifi, interface: "en1"))
check("review: dead over Wi-Fi or Direct, the cable listed: never reconnectNow (the ordinary reconnect dials a Wired row's cable)",
      plan(pin(.wifi, dead: true, wired: "anpi0", since: 1, wifi: "en0")) == .stay(.lost, recheckAt: nil)
      && plan(pin(.direct, dead: true, wired: "anpi0", since: 1, wifi: "en0")) == .stay(.direct, recheckAt: nil))
check("review: a refused listing of the cable: stays, and looks again at nothing (only a new listing changes it)",
      plan(pin(.wifi, now: 60, wired: "anpi0", since: 3, wifi: "en0", refused: 3)) == .stay(.cableRefused, recheckAt: nil)
      && plan(pin(.wifi, now: 600, wired: "anpi0", since: 3, wifi: "en0", up: 5, refused: 3, failures: 3)) == .stay(.cableRefused, recheckAt: nil))
check("review: ...a new listing (the cable out and in again, since 20) is tried once settled",
      plan(pin(.wifi, now: 21, wired: "anpi0", since: 20, wifi: "en0", up: 5, refused: 3)) == .stay(.cableSettling, recheckAt: 22)
      && plan(pin(.wifi, now: 22, wired: "anpi0", since: 20, wifi: "en0", up: 5, refused: 3)) == .moveTo(.wired, interface: "anpi0"))
check("review: after 1, 2, 3, 4 and 9 moves up in a row that did not complete (the last at 10): the next at 20, 30, 50, 70, 70",
      [1, 2, 3, 4, 9].allSatisfy { n in
          let due = 10 + P.upWait(failures: n)
          return plan(pin(.wifi, now: due - 0.001, wired: "anpi0", since: 0, wifi: "en0", up: 10, failures: n)) == .stay(.cableFailing, recheckAt: due)
              && plan(pin(.wifi, now: due, wired: "anpi0", since: 0, wifi: "en0", up: 10, failures: n)) == .moveTo(.wired, interface: "anpi0")
      } && [20.0, 30, 50, 70, 70] == [1, 2, 3, 4, 9].map { 10 + P.upWait(failures: $0) })
check("review: ...the settle still counts (a move down at 69: at 71, not 70), and with no failure the reason is the hysteresis",
      plan(pin(.wifi, now: 70, wired: "anpi0", since: 0, wifi: "en0", up: 10, down: 69, failures: 4)) == .stay(.cableSettling, recheckAt: 71)
      && plan(pin(.wifi, now: 12, wired: "anpi0", since: 0, wifi: "en0", up: 10)) == .stay(.upTooSoon, recheckAt: 15))
check("review: the new reasons read as the console prints them",
      P.Keep.cableFailing.text == "the cable is up, but the last move to it did not complete; the next waits longer"
      && P.Keep.cableRefused.text == "the cable reaches another Mac, or another launch of Sill; not tried again until it is plugged in again")
check("review: the memberwise defaults: no refused listing, no failures",
      PI(now: 1, route: .wifi, lastPong: 1).refusedCable == nil && PI(now: 1, route: .wifi, lastPong: 1).upFailures == 0)

// The model: the Mac closes the connection over a cable that works (the app back from 4 s and more in
// the background), before the fix a move to Wi-Fi and back to the cable 2 s later.
ev = live(World(cable: { _ in true }, evictAt: 10), from: .wired)
check("model (review): on the cable, the Mac closes the connection at 10, the cable fine: made again over the cable at 10.0, and nothing more (\(ev))",
      ev == ["10.00 reconnect anpi0"])
ev = live(World(cable: { _ in true }, wifiListed: { _ in false }, evictAt: 10), from: .wired)
check("model (review): ...with the Mac on no Wi-Fi at all: the same (\(ev))", ev == ["10.00 reconnect anpi0"])
ev = live(World(cable: { $0 < 10 }, browserLag: 0.5, iosReports: false, diesAfter: 0.2), from: .wired)
check("model (review): the cable pulled at 10 with iOS silent and the connection dead at 10.2, the browser 0.5 s late: over the cable first, whose dial cannot go on, so the row as listed takes Wi-Fi, and no move up after (\(ev))",
      ev == ["10.20 reconnect anpi0, landed on Wi-Fi"])
ev = live(World(cable: { _ in false }, evictAt: 10), from: .wifi)
check("model (review): on Wi-Fi, the Mac closes the connection: the ordinary reconnect, as before (\(ev))", ev == ["10.00 lost"])
ev = live(World(cable: { _ in true }, evictAt: 10), from: .wifi)
check("model (review): on Wi-Fi, the cable listed from 0: up at 2, and the Mac closing the connection at 10 is made again over the cable (\(ev))",
      ev == ["2.00 up anpi0", "10.00 reconnect anpi0"])

// The model: moves up that do not complete, against the real plan and the client's glue (the failures
// kept by the listing they were to, the refused listing). The session runs over Wi-Fi; the browser lists
// the Mac on the cable from 10 s on (out for 1 s at `replugAt`); each move up ends as `end` says after
// as long as it takes (a dial not ready: 2.5 s; no window list: 5 s; refused or taking over: 0.05 s).
enum UpEnd { case completes, notReady, noList, refused }
func upTries(_ end: UpEnd, until: Double, replugAt: Double? = nil) -> (starts: [Double], route: P.Method) {
    var s = S(), up: Double? = nil, failed: (listing: Double, count: Int)? = nil, refused: Double? = nil
    var moveEndsAt: Double? = nil, moveListing: Double? = nil
    var route = P.Method.wifi, starts: [Double] = []
    var k = 0
    while true {
        let t = (Double(k) * 50).rounded() / 1000; k += 1
        if t > until + 1e-9 { break }
        let plugged = t >= 10 && !(replugAt.map { t >= $0 && t < $0 + 1 } ?? false)
        s = P.pathSightings(s, network: [("Studio", ifs(plugged ? [anpi0, en2, en0] : [en0]))], now: t)
        if let e = moveEndsAt {
            guard t >= e - 1e-9 else { continue }   // a move under way: followBestPath returns at once
            moveEndsAt = nil
            switch end {
            case .completes: route = .wired; failed = nil
            case .refused: refused = moveListing; fallthrough   // then moveEnded, as for any move that did not complete
            case .notReady, .noList:
                if let l = moveListing { failed = (l, failed?.listing == l ? failed!.count + 1 : 1) }
            }
        }
        let listing = s.wiredSince["Studio"]
        let i = PI(now: t, route: route, lastPong: t, wired: s.wired["Studio"], wiredSince: listing,
                   wifi: P.freshWifi(s, name: "Studio", now: t), lastUp: up, lastDown: nil, refusedCable: refused,
                   upFailures: failed.map { $0.listing == listing ? $0.count : 0 } ?? 0)
        if case .moveTo(.wired, _) = P.pathPlan(i) {
            up = t; moveListing = listing; starts.append(t)
            moveEndsAt = t + [UpEnd.completes: 0.05, .notReady: 2.5, .noList: 5.0, .refused: 0.05][end]!
        }
    }
    return (starts, route)
}
var tries = upTries(.completes, until: 150)
check("model (review): a cable that works: one move up at 12, on the cable after (\(tries.starts))", tries.starts == [12] && tries.route == .wired)
tries = upTries(.notReady, until: 150)
check("model (review): a cable whose dial is never ready: tries at 12, 22, 42, 82, 142 (every 5 s before) (\(tries.starts))",
      tries.starts == [12, 22, 42, 82, 142] && tries.route == .wifi)
tries = upTries(.noList, until: 150)
check("model (review): a cable that connects but brings no window list (5 s): the same, 12, 22, 42, 82, 142 (\(tries.starts))",
      tries.starts == [12, 22, 42, 82, 142])
tries = upTries(.refused, until: 150)
check("model (review): a cable that reaches another launch: one try at 12, never again while it stays in (\(tries.starts))", tries.starts == [12])
tries = upTries(.refused, until: 150, replugAt: 30)
check("model (review): ...out at 30 and in at 31: tried once more at 33, then never (\(tries.starts))", tries.starts == [12, 33])
tries = upTries(.notReady, until: 100, replugAt: 50)
check("model (review): a dial never ready, the cable out at 50 and in at 51: the back-off starts again (53, 63, 83) (\(tries.starts))",
      tries.starts == [12, 22, 42, 53, 63, 83])


// remote (the merge): a remote session (a saved Mac dialed through the remote door, StreamClient+Remote)
// is not a candidate for the moves: pathPlan keeps it where it is, whatever its path and the browser say,
// as it keeps a Direct session; only the move home moves one (moveHome, remote-bundle, below), and its
// end is the remote reconnect's. StreamClient hands pathPlan `remote` from the session's route, and a nil route word (a
// remote session never has one).
func rpin(_ route: P.Method?, dead: Bool = false, reported: Bool = false, hinted: Bool = false, silent: Double = 0,
          wired: String? = nil, since: Double? = nil, wifi: String? = nil, up: Double? = nil, down: Double? = nil,
          refused: Double? = nil, failures: Int = 0) -> PI {
    var i = pin(route, now: 10, dead: dead, reported: reported, hinted: hinted, pong: 10 - silent, wired: wired, since: since,
                wifi: wifi, up: up, down: down, refused: refused, failures: failures)
    i.remote = true
    return i
}
check("remote: a session is at home unless said otherwise (PathInput.remote false)", !pin(.wifi).remote && !PI(now: 0, route: .wifi, lastPong: 0).remote)
check("remote: on Wi-Fi with the cable listed and settled: stays (at home: up to the cable)",
      plan(rpin(.wifi, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(pin(.wifi, wired: "anpi0", since: 0, wifi: "en0")) == .moveTo(.wired, interface: "anpi0"))
check("remote: on the cable, its path reported gone, the Mac on Wi-Fi: stays (at home: down to Wi-Fi)",
      plan(rpin(.wired, reported: true, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(pin(.wired, reported: true, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
check("remote: on the cable, the browser dropped it and no pong for 2 s: stays, no look again (at home: to Wi-Fi)",
      plan(rpin(.wired, silent: 2, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(pin(.wired, now: 10, pong: 8, wifi: "en0")) == .moveTo(.wifi, interface: "en0"))
check("remote: dead over the cable, listed or not: no reconnectNow (the remote reconnect's rules)",
      plan(rpin(.wired, dead: true, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(rpin(.wired, dead: true, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(pin(.wired, dead: true, wired: "anpi0", since: 0, wifi: "en0")) == .reconnectNow(.wired, interface: "anpi0"))
check("remote: with no word (a remote session's, as StreamClient hands it) or Direct: the remote reason, not routeUnknown or direct",
      plan(rpin(nil, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(rpin(.direct, wired: "anpi0", since: 0, wifi: "en0")) == .stay(.remote, recheckAt: nil)
      && plan(rpin(nil, dead: true, wifi: "en0")) == .stay(.remote, recheckAt: nil))
check("remote: the reason reads as the console prints it, and is none of the others",
      P.Keep.remote.text == "a remote session moves only home, once the network lists its Mac"
      && P.Keep.remote != .direct && P.Keep.remote != .routeUnknown && P.Keep.remote.text != P.Keep.direct.text)
var remoteOK = true, remoteCount = 0
for route in [nil, P.Method.wired, .wifi, .direct] { for dead in [false, true] { for reported in [false, true] { for hinted in [false, true] {
for wired in [nil, "anpi0"] as [String?] { for since in [nil, 0.0, 9.0] as [Double?] { for wifi in [nil, "en0"] as [String?] {
for up in [nil, 4.0] as [Double?] { for down in [nil, 9.0] as [Double?] { for silent in [0.0, 2.0] {
for refused in [nil, 0.0] as [Double?] { for failures in [0, 3] {
    remoteCount += 1
    let i = rpin(route, dead: dead, reported: reported, hinted: hinted, silent: silent, wired: wired, since: since, wifi: wifi,
                 up: up, down: down, refused: refused, failures: failures)
    let p = P.pathPlan(i)
    if p != .stay(.remote, recheckAt: nil) { remoteOK = false; print("   remote moved:", i, p) }
    // The same case at home still does what the 277 say it does (the flag changes nothing else).
    var home = i; home.remote = false
    if P.pathPlan(home) == .stay(.remote, recheckAt: nil) { remoteOK = false; print("   home read as remote:", home) }
}}}}}}}}}}}}
check("remote: every case of a grid (\(remoteCount)): a remote session stays, for the remote reason, never looking again; the same case at home is never read as remote", remoteOK)
// The model, as a remote session sees it: the cable plugged in at 3, pulled at 10 (iOS reports it), and
// the connection dying at 12: nothing ever moves; the loss at 12 is the remote reconnect's.
var remoteEvents: [String] = [], rs = S()
var rk = 0
while true {
    let t = (Double(rk) * 50).rounded() / 1000; rk += 1
    if t > 20 + 1e-9 { break }
    let plugged = t >= 3 && t < 10
    rs = P.pathSightings(rs, network: [("Studio", ifs(plugged ? [anpi0, en2, en0] : [en0]))], now: t)
    var i = PI(now: t, route: nil, dead: t >= 12, pathReported: t >= 10, pathHinted: false, lastPong: min(t, 10),
               wired: rs.wired["Studio"], wiredSince: rs.wiredSince["Studio"], wifi: P.freshWifi(rs, name: "Studio", now: t),
               lastUp: nil, lastDown: nil)
    i.remote = true
    if case .stay(.remote, nil) = P.pathPlan(i) {} else { remoteEvents.append(String(format: "%.2f %@", t, "\(P.pathPlan(i))")) }
}
check("model (remote): the cable in at 3 and out at 10, the connection dead at 12: never a move (\(remoteEvents))", remoteEvents.isEmpty)

// moveHome (remote-bundle, docs/remote-bundle-plan.md §7.2, H15): a session through the remote door moves
// home once the network has listed its saved Mac (by Mac ID) for moveAfter without a break; moves that did
// not complete wait upWait (10, 20, 40, then 60 s) from the last one's start, counted for one listing; a
// listing found to be another launch is never tried again while it lasts; a new listing is tried afresh.
func home(_ since: Double?, last: Double? = nil, failures: Int = 0, refused: Double? = nil, _ now: Double) -> (Bool, Double?) {
    let r = P.moveHome(listedSince: since, lastAttempt: last, failures: failures, refusedListing: refused, now: now); return (r.move, r.recheckAt)
}
check("home: not listed on the network, nothing to do", home(nil, 5) == (false, nil))
check("home: listed at 10, look again at 12", home(10, 10) == (false, 12))
check("home: not at 11.9", home(10, 11.9) == (false, 12))
check("home: at exactly 12.0", home(10, 12) == (true, nil))
check("home: listed afresh at 30 after a blink: counts from 30 (a blink restarts the count)", home(30, 31) == (false, 32) && home(30, 32) == (true, nil))
check("home: one move that did not complete, from 12: the next at 22", home(10, last: 12, failures: 1, 13) == (false, 22)
      && home(10, last: 12, failures: 1, 21.9) == (false, 22) && home(10, last: 12, failures: 1, 22) == (true, nil))
check("home: retries 10, 20, 40, 60, 60 s after 1 to 5 moves that did not complete",
      [1, 2, 3, 4, 5].map { home(10, last: 100, failures: $0, 100.5).1 } == [110, 120, 140, 160, 160])
check("home: an earlier move with no failure counted (a new listing) holds nothing back", home(30, last: 20, failures: 0, 32) == (true, nil))
check("home: ...even one that started a moment before the listing (a blink during a move): 2 s from the listing, not upWait(0)",
      home(51, last: 49, failures: 0, 53) == (true, nil) && home(51, last: 49, failures: 0, 52) == (false, 53))
check("home: a refused listing, never", home(10, refused: 10, 50) == (false, nil) && home(10, last: 12, failures: 3, refused: 10, 500) == (false, nil))
check("home: a new listing after a refused one is tried afresh", home(60, refused: 10, 62) == (true, nil))
check("home: the same rule as moveToNetwork's first look (moveAfter)", home(5, 7) == mv(5, nil, 7) && home(5, 6.999) == mv(5, nil, 6.999))

// The model: the glue as StreamClient.moveHomeIfListed runs it. The saved Mac's network row by Mac ID
// through P.sightings; failures kept by the listing they were to; a refused listing kept; a move to it
// that takes `lasts` and ends as `end` (not completing, refused as another launch, or taking over).
enum HomeEnd { case fails, refused, moves }
func homeTries(_ end: HomeEnd, until: Double, blinkAt: Double? = nil, listedAt: Double = 10, lasts: Double = 5) -> (starts: [Double], home: Bool) {
    var sight = P.NetworkSightings()
    var starts: [Double] = [], failed: (listing: Double, count: Int)? = nil, refused: Double? = nil
    var last: Double? = nil, busyUntil = -1.0, atHome = false
    var t = 0.0
    while t <= until, !atHome {
        let listed = t >= listedAt && !(blinkAt.map { t >= $0 && t < $0 + 1 } ?? false)
        sight = P.sightings(sight, listed: listed ? ["A3C5"] : [], now: t)
        if t >= busyUntil, let started = starts.last, busyUntil > 0 {
            busyUntil = -1
            let listing = failed?.listing
            switch end {
            case .fails:
                let l = sight.since["A3C5"] ?? started
                failed = (l, (listing == l ? failed!.count : 0) + 1)
            case .refused: refused = sight.since["A3C5"]
            case .moves: atHome = true
            }
        }
        if busyUntil < 0, !atHome {
            let listing = sight.since["A3C5"]
            let failures = failed.map { $0.listing == listing ? $0.count : 0 } ?? 0
            if P.moveHome(listedSince: listing, lastAttempt: last, failures: failures, refusedListing: refused, now: t).move {
                starts.append(t); last = t; busyUntil = t + lasts
            }
        }
        t = (t * 100 + 5).rounded() / 100   // 0.05 s steps
    }
    return (starts, atHome)
}
var ht = homeTries(.moves, until: 60)
check("model (home): listed at 10: one move at 12, home after it (\(ht.starts))", ht.starts == [12] && ht.home)
ht = homeTries(.fails, until: 300)
check("model (home): moves that never complete: 12, 22, 42, 82, 142, 202, 262 (\(ht.starts))", ht.starts == [12, 22, 42, 82, 142, 202, 262])
ht = homeTries(.fails, until: 120, blinkAt: 50)
check("model (home): the row gone at 50 and back at 51: tried afresh at 53, then 63, 83 (\(ht.starts))", ht.starts == [12, 22, 42, 53, 63, 83])
ht = homeTries(.refused, until: 120)
check("model (home): another launch: one try at 12, never again while it stays listed (\(ht.starts))", ht.starts == [12])
ht = homeTries(.refused, until: 120, blinkAt: 40)
check("model (home): ...listed afresh at 41: tried once more at 43, then never (\(ht.starts))", ht.starts == [12, 43])

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
