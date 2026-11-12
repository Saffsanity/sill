import Foundation
import StreamProtocol

/// Automatically update Sill (docs/one-click-update-plan.md §15): when Sill installs an update by itself,
/// and what it remembers. Pure: Foundation and SillVersion. AppUpdater asks it and runs the same state
/// machine and the same steps as Update Now (UpdateInstallPolicy.next, UpdateInstaller), so nothing here
/// is weaker than a click: the same two checks before and after the download (Apple's signature and
/// notarization, and the release signed with Sill's own update key), the same swap, the same refusals.
///
/// Noah's decisions of 2026-11-12 ("Your defaults are correct for the new updater features"): off by
/// default; usable only while the daily check is on and where Update Now is available; it downloads and
/// checks quietly and installs only while no device is connected, never disconnecting anyone; it needs
/// the update key and passes the same two checks as Update Now; a failed update is tried again at the next
/// daily check, never in a loop. The waits and counts below are the open questions' defaults (§10).
enum UpdateAutoPolicy {
    // MARK: The defaults (open questions, §10)

    /// How long after THIS Sill first read a release's verified manifest (and after its signed time, if that
    /// is later) before Sill installs it by itself (`Memory.Sighting`; the second security pass's A1: the
    /// signed line is written by whoever holds the key, so it can't be what the wait counts from). Every Mac
    /// with the switch on so waits at least this long after a release appears on GitHub, however its manifest
    /// is dated: the time Noah has to notice a release he didn't sign (Scripts/sign-update.sh --audit) and pull
    /// it or stop it. Update Now isn't held. Noah's decision of 2026-11-12: "48 hour wait seems ok" (plan
    /// §15.1). Zero turns the wait off.
    static let coolingOff: TimeInterval = 48 * 3600
    /// The oldest signature Sill installs by itself: an old release offered as the latest again (a
    /// rollback through GitHub, review 3's F7) is left to Update Now and the person's eyes.
    static let maxAge: TimeInterval = 120 * 24 * 3600
    /// A signature dated this far ahead of this Mac's clock is refused (its clock, or the signer's, is wrong).
    static let clockSkew: TimeInterval = 10 * 60
    /// How long no device must have been connected before Sill installs. Noah's decision of 2026-11-12: "can
    /// the 10 minute wait be shortened to 5 minutes?" (plan §15.1). Still far longer than any reconnect Sill
    /// makes by itself: the device's redials of a listed Mac are 5, 10, 20 and then 30 s apart (a dial let go
    /// after 5 s), so one that wants back is in again within about 35 s, and every connection starts the wait
    /// over; the cable and Wi-Fi moves hand over with no moment unconnected. Every word that names the wait
    /// comes from here (`quietMinutes`).
    static let quietFor: TimeInterval = 5 * 60
    /// Automatic attempts at one version (a failure of any kind counts, a new version that didn't start and
    /// was put back too) before Sill leaves that version to Update Now.
    static let maxAttempts = 2
    /// The least time between two automatic attempts at one version: one a daily check, never a loop.
    static let retryAfter: TimeInterval = 20 * 3600
    /// A checked copy that waited this long for a quiet moment is dropped (and is never kept across
    /// launches); a later check downloads and checks it again.
    static let maxWait: TimeInterval = 24 * 3600
    /// How long Settings says that Sill updated itself.
    static let updatedShown: TimeInterval = 7 * 24 * 3600

    /// What is kept stays small whatever is offered (the second security pass's A3): at most this many
    /// attempts and sightings, each only for a version newer than the one running, and at most `maxStops`
    /// stops, so the keychain item never comes near `maxItemBytes`.
    static let maxRemembered = 8
    static let maxStops = 32
    /// The keychain item's largest size that is read; a larger one is unreadable, never "nothing remembered".
    static let maxItemBytes = 64 << 10

    /// The waits in Settings' words.
    static var quietMinutes: Int { Int((quietFor / 60).rounded()) }
    /// "two days after it first finds it" (counted from this Sill's first read of the release's signed
    /// manifest), or "once it finds it" when the wait is off.
    static var coolingOffWords: String {
        guard coolingOff > 0 else { return "once it finds it" }
        let hours = Int((coolingOff / 3600).rounded())
        let small = ["a", "two", "three", "four", "five", "six", "seven"]
        guard hours % 24 == 0, (1...7).contains(hours / 24) else { return "\(hours) hours after it first finds it" }
        return "\(small[hours / 24 - 1]) day\(hours == 24 ? "" : "s") after it first finds it"
    }

    // MARK: What Sill remembers

    /// Kept with the switch in Sill's own keychain item (AutoUpdateStore), never in its defaults: nothing
    /// written there or given as an argument turns the switch on, and what is remembered here only ever
    /// makes Sill do less by itself.
    struct Memory: Codable, Equatable, Sendable {
        /// The switch.
        var on = false
        /// Automatic attempts, by version (SillVersion's text).
        var attempts: [String: Attempt] = [:]
        /// The highest version whose release, signed with the update key, this Sill has read (the manifest
        /// verified, by Update Now or by itself): a lower one offered later is a rollback, never installed by
        /// itself. The check's offers alone never count: GitHub's word isn't signed, and a made-up "v9.9" there
        /// would otherwise stop every later update.
        var highestSigned: String?
        /// Releases a signed stop named (their tags): never installed, also after the stop is gone.
        var stopped: [String] = []
        /// The last update Sill installed by itself, and when, to say so afterwards.
        var updatedTo: String?
        var updatedAt: Date?
        /// When this Sill first read each release's verified manifest (by tag and zip SHA-256): the cooling-off
        /// counts from there (A1), across launches. A release whose zip changed is a new sighting.
        var seen: [Sighting] = []

        init() {}

        /// Every field optional in what is stored: an item written before a field existed reads as its default.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
            attempts = try c.decodeIfPresent([String: Attempt].self, forKey: .attempts) ?? [:]
            highestSigned = try c.decodeIfPresent(String.self, forKey: .highestSigned)
            stopped = try c.decodeIfPresent([String].self, forKey: .stopped) ?? []
            updatedTo = try c.decodeIfPresent(String.self, forKey: .updatedTo)
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
            seen = try c.decodeIfPresent([Sighting].self, forKey: .seen) ?? []
        }

        struct Attempt: Codable, Equatable, Sendable {
            var count: Int
            var last: Date
            /// The last failure's words for the log (nil while one runs).
            var failure: String?
        }

        struct Sighting: Codable, Equatable, Sendable {
            let tag: String
            /// The zip's SHA-256, as the verified manifest names it.
            let sha256: String
            /// When this Sill first read the verified manifest (this Mac's clock).
            let first: Date
            /// The manifest's own signed time.
            let signed: Date
        }
    }

    // MARK: Whether to begin

    enum Start: Equatable, Sendable {
        case go
        /// Why not (the log's words).
        case no(String)
    }

    /// Whether Sill begins an automatic update of `offered` now: after a check offered it, and only from
    /// an idle updater (never beside Update Now, never twice). `available`: this build has Update Now;
    /// `signed`: the release lists a manifest; `refusal`: why Update Now can't run here; `waitUntil`: the
    /// end of the release's cooling-off, from what this Sill remembers (`waitUntil(_:tag:)`).
    static func start(_ m: Memory, checkOn: Bool, available: Bool, refusal: UpdateInstallPolicy.Refusal?,
                      offered: SillVersion?, offeredTag: String?, signed: Bool, running: SillVersion?, idle: Bool,
                      waitUntil: Date? = nil, now: Date) -> Start {
        guard m.on else { return .no("the switch is off") }
        guard checkOn else { return .no("the daily check is off") }
        guard available, let running else { return .no("Update Now isn’t available in this build") }
        guard idle else { return .no("an update is under way or waiting") }
        guard let offered, let offeredTag else { return .no("no release is offered") }
        guard offered > running else { return .no("the offered release isn’t newer") }
        guard signed else { return .no("the release isn’t signed with Sill’s update key yet") }
        if let r = refusal { return .no(UpdateInstallPolicy.words(r)) }
        if m.stopped.contains(offeredTag) { return .no("a stop signed with an update key names \(offeredTag)") }
        if let highest = m.highestSigned.flatMap(UpdateInstallPolicy.strictVersion), offered < highest {
            return .no("the latest release went back from \(highest) to \(offered)")
        }
        if let a = m.attempts[offered.description] {
            if a.count >= maxAttempts { return .no("\(a.count) attempts at \(offered) failed; Update Now still can") }
            if now.timeIntervalSince(a.last) < retryAfter { return .no("\(offered) was tried at \(UpdateManifest.dateText(a.last))") }
        }
        if let waitUntil, now < waitUntil { return .no("\(offered) cools off until \(UpdateManifest.dateText(waitUntil))") }
        return .go
    }

    /// What the manifest's signed date says to the automatic update.
    enum DateVerdict: Equatable, Sendable {
        case go
        /// Not before this moment (the cooling-off): no attempt is spent.
        case waitUntil(Date)
        /// Never by itself (Update Now still can): why.
        case refuse(String)
    }

    /// The manifest's own date and this Sill's first sight of it against now: install, wait until a moment,
    /// or never by itself. The signed date, which whoever holds the key writes, bounds only the age (120 days)
    /// and the future; the cooling-off counts from the later of it and `firstSeen` (A1), so a manifest dated
    /// back still waits the whole `coolingOff` on every Mac.
    static func dates(signedAt: Date, firstSeen: Date, now: Date) -> DateVerdict {
        if signedAt.timeIntervalSince(now) > clockSkew { return .refuse("its signature is dated later than this Mac’s clock") }
        let age = now.timeIntervalSince(signedAt)
        if age > maxAge { return .refuse("it was signed more than \(Int(maxAge / 86400)) days ago") }
        let until = max(signedAt, firstSeen).addingTimeInterval(coolingOff)
        if now < until { return .waitUntil(until) }
        return .go
    }

    /// When the cooling-off of the release `tag` ends, from what this Sill remembers (every sighting of that
    /// tag: the latest end); nil when it never read that release's manifest.
    static func waitUntil(_ m: Memory, tag: String) -> Date? {
        m.seen.filter { $0.tag == tag }.map { max($0.signed, $0.first).addingTimeInterval(coolingOff) }.max()
    }

    /// The first time this Sill read that release's verified manifest, if it has.
    static func firstSeen(_ m: Memory, tag: String, sha256: String) -> Date? {
        m.seen.first { $0.tag == tag && $0.sha256 == sha256 }?.first
    }

    /// Whether the moment to install has come: no device connected now, none since `quietSince` (when the
    /// last one left, or when the wait began) for `quietFor`, no pairing window open.
    static func quiet(devices: Int, quietSince: Date, pairing: Bool, now: Date) -> Bool {
        devices == 0 && !pairing && now.timeIntervalSince(quietSince) >= quietFor
    }

    /// Whether a checked copy has waited too long for a quiet moment.
    static func waitedTooLong(since: Date, now: Date) -> Bool {
        now.timeIntervalSince(since) >= maxWait
    }

    // MARK: Memory

    /// This Sill read the verified manifest of the release `tag` (its zip `sha256`) now: kept unless it was
    /// read before (the first sight never moves), so the cooling-off counts from the first time.
    static func sighted(_ m: Memory, tag: String, sha256: String, signedAt: Date, now: Date) -> Memory {
        guard firstSeen(m, tag: tag, sha256: sha256) == nil else { return m }
        var n = m
        n.seen.append(Memory.Sighting(tag: tag, sha256: sha256, first: now, signed: signedAt))
        return n
    }

    /// A release's app passed both checks (the second security pass's A2: never on a manifest alone, so one
    /// signed manifest for a made-up "v99" can't stop every later release installing by itself): the highest
    /// such version is kept.
    static func signedRelease(_ m: Memory, _ version: SillVersion) -> Memory {
        var n = m
        if let h = m.highestSigned.flatMap(UpdateInstallPolicy.strictVersion), h >= version { return n }
        n.highestSigned = version.description
        return n
    }

    /// An automatic attempt at `version` began.
    static func began(_ m: Memory, _ version: SillVersion, now: Date) -> Memory {
        var n = m
        let key = version.description
        n.attempts[key] = Memory.Attempt(count: (m.attempts[key]?.count ?? 0) + 1, last: now, failure: nil)
        return n
    }

    /// The attempt at `version` failed (`why`, for the log). It stays counted.
    static func failed(_ m: Memory, _ version: SillVersion, why: String) -> Memory {
        var n = m
        let key = version.description
        if var a = n.attempts[key] { a.failure = why; n.attempts[key] = a }
        return n
    }

    /// The attempt at `version` ended in a wait, not a failure (the cooling-off, no quiet moment within
    /// `maxWait`): it isn't counted.
    static func forgive(_ m: Memory, _ version: SillVersion) -> Memory {
        var n = m
        let key = version.description
        guard var a = n.attempts[key] else { return n }
        a.count -= 1
        n.attempts[key] = a.count <= 0 ? nil : a
        return n
    }

    /// A signed stop named `tag`.
    static func stopped(_ m: Memory, _ tag: String) -> Memory {
        var n = m
        if !n.stopped.contains(tag) { n.stopped.append(tag) }
        return n
    }

    /// Sill updated itself to `version`: attempts at it and older are forgotten.
    static func updated(_ m: Memory, to version: SillVersion, at: Date) -> Memory {
        var n = m
        n.updatedTo = version.description
        n.updatedAt = at
        n.attempts = n.attempts.filter { UpdateInstallPolicy.strictVersion($0.key).map { $0 > version } ?? false }
        return n
    }

    /// What is written, kept small (A3): only well-formed entries; attempts, sightings and stops only for a
    /// version newer than `running` (an older one is never offered as an update again), at most
    /// `maxRemembered` attempts and sightings (the newest) and `maxStops` stops (the highest versions). Applied
    /// to every write, so no sequence of offers grows the item.
    static func bounded(_ m: Memory, running: SillVersion?) -> Memory {
        var n = m
        func newer(_ text: String) -> Bool {
            guard let v = UpdateInstallPolicy.strictVersion(text) else { return false }
            return running.map { v > $0 } ?? true
        }
        func newerTag(_ tag: String) -> Bool {
            guard let v = UpdateInstallPolicy.strictTag(tag) else { return false }
            return running.map { v > $0 } ?? true
        }
        n.attempts = Dictionary(uniqueKeysWithValues: m.attempts
            .filter { newer($0.key) }
            .sorted { $0.value.last > $1.value.last }
            .prefix(maxRemembered)
            .map { ($0.key, Memory.Attempt(count: $0.value.count, last: $0.value.last, failure: $0.value.failure.map { String($0.prefix(200)) })) })
        n.seen = Array(m.seen.filter { newerTag($0.tag) && UpdateManifest.isHex($0.sha256, count: 64) }
            .sorted { $0.first > $1.first }
            .prefix(maxRemembered))
        var stops: [String] = []
        for tag in m.stopped where newerTag(tag) && !stops.contains(tag) { stops.append(tag) }
        n.stopped = Array(stops.sorted { UpdateInstallPolicy.strictTag($0)! > UpdateInstallPolicy.strictTag($1)! }.prefix(maxStops))
        if let h = m.highestSigned, UpdateInstallPolicy.strictVersion(h) == nil { n.highestSigned = nil }
        if let u = m.updatedTo, UpdateInstallPolicy.strictVersion(u) == nil { n.updatedTo = nil; n.updatedAt = nil }
        return n
    }

    /// What Sill's keychain item says (AutoUpdateStore's read, decided here so the check can run it): no item;
    /// what it remembers; or unreadable: too large, not what Sill writes, or the keychain's error. Unreadable is
    /// never "nothing remembered" (A3): the switch then reads off, and Sill writes the item again only when the
    /// person turns the switch on.
    enum StoreRead: Equatable, Sendable {
        case noItem
        case memory(Memory)
        case unreadable(String)
    }

    /// `status` is SecItemCopyMatching's (0 success, -25300 not found), `data` the item's bytes.
    static func storeRead(status: Int32, data: Data?, error: String) -> StoreRead {
        if status == -25300 { return .noItem }
        guard status == 0, let data else { return .unreadable(error) }
        guard data.count <= maxItemBytes else { return .unreadable("the item is \(data.count) bytes, larger than Sill ever writes") }
        guard let memory = try? JSONDecoder().decode(Memory.self, from: data) else { return .unreadable("the item isn’t what Sill writes") }
        return .memory(memory)
    }

    /// The switch, turned on or off by the person (Settings › General: the only place that can).
    static func switched(_ m: Memory, on: Bool) -> Memory {
        var n = m
        n.on = on
        return n
    }

    // MARK: Words

    /// The switch in Settings › General.
    struct Switch: Equatable, Sendable {
        /// Shown only in a build with Update Now (an update key, Sill.app).
        var shown = false
        var enabled = false
        /// Why it can't be turned on here, or won't act, under it.
        var note: String?
    }

    /// `canKeep`: Sill's keychain item can hold the switch (a release Sill.app with its keychain group).
    /// `unreadable`: the item is there but couldn't be read (A3): the switch reads off until turned on again.
    static func switchState(available: Bool, canKeep: Bool, checkOn: Bool, refusal: UpdateInstallPolicy.Refusal?, on: Bool,
                            unreadable: Bool = false) -> Switch {
        var s = Switch()
        guard available else { return s }
        s.shown = true
        if !canKeep {
            s.note = canKeepNote
        } else if !checkOn {
            s.note = "Works while Check for updates automatically is on."
        } else {
            s.note = refusal.map(UpdateInstallPolicy.words) ?? (unreadable && !on ? unreadableNote : nil)
            s.enabled = true
        }
        // On can always be turned off.
        if on { s.enabled = true }
        return s
    }

    /// Why a copy without Sill's keychain group can't keep the switch (the second pass's N9: a notarized build
    /// can lack the group too).
    static let canKeepNote = "This copy of Sill can’t keep this setting: only Sill’s releases from GitHub can."
    /// Under the switch while Sill's keychain item couldn't be read (A3).
    static let unreadableNote = "Sill couldn’t read what it keeps for this setting, so it is off. Turning it on starts it afresh."

    /// The pane's automatic part for this moment.
    static func pane(_ m: Memory, offered: SillVersion?, offeredTag: String?, running: SillVersion?, waitUntil: Date?,
                     now: Date) -> UpdateInstallPolicy.AutomaticPane {
        var a = UpdateInstallPolicy.AutomaticPane()
        a.on = m.on
        a.quietMinutes = quietMinutes
        a.updated = updatedLine(m, running: running, now: now)
        if let offered {
            a.afterFailure = afterFailure(m, version: offered)
            a.offerNote = offerNote(m, offered: offered, offeredTag: offeredTag, waitUntil: waitUntil, now: now)
        }
        return a
    }

    /// While a release is offered and the switch is on: when Sill installs it by itself, or why it won't.
    static func offerNote(_ m: Memory, offered: SillVersion, offeredTag: String?, waitUntil: Date?, now: Date) -> String {
        if let offeredTag, m.stopped.contains(offeredTag) {
            return "A stop signed with Sill’s update key names Sill \(offered), so Sill won’t install it."
        }
        if let highest = m.highestSigned.flatMap(UpdateInstallPolicy.strictVersion), offered < highest {
            return "Sill won’t install \(offered) by itself: Sill \(highest) was out before it. Update Now still can."
        }
        if let a = m.attempts[offered.description], a.count >= maxAttempts {
            return "Sill won’t install \(offered) by itself again; Update Now still can."
        }
        if let waitUntil {
            if now < waitUntil {
                return "Sill installs it by itself \(when(waitUntil, now: now, future: true)) or later, once no device has been connected for \(quietMinutes) minutes."
            }
        } else if coolingOff > 0 {
            // Not read yet: the wait starts when this Sill first reads its signed release (A1).
            return "Sill installs it by itself \(coolingOffWords), once no device has been connected for \(quietMinutes) minutes."
        }
        return "Sill installs it by itself once no device has been connected for \(quietMinutes) minutes."
    }

    /// The pane's note after Sill updated itself (this launch runs that version), for `updatedShown`.
    static func updatedLine(_ m: Memory, running: SillVersion?, now: Date) -> String? {
        guard let to = m.updatedTo, let at = m.updatedAt, let running, running.description == to,
              now.timeIntervalSince(at) < updatedShown, at.timeIntervalSince(now) < clockSkew else { return nil }
        return "Sill updated itself to \(to) \(when(at, now: now))."
    }

    /// What follows a failed automatic attempt's line.
    static func afterFailure(_ m: Memory, version: SillVersion) -> String {
        if let a = m.attempts[version.description], a.count >= maxAttempts {
            return "Sill won’t install \(version) by itself again; Update Now still can."
        }
        return "Sill tries again after its next daily check."
    }

    /// "today at 03:12", "yesterday at 21:40", "on 12 Nov 2026 at 03:12" (this Mac's zone and format);
    /// `future`: "tomorrow at …" for the day after.
    static func when(_ date: Date, now: Date, future: Bool = false) -> String {
        let calendar = Calendar.current
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let other = calendar.date(byAdding: .day, value: future ? 1 : -1, to: now), calendar.isDate(date, inSameDayAs: other) {
            return "\(future ? "tomorrow" : "yesterday") at \(time)"
        }
        let day = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        return "on \(day) at \(time)"
    }
}
