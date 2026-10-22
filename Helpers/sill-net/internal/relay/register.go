package relay

import (
	"bytes"
	"context"
	"crypto/ecdh"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

// Registration is what a successful handshake yields.
type Registration struct {
	// Fingerprint of the control plane's identity key. Also the subdomain.
	Fingerprint string
	// TunnelURL is the wss:// endpoint to hold open, including its auth secret.
	TunnelURL string
	// PublicURL is where clients reach this Headscale.
	PublicURL string
}

type initRequest struct {
	PublicKey string `json:"publicKey"`
}

type initResponse struct {
	Fingerprint     string `json:"fingerprint"`
	Nonce           string `json:"nonce"`
	ProxyPublicKey  string `json:"proxyPublicKey"`
	ExpiresAt       int64  `json:"expiresAt"`
	ProtocolVersion int    `json:"protocolVersion"`
}

type verifyRequest struct {
	Fingerprint string `json:"fingerprint"`
	Proof       string `json:"proof"`
}

type verifyResponse struct {
	Fingerprint string `json:"fingerprint"`
	TunnelURL   string `json:"tunnelUrl"`
	PublicURL   string `json:"publicUrl"`
}

// LoadNoisePrivateKey reads Headscale's Noise private key from disk.
//
// The file holds "privkey:<64 hex>". This is the *long-term identity* of the
// control plane: possession of it is what proves ownership of the fingerprint
// subdomain, so it never leaves this process.
func LoadNoisePrivateKey(path string) ([]byte, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read noise key %s: %w", path, err)
	}
	text := strings.TrimSpace(string(raw))
	text = strings.TrimPrefix(text, "privkey:")
	key, err := hex.DecodeString(text)
	if err != nil {
		return nil, fmt.Errorf("noise key is not hex: %w", err)
	}
	if len(key) != 32 {
		return nil, fmt.Errorf("noise key must be 32 bytes, got %d", len(key))
	}
	return key, nil
}

// Register performs the two-phase handshake and returns the tunnel endpoint.
//
// The public key is fetched from the *local* Headscale rather than derived from
// the private key, so what we register is exactly what clients will later see
// and pin.
func Register(ctx context.Context, relayBase, headscaleURL string, noisePriv []byte) (Registration, error) {
	relayBase = strings.TrimRight(relayBase, "/")

	publicKey, err := fetchControlKey(ctx, headscaleURL)
	if err != nil {
		return Registration{}, err
	}
	localFP := Fingerprint(publicKey)

	// ---- phase 1: challenge
	var init initResponse
	if err := postJSON(ctx, relayBase+"/api/register/init", initRequest{PublicKey: publicKey}, &init); err != nil {
		return Registration{}, fmt.Errorf("register init: %w", err)
	}

	// Never trust the relay's arithmetic. If it reports a fingerprint we did not
	// compute ourselves, it is either broken or trying to bind us to somebody
	// else's subdomain.
	if init.Fingerprint != localFP {
		return Registration{}, fmt.Errorf(
			"relay returned fingerprint %s, expected %s", init.Fingerprint, localFP)
	}

	// Refuse a v1 relay rather than downgrading. Init runs over plain HTTP, so a
	// fallback would let anyone who can tamper with this response force the
	// weaker raw-ECDH proof.
	if init.ProtocolVersion != ProtocolVersion {
		// The field arrived with v2, so an absent one decodes to 0 and means a
		// v1 relay. Report that rather than a "v0" that never existed.
		spoken := fmt.Sprintf("v%d", init.ProtocolVersion)
		if init.ProtocolVersion == 0 {
			spoken = "v1 (its init response carries no protocolVersion)"
		}
		return Registration{}, fmt.Errorf(
			"relay speaks registration protocol %s, this sidecar requires v%d — upgrade the relay",
			spoken, ProtocolVersion)
	}

	// ---- phase 2: prove we hold the private half
	ephBytes, err := hex.DecodeString(init.ProxyPublicKey)
	if err != nil {
		return Registration{}, fmt.Errorf("relay sent a malformed ephemeral key: %w", err)
	}
	curve := ecdh.X25519()
	priv, err := curve.NewPrivateKey(noisePriv)
	if err != nil {
		return Registration{}, fmt.Errorf("invalid noise private key: %w", err)
	}
	ephPub, err := curve.NewPublicKey(ephBytes)
	if err != nil {
		return Registration{}, fmt.Errorf("invalid relay ephemeral key: %w", err)
	}
	shared, err := priv.ECDH(ephPub)
	if err != nil {
		return Registration{}, fmt.Errorf("ECDH failed: %w", err)
	}

	proof, err := registrationProof(shared, init.Fingerprint, publicKey, init.Nonce, init.ProxyPublicKey)
	if err != nil {
		return Registration{}, fmt.Errorf("derive proof: %w", err)
	}

	var verified verifyResponse
	if err := postJSON(ctx, relayBase+"/api/register/verify",
		verifyRequest{Fingerprint: init.Fingerprint, Proof: proof}, &verified); err != nil {
		return Registration{}, fmt.Errorf("register verify: %w", err)
	}

	// The relay is untrusted: its URLs must name exactly the subdomain we own
	// under the domain we were configured with (HeadFwd df777ef). A substring
	// check would accept https://<fp>.attacker.example.
	baseDomain, err := BaseDomain(relayBase)
	if err != nil {
		return Registration{}, err
	}
	if err := verifyRegistrationURLs(localFP, baseDomain, verified); err != nil {
		return Registration{}, err
	}

	return Registration{
		Fingerprint: init.Fingerprint,
		TunnelURL:   verified.TunnelURL,
		PublicURL:   verified.PublicURL,
	}, nil
}

// capabilityVersion must match the constant in the sidecar's main package and
// the client shim; Headscale rejects anything below its floor with a plain-text
// 400 rather than JSON.
const capabilityVersion = 115

// ControlFingerprint returns the fingerprint of the local Headscale's Noise
// public key: the value invites carry and phones pin.
func ControlFingerprint(ctx context.Context, headscaleURL string) (string, error) {
	pub, err := fetchControlKey(ctx, headscaleURL)
	if err != nil {
		return "", err
	}
	return Fingerprint(pub), nil
}

func fetchControlKey(ctx context.Context, headscaleURL string) (string, error) {
	url := fmt.Sprintf("%s/key?v=%d", strings.TrimRight(headscaleURL, "/"), capabilityVersion)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("fetch control key: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return "", fmt.Errorf("fetch control key (v=%d): HTTP %d: %s",
			capabilityVersion, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}
	var body struct {
		PublicKey string `json:"publicKey"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 8<<10)).Decode(&body); err != nil {
		return "", fmt.Errorf("decode control key: %w", err)
	}
	if body.PublicKey == "" {
		return "", fmt.Errorf("headscale returned an empty public key")
	}
	return body.PublicKey, nil
}

func postJSON(ctx context.Context, url string, in, out any) error {
	payload, err := json.Marshal(in)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("content-type", "application/json")

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, strings.TrimSpace(string(snippet)))
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(out)
}
