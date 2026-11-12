import Foundation
import StreamProtocol

/// Update Now, the one-click update of Sill for Mac, as pure rules (docs/one-click-update-plan.md §4):
/// what a downloaded Sill must be (`Trust`), where it may come from (`Endpoints`), when Update Now is
/// offered and every refusal with its words (`Situation`, `Refusal`), what GitHub's release must say
/// (`release`), the judgement of a downloaded bundle (`verdict`), the state machine from the click to
/// the relaunch (`next`), and every word Settings, the menu and the log say about it.
///
/// UpdateInstaller does the work (download, unpack, check, swap) and AppUpdater the app's part (the
/// facts, the relaunch); this file decides. Foundation and StreamProtocol's SillVersion only, so it is
/// checked on its own with swiftc (Tests/checks/update-install, with mutants).
///
/// Sill.app passes exactly two values into the mechanism: `Trust.release` and `Endpoints.github`.
/// Nothing in the app makes another one, and no updater file reads a default, the environment or the
/// arguments (the check reads the app's sources to make sure). Only Tests/update-harness, which is no
/// part of any product, builds test values.
enum UpdateInstallPolicy {

    // MARK: Trust

    /// What a downloaded Sill must be.
    struct Trust: Equatable, Sendable {
        /// The code requirement the bundle must satisfy, without `notarized` (Security's language).
        let signer: String
        /// `notarized` must hold as well.
        let notarized: Bool
        /// The top folder of the archive and the bundle's name ("Sill.app"), and its executable.
        let bundleName: String
        let executable: String
        /// CFBundleIdentifier, and the signing identifier.
        let identifier: String
        /// The signing team; nil only for the harness's ad hoc bundles.
        let teamID: String?
        /// A stapled notarization ticket must be in the bundle.
        let stapledTicket: Bool
        /// The hardened runtime flag must be set.
        let hardenedRuntime: Bool
        /// The bundle must also satisfy the running app's own designated requirement, which the Screen
        /// Recording and Accessibility grants are kept with.
        let runningRequirement: Bool
        /// Entitlements the bundle must carry (the data-protection keychain's access group).
        let entitlements: [RequiredEntitlement]
        /// Ed25519 public keys (base64): the release's manifest must be signed with one. Empty: Update
        /// Now is not offered at all.
        let updateKeys: [String]
    }

    enum RequiredEntitlement: Equatable, Sendable {
        case string(key: String, value: String)
        case arrayContaining(key: String, value: String)
    }

    /// Sill's own designated requirement as v0.6.1 carries it (`codesign -d -r-`), in the order
    /// Security's language reads best: Apple's anchor, the Developer ID intermediate
    /// (1.2.840.113635.100.6.2.6), a Developer ID Application leaf (1.2.840.113635.100.6.1.13), the
    /// team, the identifier.
    static let pinnedRequirement = "anchor apple generic and identifier \"me.saffer.sill.mac\" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"9B2KKVM937\""

    // MARK: Endpoints

    /// Where a release may come from.
    struct Endpoints: Equatable, Sendable {
        /// The latest published release (the check's feed).
        let latestRelease: URL
        /// Origins ("https://host", or with a port) the release request may be redirected to.
        let apiOrigins: [String]
        /// An asset's URL is this, the tag, "/" and its name.
        let downloadPrefix: String
        /// The app's zip and its signed manifest.
        let assetName: String
        let manifestName: String
        /// A stop for the release (UpdateManifest.Stop), read when the release lists it; nil reads none
        /// (the switch for the whole mechanism: plan §10, Q10).
        var stopName: String? = nil
        /// Origins a download may be redirected to, and the path it must start with there.
        let redirectOrigins: [String]
        let redirectPathPrefix: String
        let maxRedirects: Int
        /// The zip's size must be within these.
        let minAssetBytes: Int64
        let maxAssetBytes: Int64
    }

    /// A release's body is read up to this (as the check's).
    static let maxReleaseBytes = 1 << 20
    /// Free space before the download: four times the zip, and this.
    static let spaceMargin: Int64 = 64 << 20
    /// How long the old Sill waits for the new one to finish launching, and the new one for the old to
    /// quit.
    static let launchWait: TimeInterval = 30
    /// How long the new Sill runs with its host up before it tells the watcher it works (the watcher then
    /// leaves it, and the copy it replaced goes): longer than "the host started" (review 3, point 6).
    static let provedAfter: TimeInterval = 30
    /// How long the watcher waits for that word before it puts the old copy back: the old Sill's quit, the
    /// new one's wait for it, its host's start and `provedAfter`, with room to spare.
    static let watchWait: TimeInterval = 150

    /// "scheme://host" or "scheme://host:port", lowercased; nil for a URL with a user or password, or
    /// without a host.
    static func origin(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// An asset's URL, built by Sill from the tag (never taken from GitHub's answer, which must equal
    /// it).
    static func assetURL(tag: String, name: String, endpoints: Endpoints) -> URL? {
        guard strictTag(tag) != nil, name == endpoints.assetName || name == endpoints.manifestName || name == endpoints.stopName else { return nil }
        return URL(string: endpoints.downloadPrefix + tag + "/" + name)
    }

    /// Whether a download may follow a redirect to `url`.
    static func downloadRedirectAllowed(_ url: URL, endpoints: Endpoints) -> Bool {
        guard let o = origin(url), endpoints.redirectOrigins.contains(o) else { return false }
        return url.path.hasPrefix(endpoints.redirectPathPrefix)
    }

    /// Whether the release request may follow a redirect to `url`.
    static func apiRedirectAllowed(_ url: URL, endpoints: Endpoints) -> Bool {
        guard let o = origin(url) else { return false }
        return endpoints.apiOrigins.contains(o)
    }

    // MARK: Versions

    /// The version rules and the architectures are UpdateManifest's (the signer compiles that file alone,
    /// with SillVersion); these name them where the rest of Update Now reads them.
    static func strictVersion(_ text: String) -> SillVersion? { UpdateManifest.strictVersion(text) }
    static func strictTag(_ tag: String) -> SillVersion? { UpdateManifest.strictTag(tag) }

    // MARK: Where Sill runs, and the refusals

    /// What Update Now's availability is decided from (AppUpdater gathers it; UpdateInstaller's
    /// `situation` reads the file system and the processes).
    struct Situation: Equatable, Sendable {
        /// The running code is a notarized Developer ID Sill (it satisfies the pinned requirement and
        /// `notarized`), in a .app bundle.
        var runningIsRelease: Bool
        /// A test feed (-SillUpdateFeed) or a test version (-SillUpdateVersion) is in use.
        var testFeed: Bool
        var bundlePath: String
        var bundleIsLink: Bool
        /// The path holds /AppTranslocation/.
        var translocated: Bool
        var volumeName: String
        var readOnlyVolume: Bool
        var networkVolume: Bool
        var diskImage: Bool
        var folderWritable: Bool
        var bundleWritable: Bool
        var ownedByUser: Bool
        /// The account that owns the bundle, by name, when it is not this one (for the refusal's words).
        var ownerName: String
        /// The copy at the path is the code that is running (its cdhash for this Mac's architecture).
        var runningIsInstalled: Bool
        /// Other accounts' names whose processes run from this bundle.
        var otherAccounts: [String]
        /// This account's other processes running from this bundle.
        var otherInstances: Int
        var freeBytes: Int64?
        var neededBytes: Int64
    }

    enum Refusal: Equatable, Sendable {
        case notRelease
        case testFeed
        case translocated
        case diskImage
        case readOnlyVolume(String)
        case networkVolume(String)
        case link(String)
        case notWritable(String)
        /// Sill.app belongs to another account (its name): the swap would hand that account's copy to
        /// this one.
        case otherOwner(String)
        case changedSinceStart(String)
        case otherAccount(String)
        case otherInstance
        case lowSpace(volume: String, neededMB: Int)
    }

    /// The first reason Update Now cannot run here, in the plan's order (§4.1), or nil.
    static func refusal(_ s: Situation) -> Refusal? {
        if !s.runningIsRelease { return .notRelease }
        if s.testFeed { return .testFeed }
        if s.translocated { return .translocated }
        if s.diskImage { return .diskImage }
        if s.readOnlyVolume { return .readOnlyVolume(s.volumeName) }
        if s.networkVolume { return .networkVolume(s.volumeName) }
        if s.bundleIsLink { return .link(s.bundlePath) }
        if !s.folderWritable || !s.bundleWritable {
            return .notWritable((s.bundlePath as NSString).deletingLastPathComponent)
        }
        if !s.ownedByUser { return .otherOwner(s.ownerName) }
        if !s.runningIsInstalled { return .changedSinceStart(s.bundlePath) }
        if let other = s.otherAccounts.first { return .otherAccount(other) }
        if s.otherInstances > 0 { return .otherInstance }
        if let free = s.freeBytes, free < s.neededBytes {
            return .lowSpace(volume: s.volumeName, neededMB: mebibytesRoundedUp(s.neededBytes))
        }
        return nil
    }

    /// Whole MiB, rounded up, for any count (Int64.max included: no addition that could overflow).
    static func mebibytesRoundedUp(_ bytes: Int64) -> Int {
        Int(bytes >> 20) + (bytes & 0xF_FFFF != 0 ? 1 : 0)
    }

    /// What the staging volume needs before the download: four times the zip, and the margin.
    static func neededBytes(assetBytes: Int64) -> Int64 { assetBytes * 4 + spaceMargin }

    /// The refusal's words, under the offer in Settings › General.
    static func words(_ r: Refusal) -> String {
        switch r {
        case .notRelease: return "This copy of Sill isn’t a notarized release, so it can’t update itself."
        case .testFeed: return "This run checks a test feed, so it doesn’t update itself."
        case .translocated:
            return "macOS is running Sill from a temporary copy. Move Sill to your Applications folder, open it from there, then update."
        case .diskImage:
            return "Sill is running from a disk image. Copy it to your Applications folder, open it from there, then update."
        case .readOnlyVolume(let v): return "Sill is on a disk this Mac can’t change (\(v))."
        case .networkVolume(let v): return "Sill is on a network disk (\(v)), so it doesn’t update itself there."
        case .link(let path): return "Sill runs through a link (\(path)), so it can’t replace itself there."
        case .notWritable(let folder): return "Sill is in a folder this account can’t change (\(folder))."
        case .otherOwner(let name): return "Sill belongs to another account on this Mac (\(name)). Update it from that account."
        case .changedSinceStart(let path): return "Sill at \(path) changed since it started. Quit Sill and open it again."
        case .otherAccount(let name):
            return "Sill is open in another account on this Mac (\(name)). Quit it there first, then update."
        case .otherInstance: return "Another copy of Sill is running. Quit it first, then update."
        case .lowSpace(let v, let mb): return "Not enough free space on \(v): about \(mb) MB are needed."
        }
    }

    // MARK: The release

    /// One asset of the release, as Sill will fetch it.
    struct Asset: Equatable, Sendable {
        let name: String
        /// The URL Sill built (GitHub's matched it).
        let url: URL
        let size: Int64
        /// GitHub's own SHA-256 of it (`digest`), when GitHub sent one: compared with the manifest's.
        let digest: String?
    }

    /// The release Update Now installs.
    struct Release: Equatable, Sendable {
        let tag: String
        let version: SillVersion
        let zip: Asset
        let manifest: Asset
        /// A stop listed beside them (read before anything is downloaded).
        var stop: Asset? = nil
    }

    /// GitHub's latest release (a 200's body) as the one to install, or why not: it must be the
    /// offered tag, strict, published, newer than `running`, with exactly one zip and one manifest at
    /// the URLs Sill builds, uploaded, of possible sizes.
    static func releaseToInstall(_ body: Data, offeredTag: String, running: SillVersion, endpoints: Endpoints) -> Result<Release, Failure> {
        guard body.count <= maxReleaseBytes,
              let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .failure(.releaseUnreadable("not a JSON object"))
        }
        guard let tag = object["tag_name"] as? String else { return .failure(.releaseUnreadable("no tag_name")) }
        guard tag == offeredTag else { return .failure(.releaseChanged(tag: String(tag.prefix(40)))) }
        guard let version = strictTag(tag) else { return .failure(.releaseUnreadable("the tag is not v and a version")) }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true {
            return .failure(.releaseUnreadable("a draft or a prerelease"))
        }
        guard version > running else { return .failure(.releaseNotNewer) }
        guard let assets = object["assets"] as? [[String: Any]] else { return .failure(.releaseUnreadable("no assets")) }
        func asset(_ name: String, sizes: ClosedRange<Int64>) -> Result<Asset?, Failure> {
            let matches = assets.filter { $0["name"] as? String == name }
            guard let a = matches.first else { return .success(nil) }
            guard matches.count == 1 else { return .failure(.releaseUnreadable("two assets named \(name)")) }
            guard a["state"] as? String == "uploaded" else { return .failure(.releaseUnreadable("\(name) is not uploaded")) }
            guard let size = (a["size"] as? NSNumber)?.int64Value, sizes.contains(size) else {
                return .failure(.releaseUnreadable("\(name)’s size"))
            }
            guard let url = assetURL(tag: tag, name: name, endpoints: endpoints),
                  a["browser_download_url"] as? String == url.absoluteString else {
                return .failure(.releaseUnreadable("\(name)’s URL"))
            }
            var digest: String?
            if let d = a["digest"] {
                guard let text = d as? String, text.hasPrefix("sha256:"),
                      UpdateManifest.isHex(String(text.dropFirst(7)).lowercased(), count: 64) else {
                    return .failure(.releaseUnreadable("\(name)’s digest"))
                }
                digest = String(text.dropFirst(7)).lowercased()
            }
            return .success(Asset(name: name, url: url, size: size, digest: digest))
        }
        var stop: Asset?
        if let name = endpoints.stopName {
            switch asset(name, sizes: 1...Int64(UpdateManifest.maxBytes)) {
            case .failure(let f): return .failure(f)
            case .success(let a): stop = a
            }
        }
        switch (asset(endpoints.assetName, sizes: endpoints.minAssetBytes...endpoints.maxAssetBytes),
                asset(endpoints.manifestName, sizes: 1...Int64(UpdateManifest.maxBytes))) {
        case (.failure(let f), _), (_, .failure(let f)):
            return .failure(f)
        case (.success(.none), _):
            return .failure(.releaseUnreadable("no \(endpoints.assetName)"))
        case (.success(_), .success(.none)):
            return .failure(.notSigned)
        case (.success(let zip?), .success(let manifest?)):
            return .success(Release(tag: tag, version: version, zip: zip, manifest: manifest, stop: stop))
        }
    }

    /// The verified manifest against the release: the same tag, the zip's name and size, GitHub's
    /// digest when it sent one.
    static func manifestMatches(_ m: UpdateManifest, release r: Release, endpoints: Endpoints) -> Failure? {
        guard m.tag == r.tag, m.version == r.version else { return .manifestMismatch("tag") }
        guard m.asset == endpoints.assetName else { return .manifestMismatch("asset") }
        guard m.size == r.zip.size else { return .manifestMismatch("size") }
        if let digest = r.zip.digest, digest != m.sha256 { return .manifestMismatch("sha256") }
        return nil
    }

    // MARK: The bundle

    typealias Architecture = UpdateManifest.Architecture

    enum EntitlementValue: Equatable, Sendable {
        case string(String)
        case strings([String])
        case bool(Bool)
        case other
    }

    /// What UpdateInstaller reads from a bundle with Security.framework and lstat.
    struct BundleFacts: Equatable, Sendable {
        /// Nil when the bundle folder, Contents/Info.plist and Contents/MacOS/‹executable› are a folder,
        /// a file and an executable file, none a link; else what is wrong.
        var tree: String?
        /// 0 when the signature is valid under UpdateInstaller's strict flags.
        var signatureStatus: Int32 = -1
        var signer = false
        var notarized = false
        var stapledTicket = false
        /// Nil when the trust does not ask.
        var runningRequirement: Bool?
        var identifier: String?
        var teamID: String?
        var flags: UInt32 = 0
        var entitlements: [String: EntitlementValue] = [:]
        /// The signed Info.plist's string values.
        var plist: [String: String] = [:]
        /// Each architecture's slice → its cdhash (40 lowercase hex digits).
        var cdhashes: [String: String] = [:]
    }

    /// A bundle that passed: its version, build and the cdhash of the slice this Mac runs.
    struct Checked: Equatable, Sendable {
        let version: SillVersion
        let build: String
        let cdhashes: [String: String]
    }

    enum BundleProblem: Error, Equatable, Sendable {
        case notABundle(String)
        case invalidSignature(Int32)
        case wrongSigner
        case notNotarized
        case noStapledTicket
        case wouldLosePermissions
        case wrongIdentity
        case noHardenedRuntime
        case entitlement(String)
        case debuggable
        case info(String)
        case notNewer(String)
        case notManifest(String)
        case needsNewerMacOS(String)
        case noSliceForThisMac
        case codeChanged
    }

    /// The judgement of a bundle's facts, in the plan's order (§4.5).
    static func verdict(_ f: BundleFacts, trust: Trust, manifest: UpdateManifest, running: SillVersion,
                        arch: Architecture, macOS: OperatingSystemVersion) -> Result<Checked, BundleProblem> {
        if let tree = f.tree { return .failure(.notABundle(tree)) }
        guard f.signatureStatus == 0 else { return .failure(.invalidSignature(f.signatureStatus)) }
        guard f.signer else { return .failure(.wrongSigner) }
        if trust.notarized, !f.notarized { return .failure(.notNotarized) }
        if trust.stapledTicket, !f.stapledTicket { return .failure(.noStapledTicket) }
        if trust.runningRequirement, f.runningRequirement != true { return .failure(.wouldLosePermissions) }
        guard f.identifier == trust.identifier, trust.teamID == nil || f.teamID == trust.teamID else { return .failure(.wrongIdentity) }
        if trust.hardenedRuntime, f.flags & 0x10000 == 0 { return .failure(.noHardenedRuntime) }
        for required in trust.entitlements {
            switch required {
            case .string(let key, let value):
                guard f.entitlements[key] == .string(value) else { return .failure(.entitlement(key)) }
            case .arrayContaining(let key, let value):
                guard case .strings(let values)? = f.entitlements[key], values.contains(value) else { return .failure(.entitlement(key)) }
            }
        }
        if f.entitlements["com.apple.security.get-task-allow"] == .bool(true) { return .failure(.debuggable) }
        guard f.plist["CFBundleIdentifier"] == trust.identifier else { return .failure(.info("CFBundleIdentifier")) }
        guard f.plist["CFBundleExecutable"] == trust.executable else { return .failure(.info("CFBundleExecutable")) }
        guard let versionText = f.plist["CFBundleShortVersionString"], let version = strictVersion(versionText) else {
            return .failure(.info("CFBundleShortVersionString"))
        }
        guard let build = f.plist["CFBundleVersion"], UpdateManifest.isDigits(build, 1...9) else { return .failure(.info("CFBundleVersion")) }
        guard version > running else { return .failure(.notNewer(versionText)) }
        guard version == manifest.version else { return .failure(.notManifest("version")) }
        guard build == manifest.build else { return .failure(.notManifest("build")) }
        if let minimum = f.plist["LSMinimumSystemVersion"] {
            guard let needed = strictVersion(minimum) else { return .failure(.info("LSMinimumSystemVersion")) }
            let have = SillVersion(components: [macOS.majorVersion, macOS.minorVersion, macOS.patchVersion])
            guard needed <= have else { return .failure(.needsNewerMacOS(minimum)) }
        }
        guard f.cdhashes[arch.rawValue] != nil else { return .failure(.noSliceForThisMac) }
        // Every slice is the one Noah signed for: the manifest names each architecture's code.
        guard f.cdhashes == manifest.cdhashes else { return .failure(.notManifest("code")) }
        return .success(Checked(version: version, build: build, cdhashes: f.cdhashes))
    }

    /// The bundle's words: what Settings says after "Couldn’t update: ".
    static func words(_ p: BundleProblem) -> String {
        switch p {
        case .notABundle: return "the download isn’t a Sill app"
        case .invalidSignature: return "the downloaded app’s code signature isn’t valid"
        case .wrongSigner: return "the downloaded app isn’t signed with the Developer ID of Sill’s developer"
        case .notNotarized, .noStapledTicket: return "Apple hasn’t notarized the downloaded app"
        case .wouldLosePermissions: return "the downloaded app wouldn’t keep Sill’s permissions"
        case .wrongIdentity: return "the downloaded app isn’t Sill"
        case .noHardenedRuntime, .debuggable: return "the downloaded app isn’t built as Sill’s releases are"
        case .entitlement: return "the downloaded app wouldn’t keep Sill’s paired devices"
        case .info: return "the downloaded app’s information isn’t Sill’s"
        case .notNewer(let v): return "the downloaded app is version \(v), not newer than this one"
        case .notManifest: return "the downloaded app isn’t the one signed with Sill’s update key"
        case .needsNewerMacOS(let v): return "the new version needs macOS \(v) or later"
        case .noSliceForThisMac: return "the new version doesn’t run on this Mac"
        case .codeChanged: return "the app changed while Sill was installing it"
        }
    }

    // MARK: Failures

    enum Failure: Error, Equatable, Sendable {
        case unavailable(Refusal)
        /// GitHub's latest release is no longer the one offered (its tag).
        case releaseChanged(tag: String)
        case releaseNotNewer
        case releaseUnreadable(String)
        /// The release has no signed manifest: Noah has not signed it for Update Now (yet).
        case notSigned
        case noConnection(String)
        case github(Int)
        case manifest(UpdateManifest.Problem)
        /// The verified manifest does not describe this release (which field).
        case manifestMismatch(String)
        /// A redirect off the allow-list (where to), or too many.
        case redirectRefused(String)
        case download(String)
        case sizeMismatch
        case tooLarge
        case hashMismatch
        case lowSpace(neededMB: Int)
        case disk(String)
        case archive(UpdateArchive.Problem)
        case bundle(BundleProblem)
        /// Right before the swap, the copy at the path was no longer the running one.
        case changedSinceStart
        case swapFailed(String)
        /// The check at the final path failed, and the old copy was put back (or not).
        case checkAfterSwap(BundleProblem, putBack: Bool)
        /// The new copy didn't come up (why), and the old copy was put back (or not).
        case didNotStart(String, putBack: Bool)
        /// A stop signed with an update key names this release (its tag): never installed.
        case stopped(tag: String)
        /// The release lists a stop that doesn't check out with an update key: nothing is installed.
        case stopUnreadable(UpdateManifest.Problem)
        /// The automatic update leaves this release to Update Now (why: UpdateAutoPolicy's words).
        case notAutomatic(String)
        case cancelled

        /// Asked again right before the automatic update's swap: an answer that says nothing about the
        /// release (no connection, GitHub's error, a download that stopped) leaves the waiting copy waiting
        /// for the next look; any other ends the attempt.
        var transient: Bool {
            switch self {
            case .noConnection, .github, .redirectRefused, .download, .cancelled: return true
            default: return false
            }
        }

        /// Whether the staging folder may be deleted: not when it holds the old copy that could not be
        /// put back (the person's way back).
        var cleanUp: Bool {
            switch self {
            case .checkAfterSwap(_, let putBack), .didNotStart(_, let putBack): return putBack
            default: return true
            }
        }
    }

    /// Settings' orange line for a failure. `running` and `offered` as SillVersion shows them;
    /// `keptAt` where the old copy is when it could not be put back.
    static func line(_ f: Failure, running: SillVersion, offered: SillVersion, keptAt: String?) -> String {
        let unchanged = "Sill \(running) is unchanged."
        func couldNot(_ why: String) -> String { "Couldn’t update: \(why). \(unchanged)" }
        switch f {
        case .unavailable(let r): return words(r)
        case .releaseChanged: return "GitHub’s latest release is no longer Sill \(offered). Check again."
        case .releaseNotNewer: return couldNot("the release isn’t newer than this Sill")
        case .releaseUnreadable: return couldNot("GitHub’s answer wasn’t a release Sill can install")
        case .notSigned: return "Sill \(offered) isn’t signed with Sill’s update key yet, so it can’t be installed from here. Try again later, or open its release page."
        case .noConnection: return couldNot("this Mac couldn’t reach GitHub")
        case .github(let status): return couldNot("GitHub answered with an error (HTTP \(status))")
        case .manifest(let p): return couldNot(updateKeyWords(p))
        case .manifestMismatch: return couldNot("the release on GitHub isn’t the one signed with Sill’s update key")
        case .redirectRefused: return couldNot("GitHub sent the download somewhere Sill doesn’t download from")
        case .download: return couldNot("the download stopped")
        case .sizeMismatch, .tooLarge, .hashMismatch: return couldNot("the download didn’t match the release")
        case .lowSpace(let mb): return couldNot("there isn’t enough free space (about \(mb) MB are needed)")
        case .disk: return couldNot("Sill couldn’t write the update")
        case .archive: return couldNot("the download isn’t an archive Sill can install")
        case .bundle(let p): return couldNot(words(p))
        case .changedSinceStart: return "Sill changed on disk since it started. Quit Sill and open it again, then update."
        case .swapFailed: return couldNot("macOS didn’t let Sill replace itself")
        case .checkAfterSwap(let p, let putBack):
            return putBack ? couldNot(words(p)) : lost(running: running, keptAt: keptAt)
        case .didNotStart(_, let putBack):
            return putBack ? "Sill \(offered) didn’t start, so Sill \(running) is back." : lost(running: running, keptAt: keptAt)
        case .stopped: return "Sill’s developer stopped Sill \(offered) with a stop signed with Sill’s update key, so it isn’t installed. \(unchanged)"
        case .stopUnreadable: return couldNot("the release carries a stop that isn’t signed with Sill’s update key")
        case .notAutomatic(let why): return "Sill didn’t install \(offered) by itself: \(why). Update Now still can."
        case .cancelled: return "Update cancelled. \(unchanged)"
        }
    }

    /// Why the release's signature with Sill's update key didn't hold, in Settings' words: kept apart from
    /// Apple's signature and notarization (BundleProblem), which the download is checked against too.
    static func updateKeyWords(_ p: UpdateManifest.Problem) -> String {
        switch p {
        case .noKey, .badKey: return "this Sill has no usable update key"
        case .unknownKey: return "the release is signed with an update key this Sill doesn’t know"
        case .badSignature: return "the release’s signature with Sill’s update key isn’t valid"
        default: return "the release’s signature with Sill’s update key can’t be read"
        }
    }

    /// The old copy was not put back: where it is when it is kept whole, else (it was not the old copy,
    /// whole, any more) the download.
    private static func lost(running: SillVersion, keptAt: String?) -> String {
        guard let keptAt else {
            return "Sill couldn’t put \(running) back in place. Download Sill again from getsill.app and put it in your Applications folder."
        }
        return "Sill couldn’t put \(running) back in place. It is at \(keptAt): quit Sill and move it to your Applications folder soon, as macOS empties that folder after a few days."
    }

    /// The log's words for a failure, with what Settings leaves out.
    static func logText(_ f: Failure) -> String {
        switch f {
        case .unavailable(let r): return words(r)
        case .releaseChanged(let tag): return "the latest release is now \(tag)"
        case .releaseNotNewer: return "the latest release is not newer"
        case .releaseUnreadable(let why): return "the release is not one to install (\(why))"
        case .notSigned: return "the release has no signed manifest yet"
        case .noConnection(let why): return "no connection (\(why))"
        case .github(let status): return "HTTP \(status)"
        case .manifest(let p): return "the manifest: \(p.text)"
        case .manifestMismatch(let field): return "the manifest’s \(field) is not the release’s"
        case .redirectRefused(let to): return "a redirect refused (to \(to))"
        case .download(let why): return "the download failed (\(why))"
        case .sizeMismatch: return "the download is not the size the manifest says"
        case .tooLarge: return "the download is larger than the manifest says"
        case .hashMismatch: return "the download’s SHA-256 is not the manifest’s"
        case .lowSpace(let mb): return "not enough free space (\(mb) MB needed)"
        case .disk(let why): return "a write failed (\(why))"
        case .archive(let p): return "the archive: \(p.text)"
        case .bundle(let p): return "the bundle: \(p)"
        case .changedSinceStart: return "the copy at the path is no longer the running one"
        case .swapFailed(let why): return "the swap failed (\(why)); nothing changed"
        case .checkAfterSwap(let p, let putBack): return "the check at the final path failed (\(p)); \(putBack ? "put back" : "NOT put back")"
        case .didNotStart(let why, let putBack): return "the new copy didn’t start (\(why)); \(putBack ? "put back" : "NOT put back")"
        case .stopped(let tag): return "a stop signed with an update key names \(tag)"
        case .stopUnreadable(let p): return "the release’s stop: \(p.text)"
        case .notAutomatic(let why): return "not installed by itself: \(why)"
        case .cancelled: return "cancelled"
        }
    }

    // MARK: The state machine (§4.6)

    /// A connected device: `key` tells one connection from another (two unnamed iPads are two devices),
    /// `name` is what the words say.
    struct Device: Equatable, Sendable {
        let key: String
        let name: String
    }

    /// Who began the update under way: the person (Update Now), or Sill by itself (Automatically update
    /// Sill, UpdateAutoPolicy). One state machine for both: the same steps, checks and refusals.
    enum Mode: Equatable, Sendable {
        case manual, automatic
    }

    enum Phase: Equatable, Sendable {
        case idle
        /// The click came while devices were connected: asks first.
        case confirming(devices: [Device])
        case fetching
        case downloading(received: Int64, total: Int64)
        case unpacking
        case checking
        /// Checked; devices connected that the person did not agree to disconnect: asks first.
        case ready(devices: [Device])
        /// Checked by the automatic update: waits for a moment with no device connected (AppUpdater
        /// looks, holds new sessions, then sends `quiet`). Install Now (Update Now's button) takes it over.
        case waiting
        case installing
        case restarting
        case failed(Failure)

        /// An update is under way: no other may start, Check Now waits.
        var busy: Bool {
            switch self {
            case .idle, .confirming, .ready, .waiting, .failed: return false
            default: return true
            }
        }
    }

    struct State: Equatable, Sendable {
        var phase = Phase.idle
        /// The devices the person agreed to disconnect, by key.
        var consented: [String] = []
        var mode = Mode.manual
    }

    enum Event: Equatable, Sendable {
        case updateNow(devices: [Device])
        /// The automatic update begins (UpdateAutoPolicy.start said go).
        case automatic
        /// The automatic update's fetch found the release still cooling off (its signed date): nothing is
        /// downloaded, and it is no failure.
        case postponed
        /// No device connected for the while UpdateAutoPolicy asks, GitHub asked again, new sessions held:
        /// the waiting copy is installed; or GitHub's answer ends the attempt (the release changed, a stop).
        case quiet(Failure?)
        /// Right before Update Now's install, new sessions held: a device connected that the person didn't
        /// agree to disconnect (it would be cut off without the question). Update Now asks again.
        case devicesJoined([Device])
        case confirm
        case cancel
        /// The release and its manifest, verified, or why not.
        case fetched(Failure?)
        case progress(received: Int64, total: Int64)
        case downloaded(Failure?)
        case unpacked(Failure?)
        case checked(Failure?, devices: [Device])
        case installed(Failure?)
        case launched(Failure?)
    }

    enum Effect: Equatable, Sendable {
        case fetch, download, unpack, check, install, launch, quit, cleanUp
    }

    /// The next state and what to do, for an event; an event a phase does not take changes nothing.
    static func next(_ s: State, _ e: Event) -> (State, [Effect]) {
        var n = s
        func fail(_ f: Failure) -> (State, [Effect]) {
            n.phase = .failed(f)
            return (n, f.cleanUp ? [.cleanUp] : [])
        }
        switch (s.phase, e) {
        case (.idle, .updateNow(let devices)), (.failed, .updateNow(let devices)):
            n.mode = .manual
            n.consented = []
            if devices.isEmpty { n.phase = .fetching; return (n, [.fetch]) }
            n.phase = .confirming(devices: devices)
            return (n, [])
        case (.idle, .automatic), (.failed, .automatic):
            n.mode = .automatic
            n.consented = []
            n.phase = .fetching
            return (n, [.fetch])
        case (.fetching, .postponed) where s.mode == .automatic:
            n.phase = .idle
            return (n, [.cleanUp])
        case (.waiting, .quiet(nil)) where s.mode == .automatic:
            n.phase = .installing
            return (n, [.install])
        case (.waiting, .quiet(let f?)) where s.mode == .automatic:
            return fail(f)
        case (.waiting, .updateNow(let devices)):
            // Install Now: the person's, from here on, with the copy already checked.
            n.mode = .manual
            n.consented = []
            if devices.isEmpty { n.phase = .installing; return (n, [.install]) }
            n.phase = .ready(devices: devices)
            return (n, [])
        case (.confirming(let devices), .confirm):
            n.consented = devices.map(\.key)
            n.phase = .fetching
            return (n, [.fetch])
        case (.confirming, .cancel):
            n.phase = .idle
            return (n, [])
        case (.fetching, .fetched(nil)):
            n.phase = .downloading(received: 0, total: 0)
            return (n, [.download])
        case (.fetching, .fetched(let f?)):
            return fail(f)
        case (.downloading, .progress(let received, let total)):
            n.phase = .downloading(received: received, total: total)
            return (n, [])
        case (.downloading, .downloaded(nil)):
            n.phase = .unpacking
            return (n, [.unpack])
        case (.downloading, .downloaded(let f?)):
            return fail(f)
        case (.unpacking, .unpacked(nil)):
            n.phase = .checking
            return (n, [.check])
        case (.unpacking, .unpacked(let f?)):
            return fail(f)
        case (.checking, .checked(nil, let devices)):
            // The automatic update never installs over a connected device: it waits for a quiet moment.
            if s.mode == .automatic { n.phase = .waiting; return (n, []) }
            if Set(devices.map(\.key)).isSubset(of: Set(s.consented)) { n.phase = .installing; return (n, [.install]) }
            n.phase = .ready(devices: devices)
            return (n, [])
        case (.checking, .checked(let f?, _)):
            return fail(f)
        case (.ready(let devices), .confirm):
            n.consented = devices.map(\.key)
            n.phase = .installing
            return (n, [.install])
        case (.ready, .cancel), (.waiting, .cancel), (.fetching, .cancel), (.downloading, .cancel), (.unpacking, .cancel), (.checking, .cancel):
            n.phase = .idle
            return (n, [.cleanUp])
        case (.installing, .devicesJoined(let devices)) where s.mode == .manual:
            n.phase = .ready(devices: devices)
            return (n, [])
        case (.installing, .installed(nil)):
            n.phase = .restarting
            return (n, [.launch])
        case (.installing, .installed(let f?)):
            return fail(f)
        case (.restarting, .launched(nil)):
            return (n, [.quit])
        case (.restarting, .launched(let f?)):
            return fail(f)
        default:
            return (s, [])
        }
    }

    // MARK: Words for Settings and the menu (§4.7)

    /// Settings › General's part of the update section that is Update Now's.
    struct Pane: Equatable {
        /// Replaces the check's line while an update runs or after one failed.
        var line: String?
        /// A second line under it, on a line of its own (the download's size: "2.4 of 5.9 MB").
        var detail: String?
        var failed = false
        /// Why Update Now is unavailable, under the line.
        var note: String?
        /// The download's share done, 0…1.
        var progress: Double?
        /// A step with no measure.
        var spinning = false
        var updateNow = false
        var updateNowEnabled = false
        var updateNowTitle = "Update Now"
        var cancel = false
        /// The question before a disconnect, with its button's title.
        var question: String?
        var confirmTitle: String?
        /// An update is under way: Check Now waits.
        var busy = false
        /// VoiceOver hears each new line.
        var announce: String?
    }

    /// What the automatic update adds to the pane: AppUpdater's, from UpdateAutoPolicy and what it
    /// remembers (its words, already made).
    struct AutomaticPane: Equatable, Sendable {
        /// Automatically update Sill is on.
        var on = false
        /// While a signed release is offered and nothing runs: when Sill installs it by itself, or why not.
        var offerNote: String?
        /// After an automatic attempt failed: what happens next.
        var afterFailure: String?
        /// After Sill updated itself (this launch runs that version), for a few days.
        var updated: String?
        /// How long the install waits with no device connected.
        var quietMinutes = 10
    }

    /// The pane for `state`, when the check offers `offered` to `running`. `available`: this build has an
    /// update key (else nothing of Update Now shows). `refusal`: why it cannot run here. `keptAt`: where
    /// the old copy is when it could not be put back.
    static func pane(_ s: State, offered: SillVersion?, running: SillVersion?, available: Bool, refusal: Refusal?,
                     keptAt: String? = nil, automatic: AutomaticPane = AutomaticPane()) -> Pane {
        var p = Pane()
        guard available, let running else { return p }
        let target = offered.map { "Sill \($0)" } ?? "the update"
        switch s.phase {
        case .idle:
            guard offered != nil else {
                p.note = automatic.updated
                return p
            }
            p.updateNow = true
            p.updateNowEnabled = refusal == nil
            p.note = refusal.map(words) ?? (automatic.on ? automatic.offerNote : nil)
        case .confirming(let devices):
            p.updateNow = false
            p.question = "Updating restarts Sill and disconnects \(names(devices.map(\.name)))."
            p.confirmTitle = "Update and Disconnect"
            p.cancel = true
        case .fetching:
            p.line = "Getting \(target) from GitHub…"
            p.spinning = true
            p.cancel = true
        case .downloading(let received, let total):
            p.line = "Downloading \(target)…"
            p.detail = total > 0 ? "\(megabytes(received)) of \(megabytes(total)) MB" : nil
            p.progress = total > 0 ? min(1, Double(received) / Double(total)) : nil
            p.spinning = total == 0
            p.cancel = true
        case .unpacking, .checking:
            p.line = "Checking \(target)…"
            p.spinning = true
            p.cancel = true
        case .ready(let devices):
            p.line = "\(target) is ready."
            p.question = "Installing it restarts Sill and disconnects \(names(devices.map(\.name)))."
            p.confirmTitle = "Install and Disconnect"
            p.cancel = true
        case .waiting:
            p.line = "\(target) is ready."
            p.note = refusal.map(words)
                ?? "Sill installs it by itself once no device has been connected for \(automatic.quietMinutes) minutes, then restarts."
            p.updateNow = true
            p.updateNowEnabled = refusal == nil
            p.updateNowTitle = "Install Now"
            p.cancel = true
        case .installing:
            p.line = "Installing \(target)…"
            p.spinning = true
        case .restarting:
            p.line = "Restarting Sill…"
            p.spinning = true
        case .failed(let f):
            p.line = line(f, running: running, offered: offered ?? running, keptAt: keptAt)
            p.failed = true
            p.updateNow = offered != nil
            p.updateNowEnabled = refusal == nil && f.cleanUp
            p.updateNowTitle = "Try Again"
            p.note = refusal.map(words) ?? (s.mode == .automatic ? automatic.afterFailure : nil)
        }
        p.busy = s.phase.busy
        p.announce = p.line ?? p.question
        return p
    }

    /// "iPad", "iPad and iPhone", "iPad, iPhone and 2 more".
    static func names(_ devices: [String]) -> String {
        switch devices.count {
        case 0: return "no device"
        case 1: return devices[0]
        case 2: return "\(devices[0]) and \(devices[1])"
        default: return "\(devices[0]), \(devices[1]) and \(devices.count - 2) more"
        }
    }

    /// Megabytes with one decimal ("5.9").
    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000)
    }

    /// The status menu's update item: its title and subtitle, and whether it opens Settings › General
    /// (else the release page, as before Update Now).
    static func menuItem(_ phase: Phase, offered: SillVersion, running: SillVersion, available: Bool, refusal: Refusal?)
        -> (title: String, subtitle: String, opensSettings: Bool) {
        if case .waiting = phase {
            return ("Sill \(offered) Is Ready to Install…", "Installs by itself while no device is connected", true)
        }
        if phase.busy {
            let step: String
            switch phase {
            case .downloading(let received, let total) where total > 0: step = "Downloading, \(Int(min(1, Double(received) / Double(total)) * 100))%"
            case .fetching, .downloading: step = "Downloading"
            case .unpacking, .checking: step = "Checking"
            case .installing: step = "Installing"
            default: step = "Restarting"
            }
            return ("Updating to Sill \(offered)…", step, true)
        }
        if available, refusal == nil {
            return ("Sill \(offered) Is Available…", "You have \(running); update it in Settings", true)
        }
        return ("Sill \(offered) Is Available…", "You have \(running); opens its download page", false)
    }

    /// Settings › General's footnote in a build with an update key (UpdatePolicy.footnote otherwise, which
    /// claims no check this build can't make). Both checks named apart: Apple's (the Developer ID signature
    /// and notarization) and Sill's own update key's (the release's signed manifest).
    static func footnote(automatic: Bool) -> String {
        let checks = "Before it installs a new version, Sill checks it two ways: it must carry Apple’s signature and notarization for Sill’s developer, and the release must be signed with Sill’s own update key."
        let ask = "Once a day, Sill asks GitHub whether a newer version is out. GitHub sees this Mac’s IP address and which version of Sill it has; nothing else is sent."
        if automatic {
            return "\(ask) Automatically update Sill is on: Sill downloads a new version \(UpdateAutoPolicy.coolingOffWords), then installs it and restarts once no device has been connected for \(UpdateAutoPolicy.quietMinutes) minutes; it never disconnects anyone. \(checks) Update Now does the same at once."
        }
        return "\(ask) Sill downloads and installs nothing by itself. Update Now downloads the new version from GitHub, puts it in place of this copy and restarts Sill; Open Release Page… shows it on GitHub instead. \(checks)"
    }
}

extension UpdateInstallPolicy.Trust {
    /// The only Trust Sill.app uses.
    static let release = UpdateInstallPolicy.Trust(
        signer: UpdateInstallPolicy.pinnedRequirement, notarized: true, bundleName: "Sill.app", executable: "Sill",
        identifier: "me.saffer.sill.mac", teamID: "9B2KKVM937", stapledTicket: true, hardenedRuntime: true,
        runningRequirement: true,
        entitlements: [.string(key: "com.apple.application-identifier", value: "9B2KKVM937.me.saffer.sill.mac"),
                       .string(key: "com.apple.developer.team-identifier", value: "9B2KKVM937"),
                       .arrayContaining(key: "keychain-access-groups", value: "9B2KKVM937.me.saffer.sill.mac")],
        updateKeys: UpdateManifest.releaseKeys)
}

extension UpdateInstallPolicy.Endpoints {
    /// The only Endpoints Sill.app uses: GitHub, over https, Saffsanity/sill's releases. GitHub sends a
    /// release download to release-assets.githubusercontent.com (measured 2026-11-11, path
    /// /github-production-release-asset/1381093165/…); objects.githubusercontent.com is its older host.
    static let github = UpdateInstallPolicy.Endpoints(
        latestRelease: URL(string: "https://api.github.com/repos/Saffsanity/sill/releases/latest")!,
        apiOrigins: ["https://api.github.com"],
        downloadPrefix: "https://github.com/Saffsanity/sill/releases/download/",
        assetName: "Sill.zip", manifestName: "Sill.zip.manifest", stopName: "Sill.zip.stop",
        redirectOrigins: ["https://release-assets.githubusercontent.com", "https://objects.githubusercontent.com"],
        redirectPathPrefix: "/github-production-release-asset",
        maxRedirects: 3, minAssetBytes: 1 << 10, maxAssetBytes: 64 << 20)
}
