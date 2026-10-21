// Command tailnet-try runs the device half of Reach from Anywhere on a Mac,
// for testing: the same package SillTailnet.xcframework wraps, started from a
// kind 60 payload (as JSON on stdin), then one round trip through the
// forwarder to the Mac's door. TEST ONLY: never part of an app.
//
//	go run ./cmd/tailnet-try -state /tmp/dev < invite.json
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"time"

	"getsill.app/tailnet-mobile/tailnet"
)

// probeAll dials each target through the node itself (not the forwarder),
// to show what the ACL lets this device reach.
func probeAll(c *tailnet.Controller, targets string) {
	srv := c.Server()
	if srv == nil || targets == "" {
		return
	}
	for _, t := range strings.Split(targets, ",") {
		ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
		conn, err := srv.Dial(ctx, "tcp", t)
		cancel()
		if err != nil {
			fmt.Printf("probe %s: refused (%v)\n", t, err)
			continue
		}
		conn.Close()
		fmt.Printf("probe %s: REACHED\n", t)
	}
}

func main() {
	state := flag.String("state", "", "state directory")
	fingerprint := flag.String("fingerprint", "", "rejoin without a key (the second start)")
	domain := flag.String("domain", "", "relay domain for a rejoin")
	probe := flag.String("probe", "", "also dial these host:port targets inside the tailnet (comma-separated) and say which answer")
	hold := flag.Duration("hold", 0, "after joining, print the forwarder's address and keep the tailnet up this long (for a TLS client to dial it)")
	flag.Parse()
	cfg := tailnet.Config{StateDir: *state, Hostname: "tailnet-try", Fingerprint: *fingerprint, Domain: *domain}
	if *fingerprint == "" {
		var inv struct{ Key, Fingerprint, Domain string }
		if err := json.NewDecoder(os.Stdin).Decode(&inv); err != nil {
			log.Fatalf("invite on stdin: %v", err)
		}
		cfg.PreauthKey, cfg.Fingerprint, cfg.Domain = inv.Key, inv.Fingerprint, inv.Domain
	}
	c := tailnet.New()
	if err := c.Start(cfg); err != nil {
		log.Fatalf("start: %v", err)
	}
	began := time.Now()
	for time.Since(began) < 120*time.Second {
		s := c.Status()
		if s.Phase == tailnet.PhaseRunning || s.Phase == tailnet.PhaseError || s.Phase == tailnet.PhaseRemoved {
			break
		}
		time.Sleep(250 * time.Millisecond)
	}
	s := c.Status()
	fmt.Printf("phase=%s ip=%s forwarder=%s relay=%s after=%v err=%q\n", s.Phase, s.TailnetIP, s.ProxyAddr, s.Relay, time.Since(began).Round(time.Millisecond), s.Error)
	if s.Phase != tailnet.PhaseRunning {
		os.Exit(1)
	}
	if *hold > 0 {
		fmt.Printf("FORWARDER %s\n", s.ProxyAddr)
		time.Sleep(*hold)
		c.Stop()
		return
	}
	for attempt := 0; attempt < 20; attempt++ {
		conn, err := net.DialTimeout("tcp", s.ProxyAddr, 5*time.Second)
		if err == nil {
			_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
			t0 := time.Now()
			line, err := bufio.NewReader(conn).ReadString('\n')
			if err == nil {
				fmt.Printf("door said %q in %v\n", line, time.Since(t0).Round(time.Millisecond))
				probeAll(c, *probe)
				c.Stop()
				return
			}
			conn.Close()
		}
		time.Sleep(time.Second)
	}
	log.Fatal("no answer from the door through the forwarder")
}
