package relay

import "testing"

// This vector MUST match the one pinned in headfwd:
//
//	headfwd-proxy-fly/registration_crypto_test.go
//	headfwd-sidecar/registration_crypto_test.go
//
// Three independent copies of this crypto now exist across two repos, and none
// of them share a package. If any drifts, registration fails with nothing more
// informative than "invalid proof" from a remote server. This test is the
// tripwire that turns that into a build failure with an explanation.
const pinnedProofVector = "f2740fc7e836710796c496894e8bc4e42e6c323aabc4c8ca7f4d983c3f1c6f9a"

func TestProofMatchesRelayVector(t *testing.T) {
	secret := make([]byte, 32)
	for i := range secret {
		secret[i] = byte(i)
	}

	got, err := registrationProof(secret, "fp", "mkey:aa", "nonce", "eph")
	if err != nil {
		t.Fatal(err)
	}
	if got != pinnedProofVector {
		t.Fatalf(
			"This relay client disagrees with the headfwd relay:\n"+
				"  bridge  %s\n  headfwd %s\n"+
				"All copies of the registration crypto must be identical.",
			got, pinnedProofVector)
	}
}

// The fingerprint is computed from the public key string alone, independently of
// the proof. That is why adding HKDF was not a breaking change: subdomains,
// pinned keys and already-issued invites are unaffected.
func TestFingerprintMatchesSharedImplementation(t *testing.T) {
	const publicKey = "mkey:a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1"
	const want = "5a9cf99c08e43aea2064d5be47e92b35" // from packages/shared/src/invite.ts

	if got := Fingerprint(publicKey); got != want {
		t.Fatalf("fingerprint drifted from the shared implementation:\n  got  %s\n  want %s", got, want)
	}
}

func TestDerivedKeyIsNotTheSharedSecret(t *testing.T) {
	secret := []byte("0123456789abcdef0123456789abcdef")
	key, err := deriveProofKey(secret, "nonce")
	if err != nil {
		t.Fatal(err)
	}
	if string(key) == string(secret) {
		t.Fatal("HKDF returned the input unchanged — this was the v1 bug")
	}
}

func TestHostPortFromURL(t *testing.T) {
	cases := map[string]string{
		"http://127.0.0.1:8080":  "127.0.0.1:8080",
		"http://127.0.0.1:8080/": "127.0.0.1:8080",
		"http://headscale":       "headscale:80",
		"https://headscale":      "headscale:443",
		"http://h:9/path":        "h:9",
	}
	for in, want := range cases {
		got, err := hostPortFromURL(in)
		if err != nil {
			t.Errorf("%s: %v", in, err)
			continue
		}
		if got != want {
			t.Errorf("%s -> %s, want %s", in, got, want)
		}
	}
	if _, err := hostPortFromURL("http://"); err == nil {
		t.Error("expected an error for a URL with no host")
	}
}
