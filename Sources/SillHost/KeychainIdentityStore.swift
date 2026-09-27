import Foundation
import Security

/// Sill.app's identity store (docs/remote-access-plan.md §4.5, docs/keychain-plan.md): the Mac's key
/// and trust list in a keychain, in one of two keychains chosen at launch.
///
/// - **Legacy (`accessGroup` nil):** the file-based login keychain, as remote access first shipped.
///   Every item keeps the default access control, which trusts the app that made it by its
///   designated requirement, and that requirement survives rebuilds signed with the same identity,
///   as the TCC grants do. But the login keychain **does not authenticate who made an item**: any
///   process of this user can create an item first, list Sill among the apps allowed to read it, and
///   Sill then adopts it (the security review, 2026-09-27). So this store is used only where the
///   strong keychain is out of reach — a development build, or a release with no embedded
///   provisioning profile — and never by an entitled Sill.app.
/// - **Data-protection (`accessGroup` set, e.g. `9B2KKVM937.me.saffer.sill.mac`):** the
///   data-protection keychain under that access group. Only a process signed by the same team and
///   entitled to that group can create or read the items, so no other process can pre-create or read
///   them: the pre-creation hole is closed, and the key becomes unreadable to other apps as a bonus.
///   Reaching this keychain needs the `keychain-access-groups` entitlement, hence a provisioning
///   profile embedded in the build (Scripts/make-app.sh --release, docs/release-checklist.md);
///   IdentityStorePlan picks it only when the running binary actually holds the entitlement.
///
/// The items, in either keychain:
/// - The key: a permanent P-256 private key, application tag `me.saffer.sill.remote.host-key`,
///   label "Sill Remote Access", looked up by its tag. Only the private key is stored; the public
///   one is derived from it.
/// - The recognition key: a generic password, service `me.saffer.sill.remote`, account
///   `recognition-key`, 32 bytes.
/// - The trust list: a generic password, same service, account `paired-devices`, JSON.
/// - Require pairing: a generic password, same service, account `require-pairing`: "1", or "0."
///   and a signature by the Mac's key (RequirePairingValue, docs/home-pairing-plan.md §4.8). A
///   missing item, or one without that signature, reads as on, so deleting it only turns pairing on.
///
/// **Adoption (migration), data-protection mode only.** A Mac that already ran a legacy-store build
/// (remote access on 0.3.x, or a development Sill) keeps its identity in the login keychain. On the
/// first launch of an entitled build, each item missing from the data-protection keychain is copied
/// from the login keychain if it is there, so the Mac ID (from the key's fingerprint) and every
/// pairing survive the update; after that the item lives in the data-protection keychain and the
/// login keychain is never consulted again. Adoption carries forward exactly the identity Sill was
/// already using on that Mac — no new exposure for an upgrader — while a fresh install (nothing to
/// adopt) gets a fresh key straight in the strong keychain, where the pre-creation guarantee is
/// whole. Landing this before the first public build keeps adoption to Noah's own Macs
/// (docs/keychain-plan.md §6).
///
/// Only an item that does not exist yet (in this keychain, and, in data-protection mode, not in the
/// login keychain either) is created. Any other failure to read one throws: a new key would be a new
/// Mac ID (every device's pin broken), and an empty list saved over an unreadable one would forget
/// every pairing. RemoteAccess then runs without an identity and the pane says why.
package final class KeychainIdentityStore: IdentityStore {
    static let keyTag = Data("me.saffer.sill.remote.host-key".utf8)
    static let label = "Sill Remote Access"
    static let service = "me.saffer.sill.remote"
    static let recognitionAccount = "recognition-key"
    static let pairedAccount = "paired-devices"
    static let requirePairingAccount = "require-pairing"

    /// The data-protection access group, or nil for the legacy login keychain. Immutable.
    let accessGroup: String?
    private var dataProtection: Bool { accessGroup != nil }

    /// `accessGroup` nil is the legacy login keychain; a group name is the data-protection keychain.
    package init(accessGroup: String? = nil) { self.accessGroup = accessGroup }

    package var summary: String {
        guard let accessGroup else { return "in the login keychain" }
        return "in the data-protection keychain (\(accessGroup))"
    }
    package var testDirectory: URL? { nil }

    /// The keychain-selecting attributes added to every query: the data-protection flag and access
    /// group when this store is the strong one, nothing for the legacy store.
    private func scope() -> [String: Any] {
        guard let accessGroup else { return [:] }
        return [kSecUseDataProtectionKeychain as String: true, kSecAttrAccessGroup as String: accessGroup]
    }

    package func loadOrCreateKey() throws -> SecKey {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Self.keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true,
        ]
        query.merge(scope()) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() {
            return item as! SecKey      // the type was just checked
        }
        guard status == errSecItemNotFound else { throw Self.error("the key couldn’t be read", status) }
        // Data-protection mode: adopt the login keychain's key (same material, so the same Mac ID)
        // before making a fresh one, so an update keeps this Mac's identity and every pairing.
        if dataProtection, let adopted = try adoptLegacyKey() { return adopted }
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Self.keyTag,
                kSecAttrLabel as String: Self.label,
            ] as [String: Any],
        ]
        if let accessGroup {
            // For SecKeyCreateRandomKey the data-protection flag and access group go inside the
            // private-key attributes, beside kSecAttrIsPermanent, so the stored key lands in the
            // data-protection keychain under the group.
            var priv = attributes[kSecPrivateKeyAttrs as String] as! [String: Any]
            priv[kSecAttrAccessGroup as String] = accessGroup
            priv[kSecUseDataProtectionKeychain as String] = true
            attributes[kSecPrivateKeyAttrs as String] = priv
        }
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
        guard let data = try read(Self.pairedAccount) else {
            // None saved yet: made now, empty, so the item is Sill's own from here on (see the type).
            // A write that fails changes nothing: the list is empty either way.
            try? savePaired([])
            return []
        }
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

    package func loadRequirePairing() throws -> Data? {
        try read(Self.requirePairingAccount)
    }

    package func saveRequirePairing(_ record: Data) throws {
        try write(record, account: Self.requirePairingAccount, label: "\(Self.label) (require pairing)")
    }

    // MARK: Generic passwords

    /// The item's bytes, or nil when it does not exist yet; anything else throws (see the type). In
    /// data-protection mode a miss first tries the login keychain and, finding the item there, copies
    /// it in (adoption) before reporting nil, so an update keeps the recognition key, the trust list
    /// and Require pairing.
    private func read(_ account: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        query.merge(scope()) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return data }
        guard status == errSecItemNotFound else { throw Self.error("\(account) couldn’t be read", status) }
        if dataProtection, let adopted = try adoptLegacyGeneric(account) { return adopted }
        return nil
    }

    /// Replaces the item's bytes, or adds it (in this store's keychain).
    private func write(_ data: Data, account: String, label: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        query.merge(scope()) { _, new in new }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Self.error("\(account) couldn’t be saved", updated) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = label
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Self.error("\(account) couldn’t be saved", added) }
    }

    // MARK: Adoption from the login keychain (data-protection mode only)

    /// The login keychain's identity key, exported and re-imported into the data-protection keychain
    /// under this store's access group, or nil when the login keychain has none (a fresh install).
    /// The re-imported key has the same material, so the same fingerprint and Mac ID. A key found but
    /// not copyable throws, rather than fall through to a fresh key and a new Mac ID.
    private func adoptLegacyKey() throws -> SecKey? {
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
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let item, CFGetTypeID(item) == SecKeyGetTypeID() else {
            throw Self.error("the login keychain’s key couldn’t be read for migration", status)
        }
        let legacyKey = item as! SecKey
        guard let material = SecKeyCopyExternalRepresentation(legacyKey, nil) as Data?,
              let group = accessGroup else {
            throw IdentityStoreError("the login keychain’s key couldn’t be exported for migration")
        }
        let importAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
        ]
        guard let imported = SecKeyCreateWithData(material as CFData, importAttrs as CFDictionary, nil) else {
            throw IdentityStoreError("the login keychain’s key couldn’t be re-imported for migration")
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: group,
            kSecAttrApplicationTag as String: Self.keyTag,
            kSecAttrLabel as String: Self.label,
            kSecValueRef as String: imported,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess || added == errSecDuplicateItem else {
            throw Self.error("the migrated key couldn’t be saved to the data-protection keychain", added)
        }
        print("Remote access: migrated the Mac’s identity key from the login keychain to the data-protection keychain (the Mac ID and paired devices are kept).")
        return imported
    }

    /// A generic-password item from the login keychain, copied into the data-protection keychain
    /// under this store's access group; nil when the login keychain has none. A copy that fails to
    /// save is ignored (the item is returned anyway): it is re-copied next launch, and unlike the key
    /// a lost recognition key or Require pairing does not change the Mac ID.
    private func adoptLegacyGeneric(_ account: String) throws -> Data? {
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
        guard status == errSecSuccess, let data = item as? Data else {
            throw Self.error("\(account) couldn’t be read from the login keychain for migration", status)
        }
        try? write(data, account: account, label: "\(Self.label) (\(account))")
        return data
    }

    private static func error(_ what: String, _ status: OSStatus) -> IdentityStoreError {
        let message = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "error \(status)"
        return IdentityStoreError("\(what): \(message)")
    }
}
