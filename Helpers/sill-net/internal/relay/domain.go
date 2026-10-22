package relay

import (
	"fmt"
	"net"
	"net/url"
	"regexp"
	"strings"
)

// The public base domain, as HeadFwd's sidecar derives it (headfwd commit
// df777ef, proxy_domain.go).
//
// The relay is untrusted. The domain a Mac is published under,
// https://<fingerprint>.<baseDomain>, is a security-relevant value, so it is
// derived here, locally, from the relay URL Sill was configured with. Nothing
// the relay returns is ever used to choose it; the URLs it returns are only
// checked against it, exactly.

// DefaultRelay is the public HeadFwd relay.
const DefaultRelay = "https://headfwd.net"

var dnsLabelRe = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)

// BaseDomain returns the domain this Mac expects to be served under: the host
// of relayURL, lowercased, without a port or trailing dot.
func BaseDomain(relayURL string) (string, error) {
	u, err := url.Parse(relayURL)
	if err != nil {
		return "", fmt.Errorf("invalid relay URL %q: %w", relayURL, err)
	}
	if u.Scheme != "https" {
		return "", fmt.Errorf("invalid relay URL %q: it must be https", relayURL)
	}
	if u.User != nil {
		return "", fmt.Errorf("invalid relay URL %q: userinfo is not allowed", relayURL)
	}
	host := strings.TrimSuffix(strings.ToLower(u.Hostname()), ".")
	if host == "" {
		return "", fmt.Errorf("invalid relay URL %q: no host", relayURL)
	}
	if net.ParseIP(host) != nil {
		return "", fmt.Errorf("relay %q is an IP address; <fingerprint>.<domain> needs a DNS name", host)
	}
	if len(host) > 253 {
		return "", fmt.Errorf("relay domain %q is too long", host)
	}
	for _, label := range strings.Split(host, ".") {
		if !dnsLabelRe.MatchString(label) {
			return "", fmt.Errorf("relay domain %q is not a valid DNS name", host)
		}
	}
	return host, nil
}

// PublicURL is where devices reach a fingerprint's control plane.
func PublicURL(fingerprint, baseDomain string) string {
	return "https://" + fingerprint + "." + baseDomain
}

// verifyRegistrationURLs accepts the relay's URLs only if they point at
// exactly https/wss://<localFP>.<baseDomain>, with no port or userinfo.
func verifyRegistrationURLs(localFP, baseDomain string, resp verifyResponse) error {
	if resp.Fingerprint != localFP {
		return fmt.Errorf("relay verify fingerprint mismatch: local=%s relay=%s", localFP, resp.Fingerprint)
	}
	expectedHost := localFP + "." + baseDomain

	pub, err := url.Parse(resp.PublicURL)
	if err != nil {
		return fmt.Errorf("relay public URL is not a valid URL: %q", resp.PublicURL)
	}
	if err := checkIssuedURL("public", pub, "https", expectedHost, baseDomain); err != nil {
		return err
	}
	if (pub.Path != "" && pub.Path != "/") || pub.RawQuery != "" || pub.Fragment != "" {
		return fmt.Errorf("relay public URL mismatch: expected=%s got=%s", PublicURL(localFP, baseDomain), resp.PublicURL)
	}

	tun, err := url.Parse(resp.TunnelURL)
	if err != nil {
		return fmt.Errorf("relay tunnel URL is not a valid URL")
	}
	return checkIssuedURL("tunnel", tun, "wss", expectedHost, baseDomain)
}

func checkIssuedURL(kind string, u *url.URL, scheme, expectedHost, baseDomain string) error {
	if !strings.EqualFold(u.Scheme, scheme) {
		return fmt.Errorf("relay %s URL has scheme %q, expected %q", kind, u.Scheme, scheme)
	}
	if u.User != nil {
		return fmt.Errorf("relay %s URL contains userinfo; refusing", kind)
	}
	if u.Port() != "" {
		return fmt.Errorf("relay %s URL has an explicit port (%s); expected %s", kind, u.Port(), expectedHost)
	}
	host := u.Hostname()
	if strings.EqualFold(host, expectedHost) {
		return nil
	}
	if i := strings.IndexByte(host, '.'); i > 0 {
		if claimed := strings.ToLower(host[i+1:]); claimed != baseDomain {
			return fmt.Errorf("relay issued a %s URL on %q but this Mac expects %q", kind, claimed, baseDomain)
		}
	}
	return fmt.Errorf("relay %s URL host mismatch: expected=%s got=%s", kind, expectedHost, host)
}
