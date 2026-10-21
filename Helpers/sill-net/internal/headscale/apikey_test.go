package headscale

import (
	"strings"
	"testing"
	"time"
)

func TestAPIKeyPrefix(t *testing.T) {
	secret := strings.Repeat("a", 30) + "-" + strings.Repeat("b", 33) // contains a dash
	key := "hskey-api-ABCDEF-12345-" + secret
	if p, ok := APIKeyPrefix(key); !ok || p != "ABCDEF-12345" {
		t.Errorf("got %q %v", p, ok)
	}
	for _, bad := range []string{"", "hskey-api-short", "hskey-auth-ABCDEF-12345-" + secret} {
		if _, ok := APIKeyPrefix(bad); ok {
			t.Errorf("accepted %q", bad)
		}
	}
}

func TestClassifyProbe(t *testing.T) {
	if ClassifyProbe(200) != ProbeValid || ClassifyProbe(401) != ProbeInvalid ||
		ClassifyProbe(500) != ProbeUnhealthy || ClassifyProbe(0) != ProbeUnhealthy {
		t.Error("classification wrong")
	}
}

func TestNeedsRotation(t *testing.T) {
	now := time.Now()
	if NeedsRotation(time.Time{}, now) {
		t.Error("unknown expiry must not rotate")
	}
	if !NeedsRotation(now.Add(13*24*time.Hour), now) {
		t.Error("13 days left should rotate")
	}
	if NeedsRotation(now.Add(30*24*time.Hour), now) {
		t.Error("30 days left should not rotate")
	}
}
