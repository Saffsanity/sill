// Package tsnode is the Mac's presence on its own Sill tailnet: a userspace
// (tsnet) node called "sill-mac", tagged tag:sill-mac, that devices dial to
// reach Sill's relay door. No TUN device, no system VPN, no admin password:
// the node lives entirely inside sill-net.
package tsnode

import (
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"

	"tailscale.com/envknob"
	"tailscale.com/tsnet"

	"getsill.app/sill-net/internal/headscale"
)

const (
	// Hostname is the MagicDNS name devices dial ("sill-mac:7455").
	Hostname   = "sill-mac"
	ServerUser = "sill-mac"
)

type Node struct {
	srv *tsnet.Server
}

// Start brings the node up against the local Headscale, minting a single-use
// tag:sill-mac key on first enrolment only. Afterwards tsnet's state dir
// holds the node key and no preauth key is needed (or kept).
func Start(ctx context.Context, stateDir, controlURL string, hs *headscale.Client, logf func(string, ...any)) (*Node, error) {
	// No log upload to log.tailscale.io: this tailnet is the Mac's own, and
	// nobody agreed to ship its logs anywhere.
	envknob.SetNoLogsNoSupport()
	dir := filepath.Join(stateDir, "tsnet")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	srv := &tsnet.Server{
		Dir:        dir,
		Hostname:   Hostname,
		ControlURL: controlURL,
		Ephemeral:  false,
		Logf:       func(string, ...any) {},
		UserLogf:   logf,
	}
	if !enrolled(dir) {
		u, err := hs.EnsureUser(ctx, ServerUser)
		if err != nil {
			return nil, fmt.Errorf("ensure %s user: %w", ServerUser, err)
		}
		key, err := hs.CreatePreAuthKey(ctx, headscale.CreatePreAuthKeyRequest{
			User:       u.ID,
			Expiration: time.Now().Add(10 * time.Minute),
			ACLTags:    []string{headscale.MacTag},
		})
		if err != nil {
			return nil, fmt.Errorf("mint the Mac's key: %w", err)
		}
		srv.AuthKey = key.Key
	}
	upCtx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	if _, err := srv.Up(upCtx); err != nil {
		srv.Close()
		return nil, fmt.Errorf("tsnet up: %w", err)
	}
	return &Node{srv: srv}, nil
}

// enrolled reports whether tsnet already holds a node identity. tsnet writes
// tailscaled.state on first successful login.
func enrolled(dir string) bool {
	fi, err := os.Stat(filepath.Join(dir, "tailscaled.state"))
	return err == nil && fi.Size() > 0
}

// Forward accepts on the tailnet's port and splices each connection to
// target() (Sill's relay door on loopback, as the app last said it) until ctx
// ends. The bytes are Sill's own TLS from end to end; nothing here reads them.
// With no door yet, a connection is closed at once.
func (n *Node) Forward(ctx context.Context, port int, logf func(string, ...any), target func() string) error {
	ln, err := n.srv.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return err
	}
	go func() { <-ctx.Done(); ln.Close() }()
	for {
		c, err := ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		go func() {
			defer c.Close()
			door := target()
			if door == "" {
				return
			}
			d := net.Dialer{Timeout: 5 * time.Second}
			up, err := d.DialContext(ctx, "tcp", door)
			if err != nil {
				logf("forward to the door: %v", err)
				return
			}
			Splice(c, up)
		}()
	}
}

// Splice copies both ways and closes both ends when either side finishes.
func Splice(a, b net.Conn) {
	var once sync.Once
	closeBoth := func() { a.Close(); b.Close() }
	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(a, b); once.Do(closeBoth); done <- struct{}{} }()
	go func() { _, _ = io.Copy(b, a); once.Do(closeBoth); done <- struct{}{} }()
	<-done
	<-done
}

// IPs returns the node's tailnet addresses, for the log.
func (n *Node) IPs() []string {
	v4, v6 := n.srv.TailscaleIPs()
	var out []string
	if v4.IsValid() {
		out = append(out, v4.String())
	}
	if v6.IsValid() {
		out = append(out, v6.String())
	}
	return out
}

func (n *Node) Close() error { return n.srv.Close() }
