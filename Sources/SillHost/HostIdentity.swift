import Foundation
import Security
import Network
import StreamProtocol

/// A paired device as the trust list stores it (docs/remote-access-plan.md §4.5). Display-only
/// data (when it last connected, and how) is kept elsewhere; this record is what trust rests on.
package struct PairedDevice: Codable, Hashable, Sendable {
    /// base64url of the SHA-256 of its SubjectPublicKeyInfo: the pin.
    package var fingerprint: String
    /// Its own name, cleaned (SafeText): "iPad".
    package var name: String
    /// "iPad14,1".
    package var model: String?
    /// Seconds since 1970.
    package var pairedAt: Double
    /// "qr" or "code" (M5 adds "icloud"): how it was trusted.
    package var method: String

    package init(fingerprint: String, name: String, model: String?, pairedAt: Double, method: String) {
        self.fingerprint = fingerprint; self.name = name; self.model = model; self.pairedAt = pairedAt; self.method = method
    }

    /// "iPad (iPad14,1)", or the name alone.
    package var displayName: String {
        guard let model, !model.isEmpty else { return name.isEmpty ? "a device" : name }
        return "\(name.isEmpty ? "Device" : name) (\(model))"
    }

    /// The fingerprint's raw bytes; nil for a damaged record, which then trusts nothing.
    package var fingerprintData: Data? { Base64URL.decode(fingerprint).flatMap { $0.count == 32 ? $0 : nil } }
}

/// The Mac's remote identity: its P-256 key, the certificate rebuilt from it at every launch, its
/// fingerprint and Mac ID, the TLS identity both doors present, and the recognition key that makes
/// the Bonjour TXT tag. Immutable once loaded, so any queue may read it.
package final class HostIdentity: @unchecked Sendable {
    package let remote: RemoteIdentity
    package let macID: String
    /// 32 random bytes kept with the key; sent only in kind 20 ok (`PairResult.recognitionKey`).
    package let recognitionKey: Data

    package var fingerprint: Data { remote.fingerprint }

    package init?(privateKey: SecKey, recognitionKey: Data) {
        guard recognitionKey.count == 32, let remote = RemoteIdentity(privateKey: privateKey) else { return nil }
        self.remote = remote
        self.recognitionKey = recognitionKey
        macID = MacID.make(fingerprint: remote.fingerprint)
    }

    /// Kind 18's signature over `info` (SecKeyCreateSignature, ECDSA P-256 / SHA-256).
    package func sign(_ info: MacInfo) -> SignedMacInfo? {
        SignedMacInfo.signing(info, with: remote.privateKey)
    }

    /// A fresh TXT record for one Bonjour registration: `r` = a new tag.
    package func txtRecord() -> NWTXTRecord? {
        RecognitionTag.make(recognitionKey: recognitionKey).map { NWTXTRecord([RecognitionTag.txtKey: $0]) }
    }
}

/// Where the Mac's identity and its trust list live. Three backends: the login keychain
/// (Sill.app), memory (SillHost --remote: nothing outlives the process) and, TEST ONLY, a 0700
/// directory (SILL_TEST_REMOTE_DIR on a host that does not advertise). The trust list never lives
/// in UserDefaults or a plist: any process of the same user can edit those, add its own key, and
/// then use Sill's Screen Recording and Accessibility grants.
package protocol IdentityStore: AnyObject {
    /// For the log: "in memory", "in the test directory …".
    var summary: String { get }
    /// The Mac's P-256 private key, created on first use. Only a key that does not exist yet is
    /// created: any other failure to read one throws, since a new key is a new Mac ID and breaks
    /// every pin.
    func loadOrCreateKey() throws -> SecKey
    /// 32 random bytes, created on first use (the same rule).
    func loadOrCreateRecognitionKey() throws -> Data
    /// The trust list: empty only when none was ever saved. One that cannot be read throws, or the
    /// next save would replace it.
    func loadPaired() throws -> [PairedDevice]
    func savePaired(_ devices: [PairedDevice]) throws
    /// TEST ONLY: a directory where a test hook may leave the current pairing link and code (the
    /// file store's own, 0700); nil for every other store.
    var testDirectory: URL? { get }
}

package struct IdentityStoreError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
}

/// SillHost --remote: a new identity and an empty trust list every run.
package final class MemoryIdentityStore: IdentityStore {
    private var key: SecKey?
    private var recognition: Data?
    private var paired: [PairedDevice] = []

    package init() {}

    package var summary: String { "in memory" }
    package var testDirectory: URL? { nil }

    package func loadOrCreateKey() throws -> SecKey {
        if let key { return key }
        guard let k = RemoteKey.generate() else { throw IdentityStoreError("no P-256 key could be made") }
        key = k
        return k
    }

    package func loadOrCreateRecognitionKey() throws -> Data {
        if let recognition { return recognition }
        let r = try Self.randomBytes(32)
        recognition = r
        return r
    }

    package func loadPaired() throws -> [PairedDevice] { paired }
    package func savePaired(_ devices: [PairedDevice]) throws { paired = devices }

    static func randomBytes(_ n: Int) throws -> Data {
        var b = [UInt8](repeating: 0, count: n)
        guard SecRandomCopyBytes(kSecRandomDefault, n, &b) == errSecSuccess else { throw IdentityStoreError("the random source failed") }
        return Data(b)
    }
}

/// TEST ONLY (SILL_TEST_REMOTE_DIR=<dir>, honoured only by a host that does not advertise): the
/// identity and trust list in a directory of mode 0700, each file 0600, so a test can pair, restart
/// the host and find the same Mac ID and pairings, without the login keychain.
/// Files: `host-key` (the private key, X9.63), `recognition-key` (32 bytes), `paired.json`, and
/// `.lock`, which one host holds for as long as it uses the directory: two hosts sharing it would
/// each save their own list over the other's.
package final class FileIdentityStore: IdentityStore {
    package let directory: URL
    /// The open `.lock`, flock'ed exclusively; closing it (or the process ending) lets it go.
    private let lock: Int32

    package init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent(".lock").path
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw IdentityStoreError("\(path) could not be opened (errno \(errno))") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw IdentityStoreError("\(directory.path) is in use by another Sill host")
        }
        lock = fd
    }

    deinit { close(lock) }

    package var summary: String { "in the test directory \(directory.path)" }
    package var testDirectory: URL? { directory }

    package func loadOrCreateKey() throws -> SecKey {
        let url = directory.appendingPathComponent("host-key")
        if let data = try Self.read(url) {
            guard let key = RemoteKey.importPrivate(data) else { throw IdentityStoreError("\(url.path) is not a P-256 key") }
            return key
        }
        guard let key = RemoteKey.generate(), let data = RemoteKey.export(key) else { throw IdentityStoreError("no P-256 key could be made") }
        try Self.writePrivate(data, to: url)
        return key
    }

    package func loadOrCreateRecognitionKey() throws -> Data {
        let url = directory.appendingPathComponent("recognition-key")
        if let data = try Self.read(url) {
            guard data.count == 32 else { throw IdentityStoreError("\(url.path) is not 32 bytes") }
            return data
        }
        let data = try MemoryIdentityStore.randomBytes(32)
        try Self.writePrivate(data, to: url)
        return data
    }

    package func loadPaired() throws -> [PairedDevice] {
        let url = directory.appendingPathComponent("paired.json")
        guard let data = try Self.read(url) else { return [] }
        guard let list = try? JSONDecoder().decode([PairedDevice].self, from: data) else { throw IdentityStoreError("\(url.path) is damaged") }
        return list
    }

    /// The file's bytes, or nil when it does not exist yet. Anything else (no permission, an I/O
    /// error) throws: taken for "missing", it would make a new key (a new Mac ID, every pin broken)
    /// or an empty trust list that the next pairing saves over the real one.
    private static func read(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw IdentityStoreError("\(url.path) could not be read (\(error.localizedDescription))")
        }
    }

    package func savePaired(_ devices: [PairedDevice]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Self.writePrivate(try encoder.encode(devices), to: directory.appendingPathComponent("paired.json"))
    }

    /// Writes `data` with mode 0600 from its creation, replacing the file atomically.
    static func writePrivate(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        try? FileManager.default.removeItem(at: tmp)
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw IdentityStoreError("could not write \(tmp.path)")
        }
        guard rename(tmp.path, url.path) == 0 else { throw IdentityStoreError("could not replace \(url.path)") }
    }
}

/// What the remote door's verify block and admission read on the network queue: immutable,
/// replaced whole under a lock on every change. Nothing that reads it ever waits on the main actor.
struct TrustSnapshot: Sendable {
    /// Paired fingerprints → display names ("iPad (iPad14,1)").
    var paired: [Data: String] = [:]
    var pairingOpen = false
    var remoteAccess = false
    var internetAccess = false
    /// Interface → network service name ("utun4" → "Tailscale"), for a session's route label.
    var serviceNames: [String: String] = [:]
}

/// The lock around the current TrustSnapshot.
final class TrustBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = TrustSnapshot()

    var snapshot: TrustSnapshot {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func update(_ change: (inout TrustSnapshot) -> Void) {
        lock.lock(); change(&value); lock.unlock()
    }
}
