import Foundation

// Checks IdentityStorePlan.choose (docs/keychain-plan.md §4): which identity store the menu-bar host
// uses for every combination of the four launch facts. The one rule that carries the hardening: an
// entitled real Sill.app uses the data-protection keychain and never the legacy one; an unentitled
// real Sill.app uses the legacy keychain; a test host (synthetic, or the bare binary) never touches
// a keychain. Pure, so it runs with no bundle, signature or keychain.

var failures = 0
func check(_ desc: String, _ got: IdentityStoreChoice, _ want: IdentityStoreChoice) {
    if got == want { return }
    failures += 1
    print("FAIL: \(desc): got \(got), want \(want)")
}

let group = "9B2KKVM937.me.saffer.sill.mac"

// A real Sill.app (bundled, not synthetic).
check("entitled real app → data-protection under its group",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: group, testRemoteDir: nil),
      .dataProtection(accessGroup: group))
check("entitled app carries the exact access group",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: "HG877AGTQ7.me.saffer.sill.mac", testRemoteDir: nil),
      .dataProtection(accessGroup: "HG877AGTQ7.me.saffer.sill.mac"))
check("unentitled real app → legacy login keychain",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: nil, testRemoteDir: nil),
      .legacy)
check("an empty entitlement is no entitlement → legacy",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: "", testRemoteDir: nil),
      .legacy)
check("a real app ignores SILL_TEST_REMOTE_DIR (entitled)",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: group, testRemoteDir: "/tmp/x"),
      .dataProtection(accessGroup: group))
check("a real app ignores SILL_TEST_REMOTE_DIR (unentitled)",
      IdentityStorePlan.choose(bundled: true, synthetic: false, entitledAccessGroup: nil, testRemoteDir: "/tmp/x"),
      .legacy)

// Sill.app run with --synthetic is a test host: never a keychain, even if somehow entitled, and it
// ignores SILL_TEST_REMOTE_DIR (only the bare binary takes the file store).
check("Sill.app --synthetic → memory, never a keychain",
      IdentityStorePlan.choose(bundled: true, synthetic: true, entitledAccessGroup: group, testRemoteDir: nil),
      .memory)
check("Sill.app --synthetic ignores the test directory",
      IdentityStorePlan.choose(bundled: true, synthetic: true, entitledAccessGroup: nil, testRemoteDir: "/tmp/x"),
      .memory)

// The bare SillMenuBar binary (not bundled).
check("bare binary → memory",
      IdentityStorePlan.choose(bundled: false, synthetic: false, entitledAccessGroup: nil, testRemoteDir: nil),
      .memory)
check("bare binary ignores an entitlement it should never have → memory",
      IdentityStorePlan.choose(bundled: false, synthetic: false, entitledAccessGroup: group, testRemoteDir: nil),
      .memory)
check("bare binary, not synthetic, with a test dir → still memory (the file store is --synthetic only)",
      IdentityStorePlan.choose(bundled: false, synthetic: false, entitledAccessGroup: nil, testRemoteDir: "/tmp/x"),
      .memory)
check("bare --synthetic with a test dir → the file store",
      IdentityStorePlan.choose(bundled: false, synthetic: true, entitledAccessGroup: nil, testRemoteDir: "/tmp/x"),
      .testDirectory("/tmp/x"))
check("bare --synthetic without a test dir → memory",
      IdentityStorePlan.choose(bundled: false, synthetic: true, entitledAccessGroup: nil, testRemoteDir: nil),
      .memory)

// Headless CLI pairing (`HeadlessPairing`, issue #180):
typealias HP = HeadlessPairing
func checkVal<T: Equatable>(_ desc: String, _ got: T, _ want: T) {
    if got == want { return }
    failures += 1
    print("FAIL: \(desc): got \(got), want \(want)")
}
checkVal("no --pair-code flag", HP.requested(in: ["Sill"]), false)
checkVal("--pair-code flag present", HP.requested(in: ["Sill", "--pair-code"]), true)
checkVal("refused when not on an interactive terminal",
         HP.validateRequest(isTerminal: false, hostRunning: true),
         .refused("Refused: --pair-code must be run from an interactive terminal (such as SSH or Terminal)."))
checkVal("refused when Sill is not running",
         HP.validateRequest(isTerminal: true, hostRunning: false),
         .refused("Sill is not running. Start Sill first, then run --pair-code again."))
checkVal("allowed when interactive terminal and Sill is running",
         HP.validateRequest(isTerminal: true, hostRunning: true),
         .allowed)

let resp = HP.Response(groupedCode: "4829 1355 7208", url: "sill://pair?v=1&fp=abc", expiresInSeconds: 300, port: 7455, error: nil)
let data = HP.encode(resp)
checkVal("response round-trips", HP.decode(data), resp)
checkVal("invalid data decodes to nil", HP.decode(Data("not json".utf8)), nil)
checkVal("stdout lines for valid code",
         HP.outputLines(for: resp),
         [
             "Pairing code (valid for 5 minutes, single-use): 4829 1355 7208",
             "Pairing link: sill://pair?v=1&fp=abc",
             "On your iPhone or iPad, open Sill → Add a Mac → Enter Code Instead (port 7455).",
         ])
let shortResp = HP.Response(groupedCode: "1111 2222 3333", url: "sill://pair?v=1", expiresInSeconds: 45, port: 7455, error: nil)
checkVal("stdout lines for sub-minute expiry",
         HP.outputLines(for: shortResp).first,
         "Pairing code (valid for 45 s, single-use): 1111 2222 3333")
let errResp = HP.Response(groupedCode: nil, url: nil, expiresInSeconds: nil, port: nil, error: "Remote access unavailable.")
checkVal("stdout lines for error response",
         HP.outputLines(for: errResp),
         ["Pairing failed: Remote access unavailable."])

if failures == 0 {
    print("keychain: every case passed (IdentityStorePlan.choose + HeadlessPairing)")
    exit(0)
} else {
    print("keychain: \(failures) FAILED")
    exit(1)
}
