**Keychain hardening (2026-09-27, branch `keychain-hardening` from
`home-pairing` (PR #37, not yet merged), PR #42 (a draft); the assessment, the
decision, what was implemented and its proof with the real profile are in
`docs/keychain-plan.md`).** Noah's pre-1.0 question: move Sill.app's
remote-access identity (the Mac's key, recognition key, trust list and Require
pairing) from the legacy login keychain, which does not authenticate who made
an item (a process running before Sill's first launch can pre-create every item
and Sill adopts it — the home-pairing security review), to the data-protection
keychain, which no other process can pre-create or read. Reproduced the risk
and settled the cost with test items of own names in throwaway keychains only
(never the login keychain, never Sill's real items): the legacy keychain's
creator and ACL are attacker-set, so Sill's verbatim lookups adopt a planted
key (and a planted key signs a verifying require-pairing-off record); and the
data-protection path needs a `keychain-access-groups` entitlement — a Developer
ID binary that carries it without a provisioning profile is AMFI-killed at
launch (exit 137, codesign still valid), while an ad-hoc build without it gets
`-34018`. So the strong keychain is profile-or-the-app-won't-launch, and only
Sill.app is affected (the CLI is memory, iOS is already data-protection).
- Implemented (the recommended path): `IdentityStorePlan` (pure,
  `Tests/checks/keychain`, 13 cases, 7 mutants, in CI's matrix) chooses the
  store from four launch facts — an entitled real Sill.app uses the
  data-protection keychain and **never** the legacy one beside it (so no
  planted legacy item is adopted), an unentitled real Sill.app uses the login
  keychain (the safe, profile-free fallback), a test host uses memory or the
  test directory. `AppModel.entitledKeychainAccessGroup()` reads the running
  binary's own `keychain-access-groups` (`SecTaskCopyValueForEntitlement`);
  measured nil for every ad-hoc/dev build, so only a profile-embedded Developer
  ID build takes the strong path. `KeychainIdentityStore(accessGroup:)` is
  parameterised — nil is the legacy keychain byte-for-byte, a group adds
  `kSecUseDataProtectionKeychain` + the access group to every query.
  `Packaging/SillRelease.entitlements` and `make-app.sh --release`: with a
  profile at `Packaging/embedded.provisionprofile` (gitignored) it verifies the
  profile authorises the access group and is not expired (refusing either, which
  would AMFI-kill or fail to launch the app), embeds it and signs with the
  entitlements; without one it signs as before (login keychain) and says so;
  every build's last line names the identity keychain. `release.sh`'s
  `check_signature` confirms the state. The CLI and the bare binary are
  unchanged.
- **Review (2026-09-27, `docs/keychain-plan.md` §9a), four findings verified
  and fixed:** (1) **Auto-migration reopened the pre-creation hole — removed.**
  The first draft adopted the login keychain's items on the first entitled
  launch (to keep the Mac ID and pairings), but the login keychain cannot
  authenticate a maker, so the adoption code (no maker check, no gate) would
  have promoted a *planted* key into the strong keychain as the Mac's identity
  — the very attack this closes, only relocated. There is no sound legacy-side
  gate, so migration is dropped: the store now never reads the login keychain,
  and Noah's own dev Macs (the only Macs with legacy items before the first
  public build) do a documented one-time reset (a fresh key, a new Mac ID,
  re-pair). This also resolves the draft's leaving the exportable legacy key in
  the weak keychain. (2) **The identity key set no accessibility — fixed:** the
  data-protection default is `WhenUnlocked`, so remote access would have failed
  while the Mac was locked and its owner away; every item is now
  `AfterFirstUnlockThisDeviceOnly` (readable after first unlock, never off this
  Mac). (3) **The release path could not build the hardened app at all —
  fixed:** `SillRelease.entitlements` carried an XML comment, which codesign's
  AMFI parser rejects for a restricted-entitlement file, so `--release` with a
  valid profile failed at signing (the draft's rehearsal had no valid profile
  to reach that step); the comment is removed (its rationale moved into
  make-app.sh; `SillDebug.entitlements` keeps its comment — get-task-allow alone
  does not trip AMFI's parser, verified). (4) **make-app.sh did not check the
  profile's expiry — fixed:** Gatekeeper checks a Developer ID profile at every
  launch, so an expired embedded profile stops the app launching; make-app.sh
  now refuses an expired profile (and warns within 30 days) before signing.
- Verified before the profile existed (no notarization, no device; every keychain touch
  used throwaway keychains and test service names, never the login keychain or
  Sill's real items): `swift build` clean; `Tests/checks/run-all.sh` all 28
  pass, keychain's 7 mutants caught. The four `make-app.sh` paths, driven with
  throwaway CMS profiles and a real Developer ID signature into `.build` (the
  bundle deleted after, never installed or launched): default (Apple
  Development) → login-keychain note; profile-less `--release` → login-keychain
  fallback, no keychain groups, `codesign --verify --strict` clean; a valid
  (future-dated, right app-id) profile → the app builds, embeds the profile,
  carries the three entitlements, verifies strict, prints the data-protection
  note; a garbage, wrong-app-id, or expired profile refused (exit 1) before any
  AMFI-killable app is written. Confirmed with a throwaway-signed test binary
  that the entitlements comment broke codesign and that stripping it signs and
  reads the entitlements back.
- **Proved with the real profile (2026-09-27, `docs/keychain-plan.md` §9b).**
  Noah registered the App ID `me.saffer.sill.mac` and made the Developer ID
  profile "Sill Developer ID" (UUID 18e9509f-5498-4533-ba59-293461a61a0d,
  macOS, team 9B2KKVM937, `keychain-access-groups` `9B2KKVM937.*`, only the
  Developer ID certificate 42424F38…, until 2044-09-22), at
  `Packaging/embedded.provisionprofile` (git-ignored; copies in
  ~/Library/Developer/Xcode/UserData/Provisioning Profiles/ and ~/Downloads).
  Two findings with it, either of which stopped the hardened release, fixed: the
  draft keyed the application identifier as iOS's `application-identifier`, so
  make-app.sh refused the real profile (a Mac profile says
  `com.apple.application-identifier`) and, worse, `SillRelease.entitlements`
  with that key had the app killed at every launch (a probe signed so: exit
  137, taskgated "Unsatisfied entitlements: application-identifier", AMFI "No
  matching profile found"). Now the entitlements use
  `com.apple.application-identifier`; make-app.sh checks what taskgated checks
  (every entitlement the file holds granted by the profile, the group by name or
  `TEAM.*`, the signing certificate among the profile's — an Apple
  Development-signed probe with this profile was killed too — and not expired)
  and embeds the profile's bytes alone (`cat`); `check_signature` requires
  `com.apple.application-identifier`.
  Proven: `make-app.sh --release` prints the data-protection line, embeds the
  profile byte for byte, carries exactly the three entitlements, the hardened
  runtime and a timestamp, and verifies `--deep --strict`; `release.sh
  --dry-run` exit 0 (check_signature, the zip, the signed image); the built
  app's executable run only with `-SillRenderPreviews` exits 0 with 124
  previews, taskgated "allowing entitlement(s) … due to provisioning profile",
  no AMFI denial and no keychain call (then unregistered from LaunchServices and
  removed); a probe app (bundle ID `me.saffer.sill.mac`, the same profile and
  entitlements, Developer ID, hardened) reads its group, makes a generic
  password and a P-256 key exactly as `KeychainIdentityStore` does (the group,
  `pdmn` `cku`, `sync` 0), a scratch copy of `KeychainIdentityStore` with only
  its three name constants changed makes all four items, and a rebuilt probe
  finds the same key (a rebuild keeps the Mac ID); the same probe ad hoc, or
  Developer ID without entitlements, gets -34018 and can plant nothing; every
  test item deleted and confirmed gone, nothing of Sill's own touched, no
  prompt. Refusals checked with throwaway profiles (the iOS key, another app
  ID, team, group or certificate, none, a malformed one, expired, garbage) and
  the draft's entitlements against the real profile; the development build and
  the profile-free release as before; `Tests/checks/run-all.sh` all 28.
  Also corrected: "two teams" (both certificates are team 9B2KKVM937;
  HG877AGTQ7 is the Apple Development certificate's member ID).
- **The adversarial pass (2026-09-27, §9b's last part):** all of the above
  re-run from the commit, and more. The probe with the release's entitlements
  and no embedded profile is killed at launch though the profile sits in
  Xcode's folder here (the launch rests on the embedded copy). A new probe built
  from the branch's own store, plan and entitlement reader, with user
  interaction disallowed: as the release, its four items land in the group
  (`cku`, `sync` 0) and a query pinned to the login keychain and `security
  find-generic-password` find none (a control item there is found); ad hoc,
  Developer ID without entitlements and the development build's shape are
  refused (-34018) reading, adding, updating and deleting in the group; the
  development shape's store writes the login keychain, and with those
  same-named items there the release-shaped store loads its own (no adoption);
  the group held no item of any class before and after, and no test name is in
  either keychain. Two fixes: make-app.sh checked only the entitlements it knew
  (an added `com.apple.developer.icloud-services` was signed in, and a probe so
  signed was killed at launch; now every key is checked), and `cp -X`'s copy of
  the quarantined download kept the quarantine flag, which ditto carries into
  the zip and the image (now `cat`, none). Rechecked after: the build, `release.sh
  --dry-run` (13 s, "Unnotarized Developer ID"), the launch, and the refusals
  (the proof's eleven profiles as before, plus the extra entitlement, the iOS
  key, get-task-allow, an empty list, a dictionary, another team and its group).
- **For Noah (still device work, `docs/keychain-plan.md` §10,
  release-checklist.md Part 1 §5):** remote access with the Mac locked and you
  away (the items are `AfterFirstUnlockThisDeviceOnly`, proved `cku`, but never
  read while locked here); the first hardened launch on a Mac that ran a
  legacy-store build makes a fresh Mac ID (re-pair once; the one-time reset is
  in the checklist), then the same Mac ID across relaunches and rebuilds; a
  notarized download on a second Mac (notarization with the profile embedded,
  the first launch from quarantine, Remote Access making the identity). Also:
  by 2027-02-01 a new Developer ID certificate and the profile made again with
  it (make-app.sh refuses a profile that doesn't list the signing certificate);
  releases from GitHub Actions have no profile (git-ignored), so they ship on
  the login keychain until the release workflow gets one (a secret, or the file
  committed: it holds no secret). Land it with home pairing, before the first
  public build (off the wire, so not a floor blocker). The base is
  `home-pairing` until #37 merges; then merge main in.
