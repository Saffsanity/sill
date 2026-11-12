# One-click update for Sill for Mac — the plan

Noah, 2026-11-11: "make a note that I want to make the Sill update checker also have a 1 click updater
as a new feature", and the same evening: "Start working on ... one-click updater ... Use subagents."
Branch `one-click-update` from main at dd6ea6a (0.6.1 released that day, plus #339), main at 936d627 (#349)
merged in; draft pull request #354.

This is the most security-sensitive code Sill for Mac has: it downloads a program and replaces the app
that is running. It is written for a hostile reader: every claim says what enforces it, and every
residual risk is named. A separate security review follows.

**Status: inert until Noah makes the update key** (his choice of 2026-11-12, §10 Q1; his steps, §14).
Update Now needs two signatures on a release (§3):
Apple's Developer ID and notarization, and Noah's own update key, whose public half is compiled in
(`UpdateManifest.releaseKeys`). That list is empty on this branch, on purpose: no key exists yet and none
was made here. With it empty, no build from this branch shows Update Now anywhere; Settings and the menu
are what they were. Setting it is one line (§4.8), Noah's.

## 1. What and why

Sill for Mac has an update **check** (docs/update-notice-plan.md §6; `UpdateChecker`, `UpdatePolicy`):
once a day it asks GitHub's releases feed whether a newer published release exists and, when one does,
offers "Sill 0.6.2 Is Available…" in the status menu and in Settings › General, which opens the
release's page. It downloads nothing.

One click: when the check has found a newer release that Noah has signed for it, **Update Now** (beside
the existing Open Release Page…) downloads it, checks it, replaces Sill.app where it is, and relaunches
Sill. Progress and any failure show inline in Settings › General (no alert: AppDelegate's modal-loop
rule). Never automatic, never silent: only the person's click starts it, and a click while a device is
connected asks first. Whenever anything about the situation is not exactly right, the updater changes
nothing and says why, and Open Release Page… remains.

Hard rules that hold throughout: Apple frameworks only (no Sparkle; CryptoKit for the signature), no
server of Sill's, nothing privileged ever (no admin prompt, no helper tool, no SMJobBless, no installer
package), no test hook that loosens anything in Sill.app, and the update key never on GitHub.

Not in scope: automatic or background installs; delta updates; "Skip This Version"; the iOS app (the
App Store updates it); a nightly is never offered the release of its own version (the check compares
versions only, so a nightly 0.6.2 (1400) sees nothing until 0.6.3 is out: known, unchanged).

## 2. The design on one page

```
Update Now (a SwiftUI Button action, or the confirmation's)
  │  refusal? (§4.1) ─────────────────────────────► the reason, inline; nothing done
  │  devices connected? ──────────────────────────► "Update and Disconnect" / Cancel
  ▼
the release again: GET api.github.com/repos/Saffsanity/sill/releases/latest
  │  the same tag as offered, strictly newer, exactly one Sill.zip and one Sill.zip.manifest (§4.3)
  ▼
the manifest (≤ 4 KB): signed with a key compiled into this Sill? names this tag, this zip's size? (§4.3)
  ▼
staging folder: FileManager's item-replacement directory on Sill.app's own volume (0700, this user's)
  │
download https://github.com/Saffsanity/sill/releases/download/<tag>/Sill.zip
  │  redirects only to GitHub's release-assets host; https; the manifest's size and SHA-256
  ▼
unpack with Sill's own zip reader (no ditto, no process), every entry checked first (§4.4)
  ▼
check staging/Sill.app (§4.5): Developer ID team 9B2KKVM937 as me.saffer.sill.mac, notarized, valid
  strictly with nested code, this app's own designated requirement, the three keychain entitlements,
  the hardened runtime, a stapled ticket, version > running and = the manifest's, a slice for this Mac,
  this macOS, and every slice's code the one the manifest names
  ▼
devices connected since the click? ───────────────► "Install and Disconnect" / Cancel
  ▼
the copy at the path is still the one running (cdhash), then renamex_np(RENAME_SWAP): atomic
  ▼
check /Applications/Sill.app again, every check, the same code ─ fails ─► swap back, say so
  ▼
launch it as a new instance (NSWorkspace, no prompt); it waits for this one to quit
  │  not finished launching in 30 s, or it quits, or its running code is not the code checked
  │  ──────────────────────────────────────────────► stop it, swap back, say so
  ▼
this Sill quits through its normal quit path (a run-loop Timer: windows home, virtual display gone)
  ▼
the new Sill starts its host, then deletes the staging folder with the old copy in it
```

## 3. The threat model, point by point

What is trusted, and why. Two signatures, each necessary, neither enough alone:
- **Noah's update key** (Ed25519, CryptoKit): its signature over the release's manifest (§4.3) says
  "Noah released exactly this zip and exactly this code as this version". Its public half is compiled
  into Sill; its private half lives only on Noah's Mac (§4.8), never on GitHub or in CI. It answers T4.
- **The code signature**, checked by Security.framework against a requirement compiled into Sill:
  Apple's anchor, a Developer ID Application certificate of team 9B2KKVM937, the identifier
  me.saffer.sill.mac, and Apple's notarization. It says "this is Sill, built and signed with Sill's
  Developer ID, and Apple scanned and notarized it"; it keeps the grants and the keychain (T17).
Not trusted: the network (TLS is necessary, not sufficient: a Mac behind a TLS-intercepting proxy trusts
its root), GitHub's metadata, the release's `.sha256` file and the API's `digest` (same origin as the
file: GitHub's digest is compared with the signed manifest and must agree, nothing more).

**T1. A hostile network** (Wi‑Fi, DNS, a proxy, a TLS root someone installed). It can block, slow,
truncate or replace what Sill downloads. Replacement fails the manifest's signature (before the zip is
fetched) or its SHA-256 (after); truncation fails the size, the hash, the zip reader and the code
signature; a block or a slow link fails with words and changes nothing. Requests go only to the
allow-list (T5), so the network cannot point Sill at a host on the LAN.

**T2. GitHub's release metadata is input, not instruction.** The tag must be `v` + digits and dots
exactly (no `-rc`, no path characters); the release must not be a draft or a pre-release; the zip must be
named exactly `Sill.zip`, `state` "uploaded", 1 KB to 64 MiB, and the manifest `Sill.zip.manifest`, at
most 4 KB, one of each; each `browser_download_url` must equal the URL Sill builds itself from the tag;
GitHub's `digest`, when sent, must be `sha256:` + 64 hex digits and equal the manifest's. The tag must
be the one the check offered, and its version newer than the running one. Anything else: refused.

**T3. A compromised GitHub account or release.** An attacker who can publish releases can replace
`Sill.zip`, publish a release "v9.9.9", or move a tag. Without the update key they cannot make a
manifest any Sill accepts, so nothing is even downloaded; without Sill's Developer ID key and Apple's
notarization, nothing they make passes §4.5. A genuine older manifest and zip re-served under a newer
tag: the manifest names its own tag and version, both must match, and the version must be newer than
the running one: refused. A withheld release (a "freeze") cannot be detected: the next check offers
the newest, and a release Noah signed later is offered then.

**T4. The Developer ID key lives in GitHub Actions (added: the biggest one), and the second factor that
answers it.** Since 2026-10-30 `SILL_SIGN_IN_CI` is `true`: the `release` environment holds the Developer
ID identity and the notary key behind Noah's approval, and the `nightly` environment holds them too, with
**no reviewer**, reachable by any commit on main at the next night's run, and that job's token can publish
a release (CLAUDE.md, "Nightly builds", the review's "route through main"). So "a commit lands on main" is
enough to produce a Developer ID signed, notarized Sill and to publish it as the latest release: the code
signature alone would prove only "built by Sill's CI", and one click would install it everywhere. The
update key closes that: CI can sign and notarize and publish, but it cannot sign a manifest, so no Sill
installs what it publishes; the person still sees Open Release Page…, as today. The signing step must not
reopen it: `sign-update.sh` signs only a zip Noah knows without GitHub (the one `release.sh` made on his
Mac, byte for byte, or the SHA-256 printed by a release workflow run he approved), so a build CI
published unapproved, or a zip swapped in a real release before he signs, is refused there; and the key is
held by one signer binary built once from files he read (`--install-signer`, outside the repository),
never rebuilt from the checkout of the day, which the keychain item trusts alone. That binary would sign
whatever it is handed, and any program running as Noah can run it (a script of a later commit he runs,
release.sh or make-app.sh among them, or a changed `sign-update.sh`), so it signs nothing with the
keychain's key until Noah confirms in person (LocalAuthentication: Touch ID or his password), the prompt
naming the tag, the zip's size and the start of its SHA-256, which he compares with what `release.sh` (or
the approved run) printed: nothing is signed unseen (the second review, §12b). What remains: someone with
both the update key (Noah's Mac or its backup) and a Developer ID signed, notarized build, or Noah allowing
a prompt he did not compare. The two alternatives Noah could have chosen instead are §10 Q1.

**T5. A redirect to another host.** Downloads start at
`https://github.com/Saffsanity/sill/releases/download/<tag>/<asset>` (built by Sill, compared with the
API's URL). Redirects are followed only to `https://release-assets.githubusercontent.com` or
`https://objects.githubusercontent.com` (measured 2026-11-11: GitHub sends release downloads to the
first, path `/github-production-release-asset/1381093165/…`; the second is its older host), with a path
under `/github-production-release-asset`, no user, password or port, at most three. Any other redirect,
an http one included, ends the transfer before a request goes there. The release request follows
redirects only to `https://api.github.com/`. Each session is ephemeral: no cookies, no cache, no
credential store; every authentication challenge but the server's certificate is refused, so no
credential is ever sent; a fixed User-Agent (`Sill/0.6.1`) and `Accept-Language: en`; TLS 1.2 at least.

**T6. Too large, too small, the disk filling up.** The manifest's size (signed) must equal the API's, 1
KB to 64 MiB (v0.6.1's zip is 5.9 MB); Sill stops reading at one byte past it, and a body that ends short
or long is refused, as is a Content-Length that disagrees. Before downloading, the volume must have 4 ×
8 MiB + 64 MiB free (the refusal); after reading the zip's directory, its unpacked total + 64 MiB. Every
write that fails (ENOSPC included) ends the update and deletes the staging folder: nothing at Sill.app's
path has changed, since nothing touches it before the swap.

**T7. A truncated or corrupted download.** The SHA-256 of the bytes received, and again of the file
read back for unpacking, must equal the signed manifest's; each entry's CRC-32 and sizes must match; the
code signature covers every byte that counts.

**T8. A hostile archive.** Sill reads the zip itself (`UpdateArchive`, pure Swift, Apple's Compression
for deflate) and writes files only through directory descriptors it created (`openat`, `mkdirat`,
`O_NOFOLLOW | O_EXCL`), so no entry can write outside the staging folder whatever its name. Refused
before anything is written:
- a name not under `Sill.app/`; absolute; with `..`, `.`, an empty part, a backslash, a NUL or any byte
  outside printable ASCII (no Unicode normalization tricks on APFS);
- two names equal ignoring case (APFS's default is case-insensitive: the second would overwrite the
  first);
- a symbolic link whose target is absolute, leaves `Sill.app`, points at nothing in the archive or at
  another link; any entry under a link (no write through a link);
- a type other than file, folder or link; setuid, setgid or sticky bits; encryption; zip64; a
  compression method other than stored or deflate; a disk-spanning archive; not made on a Unix system;
- a local header whose name, method, flags or sizes disagree with the central directory (one tool
  reading one, another the other, is the classic zip confusion); two entries sharing bytes;
- more than 4,096 entries, more than 512 MiB unpacked, an entry that claims to inflate more than 1,100
  times or does inflate past its declared size, a CRC that does not match;
- a top level that is not exactly one folder `Sill.app` (a "bundle that is not a bundle": a file or a
  link named Sill.app, or a second top-level item).
AppleDouble entries (`._name`, `__MACOSX/`) carry only extended attributes and resource forks; they are
skipped, never written, so no resource fork or attribute from the download lands on disk (a zip built on
a Mac whose files carry `com.apple.provenance` has them, as ditto writes them; v0.6.1's, built by CI, has
none). Links are created last. Folders 0755; files 0644, or 0755 when the archive marks them executable;
each file flushed (F_FULLFSYNC) before the swap.

**T9. Parsing hostile input.** Sill parses the manifest (4 KB of printable ASCII, a strict grammar) and
the zip in Swift (bounds-checked), inflates with Apple's Compression, and lets Security.framework read
the bundle's signature, Mach-O headers and Info.plist, as Finder and Gatekeeper do for any download.
Nothing from the download is executed, loaded (no `dlopen`, no `Bundle.load`, no image or nib from it)
or opened by another app before every check has passed.

**T10. The gap between checking and replacing.** Security.framework's own header says static validation
"is only secure if the code is not subject to concurrent modification". So:
- the bundle is checked where it will be swapped from (the staging folder, same volume, 0700);
- the swap is one `renamex_np(…, RENAME_SWAP)`: atomic, both sides on one volume (`st_dev` compared);
- the bundle is checked again at its final path, every check, and its code must be the code checked
  (every slice's cdhash) — which the manifest also names;
- after the launch, the running new process's own code (by pid, `SecCodeCopyGuestWithAttributes`) must
  satisfy the pinned requirement with one of those cdhashes, or it is stopped and the old copy put back;
- macOS itself checks a notarized app's integrity at its first launch since Ventura (WWDC22 "What's new
  in privacy"), and the kernel validates every code page as it loads.

**T11. A replaced helper, a stale temporary folder.** There is no helper: no updater binary, no script,
no ditto, no shell. The programs involved are Sill itself and LaunchServices starting the new Sill. The
staging folder is new for each attempt (`FileManager.url(for: .itemReplacementDirectory, in:
.userDomainMask, appropriateFor: Sill.app)`: a random name in this user's temporary folder, 0700, on
Sill.app's volume); nothing in a leftover one is ever read or reused; the one an update leaves is deleted
once the next Sill's host has started (T20).

**T12. Another process of the same user.** Malware already running as this user can rewrite what this
user owns; the updater cannot stop that and does not try. What it must not do is lend it Sill's own
right to change Sill.app: since macOS 13, App Management keeps apps of other teams from modifying a
signed app, while Sill (team 9B2KKVM937) may modify itself (NSUpdateSecurityPolicy's default: apps of the
same Team ID may). The updater runs only Sill's own code, checks at the final path, pins the code through
the launch (T10), and on any doubt swaps the old copy back, but only the old copy: what waits in the
staging folder after the swap (this user's, so anything of this user can change it) is put back only if it
is still the code that was running (its cdhash), else it stays out and the checked new copy stays in place.
A race can make the update fail; it cannot make Sill launch, or put into Sill.app's place, code other than
what it checked or what was running. The check at the final path reads through Security's static code,
which reads the files again: an NSBundle and a CFBundle made for that path before the swap (as
Sill.app's Bundle.main is) still give the old Info.plist after it (measured in the harness: 1.0 from
both, 1.1 from Security), so after the swap the updater decides nothing from a bundle object (it reads
Bundle.main only at launch, for the running version). A folder above Sill.app that is a link is refused (§4.1), so the swap
cannot be sent elsewhere between the checks and the exchange; the exchange itself is by path (not by
directory descriptors), which a process of this user that can rename folders above Sill.app could still
race: T12's residue. Not measured here: whether App Management stops
another process of this user from renaming the bundle's folder itself (Apple's pages don't say); nothing
here depends on it.

**T13. Another account on this Mac running the same Sill.app.** Noah's Mac has one most days (a second
logged-in account runs /Applications/Sill.app beside his, measured 2026-11-11). The updater finds every
process running its executable (the same file by device and inode, whatever path started it) or any file
in its bundle (`proc_listallpids`, `proc_pidpath`: readable for other users' processes, measured), and
every other Sill of this account by bundle identifier wherever it runs from (the new copy waits for every
one of them, so one left running would leave no Sill), and refuses while one runs (Q3); it looks again
right before the swap. What would happen otherwise, and why it
refuses: that process keeps running its old code (its executable's vnode stays alive, at the staging path
after the swap), but resources it loads later come from the new bundle at the same path (a mix of
versions); its login item names the path, so its next login starts the new version; its Screen Recording
and Accessibility grants are its own, kept by the designated requirement; its keychain items are in its
own keychain, read by the same access group. The other account cannot touch this user's staging folder
(0700). A bundle owned by another account is refused anyway, with words of its own (T18, §4.1): an
update leaves Sill.app owned by the account that ran it, so from the other account Update Now then says
"Sill belongs to another account on this Mac (‹name›). Update it from that account." What Noah sees: Q3.

**T14. A second update racing the first.** One AppUpdater per process, a state machine that takes Update
Now only when idle or failed, and every step's answer carries its attempt: Cancel retires the attempt, and
an answer of another attempt is dropped before it touches anything; another Sill of this user is refused
(T13); right before
the swap, the copy at the path must still be the code that is running (its cdhash, as a requirement the
kernel's copy of this process must satisfy), so a copy replaced meanwhile (another account's updater, a
drag in Finder) stops the swap with nothing changed. Two accounts both past that check within
milliseconds would both swap: each puts a checked genuine copy in place; noted, not worth a lock file in
/Applications.

**T15. Downgrade and the same version.** The bundle's CFBundleShortVersionString, read from its signed
Info.plist (`kSecCodeInfoPList`, after validation), must be digits and dots only, greater than the
running version, and equal to the manifest's (which equals its tag's). The running version is this
process's own bundle's, read at launch, never `-SillUpdateVersion` (that hook stays the check's, and with
it, or a test feed, Update Now is unavailable: §4.1).

**T16. The wrong build for this Mac.** The bundle's executable must have a slice for the running
architecture (arm64, or x86_64 under Rosetta), and its LSMinimumSystemVersion must not be above this
macOS.

**T17. What an update must keep.** The identity (the data-protection keychain's access group): the new
bundle must carry `com.apple.application-identifier` "9B2KKVM937.me.saffer.sill.mac",
`com.apple.developer.team-identifier` "9B2KKVM937" and `keychain-access-groups` containing
"9B2KKVM937.me.saffer.sill.mac", and no `get-task-allow`. The Screen Recording and Accessibility grants
(TCC keeps the designated requirement): the new bundle must satisfy the running app's own designated
requirement, not only the pinned one. The login item (SMAppService.mainApp records the bundle's path:
LoginItem.swift): the same path, by construction. The same bundle identifier and team: pinned.

**T18. Where Sill runs.** Refused, with words (§4.1): a folder this account cannot write, or a Sill.app
it cannot write or does not own; a Sill.app that is a symbolic link; App Translocation (the path holds
`/AppTranslocation/`, or the volume is read-only); a read-only volume; a disk image (an I/O Registry
ancestor is the disk image driver: measured, AppleDiskImageDevice on macOS 27); a network volume; Sill not
in a `.app` bundle (the bare binary). Never an admin prompt, never a privileged anything.

**T19. A device streaming; a staged window.** Updating ends every session. A click while a device is
connected asks first (Q2); after the download, if a device the person did not agree to disconnect has
connected, it asks again before installing. The quit is the ordinary one (NSApp.terminate →
applicationShouldTerminate → HostShutdown.releaseForQuit), which puts a staged window home, removes the
virtual display and puts sized windows back, as Quit Sill does.

**T20. The relaunch.** No helper is left behind because none starts. The old Sill launches the new
bundle as a new instance (`NSWorkspace.openApplication`, `createsNewApplicationInstance`, no prompt, not
activated) and keeps running; the new Sill, finding another Sill of this user running, finishes launching
and waits (a run-loop Timer, up to 30 s) for it to quit before it starts anything (no status item, no
host, no keychain). The old Sill waits (up to 30 s) for the new one to finish launching
(`NSRunningApplication.isFinishedLaunching`), checks its running code (T10), then quits from a run-loop
Timer (the modal-loop rule: NSApp.terminate can answer `.terminateLater`). If the new Sill fails to
launch, quits, or does not finish launching in time, the old one stops it, swaps the old copy back and
stays, saying so. Once the new Sill's host has started, it deletes the staging folder and the old copy in
it, never while an update of its own is under way, and never a folder holding a copy that could not be put
back (set aside by a rename, with a note in it: the person's way back stays until they move it). It finds
the folder by a note the old Sill wrote right after the swap (`Update Now leftover.txt` in Sill's Caches
folder), not by listing: macOS's System Policy denies reading the temporary-items folder to most processes,
Sill.app among them (measured: the harness and an ad hoc app started by Launch Services both get EPERM
listing it, "deny(1) file-read-data …/TemporaryItems" in the log). The note is this user's to write, so
before deleting anything the new Sill checks that the folder it names still is one of its own staging
folders that may go (directly in the item-replacement folder for Sill.app's volume, `NSIRD_Sill_…`, this
user's, not a link, without the kept note); a forged note can name nothing else. If the new Sill fails
after that, the old copy is gone; if it fails before (it crashes during its first start), the old copy is
still in the staging folder, whose path the log gives ("Sill 0.6.1 is kept at …"), and the way back is §12's
last paragraph.

**T21. Hooks.** Nothing in Sill.app can loosen the pinned requirement, the update keys, the allow-list,
the version rule or the size limits: Trust and Endpoints are immutable values made whole; the mechanism
takes them as parameters; the app passes two constants (`UpdateInstallPolicy.Trust.release`,
`.Endpoints.github`); no updater file reads UserDefaults, the environment or the arguments.
`Tests/checks/update-install` reads the app's sources and fails if any file but the policy makes a Trust
or Endpoints (`Trust(`, `Trust.init(`), if any file but AppUpdater makes an UpdateInstaller, if AppUpdater
gives it anything but the two constants, or if an updater file's code mentions UserDefaults,
CFPreferences, NSUbiquitousKeyValueStore, `.environment`, `.arguments`, CommandLine, getenv, `-Sill` or
`SILL_`. A text rule catches the plain ways, not every way: a reviewer still reads changes to these files. The harness that injects test values (`Tests/update-harness`)
compiles the same files into its own binary; it is no part of any product.

**T22. Logs.** One line per step, never the download URL's signed query (GitHub's short-lived
capability), never more than host and path; what failed and why.

**T23. Homebrew (added).** Sill is also a Homebrew cask (Saffsanity/homebrew-sill). A copy installed by
brew updates like any other (Q6); brew's record then names the old version until `brew upgrade`, which
reinstalls the same or a newer one. The cask can say `auto_updates true`.

**T24. The release process is now part of the updater's contract (added).** Every release from now on
must publish `Sill.zip` (that name) with a single top-level `Sill.app`, stapled, Developer ID signed with
the three entitlements and the embedded profile, its CFBundleShortVersionString equal to its tag; and,
for Update Now, `Sill.zip.manifest` signed on Noah's Mac (§4.8). docs/release-checklist.md says so;
`release.sh` already makes the zip exactly so.

**T25. Denial of service.** A hostile release, network or local process can make an update fail. It
fails closed: nothing changed, the reason shown, Open Release Page… there.

**T26. The login item and macOS's records.** SMAppService and TCC key Sill by its path and designated
requirement, both kept. Not measured here (it needs a real update): §12 checks it.

**T27. Revocation.** The code signature check runs with macOS's default network behaviour (no
`kSecCSNoNetworkAccess`), so macOS may ask Apple about a revoked notarization or certificate; with no
network, the stapled ticket suffices. Measured: the release's check takes 25 ms with and without
`kSecCSNoNetworkAccess`, so with a stapled ticket it likely makes no online check at all; whether a revoked
notarization would be caught is not measured (no revoked build to try). Not
`kSecCSEnforceRevocationChecks`, which would fail every update on a network that blocks Apple's OCSP (Q8).

**T28. The update key itself (added with the second factor).** Lost: no Sill can verify a new manifest,
so no release shows Update Now (Open Release Page… as today) until a release carrying a new public key is
installed by hand once (§4.8). Leaked: the attacker still needs a Developer ID signed, notarized build
(T4's route through CI, or Sill's Developer ID key); the answer is the same rotation, with the release
notes asking people to update by hand once. A key compiled in that is not a usable Ed25519 public key
(wrong length, not decodable, or one of the points of small order, for which a signature can be forged
for some messages) makes every manifest fail: `UpdateManifest.usableKey`, checked for every compiled key.

**T29. A release not signed yet (added).** The check stores whether the release lists `Sill.zip.manifest`
(`updateLatestSigned`); without it Update Now does not show and the release page is the way, as today.
If someone clicks in the moment between the check and Noah's signing, the release is read again at the
click and the answer is "Sill 0.6.2 isn’t ready for Update Now yet. Try again later, or open its release
page." — nothing downloaded.

## 4. The rule (pure: `UpdateInstallPolicy.swift`, `UpdateManifest.swift`, `UpdateArchive.swift`)

Foundation, CryptoKit, Compression and StreamProtocol's SillVersion only, checked on their own with
swiftc (`Tests/checks/update-install`, with mutants in CI's matrix).

### 4.1 When Update Now is offered, and every refusal

Update Now shows only in a build with an update key, while the check offers a newer release that lists
its manifest. It is enabled only when none of these holds; the first that holds is the line Settings
shows under the offer (in this order):

| Refusal | Words (Settings › General, under the offer) |
|---|---|
| The running code is not a notarized Developer ID Sill in a `.app` bundle (the bare binary, a development or ad hoc build, an unnotarized test build) | This copy of Sill isn’t a notarized release, so it can’t update itself. |
| A test feed or a test version is in use | This run checks a test feed, so it doesn’t update itself. |
| Translocated | macOS is running Sill from a temporary copy. Move Sill to your Applications folder, open it from there, then update. |
| A disk image | Sill is running from a disk image. Copy it to your Applications folder, open it from there, then update. |
| A read-only volume | Sill is on a disk this Mac can’t change (‹volume›). |
| A network volume | Sill is on a network disk (‹volume›), so it doesn’t update itself there. |
| The bundle path is a symbolic link | Sill runs through a link (‹path›), so it can’t replace itself there. |
| The folder or the bundle is not writable | Sill is in a folder this account can’t change (‹folder›). |
| The bundle belongs to another account (the last to install or update it) | Sill belongs to another account on this Mac (‹full name›). Update it from that account. |
| The copy at the path is not the running one | Sill at ‹path› changed since it started. Quit Sill and open it again. |
| Another account runs Sill from this copy | Sill is open in another account on this Mac (‹full name›). Quit it there first, then update. |
| Another Sill of this account runs from this copy | Another copy of Sill is running. Quit it first, then update. |
| Not enough free space (estimate) | Not enough free space on ‹volume›: about ‹n› MB are needed. |

Each refusal keeps Open Release Page… and logs one line the first time it is shown in a run.

### 4.2 The version rule

`strictVersion(text)`: digits and dots only, 1 to 8 parts of 1 to 9 digits (no prefix parse: SillVersion
reads "0.6.2-evil" as 0.6.2; this does not). A tag is `v` + a strict version. Allowed only when
`new > running` (SillVersion order) and `new == manifest's version == tag's`.

### 4.3 The release, the manifest and the download

`releaseToInstall(json, offeredTag:, running:, endpoints:)` reads the API's JSON (at most 1 MB): T2's
rules. `assetURL(tag:, name:)` = endpoints' prefix + tag + "/" + name. `downloadRedirectAllowed` and
`apiRedirectAllowed`: T5.

The manifest (`UpdateManifest`), `Sill.zip.manifest`, ASCII, each line ending in "\n", at most 4 KB:

```
Sill update 1
tag v0.6.2
version 0.6.2
build 1400
asset Sill.zip
size 5920002
sha256 a50c5fd38958db5d3f9aea4ef569705effa3462b2d522b73c12baea0a1fc9926
cdhash arm64 d5feca97b4d531345aefab17bb8b588358f2975f
cdhash x86_64 ‹40 hex›
key 1a2b3c4d
signature ‹88 characters of base64›
```

The signature is Ed25519 (CryptoKit's Curve25519.Signing) over every byte before the `signature` line.
`key` is the first 8 hex digits of SHA-256 of the signing public key: it picks the compiled-in key to try.
Read strictly: exactly these lines in this order, one or both architectures (arm64 first), the version
equal to the tag's, lowercase hex, canonical base64, nothing else. Verified before the zip is fetched;
then `manifestMatches`: its tag and version are the release's, its asset is `Sill.zip`, its size is the
API's, and GitHub's digest (when sent) is its SHA-256. The zip must then be exactly its size and
SHA-256, and the unpacked app's code exactly its cdhashes (§4.5).

### 4.4 The archive (`UpdateArchive`)

`UpdateArchive.read(bytes, top:) -> Result<Listing, Problem>`: the end-of-central-directory record,
found by searching back from the end (a comment is allowed and ignored; one disk only), every central
entry and its local header, T8's rules, the limits; a `Listing` of entries in archive order with their
kind, mode, sizes, CRC and data offset. `inflate` hands each piece to the writer and refuses more than
the size. The writer (UpdateInstaller) only ever writes what a `Listing` says.

### 4.5 The bundle

Gathered by UpdateInstaller from Security.framework and lstat, judged here (`verdict`), in this order:
1. `Sill.app` is a folder, not a link; `Contents/Info.plist` and `Contents/MacOS/Sill` are regular
   files, the latter executable.
2. The signature is valid on every slice: `SecStaticCodeCheckValidityWithErrors` with `kSecCSCheckAllArchitectures |
   kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSRestrictSymlinks | kSecCSRestrictSidebandData |
   kSecCSRestrictToAppLike`, no requirement (measured: a resource fork or a changed resource or
   executable fails it).
3. Every slice satisfies the pinned requirement (`kSecCSCheckAllArchitectures` on every requirement check,
   3 to 6: by default Security checks only this Mac's slice), without `notarized`:
   `anchor apple generic and identifier "me.saffer.sill.mac" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "9B2KKVM937"`
   (Apple's anchor, the Developer ID intermediate, a Developer ID Application leaf, the team, the
   identifier: exactly Sill's own designated requirement, read from v0.6.1 with `codesign -d -r-`). The
   team, not one certificate, so a renewed Developer ID certificate (due before 2027-02-01) keeps working.
4. It satisfies `notarized`. Which API and why: the Gatekeeper assessment API (SecAssessment) is no
   longer in the macOS 27 SDK's headers, and `spctl` would mean a subprocess, output parsing, and an
   answer that follows the person's Gatekeeper settings (with Gatekeeper turned off it accepts
   anything). The requirement keyword `notarized` is compiled by Security (`csreq`), evaluated in
   process with the rest, independent of those settings, and offline with a stapled ticket; it is not
   in Apple's 2016 requirement-language page, so it was measured (2026-11-11): v0.6.1 satisfies it with
   the network allowed and with `kSecCSNoNetworkAccess`; Calculator.app (validly Apple-signed) and
   Xcode.app (App Store) do not; an ad hoc copy does not. Backed by 5, and by Gatekeeper's own check of a
   notarized app at its first launch.
5. A stapled ticket is present (`kSecCodeInfoStapledNotarizationTicket`, `kSecCSContentInformation`):
   every release is stapled (release.sh checks it), and it makes 4 independent of the network. (Its
   presence alone proves nothing: an ad hoc re-signed copy keeps the ticket file; 4 checks it. A copy
   with the ticket removed still satisfies 4 once macOS has seen the ticket, measured: 5 catches it.)
6. It satisfies this running app's own designated requirement (T17).
7. Signing information: identifier me.saffer.sill.mac, team 9B2KKVM937, the hardened runtime flag
   (0x10000), the three entitlements, no get-task-allow.
8. Info.plist (`kSecCodeInfoPList`): CFBundleIdentifier me.saffer.sill.mac, CFBundleExecutable Sill,
   CFBundleShortVersionString strict, newer than running and the manifest's version; CFBundleVersion
   digits and the manifest's build; LSMinimumSystemVersion ≤ this macOS.
9. The executable has a slice for this Mac's architecture.
10. Every slice's cdhash (`kSecCodeInfoUnique` of each architecture's static code) is the manifest's: the
    code Noah signed for, and nothing else.

### 4.6 The state machine

Phases: `idle`, `confirming(devices)`, `fetching`, `downloading(received, total)`, `unpacking`,
`checking`, `ready(devices)`, `installing`, `restarting`, `failed(Failure)`. Events: `updateNow(devices)`,
`confirm`, `cancel`, `fetched`, `progress`, `downloaded`, `unpacked`, `checked(devices)`, `installed`,
`launched`. `next(state, event) -> (state, [Effect])` with effects `fetch`, `download`, `unpack`, `check`,
`install`, `launch`, `quit`, `cleanUp`. Update Now is taken only in `idle` and `failed`; Cancel only
before `installing`; after `installing` nothing but the launch's result moves it. The devices the person
agreed to disconnect are kept (`consented`); after the check, a device not among them asks again. A
failure that left the old copy out of place (not put back) never cleans up: the staging folder holds it.

### 4.7 Words

Settings › General's update section keeps its line, switch and Check Now. With Update Now: its button
(disabled with the refusal's line under it when one holds) and Open Release Page…. During an update the
line says the step ("Getting Sill 0.6.2 from GitHub…", "Downloading Sill 0.6.2… 2.1 of 5.9 MB",
"Checking Sill 0.6.2…", "Installing Sill 0.6.2…", "Restarting Sill…") over a progress bar, with Cancel
until installing. A failure is the orange line ("Couldn’t update: ‹why›. Sill 0.6.1 is unchanged.") with
Try Again and Open Release Page…. The status menu's item: "Sill 0.6.2 Is Available…" with "You have
0.6.1; update it in Settings" opens Settings › General when Update Now is offered and not refused (Q4),
the release page otherwise (as today, "You have 0.6.1; opens its download page"); during an update,
"Updating to Sill 0.6.2…" with the step, opening Settings. VoiceOver hears each step, the question and
the result. The footnote, while Update Now shows: "… Sill never downloads or installs anything by itself.
Update Now downloads the new version from GitHub, checks that it is Sill, signed by its developer and
notarized by Apple, puts it in place of this copy and restarts Sill; Open Release Page… shows it on GitHub
instead."

### 4.8 The update key: where it lives, the release step, rotation and loss

- **Made once, on Noah's Mac:** `Scripts/sign-update.sh --new-key` makes an Ed25519 key with CryptoKit
  and keeps it in his **login keychain** (a generic password: service `me.saffer.sill.update-signing`,
  account `ed25519`, label "Sill update signing key", not synchronizable) and prints its public key and
  key ID; that public key goes into `UpdateManifest.releaseKeys` (one line, a commit of its own). Then
  one copy of the private key off the Mac, for loss: a 1Password item (or paper in a safe), never a file
  in the repository, the handoff folder or ~/Downloads, never GitHub, never CI. Why the keychain and not
  a file under ~/Downloads/sill-keys/: ~/Downloads is where every agent and tool works (worktrees, the
  handoff folder, scratch): a plaintext file there can be read by any process of his account without a
  prompt and swept into a zip, a backup or a commit by mistake; the keychain keeps it encrypted at rest
  and asks before giving it to a program, so each signing is a deliberate click. A file is still
  possible (`--key-file`, a new file of mode 0600; best on an encrypted disk image mounted only for
  signing). Nothing here made a key: the harness and the checks make throwaway ones in memory.
- **The signer, once per reviewed change to it:** `Scripts/sign-update.sh --install-signer` lists the five
  files the signer is built from (UpdateManifest, UpdateInstallPolicy, UpdateArchive, StreamProtocol's
  Compatibility.swift and `Scripts/update-manifest.swift`) with their SHA-256 and the commit, asks whether
  he has read them, and builds it into `~/Library/Application Support/Sill Update Signer/` (0700) with its
  own SHA-256 beside it. Signing runs that binary only, after checking it is unchanged, never one built
  from the checkout of the day: a commit on main that changes those files does not reach the key until he
  installs the signer again. The keychain item trusts the binary that made it (a later signer asks once),
  so the signer itself asks Noah in person before every signature with the keychain's key (Touch ID or his
  password; the prompt says "sign Sill v0.6.2 for Update Now: Sill.zip, ‹size› bytes, SHA-256
  ‹its first 16 hex digits›"). A key in a file (tests, the rehearsal) has no prompt.
- **The release step:** right after a release is published, on his Mac: `Scripts/sign-update.sh v0.6.2`.
  It first needs the zip he knows: `.build/Sill-0.6.2.zip` from his own `release.sh` run (the default,
  `--zip` for another path), or `--expect-sha256` with the SHA-256 that a release workflow run he approved
  printed; GitHub's `Sill.zip` must be that, byte for byte, or nothing is signed. Then it reads the published
  release (published, not a prerelease, Sill.zip and Sill.zip.sha256 uploaded), downloads the zip into
  `.build/update-sign`, checks it as the checklist checks a download (its SHA-256 against the `.sha256` file
  and GitHub's digest; exactly one Sill.app; `codesign --verify --strict --deep` with the pinned requirement
  and `notarized`; `stapler validate`; spctl's "Notarized Developer ID"; the version is the tag's), reads
  each slice's cdhash with codesign (the same value as Update Now's Security reading, checked by the
  harness on v0.6.1's both slices), signs the manifest with the installed signer (Touch ID or his password,
  the prompt naming the tag, the size and the start of the SHA-256, which he compares with what release.sh
  printed), reads it back with the key the tag's app carries, shows it, asks, uploads
  `Sill.zip.manifest`, and downloads it again to compare. Until he does, Update Now does not show for that
  release (T29).
- **Rotation (planned):** release N carries both keys in `releaseKeys` and is signed with the old one (the
  Sills before N know only it); from N + 1 on, sign with the new one (N knows both); N + 2 may drop the old.
- **Lost:** no new manifest can be made that any Sill in the field accepts. Releases then go out unsigned
  (Open Release Page… as today), and one release carries a new key, installed by hand once (its notes
  say so); from it on, Update Now works again.
- **Leaked:** rotate as for a loss, and say in the release notes that people should update by hand once.
  The leaked key alone installs nothing (T4: a Developer ID signed, notarized build is still needed).

## 5. The mechanism (`Sources/SillMenuBar/UpdateInstaller.swift`)

Foundation, Security, CryptoKit, IOKit and Darwin; no AppKit; compiled on its own with swiftc by the
harness. Every step returns a `Result` with a Failure; nothing throws past it.

- `prepare`: one GET of the latest release (1 MB, 30 s, the API's redirect rule), `releaseToInstall`,
  one GET of the manifest (its size exactly, the download redirect rule), `UpdateManifest.verify` with the
  trust's keys, `manifestMatches`. Nothing written.
- `makeStaging(for installed:)`: the item-replacement directory, its `st_dev` equal to the installed
  bundle's parent's, mode 0700, this user's, empty.
- `download`: a delegate-based data task writing to a file it created with `O_EXCL | O_NOFOLLOW`,
  hashing as it goes, stopping at the manifest's size + 1, Content-Length checked, the redirect rule,
  cancellable; timeouts 30 s between bytes, 10 minutes in all.
- `unpack`: the file read back and hashed again, `UpdateArchive.read`, the space checked, the listing
  written under directory descriptors (each file's size and CRC checked, its mode set, flushed), links
  last, the zip deleted.
- `facts` and `check`: §4.5's facts, the verdict, the cdhashes.
- `install(staged, installed, runningCDHash, expected, …)`: lstat the installed path (a folder, not a
  link), its cdhash equal to the running process's, then `renamex_np(staged, installed, RENAME_SWAP)`,
  then `check` at the installed path with the same code expected; on failure the swap is undone.
- `putBack`: the same exchange again (the old copy back at its path, the new one in staging).
- `noteLeftover`, `removeLeftover(noted:for:)`: the folder holding the replaced copy, noted after the
  swap and removed by the next Sill once its host is up, only while it is still a staging folder that may
  go (`isLeftover`). `cleanUpStaging(for installed:)` does the same by listing the item-replacement folder,
  a best effort: macOS denies the listing to most processes (T20). `setAside`: a folder holding an old copy
  not put back, renamed out of both.
- `situation`, `runningCode`, `runningIsInstalled`, `process(_:satisfies:)`: the facts of §4.1 and T10.

AppUpdater (`Sources/SillMenuBar/AppUpdater.swift`, main actor, @Observable) gathers the facts for
§4.1, runs the effects (each answer tagged with its attempt), the relaunch (NSWorkspace,
NSRunningApplication, the running code's check), the quit (a run-loop Timer), and at launch the wait for
another instance (`waitForOtherSill`, called by AppDelegate) and, after the host has started, the
clean-up.

## 6. Files

New: `UpdateInstallPolicy.swift`, `UpdateManifest.swift`, `UpdateArchive.swift`, `UpdateInstaller.swift`,
`AppUpdater.swift` (Sources/SillMenuBar); `Scripts/sign-update.sh` and `Scripts/update-manifest.swift`
(the release step); `Tests/checks/update-install/` (main.swift, build.sh, run.sh, mutants.py);
`Tests/update-harness/` (main.swift, server.py, make-zip.py, run.sh; local only, not CI). Changed:
`UpdatePolicy.swift` and `UpdateChecker.swift` (the release's signed flag, `updateLatestSigned`),
`AppModel.swift` (owns `updater`), `AppDelegate.swift` (the wait at launch), `SettingsPanes.swift`
(UpdatesSection), `StatusItemController.swift` (the item), `DebugHooks.swift` (previews of the new
states), `Tests/checks/update-policy` (the flag), `site/privacy.html` (one marked paragraph),
`docs/release-checklist.md` (T24, §4.8), `docs/DEVELOPMENT.md`, `CLAUDE.md`, `Tests/checks/README.md`,
`.github/workflows/ci.yml` (the mutants matrix).

## 7. Privacy

Update Now sends GitHub (api.github.com once, github.com twice: the manifest and the zip, and
release-assets.githubusercontent.com for each) what the check sends: the Mac's IP address, `User-Agent:
Sill/‹version›`, `Accept-Language: en`; no identifier, cookie or credential. macOS may check the new
version's signature and notarization with Apple, as it does for any app. The privacy page's Update check
section gains one paragraph between `<!-- Update Now: …` and `<!-- /Update Now -->` (docs/release-
checklist.md part 1 §3's marker rule).

## 8. Compatibility rules for later versions (part of this feature's contract)

- Every later Sill keeps the wait at launch (§5) and finishes launching within 30 s while another Sill
  runs: the version that updates to it launches it beside itself and waits for that.
- Every release keeps T24's shape and, for Update Now, its manifest. The manifest's first line, "Sill
  update 1", names its format; a later format gets another number and is published beside, never instead
  of, a "1" while Sills that read only "1" are in use.
- A change to the pinned requirement (a new team, a new identifier) or a new update key ships first in a
  version updated by hand (or, for a key, by rotation, §4.8); the updater never takes a requirement or a
  key from the download.

## 9. What must never be possible, and what enforces it

| Never | Enforced by |
|---|---|
| Installing a build Noah did not sign for with his update key | the manifest's Ed25519 signature (§4.3), checked before the download; its SHA-256 and the code's cdhashes after |
| Installing code not signed by Developer ID team 9B2KKVM937 as me.saffer.sill.mac | §4.5 3, at staging and at the final path; T10's launch check |
| Installing code Apple did not notarize | §4.5 4 and 5 |
| A downgrade or the same version | §4.2, from the bundle's signed Info.plist and the signed manifest; the running version from this process's bundle |
| Downloading from a host off the allow-list | T5's redirect delegate, before the request is made |
| Writing outside the staging folder while unpacking | directory descriptors, `O_NOFOLLOW`, §4.4's rules |
| Running anything from the download before it passed | no execution, load or open before §4.5; the launch only after the final check |
| An argument, variable or default loosening any of it in Sill.app | immutable constants only; the update-install check's source rules |
| A privileged step | none exists: no prompt, helper, package or authorization call |
| Half an update | one atomic swap; put back on every later failure |

## 10. Open questions (each with the default this branch takes)

1. **How far to trust GitHub Actions (T4). Settled by Noah on 2026-11-12: the update key.** In his words,
   quoting the option: "Add an update key that only you hold... You sign each release with one command on
   your Mac after it publishes. The key never goes near GitHub. Sill installs an update only if it carries
   both Apple's signature and yours." Built here as §4.3 and §4.8; his steps are §14. Considered and not
   taken: (a) trusting the Developer ID signature and notarization alone (one commit on main would then be
   enough to install code everywhere with a click, the `nightly` environment having no reviewer); (c)
   taking the Developer ID identity out of the `nightly` environment (testers' nightlies would lose
   notarization, their keychain items and their grants with every build, and the `release` route would
   remain). (c) stays open as a hardening of its own.
2. **A device connected at the click.** Default: ask ("Updating restarts Sill and disconnects ‹iPad›."
   [Update and Disconnect] [Cancel]), and ask again before installing if one he did not agree to has
   connected meanwhile. Alternatives: wait until none is connected; never ask.
3. **Another account runs Sill from this copy.** Default: refuse (T13). What Noah sees, since his Mac has
   the second account running Sill most days: Settings › General shows Update Now dimmed and, under it,
   "Sill is open in another account on this Mac (‹that account's full name›). Quit it there first, then
   update."; the menu's item opens the release page, as today. What he does: switch to that account
   (fast user switching, or the Lock Screen's account list), choose Quit Sill from its menu, switch back
   (within a second Update Now is enabled: Settings looks again every second), and click Update Now. That
   account's Sill then starts the new version at its next login (its login item names the path) or when
   opened. Logging that account out does the same. In the second account itself, Update Now is dimmed
   with "Sill belongs to another account on this Mac (‹his full name›). Update it from that account."
   whenever his account installed or last updated Sill.app (it owns it then). Alternative: update anyway,
   and that account's Sill runs old code with new resources until it quits.
4. **The status menu's item.** Default: opens Settings › General when Update Now is offered and not
   refused, the release page otherwise. Alternatives: the release page always (as today); or the item
   starts the update.
5. **A nightly updating to a release.** Default: allowed (it is a notarized Developer ID Sill, and the
   release is signed with the update key).
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
12. **Where the update key lives.** Default: his login keychain with one offline copy (§4.8).
    Alternative: a file of mode 0600 (`--key-file`), best on an encrypted disk image.

## 11. Gates (what this branch verifies without touching Noah's Sill)

- G1 `Tests/checks/update-install`: every rule of §4 and its words, the manifest with throwaway keys,
  archives built in the check (every hostile kind of T8), the app's sources (T21); every mutant caught.
  `Tests/checks/update-policy`: the signed flag.
- G2 `Tests/update-harness/run.sh`: against scratch bundles in `.build` (ad hoc, a test identifier, the
  trust, endpoints and update key made by the harness only) and a stand-in for GitHub on 127.0.0.1: the
  positive path (a ditto zip with AppleDouble entries, a plain one, a redirect to the asset path, no
  GitHub digest, an NSBundle and a CFBundle held for the installed path across the swap as Bundle.main is
  in Sill.app), put back, and each hostile case refused for its reason with the installed copy's tree
  unchanged: a missing manifest, one by another key, one changed after signing, one of another tag, a
  digest that disagrees, a SHA-256 that disagrees, a lower and the same version, another release than
  offered, a 404; a redirect to another host, to another path, without end; a truncated download, a
  Content-Length too large, more bytes than signed, a 500; a name under ../, an absolute name, a link out
  written through, Info.plist and info.plist, a setuid executable, a file named UpdTest.app, a second
  top-level folder; another identifier, a resource and the executable changed after signing, a version
  not the manifest's, code the manifest doesn't name; a change between the check and the swap (caught
  after it, put back); a copy at the path that isn't the running one. The requests (Sill's User-Agent, no
  credential, no cookie, none to the refused hosts). The launch check against a running process. Where
  an app runs: writable, a process running from it, a folder made read-only, a link, no space, a disk
  image writable and read-only. Staging folders made, one set aside, the noted leftover removed and five
  forged notes refused. With the genuine v0.6.1 (downloaded
  read-only with `gh`): `Trust.release`'s every rule with the harness's key: 0.6.1 over 0.6.0 installed;
  the same version, a v0.6.2 tag, another team pinned, Apple's own requirement as the running one, a
  tampered, an ad hoc and an unstapled copy, a manifest naming other code: refused.
- G3 `swift build -c release`: only the known CaptureProbe warning.
- G4 `Tests/checks/run-all.sh`: all pass.
- G5 previews from the bare SillMenuBar binary (never the bundle) against main's: identical but for the
  new samples (pane-update-now-*, menu.txt's update-now-*): with no key, nothing else changes.
- G6 `Scripts/sign-update.sh` against a stand-in `gh` serving the genuine v0.6.1, with a throwaway key file
  and a signer installed in a scratch folder (`SILL_SIGNER_DIR`): every check, the manifest, the "upload"
  recorded and read back, nothing sent anywhere; refused for a zip that isn't the one known, a signer
  changed after installing, no signer.
- Not on this Mac: the real end to end (two notarized builds, a key and Noah's hands: §12). No built
  Sill.app is launched, /Applications/Sill.app is never touched, no key is made in his keychain.

## 12. Noah's end-to-end test (two notarized builds and a rehearsal key; nothing here does it)

The real path cannot be rehearsed with a release of Saffsanity/sill without offering it to everyone, so
the rehearsal uses a throwaway public repository, a throwaway key, and a scratch branch that changes only
constants. Builds made from it are never released.

Prepare (on his Mac, in a scratch clone whose pushes go nowhere, so no rehearsal tag can ever reach
Saffsanity/sill, where a pushed `v*` tag starts the release workflow: `git clone
https://github.com/Saffsanity/sill ~/Downloads/sill-rehearsal && cd ~/Downloads/sill-rehearsal && git
remote set-url --push origin DISABLED && git checkout -b update-rehearsal origin/one-click-update`, or
origin/main once this has merged):
1. A public repository `Saffsanity/sill-update-rehearsal` with a README (`gh repo create
   Saffsanity/sill-update-rehearsal --public --add-readme`: a release's tag needs a commit), no code.
2. The signer, once (§14, 1.1 and 1.2: read its five files, then `Scripts/sign-update.sh
   --install-signer`), and a rehearsal key in a file: `Scripts/sign-update.sh --new-key --key-file
   ~/Desktop/rehearsal.key` (prints the public key; never the real key, which stays in the keychain). Copy
   `Packaging/embedded.provisionprofile` from ~/Downloads/winstream into the clone (it is git-ignored, and
   without it a release build has no keychain group: the rehearsal's builds would lose the pairings and
   Update Now would refuse them). On `update-rehearsal`: that public key in `UpdateManifest.releaseKeys`;
   the rehearsal repository in `UpdatePolicy.feed` and in `UpdateInstallPolicy.Endpoints.github`'s two
   URLs (`git grep -n 'Saffsanity/sill/' -- 'Sources/SillMenuBar/Update*.swift'` finds the three lines);
   CFBundleShortVersionString 0.6.90 in Packaging/Info.plist; commit, and `git tag v0.6.90` (release.sh
   builds only a tagged commit; the tag stays in this clone). Then `SILL_SIGN_IDENTITY=…
   SILL_NOTARY_PROFILE=sill-notary SILL_UNIVERSAL=1 Scripts/release.sh` (no `--publish`): a notarized
   `.build/Sill-0.6.90.zip` — build A, kept.
3. Version 0.6.91 (commit, `git tag v0.6.91`), the same command: build B. Publish B as release `v0.6.91`
   of the rehearsal repository with `Sill.zip` and `Sill.zip.sha256` (`gh release create v0.6.91 --repo
   Saffsanity/sill-update-rehearsal …`), then `Scripts/sign-update.sh v0.6.91 --repo
   Saffsanity/sill-update-rehearsal --key-file ~/Desktop/rehearsal.key --expect-key ‹the public key›` (it
   compares the published zip with this clone's `.build/Sill-0.6.91.zip`).
4. Note what to come back to: `/Applications/Sill.app`'s version (Settings › General's footer); the way
   back is the real release from getsill.app/download.

Run:
5. Quit Sill. Unzip build A and drag it to /Applications, replacing Sill. Open it. Screen Recording and
   Accessibility stay allowed (same designated requirement), the iPad stays paired (same keychain group).
6. With the other account's Sill running: Settings › General shows Update Now dimmed with "Sill is open
   in another account on this Mac (…)". Quit it there (Q3), back: Update Now enabled within a second.
7. Settings › General › Check Now: "Sill 0.6.91 is available." with Update Now (the release is signed).
8. With the iPad connected, Update Now: the question with the iPad's name; Update and Disconnect.
9. Watch: "Getting…", the download's progress, "Checking…", "Installing…", "Restarting Sill…"; the menu
   bar icon goes and comes back within a few seconds; the iPad reconnects by itself.
10. Sill.log (Show Log…): "Update: getting Sill 0.6.91 …", "… manifest is signed with the update key …",
    "Update: downloading …", "Update: Sill 0.6.91 (…) checked: …", "Update: replaced /Applications/Sill.app
    …", "Update: Sill 0.6.91 started (pid …) …; quitting.", then from the new process "Another Sill is
    running …; waiting", "The other Sill quit; starting.", "Sill 0.6.91 (…) running from
    /Applications/Sill.app" and "Update: removed 1 folder an earlier update left (…)".
11. Settings › General's footer says 0.6.91; Screen Recording and Accessibility still allowed (no prompt),
    Launch at Login still on, the iPad connects without pairing again, and macOS showed no "downloaded
    from the Internet" or "App Management" prompt.
12. `codesign -dvvv /Applications/Sill.app` shows 0.6.91's CDHash (the manifest's arm64 line); `ls -la
    /Applications | grep Sill` shows his account as owner.
13. A release not yet signed: publish 0.6.92 without running sign-update.sh, Check Now: "Sill 0.6.92 is
    available." with Open Release Page… and no Update Now. Then sign it: Check Now again shows Update Now.
14. A failed launch: a build C (0.6.93) whose first line in AppDelegate's applicationDidFinishLaunching is
    `exit(1)`, released and signed in the rehearsal repository: Update Now, then "Sill 0.6.93 didn’t
    start, so Sill 0.6.92 is back." with 0.6.92 still running.
15. Refusals: drag build A out of the zip into ~/Downloads and open it there (translocated or not: the
    line says which); "This copy of Sill isn’t a notarized release…" from a development build; in the
    second account, its Sill opened with a newer signed release offered: "Sill belongs to another account
    on this Mac (‹your name›). Update it from that account." (the update left Sill.app owned by your
    account).

Back: quit Sill, install the real release from getsill.app/download, open it; delete the rehearsal
repository, the rehearsal key file and the clone (`~/Downloads/sill-rehearsal`, its tags with it). If
anything goes wrong in between: the old copy is in the folder
Sill.log names ("Sill’s previous copy is kept at /private/var/folders/…/NSIRD_Sill_…/Sill.app"); quit
Sill, Finder › Go › Go to Folder…, that folder, drag Sill.app to Applications, Replace.

The first real one: Noah makes the real key (§4.8), its public key ships in a release installed by hand
(the first with Update Now able to verify), and the release after it is the first real Update Now;
steps 7 to 12 again then.

## 12a. The review before the first build (2026-11-12, a subagent reading the code as written)

An Opus subagent read the plan and the code read-only, before anything was compiled, as a hostile reviewer.
Twelve findings; each was taken, and how:

1. **High: the signing step signed whatever GitHub served.** It checked only what T4's attacker can meet (a
   Developer ID signed, notarized zip of the right version) and signed. Fixed: `sign-update.sh` signs only a
   zip Noah knows without GitHub, his own `release.sh` output byte for byte (the default,
   `.build/Sill-<version>.zip`), or `--expect-sha256` with the SHA-256 a release run he approved printed;
   GitHub's `Sill.zip` must be it, or nothing is signed. G6 runs both refusals.
2. **High: the signer was rebuilt from the checkout at every signing, with the key in reach.** A commit
   changing any file it compiled would run with the key; the changing binary trained "Allow". Fixed: the
   signer is installed once (`--install-signer`) from five files Noah has read, outside the repository, its
   SHA-256 checked at every signing; the keychain item trusts the binary that made it; it compiles nothing of
   the app but the pure manifest files (no network code), and the shell reads the cdhashes with codesign
   (checked equal to Update Now's Security reading on v0.6.1's both slices).
3. **Medium: putting the old copy back moved whatever was in the staging folder into place.** Fixed:
   `putBack` swaps only when the staged folder's code is still the running code's (its cdhash); otherwise the
   checked new copy stays and the failure says so. The harness puts another bundle there and sees it refused.
4. **Medium: an update with another copy of Sill running from another path left no Sill running** (the new
   copy waits for every Sill with its bundle identifier). Fixed: every other Sill of this account, by bundle
   identifier wherever it runs from, refuses Update Now.
5. **Medium-low: Cancel did not retire its attempt, and stale answers wrote state before the attempt was
   checked.** Fixed: Cancel increments the attempt; every step's answer checks its attempt first, before it
   touches anything.
6. **Medium-low: the clean-up at start could delete a live staging folder, or the copy the person was told
   to keep.** Fixed: no clean-up while an update is under way; a staging folder holding a copy that could not
   be put back carries a marker file and is never deleted by Sill.
7. **Low: the requirement checks looked at this Mac's slice only.** Fixed: `kSecCSCheckAllArchitectures` on
   the pinned requirement, `notarized` and the running app's requirement.
8. **Low: other accounts and other copies were looked for only at the click, by a path string.** Fixed:
   processes match the executable by device and inode (or any file in the bundle by path), and the whole
   look is taken again right before the swap.
9. **Low: a linked folder above Sill.app could redirect the swap.** Fixed in part: a link anywhere on the
   path refuses. The exchange stays path-based (T12's residue, said there).
10. **Low: consent was matched by display name.** Fixed: devices are matched by their connection; two iPads
    of one name are two devices.
11. **Low: the update section could vanish mid-update when a later check changed the offer.** Fixed: the
    release clicked for is kept until the update ends, and the section follows it.
12. **Low: the entitlements were read without `kSecCSRequirementInformation`, and T27 claimed more than was
    measured.** Fixed: the flag is passed; T27 now says what was measured and what was not.

Its notes on the tests, also taken: the genuine install compared versions that were equal (now the tree and
the code); the 401 case was missing (added: no credential, ever); `c == expected` after the swap is implied
by the verdict against the same manifest and so cannot be told apart by a test (said here, not a mutant);
the source rules missed `Trust.init(` and CFPreferences (added); the mechanism had no mutants (eight now,
`Tests/update-harness/mutants.py`). It found no compile error with confidence; the first build found one
(BundleProblem had to conform to Error).

## 12b. The second review (2026-11-12, after the first build; a subagent reading the fixes)

An Opus subagent read the twelve fixes and the night's later changes read-only, as a hostile reviewer
(`git diff 17bb723..HEAD`). Six findings; each was checked here against the code and taken:

1. **Medium: a late Cancel stopped an update half done.** Cancel retired the attempt in any phase, and a
   Cancel arriving once installing had begun (a click on the button the next frame removes, an assistive
   technology's late action) dropped the install's answer: no launch, the phase busy for good, and a copy
   not put back never kept. Fixed: Cancel retires the attempt only in a phase that takes it.
2. **Medium: the signer signs whatever it is handed, and anything running as Noah can run it.** The checkout's
   `sign-update.sh` chooses what is signed, and the installed signer reads the keychain's key without a
   prompt, so a later commit's script (or any program running as him) could have it sign silently. Fixed:
   every signature with the keychain's key needs Noah in person (LocalAuthentication, Touch ID or his
   password), the prompt naming the tag, the size and the start of the SHA-256 to compare with what
   release.sh printed (T4, §14 3.3). Also: `--install-signer` copies the files first and shows and builds
   from the same copies, names `sign-update.sh` too (it chooses what is signed), and stops on a failed
   compile (a stale `update-manifest.new` could have been installed); `SILL_SIGNER_DIR` only with a key file.
3. **Low-medium: the put-back trusted a cdhash.** A cdhash is read from the executable's signature and says
   nothing of Info.plist, the resources or the other slice, so a staged old copy changed there was put back;
   and when the put-back was refused, the copy that had just failed its check stayed at Sill's path, and the
   person was pointed at the staged copy as the way back. Fixed: `isTheOldCopy` also validates everything
   sealed, on every slice, against the pinned signer; when no whole old copy can come back, the copy that
   failed its check is moved off the path (`moveAside`); only a whole old copy is kept and offered, else
   Settings says to download Sill again. The harness changes a resource of each copy and sees both.
4. **Low: device keys could repeat.** A connection's object identity is an address, reused once it is gone,
   so a device connecting during the download could pass for one the person agreed to. Fixed: the key is
   the connection's endpoint (a new connection has a new source port) with its identity.
5. **Low: the old copy was deleted also when the new Sill's host failed to start.** Fixed: only once the host
   is up (T20).
6. **Low: the note that keeps an old copy could fail on a full disk** (one way an update fails), and the next
   start would delete it. Fixed: the staging folder is renamed out of the clean-up's reach ("Sill previous
   copy ‹…›"; a rename needs no space), with the note when it can be written.

Its verdicts on the rest: fixes 4, 7, 8, 9, 11 and 12 hold, 5 and 6 with findings 1, 5 and 6, 10 with
finding 4; the owner refusal and the rounding hold; nothing in Sill.app lets an argument, a variable or a
default loosen the trust, the hosts or the version rule.

## 13. Progress

- 2026-11-11 22:40 EST: facts gathered (below), plan written and pushed (e7de2b3); the five decisions
  sent to the coordinator.
- 23:00: the coordinator (and Noah's recommendation to come): build the second factor now, the key list
  empty on the branch, the release step written, the alternatives and their costs kept (this version).
- 2026-11-12 00:09: an independent review of the code as written (read-only, a subagent): twelve findings,
  each taken: the signing step signed whatever GitHub served (now a zip Noah knows, by its SHA-256) and was
  rebuilt from the checkout with the key in reach (now a signer installed once); the put-back carried
  whatever was in staging into place (now only the running code); another copy of Sill from another path
  left no Sill running (now refused); Cancel did not retire its attempt; the clean-up could delete a live or
  a kept staging folder; requirements were checked on this Mac's slice only; processes matched by a path
  string (now by file identity, again right before the swap); a linked folder above Sill.app; consent by
  name (now by connection); the section could vanish mid-update; the entitlements' flag. Its notes on the
  tests too: the genuine install's assertion, a 401 case, stronger source rules.
- Disk under the 25 GB floor from 22:50 (12 to 22 GB free while other agents built): code and documents
  written without compiling until it is back.
- 00:12 to 00:33: compiled at last (the coordinator's floor of 20 GB, through heavy.sh). The first build
  found one error (BundleProblem had to conform to Error); the check's synthetic executable compressed past
  the ratio case's limit (made incompressible). update-install 474 checks, its 60 mutants all caught.
- 00:20: Noah's ruling on Q1 (the key; §10, §14); the review's twelve findings written up (§12a).
- 00:36: a refusal of its own for a Sill.app another account owns (it said "a folder this account can't
  change" when the folder could be changed): on Noah's two-account Mac the second account's case after
  every update from the first.
- 00:39, the harness's first run: the post-swap check is right to read through Security. With an NSBundle
  and a CFBundle held for the installed path across the swap (as Sill.app's Bundle.main is), both still
  said 1.0 after it, while Security's read said 1.1. It found one fault in the code and one in itself:
  the refusal's MiB rounding overflowed for Int64.max bytes and trapped (now
  `mebibytesRoundedUp`, which never adds; the check asks for Int64.max too); its hostile "UpdTest.app is
  a file" zip was under the release's 1 KB floor, so the size rule refused it first (now 4 KB).
- Measured for this plan: v0.6.1's zip (13 entries, stored and deflate, 8 with data descriptors, no
  AppleDouble, no links, 16.1 MB unpacked); its signature (Developer ID 9B2KKVM937, runtime, universal,
  stapled, the designated requirement in §4.5 3); the `notarized` keyword (§4.5 4); strict validation
  failing a resource fork and a changed resource or executable; a locally made ditto zip storing links
  uncompressed and AppleDouble entries beside files with attributes; GitHub's redirect host
  (release-assets.githubusercontent.com, path `/github-production-release-asset/1381093165/…`); the
  item-replacement directory on the data volume and an atomic swap with a folder in ~/Downloads;
  `proc_pidpath` reading uid 502's Sill; a folder moved to another parent needs write permission on
  itself; a mounted disk image's volume under AppleDiskImageDevice in the I/O Registry.

## 14. For Noah: the update key, step by step

Three things, at the Mac. The key list stays empty in the code until step 2's commit; nothing here made a key.

**1. Once: the signer, the key, its backup.**
1. Read the five files the signer is built from: `Scripts/update-manifest.swift`,
   `Sources/SillMenuBar/UpdateManifest.swift`, `UpdateInstallPolicy.swift`, `UpdateArchive.swift` and
   `Sources/StreamProtocol/Compatibility.swift` (the last three only for the version and the format's
   helpers). The signer is the only program that will ever hold the key.
2. `Scripts/sign-update.sh --install-signer`: it lists those files with their SHA-256 and the commit,
   asks whether you read them, and builds the signer into `~/Library/Application Support/Sill Update
   Signer/`. Every signing checks that binary is unchanged. After a change to those files, read it and run
   this again (the keychain then asks once before the new signer may use the key).
3. `Scripts/sign-update.sh --new-key`: makes the key and keeps it in your login keychain ("Sill update
   signing key", never synced), and prints the public key and its key ID. It refuses to make a second one.
4. Back it up once, off the Mac: `security find-generic-password -s me.saffer.sill.update-signing -a ed25519
   -w` shows the private key (the keychain asks); put it in a 1Password item (or on paper in a safe), and
   nowhere else: not a file in the repository, the handoff folder or Downloads, not GitHub, not CI.
5. What a lost key costs: no Sill already installed can accept another update through Update Now. Releases
   then go out unsigned (Update Now doesn't show; Open Release Page… as before) until one carrying a new
   public key is installed by hand once; its notes say so. A leaked key: the same, and the notes ask people
   to update by hand once; the leaked key alone installs nothing (a Developer ID signed, notarized build is
   still needed).

**2. Once: the public key into the app.**
1. Give the public key that step 1.3 printed (a line of base64; it is not a secret) to whoever makes the
   change, or make it yourself.
2. It goes into `Sources/SillMenuBar/UpdateManifest.swift`, `static let releaseKeys: [String] =
   ["‹the public key›"]`, in a commit of its own, reviewed, before the first release that carries the
   updater. `Tests/checks/update-install` checks every key there is usable.
3. That first release is installed by hand (the Sill before it has no key to check with): it is the first
   one whose Update Now works, and the release after it is the first Update Now installs.

**3. Every release: sign it after it is published.**
1. Publish as today (part 2 of docs/release-checklist.md).
2. On your Mac, from the release's tag: `Scripts/sign-update.sh v0.6.2`. If you built and published it here
   (`release.sh --publish`), that is all: it compares GitHub's `Sill.zip` with `.build/Sill-0.6.2.zip`. If
   the release workflow built it in a run you approved, add `--expect-sha256 ‹the SHA-256 that run's log
   printed for Sill.zip›`. A release you did not build here or approve has neither, and is refused: that is
   the point.
3. It checks the zip (the checklist's download checks). Then Touch ID (or your password) asks you to allow
   "sign Sill v0.6.2 for Update Now: Sill.zip, ‹size› bytes, SHA-256 ‹16 hex digits›": compare those
   digits with the start of the SHA-256 `release.sh` printed for Sill.zip (or the approved run's), and
   allow only when they match. Any other time this prompt appears (when you didn't just run
   sign-update.sh), cancel it: something is trying to use your key. Then it shows the manifest, asks
   "Upload Sill.zip.manifest to v0.6.2 in Saffsanity/sill?", and on yes uploads it and reads it back. When it
   worked, the last line is "Uploaded and read back: v0.6.2 is signed for Update Now." and the release lists
   `Sill.zip.manifest`.
4. Until you sign a release, Sill shows it as before Update Now: "Sill 0.6.2 is available." with Open
   Release Page… and no Update Now (every Sill's check notes whether the release lists the manifest). A Sill
   that checked before you signed shows Update Now after its next daily check, or at Check Now. Someone who
   clicked Update Now in between is told "Sill 0.6.2 isn’t ready for Update Now yet. Try again later, or
   open its release page." and nothing is downloaded.
