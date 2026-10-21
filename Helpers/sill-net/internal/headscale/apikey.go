package headscale

// Admin API key lifecycle: reuse while Headscale accepts it, rotate near
// expiry, mint only when Headscale has actually rejected it.
//
// Ported from bridge's TailnetServer.swift / scripts/lib/headscale-apikey.mjs.
// The key is checked with an HTTP request made WITH the stored key, never via
// `headscale apikeys list`: the CLI goes over a unix socket, and treating any
// CLI failure as "key invalid" minted replacements on a healthy server.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	RotateWithin = 14 * 24 * time.Hour
	KeyLifetime  = 90 * 24 * time.Hour
)

type ProbeVerdict int

const (
	ProbeValid ProbeVerdict = iota
	ProbeInvalid
	ProbeUnhealthy
)

// ClassifyProbe: only a 401 justifies minting. No response, or any other
// status, means Headscale is unhealthy and minting would be a guess.
func ClassifyProbe(status int) ProbeVerdict {
	switch status {
	case 200:
		return ProbeValid
	case 401:
		return ProbeInvalid
	default:
		return ProbeUnhealthy
	}
}

// APIKeyPrefix returns the 12-character database prefix of a full key.
//
// Fixed-width, NOT "everything up to the last dash": the key is `hskey-api-` +
// 12 base64url chars + `-` + 64 base64url chars, and base64url includes `-`.
func APIKeyPrefix(key string) (string, bool) {
	const head = "hskey-api-"
	if !strings.HasPrefix(key, head) {
		return "", false
	}
	rest := key[len(head):]
	if len(rest) != 12+1+64 || rest[12] != '-' {
		return "", false
	}
	return rest[:12], true
}

// NeedsRotation reports whether a key expiring at exp should be replaced now.
// An unknown expiry is left alone: rotating on missing data churns keys.
func NeedsRotation(exp time.Time, now time.Time) bool {
	if exp.IsZero() {
		return false
	}
	return exp.Sub(now) < RotateWithin
}

type apiKeyRow struct {
	Prefix     string    `json:"prefix"`
	Expiration time.Time `json:"expiration"`
}

// KeyBootstrap carries what EnsureAPIKey needs to mint via the CLI when no
// valid key exists yet.
type KeyBootstrap struct {
	BaseURL    string // http://127.0.0.1:<port>
	KeyPath    string // file holding the key, 0600
	Binary     string // headscale binary
	ConfigPath string // headscale config.yaml
	Logf       func(format string, args ...any)
}

// EnsureAPIKey returns a key Headscale accepts, and the previous key if it
// rotated one (to expire once callers have switched over).
func EnsureAPIKey(ctx context.Context, b KeyBootstrap) (key string, rotatedFrom string, err error) {
	logf := b.Logf
	if logf == nil {
		logf = func(string, ...any) {}
	}
	if raw, rerr := os.ReadFile(b.KeyPath); rerr == nil {
		existing := strings.TrimSpace(string(raw))
		if existing != "" {
			status, rows := probeAPIKey(ctx, b.BaseURL, existing)
			switch ClassifyProbe(status) {
			case ProbeUnhealthy:
				return "", "", fmt.Errorf("headscale neither accepted nor rejected the stored API key (HTTP %d); not minting a new one", status)
			case ProbeValid:
				var exp time.Time
				if p, ok := APIKeyPrefix(existing); ok {
					for _, r := range rows {
						if r.Prefix == p {
							exp = r.Expiration
						}
					}
				}
				if !NeedsRotation(exp, time.Now()) {
					return existing, "", nil
				}
				next, cerr := createAPIKeyHTTP(ctx, b.BaseURL, existing)
				if cerr != nil {
					return "", "", cerr
				}
				if st, _ := probeAPIKey(ctx, b.BaseURL, next); ClassifyProbe(st) != ProbeValid {
					return "", "", errors.New("headscale minted a replacement API key but then rejected it; kept the old one")
				}
				if err := os.WriteFile(b.KeyPath, []byte(next+"\n"), 0o600); err != nil {
					return "", "", err
				}
				logf("[headscale] rotated the admin API key")
				return next, existing, nil
			case ProbeInvalid:
				logf("[headscale] stored API key rejected; minting a new one")
			}
		}
	}

	// No valid key to authenticate with: the one step that needs the CLI.
	cmd := exec.CommandContext(ctx, b.Binary, "--config", b.ConfigPath, "apikeys", "create", "--expiration", "90d")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", "", fmt.Errorf("headscale apikeys create: %v: %s", err, strings.TrimSpace(string(out)))
	}
	var minted string
	for _, line := range strings.Split(string(out), "\n") {
		if l := strings.TrimSpace(line); l != "" {
			minted = l
		}
	}
	if minted == "" || strings.Contains(minted, " ") {
		return "", "", fmt.Errorf("could not parse an API key from headscale's output: %s", out)
	}
	if err := os.WriteFile(b.KeyPath, []byte(minted+"\n"), 0o600); err != nil {
		return "", "", err
	}
	return minted, "", nil
}

func probeAPIKey(ctx context.Context, base, key string) (int, []apiKeyRow) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/api/v1/apikey", nil)
	req.Header.Set("Authorization", "Bearer "+key)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil
	}
	defer resp.Body.Close()
	var body struct {
		APIKeys []apiKeyRow `json:"apiKeys"`
	}
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	_ = json.Unmarshal(raw, &body)
	return resp.StatusCode, body.APIKeys
}

func createAPIKeyHTTP(ctx context.Context, base, bearer string) (string, error) {
	payload, _ := json.Marshal(map[string]string{
		"expiration": time.Now().Add(KeyLifetime).UTC().Format(time.RFC3339),
	})
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+"/api/v1/apikey", bytes.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+bearer)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("rotate API key: %w", err)
	}
	defer resp.Body.Close()
	var out struct {
		APIKey string `json:"apiKey"`
	}
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("rotate API key: HTTP %d", resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return "", err
	}
	if _, ok := APIKeyPrefix(out.APIKey); !ok {
		return "", errors.New("rotate API key: unexpected key shape")
	}
	return out.APIKey, nil
}

// ExpireAPIKey expires a rotated-out key. Best-effort: it lapses on its own.
func ExpireAPIKey(ctx context.Context, base, bearer, old string) error {
	p, ok := APIKeyPrefix(old)
	if !ok {
		return nil
	}
	payload, _ := json.Marshal(map[string]string{"prefix": p})
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, base+"/api/v1/apikey/expire", bytes.NewReader(payload))
	req.Header.Set("Authorization", "Bearer "+bearer)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("expire old API key: HTTP %d", resp.StatusCode)
	}
	return nil
}

// Health polls /health until Headscale answers or ctx ends.
func WaitHealthy(ctx context.Context, base string) error {
	for {
		req, _ := http.NewRequestWithContext(ctx, http.MethodGet, base+"/health", nil)
		resp, err := http.DefaultClient.Do(req)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == 200 {
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("headscale at %s never became healthy: %w", base, ctx.Err())
		case <-time.After(500 * time.Millisecond):
		}
	}
}
