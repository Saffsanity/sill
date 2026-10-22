// Package ledger records which preauth keys sill-net minted for which paired
// device, so removing a device on the Mac can remove exactly its nodes from
// the tailnet: the nodes that joined with one of its keys.
//
// A device is named by its Sill key (base64url SHA-256 of its SPKI), the same
// value the Mac's trust list keys it by. Nothing here is secret: preauth key
// IDs are Headscale's row numbers, never the keys themselves.
package ledger

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

type Ledger struct {
	path string
	mu   sync.Mutex
	keys map[string][]string // device -> preauth key IDs
}

func Open(path string) (*Ledger, error) {
	l := &Ledger{path: path, keys: map[string][]string{}}
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return l, nil
	}
	if err != nil {
		return nil, err
	}
	var file struct {
		Devices map[string][]string `json:"devices"`
	}
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil, err
	}
	if file.Devices != nil {
		l.keys = file.Devices
	}
	return l, nil
}

// Add records a key minted for device.
func (l *Ledger) Add(device, keyID string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.keys[device] = append(l.keys[device], keyID)
	return l.flushLocked()
}

// Keys is every key minted for device.
func (l *Ledger) Keys(device string) []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]string(nil), l.keys[device]...)
}

// Devices lists every device with a key, sorted.
func (l *Ledger) Devices() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	out := make([]string, 0, len(l.keys))
	for d := range l.keys {
		out = append(out, d)
	}
	sort.Strings(out)
	return out
}

// Forget drops a device once its nodes are gone.
func (l *Ledger) Forget(device string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.keys, device)
	return l.flushLocked()
}

// Rename moves every key recorded for from (a pairing window's pending
// entry) to to (the device that paired through it), so that removing the
// device removes the node that joined with the window's key.
func (l *Ledger) Rename(from, to string) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	keys := l.keys[from]
	if len(keys) == 0 {
		return nil
	}
	delete(l.keys, from)
	l.keys[to] = append(l.keys[to], keys...)
	return l.flushLocked()
}

// PendingPrefix names a pairing window's entry: keys minted for a QR code,
// before any device has paired with it.
const PendingPrefix = "pending:"

// Stale lists the devices with keys that are not in paired.
func (l *Ledger) Stale(paired []string) []string {
	want := map[string]bool{}
	for _, p := range paired {
		want[p] = true
	}
	var out []string
	for _, d := range l.Devices() {
		if !want[d] && !strings.HasPrefix(d, PendingPrefix) {
			out = append(out, d)
		}
	}
	return out
}

func (l *Ledger) flushLocked() error {
	raw, err := json.MarshalIndent(struct {
		Devices map[string][]string `json:"devices"`
	}{l.keys}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(l.path), 0o700); err != nil {
		return err
	}
	tmp := l.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, l.path)
}
