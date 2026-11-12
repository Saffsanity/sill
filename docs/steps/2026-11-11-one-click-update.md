**Update Now, the one-click update of Sill for Mac (2026-11-11 and 12, branch `one-click-update` from main
at dd6ea6a, main at 936d627 (PR #349), 57a6d86 (PR #351) and a4bad80 (PR #353) merged in, not rebased; draft PR #354; the plan, its threat model point by point, the open questions with the default taken
for each, the gates and Noah's rehearsal are in `docs/one-click-update-plan.md`).** Noah, 2026-11-11: "make a
note that I want to make the Sill update checker also have a 1 click updater as a new feature", then "Start
working on ... one-click updater ... Use subagents." On 2026-11-12 he chose the second factor, quoting the
option: "Add an update key that only you hold... You sign each release with one command on your Mac after
it publishes. The key never goes near GitHub. Sill installs an update only if it carries both Apple's
signature and yours." (the plan's §10 Q1; his steps, §14). **Inert until Noah makes the update key:**
`UpdateManifest.releaseKeys` is empty on purpose, so no build from this branch shows Update Now; Settings and
the menu are what they were. Round 3 (2026-11-12): Noah, "the "2.4 of 5.9 MB" text to be below the
"Downloading Sill 0.4..." text. Also add a toggle for "Automatically update Sill" that works as intended.",
then "Add the update key language when applicable as well", and "Your defaults are correct for the new
updater features" (the plan's §15.1); the independent security review's findings (§12c) taken first.
- Two signatures, each necessary: Noah's update key (Ed25519, CryptoKit) over the release's manifest
  (`Sill.zip.manifest`: tag, version, build, size, SHA-256, each slice's cdhash; verified before the zip is
  fetched), because GitHub Actions holds the Developer ID identity (the `nightly` environment signs and
  notarizes with no reviewer, and its token can publish); and the code signature against a requirement
  compiled in (Apple's anchor, a Developer ID Application leaf of team 9B2KKVM937, me.saffer.sill.mac,
  `notarized`, measured: the SDK has no SecAssessment, and spctl follows Gatekeeper's settings), every slice,
  strict, with the running app's own designated requirement, the keychain entitlements, the hardened
  runtime and a stapled ticket. Version from the signed Info.plist, strictly newer than this bundle's own.
- The mechanism (`UpdateInstaller`): GitHub's hosts only (release-assets.githubusercontent.com after
  github.com, https, no credential, the manifest's size and SHA-256); Sill's own zip reader (`UpdateArchive`:
  central and local headers agree, printable ASCII names under Sill.app, no case duplicates, links only
  inside and never written through, no zip64, encryption or setuid, AppleDouble skipped) writing through
  directory descriptors with O_NOFOLLOW; checks in a 0700 item-replacement folder on Sill.app's volume; one
  `renamex_np(RENAME_SWAP)`, the staged copy checked again right before it (F5); every check again at
  /Applications with the same code; put back (only the old copy, by cdhash) on any failure. The relaunch:
  the new copy as a new instance waits for the old to quit (`AppUpdater.waitForOtherSill`, a contract for
  every later Sill, only for a genuine Sill: N7); the old starts the watcher (`/bin/sh` with
  `UpdateInstaller.watcherScript`, values as arguments) and quits from a run-loop Timer once the new one's
  running code is the code checked; the new tells the watcher once its host has been up 30 s (a token in
  Sill's Caches) and then removes the old copy, finding its folder by a note written before the swap
  (macOS's System Policy denies listing the temporary-items folder to apps, measured); without that word
  within 150 s the watcher stops the new one, puts the old copy back (only it, whole) and starts it. Refusals with words (`UpdateInstallPolicy.refusal`): a build that is not a notarized release,
  a test feed or version, translocated, a disk image, read-only or network volume, a link on the way, a
  folder this account can't change, a Sill.app another account owns (the last to install or update it), a
  copy changed since launch, another account's Sill or another Sill of this account, no room. A device connected asks first (by connection). Never a hook: two constants, and
  `Tests/checks/update-install` reads the sources.
- The release step: `Scripts/sign-update.sh v<version>` on Noah's Mac (never CI), with a signer installed
  once from files he read (`--install-signer`: built with the hardened runtime, F1; the trust it records,
  F2: the update keys, the pinned requirement, `Trust.release` and `Endpoints.github`, each release's
  source compared with it before signing), signing only a zip he knows without GitHub (his own
  `release.sh` output, or a release run he approved: `--expect-sha256` then, `--run` since the third pass); the key in his login keychain
  (`--new-key`, once) with one copy off the Mac (docs/release-checklist.md part 1 §7, part 2), and every
  signature with it confirmed by him in person (Touch ID or his password, the prompt showing the tag, the
  size and the whole SHA-256 in groups of eight, F4), so nothing running as him signs silently. The
  manifest carries the time it was signed (`signed …Z`). A stop (`Sill.zip.stop`, the signer's `stop`)
  names a release no Sill installs. The check stores
  `updateLatestSigned`: an unsigned release shows Open Release Page… alone, as before.
- An independent review of the code as written (a read-only subagent, 2026-11-12): twelve findings, all
  taken (the plan's §12a has each and its fix; the two high ones were in the signing step). A second one
  of the fixes after the first build: six, all taken (§12b): a late Cancel stranded an update; the signer
  could be run silently by anything running as Noah (now in person per signature); the put-back trusted a
  cdhash (now the old copy validated whole, a copy that failed its check moved off the path, only a whole
  old copy offered); device keys could repeat; the old copy went even when the host failed; a full disk
  could lose the note keeping it (now a rename).
- Automatically update Sill (the plan's §15; `UpdateAutoPolicy`, pure): a switch under "Check for updates
  automatically", off by default, shown only where Update Now is; kept with what it remembers in Sill's
  keychain group (`AutoUpdateStore`, data-protection, this device only), never the defaults, set only from
  Settings (`setAutomaticUpdate`). One state machine with Update Now (a `mode`, a `waiting` phase): after a
  check GitHub answered, Update Now's steps for a release this Sill first read at least 48 h ago (its own first
  read of the verified manifest, kept across launches, never before the signed time: the second pass's A1) and
  signed at most 120 days ago, never below the highest release whose app passed both checks here or a stopped
  one, two attempts a version at most (counted only once the release verified), 20 h apart; then a wait
  for 5 minutes with no device connected (Noah, 2026-11-12) and no pairing window, GitHub asked again, and in one step on the
  host's queue the hold of new sessions with the count of the connected ones
  (`StreamServer.holdNewSessions`; goodbye `restarting`, reconnect true), then the install. The download's
  size on a line of its own under "Downloading …" (`Pane.detail`); every line that names a check names
  Apple's or the update key's, and a build without a key names neither.
- Review 3 (the independent security review, `~/Downloads/sill-handoff/one-click-update/SECURITY-REVIEW.md`,
  on 38385a7; the plan's §12c): F1–F7 and N1–N8 each verified here and fixed or answered, each fix with the
  check that fails without it; the reviewer's seven points for an automatic updater met (§15.6).
- The second security pass (the same reviewer, on 312b514; the plan's §12d): A1 (high: the cooling-off
  counted from the manifest's own signed line, which whoever holds the key writes) now counts from this Sill's
  first read of the verified manifest, with a signing record and `sign-update.sh --audit` for Noah to notice a
  release he didn't sign (its daily LaunchAgent his choice); R1 (the app names its commit, `SillCommit`, and
  signing needs it and GitHub's tag to be the local tag's), R2 (the updater's changes since the last signed
  release shown), R3 (the leftover note before the last check), A2 (the floor only after both checks), A3
  (attempts only on verified releases, the memory bounded, an unreadable item never "nothing remembered"),
  W1 (the watcher checks the copy after its moves, its note a new file renamed into place), W2 (notes read as
  small regular files without waiting, the launch's off the main actor, the started note a file named with the
  token), G1 (Install Now on a waiting copy asks GitHub again); N9 answered (a wrong clock no longer costs
  attempts; a quit during the install step leaves the new copy unstarted; the switch's and the footnote's
  words). Each verified first, each fix with a check that fails without it.
- Use nightly builds (the plan's §16; Noah, 2026-11-12: "can you add a toggle to Use Nightly Builds? That in
  tandem with automatic updates should download any update found immediately instead of 48 hours out", and
  "A separate nightly key that GitHub holds seems like the best option"): a switch under Automatically update
  Sill, off by default, shown only with Update Now and a nightly key compiled in (`UpdateManifest.nightlyKeys`,
  empty on purpose). The nightly key is a GitHub secret of the environment `nightly`
  (`SILL_NIGHTLY_UPDATE_KEY`), used by nightly.yml's "Sign the nightly for Update Now" (`Scripts/sign-nightly.sh`;
  green and silent without it); its manifests have their own first line ("Sill nightly 1") and key list, so
  neither key or format ever crosses over (T35, T36), and a key in both lists is trusted for neither nightly.
  The offer comes from the verified manifest alone (version, build, commit; GitHub's title never read); the
  order is a release's by version alone, a nightly's by version, then build (`isNewer`, `chooseOffer`: a tie goes
  to the release; the release of a nightly's own version is never offered, as the update check never has, since
  main keeps a version before and after its release); the automatic update installs nightlies with no
  cooling-off, 30 days at most, above a nightly floor raised only after both checks, attempts by build. T38
  says plainly what stands between the nightly channel and every Mac with both switches on: only the next
  night's build and the watcher. Device impact: none (the wire is the release's). Noah's one-time steps:
  §16.8 and the checklist's Nightlies.
- The third security pass (the same reviewer, on b69429ed; the plan's §12e; each finding confirmed against its
  proof first, none unreal). NB1 (high, a design finding: on the nightly channel both proofs are one GitHub
  job's, so any push to main reaches every Mac with both switches on within about a day) is Noah's to decide
  and is not decided: the plan's §16.10 has the reviewer's four options (a ruleset on main; `can_admins_bypass`
  off with a wait timer or a required reviewer on `nightly`; a 12 to 24 hour cooling-off for nightlies with a
  nightly audit; the automatic update for releases only), what each stops and doesn't, which survive his account
  being taken over (the last two: they live in the installed Sills) and which only make a push visible (the
  settings), and the exact web steps and `gh api` commands for the two settings, none run. Done whatever he
  answers: the switch's words say what a nightly trusts ("Nightly builds are built and signed by GitHub from
  Sill's newest code; nobody looks at them first."), and the nightly's wait is one constant,
  `UpdateAutoPolicy.nightlyCoolingOff`, 0 today, its words derived from it, checked at 0 and at 12 hours.
  AU1 (medium): the audit reads every release carrying a manifest, drafts and pre-releases too, and with
  `--notify` notifies whenever it couldn't run; its LaunchAgent every four hours from when it is loaded; Sill's
  wait counts from the later of the first sight and `published_at`; §15.4 says the record and the audit guard
  against a key leaked off this Mac, not against someone in control of it. CL1 (low): the wait counts on
  GitHub's clock too (the `Date` of its HTTPS answers; none read as a wait, never a go). W3 (low): a failed
  final check of the watcher's leaves the new copy at Sill's path, not started, with a `kept` note Sill shows;
  `whole` refuses a file with two names. R1′: `sign-update.sh --run ID` signs a CI-built release only when
  GitHub's record of the run names the local tag's commit, from the run's artifact (release.yml keeps the zip
  30 days); `--expect-sha256` is gone. R2: the four files that steer the updater are in its diff, and `--yes`
  never answers that question. N10: a key in both lists trusted for neither by the code (a); a nightly never
  signed as a release (e); both switches held back on a failed write (g); the watcher's token in `ps` accepted
  and said (j); failure words cut by UTF-8 bytes (k); stops by version and SHA-256 (l);
  `SILL_SIGN_TEST_BUILT_FROM` only with the tests' key, `UpdateManifest.testKeySeed`, which no Sill trusts (m);
  the footnote's "each time Sill opens" (n), and a launch now reads the nightly only while the daily check is on
  (found while fixing n; the privacy page says when Sill asks); (b), (c), (d), (f) and (i) answered in §12e.
- Verified (2026-11-12, this Mac, macOS 27.2 and Xcode 27.1, no device involved, every heavy job through
  heavy.sh; the plan's Progress): `Tests/checks/update-install` 480 checks and its 60 mutants (all 60 on the
  code before the owner refusal, 60 of 60; the refusal's four again after it, 4 of 4); `update-policy` 129;
  `Tests/update-harness/run.sh` 174 of 174 (installs, put-backs, each hostile case refused with the
  installed copy unchanged, a bundle held across the swap reading the old version while Security reads the
  new, the genuine v0.6.1 under `Trust.release` with codesign's CDHash equal to Security's on both slices)
  and its 12 mechanism mutants, 12 of 12; `sign-test.sh` all 14 steps; `swift build -c release` clean
  but the known CaptureProbe warning; previews from the bare SillMenuBar identical to main's (936d627) but
  the 36 new pane-update-now files and menu.txt's appended samples; CI's Build and check green on df36dc2
  and be7e41b (run-all's 67 checks, the iOS build, no AppUpdater warning). Found on the way: macOS's System Policy denies listing the
  temporary-items folder (the clean-up now goes by a note), the low-space rounding's overflow, and a
  freshly started ad hoc app held unwritable by the system policy for a moment (harness only).
- Verified, round 3 (2026-11-12 04:40–05:20, this Mac, heavy jobs through heavy.sh, no device, nothing
  launched but the harness's test executables and the bare SillMenuBar for previews): `update-install` 716
  checks (the date, the stop, the automatic rule, both modes, the words, the reviewer's F6 cases, the source
  rules for the switch); `update-policy` 129; `Tests/update-harness/run.sh` 227 of 227 (the stop's four
  cases, link-through-link, the check right before the swap, a hard link, the watcher's six: a new copy that
  proves itself stays, one that quits at once, one that never proves itself and one that writes another
  token are put back and the old copy started, an old copy changed while it waited is never put back, and
  a process that isn't the new copy is never stopped); `sign-test.sh` all passed (F1's runtime and
  DYLD_INSERT_LIBRARIES marker, F2's four refusals and the comment-only change, the signed time, a stop
  signed and verified, F3's words); `swift build -c release` clean but the CaptureProbe warning; previews
  from the bare SillMenuBar against main's (0d22bbf) rendered in the same run: 161 identical, the General
  pane's four only by the "Running from" path, menu.txt's appended samples, 126 new pane-update-now files
  (`~/Downloads/sill-handoff/one-click-update/previews/`); `update-install`'s mutants 82 of 82 (22 new: the prompt's digest, the date, the stop's signature and carriage returns, the cooling-off, the age and clock limits, the rollback floor, attempts, the daily check, the update key, a device or a pairing window at the quiet moment, the automatic mode never asking, a device that joined cut off, Install Now when refused; three caught by a trap in the check, as one was before); the harness's 13 round-3 mutants, 13 of 13 (the stop's two, the watcher's six, the check right before the swap, the note before it, hard links, a link at the signature's file, any Sill waited for; "a stop ignored" first left an empty `case` that didn't compile, fixed and run alone), its twelve older ones' patterns still applying once (not re-run); CI's Build and check green on 623e534. Found on the way: the
  watcher read no CDHash (`codesign -d -v` prints none; now `-vvv --arch`), a SIGPIPE race under pipefail
  in sign-update.sh's `codesign | grep -q` and `spctl | grep -q`, `Process.waitUntilExit` hanging after a
  hop in the harness, and macOS's SwiftUI forms have no Dynamic Type (the larger-text previews set 17 pt).
- Verified, round 4 (2026-11-12 06:50–10:37, this Mac, heavy jobs through heavy.sh, no device, nothing launched
  but the harness's test executables and the bare SillMenuBar for previews). The 5 minutes (aa8ee628):
  `update-install` 718, its 85 mutants 85 of 85 on an export of the commit, the harness 227 of 227, previews. The
  second pass (b6486d0b, on an export of the commit): `update-install` 766 of 766, the harness 265 of 265 (38 new:
  the staged copy changed when the leftover note appears, a link planted at the restored note, the note landing in
  the put-back copy, the old copy replaced by a link, a FIFO, a link and a 5,000-byte file where a note goes, a
  FIFO and a link at the started note), `sign-test.sh` all passed (the signing record, the audit's alarm and its
  notification, R1's three refusals and an annotated tag read through, R2's diff), `swift build -c release`; CI's
  Build and check green on b6486d0b. Use nightly builds (2f096747): `update-install` 833 of 833 (67 new: the
  nightly format and its separation both ways, the order, what Update Now offers, the downloaded app's order by
  channel, the listing and its pair, the nightly rule, the switch's and the offer's words, the source rules);
  `swift build -c release` with no warning from the changed files; the harness 277 of 277 (a nightly feed on the
  stand-in: offered from its manifest and installed through the same steps, T35, T36 both ways, T37's
  half-published pair, an older nightly, one moved on since the offer, one not signed yet, no pre-release);
  `sign-test.sh` all passed (62 steps: the nightly key in a file only, its separation from the update key both
  ways, sign-nightly.sh signing tonight's zip and refusing a release's app, another commit's and a key the commit
  doesn't carry, --new-key's mode 0600 and its clean-up); the mutants on an export of 2f096747, the second pass's
  and the nightly's among them: `update-install` 116 of 116 (115 on that export; the 116th, the nightly floor's,
  was written so it couldn't compile: fixed, and caught on an export of 2929da1e), the harness 16 of 16 (the
  second pass's eleven and the nightly's five); previews from the bare SillMenuBar, 319 files (against the round
  before, aa8ee628's: the second pass's words in the 39 automatic-update renderings, 27 new, 6 the second pass's
  and 21 the nightly's, the rest identical; in the handoff's previews/); CI's Build and check green on 2f096747.
  Found on the way, each fixed before the first build: the design's "release V offered to nightly V" (main keeps a
  version before and after its release, so nightly users would have seen an older release offered for weeks, then
  refused); nightly.yml red between the secret and the compiled key (now green, signing nothing); `sign-nightly.sh
  --new-key`'s exec, which skipped the trap and left the compiled signer in TMPDIR (shown before and after: the
  old script left its sill-nightly-sign folder there, the fix nothing). From the previews, then fixed (2929da1e):
  with nightlies on, the footnote still said every new version waits two days and is signed with the update key;
  it now names the nightly key and the missing wait (update-install 836 of 836, the build, the harness 277 of 277;
  only the six nightly-on samples' renderings changed).
- Verified, round 5 (2026-11-12 11:50–13:32, this Mac, heavy jobs through heavy.sh, no device, nothing launched but
  the harness's test executables and the bare SillMenuBar for previews), on cd9eaaa3 (the worktree's run is the
  commit's; the mutants on an export of it), then f9a962d4 (two check rules and the signing test's R2 list, no app
  source): `update-install` 903 of 903 (67 new), 904 on f9a962d4; `swift build -c release`, no
  warning; the harness 288 of 288 (11 new: GitHub's clock and `published_at` read from the stand-in's answers, a
  fixed date word for word, none and "yesterday" read as none; a stop naming the release's version in another
  form; the watcher keeping the new copy at Sill's path when the put-back copy fails its last check, and refusing
  an old copy with a file of two names); `sign-test.sh` all 83 steps (21 new: `--run` and its seven refusals, the
  audit naming a release outside the record as a draft, a pre-release and published with a notification each,
  a notification when `gh` can't list, `--yes` never answering the updater's question, the four steering files in
  its list, a nightly never signed as a release, `SILL_SIGN_TEST_BUILT_FROM` refused with another key);
  `repo-rules` 10 of 10. The mutants on an export of cd9eaaa3: `update-install` 139 of 141 (25 new); the two left
  were holes in the check's source rules, not in the code (fetch's GitHub clock without the publication, which
  no rule pinned; `if false,` before the kept branch, past a rule that looked only for its two strings): rules for
  both in f9a962d4, and on its export those two and a new one (this Mac's clock taken for GitHub's) 3 of 3; the
  harness's new and moved ones 7 of 7 (W3's two, N10 l's, CL1's two, "a stop ignored" and W1's, moved), its 34
  others' patterns still applying once (not re-run). `sign-test.sh` against b69429ed's `sign-update.sh`: 20
  failed, each a round-5 case (N10 m and the record it then wrote, R1′'s three, AU1's nine with the audit's new
  words, R2's six, N10 e). Previews from the bare SillMenuBar, 319: 301 identical to round 4's, 18 changed (the
  five nightly-on samples' note and footnote; and auto-stopped's three, whose stop, recorded as v0.4.0 for an
  offered v0.4, round 4 matched by text and so showed the cooling-off's words: matched by version now, N10 l, it
  shows the stop's); in the handoff's previews/ with COMPARE-round5.txt. CI's Build and check green on cd9eaaa3.
  Found on the way: the
  check's T36 rule and two of the signing test's audit lines still named the old words (fixed before the commit);
  while fixing N10 n, that a launch read the nightly pre-release with "Check for updates automatically" off
  (fixed, with a check and a mutant); and §16.10's `gh api` commands, first written as indented heredocs whose
  terminator a copy from the page would break, are here-strings now (run with a stand-in `gh` that only parses
  the bodies, in zsh and bash; nothing sent to GitHub).
- **Untested, for Noah:** the plan's §12 rehearsal with a throwaway repository and key (two notarized
  builds); the first real Update Now (a release carrying the key installed by hand first); §14's three
  step lists (once: the signer, the key, its backup; once: the public key into `releaseKeys`, a commit of
  its own; every release: `sign-update.sh` after publishing). Open: §10 Q2 ask before disconnecting, Q3
  refuse while the other account's Sill runs (with what he sees), Q4 the menu item opens Settings. The
  automatic update's steps (the plan's §15.8, A1–A9: the switch, its keeping, a quiet install with the
  iPad trying to connect during the hold, the watcher's put-back of a release that quits at launch and its
  renames in /Applications under App Management, a stop, a quit during an install step, VoiceOver), and
  its open questions 14 and 16–23 with their defaults (Noah decided 13 and 15 on 2026-11-12: "48 hour wait
  seems ok, can the 10 minute wait be shortened to 5 minutes?"; the stop,
  two attempts a day apart, 120 days, the watcher's 30 s and 150 s, GitHub asked again before the swap,
  the "restarting" goodbye, the keychain group for the switch, a day's wait at most, Check Now included).
  From the second and third passes: the audit (`sign-update.sh --audit` by hand after a release, a pre-release
  and a draft among GitHub's releases; the LaunchAgent if he wants it every four hours, and its notification
  when `gh`'s login has expired), a release built by the release workflow signed with `--run` (GitHub's record
  of the run against his tag, the zip from its artifact: only ever run against the stand-in here), and the
  first sight's wait on a real release (the pane's "… or later" date two days after the first daily check that
  read it, on GitHub's clock too). Use nightly builds: NB1's decision first (the plan's §16.10: which of the
  four options, and `nightlyCoolingOff`), then the nightly key's four steps (the plan's §16.8; the reviewer:
  the secret once `can_admins_bypass` is off on `nightly`), then a nightly run that ends "Signed for Update
  Now", the switch on a Mac with that build (the offer names the build; Update Now installs it; with
  Automatically update Sill on, it installs within the next check and 5 quiet minutes), the switch off on a
  nightly (no downgrade, its note), and the plan's §16.9 defaults.
