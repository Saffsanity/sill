import Foundation
import Security
import StreamProtocol

/// This device's remote identity (docs/remote-access-plan.md §7.2): a P-256 key in the Keychain,
/// tag `me.saffer.sill.device-key`, readable only while the device is unlocked, never synced and
/// never in a backup (`WhenUnlockedThisDeviceOnly`), so a lost or restored device cannot use it.
/// Made at the first pairing; its certificate is rebuilt at each launch (the pin is the key).
/// The Keychain's answers mean what DeviceKeyPolicy says (SavedMacs.swift, pure, #140): a key is
/// made only when the Keychain says there is none, and used only once it gives that key back, so
/// a pairing is never made with a key the next launch would not find.
///
/// A software key: whether Network.framework can sign the TLS handshake with a Secure Enclave key
/// is R0-a, on a real device (open question 12). DEBUG `-SillDeviceKeySE 1` makes and uses a
/// Secure Enclave key under its own tag for that check; the simulator has no Secure Enclave.
///
/// Main thread, or the network queue once made: the identity is immutable and cached.
enum DeviceIdentity {
    static let tag = Data("me.saffer.sill.device-key".utf8)
    #if DEBUG
    static let secureEnclaveTag = Data("me.saffer.sill.device-key.se".utf8)
    static var usesSecureEnclave: Bool { UserDefaults.standard.bool(forKey: "SillDeviceKeySE") }
    #endif

    private static let lock = NSLock()
    private static var cached: RemoteIdentity?

    private static var currentTag: Data {
        #if DEBUG
        if usesSecureEnclave { return secureEnclaveTag }
        #endif
        return tag
    }

    /// The identity when this device has a key; nil before the first pairing, after a restore from
    /// a backup (the key does not travel), and while the Keychain cannot be read (the next call
    /// reads it again).
    static func existing() -> RemoteIdentity? {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        guard case (let key?, .found) = read(currentTag) else { return nil }
        cached = RemoteIdentity(privateKey: key)
        return cached
    }

    /// The identity, made now if the Keychain says this device has none (the first pairing). Any
    /// other failed read (the device locked, the Keychain refusing for a moment) throws, and never
    /// makes a second key under the tag: a later read would take either, and the Mac knows one
    /// (DeviceKeyPolicy.load). A key made now is used only once the Keychain gives it back
    /// (`makeKey`).
    static func loadOrCreate() throws -> RemoteIdentity {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let (stored, answer) = read(currentTag)
        let key: SecKey
        switch DeviceKeyPolicy.load(answer) {
        case .use:
            guard let stored else { throw IdentityError("the Keychain gave back no key") }
            key = stored
        case .make:
            key = try makeKey()
            #if DEBUG
            print("device key: made \(SPKI.fingerprint(of: key).map(RemoteIdentity.shortName) ?? "?")…, given back by the Keychain")
            #endif
        case .fail(let status):
            #if DEBUG
            print("device key: the Keychain didn’t answer (\(status)); no new key made")
            #endif
            throw IdentityError("the Keychain didn’t answer: \(status)")
        }
        guard let id = RemoteIdentity(privateKey: key) else { throw IdentityError("the key couldn’t make a certificate") }
        cached = id
        return id
    }

    /// True only when the Keychain says, for every tag this build uses, that there is no key
    /// (errSecItemNotFound): a restore from a backup, where the key did not travel. Any other
    /// answer (the Keychain not readable yet, a DEBUG run with the Secure Enclave key under its
    /// own tag, which found none and made the real pairings look keyless) is not proof, and
    /// clearing the saved Macs on it would lose pairings the key still serves
    /// (DeviceKeyPolicy.clearsSavedMacs).
    static func knownMissing() -> Bool {
        var tags = [tag]
        #if DEBUG
        tags.append(secureEnclaveTag)
        #endif
        return DeviceKeyPolicy.clearsSavedMacs(tags.map { answer(SecItemCopyMatching(keyQuery($0) as CFDictionary, nil)) })
    }

    /// Forgets the key (`-SillForgetMacs 1`).
    static func forget() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
        let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrApplicationTag as String: currentTag]
        SecItemDelete(query as CFDictionary)
    }

    struct IdentityError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private static func keyQuery(_ tag: Data) -> [String: Any] {
        [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
    }

    /// A Keychain status as DeviceKeyPolicy reads it.
    private static func answer(_ status: OSStatus) -> DeviceKeyPolicy.Answer {
        switch status {
        case errSecSuccess: return .found
        case errSecItemNotFound: return .notFound
        default: return .failed(status)
        }
    }

    /// The key under `tag` and the Keychain's answer.
    private static func read(_ tag: Data) -> (SecKey?, DeviceKeyPolicy.Answer) {
        var query = keyQuery(tag)
        query[kSecReturnRef as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return (nil, answer(status)) }
        guard let item, CFGetTypeID(item) == SecKeyGetTypeID() else { return (nil, .failed(errSecInvalidItemRef)) }
        return ((item as! SecKey), .found)      // the type was just checked
    }

    /// Whether the Keychain gives back `key` under the current tag, by the query the next launch
    /// makes, among every key under it (one an older build put there beside it does not hide it).
    private static func readBack(_ key: SecKey) -> DeviceKeyPolicy.Answer {
        var query = keyQuery(currentTag)
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnRef as String] = true
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess else { return answer(status) }
        guard let want = SPKI.fingerprint(of: key) else { return .notFound }
        let keys = ((items as? [AnyObject]) ?? []).filter { CFGetTypeID($0) == SecKeyGetTypeID() }.map { $0 as! SecKey }
        return keys.contains { SPKI.fingerprint(of: $0) == want } ? .found : .notFound
    }

    /// The one explicit add of a key made now that the Keychain did not give back.
    private static func add(_ key: SecKey) -> OSStatus {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: currentTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueRef as String: key,
        ]
        #if DEBUG
        if usesSecureEnclave { attributes.removeValue(forKey: kSecAttrAccessible as String) }   // its token holds its access control
        #endif
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// A new key, kept in the Keychain and given back by it (DeviceKeyPolicy.made): one the next
    /// launch would not find would pair this launch alone, then the launch clears the saved Mac,
    /// and the Mac lists this device once more at every pairing (#140).
    private static func makeKey() throws -> SecKey {
        var privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: currentTag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        #if DEBUG
        if usesSecureEnclave {
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, nil) else {
                throw IdentityError("no Secure Enclave access control")
            }
            privateAttributes.removeValue(forKey: kSecAttrAccessible as String)
            privateAttributes[kSecAttrAccessControl as String] = access
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }
        #endif
        attributes[kSecPrivateKeyAttrs as String] = privateAttributes
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw IdentityError("no key could be made (\(error.map { "\($0.takeRetainedValue())" } ?? "no reason given"))")
        }
        var added: Int32?
        for _ in 0..<2 {      // DeviceKeyPolicy.made: the read-back, at most one add, the read-back again
            switch DeviceKeyPolicy.made(readBack: readBack(key), added: added) {
            case .use: return key
            case .add:
                added = add(key)
                #if DEBUG
                print("device key: not given back once made; added by itself: \(added ?? 0)")
                #endif
            case .fail(let status):
                #if DEBUG
                print("device key: the Keychain didn’t keep it (\(status)); the pairing fails")
                #endif
                // Deleted again by its reference where it was kept after all, so it never turns up
                // beside a key a pairing used.
                SecItemDelete([kSecClass as String: kSecClassKey, kSecValueRef as String: key] as CFDictionary)
                throw IdentityError("the Keychain didn’t keep it: \(status)")
            }
        }
        throw IdentityError("the Keychain didn’t keep it")
    }
}
