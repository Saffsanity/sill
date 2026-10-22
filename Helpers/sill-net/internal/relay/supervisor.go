package relay

import (
	"context"
	"strings"
	"sync"
	"time"
)

// Status is one relay's state, for the portal.
type Status struct {
	URL       string    `json:"url"`
	State     string    `json:"state"` // connecting | connected | error
	PublicURL string    `json:"publicUrl,omitempty"`
	Error     string    `json:"error,omitempty"`
	Since     time.Time `json:"since"`
}

// Supervisor keeps one registration+tunnel alive per configured relay, and
// can be reconfigured at runtime when the user edits the relay list.
//
// Every relay is registered with (rather than failing over between them)
// because a client picks whichever relay answers for its fingerprint, so each
// needs its own live tunnel. Relays are untrusted -- they carry sealed TS2021
// and WireGuard bytes; client-side key pinning is what makes that safe.
type Supervisor struct {
	HeadscaleURL string
	NoisePriv    []byte
	Logf         func(string, ...any)

	mu      sync.Mutex
	running map[string]context.CancelFunc
	status  map[string]*Status
}

func (s *Supervisor) logf(f string, a ...any) {
	if s.Logf != nil {
		s.Logf(f, a...)
	}
}

// Set makes the running relays match urls exactly.
func (s *Supervisor) Set(urls []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.running == nil {
		s.running = map[string]context.CancelFunc{}
		s.status = map[string]*Status{}
	}
	want := map[string]bool{}
	for _, u := range urls {
		u = strings.TrimRight(strings.TrimSpace(u), "/")
		if u != "" {
			want[u] = true
		}
	}
	for u, cancel := range s.running {
		if !want[u] {
			cancel()
			delete(s.running, u)
			delete(s.status, u)
		}
	}
	for u := range want {
		if _, ok := s.running[u]; ok {
			continue
		}
		ctx, cancel := context.WithCancel(context.Background())
		s.running[u] = cancel
		s.status[u] = &Status{URL: u, State: "connecting", Since: time.Now()}
		go s.supervise(ctx, u)
	}
}

func (s *Supervisor) setStatus(u string, fn func(*Status)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if st, ok := s.status[u]; ok {
		fn(st)
	}
}

// Snapshot returns the current status of every relay.
func (s *Supervisor) Snapshot() []Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Status, 0, len(s.status))
	for _, st := range s.status {
		out = append(out, *st)
	}
	return out
}

// PublicURL returns the first connected relay's public control URL.
func (s *Supervisor) PublicURL() string {
	for _, st := range s.Snapshot() {
		if st.State == "connected" {
			return st.PublicURL
		}
	}
	return ""
}

func (s *Supervisor) supervise(ctx context.Context, relayURL string) {
	name := relayURL
	backoff := 2 * time.Second
	const maxBackoff = 2 * time.Minute
	for ctx.Err() == nil {
		rctx, cancel := context.WithTimeout(ctx, 60*time.Second)
		reg, err := Register(rctx, relayURL, s.HeadscaleURL, s.NoisePriv)
		cancel()
		if err != nil {
			s.logf("[relay %s] registration failed: %v (retrying in %s)", name, err, backoff)
			s.setStatus(relayURL, func(st *Status) { st.State, st.Error, st.Since = "error", err.Error(), time.Now() })
			select {
			case <-ctx.Done():
				return
			case <-time.After(backoff):
			}
			if backoff < maxBackoff {
				backoff *= 2
			}
			continue
		}
		s.logf("[relay %s] registered as %s", name, reg.PublicURL)
		s.setStatus(relayURL, func(st *Status) {
			st.State, st.Error, st.PublicURL, st.Since = "connected", "", reg.PublicURL, time.Now()
		})
		t := &Tunnel{HeadscaleURL: s.HeadscaleURL}
		err = t.Run(ctx, reg.TunnelURL)
		if ctx.Err() != nil {
			return
		}
		s.logf("[relay %s] tunnel closed: %v", name, err)
		s.setStatus(relayURL, func(st *Status) { st.State, st.Since = "connecting", time.Now() })
		backoff = 2 * time.Second
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
	}
}
