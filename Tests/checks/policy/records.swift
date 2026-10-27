// A row keeps its TXT record while its result stays listed (DiscoveryPolicy.rowRecords; Noah's iPad,
// 2026-10-27: with the USB cable pulled, iPadOS listed the Mac on en2 and en0, then on en0 alone, with no
// TXT record at all, so its row was taken by its name alone and read "Update Sill"), in the policy check:
// the console's listings through the rows, their words, the sightings and the Remote rows; a browser made
// again (issue #69), which starts afresh (the review of #232: a service that took the Mac's name while Sill
// was in the background is never read with the Mac's old record), and one that failed and waits, whose rows
// stay as they were; the DEBUG test rows beside a result of the same name; a name in two domains; and
// random sessions of a browser's reports, with rebuilds, against a model. A function main.swift calls after
// pairing at home's.
import Foundation

func rowRecordsPolicy() {
    typealias Rec = P.RowRecord
    typealias Key = P.RowRecordKey
    typealias I = P.Interface
    typealias R = (key: Key, record: Rec?)
    let mac = "Noah\u{2019}s MacBook Pro"
    /// `name`'s result from browser `b` (the first unless said), in `domain` ("local." unless said).
    func k(_ name: String, _ b: Int = 1, _ domain: String = "local.") -> Key { Key(browser: b, name: name, domain: domain) }
    let paired = Rec(tag: "TAG", door: .pairingRequired)          // "TAG" names the saved Mac "M"
    let anpi0 = I(name: "anpi0", type: .wiredEthernet), en2 = I(name: "en2", type: .wiredEthernet), en0 = I(name: "en0", type: .wifi)
    let saved: [(macID: String, bonjourName: String?)] = [("M", mac)]
    /// A row as recomputeMacs builds it from the record it is read with: the saved Mac it is (by the
    /// tag, else by its name alone), its word and a tap's dial in a DEBUG build, M seen over TLS.
    func row(_ record: Rec?, _ interfaces: [I]) -> (macID: String?, byName: Bool, word: P.RowWord, tap: P.HomeDial) {
        let tagged = record?.tag == "TAG" ? "M" : nil
        let carries = !(record?.tag ?? "").isEmpty
        let named = P.rowMac(tagged: tagged, carriesTag: carries, name: mac, saved: saved)
        let door = P.rowDoor(record?.door ?? .plain, otherTagUnderSavedName: P.otherTagUnderSavedName(tagged: tagged, carriesTag: carries,
                                                                                                        name: mac, saved: saved))
        let method = P.method(direct: false, interfaces: interfaces)
        return (tagged, named?.tagNamed == false,
                P.rowWord(door: door, saved: named != nil, revoked: false, homeTLS: true, debug: true, method: method, cable: false),
                P.homeDial(door: door, saved: named != nil, revoked: false, homeTLS: true, debug: true, tap: true))
    }
    func remoteRowsOfM(_ listedIDs: [String?], now: Double = 20) -> [String] {
        P.remoteRows(saved: [(macID: "M", name: mac)], listedIDs: Set(listedIDs.compactMap { $0 }), now: now, searchingSince: 0,
                     localNetworkDenied: false).map(\.macID)
    }

    // The console's three listings, as recomputeMacs reads each report of the network browser: the rows,
    // the sightings by name, the Mac IDs its network rows name (the saved Mac's sightings, its Remote row).
    var records: [Key: Rec] = [:], sightings = P.NetworkSightings()
    var seen: [(macID: String?, byName: Bool, word: P.RowWord, tap: P.HomeDial)] = [], since: [Double?] = [], remote: [Int] = []
    var before: [P.RowWord] = []
    for (t, interfaces, record) in [(1.0, [anpi0, en2, en0], paired as Rec?), (2.0, [en2, en0], nil), (2.5, [en0], nil)] {
        let rows = P.rows(network: [mac], nearby: [])
        records = P.rowRecords(records, listed: rows.map { (key: k($0.name), record: record) })
        sightings = P.sightings(sightings, listed: Set(rows.map(\.name)), now: t)
        let r = row(records[k(mac)], interfaces)
        seen.append(r)
        since.append(sightings.since[mac])
        remote.append(remoteRowsOfM([r.macID], now: t + 10).count)
        before.append(row(record, interfaces).word)
    }
    check("records: the cable pulled, the Mac's row Wired, Wired, Wi‑Fi, M by its tag throughout, dialed pinned",
          seen.map(\.word) == [.method(.wired), .method(.wired), .method(.wifi)] && seen.allSatisfy { $0.macID == "M" && !$0.byName && $0.tap == .pinned })
    check("records: listed since its first look throughout, and no Remote row for M beside it", since == [1, 1, 1] && remote == [0, 0, 0])
    check("records: before the fix, Wired, then Update Sill twice", before == [.method(.wired), .updateSill, .updateSill])
    check("records: before the fix, the row named no Mac ID, so M's Remote row came beside it", remoteRowsOfM([row(nil, [en0]).macID], now: 12.5) == ["M"])

    // A browser made again (back from the background, or after a failure): the old one's last results
    // beside the new one's while it settles (DiscoveryPolicy.browserResults), keyed by the browser that
    // delivered them. Here the cable was pulled before: the old result carries no record and M's is kept.
    let ends = 100 + P.rebuildSettle
    func shown(_ kept: [R], _ fresh: [R], _ t: Double, settle: Double? = ends) -> [R] {
        P.browserResults(kept: kept, fresh: fresh, name: { $0.key.name }, settleEnds: settle, now: t)
    }
    var rebuilt: [Key: Rec] = [k(mac): paired]
    rebuilt = P.rowRecords(rebuilt, listed: shown([(k(mac), nil)], [], 100))
    let whileOldShown = rebuilt[k(mac)]
    rebuilt = P.rowRecords(rebuilt, listed: shown([(k(mac), nil)], [(k(mac, 2), nil)], 100.05))
    let newWithout = rebuilt[k(mac, 2)]
    rebuilt = P.rowRecords(rebuilt, listed: shown([(k(mac), nil)], [(k(mac, 2), nil)], 200))
    check("records: a browser made again: the old browser's result keeps M's record while it alone is shown; the new browser's result of the name, without a record, is read with none, while it settles and after",
          whileOldShown == paired && newWithout == nil && rebuilt.isEmpty)
    var resolved: [Key: Rec] = [k(mac): paired]
    resolved = P.rowRecords(resolved, listed: shown([(k(mac), nil)], [], 100))
    resolved = P.rowRecords(resolved, listed: shown([(k(mac), nil)], [(k(mac, 2), paired)], 100.05))
    resolved = P.rowRecords(resolved, listed: shown([(k(mac), nil)], [(k(mac, 2), nil)], 101))
    check("records: …and with its own record (a fresh browse resolves the TXT record again), M's row as before, kept as it goes on",
          resolved == [k(mac, 2): paired] && row(resolved[k(mac, 2)], [en0]).word == .method(.wifi))
    // The review of #232: M listed with its record; Sill in the background, M's registration gone meanwhile
    // and its name taken by another service with no record (an older Sill, the CLI); the browser made again
    // on the return lists that name with no record.
    var back: [Key: Rec] = P.rowRecords([:], listed: [(k(mac), paired)])
    back = P.rowRecords(back, listed: shown([(k(mac), paired)], [], 100))
    back = P.rowRecords(back, listed: shown([(k(mac), paired)], [(k(mac, 2), nil)], 100.2))
    let other = row(back[k(mac, 2)], [en0])
    check("records: a service that took M's name while Sill was in the background, listed with no record: by its name alone, Update Sill, nothing dialed",
          back.isEmpty && other.macID == nil && other.byName && other.word == .updateSill && other.tap == .updateSill)
    check("records: …M's Remote row stays, and the reconnect's refused pinned dial of such a row only skips it, never newKey",
          remoteRowsOfM([other.macID]) == ["M"]
          && P.afterPinRefused(macID: "M", tried: ["network:\(mac)"], rows: [("network:\(mac)", other.macID)], tagNamed: !other.byName, tapped: false) == .skipRow)
    var oneKey: [Key: Rec] = P.rowRecords([:], listed: [(k(mac), paired)])
    oneKey = P.rowRecords(oneKey, listed: [(k(mac), nil)])
    let asM = row(oneKey[k(mac)], [en0])
    check("records: …where one key for both browsers (the rule as #232 first had it) read it as M: Remote row hidden, dialed pinned, a refusal marking M newKey",
          asM.macID == "M" && remoteRowsOfM([asM.macID]).isEmpty && asM.tap == .pinned
          && P.afterPinRefused(macID: "M", tried: ["network:\(mac)"], rows: [("network:\(mac)", "M")], tagNamed: true, tapped: false) == .newKey)
    var settled: [Key: Rec] = [k(mac): paired]
    settled = P.rowRecords(settled, listed: shown([(k(mac), nil)], [], 101))
    let duringSettle = settled[k(mac)]
    settled = P.rowRecords(settled, listed: shown([(k(mac), nil)], [], ends))
    check("records: a name the new browser does not list keeps its record while the old results are shown, and is forgotten at the settle's end",
          duringSettle == paired && settled.isEmpty)
    var waiting: [Key: Rec] = [k(mac): paired]
    waiting = P.rowRecords(waiting, listed: shown([(k(mac), nil)], [], 1e9, settle: .infinity))
    let waited = waiting[k(mac)]
    waiting = P.rowRecords(waiting, listed: shown([(k(mac), nil)], [(k("Office"), nil)], 1e9 + 1, settle: .infinity))
    check("records: while a failed browser waits to be made again, the rows as they were, the record with them, and what it still says joins them",
          waited == paired && waiting == [k(mac): paired])
    // The nearby browser stopped (its results gone) and started again: another browser, nothing kept.
    var nearby = P.rowRecords([:], listed: [(k(mac, 3), paired)])
    nearby = P.rowRecords(nearby, listed: [])
    nearby = P.rowRecords(nearby, listed: [(k(mac, 4), nil)])
    check("records: the nearby browser stopped, then another listing the Mac without a record: no record (a plain door)", nearby.isEmpty)
    // A DEBUG test row (no browser: 0) after a result of the same name: the row, built from its name's first
    // entry, the result, reads the result's record, never the test row's own making.
    let testRow = Rec(tag: nil, door: .pairingRequired)
    let withTest = P.rowRecords([k(mac): paired], listed: [(k(mac), nil), (k(mac, 0), testRow)])
    check("records: a test row of a result's name never lends the result its record",
          P.rowRecords([:], listed: [(k(mac), nil), (k(mac, 0), testRow)])[k(mac)] == nil && withTest[k(mac)] == paired && withTest[k(mac, 0)] == testRow)
    // Two test rows of one name (a move test's and a path test's, say) share their key, browser 0: the row,
    // built from the first, is read with the first's record, as the rule reads a key listed twice.
    check("records: two test rows of one name, one key: read with the first's record",
          P.rowRecords([:], listed: [(k(mac, 0), testRow), (k(mac, 0), Rec(tag: nil, door: .plain))]) == [k(mac, 0): testRow])
    let twoDomains = P.rowRecords(P.rowRecords([:], listed: [(k(mac, 1, "local."), paired)]),
                                  listed: [(k(mac, 1, "example.com."), nil), (k(mac, 1, "local."), nil)])
    check("records: a name in two domains, two results: the one with no record of its own never reads the other's",
          twoDomains == [k(mac, 1, "local."): paired])

    // 5,000 random sessions of 40 reports at three names (one of them also in a second domain), each
    // listed or not, without a record or with one of four, and now and then the browser made again: the
    // rows' results kept beside the new one's for its settle, the new browser's own under its new number.
    // Each result is read with the last record it carried since it was last listed afresh among what the
    // rows show, never one it was not given then, nothing once it left, and never what a browser it did
    // not come from delivered.
    struct LCG {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    }
    var rng = LCG(s: 0x2026_1027)
    let services = [("A", "local."), ("B", "local."), ("C", "local."), ("A", "example.com.")]
    let choices = [paired, Rec(tag: "TAG", door: .open), Rec(tag: "TAG", door: .plain), Rec(tag: "NEW", door: .pairingRequired)]
    var sessions = 0, agreed = 0, onlyGiven = true, forgotten = true, rebuilds = 0, afterRebuild = 0, crossed = 0
    for _ in 0..<5_000 {
        var memory: [Key: Rec] = [:], runs: [Key: [Rec?]] = [:]
        var browser = 1, kept: [R] = [], shownNow: [R] = [], settleEnds: Double?, ok = true
        for step in 0..<40 {
            let t = Double(step)
            if rng.next() % 8 == 0 { kept = shownNow; settleEnds = t + P.rebuildSettle; browser += 1; rebuilds += 1 }
            let fresh: [R] = services.compactMap { s in
                switch rng.next() % 4 {
                case 0: return nil
                case 1: return (k(s.0, browser, s.1), nil)
                default: return (k(s.0, browser, s.1), choices[Int(rng.next() % UInt64(choices.count))])
                }
            }
            shownNow = P.browserResults(kept: kept, fresh: fresh, name: { $0.key.name }, settleEnds: settleEnds, now: t)
            if let e = settleEnds, t >= e { kept = []; settleEnds = nil }
            let before = memory
            memory = P.rowRecords(memory, listed: shownNow)
            let keys = Set(runs.keys).union(shownNow.map(\.key))
            for key in keys {
                let item = shownNow.first { $0.key == key }
                if let item { runs[key, default: []].append(item.record) } else { runs[key] = nil }
                if memory[key] != runs[key]?.reversed().compactMap({ $0 }).first { ok = false }
                if let got = memory[key], !(runs[key] ?? []).contains(got) { onlyGiven = false }
                if item == nil, memory[key] != nil { forgotten = false }
                // A result of the new browser, without a record, under a name an older browser's result had one for.
                if let item, item.record == nil, key.browser == browser, before.contains(where: { $0.key.browser < browser && $0.key.name == key.name }) {
                    afterRebuild += 1
                    if let got = memory[key], !(runs[key] ?? []).contains(got) { crossed += 1 }
                }
            }
        }
        sessions += 1
        if ok { agreed += 1 }
    }
    check("records: \(agreed) of \(sessions) random sessions (\(rebuilds) rebuilds) read each result as the model does", agreed == sessions && rebuilds > 1_000)
    check("records: a result is only ever read with a record delivered for it since it was last listed afresh, and none once it left",
          onlyGiven && forgotten)
    check("records: a new browser's result without a record, under a name the old browser had a record for, never read with that record (\(afterRebuild) times)",
          crossed == 0 && afterRebuild > 100)
}
