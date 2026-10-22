package tailnet

import (
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

// A controller with a proxy but no tsnet node, which is all Suspend/Resume and
// the listener half of a probe touch.
func controllerWithProxy(t *testing.T, origin string) *Controller {
	t.Helper()
	c := New()
	addr, err := c.ensureProxy((&dialRecorder{to: origin}).dial)
	if err != nil {
		t.Fatalf("ensureProxy: %v", err)
	}
	c.setStatus(func(s *Status) { s.ProxyAddr = addr })
	t.Cleanup(c.Stop)
	return c
}

// The webview holds the proxy's port in its configuration, so a lock and unlock
// must hand back the same one — otherwise every unlock would reset the page's
// networking and drop its sockets.
func TestSuspendResumeKeepsProxyAddr(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("up"))
	})
	c := controllerWithProxy(t, origin)
	before := c.Status().ProxyAddr

	c.Suspend()
	c.Resume()

	if after := c.Status().ProxyAddr; after != before {
		t.Fatalf("proxy moved across suspend/resume: %s -> %s", before, after)
	}
	if got := get(t, before); !strings.Contains(got, "up") {
		t.Fatalf("proxy not serving after resume: %q", got)
	}
}

// After a probe, a proxy whose socket died is serving again on the same port.
//
// Which path revives it is timing: here the serve loop's Accept sees the closed
// socket and re-listens, racing the probe's Check. On iOS a reclaimed socket
// blocks Accept rather than failing it, so there Check is the one that fires —
// TestCheckRevivesOnSamePort covers that path on its own. This asserts the
// outcome the webview cares about.
func TestProbeLeavesProxyServing(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("up"))
	})
	c := controllerWithProxy(t, origin)
	addr := c.Status().ProxyAddr

	c.socksLn.mu.Lock()
	inner := c.socksLn.ln
	c.socksLn.mu.Unlock()
	_ = inner.Close()

	res := c.probe(doorTarget, time.Second)
	// No node, so the dial half cannot pass; the listener half is the point.
	if res.ok {
		t.Fatal("probe claimed success with no tailnet")
	}
	if got := get(t, addr); !strings.Contains(got, "up") {
		t.Fatalf("proxy not serving after revival: %q", got)
	}
}

// A recovery must rebind listeners Suspend released, even when nobody called
// Resume.
func TestRecoverResumesSuspendedListeners(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("up"))
	})
	c := controllerWithProxy(t, origin)
	c.cfg.Fingerprint = "0123456789abcdef0123456789abcdef"
	addr := c.Status().ProxyAddr

	c.Suspend()
	if _, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		t.Fatal("suspended proxy still accepting; the test proves nothing")
	}

	// No node, so Recover goes on to the rebuild path, which points the
	// forwarder at nothing while it works (and then fails for want of a state
	// dir). What matters is that the LISTENER is back on the same port.
	c.Recover("")
	conn, err := net.DialTimeout("tcp", addr, time.Second)
	if err != nil {
		t.Fatalf("forwarder not rebound by Recover: %v", err)
	}
	conn.Close()
}

// A device that never enrolled has nothing to recover, and Recover must say so
// rather than kick off a start with no fingerprint.
func TestRecoverWithoutEnrolmentDoesNothing(t *testing.T) {
	c := New()
	if c.Recover("") {
		t.Fatal("Recover started something on an unenrolled controller")
	}
	if c.Status().Phase != PhaseIdle {
		t.Fatalf("phase changed to %q", c.Status().Phase)
	}
}

// An identity failure must stay on screen. Retrying would replace the one
// message that tells the user something is impersonating their control plane.
func TestRecoverLeavesIdentityFailureAlone(t *testing.T) {
	c := New()
	c.cfg.Fingerprint = "0123456789abcdef0123456789abcdef"
	c.setStatus(func(s *Status) {
		s.Phase = PhaseError
		s.Error = verifyFailureMessage(errString("fingerprint_mismatch"))
	})
	if c.Recover("") {
		t.Fatal("Recover retried past an identity failure")
	}
}

type errString string

func (e errString) Error() string { return string(e) }
