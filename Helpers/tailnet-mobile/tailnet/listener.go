package tailnet

import (
	"log"
	"net"
	"sync"
	"time"
)

// revivingListener is a loopback listener that survives iOS reclaiming its
// socket.
//
// When an app is suspended, iOS may take back the resources behind its sockets
// (Apple TN2277, "Networking and Multitasking"). A listening socket this happens
// to is left defunct: dials to its port are refused, and Accept on it never
// returns — it does not even fail, so nothing inside the process notices. Both
// of this package's loopback listeners are exposed to that: the SOCKS5 proxy,
// whose port is baked into WKWebView's proxy configuration, and the control
// shim, whose port is baked into the tsnet node's ControlURL. Losing either
// looked, from the phone, exactly like the server being down, and no amount of
// rebuilding the tailnet behind them fixed it.
//
// Three ways back, all keeping the SAME port, because the port is what the
// webview and tsnet hold:
//
//   - Check dials the port and re-listens if nothing answers. This is the only
//     reliable detector, since a defunct socket's Accept just blocks.
//   - Accept re-listens when the socket errors rather than giving up.
//   - Suspend/Resume close the socket before the app can be suspended and bind
//     it again after — the approach Apple recommends for listeners outright.
//
// It satisfies net.Listener, so the SOCKS server and the shim's http.Server use
// it without knowing.
type revivingListener struct {
	name string

	mu        sync.Mutex
	ln        net.Listener
	addr      string // host:port, stable unless the port could not be rebound
	closed    bool
	suspended bool
	// changed is closed (and replaced) whenever ln changes, so an Accept parked
	// on a suspended listener wakes as soon as there is something to accept on.
	changed chan struct{}
}

// listenLoopback binds a fresh loopback listener on an ephemeral port.
func listenLoopback(name string) (*revivingListener, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	return newRevivingListener(name, ln), nil
}

func newRevivingListener(name string, ln net.Listener) *revivingListener {
	return &revivingListener{
		name:    name,
		ln:      ln,
		addr:    ln.Addr().String(),
		changed: make(chan struct{}),
	}
}

// swapLocked replaces the inner listener and wakes anything waiting on it.
func (l *revivingListener) swapLocked(ln net.Listener) {
	l.ln = ln
	if ln != nil {
		l.addr = ln.Addr().String()
	}
	close(l.changed)
	l.changed = make(chan struct{})
}

func (l *revivingListener) Accept() (net.Conn, error) {
	for {
		l.mu.Lock()
		ln, closed, changed := l.ln, l.closed, l.changed
		l.mu.Unlock()
		if closed {
			return nil, net.ErrClosed
		}
		if ln == nil {
			// Suspended, or a rebind failed. Wait for Resume or a Check to put
			// a socket back rather than spinning.
			select {
			case <-changed:
			case <-time.After(time.Second):
			}
			continue
		}

		conn, err := ln.Accept()
		if err == nil {
			return conn, nil
		}

		l.mu.Lock()
		switch {
		case l.closed:
			l.mu.Unlock()
			return nil, net.ErrClosed
		case l.ln != ln || l.suspended:
			// Replaced by Check or Resume, or deliberately closed by Suspend.
			// Not a failure: go round and pick up whatever is current.
			l.mu.Unlock()
			continue
		}
		// The socket failed underneath us. Re-listen on the same port.
		log.Printf("[listener] %s accept failed (%v); re-listening on %s", l.name, err, l.addr)
		_ = ln.Close()
		l.relistenLocked()
		l.mu.Unlock()
	}
}

// relistenLocked binds the remembered address again, falling back to a fresh
// port if something else took it. Returns whether the address changed.
func (l *revivingListener) relistenLocked() bool {
	old := l.addr
	ln, err := net.Listen("tcp", old)
	if err != nil {
		// Losing the port is worse than a moved port but far better than no
		// listener: the caller learns of the move through Addr and can
		// re-point whatever held the old one.
		log.Printf("[listener] %s could not rebind %s (%v); taking a fresh port", l.name, old, err)
		ln, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			log.Printf("[listener] %s could not listen at all: %v", l.name, err)
			l.swapLocked(nil)
			return false
		}
	}
	l.swapLocked(ln)
	if l.addr != old {
		log.Printf("[listener] %s moved %s -> %s", l.name, old, l.addr)
		return true
	}
	log.Printf("[listener] %s re-listening on %s", l.name, l.addr)
	return false
}

// Check dials the listener and rebinds it if nothing answers. Returns whether
// the socket had to be replaced.
//
// The dial is what makes this work: a defunct socket's Accept blocks forever,
// so the only symptom visible from inside the process is a refused connect.
func (l *revivingListener) Check() (revived bool) {
	l.mu.Lock()
	ln, addr, closed, suspended := l.ln, l.addr, l.closed, l.suspended
	l.mu.Unlock()
	if closed || suspended {
		return false
	}
	if ln != nil {
		c, err := net.DialTimeout("tcp", addr, time.Second)
		if err == nil {
			_ = c.Close()
			return false
		}
		log.Printf("[listener] %s not answering on %s: %v", l.name, addr, err)
	}

	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed || l.suspended || l.ln != ln {
		// Someone else already dealt with it.
		return false
	}
	if ln != nil {
		_ = ln.Close()
	}
	l.relistenLocked()
	return true
}

// Suspend closes the socket but remembers its address, so Resume can bind the
// same port again. Accept parks rather than failing in between.
func (l *revivingListener) Suspend() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed || l.suspended {
		return
	}
	l.suspended = true
	if l.ln != nil {
		_ = l.ln.Close()
	}
	l.swapLocked(nil)
}

// Resume rebinds after Suspend. Returns whether the address changed.
func (l *revivingListener) Resume() (moved bool) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed || !l.suspended {
		return false
	}
	l.suspended = false
	return l.relistenLocked()
}

func (l *revivingListener) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.closed {
		return net.ErrClosed
	}
	l.closed = true
	var err error
	if l.ln != nil {
		err = l.ln.Close()
	}
	l.swapLocked(nil)
	return err
}

func (l *revivingListener) Addr() net.Addr {
	l.mu.Lock()
	defer l.mu.Unlock()
	addr, err := net.ResolveTCPAddr("tcp", l.addr)
	if err != nil {
		return &net.TCPAddr{}
	}
	return addr
}

// AddrString is Addr without the round trip through net.TCPAddr.
func (l *revivingListener) AddrString() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.addr
}
