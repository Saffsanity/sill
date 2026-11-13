**A copy of Sill.app takes no test hook, from this build on (2026-10-29, branch `sec-test-host-identity` from main
at 150479b5, PR #249; the security scan of 2026-10-18, finding 1, Medium; the security batch of 2026-10-29; the
report in sill-handoff's `triage/2026-10-29-security/f1-test-host-report.md`).** `AppModel.bundled`, the one gate
on every TEST ONLY hook that bears on who gets in (`SILL_TEST_REMOTE_DIR`'s trust list, `-requirePairing`, the
`-Sill…After` hooks, the doors' `SILL_TEST_*`: docs/home-pairing-plan.md §4.3), was
`Bundle.main.bundleURL.pathExtension == "app"`, the folder's name: Sill.app copied to a folder named Sill.bin, or
its executable started through a symlink or a hard link (Foundation then finds no bundle), read as the bare binary
and took them all, keeping Sill's grants (TCC keys them to the bundle ID and designated requirement; the scan's
premise, not tried). Now `bundled` is `AppIdentity.isSillApp` (Sources/SillMenuBar/AppIdentity.swift, pure but for
its reader) of four facts read once at launch: Sill.app when the running code's signing identifier is
`me.saffer.sill.mac` (the kernel's, SecTaskCopySigningIdentifier: every copy that can hold Sill's grants carries
it, and a file replaced after launch does not change it), when it is signed with any certificate or its signature
can't be read (fail closed), when its bundle's CFBundleIdentifier is Sill's, or, as before, in a `.app`. The one
test host is the bare binary as `swift build` makes it (identifier `SillMenuBar`, `adhoc,linker-signed`, no
Info.plist). Sill.app's code outside a `.app` says why first: "Running from …, which is not a .app, as Sill.app
itself (signed me.saffer.sill.mac): it takes no test hook." No wire change; the CLI unchanged. Builds from before
keep the old rule: 0.4.0, 0.5.1 and the nightly 0.5.5 (987) take every hook from a renamed copy or a link
(SECURITY.md names them; what that leaves open is the review's R1, for Noah, in the report).
- Verified: `swift build -c release`, only the CaptureProbe warning; `Tests/checks/test-host` (new, in CI's
  mutants matrix) 133 checks (1,344 combinations against an oracle; the reader for real on ad hoc copies of
  its own binary under `sandbox-exec`: signed again as Sill, a Sill.bin bundle, a hard link, a symlink, a file
  replaced after launch) and 22 of 22 mutants; `door-policy` 128, `keychain` and its 7 mutants; `run-all.sh`
  all 57. Live: the bare binary on loopback took `-requirePairing NO` (an unpaired TLS client admitted),
  `-SillSetAfter 'requirePairing=1'` (the next refused) and the `SILL_TEST_*`; the bare binary in a scratch
  Sill.bin with Sill's Info.plist, run only under `sandbox-exec` (no network, no LaunchServices database
  write, no TCC, no preference write, nothing written in the home folder), also signed ad hoc and through a
  symlink: the line, every hook "ignored", "Home door: TLS, pairing required (0 paired)."; origin/main's build
  in that bundle took every hook. Sill's real preferences byte for byte; LaunchServices' 43 records of Sill's
  ID the same before and after.
- The review (2026-10-29, after b0d9b03b; the report's "The review"), three lenses, four findings, each reproduced
  first, the fixes in commits of their own: R1, the fix holds for Sill.app built from it on, and a build from
  before keeps its rule: the nightly 0.5.5 (987)'s own Developer ID build, renamed Sill.bin under the same
  sandbox, took every hook ("Home door: TLS, pairing not required.", "Settings: require pairing off → on"), so
  SECURITY.md, the plan's §4.3 and this entry now say which builds (f562b4c3) and what that leaves open is Noah's,
  in the report; R2, out of the finding's scope, for Noah, in the report; R3, the reader's two fail-closed answers
  (a read that failed, an identifier with neither a certificate nor the ad hoc flag) were unchecked, three mutants
  turning them into a test host surviving: `signature(read:)`, pure, 12 checks and 2 mutants (7ce5874c); R4, two
  comments with the old rule, DebugHooks' header and the plan's §13 (b16d66c7). Tried and holding: this branch's
  build signed as Sill in a Sill.bin, every hook "ignored", "pairing required (0 paired)"; `CFProcessPath` and
  argv[0] do not move `Bundle.main` (a symlink does, and the kernel's identifier answers it). Verified after:
  `test-host` 145 checks and 24 of 24 mutants; `run-all.sh` all 57 (9 min 58 s); `swift build -c release`, only
  the CaptureProbe warning; the bare binary on loopback took `-requirePairing NO` (an unpaired TLS client
  admitted), `-SillSetAfter 'requirePairing=1'` (the next refused: "certificate unknown") and the `SILL_TEST_*`;
  previews 146; Sill's preferences, LaunchServices' 43 records and Sill.log untouched by the sandboxed runs. No
  iOS file and no wire changed, so the three iOS builds were not run.
- **Untested, for Noah:** a certificate-signed build reading itself (signing needs the keychain): with Sill.app
  from this branch installed as usual, Sill.log has no "Running from …" line and Settings › Devices and Remote
  Access work as before. Don't run a copy of Sill.app outside /Applications to see the refusal: a launched copy
  can register with LaunchServices for Sill's ID and take the login item (2026-10-20). Seen, not changed:
  LaunchServices lists 43 copies under Sill's ID (old worktrees' `.build/Sill.app`, `wt-mod157` among them, the
  Trash, scratch folders).
