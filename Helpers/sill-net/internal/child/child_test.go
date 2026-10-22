package child

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"syscall"
	"testing"
	"time"
)

// KillStale stops only a process running exactly this command (the pid file
// can name a pid since reused by anything else).
func TestKillStaleMatchesCommandOnly(t *testing.T) {
	sleep, _ := exec.LookPath("sleep")
	dir := t.TempDir()
	pid := filepath.Join(dir, "pid")

	other := exec.Command(sleep, "30")
	if err := other.Start(); err != nil {
		t.Fatal(err)
	}
	defer other.Process.Kill()
	_ = os.WriteFile(pid, []byte(strconv.Itoa(other.Process.Pid)), 0o600)
	(&Proc{Bin: sleep, Args: []string{"31"}, PidPath: pid}).KillStale()
	if syscall.Kill(other.Process.Pid, 0) != nil {
		t.Fatal("killed a process running another command")
	}

	same := exec.Command(sleep, "32")
	if err := same.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() { _ = same.Wait(); close(done) }()
	_ = os.WriteFile(pid, []byte(strconv.Itoa(same.Process.Pid)), 0o600)
	(&Proc{Bin: sleep, Args: []string{"32"}, PidPath: pid}).KillStale()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("left a stale process running the same command")
	}
}
