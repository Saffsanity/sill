// Package relay dials out to a headfwd-compatible relay so a Headscale behind
// NAT can be reached from anywhere.
//
// The relay is UNTRUSTED. It only ever sees sealed TS2021/WireGuard bytes, and
// what makes that safe is client-side key pinning (see the control shim in
// packages/tailnet-client). A relay compromise costs availability, not
// confidentiality. See docs/tailnet-threat-model.md.
//
// Wire-compatible with github.com/pastudan/headfwd at registration protocol v2,
// so bridgeproxy.net and headfwd.net are interchangeable and each can be the
// other's fallback. The crypto below MUST match
// headfwd-proxy-fly/registration_crypto.go byte for byte.
package relay

import (
	"crypto/hkdf"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
)

// ProtocolVersion is the registration protocol this client speaks.
//
// v1 used the raw X25519 ECDH output directly as an HMAC key over the bare
// nonce. An ECDH output is a curve point with algebraic structure rather than
// uniform keying material, the same long-term Noise static key is reused across
// protocols (so a chosen-input MAC oracle is a cross-protocol risk), and the MAC
// covered only the nonce — a valid proof was not bound to the registration it
// authorised. v2 fixes all three.
const ProtocolVersion = 2

// hkdfInfo domain-separates this derivation. Changing it breaks the protocol.
const hkdfInfo = "headfwd registration proof v2"

// deriveProofKey turns a raw ECDH shared secret into a uniform MAC key, salted
// with the relay's single-use nonce.
func deriveProofKey(sharedSecret []byte, nonce string) ([]byte, error) {
	return hkdf.Key(sha256.New, sharedSecret, []byte(nonce), hkdfInfo, 32)
}

// registrationProof computes the v2 proof over the full registration transcript.
func registrationProof(sharedSecret []byte, fingerprint, publicKey, nonce, ephemeralPubHex string) (string, error) {
	key, err := deriveProofKey(sharedSecret, nonce)
	if err != nil {
		return "", err
	}
	h := hmac.New(sha256.New, key)
	h.Write(transcript(fingerprint, publicKey, nonce, ephemeralPubHex))
	return hex.EncodeToString(h.Sum(nil)), nil
}

// transcript serialises the registration context unambiguously. Fields are
// length-prefixed so ("ab","c") and ("a","bc") cannot serialise identically.
func transcript(fingerprint, publicKey, nonce, ephemeralPubHex string) []byte {
	var buf []byte
	appendField := func(s string) {
		var n [4]byte
		l := len(s)
		n[0] = byte(l >> 24)
		n[1] = byte(l >> 16)
		n[2] = byte(l >> 8)
		n[3] = byte(l)
		buf = append(buf, n[:]...)
		buf = append(buf, s...)
	}
	appendField(hkdfInfo)
	appendField(fingerprint)
	appendField(publicKey)
	appendField(nonce)
	appendField(ephemeralPubHex)
	return buf
}

// Fingerprint hashes the control plane's public key AS TEXT, including its
// "mkey:" prefix, and truncates to 128 bits.
//
// This is computed independently of the proof, which is why the HKDF change was
// not a breaking one: subdomains, pinned keys and issued invites are all
// unaffected by anything above.
func Fingerprint(publicKey string) string {
	sum := sha256.Sum256([]byte(publicKey))
	return hex.EncodeToString(sum[:])[:32]
}
