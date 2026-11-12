import Foundation
import Security

/// Where Automatically update Sill keeps its switch and what it remembers (UpdateAutoPolicy.Memory): one
/// generic-password item in Sill's own keychain group, in the data-protection keychain, readable after the
/// first unlock, never synchronized and never off this Mac. Only code signed with Sill's team and holding
/// that group (a release Sill.app with its provisioning profile) can read, add or change it: `defaults
/// write`, a launch argument, the CLI and a device's settings change have no path to it, and no other
/// process of this user can put an item there for Sill to find (review 3, the automatic update's point 2).
/// Settings › General's switch is the only code that turns it on (AppUpdater.setAutomaticUpdate).
///
/// Without the group (every development and ad hoc build, the bare binary) nothing is read or written, and
/// the switch can't be turned on. A failed write leaves the switch as it was; what makes Sill do less by
/// itself (an attempt counted, a stop) holds for this launch even when it can't be written.
@MainActor
final class AutoUpdateStore {
    static let service = "me.saffer.sill.update"
    static let account = "automatic"

    let accessGroup: String?
    private(set) var memory = UpdateAutoPolicy.Memory()
    /// The last read's or write's failure, for the log; nil when it worked.
    private(set) var problem: String?

    /// The group can hold the switch.
    var canKeep: Bool { accessGroup != nil }

    init(accessGroup: String?) {
        self.accessGroup = accessGroup
        guard let accessGroup else { return }
        memory = read(group: accessGroup) ?? UpdateAutoPolicy.Memory()
    }

    /// Changes what is remembered. The switch turns on only when the item could be written.
    func update(_ change: (UpdateAutoPolicy.Memory) -> UpdateAutoPolicy.Memory) {
        let next = change(memory)
        guard next != memory else { return }
        if let group = accessGroup, write(next, group: group) {
            memory = next
            return
        }
        var held = next
        if next.on && !memory.on { held.on = false }
        memory = held
    }

    private func query(group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: Self.account,
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrAccessGroup as String: group]
    }

    /// The item's memory; nil when there is none or it can't be read (the switch then reads off).
    private func read(group: String) -> UpdateAutoPolicy.Memory? {
        var q = query(group: group)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { problem = nil; return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count <= 64 << 10 else {
            problem = Self.text(status)
            return nil
        }
        guard let memory = try? JSONDecoder().decode(UpdateAutoPolicy.Memory.self, from: data) else {
            problem = "the item isn’t what Sill writes"
            return nil
        }
        problem = nil
        return memory
    }

    private func write(_ memory: UpdateAutoPolicy.Memory, group: String) -> Bool {
        guard let data = try? JSONEncoder().encode(memory) else { problem = "it couldn’t be encoded"; return false }
        let q = query(group: group)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Sill Automatic Update"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { problem = Self.text(status); return false }
        problem = nil
        return true
    }

    private static func text(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "error \(status)"
    }
}
