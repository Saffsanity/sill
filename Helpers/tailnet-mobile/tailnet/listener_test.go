package tailnet

import (
	"errors"
	"net"
	"testing"
	"time"
)

func newTestListener(t *testing.T) *revivingListener {
	t.Helper()
	l, err := listenLoopback("test")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { _ = l.Close() })
	return l
}

// acceptLoop runs Accept until it errors, forwarding each connection.
func acceptLoop(l *revivingListener) (chan net.Conn, chan error) {
	conns := make(chan net.Conn, 16)
	done := make(chan error, 1)
	go func() {
		for {
			c, err := l.Accept()
			if err != nil {
				done <- err
				return
			}
			conns <- c
		}
	}()
	return conns, done
}

func dialWithin(t *testing.T, addr string, within time.Duration) net.Conn {
	t.Helper()
	giveUp := time.Now().Add(within)
	for {
		c, err := net.DialTimeout("tcp", addr, time.Second)
		if err == nil {
			return c
		}
		if time.Now().After(giveUp) {
			t.Fatalf("dial %s: %v", addr, err)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func expectAccepted(t *testing.T, conns chan net.Conn) {
	t.Helper()
	select {
	case c := <-conns:
		_ = c.Close()
	case <-time.After(2 * time.Second):
		t.Fatal("listener did not accept")
	}
}

// A socket iOS reclaimed refuses dials while Accept stays parked on it. Closing
// the inner listener behind the wrapper's back reproduces the refused dials, and
// Check must bring it back on the same port — the port is what the webview's
// proxy configuration and tsnet's ControlURL hold.
func TestCheckRevivesOnSamePort(t *testing.T) {
	l := newTestListener(t)
	before := l.AddrString()

	if l.Check() {
		t.Fatal("a healthy listener was replaced")
	}

	l.mu.Lock()
	inner := l.ln
	l.mu.Unlock()
	_ = inner.Close()
	if _, err := net.DialTimeout("tcp", before, time.Second); err == nil {
		t.Fatal("dial to a closed socket succeeded; the test is not reproducing anything")
	}

	if !l.Check() {
		t.Fatal("Check did not notice the dead socket")
	}
	if got := l.AddrString(); got != before {
		t.Fatalf("address moved: %s -> %s", before, got)
	}

	conns, _ := acceptLoop(l)
	c := dialWithin(t, before, 2*time.Second)
	defer c.Close()
	expectAccepted(t, conns)
}

// Accept must survive its socket failing rather than ending the serve loop,
// which is what used to leave the proxy dead until the app was force-quit.
func TestAcceptSurvivesSocketError(t *testing.T) {
	l := newTestListener(t)
	addr := l.AddrString()
	conns, done := acceptLoop(l)

	l.mu.Lock()
	inner := l.ln
	l.mu.Unlock()
	_ = inner.Close()

	c := dialWithin(t, addr, 2*time.Second)
	defer c.Close()
	select {
	case <-conns:
	case err := <-done:
		t.Fatalf("Accept gave up: %v", err)
	case <-time.After(2 * time.Second):
		t.Fatal("reopened listener did not accept")
	}
}

func TestCloseStopsRevival(t *testing.T) {
	l := newTestListener(t)
	addr := l.AddrString()
	_, done := acceptLoop(l)

	_ = l.Close()
	select {
	case err := <-done:
		if !errors.Is(err, net.ErrClosed) {
			t.Fatalf("Accept returned %v, want ErrClosed", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Accept did not return after Close")
	}

	if l.Check() {
		t.Fatal("Check revived a closed listener")
	}
	if _, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		t.Fatal("a closed listener is still accepting")
	}
}

// Suspend releases the socket before iOS can reclaim it; Resume binds the same
// port, and an Accept that was parked in between picks it up without help.
func TestSuspendResumeKeepsPort(t *testing.T) {
	l := newTestListener(t)
	addr := l.AddrString()
	conns, done := acceptLoop(l)

	l.Suspend()
	if _, err := net.DialTimeout("tcp", addr, time.Second); err == nil {
		t.Fatal("a suspended listener is still accepting")
	}
	if l.Check() {
		t.Fatal("Check must not rebind a deliberately suspended listener")
	}

	if moved := l.Resume(); moved {
		t.Fatalf("Resume moved the port from %s to %s", addr, l.AddrString())
	}
	c := dialWithin(t, addr, 2*time.Second)
	defer c.Close()
	select {
	case <-conns:
	case err := <-done:
		t.Fatalf("Accept ended across suspend/resume: %v", err)
	case <-time.After(2 * time.Second):
		t.Fatal("no accept after Resume")
	}
}

// If the old port has been taken, a moved port is better than no listener.
// The caller reads the new address and re-points whatever held the old one.
func TestResumeFallsBackToFreshPort(t *testing.T) {
	l := newTestListener(t)
	addr := l.AddrString()
	l.Suspend()

	squatter, err := net.Listen("tcp", addr)
	if err != nil {
		t.Skipf("could not occupy %s to force the fallback: %v", addr, err)
	}
	defer squatter.Close()

	if !l.Resume() {
		t.Fatal("expected Resume to report a moved port")
	}
	if l.AddrString() == addr {
		t.Fatal("address did not change")
	}
	conns, _ := acceptLoop(l)
	c := dialWithin(t, l.AddrString(), 2*time.Second)
	defer c.Close()
	expectAccepted(t, conns)
}
