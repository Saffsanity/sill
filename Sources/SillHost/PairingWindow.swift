import Foundation
import CryptoKit
import StreamProtocol

/// One pairing window's rules (docs/remote-access-plan.md §4.6): open for 5 minutes, for one
/// device, with at most five wrong proofs, spaced out so nobody can hammer it. Pure (no clock, no
/// I/O: `now` is passed in), so it is checked on its own with swiftc. RemoteAccess owns one on
/// the main actor.
struct PairingWindow {
    enum CloseReason: String, Sendable {
        /// A device paired with it.
        case used
        /// Its 5 minutes ran out (noticed at the next attempt, or by the owner's timer).
        case expired
        /// Five wrong proofs.
        case stopped
        /// The Mac's user closed it, or Remote Access went off.
        case cancelled
        /// No window was ever opened.
        case none
    }

    struct Open {
        /// The QR path's key (16 bytes).
        let secret: Data
        /// The typed path's 12 digits.
        let code: String
        /// K from the code (PBKDF2, ~0.1 s, derived off the main actor); nil until then.
        var codeKey: SymmetricKey?
        let expiresAt: Double
        var failures = 0
        var nextAllowedAt: Double = 0
        var lastAttemptBySource: [String: Double] = [:]
        let requestedBy: String?
        var lastWrongFrom: String?
    }

    enum State {
        case closed(CloseReason)
        case open(Open)
    }

    enum Verdict: Equatable {
        /// The proof holds: send proof_M. The window is now closed (used).
        case accept(proofM: Data)
        /// A wrong proof; this many are still taken.
        case reject(triesLeft: Int)
        /// Not now: too soon after a wrong one, the same source within 5 s, or a typed code
        /// before its key is ready. Nothing counted.
        case busy(retryAfter: Double)
        /// No window, or it just closed (expired, or stopped by this very proof, the fifth wrong one).
        case closed(CloseReason)
    }

    static let lifetime: Double = 300
    static let maxFailures = 5
    /// The same source may try once per this many seconds.
    static let sourceSpacing: Double = 5
    /// After the 1st, 2nd, 3rd and 4th wrong proof, the next is taken 1, 2, 4, then 8 s later.
    static let spacing: [Double] = [1, 2, 4, 8]

    private(set) var state: State = .closed(.none)

    var isOpen: Bool { if case .open = state { return true }; return false }
    var current: Open? { if case .open(let w) = state { return w }; return nil }
    var closeReason: CloseReason? { if case .closed(let r) = state { return r }; return nil }

    /// Opens a fresh window (a new secret and code), replacing any other.
    mutating func open(secret: Data, code: String, now: Double, lifetime: Double = Self.lifetime, requestedBy: String?) {
        state = .open(Open(secret: secret, code: code, expiresAt: now + lifetime, requestedBy: requestedBy))
    }

    /// K for `code`, once derived; ignored when the window has moved on to another code.
    mutating func setCodeKey(_ key: SymmetricKey, code: String) {
        guard case .open(var w) = state, w.code == code else { return }
        w.codeKey = key
        state = .open(w)
    }

    mutating func close(_ reason: CloseReason) {
        guard isOpen else { return }
        state = .closed(reason)
    }

    /// Closes it as expired when its time is up. Whether it did.
    mutating func expireIfDue(now: Double) -> Bool {
        guard case .open(let w) = state, now >= w.expiresAt else { return false }
        state = .closed(.expired)
        return true
    }

    /// Judges one PairRequest's proof. `fpDevice` and `fpMac` are the two keys of the TLS session
    /// it arrived on, never anything the message says; `source` is the connection's address.
    mutating func tryProof(method: String, proof: Data, fpDevice: Data, fpMac: Data, source: String, now: Double) -> Verdict {
        guard case .open(var w) = state else { return .closed(closeReason ?? .none) }
        if now >= w.expiresAt {
            state = .closed(.expired)
            return .closed(.expired)
        }
        if now < w.nextAllowedAt { return .busy(retryAfter: w.nextAllowedAt - now) }
        if let last = w.lastAttemptBySource[source], now - last < Self.sourceSpacing {
            return .busy(retryAfter: Self.sourceSpacing - (now - last))
        }
        let key: SymmetricKey?
        switch method {
        case PairRequest.qr: key = PairingProof.qrKey(secret: w.secret)
        case PairRequest.code:
            guard let k = w.codeKey else { return .busy(retryAfter: 1) }
            key = k
        default: key = nil          // an unknown method never matches: a wrong proof
        }
        w.lastAttemptBySource[source] = now
        if let key, PairingProof.isValidDeviceProof(proof, key: key, deviceFingerprint: fpDevice, macFingerprint: fpMac) {
            state = .closed(.used)
            return .accept(proofM: PairingProof.macProof(key: key, macFingerprint: fpMac, deviceFingerprint: fpDevice))
        }
        w.failures += 1
        w.lastWrongFrom = source
        if w.failures >= Self.maxFailures {
            state = .closed(.stopped)
            return .closed(.stopped)
        }
        w.nextAllowedAt = now + Self.spacing[min(w.failures - 1, Self.spacing.count - 1)]
        state = .open(w)
        return .reject(triesLeft: Self.maxFailures - w.failures)
    }
}
