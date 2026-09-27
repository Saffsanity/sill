# The keychain hardening question

**Branch `keychain-hardening` from `home-pairing` (PR #37), 2026-09-27.** Noah asked, before
1.0: should Sill's keys move from the legacy login keychain to the stronger (data‑protection)
keychain, which the home‑pairing security review flagged, given that that needs a provisioning
profile for Sill.app? This document assesses the risk against the threat model, compares the
fixes, settles whether the profile can be made from this Mac without Noah, and recommends one
path. It commits nothing but itself; the code change, if taken, is a later step.

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

- **A provisioning profile is mandatory, and getting it wrong bricks the app.** `application-identifier`
  and `keychain-access-groups` are profile‑restricted entitlements on macOS. A binary signed with
  the Developer ID cert **and** those entitlements but **no** provisioning profile has a valid
  signature (`codesign -v --strict` passes) yet is **killed by AMFI at launch** (exit 137,
  `Killed: 9`) — worse than a keychain error, the whole app won't start. Ad‑hoc without the
  entitlements just returns `-34018` from the keychain. So the release path must embed a
  `Contents/embedded.provisionprofile` that authorises the access group and sign with a matching
  release entitlements file; there is no "just add the entitlement" shortcut.
- **Two teams.** The Apple Development identity on this Mac is team **HG877AGTQ7**
  (`noah@apple.saffer.me`); the Developer ID is team **9B2KKVM937** (NOAH WILLIAM SAFFER).
  `make-app.sh` signs dev builds with Apple Development (HG877AGTQ7) and release builds with
  Developer ID (9B2KKVM937), so their access groups would differ (`HG877AGTQ7.…` vs `9B2KKVM937.…`)
  and never share items. Only the Developer ID build is what users run; the release group is
  `9B2KKVM937.me.saffer.sill.mac`.
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

## 9. What the follow‑up build step would change (sketch, not in this commit)

- `Packaging/`: a release entitlements file (`application-identifier`, `keychain-access-groups`
  `[9B2KKVM937.me.saffer.sill.mac]`, `com.apple.developer.team-identifier`) and the checked‑in
  `embedded.provisionprofile` (or a documented path to it).
- `Scripts/make-app.sh --release` / `Scripts/release.sh`: copy the profile into
  `Contents/embedded.provisionprofile`, sign `--release` with the release entitlements, and verify
  after signing that the embedded profile authorises the access group. The default (Apple
  Development) and ad‑hoc paths keep `SillDebug.entitlements` (no keychain groups).
- `Sources/SillHost/`: a `DataProtectionIdentityStore` (the same `IdentityStore` protocol,
  `kSecUseDataProtectionKeychain` + `kSecAttrAccessGroup`); `KeychainIdentityStore` stays for the
  legacy/dev path.
- `Sources/SillMenuBar/AppModel.swift`: choose the store by a launch‑time
  `keychain-access-groups` entitlement check (entitled → data‑protection only; else legacy; test
  hooks unchanged).
- Migration: only if a public build ever wrote legacy items — a guarded one‑time copy, or the
  documented dev‑Mac reset if we land before first public build.
- `docs/release-checklist.md`: the one‑time `-allowProvisioningUpdates` command, profile renewal,
  and the two‑team note.

## 10. For Noah

- **Decide the sequencing:** land the keychain move with home pairing (recommended, migration‑free),
  or after 1.0 (needs migration). Either way it is off the wire, so it does not touch the floor.
- **The profile** for `me.saffer.sill.mac` (team 9B2KKVM937, Keychain Sharing, Developer ID) is
  made by one `xcodebuild -allowProvisioningUpdates` run on this Mac; it registers a new App ID and
  profile on your account and may ask for your Apple Account. This plan did not run it (a background
  run must stop on that prompt, and the profile should land with the code that uses it).
- **Verification is device work:** only a Developer‑ID‑signed, profile‑embedded, notarised build can
  prove the app launches (not AMFI‑killed) and reads/writes its data‑protection items, and that a
  rebuild keeps them. Budget an "untested, for Noah" pass like the other signing work.
- **If the profile slips:** ship 1.0 on the legacy store; optionally take the Secure Enclave interim
  (no profile, removes key exfiltration); the full move waits for 1.x with a migration.

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
