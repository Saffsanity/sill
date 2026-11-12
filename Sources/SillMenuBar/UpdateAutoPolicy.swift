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

    /// How long a release must have been signed (its manifest's own date) before Sill installs it by
    /// itself: the time Noah has to see a release he didn't make and pull it. Update Now isn't held. Zero
    /// turns the wait off (plan §10, Q9).
    static let coolingOff: TimeInterval = 48 * 3600
    /// The oldest signature Sill installs by itself: an old release offered as the latest again (a
    /// rollback through GitHub, review 3's F7) is left to Update Now and the person's eyes.
    static let maxAge: TimeInterval = 120 * 24 * 3600
    /// A signature dated this far ahead of this Mac's clock is refused (its clock, or the signer's, is wrong).
    static let clockSkew: TimeInterval = 10 * 60
    /// How long no device must have been connected before Sill installs: longer than a reconnect, a short
    /// trip to the background or a cable pulled and plugged in again, short enough to fit a night.
    static let quietFor: TimeInterval = 10 * 60
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

    /// The waits in Settings' words.
    static var quietMinutes: Int { Int((quietFor / 60).rounded()) }
    static var coolingOffWords: String {
        guard coolingOff > 0 else { return "once it is out" }
        let hours = Int((coolingOff / 3600).rounded())
        guard hours % 24 == 0 else { return "\(hours) hours after it is signed" }
        return hours == 24 ? "a day after it is signed" : "\(hours / 24) days after it is signed"
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
        /// The highest version the daily check has offered: a lower one offered later is a rollback,
        /// never installed by itself.
        var highestOffered: String?
        /// Releases a signed stop named (their tags): never installed, also after the stop is gone.
        var stopped: [String] = []
        /// The last update Sill installed by itself, and when, to say so afterwards.
        var updatedTo: String?
        var updatedAt: Date?

        struct Attempt: Codable, Equatable, Sendable {
            var count: Int
            var last: Date
            /// The last failure's words for the log (nil while one runs).
            var failure: String?
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
    /// end of a cooling-off this launch already learned for this version.
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
        if let highest = m.highestOffered.flatMap(UpdateInstallPolicy.strictVersion), offered < highest {
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

    /// The manifest's own date against now: install, wait until a moment, or never by itself.
    static func dates(signedAt: Date, now: Date) -> DateVerdict {
        if signedAt.timeIntervalSince(now) > clockSkew { return .refuse("its signature is dated later than this Mac’s clock") }
        let age = now.timeIntervalSince(signedAt)
        if age > maxAge { return .refuse("it was signed more than \(Int(maxAge / 86400)) days ago") }
        if age < coolingOff { return .waitUntil(signedAt.addingTimeInterval(coolingOff)) }
        return .go
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

    /// The check offered `offered`: the highest offer is kept.
    static func offered(_ m: Memory, _ offered: SillVersion) -> Memory {
        var n = m
        if let h = m.highestOffered.flatMap(UpdateInstallPolicy.strictVersion), h >= offered { return n }
        n.highestOffered = offered.description
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
    static func switchState(available: Bool, canKeep: Bool, checkOn: Bool, refusal: UpdateInstallPolicy.Refusal?, on: Bool) -> Switch {
        var s = Switch()
        guard available else { return s }
        s.shown = true
        if !canKeep {
            s.note = "This copy of Sill can’t keep this setting: it isn’t a notarized release."
        } else if !checkOn {
            s.note = "Works while Check for updates automatically is on."
        } else {
            s.note = refusal.map(UpdateInstallPolicy.words)
            s.enabled = true
        }
        // On can always be turned off.
        if on { s.enabled = true }
        return s
    }

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
        if let highest = m.highestOffered.flatMap(UpdateInstallPolicy.strictVersion), offered < highest {
            return "Sill won’t install \(offered) by itself: \(highest) was offered before it. Update Now still can."
        }
        if let a = m.attempts[offered.description], a.count >= maxAttempts {
            return "Sill won’t install \(offered) by itself again; Update Now still can."
        }
        if let waitUntil, now < waitUntil {
            return "Sill installs it by itself \(when(waitUntil, now: now, future: true)) or later, once no device has been connected for \(quietMinutes) minutes."
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
