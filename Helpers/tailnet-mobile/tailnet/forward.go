package tailnet

import (
	"context"
	"errors"
	"io"
	"log"
	"net"
	"sync"
	"time"
)

// DialFunc dials a target inside the tailnet.
type DialFunc func(ctx context.Context, network, addr string) (net.Conn, error)

// errNoTailnet is what a connection gets while the stack is being rebuilt.
var errNoTailnet = errors.New("the tailnet is not available")

// forwarder is Sill's way into the tailnet: a loopback TCP port whose every
// connection is spliced to one fixed target inside it, the Mac's door
// (sill-mac:7455). Sill dials 127.0.0.1:<port> with its own TLS and pinned
// keys, exactly as it dials any address of a saved Mac, so nothing above the
// socket knows a tailnet is there.
//
// Unlike Bridge's SOCKS proxy it takes no destination from the connection:
// whatever dials this port reaches the Mac's door and nothing else, and no
// other app on the device could use it to reach anything on the tailnet but
// that door, which requires Sill's own paired key anyway.
//
// Like the SOCKS proxy it outlives every tsnet node: the dial behind the port
// is swapped on a rebuild, so the address Sill dials stays the same.
type forwarder struct {
	ln     net.Listener
	target string
	// wait is how long a connection waits for a node when there is none (a
	// start or a rebuild in flight), so the first dial after a launch lands
	// once the node is up instead of failing. Sill's whole dial allows 20 s.
	wait time.Duration

	mu    sync.Mutex
	dial  DialFunc
	conns map[net.Conn]struct{}
	done  bool
}

func newForwarder(ln net.Listener, target string, dial DialFunc) *forwarder {
	return &forwarder{ln: ln, target: target, dial: dial, wait: 8 * time.Second, conns: map[net.Conn]struct{}{}}
}

func (f *forwarder) setDial(dial DialFunc) {
	f.mu.Lock()
	f.dial = dial
	f.mu.Unlock()
}

func (f *forwarder) dialer() DialFunc {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.dial
}

func (f *forwarder) serve() {
	for {
		c, err := f.ln.Accept()
		if err != nil {
			f.mu.Lock()
			done := f.done
			f.mu.Unlock()
			if done {
				return
			}
			// A revivingListener only returns an error once closed; anything
			// else is worth a pause rather than a hot loop.
			time.Sleep(50 * time.Millisecond)
			continue
		}
		go func() {
			if err := f.handle(c); err != nil {
				log.Printf("[tailnet] forward: %v", err)
			}
		}()
	}
}

func (f *forwarder) track(c net.Conn) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.done {
		return false
	}
	f.conns[c] = struct{}{}
	return true
}

func (f *forwarder) forget(c net.Conn) {
	f.mu.Lock()
	delete(f.conns, c)
	f.mu.Unlock()
}

// closeConns drops every spliced connection: the node behind them is going,
// and Sill's own reconnect is faster than a half-dead socket's timeout.
func (f *forwarder) closeConns() {
	f.mu.Lock()
	conns := f.conns
	f.conns = map[net.Conn]struct{}{}
	f.mu.Unlock()
	for c := range conns {
		_ = c.Close()
	}
}

func (f *forwarder) close() {
	f.mu.Lock()
	f.done = true
	f.mu.Unlock()
	_ = f.ln.Close()
	f.closeConns()
}

func (f *forwarder) handle(client net.Conn) error {
	if !f.track(client) {
		client.Close()
		return nil
	}
	defer f.forget(client)
	defer client.Close()
	dial := f.dialer()
	for deadline := time.Now().Add(f.wait); dial == nil && time.Now().Before(deadline); dial = f.dialer() {
		time.Sleep(100 * time.Millisecond)
		f.mu.Lock()
		done := f.done
		f.mu.Unlock()
		if done {
			return nil
		}
	}
	if dial == nil {
		return errNoTailnet
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	up, err := dial(ctx, "tcp", f.target)
	cancel()
	if err != nil {
		return err
	}
	if !f.track(up) {
		up.Close()
		return nil
	}
	defer f.forget(up)
	splice(client, up)
	return nil
}

// splice copies both ways and closes both ends once either side is done.
func splice(a, b net.Conn) {
	var once sync.Once
	closeBoth := func() { a.Close(); b.Close() }
	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(a, b); once.Do(closeBoth); done <- struct{}{} }()
	go func() { _, _ = io.Copy(b, a); once.Do(closeBoth); done <- struct{}{} }()
	<-done
	<-done
}
