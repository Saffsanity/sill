# One-click update for Sill for Mac — the plan

Noah, 2026-11-11: "make a note that I want to make the Sill update checker also have a 1 click updater
as a new feature", and the same evening: "Start working on ... one-click updater ... Use subagents."
Branch `one-click-update` from main at dd6ea6a (0.6.1 released that day, plus #339).

This is the most security-sensitive code Sill for Mac has: it downloads a program and replaces the app
that is running. It is written for a hostile reader: every claim says what enforces it, and every
residual risk is named. A separate security review follows.

## 1. What and why

Sill for Mac has an update **check** (docs/update-notice-plan.md §6; `UpdateChecker`, `UpdatePolicy`):
once a day it asks GitHub's releases feed whether a newer published release exists and, when one does,
offers "Sill 0.6.2 Is Available…" in the status menu and in Settings › General, which opens the
release's page. It downloads nothing.

One click: when the check has found a newer release, **Update Now** (beside the existing Open Release
Page…) downloads it, checks it, replaces Sill.app where it is, and relaunches Sill. Progress and any
failure show inline in Settings › General (no alert: AppDelegate's modal-loop rule). Never automatic,
never silent: only the person's click starts it, and a click while a device is connected asks first.
Whenever anything about the situation is not exactly right, the updater changes nothing and says why,
and Open Release Page… remains.

Hard rules that hold throughout: Apple frameworks only (no Sparkle), no server of Sill's, nothing
privileged ever (no admin prompt, no helper tool, no SMJobBless, no installer package), no test hook
that loosens anything in Sill.app.

Not in scope: automatic or background installs; delta updates; "Skip This Version"; the iOS app (the
App Store updates it); a nightly is never offered the release of its own version (the check compares
versions only, so a nightly 0.6.2 (1400) sees nothing until 0.6.3 is out: known, unchanged).

## 2. The design on one page

```
Update Now (a SwiftUI Button action, or the confirmation's)
  │  refusal? (§4.1) ─────────────────────────────► the reason, inline; nothing done
  │  devices connected? ──────────────────────────► "Update and Disconnect" / Cancel
  ▼
fresh release info: GET api.github.com/repos/Saffsanity/sill/releases/latest
  │  the same tag as offered, strictly newer, asset Sill.zip with its size and SHA-256 (§4.3)
  ▼
staging folder: FileManager's item-replacement directory on Sill.app's own volume (0700, per user)
  │
download https://github.com/Saffsanity/sill/releases/download/<tag>/Sill.zip
  │  redirects only to GitHub's release-assets host; https; size = the declared size; SHA-256 = digest
  ▼
unpack with Sill's own zip reader (no ditto, no process), every entry checked first (§4.4)
  ▼
check staging/Sill.app (§4.5): signed by Developer ID team 9B2KKVM937 as me.saffer.sill.mac,
  notarized, valid strictly with nested code, this app's own designated requirement, the three
  keychain entitlements, hardened runtime, a stapled ticket, version > running and = the tag,
  a slice for this Mac, runs on this macOS
  ▼
devices connected since the click? ───────────────► "Ready: Install and Disconnect" / Cancel
  ▼
the copy at the path is still the one running (cdhash), then renamex_np(RENAME_SWAP): atomic
  ▼
check /Applications/Sill.app again, the same checks, the same cdhash ─ fails ─► swap back, say so
  ▼
launch it as a new instance (NSWorkspace, no prompt); it waits for this one to quit
  │  not finished launching in 30 s, or it quits, or its running cdhash differs ─► swap back
  ▼
this Sill quits through its normal quit path (a run-loop Timer: windows home, virtual display gone)
  ▼
the new Sill starts its host, then deletes the staging folder with the old copy in it
```

## 3. The threat model, point by point

What is trusted, and why: **the code signature**, checked by Security.framework against a requirement
compiled into the running app. Not the network (TLS is necessary, not sufficient: a Mac behind a
TLS-intercepting proxy trusts its root), not GitHub's metadata, not the release's `.sha256` or the API's
`digest` (same origin as the file: a transfer check only). The checks that decide are in §4.5.

**T1. A hostile network** (Wi‑Fi, DNS, a proxy, a TLS root someone installed). It can block, slow,
truncate or replace what Sill downloads. Replacement fails the signature check; truncation fails the
size, the hash, the zip reader and the signature; a block or a slow link fails with words and changes
nothing. Requests go only to the allow-list (T5), so the network cannot point Sill at a host on the LAN.

**T2. GitHub's release metadata is input, not instruction.** The tag must be `v` + digits and dots
exactly (no `-rc`, no path characters); the release must not be a draft or a pre-release; the asset must
be named exactly `Sill.zip`, `state` "uploaded", 1 KB to 64 MiB; its `browser_download_url` must equal
the URL Sill builds itself from the tag; its `digest` must be `sha256:` + 64 hex digits (or, if GitHub
stops sending `digest`, the `Sill.zip.sha256` asset, at most 1 KB, "‹64 hex›  Sill.zip"). The tag must
be the one the check offered, and its version newer than the running one. Anything else: refused.

**T3. A compromised GitHub account or release.** An attacker who can publish releases can replace
`Sill.zip`, publish a release "v9.9.9", or move a tag. Without Noah's Developer ID private key **and**
Apple's notarization of the result, nothing they upload passes §4.5. With a genuine older Sill re-served
under a newer tag: the version is read from the downloaded bundle's own Info.plist, which the signature
seals, and it must be newer than the running one and equal to the tag's: refused. With a genuine nightly
of a higher version labelled as a release: it is Noah's signed, notarized code and passes (Q5). Withheld
releases (a "freeze") cannot be detected without signed metadata: the next check offers the newest.

**T4. The Developer ID key lives in GitHub Actions (added: the biggest one).** Since 2026-10-30
`SILL_SIGN_IN_CI` is `true`: the `release` environment holds the Developer ID identity and the notary key
behind Noah's approval, and the `nightly` environment holds them too, with **no reviewer**, reachable by
any commit on main at the next night's run; that job's token can publish a release (CLAUDE.md, "Nightly
builds", the review's finding on "the route through main"). So today "a commit lands on main" is enough
to produce a Developer ID signed, notarized Sill and to publish it as the latest release. The code
signature pin then proves only "built by Sill's CI", and one click installs it. Without the updater the
same build would be on the download page, so the updater does not create this exposure, but it widens
its reach from "whoever downloads the release" to "everyone who clicks Update Now". Apple's notarization
scan and Apple's ability to revoke a notarization or a certificate (caught online, T27) are the remaining
checks. Noah decides (Q1): accept it, keep the Developer ID key out of `nightly`, or add an update key
kept offline (§10).

**T5. A redirect to another host.** The download starts at
`https://github.com/Saffsanity/sill/releases/download/<tag>/Sill.zip` (built by Sill, compared with the
API's URL). Redirects are followed only to `https://release-assets.githubusercontent.com` or
`https://objects.githubusercontent.com` (measured 2026-11-11: GitHub sends release downloads to the
first; the second is its older host), with a path under `/github-production-release-asset`, no user,
password or port, at most three. Any other redirect, an http one included, ends the download: nothing is
fetched from it. The API request follows redirects only to `https://api.github.com/`. The session is
ephemeral: no cookies, no cache, no credential store, no Authorization header, `waitsForConnectivity`
off; a fixed User-Agent (`Sill/0.6.1`) and `Accept-Language: en`.

**T6. Too large, too small, the disk filling up.** The declared size must be 1 KB to 64 MiB (v0.6.1's
zip is 5.9 MB); Sill stops reading at one byte past it, and a body that ends short or long is refused, as
is a Content-Length that disagrees. Before downloading, the staging volume must have 4 × the size +
64 MiB free; after reading the zip's directory, its unpacked total + 64 MiB. Every write that fails
(ENOSPC included) ends the update and deletes the staging folder: nothing at Sill.app's path has
changed, since nothing touches it before the swap.

**T7. A truncated or corrupted download.** The SHA-256 of the bytes received must equal the digest;
each entry's CRC-32 and sizes must match; the signature check covers every byte that counts.

**T8. A hostile archive.** Sill reads the zip itself (`UpdateArchive`, pure Swift, Apple's Compression
for deflate) and writes files only through directory descriptors it created (`openat`, `mkdirat`,
`O_NOFOLLOW | O_EXCL`), so no entry can write outside the staging folder whatever its name. Refused
before anything is written:
- a name not under `Sill.app/`; absolute; with `..`, `.`, an empty part, a backslash, a NUL or any byte
  outside printable ASCII (no Unicode normalization tricks on APFS);
- two names equal ignoring case (APFS's default is case-insensitive: the second would overwrite the
  first);
- a symbolic link whose target is absolute, leaves `Sill.app`, or passes through another link; any entry
  under a link (no write through a link);
- a type other than file, directory or link; setuid, setgid or sticky bits; encryption; zip64; a
  compression method other than stored or deflate; a disk-spanning archive;
- a local header whose name, method or sizes disagree with the central directory (one tool reading one,
  another the other, is the classic zip confusion);
- more than 4,096 entries, more than 512 MiB unpacked, an entry that inflates past its declared size, a
  CRC that does not match;
- a top level that is not exactly one directory `Sill.app` (a "bundle that is not a bundle": a file or a
  link named Sill.app, or a second top-level item).
AppleDouble entries (`._name`, `__MACOSX/`) carry only extended attributes and resource forks; they are
skipped, never written, so no resource fork or attribute from the download lands on disk (a zip built on
a Mac whose files carry `com.apple.provenance` has them; v0.6.1's, built by CI, has none). Links are
created last. Directories 0755; files 0644, or 0755 when the archive marks them executable.

**T9. Parsing hostile input.** Sill parses the zip in Swift (bounds-checked, no unsafe pointers into the
file), inflates with Apple's Compression, and lets Security.framework read the bundle's signature,
Mach-O headers and Info.plist, as Finder and Gatekeeper do for any download. Nothing from the download
is executed, loaded (no `dlopen`, no `Bundle.load`, no image or nib from it) or opened by another app
before every check has passed.

**T10. The gap between checking and replacing.** Security.framework's own header says static validation
"is only secure if the code is not subject to concurrent modification". So:
- the bundle is checked where it will be swapped from (the staging folder, same volume, 0700);
- the swap is one `renamex_np(…, RENAME_SWAP)`: atomic, both sides on one volume (`st_dev` compared);
- the bundle is checked again at its final path, every check, and its cdhash must equal the staged one's
  (the same code moved, not another);
- after the launch, the running new process's own code (by pid, `SecCodeCopyGuestWithAttributes`) must
  satisfy the pinned requirement and carry that cdhash, or it is terminated and the old copy put back;
- macOS itself checks a notarized app's integrity at its first launch since Ventura (WWDC22 "What's new
  in privacy"), and the kernel validates every code page as it loads.

**T11. A replaced helper, a stale temporary folder.** There is no helper: no updater binary, no script,
no ditto, no shell. The programs involved are Sill itself and LaunchServices starting the new Sill. The
staging folder is new for each attempt (`FileManager.url(for: .itemReplacementDirectory, in:
.userDomainMask, appropriateFor: Sill.app)`: a random name in this user's temporary folder, 0700, on
Sill.app's volume); nothing in a leftover one is ever read or reused; leftovers (`NSIRD_Sill_*`) are
deleted once a Sill's host has started.

**T12. Another process of the same user.** Malware already running as this user can rewrite what this
user owns; the updater cannot stop that and does not try. What it must not do is lend it Sill's own
right to change Sill.app: since macOS 13, App Management keeps apps of other teams from modifying a
signed app, while Sill (team 9B2KKVM937) may modify itself (NSUpdateSecurityPolicy's default). The
updater runs only Sill's own code, checks at the final path, pins the cdhash through the launch (T10),
and on any doubt swaps the old copy back. A race can make the update fail; it cannot make Sill launch
code other than what it checked.

**T13. Another account on this Mac running the same Sill.app.** Noah's Mac has one (uid 502 runs
/Applications/Sill.app beside uid 501, 2026-11-11). The updater finds every process whose executable is
in its own bundle (`proc_listallpids`, `proc_pidpath`: readable for other users' processes, measured) and
refuses while one runs (Q3): "Sill is open in another account on this Mac (‹name›). Quit it there
first." What would happen otherwise, and why it refuses: that process keeps running its old code (its
executable's vnode stays alive, at the staging path after the swap), but resources it loads later come
from the new bundle at the same path (a mix of versions); its login item names the path, so its next
login starts the new version; its Screen Recording and Accessibility grants are its own, kept by the
designated requirement; its keychain items are in its own keychain, read by the same access group. The
other account cannot touch this user's staging folder (0700). A bundle owned by another account is
refused anyway (T18).

**T14. A second update racing the first.** One AppUpdater per process, a state machine that takes
Update Now only when idle or failed; another Sill of this user running from the same bundle is refused
(T13); right before the swap, the copy at the path must still be the code that is running (its cdhash
equals this process's own), so a copy replaced meanwhile (another account's updater, a drag in Finder)
stops the swap with nothing changed. Two accounts both past that check within milliseconds would both
swap: each puts a checked genuine copy in place; noted, not worth a lock file in /Applications.

**T15. Downgrade and the same version.** The bundle's CFBundleShortVersionString, read from its signed
Info.plist (`kSecCodeInfoPList`, after validation), must be digits and dots only, greater than the
running version, and equal to the tag's version. The running version is this process's own signed
Info.plist's, never `-SillUpdateVersion` (that hook stays the check's, and with it set the updater is
unavailable: §4.1). A test feed (`-SillUpdateFeed`) makes the updater unavailable too.

**T16. The wrong build for this Mac.** The bundle's executable must have a slice for the running
architecture (arm64, or x86_64), and its LSMinimumSystemVersion must not be above this macOS.

**T17. What an update must keep.** The identity (the data-protection keychain's access group): the new
bundle must carry exactly `com.apple.application-identifier` "9B2KKVM937.me.saffer.sill.mac",
`com.apple.developer.team-identifier` "9B2KKVM937" and `keychain-access-groups` containing
"9B2KKVM937.me.saffer.sill.mac", and no `get-task-allow`. The Screen Recording and Accessibility grants
(TCC keeps the designated requirement): the new bundle must satisfy the running app's own designated
requirement, not only the pinned one. The login item (SMAppService.mainApp records the bundle's path:
LoginItem.swift): the same path, by construction. The same bundle identifier and team: pinned.

**T18. Where Sill runs.** Refused, with words (§4.1): a folder this account cannot write, or a Sill.app
it cannot write or does not own; a Sill.app that is a symbolic link; App Translocation (the path holds
`/AppTranslocation/`, or the volume is read-only); a read-only volume; a disk image (DiskArbitration's
device model "Disk Image"); a network volume; Sill not in a `.app` bundle (the bare binary). Never an
admin prompt, never a privileged anything.

**T19. A device streaming; a staged window.** Updating ends every session. A click while a device is
connected asks first (Q2); after the download, if a device connected since the person's answer, it asks
again before installing. The quit is the ordinary one (NSApp.terminate → applicationShouldTerminate →
HostShutdown.releaseForQuit), which puts a staged window home, removes the virtual display and puts
sized windows back, as Quit Sill does.

**T20. The relaunch.** No helper is left behind because none starts. The old Sill launches the new
bundle as a new instance (`NSWorkspace.openApplication`, `createsNewApplicationInstance`, no prompt, not
activated) and keeps running; the new Sill, finding another Sill of this user running, finishes launching
and waits (up to 30 s, a run-loop Timer) for it to quit before it starts anything (no status item, no
host, no keychain). The old Sill waits (up to 30 s) for the new one to finish launching
(`NSRunningApplication.isFinishedLaunching`), checks its running code (T10), then quits from a run-loop
Timer (the modal-loop rule: NSApp.terminate can answer `.terminateLater`). If the new Sill fails to
launch, quits, or does not finish launching in time, the old one terminates it, swaps the old copy back
and stays, saying so. Once the new Sill's host has started, it deletes the staging folder and the old
copy in it. If the new Sill fails after that (it started but crashes later), the old copy is gone; if it
fails before (it crashes during its first start), the old copy is still in the staging folder, whose
path the log gives ("Sill 0.6.1 is kept at …"), and the manual way back is §12's.

**T21. Hooks.** Nothing in Sill.app can loosen the pinned requirement, the allow-list, the version rule
or the size limits: the mechanism takes them as parameters, the app passes two constants
(`UpdateInstallPolicy.Trust.release`, `UpdateInstallPolicy.Endpoints.github`), and no updater file reads
UserDefaults, the environment or the arguments. `Tests/checks/update-install` fails if any app source
builds a Trust or Endpoints other than those constants, or if an updater file mentions UserDefaults,
ProcessInfo or CommandLine. The harness that injects test values (`Tests/update-harness`) compiles the
same files into its own binary; it is not part of any product.

**T22. Logs.** One line per step, never the download URL's signed query (GitHub's short-lived
capability), never more than host and path; what failed and why.

**T23. Homebrew (added).** Sill is also a Homebrew cask (Saffsanity/homebrew-sill). A copy installed by
brew updates like any other (Q6); brew's record then names the old version until `brew upgrade`, which
reinstalls the same or a newer one. The cask can say `auto_updates true`.

**T24. The release process is now part of the updater's contract (added).** Every release from now on
must publish `Sill.zip` (that name) with a single top-level `Sill.app`, stapled, Developer ID signed
with the three entitlements and the embedded profile, its CFBundleShortVersionString equal to its tag.
docs/release-checklist.md says so; `release.sh` already makes exactly that.

**T25. Denial of service.** A hostile release, network or local process can make an update fail. It
fails closed: nothing changed, the reason shown, Open Release Page… there.

**T26. The login item and macOS's records.** SMAppService and TCC key Sill by its path and designated
requirement, both kept. Not measured here (it needs a real update): §12 checks it.

**T27. Revocation.** The signature check runs with macOS's default network behaviour (no
`kSecCSNoNetworkAccess`): when Apple can be reached, a revoked notarization or certificate fails it; with
no network, the stapled ticket suffices (measured: the release's check takes 25 ms either way, so it does
not wait on the network). Not `kSecCSEnforceRevocationChecks`, which would fail every update on a network
that blocks Apple's OCSP (Q8).

## 4. The rule (pure: `Sources/SillMenuBar/UpdateInstallPolicy.swift` and `UpdateArchive.swift`)

Foundation and StreamProtocol's SillVersion only, checked on its own with swiftc
(`Tests/checks/update-install`, with mutants in CI's matrix).

### 4.1 When Update Now is offered, and every refusal

Update Now shows only while the check offers a newer release. It is enabled only when none of these
holds; the first that holds is the line Settings shows (in this order):

| Refusal | Words (Settings › General, under the offer) |
|---|---|
| The running code is not a notarized Developer ID Sill in a `.app` bundle (the bare binary, a development or ad hoc build, an unnotarized test build) | This copy of Sill isn’t a notarized release, so it can’t update itself. |
| A test feed or a test version is in use | This run checks a test feed, so it doesn’t update itself. |
| Translocated | macOS is running Sill from a temporary copy. Move Sill to your Applications folder, open it from there, then update. |
| A disk image | Sill is running from a disk image. Copy it to your Applications folder, open it from there, then update. |
| A read-only or network volume | Sill is on a disk this Mac can’t change (‹volume›). |
| The bundle path is a symbolic link | Sill runs through a link (‹path›), so it can’t replace itself there. |
| The folder or the bundle is not writable, or the bundle belongs to another account | Sill is in a folder this account can’t change (‹folder›). |
| The copy at the path is not the running one | Sill at ‹path› changed since it started. Quit Sill and open it again. |
| Another account runs Sill from this copy | Sill is open in another account on this Mac (‹user›). Quit it there first. |
| Another Sill of this account runs from this copy | Another copy of Sill is running. Quit it first. |
| Not enough free space (estimate) | Not enough free space on ‹volume›: about ‹n› MB are needed. |

Each refusal keeps Open Release Page… and logs one line the first time it is shown in a run.

### 4.2 The version rule

`strictVersion(text)`: digits and dots only, 1 to 8 parts of 1 to 9 digits (no prefix parse: SillVersion
reads "0.6.2-evil" as 0.6.2; this does not). A tag is `v` + a strict version. Allowed only when
`new > running` (SillVersion order) and `new == tag`.

### 4.3 The release and the download

`asset(fromRelease:offeredTag:running:endpoints:)` reads the API's JSON (at most 1 MB): T2's rules.
`downloadURL(tag:)` = endpoints' prefix + tag + "/Sill.zip". `redirectAllowed(url, endpoints)`: T5.
`digest(fromAPI:)` and `digest(fromSHA256File:)`: 64 lowercase hex digits.

### 4.4 The archive (`UpdateArchive`)

`UpdateArchive.read(bytes) -> Result<Listing, Failure>`: the end-of-central-directory record, found
by searching back from the end (a comment is allowed and ignored; one disk only), every central entry
and its local header, T8's rules, the limits; a `Listing` of entries in archive order with their kind,
mode, sizes, CRC and data offset. The writer (UpdateInstaller) only ever writes what a `Listing` says.

### 4.5 The bundle

Gathered by UpdateInstaller from Security.framework, judged here (`bundleVerdict`): in this order, each
with its words (all of them "…, so Sill didn’t install it." after a lead sentence):
1. `Sill.app` is a directory, not a link; `Contents/Info.plist` and `Contents/MacOS/Sill` are regular
   files, the latter executable.
2. The signature is valid: `SecStaticCodeCheckValidityWithErrors` with `kSecCSCheckAllArchitectures |
   kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSRestrictSymlinks | kSecCSRestrictSidebandData |
   kSecCSRestrictToAppLike`, no requirement (measured: a resource fork or a changed resource fails it).
3. It satisfies the pinned requirement, without `notarized`:
   `anchor apple generic and identifier "me.saffer.sill.mac" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "9B2KKVM937"`
   (Apple's anchor, the Developer ID intermediate, a Developer ID Application leaf, the team, the
   identifier: exactly Sill's own designated requirement, read from v0.6.1 with `codesign -d -r-`).
4. It satisfies `notarized`. Which API and why: the Gatekeeper assessment API (SecAssessment) is no
   longer in the macOS 27 SDK's headers, and `spctl` would mean a subprocess, output parsing, and an
   answer that follows the person's Gatekeeper settings (with Gatekeeper turned off it accepts
   anything). The requirement keyword `notarized` is compiled by Security (`csreq`), evaluated in
   process with the rest, independent of those settings, and offline with a stapled ticket; it is not
   in Apple's 2016 requirement-language page, so it was measured (2026-11-11): v0.6.1 satisfies it with
   the network allowed and with `kSecCSNoNetworkAccess`; Calculator.app (validly Apple-signed) and
   Xcode.app (App Store) do not; an ad hoc copy does not. Backed by 5.
5. A stapled ticket is present (`kSecCodeInfoStapledNotarizationTicket`, `kSecCSContentInformation`):
   every release is stapled (release.sh checks it), and it makes 4 independent of the network. (Its
   presence alone proves nothing: an ad hoc re-signed copy keeps the ticket file; 4 checks it.)
6. It satisfies this running app's own designated requirement (T17).
7. Signing information: identifier me.saffer.sill.mac, team 9B2KKVM937, the hardened runtime flag
   (0x10000), the three entitlements exactly, no get-task-allow.
8. Info.plist (`kSecCodeInfoPList`, after 2): CFBundleIdentifier me.saffer.sill.mac, CFBundleExecutable
   Sill, the version rule (4.2), LSMinimumSystemVersion ≤ this macOS.
9. The executable has this Mac's architecture.
The cdhash (`kSecCodeInfoUnique`) is kept: the check at the final path and the launched process must
show the same.

### 4.6 The state machine

Phases: `idle`, `confirming(devices)`, `fetching`, `downloading(received, total)`, `unpacking`,
`checking`, `ready(devices)`, `installing`, `restarting`, `failed(Failure)`. Events: `updateNow(devices)`,
`confirm`, `cancel`, `release(Result)`, `progress`, `downloaded(Result)`, `checked(Result, devices)`,
`installed(Result)`, `launched(Result)`. `next(phase, event) -> (phase, [Effect])` with effects `fetch`,
`download`, `unpack`, `check`, `install`, `launch`, `quit`, `putBack`, `cleanUp`. Update Now is taken only
in `idle` and `failed`; Cancel only before `installing`; after `installing` nothing but the launch's
result moves it. Every failure carries words and whether the old copy was put back.

### 4.7 Words

Settings › General's update section keeps its line, switch and Check Now. With an offer: **Update Now**
(disabled with the refusal's line under it when one holds) and Open Release Page…. During an update the
line says the step ("Downloading Sill 0.6.2… 2.1 of 5.9 MB", "Checking Sill 0.6.2…", "Installing Sill
0.6.2…", "Restarting Sill…") over a progress bar, with Cancel until installing. A failure is the orange
line ("Couldn’t update: ‹why›. Sill 0.6.1 is unchanged.") with Try Again and Open Release Page…. The
status menu's item: "Sill 0.6.2 Is Available…" with "You have 0.6.1; update in Settings" opens Settings ›
General when Update Now is offered (Q4), the release page otherwise (as today); during an update,
"Updating to Sill 0.6.2…" with the step, opening Settings. VoiceOver hears each step and the result.

## 5. The mechanism (`Sources/SillMenuBar/UpdateInstaller.swift`)

Foundation, Security, CryptoKit (SHA-256), Compression (inflate), DiskArbitration and Darwin; no AppKit;
compiled on its own with swiftc by the harness. Its own serial queue; every public step returns a
`Result` with a Failure; nothing throws past it.

- `makeStaging(for installed:)`: the item-replacement directory, its `st_dev` equal to the installed
  bundle's parent's, mode 0700, empty.
- `fetchRelease`: one GET of the latest release, at most 1 MB, 15 s, the redirect rule of the check.
- `download(asset, into staging)`: a delegate-based data task writing to a file it created with
  `O_EXCL`, hashing as it goes, stopping at size + 1, Content-Length checked, the redirect rule,
  cancellable; timeouts 30 s between bytes, 10 minutes in all.
- `unpack(zip)`: read the file (bounded), `UpdateArchive.read`, check space, write the listing under
  directory descriptors, verify each entry's size and CRC, close everything, delete the zip.
- `check(bundle, running:, tag:)`: §4.5's facts, the verdict, the cdhash.
- `install(staged, installed, expectedRunningCDHash)`: lstat the installed path (a directory, not a
  link), its cdhash equal to the running process's, then `renamex_np(staged, installed, RENAME_SWAP)`,
  then `check` at the installed path with the same cdhash; on failure the swap is undone.
- `putBack`: the same swap again (old copy back at its path, new copy in staging).
- `cleanUpStaging(for installed:)`: removes `NSIRD_Sill_*` folders in the item-replacement directory's
  parent folder for that volume (never following a link).

AppUpdater (`Sources/SillMenuBar/AppUpdater.swift`, main actor, @Observable) gathers the facts for
§4.1 (the running code's own signature and cdhash, the bundle path's stat, statfs and DiskArbitration,
`access`, the processes running from the bundle, the free space, the devices), runs the effects, the
relaunch (NSWorkspace, NSRunningApplication, SecCodeCopyGuestWithAttributes), the quit (a run-loop
Timer), and at launch the wait for another instance and, after the host has started, the cleanup.

## 6. Files

New: `UpdateInstallPolicy.swift`, `UpdateArchive.swift`, `UpdateInstaller.swift`, `AppUpdater.swift`
(Sources/SillMenuBar); `Tests/checks/update-install/` (main.swift, build.sh, run.sh, mutants.py);
`Tests/update-harness/` (main.swift, server.py, make-zip.py, run.sh; local only, not CI). Changed:
`AppModel.swift` (owns `updater`), `AppDelegate.swift` (the wait at launch), `SettingsPanes.swift`
(UpdatesSection), `StatusItemController.swift` (the item), `UpdatePolicy.swift` (the footnote),
`DebugHooks.swift` (previews of the new states), `site/privacy.html` (one marked paragraph),
`docs/release-checklist.md` (T24), `docs/DEVELOPMENT.md`, `CLAUDE.md`, `Tests/checks/README.md`,
`.github/workflows/ci.yml` (the mutants matrix).

## 7. Privacy

Update Now sends GitHub (api.github.com once, github.com once, release-assets.githubusercontent.com
once) what the check sends: the Mac's IP address, `User-Agent: Sill/‹version›`, `Accept-Language: en`;
no identifier, cookie or credential. macOS may check the new version's signature and notarization with
Apple, as it does for any app. The privacy page's Update check section gains one paragraph between
`<!-- Update Now: …` and `<!-- /Update Now -->` (docs/release-checklist.md part 1 §3's marker rule).

## 8. Compatibility rules for later versions (part of this feature's contract)

- Every later Sill keeps the wait at launch (§5) and finishes launching within 30 s while another Sill
  runs: the version that updates to it launches it beside itself and waits for that.
- Every release keeps T24's shape. A release that cannot (a renamed asset, a new top level) is installed
  by hand once; the updater refuses it cleanly.
- A change to the pinned requirement (a new team, a new identifier) ships first in a version updated by
  hand; the updater never accepts a requirement from the download.

## 9. What must never be possible, and what enforces it

| Never | Enforced by |
|---|---|
| Installing code not signed by Developer ID team 9B2KKVM937 as me.saffer.sill.mac | §4.5 3, at staging and at the final path; T10's launch check |
| Installing code Apple did not notarize | §4.5 4 and 5 |
| A downgrade or the same version | §4.2, from the bundle's signed Info.plist; the running version from this process's |
| Downloading from a host off the allow-list | T5's redirect delegate, before the request is made |
| Writing outside the staging folder while unpacking | directory descriptors, `O_NOFOLLOW`, §4.4's rules |
| Running anything from the download before it passed | no execution, load or open before §4.5; the launch only after the final check |
| An argument, variable or default loosening any of it in Sill.app | constants only; the update-install check's source rules |
| A privileged step | none exists: no prompt, helper, package or authorization call |
| Half an update | one atomic swap; put back on every later failure |

## 10. Open questions (each with the default this branch takes)

1. **The Developer ID key in GitHub (T4).** Default: the code signature as the trust root, as asked, and
   this question raised before the first release that carries the updater. Options: (a) accept: one
   click installs whatever main's CI signs and notarizes; (b) **recommended**: an update key kept off
   GitHub (CryptoKit Ed25519, the public key compiled in), whose signature over the zip's SHA-256,
   version and tag (`Sill.zip.sig`) the updater also requires — CI can sign and notarize but cannot make
   it; costs a key Noah keeps for the life of the app and a signing step on his Mac per release; a lost
   key means one update by hand; (c) take the Developer ID key out of the `nightly` environment (nightly
   Mac builds ad hoc, or signed on Noah's Mac).
2. **A device connected at the click.** Default: ask ("Updating restarts Sill and disconnects ‹iPad›."
   [Update and Disconnect] [Cancel]), and ask again before installing if one connected meanwhile.
   Alternatives: wait until none is connected; never ask.
3. **Another account runs Sill from this copy.** Default: refuse (T13). Alternative: update anyway; that
   account's Sill runs old code with new resources until it quits.
4. **The status menu's item.** Default: opens Settings › General when Update Now is offered, the release
   page otherwise. Alternatives: the release page always (as today); or the item starts the update.
5. **A nightly updating to a release.** Default: allowed (it is a notarized Developer ID Sill).
6. **A copy installed by Homebrew.** Default: allowed (T23).
7. **A second Sill at launch.** Default: waits up to 30 s for the other to quit, then quits itself with a
   line. Before this change two Sills ran side by side (two hosts, two status items).
8. **Revocation.** Default: macOS's default network behaviour (T27). Alternative: enforce it.
9. **The old copy.** Default: kept in the staging folder until the new Sill's host has started, then
   deleted. Alternatives: to the Trash; kept until the next launch.
10. **Quarantine on the new copy.** Default: none (the update is checked by Sill; macOS checks a
    notarized app's integrity at first launch anyway). With it, the first launch would show "Sill is an
    app downloaded from the Internet" after a one-click update.
11. **Cancel during the download.** Default: yes, until installing begins.

## 11. Gates (what this branch verifies without touching Noah's Sill)

- G1 `Tests/checks/update-install`: every rule of §4 and its words; every mutant caught.
- G2 `Tests/update-harness/run.sh`: against scratch bundles in `.build` (ad hoc, a test identifier, the
  trust and endpoints injected by the harness only) and a loopback server: the positive path, and each
  hostile case refused for the right reason with the installed copy's tree hash unchanged: wrong
  identifier, wrong team, ad hoc, tampered after signing, lower version, same version, a version ≠ tag,
  a symlink escape, a traversal name, case-duplicate names, a local/central mismatch, a zip bomb, an
  AppleDouble entry (skipped, still installs), a redirect to another host, a redirect to http, a
  truncated download, an oversize one, a wrong digest, a full disk (a tiny disk image); the swap and its
  put-back; the genuine v0.6.1 (downloaded read-only with `gh`) under the production trust with an
  injected running version: 0.6.0 accepted, 0.6.1 and 0.6.2 refused, tampered, ad hoc re-signed and
  unstapled copies refused.
- G3 `swift build -c release`: only the known CaptureProbe warning.
- G4 `Tests/checks/run-all.sh`: all pass.
- G5 previews from the bare SillMenuBar binary (never the bundle) against main's: only the update
  section, its new states and menu.txt's update samples differ.
- Not on this Mac: the real end to end (two notarized releases and Noah's hands: §12). No built Sill.app
  is launched, /Applications/Sill.app is never touched, Noah's keychain and identity are never used.

## 12. Noah's end-to-end test (needs two notarized builds; nothing here does it)

The real path cannot be rehearsed with a GitHub release of Saffsanity/sill without offering it to
everyone, so the rehearsal uses a throwaway public repository and a test branch that changes only the
two repository constants.

Prepare (on his Mac, from this branch merged into a scratch branch `update-rehearsal`, never pushed to
main):
1. Create a public repository `Saffsanity/sill-update-rehearsal` (no code needed).
2. On `update-rehearsal`, set `UpdatePolicy.feed` and `UpdateInstallPolicy.Endpoints.github`'s
   repository to it (two lines; `git grep -n 'Saffsanity/sill/'` finds them), and
   CFBundleShortVersionString to 0.6.90. `SILL_SIGN_IDENTITY=… SILL_NOTARY_PROFILE=sill-notary
   SILL_UNIVERSAL=1 Scripts/release.sh` (no `--publish`): a notarized `.build/Sill-0.6.90.zip`. Keep it
   (build A).
3. Version 0.6.91, the same command: build B. Publish B as a release `v0.6.91` of the rehearsal
   repository with `Sill.zip` and `Sill.zip.sha256` (`gh release create v0.6.91 --repo
   Saffsanity/sill-update-rehearsal …`).
4. Note what to come back to: `/Applications/Sill.app`'s version (Settings › General's footer), and
   that `~/Downloads/Sill.app` and the getsill.app download are the way back.

Run:
5. Quit Sill. Unzip build A and drag it to /Applications, replacing Sill. Open it. Screen Recording and
   Accessibility stay allowed (same designated requirement), the iPad stays paired (same keychain group).
6. Settings › General › Check Now: "Sill 0.6.91 is available." with Update Now.
7. With the iPad connected, Update Now: the question with the iPad's name; Update and Disconnect.
8. Watch: the progress line, "Checking…", "Installing…", "Restarting Sill…"; the menu bar icon goes and
   comes back within a few seconds; the iPad reconnects by itself.
9. Sill.log (Show Log…): "Update: downloading Sill 0.6.91 (… MB) from github.com", "Update: Sill 0.6.91
   checked: Developer ID 9B2KKVM937, notarized, 0.6.91 > 0.6.90 …", "Update: replaced
   /Applications/Sill.app …", "Update: Sill 0.6.91 started (pid …); this Sill quits", then from the new
   process "Sill 0.6.91 (…) running from /Applications/Sill.app" and "Update: removed the previous copy
   …".
10. Settings › General's footer says 0.6.91; Screen Recording and Accessibility are still allowed (no
    prompt), Launch at Login is still on, the iPad connects without pairing again, and macOS showed no
    "downloaded from the Internet" or "App Management" prompt.
11. `codesign -dv /Applications/Sill.app` says 0.6.91's cdhash; `ls -la` shows Noah as owner.
12. Refusals, one at a time, each with Update Now disabled and its line: run build A from
    `~/Downloads` (translocated or not: drag it out of the zip into Downloads, open it there): "macOS is
    running Sill from a temporary copy…" or the folder line; with the other account running Sill:
    "Sill is open in another account…".
13. A failed launch: rehearse once with a build C (0.6.92) whose `main.swift` calls `exit(1)` at once,
    published as `v0.6.92`: Update Now, then "Sill 0.6.92 didn’t start, so Sill 0.6.91 is back" and
    0.6.91 still running.

Back: quit Sill, install the real release from getsill.app/download (or `~/Downloads/Sill.app`),
open it; delete the rehearsal repository. If anything goes wrong in between: the old copy is in the
folder Sill.log names ("Sill 0.6.90 is kept at /private/var/folders/…/NSIRD_Sill_…/Sill.app"); quit
Sill, Finder › Go › Go to Folder…, that folder, drag Sill.app to Applications, Replace.

The first real one: when 0.6.3 (or whichever release follows the first one with the updater) is out,
Noah's own Sill offers it; steps 6 to 11 again, then the issue's notes.

## 13. Progress

- 2026-11-11 22:40 EST: facts gathered (below), plan written.
- Measured for this plan: v0.6.1's zip (13 entries, stored and deflate, 8 with data descriptors, no
  AppleDouble, no links, 16.1 MB unpacked); its signature (Developer ID 9B2KKVM937, runtime, universal,
  stapled, the designated requirement in §4.5 3); the `notarized` keyword (§4.5 4); strict validation
  failing a resource fork and a changed resource or executable; GitHub's redirect host
  (release-assets.githubusercontent.com, path `/github-production-release-asset/1381093165/…`); the
  item-replacement directory on the data volume and an atomic swap with a folder in ~/Downloads;
  `proc_pidpath` reading uid 502's Sill; a directory moved to another parent needs write permission on
  itself.
