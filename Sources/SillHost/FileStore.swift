import Foundation
import CryptoKit
import CoreServices
import StreamProtocol

/// Where files from devices land on the Mac, and how (docs/files-plan.md §7.1, §7.3 and §11): the
/// destination (Downloads › Sill unless the Mac's person chose another folder) and its hidden staging folder
/// `.Sill Incoming`, on the same volume so the last move is atomic. A file is written there under a name of
/// Sill's own (`<transfer>-<file>.part`, created new and never through a link, mode 0600), hashed as it is
/// written, and only once it is whole and its size and SHA-256 are the sender's is it marked as downloaded
/// (`com.apple.quarantine` with Sill as the agent, so Gatekeeper checks an app, a package or a script in it
/// before it opens) and where from (`kMDItemWhereFroms`), made 0644, and moved into the destination under a free
/// name (FileNames.unique) with `renamex_np(RENAME_EXCL)`, which never replaces anything. What was partial is
/// deleted at a cancel, a quit and the next launch. Every write goes through `write(2)`, whose failure is an
/// error, never an exception: a full volume ends the transfer `noRoom`, not Sill.
///
/// Threading: none of its own. FileHub calls it on `sill.files` only. Foundation, CryptoKit and CoreServices
/// (the quarantine's keys); checked on its own on a scratch folder (`Tests/checks/file-store`).
package final class FileStore {
    /// The hidden staging folder inside the destination.
    package static let stagingName = ".Sill Incoming"

    package enum Failure: Error, Equatable {
        /// The volume is full (ENOSPC, EDQUOT).
        case noRoom
        /// Anything else: the folder is a link, cannot be made or written, the move failed.
        case cantSave(String)
        /// The file's size or SHA-256 is not the sender's.
        case damaged

        /// The transfer's reason for it.
        package var reason: FileReason {
            switch self {
            case .noRoom: return .noRoom
            case .cantSave: return .cantSave
            case .damaged: return .damaged
            }
        }
    }

    /// One file on its way: its staging file, open for writing, and what has been written.
    package final class Staging {
        package let url: URL
        fileprivate var fd: Int32
        package fileprivate(set) var written: UInt64 = 0
        fileprivate var hash = SHA256()

        fileprivate init(url: URL, fd: Int32) { self.url = url; self.fd = fd }
        deinit { if fd >= 0 { close(fd) } }
    }

    package let destination: URL
    package var staging: URL { destination.appendingPathComponent(Self.stagingName, isDirectory: true) }
    /// What a kept file is marked as coming from: "‹device›, through Sill" in Get Info's Where from.
    private let agentBundleID: String

    package init(destination: URL, agentBundleID: String = Bundle.main.bundleIdentifier ?? "me.saffer.sill.mac") {
        self.destination = destination.standardizedFileURL
        self.agentBundleID = agentBundleID
    }

    /// Downloads › Sill: a folder Sill makes, so macOS asks nothing (NSDownloadsFolderUsageDescription).
    package static var defaultDestination: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return downloads.appendingPathComponent("Sill", isDirectory: true)
    }

    /// The destination and its staging folder, made if they are missing (0755 and 0700). Neither may be a
    /// link: a folder Sill writes into is one it can name.
    package func prepare() throws {
        try makeFolder(destination, mode: 0o755)
        try makeFolder(staging, mode: 0o700)
    }

    private func makeFolder(_ url: URL, mode: mode_t) throws {
        var st = stat()
        if lstat(url.path, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFDIR else { throw Failure.cantSave("\(url.lastPathComponent) is not a folder") }
            return
        }
        guard errno == ENOENT else { throw Failure.cantSave(String(cString: strerror(errno))) }
        // The destination's parent (Downloads) made if it is missing; the staging folder's is the destination.
        let parent = url.deletingLastPathComponent()
        var pst = stat()
        if lstat(parent.path, &pst) != 0 {
            do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
            catch { throw Failure.cantSave("\(parent.lastPathComponent): \(error.localizedDescription)") }
        }
        guard mkdir(url.path, mode) == 0 || errno == EEXIST else { throw Failure.cantSave(String(cString: strerror(errno))) }
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { throw Failure.cantSave("\(url.lastPathComponent) is not a folder") }
    }

    /// The staging file's name: Sill's own, never the sender's.
    package static func stagingFileName(transfer: UInt32, file: UInt32) -> String {
        String(format: "%08x-%08x.part", transfer, file)
    }

    /// A new, empty staging file for `file` of `transfer`: created exclusively, never through a link, 0600.
    package func open(transfer: UInt32, file: UInt32) throws -> Staging {
        try prepare()
        let url = staging.appendingPathComponent(Self.stagingFileName(transfer: transfer, file: file))
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.failure(errno) }
        return Staging(url: url, fd: fd)
    }

    /// The part's bytes, at the end of what was written (parts come in order).
    package func write(_ bytes: Data, to s: Staging) throws {
        guard s.fd >= 0 else { throw Failure.cantSave("closed") }
        try bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var done = 0
            while done < raw.count {
                let n = Darwin.write(s.fd, raw.baseAddress! + done, raw.count - done)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw Self.failure(errno)
                }
                done += n
            }
        }
        s.hash.update(data: bytes)
        s.written += UInt64(bytes.count)
    }

    /// The file is whole: its size and SHA-256 checked against the sender's, then marked as downloaded from
    /// `device` and where from, 0644, and moved into the destination under a free name. Returns that name. On
    /// any failure the staging file is deleted.
    package func finish(_ s: Staging, size: UInt64, sha256: String, name: String, device: String) throws -> String {
        defer { discard(s) }
        guard s.fd >= 0 else { throw Failure.cantSave("closed") }
        let digest = Base64URL.encode(Data(s.hash.finalize()))
        guard s.written == size, digest == sha256 else { throw Failure.damaged }
        guard fsync(s.fd) == 0 || errno == ENOTSUP else { throw Self.failure(errno) }
        guard fchmod(s.fd, 0o644) == 0 else { throw Self.failure(errno) }
        close(s.fd); s.fd = -1
        try mark(s.url, device: device)
        return try Self.place(FileNames.clean(name), exists: { self.exists($0) }) { candidate in
            renamex_np(s.url.path, self.destination.appendingPathComponent(candidate).path, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
        }
    }

    /// A kept file moved into place under a free name: `cleaned`, or its next number (FileNames.unique) against what
    /// `exists` sees and what was tried, never replacing anything. `rename` moves it there and returns 0 or its errno:
    /// EEXIST (the name taken after all, in between or by what `exists` missed) tries the next number; any other
    /// error is the file's failure (a full volume: noRoom).
    static func place(_ cleaned: String, exists: (String) -> Bool, rename: (String) -> Int32) throws -> String {
        var tried = Set<String>()
        for _ in 0..<64 {
            guard let candidate = FileNames.unique(cleaned, taken: { tried.contains($0.lowercased()) || exists($0) }) else { break }
            let code = rename(candidate)
            if code == 0 { return candidate }
            guard code == EEXIST else { throw failure(code) }
            tried.insert(candidate.lowercased())      // taken in between: the next number
        }
        throw Failure.cantSave("no free name")
    }

    /// Whether anything is at `name` in the destination, a link included (lstat: a link to nothing counts).
    func exists(_ name: String) -> Bool {
        var st = stat()
        return lstat(destination.appendingPathComponent(name).path, &st) == 0
    }

    /// Quarantine with Sill as the agent and the type of an ordinary download, and Where from. A file that
    /// cannot be marked is not kept.
    private func mark(_ url: URL, device: String) throws {
        var u = url
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "Sill",
            kLSQuarantineAgentBundleIdentifierKey as String: agentBundleID,
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
        ]
        do { try u.setResourceValues(values) } catch { throw Failure.cantSave("quarantine: \(error.localizedDescription)") }
        let from = "\(SafeText.label(device)), through Sill"
        if let plist = try? PropertyListSerialization.data(fromPropertyList: [from], format: .binary, options: 0) {
            _ = plist.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, XATTR_NOFOLLOW) }
        }
    }

    /// The staging file closed and deleted (a cancel, a stop, a finish that failed).
    package func discard(_ s: Staging) {
        if s.fd >= 0 { close(s.fd); s.fd = -1 }
        unlink(s.url.path)
    }

    /// Every leftover in the staging folder deleted: at launch, at quit, when the folder changes. Never follows
    /// a link; never touches the destination's own files. Returns how many went.
    @discardableResult
    package func cleanLeftovers() -> Int {
        var st = stat()
        guard lstat(staging.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return 0 }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
        var gone = 0
        for name in names where unlink(staging.appendingPathComponent(name).path) == 0 { gone += 1 }
        return gone
    }

    /// Why a folder the Mac's person chose cannot take files from devices, in Settings' words; nil when it can:
    /// it must be a folder, not a link to one (Sill writes only where it can name the place), and writable.
    package static func refusal(forFolder url: URL) -> String? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return "That folder can’t be found." }
        if (st.st_mode & S_IFMT) == S_IFLNK { return "Choose the folder itself, not an alias or a link to it." }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return "Choose a folder." }
        guard access(url.path, W_OK) == 0 else { return "Sill can’t save files in that folder." }
        return nil
    }

    /// The destination volume's free space for an ordinary file (nil when it cannot be read).
    package func freeSpace() -> UInt64? {
        let probe = (try? destination.checkResourceIsReachable()) == true ? destination : destination.deletingLastPathComponent()
        guard let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, free >= 0 else { return nil }
        return UInt64(free)
    }

    /// A write's or a move's failure, by errno: a full volume, or anything else.
    package static func failure(_ code: Int32) -> Failure {
        code == ENOSPC || code == EDQUOT ? .noRoom : .cantSave(String(cString: strerror(code)))
    }
}
