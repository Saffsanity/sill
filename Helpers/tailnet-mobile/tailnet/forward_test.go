package tailnet

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"sync"
	"testing"
	"time"
)

// dialRecorder stands in for tsnet's Dial: it records what it was asked for
// and connects to a loopback server instead.
type dialRecorder struct {
	mu      sync.Mutex
	targets []string
	to      string
	err     error
}

func (d *dialRecorder) dial(ctx context.Context, network, addr string) (net.Conn, error) {
	d.mu.Lock()
	d.targets = append(d.targets, addr)
	d.mu.Unlock()
	if d.err != nil {
		return nil, d.err
	}
	return net.Dial("tcp", d.to)
}

func (d *dialRecorder) seen() []string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return append([]string(nil), d.targets...)
}

// get makes one HTTP request through the forwarder at addr.
func get(t *testing.T, addr string) string {
	t.Helper()
	conn, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		t.Fatalf("dial forwarder: %v", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := io.WriteString(conn, "GET / HTTP/1.1\r\nHost: mac\r\nConnection: close\r\n\r\n"); err != nil {
		t.Fatalf("write request: %v", err)
	}
	body, _ := io.ReadAll(conn)
	return string(body)
}

// httpTestServer runs an HTTP server on loopback and returns its address.
func httpTestServer(t *testing.T, h http.HandlerFunc) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	srv := &http.Server{Handler: h}
	go func() { _ = srv.Serve(ln) }()
	t.Cleanup(func() { _ = srv.Close() })
	return ln.Addr().String()
}

// A node that comes up while a connection waits carries it.
func TestForwarderWaitsForNode(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("late")) })
	f, addr := startForwarder(t, nil)
	go func() { time.Sleep(400 * time.Millisecond); f.setDial((&dialRecorder{to: origin}).dial) }()
	if got := get(t, addr); !contains(got, "late") {
		t.Fatalf("connection made before the node: %q", got)
	}
}

func startForwarder(t *testing.T, dial DialFunc) (*forwarder, string) {
	t.Helper()
	ln := newTestListener(t)
	f := newForwarder(ln, doorTarget, dial)
	go f.serve()
	t.Cleanup(f.close)
	return f, ln.AddrString()
}

// Every connection goes to the Mac's door and only there, whatever the
// client writes: the forwarder takes no destination from the connection.
func TestForwarderDialsOnlyTheDoor(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("door")) })
	rec := &dialRecorder{to: origin}
	_, addr := startForwarder(t, rec.dial)
	for i := 0; i < 3; i++ {
		if got := get(t, addr); !contains(got, "door") {
			t.Fatalf("request %d: %q", i, got)
		}
	}
	for _, target := range rec.seen() {
		if target != doorTarget {
			t.Fatalf("dialled %q, want only %q", target, doorTarget)
		}
	}
	if len(rec.seen()) != 3 {
		t.Fatalf("dials: %v", rec.seen())
	}
}

// With no node behind it the forwarder waits a little for one, then closes:
// Sill's dial fails rather than hanging.
func TestForwarderWithoutNodeClosesAfterWait(t *testing.T) {
	f, addr := startForwarder(t, nil)
	f.wait = 300 * time.Millisecond
	conn, err := net.DialTimeout("tcp", addr, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if _, err := conn.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
		var ne net.Error
		if errors.As(err, &ne) && ne.Timeout() {
			t.Fatal("forwarder held a connection with no tailnet behind it")
		}
	}
}

// A rebuild swaps the dial behind the same port.
func TestForwarderSwapsDialBehindSamePort(t *testing.T) {
	first := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("first")) })
	second := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("second")) })
	f, addr := startForwarder(t, (&dialRecorder{to: first}).dial)
	if got := get(t, addr); !contains(got, "first") {
		t.Fatalf("before: %q", got)
	}
	f.setDial((&dialRecorder{to: second}).dial)
	if got := get(t, addr); !contains(got, "second") {
		t.Fatalf("after: %q", got)
	}
}

// The forwarder runs on a revivingListener: a reclaimed socket comes back on
// the same port, which is the iOS lock-and-unlock sequence in miniature.
func TestForwarderWorksAcrossRevival(t *testing.T) {
	origin := httpTestServer(t, func(w http.ResponseWriter, r *http.Request) { _, _ = w.Write([]byte("hello")) })
	l := newTestListener(t)
	f := newForwarder(l, doorTarget, (&dialRecorder{to: origin}).dial)
	go f.serve()
	t.Cleanup(f.close)
	addr := l.AddrString()
	if got := get(t, addr); !contains(got, "hello") {
		t.Fatalf("before: %q", got)
	}
	l.mu.Lock()
	inner := l.ln
	l.mu.Unlock()
	_ = inner.Close()
	l.Check()
	if got := get(t, addr); !contains(got, "hello") {
		t.Fatalf("after revival: %q", got)
	}
}

// closeConns drops live spliced connections (a node going away).
func TestForwarderCloseConnsDropsLiveSessions(t *testing.T) {
	hold := make(chan struct{})
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	t.Cleanup(func() { ln.Close(); close(hold) })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() { <-hold; c.Close() }()
		}
	}()
	f, addr := startForwarder(t, (&dialRecorder{to: ln.Addr().String()}).dial)
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	time.Sleep(100 * time.Millisecond)
	f.closeConns()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	if _, err := conn.Read(make([]byte, 1)); err == nil {
		t.Fatal("connection still open after closeConns")
	} else {
		var ne net.Error
		if errors.As(err, &ne) && ne.Timeout() {
			t.Fatal("connection still open after closeConns")
		}
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
