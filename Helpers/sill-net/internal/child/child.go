// Package child runs and supervises a long-lived subprocess (Headscale).
package child

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Proc struct {
	Name    string
	Bin     string
	Args    []string
	Env     []string
	LogPath string
	PidPath string
	Logf    func(string, ...any)
}

// KillStale terminates a previous instance recorded in the pid file, if it is
// still alive and is the same program. A crashed nvrd leaves its Headscale
// running and holding the port; this is what lets the next start succeed.
func (p *Proc) KillStale() {
	raw, err := os.ReadFile(p.PidPath)
	if err != nil {
		return
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil || pid <= 1 {
		return
	}
	out, err := exec.Command("ps", "-p", strconv.Itoa(pid), "-o", "comm=").Output()
	if err != nil || !strings.Contains(string(out), filepath.Base(p.Bin)) {
		return
	}
	_ = syscall.Kill(pid, syscall.SIGTERM)
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) && syscall.Kill(pid, 0) == nil {
		time.Sleep(200 * time.Millisecond)
	}
	_ = syscall.Kill(pid, syscall.SIGKILL)
}

// Run starts the process and restarts it with backoff until ctx ends, at
// which point it is sent SIGTERM (then SIGKILL after 10s). started is closed
// after the first successful exec.
func (p *Proc) Run(ctx context.Context, started chan<- struct{}) {
	backoff := time.Second
	first := true
	for ctx.Err() == nil {
		logf, err := os.OpenFile(p.LogPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
		if err != nil {
			p.Logf("[%s] open log: %v", p.Name, err)
			return
		}
		cmd := exec.Command(p.Bin, p.Args...)
		cmd.Env = append(os.Environ(), p.Env...)
		cmd.Stdout = io.MultiWriter(logf)
		cmd.Stderr = cmd.Stdout
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if err := cmd.Start(); err != nil {
			logf.Close()
			p.Logf("[%s] start failed: %v", p.Name, err)
		} else {
			_ = os.WriteFile(p.PidPath, []byte(fmt.Sprint(cmd.Process.Pid)), 0o600)
			if first && started != nil {
				close(started)
				first = false
			}
			began := time.Now()
			done := make(chan error, 1)
			go func() { done <- cmd.Wait() }()
			select {
			case err := <-done:
				logf.Close()
				p.Logf("[%s] exited: %v", p.Name, err)
				if time.Since(began) > time.Minute {
					backoff = time.Second
				}
			case <-ctx.Done():
				_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
				select {
				case <-done:
				case <-time.After(10 * time.Second):
					_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
					<-done
				}
				logf.Close()
				_ = os.Remove(p.PidPath)
				return
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		if backoff < 30*time.Second {
			backoff *= 2
		}
	}
}
