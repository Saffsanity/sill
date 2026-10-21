// Package tailnet runs a Mac's private Sill tailnet inside the iOS app
// process, for Reach from Anywhere (docs/relay-plan.md). Ported from Frigate
// Launcher's tailnet-mobile, itself from Bridge's.
//
// iOS has no subprocesses, so the stack is assembled in-process:
//
//	control shim   loopback, ephemeral   what tsnet's ControlURL points at
//	tsnet          in-process            userspace WireGuard, no VPN entitlement
//	forwarder      loopback, ephemeral   what Sill dials: spliced to sill-mac:7455
//
// Nothing here needs a NetworkExtension or the VPN entitlement. tsnet is
// userspace, so the tailnet exists only inside this process, which also means
// it cannot disturb a system Tailscale the person already runs.
//
// What crosses the forwarder is Sill's own TLS 1.3 with both keys pinned, so
// this tailnet is a path, never a trust anchor: the relay, DERP and even the
// Mac's Headscale could at most refuse service.
package tailnet

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"getsill.app/tailnet-mobile/internal/invite"
	"getsill.app/tailnet-mobile/internal/shim"
	"getsill.app/tailnet-mobile/internal/state"
	"tailscale.com/envknob"
	"tailscale.com/tsnet"
)

// defaultRelays is the built-in relay list, used when the Mac's invite names
// none. A DOMAIN, not an origin: a relay routes by fingerprint subdomain
// (https://<fingerprint>.<domain>). A relay is untrusted and is checked
// against the invite's fingerprint before anything is transmitted.
var defaultRelays = []shim.Relay{
	{Name: "headfwd", Domain: "headfwd.net"},
}

// doorTarget is the Mac's node and port on its tailnet (sill-net's tsnode).
const doorTarget = "sill-mac:7455"

// Phase is the coarse state the UI reports. It exists because enrolment has no
// completion callback worth exposing across a C boundary: the app polls a
// snapshot, exactly as the desktop onboarding page polls the tray.
type Phase string

const (
	PhaseIdle      Phase = "idle"
	PhaseVerifying Phase = "verifying"
	PhaseJoining   Phase = "joining"
	PhaseRunning   Phase = "running"
	PhaseError     Phase = "error"
	// PhaseRepairing is a rebuild of a stack that believed it was running.
	// Distinct from joining so the app can keep the webview on screen rather
	// than dropping back to a connecting splash over work the user can see.
	PhaseRepairing Phase = "repairing"
	// PhaseRemoved means this device was removed from the Mac's relay: the
	// Mac's Remove deletes its node on the control plane. Distinct from error
	// because nothing can be retried: only a new key from the Mac helps.
	PhaseRemoved Phase = "removed"
)

// removedMessage is the sentence the app shows for PhaseRemoved.
const removedMessage = "This device was removed from the Mac's relay. Connect to the Mac at home to join again."

// Config is what the app hands us on start.
type Config struct {
	// PreauthKey is set only for the first join, from the Mac's kind 60 over
	// a paired session. It is used for exactly one enrolment and never
	// written to disk.
	PreauthKey string `json:"preauthKey"`
	// Fingerprint identifies the control plane on every start. The app
	// persists it; it is public, unlike the preauth key.
	Fingerprint string `json:"fingerprint"`
	// Domain is the relay's domain the Mac registered with ("headfwd.net").
	// Empty means the built-in list.
	Domain string `json:"domain"`
	// StateDir must be app-writable — the bundle is read-only and code-signed.
	StateDir string `json:"stateDir"`
	// Hostname is what this device is called on the tailnet.
	Hostname string `json:"hostname"`
	// RelayOverride replaces the built-in relay list, for staging and tests.
	RelayOverride string `json:"relayOverride"`
}

// Status is the snapshot the app polls.
type Status struct {
	Phase    Phase  `json:"phase"`
	Enrolled bool   `json:"enrolled"`
	Running  bool   `json:"running"`
	Relay    string `json:"relay"`
	// ProxyAddr is the forwarder's 127.0.0.1:<port>: what Sill dials.
	ProxyAddr string `json:"proxyAddr"`
	TailnetIP string `json:"tailnetIP"`
	// Error is a user-facing sentence when Phase is error, empty otherwise.
	Error string `json:"error"`
	// Detail carries the progress line for the current phase.
	Detail string `json:"detail"`
	// Recovering is true while Recover is working through its cheap tiers on a
	// node that is still up. Deliberately not a Phase: the node is running the
	// whole time, and the app must not treat this as a reason to leave the page.
	Recovering bool `json:"recovering"`
	// LastRecovery is what the most recent Recover did, for the app's settings
	// screen. It is how a device in someone's pocket tells us which tier is
	// actually doing the work.
	LastRecovery *Recovery `json:"lastRecovery,omitempty"`
}

// Recovery describes one finished Recover.
type Recovery struct {
	// Action is the cheapest step that got the path working: "none" (it was
	// already fine), "listeners" (a loopback socket had to be rebound),
	// "rebind" (magicsock sockets and DERP were renewed), "rebuild" (a new
	// tsnet node behind the same shim and proxy) or "rejoin" (the whole stack,
	// relay verification included). When OK is false it is the last one tried.
	Action string    `json:"action"`
	OK     bool      `json:"ok"`
	Ms     int64     `json:"ms"`
	At     time.Time `json:"at"`
}

// Controller owns the whole stack. Safe for concurrent use; the app calls in
// from its main actor and from a polling task.
type Controller struct {
	mu     sync.Mutex
	status Status
	cfg    Config
	srv    *tsnet.Server
	// The control shim outlives a node rebuild: it holds the verified relay
	// and the pin, so keeping it is what lets a rebuild skip re-verification.
	sh      *shim.Shim
	shimSrv *http.Server
	shimLn  *revivingListener
	// socks (the forwarder) outlives every tsnet node this controller
	// builds: its port is what Sill dials, so the listener is bound once and
	// the dial behind it is swapped instead.
	socks   *forwarder
	socksLn *revivingListener
	// starting guards against a second Start while one is still in flight, and
	// against a Start racing a Repair. The app calls Start again on every
	// foreground, and iOS foregrounds an app more often than is obvious.
	starting bool
	cancel   context.CancelFunc

	// recovering guards Recover's cheap tiers, which run on a live node and so
	// do not take `starting`.
	recovering bool
	// lastRebuild rate-limits the expensive tiers. A server that is simply
	// off would otherwise have every foreground tear down a healthy node.
	lastRebuild time.Time
	// suspended is set between Suspend and Resume.
	suspended bool
	// shimMoved means the shim could not get its old port back, so the running
	// node's ControlURL points at nothing. Only a rebuild re-applies it.
	shimMoved bool
	// recoverFrom and recoverAction describe a Recover that escalated into a
	// rebuild, so the rebuild's outcome can be reported against it when it
	// lands. Zero when no escalated recovery is in flight.
	recoverFrom   time.Time
	recoverAction string
}

func New() *Controller {
	return &Controller{status: Status{Phase: PhaseIdle}}
}

func (c *Controller) Status() Status {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.status
}

// Server is the running tsnet node, or nil when the stack is down.
func (c *Controller) Server() *tsnet.Server {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.status.Running {
		return nil
	}
	return c.srv
}

func (c *Controller) setStatus(mutate func(*Status)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	mutate(&c.status)
}

// markRemoved records that the control plane no longer knows this node.
func (c *Controller) markRemoved() {
	log.Printf("[tailnet] this node was logged out by its control plane; treating the device as removed")
	c.setStatus(func(s *Status) {
		s.Phase = PhaseRemoved
		s.Running = false
		s.Error = removedMessage
	})
	c.finishRecovery(false)
}

// loggedOut reports whether a backend state means the control plane has
// dropped this node. NeedsMachineAuth is included because an admin-disabled
// node lands there on some control-plane versions.
func loggedOut(state string) bool {
	return state == "NeedsLogin" || state == "NeedsMachineAuth"
}

func (c *Controller) fail(err error, detail string) {
	log.Printf("[tailnet] %v", err)
	c.setStatus(func(s *Status) {
		s.Phase = PhaseError
		s.Running = false
		s.Error = detail
	})
	c.finishRecovery(false)
}

// Start brings the stack up in the background and returns immediately.
//
// Returning early is what lets the onboarding UI show progress: verification
// reaches out to a relay over the public internet and enrolment waits on a
// control round-trip, so a synchronous call would block the caller for seconds
// with nothing to display.
//
// Safe to call repeatedly. An already-running stack is left alone, which is
// what makes "start on every foreground" the correct thing for the app to do.
//
// Note what that early return cannot do: status.Running is a latch, so a node
// that is up but wedged is left alone here too, and calling Start again will
// never revive it. Repair is the way past that, and is what the app's retry
// paths use.
func (c *Controller) Start(cfg Config) error {
	c.mu.Lock()
	if c.starting {
		c.mu.Unlock()
		return nil
	}
	sameNet := strings.EqualFold(strings.TrimSpace(c.cfg.Fingerprint), strings.TrimSpace(cfg.Fingerprint))
	if c.status.Running && cfg.PreauthKey == "" && sameNet {
		c.mu.Unlock()
		return nil
	}
	// Another Mac's tailnet (its own state dir): the node up now is not it.
	switchNet := c.status.Running && !sameNet
	c.starting = true
	c.cfg = cfg
	c.mu.Unlock()

	// A preauth key means "re-enrol", and another fingerprint another
	// tailnet, so tear down whatever is up first.
	if cfg.PreauthKey != "" || switchNet {
		c.Stop()
		c.mu.Lock()
		c.starting = true
		c.mu.Unlock()
	}

	fp := strings.ToLower(strings.TrimSpace(cfg.Fingerprint))
	preauth := strings.TrimSpace(cfg.PreauthKey)
	if !invite.IsFingerprint(fp) {
		err := errors.New("no valid control-plane fingerprint")
		c.mu.Lock()
		c.starting = false
		c.mu.Unlock()
		c.fail(err, "This device has not joined the Mac's relay yet.")
		return err
	}
	if strings.TrimSpace(cfg.StateDir) == "" {
		err := errors.New("stateDir is required")
		c.mu.Lock()
		c.starting = false
		c.mu.Unlock()
		c.fail(err, "The app could not find a place to store its network state.")
		return err
	}

	// Synchronously, so the very first status the app reads after Start
	// already carries the proxy address. See publishProxyEarly.
	c.publishProxyEarly()

	go c.run(fp, preauth)
	return nil
}

// publishProxyEarly binds the forwarder before any node exists, with no dial
// behind it, and publishes its address, so a dial made before the node is up
// fails at once rather than hanging. bringUp later swaps the real dial in
// behind the same port.
func (c *Controller) publishProxyEarly() {
	addr, err := c.ensureProxy(nil)
	if err != nil {
		// Not fatal here: bringUp binds it again and reports the failure
		// properly if the port really cannot be had.
		log.Printf("[tailnet] early proxy bind: %v", err)
		return
	}
	c.setStatus(func(s *Status) { s.ProxyAddr = addr })
}

// run is the full path: open state, verify the control plane through a relay,
// start the shim, and bring a node up behind it. Everything a first launch
// needs, and the last resort for recovery.
func (c *Controller) run(fingerprint, preauthKey string) {
	defer func() {
		c.mu.Lock()
		c.starting = false
		c.mu.Unlock()
	}()

	cfg := c.cfg

	// Opt out of Tailscale's log upload before anything starts. tsnet wires
	// up logtail unconditionally, which ships client logs to
	// log.tailscale.io; this control plane is the Mac's own, and nobody agreed
	// to that upload. With this set, logging stays local.
	envknob.SetNoLogsNoSupport()

	// Whatever a previous attempt left behind goes first. A full run builds
	// its own shim, and a stale one would keep serving the old relay choice.
	c.teardownNode()
	c.stopShim()
	// A rejoin from Recover comes through here without Start, and teardown
	// just pointed the proxy at nothing; keep its address published.
	c.publishProxyEarly()

	// 0700: the pinned control-plane key lives here. Not a secret, but nothing
	// else has any business rewriting the thing we verify the server against.
	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		c.fail(fmt.Errorf("create state dir: %w", err), "The app could not write to its storage.")
		return
	}

	store, err := state.Open(filepath.Join(cfg.StateDir, "state.json"))
	if err != nil {
		c.fail(fmt.Errorf("open state: %w", err), "The app could not read its saved network settings.")
		return
	}

	relays := defaultRelays
	if d := strings.TrimSpace(cfg.Domain); d != "" {
		relays = []shim.Relay{{Name: d, Domain: d}}
	}
	if o := strings.TrimSpace(cfg.RelayOverride); o != "" {
		relays = parseRelays(o)
		if len(relays) == 0 {
			c.fail(errors.New("relay override contained no usable entries"),
				"The configured relay list is empty.")
			return
		}
	}

	sh := shim.New(fingerprint, relays, store)

	c.setStatus(func(s *Status) {
		s.Phase = PhaseVerifying
		s.Error = ""
		s.Detail = "Checking the relay answers for this Mac"
	})

	// Verify, then speak. This must complete before the preauth key is handed
	// to tsnet: a relay that can answer the identity request with a key of its
	// own choosing impersonates the control plane and harvests the credential
	// on first contact. The ordering is the entire reason a relay can be
	// untrusted infrastructure.
	//
	// A device that already holds a pin asks every relay at once and takes the
	// first that matches it. Nothing about the security changes — each answer
	// is still checked against the pin — but a relay that is slow or down no
	// longer costs its whole timeout before the next one is tried, and that
	// wait was most of the "Reconnecting" screen.
	verifyCtx, cancelVerify := context.WithTimeout(context.Background(), 30*time.Second)
	if preauthKey == "" && sh.PinnedKey() != "" {
		_, err = sh.VerifyPinnedFirst(verifyCtx)
	} else {
		_, err = sh.VerifyAndPin(verifyCtx)
	}
	cancelVerify()
	if err != nil {
		c.fail(fmt.Errorf("verify control plane: %w", err), verifyFailureMessage(err))
		return
	}
	relayName := sh.CurrentRelay()
	log.Printf("[tailnet] verified control plane via %s", relayName)
	c.setStatus(func(s *Status) {
		s.Relay = relayName
		s.Phase = PhaseJoining
		s.Detail = "Registering this device"
	})

	if err := c.startShim(sh); err != nil {
		c.fail(fmt.Errorf("bind control shim: %w", err), "The app could not open a local port.")
		return
	}

	c.bringUp(preauthKey)
}

// rebuildNode replaces the tsnet node and nothing else.
//
// The shim is kept, which is the point: it already holds the verified relay and
// the pin, so the new node goes straight to the control round trip without the
// public-internet verification that dominates a full run. Only valid while the
// shim still answers on the port the node's ControlURL names.
func (c *Controller) rebuildNode() {
	defer func() {
		c.mu.Lock()
		c.starting = false
		c.mu.Unlock()
	}()
	c.bringUp("")
}

// startShim binds the control shim on a loopback listener that survives iOS
// reclaiming it.
//
// The shim listens on an ephemeral loopback port, unlike the desktop's fixed
// 8720. tailscaled persists its control URL in a state file and must find the
// shim again after a restart, which forces a fixed port there. tsnet re-applies
// ControlURL from the Server struct on every start, so there is nothing to keep
// stable across launches — and an ephemeral port cannot collide with whatever
// else happens to be listening on the device. Within one node's life it DOES
// have to stay put, which is what the reviving listener is for.
func (c *Controller) startShim(sh *shim.Shim) error {
	ln, err := listenLoopback("shim")
	if err != nil {
		return err
	}
	srv := &http.Server{Handler: sh.Handler(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Printf("[tailnet] control shim stopped: %v", err)
		}
	}()
	c.mu.Lock()
	c.sh, c.shimSrv, c.shimLn, c.shimMoved = sh, srv, ln, false
	c.mu.Unlock()
	return nil
}

func (c *Controller) stopShim() {
	c.mu.Lock()
	srv := c.shimSrv
	c.sh, c.shimSrv, c.shimLn, c.shimMoved = nil, nil, nil, false
	c.mu.Unlock()
	if srv != nil {
		// Closes the listener too: http.Server tracks what it serves on.
		_ = srv.Close()
	}
}

// teardownNode closes the current tsnet node, pointing the proxy at nothing
// first so a request arriving mid-teardown fails fast instead of being dialled
// into a netstack that is closing underneath it.
func (c *Controller) teardownNode() {
	c.mu.Lock()
	srv, socks, cancel := c.srv, c.socks, c.cancel
	c.srv, c.cancel = nil, nil
	c.mu.Unlock()

	if socks != nil {
		socks.setDial(nil)
		socks.closeConns()
	}
	if cancel != nil {
		cancel()
	}
	if srv != nil {
		_ = srv.Close()
	}
}

// bringUp starts a tsnet node against the current shim and points the proxy at
// it. Callers hold `starting`.
func (c *Controller) bringUp(preauthKey string) {
	c.mu.Lock()
	cfg := c.cfg
	shimLn := c.shimLn
	c.mu.Unlock()
	if shimLn == nil {
		c.fail(errors.New("no control shim"), "The app could not open a local port.")
		return
	}
	controlURL := "http://" + shimLn.AddrString()

	srv := &tsnet.Server{
		Dir:        filepath.Join(cfg.StateDir, "tsnet"),
		Hostname:   sanitizeHostname(cfg.Hostname),
		ControlURL: controlURL,
		// Not ephemeral: an ephemeral node is reaped by the control plane when
		// it disconnects, and a phone disconnects every time it is locked. The
		// node identity has to survive that, or the device would need a fresh
		// invite after every screen lock.
		Ephemeral: false,
		Logf:      func(format string, args ...any) { log.Printf("[tsnet] "+format, args...) },
	}
	// The preauth key is passed in memory and only for the first enrolment.
	// tsnet ignores it once the node has state, which is exactly right: these
	// keys are single-use, so a spent one must never be retried or persisted.
	if preauthKey != "" {
		srv.AuthKey = preauthKey
	}
	// AdvertiseTags is deliberately unset. The key is already tagged
	// server-side (tag:sill-device), and asking for tags here would conflict
	// with what the key grants.

	upCtx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	c.mu.Lock()
	c.srv = srv
	c.cancel = cancel
	c.mu.Unlock()

	// A rejoin of a node that was deleted on the control plane never errors:
	// tsnet.Up sits in NeedsLogin until its context expires, because it cannot
	// tell that from the brief NeedsLogin a fresh key passes through. Without
	// a key there is no such transient, so a node that stays logged out for a
	// few seconds on a keyless start is one the Mac removed.
	var removed atomic.Bool
	if preauthKey == "" {
		go func() {
			streak := 0
			for {
				select {
				case <-upCtx.Done():
					return
				case <-time.After(3 * time.Second):
				}
				lc, err := srv.LocalClient()
				if err != nil {
					continue
				}
				st, err := lc.StatusWithoutPeers(upCtx)
				if err != nil || st == nil {
					continue
				}
				if loggedOut(st.BackendState) {
					streak++
				} else {
					streak = 0
				}
				if streak >= 2 {
					removed.Store(true)
					cancel()
					return
				}
			}
		}()
	}

	st, err := srv.Up(upCtx)
	cancel()
	if err != nil {
		_ = srv.Close()
		c.mu.Lock()
		if c.srv == srv {
			c.srv, c.cancel = nil, nil
		}
		c.mu.Unlock()
		if removed.Load() {
			c.markRemoved()
			return
		}
		c.fail(fmt.Errorf("join tailnet: %w", err), joinFailureMessage(err, preauthKey != ""))
		return
	}

	ip := ""
	if len(st.TailscaleIPs) > 0 {
		ip = st.TailscaleIPs[0].String()
	}
	log.Printf("[tailnet] joined the tailnet as %s", ip)

	// The forwarder is what Sill dials. Bound once per process and pointed at
	// each new tsnet node, so its address stays the same across a rebuild.
	proxyAddr, err := c.ensureProxy(srv.Dial)
	if err != nil {
		c.fail(fmt.Errorf("bind proxy: %w", err), "The app could not open a local port.")
		return
	}

	c.setStatus(func(s *Status) {
		s.Phase = PhaseRunning
		s.Enrolled = true
		s.Running = true
		s.ProxyAddr = proxyAddr
		s.TailnetIP = ip
		s.Error = ""
		s.Detail = "This device is on the Mac's relay"
	})
	c.finishRecovery(true)
}

// ensureProxy binds the forwarder on first use and points it at dial.
//
// Returns the address, which is stable for the life of the process unless iOS
// took the port and something else claimed it before it could be rebound.
func (c *Controller) ensureProxy(dial DialFunc) (string, error) {
	c.mu.Lock()
	socks, ln := c.socks, c.socksLn
	c.mu.Unlock()

	if socks != nil {
		// The node was down for a while; make sure the listener survived it.
		ln.Check()
		socks.setDial(dial)
		return ln.AddrString(), nil
	}

	ln, err := listenLoopback("forward")
	if err != nil {
		return "", err
	}
	socks = newForwarder(ln, doorTarget, dial)
	go socks.serve()

	c.mu.Lock()
	c.socks = socks
	c.socksLn = ln
	c.mu.Unlock()

	addr := ln.AddrString()
	log.Printf("[tailnet] forwarder on %s to %s", addr, doorTarget)
	return addr, nil
}

// Health reports whether the tailnet is genuinely usable right now.
//
// Deliberately not a read of Status.Running, which is a latch: it is set when a
// node comes up and cleared only by Stop or a failure, so a node whose
// transport has died still reports true. This asks the node itself. It is the
// cheap check; Probe is the thorough one.
func (c *Controller) Health() (bool, Phase) {
	c.mu.Lock()
	srv, phase, running := c.srv, c.status.Phase, c.status.Running
	c.mu.Unlock()

	if srv == nil || !running {
		return false, phase
	}
	// LocalClient talks to the node's own local API. A node whose netstack has
	// gone away fails here, which is the signal Status cannot give us.
	lc, err := srv.LocalClient()
	if err != nil {
		return false, phase
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := lc.Status(ctx)
	if err != nil || st == nil {
		return false, phase
	}
	// A running node the control plane has since deleted drops to NeedsLogin
	// at its next map poll. That is not a transport fault Recover could fix,
	// so say what it is.
	if loggedOut(st.BackendState) {
		c.markRemoved()
		return false, PhaseRemoved
	}
	return st.BackendState == "Running", phase
}

// Repair rebuilds a stack that believes it is running but is not.
//
// This exists because Start cannot do it. Start returns early when
// status.Running is true, and Running is a latch — so a tsnet node that is up
// but wedged (the common case after a phone has moved between networks or been
// suspended for a while) is immune to every recovery path the app has: the
// foreground start, the backoff retry, and the user's own Try again button.
// Force-quitting the app was the only way out, because it was the only thing
// that cleared the latch.
//
// The forwarder is deliberately left alone, so the port Sill dials never
// changes. So is the shim,
// when it is still answering where the node expects it: the relay has already
// been verified, and redoing that over the public internet is the slow half of
// a rebuild. Recover is usually the better entry point; this is the forced
// version of its expensive tier.
func (c *Controller) Repair() error {
	if err := c.repair(time.Time{}); err != nil && !errors.Is(err, errBusy) {
		return err
	}
	return nil
}

// errBusy means a start or rebuild is already in flight, so nothing new began.
var errBusy = errors.New("a start or rebuild is already in progress")

// repair is Repair, optionally on behalf of a Recover that started at
// `recoverStart`, so the rebuild's outcome lands in Status.LastRecovery.
func (c *Controller) repair(recoverStart time.Time) error {
	c.mu.Lock()
	if c.starting {
		c.mu.Unlock()
		return errBusy
	}
	fp := strings.TrimSpace(c.cfg.Fingerprint)
	if fp == "" {
		c.mu.Unlock()
		return errors.New("this device has not joined the Mac's relay")
	}
	c.starting = true
	c.lastRebuild = time.Now()
	keepShim := c.sh != nil && c.shimLn != nil && !c.shimMoved
	c.status.Phase = PhaseRepairing
	c.status.Running = false
	c.status.Error = ""
	c.status.Detail = "Reconnecting to the Mac's relay"
	c.mu.Unlock()

	c.teardownNode()

	if keepShim {
		// The shim answering is part of the premise; make sure of it.
		c.mu.Lock()
		shimLn := c.shimLn
		c.mu.Unlock()
		if shimLn.Check() && shimLn.AddrString() != "" {
			log.Printf("[tailnet] shim listener revived before rebuild")
		}
		c.noteRecovery(recoverStart, "rebuild")
		log.Printf("[tailnet] repairing: rebuilding the node behind the existing shim and proxy")
		go c.rebuildNode()
		return nil
	}
	c.noteRecovery(recoverStart, "rejoin")
	log.Printf("[tailnet] repairing: full rejoin behind the existing proxy")
	go c.run(fp, "")
	return nil
}

// Stop tears the stack down. Idempotent.
func (c *Controller) Stop() {
	c.mu.Lock()
	socks := c.socks
	c.socks, c.socksLn = nil, nil
	// Unlike Repair, a Stop really does release the port: the next Start binds
	// a fresh one, which the status names.
	c.status.Running = false
	c.status.ProxyAddr = ""
	c.status.TailnetIP = ""
	c.status.Recovering = false
	if c.status.Phase == PhaseRunning {
		c.status.Phase = PhaseIdle
	}
	c.suspended = false
	c.recovering = false
	c.recoverFrom, c.recoverAction = time.Time{}, ""
	c.mu.Unlock()

	// Forwarder first: it holds connections dialled through tsnet, and
	// closing tsnet out from under them just produces noise.
	if socks != nil {
		socks.close()
	}
	c.teardownNode()
	c.stopShim()
}

// sanitizeHostname reduces a device name to something a control plane accepts.
//
// iOS device names are free text and, since iOS 16, usually just "iPhone";
// Tailscale would mangle them itself.
func sanitizeHostname(name string) string {
	name = strings.TrimSpace(strings.ToLower(name))
	if name == "" {
		return "sill-device"
	}
	var b strings.Builder
	lastDash := false
	for _, r := range name {
		switch {
		case (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'):
			b.WriteRune(r)
			lastDash = false
		default:
			if !lastDash && b.Len() > 0 {
				b.WriteByte('-')
				lastDash = true
			}
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		return "sill-device"
	}
	if len(out) > 63 {
		out = strings.Trim(out[:63], "-")
	}
	return out
}

// parseRelays reads a comma-separated override list. Entries are domains, or
// full origins for a local test relay that has neither wildcard DNS nor a
// certificate.
func parseRelays(spec string) []shim.Relay {
	var out []shim.Relay
	for _, raw := range strings.Split(spec, ",") {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if strings.HasPrefix(entry, "http://") || strings.HasPrefix(entry, "https://") {
			name := entry
			if u := strings.SplitN(strings.TrimPrefix(strings.TrimPrefix(entry, "https://"), "http://"), "/", 2); len(u) > 0 {
				name = u[0]
			}
			out = append(out, shim.RelayAtOrigin(name, entry))
			continue
		}
		out = append(out, shim.Relay{Name: entry, Domain: entry})
	}
	return out
}

// verifyFailureMessage separates "we could not reach the control plane" from
// "something served the wrong identity". They need opposite responses from the
// user, and collapsing them into one message sends people after the wrong
// problem — the case the relay's own 503-vs-400 distinction exists for.
func verifyFailureMessage(err error) string {
	msg := err.Error()
	switch {
	case strings.Contains(msg, "fingerprint_mismatch"):
		return "The relay answered with another Mac's identity. Something may be impersonating your Mac's relay; nothing was sent."
	case strings.Contains(msg, "pin_mismatch"):
		return "The Mac's relay identity changed since this device joined. Connect to the Mac at home to join again."
	case strings.Contains(msg, "not connected to it"):
		return "The Mac isn't connected to its relay right now: it may be asleep, off, or offline."
	default:
		return "Couldn't reach the Mac's relay. Check this device's internet connection."
	}
}

func joinFailureMessage(err error, hadKey bool) string {
	if hadKey {
		return "This device couldn't join the Mac's relay. Connect to the Mac at home to try again."
	}
	return "This device couldn't rejoin the Mac's relay. It may have been removed; connect to the Mac at home to join again."
}

// StatusJSON is the serialized snapshot handed across the C boundary.
func (c *Controller) StatusJSON() string {
	b, err := json.Marshal(c.Status())
	if err != nil {
		return `{"phase":"error","error":"could not encode status"}`
	}
	return string(b)
}
