# The keychain hardening question

**Branch `keychain-hardening` (PR #42, a draft) from `home-pairing` (PR #37), 2026-09-27.** Noah asked, before
1.0: should Sill's keys move from the legacy login keychain to the stronger (data‑protection)
keychain, which the home‑pairing security review flagged, given that that needs a provisioning
profile for Sill.app? This document assesses the risk against the threat model, compares the
fixes, settles whether the profile can be made from this Mac without Noah, and recommends one
path. §1–§8 assessed the question and recommended the move; §9 is now what the branch implemented
(the pure rule, the store, make-app.sh and release.sh, the checks), §9a its review, §9b the proof with
the real provisioning profile once Noah had made it (2026-09-27: two fixes, then the build, its
launch and the keychain itself, and an adversarial pass that re-ran them and fixed two more), and
§10 is what is left for Noah (the checks only his devices and a notarized build can make).

Short answer: **yes, move to the data‑protection keychain, but do it as its own well‑tested change
that lands in or right after home pairing, before the first public build writes any keys — so
there is essentially nothing to migrate.** The cheap legacy‑keychain half‑measures do not close
the hole (the legacy keychain cannot say who made an item, and an attacker can forge a Sill‑looking
ACL). The data‑protection keychain does close it, at the price of a Developer ID provisioning
profile for `me.saffer.sill.mac` embedded in every build users run, a two‑team wrinkle, and a
launch‑time footgun (get the entitlements wrong and macOS kills the app). Making the profile from
this Mac is mechanically possible without Noah but mutates his developer account and can prompt for
his Apple Account, so it is a deliberate one‑command step, not something a planning run does
silently. Keychain storage is internal to one Mac, not on the wire, so this is **not** gated by the
1.0 compatibility floor and stays migratable in 1.x if it slips — but the migration cost only
grows, so before the first public home‑pairing build is the cheap moment.

---

## 1. The risk, exactly (reproduced 2026-09-27)

`KeychainIdentityStore` (Sources/SillHost/KeychainIdentityStore.swift) keeps four items in the
**legacy, file‑based login keychain**: the Mac's P‑256 identity private key (application tag
`me.saffer.sill.remote.host-key`), the recognition key, the paired‑devices trust list, and the
`require-pairing` record (all generic passwords under service `me.saffer.sill.remote`). Only
Sill.app uses this store; the CLI uses `MemoryIdentityStore`, the tests `FileIdentityStore`, and
iOS uses the data‑protection keychain already (device‑derived access group, no work needed).

The legacy keychain **does not record who created an item.** An item's `crtr` (creator) attribute
is whatever the writer set, and its access‑control list (ACL) lists which programs *may* use it,
chosen by the writer — neither is authenticated. Sill's lookups fetch by tag/service+account only
and adopt whatever they find; the store creates an item only when it is missing (`errSecItemNotFound`).
So a process of this user that runs **before Sill's first launch** can pre‑create every item, list
Sill (or all apps) as allowed to read it, and Sill will then use a key, a trust list and a Require
pairing that the other process chose. After the first launch every item exists and carries Sill's
own ACL, and another app reading or writing one gets the keychain's prompt — the exposure is a
one‑time race at install / first run.

I reproduced all of this in a throwaway file keychain with test names only
(`me.saffer.silltest.*`; scratch `keychain/repro.sh`, `kcprobe.swift`), never touching the login
keychain (writes pinned with `kSecUseKeychain`, reads with `kSecMatchSearchList`):

- An "attacker" tool planted an EC private key under the identity tag. Sill's **verbatim**
  `loadOrCreateKey()` query found it, and the key Sill would adopt equalled the attacker's key
  (`== attacker's key: true`). The adopted key signed a `require-pairing` **off** record that
  verified under the attacker's public key. Because the Mac ID is `MacID.make(fingerprint)` of that
  key, **planting the key gives the attacker the Mac's whole identity and lets them forge the
  signed "pairing off" record** — so the require‑pairing signature (below) does not help against a
  pre‑creation attacker who plants the key.
- The `security` tool planted the `require-pairing` record as a plain `"0"` and a trust list with
  a device, both with `-A` (every app allowed) and creator code `HACK`. Sill's verbatim generic
  `read()` returned them with no prompt. `security dump-keychain -a -r` showed `crtr="HACK"` (the
  creator is attacker‑chosen) and an all‑apps ACL — nothing binds an item to its true maker.

What is **already** mitigated in `home-pairing`, and is the ceiling of what the legacy keychain
buys: `require-pairing` is honoured off only as `"0."` plus this Mac's ECDSA signature over
`sill-require-pairing-off-v1\n‹Mac ID›` (`RequirePairingValue`); a missing or plain‑`"0"` record
reads **on**. The trust list is created empty at first launch, not first pairing. Both shrink the
window to "before first launch" and stop a *post*‑first‑launch attacker (who cannot sign for Sill's
real key) — but neither touches the key itself, which is the crown jewel.

## 2. The threat model, weighed honestly

The attacker is **a process running as Noah's user, before Sill's first launch.** That is a high
bar: such a process can already read his files, install a LaunchAgent, replace `/Applications/Sill.app`
outright, sniff loopback, and (if Sill's TCC grants leak, or its own are granted) record the screen
or inject input. Keychain pre‑creation is one path among many, and not the easiest.

Its distinctive payoff is what the other paths do **not** give: a **persistent, portable secret and
standing trust that outlive the attacker's code on the box.**

- **Impersonating the Mac to paired devices.** With the key planted, every device Noah later pairs
  pins the attacker's key as "this Mac". The attacker, who holds that private key, can then
  impersonate the Mac to those devices from anywhere (the remote door, or a look‑alike on the
  network) for the life of the pairing, receiving what a device streams or types to "its Mac" —
  even after the attacker's on‑box code is gone. Today the key is an exportable login‑keychain key,
  so the same prize also falls to any attacker who *reads* it post‑compromise, not only one who
  plants it.
- **Standing as a trusted device.** A planted trust list entry makes the attacker's own device
  trusted at the doors — usable whenever a door is reachable and on.
- **Pairing off / the loopback confused deputy.** A forged signed `require-pairing` off (needs the
  planted key) reopens the home door to any app on the Mac over loopback, borrowing Sill's Screen
  Recording and Accessibility grants.

Verdict: this is a real hardening item for a feature Sill markets as secure pairing, worth closing
before it has a public installed base — but not a five‑alarm emergency. It requires deep pre‑existing
compromise, and its worst outcome (a portable key) is what the data‑protection keychain, or the
Secure Enclave, specifically removes.

## 3. Why the cheap legacy‑keychain fixes do not work

The tempting no‑profile options each fail against a deliberate attacker, because the legacy
keychain fundamentally does not authenticate the maker:

- **Refuse items whose ACL is not "only Sill".** Unsound: Sill's designated requirement is public
  (it is derivable from the team and signing cert), so an attacker can create the item with an ACL
  that trusts *exactly* Sill's DR (`-T /path/to/Sill.app`, or a crafted `SecAccess`). A planted item
  can be made byte‑for‑byte indistinguishable from a Sill‑made one. ACL inspection stops only lazy
  attackers who used `-A`. (It also needs the deprecated `SecKeychainItemCopyAccess`/`SecACLCopyContents`.)
- **Discard pre‑existing items and create fresh at first launch.** Unsound and self‑defeating:
  Sill cannot tell its own item from a previous launch apart from a planted one, and discarding on
  every launch means a new key (new Mac ID) each time, so no device ever stays paired.
- **Bind the trust list to the key (sign it, like `require-pairing`).** Cheap, and worth keeping as
  defence in depth, but it does not close the hole: it is only safe when the key is Sill's own, which
  is exactly what fails when the key was planted. It reduces to the post‑first‑launch guarantee we
  already have.

So no legacy‑keychain check closes the key hole. The require‑pairing signature already shipped is
the most these can buy; keep it.

## 4. The real fix: the data‑protection keychain with an access group

Put the items in the data‑protection keychain (`kSecUseDataProtectionKeychain: true`) under the
access group `‹TeamID›.me.saffer.sill.mac`. Then **only a process signed by that team and entitled
to that access group can create or read the items.** A random user process — unsigned, ad‑hoc, or a
different team — gets `errSecMissingEntitlement` and cannot pre‑create or read anything. This closes
the pre‑creation hole completely and makes the key unreadable to other apps as a bonus. It is the
only sound fix.

What it takes, and what it breaks — all measured on this Mac (scratch `keychain/dpkc.swift`,
`signtest.sh`), signing local throwaway binaries with the certs already present:

- **A provisioning profile is mandatory, and getting it wrong bricks the app.** The application
  identifier (on macOS the key is `com.apple.application-identifier`; iOS's `application-identifier`
  is one a Mac profile never grants, §9b) and `keychain-access-groups` are profile‑restricted
  entitlements on macOS. A binary signed with the Developer ID cert **and** those entitlements but
  **no** provisioning profile has a valid signature (`codesign -v --strict` passes) yet is **killed
  by AMFI at launch** (exit 137, `Killed: 9`) — worse than a keychain error, the whole app won't
  start. Ad‑hoc without the entitlements just returns `-34018` from the keychain. So the release
  path must embed a `Contents/embedded.provisionprofile` that authorises the access group and sign
  with a matching release entitlements file; there is no "just add the entitlement" shortcut.
- **One team, two certificates (corrected in §9b).** This bullet first called them two teams: the
  Apple Development certificate's name ends in (HG877AGTQ7), but that is the member's own ID, and
  its team (the certificate's OU) is **9B2KKVM937**, as docs/menu-bar-app-plan.md says; the
  Developer ID certificate is NOAH WILLIAM SAFFER (9B2KKVM937). `make-app.sh` signs dev builds with
  Apple Development and release builds with Developer ID. What separates them is the certificate:
  the Developer ID provisioning profile lists only the Developer ID certificate, so a development
  build that carried the entitlements would be killed at launch (measured, §9b). Only the Developer
  ID build is what users run; the group is `9B2KKVM937.me.saffer.sill.mac`.
- **Dev builds and the bare binary must stay entitlement‑free.** An Apple Development or ad‑hoc
  build given the restricted entitlements without its own profile is AMFI‑killed too. So dev builds
  (`make-app.sh` default) and the bare `SillMenuBar` test binary must **not** carry them and must
  fall back to a store that works without them; the CLI already uses `MemoryIdentityStore`. The
  clean rule: the process checks at launch whether it holds the `keychain-access-groups` entitlement
  and uses the data‑protection store **only** when it does (never falling back to legacy when
  entitled, so the planted‑legacy‑item hole cannot reopen); otherwise it uses the legacy store
  (dev) or memory (CLI). Real users only ever run the entitled Developer ID build.
- **Migration.** Any Mac that already wrote the legacy items (remote access used on 0.3.x; and,
  once home pairing ships, the home‑door key for everyone who turns the TLS door on) has them in the
  *wrong* keychain. New code reading the data‑protection keychain would not find them, make a fresh
  key, get a new Mac ID, and **break every paired device's pin and lose the trust list.** Avoiding
  that needs a one‑time migration (copy legacy → data‑protection at first entitled launch), which is
  itself security‑sensitive — it must not adopt a *planted* legacy item, so it can only trust a
  legacy item whose ACL is Sill's own, which brings back the unreliable ACL inspection. The way to
  sidestep migration almost entirely is timing (§6): switch before the public writes any legacy key.

## 5. A cheaper partial step: the Secure Enclave (no profile)

Making the Mac's identity key a **Secure Enclave** key (`kSecAttrTokenIDSecureEnclave`, as the iOS
device key already is) needs no provisioning profile and removes the worst outcome — the key becomes
**non‑exportable**, so neither a planted‑key attacker nor one who reads the keychain later can carry
the Mac's private identity **off** the box. It does **not** close pre‑creation‑adoption (Sill would
still adopt an attacker's SE key by tag, and the attacker could set a permissive ACL to use it
on‑box), and it does not stop the trust‑list or require‑pairing planting. So it caps the damage but
is not the fix; it is a reasonable profile‑free interim if the profile work slips, and it composes
with the data‑protection keychain later. (Caveat: SE key generation on macOS wants a signed,
non‑ad‑hoc binary; confirm dev and bare‑binary paths before relying on it. Not tested here.)

## 6. Sequencing: this is not a 1.0 floor blocker, but before the first public build is cheapest

The compatibility floor (docs/update-notice-plan.md, CLAUDE.md) is about the wire and device
compatibility. **Where one Mac keeps its own key is internal**, not on the wire, so moving keychains
does not touch the floor and can happen in 1.x with a migration. The reason to do it early is purely
to avoid migration: the installed base with legacy items is near zero today (remote access is off by
default and home pairing has not shipped), and grows the moment the first public home‑pairing / 1.0
build starts creating the TLS home‑door key for everyone. So the cheap, migration‑free moment is
**in or immediately after home pairing, before the first public build** — then Sill's very first
keys for the public go straight into the data‑protection keychain and only Noah's own dev Macs need
a one‑time reset (`for k in … ; do security delete-generic-password …; done`, documented).

## 7. Can the profile be made from this Mac without Noah?

**Yes, mechanically — but it mutates his developer account and may prompt, so it is a deliberate
step, not a silent one.** Evidence gathered here:

- An **Apple Account is signed into Xcode** and already provisions team **9B2KKVM937**: the
  TestFlight rehearsal's automatic signing created `iOS Team Store Provisioning Profile: me.saffer.sill`
  (present under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`). So the account can
  create profiles for this team without a portal visit.
- The **Developer ID Application** cert (9B2KKVM937) is in the keychain; **Xcode 27.0** is active.
- No App Store Connect API key is on disk (`~/.appstoreconnect/private_keys` etc. empty), so an
  unattended creation would rely on the signed‑in account session, which can trigger an Apple
  Account / 2FA prompt.

The path is a minimal macOS app target for `me.saffer.sill.mac` with the **Keychain Sharing**
capability, automatic signing, Developer ID, built once with `-allowProvisioningUpdates` (the same
mechanism the TestFlight tooling used for the App Store profile) — Xcode registers the App ID with
Keychain Sharing and mints a **Developer ID** provisioning profile that authorises
`9B2KKVM937.me.saffer.sill.mac`. `make-app.sh`/`release.sh` then embed that profile as
`Contents/embedded.provisionprofile` and sign the release with the matching entitlements.

Why this plan does **not** mint it now: (1) it registers a new App ID and capability and a profile
on Noah's account — allowed, but it should land together with the `make-app.sh`/`release.sh` changes
that consume it, so the profile is not orphaned; (2) it can prompt for his Apple Account, which a
background run must stop on; (3) the deliverable here is the decision, not the asset. The exact
command belongs in the follow‑up build step and docs/release-checklist.md.

## 8. Recommendation

Adopt the **data‑protection keychain with the `9B2KKVM937.me.saffer.sill.mac` access group** for
Sill.app's identity items, gated behind an embedded Developer ID provisioning profile, as a
separate, fully‑tested change that lands **in or right after home pairing, before the first public
build**, so there is no migration for new installs. Keep the legacy store for un‑entitled dev builds
and memory for the CLI, chosen by a launch‑time entitlement check (never fall back when entitled).
Keep the require‑pairing signature. Do **not** ship the half‑measures as a substitute. If the profile
or its verification is not ready in time, ship 1.0 on the legacy store (it is not a floor blocker)
and either take the **Secure Enclave** interim to cap key exfiltration or accept the documented
residual risk; then do the keychain move in 1.x with a migration. Optionally add trust‑list signing
as defence in depth regardless.

Reasons in one breath: the legacy keychain cannot authenticate an item's maker and the ACL is
forgeable, so only the access group closes the pre‑creation hole; the fix's real costs (profile,
two teams, AMFI footgun, migration) are all manageable **if** it lands before there is anything to
migrate; and the whole thing sits off the wire, so early is a convenience, not a constraint.

## 9. What this branch implemented (2026-09-27)

The recommended path, built and rehearsed. The one architectural choice made here that the §8
sketch left open: rather than a second store class, `KeychainIdentityStore` is **parameterised**
with an `accessGroup` — nil is the legacy login keychain (byte‑for‑byte as before), a group name is
the data‑protection keychain — because the two keychains' queries are identical but for two
attributes, and one code path is easier to keep sound than two.

- **The rule, pure and checked.** `Sources/SillMenuBar/IdentityStorePlan.swift` turns four launch
  facts (bundled? synthetic? the `keychain-access-groups` the running binary actually holds?
  SILL_TEST_REMOTE_DIR?) into one `IdentityStoreChoice`: `.dataProtection(accessGroup:)` for an
  entitled real Sill.app and **never the legacy store beside it**, `.legacy` for an unentitled real
  Sill.app, `.memory` / `.testDirectory` for a test host. `Tests/checks/keychain` (13 cases, 7
  mutants) fixes it, and it is in CI's mutants matrix.
- **The launch‑time entitlement check.** `AppModel.entitledKeychainAccessGroup()` reads the running
  binary's own `keychain-access-groups` with `SecTaskCopyValueForEntitlement(SecTaskCreateFromSelf…)`.
  Measured 2026-09-27: an unsigned or ad‑hoc binary reads its own entitlement as **nil**, so every
  development and ad‑hoc build takes the legacy path; only a profile‑embedded Developer ID build
  reads a group and takes the data‑protection path. It authenticates nothing about other apps — it
  only asks what this process is entitled to.
- **The store.** `KeychainIdentityStore(accessGroup:)` adds `kSecUseDataProtectionKeychain` +
  `kSecAttrAccessGroup` to every query in data‑protection mode; `summary` names the keychain.
- **No migration from the login keychain — by design (see §9a).** In data‑protection mode the store
  **never reads the login keychain**: every query is pinned to the data‑protection keychain, and a
  fresh install (or an entitled build's first launch on a Mac that had legacy items) creates a fresh
  key straight in the strong keychain. Because this lands before the first public build, the only
  Macs with legacy items are Noah's own dev Macs, which do a **one‑time reset** (delete the legacy
  items and re‑pair; the command is in release‑checklist.md Part 1 §5). Public installs have nothing
  to migrate. (An earlier draft auto‑adopted the legacy items; §9a says why that was removed.)
- **Availability.** Each data‑protection item is created `AfterFirstUnlockThisDeviceOnly`: readable
  once the Mac has been unlocked after boot — so remote access, whose whole point is a Mac left at
  home while its owner is away, works while the screen is later locked — but never synced to iCloud
  and never carried to another Mac in a keychain restore, so the identity key cannot leave this Mac
  (the same posture as the iOS device key). The default keychain accessibility is `WhenUnlocked`,
  which would have made the identity unreadable exactly when remote access needs it (§9a).
- **make-app.sh / release.sh, with a safe fallback.** `Packaging/SillRelease.entitlements`
  (`com.apple.application-identifier` — the macOS key since §9b —, `keychain-access-groups`
  `[9B2KKVM937.me.saffer.sill.mac]`, `com.apple.developer.team-identifier`, **no XML comments** —
  codesign's AMFI entitlement parser rejects a comment in a file that carries restricted
  entitlements; §9a). `make-app.sh --release`: **with** a profile at
  `Packaging/embedded.provisionprofile` (or `SILL_PROVISION_PROFILE`) it checks what macOS checks at
  every launch (§9b): the profile grants every entitlement the file asks for, one added later too
  (the application identifier and the team the same, the group by its name or a pattern such as
  `9B2KKVM937.*`), lists the certificate that signed the build, and **has not expired**; a profile
  that fails any of them is refused before an app macOS would kill is written. It embeds the
  profile's bytes alone (none of the download's extended attributes, its quarantine flag included;
  §9b), signs with the release entitlements, and verifies the signed app carries the
  group and the application identifier; **without** a profile it signs as before (no keychain
  entitlements — a valid, notarizable Developer ID app on the login keychain) and says so in the
  log. Every build's last line names the identity keychain. `release.sh`'s `check_signature`
  confirms the state (an embedded profile ⇒ `keychain-access-groups` and
  `com.apple.application-identifier` present, else the login‑keychain note). The default (Apple
  Development) and ad‑hoc paths keep `SillDebug.entitlements` (no keychain groups), so a dev build is
  never AMFI‑killed and always takes the legacy store.
- **The CLI** is unchanged (`MemoryIdentityStore`), and the bare `SillMenuBar` test binary stays on
  memory / the test directory — neither carries the entitlement, both are safe.

## 9a. Review (2026-09-27)

A review of the first draft (§9 as it was) found that the hardening's steady state was sound but
its edges reopened the hole it set out to close, or would not have shipped at all. Each finding was
verified — by reading the code, and, for the release‑path ones, against real `codesign`/`security`
runs with throwaway CMS profiles and test binaries only — and fixed:

- **Auto‑migration reopened the pre‑creation hole (removed).** The draft adopted the login keychain's
  items on the first entitled launch, to keep the Mac ID and pairings. But §1/§3 already established
  that the login keychain cannot authenticate a maker and that a Sill‑trusting ACL is forgeable, so
  the adoption code — which read the item by tag/service with *no* maker check and *no* gate — would
  have promoted a **planted** key into the strong keychain as the Mac's permanent identity, exactly
  the pre‑creation attack, merely relocated to "before the entitled build's first launch." There is
  no sound gate on the legacy side (ACL inspection is the forgeable check §3 rejects; a partial
  adoption of only the generics is still useless and still seeds a planted trust list / pairing‑off).
  So auto‑migration is **dropped**: the store never reads the login keychain, and Noah's own dev
  Macs (the only Macs with legacy items before the first public build) do the documented one‑time
  reset. This also resolves the draft's second gap — that adoption never *deleted* the exportable
  legacy key, leaving it in the weak keychain — since the reset removes it.
- **The identity key set no accessibility (fixed).** Neither the created key nor the (now removed)
  re‑imported key set `kSecAttrAccessible`, so the data‑protection keychain's default,
  `WhenUnlocked`, applied — and remote access, used while the Mac is locked and its owner is away,
  would have failed exactly then. The store now creates every item
  `AfterFirstUnlockThisDeviceOnly`. (Set consciously; the data‑protection keychain was unreachable
  without the profile. Since §9b the items are proved to carry it — `pdmn` `cku` — and what is left,
  reading them while the Mac is locked, is on Noah's devices, §10.)
- **The release path could not build the hardened app at all (fixed).** `Packaging/SillRelease.entitlements`
  carried an explanatory XML comment. codesign feeds a restricted‑entitlement file to AMFI's
  `AMFIUnserializeXML`, which rejects comments ("syntax error near line 5"), so `make-app.sh --release`
  **with a valid profile** failed at the sign step — the draft's rehearsal never caught it because
  it had no valid profile to reach that step. Reproduced here with a throwaway‑signed test binary
  (comment → fail; comment stripped → signs, entitlements read back correctly). The comment is
  removed from the entitlements file; its rationale moved into `make-app.sh`'s comment. (`SillDebug.entitlements`
  keeps its comment: `get-task-allow` alone does not trigger AMFI's strict parser — verified.)
- **make-app.sh did not check the profile's expiry (fixed).** It matched the profile's
  `application-identifier` but not its `ExpirationDate`. Gatekeeper evaluates a Developer ID
  profile's validity at every launch, so an expired embedded profile ships an app that will not
  launch, with no fallback. `make-app.sh` now refuses an expired profile (and warns within 30 days)
  before signing.

Rehearsed here (no notarization, no device, no profile minted; every keychain touch used throwaway
keychains and test service names, never the login keychain or Sill's real items): `swift build`
clean; `Tests/checks/run-all.sh` all pass and the keychain check's 7 mutants are caught. The four
`make-app.sh` paths against throwaway CMS profiles and a real Developer ID signature into `.build`
(the bundle deleted after, never installed or launched): the default (Apple Development) →
login‑keychain note; a profile‑less `--release` → login‑keychain fallback, no keychain groups,
`codesign --verify --strict` clean; a valid (future‑dated, right app‑id) profile → the app builds,
embeds the profile, carries the three entitlements, verifies strict, and prints the data‑protection
note; a garbage, wrong‑app‑id, or expired profile is refused (exit 1) before any AMFI‑killable app
is written.

Left for the follow‑up (it needed the profile and a device): the profile's proof is §9b; what still
needs Noah's devices is §10, and `docs/release-checklist.md` Part 1 §5 has the profile, its
renewal and the dev‑Mac reset.

## 9b. Proved with the real profile (2026-09-27)

Noah registered the App ID `me.saffer.sill.mac` ("Sill for Mac") and made the Developer ID
provisioning profile **"Sill Developer ID"** on the developer site: UUID
`18e9509f-5498-4533-ba59-293461a61a0d`, macOS, team 9B2KKVM937, all Macs; it grants
`com.apple.application-identifier` `9B2KKVM937.me.saffer.sill.mac`,
`com.apple.developer.team-identifier` 9B2KKVM937 and `keychain-access-groups` `9B2KKVM937.*`, lists
one certificate (the Developer ID Application certificate, SHA-1 `42424F38…71D8D6`), and expires
2044-09-22. With it at `Packaging/embedded.provisionprofile` the hardened path was run for real,
headless: nothing installed, opened as an app or notarized, and only test names in the keychain
(scratch `keychain/proof`).

**Two findings, either of which would have stopped the hardened release, fixed.** One root: the
draft wrote the application identifier under iOS's key, `application-identifier`, and the earlier
rehearsal's throwaway profiles did the same, so nothing caught it before a real Mac profile, which
names it `com.apple.application-identifier`.
- **make-app.sh refused the real profile.** It read `Entitlements:application-identifier`, found
  nothing, and stopped: "the provisioning profile … is for 'nothing', not
  '9B2KKVM937.me.saffer.sill.mac'".
- **The app would have been killed at every launch.** A probe bundle signed as the release is (the
  draft's `SillRelease.entitlements`, this profile, Developer ID, the hardened runtime, a timestamp)
  exited 137 at once: taskgated-helper logged "me.saffer.sill.mac: Unsatisfied entitlements:
  application-identifier" and "Disallowing", amfid "No matching profile found" (-413). The same
  probe with `com.apple.application-identifier` launched: "allowing entitlement(s) for
  me.saffer.sill.mac due to provisioning profile". Fixing make-app.sh's read alone would have
  shipped an app that never starts.
- Fixed: `SillRelease.entitlements` uses `com.apple.application-identifier`. make-app.sh checks what
  taskgated checks: that the profile grants each of the file's entitlements (the application
  identifier and the team the same, each keychain group by its name or a pattern such as
  `9B2KKVM937.*`; since the adversarial pass below, every key the file holds, not only these), that
  it lists the certificate that signed the build (right after signing: an
  Apple Development-signed probe with the same profile and entitlements was killed at launch,
  "Unsatisfied entitlements: com.apple.developer.team-identifier, keychain-access-groups", so a
  profile covers only the certificates it names, and the Developer ID certificate ends on
  2027-02-01), and, as before, that it has not expired. It embeds the profile's bytes alone, so the
  download's extended attributes stay out of the app: kMDItemWhereFroms (the developer site's
  download address), com.apple.macl and, since the adversarial pass, the quarantine flag (the
  proof's `cp -X` dropped the first two only). `release.sh`'s `check_signature` also requires
  `com.apple.application-identifier` (the draft's probe fails it, the fixed one passes).
  Each refusal checked with throwaway CMS profiles (only the iOS key, another application
  identifier, another team, another team's group, another certificate, no certificate, an entry
  that is not a certificate, expired, undecodable): exit 1, the stage removed, no app written; the
  draft's entitlements file against the real profile refused ("grants application-identifier
  'nothing'"); an exact group accepted; a profile within 30 days of its end warned. The development
  build and the profile-free release are as before (the login keychain, no keychain groups).
- Also corrected: §4's "two teams". Both certificates on this Mac are team 9B2KKVM937.

**Proven, on the fixed branch with the real profile:**
- **The build.** `SILL_RELEASE_DRY_RUN=1 SILL_SIGN_IDENTITY='Developer ID Application: NOAH WILLIAM
  SAFFER (9B2KKVM937)' Scripts/make-app.sh --release`: exit 0 and "identity keychain:
  data-protection keychain (access group 9B2KKVM937.me.saffer.sill.mac)";
  `Contents/embedded.provisionprofile` byte for byte the installed one (SHA-256 `4f9f99b0…`);
  `codesign -d --entitlements` exactly `com.apple.application-identifier`
  `9B2KKVM937.me.saffer.sill.mac`, `com.apple.developer.team-identifier` `9B2KKVM937` and
  `keychain-access-groups` `[9B2KKVM937.me.saffer.sill.mac]`; the `runtime` flag, a secure
  timestamp, Developer ID Application; `codesign --verify --deep --strict` valid.
  `Scripts/release.sh --dry-run` end to end, exit 0 in 19 s: `check_signature`'s "Identity keychain:
  data-protection (…)", the zip, and the signed disk image with the app byte for byte. Gatekeeper:
  "Unnotarized Developer ID" (notarization's part).
- **The launch.** The built Sill.app's executable run only as `-SillRenderPreviews <dir>` (with
  `-SillLogFile` in scratch, so Sill.log was untouched), which exits before the identity store, the
  listeners and Bonjour start: exit 0, 124 previews; taskgated-helper "allowing entitlement(s) for
  me.saffer.sill.mac due to provisioning profile (isUPP: 1)", the kernel's AppleSystemPolicy "exec,
  allowed", no AMFI or taskgated denial, and no keychain call in the process's log. The bundle was
  then unregistered from LaunchServices and removed, with the rehearsal's zip and image: an
  entitled copy that LaunchServices opened would make a real identity.
- **The keychain.** A probe app in scratch with `CFBundleIdentifier` `me.saffer.sill.mac`, this
  profile and these entitlements, Developer ID with the hardened runtime and a timestamp:
  - reads its own `keychain-access-groups` as `[9B2KKVM937.me.saffer.sill.mac]`
    (`SecTaskCopyValueForEntitlement`, as `AppModel.entitledKeychainAccessGroup()` does);
  - a generic password (service `me.saffer.silltest.probe`) and a permanent P-256 key (tag
    `me.saffer.silltest.probekey`), made exactly as `KeychainIdentityStore` makes them (the update,
    then the add with the label and `AfterFirstUnlockThisDeviceOnly`; `SecKeyCreateRandomKey` with
    the data-protection flag, the group and the accessibility inside `kSecPrivateKeyAttrs`), land in
    the data-protection keychain with `agrp` `9B2KKVM937.me.saffer.sill.mac`, `pdmn` `cku`
    (AfterFirstUnlockThisDeviceOnly) and `sync` 0, the key permanent and 256 bits; both read back;
  - `KeychainIdentityStore` itself: its names are `static let` constants, so it cannot take test
    names without a code change. A scratch copy with only those three constants changed (service
    `me.saffer.silltest.remote`, its key tag, its label), every query as the branch has it, made
    its key, recognition key, trust list (empty, then one device) and Require pairing, all four
    `cku` in the group; a second process of a rebuilt probe (another binary, another cdhash) found
    the same key (the same public key, so the same Mac ID), recognition key, list and record, so a
    rebuild keeps the identity;
  - unentitled processes get nothing and plant nothing: the same probe signed ad hoc with no
    entitlements, and signed Developer ID with the hardened runtime and no entitlements (the
    profile-free release's shape), get -34018 (errSecMissingEntitlement) naming the group, and
    -25300 through the data-protection keychain without a group or through the login keychain;
    their `SecItemAdd` and `SecKeyCreateRandomKey` into the group fail with -34018; the store in
    such a process throws "couldn't be read: A required entitlement is not present." and makes no
    key;
  - everything was deleted after, and is gone from both keychains (the probe's reads; the
    `security` tool finds no test name in the login keychain). Nothing touched service
    `me.saffer.sill.remote` or home pairing's items, and no keychain or Apple Account prompt
    appeared.
  - Seen on macOS 27: an entitled process's query without `kSecUseDataProtectionKeychain` finds the
    data-protection items too. The store sets the flag on every query, so nothing changes for it.
- **Not proven here:** the screen was unlocked throughout (`CGSessionCopyCurrentDictionary`), so
  reading the `cku` items while the Mac is locked is still Noah's (§10), as are a notarized
  download's first launch and a real Sill.app's first hardened launch, which would make the real
  identity and so was never run here.

**The adversarial pass (2026-09-27, after the proof; scratch `keychain/proof/verify`).** The proof
re-run from the committed branch, not taken from its logs, and more:
- The build (the three entitlements, the profile byte for byte, the runtime, the timestamp, the
  signing certificate the one the profile lists, `--verify --deep --strict`), `check_signature`
  (which refuses a copy of the app re-signed with the draft's key), `release.sh --dry-run` (exit 0
  in 13 s; Gatekeeper "Unnotarized Developer ID") and the launch as above: exit 0, 124 previews,
  taskgated's "allowing", no connection to the keychain daemons, Sill's defaults and Sill.log
  untouched.
- A negative control the proof lacked: the probe with the release's entitlements and no embedded
  profile is killed at launch ("Disallowing me.saffer.sill.mac because no eligible provisioning
  profiles found"), although the profile sits in Xcode's Provisioning Profiles folder on this Mac:
  the launch rests on the embedded copy, which a user's Mac gets too.
- A new probe built from the branch's own `KeychainIdentityStore.swift` (only the three name
  constants changed), `IdentityStorePlan.swift` and `AppModel.entitledKeychainAccessGroup()`
  verbatim, with user interaction disallowed (no prompt could show), signed four ways:
  - as the release (its entitlements file and the profile): the plan picks the data-protection
    store, whose four items land in the group (`cku`, `sync` 0); a query without the group finds
    them under it; a query pinned to the login keychain (`kSecUseDataProtectionKeychain` false and
    `kSecMatchSearchList`) and `security find-generic-password` find none of them, while the pinned
    query does find a control item put in the login keychain; a rebuild (another cdhash) loads the
    same key and values;
  - ad hoc, Developer ID without entitlements, and as the development build (Apple Development,
    hardened, get-task-allow): the plan picks the login keychain; reading, adding, updating and
    deleting in the group are refused (-34018), no key can be planted there, and the release-shaped
    items stay as they were;
  - the development shape's store writes its four items to the login keychain (the pinned query and
    `security find-generic-password` find them; only the private key is stored), and with those
    same-named items there the release-shaped store loads its own key and values: no legacy item is
    adopted;
  - before the pass and after it the group held no item of any class, so nothing of the proof's
    probe remained and no identity was made there, and no test name of any probe of this branch is
    in either keychain.
- Found and fixed: make-app.sh checked only the entitlements it knew by name. With
  `com.apple.developer.icloud-services` added to the file it wrote the app, and a probe signed so
  was killed at launch ("Unsatisfied entitlements: com.apple.developer.icloud-services"); it now
  checks every key the file holds, and refuses one it cannot compare (an empty list, a dictionary).
  And `cp -X`'s copy of the quarantined download got the quarantine flag back, which ditto keeps: in
  a zip made as release.sh makes it (an AppleDouble `._embedded.provisionprofile` holding the
  download's quarantine record) and in a copy made as make-dmg.sh puts the app on the image.
  make-app.sh now writes the profile's bytes with `cat`, whose file gets none, and the app launched
  with it as before. After the fixes: the real profile builds as above; the
  extra entitlement, the draft's key, get-task-allow, an empty list, a dictionary, another team and
  another team's group are refused with no app written; a second group under the profile's pattern
  is accepted; the proof's eleven throwaway profiles get the verdicts they got before.

## 10. For Noah

The code is in place (§9, §9a) and proven with the real profile (§9b): the release builds hardened,
launches, and only it reads and writes the group. What is left needs your devices, a notarized
build or your decision:

- **Remote access with the Mac locked and you away.** The identity items are
  `AfterFirstUnlockThisDeviceOnly` (proved: `pdmn` `cku`), which should stay readable after the
  first unlock. Pair a device to a hardened build, lock the Mac, and connect from away (the
  iPhone's hotspot, through Tailscale), and leave it locked a while before you do. If the identity
  is unreadable while locked (Sill.log's "Remote access unavailable: …", or the device refused),
  reconsider the accessibility.
- **The first hardened launch: a fresh Mac ID, then re-pairing.** The store never reads the login
  keychain (no auto-migration, §9a), so a Mac that ran a legacy-store build gets a new key and Mac
  ID on its first hardened launch, and the log says "Remote access: the identity is in the
  data-protection keychain (access group 9B2KKVM937.me.saffer.sill.mac)". Re-pair each device once;
  then relaunch, and install a rebuild: the Mac ID stays (the probe showed a rebuild keeps the
  items). To start clean first, the one-time reset in release-checklist.md Part 1 §5.
- **A notarized download on a second Mac.** `Scripts/release.sh` for real (notarization with the
  profile embedded), then on a Mac that never had Sill: the downloaded image opens, Sill launches
  from quarantine (Gatekeeper and the profile at first launch), Remote Access on makes the identity
  (the log line above), a device pairs, and a relaunch keeps the Mac ID.
- **By 2027-02-01:** a new Developer ID certificate, and the profile made again with it
  (release-checklist.md Part 1 §5); make-app.sh refuses the old profile with a new certificate.
- **Releases from GitHub Actions** have no profile (it is git-ignored), so they ship on the login
  keychain, which their log says. If releases are to be made there, give the release workflow the
  profile: a secret written to `Packaging/embedded.provisionprofile` before `release.sh`, or the
  file committed (it holds no secret).
- **Sequencing:** land it with home pairing, before the first public build, so new installs write
  straight to the strong keychain. It is off the wire, so it does not touch the 1.0 compatibility
  floor; slipping it to 1.x still works, with the same one-time reset for anyone who had legacy
  items.

## Appendix — the reproduction (scratch, not committed)

`keychain/repro.sh` + `kcprobe.swift`: throwaway file keychain, test names, search pinned to it.
Result — Sill's verbatim key query adopts a planted EC key (`== attacker's key: true`) which signs
a verifying `require-pairing` off record; Sill's generic read returns a planted plain‑`"0"`
require‑pairing and a planted trust list with no prompt; `dump-keychain` shows `crtr="HACK"` and an
all‑apps ACL (no authenticated maker).

`keychain/dpkc.swift` + `signtest.sh`: the same probe signed several ways. Ad‑hoc, no entitlements →
`-34018`. Developer ID **and** `application-identifier`/`keychain-access-groups` but **no** profile →
valid signature, **AMFI kill at launch** (exit 137). Apple Development + entitlements, no profile →
same kill. This is the evidence that the data‑protection path is profile‑or‑nothing.

`keychain/proof` (2026-09-27, §9b): `kcprobe.swift` (the probe: its entitlements, the items made as
`KeychainIdentityStore` makes them, a plant, the deletes, and the store itself through
`KeychainIdentityStore-testnames.swift`, the branch's file with only its three name constants
changed, and `StoreShim.swift`, its protocol and types copied from HostIdentity.swift),
`make-bundle.sh` (the probe app: bundle ID, profile, entitlements, signature), the throwaway
profiles in `profiles/`, and every run's log. With the draft's `application-identifier` the probe
was killed at launch; with `com.apple.application-identifier` it ran.

`keychain/proof/verify` (2026-09-27, §9b's adversarial pass): `probe/` (`main.swift`, the probe
`kcverify`, compiled with `KIS.swift`, the branch's store with only its three name constants
changed, `Plan.swift`, `Entitled.swift`, extracted from AppModel, and `Shim.swift`; `mkbundle.sh`
signs it each way, `run.sh` runs it under a 30 s watchdog), `mktests.sh` (make-app.sh against
entitlement variants and the throwaway profiles), and every run's log.
