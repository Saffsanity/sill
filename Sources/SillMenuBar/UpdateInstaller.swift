import CryptoKit
import Darwin
import Foundation
import IOKit
import Security
import StreamProtocol

/// Update Now's mechanism (docs/one-click-update-plan.md §5): the release and its signed manifest from
/// GitHub, the download, the unpacking, the checks of the bundle, and the swap into place, each a step
/// that returns a `Result` and changes nothing at Sill.app's path until the swap. UpdateInstallPolicy
/// decides; this file does. AppUpdater (the app's main actor) runs the steps, the relaunch and the quit.
///
/// It takes its Trust and Endpoints as parameters, so Tests/update-harness can drive it against
/// scratch bundles and a server on 127.0.0.1 with test values; Sill.app passes only
/// `UpdateInstallPolicy.Trust.release` and `.Endpoints.github` (AppUpdater), and nothing here reads a
/// default, the environment or the arguments.
///
/// No other program runs: the zip is read and written by Sill's own code (UpdateArchive), through
/// directory descriptors this file opens with O_NOFOLLOW, and nothing from the download is executed,
/// loaded or opened before every check has passed. Foundation, Security, CryptoKit, IOKit and Darwin:
/// no AppKit, so the harness compiles it with swiftc.
final class UpdateInstaller: @unchecked Sendable {
    typealias Policy = UpdateInstallPolicy
    typealias Failure = UpdateInstallPolicy.Failure

    let trust: Policy.Trust
    let endpoints: Policy.Endpoints
    /// "Sill/0.6.1": the check's User-Agent.
    let userAgent: String

    init(trust: Policy.Trust, endpoints: Policy.Endpoints, userAgent: String) {
        self.trust = trust
        self.endpoints = endpoints
        self.userAgent = userAgent
    }

    /// Cancels the step in flight: the transfer at once, the unpacking between entries.
    final class Cancel: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        private var task: URLSessionTask?

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let t = task
            lock.unlock()
            t?.cancel()
        }

        /// False when already cancelled (the task is then not started).
        func attach(_ t: URLSessionTask) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled else { return false }
            task = t
            return true
        }
    }

    // MARK: The release and its manifest

    /// GitHub's latest release, which must be `offeredTag` and newer than `running`, and its manifest,
    /// signed with one of the trust's keys and describing exactly that release's zip. Nothing is written.
    func prepare(offeredTag: String, running: SillVersion, cancel: Cancel) async -> Result<(release: Policy.Release, manifest: UpdateManifest), Failure> {
        guard !trust.updateKeys.isEmpty else { return .failure(.manifest(.noKey)) }
        let endpoints = self.endpoints
        let body = Buffer()
        let api = Transfer(allowed: { Policy.apiRedirectAllowed($0, endpoints: endpoints) },
                           maxRedirects: endpoints.maxRedirects, limit: Int64(Policy.maxReleaseBytes), exactSize: nil,
                           sink: { body.append($0); return nil }, progress: nil)
        if case .failure(let f) = await api.run(URLRequest(url: endpoints.latestRelease),
                                                 configuration: configuration(api: true, resourceTimeout: 30), cancel: cancel) {
            return .failure(f)
        }
        let release: Policy.Release
        switch Policy.releaseToInstall(body.data, offeredTag: offeredTag, running: running, endpoints: endpoints) {
        case .failure(let f): return .failure(f)
        case .success(let r): release = r
        }
        let manifestBody = Buffer()
        let fetch = Transfer(allowed: { Policy.downloadRedirectAllowed($0, endpoints: endpoints) },
                             maxRedirects: endpoints.maxRedirects, limit: release.manifest.size, exactSize: release.manifest.size,
                             sink: { manifestBody.append($0); return nil }, progress: nil)
        if case .failure(let f) = await fetch.run(URLRequest(url: release.manifest.url),
                                                   configuration: configuration(api: false, resourceTimeout: 30), cancel: cancel) {
            return .failure(f)
        }
        switch UpdateManifest.verify(manifestBody.data, keys: trust.updateKeys) {
        case .failure(let p):
            return .failure(.manifest(p))
        case .success(let manifest):
            if let f = Policy.manifestMatches(manifest, release: release, endpoints: endpoints) { return .failure(f) }
            return .success((release, manifest))
        }
    }

    // MARK: The download

    /// The zip into `staging`/download.zip (a new file), exactly the manifest's size and SHA-256.
    /// `progress` gets the bytes so far and the total.
    func download(_ release: Policy.Release, manifest: UpdateManifest, into staging: URL,
                  progress: @escaping @Sendable (Int64, Int64) -> Void, cancel: Cancel) async -> Result<URL, Failure> {
        let endpoints = self.endpoints
        let file = staging.appendingPathComponent("download.zip")
        let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .failure(.disk(Self.errnoText())) }
        let hash = Hasher()
        let total = manifest.size
        let transfer = Transfer(allowed: { Policy.downloadRedirectAllowed($0, endpoints: endpoints) },
                                maxRedirects: endpoints.maxRedirects, limit: total, exactSize: total,
                                sink: { data in
                                    hash.update(data)
                                    return Self.writeAll(fd, data)
                                },
                                progress: { progress($0, total) })
        let result = await transfer.run(URLRequest(url: release.zip.url), configuration: configuration(api: false, resourceTimeout: 600),
                                        cancel: cancel)
        close(fd)
        switch result {
        case .failure(let f):
            return .failure(f)
        case .success(let received):
            guard received == total else { return .failure(.sizeMismatch) }
            guard hash.hex == manifest.sha256 else { return .failure(.hashMismatch) }
            return .success(file)
        }
    }

    // MARK: Unpacking

    /// The zip's app into `staging`/‹bundle name›, by the archive's listing alone: the zip read again
    /// and its SHA-256 checked again (it is a file on disk now), every entry checked before the first
    /// is written, written through directory descriptors made here, each file's size and CRC checked,
    /// links last. The zip is deleted after.
    func unpack(_ zip: URL, manifest: UpdateManifest, into staging: URL, cancel: Cancel) -> Result<URL, Failure> {
        let zipFD = open(zip.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard zipFD >= 0 else { return .failure(.disk(Self.errnoText())) }
        let handle = FileHandle(fileDescriptor: zipFD, closeOnDealloc: true)
        guard let data = try? handle.readToEnd(), Int64(data.count) == manifest.size else { return .failure(.sizeMismatch) }
        try? handle.close()
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == manifest.sha256 else { return .failure(.hashMismatch) }
        let listing: UpdateArchive.Listing
        switch UpdateArchive.read(data, top: trust.bundleName) {
        case .failure(let p): return .failure(.archive(p))
        case .success(let l): listing = l
        }
        if let free = Self.freeBytes(at: staging), free < listing.totalBytes + Policy.spaceMargin {
            return .failure(.lowSpace(neededMB: Int((listing.totalBytes + Policy.spaceMargin) >> 20) + 1))
        }
        let root = open(staging.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { return .failure(.disk(Self.errnoText())) }
        defer { close(root) }
        // Nothing of this name may be there yet: the staging folder is new and empty.
        var existing = stat()
        guard fstatat(root, trust.bundleName, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
            return .failure(.disk("the staging folder is not empty"))
        }
        let result: Result<Void, Failure> = data.withUnsafeBytes { zipBytes in
            var links: [UpdateArchive.Entry] = []
            for entry in listing.entries {
                if cancel.isCancelled { return .failure(.cancelled) }
                switch entry.kind {
                case .directory:
                    let fd = Self.folder(entry.components[...], under: root, create: true)
                    guard fd >= 0 else { return .failure(.disk("\(entry.path): \(Self.errnoText())")) }
                    close(fd)
                case .file(let executable):
                    let parent = Self.folder(entry.components.dropLast(), under: root, create: true)
                    guard parent >= 0 else { return .failure(.disk("\(entry.path): \(Self.errnoText())")) }
                    defer { close(parent) }
                    if let f = Self.writeFile(entry, executable: executable, in: parent, zip: zipBytes) { return .failure(f) }
                case .link:
                    links.append(entry)
                }
            }
            // Links last, so nothing is ever written through one (UpdateArchive refused entries under a
            // link and links to links; O_NOFOLLOW above refuses the rest).
            for entry in links {
                guard case .link(let target) = entry.kind else { continue }
                let parent = Self.folder(entry.components.dropLast(), under: root, create: true)
                guard parent >= 0 else { return .failure(.disk("\(entry.path): \(Self.errnoText())")) }
                defer { close(parent) }
                guard symlinkat(target, parent, entry.components.last!) == 0 else { return .failure(.disk("\(entry.path): \(Self.errnoText())")) }
            }
            return .success(())
        }
        unlink(zip.path)
        switch result {
        case .failure(let f): return .failure(f)
        case .success: return .success(staging.appendingPathComponent(trust.bundleName))
        }
    }

    /// One file of the archive, created new (O_EXCL, O_NOFOLLOW) in `parent`, its bytes, size and CRC
    /// checked, its mode 0644 or 0755, flushed to the disk.
    private static func writeFile(_ entry: UpdateArchive.Entry, executable: Bool, in parent: Int32,
                                  zip: UnsafeRawBufferPointer) -> Failure? {
        let name = entry.components.last!
        let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .disk("\(entry.path): \(errnoText())") }
        defer { close(fd) }
        let input = UnsafeRawBufferPointer(rebasing: zip[entry.dataOffset..<(entry.dataOffset + entry.compressedSize)])
        var writeError: String?
        let crc: UInt32
        if entry.method == 0 {
            if let error = writeAll(fd, input) { return .disk("\(entry.path): \(error)") }
            crc = UpdateArchive.crc32(input)
        } else {
            switch UpdateArchive.inflate(input, size: entry.size, name: entry.path, write: { piece in
                writeError = writeAll(fd, piece)
                return writeError == nil
            }) {
            case .failure(.writeFailed): return .disk("\(entry.path): \(writeError ?? "a write failed")")
            case .failure(let p): return .archive(p)
            case .success(let c): crc = c
            }
        }
        guard crc == entry.crc32 else { return .archive(.crc(entry.path)) }
        guard fchmod(fd, executable ? 0o755 : 0o644) == 0 else { return .disk("\(entry.path): \(errnoText())") }
        // On the disk before the swap: a power cut after it must not leave a half-written app in place.
        guard fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0 else { return .disk("\(entry.path): \(errnoText())") }
        return nil
    }

    /// The folder `parts` under the descriptor `root`, made (0755) where missing when `create`, every
    /// step opened with O_NOFOLLOW so a link anywhere on the way is refused. A descriptor the caller
    /// closes, or -1 (errno set).
    static func folder(_ parts: ArraySlice<String>, under root: Int32, create: Bool) -> Int32 {
        var fd = dup(root)
        guard fd >= 0 else { return -1 }
        for part in parts {
            if create, mkdirat(fd, part, 0o755) != 0, errno != EEXIST {
                let saved = errno
                close(fd)
                errno = saved
                return -1
            }
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let saved = errno
            close(fd)
            guard next >= 0 else { errno = saved; return -1 }
            if create, fchmod(next, 0o755) != 0 {
                let saved = errno
                close(next)
                errno = saved
                return -1
            }
            fd = next
        }
        return fd
    }

    // MARK: Checking a bundle

    /// What the trust's checks read from `bundle` (§4.5): the tree by lstat, the signature by
    /// Security.framework under the strict flags, the requirements, the signing information and each
    /// architecture's cdhash.
    func facts(of bundle: URL, runningRequirement: SecRequirement?) -> Policy.BundleFacts {
        var f = Policy.BundleFacts()
        f.tree = Self.treeProblem(bundle, executable: trust.executable)
        guard f.tree == nil else { return f }
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundle as CFURL, [], &code)
        guard created == errSecSuccess, let code else { f.signatureStatus = created; return f }
        f.signatureStatus = SecStaticCodeCheckValidityWithErrors(code, Self.strictFlags, nil, nil)
        guard f.signatureStatus == errSecSuccess else { return f }
        // Every requirement on every slice: SecStaticCodeCheckValidity checks only this Mac's slice unless asked.
        f.signer = Self.satisfies(code, trust.signer)
        if trust.notarized { f.notarized = Self.satisfies(code, "notarized") }
        if trust.runningRequirement {
            f.runningRequirement = runningRequirement.map { SecStaticCodeCheckValidity(code, Self.allSlices, $0) == errSecSuccess } ?? false
        }
        var info: CFDictionary?
        if SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSContentInformation | kSecCSRequirementInformation),
                                         &info) == errSecSuccess,
           let d = info as? [String: Any] {
            f.identifier = d[kSecCodeInfoIdentifier as String] as? String
            f.teamID = d[kSecCodeInfoTeamIdentifier as String] as? String
            f.flags = (d[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
            f.stapledTicket = ((d[kSecCodeInfoStapledNotarizationTicket as String] as? Data)?.count ?? 0) > 0
            if let e = d[kSecCodeInfoEntitlementsDict as String] as? [String: Any] { f.entitlements = e.mapValues(Self.entitlement) }
            if let p = d[kSecCodeInfoPList as String] as? [String: Any] { f.plist = p.compactMapValues { $0 as? String } }
        }
        for arch in Policy.Architecture.allCases {
            if let h = Self.cdhash(of: bundle, arch: arch) { f.cdhashes[arch.rawValue] = h }
        }
        return f
    }

    /// The trust's judgement of `bundle` against the verified manifest.
    func check(_ bundle: URL, manifest: UpdateManifest, running: SillVersion, runningRequirement: SecRequirement?) -> Result<Policy.Checked, Failure> {
        switch Policy.verdict(facts(of: bundle, runningRequirement: runningRequirement), trust: trust, manifest: manifest,
                              running: running, arch: .current, macOS: ProcessInfo.processInfo.operatingSystemVersion) {
        case .success(let c): return .success(c)
        case .failure(let p): return .failure(.bundle(p))
        }
    }

    /// Every slice, nested code, no link out of the bundle, no resource fork or other sideband data, an
    /// app's layout: what a strict `codesign --verify --deep` asks, and more.
    static let strictFlags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
                                          | kSecCSRestrictSymlinks | kSecCSRestrictSidebandData | kSecCSRestrictToAppLike)

    static let allSlices = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)

    /// Whether every slice of `code` satisfies `requirement`.
    static func satisfies(_ code: SecStaticCode, _ requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, allSlices, req) == errSecSuccess
    }

    /// The cdhash (40 lowercase hex digits) of `bundle`'s slice for `arch`, or nil when it has none.
    static func cdhash(of bundle: URL, arch: Policy.Architecture) -> String? {
        var code: SecStaticCode?
        let attributes = [kSecCodeAttributeArchitecture as String: arch.rawValue] as CFDictionary
        guard SecStaticCodeCreateWithPathAndAttributes(bundle as CFURL, [], attributes, &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess, let d = info as? [String: Any],
              let unique = d[kSecCodeInfoUnique as String] as? Data, unique.count == 20 else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    static func entitlement(_ value: Any) -> Policy.EntitlementValue {
        if let s = value as? String { return .string(s) }
        if let a = value as? [Any] {
            let strings = a.compactMap { $0 as? String }
            return strings.count == a.count ? .strings(strings) : .other
        }
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
        return .other
    }

    /// Nil when `bundle` is a folder (not a link) with Contents/Info.plist a file and
    /// Contents/MacOS/‹executable› an executable file, none of them links; else what is wrong.
    static func treeProblem(_ bundle: URL, executable: String) -> String? {
        func type(_ path: String) -> mode_t? {
            var s = stat()
            return lstat(path, &s) == 0 ? s.st_mode & S_IFMT : nil
        }
        let base = bundle.path
        guard type(base) == S_IFDIR else { return "the app is not a folder" }
        guard type(base + "/Contents") == S_IFDIR else { return "no Contents folder" }
        guard type(base + "/Contents/Info.plist") == S_IFREG else { return "no Info.plist" }
        guard type(base + "/Contents/MacOS") == S_IFDIR else { return "no MacOS folder" }
        var s = stat()
        guard lstat(base + "/Contents/MacOS/" + executable, &s) == 0, s.st_mode & S_IFMT == S_IFREG, s.st_mode & 0o111 != 0 else {
            return "no executable"
        }
        return nil
    }

    // MARK: The swap

    /// The checked `staged` app into `installed`'s place in one atomic exchange (renamex_np,
    /// RENAME_SWAP), when the copy there is still a folder and, given `runningCDHash`, still the code
    /// that is running. Then every check again at `installed`, the same code required; on any failure
    /// the exchange is undone. Afterwards `staged` holds the old copy.
    func install(staged: URL, installed: URL, runningCDHash: String, expected: Policy.Checked, manifest: UpdateManifest,
                 running: SillVersion, runningRequirement: SecRequirement?) -> Result<Void, Failure> {
        guard Self.isFolder(installed) else { return .failure(.changedSinceStart) }
        guard Self.cdhash(of: installed, arch: .current) == runningCDHash else { return .failure(.changedSinceStart) }
        guard Self.isFolder(staged) else { return .failure(.swapFailed("the checked copy is gone")) }
        guard let a = Self.device(of: staged.deletingLastPathComponent()), let b = Self.device(of: installed.deletingLastPathComponent()),
              a == b else { return .failure(.swapFailed("not on the same volume")) }
        guard renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 else { return .failure(.swapFailed(Self.errnoText())) }
        switch check(installed, manifest: manifest, running: running, runningRequirement: runningRequirement) {
        case .success(let c) where c == expected:
            return .success(())
        case .failure(.bundle(let p)):
            return .failure(.checkAfterSwap(p, putBack: putBack(staged: staged, installed: installed, old: runningCDHash)))
        default:
            return .failure(.checkAfterSwap(.codeChanged, putBack: putBack(staged: staged, installed: installed, old: runningCDHash)))
        }
    }

    /// The exchange again: the old copy back at `installed`, the new one in `staged`, but only when what
    /// waits in `staged` is still the old copy, the code that was running (`old`, its cdhash for this
    /// Mac's slice): the staging folder is this user's, and anything of this user could have put
    /// something else there meanwhile, which Sill's right to change Sill.app must never carry into place.
    func putBack(staged: URL, installed: URL, old: String) -> Bool {
        guard Self.isFolder(staged), Self.cdhash(of: staged, arch: .current) == old else { return false }
        return renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0
    }

    // MARK: Staging

    /// A new, empty folder for one update on `installed`'s volume (FileManager's item-replacement
    /// directory: this user's, mode 0700), so the swap is one rename on one volume.
    static func makeStaging(for installed: URL) -> Result<URL, Failure> {
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true) else {
            return .failure(.disk("no temporary folder on Sill’s volume"))
        }
        var s = stat()
        guard lstat(dir.path, &s) == 0, s.st_mode & S_IFMT == S_IFDIR, s.st_uid == getuid(), chmod(dir.path, 0o700) == 0,
              (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true,
              let a = device(of: dir), let b = device(of: installed.deletingLastPathComponent()), a == b else {
            try? fm.removeItem(at: dir)
            return .failure(.disk("no usable temporary folder on Sill’s volume"))
        }
        return .success(dir)
    }

    /// Removes a staging folder (it never follows a link inside it).
    static func remove(_ staging: URL) {
        try? FileManager.default.removeItem(at: staging)
    }

    /// The file that marks a staging folder holding the old copy that could not be put back: the
    /// person's way back, which no clean-up deletes.
    static let keptMarker = "Sill’s previous copy is here.txt"

    /// Marks `staging` as holding the old copy that could not be put back.
    static func markKept(_ staging: URL, path: String) {
        let text = "This folder holds the copy of Sill that an update replaced and could not put back: \(path).\nTo go back to it, quit Sill and move it to your Applications folder.\n"
        FileManager.default.createFile(atPath: staging.appendingPathComponent(keptMarker).path, contents: Data(text.utf8),
                                       attributes: [.posixPermissions: 0o600])
    }

    /// Removes the staging folders earlier updates left (`NSIRD_‹this process's name›_…` in the
    /// temporary-items folder of `installed`'s volume), but `keep` and any marked as holding a copy that
    /// could not be put back; what it removed.
    static func cleanUpStaging(for installed: URL, keep: URL? = nil) -> [String] {
        let fm = FileManager.default
        guard let probe = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true) else {
            return []
        }
        let parent = probe.deletingLastPathComponent()
        try? fm.removeItem(at: probe)
        let prefix = "NSIRD_\(ProcessInfo.processInfo.processName)_"
        var removed: [String] = []
        for name in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(prefix) {
            let url = parent.appendingPathComponent(name)
            if let keep, url.standardizedFileURL.path == keep.standardizedFileURL.path { continue }
            var s = stat()
            guard lstat(url.path, &s) == 0, s.st_mode & S_IFMT == S_IFDIR, s.st_uid == getuid() else { continue }
            var marker = stat()
            if lstat(url.appendingPathComponent(keptMarker).path, &marker) == 0 { continue }
            if (try? fm.removeItem(at: url)) != nil { removed.append(url.path) }
        }
        return removed
    }

    // MARK: Where Sill runs

    /// The running code as the trust sees it: whether it is a notarized Developer ID Sill, its own
    /// designated requirement, and the cdhash the kernel runs.
    struct RunningCode {
        let isRelease: Bool
        let requirement: SecRequirement?
    }

    static func runningCode(trust: Policy.Trust) -> RunningCode {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return RunningCode(isRelease: false, requirement: nil) }
        var signer: SecRequirement?
        let dynamicOK = SecRequirementCreateWithString(trust.signer as CFString, [], &signer) == errSecSuccess
            && signer.map { SecCodeCheckValidity(me, [], $0) == errSecSuccess } == true
        var onDisk: SecStaticCode?
        var requirement: SecRequirement?
        var notarized = !trust.notarized
        if SecCodeCopyStaticCode(me, [], &onDisk) == errSecSuccess, let onDisk {
            SecCodeCopyDesignatedRequirement(onDisk, [], &requirement)
            if trust.notarized { notarized = satisfies(onDisk, "notarized") }
        }
        return RunningCode(isRelease: dynamicOK && notarized, requirement: requirement)
    }

    /// Whether the copy at `bundle` is the code this process runs: its slice's cdhash on disk, as a
    /// requirement the kernel's copy of this process's code must satisfy.
    static func runningIsInstalled(_ bundle: URL) -> (Bool, String?) {
        guard let onDisk = cdhash(of: bundle, arch: .current) else { return (false, nil) }
        var me: SecCode?
        var req: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecRequirementCreateWithString("cdhash H\"\(onDisk)\"" as CFString, [], &req) == errSecSuccess, let req else { return (false, nil) }
        return (SecCodeCheckValidity(me, [], req) == errSecSuccess, onDisk)
    }

    /// Whether the running process `pid` satisfies `requirement` (the new copy, after its launch).
    static func process(_ pid: pid_t, satisfies requirement: String) -> Bool {
        var guest: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var req: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess, let guest,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecCodeCheckValidity(guest, [], req) == errSecSuccess
    }

    /// The requirement the launched copy must satisfy: the trust's signer and one of the checked cdhashes.
    func launchRequirement(_ checked: Policy.Checked) -> String {
        let hashes = checked.cdhashes.values.sorted().map { "cdhash H\"\($0)\"" }.joined(separator: " or ")
        return "\(trust.signer) and (\(hashes))"
    }

    /// Where `bundle` is, for UpdateInstallPolicy.refusal (the running-code facts come from the caller).
    static func situation(bundle: URL, executable: String, runningIsRelease: Bool, testFeed: Bool, runningIsInstalled: Bool,
                          neededBytes: Int64) -> Policy.Situation {
        var owned = false
        var ownerName = "another account"
        var s = stat()
        if lstat(bundle.path, &s) == 0 {
            owned = s.st_uid == getuid()
            if !owned { ownerName = accountName(s.st_uid) }
        }
        // A link anywhere on the way (the bundle or a folder above it) could send the swap elsewhere
        // between the checks and the exchange.
        var link = false
        var walk = bundle.standardizedFileURL
        while walk.path != "/" {
            var l = stat()
            if lstat(walk.path, &l) == 0, l.st_mode & S_IFMT == S_IFLNK { link = true; break }
            walk = walk.deletingLastPathComponent()
        }
        var readOnly = false, network = false, image = false
        var volume = "this disk"
        var fs = statfs()
        if statfs(bundle.path, &fs) == 0 {
            readOnly = fs.f_flags & UInt32(MNT_RDONLY) != 0
            network = fs.f_flags & UInt32(MNT_LOCAL) == 0
            let from = withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
            image = from.hasPrefix("/dev/") && isDiskImage(bsdName: String(from.dropFirst(5)))
            if let name = (try? bundle.resourceValues(forKeys: [.volumeNameKey]))?.volumeName {
                volume = name
            } else {
                volume = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
            }
        }
        let parent = bundle.deletingLastPathComponent()
        let others = processesRunning(from: bundle, executable: executable, excluding: getpid())
        let me = getuid()
        let accounts = Set(others.filter { $0.uid != me }.map { accountName($0.uid) }).sorted()
        return Policy.Situation(
            runningIsRelease: runningIsRelease, testFeed: testFeed, bundlePath: bundle.path, bundleIsLink: link,
            translocated: bundle.path.contains("/AppTranslocation/"), volumeName: volume, readOnlyVolume: readOnly,
            networkVolume: network, diskImage: image, folderWritable: access(parent.path, W_OK) == 0,
            bundleWritable: access(bundle.path, W_OK) == 0, ownedByUser: owned, ownerName: owned ? "" : ownerName,
            runningIsInstalled: runningIsInstalled,
            otherAccounts: accounts, otherInstances: others.filter { $0.uid == me }.count,
            freeBytes: freeBytes(at: parent), neededBytes: neededBytes)
    }

    /// Every other process running `bundle`'s executable (the same file, by device and inode, whatever
    /// path it was started by) or any other file inside it (by path), any account's (proc_pidpath reads
    /// other users' processes), with its user.
    static func processesRunning(from bundle: URL, executable: String, excluding own: pid_t) -> [(pid: pid_t, uid: uid_t)] {
        let prefix = bundle.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var main = stat()
        let haveMain = stat(bundle.appendingPathComponent("Contents/MacOS/\(executable)").path, &main) == 0
        let wanted = proc_listallpids(nil, 0)
        guard wanted > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(wanted) + 256)
        let count = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.stride))
        }
        guard count > 0 else { return [] }
        var found: [(pid: pid_t, uid: uid_t)] = []
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(min(Int(count), pids.count)) where pid > 0 && pid != own {
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let text = String(cString: path)
            var file = stat()
            let same = haveMain && stat(text, &file) == 0 && file.st_dev == main.st_dev && file.st_ino == main.st_ino
            guard same || text.hasPrefix(prefix) else { continue }
            found.append((pid, uid(of: pid) ?? uid_t.max))
        }
        return found
    }

    /// A process's user (sysctl, readable for any process).
    static func uid(of pid: pid_t) -> uid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ucred.cr_uid
    }

    /// An account's full name, else its short name, else its number.
    static func accountName(_ uid: uid_t) -> String {
        guard let pw = getpwuid(uid) else { return "user \(uid)" }
        if let gecos = pw.pointee.pw_gecos {
            let full = String(cString: gecos).split(separator: ",").first.map(String.init) ?? ""
            if !full.isEmpty { return full }
        }
        return String(cString: pw.pointee.pw_name)
    }

    /// Whether the disk `bsdName` (disk7s1) lies on a disk image: an ancestor in the I/O Registry is
    /// the disk image driver (AppleDiskImageDevice since DiskImages2, IOHDIXHDDrive before).
    static func isDiskImage(bsdName: String) -> Bool {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return false }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return false }
        var depth = 0
        while entry != 0, depth < 64 {
            if IOObjectConformsTo(entry, "AppleDiskImageDevice") != 0 || IOObjectConformsTo(entry, "IOHDIXHDDrive") != 0 {
                IOObjectRelease(entry)
                return true
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = status == KERN_SUCCESS ? parent : 0
            depth += 1
        }
        if entry != 0 { IOObjectRelease(entry) }
        return false
    }

    static func freeBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    static func isFolder(_ url: URL) -> Bool {
        var s = stat()
        return lstat(url.path, &s) == 0 && s.st_mode & S_IFMT == S_IFDIR
    }

    static func device(of url: URL) -> dev_t? {
        var s = stat()
        return stat(url.path, &s) == 0 ? s.st_dev : nil
    }

    // MARK: Writing

    /// Writes all of `bytes`; nil, or the error's words.
    static func writeAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer) -> String? {
        var offset = 0
        while offset < bytes.count {
            let n = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                return errnoText()
            }
            offset += n
        }
        return nil
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> String? {
        data.withUnsafeBytes { writeAll(fd, $0) }
    }

    static func errnoText() -> String {
        String(cString: strerror(errno))
    }

    // MARK: The network

    /// The session for one request: ephemeral, no cookies, cache or credentials, Sill's User-Agent and a
    /// fixed language; GitHub's API headers for the release.
    func configuration(api: Bool, resourceTimeout: TimeInterval) -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = resourceTimeout
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.waitsForConnectivity = false
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        var headers = ["User-Agent": userAgent, "Accept-Language": "en"]
        if api {
            headers["Accept"] = "application/vnd.github+json"
            headers["X-GitHub-Api-Version"] = "2022-11-28"
        }
        c.httpAdditionalHeaders = headers
        return c
    }

    /// Bytes gathered across the delegate queue (written there, read after the transfer ends).
    final class Buffer: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        func append(_ d: Data) { lock.lock(); bytes.append(d); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    }

    /// A SHA-256 fed across the delegate queue.
    final class Hasher: @unchecked Sendable {
        private let lock = NSLock()
        private var sha = SHA256()
        func update(_ d: Data) { lock.lock(); sha.update(data: d); lock.unlock() }
        var hex: String {
            lock.lock(); defer { lock.unlock() }
            return sha.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}

/// One GET by Update Now's rules (T5, T6): redirects only where `allowed` says and at most
/// `maxRedirects`; no credentials (every authentication challenge but the server's certificate is
/// refused); a status of 200 only; the body handed to `sink` in pieces, never more than `limit`
/// bytes, and exactly `exactSize` when it is given (a Content-Length that disagrees ends it first).
private final class Transfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Failure = UpdateInstallPolicy.Failure

    private let allowed: (URL) -> Bool
    private let maxRedirects: Int
    private let limit: Int64
    private let exactSize: Int64?
    /// Nil when the piece was taken, else why not (a write's error).
    private let sink: (Data) -> String?
    private let progress: ((Int64) -> Void)?
    // The delegate queue is serial; `continuation` is set before the task starts.
    private var redirects = 0
    private var received: Int64 = 0
    private var failure: Failure?
    private var continuation: CheckedContinuation<Result<Int64, Failure>, Never>?

    init(allowed: @escaping (URL) -> Bool, maxRedirects: Int, limit: Int64, exactSize: Int64?,
         sink: @escaping (Data) -> String?, progress: ((Int64) -> Void)?) {
        self.allowed = allowed
        self.maxRedirects = maxRedirects
        self.limit = limit
        self.exactSize = exactSize
        self.sink = sink
        self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration, cancel: UpdateInstaller.Cancel) async -> Result<Int64, Failure> {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        var request = request
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return await withCheckedContinuation { c in
            continuation = c
            let task = session.dataTask(with: request)
            if cancel.attach(task) {
                task.resume()
            } else {
                continuation = nil
                c.resume(returning: .failure(.cancelled))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard let url = request.url, redirects <= maxRedirects, allowed(url) else {
            failure = .redirectRefused(request.url.flatMap(UpdateInstallPolicy.origin) ?? "an address Sill doesn’t download from")
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        answer(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        answer(challenge, completionHandler)
    }

    /// The server's certificate by the system's rules; anything that would send a credential, refused,
    /// and the transfer ends there.
    private func answer(_ challenge: URLAuthenticationChallenge,
                        _ completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            if failure == nil { failure = .download("the server asked for a credential, which Sill never sends") }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard failure == nil else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse else {
            failure = .download("not an HTTP answer")
            completionHandler(.cancel)
            return
        }
        guard http.statusCode == 200 else {
            failure = .github(http.statusCode)
            completionHandler(.cancel)
            return
        }
        let length = http.expectedContentLength
        if length >= 0 {
            if let exactSize, length != exactSize { failure = .sizeMismatch; completionHandler(.cancel); return }
            if length > limit { failure = .tooLarge; completionHandler(.cancel); return }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        received += Int64(data.count)
        guard received <= limit else {
            failure = .tooLarge
            dataTask.cancel()
            return
        }
        if let error = sink(data) {
            failure = .disk(error)
            dataTask.cancel()
            return
        }
        progress?(received)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Int64, Failure>
        if let failure {
            result = .failure(failure)
        } else if let e = error as? URLError {
            switch e.code {
            case .cancelled: result = .failure(.cancelled)
            case .timedOut: result = .failure(.download("no data for 30 s"))
            case _ where received > 0:
                // Bytes came, then the transfer broke: a download that stopped, not a Mac offline.
                result = .failure(.download(e.localizedDescription))
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed:
                result = .failure(.noConnection(e.localizedDescription))
            default:
                result = .failure(UpdatePolicy.tlsCodes.contains(e.code.rawValue) ? .noConnection(e.localizedDescription)
                                                                                    : .download(e.localizedDescription))
            }
        } else if let error {
            result = .failure(.download(error.localizedDescription))
        } else if let exactSize, received != exactSize {
            result = .failure(.sizeMismatch)
        } else {
            result = .success(received)
        }
        let c = continuation
        continuation = nil
        c?.resume(returning: result)
    }
}
