// Package state persists client-side tailnet state to a JSON file.
//
// What lives here is small but security-relevant: the pinned control-plane
// identity key, and any relay addresses learned at runtime. The pin is the
// thing that stops a hostile relay impersonating the control plane on a
// subsequent connection, so losing this file downgrades a device to
// first-contact trust rather than breaking it outright.
package state

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"getsill.app/tailnet-mobile/internal/shim"
)

type fileState struct {
	// PinnedKeys holds the current identity key, and during a rotation the
	// next one too, so a staged rollout doesn't lock the device out.
	PinnedKeys []string     `json:"pinnedKeys"`
	Relays     []shim.Relay `json:"relays"`
}

type Store struct {
	path string
	mu   sync.RWMutex
	data fileState
}

// Open loads state from disk, tolerating a missing file (first run) but not a
// corrupt one — silently discarding a pin would quietly weaken the client.
func Open(path string) (*Store, error) {
	s := &Store{path: path}
	buf, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return s, nil
		}
		return nil, fmt.Errorf("read state %s: %w", path, err)
	}
	if err := json.Unmarshal(buf, &s.data); err != nil {
		return nil, fmt.Errorf("parse state %s: %w", path, err)
	}
	return s, nil
}

func (s *Store) PinnedKeys() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]string(nil), s.data.PinnedKeys...)
}

func (s *Store) SetPinnedKeys(keys []string) error {
	s.mu.Lock()
	s.data.PinnedKeys = append([]string(nil), keys...)
	s.mu.Unlock()
	return s.flush()
}

func (s *Store) Relays() []shim.Relay {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return append([]shim.Relay(nil), s.data.Relays...)
}

func (s *Store) SetRelays(relays []shim.Relay) error {
	s.mu.Lock()
	s.data.Relays = append([]shim.Relay(nil), relays...)
	s.mu.Unlock()
	return s.flush()
}

// flush writes atomically via a temp file and rename. A half-written state file
// would fail to parse on next start, and Open treats that as fatal — so the
// write must be all-or-nothing.
func (s *Store) flush() error {
	s.mu.RLock()
	buf, err := json.MarshalIndent(s.data, "", "  ")
	s.mu.RUnlock()
	if err != nil {
		return err
	}

	dir := filepath.Dir(s.path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("create state dir: %w", err)
	}

	tmp, err := os.CreateTemp(dir, ".state-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName) // no-op once the rename succeeds

	// 0600: the pin is not a secret, but the file sits in a user profile and
	// there is no reason for other local accounts to read or edit it.
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(buf); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, s.path)
}
