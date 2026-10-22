package shim

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"getsill.app/tailnet-mobile/internal/invite"
)

const realKey = "mkey:11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa11aa"
const rogueKey = "mkey:66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff66ff"

// relayServing starts a relay that answers /key with the given key.
func relayServing(t *testing.T, key string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/key" {
			_ = json.NewEncoder(w).Encode(map[string]string{"publicKey": key})
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	return srv
}

// deadRelay is an address nothing listens on.
func deadRelay(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	srv.Close() // closed immediately: connections are refused
	return srv
}

type memStore struct {
	mu     sync.Mutex
	pins   []string
	relays []Relay
}

func (m *memStore) PinnedKeys() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]string(nil), m.pins...)
}
func (m *memStore) SetPinnedKeys(k []string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.pins = append([]string(nil), k...)
	return nil
}
func (m *memStore) Relays() []Relay { return nil }
func (m *memStore) SetRelays(r []Relay) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.relays = r
	return nil
}

func TestFailsOverToSecondRelay(t *testing.T) {
	// The whole point of two relays: the first being down must not stop us.
	dead := deadRelay(t)
	good := relayServing(t, realKey)

	s := New(invite.Fingerprint(realKey), []Relay{
		RelayAtOrigin("primary", dead.URL),
		RelayAtOrigin("backup", good.URL),
	}, &memStore{})

	key, err := s.VerifyAndPin(context.Background())
	if err != nil {
		t.Fatalf("expected failover to succeed: %v", err)
	}
	if key != realKey {
		t.Fatalf("wrong key: %q", key)
	}
	if s.CurrentRelay() != "backup" {
		t.Fatalf("expected to be using backup, got %q", s.CurrentRelay())
	}
}

func TestRejectsHostileRelayAndFailsOver(t *testing.T) {
	// A relay serving its own key is hostile, not merely broken. We must not
	// trust it — but a healthy relay later in the list should still work.
	hostile := relayServing(t, rogueKey)
	good := relayServing(t, realKey)

	s := New(invite.Fingerprint(realKey), []Relay{
		RelayAtOrigin("hostile", hostile.URL),
		RelayAtOrigin("honest", good.URL),
	}, &memStore{})

	key, err := s.VerifyAndPin(context.Background())
	if err != nil {
		t.Fatalf("expected to skip the hostile relay: %v", err)
	}
	if key != realKey {
		t.Fatalf("pinned the wrong key: %q", key)
	}
	if s.CurrentRelay() != "honest" {
		t.Fatalf("must not select the hostile relay, got %q", s.CurrentRelay())
	}
	if s.PinnedKey() != realKey {
		t.Fatalf("pinned key must be the genuine one, got %q", s.PinnedKey())
	}
}

func TestAllRelaysHostileFailsClosed(t *testing.T) {
	// If every relay lies, we must refuse rather than pick the least-bad one.
	a := relayServing(t, rogueKey)
	b := relayServing(t, rogueKey)

	s := New(invite.Fingerprint(realKey), []Relay{
		RelayAtOrigin("a", a.URL),
		RelayAtOrigin("b", b.URL),
	}, &memStore{})

	if _, err := s.VerifyAndPin(context.Background()); err == nil {
		t.Fatal("expected failure when every relay serves a bad key")
	}
	if s.PinnedKey() != "" {
		t.Fatalf("nothing should have been pinned, got %q", s.PinnedKey())
	}
	if s.CurrentRelay() != "" {
		t.Fatalf("no relay should be selected, got %q", s.CurrentRelay())
	}
}

func TestPinSurvivesRelaySwap(t *testing.T) {
	// Once pinned, a relay that later swaps in its own key must be rejected
	// even though it is the same relay we successfully used before.
	store := &memStore{}
	good := relayServing(t, realKey)

	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("r", good.URL)}, store)
	if _, err := s.VerifyAndPin(context.Background()); err != nil {
		t.Fatalf("initial pin failed: %v", err)
	}

	// New process, same persisted pin, but the relay now lies.
	hostile := relayServing(t, rogueKey)
	s2 := New(invite.Fingerprint(rogueKey), []Relay{RelayAtOrigin("r", hostile.URL)}, store)
	if _, err := s2.VerifyAndPin(context.Background()); err == nil {
		t.Fatal("a pinned client must reject a swapped key even with a matching fingerprint")
	}
}

func TestKeyEndpointServesPinNotRelay(t *testing.T) {
	// tailscaled asks the shim, and the shim answers from its pin — the relay
	// gets no second chance to substitute a key after enrolment.
	good := relayServing(t, realKey)
	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("r", good.URL)}, &memStore{})
	if _, err := s.VerifyAndPin(context.Background()); err != nil {
		t.Fatal(err)
	}

	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/key?v=96", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}
	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body["publicKey"] != realKey {
		t.Fatalf("shim served %q, want the pinned key", body["publicKey"])
	}
}

func TestKeyEndpointRefusesBeforeVerification(t *testing.T) {
	// Serving an unverified key would defeat the point of pinning.
	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("r", "http://127.0.0.1:1")}, &memStore{})
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/key?v=96", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("want 503 before verification, got %d", rec.Code)
	}
}

func TestSlowRelayDoesNotHangForever(t *testing.T) {
	// A relay that accepts the connection and then stalls is a denial of
	// service; the context deadline must cut it off.
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(2 * time.Second)
	}))
	t.Cleanup(slow.Close)

	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("slow", slow.URL)}, &memStore{})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()

	done := make(chan struct{})
	go func() {
		_, _ = s.VerifyAndPin(ctx)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(1500 * time.Millisecond):
		t.Fatal("VerifyAndPin did not respect the context deadline")
	}
}

// pinnedShim returns a shim over relays whose store already holds realKey.
func pinnedShim(t *testing.T, relays []Relay) *Shim {
	t.Helper()
	store := &memStore{pins: []string{realKey}}
	return New(invite.Fingerprint(realKey), relays, store)
}

// The reconnect fast path: a slow first relay must not hold up a healthy
// second one. Before VerifyPinnedFirst the phone waited out the first relay's
// full timeout on every reconnect.
func TestPinnedVerifyDoesNotWaitForSlowRelay(t *testing.T) {
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(3 * time.Second):
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(slow.Close)
	good := relayServing(t, realKey)

	s := pinnedShim(t, []Relay{RelayAtOrigin("slow", slow.URL), RelayAtOrigin("fast", good.URL)})
	start := time.Now()
	key, err := s.VerifyPinnedFirst(context.Background())
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if key != realKey || s.CurrentRelay() != "fast" {
		t.Fatalf("got key %q via %q", key, s.CurrentRelay())
	}
	if took := time.Since(start); took > time.Second {
		t.Fatalf("waited %v for the slow relay", took)
	}
}

// Racing must not weaken the check: a hostile relay answering first is still
// rejected, and the honest one wins.
func TestPinnedVerifyRejectsFastHostileRelay(t *testing.T) {
	hostile := relayServing(t, rogueKey)
	slowGood := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(150 * time.Millisecond)
		_ = json.NewEncoder(w).Encode(map[string]string{"publicKey": realKey})
	}))
	t.Cleanup(slowGood.Close)

	s := pinnedShim(t, []Relay{RelayAtOrigin("hostile", hostile.URL), RelayAtOrigin("honest", slowGood.URL)})
	key, err := s.VerifyPinnedFirst(context.Background())
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if key != realKey || s.CurrentRelay() != "honest" {
		t.Fatalf("got key %q via %q", key, s.CurrentRelay())
	}
}

func TestPinnedVerifyAllHostileFailsClosed(t *testing.T) {
	a := relayServing(t, rogueKey)
	b := relayServing(t, rogueKey)
	s := pinnedShim(t, []Relay{RelayAtOrigin("a", a.URL), RelayAtOrigin("b", b.URL)})
	if _, err := s.VerifyPinnedFirst(context.Background()); err == nil {
		t.Fatal("expected failure when every relay serves a bad key")
	}
	if s.CurrentRelay() != "" {
		t.Fatalf("no relay should be selected, got %q", s.CurrentRelay())
	}
}

// Without a pin there is nothing to race against, and the first key seen would
// be the one pinned — so it must take the ordered path.
func TestPinnedVerifyWithoutPinUsesOrderedWalk(t *testing.T) {
	good := relayServing(t, realKey)
	dead := deadRelay(t)
	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("dead", dead.URL), RelayAtOrigin("good", good.URL)}, &memStore{})
	if _, err := s.VerifyPinnedFirst(context.Background()); err != nil {
		t.Fatalf("verify: %v", err)
	}
	if s.PinnedKey() != realKey {
		t.Fatalf("expected the ordered walk to pin, got %q", s.PinnedKey())
	}
}

func TestPinPersistsAcrossRestart(t *testing.T) {
	store := &memStore{}
	good := relayServing(t, realKey)

	s := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("r", good.URL)}, store)
	if _, err := s.VerifyAndPin(context.Background()); err != nil {
		t.Fatal(err)
	}

	// A fresh shim reading the same store starts out already pinned.
	s2 := New(invite.Fingerprint(realKey), []Relay{RelayAtOrigin("r", good.URL)}, store)
	if s2.PinnedKey() != realKey {
		t.Fatalf("pin did not survive restart, got %q", s2.PinnedKey())
	}
}
