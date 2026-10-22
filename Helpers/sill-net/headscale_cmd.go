package main

import (
	"os"
	"syscall"
	"time"

	"github.com/juanfont/headscale/cmd/headscale/cli"
)

// runHeadscale runs Headscale's own command line (serve, apikeys …) inside
// this binary: `sill-net headscale serve --config …`. One binary instead of
// two, so the Go runtime, tsnet and gvisor ship once (docs/relay-plan.md).
//
// `serve` must never outlive the sill-net that started it, even one killed
// with SIGKILL (Sill.app crashing): macOS has no parent-death signal, so it
// watches its parent and stops when it becomes an orphan.
func runHeadscale(args []string) {
	if len(args) > 0 && args[0] == "serve" {
		parent := os.Getppid()
		go func() {
			for {
				time.Sleep(time.Second)
				if os.Getppid() != parent {
					_ = syscall.Kill(os.Getpid(), syscall.SIGTERM)
					time.Sleep(10 * time.Second)
					os.Exit(1)
				}
			}
		}()
	}
	os.Args = append([]string{"headscale"}, args...)
	cli.Execute()
}
