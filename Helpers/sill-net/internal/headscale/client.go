// Package headscale is a minimal client for the Headscale admin API.
//
// Only the calls Bridge actually needs are implemented. The API key lives here,
// in the sidecar, and never reaches the Node server — a bug in a REST handler
// must not be able to mint network credentials.
package headscale

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type Client struct {
	BaseURL string
	APIKey  string
	HTTP    *http.Client
}

func New(baseURL, apiKey string) *Client {
	return &Client{
		BaseURL: strings.TrimRight(baseURL, "/"),
		APIKey:  apiKey,
		HTTP:    &http.Client{Timeout: 15 * time.Second},
	}
}

type User struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// PreAuthKey as returned by Headscale. `ACLTags` is the field that makes the
// whole identity model work: a key minted with `tag:user-dan` stamps that tag
// onto whichever node redeems it, so the device cannot choose its own identity.
//
// Note `User` is a nested object on the way *out*, even though the create
// request takes a bare numeric ID on the way in. Modelling it as a string here
// makes decoding silently fail.
//
// `Key` IS NOT RELIABLE on Headscale 0.29+. Keys are stored bcrypt-hashed
// there, so `PreAuthKey.Proto()` returns a masked placeholder
// ("hskey-auth-<prefix>-***") for every key minted since the change, and only
// legacy plaintext rows still round-trip. Anything that needs to recognise a
// specific key later must key on `ID`, which is populated on both create and
// list in 0.26 and 0.29 alike. See ListPreAuthKeys.
type PreAuthKey struct {
	// Headscale's own primary key for this preauth key. A JSON string even
	// though the proto types it as uint64, because the API serialises 64-bit
	// ids as strings.
	ID         string    `json:"id"`
	Key        string    `json:"key"`
	User       User      `json:"user"`
	Reusable   bool      `json:"reusable"`
	Ephemeral  bool      `json:"ephemeral"`
	Used       bool      `json:"used"`
	Expiration time.Time `json:"expiration"`
	ACLTags    []string  `json:"aclTags"`
}

type Node struct {
	PreAuthKey  *PreAuthKey `json:"preAuthKey,omitempty"`
	ID          string      `json:"id"`
	Name        string      `json:"name"`
	GivenName   string      `json:"givenName"`
	IPAddresses []string    `json:"ipAddresses"`
	ForcedTags  []string    `json:"forcedTags"`
	ValidTags   []string    `json:"validTags"`
	// Headscale 0.29 replaced forcedTags/validTags with a single `tags` list:
	// the tags the node actually holds, from its preauth key or an admin.
	// Advertised-but-unapproved tags are not in it. See EffectiveTags.
	Tags   []string `json:"tags"`
	Online bool     `json:"online"`
	// When the control plane last heard from the node. A pointer because
	// Headscale omits it for a node that registered and never connected, and a
	// zero time.Time would render as 0001-01-01 rather than "never".
	LastSeen *time.Time `json:"lastSeen,omitempty"`
	// The Headscale user that owns this node -- i.e. the user whose preauth key
	// it redeemed, since `EnsureUser` names that user after the invite's target.
	//
	// Emphatically NOT an identity for authentication: only `ForcedTags` is that,
	// and this is a weaker statement. It exists so Bridge can attribute a machine
	// that joined with a user's invite but whose ACL tag never landed -- such a
	// node is otherwise unattributable, and its owner cannot reach it at all.
	User User `json:"user"`
}

// EffectiveTags is the node's authoritative tag list on either API shape:
// forcedTags on Headscale 0.26, tags on 0.29+. Never validTags, which only
// lists what a node could claim.
func (n Node) EffectiveTags() []string {
	if len(n.ForcedTags) > 0 {
		return n.ForcedTags
	}
	return n.Tags
}

func (c *Client) do(ctx context.Context, method, path string, body any, out any) error {
	var rdr io.Reader
	if body != nil {
		buf, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal %s %s: %w", method, path, err)
		}
		rdr = bytes.NewReader(buf)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, rdr)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		snippet, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("%s %s: HTTP %d: %s", method, path, resp.StatusCode, strings.TrimSpace(string(snippet)))
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

func (c *Client) ListUsers(ctx context.Context) ([]User, error) {
	var out struct {
		Users []User `json:"users"`
	}
	if err := c.do(ctx, http.MethodGet, "/api/v1/user", nil, &out); err != nil {
		return nil, err
	}
	return out.Users, nil
}

func (c *Client) CreateUser(ctx context.Context, name string) (*User, error) {
	var out struct {
		User User `json:"user"`
	}
	if err := c.do(ctx, http.MethodPost, "/api/v1/user", map[string]string{"name": name}, &out); err != nil {
		return nil, err
	}
	return &out.User, nil
}

// EnsureUser returns the named user, creating it if absent. Headscale requires
// a preauth key to belong to a user even when the identity that matters is the
// ACL tag, so every tagged key still needs an owning user record.
func (c *Client) EnsureUser(ctx context.Context, name string) (*User, error) {
	users, err := c.ListUsers(ctx)
	if err != nil {
		return nil, err
	}
	for i := range users {
		if strings.EqualFold(users[i].Name, name) {
			return &users[i], nil
		}
	}
	return c.CreateUser(ctx, name)
}

// CreatePreAuthKeyRequest creates a tagged key.
//
// `User` is the numeric user *ID*, not the name — Headscale 0.26 rejects a name
// with `invalid value for uint64 field user`. It is a string here because the
// API serialises 64-bit IDs as JSON strings.
type CreatePreAuthKeyRequest struct {
	User       string    `json:"user"`
	Reusable   bool      `json:"reusable"`
	Ephemeral  bool      `json:"ephemeral"`
	Expiration time.Time `json:"expiration"`
	// ACLTags is what upstream headfwd omits. Without it every node joins
	// untagged and Bridge's WhoIs-based auth has nothing to read.
	ACLTags []string `json:"aclTags,omitempty"`
}

func (c *Client) CreatePreAuthKey(ctx context.Context, req CreatePreAuthKeyRequest) (*PreAuthKey, error) {
	var out struct {
		PreAuthKey PreAuthKey `json:"preAuthKey"`
	}
	if err := c.do(ctx, http.MethodPost, "/api/v1/preauthkey", req, &out); err != nil {
		return nil, err
	}
	return &out.PreAuthKey, nil
}

// ListPreAuthKeys returns every key minted for a user, used or not.
//
// This is how Bridge learns an invite was actually redeemed. Headscale is the
// only party that sees a redemption — the joining node talks to it directly and
// the Bridge server is never in that path — so without this the server's
// `consumed_at` stays NULL forever and a used invite looks pending until it
// expires.
//
// The `?user=` parameter is sent but NOT TRUSTED. Headscale 0.26 declared
// `ListPreAuthKeysRequest{ user }` and filtered server-side; 0.29 made that
// message empty and returns every key on the control plane regardless. The
// parameter is kept so a 0.26 deployment still narrows the query, and the same
// filter is applied here so the result means the same thing on both.
//
// A key with no owning user is KEPT rather than dropped. In 0.29 a tagged key
// can be system-created with a nil user, and every key Bridge mints is tagged —
// discarding those would silently reconcile nothing at all, which is the exact
// class of failure this function already had once.
func (c *Client) ListPreAuthKeys(ctx context.Context, username string) ([]PreAuthKey, error) {
	var out struct {
		PreAuthKeys []PreAuthKey `json:"preAuthKeys"`
	}
	path := "/api/v1/preauthkey?user=" + url.QueryEscape(username)
	if err := c.do(ctx, http.MethodGet, path, nil, &out); err != nil {
		return nil, err
	}

	filtered := make([]PreAuthKey, 0, len(out.PreAuthKeys))
	for _, k := range out.PreAuthKeys {
		owner := strings.TrimSpace(k.User.Name)
		if owner == "" || strings.EqualFold(owner, username) {
			filtered = append(filtered, k)
		}
	}
	return filtered, nil
}

// ExpirePreAuthKey makes a key permanently unredeemable.
//
// Revoking an invite in Bridge used to be a purely local UPDATE, which meant a
// "revoked" key was still live in Headscale for the rest of its 24h TTL. The
// audit trail said one thing and the control plane did another; this is the
// call that makes the two agree.
//
// Two request shapes because the API changed under us: 0.29 takes
// `ExpirePreAuthKeyRequest{ id }`, 0.26 took `{ user, key }`. The id form is
// tried first and the legacy form is the fallback, so one binary works against
// both. `key` is only usable on 0.26 anyway — on 0.29 it is a masked
// placeholder (see PreAuthKey) — so an empty id against an old server is the
// only case the fallback can serve.
func (c *Client) ExpirePreAuthKey(ctx context.Context, username, keyID, key string) error {
	if keyID != "" {
		err := c.do(ctx, http.MethodPost, "/api/v1/preauthkey/expire", map[string]string{"id": keyID}, nil)
		if err == nil {
			return nil
		}
		// A 0.26 server rejects the id-only body. Anything else (auth, network,
		// a genuinely missing key) is a real failure and must not be retried
		// into a second confusing error.
		if !isBadRequest(err) || key == "" {
			return err
		}
	}
	if key == "" {
		return fmt.Errorf("expire preauth key for %s: no key id and no legacy key to fall back on", username)
	}
	body := map[string]string{"user": username, "key": key}
	return c.do(ctx, http.MethodPost, "/api/v1/preauthkey/expire", body, nil)
}

// isBadRequest reports whether an error from do() was an HTTP 400.
//
// String matching because do() formats its failures rather than wrapping a
// typed error, and giving it one would churn every call site for the sake of
// this one branch.
func isBadRequest(err error) bool {
	return err != nil && strings.Contains(err.Error(), "HTTP 400")
}

// ErrNoPolicy is returned by GetPolicy when a database-mode control plane has
// never had a policy stored. That is the normal state of a fresh install, not
// a failure, so callers seed rather than error.
var ErrNoPolicy = fmt.Errorf("headscale has no stored policy")

// GetPolicy returns the policy text Headscale is enforcing.
//
// In database mode this is the stored HuJSON exactly as it was last set,
// comments included -- which is what lets the sidecar keep editing it as text.
// Headscale reports "no policy yet" as a 500 wrapping gorm's "record not
// found", so that string is what maps to ErrNoPolicy.
func (c *Client) GetPolicy(ctx context.Context) (string, error) {
	var out struct {
		Policy string `json:"policy"`
	}
	if err := c.do(ctx, http.MethodGet, "/api/v1/policy", nil, &out); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "not found") {
			return "", ErrNoPolicy
		}
		return "", err
	}
	if strings.TrimSpace(out.Policy) == "" {
		return "", ErrNoPolicy
	}
	return out.Policy, nil
}

// SetPolicy replaces the policy. Database mode only: Headscale refuses this in
// file mode with "update is disabled".
//
// Headscale validates before it stores and applies the result to connected
// nodes immediately, so a successful return means the new tag is live -- no
// reload, and no window where a half-edited policy is enforced.
func (c *Client) SetPolicy(ctx context.Context, policy string) error {
	return c.do(ctx, http.MethodPut, "/api/v1/policy", map[string]string{"policy": policy}, nil)
}

func (c *Client) ListNodes(ctx context.Context) ([]Node, error) {
	var out struct {
		Nodes []Node `json:"nodes"`
	}
	if err := c.do(ctx, http.MethodGet, "/api/v1/node", nil, &out); err != nil {
		return nil, err
	}
	return out.Nodes, nil
}

// NodeByID finds one node by Headscale's own id, or nil when there is none.
//
// Done by listing rather than GET /api/v1/node/{id} because the list shape is
// the one already decoded (and tested) here, and the node count on a Bridge
// tailnet is a handful per person.
func (c *Client) NodeByID(ctx context.Context, id string) (*Node, error) {
	nodes, err := c.ListNodes(ctx)
	if err != nil {
		return nil, err
	}
	for i := range nodes {
		if nodes[i].ID == id {
			return &nodes[i], nil
		}
	}
	return nil, nil
}

// DeleteNode removes a node from the control plane.
//
// This is what actually takes a device off the tailnet: its node key stops
// being valid, peers drop it from their netmaps, and the device's own daemon
// falls back to NeedsLogin. Rejoining needs a fresh preauth key.
func (c *Client) DeleteNode(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, "/api/v1/node/"+url.PathEscape(id), nil, nil)
}

// NodeByIP finds the node holding a tailnet address. Comparison is exact: a
// prefix match here would let one node be mistaken for another (100.64.0.1 vs
// 100.64.0.10), which would be an identity-confusion bug.
func (c *Client) NodeByIP(ctx context.Context, ip string) (*Node, error) {
	nodes, err := c.ListNodes(ctx)
	if err != nil {
		return nil, err
	}
	for i := range nodes {
		for _, addr := range nodes[i].IPAddresses {
			if addr == ip {
				return &nodes[i], nil
			}
		}
	}
	return nil, nil
}
