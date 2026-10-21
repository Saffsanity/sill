// Package invite holds the control plane's fingerprint and the check that a
// served identity key matches it (ported from Bridge's invite package through
// Frigate Launcher). Sill gets the fingerprint over a paired, pinned session
// from the Mac itself (kind 60), never from a relay; the invite-key string
// format is kept, with its tests, for compatibility with HeadFwd's other
// clients.
package invite

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
)

const (
	// Version prefix. Anything else is rejected rather than guessed at, so the
	// format can change without an old client silently misreading a new key.
	//
	// Contains a separator itself, so the version is matched as a literal prefix
	// rather than "the text before the first _".
	Version = "inv_v2"

	// VersionV1 is the original format, still accepted.
	VersionV1 = "inv1"

	// preauthPrefix is the constant prefix Headscale puts on every preauth key —
	// 11 characters of zero information. v2 strips it on mint and restores it
	// here, so callers still receive a key ready for `tailscale up`. v1 keys are
	// carried verbatim, which is also what a key lacking the prefix is emitted as.
	preauthPrefix = "hskey-auth-"

	// FingerprintHexLen is 128 bits of SHA-256, hex-encoded.
	FingerprintHexLen = 32
)

var (
	ErrMalformed          = errors.New("invite key is not in the expected format")
	ErrUnsupportedVersion = errors.New("unsupported invite key version; update the app and try again")
	ErrBadFingerprint     = errors.New("invite key has an invalid fingerprint")
	ErrBadPreauthKey      = errors.New("invite key has an empty key section")
)

type Key struct {
	// Fingerprint of the control plane's public identity key. Public, and the
	// anchor for verification: it arrives out of band, never via a relay.
	Fingerprint string
	// PreauthKey is secret — a single-use Headscale key, already tagged.
	PreauthKey string
}

// Parse validates an invite key's structure.
//
// Structural validity proves nothing about authenticity. The key is only
// trustworthy once VerifyServerKey has matched the fingerprint against what the
// control plane actually serves.
func Parse(raw string) (Key, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return Key{}, fmt.Errorf("%w: empty", ErrMalformed)
	}

	// Longest version prefix first, so "inv_v2_" is never read as "inv".
	var body string
	var restorePrefix bool
	switch {
	case strings.HasPrefix(s, Version+"_"):
		body, restorePrefix = s[len(Version)+1:], true
	case strings.HasPrefix(s, VersionV1+"_"):
		body, restorePrefix = s[len(VersionV1)+1:], false
	case s == Version || s == VersionV1:
		// A known version and nothing else: truncated, not from the future.
		// Reporting "update Bridge" would send someone after the wrong problem.
		return Key{}, fmt.Errorf("%w: missing key section", ErrMalformed)
	default:
		got := s
		if i := strings.Index(s, "_"); i >= 0 {
			got = s[:i]
		}
		return Key{}, fmt.Errorf("%w (got %q)", ErrUnsupportedVersion, got)
	}

	// Split once: the fingerprint is hex and cannot contain a separator, so
	// everything after the first one is the key — underscores and all.
	sep := strings.Index(body, "_")
	if sep < 0 {
		return Key{}, fmt.Errorf("%w: missing key section", ErrMalformed)
	}

	fp := strings.ToLower(body[:sep])
	preauth := body[sep+1:]
	if restorePrefix && preauth != "" {
		preauth = preauthPrefix + preauth
	}

	if len(fp) != FingerprintHexLen || !isHex(fp) {
		return Key{}, ErrBadFingerprint
	}
	if preauth == "" {
		return Key{}, ErrBadPreauthKey
	}
	return Key{Fingerprint: fp, PreauthKey: preauth}, nil
}

// IsFingerprint reports whether fp is a 32-character lowercase hex
// fingerprint, the form the Mac sends and the relay's subdomain uses.
func IsFingerprint(fp string) bool {
	return len(fp) == FingerprintHexLen && isHex(fp)
}

func isHex(s string) bool {
	for _, r := range s {
		if (r < '0' || r > '9') && (r < 'a' || r > 'f') {
			return false
		}
	}
	return true
}

// Fingerprint hashes the control plane's public key as text — including its
// "mkey:" prefix — and truncates. Must match the TypeScript and the sidecar
// exactly; see the note in the sidecar's identity package.
func Fingerprint(publicKey string) string {
	sum := sha256.Sum256([]byte(publicKey))
	return hex.EncodeToString(sum[:])[:FingerprintHexLen]
}

// VerifyResult explains an accept/reject decision. The reason is surfaced to the
// user, because "the server identity changed" needs a different response from
// "this invite expired".
type VerifyResult struct {
	OK         bool
	MatchedPin bool
	Reason     string
	Detail     string
}

// VerifyServerKey decides whether a served identity key may be trusted.
//
// This is the check that makes an untrusted relay safe, and it MUST run before
// the preauth key is transmitted. A relay that can answer the identity request
// with a key of its own choosing — and be believed — impersonates the control
// plane and harvests the preauth key on first contact. Verify, then speak.
//
// When pins exist the served key must be one of them even if the fingerprint
// matches: a pin is a stronger statement than an invite, and the invite may
// predate a rotation. Passing both the current and next key makes rotation a
// staged rollout instead of a fleet-wide lockout.
func VerifyServerKey(expectedFingerprint, servedPublicKey string, pinnedKeys []string) VerifyResult {
	actual := Fingerprint(servedPublicKey)
	if subtle.ConstantTimeCompare([]byte(actual), []byte(strings.ToLower(expectedFingerprint))) != 1 {
		return VerifyResult{
			Reason: "fingerprint_mismatch",
			Detail: "The server identity did not match this invite. Do not continue — either the invite is stale, or something is impersonating the control plane.",
		}
	}

	if len(pinnedKeys) > 0 {
		for _, pin := range pinnedKeys {
			if subtle.ConstantTimeCompare([]byte(pin), []byte(servedPublicKey)) == 1 {
				return VerifyResult{OK: true, MatchedPin: true}
			}
		}
		return VerifyResult{
			Reason: "pin_mismatch",
			Detail: "The server identity changed since this device enrolled. If the key was rotated intentionally, re-enrol with a fresh invite.",
		}
	}

	return VerifyResult{OK: true}
}
