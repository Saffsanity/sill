# One-click update for Sill for Mac — the plan

Noah, 2026-11-11: "make a note that I want to make the Sill update checker also have a 1 click updater
as a new feature", and the same evening: "Start working on ... one-click updater ... Use subagents."
Branch `one-click-update` from main at dd6ea6a (0.6.1 released that day, plus #339), main at 936d627 (#349)
and 57a6d86 (#351) merged in; draft pull request #354.

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
versions only, so a nightly 0.6.2 (1400) sees no release until 0.6.3 is out: known, unchanged, and kept by
§16.3; with "Use nightly builds" on, it gets the next nightly).

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
Mac, byte for byte, or the zip a release workflow run he approved kept, taken with `--run` only when
GitHub's own record of that run names his tag's commit: the third security pass's R1′), so a build CI
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

**T11. A replaced helper, a stale temporary folder.** One helper, since review 3: the watcher (§15.5),
`/bin/sh` running a script compiled into Sill (`UpdateInstaller.watcherScript`), every path and value an
argument and never part of its text, started by the old Sill just before it quits. No updater binary, no
ditto. The programs involved are Sill itself, LaunchServices starting the new Sill, and the watcher with
the system tools it calls by full path (`ps`, `kill`, `codesign`, `mv`, `open`). The
staging folder is new for each attempt (`FileManager.url(for: .itemReplacementDirectory, in:
.userDomainMask, appropriateFor: Sill.app)`: a random name in this user's temporary folder, 0700, on
Sill.app's volume); nothing in a leftover one is ever read or reused; the one an update leaves is deleted
once the next Sill's host has started (T20).

**T12. Another process of the same user.** Malware already running as this user can rewrite what this
user owns; the updater cannot stop that and does not try. What it must not do is lend it Sill's own
right to change Sill.app: since macOS 13, App Management keeps apps of other teams from modifying a
signed app, while Sill (team 9B2KKVM937) may modify itself (NSUpdateSecurityPolicy's default: apps of the
same Team ID may). The updater runs only Sill's own code, checks the staged copy again right before the
swap (review 3, F5: a process of this user that changed it in the staging folder after the first check is
caught there, before Sill's right to change Sill.app moves it) and at the final path, pins the code through
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
here depends on it. The second security pass (R3): the leftover note is written before the last check, so its
appearance no longer marks the end of that check; but a process of this user that changes the staged copy
between the last check and the swap and then stops Sill with SIGKILL before the check after the swap has
finished leaves its changed copy at Sill's path, unchecked after the swap. That copy then runs as Sill once
it is opened; macOS still checks its signature, so a changed executable doesn't run, and changed resources
can't add a TCC grant or the keychain group it doesn't already have (the reviewer's reading).

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

**T20. The relaunch.** The one helper left behind is the watcher (§15.5): if the new Sill doesn't run for
`provedAfter` (30 s) with its host up within `watchWait` (150 s), it puts the old copy back and starts it.
The old Sill launches the new
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
notes asking people to update by hand once. A leaked key cannot be revoked (review 3, N1): every Sill not
updated by hand keeps trusting it. What limits the damage: the attacker still needs Apple's signature and
notarization for Sill's team (T4); the automatic update installs a release only two days after this Mac
first read its verified manifest (never counted from the manifest's own signed line, which whoever holds the
key writes: the second security pass's A1) and asks GitHub again right before it installs, so a release Noah
pulls within two days of its appearance installs nowhere by itself (§15.4; two days on GitHub's clock too, from
the release's latest publication: the third security pass's CL1 and AU1); the signing record and
`sign-update.sh --audit` (drafts and pre-releases included) are how he notices one he didn't sign (his choice to
run it every few hours), against a key that leaked off his Mac, not against someone in control of it; and a stop
signed with a key the Sills know (`Sill.zip.stop`, §15.4) names a release none installs, also by Update Now.
What none of this covers: Update Now (the person installs at once), and a leaked key's release that nobody
notices within those two days. A key compiled in that is not a usable Ed25519 public key
(wrong length, not decodable, or one of the points of small order, for which a signature can be forged
for some messages) makes every manifest fail: `UpdateManifest.usableKey`, checked for every compiled key.

**T29. A release not signed yet (added).** The check stores whether the release lists `Sill.zip.manifest`
(`updateLatestSigned`); without it Update Now does not show and the release page is the way, as today.
If someone clicks in the moment between the check and Noah's signing, the release is read again at the
click and the answer is "Sill 0.6.2 isn’t signed with Sill’s update key yet, so it can’t be installed from
here. Try again later, or open its release page." — nothing downloaded.

**T30. Automatically update Sill: nobody is there (added in round 3, §15).** With the switch on, the two
proofs are the whole gate, and a release that passes them installs on every such Mac within a day. So F1, F2
and F3 were fixed first (§12c); a release installs by itself only two days after this Mac first read its
verified manifest (the second security pass's A1: not the manifest's own signed line, which whoever holds the
key writes) and only while GitHub still lists it, unchanged and not stopped, right before the swap; a release
signed long ago, dated in the future, or below a version whose app passed both checks here never installs by
itself (F7, A2). Update Now is unchanged: the person sees the version and clicks.

**T31. Who turns it on (added).** Only Settings › General's switch. The switch and what the update remembers
live in one item of Sill's keychain group (data-protection keychain, this device only, never synced): no
process without Sill's signature and group can read, add or change it, so `defaults write`, a launch
argument, the CLI and a device's settings change (kind 17, `DeviceSettings`) have no path to it, and nothing
of this user can plant an item for Sill to find. A process with Accessibility can click the switch, as it can
click Update Now. `updateCheck` (the daily check's switch) is a default: turning it off stops automatic
updates, a denial and nothing more.

**T32. The moment (added).** "No device connected" is decided on the host's own queue, in the same step that
holds new sessions (`StreamServer.holdNewSessions`): between the last look and the quit no session can be
registered (each one that tries is told Sill is restarting and reconnects by itself), so none is cut off.
A paired device that connects and leaves can delay an update or let it begin, which changes nothing it
installs. Update Now's install holds the same way, and asks about a device that joined since its question.

**T33. A copy that waits, and loops (added).** A checked copy waits in this user's temporary folder for its
moment, up to a day: anything of this user can change it there, so the whole check runs again right before the
swap (T12, F5), and it never outlives the launch. Attempts are bounded (two a version, a day apart), a
refusal is looked at before any download, and every attempt's staging folder goes with it (§15.3).

**T34. The watcher (added).** The one helper (T11): `/bin/sh` with a fixed script, its values as arguments,
started by the old Sill. It stops only the process the old Sill started (and only while that process runs
Sill's executable from Sill's path), and puts back only the old copy, valid, of the pinned requirement and
the cdhash that ran, and checks the copy at Sill's path again after its moves before it starts it (the second
security pass's W1). A process of this user can make the started note (no put-back) or stop the new Sill
early (a put-back of the previous genuine version): neither installs anything new; a link or a FIFO planted
where it writes or looks holds nothing up and is never written through (W1, W2). Its renames in
/Applications run as this user, responsible to the old Sill for App Management (not measured: Noah's step
A6).

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
`checking`, `ready(devices)`, `waiting`, `installing`, `restarting`, `failed(Failure)`; the state also
carries its `mode`, `manual` (Update Now) or `automatic` (§15.2). Events: `updateNow(devices)`,
`automatic`, `postponed`, `quiet(Failure?)`, `confirm`, `cancel`, `fetched`, `progress`, `downloaded`,
`unpacked`, `checked(devices)`, `installed`, `launched`. `next(state, event) -> (state, [Effect])` with effects `fetch`, `download`, `unpack`, `check`,
`install`, `launch`, `quit`, `cleanUp`. Update Now is taken only in `idle` and `failed`; Cancel only
before `installing`; after `installing` nothing but the launch's result moves it. The devices the person
agreed to disconnect are kept (`consented`); after the check, a device not among them asks again. A
failure that left the old copy out of place (not put back) never cleans up: the staging folder holds it.

### 4.7 Words

Settings › General's update section keeps its line, switch and Check Now. With Update Now: its button
(disabled with the refusal's line under it when one holds) and Open Release Page…. During an update the
line says the step ("Getting Sill 0.6.2 from GitHub…", "Downloading Sill 0.6.2…" with "2.1 of 5.9 MB" on
a line of its own under it (Noah, 2026-11-12), "Checking Sill 0.6.2…", "Installing Sill 0.6.2…",
"Restarting Sill…") over a progress bar, with Cancel
until installing. A failure is the orange line ("Couldn’t update: ‹why›. Sill 0.6.1 is unchanged.") with
Try Again and Open Release Page…. The status menu's item: "Sill 0.6.2 Is Available…" with "You have
0.6.1; update it in Settings" opens Settings › General when Update Now is offered and not refused (Q4),
the release page otherwise (as today, "You have 0.6.1; opens its download page"); during an update,
"Updating to Sill 0.6.2…" with the step, opening Settings. VoiceOver hears each step, the question and
the result. The footnote names both checks wherever Update Now exists (Noah, 2026-11-12: "Add the update key
language when applicable as well"), and a build with no update key keeps the check's own footnote, which
claims no check it can't make; every line that names a check names the one that failed (§15.7 lists them).

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
  `--zip` for another path), or `--run <ID>` for a release workflow run he approved: GitHub's record of that
  run (`gh api repos/…/actions/runs/<ID>`: release.yml, finished, successful, for this tag) must name his
  tag's commit as the one it built (`head_sha`), and the zip is the one that run kept as its artifact
  `sill-zip-v0.6.2` (the third security pass's R1′: the app's `SillCommit` is its own build's word); GitHub's
  `Sill.zip` must be that, byte for byte, or nothing is signed. It refuses a nightly build (`SillChannel`,
  N10 e). Then it reads the published
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
- Every later Sill.app, with Update Now or without, answers the watcher (§15.5): once its host has been up
  `provedAfter` (30 s), or when it is quit, it makes the started note, a regular file named
  "Update Now started ‹token›.txt" in Sill's Caches folder (`me.saffer.sill.mac`), ‹token› the pending note's
  first line, a UUID's text (`AppUpdater.afterHostUp`, `willQuit`). The watcher only looks whether that regular
  file is there (the second security pass's W2: never opened). A later Sill that didn't would be put back by
  the watcher of the version that updated to it, 150 s after its launch.
- Every later Sill reads the restored note as this one writes it: the token, why, and, when the copy the
  watcher put back failed its last check, a third line: `kept` when the new copy stayed, whole (the third
  security pass's W3), `lost` when no whole copy could be left at Sill's path (the fourth pass's W4). A Sill that
  finds `kept` and the pending note naming its own version says it stayed (`.keptUnstarted`), one that finds
  `lost` says the update didn't finish (`.noWholeSillLeft`), never that the old one is back.
- The manifest's signed date (`signed …Z`) and a stop (`Sill stop 1`) are part of format "1" from this
  version on: no Sill.app with an update key ever shipped before them.
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
| Automatically update Sill turned on by anything but Settings › General | the switch in Sill's keychain group only, set only by `setAutomaticUpdate` from `SettingsPanes`; the update-install check's source rules (T31) |
| An automatic install over a connected device, or a device cut off by Update Now's restart | the hold and the count in one step on the host's queue (T32); Update Now asks about a device that joined |
| An automatic install of a release this Mac first read less than two days ago (however its manifest is dated), signed long ago or in the future, below one whose app passed both checks here, or stopped | `UpdateAutoPolicy.start`, `dates` and the first sights kept in the keychain item (§12d, A1), the stop read before the download, GitHub asked again before the swap (T30) |
| An automatic retry loop, or a memory grown until it reads as nothing | two attempts a version, a day apart, counted only on a verified release, remembered in the keychain item, kept small (`bounded`), and an unreadable item never read as nothing (§15.3, §12d A3) |
| A nightly offered or installed without "Use nightly builds" on, or offered on GitHub's unsigned word | the switch only from Settings; the offer only from a manifest verified with the nightly key (`readNightly`; the title never read) (§16.2, T37) |
| A nightly key satisfying a release, or the update key a nightly | another first line ("Sill nightly 1"), another key list, a key in both lists trusted for neither nightly (`UpdateManifest.verify`'s channel, `Trust.release`) (T35, T36) |
| A broken new version left in place with nobody there | the watcher puts the old copy back and starts it (T34) |

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
   line; only for a genuine Sill (one that satisfies Sill's requirement: review 3, N7). Before this change two Sills ran side by side (two hosts, two status items).
8. **Revocation.** Default: macOS's default network behaviour (T27). Alternative: enforce it.
9. **The old copy.** Default: kept in the staging folder until the new Sill has run 30 s with its host up
   (the watcher's word, §15.5), then deleted. Alternatives: to the Trash; kept until the next launch.
10. **Quarantine on the new copy.** Default: none (the update is checked by Sill; macOS checks a
    notarized app's integrity at first launch anyway). With it, the first launch would show "Sill is an
    app downloaded from the Internet" after a one-click update.
11. **Cancel during the download.** Default: yes, until installing begins.
12. **Where the update key lives.** Default: his login keychain with one offline copy (§4.8).
    Alternative: a file of mode 0600 (`--key-file`), best on an encrypted disk image.

Automatically update Sill (§15). Noah decided five points on 2026-11-12 (§15.1); these are what he was
not asked, each with the default taken:

13. **The cooling-off. Decided by Noah on 2026-11-12: "48 hour wait seems ok".** 48 hours before Sill
    installs a release by itself, counted (since the second security pass's A1) from when that Sill first
    read the release's verified manifest, never before its signed time (Update Now at once; §15.1, §15.4).
    Cost per release: none for Noah; automatic installs come two to three days after he publishes.
14. **A signed stop.** Default: built and read (`Sill.zip.stop`, §15.4). Cost per release: none until used;
    using it, one signature in person and one upload. Alternative: none (pulling the release within the
    cooling-off already stops the automatic update everywhere, as each Sill asks GitHub again before its
    swap): `stopName = nil`.
15. **The wait with no device connected. Decided by Noah on 2026-11-12: "can the 10 minute wait be
    shortened to 5 minutes?"** 5 minutes (any device restarts it; still far longer than every reconnect Sill
    makes by itself, §15.2).
16. **How many retries.** Default: two attempts a version, at least 20 hours apart (a daily check each), then
    Update Now only. Alternatives: three; one.
17. **The oldest release installed by itself.** Default: one signed within 120 days and not below the
    highest version whose signed release this Sill has read. Alternative: no age limit.
18. **The watcher.** Default: the new Sill must run 30 s with its host up within 150 s, else the old copy is
    put back and started, for Update Now too. Alternatives: only for the automatic update; longer times.
19. **GitHub asked again right before the automatic swap.** Default: yes (one request and the manifest; a
    failure that says nothing about the release waits for the next look). Alternative: no.
20. **A device that tries to connect while Sill installs.** Default: told that Sill is restarting, and it
    reconnects by itself. Alternative: refused without a word (it would show "disconnected").
21. **Where the switch lives.** Default: Sill's keychain group with what it remembers, never its defaults
    (only Settings can turn it on). Alternative: UserDefaults, as the daily check's switch (then `defaults
    write` would turn it on).
22. **A copy that finds no quiet moment.** Default: dropped after a day (no attempt spent; a later check
    downloads it again, about 6 MB). Alternative: kept until the next launch.
23. **Check Now and the automatic update.** Default: any check GitHub answers may begin it, Check Now's
    too. Alternative: the daily check alone.

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
  tampered, an ad hoc and an unstapled copy, a manifest naming other code: refused. A nightly feed (§16): a
  nightly offered from its verified manifest and installed through the same steps; refused: one signed with the
  update key, a release-format manifest, a release signed with the nightly key, a half-published pair, an
  older nightly, one moved on since the offer; nothing offered for one not signed yet or no pre-release.
  The third security pass (§12e): GitHub's clock and `published_at` read from the stand-in's answers (a
  `Date` word for word, none, one that isn't a date); a stop naming the release's version in another form;
  the watcher keeping the new copy at Sill's path when the put-back copy fails its last check, and refusing
  an old copy with a file of two names. The fourth (§12f): the release `id` read, and none; the watcher's
  put-back of the new copy only when it is whole (a changed one stays parked) and its `kept` only when the
  path checks whole after the move (else `lost`).
- G3 `swift build -c release`: only the known CaptureProbe warning.
- G4 `Tests/checks/run-all.sh`: all pass.
- G5 previews from the bare SillMenuBar binary (never the bundle) against main's: identical but for the
  new samples (pane-update-now-*, menu.txt's update-now-*): with no key, nothing else changes.
- G6 `Scripts/sign-update.sh` against a stand-in `gh` serving the genuine v0.6.1, with a throwaway key file
  and a signer installed in a scratch folder (`SILL_SIGNER_DIR`): every check, the manifest, the "upload"
  recorded and read back, nothing sent anywhere; refused for a zip that isn't the one known, a signer
  changed after installing, no signer. The nightly key (§16): made only in a file, never verifying a release
  or verified by the update key; `Scripts/sign-nightly.sh` signing a nightly of its commit and refusing a
  release's app, another commit's and a key the commit's Sill doesn't carry; `--new-key` leaving nothing behind.
  The third security pass (§12e): `--run` (GitHub's record of the run against the tag's commit, the run's
  artifact) and its seven refusals; the audit naming a release outside the record as a draft, a pre-release
  and published, each with a notification, and notifying when `gh` can't list; `--yes` never answering the
  updater's question; a nightly never signed as a release; `SILL_SIGN_TEST_BUILT_FROM` only with the tests'
  key. The fourth (§12f): `--run`'s event and head repository; the audit naming a `Sill.zip` outside the record
  behind a renamed manifest, a recorded release GitHub doesn't list, an empty listing, a login without push
  rights, a manifest over 4 KiB (never downloaded); `--pulled`.
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
   `.build/Sill-<version>.zip`), or `--expect-sha256` with the SHA-256 a release run he approved printed
   (since the third security pass, `--run` with that run's number in its place: §12e, R1′);
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

## 12c. The security review (review 3, 2026-11-12: an independent subagent, read-only, on 38385a7)

`~/Downloads/sill-handoff/one-click-update/SECURITY-REVIEW.md` has every finding, its proof and the
reviewer's fixes. Each was verified here first; what was done, and the check that fails without it:

| | Finding | Done | Check that fails without it |
|---|---|---|---|
| F1 | HIGH. Any process of Noah's could drive the installed signer silently (DYLD_INSERT_LIBRARIES into an unhardened binary). | The signer is built with the hardened runtime (`codesign -o runtime`); `sign-update.sh` refuses a signer without it; every signature still asks in person (Touch ID or the password). | `sign-test.sh`: a signer without the runtime refused; measured: a marker library loads into the unhardened signer, not into the hardened one. |
| F2 | HIGH. Noah's signature did not pin which keys the release trusts. | `--install-signer` records the trust anchors (the `releaseKeys` line, the pinned requirement, the `Trust` and `Endpoints` blocks, comments stripped) and shows them; signing compares the tag's own sources with the record and stops, with the difference shown, when they differ. | `sign-test.sh`: a tag whose keys or requirement changed is refused. |
| F3 | MEDIUM. The key's backup step could leave the key readable by every process of the account. | §14 1.4 rewritten: in Terminal.app, the keychain's question answered Allow, never Always Allow; the 44 characters typed into a 1Password item (or on paper), never copied and pasted; ⌘K after. (Corrected by the second pass: this row said an encrypted disk image, which §14 doesn't.) | `sign-test.sh` reads both documents for "never Always Allow" and "Terminal.app". |
| F4 | MEDIUM. The in-person prompt showed 64 bits of the SHA-256. | The whole SHA-256, in groups of eight, in the prompt and printed before it (`UpdateManifest.signingReason`, `grouped`). | `update-install`: the prompt's exact text and its 64 digits; mutant "the prompt's digest shortened". |
| F5 | LOW. A same-user process could leave a changed, unchecked copy at Sill's path (change it in staging, kill Sill after the swap). | The staged copy is checked once more right before the swap and must equal the first check (`UpdateInstaller.install`); the quit waits for an install step (`AppDelegate`); T12 corrected. The moment left is between that check and `renamex_np` (microseconds), and the check after the swap still covers it. | Harness: "changed after the check, before install" refused before the swap; "raced" caught after it and put back; mutant "no check right before the swap". |
| F6 | LOW. A link through a link escaped Sill.app; Security opened links at the signature's own paths. | The link rule walks a target as the file system does and refuses a step into any link (the reviewer's patch); links at `Contents/_CodeSignature` and `Contents/CodeResources` refused; the tree check refuses anything but files, folders and links there. | `update-install`: the reviewer's three cases and two more; mutants "a walk through a link", "links at the signature's paths"; harness case "link-through-link" and "the new copy's CodeResources a link". |
| F7 | LOW. Rollback to an older signed release; manifests never expire. | The manifest carries its signed date (`signed …Z`). The automatic update installs nothing signed more than 120 days ago or dated ahead of this Mac's clock, and never a version below the highest whose signed release it has read (§15.3). Update Now shows the version and the person decides. | `update-install`: the date's form, a changed date, `dates`, the start rule's rollback case. |
| N1 | A leaked key cannot be revoked. | T28 says so, and what limits the damage (§15.4: the second look at GitHub, the stop, and the cooling-off, which the second security pass (A1) found counted from a line the key's holder writes: now from each Mac's first read of the manifest, with the signing record and `--audit` for Noah to notice). | Documentation; `update-install`'s A1 cases. |
| N2 | `refresh()` ran 10–70 ms on the main actor every second. | The look runs in a detached task; one at a time, callers queued (`AppUpdater.refresh`). | By reading (AppKit: no harness). |
| N3 | `forceTerminate` could end the old Sill itself. | Never this process: guarded in both places (`opened`). | By reading; the reviewer's probe: the launch always returned a new process here. |
| N4 | Hard links and open descriptors in the staged copy. | Every file of the app one name (`st_nlink == 1`), and only files, folders and links. | Harness "a hard link"; mutant "hard links taken". |
| N5 | A crash after the swap leaked the staging folder; the kept way back can be emptied by macOS. | The leftover note is written before the swap; the words say "soon, as macOS empties that folder after a few days". | Harness "the swap fails" (the note already there); mutant "the note after the swap"; `update-install`: the line. |
| N6 | The signer was built from 1,500 lines. | `strictVersion`, `strictTag` and `Architecture` moved beside `UpdateManifest`: the signer compiles `Compatibility.swift`, `UpdateManifest.swift` and `update-manifest.swift`. | `sign-test.sh` builds it so. |
| N7 | Any process claiming Sill's bundle identifier made every launch wait 30 s and quit. | Only a process that satisfies Sill's requirement counts, at launch and in the refusal (`UpdateInstaller.genuine`). | Harness: `genuine` against a running process; mutant "any Sill waited for". |
| N8 | The harness drives `UpdateInstaller` only. | Still so, plus the watcher (§15.5) now in it; the relaunch, the wait at launch, the quit and the hold remain AppKit's, covered by the pure state machine, by reading and by Noah's steps (§12, §15.8). TLS stays unexercised (the stand-in is plain HTTP). | — |

The reviewer's seven points for an automatic updater are §15.6.

## 12d. The second security pass (2026-11-12, the same reviewer, on 312b514)

`SECURITY-REVIEW.md`'s second section has every finding and its proof (0 critical, 1 high, 1 medium, 5 low,
3 notes). Its verdicts: the rehearsal can go as it is; the real update key can be made; Update Now ships after
W1 and W2; the automatic update after A1, then A2, A3 and G1. Each was verified here first (by reading, and for
A1, A2, A3 and W1 against the reviewer's proofs: the backdated manifest went at once, `highestSigned` rose on a
manifest alone, the attempts grew without bound, the watcher wrote through a planted link); what was done, and
the check that fails without it:

| | Finding | Done | Check that fails without it |
|---|---|---|---|
| A1 | HIGH. The cooling-off counted from the manifest's `signed` line, which whoever holds the key writes: a manifest dated 49 hours back went at once. | The wait counts from the later of the signed time and this Sill's first read of that verified manifest, kept per release (tag and zip SHA-256) in the keychain memory across launches (`Memory.Sighting`, `sighted`, `dates(signedAt:firstSeen:now:)`, `waitUntil`); a release whose zip changed is a new sighting. The signed date keeps the 120 days and the future refusal. Noah's way to notice: the signing record and `sign-update.sh --audit` (§15.4), run daily if he chooses. The words: "two days after it first finds it". | `update-install`: the reviewer's backdated manifest waits 48 h from its first sight; a later read never moves it; a new zip is a new sighting; mutants "A1: …" (four). `sign-test.sh`: the record, the audit's alarm for a manifest signed outside it, its notification. |
| R1 | MEDIUM. The trust record was compared with the local tag's sources; nothing tied the zip to that commit, and tags are unprotected. | `make-app.sh` writes `SillCommit` (the commit, "+changes" when the app's files differ from it) into the signed Info.plist; `sign-update.sh` signs only an app naming the commit of the local tag, and only while GitHub's tag (read through an annotated one) names it too. | `sign-test.sh`: an app built from another commit, an app naming none, a moved tag on GitHub: each refused before signing; an annotated tag read through. |
| R2 | NOTE. The record pins four constants, not the code that uses them. | Before signing, `sign-update.sh` shows the updater's own files' changes since the last release in the signing record and asks. | `sign-test.sh`: the change since a recorded v0.6.0 shown. |
| R3 | LOW. The leftover note, written between the last check and the swap, marked the moment to change the staged copy and SIGKILL Sill. | The note comes before the last check; T12 says what a SIGKILL in the moment after it still leaves. | Harness "changed when the leftover note appears" (refused before the swap); mutant "R3: the note between the last check and the swap"; `update-install`'s source rule. |
| A2 | LOW. The floor rose on any verified manifest before the app was downloaded: one signed "v99" froze every later release. | The floor rises only once an app passed both checks (`startCheck`). | `update-install`'s source rule; mutant "A2: the floor raised on a manifest". |
| A3 | LOW. Attempts counted on offers nobody verified (defaults any process writes); an item over 64 KiB read as nothing (the switch off, the floor and the stops forgotten). | An attempt counts only once the manifest verified and its dates let it go on (`fetch`); every write is kept small (`bounded`: versions newer than the one running, eight attempts and sightings, 32 stops, well-formed text; the fullest memory a few KiB); an item that can't be read is never "nothing remembered": the switch reads off with a note, and only the person turning it on writes over it (`storeRead`, `AutoUpdateStore.unreadable`). | `update-install`: 1,500 attempts bounded to eight, the fullest memory's size, `storeRead`'s answers, the switch's note; mutants "A3: …" (four). |
| W1 | LOW. The watcher put back without a check after its moves, and wrote its note through a link planted in Sill's Caches folder. | After its moves and its note it checks the copy at Sill's path as it checked the old copy (a folder, not a link; valid; the cdhash that ran), and moves it aside unstarted if that fails; the note goes in a new file renamed into place (`mktemp`, `1<>`, `mv -f -h`). | Harness "a link planted at the restored note", "the note lands in the put-back copy", "the old copy replaced by a link"; mutants "W1: …" (three in the harness, two in `update-install`'s source rules). |
| W2 | LOW. The notes were read on the main actor with `Data(contentsOf:)`: a FIFO planted there hung Sill's launch or quit; the watcher's `head` could block too. | Notes are read only as small regular files (`O_NOFOLLOW`, `O_NONBLOCK`, `fstat`'s `S_ISREG`, 4 KiB), the launch's off the main actor; the started note is a file whose name carries the token (`isToken`), which the watcher looks for and never opens (§8). | Harness: a FIFO, a link and a 5,000-byte file where a note goes; "a FIFO at the started note", "a link at the started note"; mutants "W2: …" (three in the harness, two in `update-install`). |
| G1 | NOTE. Install Now on a waiting copy skipped the second look at GitHub. | A phase of its own, `lookingAgain`: GitHub asked again (still the latest, the manifest the one checked, no stop), then the install or the question. | `update-install`'s state machine; mutant "G1: Install Now without a second look". |

N9, each answered:
- **The clock.** A refusal by the dates (a clock set back makes a fresh release "dated in the future") is no
  longer counted as an attempt (A3): a wrong clock costs only the wait, and Sill installs by itself once the
  clock is right.
- **The stop.** Any garbage named `Sill.zip.stop` stops a release, by design (fail closed); whoever can put it
  there can already pull the release.
- **Quit during an install.** The quit waits for the step (F5) and now never starts the new copy
  (`quitRequested`): it is in place, checked twice, and starts the next time Sill opens. No watcher runs then,
  so a new copy that doesn't start is not put back by itself: the copy it replaced stays in the staging folder
  until the new one's host is up, and the download page is the way back.
- **Forged notes.** Any process of the user can write Sill's notes and make the pane say "Sill updated itself
  to …" (the pending note naming the version that runs) or "… didn't start, so … is back" (a matching token,
  from `ps`). Accepted: they are words about this Mac's own Sill; no note installs anything, grows the memory
  (A3), holds Sill up (W2) or names a path outside Sill's notes (`isToken`); a process that can write them can
  already show windows of its own.
- **The switch's words.** "… it isn't a notarized release." was wrong for a notarized build without the keychain
  group: now "This copy of Sill can’t keep this setting: only Sill’s releases from GitHub can." The footnote's
  "Update Now does the same at once." read as Update Now never disconnecting: now "Update Now checks it the
  same way, at once."
- **§12c's F3 row** said an encrypted disk image, which §14 doesn't: corrected.

R2's residue: the diff shows the updater's code; Noah still has to read it. The rest of the reviewer's reading
holds (its "What held": the stop, the second look, the hold, the store, no way in, the watcher's spawn).

## 12e. The third security pass (2026-11-12, the same reviewer, on b69429ed)

`SECURITY-REVIEW.md`'s third section has every finding and its proof (0 critical, 1 high, 1 medium, 2 low, the
notes N10 a to n; R1 and R2 only partly closed; R3, A2, A3, W1, W2, G1 and N9 closed). Each was confirmed here
against its proof before it was fixed: the code each proof ran, read at the lines it names, does what the proof
says (for AU1, CL1, W3 and N10 k, l and m: the audit's `select(.draft == false and .prerelease == false)` and its
`die` before the notification; `fetch`'s `Date()` as both the first sight and now; the watcher's `exit 7` with
nothing at Sill's path and no `-links` test; `prefix(200)` on Characters; `stop.tag == release.tag`; the variable
taken with any key file), and the new checks fail on the code before the fix (the mutants, and `sign-test.sh` run
against b69429ed's `sign-update.sh`). None turned out not to be real. What was done, and the check that fails
without it:

| | Finding | Done | Check that fails without it |
|---|---|---|---|
| NB1 | HIGH (design). On the nightly channel both proofs are one GitHub job's: any push to main reaches every Mac with both switches on within about a day. | Noah decides (§16.10: the reviewer's four options, what each stops and doesn't, which survive his account being taken over, and the exact steps and `gh api` commands for the two settings, none of them run here). Whatever he answers: the switch's words say what a nightly trusts, the reviewer's sentence ("Nightly builds are built and signed by GitHub from Sill's newest code; nobody looks at them first."); the nightly's wait is one constant, `UpdateAutoPolicy.nightlyCoolingOff`, 0 today, whose words follow it (`nightlyCoolingOffWords`, `nightlyWords(wait:)`, the footnote, the offer's note) and whose wait, above 0, counts as a release's (first sight, both clocks, the nightly's key). Today's behaviour is unchanged. | `update-install`: the words; 0 and 12 hours through `dates`, `start`, `sighted`, `bounded`, `waitUntil` and the notes; mutants "NB1: the nightly words as two checks", "NB1: the nightly's wait changed silently", "NB1: a nightly that waits begun early", "NB1: no wait taken as a wait", "NB1: a nightly's offer note without its wait", "a nightly with a cooling-off". |
| AU1 | MEDIUM. `--audit` skipped drafts and pre-releases, stopped without a notification when `gh` couldn't list, ran at a time written in the repository; a release's first sight outlived the release. | The audit reads every release that carries `Sill.zip.manifest`, drafts and pre-releases included, each manifest by its asset id (a draft's has no download address), and names each one's state; with `--notify`, every stop of an audit notifies (an EXIT trap: an expired login, no network, an unreadable listing); the checklist's LaunchAgent runs it every four hours from when it is loaded (`StartInterval`), no time written. In Sill: the wait counts from the later of the first sight and the release's `published_at` (GitHub's field, kept per sighting, only ever later), so a release deleted and published again starts over; a release whose answer doesn't say when it was published never installs by itself. §15.4 says the record and the audit guard against a key leaked off this Mac, not against someone in control of it or of Noah's account. | `sign-test.sh`: a release outside the record as a pre-release, as a draft and published, each named with a notification; `gh` failing as an expired login: a notification. `update-install`: published again on day 2 waits afresh; no `published_at`, no automatic install; the publication kept only ever later; mutants "AU1: …" (five) and "CL1, AU1: the dates without GitHub's". |
| CL1 | LOW. The cooling-off counted on this Mac's wall clock. | The wait counts on GitHub's clock too: `Transfer` keeps the `Date` header of each HTTPS answer (`httpDate`: RFC 9110's IMF-fixdate only, a real date with its own weekday, GMT), the sighting keeps GitHub's time at the first read (`firstGitHub`, filled once), and the install needs 48 h by GitHub's clock (from the later of that and `published_at`) as well as by this Mac's. A missing or unreadable date never counts as a go: Sill waits for an answer that has one. | `update-install`: the reviewer's two proofs (the clock 47 h ahead an hour after the first read; the clock 72 h behind at the first read with a matching signed date) wait; no date waits; the date parser's forms; mutants "CL1: …" (four). Harness: GitHub's clock and `published_at` read from the stand-in's answer, a fixed `Date` word for word, none and "yesterday" read as none; mutants "CL1: GitHub's clock never read", "CL1: GitHub's clock left off the release". |
| W3 | LOW. When the watcher's final check failed, nothing was left at Sill's path; `whole` had no one-name rule. | On a failed final check the watcher moves the put-back copy aside and the new copy (`did not start.app`, checked whole when it was installed) back to Sill's path, not started, never into whatever stands there (exit 7 then), and writes the restored note with a third line, `kept` (exit 8); Sill, opened again, says "Sill 0.4 didn’t start the first time, and the copy it replaced failed its last check, so Sill 0.4 stayed. …" (`.keptUnstarted`). `whole` refuses a copy with a regular file of more than one name (`find -type f -links +1`), as the installer's tree check does. | Harness: "the note lands in the put-back copy" (the reviewer's B: the put-back copy fails its last check, the new copy is back at Sill's path, the note says `kept`, nothing started) and "W3: a second name for a file of the old copy while it waits" (the reviewer's F: the old copy refused, nothing put back); mutants "W3: Sill's path left empty when the last check fails", "W3: a file with two names taken". `update-install`: the words, the source rules; mutant "W3: a new copy the watcher kept unsaid". |
| R1′ | MEDIUM (carried). `SillCommit` is the build's own word: a tag moved for the CI run and moved back before signing passed every check. | `sign-update.sh --run ID`: GitHub's record of the run (`gh api repos/…/actions/runs/ID`) must be release.yml's, completed successfully, started for this tag, and must name the local tag's commit as `head_sha`; the zip is the artifact `sill-zip-<tag>` that run kept (release.yml now keeps the published zip for 30 days). `--expect-sha256` is gone. The checklist prefers a zip built on this Mac. | `sign-test.sh`: signed from the run's artifact; refused: a run that built another commit, one that didn't succeed, another workflow's, one for another tag, one without the artifact, an artifact that isn't GitHub's zip, `--run` with `--zip`. |
| R2 | NOTE (carried). The list of the updater's files missed four that steer it; `--yes` skipped the question. | `updater_files` adds AppModel.swift, SettingsPanes.swift, StreamProtocol/Compatibility.swift and SillHost/StreamServer.swift; the question about the updater's changes is asked whatever `--yes` says. | `sign-test.sh`: `--yes` with no answer refuses; each of the four files is in the list. |
| N10 a | A nightly key in `releaseKeys` was a release key; only the check refused it. | `Trust.release` trusts a key in both lists for neither, and the tests' key for nothing. | `update-install`; mutant "N10 a: a nightly key in releaseKeys trusted". |
| N10 e | `sign-update.sh` didn't refuse an app with `SillChannel`. | Refused before any other check of the app. | `sign-test.sh`: a nightly of the tag's commit. |
| N10 g | The store held back `on` on a failed write, not `nightly`. | Both (`UpdateAutoPolicy.heldBack`). | `update-install`; mutants "N10 g: …" (two). |
| N10 j | The watcher's token is in its arguments (`ps`). | Accepted, said in `watcherScript`'s comment and below: any process that can read it can as well kill the watcher, which is all a made-up started note achieves (no put-back); another hand-over (a file, a pipe) would leave that unchanged. | — |
| N10 k | A failure's words were cut by Characters (200 clusters: 112,511 bytes). | Cut at 200 bytes of UTF-8, between scalars (`utf8Prefix`). | `update-install`: 250 clusters of 301 scalars stay within 200 bytes; mutant "N10 k: words cut by Characters". |
| N10 l | Stops matched the tag's text. | By version (SillVersion's order) and the zip's SHA-256, beside the release and in what Sill remembers (`stopNames`, `isStopped`). | `update-install`: a stop for v0.4 stops v0.4.0 and one for v0.4.0 stops v0.4.0.0, by the zip's SHA-256 too; mutants "N10 l: …" (two). Harness: "a stop naming the release's version in another form (v1.1.0 for v1.1)" refused, "a stop for another release" installs; mutant "N10 l: a stop by its tag's text". |
| N10 m | `SILL_SIGN_TEST_BUILT_FROM` was honoured with any key file. | Only with the tests' key, `UpdateManifest.testKeySeed` (SHA-256 of a sentence, so anyone can make it), which `Trust.release` trusts for nothing and the signer's `test-key` writes. | `sign-test.sh`: the variable with another key refused; `update-install`: the tests' key in no list. |
| N10 n | The footnote said "Once a day" with nightlies on, when Sill also asks at each launch. | "Once a day, and with nightly builds on each time Sill opens, …". Found while fixing it: with "Check for updates automatically" off, a launch still read the nightly pre-release; now a launch reads it only while that check is on (`checkAnswered(atLaunch:)`), and the privacy page says when Sill asks (on turning the switch on, with each daily check, at each launch while the check is on). | `update-install`; mutants "N10 n: once a day only, with nightlies too", "N10 n: the nightly asked at launch with the daily check off". |

The rest of N10, each answered (accepted, with the reason):
- **(b) Commit counts of two lines compared as one.** A release built on a branch (1450) is offered main's nightly
  of its version (1460), which lacks that branch's fixes. Accepted: releases are tagged on main's first-parent
  line (docs/release-checklist.md: "only main builds"), so a release's count and a later nightly's are counts on
  one line; a branch release would be a process error, and the nightly then is still a genuine build of main,
  newer code by the order the person chose with the switch.
- **(c) No stop for nightlies; a release's stop doesn't reach them.** Accepted: deleting
  `Sill-nightly.zip.manifest` from the pre-release stops a nightly everywhere it hasn't installed (each Sill reads
  it again before it downloads and right before it installs by itself); a stopped release's zip offered as a
  nightly needs the nightly key, which T38 already treats as main's own power (NB1).
- **(d) A leaked nightly key can re-sign an old genuine build with a fresh date.** Accepted: the 30 days bind only
  the signed date, the nightly floor binds what each Mac has seen (a build below its highest is refused), and
  every build so re-signed is a genuine notarized Sill of Sill's team; a key that leaked is replaced (§16.8).
- **(f) `SillCommit` and `SillChannel` catch mistakes, never a hostile build.** Accepted and said: R1′'s `--run`
  takes the commit from GitHub's record, not the app; a zip built on this Mac needs no such word.
- **(h) The nightly words read as two independent checks.** Fixed with NB1 (i).
- **(i) A made-up `updateLatestTag` in defaults hides the nightly offer until the next check rewrites it.**
  Accepted: denial only, by a process of this user (which could as well quit Sill), until the next daily check.

R1′'s residue: `--run` trusts GitHub's record of the run (whoever controls the account can start a run of
another commit, but then `head_sha` says so); a zip built on this Mac remains the way to prefer.

W3's residue: the watcher no longer leaves Sill's path empty by its own decision, but a process of this user can
still remove what is there or the parked copy (in the staging folder, which belongs to the user), as it could
remove Sill.app at any other time; what App Management allows there is Noah's A6.

## 12f. The fourth security pass (2026-11-12, the same reviewer, on 3ec9e3d1)

`SECURITY-REVIEW.md`'s fourth section: 0 critical, high or medium; 2 low (AU2, W4), the notes N11 a to h. CL1, R1′
and R2 closed; AU1 and W3 closed but for AU2 and W4; NB1 carried, Noah's. Each finding was confirmed against its
proof before it was fixed (the code each proof ran, read at the lines it names: `sighted`'s "only ever later",
sightings keyed by tag and zip, the audit's `select(.name == "Sill.zip.manifest")` and its pass on `[]`; the
watcher's unchecked `mv "$parked" "$app"` after a test of the path; `waitUntil`'s `p − g` carried over whatever
its size; `--run` without `event` or `head_repository`; the weekday). None turned out not to be real.

| | Finding | Done | Check that fails without it |
|---|---|---|---|
| AU2 | LOW. A rogue release could come back unseen: as another, older release object (its earlier `published_at` ignored, so it went at once), behind a renamed manifest, or after an empty listing. | In Sill: GitHub's release `id` (a positive whole number GitHub never gives another release) is kept in each sighting, and the same tag and zip on another release object is another sighting, which waits afresh; a release whose answer has no `id` never installs by itself. Chosen over restarting on any change of `published_at`: the `id` names the object itself, so an edit of the same release (its notes, a pre-release toggle) moves nothing while any other object, older or newer, waits, and nothing depends on GitHub keeping or changing a date. In the audit: a `Sill.zip` not in the record (by GitHub's digest) on any release at or above the record's lowest version, whatever its manifest is called; a release the record names that GitHub doesn't list (unless marked with `--pulled`); an empty listing; a login GitHub lists no drafts to (`permissions.push`). | `update-install`: the reviewer's proof (an older object back two days later waits 48 h from its return), the same object read again, no `id`; mutants "AU2: …" (five). Harness: the `id` read from the stand-in's answer, and none. `sign-test.sh`: a renamed manifest beside a `Sill.zip` outside the record; a recorded release missing (an older release's `Sill.zip` not named); an empty listing; no push permission; `--pulled`. |
| W4 | LOW. The watcher's put-back moved the parked new copy back unchecked, and tested Sill's path before a move that isn't exclusive. | The parked copy is checked as the old one is (a folder, not a link, no file with two names, strictly valid, the requirement) with the new copy's cdhash, which the watcher now takes as one more argument (the code the swap checked); only then, and only to an empty path, is it moved back; Sill's path is checked whole again after that move, the `kept` note written before that check, and `kept` stays only if it holds, else the note says `lost` (exit 9) and Sill says so: "An update of Sill didn’t finish: the new version didn’t start the first time, and Sill’s watcher couldn’t leave a whole copy of Sill in its place. …" (`.noWholeSillLeft`). No exclusive rename exists in /bin/sh (`mv` moves into a folder made at the path in the moment between), so the check after the move decides: whatever stands there then is either the new copy whole, said `kept`, or not, said `lost`; a race can only cost Sill its path, which a process of this user can do anyway, never a changed copy said to be kept. | Harness: "W3: the put-back copy fails its last check, the new copy goes back whole"; "W4: the kept note lands in the copy moved back, so the check after the move says lost"; "W4: the parked new copy changed, never moved back"; mutants "W4: …" (four). `update-install`: the words, the source rules; mutants "W4: …" (five). |
| N11 a | The gate's estimate carried GitHub's publication delay over whatever its size: a first `Date` years off held the estimate years out. | A publication more than `maxAge` (120 days) after GitHub's time at the first sight is not carried over (none genuine can be); `dates`, with GitHub's clock in the answer just read, decides. A first `Date` years ahead still makes `dates` wait: that fails safe, as asked. | `update-install`: 25 years back, 30 hours, 10 years ahead; mutant "N11 a: any publication carried over". |
| N11 b | The audit passed an empty listing and one missing a recorded release. | AU2's audit part, above. | `sign-test.sh`, above. |
| N11 c | `--run` didn't check the run's `event` or `head_repository.full_name`. | A pushed tag or Run workflow (`push`, `workflow_dispatch`) on this repository's own code. | `sign-test.sh`: a `pull_request` run, another repository's head; a dispatched run signs. |
| N11 d | The audit's notification is best-effort and can't report a run that never happened. | Accepted, said here and in §15.4: `osascript … \|\| true` (a failed notification must not hide the alarm, which `audit.log` and the exit status keep); a Mac off, a LaunchAgent unloaded or notifications turned off for Script Editor leave only `audit.log`, which is why GitHub's "Watch › Releases" mail is named beside it. | — |
| N11 e | N10 b's answer rested on a rule nothing enforced: releases tagged on main's line. | `release.sh` refuses a release (and `--check-tag`) whose commit isn't an ancestor of `origin/main` as the checkout knows it (the release workflow's checkout fetches every branch). | Tried in a scratch repository: on main, nothing; a branch's commit, refused; no `origin/main`, refused with the command to fetch. |
| N11 f | `httpDate`'s comment said "Wed, 12 Nov 2026", a Thursday. | "Thu, 12 Nov 2026". | — |
| N11 g | The audit downloaded a manifest asset of any size. | A `Sill.zip.manifest` over 4 KiB (more than any Sill reads) is named and never downloaded. | `sign-test.sh`: a 5,000-byte one named, its asset never asked for. |
| N11 h | The note's `1<>` still opens through a link planted in the moment after `mktemp`. | Accepted, now in every branch: every note is written before the check that follows it (the restored note before the put-back copy's check; with W4, the `kept` note before the check after the move), so a write through such a link into the copy at Sill's path is caught and the copy is never said whole. | Harness: "W4: the kept note lands in the copy moved back …" (a note written into the copy at Sill's path is caught). |

## 12g. The fifth security pass (2026-11-12, the same reviewer, on f9bab246: round 6 only)

`SECURITY-REVIEW.md`'s fifth section: nothing new critical, high or medium; one low (AU3) and the notes N12 a to d.
Round 6 closed what it set out to: W4; AU2 for its three proofs (a narrower form left: both of a release's files
renamed); N11 b, c, e, f, g; d and h accepted with sound reasons; a closed for what was proved, with a stall left
(N12 a). Each finding was confirmed against its proof before it was fixed (the audit's listing rule asks only where
an unpulled recorded release went, and nothing asks whether a pulled one is back; `waitUntil` still carried a
publication over up to 120 days; the floor is the lowest version signed). None turned out not to be real.

| | Finding | Done | Check that fails without it |
|---|---|---|---|
| AU3 | LOW. A release marked `--pulled` and published again by anyone with write access from its genuine files (Noah's signed manifest and the zip) passed the audit silently, and Macs below its version would install it 48 hours after reading it; no key needed. | The audit names a listed release whose tag is marked pulled, with its own words ("YOU MARKED IT PULLED, AND IT IS BACK ON GITHUB …: pull it again, and publish a newer release to stop it for good"). §15.4, §14 and the checklist (where it says how to pull a release) say that pulling stops a release only while it stays pulled, and that to stop one for good Noah publishes a newer release: each Mac's floor then refuses the old one once it has installed the newer. | `sign-test.sh`: the release marked pulled, back from its own files, named with a notification (against round 6's script: "all … in your signing record", exit 0). |
| AU2′ | (The pass's table.) AU2's narrower form: a release with both of Sill's files renamed passed the audit (uninstallable while renamed: a gamble against an audit whose times are unknown). | The audit names a release at or above its floor that carries neither `Sill.zip` nor `Sill.zip.manifest` and isn't in the record. | `sign-test.sh`: a v0.7.0 carrying both under other names. |
| N12 a | The gate still carried a first `Date` up to 120 days back whole, holding the automatic install that long though `dates` would go at 48 hours (fails safe). | The start rule's estimate is this Mac's half alone (the later of the signed time and the first sight, plus the wait); GitHub's half (its clock, the latest publication) is `dates`'s, at each look. Nothing needs the carry: a look past this Mac's half costs one read of the release and its manifest, which counts no attempt and only ever lengthens waits, and since AU2 a release published again is another release object with its own first sight. | `update-install`: a first `Date` 25 years and 100 days back each give this Mac's 48 hours and `dates` goes then; a later publication waits in `dates` (AU1); mutant "N12 a: the estimate from the signed time alone". |
| N12 b | The audit's floor is the lowest version signed: an unsigned first key-carrying release would leave the versions between it and the floor audited by their manifests alone. | The checklist (part 1 §7) and §14 say to sign that first release too, though no Sill installs it through Update Now. Chosen over flooring the audit at the first version whose source holds a key: the audit runs from the copy beside the signer, with no checkout to read that history from, and a release Noah signs anyway costs one command. | — (a step of Noah's) |
| N12 c | §16.10's wording, three points. | Option 1: the Actions token here can't open a pull request (the repository doesn't let Actions create them: `can_approve_pull_request_reviews` false, read 2026-11-12; nightly.yml grants no pull-request write) but can merge one someone else opened; the conclusion stands. The stronger variant: `actor_id` 5 for the admin role is unverified, and the web page's steps are the sure way. The declined option: it survives secrets that leave GitHub outright, and against a push to main it holds only as far as what Noah checks before each night's tap (the notice's checks 1 to 3 belong in that step). | — (docs) |
| N12 d | H (a descriptor opened on a file of the parked copy while it sits in staging changes it after the watcher's last check: `kept` for a copy that isn't valid). | The first pass's N4, here in the put-back branch: accepted as N4 is. No check can see an open descriptor; the main swap has the same residue (T12). A changed executable doesn't run (macOS checks the code's pages), and a changed resource adds no grant the copy didn't have. | — |

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
- 01:00 to 01:20: the second review (§12b), its six findings taken (df36dc2). CI's Build and check passed on
  df36dc2 on GitHub's runner: `swift build -c release`, `Tests/checks/run-all.sh` (67 checks, update-install
  480 and update-policy 129 among them), the iOS app's build and the CLI's steps.
- 01:22: the harness found the clean-up could never list the temporary-items folder (T20): now a note
  names the folder for the next Sill (4716964).
- 02:02, after the second review's fixes: update-install 480 of 480; the harness 174 of 174 (the noted
  leftover removed and five forged notes refused; listing the temporary-items folder denied, as to an app:
  "System Policy: deny(1) file-read-data …/TemporaryItems" in the log); sign-test all; `swift build -c
  release` clean (the two capture warnings the 01:23 build gave in AppUpdater gone); previews identical to
  main's (936d627) but the 36 new files and menu.txt's appended samples. Seen once in the 01:23 run and not
  again: macOS's system policy put the freshly started ad hoc test app into provenance tracking ("ASP:
  Security policy would not allow process"), and while it ran its bundle read as not writable to the
  harness; the harness now looks again for up to 5 s. Sill, notarized and of its own team, is not tracked so;
  the rehearsal (§12, step 11) is where a real update shows it.

- 2026-11-12 03:30–06:30 (round 3: the security review, the size line, Automatically update Sill, the update
  key's words; the Mac restarted at 03:02, so the session's scratch moved to the handoff folder): every
  finding verified and fixed or answered (§12c); the automatic update built (§15); main at 0d22bbf (PR #356,
  the notes in docs/steps) merged with `Scripts/migrate-notes.py`. Results on 623e534 and 3e68898:
  `update-install` 716 checks and 82 of 82 mutants; the harness 227 of 227 and its 13 new mutants, 13 of 13;
  `sign-test.sh` all passed; `swift build -c release` clean but CaptureProbe's; previews against main's
  rendered in the same run (161 identical; the General pane's path; 126 new); CI's Build and check green on
  623e534. Found by running: the watcher's CDHash read (`codesign -d -v` prints none), a SIGPIPE race in
  sign-update.sh's `| grep -q` pipes under pipefail, `Process.waitUntilExit` waiting for good in the harness,
  an empty `case` in a mutant. Found by reading, fixed: the rollback floor had risen with the check's
  unsigned offer (a made-up "v9.9" would have stopped every later automatic update); the automatic update
  could have begun over a lost old copy; a later Sill without Update Now would not have answered the
  watcher (now every Sill.app does: §8); Update Now's install could cut off a device that joined after its
  question (now held and asked about, as the automatic update).
- 2026-11-12, round 4. Noah: the quiet wait 5 minutes (48 hours kept); then "can you add a toggle to Use
  Nightly Builds?", the nightly key his choice. The security review's second pass (§12d) taken first, on the
  coordinator's order, then the nightly design (§16, written before its code) and its code on top: aa8ee628
  (5 minutes: update-install 718, its 85 mutants 85 of 85 on an export of that commit, the harness 227 of 227,
  previews), then the second pass's fixes, then Use nightly builds. Their results are in the step file and the
  pull request.

## 14. For Noah: the update key, step by step

Three things, at the Mac. The key list stays empty in the code until step 2's commit; nothing here made a key.

**1. Once: the signer, the key, its backup.** In Terminal.app, never a terminal inside the Claude app
(agents can read that one).
1. Read the three files the signer is built from: `Scripts/update-manifest.swift`,
   `Sources/SillMenuBar/UpdateManifest.swift` and `Sources/StreamProtocol/Compatibility.swift` (the last
   only for SillVersion), and `Scripts/sign-update.sh`, which chooses what it signs. The signer is the only
   program that will ever hold the key.
2. `Scripts/sign-update.sh --install-signer`: it lists those files with their SHA-256 and the commit, and
   the trust it will hold every release to (the update keys, the pinned code requirement, Trust.release and
   Endpoints.github, as the checkout says them), asks whether you read them, and builds the signer into
   `~/Library/Application Support/Sill Update Signer/` with the hardened runtime (no program can load code
   into it or attach to it). Every signing checks that binary is unchanged and hardened, and that the
   release's Sill carries exactly that trust. After a change to any of it that you have read (your key,
   step 2; a rotation), run this again from that checkout. The keychain then asks once before the new
   signer may use the key: allow it only right after you ran --install-signer yourself; any other time a
   prompt about the update key appears, deny it.
3. `Scripts/sign-update.sh --new-key`: makes the key and keeps it in your login keychain ("Sill update
   signing key", never synced), and prints the public key and its key ID. It refuses to make a second one.
4. Back it up once, off the Mac, in Terminal.app: `security find-generic-password -s
   me.saffer.sill.update-signing -a ed25519 -w` shows the private key. At the keychain's question choose
   Allow, never Always Allow (Always Allow would let `security`, and so any program running as you, read the
   key without asking). Type its 44 characters into a 1Password item (or on paper in a safe); don't copy and
   paste it (Sill shares the clipboard with your devices, and Universal Clipboard with your other Apple
   devices); then press ⌘K to clear the window. Nowhere else: not a file in the repository, the handoff
   folder or Downloads, not GitHub, not CI.
5. What a lost key costs: no Sill already installed can accept another update through Update Now. Releases
   then go out unsigned (Update Now doesn't show; Open Release Page… as before) until one carrying a new
   public key is installed by hand once; its notes say so. A leaked key: the same, and the notes ask people
   to update by hand once; the leaked key alone installs nothing (a Developer ID signed, notarized build is
   still needed), but no Sill that never updates by hand can be told to stop trusting it (N1).

**2. Once: the public key into the app.**
1. Give the public key that step 1.3 printed (a line of base64; it is not a secret) to whoever makes the
   change, or make it yourself.
2. It goes into `Sources/SillMenuBar/UpdateManifest.swift`, `static let releaseKeys: [String] =
   ["‹the public key›"]`, in a commit of its own, reviewed, before the first release that carries the
   updater. `Tests/checks/update-install` checks every key there is usable.
3. From a checkout of that commit, `Scripts/sign-update.sh --install-signer` again: it shows the trust
   with your key in it, and from then on a release is signed only while its Sill trusts exactly that key.
4. That first release is installed by hand (the Sill before it has no key to check with): it is the first
   one whose Update Now works, and the release after it is the first Update Now installs. Sign it too (step
   3), though no Sill installs it through Update Now: the audit checks every release from the lowest version
   you signed (the fifth security pass's N12 b).

**3. Every release: sign it after it is published.**
1. Publish as today (part 2 of docs/release-checklist.md).
2. On your Mac, from the release's tag: `Scripts/sign-update.sh v0.6.2`. If you built and published it here
   (`release.sh --publish`), that is all: it compares GitHub's `Sill.zip` with `.build/Sill-0.6.2.zip`, the
   way to prefer. If the release workflow built it in a run you approved, add `--run ‹the run's number›` (the
   digits at the end of the run page's address): it asks GitHub which commit that run built and signs only
   when it is your tag's, taking the zip that run kept (the third security pass's R1′). A release you did not
   build here or approve has neither, and is refused: that is the point.
3. It checks that v0.6.2's Sill trusts exactly what you recorded at step 1.2 (or 2.3), and refuses
   otherwise, showing the difference: another key, team or host slipped into the release is caught here.
   It checks that GitHub's tag v0.6.2 names the same commit as your tag, and that the app in the zip was built
   from that commit (its Info.plist says which: `make-app.sh` writes it), and refuses otherwise (the second
   security pass's R1: a tag moved on GitHub, a build of another commit), and refuses a nightly build. It
   shows what changed in the updater's own files and the ones that steer it since the last release you
   signed and asks whether you read it, whatever `--yes` says (R2).
   It checks the zip (the checklist's download checks) and prints its SHA-256 in groups of eight. Then
   Touch ID (or your password) asks you to allow "sign Sill v0.6.2 for Update Now: Sill.zip, ‹size› bytes,
   SHA-256 ‹64 hex digits in groups of eight›": compare every group with the SHA-256 `release.sh` printed
   for Sill.zip (or the approved run's), and allow only when all match. Any other time this prompt appears
   (when you didn't just run sign-update.sh), cancel it: something is trying to use your key. Then it
   shows the manifest, asks
   "Upload Sill.zip.manifest to v0.6.2 in Saffsanity/sill?", and on yes uploads it and reads it back. When it
   worked, the last line is "Uploaded and read back: v0.6.2 is signed for Update Now." and the release lists
   `Sill.zip.manifest`.
4. Until you sign a release, Sill shows it as before Update Now: "Sill 0.6.2 is available." with Open
   Release Page… and no Update Now (every Sill's check notes whether the release lists the manifest). A Sill
   that checked before you signed shows Update Now after its next daily check, or at Check Now. Someone who
   clicked Update Now in between is told "Sill 0.6.2 isn’t ready for Update Now yet. Try again later, or
   open its release page." and nothing is downloaded.
5. Every manifest you sign goes in the signing record beside the signer (`signed.txt`; one Mac's: sign on
   that Mac, or the audit there names what you signed elsewhere).
   `Scripts/sign-update.sh --audit` compares every release on GitHub with it, drafts and pre-releases
   included (each manifest, each `Sill.zip` since the first release you signed, and every release you signed
   still listed), and says "Audit: all N signed releases in Saffsanity/sill (drafts and pre-releases
   included) are in your signing record, every Sill.zip since v0.6.2 is too, and every release you signed is
   listed." when all is well; a release you pulled yourself is marked with `Scripts/sign-update.sh --pulled
   v0.6.2`, or the audit keeps asking where it went; a release whose manifest
   verifies with your key but that you never signed here is a release you didn't make (a leaked key): pull it
   at once (delete the release, or mark it a prerelease; mark a deleted one with `--pulled`) or upload a stop
   (§15.4). Pulling stops it only while it stays pulled (anyone with write access can publish it again from its
   files, and the audit then names it): to stop it for good, publish a newer release. Sills with "Automatically
   update Sill" on install such a release two days after they first find it, so you have those two days.

**4. Your choice: the audit every few hours.** Running `--audit` by hand after each release costs a few
seconds. To have it look every four hours and notify you when something is wrong or when it couldn't run,
install the LaunchAgent in docs/release-checklist.md part 1 §7 (one command; it runs the copy of
`sign-update.sh` installed beside the signer every four hours from when you load it, no time of day written
anywhere, makes a few requests to GitHub's API each time, needs no secret, and shows nothing while all is
well). Without it, the two days protect only as well as you happen to notice; GitHub's "Watch › Custom ›
Releases" mail is the zero-setup complement (it sees a release published, not an asset replaced on an old one
or a release turned into a draft). The record and the audit guard against a key that leaked off this Mac:
someone in control of this Mac or of your account here also controls `signed.txt`, the script and the
LaunchAgent.

## 15. Automatically update Sill (round 3, 2026-11-12)

Noah, 2026-11-12: "The updater screens look good except I would like the "2.4 of 5.9 MB" text to be below
the "Downloading Sill 0.4..." text. Also add a toggle for "Automatically update Sill" that works as
intended." Then: "Add the update key language when applicable as well."

### 15.1 Noah's decisions (2026-11-12)

In his words: "Your defaults are correct for the new updater features". So these are decided:
1. Off by default.
2. Usable only while "Check for updates automatically" is on, and only where Update Now is available.
3. It downloads and checks quietly, and installs only while no device is connected, never disconnecting
   anyone.
4. It needs the update key, and passes the same two checks as Update Now.
5. A failed update is tried again at the next daily check, never in a loop.

Later the same day, after reading the summary: "48 hour wait seems ok, can the 10 minute wait be shortened to
5 minutes?" So also decided:
6. The cooling-off is 48 hours (`UpdateAutoPolicy.coolingOff`), counted since the second security pass (A1)
   from when that Sill first read the release's verified manifest, never before its signed time.
7. The wait with no device connected is 5 minutes (`UpdateAutoPolicy.quietFor`; every word that names it is
   made from it).

### 15.2 The design

- **One state machine** (§4.6): the state carries a `mode`. `automatic` begins only from `idle` or
  `failed` (never beside Update Now, a question, or a copy already waiting, and never after a failure that
  left the old copy out of place: its way back stays the person's); its steps are Update Now's
  (fetch, download, unpack, check), with the same refusals and the same two checks; after the check it
  goes to `waiting`, never to `ready` (a device connected is never asked about, and never disconnected).
  `quiet(nil)` installs a waiting copy; `quiet(failure)` ends it. Install Now (Update Now's button on a
  waiting copy) makes it the person's from there: at once with nobody connected, else the question.
- **The rule** (`UpdateAutoPolicy`, pure, checked): it begins after a check GitHub answered, and when the
  switch is turned on, when the switch is on, the daily check is on, Update Now is available and not
  refused (looked at afresh first, off the main actor), the offer is newer and signed with the update key,
  no stop names it, it isn't below the highest version whose signed release this Sill has read, and it has had fewer than
  two attempts, the last at least 20 hours ago.
- **The dates.** The manifest's `signed` line (UTC, by the signer's clock; GitHub's own date is not signed)
  and this Sill's first read of that verified manifest (its own clock, kept in its memory across launches:
  the second security pass's A1). A release waits until 48 hours after the later of the two (no attempt
  spent; Settings says until when); one signed more than 120 days ago, or more than 10 minutes in this Mac's
  future, is never installed by itself ("Sill didn’t install 0.4 by itself: … Update Now still can."), and
  that refusal is no attempt either.
- **The quiet moment.** A checked copy waits; a run-loop Timer looks every 30 s. Any device connected
  restarts the wait (and the host's status changes reset it at once); once none has been connected for 5
  minutes and no pairing window is open, GitHub is asked again (the release must still be the latest, its
  manifest the one checked, and no stop beside it; an answer that says nothing, such as no connection,
  waits for the next look). Then, in one step on the host's queue, new sessions are held and the
  connected ones counted (`StreamServer.holdNewSessions`): with any connected the hold is released and the
  wait begins again; with none, the install (the staged copy checked again right before the swap), the
  relaunch and the quit, the hold kept until the quit. A device that tries to connect meanwhile is told
  "‹Mac› is restarting Sill to install an update. It reconnects in a moment." (goodbye `restarting`,
  reconnect true: a device that doesn't know the reason shows the message and reconnects). A copy that
  waited a day without a quiet moment is dropped (no attempt spent) and a later check starts afresh; a
  waiting copy never outlives the launch.
- **Where the switch lives.** With what the update remembers (attempts by version, the highest version
  whose signed release it read, stopped releases, the last update it made), in one item of Sill's own keychain group in the
  data-protection keychain (`AutoUpdateStore`: service `me.saffer.sill.update`, this device only, after
  first unlock, never synchronized). Not in Sill's defaults. Only Settings › General's switch turns it on
  (`AppUpdater.setAutomaticUpdate`, called from `SettingsPanes` alone); no kind 17, `DeviceSettings`, launch
  argument, `defaults write` or CLI flag names it (`update-install` reads the sources for it). A build
  without the group (every development and ad hoc build) keeps nothing and dims the switch: "This copy of
  Sill can’t keep this setting: it isn’t a notarized release."
- **The watcher** (§15.5) puts the old copy back if the new one doesn't run.
- **Words** (§15.7): the download's size on a line of its own under "Downloading …"; the switch and its
  notes; the waiting copy ("Sill 0.4 is ready." with "Sill installs it by itself once no device has been
  connected for 5 minutes, then restarts.", Install Now and Cancel); after a failure, "Sill tries again
  after its next daily check." or "Sill won’t install 0.4 by itself again; Update Now still can."; after an
  update, "Sill updated itself to 0.4 today at 03:12." for a week; the menu's "Sill 0.4 Is Ready to
  Install…" with "Installs by itself while no device is connected".

### 15.3 What Sill remembers, and the bounds on every loop (review 3's point 5)

- Attempts by version: count, the last one's time, the last failure's words. Two at most, at least 20 hours
  apart. An attempt counts only once the release's manifest verified and its dates let it go on (the second
  security pass's A3: an offer nobody verified counts nothing). Every failure after that counts, a new
  version that didn't run and was put back by the watcher too (so a release that crashes at launch on this
  Mac is installed and put back at most twice, a day apart, then left to Update Now). A wait (the
  cooling-off, a day without a quiet moment) is not an attempt.
- What is written is kept small (`UpdateAutoPolicy.bounded`, A3): attempts, first sights and stops only for
  versions newer than the one running, at most eight attempts and eight sights and 32 stops, only
  well-formed text; the fullest memory is a few KiB. An item that can't be read (larger than 64 KiB, not what
  Sill writes, a keychain error) is never taken for "nothing remembered": the switch reads off, with "Sill
  couldn’t read what it keeps for this setting, so it is off. Turning it on starts it afresh.", and nothing
  Sill does by itself writes over it.
- A refusal is looked at before anything is downloaded: a refusal that holds most days (another account's
  Sill, a read-only volume) downloads nothing.
- Staging: every attempt makes one folder and its end removes it, but for a folder holding the old copy that
  could not be put back (set aside, the person's way back); what earlier attempts left goes once the next
  Sill's host is up (T20).
- The highest version whose app passed both checks here (the second security pass's A2: not a manifest alone,
  so one signed manifest for a made-up "v99" can't stop every later release; a later, lower offer is a
  rollback: never by itself; the check's offers alone never count), and the tags a signed stop named (never
  installed, also after the stop is gone).

### 15.4 A cooling-off, a way to notice, and a way to stop (review 3's point 1; the second pass's A1; questions 13 and 14)

- The cooling-off: 48 hours (`UpdateAutoPolicy.coolingOff`; 0 turns it off), Noah's decision of 2026-11-12
  ("48 hour wait seems ok"), counted from when this Sill first read the release's verified manifest (and never
  before its signed time). Until the second security pass it counted from the manifest's own `signed` line,
  which is written by whoever holds the key: a release signed with a leaked key and dated two days back
  installed at once (A1). The first read is this Mac's own moment, kept per release (tag and zip SHA-256) in
  its keychain memory across launches; a release whose zip changes is read afresh and waits again. Cost per
  release: none for Noah; automatic installs come two to three days after he publishes, Update Now at once.
- **On two clocks, from the latest publication (the third security pass's CL1 and AU1).** The 48 hours must
  have passed on this Mac's clock and on GitHub's: the sighting keeps GitHub's time at the first read (the
  `Date` header of its HTTPS answer, `UpdateInstallPolicy.httpDate`: TLS keeps it from the network and no
  repository token sets it), and at the install GitHub's time in the answer just read must be 48 hours past
  the later of that first time and the release's `published_at` (GitHub's field, which no token sets; the
  sighting keeps the latest one GitHub gave, only ever later; GitHub's half is decided at each look, the start
  rule's estimate being this Mac's half alone: the fifth security pass's N12 a). So a clock moved on this Mac
  shortens nothing
  (a jump forward waits for GitHub's clock; a clock behind at the first read only lengthens the wait), and a
  release deleted and published again starts its wait over. The sighting is also kept by GitHub's release object
  (its `id`, which GitHub never gives another release: the fourth security pass's AU2), so the same tag and zip
  brought back on another, older release object, whose earlier `published_at` would move nothing, wait afresh
  too, while an edit of the same release or a pre-release toggle moves nothing; an answer without an `id` never
  installs by itself. An answer without a `Date` Sill can read (or one
  in another form than RFC 9110's IMF-fixdate) never counts as a go: the automatic update waits for an
  answer that has one ("waits for an answer from GitHub with a date"); a release whose answer doesn't say
  when it was published never installs by itself (GitHub always says it). Update Now is unchanged.
- **What the wait protects against now.** A release signed with Noah's update key that he didn't make (a
  leaked key, with a notarized build: T4, T28), or one he made and regrets: every Mac with the switch on
  waits at least two days after the release appears on GitHub before it downloads it, however the manifest is
  dated, and asks GitHub again right before the swap. If Noah pulls the release (deletes it, or marks it a
  prerelease), publishes a newer one, or uploads a stop within those two days, it installs nowhere by itself.
  Pulling stops a release only while it stays pulled (the fifth security pass's AU3): anyone with write access
  to the repository can publish it again from its genuine files (his signed manifest and the zip, no key
  needed), and every Mac below its version installs it 48 hours after reading it (a new release object, a
  fresh wait). To stop a release for good, Noah publishes a newer one: each Mac's floor then refuses the old one
  once it has installed the newer. The audit names a release marked pulled that is back.
- **What it does not protect against.** Update Now (the person installs at once, after seeing the version);
  a release nobody notices within two days (the wait buys time, not attention); a Mac that can't keep its
  memory (no keychain group) restarts the wait at every launch, never shortens it. A Mac's clock no longer
  shortens it (CL1, above). Nightlies have no cooling-off today (§16.7, T38; the one constant Noah may change,
  §16.10).
- **A way to notice (A1's second half).** Every manifest `sign-update.sh` signs goes in the signing record
  (`signed.txt` beside the signer: the time, the tag, the manifest's SHA-256 and the zip's).
  `Scripts/sign-update.sh --audit` downloads the `Sill.zip.manifest` of every release that carries one,
  drafts and pre-releases included (the third security pass's AU1: a release turned into either for a few
  minutes around each run otherwise passed unseen; read-only: the release listing with Noah's `gh` login, and
  each manifest by its asset id, a few kilobytes) and compares each with the record: one that verifies with
  a recorded update key but that this signer never made is a release Noah didn't sign, and it says so and
  exits 1. Since the fourth security pass (AU2, N11 b and g) it also names a `Sill.zip` not in the record (by
  GitHub's digest) on any release at or above the lowest version the record names, whatever became of its
  manifest (renamed, deleted); a release the record names that GitHub doesn't list (a release Noah pulled is
  marked so with `Scripts/sign-update.sh --pulled v0.6.3`); a listing with no release at all; a login GitHub
  lists no drafts to (`permissions.push`); and a manifest larger than any Sill reads, never downloaded. Since the
  fifth pass it also names a release marked pulled that GitHub lists again (AU3), and a release at or above that
  lowest version carrying neither `Sill.zip` nor `Sill.zip.manifest` that isn't in the record (AU2's narrower
  form: both renamed away while the audit looks). That lowest version is the audit's floor, so the first release
  that carries the update key is signed too (the checklist, N12 b). With `--notify` it posts a notification then, and also whenever it couldn't run (any stop: an
  expired `gh` login, no network), so it never fails in silence. The notification is best-effort (a failed
  `osascript` must not hide the alarm, which the exit status and `audit.log` keep), and no audit reports a run
  that never happened (the Mac off, the LaunchAgent unloaded, Script Editor's notifications off): accepted (the
  fourth security pass's N11 d), with GitHub's own release mail beside it. It needs nothing from Noah to keep the
  record; running the audit is his decision: by hand after each release (a few seconds), or every four hours
  with the LaunchAgent in docs/release-checklist.md (`StartInterval`: counted from when he loads it, so no time
  of day is written in the repository; a few requests to GitHub's API each run, no secret). Also free and
  without setup: GitHub's "Watch › Custom › Releases" mails him every release published in the repository (a
  new release, not an asset replaced on an old one, which only the audit sees).
- **What the record and the audit guard against, and what not (AU1).** A key that leaked off this Mac (a
  backup, the 1Password copy, a file): whoever signs with it elsewhere leaves no line in this Mac's record,
  and the audit names the release. They do not guard against someone in control of this Mac or of Noah's
  account here: that person also controls `signed.txt`, `sign-update.sh` and the LaunchAgent (and can sign
  with the keychain's key whenever Noah allows a prompt), so the audit there says what they want.
- The stop: `Sill.zip.stop` beside a release, `Sill stop 1` with the release's tag and its zip's SHA-256,
  signed with an update key (`UpdateManifest.Stop`; the signer's `stop` command, asked in person). Read
  before anything is downloaded, by Update Now and the automatic update: one that names this release (its
  version as SillVersion compares them, so a stop for v0.7.0 stops v0.7.0.0 too, and its zip's SHA-256: the
  third security pass's N10 l) ends the update ("Sill’s developer stopped Sill 0.4 with a stop signed with
  Sill’s update key, so it isn’t installed."), one that doesn't verify ends it too (fail closed), one naming
  another release changes nothing; the tag is remembered, and matched by version too. `Endpoints.github.stopName = nil` turns the mechanism off. Cost per
  release: none until it is used; using it: one signature in person and one upload. Pulling the release
  (or marking it a prerelease) within the cooling-off stops the automatic update everywhere too, since
  each Sill asks GitHub again right before its swap: the stop matters for a release that must stay listed.
- To stop a release: `"$HOME/Library/Application Support/Sill Update Signer/update-manifest" stop --tag v0.6.3
  --sha256 <the sha256 line of its Sill.zip.manifest> --out Sill.zip.stop`, then `gh release upload v0.6.3
  Sill.zip.stop --repo Saffsanity/sill` (docs/release-checklist.md part 1 §7).

### 15.5 The watcher (review 3's point 6)

Just before the old Sill quits, once the new one has finished launching and its running code is the code
checked, the old Sill writes a note for the new one (a random token, the new version, the mode) and starts
`/bin/sh` with the watcher's fixed script, in a session of its own, its output to /dev/null. The new Sill,
once its host has been up for 30 s (`provedAfter`), or when it is quit, makes the started note, a regular file
whose name carries the token (§8); the watcher, looking once a second whether it is there (never opening it:
the second security pass's W2), then ends, and the new Sill removes the old copy 3 s later. If the new
Sill's process is gone without the note, or there is no note after 150 s (`watchWait`): the watcher stops
that process (only while it runs Sill's executable from Sill's path: `ps`), checks the old copy (a folder, not
a link; no file with a second name, the third security pass's W3; valid with strict checks, the trust's
requirement, the cdhash it ran with), puts it back at Sill's
path (two renames; the new copy goes to "did not start.app" in the staging folder), writes the restored note
(the token, why: a new file renamed into place, never written through a link or onto a FIFO), checks the copy
at Sill's path again as before the move (W1: anything that changed it meanwhile, in the staging folder that
is this user's, or wrote into it through a planted link, is moved aside to "failed its check.app" and never
started; then, W3, the new copy goes back to Sill's path, not started, and the restored note gets a third line,
`kept`, so Sill's path is never left empty by the watcher's own choice and the Sill opened next says so; and, the
fourth security pass's W4, that new copy is checked whole first (with its own cdhash, the code the swap checked,
which the watcher takes as one more argument), moved only to an empty path, and Sill's path checked whole again
after the move, the `kept` note written before that check; when any of it fails, the third line says `lost`, and
the Sill opened next says no whole copy was left) and starts it with `open`. That Sill says what happened ("Sill 0.4 didn’t start, so Sill 0.3 is back.",
then the automatic note) and counts the attempt. Nothing that isn't the old copy, whole, is put back; a
process that isn't the new Sill is never stopped. A process of this user can write the started note (no
put-back) or stop the new Sill early (a put-back of the previous genuine version, checked): neither installs
anything new. It runs for Update Now too: one path. `Tests/update-harness`'s watcher cases run it for real,
with the test app's own executable as the launcher in place of `open`.

### 15.6 The reviewer's seven points, and how each is met

1. *A cooling-off on a signed date, and a signed way to stop:* met, both switchable, with their costs (§15.4):
   the cooling-off's 48 hours decided by Noah (13), counted since the second pass (A1) from each Mac's first
   read of the manifest, with the signing record and `--audit` for Noah to notice; the stop still an open
   question (14). F1, F2, F3 and F7 are fixed first (§12c). Checked: `update-install` (the dates, the first
   sight, the stop's format and signature, the start rule, which answers end a waiting copy).
2. *Only Settings turns it on:* met (§15.2). An attacker running as Noah cannot read, add or change the item
   (no process without Sill's signature and keychain group can); with Accessibility granted to it, it can click
   the switch, as it can click Update Now; `defaults write me.saffer.sill.mac updateCheck 0` turns the daily
   check off and so stops automatic updates (a denial, nothing installed). Checked: `update-install` reads the
   sources.
3. *No gap between the look and the quit:* met: the hold and the count in one step on the host's queue, then
   no session can register until the quit; a pairing window open counts as not quiet. Update Now's install
   holds the same way (the gap the reviewer found there too): a device that connected since the person's
   answer is asked about first (`devicesJoined`), never cut off. Checked: `update-install`'s state machine
   (and its mutant "a device that joined cut off"); the hold itself by reading, and Noah's step A4.
4. *The waiting copy checked again before the swap:* met: `install` runs the whole check on the staged copy
   (the code signature with strict flags, the pinned requirement, notarization and the stapled ticket, the
   identifier, team, entitlements and hardened runtime, the version, every slice's cdhash against the
   manifest, the tree: files, folders and links only, each file one name, the signature's own files real
   files) and requires the same result as the first check; GitHub is asked again before it. Checked: the
   harness's staged-copy cases and mutant.
5. *Bounded retries:* met (§15.3). Checked: `update-install`'s start rule.
6. *A failure after the old Sill quit:* met (§15.5). Checked: the harness's six watcher cases and five
   mutants.
7. *One state machine; the quit from a run-loop Timer:* met (§15.2): the quit is `quitForUpdate`'s Timer, the
   quiet looks are a run-loop Timer, and a relaunched Sill starts nothing at once (its own version is the
   offer, and attempts are spaced). Checked: `update-install`'s state machine cases.

### 15.7 The words, in one place

Wherever words say what an update is checked against, they name both checks; a build without an update key
says nothing of either (Noah: "Add the update key language when applicable as well").
- Footnote, switch off: "Once a day, Sill asks GitHub whether a newer version is out. GitHub sees this Mac’s
  IP address and which version of Sill it has; nothing else is sent. Sill downloads and installs nothing by
  itself. Update Now downloads the new version from GitHub, puts it in place of this copy and restarts Sill;
  Open Release Page… shows it on GitHub instead. Before it installs a new version, Sill checks it two ways: it
  must carry Apple’s signature and notarization for Sill’s developer, and the release must be signed with
  Sill’s own update key."
- Footnote, switch on: "… nothing else is sent. Automatically update Sill is on: Sill downloads a new version
  two days after it first finds it, then installs it and restarts once no device has been connected for 5
  minutes; it never disconnects anyone. Before it installs a new version, Sill checks it two ways: … Update
  Now checks it the same way, at once."
- Footnote, Use nightly builds on (the third security pass's NB1 and N10 n): "Once a day, and with nightly
  builds on each time Sill opens, Sill asks GitHub whether a newer version is out. … Before it installs a new
  version, Sill checks it two ways: it must carry Apple’s signature and notarization for Sill’s developer, and
  a release must be signed with Sill’s own update key; a nightly build is signed by GitHub, which builds it."
  With Automatically update Sill on too: "… Sill downloads a new release two days after it first finds it, and a
  nightly build as soon as it finds it, then installs it …" (the nightly's words from `nightlyCoolingOff`).
- Under "Use nightly builds", while on: §16.5's note.
- A build without an update key: the check's own footnote, unchanged ("… Sill never downloads or installs
  anything by itself: a new version opens its page on GitHub, where you download it.").
- Apple's check: "Couldn’t update: the downloaded app isn’t signed with the Developer ID of Sill’s
  developer.", "… Apple hasn’t notarized the downloaded app.", "… the downloaded app’s code signature isn’t
  valid." (each "Sill 0.3 is unchanged." after).
- The update key's check: "Sill 0.4 isn’t signed with Sill’s update key yet, so it can’t be installed from
  here. Try again later, or open its release page.", "Couldn’t update: the release’s signature with Sill’s
  update key isn’t valid.", "… the release is signed with an update key this Sill doesn’t know.", "… the
  release’s signature with Sill’s update key can’t be read.", "… this Sill has no usable update key.", "… the
  release on GitHub isn’t the one signed with Sill’s update key.", "… the downloaded app isn’t the one signed
  with Sill’s update key.", "Sill’s developer stopped Sill 0.4 with a stop signed with Sill’s update key, so it
  isn’t installed.", "… the release carries a stop that isn’t signed with Sill’s update key."
- The switch: "Automatically update Sill"; under it when it can't act: "Works while Check for updates
  automatically is on.", "This copy of Sill can’t keep this setting: only Sill’s releases from GitHub can.",
  "Sill couldn’t read what it keeps for this setting, so it is off. Turning it on starts it afresh.", or the
  refusal's own line.
- While a release is offered, under Update Now: "Sill installs it by itself two days after it first finds it,
  once no device has been connected for 5 minutes." (before this Sill has read its manifest), "Sill installs it
  by itself tomorrow at 03:00 or later, once no device has been connected for 5 minutes.", "Sill installs it by
  itself once no device has been connected for 5 minutes." (the wait over), "A stop signed with Sill’s update key names Sill 0.4, so Sill won’t install it.", "Sill
  won’t install 0.4 by itself: Sill 0.5 was out before it. Update Now still can.", "Sill won’t install 0.4 by
  itself again; Update Now still can."
- Waiting: "Sill 0.4 is ready." / "Sill installs it by itself once no device has been connected for 5
  minutes, then restarts." [Install Now] [Cancel]. Menu: "Sill 0.4 Is Ready to Install…" / "Installs by
  itself while no device is connected". Install Now: "Checking Sill 0.4 with GitHub again…" [Cancel] (the
  second pass's G1), then the install or the question.
- After: "Sill didn’t install 0.4 by itself: it was signed more than 120 days ago. Update Now still can.",
  "Sill tries again after its next daily check.", "Sill won’t install 0.4 by itself again; Update Now still
  can.", "Sill updated itself to 0.4 today at 03:12.", "Sill 0.4 didn’t start, so Sill 0.3 is back.", and when the
  copy the watcher put back failed its last check (the third security pass's W3): "Sill 0.4 didn’t start the
  first time, and the copy it replaced failed its last check, so Sill 0.4 stayed. If it misbehaves, download Sill
  again from getsill.app.", and when neither copy could be left whole (W4): "An update of Sill didn’t finish: the
  new version didn’t start the first time, and Sill’s watcher couldn’t leave a whole copy of Sill in its place. If
  this copy misbehaves, download Sill again from getsill.app."
- The way back: "Sill couldn’t put 0.3 back in place. It is at ‹path›: quit Sill and move it to your
  Applications folder soon, as macOS empties that folder after a few days."
- To a device during the hold: "‹Mac› is restarting Sill to install an update. It reconnects in a moment."

### 15.8 For Noah (with the rehearsal build of §12, its key, and a second notarized release)

A1. Settings › General: "Automatically update Sill" under "Check for updates automatically", off. With the
    daily check off it is dimmed with "Works while Check for updates automatically is on."
A2. Turn it on; quit and relaunch Sill: still on. `defaults read me.saffer.sill.mac` names nothing of it.
A3. For the rehearsal set `coolingOff` to 0 in that build (one line, as its key), or wait two days. With a
    newer release published and signed: Check Now. Within seconds Settings shows "Downloading Sill …" with
    the size under it, then "Sill … is ready." with Install Now and Cancel; the log's "Automatic update:"
    lines.
A4. With the iPad connected, nothing installs for as long as it stays. Disconnect it; about 5 minutes later
    (5 to 5½: Sill looks every 30 s) the log's "no device connected for 5 minutes; new sessions are held",
    the install and the restart. Try
    to connect the iPad in that minute: its message, then it reconnects to the new Sill by itself.
A5. Connect a device at minute 4 and leave again: the 5 minutes start over.
A6. The watcher: a rehearsal release whose app quits at launch (a build with `exit(1)` first thing, signed
    and notarized): within about two and a half minutes the old version is back and running, Settings: "Sill …
    didn’t start, so Sill … is back." and "Sill tries again after its next daily check."; a day later the
    same once more, then "won’t install … by itself again". Watch that the watcher's renames in
    /Applications are allowed (App Management: the responsible process is the old Sill, of the same team).
A7. A stop: sign one for the rehearsal release (§15.4), upload it, Check Now: the stop's line, nothing
    downloaded.
A8. Quit Sill while it installs (the second of "Installing…"): it quits once the step is done.
A9. VoiceOver: the switch, the download's two lines read together, the waiting copy's buttons.
A10. The security review's "Tests still wanted on real hardware": App Management with a real swap in
    /Applications on macOS 14, 15, 26 and 27 (no prompt for Sill; whether another process of the account can
    rename or write into the swapped-in bundle right after); continuity through a real update in both accounts
    (TCC grants, the login item with no Background Items notice, the data-protection keychain and pairings, no
    Gatekeeper prompt at the relaunch, the 30-second handshake under heavy load); the signer as it will run
    (the key item's real ACL after `--new-key`, the installed signer refusing injection, the in-person prompt's
    text, `notarized` on the real release offline).

## 16. Use nightly builds (round 4, 2026-11-12; written before the code)

Noah, 2026-11-12: "can you add a toggle to Use Nightly Builds? That in tandem with automatic updates should
download any update found immediately instead of 48 hours out. I think it will make it easier for folks to
download nightly builds." And, on the second proof: "A separate nightly key that GitHub holds seems like the
best option".

### 16.1 What it does

A switch, "Use nightly builds", in Settings › General's update section, under "Automatically update Sill",
off by default. With it on, the daily check (and each launch while that check is on: the third security pass's
N10 n; the footnote and the privacy page say so) also reads the pre-release `nightly` that
`.github/workflows/nightly.yml` publishes every night main moved (Developer ID signed and notarized in
GitHub Actions), and offers its newest build when it is newer than this Sill; Update Now installs it; with
"Automatically update Sill" on too, a nightly found is downloaded at once (no 48-hour wait) and installed
under the same rule as a release: 5 minutes with no device connected, never disconnecting anyone, the
watcher, the same retry bounds. Releases are still offered beside nightlies (§16.3).

### 16.2 The second proof: a nightly key (Noah's decision of 2026-11-12)

A nightly can't carry Noah's offline update key: nobody signs at 09:17 UTC by hand. So:
- **A separate nightly key** (Ed25519), its private half a GitHub Actions secret of the environment
  `nightly` (`SILL_NIGHTLY_UPDATE_KEY`), used only by nightly.yml to sign each nightly's manifest; its
  public half compiled into Sill (`UpdateManifest.nightlyKeys`, empty until Noah makes the key: until then
  the switch doesn't show and the channel is inert, as Update Now is without an update key).
- **Separate everywhere.** A nightly's manifest has its own first line, "Sill nightly 1", and is verified
  only with `nightlyKeys`; a release's, "Sill update 1", only with `releaseKeys`. Neither format parses as
  the other, and neither key list is ever tried for the other, so a nightly key can never satisfy a
  release's check (a release still needs the offline update key), and the release key's manifest is never
  a nightly (decided: the update key signs releases only; a nightly signed with it would mean the offline
  key had been brought to CI). The nightly key is trusted only while the switch is on, and only for the
  nightly channel's asset at the tag `nightly`.
- **What the nightly key adds over Apple's signature and notarization alone:** a nightly asset swapped or
  replayed on GitHub (an older notarized nightly, a build of another commit, a release's zip) fails: the
  signed manifest names this night's version, build, commit, zip size, SHA-256 and every slice's cdhash,
  and its signed time; a rollback to an older notarized nightly fails the (version, build) rule and the
  nightly floor (§16.3); a nightly offered as a release fails (another format, another key list). **What it
  does not add:** whoever can change main or the workflow gets a signed, notarized nightly. That is what a
  nightly is: code from main, built by CI, unreviewed by Noah at the moment it ships. Hence off by default,
  and the words say so.
- **The option not taken: Apple's checks alone.** It needs no key or secret, but then anyone who could
  replace an asset on the pre-release (a token with release rights, a compromised workflow run) could serve
  any older notarized Sill, or one of another commit, to every Sill on the channel; the nightly key binds
  each night's files to that night's build. Not built.
- **How a Sill learns of a nightly: from its signed manifest alone.** The daily look (with the switch on)
  reads the pre-release's listing and downloads `Sill-nightly.zip.manifest` (a few kilobytes), verifies it
  with the nightly key, checks it against the zip beside it (its name, size and GitHub's digest), and offers
  exactly the version and build it names (`UpdateInstaller.nightlyOffer`, `readNightly`;
  `UpdateInstallPolicy.nightlyListing`, `nightlyMatches`). The pre-release's title, notes and page are never
  read (the page is the one Sill builds). So no unsigned word can make a Sill say a nightly is available, a
  half-published pair (the zip of one night, the manifest of another) offers nothing, and Update Now's own
  read must find the very version and build offered ("GitHub’s newest nightly is no longer …" otherwise).
- **A key in both lists is trusted for neither nightly** (`Trust.release` filters `nightlyKeys` by
  `releaseKeys`), and the signer makes the nightly key only in a file (`new-key --nightly` refuses the
  keychain, where the update key lives); `update-install` checks the lists are disjoint.

### 16.3 Versions and their crossings

A nightly carries what main says, with the commit count as its build (`git rev-list --count HEAD`, as
make-app.sh stamps every build): "0.6.2 (1471)". Main moves to the next number only once App Review has
approved a release (release-checklist "Versions": "0.6.1 since App Review approved 0.6.0"), so a version's
nightlies come both before its release and after it until main moves on (0.6.1: nightlies of it before
v0.6.1, tagged at 1388, and after it), and only the build orders builds of one version in time.
- **The order.** A release by its version alone, as the update check has always compared (`releaseToInstall`,
  `verdict` for a release's manifest). A nightly by version, then build (`UpdateInstallPolicy.isNewer`):
  against this Sill's own build, whatever it is (a release's build is its commit count too).
- **The offer.** A release when its version is higher than this Sill's (`chooseOffer`), never the release
  of a nightly's own version: whether it is newer or older code only its signed build could tell, and the
  offer is made before any manifest is read (the review of this design found a nightly user would otherwise
  see "Sill 0.6.1 is available" for weeks after v0.6.1, then a refusal at Update Now). A nightly, with the
  switch on, when its (version, build) is newer. Both: the higher version, and on a tie the release (the
  tested one; the next night's nightly is offered after it if it is newer).
- **A release Sill turning the switch on:** offered the newest nightly if it is newer by (version, build),
  so on the night after a release the nightly of main's newest commit comes, whatever its version.
- **The switch off while a nightly runs:** no downgrade. The pane says "You have a nightly build, 0.6.3
  (1520). Sill updates to the next release after 0.6.3." Stable updates resume with release 0.6.4 or any
  later one (release 0.6.3 itself is never offered to a nightly of 0.6.3, as above).
- **A release published while someone runs a nightly of its version:** not offered (as above); with the
  switch on, the next nightly brings its code, and with it off, the next version does.
- **The rollback floors, one per channel:** the highest release version and the highest nightly (version,
  build) whose app passed both checks here (the second security pass's A2: never a manifest alone); the
  automatic update never installs below either.
- **Attempts:** counted only once the nightly's manifest verified (A3), by version and build; the memory keeps
  only nightlies newer than the running one by (version, build), and releases newer by version.
- **Dates.** A nightly's manifest carries its signed time too. No cooling-off for a nightly (Noah: "should
  download any update found immediately"): `UpdateAutoPolicy.nightlyCoolingOff`, 0, one constant whose words
  (the note under the switch, the footnote, the offer's note) follow it, and whose wait, once above 0, counts as
  a release's does, from each Mac's first sight on both clocks, kept by the nightly's key "0.6.2 (1471)" (the
  third security pass's NB1 asks Noah whether it should be some hours: §16.10). The age limit for a nightly installed by itself is 30 days (a
  quiet main can leave the newest nightly a few weeks old; replay below what this Sill has seen is the floor's
  job), and a signature more than 10 minutes in this Mac's future is refused, as for a release.

### 16.4 What nightly.yml publishes

After `release.sh --nightly --publish` (the dated `Sill-nightly-<yyyymmdd>-<sha7>` files, as today), a step
"Sign the nightly for Update Now" with the secret `SILL_NIGHTLY_UPDATE_KEY`:
`Scripts/sign-nightly.sh` reads tonight's notarized zip, its app's version, build and every slice's cdhash,
the zip's size and SHA-256 and the commit (refusing an app that isn't a nightly, `SillChannel`, or was built
from another commit, `SillCommit`), signs a "Sill nightly 1" manifest with the key (in a file under
`$RUNNER_TEMP`, deleted at the end), verifies it with the public keys compiled into this commit (none, or
another key, and it stops: no Sill would take it), and uploads
`Sill-nightly.zip` (tonight's zip under a fixed name) first and `Sill-nightly.zip.manifest` second. A Sill
reading between the two sees a manifest that names another zip, and refuses; a night that fails or
publishes half leaves either last night's pair or a mismatched pair, and a mismatched pair is never
installed (the manifest binds the size, the SHA-256 and the cdhashes). Without the secret the step says
"The nightly isn't signed for Update Now: the environment nightly has no SILL_NIGHTLY_UPDATE_KEY
(docs/release-checklist.md, Nightlies)" and the job stays green; with the secret but no nightly key compiled
into the commit (Noah's steps between setting the one and committing the other) it says so and stays green
too; only a compiled key that isn't the secret's half stops the step. No secret or setting is added by this
branch.

### 16.5 Who can turn it on, and the words

- Only Settings › General's switch (`AppUpdater.setNightly`), stored with the automatic switch in Sill's
  keychain item (`AutoUpdateStore`); never a device, a launch argument, `defaults` or the CLI; off by
  default; shown only where Update Now is and a nightly key is compiled in.
- The words: the switch "Use nightly builds"; under it, while on (the third security pass's NB1: the earlier
  "Each is checked two ways: … and Sill's nightly key, which only the nightly build signs with" read as two
  independent checks, when GitHub's one job makes both; the reviewer's sentence is taken word for word): "Nightly
  builds are built and signed by GitHub from Sill's newest code; nobody looks at them first. They are less tested
  than releases and may break. With Automatically update Sill on, each one installs by itself as soon as Sill
  finds it, without the wait a release has, once no device has been connected for 5 minutes. Turning this off
  doesn't go back to the last release: Sill keeps the nightly you have until a release with a higher version
  number." (the minutes from `UpdateAutoPolicy.quietMinutes`; the "as soon as …" from `nightlyCoolingOff`:
  with 12 hours, "each one installs by itself 12 hours after it first finds it, once …",
  `UpdateInstallPolicy.nightlyWords(wait:)`). The offers and steps name the build: "Sill nightly 0.6.2 (1471)
  is available.", "Downloading Sill nightly 0.6.2 (1471)…". The update key's failures for a nightly name the
  nightly key. The footnote, while it is on, says a nightly is signed by GitHub ("… and a release must be signed
  with Sill’s own update key; a nightly build is signed by GitHub, which builds it."), that Sill also asks at
  each launch ("Once a day, and with nightly builds on each time Sill opens, Sill asks GitHub …": N10 n), and,
  with Automatically update Sill on, the nightly's wait from the same constant ("Sill downloads a new release
  two days after it first finds it, and a nightly build as soon as it finds it, then installs it …"); off, it
  never names nightlies.
- Sill for iPhone and iPad is not affected (its nightlies are TestFlight's). A Mac on a nightly speaks the
  same wire, additive as always: a device on the App Store version connects to it as to a newer release,
  and skips what it doesn't know.

### 16.6 The watcher and the bounds

Unchanged: the watcher, the hold, the quiet moment. Attempts are kept by version and build for a nightly, so
a nightly that fails twice is skipped until the next night's build (a new build number); a release's by
version, as before.

### 16.7 Threat model, the new points

**T35. The nightly key in CI.** Held by GitHub as a secret of the environment `nightly` (main only, no
reviewer, as the Developer ID identity there). Whoever can run that environment can sign a nightly, which
only Sills with "Use nightly builds" on accept, and only for the nightly channel. It cannot sign a release.

**T36. A nightly served as a release, or a release as a nightly.** Another first line and another key list:
refused both ways (`update-install`, `sign-test.sh`).

**T37. A replayed or half-published nightly.** The signed manifest binds the night's build, commit, zip and
cdhashes; the (version, build) rule and the nightly floor refuse an older one; a pair from two nights fails
the size or the SHA-256, before anything is downloaded and before anything is offered.

**T38. What stands between the nightly channel and every Mac with both switches on (read this before
turning "Use nightly builds" on for anyone else).** Whoever holds the nightly key (a leaked copy, or a run
of the environment that holds it), can write to the pre-release `nightly` and can get a build notarized for
Sill's team can publish a nightly that every Mac with "Use nightly builds" and "Automatically update Sill"
both on installs by itself, at its next daily check, once no device has been connected for 5 minutes. All
three are in the environment `nightly`, which any commit on main runs every night with no reviewer (T4,
T35): a pull request merged to main, or a workflow changed there, is enough. Nothing else stands in the
way: there is no cooling-off for nightlies (Noah's decision: "should download any update found
immediately"), no signing record to audit (CI signs them, not Noah's Mac), and the second security pass's
lessons for releases (the first sight, the audit) don't apply. The third security pass (NB1, HIGH) read the
repository's settings on 2026-11-12: main is unprotected and has no ruleset, the only collaborator is
Saffsanity (admin), the `nightly` environment has no reviewer and no wait timer and lets admins bypass its
rules (`can_admins_bypass` true), and the `gh` login every agent session on this Mac uses has admin rights:
so both proofs are one GitHub job's, and whoever can push to main (or change its workflow) holds both.
§16.10 lists the four ways to narrow it, for Noah. What remains is only (1) the next night's
build, which replaces it as the newest (a Mac that installed the bad build updates to the next genuine one,
unless the bad build stopped it from updating, which it can), and (2) the watcher, which puts the old copy
back only when the new one doesn't run at all. Someone who notices can delete `Sill-nightly.zip.manifest`
from the pre-release, and no Sill installs that nightly after (each reads the manifest again before it
downloads, and again right before it installs by itself); with no cooling-off, most Macs with both switches on
will have installed it by then. A leaked nightly key alone (no notarization) installs
nothing new: the manifest binds the version, build and every slice's code, and the app must still pass
Apple's checks for Sill's team, so it can only point Sills at genuine builds newer than what they run, and
only from the pre-release, which takes write access to the repository too. A key that leaked is replaced
with §16.8's steps, the old public key taken out of `nightlyKeys`; a Sill that trusts only the old key can't
verify the new key's nightlies and keeps trusting the old one until it is updated once by hand (the next
nightly or a release, downloaded), as with the update key (T28). So "Use nightly builds" with automatic updates means trusting main
and the nightly environment as much as Noah's own Mac; it is off by default, and its note under the switch
says nightlies install by themselves without the two-day wait.

### 16.8 Noah's one-time steps for the nightly key (a few minutes; Terminal.app)

1. Make the key in a file on an encrypted disk image, never in the repository, ~/Downloads or the handoff
   folder: `Scripts/sign-nightly.sh --new-key --key-file "/Volumes/<encrypted image>/sill-nightly.key"` (it
   compiles the signer, about half a minute, and refuses a file that is there already). It shows "public key
   <44 characters> (key ID <8 hex digits>)" and where each half goes.
2. Store the private half as the secret, straight from that file, without the clipboard:
   `gh secret set SILL_NIGHTLY_UPDATE_KEY --env nightly --repo Saffsanity/sill < "/Volumes/<encrypted
   image>/sill-nightly.key"`. It answers with a line starting "✓" that names the secret; `gh secret list
   --env nightly --repo Saffsanity/sill` then lists SILL_NIGHTLY_UPDATE_KEY.
3. The public key into `Sources/SillMenuBar/UpdateManifest.swift`, `nightlyKeys` (one line, a commit of its
   own; `Tests/checks/update-install` checks that it is usable and differs from every release key).
4. Eject the disk image (or delete the file: losing it costs nothing but a new key, step 1 to 3 again, and
   Sills on the old key need one update by hand or by a release).
5. The next nightly run's summary then ends "Signed for Update Now: Sill-nightly.zip and its manifest on the
   pre-release nightly", and the pre-release lists `Sill-nightly.zip` and `Sill-nightly.zip.manifest` beside
   the dated files. Until a release carries the public key, no Sill offers a nightly (the switch doesn't show).
Never: reuse the release key (or any key of `releaseKeys`) as the nightly key; put the nightly key in the
login keychain item the release signer reads (`me.saffer.sill.update-signing`), or the release key into
GitHub; sign a release's manifest with the nightly key, or a nightly with the release key.

### 16.9 Open questions, each with the default taken

1. **Use nightly builds without Automatically update Sill.** Default: allowed; Update Now then offers the
   newest nightly and nothing installs by itself. Alternative: the nightly switch only with the automatic one.
2. **A cooling-off for nightlies.** Default: none, Noah's words ("should download any update found
   immediately"); T38 is its cost. Alternative: a few hours (12, say) from each Mac's first read, as releases
   have since the second pass, which would give a window against a bad night on main. The third security
   pass's NB1 puts it to Noah again with three other ways (§16.10); his answer is one line,
   `UpdateAutoPolicy.nightlyCoolingOff`.
3. **The oldest nightly installed by itself.** Default: 30 days by its signed time. Alternatives: 14; none.
4. **A release and a nightly of one version.** Default: the release (the tested one). Alternative: the higher
   build.
5. **Release V for someone on nightly V.** Default: never offered, as the update check never has (main keeps a
   version before and after its release, so only the release's signed build could order them). The other
   way: on a nightly, read the latest release's manifest when its version is this Sill's, and offer it when
   its signed build is newer: one more request a day for nightly users, a third look in the code.
6. **Turning the switch off.** Default: no downgrade; Sill keeps the nightly until a release with a higher
   version number.
   Alternative: offer the latest release even when older (Update Now never installs an older version today).
7. **An audit for nightlies.** Default: none (CI signs them; no record on Noah's Mac). Alternative: the nightly
   job keeps a record of what it signed, and `--audit` reads it.
8. **The pre-release's notes** say a nightly is offered only with "Use nightly builds" on once the commit
   carries a nightly key, and that the update check never offers one before (`release.sh`'s `nightly_body`).

### 16.10 NB1: what stands between a push to main and every Mac with both switches on (for Noah to decide)

The third security pass's NB1 (HIGH, a design finding): on the nightly channel both proofs, Apple's signature
and notarization and the nightly key's manifest, are made by the one job that builds main (`nightly.yml`'s Mac
job, in the environment `nightly`, which holds the Developer ID .p12, the notary key and the nightly key), so
whoever can push to main or change its workflow holds both: every holder of Noah's GitHub credentials, every
agent session on this Mac among them (its `gh` login has admin rights), and a GitHub-owned action at a pinned
SHA if one were bad. With "Use nightly builds" and "Automatically update Sill" both on, nobody is in the loop:
the next nightly run (09:17 UTC, or at once by hand), Apple's automated notarization scan, the Mac's next look
(each daily check and each launch), then 5 quiet minutes. The 30-day limit, the nightly floor and the watcher
don't change that (a fresh build is newer, runs for 30 s, and nightlies have no stop). If the environment's
secrets ever left GitHub, whoever has them keeps that power until the Developer ID certificate, the notary key
and the nightly key are all replaced.

**The decision is Noah's and is not made.** What this branch did whatever he answers: the switch's words say
what a nightly trusts (§16.5: "Nightly builds are built and signed by GitHub from Sill's newest code; nobody
looks at them first."); the nightly's wait before it installs by itself is one constant,
`UpdateAutoPolicy.nightlyCoolingOff`, 0 today (his decision of 2026-11-12 stands until he changes it), with the
pane's, the offer's and the footnote's words derived from it and `update-install` covering both 0 and 12 hours
from the first sight (on both clocks, kept by the nightly's key); so option 3's wait is a one-line change and a
re-render (and the held-back nightly sentences in README.md, site/support.html and site/download.html, which say
"without the two-day wait", read again). Nothing about today's behaviour changed.

The reviewer's four options (any one narrows it; the first two are settings, not code):

1. **A ruleset on main: no force push, no deletion, changes through pull requests.**
   - Stops: any change to main that doesn't go through a pull request (a direct push, a force push, a
     deletion); anyone who can merge one still changes main. With Required approvals 0, that is everyone with
     `contents: write`: a collaborator with write access or a leaked token without admin rights can each open
     a pull request and merge it; a workflow's `GITHUB_TOKEN` (nightly.yml's Mac job has `contents: write`)
     can't open one here (the repository doesn't let Actions create pull requests, `can_approve_pull_request_reviews`
     false as read on 2026-11-12, and nightly.yml grants no pull-request write) but can merge one someone else
     opened. The conclusion stands (the fourth and fifth security passes read this bullet).
   - Doesn't stop: an admin. Noah's account, and his `gh` login on this Mac, can open a pull request and
     merge it with no approval, or edit or delete the ruleset. Mostly a record: every change to main becomes
     a pull request, or a ruleset change in the repository's log.
   - The stronger variant for a one-person repository: Required approvals 1, with the repository admin role on
     the bypass list for pull requests only. Then only an admin merges without an approval (Noah, through
     the bypass), and a non-admin token's pull request waits for an approval nobody else can give; an admin
     (his account, his `gh` login) is still not stopped. Web page: as below, but Bypass list → Add bypass →
     Repository admin, then its menu "For pull requests only"; and Required approvals 1. Command: as below,
     with `"bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request"}]`
     and `"required_approving_review_count": 1`. That 5 is GitHub's id for the repository admin role is
     unverified here (it matches GitHub's examples as the reviewer recalls them; no API call was made from this
     branch): the web page's steps are the sure way.
   - Survives his account being taken over: no; it only makes a push visible.
   - Cost: every change to main goes through a pull request, Noah's own too (`gh pr merge` works as now).
   - In the web page: github.com/Saffsanity/sill → Settings → Rules → Rulesets → New ruleset → New branch
     ruleset. Ruleset name "main"; Enforcement status Active; Bypass list empty; Target branches: Add target →
     Include default branch; Branch rules: keep "Restrict deletions" and "Block force pushes" checked, check
     "Require a pull request before merging" with Required approvals 0 (a one-person repository can't approve
     its own pull requests); Create.
   - Or, in Terminal.app, the same as one command:
     ```
     gh api --method POST repos/Saffsanity/sill/rulesets --input - <<< '{
       "name": "main",
       "target": "branch",
       "enforcement": "active",
       "bypass_actors": [],
       "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
       "rules": [
         {"type": "deletion"},
         {"type": "non_fast_forward"},
         {"type": "pull_request", "parameters": {"required_approving_review_count": 0,
           "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false,
           "require_last_push_approval": false, "required_review_thread_resolution": false}}
       ]
     }'
     ```
     It answers with the ruleset (its `id`). Check: `gh api repos/Saffsanity/sill/rules/branches/main --jq
     '.[].type'` prints deletion, non_fast_forward and pull_request. Undo: `gh api --method DELETE
     repos/Saffsanity/sill/rulesets/<its id>`.

2. **On the `nightly` environment: `can_admins_bypass` off, and a wait timer of some hours or a required
   reviewer.** These are the only gates outside main's own code.
   - Stops: a nightly run's jobs from getting the environment's secrets (and so from signing, notarizing and
     publishing) until the timer has run out, or until a reviewer approved the run on its page; with the
     bypass off, an admin can't skip either without changing the setting first. Against someone who can push
     to main but isn't an admin, a reviewer stops the bad night and a timer gives the time to cancel it.
   - Doesn't stop: an admin. With Noah's account or his `gh` login, the reviewer is Noah: an approval through
     the web page or the API is his, and the setting itself can be turned back. GitHub notifies the reviewer of
     each run waiting for review (as his notification settings say), and a change to the setting is in the
     repository's log: a push becomes visible.
   - Survives his account being taken over: no; it only makes a push visible (and slower).
   - Cost: with a reviewer, every night waits for Noah's click on the run's page ("Review deployments"; both of
     nightly.yml's jobs, Sill for Mac and Sill for iPhone and iPad, use the environment); with a timer, every
     night publishes that much later (720 minutes: from about 21:17 UTC, plus the build).
   - In the web page: github.com/Saffsanity/sill → Settings → Environments → nightly. Under "Deployment
     protection rules": check "Required reviewers" and add Saffsanity, or check "Wait timer" and enter the
     minutes (720 for 12 hours), or both; uncheck "Allow administrators to bypass configured protection rules";
     leave "Deployment branches and tags" as it is (Selected branches and tags: main); Save protection rules.
   - Or, in Terminal.app (both a reviewer and 12 hours here; for a timer alone give `"reviewers": []`, for a
     reviewer alone `"wait_timer": 0`):
     ```
     gh api --method PUT repos/Saffsanity/sill/environments/nightly --input - <<< '{
       "wait_timer": 720,
       "prevent_self_review": false,
       "reviewers": [{"type": "User", "id": 19507835}],
       "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true},
       "can_admins_bypass": false
     }'
     ```
     19507835 is Saffsanity's user ID (`gh api repos/Saffsanity/sill --jq .owner.id`). The
     `deployment_branch_policy` line is today's, written out so the change keeps main as the only branch that
     may use the environment; `prevent_self_review` stays false, or Noah couldn't approve the runs he starts.
     This PUT may not take `can_admins_bypass` (whether GitHub's environment API accepts it there wasn't checked
     here: no API call is made from this branch); if it doesn't, the bypass stays on without a word. The check
     command below shows which: if it still says `"can_admins_bypass": true`, the web page's checkbox ("Allow
     administrators to bypass configured protection rules", unchecked) is the sure way.
     Check: `gh api repos/Saffsanity/sill/environments/nightly --jq '{can_admins_bypass, rules:
     [.protection_rules[] | {type, wait_timer, reviewers: [.reviewers[]?.reviewer.login]}]}'`. Undo: the same
     command with `"wait_timer": 0`, `"reviewers": []` and `"can_admins_bypass": true`.

3. **A cooling-off for nightlies from first sight (12 to 24 hours), with a nightly audit that lists each night's
   commit and the pull requests in it.** This revisits Noah's decision ("should download any update found
   immediately").
   - Stops: a bad night reaching a Mac by itself before that many hours after the Mac first found it (on its
     clock and on GitHub's, as a release's two days); within them, deleting `Sill-nightly.zip.manifest` from
     the pre-release `nightly` stops it on every Mac that hasn't installed it (each reads the manifest again
     before it downloads, and right before it installs by itself).
   - Doesn't stop: a bad night nobody notices within the wait (it buys time, not attention), Update Now (a
     person installs at once), or the one-job origin of both proofs.
   - Survives his account being taken over: the wait does, and only the wait. It lives in the Sills already
     installed, which no GitHub setting or push changes (even a first bad nightly that sets its own wait to 0
     waits the wait of the build before it). But stopping a nightly inside the wait means deleting its
     manifest on GitHub: an attacker who locks Noah out of the account leaves him no way to, and then the wait
     only delays the install (the fourth security pass).
   - Cost: nightlies install by themselves half a day to a day later. The wait is the one line
     `UpdateAutoPolicy.nightlyCoolingOff = 12 * 3600` (or 24) and a re-render of the previews. The notice is
     not built (a script on Noah's Mac beside `--audit`, a few hours of work), and to be worth having it must
     check five things for each night's `Sill-nightly.zip.manifest` (read by asset id, verified with the
     nightly key), as the fourth security pass sets them out:
     1. Where the commit came from, by something an agent with his GitHub token can't make: every commit since
        the last approved nightly signed with a key only he holds (an SSH or GPG key behind Touch ID or on a
        hardware key, its public half pinned on his Mac), or on a list he keeps. A list of pull requests alone
        can't tell his merges from an agent's.
     2. That nothing the build and the signing depend on changed unseen: `.github/workflows/`,
        `.github/actions/`, `Scripts/sign-nightly.sh`, `release.sh`, `make-app.sh`, `update-manifest.swift`,
        `Package.swift`, `Packaging/`; any change there named loudly.
     3. That the assets came from that commit's run: uploaded by github-actions[bot], in a successful
        nightly.yml run (scheduled or dispatched, on main) whose `head_sha` is the manifest's `commit`. This, not
        (1), catches a zip uploaded by a user (stolen secrets used outside GitHub) and a `commit` field that
        names a clean commit for a build of another.
     4. That GitHub's gates are as he left them: the `nightly` environment (its rules, branch policy and
        bypass), the rulesets, the collaborators, deploy keys and Actions permissions, against a baseline kept
        on his Mac.
     5. That it runs often enough inside the wait (hourly), notifies when it can't run, and gives the one
        command that pulls the night (delete `Sill-nightly.zip.manifest`).

     What it can't catch: a bad change he merged himself (reading it is his job); a build that isn't what its
     commit says, through a runner, toolchain or action at fault (there are no reproducible builds); anyone in
     control of his Mac, who controls the notice, the baseline and his signing prompts; a notice nobody reads
     within the wait (a night's sleep is most of 12 hours); Update Now clicks; a lockout from his account (he
     sees the notice, but can't pull the night); anything once a Mac has installed it.

4. **Keep the automatic update to releases, and offer a nightly to Update Now only.**
   - Stops: the path with nobody in the loop. A person clicks Update Now for each nightly, after seeing its
     version and build.
   - Doesn't stop: a person installing a bad nightly (nobody reviews it either), or the one-job origin of
     both proofs.
   - Survives his account being taken over: yes. It lives in the Sills already installed.
   - Cost: Noah's "download any update found immediately" for nightlies is gone; with "Automatically update
     Sill" on, a nightly is offered, never installed by itself. Not built (a change to `UpdateAutoPolicy.start`
     and the words; under an hour, and its checks).

The option Noah declined on 2026-11-12 ("A separate nightly key that GitHub holds seems like the best option"):
**sign each nightly on his Mac, with a key behind Touch ID as the update key is.** It restores two independent
proofs (Apple's notarization from CI, the nightly's signature from his Mac), and it survives the environment's
secrets leaving GitHub outright: no key is there. Against a push to main it holds only as far as what Noah checks
before each night's tap (the fifth security pass): CI still builds and notarizes a commit pushed to main, and a
routine tap signs it, so the notice's checks 1 to 3 above (where the commit came from, nothing the build depends on
changed unseen, the assets from that commit's run) belong in that step. Its cost is that tap and those checks each
night, with his Mac on and awake when the nightly is built; a night he doesn't sign has no nightly for Update Now.
Named here as the fourth security pass asked, not built.

The reviewer's verdicts (third pass): "Use nightly builds" alone, through Update Now: go, with the honest words
(done) and the ruleset on main (option 1). "Use nightly builds" with the automatic update: not yet; something
outside main's own code must stand between a push and the install (option 2 with the bypass off, or option 3),
or Noah accepts in so many words that every holder of his GitHub credentials, every agent session on this Mac
among them, can put code on every such Mac within a day. Setting the nightly key's secret: once
`can_admins_bypass` is off on `nightly`. The fourth pass: unchanged for the nightly with the automatic update (one
of option 2 with the bypass verified off, option 3 with a notice that checks the five things above, option 4, or
Noah's acceptance in so many words); for the secret, check the bypass with option 2's command after the change,
and use the web page's checkbox if the PUT left it on. Nothing in this branch changes a GitHub setting; the
commands above are for Noah to run or approve.
