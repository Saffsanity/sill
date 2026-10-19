import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { failures += 1; print("FAIL: \(message)") }
}

for text in ["sill://", "sill:///", "sill://open", "sill://open/", "SILL://OPEN"] {
    check(VisionSessionPolicy.isLaunchURL(URL(string: text)!), "launch: \(text)")
}
for text in ["https://open", "other://", "sill://pair", "sill://pair?v=1",
             "sill://connect", "sill://open/path", "sill:///path", "sill://open//",
             "sill://open?", "sill://?host=example.invalid", "sill://open?command=quit",
             "sill://open#", "sill://open#pair", "sill://user@open", "sill://user:pass@open",
             "sill://open:1234", "sill://open:0", "sill://open:", "sill://%6fpen", "sill:open", "sill:", "sill:/"] {
    check(!VisionSessionPolicy.isLaunchURL(URL(string: text)!), "not a launch: \(text)")
}

let link = PairLink(fingerprint: Data(repeating: 1, count: 32), secret: Data(repeating: 2, count: 16),
                    name: "Test Mac", port: 48000, addresses: [])
check(!VisionSessionPolicy.isLaunchURL(URL(string: link.url)!), "real pairing reaches the existing handler")
check((try? PairLink.parse(link.url).get()) == link, "real pairing still parses")
for text in ["sill://pair", "sill://pair?v=1", "sill://pair?v=2"] {
    check(!VisionSessionPolicy.isLaunchURL(URL(string: text)!), "malformed pairing reaches the existing handler")
    if case .success = PairLink.parse(text) { check(false, "malformed pairing fails: \(text)") }
}

if failures > 0 { exit(1) }
print("vision-launch: launch routes, strict route boundaries, and pairing checks passed")
