package tailnet

import (
	"context"
	"errors"
	"log"
	"strings"
	"time"
)

// DefaultProbeTarget is what Recover dials when the app does not say: the
// Mac's door, the forwarder's own target.
const DefaultProbeTarget = doorTarget

// rebuildInterval is the least time between two node rebuilds that Recover will
// start on its own. A rebuild is a control round trip and a fresh join; worth
// doing promptly once, and not worth repeating while the server is simply off.
const rebuildInterval = 10 * time.Second

// Suspend releases the loopback listeners ahead of iOS suspending the app.
//
// Apple's guidance for listening sockets is to close them before the app can
// be suspended and reopen them afterwards (TN2277): a listener left open may
// have its resources reclaimed while suspended, after which it refuses every
// connection while looking fine from inside the process. The tsnet node itself
// stays in memory — rebuilding it is exactly the cost this avoids — and the
// ports are remembered so Resume can bind the same ones, which is what keeps
// the webview's proxy configuration and the node's ControlURL valid.
func (c *Controller) Suspend() {
	c.mu.Lock()
	if c.suspended {
		c.mu.Unlock()
		return
	}
	c.suspended = true
	socksLn, shimLn := c.socksLn, c.shimLn
	c.mu.Unlock()

	if socksLn != nil {
		socksLn.Suspend()
	}
	if shimLn != nil {
		shimLn.Suspend()
	}
	log.Printf("[tailnet] suspended: loopback listeners released")
}

// Resume binds the listeners Suspend released, on the same ports where it can.
func (c *Controller) Resume() {
	c.mu.Lock()
	if !c.suspended {
		c.mu.Unlock()
		return
	}
	c.suspended = false
	socksLn, shimLn := c.socksLn, c.shimLn
	c.mu.Unlock()

	if socksLn != nil && socksLn.Resume() {
		// Something took the port while we were away. The app reads the new
		// address from the status before it dials again.
		addr := socksLn.AddrString()
		c.setStatus(func(s *Status) {
			if s.ProxyAddr != "" {
				s.ProxyAddr = addr
			}
		})
	}
	if shimLn != nil && shimLn.Resume() {
		c.mu.Lock()
		c.shimMoved = true
		c.mu.Unlock()
	}
	log.Printf("[tailnet] resumed: loopback listeners rebound")
}

// probeResult says how far a Probe got.
type probeResult struct {
	ok bool
	// revived is true when a loopback listener had to be rebound first.
	revived bool
	err     error
}

// Probe checks the path Sill actually uses, end to end.
//
// Listeners first, because a reclaimed loopback socket is invisible to every
// other check. Then a real TCP dial to the Mac's door through the node, which
// is the only test that exercises WireGuard, DERP and the netmap together.
// Health's BackendState answer stays "Running" through all of those failing.
//
// A dial the server refuses counts as success: a refusal can only come back
// across a working tailnet, so what is down is Sill on the Mac, not this device's
// network — and rebuilding the node would not help.
func (c *Controller) probe(target string, timeout time.Duration) probeResult {
	c.mu.Lock()
	srv, running, socksLn, shimLn := c.srv, c.status.Running, c.socksLn, c.shimLn
	c.mu.Unlock()

	var res probeResult
	if socksLn != nil {
		if socksLn.Check() {
			res.revived = true
			addr := socksLn.AddrString()
			c.setStatus(func(s *Status) {
				if s.ProxyAddr != "" && s.ProxyAddr != addr {
					s.ProxyAddr = addr
				}
			})
		}
	}
	if shimLn != nil {
		before := shimLn.AddrString()
		if shimLn.Check() {
			res.revived = true
			if shimLn.AddrString() != before {
				c.mu.Lock()
				c.shimMoved = true
				c.mu.Unlock()
			}
		}
	}

	if srv == nil || !running {
		res.err = errors.New("the tailnet is not running")
		return res
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	conn, err := srv.Dial(ctx, "tcp", target)
	if err == nil {
		_ = conn.Close()
		res.ok = true
		return res
	}
	if strings.Contains(err.Error(), "refused") {
		res.ok = true
		return res
	}
	res.err = err
	return res
}

// Recover gets the path to the Mac working again, trying the cheapest thing
// that could work first. Returns false when nothing was started — a rebuild or
// another recovery is already in flight, or the device has never enrolled.
//
// The tiers, each tried only when the one before did not restore a working
// dial to `target`:
//
//  1. Loopback listeners: rebind any the OS reclaimed (see revivingListener).
//     Free, and after a long lock the most likely fix.
//  2. Rebind: ask magicsock for fresh UDP sockets, re-STUN, and drop the DERP
//     connections so they redial. This is what a network change needs and is
//     far cheaper than a new node — no control round trip, no re-login.
//  3. Rebuild: a new tsnet node behind the existing shim and proxy, skipping
//     relay verification because the shim already holds a verified relay.
//  4. Rejoin: the full start, verification included, when the shim itself
//     cannot be kept.
//
// Tiers 3 and 4 are rate-limited to one per rebuildInterval, so a server that
// is simply down does not make every foreground tear down a healthy node.
// The outcome, including which tier did the work, is left in
// Status.LastRecovery.
func (c *Controller) Recover(target string) bool {
	if strings.TrimSpace(target) == "" {
		target = DefaultProbeTarget
	}
	start := time.Now()

	// Rebind anything Suspend released before looking at anything else. The
	// app is meant to call Resume on the way back to the foreground, but a
	// recovery that finds the listeners deliberately closed would otherwise
	// probe, fail, and escalate to a full rebuild over a problem that one
	// bind fixes. A VoIP push waking the app mid-grace is exactly that case.
	c.Resume()

	c.mu.Lock()
	if c.starting || c.recovering {
		c.mu.Unlock()
		return false
	}
	if strings.TrimSpace(c.cfg.Fingerprint) == "" {
		c.mu.Unlock()
		return false
	}
	// A verification failure is not transient. Something served an identity
	// this invite does not vouch for, and quietly trying again would bury the
	// one message the user needs to see — the same rule the app's own retry
	// follows.
	if c.status.Phase == PhaseError && isIdentityFailure(c.status.Error) {
		c.mu.Unlock()
		return false
	}
	running := c.srv != nil && c.status.Running
	if !running {
		// Nothing up to recover cheaply. A node that failed or never came up
		// needs a start, which repair does with the right choice of shim.
		c.mu.Unlock()
		log.Printf("[tailnet] recover: node not running; rebuilding")
		return c.repair(start) == nil
	}
	// Tier 1 onwards run on the live node. `recovering` keeps a second Recover
	// out; a Repair can still interleave, and repair() tolerates that.
	c.recovering = true
	c.status.Recovering = true
	c.mu.Unlock()

	go c.recoverTiers(target, start)
	return true
}

func (c *Controller) recoverTiers(target string, start time.Time) {
	done := func(action string, ok bool) {
		c.mu.Lock()
		c.recovering = false
		c.status.Recovering = false
		c.status.LastRecovery = &Recovery{Action: action, OK: ok, Ms: time.Since(start).Milliseconds(), At: time.Now()}
		c.mu.Unlock()
		log.Printf("[tailnet] recover: %s (ok=%v) in %v", action, ok, time.Since(start).Round(time.Millisecond))
	}

	// Tier 1: listeners, then the probe.
	res := c.probe(target, 3*time.Second)
	action := "none"
	if res.revived {
		action = "listeners"
	}
	c.mu.Lock()
	shimMoved := c.shimMoved
	c.mu.Unlock()
	if res.ok && !shimMoved {
		done(action, true)
		return
	}
	if !res.ok {
		log.Printf("[tailnet] recover: probe failed after listener check: %v", res.err)
	}

	// Tier 2: renew magicsock and DERP in place. Skipped when the shim moved,
	// because the node's ControlURL now points at a port nobody answers on and
	// only a new node picks up the new one.
	if !shimMoved {
		c.mu.Lock()
		srv := c.srv
		c.mu.Unlock()
		if srv != nil {
			if lc, err := srv.LocalClient(); err == nil {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				for _, a := range []string{"rebind", "restun", "break-derp-conns"} {
					if err := lc.DebugAction(ctx, a); err != nil {
						log.Printf("[tailnet] recover: %s: %v", a, err)
					}
				}
				cancel()
			}
		}
		// DERP needs a moment to redial and the first handshake after a rebind
		// can be slow, so give it a few tries rather than one.
		deadline := time.Now().Add(8 * time.Second)
		for time.Now().Before(deadline) {
			if r := c.probe(target, 2500*time.Millisecond); r.ok {
				done("rebind", true)
				return
			}
			time.Sleep(500 * time.Millisecond)
		}
	}

	// Tiers 3/4: a new node.
	c.mu.Lock()
	tooSoon := !c.lastRebuild.IsZero() && time.Since(c.lastRebuild) < rebuildInterval && !shimMoved
	if tooSoon {
		c.mu.Unlock()
		done("rebind", false)
		return
	}
	c.mu.Unlock()
	err := c.repair(start)
	c.mu.Lock()
	c.recovering = false
	c.status.Recovering = false
	c.mu.Unlock()
	switch {
	case errors.Is(err, errBusy):
		// Someone else's rebuild is already running; it will report itself.
	case err != nil:
		done("rebuild", false)
	}
}

// isIdentityFailure matches the user-facing sentences verifyFailureMessage
// produces for a fingerprint or pin mismatch.
func isIdentityFailure(msg string) bool {
	return strings.Contains(msg, "impersonating") || strings.Contains(msg, "identity changed")
}

// noteRecovery records that a rebuild is being done on behalf of a Recover,
// so its outcome can be reported when bringUp or fail finishes it.
func (c *Controller) noteRecovery(start time.Time, action string) {
	if start.IsZero() {
		return
	}
	c.mu.Lock()
	c.recoverFrom, c.recoverAction = start, action
	c.mu.Unlock()
}

// finishRecovery closes out a recovery that escalated to a rebuild. A no-op when
// none is pending, so every success and failure path can call it.
func (c *Controller) finishRecovery(ok bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.recoverFrom.IsZero() {
		return
	}
	c.status.LastRecovery = &Recovery{
		Action: c.recoverAction,
		OK:     ok,
		Ms:     time.Since(c.recoverFrom).Milliseconds(),
		At:     time.Now(),
	}
	log.Printf("[tailnet] recover: %s (ok=%v) in %v", c.recoverAction, ok, time.Since(c.recoverFrom).Round(time.Millisecond))
	c.recoverFrom, c.recoverAction = time.Time{}, ""
}
