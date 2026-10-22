// Package shim implements the local control shim.
//
// tailscaled accepts exactly one --login-server and persists it in its state
// file, so relay failover cannot be done by handing it a list. Instead
// tailscaled is pointed at this shim on 127.0.0.1, and the shim decides which
// relay to use per request. That has two consequences worth stating plainly:
//
//   - The control URL baked into every client's tailscaled state is loopback,
//     so it never has to change — not to add a relay, not to replace one, not
//     to move off a vendor entirely.
//   - The relay list lives in a process we ship and auto-update, rather than in
//     client state we cannot reach.
//
// The shim also answers /key from its pinned copy rather than forwarding it.
// A relay that can answer the identity request with a key of its own choosing
// impersonates the control plane, so once a key is pinned we stop asking.
package shim

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"sync"
	"time"

	"getsill.app/tailnet-mobile/internal/invite"
)

// Relay is one reachable front-end for the control plane.
type Relay struct {
	// Name is for logs and the tray UI ("headfwd").
	Name string
	// Domain is the relay's apex, e.g. "headfwd.net".
	//
	// NOT a full origin: the relay routes by fingerprint subdomain, so the URL
	// a client actually fetches is https://<fingerprint>.<domain>. Hitting the
	// apex directly returns "invalid subdomain". Storing the domain rather than
	// a pre-built URL is what lets one relay entry serve any control plane, and
	// keeps the fingerprint — which the shim already holds — the single source
	// of that value.
	Domain string

	// originOverride bypasses subdomain composition and uses this origin
	// verbatim. Only tests set it — a real relay is always reached by
	// fingerprint subdomain over TLS, and an httptest server has neither a
	// wildcard cert nor a resolvable name.
	originOverride string
}

// originFor builds the URL to fetch for a given control-plane fingerprint.
func (r Relay) originFor(fingerprint string) string {
	if r.originOverride != "" {
		return r.originOverride
	}
	return fmt.Sprintf("https://%s.%s", fingerprint, r.Domain)
}

// RelayAtOrigin builds a relay pinned to a literal origin, for tests and for
// pointing a dev client at a locally-running relay.
func RelayAtOrigin(name, origin string) Relay {
	return Relay{Name: name, Domain: name, originOverride: strings.TrimRight(origin, "/")}
}

// OriginForTest exposes origin composition so callers outside this package can
// assert on it. Not used in production paths.
func (r Relay) OriginForTest(fingerprint string) string { return r.originFor(fingerprint) }

// Store persists the pinned identity key and the learned relay list across
// restarts. Implemented over a JSON file on disk by the state package.
type Store interface {
	PinnedKeys() []string
	SetPinnedKeys(keys []string) error
	Relays() []Relay
	SetRelays(relays []Relay) error
}

type Shim struct {
	// Fingerprint from the invite key. The anchor for verification.
	Fingerprint string
	// Relays to try, in order. Hardcoded defaults, plus anything learned.
	relays []Relay
	store  Store
	client *http.Client

	mu      sync.RWMutex
	pinned  []string
	current *Relay
}

func New(fingerprint string, relays []Relay, store Store) *Shim {
	s := &Shim{
		Fingerprint: fingerprint,
		relays:      relays,
		store:       store,
		client: &http.Client{
			Timeout: 15 * time.Second,
			// Never follow a redirect: a hostile relay could otherwise bounce
			// the control connection to an origin of its choosing, and the
			// pinning check would be applied to the wrong hop.
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		},
	}
	if store != nil {
		s.pinned = store.PinnedKeys()
		if learned := store.Relays(); len(learned) > 0 {
			s.relays = append(s.relays, learned...)
		}
	}
	return s
}

// ErrNoRelay means every configured relay failed. Callers should surface this
// as "cannot reach the Mac right now", not as an authentication problem.
var ErrNoRelay = errors.New("no relay could be reached")

// capabilityVersion is the Tailscale client capability version we present when
// fetching the control plane's identity key. Headscale rejects anything below
// its floor with a plain-text "unsupported client version" and HTTP 400 — not
// JSON — so a stale value surfaces as a confusing parse error. Headscale 0.29
// requires >= 115. Keep in step with the sidecar's constant of the same name.
const capabilityVersion = 115

// keyResponse is Headscale's /key response shape.
type keyResponse struct {
	PublicKey string `json:"publicKey"`
}

// VerifyAndPin fetches the control plane's identity key through whichever relay
// answers, verifies it, and pins it on success.
//
// This must be called BEFORE the preauth key is handed to tailscaled. The
// ordering is the entire reason a relay can be untrusted.
func (s *Shim) VerifyAndPin(ctx context.Context) (string, error) {
	var lastErr error

	for i := range s.relays {
		relay := s.relays[i]
		key, err := s.fetchKey(ctx, relay)
		if err != nil {
			log.Printf("[shim] relay %s unreachable: %v", relay.Name, err)
			lastErr = err
			continue
		}

		s.mu.RLock()
		pins := append([]string(nil), s.pinned...)
		s.mu.RUnlock()

		res := invite.VerifyServerKey(s.Fingerprint, key, pins)
		if !res.OK {
			// A relay serving the wrong key is not a transport failure — it is
			// either hostile or misconfigured. Try the next one rather than
			// trusting it, but keep the reason: if every relay says the same
			// thing, the invite is probably just stale.
			log.Printf("[shim] relay %s served an untrusted key (%s)", relay.Name, res.Reason)
			lastErr = fmt.Errorf("%s: %s", res.Reason, res.Detail)
			continue
		}

		s.mu.Lock()
		s.current = &relay
		if len(s.pinned) == 0 {
			s.pinned = []string{key}
			if s.store != nil {
				if err := s.store.SetPinnedKeys(s.pinned); err != nil {
					log.Printf("[shim] could not persist pin: %v", err)
				}
			}
			log.Printf("[shim] pinned control-plane identity via %s", relay.Name)
		}
		s.mu.Unlock()
		return key, nil
	}

	if lastErr == nil {
		lastErr = ErrNoRelay
	}
	return "", fmt.Errorf("%w: %v", ErrNoRelay, lastErr)
}

// VerifyPinnedFirst is VerifyAndPin for a client that already holds a pin: it
// asks every relay at once and takes the first answer that matches the pin.
//
// The check applied to each answer is identical — invite.VerifyServerKey with
// the stored pins — so racing the relays changes how long verification takes,
// not what it accepts. What it removes is the serial wait: VerifyAndPin gives
// each relay its whole client timeout before trying the next, so one relay
// being slow or unreachable used to add up to fifteen seconds to every phone
// reconnect. Without a pin there is nothing to race against safely (the first
// key seen is what gets pinned), so that case falls back to the ordered walk.
//
// Errors, when every relay fails, are reported the way VerifyAndPin reports
// them: the error of the last relay in list order, wrapped in ErrNoRelay.
func (s *Shim) VerifyPinnedFirst(ctx context.Context) (string, error) {
	s.mu.RLock()
	pins := append([]string(nil), s.pinned...)
	s.mu.RUnlock()
	if len(pins) == 0 || len(s.relays) < 2 {
		return s.VerifyAndPin(ctx)
	}

	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	type result struct {
		index int
		key   string
		err   error
	}
	results := make(chan result, len(s.relays))
	for i := range s.relays {
		relay := s.relays[i]
		go func(i int) {
			key, err := s.fetchKey(ctx, relay)
			if err == nil {
				if res := invite.VerifyServerKey(s.Fingerprint, key, pins); !res.OK {
					log.Printf("[shim] relay %s served an untrusted key (%s)", relay.Name, res.Reason)
					err = fmt.Errorf("%s: %s", res.Reason, res.Detail)
				}
			} else {
				log.Printf("[shim] relay %s unreachable: %v", relay.Name, err)
			}
			results <- result{index: i, key: key, err: err}
		}(i)
	}

	errs := make([]error, len(s.relays))
	for range s.relays {
		r := <-results
		if r.err != nil {
			errs[r.index] = r.err
			continue
		}
		relay := s.relays[r.index]
		s.mu.Lock()
		s.current = &relay
		s.mu.Unlock()
		return r.key, nil
	}

	lastErr := errs[len(errs)-1]
	if lastErr == nil {
		lastErr = ErrNoRelay
	}
	return "", fmt.Errorf("%w: %v", ErrNoRelay, lastErr)
}

func (s *Shim) fetchKey(ctx context.Context, relay Relay) (string, error) {
	url := fmt.Sprintf("%s/key?v=%d", relay.originFor(s.Fingerprint), capabilityVersion)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	resp, err := s.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		// Translate the two statuses that mean something specific here. A bare
		// "HTTP 503" reads as "the relay is broken" when it actually means the
		// relay is fine and the control plane behind it is not connected —
		// which sends whoever is debugging to the wrong side entirely. The
		// relay is untrusted, so treat these as hints for a human, never as
		// facts to act on.
		switch resp.StatusCode {
		case http.StatusServiceUnavailable:
			return "", fmt.Errorf(
				"HTTP 503: the relay is up but this tailnet's Headscale is not connected to it")
		case http.StatusBadRequest:
			// Note this does NOT mean "unknown tailnet": the relay answers 503
			// for any well-formed fingerprint it has no live control plane for,
			// registered or not. 400 is a malformed subdomain, so it points at
			// a bad relay URL rather than a bad invite.
			return "", fmt.Errorf(
				"HTTP 400: the relay rejected the address as malformed (bad relay URL, not a bad invite)")
		}
		return "", fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// Cap the body: a hostile relay must not be able to exhaust memory with an
	// endless response to an endpoint we contact before trusting it.
	var kr keyResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<10)).Decode(&kr); err != nil {
		return "", fmt.Errorf("decode key: %w", err)
	}
	if kr.PublicKey == "" {
		return "", errors.New("empty public key")
	}
	return kr.PublicKey, nil
}

// PinnedKey returns the verified identity key, if one has been pinned.
func (s *Shim) PinnedKey() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if len(s.pinned) == 0 {
		return ""
	}
	return s.pinned[0]
}

// CurrentRelay names the relay currently in use, for the tray UI.
func (s *Shim) CurrentRelay() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.current == nil {
		return ""
	}
	return s.current.Name
}

// Handler is what tailscaled talks to. Everything except /key is proxied
// through to the live relay; /key is answered from the pin.
func (s *Shim) Handler() http.Handler {
	mux := http.NewServeMux()

	// Answer the identity request locally from the pinned key. This is the
	// headfwd pinning patch generalised: once we know the real key, a relay
	// never gets another chance to substitute one.
	mux.HandleFunc("/key", func(w http.ResponseWriter, r *http.Request) {
		key := s.PinnedKey()
		if key == "" {
			http.Error(w, "control plane identity not yet verified", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(keyResponse{PublicKey: key})
	})

	// Everything else (the TS2021 control channel) goes to the live relay. The
	// payload is end-to-end encrypted between tailscaled and Headscale, so the
	// shim is a dumb pipe here — it just picks the destination.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		s.mu.RLock()
		relay := s.current
		s.mu.RUnlock()
		if relay == nil {
			http.Error(w, "no relay selected", http.StatusServiceUnavailable)
			return
		}

		target, err := url.Parse(relay.originFor(s.Fingerprint))
		if err != nil {
			http.Error(w, "bad relay URL", http.StatusInternalServerError)
			return
		}

		proxy := httputil.NewSingleHostReverseProxy(target)
		// Route by Host, not just by URL.
		//
		// The relay selects the control plane from the fingerprint subdomain in
		// the Host header, but NewSingleHostReverseProxy rewrites only the URL
		// and leaves Host as whatever the client sent — here the loopback
		// address tailscaled dialled. The relay then sees "127.0.0.1:8800",
		// cannot match a subdomain, and answers 400 to every proxied request.
		// /key still worked (it is served locally from the pin), so the shim
		// looked healthy while the TS2021 control channel behind it was dead
		// and `tailscale up` failed with a bare "EOF".
		director := proxy.Director
		proxy.Director = func(req *http.Request) {
			director(req)
			req.Host = target.Host
		}
		// TS2021 uses a custom HTTP Upgrade, so the transport must not try to
		// be clever about connection reuse or compression.
		proxy.Transport = &http.Transport{
			Proxy:               http.ProxyFromEnvironment,
			DialContext:         (&net.Dialer{Timeout: 10 * time.Second}).DialContext,
			DisableCompression:  true,
			TLSHandshakeTimeout: 10 * time.Second,
		}
		proxy.ErrorHandler = func(w http.ResponseWriter, _ *http.Request, err error) {
			log.Printf("[shim] proxy to %s failed: %v", relay.Name, err)
			http.Error(w, "relay unreachable", http.StatusBadGateway)
		}
		proxy.ServeHTTP(w, r)
	})

	return mux
}
