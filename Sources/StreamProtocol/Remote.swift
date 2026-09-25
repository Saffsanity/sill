import Foundation
import Security
import CryptoKit

// Remote access payloads (kinds 18–22, docs/remote-access-plan.md §3.2). The rules of
// HostSettings.swift apply to every one of them: JSON only; fields added later are optional; no
// enums on the wire (strings, so an unknown value is skipped instead of failing the whole decode);
// never rename or retype a field. The generation is in the ALPN (`sill/1`), `MacInfo.v`,
// `PairRequest.v` and the pairing link's `v`.

/// One way to reach the Mac from afar. Plain values, never enums: an unknown case would fail an
/// older reader.
public struct MacAddress: Codable, Hashable, Sendable {
    /// "mac-mini.tail1234.ts.net", "100.101.102.103" or "fd7a:115c:a1e0::1234" (no brackets).
    public var host: String
    /// Nil: `MacInfo.remotePort`. Set only for an address name whose router forwards another
    /// outside port.
    public var port: Int?
    /// "vpn", "lan" or "internet".
    public var kind: String
    /// Where it comes from, as the Mac's pane names it: "Tailscale", "Wi‑Fi", "Router",
    /// "Address name", "IPv6", "VPN (utun6)", "This Mac" (test hosts).
    public var via: String

    public init(host: String, port: Int? = nil, kind: String, via: String) {
        self.host = host; self.port = port; self.kind = kind; self.via = via
    }

    public static let vpn = "vpn", lan = "lan", internet = "internet"
}

/// Inside kind 18: who this Mac is and how to reach it from afar. Nothing here is secret: whoever
/// can connect at all already shares a network with the Mac.
public struct MacInfo: Codable, Hashable, Sendable {
    /// 1.
    public var v: Int
    /// 16 Crockford characters, `MacID.make(fingerprint)`.
    public var macID: String
    /// The Mac's name (SafeText).
    public var name: String
    /// Seconds since 1970; a device takes only a newer one than it has.
    public var issuedAt: Double
    /// The Mac's Remote Access switch.
    public var remoteAccess: Bool
    /// The configured remote port, also while Remote Access is off (pairing uses it).
    public var remotePort: Int
    /// "Allow connections from the internet".
    public var internet: Bool
    /// In dial order; empty while Remote Access is off and no pairing window is open.
    public var addresses: [MacAddress]

    public init(v: Int = 1, macID: String, name: String, issuedAt: Double, remoteAccess: Bool, remotePort: Int,
                internet: Bool, addresses: [MacAddress]) {
        self.v = v; self.macID = macID; self.name = name; self.issuedAt = issuedAt
        self.remoteAccess = remoteAccess; self.remotePort = remotePort; self.internet = internet
        self.addresses = addresses
    }
}

/// Kind 18. `info` is the exact JSON bytes of a MacInfo and `sig` covers those bytes, so the
/// signature never depends on how either side would re-encode the JSON. Plain base64 (bulk).
public struct SignedMacInfo: Codable, Sendable {
    /// base64 of MacInfo's JSON bytes.
    public var info: String
    /// base64 of the Mac's public key, X9.63 (65 bytes).
    public var key: String
    /// base64 of a DER ECDSA P-256 / SHA-256 signature over the `info` bytes.
    public var sig: String

    public init(info: String, key: String, sig: String) {
        self.info = info; self.key = key; self.sig = sig
    }

    /// Signs `info` with the Mac's identity key (host side). Nil if the key cannot sign.
    public static func signing(_ info: MacInfo, with privateKey: SecKey) -> SignedMacInfo? {
        let bytes = Wire.encode(info)
        guard !bytes.isEmpty, let point = RemoteKey.publicPoint(privateKey),
              let sig = SecKeyCreateSignature(privateKey, .ecdsaSignatureMessageX962SHA256, bytes as CFData, nil) as Data?
        else { return nil }
        return SignedMacInfo(info: bytes.base64EncodedString(), key: point.base64EncodedString(), sig: sig.base64EncodedString())
    }

    /// The MacInfo and the fingerprint of the key that signed it, when the signature verifies over
    /// the exact `info` bytes, the key is a P-256 point, the JSON decodes and its `macID` is that
    /// key's Mac ID. A device that saved this Mac then also requires `fingerprint` to equal its pin
    /// and `issuedAt` to be newer than the one it has (SavedMacs, on the device).
    public func verified() -> (info: MacInfo, fingerprint: Data)? {
        guard let bytes = Data(base64Encoded: info), let point = Data(base64Encoded: key), point.count == 65,
              let sigData = Data(base64Encoded: sig),
              let publicKey = try? P256.Signing.PublicKey(x963Representation: point),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: sigData),
              publicKey.isValidSignature(signature, for: bytes),
              let decoded = Wire.decode(MacInfo.self, from: bytes) else { return nil }
        let fp = SPKI.fingerprint(point: point)
        guard decoded.macID == MacID.make(fingerprint: fp) else { return nil }
        return (decoded, fp)
    }

    /// The MacInfo without checking anything: for display on a device that has not paired with
    /// this Mac (its Away from home group). Never saved.
    public func unverifiedInfo() -> MacInfo? {
        Data(base64Encoded: info).flatMap { Wire.decode(MacInfo.self, from: $0) }
    }
}

/// Kind 19: the device's one message on a pairing connection.
public struct PairRequest: Codable, Sendable {
    /// 1.
    public var v: Int
    /// "qr" or "code".
    public var method: String
    /// base64url(proof_D) (PairingProof).
    public var proof: String
    /// "iPad"; the Mac applies SafeText.
    public var name: String
    /// "iPad14,1".
    public var model: String?

    public init(v: Int = 1, method: String, proof: String, name: String, model: String?) {
        self.v = v; self.method = method; self.proof = proof; self.name = name; self.model = model
    }

    public static let qr = "qr", code = "code"
}

/// Kind 20: the Mac's answer to kind 19. The Mac closes the connection after sending it.
public struct PairResult: Codable, Sendable {
    public var ok: Bool
    /// ok: base64url(proof_M), checked by the device before it saves anything.
    public var proof: String?
    /// ok: the Mac ID.
    public var macID: String?
    /// ok: the Mac's name.
    public var name: String?
    /// ok: base64url of 32 bytes that resolve the Mac's Bonjour TXT tag (RecognitionTag). Sent
    /// nowhere else.
    public var recognitionKey: String?
    /// Not ok: "code", "closed", "expired", "stopped" or "busy".
    public var reason: String?
    /// With "code": the wrong proofs the window still takes.
    public var triesLeft: Int?
    /// With "busy": seconds until the Mac takes another proof.
    public var retryAfter: Double?

    public init(ok: Bool, proof: String? = nil, macID: String? = nil, name: String? = nil, recognitionKey: String? = nil,
                reason: String? = nil, triesLeft: Int? = nil, retryAfter: Double? = nil) {
        self.ok = ok; self.proof = proof; self.macID = macID; self.name = name; self.recognitionKey = recognitionKey
        self.reason = reason; self.triesLeft = triesLeft; self.retryAfter = retryAfter
    }

    public static let code = "code", closed = "closed", expired = "expired", stopped = "stopped", busy = "busy"
}

/// Kind 22: why the host is about to close this session.
public struct Goodbye: Codable, Sendable {
    /// "removed", "remoteOff", "internetOff", "quit" or "busy".
    public var reason: String

    public init(reason: String) { self.reason = reason }

    public static let removed = "removed", remoteOff = "remoteOff", internetOff = "internetOff", quit = "quit", busy = "busy"
}
