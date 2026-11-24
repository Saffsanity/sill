import Foundation
import StreamProtocol

/// Selects a saved Mac. Addresses in links are looked up in the device's records.
enum ConnectionLink: Equatable {
    case macID(String)
    case address(ParsedAddress)

    enum Failure: Error, Equatable {
        case malformed
        case missing
        case ambiguous
        case needsPairing

        var message: String {
            switch self {
            case .malformed: return "This Sill connection link is invalid."
            case .missing: return "This Mac isn’t saved on this device. Pair it in Sill first."
            case .ambiguous: return "More than one saved Mac uses this address. Copy a link from the Mac’s tile or row in Sill."
            case .needsPairing: return "Pair this Mac again in Sill, then open its connection link."
            }
        }
    }

    static func parse(_ url: URL) -> ConnectionLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "sill", parts.host?.lowercased() == "connect",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let items = parts.queryItems, items.count == 1, let value = items[0].value else { return nil }

        switch items[0].name {
        case "mac":
            guard value.utf8.allSatisfy({ $0 < 128 }) else { return nil }
            let id = value.uppercased()
            return MacID.isWellFormed(id) ? .macID(id) : nil
        case "address":
            guard case .success(let address) = AddressParser.parse(value) else { return nil }
            return .address(address)
        default: return nil
        }
    }

    static func url(for macID: String) -> URL? {
        guard MacID.isWellFormed(macID) else { return nil }
        return URL(string: "sill://connect?mac=\(macID)")
    }

    func target(in savedMacs: [SavedMac]) -> Result<SavedMac, Failure> {
        let matches: [SavedMac]
        switch self {
        case .macID(let id):
            matches = savedMacs.filter { $0.macID == id }
        case .address(let address):
            matches = savedMacs.filter { mac in
                mac.allAddresses.contains { stored in
                    guard case .success(let parsed) = AddressParser.parse(stored.host),
                          parsed.host.lowercased() == address.host.lowercased() else { return false }
                    return address.port.map { $0 == (stored.port ?? mac.remotePort) } ?? true
                }
            }
        }
        guard let mac = matches.first else { return .failure(.missing) }
        guard matches.count == 1 else { return .failure(.ambiguous) }
        guard mac.revoked != true, mac.newKey != true, mac.fingerprintData != nil else { return .failure(.needsPairing) }
        return .success(mac)
    }
}
