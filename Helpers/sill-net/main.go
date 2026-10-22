// Command sill-net gives Sill for Mac a way in from anywhere without a port
// forward or a VPN account: Reach from Anywhere (docs/relay-plan.md).
//
// It owns, in order of startup:
//
//  1. Headscale, the control plane of this Mac's own private tailnet, run as a
//     supervised child with a config and a static ACL policy sill-net writes.
//  2. Headscale's admin API key and every preauth key (one per invite, single
//     use, ten minutes, tagged tag:sill-device), recorded per paired device.
//  3. Registration with a HeadFwd relay (headfwd.net by default), so devices
//     reach this Headscale behind NAT through https://<fingerprint>.<relay>.
//     The relay sees only Noise-sealed control traffic and cannot pose as
//     this Headscale: devices pin its key.
//  4. A tsnet node ("sill-mac", tag:sill-mac) whose port 7455 is forwarded to
//     Sill's relay door on loopback. What travels there is Sill's own TLS 1.3
//     with both keys pinned, so neither the relay, nor DERP, nor this tailnet
//     is ever trusted with the stream.
//
// Sill.app (RelaySupervisor) runs it and talks to it over stdin and stdout,
// one JSON object a line; its log goes to stderr. It exits when stdin closes,
// so it never outlives the app. No listening port of its own but Headscale's,
// on loopback.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"getsill.app/sill-net/internal/child"
	"getsill.app/sill-net/internal/headscale"
	"getsill.app/sill-net/internal/ledger"
	"getsill.app/sill-net/internal/relay"
	"getsill.app/sill-net/internal/tsnode"
)

// Event is one line on stdout.
type Event struct {
	Event string `json:"event"` // "status", "invite", "removed"
	// status
	State       string `json:"state,omitempty"` // "starting", "ready", "error"
	Relay       string `json:"relay,omitempty"` // "connecting", "connected", "error"
	Fingerprint string `json:"fingerprint,omitempty"`
	Domain      string `json:"domain,omitempty"`
	Error       string `json:"error,omitempty"`
	// invite / removed
	Device string `json:"device,omitempty"`
	Key    string `json:"key,omitempty"`
	MacIP  string `json:"macIP,omitempty"`
	Nodes  int    `json:"nodes,omitempty"`
	ID     int    `json:"id,omitempty"`
}

// Command is one line on stdin.
type Command struct {
	Cmd     string   `json:"cmd"` // "invite", "remove", "paired", "door", "stop"
	Device  string   `json:"device,omitempty"`
	Devices []string `json:"devices,omitempty"`
	Door    string   `json:"door,omitempty"`
	ID      int      `json:"id,omitempty"`
}

type daemon struct {
	dataDir  string
	hsDir    string
	hsURL    string
	hsBin    string
	hsArgs   []string // ["headscale"] when Headscale runs inside this binary
	relayURL string
	domain   string
	devices  *ledger.Ledger

	out   *json.Encoder
	outMu sync.Mutex

	mu     sync.RWMutex
	hs     *headscale.Client
	node   *tsnode.Node
	relays *relay.Supervisor
	fp     string
	macIP  string
	door   string
	state  string
	err    string
	relayS string
}

func (d *daemon) logf(f string, a ...any) { log.Printf(f, a...) }

func (d *daemon) emit(e Event) {
	d.outMu.Lock()
	defer d.outMu.Unlock()
	_ = d.out.Encode(e)
}

func (d *daemon) emitStatus() {
	d.mu.RLock()
	e := Event{Event: "status", State: d.state, Relay: d.relayS, Fingerprint: d.fp, Domain: d.domain, Error: d.err}
	d.mu.RUnlock()
	d.emit(e)
}

func (d *daemon) setState(state, errText string) {
	d.mu.Lock()
	changed := d.state != state || d.err != errText
	d.state, d.err = state, errText
	d.mu.Unlock()
	if changed {
		d.emitStatus()
	}
}

func (d *daemon) headscale() *headscale.Client {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.hs
}

// bringUp waits for Headscale, settles the API key, starts the relay and the
// tsnet node. Retries for ever with backoff: a Mac that starts with no network
// must come good by itself once it has one.
func (d *daemon) bringUp(ctx context.Context) {
	backoff := 2 * time.Second
	for ctx.Err() == nil {
		err := d.bringUpOnce(ctx)
		if err == nil {
			return
		}
		d.setState("error", err.Error())
		d.logf("control plane: %v (retrying in %s)", err, backoff)
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff < time.Minute {
			backoff *= 2
		}
	}
}

func (d *daemon) bringUpOnce(ctx context.Context) error {
	wctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	if err := headscale.WaitHealthy(wctx, d.hsURL); err != nil {
		return err
	}
	key, rotatedFrom, err := headscale.EnsureAPIKey(wctx, headscale.KeyBootstrap{
		BaseURL:    d.hsURL,
		KeyPath:    filepath.Join(d.hsDir, "api-key"),
		Binary:     d.hsBin,
		BinArgs:    d.hsArgs,
		ConfigPath: filepath.Join(d.hsDir, "config.yaml"),
		Logf:       d.logf,
	})
	if err != nil {
		return err
	}
	if rotatedFrom != "" {
		_ = headscale.ExpireAPIKey(wctx, d.hsURL, key, rotatedFrom)
	}
	hs := headscale.New(d.hsURL, key)

	fp, err := relay.ControlFingerprint(wctx, d.hsURL)
	if err != nil {
		return err
	}
	noise, err := relay.LoadNoisePrivateKey(filepath.Join(d.hsDir, "noise_private.key"))
	if err != nil {
		return err
	}
	d.mu.Lock()
	d.hs, d.fp = hs, fp
	d.mu.Unlock()

	sup := &relay.Supervisor{HeadscaleURL: d.hsURL, NoisePriv: noise, Logf: d.logf}
	sup.Set([]string{d.relayURL})
	d.mu.Lock()
	d.relays = sup
	d.mu.Unlock()
	go d.watchRelay(ctx, sup)

	node, err := tsnode.Start(ctx, d.dataDir, d.hsURL, hs, d.logf)
	if err != nil {
		return err
	}
	ips := node.IPs()
	d.mu.Lock()
	d.node = node
	if len(ips) > 0 {
		d.macIP = ips[0]
	}
	d.mu.Unlock()
	go func() {
		for ctx.Err() == nil {
			if err := node.Forward(ctx, headscale.DoorPort, d.logf, d.doorAddr); err != nil {
				d.logf("tailnet listener: %v (again in 5 s)", err)
				time.Sleep(5 * time.Second)
			}
		}
	}()
	d.logf("tailnet node up at %v; control fingerprint %s", ips, fp)
	d.setState("ready", "")
	return nil
}

func (d *daemon) doorAddr() string {
	d.mu.RLock()
	defer d.mu.RUnlock()
	return d.door
}

// watchRelay turns the supervisor's status into one event per change.
func (d *daemon) watchRelay(ctx context.Context, sup *relay.Supervisor) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
		state := "connecting"
		for _, s := range sup.Snapshot() {
			state = s.State
		}
		d.mu.Lock()
		changed := d.relayS != state
		d.relayS = state
		d.mu.Unlock()
		if changed {
			d.emitStatus()
		}
	}
}

// invite mints a single-use device key, tagged, for ten minutes, and records
// it against the paired device it is for.
func (d *daemon) invite(ctx context.Context, device string, id int) error {
	hs := d.headscale()
	if hs == nil {
		return errors.New("the control plane is not up yet")
	}
	if strings.TrimSpace(device) == "" {
		return errors.New("an invite needs the paired device's key")
	}
	u, err := hs.EnsureUser(ctx, "sill-devices")
	if err != nil {
		return fmt.Errorf("ensure the devices' user: %w", err)
	}
	key, err := hs.CreatePreAuthKey(ctx, headscale.CreatePreAuthKeyRequest{
		User:       u.ID,
		Expiration: time.Now().Add(10 * time.Minute),
		ACLTags:    []string{headscale.DeviceTag},
	})
	if err != nil {
		return fmt.Errorf("mint a device key: %w", err)
	}
	if err := d.devices.Add(device, key.ID); err != nil {
		return fmt.Errorf("record the key: %w", err)
	}
	d.mu.RLock()
	e := Event{Event: "invite", ID: id, Device: device, Key: key.Key, Fingerprint: d.fp, Domain: d.domain, MacIP: d.macIP}
	d.mu.RUnlock()
	d.emit(e)
	return nil
}

// remove deletes every node that joined with a key minted for device, then
// forgets the device. Safe to repeat.
func (d *daemon) remove(ctx context.Context, device string) error {
	hs := d.headscale()
	if hs == nil {
		return errors.New("the control plane is not up yet")
	}
	keys := map[string]bool{}
	for _, k := range d.devices.Keys(device) {
		keys[k] = true
	}
	nodes, err := hs.ListNodes(ctx)
	if err != nil {
		return err
	}
	n := 0
	for _, node := range nodes {
		if node.PreAuthKey == nil || !keys[node.PreAuthKey.ID] {
			continue
		}
		if err := hs.DeleteNode(ctx, node.ID); err != nil {
			return fmt.Errorf("delete node %s: %w", node.ID, err)
		}
		n++
	}
	for k := range keys {
		_ = hs.ExpirePreAuthKey(ctx, "sill-devices", k, "")
	}
	if err := d.devices.Forget(device); err != nil {
		return err
	}
	d.emit(Event{Event: "removed", Device: device, Nodes: n})
	return nil
}

func (d *daemon) handle(ctx context.Context, c Command) {
	cctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	var err error
	switch c.Cmd {
	case "invite":
		err = d.invite(cctx, c.Device, c.ID)
	case "remove":
		err = d.remove(cctx, c.Device)
	case "paired":
		// Devices removed while sill-net was not running.
		for _, gone := range d.devices.Stale(c.Devices) {
			if e := d.remove(cctx, gone); e != nil {
				err = e
			}
		}
	case "door":
		if _, _, e := net.SplitHostPort(c.Door); e != nil || !strings.HasPrefix(c.Door, "127.0.0.1:") {
			err = fmt.Errorf("the door must be 127.0.0.1:<port>, not %q", c.Door)
			break
		}
		d.mu.Lock()
		d.door = c.Door
		d.mu.Unlock()
	default:
		err = fmt.Errorf("unknown command %q", c.Cmd)
	}
	if err != nil {
		d.logf("%s: %v", c.Cmd, err)
		d.emit(Event{Event: "error", ID: c.ID, Device: c.Device, Error: err.Error()})
	}
}

// freePort asks the kernel for a free loopback port for Headscale.
func freePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "headscale" {
		runHeadscale(os.Args[2:])
		return
	}
	home, _ := os.UserHomeDir()
	var (
		dataDir  = flag.String("data", filepath.Join(home, "Library", "Application Support", "Sill", "net"), "state directory")
		hsBin    = flag.String("headscale", "", "a separate headscale binary (default: the one built into sill-net)")
		relayURL = flag.String("relay", relay.DefaultRelay, "the HeadFwd relay to register with")
		door     = flag.String("door", "", "Sill's relay door, 127.0.0.1:<port>")
	)
	flag.Parse()
	log.SetFlags(0)
	log.SetPrefix("sill-net: ")

	// Headscale is built into this binary (headscale_cmd.go) and runs as its
	// own process: `sill-net headscale serve …`. One Go runtime, tsnet and
	// gvisor instead of two copies (docs/relay-plan.md, size).
	bin, binArgs := *hsBin, []string(nil)
	if bin == "" {
		self, err := os.Executable()
		if err != nil {
			log.Fatal(err)
		}
		bin, binArgs = self, []string{"headscale"}
	}
	domain, err := relay.BaseDomain(*relayURL)
	if err != nil {
		log.Fatal(err)
	}
	if *door != "" && !strings.HasPrefix(*door, "127.0.0.1:") {
		log.Fatalf("--door must be 127.0.0.1:<port>")
	}
	port, err := freePort()
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(*dataDir, 0o700); err != nil {
		log.Fatal(err)
	}
	devices, err := ledger.Open(filepath.Join(*dataDir, "devices.json"))
	if err != nil {
		log.Fatalf("devices: %v", err)
	}
	d := &daemon{
		dataDir:  *dataDir,
		hsDir:    filepath.Join(*dataDir, "headscale"),
		hsURL:    fmt.Sprintf("http://127.0.0.1:%d", port),
		hsBin:    bin,
		hsArgs:   binArgs,
		relayURL: strings.TrimRight(*relayURL, "/"),
		domain:   domain,
		devices:  devices,
		out:      json.NewEncoder(os.Stdout),
		door:     *door,
		state:    "starting",
		relayS:   "connecting",
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfgPath, err := headscale.WriteConfig(headscale.ConfigParams{StateDir: d.hsDir, Port: port})
	if err != nil {
		log.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(d.dataDir, "logs"), 0o700); err != nil {
		log.Fatal(err)
	}
	hsProc := &child.Proc{
		Name:    "headscale",
		Bin:     d.hsBin,
		Args:    append(append([]string(nil), d.hsArgs...), "serve", "--config", cfgPath),
		LogPath: filepath.Join(d.dataDir, "logs", "headscale.log"),
		PidPath: filepath.Join(d.hsDir, "headscale.pid"),
		Logf:    d.logf,
	}
	hsProc.KillStale()
	hsDone := make(chan struct{})
	go func() { hsProc.Run(ctx, nil); close(hsDone) }()
	d.emitStatus()
	go d.bringUp(ctx)

	// Commands, until stdin closes: the app quit or crashed, and sill-net
	// must not outlive it.
	go func() {
		defer stop()
		r := bufio.NewReader(os.Stdin)
		for {
			line, err := r.ReadBytes('\n')
			if len(strings.TrimSpace(string(line))) > 0 {
				var c Command
				if jerr := json.Unmarshal(line, &c); jerr != nil {
					d.logf("unreadable command: %v", jerr)
				} else if c.Cmd == "stop" {
					return
				} else {
					go d.handle(ctx, c)
				}
			}
			if err != nil {
				if !errors.Is(err, io.EOF) {
					d.logf("stdin: %v", err)
				}
				return
			}
		}
	}()

	<-ctx.Done()
	d.logf("stopping")
	d.mu.RLock()
	if d.node != nil {
		_ = d.node.Close()
	}
	if d.relays != nil {
		d.relays.Set(nil)
	}
	d.mu.RUnlock()
	select {
	case <-hsDone:
	case <-time.After(12 * time.Second):
	}
}
