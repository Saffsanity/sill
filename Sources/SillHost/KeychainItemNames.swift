import Foundation

/// Query identities, separate from access-group scoping. Keeping the defaults
/// stable preserves existing Sill pairings; embedders never query those items.
struct KeychainItemNames: Equatable {
    let keyTag: Data
    let service: String

    init(namespace: String? = nil) {
        let prefix = namespace.map { $0 + ".sill.remote" } ?? "me.saffer.sill.remote"
        service = prefix
        keyTag = Data((prefix + ".host-key").utf8)
    }
}
