import Foundation
// H3 (UpdatePolicy): every row of the plan's §6.4, the offer, the schedule, the feeds and pages
// Sill accepts, and every text. Compiled with Sources/StreamProtocol and
// Sources/SillMenuBar/UpdatePolicy.swift (its `import StreamProtocol` dropped).
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = UpdatePolicy
let v03 = SillVersion("0.3.0")!, v04 = SillVersion("0.4")!
let now = Date(timeIntervalSince1970: 1_790_265_600)
let page = "https://github.com/Saffsanity/sill/releases/tag/v0.4.0"
func body(_ tag: Any? = "v0.4.0", html: Any? = page, draft: Any? = false, prerelease: Any? = false) -> Data {
    var d: [String: Any] = ["name": "x", "assets": []]
    if let tag { d["tag_name"] = tag }
    if let html { d["html_url"] = html }
    if let draft { d["draft"] = draft }
    if let prerelease { d["prerelease"] = prerelease }
    return try! JSONSerialization.data(withJSONObject: d)
}
func ok(_ b: Data, etag: String? = "W/\"e1\"") -> P.Answer { .http(status: 200, body: b, etag: etag, rateLimitReset: nil) }
func status(_ s: Int, reset: Date? = nil) -> P.Answer { .http(status: s, body: Data("{}".utf8), etag: nil, rateLimitReset: reset) }
let empty = P.Stored()
let storedRelease = P.Stored(lastCheck: now.addingTimeInterval(-86_400), etag: "W/\"e0\"", latestTag: "v0.4.0", latestURL: page)
let offer04 = P.Offer(version: v04, tag: "v0.4.0", url: URL(string: page)!)
func interpret(_ a: P.Answer, _ s: P.Stored = empty, running: SillVersion = v03, test: Bool = false) -> (P.Outcome, P.Stored) {
    P.interpret(a, stored: s, running: running, now: now, anyReleaseURL: test)
}

// 200, published, newer: everything stored.
var (o, s) = interpret(ok(body()))
check(o == .newer(offer04), "200 newer: \(o)")
check(s == P.Stored(lastCheck: now, etag: "W/\"e1\"", latestTag: "v0.4.0", latestURL: page), "200 newer stores all four: \(s)")
// 200, published, not newer (same, older, and the running version written with its build).
(o, s) = interpret(ok(body("v0.3.0", html: "https://github.com/Saffsanity/sill/releases/tag/v0.3.0")))
check(o == .upToDate(tag: "v0.3.0") && s.latestTag == "v0.3.0" && s.lastCheck == now, "200 same: \(o)")
check(interpret(ok(body("0.2.9")), running: v03).0 == .upToDate(tag: "0.2.9"), "an older release")
check(interpret(ok(body("v0.3.0")), running: SillVersion("0.3.0 (85)")!).0 == .upToDate(tag: "v0.3.0"), "0.3.0 (85) against v0.3.0")
check(interpret(ok(body("v0.10.0", html: page)), running: SillVersion("0.9.5")!).0 != .upToDate(tag: "v0.10.0"), "0.10 is newer than 0.9.5")
check(interpret(ok(body("0.4")), running: v03).0 == .newer(P.Offer(version: v04, tag: "0.4", url: URL(string: page)!)), "a tag without v")
// A 200 without an ETag clears the stored one.
(o, s) = interpret(ok(body(), etag: nil), storedRelease)
check(s.etag == nil && s.latestTag == "v0.4.0", "200 without an ETag clears it: \(s)")
// 304 with a stored release: as for it, newer or not; only the time moves.
(o, s) = interpret(status(304), storedRelease)
check(o == .newer(offer04) && s == P.Stored(lastCheck: now, etag: storedRelease.etag, latestTag: "v0.4.0", latestURL: page), "304 newer: \(o) \(s)")
(o, s) = interpret(status(304), storedRelease, running: v04)
check(o == .upToDate(tag: "v0.4.0"), "304 after updating: up to date")
// 304 with no stored release.
(o, s) = interpret(status(304))
check(o == .notARelease("a 304 before any release") && s.lastCheck == now, "304 before any release: \(o)")
// 404: a withdrawn release stops being offered.
(o, s) = interpret(status(404), storedRelease)
check(o == .noRelease && s == P.Stored(lastCheck: now), "404 clears ETag, tag and URL: \(s)")
// 403 and 429, with and without the reset.
let reset = now.addingTimeInterval(42 * 60)
(o, s) = interpret(status(403, reset: reset), storedRelease)
check(o == .limited(status: 403, reset: reset) && s == P.Stored(lastCheck: now, etag: storedRelease.etag, latestTag: "v0.4.0", latestURL: page), "403: \(o)")
check(interpret(status(429)).0 == .limited(status: 429, reset: nil), "429 without a reset")
// Any other status.
check(interpret(status(502)).0 == .httpError(502) && interpret(status(500)).0 == .httpError(500) && interpret(status(301)).0 == .httpError(301), "other statuses")
check(interpret(status(500), storedRelease).1.latestTag == "v0.4.0", "a 5xx keeps the stored release")
// 200s that are not published releases: only the time moves, the stored release stays.
let notReleases: [(Data, String)] = [
    (body(nil), "no tag_name"), (body(4), "no tag_name"), (body("nightly"), "the tag “nightly” is not a version"),
    (body(draft: true), "a draft"), (body(prerelease: true), "a prerelease"),
    (body(html: "https://evil.example/sill"), "html_url is not on github.com"), (body(html: "http://github.com/x"), "html_url is not on github.com"),
    (body(html: nil), "html_url is not on github.com"), (body(html: "https://github.com.evil.example/x"), "html_url is not on github.com"),
    (Data("[1,2]".utf8), "not a JSON object"), (Data("<html>".utf8), "not a JSON object"), (Data(), "not a JSON object"),
]
for (b, why) in notReleases {
    (o, s) = interpret(ok(b), storedRelease)
    check(o == .notARelease(why), "not a release (\(why)): \(o)")
    check(s == P.Stored(lastCheck: now, etag: storedRelease.etag, latestTag: "v0.4.0", latestURL: page), "not a release keeps the stored release (\(why))")
}
check(interpret(ok(body(draft: NSNull(), prerelease: nil))).0 == .newer(offer04), "draft and prerelease missing or null count as false")
// With a test feed any http or https page counts.
check(interpret(ok(body(html: "http://127.0.0.1:8080/release")), test: true).0 == .newer(P.Offer(version: v04, tag: "v0.4.0", url: URL(string: "http://127.0.0.1:8080/release")!)), "a test feed's page")
check(interpret(ok(body(html: "file:///etc/passwd")), test: true).0 == .notARelease("html_url is not on github.com"), "never a file URL")
// A refused redirect and a body too large.
(o, s) = interpret(.redirected(host: "evil.example"), storedRelease)
check(o == .notARelease("a redirect to evil.example") && s.lastCheck == now && s.latestTag == "v0.4.0", "a redirect elsewhere: \(o)")
check(interpret(.tooLarge).0 == .notARelease("more than 1 MB"), "more than 1 MB")
// No HTTP answer: nothing stored.
for code in [-1009, -1005, -1004, -1003, -1006, -1020, -1018, -1200, -1202, -1206] {
    (o, s) = interpret(.failed(code: code, description: "d"), storedRelease)
    check(o == .noConnection(code: code, description: "d") && s == storedRelease && !o.answered, "no connection \(code)")
}
(o, s) = interpret(.failed(code: -1001, description: "timed out"), storedRelease)
check(o == .timeout && s == storedRelease && !o.answered, "timeout")
(o, s) = interpret(.failed(code: -1100, description: "odd"), storedRelease)
check(o == .failed(code: -1100, description: "odd") && s == storedRelease && !o.answered, "another URLError")
check(P.Outcome.noRelease.answered && P.Outcome.limited(status: 403, reset: nil).answered && P.Outcome.httpError(500).answered
      && P.Outcome.notARelease("x").answered && P.Outcome.upToDate(tag: "v").answered, "HTTP answers")

// The offer: the stored release, newer than what runs, on github.com.
check(P.offer(stored: storedRelease, running: v03) == offer04, "offered")
check(P.offer(stored: storedRelease, running: v04) == nil, "gone once 0.4 runs (updated)")
check(P.offer(stored: storedRelease, running: SillVersion("0.5")!) == nil, "a build ahead of the release")
check(P.offer(stored: storedRelease, running: SillVersion("0.2")!) == offer04, "back after a downgrade")
check(P.offer(stored: storedRelease, running: nil) == nil, "no running version, no offer")
var forged = storedRelease; forged.latestURL = "https://evil.example/sill"
check(P.offer(stored: forged, running: v03) == nil, "a stored page not on github.com is never offered")
check(P.offer(stored: P.Stored(latestTag: "nightly", latestURL: page), running: v03) == nil, "a stored tag that is not a version")

// When.
check(P.isDue(lastCheck: nil, now: now, period: P.period), "never checked: due")
check(P.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now, period: P.period), "24 h ago: due")
check(!P.isDue(lastCheck: now.addingTimeInterval(-86_399), now: now, period: P.period), "just under 24 h: not due")
check(P.isDue(lastCheck: now.addingTimeInterval(3600), now: now, period: P.period), "in the future (the clock went back): due")
let last = now.addingTimeInterval(-3600)
check(P.nextCheck(lastCheck: last, retryAt: nil, now: now, period: P.period, jitter: 600, delay: 30) == last.addingTimeInterval(86_400 + 600), "a period and the jitter after the last answer")
check(P.nextCheck(lastCheck: nil, retryAt: nil, now: now, period: P.period, jitter: 600, delay: 30) == now.addingTimeInterval(30), "due: 30 s from now")
check(P.nextCheck(lastCheck: now.addingTimeInterval(-90_000), retryAt: nil, now: now, period: P.period, jitter: 600, delay: 30) == now.addingTimeInterval(30), "overdue (a wake): 30 s")
check(P.nextCheck(lastCheck: last, retryAt: now.addingTimeInterval(3600), now: now, period: P.period, jitter: 0, delay: 30) == now.addingTimeInterval(3600), "a retry an hour later")
check(P.nextCheck(lastCheck: last, retryAt: now.addingTimeInterval(-10), now: now, period: P.period, jitter: 0, delay: 30) == now.addingTimeInterval(30), "a retry that fell due asleep: 30 s after the wake")
check(P.period == 86_400 && P.jitter == 1800 && P.retry == 3600 && P.launchDelay == 30 && P.requestTimeout == 10 && P.maxBody == 1 << 20, "the constants")
// The jitter's range, as UpdateChecker draws it.
var inRange = true
for _ in 0..<1000 { let j = TimeInterval.random(in: 0...P.jitter); let n = P.nextCheck(lastCheck: last, retryAt: nil, now: now, period: P.period, jitter: j, delay: 30)
    if n < last.addingTimeInterval(86_400) || n > last.addingTimeInterval(86_400 + 1800) { inRange = false } }
check(inRange, "the next check is 24 h to 24 h 30 min after the last")

// Feeds and pages.
for (u, want) in [("http://127.0.0.1:8080/latest", true), ("https://127.0.0.1/x", true), ("http://[::1]:9/latest", true), ("http://localhost:1/", true),
                  ("http://LOCALHOST:1/", true), ("http://127.0.0.2/", false), ("https://api.github.com/repos/Saffsanity/sill/releases/latest", false),
                  ("ftp://127.0.0.1/x", false), ("http://localhost.evil.example/", false), ("http://127.0.0.1.nip.io/", false),
                  ("file:///tmp/feed.json", false), ("http://192.168.1.2/", false)] {
    check(P.isLocalFeed(URL(string: u)!) == want, "isLocalFeed(\(u)) == \(want)")
}
check(P.redirectAllowed(URL(string: "https://api.github.com/repositories/1/releases/latest")!), "a redirect within api.github.com")
check(!P.redirectAllowed(URL(string: "http://api.github.com/x")!) && !P.redirectAllowed(URL(string: "https://api.github.com.evil.example/x")!)
      && !P.redirectAllowed(URL(string: "https://github.com/x")!) && !P.redirectAllowed(URL(string: "http://127.0.0.1/x")!), "redirects elsewhere refused")
check(P.feed.absoluteString == "https://api.github.com/repos/Saffsanity/sill/releases/latest", "the feed")

// Words.
let t: (Date) -> String = { _ in "15:42" }
check(P.menuTitle(offer04) == "Sill 0.4 Is Available…" && P.menuSubtitle(running: v03) == "You have 0.3; opens its download page", "the menu item")
func log(_ o: P.Outcome, manual: Bool = false, retry: TimeInterval = 3600) -> String? { P.logLine(o, manual: manual, running: "0.3.0", retryIn: retry, time: t) }
check(log(.newer(offer04)) == "Update check: Sill 0.4 is available (this is 0.3.0): \(page)" && log(.newer(offer04), manual: true) == log(.newer(offer04)), "log: newer")
check(log(.upToDate(tag: "v0.3.0")) == nil, "log: nothing new, automatic: nothing")
check(log(.upToDate(tag: "v0.3.0"), manual: true) == "Update check: up to date (this is 0.3.0; the latest release is v0.3.0).", "log: up to date, Check Now")
check(log(.noRelease) == "Update check failed: GitHub has no release of Sill (HTTP 404)." && log(.noRelease, manual: true) == log(.noRelease), "log: 404")
check(log(.limited(status: 403, reset: reset)) == "Update check failed: GitHub is limiting requests from this network (HTTP 403; it resets at 15:42).", "log: 403")
check(log(.limited(status: 429, reset: nil)) == "Update check failed: GitHub is limiting requests from this network (HTTP 429).", "log: 429 without a reset")
check(log(.httpError(502)) == "Update check failed: HTTP 502.", "log: 502")
check(log(.notARelease("a draft")) == "Update check failed: the answer is not a published release (a draft).", "log: not a release")
check(log(.noConnection(code: -1009, description: "The Internet connection appears to be offline.")) == "Update check failed: no connection (-1009: The Internet connection appears to be offline.); trying again in 1 hour.", "log: offline")
check(log(.noConnection(code: -1009, description: "x"), manual: true) == "Update check failed: no connection (-1009: x).", "log: offline, Check Now")
check(log(.timeout) == "Update check failed: no answer in 10 s; trying again in 1 hour." && log(.timeout, manual: true) == "Update check failed: no answer in 10 s.", "log: timeout")
check(log(.failed(code: -1100, description: "odd")) == "Update check failed: odd (-1100); trying again in 1 hour.", "log: other")
check(log(.timeout, retry: 4.0 / 24 < 1 ? 1 : 4.0 / 24) == "Update check failed: no answer in 10 s; trying again in 1 s.", "log: a scaled retry")
check(P.duration(3600) == "1 hour" && P.duration(7200) == "2 hours" && P.duration(1800) == "30 minutes" && P.duration(4) == "4 s", "durations")
func line(_ o: P.Outcome) -> (String, Bool) { let r = P.resultLine(o, time: t); return (r.text, r.failed) }
check(line(.newer(offer04)) == ("Sill 0.4 is available.", false) && line(.upToDate(tag: "v0.3.0")) == ("Sill is up to date.", false), "pane: found, up to date")
check(line(.noRelease) == ("Couldn’t check: GitHub has no release of Sill yet.", true), "pane: 404")
check(line(.limited(status: 403, reset: reset)) == ("Couldn’t check: GitHub is limiting requests from this network. Try again after 15:42.", true), "pane: 403")
check(line(.limited(status: 403, reset: nil)) == ("Couldn’t check: GitHub is limiting requests from this network. Try again in an hour.", true), "pane: 403 without a reset")
check(line(.httpError(502)) == ("Couldn’t check: GitHub answered with an error (HTTP 502).", true), "pane: 502")
check(line(.notARelease("x")) == ("Couldn’t check: GitHub’s answer wasn’t a release Sill understands.", true), "pane: not a release")
check(line(.noConnection(code: -1009, description: "x")) == ("Couldn’t check: this Mac isn’t connected to the internet.", true), "pane: offline")
check(line(.noConnection(code: -1202, description: "The certificate for this server is invalid.")) == ("Couldn’t check: The certificate for this server is invalid.", true), "pane: TLS")
check(line(.timeout) == ("Couldn’t check: GitHub didn’t answer within 10 seconds.", true), "pane: timeout")
check(line(.failed(code: -1, description: "Something.")) == ("Couldn’t check: Something.", true), "pane: other")
func pane(checking: Bool = false, result: P.Outcome? = nil, offer: P.Offer? = nil, lastCheck: Date? = nil, hasVersion: Bool = true, testPattern: Bool = false) -> P.Pane {
    P.pane(checking: checking, result: result, resultID: 3, offer: offer, lastCheck: lastCheck, hasVersion: hasVersion, testPatternOnly: testPattern,
           time: t, date: { _ in "Sep 24, 2026 at 13:00" })
}
check(pane() == P.Pane(line: "Not checked yet.", failed: false, releasePage: nil, canCheck: true, resultID: 3), "pane: never")
check(pane(lastCheck: last).line == "Last checked Sep 24, 2026 at 13:00.", "pane: last checked")
check(pane(checking: true, result: .noRelease, lastCheck: last) == P.Pane(line: "Checking…", releasePage: nil, canCheck: false, resultID: 3), "pane: checking, Check Now off")
check(pane(result: .noRelease, offer: offer04).line == "Couldn’t check: GitHub has no release of Sill yet." && pane(result: .noRelease).failed, "pane: a result wins")
check(pane(offer: offer04, lastCheck: last) == P.Pane(line: "Sill 0.4 is available.", releasePage: URL(string: page)!, canCheck: true, resultID: 3), "pane: offered, Open Release Page…")
check(pane(hasVersion: false) == P.Pane(line: "This build of Sill has no version number, so it can’t check.", canCheck: false, resultID: 3), "pane: no version")
check(pane(lastCheck: last, testPattern: true) == P.Pane(line: "Sill doesn’t check for updates in test pattern mode.", canCheck: false, resultID: 3), "pane: test pattern")
check(P.footnote.contains("GitHub sees this Mac’s IP address and which version of Sill it has; nothing else is sent."), "the footnote says what is sent")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
