import Foundation
import Security

/// Sill.app's identity store (docs/remote-access-plan.md §4.5): the Mac's key and trust list in the
/// login keychain.
///
/// The legacy file-based keychain, not the data-protection one: that needs a
/// `keychain-access-groups` entitlement and so a provisioning profile, which the bundle
/// make-app.sh signs has not got (Packaging/SillDebug.entitlements holds only get-task-allow).
/// Every item keeps the default access control, which trusts the app that made it by its
/// designated requirement. That requirement survives rebuilds signed with the same Apple
/// Development identity, as the TCC grants do, so a rebuilt Sill reads its identity without a
/// prompt (checked by hand in R0-b and R8, since no test may touch the login keychain).
///
/// - The key: a permanent P-256 private key, application tag `me.saffer.sill.remote.host-key`,
///   label "Sill Remote Access", looked up by its tag. Only the private key is stored; the public
///   one is derived from it.
/// - The recognition key: a generic password, service `me.saffer.sill.remote`, account
///   `recognition-key`, 32 bytes.
/// - The trust list: a generic password, same service, account `paired-devices`, JSON.
///
/// Only an item that does not exist yet is created. Any other failure to read one throws: a new
/// key would be a new Mac ID (every device's pin broken), and an empty list saved over an
/// unreadable one would forget every pairing. RemoteAccess then runs without an identity and the
/// pane says why.
package final class KeychainIdentityStore: IdentityStore {
    static let keyTag = Data("me.saffer.sill.remote.host-key".utf8)
    static let label = "Sill Remote Access"
    static let service = "me.saffer.sill.remote"
    static let recognitionAccount = "recognition-key"
    static let pairedAccount = "paired-devices"

    package init() {}

    package var summary: String { "in the login keychain" }
    package var testDirectory: URL? { nil }

    package func loadOrCreateKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Self.keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() {
            return item as! SecKey      // the type was just checked
        }
        guard status == errSecItemNotFound else { throw Self.error("the key couldn’t be read", status) }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Self.keyTag,
                kSecAttrLabel as String: Self.label,
            ] as [String: Any],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            let reason = error.map { "\($0.takeRetainedValue())" } ?? "no reason given"
            throw IdentityStoreError("no key could be made in the keychain (\(reason))")
        }
        return key
    }

    package func loadOrCreateRecognitionKey() throws -> Data {
        if let data = try read(Self.recognitionAccount) {
            guard data.count == 32 else { throw IdentityStoreError("the recognition key in the keychain is damaged") }
            return data
        }
        let data = try MemoryIdentityStore.randomBytes(32)
        try write(data, account: Self.recognitionAccount, label: "\(Self.label) (recognition key)")
        return data
    }

    package func loadPaired() throws -> [PairedDevice] {
        guard let data = try read(Self.pairedAccount) else { return [] }
        guard let list = try? JSONDecoder().decode([PairedDevice].self, from: data) else {
            throw IdentityStoreError("the paired devices in the keychain are damaged")
        }
        return list
    }

    package func savePaired(_ devices: [PairedDevice]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(try encoder.encode(devices), account: Self.pairedAccount, label: "\(Self.label) (paired devices)")
    }

    // MARK: Generic passwords

    /// The item's bytes, or nil when it does not exist yet; anything else throws (see the type).
    private func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw Self.error("\(account) couldn’t be read", status) }
        return data
    }

    /// Replaces the item's bytes, or adds it.
    private func write(_ data: Data, account: String, label: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Self.error("\(account) couldn’t be saved", updated) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = label
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Self.error("\(account) couldn’t be saved", added) }
    }

    private static func error(_ what: String, _ status: OSStatus) -> IdentityStoreError {
        let message = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "error \(status)"
        return IdentityStoreError("\(what): \(message)")
    }
}
