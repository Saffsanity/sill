package invite

import (
	"errors"
	"testing"
)

// This mirrors packages/shared/scripts/verify-invite.ts. Both implementations
// must agree exactly: the server issues keys with one and clients parse them
// with the other, and a client cannot be hot-fixed once shipped.
func TestFingerprintMatchesTypeScript(t *testing.T) {
	const publicKey = "mkey:a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1a3f1"
	const wantFromTypeScript = "5a9cf99c08e43aea2064d5be47e92b35"

	if got := Fingerprint(publicKey); got != wantFromTypeScript {
		t.Fatalf("Go and TypeScript disagree on the fingerprint:\n  go = %s\n  ts = %s", got, wantFromTypeScript)
	}
}

func TestParseRoundTrip(t *testing.T) {
	const fp = "5a9cf99c08e43aea2064d5be47e92b35"
	// Real Headscale preauth keys contain underscores; a naive split truncates.
	const preauth = "hskey-auth-k7Yd_2mQx-9Lp_ZZa4"

	k, err := Parse("inv1_" + fp + "_" + preauth)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if k.Fingerprint != fp {
		t.Errorf("fingerprint: got %q", k.Fingerprint)
	}
	if k.PreauthKey != preauth {
		t.Errorf("preauth key truncated: got %q, want %q", k.PreauthKey, preauth)
	}
}

func TestParseTolerantAndStrict(t *testing.T) {
	const fp = "5a9cf99c08e43aea2064d5be47e92b35"
	valid := "inv1_" + fp + "_hskey-auth-abc"

	if _, err := Parse("\n  " + valid + "\t "); err != nil {
		t.Errorf("should tolerate surrounding whitespace: %v", err)
	}
	if k, err := Parse("inv1_5A9CF99C08E43AEA2064D5BE47E92B35_hskey"); err != nil || k.Fingerprint != fp {
		t.Errorf("should normalise an uppercase fingerprint: %v / %q", err, k.Fingerprint)
	}

	cases := []struct {
		name string
		in   string
		want error
	}{
		{"empty", "   ", ErrMalformed},
		{"no separator", "inv1", ErrMalformed},
		{"future version", "inv2_" + fp + "_k", ErrUnsupportedVersion},
		{"no version", "_" + fp + "_k", ErrUnsupportedVersion},
		{"short fingerprint", "inv1_abc_k", ErrBadFingerprint},
		{"non-hex fingerprint", "inv1_zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz_k", ErrBadFingerprint},
		{"missing key section", "inv1_" + fp, ErrMalformed},
		{"empty key section", "inv1_" + fp + "_", ErrBadPreauthKey},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Parse(tc.in)
			if !errors.Is(err, tc.want) {
				t.Fatalf("want %v, got %v", tc.want, err)
			}
		})
	}
}

func TestVerifyServerKey(t *testing.T) {
	const real = "mkey:11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa"
	const rogue = "mkey:66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff"
	fp := Fingerprint(real)

	if res := VerifyServerKey(fp, real, nil); !res.OK {
		t.Error("must accept the genuine key when unpinned")
	}
	// The attack that matters: a relay answering with its own key.
	if res := VerifyServerKey(fp, rogue, nil); res.OK || res.Reason != "fingerprint_mismatch" {
		t.Errorf("must reject a substituted key, got %+v", res)
	}
	if res := VerifyServerKey(fp, real, []string{real}); !res.OK || !res.MatchedPin {
		t.Error("must accept a key matching the pin")
	}
	// A pin outranks the invite: the invite may predate a rotation.
	if res := VerifyServerKey(fp, real, []string{rogue}); res.OK || res.Reason != "pin_mismatch" {
		t.Errorf("must reject an unpinned key even when the fingerprint matches, got %+v", res)
	}
	// Staged rotation: old and new both trusted during the window.
	if res := VerifyServerKey(fp, real, []string{rogue, real}); !res.OK {
		t.Error("must accept either key mid-rotation")
	}
}

func TestVerifyRejectsMangledKeys(t *testing.T) {
	const real = "mkey:11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa"
	fp := Fingerprint(real)

	// Each of these is a plausible relay trick that must not be normalised away
	// before hashing.
	for _, mangled := range []string{
		real[:len(real)-8],  // truncated
		"  " + real + "  ",  // padded
		real + "\n",         // trailing newline
		real[len("mkey:"):], // prefix stripped
		"",                  // empty
	} {
		if res := VerifyServerKey(fp, mangled, nil); res.OK {
			t.Errorf("must reject mangled key %q", mangled)
		}
	}
}
