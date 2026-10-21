package relay

import "testing"

const testFP = "0123456789abcdef0123456789abcdef"

func TestBaseDomain(t *testing.T) {
	ok := map[string]string{
		DefaultRelay:                      "headfwd.net",
		"https://Relay.Example.COM:8443/": "relay.example.com",
		"https://example.com.":            "example.com",
	}
	for in, want := range ok {
		got, err := BaseDomain(in)
		if err != nil || got != want {
			t.Fatalf("BaseDomain(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{
		"http://headfwd.net", "https://127.0.0.1", "https://[::1]:8080", "https://",
		"example.com", "https://user@example.com", "https://-bad.com", "https://a..b",
	} {
		if got, err := BaseDomain(bad); err == nil {
			t.Fatalf("BaseDomain(%q) = %q, want an error", bad, got)
		}
	}
}

func TestVerifyRegistrationURLs(t *testing.T) {
	good := verifyResponse{
		Fingerprint: testFP,
		PublicURL:   "https://" + testFP + ".headfwd.net",
		TunnelURL:   "wss://" + testFP + ".headfwd.net/tunnel?auth=secret",
	}
	if err := verifyRegistrationURLs(testFP, "headfwd.net", good); err != nil {
		t.Fatalf("genuine URLs refused: %v", err)
	}
	cases := map[string]verifyResponse{
		"other fingerprint":    {Fingerprint: "ffff" + testFP[4:], PublicURL: good.PublicURL, TunnelURL: good.TunnelURL},
		"attacker suffix":      {Fingerprint: testFP, PublicURL: "https://" + testFP + ".headfwd.net.attacker.example", TunnelURL: good.TunnelURL},
		"attacker domain":      {Fingerprint: testFP, PublicURL: "https://" + testFP + ".attacker.example", TunnelURL: good.TunnelURL},
		"fingerprint in query": {Fingerprint: testFP, PublicURL: "https://attacker.example/?" + testFP, TunnelURL: good.TunnelURL},
		"public with path":     {Fingerprint: testFP, PublicURL: good.PublicURL + "/x", TunnelURL: good.TunnelURL},
		"public http":          {Fingerprint: testFP, PublicURL: "http://" + testFP + ".headfwd.net", TunnelURL: good.TunnelURL},
		"public port":          {Fingerprint: testFP, PublicURL: "https://" + testFP + ".headfwd.net:8443", TunnelURL: good.TunnelURL},
		"public userinfo":      {Fingerprint: testFP, PublicURL: "https://x@" + testFP + ".headfwd.net", TunnelURL: good.TunnelURL},
		"tunnel ws":            {Fingerprint: testFP, PublicURL: good.PublicURL, TunnelURL: "ws://" + testFP + ".headfwd.net/tunnel"},
		"tunnel other host":    {Fingerprint: testFP, PublicURL: good.PublicURL, TunnelURL: "wss://attacker.example/" + testFP},
	}
	for name, resp := range cases {
		if err := verifyRegistrationURLs(testFP, "headfwd.net", resp); err == nil {
			t.Fatalf("%s: accepted", name)
		}
	}
}
