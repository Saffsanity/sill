// SpotlightMacs (iOSClient): saved Macs as Spotlight items, and which row a Spotlight tap dials.
// Compiled with iOSClient/SpotlightMacs.swift alone (run.sh).
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}

// Identifiers: one per saved Mac, and only Sill's own read back.
let id = SpotlightMacs.identifier("A1B2C3")
check(id == "mac:A1B2C3", "an item's identifier is the Mac ID behind a prefix")
check(SpotlightMacs.macID(fromIdentifier: id) == "A1B2C3", "and reads back")
check(SpotlightMacs.macID(fromIdentifier: "mac:") == nil, "an empty Mac ID is none")
check(SpotlightMacs.macID(fromIdentifier: "A1B2C3") == nil, "no prefix: not Sill's")
check(SpotlightMacs.macID(fromIdentifier: "window:A1B2C3") == nil, "another prefix: not Sill's")
check(SpotlightMacs.macID(fromIdentifier: "mac:A1:B2") == nil, "a Mac ID never holds a colon")
check(SpotlightMacs.macID(fromIdentifier: "mac:" + String(repeating: "a", count: 200)) == nil, "nor runs past 128 characters")

// Which saved Macs are indexed: not one this device was removed from.
let macs: [SpotlightMacs.Mac] = [.init(macID: "m1", name: "Mac mini", revoked: false),
                                  .init(macID: "m2", name: "Studio", revoked: true),
                                  .init(macID: "m3", name: "", revoked: false)]
let indexed = SpotlightMacs.indexed(macs)
check(indexed.map(\.macID) == ["m1", "m3"], "a removed Mac is left out")
check(indexed.last?.name == "Mac", "a Mac without a name is indexed as Mac")

// A tap: the Mac's row on the network or nearby at once, its Remote row only after the network's wait.
let R = SpotlightMacs.Route.self
let rows: [(route: SpotlightMacs.Route, macID: String?)] = [(R.network, "other"), (R.remote, "m1"), (R.direct, "m1"), (R.network, "m1")]
check(SpotlightMacs.choice(for: "m1", rows: rows, waited: false) == .row(3), "the network row first, at once")
check(SpotlightMacs.choice(for: "m1", rows: [(R.remote, "m1"), (R.direct, "m1")], waited: false) == .row(1), "then a Direct row")
check(SpotlightMacs.choice(for: "m1", rows: [(R.remote, "m1")], waited: false) == .wait, "a Remote row waits for the network's 3 s")
check(SpotlightMacs.choice(for: "m1", rows: [(R.remote, "m1")], waited: true) == .row(0), "then dials it")
check(SpotlightMacs.choice(for: "m1", rows: [], waited: false) == .wait, "no row yet: wait")
check(SpotlightMacs.choice(for: "m1", rows: [], waited: true) == .dialSaved, "no row after the wait: the saved Mac's own dial")
check(SpotlightMacs.choice(for: "m1", rows: [(R.network, nil), (R.network, "other")], waited: true) == .dialSaved,
      "never another Mac's row, nor an unsaved one")

// One index at a time: a write while one runs waits and runs once after it, with the list as it is
// then (a launch's index, then the same launch clearing the list, must end with the cleared list).
var run = SpotlightMacs.Run()
check(run.request(), "idle: a write starts at once")
check(!run.request(), "a write while one runs does not start a second")
check(!run.request(), "nor does a third")
check(run.finished(), "the run ends: one more, for the writes that waited")
check(!run.finished(), "that one ends: nothing waited, so idle")
check(run.request(), "idle again: the next write starts at once")
check(!run.finished(), "a run with nothing waiting ends idle")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
