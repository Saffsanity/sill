# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Current step

**The Mac's pointer on the device (2026-09-26/27, branch `pointer-visibility`
from main at 8b0d418, merged with main at cf05a78 in b6f57d0 and at 676b362
in e7307e6, not rebased; the plan and the results, host, device and the
review's fixes, are in `docs/pointer-visibility-plan.md`).** Noah: "When the
Mac is controlling the mouse pointer, it should show the real mouse pointer
on the desktop on Sill. When Sill is controlling the Mac, continue to hide
the real pointer and only render the client side one in portrait mode when
the trackpad is used" (2026-09-25); the plan's defaults, but Q4: the pointer
is sampled at the stream's frame rate while it moves. Built, reviewed and
checked; the pull request waits on Noah's device tests (P1–P12, below).
- Wire: kind 26 `macPointer`, host → device, JSON `MacPointer`
  (`Pointer.swift`): where the Mac's pointer is in the streamed frame (`x`,
  `y` as fractions to 4 places, left out off the stream), `inside`, and `seen`,
  the input messages (kind 8) the host had read on that connection, so a device
  drops a report built before the host read its latest input. Every field
  optional; older readers skip 26. 24, 25 and 27 stay held for the Mac menu bar.
- Host: one controller, the Mac or the device whose input the host read last
  (`PointerControl`, pure). Any kind 8 hands the pointer to its device; a
  pointer or scroll input, and Sill's own post or warp (noted just before it),
  open a 0.25 s settle; a read 0.5 pt or more from the last position that
  counted, outside the settle, is the Mac's (a slow drag adds up, jitter never
  does); a read more than 0.25 s after the one before starts afresh.
  `PointerWatch` reads `CGEvent(source: nil).location` (no permission; a
  sample takes about 0.2 µs) at each 30 ms link tick, and at the stream's frame
  rate while the pointer moves over the source and some device is sent it,
  when that is more often than the tick (`PointerWatch.samplerInterval`: off
  the source every device hears the same `inside: false`, and at 33 fps and
  below the tick samples as often); it judges the read against the streamed
  source (the Desktop's display, a staged window's crop or full-screen band, a
  regular-mode window's bounds and on-screen flag, re-read on `sill.pointer` at
  most every 0.1 s after a move while some device is sent the pointer, and
  every 2 s anyway), inside meaning 0 ≤ x < 1 and 0 ≤ y < 1 (the far edges are
  the next display's), and reads nothing while nothing streams. StreamServer
  sends kind 26, only when it changed, to every device but the one driving, as
  it sends ticks (not counted in `inflight`; it stands in for that device's
  tick). No line prints; `ptr.sent` and `ptr.mac` join the `[1s]` lines when
  they happen. A synthetic host never reads the real pointer and never posts
  input (`in.dry` instead, InputInjector's dry run, and no activation or
  raise), and has a pointer only with the TEST ONLY `SILL_TEST_POINTER_PATH`;
  `SILL_TEST_SOFTWARE_ENCODER=1` keeps a synthetic host off the hardware
  encoder for good, and `SILL_TEST_LOOPBACK=1` puts both its doors on
  127.0.0.1 alone (Build and run).
- Device: one sprite (`HEVCDisplayView.setPointer`, in the Mac's shape from
  kind 14) shows what `PointerPresence` (pure) says. Kind 26 is judged on the
  network queue, where input is sent and counted (`PointerFeed`): stale when
  its `seen` is below SessionLink's `inputsOnSession` or a coalesced move
  waits; during a hand-over's carry-over (a move to a new connection while
  this device had the pointer, until its first input there) a report of this
  device's own position is dropped; else the Mac has the pointer, and its
  arrow shows where the report says, in every layout, drawn whatever
  connection carries the session by then. Every input this device sends gives
  the pointer back to it: its own arrow then shows only for the portrait
  trackpad (`setOwnPointer(_:from: .trackpad)`), never in landscape, never for
  a finger, typing, a key or the iPad's own pointer, and not for the Pencil
  unless Q2's flip (`pencilShowsPointer`). A key of the portrait key row keeps
  what shows (`sendFromKeyRow`: the Mac's arrow stays where it is, as this
  device's own). The pad's cursor is `PadCursor`: a stroke's first finger
  starts at the anchor (the newer of the Mac's last position and this device's
  last pointer event), and before any move, click, long press or scroll it
  carries on from the anchor again whenever the Mac or another device took the
  pointer, or moved it on, since the pad last looked (`reseeds`), so a finger
  resting while the Mac's mouse moves carries on from the Mac's pointer
  whichever of the two had it when the finger landed. The layout reaches the
  client (`DuoLayout.isPortrait`); nothing shows while nothing streams. Q1's
  linger timer is built and idle. DEBUG `-SillInputScript` runs only against
  a test host on this Mac (a loopback address and no `hostVersion`).
- Review (2026-09-27, the plan's "Review fixes"): eight findings, each
  reproduced before it was fixed (the seventh, a race, from the code and the
  pure model): the frame-rate sampler ran with the pointer off the source (120
  reads and 140 wakeups a second at 120 fps, nothing sent) and, below 33 fps,
  sampled less often than the tick; a regular-mode window was re-read 8.6
  times a second while one device drove alone; the column at maxX and the row
  at maxY read as inside; a finger that landed while the Mac had the pointer
  and rested while it moved on pulled it back to where it landed (P3's second
  order); a report landing just before a move's hand-over was never drawn;
  `-SillInputScript` would have sent input to any host a session reached,
  Sill.app included; a stale comment.
- Verified (the plan's Results and "Review fixes"): `swift build -c release`;
  iOS Debug and Release for the simulator and Debug for a device (only the old
  `StreamClient` capture warning); `Tests/checks/run-all.sh`, all 19 on the
  merge, and the pointer checks' mutants (pointer-control 152 checks and 33 of
  33, pointer-presence 165 and 43 of 43, pointer-watch 132 and 40 of 40; the
  452 of the device step's run before the review); the review's harness (the
  real StreamServer and PointerWatch, loopback only, a scripted pointer) against
  98d2860's: off the source 33 reads a second instead of 120, back over it the
  first report within a tick (2.7–24 ms), 30 ms apart at 24 and 30 fps, 0.6
  window re-reads a second with one device driving and 8.6 with a watcher, and
  three integration mutants of StreamServer's call each bringing one back; the
  host's synthetic gates on loopback-only hosts (H4–H9, H13, the remote door,
  new ones for the edge and for 24 and 30 fps) and, with no device connected
  to Sill.app, H2 against the host step's base logs and the sampler at 120 fps
  (8.0 ms apart); S1's 40 photos; live on a simulator of its own, 51 of 51 on
  the merge: S2–S7 as before (S5 across the move from AWDL) and S2b and S2c
  (the finger landing while the Mac has the pointer, the Mac's mouse moving it
  on, then a move and a click from where it went) and S8 (the input script
  refused against a host that says it is Sill, run by 127.0.0.1, ::1 and
  localhost against one that does not); H12, the bare app's 100 previews
  identical to main's. Not run: S5's moves to the cable and back to Wi-Fi
  (they need a host on this Mac's own Wi-Fi and cable addresses, and test hosts
  listen on loopback only now), the hand-over race live, anything on a device.
- **Untested, for Noah:** everything on the devices, the plan's P1–P12: the
  Desktop in landscape (move the Mac's mouse: the arrow on the iPad where it
  is, in its shape, following within about a tick; stop: it stays; tap the
  iPad: gone; move again: back; to another display and back: gone at the
  edge, back within a tick); a window in regular mode (shown over it, gone off
  it, still over a window covering it, gone minimized); portrait (the
  trackpad's arrow starts where the Mac's was, no jump on the Mac; lift: it
  stays; the Mac's mouse: the arrow jumps to it; a finger resting on the pad
  while the Mac's mouse moves, then moving or tapping: it carries on from the
  Mac's pointer, both when the finger came down after the iPad drove and when
  it came down while the Mac already had the pointer); rotation (the pad's
  arrow gone in landscape, the Mac's shown in both); typing and hardware keys
  hide the portrait arrow, the key row does not; the Pencil draws none; the
  virtual display (the arrow over the staged window, a full-screen video's
  band); remote (the arrow trails by about the round trip, `net.dropped` no
  higher while the mouse moves); two devices (the iPhone shows the arrow the
  iPad's trackpad moves); mixed builds (this iPad against PR #13's Sill.app: no
  Mac arrow; PR #13's iPad against this Sill.app: as before); five minutes on
  a still window (Sill.app's CPU as before, frame age and rtt unchanged,
  `ptr.sent` only in seconds the mouse moved over the stream, the arrow never
  choppy enough to want Q4 undone); moves keep the device's control
  (streaming in landscape, tap, plug the cable in and later pull it: no arrow
  at either move; move the Mac's mouse: it shows).

**The Mac download in a disk image (2026-09-27, branch `mac-dmg` from main at
cf05a78, PR #29).** Noah: "Sill should open in a .dmg and be draggable into
applications folder like regular apps". `Scripts/release.sh` now makes
`Sill.dmg` beside `Sill.zip`, from the same notarized, stapled app. Nothing was
notarized, published or tagged, and the download page still links the zip.
- The image (`Scripts/make-dmg.sh`, Layout): Sill.app, a link to
  /Applications, a white background with an arrow from one to the other
  (`design/DMGBackground.svg`, 660 x 400 points, the arrow in the app icon's
  greys, "To install Sill, drag it to Applications." under them), and the
  app's icon as the volume's. Its window: 660 x 432 points at (200, 120), the
  picture and macOS 27's 32-point title bar, icon view, no toolbar, sidebar,
  path or status bar, 128-point icons at (170, 180) and (490, 180). HFS+ and
  ULFO (LZFSE, read-only): the script's header says why, and why not APFS.
  The window is a `.DS_Store` that `Scripts/dmg-layout` (Swift: Foundation,
  ImageIO) writes with no Finder and no AppleScript, in Finder's own layout:
  re-encoding the records of a Finder-made installer image's `.DS_Store`
  (2023) gives its header, DSDB's five words, its leaf and the used part of
  its root block byte for byte (only the stale bytes Finder leaves in unused
  space differ, the 12 after DSDB's five words among them), and Claude's image
  of September 2026 has the same blocks, free lists and header. The
  background's alias is Finder's form (tags 0, 16, 17, 1, 2, 14, 15, 18 and
  19; tag 20, the build folder's image, left out), and CoreFoundation
  resolves it to the picture on the mounted image. `Tests/checks/dmg-layout`
  checks the writer (Layout).
- release.sh: `make-dmg.sh --prepare` right after the build (the layout tool
  and the background, so a problem with either stops the run before anything
  goes to Apple); a real run, after the zip's checks, makes the image of the
  stapled app, signs it with the same identity, sends it to Apple on its own
  (`notarize`, the zip's code as a function; its answer and log
  `.build/Sill-<version>-dmg-notary*`), staples it and checks it
  (`check_disk_image`: hdiutil verify, stapler validate, spctl's open context
  as "Notarized Developer ID", mounted `-nobrowse` in `$TMPDIR` with the
  Sill.app inside through `check_gatekeeper`, detached on failure too); it
  prints both SHA-256s, and `--publish` uploads Sill.dmg, Sill.dmg.sha256,
  Sill.zip and Sill.zip.sha256, the notes naming both hashes. A dry run makes
  the image from the app before stapling, signed with the identity.
- The zip stays in every release for now; the download page moves to the
  image only once a release carries it: docs/release-checklist.md, part 2
  (the release first, the link checked, then the page, then the site
  republished), and the page's new lines wait in a comment above its card in
  `site/download.html`. The release workflow's verify job makes
  `Sill-<version>-adhoc.dmg` (`make-dmg.sh --sign -`) and keeps it as a second
  artifact; the publish job keeps both submissions' answers and logs as the
  artifact `notary-v<version>`.
- Review fixes (2026-09-27; one review of the branch, each finding checked
  here before it was fixed):
  - The window was 4 points too short on macOS 27. Its WindowBounds was
    {{200, 120}, {660, 428}}, 400 and a 28-point title bar, but AppKit on this
    Mac (macOS 27.0, 26A428; Finder records the same SDK) gives a titled
    window a 32-point bar: `NSWindow.frameRect(forContentRect:)` makes 660 x
    400 a 660 x 432 frame, and a 428-point frame keeps 396 points. (Another
    project, on macOS 27, captured Finder opening a 660 x 432 WindowBounds as
    a 660 x 432 frame, the picture anchored at the top.) Now 432
    (`DMGLayout.titleBar` 32). Under macOS 14's and 15's 28-point bar (not
    measured here) that leaves 4 points below the picture, so the picture is
    white to every edge (it faded to #f2f3f5 at the bottom) and so is the
    view's backgroundColor (make-dmg.sh's `edge`). DMGLayout's comment had
    Finder-made images adding the title bar; the Finder-made one of 2023 has
    WindowBounds 512 x 400 for its 512 x 400 picture (Claude.dmg's tool adds
    22, the bar before macOS 11: 444 for a 422 picture).
  - The publish job's notary logs were never kept. The pinned upload-artifact
    (v7.0.1) skips every file and folder whose name starts with a dot, the
    search's root included, unless `include-hidden-files` is true, so
    `.build/Sill-*-notary*` found nothing and the step passed without an
    artifact, on main as well (the zip's log). Now `include-hidden-files:
    true` and `if-no-files-found: warn`. Checked with the action's own
    `dist/upload/index.js` under node, the step's inputs read from the YAML,
    in a workspace holding the four notary files beside the zip and the
    image: before, "No files were found"; now "there will be 4 files
    uploaded", and a warning when there are none. The verify job's two
    uploads name their file and were always found.
  - The writer's checks lived in the session's scratchpad: now
    `Tests/checks/dmg-layout` (Layout), 70 checks and 43 of 43 mutants (the
    28-point bar among them), in `run-all.sh`, CI and CI's mutants matrix
    (fifteen jobs). It holds the allocator to the Finder-made file (its
    10,244 bytes, header bytes, blocks and free lists, compared again here
    with the scratch tests' own reader), and fails when make-dmg.sh's layout
    arguments (the script sourced) or the SVG's size and white fill move
    without it.
- Verified after the fixes (2026-09-27, 03:13-03:17): the rehearsal again,
  `SILL_SIGN_IDENTITY='Developer ID Application: NOAH WILLIAM SAFFER
  (9B2KKVM937)' Scripts/release.sh --dry-run`, exit 0 in 17 s (the build
  cached, the layout tool compiled) with no keychain prompt: Sill-0.3.0.dmg
  2.9 MB (the zip 2.8 MB, the app 6.0 MB), UDIF read-only compressed (lzfse),
  its CRC32 valid, signed by that identity with a timestamp, identifier
  me.saffer.sill.dmg; `spctl -a -vv -t open --context
  context:primary-signature` rejects it as "Unnotarized Developer ID", which
  notarization changes. Mounted: an HFS+ volume "Sill", 21.0 MB with 6.3 MB
  used, exactly the five items, Applications a link to /Applications, the
  custom-icon flag, .VolumeIcon.icns the app's, the TIFF 660x400 at 72 dpi
  and 1320x800 at 144, white at every corner and edge in both, the
  `.DS_Store` read back by the tool and by the scratch tests' own decoder
  (10,244 bytes in Finder's blocks, bounds {{200, 120}, {660, 432}}, the
  view's colour white, the icons' places, the alias's IDs the folder's and
  the file's), the alias resolving to the picture on that mount, and Sill.app
  byte for byte `.build/Sill.app`, passing codesign --deep --strict (the
  image stays there for Noah's look). `Tests/checks/run-all.sh`, all 16
  (130 s), and `dmg-layout --mutants`, 43 of 43. In the session's scratchpad
  (`mac-dmg/tests`, removed at the end): make-dmg.sh for real (hdiutil,
  codesign ad hoc) against a fake app, 101 checks (the build's 97 with the
  edges' white and the view's colour) and 26 of 26 mutants (the build's 24,
  now the 28-point bar where it had 22, and a grey edge and a grey picture),
  no image left attached; release.sh's 169 checks and publish_release's 13
  again (release.sh has not changed since the build); both workflows parse,
  their actions pinned, every run block parsing under /bin/bash 3.2.
  Earlier, the build's run before the review: release.sh against stand-ins,
  169 checks (PR #18's 101 and 68 for the image: every step's order, the image
  made once from the stapled app, both submissions, the four assets with their
  checksum files, every failure stopping before anything is published, the
  mount detached, also when it holds no HFS+ volume, a busy attach tried
  again) and 38 of 38 mutants; publish_release with the real gh against a
  stand-in GitHub API (the four uploads with their names and sizes, the
  notes), 13 checks.
- **Untested, for Noah:** a real release (two notarizations, the image's
  staple, spctl's "Notarized Developer ID" for it, `--publish`'s four assets,
  the `notary-v<version>` artifact on a signed run); the window in the Finder
  on macOS 27 (the whole picture, a scroll settles back, the names under the
  icons readable in Dark Mode on the white picture, the volume icon): the
  checklist's part 1 §2 has the look; on macOS 14 or 15, the 4 points of white
  below the picture; the image on another Mac (downloaded, so quarantined: it
  opens, the drag, Sill opens, also offline); the verify job on GitHub
  (hdiutil and Quick Look on the runner); the page's move.
- Known: files written from a Claude session carry `com.apple.provenance`,
  which `xattr -d` can't remove, so the rehearsal image's files carry it
  (Claude.dmg's have none); the zip has always carried the same attributes in
  its AppleDouble entries. Not changed here.

**TestFlight tooling (2026-09-26, branch `testflight-tooling` from main at
150f781).** Noah: "help me do the 4 opens for TestFlight" (the App Store
Connect record, screenshots, the 0.5 archive and upload, the placeholder and
the site). This branch makes those minutes of work: the upload tooling and
the record field by field. Nothing was uploaded and no record was created.
- `Scripts/release-ios.sh` (Layout): archive (Release, generic/platform=iOS,
  automatic signing, `-allowProvisioningUpdates`), export with
  `Packaging/ExportOptions-appstore.plist` (app-store-connect, team
  9B2KKVM937, automatic, destination export, `manageAppVersionAndBuildNumber`
  NO), the .ipa unpacked and checked, and with `--upload` a second export
  whose destination is upload. `--bump` (a clean tree; `CURRENT_PROJECT_VERSION`
  + 1 in both configurations, committed alone), `--api-key`/`--api-issuer`
  (`--api-key-id`; an App Store Connect key instead of Xcode's account,
  refused inside the repository, only its path given to xcodebuild),
  `--sign-at-export` (the archive unsigned, the export signs), `--unsigned`
  (CI without the key), `--print-version`, `--privacy-report` (xcodebuild
  has no command for the report: the manifests, the required-reason APIs the
  binary imports or calls, and the Organizer's way to the PDF). Refuses any
  Xcode but 27; one line per step, xcodebuild's output in `.build/ios/*.log`.
- Signing, as the rehearsal found it (2026-09-26): the first export made a
  cloud-managed Apple Distribution certificate (a POST for
  DISTRIBUTION_MANAGED; "Apple Distribution: NOAH WILLIAM SAFFER
  (9B2KKVM937)", until 2027-09-26; no private key in the keychain) and the
  profile "iOS Team Store Provisioning Profile: me.saffer.sill" (until
  2027-09-26); the App ID is Xcode's "XC me saffer sill". An archive made
  with `CODE_SIGNING_ALLOWED=NO` exports the same way with the same
  entitlements, so CI needs no certificate or profile, only an App Store
  Connect key with the Admin role (cloud signing refuses others). Uploading
  takes Account Holder, Admin, App Manager or Developer, but every export
  signs, so the notary key (Developer) can't run the script.
- `.github/workflows/testflight.yml` (Layout): by hand only. Without the key
  `--unsigned` and that .ipa as the artifact; with the secrets
  `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID` and
  `SILL_TESTFLIGHT_KEY_P8`, `--sign-at-export` and the signed .ipa; with the
  variable `SILL_TESTFLIGHT_IN_CI` true too, `--upload`.
- docs/release-checklist.md, "TestFlight": the record field by field (§1),
  the App Store address (§2), the site (§3: sill-site holds main's `site/`
  but for download.html, kept at "being prepared" on purpose, so TestFlight
  needs no republish; a later one leaves out download.html, `.nojekyll` and
  `.github`), the build (§4),
  internal testers (§5), Test Information with a beta description (§6),
  external testers and Beta App Review (§7), the screenshot session (§8,
  metadata §9) and TestFlight from GitHub Actions. docs/app-store-metadata.md:
  the version record says 0.5 (App Store Connect proposes 1.0).
- Verified: the rehearsal on this Mac, archive and export in 49 s (the plan's
  numbers are in the checklist's §4), Sill.ipa 2.0 MB, App Store profile,
  `beta-reports-active` true, get-task-allow false, 0.5 (1),
  `ITSAppUsesNonExemptEncryption` false, the Local Network and camera
  strings, `PrivacyInfo.xcprivacy`, no keychain or Apple Account prompt (no
  SecurityAgent line in the unified log); the unsigned archive's export with
  the same signature and entitlements; the script offline against a
  stand-in xcodebuild playing the rehearsal's archive and .ipa (123 checks,
  27 of 27 mutants caught; in the session's scratchpad, `testflight/tests`);
  the workflow's YAML (every action pinned, no expression in a run script,
  bash 3.2 parses each run block) and its shell steps with fake inputs.
- Review fixes (2026-09-26): `--upload` refuses uncommitted changes as
  `--bump` does (a build that stays here only warns), and both count new
  files in iOSClient and Sources/StreamProtocol, which reach the build
  unlisted (the local StreamProtocol package, the asset catalog); an
  `appStoreText` that is neither the placeholder nor an App Store address
  stops the build; `--api-key` refuses a file that isn't a .p8 key, and a
  relative `--api-key` or `--privacy-report` path is the caller's, not the
  repository's; an expired Xcode sign-in, and a failure after `--bump` (its
  commit, then run again without it), are named. Roles, from Apple's pages:
  uploading takes Developer or above and signing through a key Admin (the
  docs had App Manager, and a notary key that could do neither). The
  workflow's key step names a secret that isn't base64 (it ended at
  base64's own complaint). The checklist's republish (§3, and part 1 §3's)
  deleted sill-site's own `.nojekyll` and `.github/FUNDING.yml` (tried with
  this Mac's openrsync on a copy), part 2's first release pointed at the
  rsync below, which leaves out download.html, and §3 said the published
  pages lacked the email_off comments (Cloudflare strips them; sill-site
  has them). Verified: the offline checks, 150 (123 and 27 new), and 39 of
  39 mutants (27 and 12 new); the key step under bash 3.2 with a good, a
  raw, a garbled and an empty secret; the export options against Xcode
  27.0's `xcodebuild -help`.
- **Untested, for Noah:** the record, the upload (`Scripts/release-ios.sh
  --upload` after the checklist's TestFlight §1 and §2), TestFlight on the
  devices, any run on GitHub (unsigned first, then with the key), signing
  through an API key, and the Organizer's privacy report PDF.

**Before going public (2026-09-26, branch `public-sweep` from main at 150f781,
with main at a550e27 merged in, PR #24).** Noah's four steps for the first Mac
release end with making Saffsanity/sill public, which publishes its whole
history, so a sweep read the tree, every branch's history, the v0.3.0 release
and the repository's settings first. The branch fixes what the tree can:
docs/menu-bar-app-plan.md without the Apple Account's address (in the Apple
Development identity's name) or the name in that certificate's O field; made-up
Tailscale values in place of this Mac's in DebugHooks' long-name preview
(compiled into Sill.app: a person's Mac on the real tailnet), three comments,
the addresses, pairing-address and origin checks and the remote access plan; the
README and the site say the Mac download is out and the iPhone and iPad app is
on its way to the App Store (the site's steps sent visitors to a listing that
does not exist); the license is Apache-2.0 unless Noah says otherwise (final
once the repository is public); .gitignore leaves out signing keys, profiles,
keychains and design/reel/, and the checklist's `gh secret set` commands read
the keys from outside the repository; release docs after v0.3.0 and with
immutable releases (a deleted immutable release's tag can never be used again);
SECURITY.md and issue forms; the ledger check's fix, which main's PR #22 also
made (the merge keeps main's lines). Verified: a clean `swift build -c release`,
whose SillMenuBar holds none of the old values; `Tests/checks/run-all.sh`, all
15; the three changed checks' output equal to main's once the replaced values
are masked; the four address checks' mutants, 74 of 74; the preview name 291.5
pt wide with its port against 291.6.
- **For Noah, before the repository goes public:** what history, the other
  branches, the tag v0.3.0 and the 0.3.0 binary still carry (the sweep's report
  lists it): accept it, or publish a fresh repository; whether Apache-2.0 stays;
  immutable releases and the Actions allow-list (both possible while private).
  Right after: secret scanning and push protection, private vulnerability
  reporting, rulesets for main and the v* tags, the site republished, then the
  edits the comments hold back (the README's CI badge, index.html's "Free and
  open source", support.html's issues link, the checklist's private-repository
  lines). The sweep's report has the commands.

**Update check and device notice (2026-09-25, branch `update-notice` from
`remote-access` at cb0ec55, PR #13, with main merged in at 1f3072a and again
at 32d532b, not rebased; the plan, its open questions with the defaults taken,
and the results are in `docs/update-notice-plan.md`).** Noah's
request: an update check in Sill.app with Apple frameworks only (GitHub's
releases feed, not Sparkle), and a host-to-device notice so a later Mac can tell
an old device to update instead of failing silently. The first public builds
set the compatibility floor for good (the section before Conventions).
- Wire (additive; `Compatibility.swift`): kind 23 `Hello {appVersion, build,
  protocol, device}`, the first message of every session connection a device
  makes (never a pairing connection; older hosts skip it); `SillVersion` (tags,
  bundles and the wire's versions: "v" dropped, the digits-and-dots prefix,
  compared part by part, "0.10" > "0.9"); `SillProtocol.current` 1. Kind 22
  gains `message`, `minimumVersion`, `reconnect` and the reason "update" (nil
  fields left out: the five goodbyes of today are byte for byte what they were).
  Window lists carry `hostVersion` (Sill.app's; nil from SillHost) and
  `protocol`.
- Host: `DeviceGate.minimumDeviceVersion` is "0": nobody is refused and nothing
  waits. Above it (only `SILL_TEST_MIN_DEVICE_VERSION` on a host that does not
  advertise, in this build), both doors hold a ready connection unregistered
  until its first message: a hello the floor admits is served; a lower version,
  no hello, another kind, the end or 2 s of silence gets kind 22 "update" ("Update
  Sill on your iPad to keep using ‹Mac›. It needs version 1.2 or later.",
  `"reconnect":false`) and this side's FIN, what it still sends is read and
  dropped until it closes (at most 1 s: cancelling at once answered its later
  messages with a reset, which can beat the notice), and it is never registered
  (no "Client connected", no "Client left", no "Remote client connected"). One Refused line per source a
  minute, then a count line; a source refused 5 times in 60 s hears it 2 s late.
  `SILL_TEST_GOODBYE` sends another kind 22 instead. A hello is logged ("Client
  hello: iPad (iPad14,1), Sill 1.0 (42), protocol 1 (…)") and names the Mac
  card's row before its stats. Pairing is never refused for age. What changed
  while the gate held a connection is judged again as it admits it: the remote
  door re-reads its trust snapshot (`serve`'s recheck, `RemoteServer.stillAdmits`:
  removed, Remote Access or internet access off, the 8-session limit, each with
  its goodbye and closeSessions' line), and at home a connection on peer-to-peer
  Wi-Fi that the peer-to-peer listener accepted is disconnected if Direct
  Wireless went off meanwhile. The remote door's refusals at admission
  (remoteOff, busy) close like the
  gate's (`closeWithGoodbye`); over TLS the close_notify and FIN go only at the
  cancel, so the device sees the end, and the notice, up to 1 s after the
  goodbye.
- Device: `GoodbyePolicy` is the one rule for how a session ends. Today's five
  reasons keep their words; "update" and any reason this build does not know
  are notices: the Mac's message (SafeText, at most 300 characters) as the status
  line, spoken, a reconnect only with `"reconnect":true`, looked at before a
  remote dial's failure rules (before, an unknown reason showed "disconnected"
  and redialled at once: a loop against a Mac that refuses). "update" adds
  "Update Sill in the App Store" under it once `SillLinks.appStoreText` holds
  the App Store address (a placeholder now; DEBUG `-SillAppStoreURL`). The
  hello goes out first on a tap's, a reconnect's, a wired dial's and its
  fallback's, a move's and a remote winner's connection (`-SillHelloVersion`),
  written to a home dial's connection as it is made, before it is the
  session's (a send made before `.ready` then follows it), and a tear-down
  forgets the session's viewport and a pointer re-send still waiting;
  `hostVersion`/`hostProtocol` are kept, shown nowhere. A refused home session
  shows the stream screen for a frame or two first (connected at `.ready`;
  accepted, open question 10).
- Sill.app: `UpdateChecker` (+ pure `UpdatePolicy`) asks
  https://api.github.com/repos/Saffsanity/sill/releases/latest 30 s after launch
  when due, then every 24 h plus 0–30 min, an hour after a check with no answer,
  re-armed at wake, and at Check Now: an ephemeral URLSession, `User-Agent:
  Sill/‹version›`, GitHub's Accept and API version, `Accept-Language: en` (it would
  otherwise send the Mac's languages), If-None-Match; no cookies, cache or
  credentials; redirects only to api.github.com; 1 MB, 10 s. A published release
  (not a draft or prerelease, its page on github.com) whose tag is newer than
  CFBundleShortVersionString is offered as "Sill 0.4 Is Available…" after the
  card (the glyph stays) and in Settings › General ("Check for updates
  automatically", on by default, wired to the checker from launch; Check Now's
  result until GitHub answers an automatic check, else the offer or the last
  check; Open Release Page…; Check Now); both open the page in the browser,
  nothing is downloaded. A 404
  (the repository is private today) is one log line a day and nothing else.
  `make-app.sh --release` builds only a commit tagged `v‹version›`.
- Verified (the plan's Results has every number): clean builds (only the
  CaptureProbe and `StreamClient` capture warnings); pure checks with swiftc
  and mutants: the protocol 74 (13 of 13), DeviceGate 58 (14 of 14),
  GoodbyePolicy 42 (16 of 16), UpdatePolicy 124 (18 of 18); cb0ec55's
  StreamProtocol reads the new payloads and skips kind 23; the CLI's stdout,
  idle 35 s and with a Desktop pick, masked and sorted, equals cb0ec55's;
  UpdateChecker alone against `sillfeed.py` (every answer of §6.4, the headers
  and nothing else, the timeout, the retry, Check Now joining); the bare app end
  to end (the live menu item, the pane, 304, 404 silent, off, test pattern
  mode); previews differ from cb0ec55's only in General, menu.txt's new sample
  and the new update states; the gate on the CLI (both doors, the loop
  slowdown, the count line, SILL_TEST_GOODBYE) and on StreamServer alone (no
  resets); the simulator against real hosts: the notice at home and through
  the remote door, no reconnect, redials only when asked, an older host, and
  photos at eight sizes.
- Review fixes (2026-09-25, after a85118d; the plan's "Review fixes"), in the
  bullets above: the hello written as a home dial is made, the gate's second
  look, the door's refusals with a FIN, the pane after a later check, the switch
  from launch. Checked: a stand-in with
  the real SessionLink.swift and a listener logging kinds: the hello first in 5
  of 5 each for a send right after start, after a hop to the network queue and
  200 ms into a Bonjour dial still resolving (the old order lost it in all
  three); the device against a stand-in Mac. A rig of StreamServer and
  RemoteAccess alone (no encoder): a hello held through Remove, Remote Access
  off and internet access off gets removed, remoteOff and internetOff with their
  lines (the build before served all three); 12 held sessions: 8 served, 4 busy
  (12 before); remoteOff and busy at admission with the hello 0.5 ms after the
  handshake: 30 of 30 end in a FIN (8 and 21 resets in 30 before). The real CLI
  with the en0 stand-in: a held connection is disconnected once Direct Wireless
  is off (the build before registered and served it). The checker alone: Check
  Now's result, then an automatic answer, 12 of 12 (5 failures before); the
  bare app: off at 0 s sends nothing, on at 0 s from a saved off asks (the build
  before did the reverse), the pane follows a release found after Check Now.
  H4–H6, H7 (42), UpdatePolicy (124) and H8's seven runs pass; the CLI's stdout,
  masked and sorted, equals cb0ec55's; previews equal the build before's; iOS
  Debug, Release and device builds with only the old warning.
- Merged with main (merge 104a9bd of main at 1f3072a: PRs #11 encoder recovery,
  #12 follow-best-path, #14 App Store readiness, #15 the public README). Where
  they meet: every connection the device opens says hello first, #12's moves
  included: `startMove` (from AWDL, to the cable, to Wi-Fi, a rescue's
  reconnect, each fallback) writes it as the connection is made, as
  `connect(to:)` does, and a remote winner says it in `adopt`; main's `rescue`
  reads `goodbye`. `SillLinks` is one enum (the site's addresses and the App
  Store one), once in the project file. The public README stays main's; this
  branch's Updates, tag and hello paragraphs are in docs/DEVELOPMENT.md. The
  pointer plan's Mac menu bar kinds move to 24, 25 and 27 (23 is the hello).
  Fix-ups: `release.sh --dry-run` builds an untagged commit again
  (`SILL_RELEASE_DRY_RUN=1`) while a real run names the missing tag in its
  preflight, and the checklist gains the tag and the App Store address
  (184d902); the privacy policy's Update check section, and the download page
  (05d9d3a). Verified on the merge: clean builds (only the CaptureProbe and
  `StreamClient` capture warnings; `make-app.sh` without `--install`); this
  branch's pure checks against the merged sources (the protocol 74, DeviceGate
  58, GoodbyePolicy 42, UpdatePolicy 124, their 61 mutants caught) and main's
  (the discovery policy 286 with 70 of 70 mutants, main's own 187 with the 20
  older ones, the fence in its 12 modes with 16 of 16, the remote rules 64
  with 35 of 35, the ledger 90 with 5,000 random runs and 3 of 3, the remote
  protocol 188); the hello first on the merged SessionLink (the review's check,
  and a new one for #12's hold and fenced hand-overs: the move's connection
  says hello first, one without it is caught; the source: two connections
  made, three hellos sent); the checker alone against sillfeed.py (42, and the
  stale-result check); the bare app's H8 runs 1 and 2; previews from the bundle
  against origin/main's: only General, menu.txt's `update-available` sample and
  the 20 new update states differ; the CLI's stdout against origin/main's,
  idle 35 s and with a Desktop pick, masked and sorted: identical; the gate on
  the merged CLI (H5, H6 a–h with the remote door, the slowdown and its count
  line) and origin/main's host skipping the hello; a simulator of its own
  (deleted after): at floor 99 the notice, no reconnect, no second connection
  in 60 s; at floor 0.1 admitted and streaming, and with `-SillMoveTest 1` the
  move's own connection admitted with its hello and the session moved to it;
  the update and notice cases at four sizes above main's footer.
- Review fixes after the merge (2026-09-25; the plan's "Review fixes after the
  merge"): `release.sh --publish` refuses, before building, unless origin's tag
  v‹version› names HEAD (gh would make a missing tag from the default branch's
  tip), passes gh `--verify-tag` in Saffsanity/sill, and warns when
  `SILL_RELEASE_REPO` is elsewhere, since every update check reads only
  Saffsanity/sill (the checklist's sill-site fallback publishes a download no
  Sill.app offers); the tag match is `grep -Fx`. A goodbye on a move's
  connection before its window list ends a session whose own connection has
  gone with the Mac's words (a rescue refused by a newer Mac: the notice, no
  reconnect), and a live session's move up no longer retries the listing that
  refused it. The privacy policy says the device tells the Mac its version
  "when it connects" (no VPN outside the Remote Access markers), and its short
  version names the fixed "en" and the IP address. §13 of the plan is the floor
  as written here; getsill.app and support@getsill.app read as confirmed in
  SillLinks, the checklist and the metadata. Verified: the builds; release.sh
  and make-app.sh against scratch repositories (60 checks, 13 of 13 mutants;
  d4abceb's fail 40) and `publish_release` against a fake GitHub API; the
  simulator against Python stand-ins, before and after; the site's cut gate;
  every pure check with its mutants, H7 (42) and the stale-result check (11).
- Merged with main again (2026-09-26; merge c01610b of main at 32d532b: PR
  #16, the best path's follow-ups, and PR #17, GitHub Actions; the plan's
  "Merged with main again"). No host source changed on main since 1f3072a.
  Where they met: `sessionEnded` keeps GoodbyePolicy's rule and passes #16's
  `afterQuit` after goodbye "quit" (a notice never sets it); release.sh keeps
  both sides' checks, main's `SILL_RELEASE_TAG`, `--check-tag`, icon check and
  `gh api` preflight (`gh auth status`, which the Actions token can't answer,
  is gone) and this branch's tag rule, and the release workflow
  (`GITHUB_ACTIONS` with `SILL_RELEASE_TAG`) does not ask origin for the tag
  (`in_release_workflow`: its checkout is origin's tag and keeps no
  credentials); the checklist says a pushed tag starts the release workflow,
  which publishes when `SILL_SIGN_IN_CI` is on, so `--publish` by hand then
  does not. `Tests/checks`: protocol's kind 23 case is the hello, and this
  branch's four pure checks moved in (662a70e): `compatibility` 74,
  `device-gate` 58, `goodbye` 42 and `update-policy` 124, with 61 mutants, in
  CI's mutants matrix too. Verified: a clean release build and the three iOS
  builds (only the known warnings); CI's CLI step; `Tests/checks/run-all.sh`,
  all 13, and `--mutants`, all 279 mutants caught; the hello first on the
  merged SessionLink and StreamClient; release.sh and make-app.sh in scratch
  repositories with a stub gh (101 checks, 20 of 20 mutants; the scripts
  before the merge fail 26 and 50 of them) and `publish_release` against a
  fake GitHub API; the simulator against this head's CLI (floor 99: the
  notice, no reconnect; floor 0.1: admitted and streaming, and a move's own
  connection with its hello; a goodbye "quit": its words and one connection).
- **Untested, for Noah:** the plan's V1–V7: V1 the real check today (install
  this Sill.app yourself; within a minute "Update check failed: GitHub has no
  release of Sill (HTTP 404)." once, no menu item, Check Now says "Couldn’t
  check: GitHub has no release of Sill yet.", `updateLastCheck` set), V2 once
  the repository is public with a newer release, V3 a refusal on the iPad (its
  Debug build, `-SillConnect <this Mac>:P`, against
  `SILL_TEST_MIN_DEVICE_VERSION=99 SillHost --synthetic`; VoiceOver speaks it; no
  reconnect in 2 minutes), V4 mixed builds (PR #13's iPad build against this
  Sill.app and this iPad build against PR #13's: as before), V5 VoiceOver on the
  Mac, V6 the first two notarized builds (permissions kept across the update;
  `--release` refuses an untagged HEAD, `release.sh --dry-run` only warns,
  `--publish` refuses until the tag is pushed), V7
  the privacy policy's Update check section (site/privacy.html) on the
  published site, once Saffsanity/sill-site is republished.

**GitHub Actions (2026-09-25, branch `github-actions` from main at 1f3072a).**
Noah: the download link still fails; a new release should be checked by
GitHub, and does that cost money. The link fails twice over: there is no
release (`release.sh --publish` has never run; `gh release list` is empty), and
Saffsanity/sill is private, so its release files are a 404 to anyone not signed
in with access (docs/release-checklist.md, "Releasing from GitHub Actions",
has both ways out: go public, or publish in sill-site). Added:
- `.github/workflows/ci.yml` (Layout): pull requests and pushes to main that
  touch more than documents, the site or design files, and by hand; one job on
  `xcode-27`, 30 minutes, cancelling an older run of the same event and ref.
  Runner: the newest image GitHub offers and the only one with Xcode 27 (macOS
  27.0 26A428 with Xcode 27.0 27A266a as the default, 27.1 installed as
  `Xcode_27.1_beta.app` and a 27.2 beta; a public preview, issue 14404);
  `macos-latest` is macOS 26 with Xcode 26.6 at most, `macos-15` Xcode 16.4
  and 26.3, never tried with this code. `.github/actions/select-xcode` takes
  the newest Xcode 27 whose folder is not a beta (27.0 there, the same build
  as this Mac) and prints `xcodebuild -version`. The `.build` cache is keyed
  on that toolchain and Package.swift (there is no Package.resolved),
  `.build/checks` left out. The iOS build is arm64 only and not `-quiet`:
  Xcode 27's -quiet heads a compile that only warned with "error: the
  following command failed with exit code 0". The CLI runs only where it exits
  before the host starts: `--internet` alone (exit 2) and
  `--print-reachability`. Mutants only by hand, a job per check. Actions
  pinned by commit (checkout v7.0.1, cache v6.1.0, upload-artifact v7.0.1, the
  newest on 2026-09-25).
- `.github/workflows/release.yml`: a pushed tag `v*` or by hand with a tag
  (`SILL_RELEASE_TAG`); checkout with the whole history (make-app.sh's build
  number is the commit count). Repository variable `SILL_SIGN_IN_CI` not
  `true`: verify (the tag, the checks, `make-app.sh` signed ad hoc, the icon
  there, `Sill-<version>-adhoc.zip` as an artifact for 14 days). `true`:
  the checks, a check that the five secrets are set, the .p12 into
  `$RUNNER_TEMP/sill-release.keychain-db` (random password, masked; first in
  the search list and the default keychain, where notarytool keeps profiles),
  `notarytool store-credentials sill-notary --keychain` (validates the key),
  `release.sh --publish` with `GH_TOKEN` (the run's token, `contents: write`,
  or `SILL_RELEASE_TOKEN` for `SILL_RELEASE_REPO`), the notary log as an
  artifact, and an always() step that deletes the keychain and key files.
- `Scripts/release.sh`: `SILL_RELEASE_TAG` in the preflight (the tag must be
  `v<CFBundleShortVersionString>` and, when it is here, name HEAD);
  `--check-tag` checks only that. It refuses a build without Assets.car and
  AppIcon.icns (make-app.sh only warns when Quick Look or actool fail). Publish
  asks `gh api repos/<repo>` instead of `gh auth status`, which asks GET /user,
  and Actions' token can't answer that.
- `Tests/checks/` (Layout): the pure checks from this session's scratch
  folders, the newest of each, the ones run against the sources main now has,
  unchanged but for paths (the compile line in six `main.swift` headers; the
  policy, fence and clientlink mutants scripts read the repository and write
  to `.build/checks/<name>/`): policy 286 (integrate-12's merged check, 70
  mutants), fence 14 modes (review-moves-b's, 19), ledger 90 (ledger-union,
  no mutants), clientlink 89 (14), remote-rules 64 (rf2, 35), origin 66 (10),
  protocol 188 plus crosscheck.py's 8 (20), addresses 41 (step 3, 15),
  pairing-address 80 (pairing-address/fixes, 35). Not here then:
  EncoderMailbox's (only on encoder-two-in-flight, which carried it as
  Scripts/encoder-check; since that branch merged main at 32d532b,
  `encoder-mailbox` and `encoder-slowstate` are here and in CI: "A new
  session for the slow state"), and update-notice's one-line change to
  protocol's kind 23 case.
- Verified here, nothing pushed and no Actions run: `Tests/checks/run-all.sh`
  passes (all nine, 132 s); every mutant caught (`run-all.sh --mutants`, about
  44 minutes here: policy 70, fence 19, remote-rules 35, pairing-address 35,
  protocol 20, addresses 15, clientlink 14, origin 10); `swift build -c
  release` (28 s, only the CaptureProbe warning); the iOS command (only the
  StreamClient warning; both simulator slices); the CLI step under `bash -eo
  pipefail`; the three YAML files parse (PyYAML) and pass a structural check
  (every action pinned by hash, no expression inside a run script);
  release.sh's `--check-tag` on a match, a mismatch, unset, a tag on another
  commit and an annotated tag (a scratch clone), and a dry run with a wrong
  tag stopping before it builds; the Xcode rule on two fake image layouts; `gh
  api repos/Saffsanity/sill` answers.
- Review fixes (one pass: triggers and permissions, secrets, the Xcode step,
  the cache, injected failures, costs, docs):
  - The Xcode step would have failed every job: the image's `bash` is 3.2 (its
    README), which ends a `$(` at a `case` pattern's `)`, so the loop listing
    the Xcodes stopped short and `sudo xcode-select --switch` was handed the
    rest of the script as a path (reproduced with `/bin/bash`; zsh parses it).
    The loop is a function now. The step takes `version` (27 in both
    workflows: the newest 27.x that is not a beta, compared as text, as awk
    finds 27.10 equal to 27.1) and `fallback` (CI: a warning and the newest
    Xcode there; release.yml: `false`, the job fails); the old message said
    the default stayed selected and exited 1. 13 fake layouts under
    `/bin/bash` with stubbed sudo, xcodebuild and swift; every `run:` block
    parses with `/bin/bash -n`.
  - The cache's `!.build/checks` excluded nothing: actions/cache 6.1.0 globs
    with implicitDescendants off and tars each listed path whole (its
    dist/save/index.js), so `.build` took `.build/checks`; now `.build/*` with
    the exclusion. `.build` is 196 MB here, 135 of it the SDK's precompiled
    modules, module cache and stat caches.
  - `run-all.sh` skipped a check whose `run.sh` had lost its exec bit (seven
    of nine skipped: "All passed.", exit 0) and died on an unbound array with
    none: now every folder with a `run.sh` is a check, a non-executable one
    fails, none at all is an error.
  - Failures injected in a scratch copy: a behaviour mutant for each of the
    nine (the ledger's made by hand), a compile error for each build style
    (swiftc in run.sh; build.sh without `set -e`; with `|| true`), a failing
    cross-check, two broken checks under `bash -eo pipefail` (exit 2), a
    no-op mutant (`--mutants` fails on 14 of 15): every one fails as it
    should.
  - CI's concurrency group has the event, so a push to main no longer cancels
    a mutants run started by hand, nor the other way round.
  - The iOS step builds arm64 only (`ARCHS=arm64`; the generic simulator
    destination also compiled every file for x86_64): 61 compiles, 43 s of CPU
    here, `** BUILD SUCCEEDED **`, only the StreamClient warning.
  - `release.sh --publish` asks gh in its preflight whether it reaches the
    repository and whether the release exists, before building; both used to
    surface only after notarization (a stub gh: exists, missing, no access,
    no gh; `--dry-run` and `--check-tag` make no gh call).
  - The checklist's costs, against the fetched pages: they print no multiplier
    table any more (the prices' ratio is still ten), a budget stops usage
    only with "Stop usage when budget limit is reached" where offered, 15 to
    20 CI runs a month fit in Free's included minutes, the mutants take about
    an hour and a half (some 900 included minutes).
- **Untested, for Noah:** every run on GitHub (the first will be this
  branch's pull request: a draft counts too). The keychain and notary steps
  never ran (they change the keychain search list and the default keychain,
  which is not for this Mac), nor make-app.sh's Quick Look icon, spctl or
  notarytool on a runner. The steps: decide public or sill-site; set the secrets
  (`gh secret set`, the checklist); push a tag with the variable unset and
  try the artifact; then set `SILL_SIGN_IN_CI` and push the next tag. Costs:
  free once public; private, about 10 minutes a CI run against roughly 200
  included macOS minutes a month on GitHub Free (a macOS minute counts ten),
  then $0.062 a minute with a payment method on file, and nothing without one.

**Public README (2026-09-25, branch `public-readme` from main at b50e224,
draft PR #15).** For the repository going public at launch: `README.md` is the
public front page, everything the old README said is in `docs/DEVELOPMENT.md`
(word for word but for local paths, cross-references and two notes on the iOS
project, plus the two cable sentences main's README gained from
follow-best-path, PR #12, after this branch began), `LICENSE` is the Apache
License 2.0 as apache.org publishes it with "Copyright 2026 Noah Saffer" in
its appendix, and `.github/FUNDING.yml` names GitHub Sponsors (Saffsanity)
only, until there is a Ko-fi handle (see Layout for all four). The README
claims only what the site and this file back: Apple silicon and macOS 14, iOS
17, no latency figures, and the home connection's lack of encryption said
plainly.
- **For Noah:** Sponsorships turned on in the repository's settings (General,
  Features), or GitHub shows no Sponsor button (github.com/sponsors/Saffsanity
  is live since 2026-09-25); a Ko-fi handle, if wanted, goes in two places, a
  `ko_fi:` line in FUNDING.yml and a link in the README's Tips; the license,
  Apache-2.0 unless Noah says otherwise (docs/BRIEF.md; for MPL-2.0, replace
  LICENSE and the README's License section before the repository is public);
  the App Store badge and the sentence under the README's links, as the
  listing and the first notarized Sill for Mac come out.
- Merging: main gained follow-best-path (PR #12, cea195c) after this branch
  began, so PR #15 conflicts in README.md and CLAUDE.md: take this branch's
  README.md (DEVELOPMENT.md's step 3 of The iOS app already has PR #12's
  cable sentences) and keep both Current step entries. The open branches that
  edit the old README put that text in docs/DEVELOPMENT.md:
  app-store-readiness's release paragraph under Releasing (its Layout list
  fits the Overview), encoder-two-in-flight's stats-line bullet and its
  Resolution note under What to try if it's slow, and update-notice's (local,
  not pushed) Updates paragraph under Sill.app, the menu bar host, its
  Distribution text under Releasing and its device-hello paragraph after the
  gear paragraph of The iOS app. A change the public README describes (pairing
  at home, say) also updates README.md's How it works and Good to know.

**App Store readiness (2026-09-25, branch `app-store-readiness` from main at
76366e8; main at ba91136, PR #13 remote access, merged in, not rebased).** What
a first upload of the iOS app and the first Developer ID download of Sill.app
need, after the App Store audit. `docs/app-store-metadata.md` has the reasons,
Apple's sources and every text to paste into App Store Connect;
`docs/release-checklist.md` the order of work, once and on every release.
- Adds: the privacy manifest, `iOSClient/PrivacyInfo.xcprivacy`, a resource of
  the target (UserDefaults CA92.1 and `systemUptime` 35F9.1, no tracking,
  nothing collected; remote access uses no required-reason API outside those
  two); `ITSAppUsesNonExemptEncryption` NO in `iOSClient/Info.plist`, which the
  build merges with the generated keys (the home connection is plain TCP, and
  remote access's TLS 1.3, CryptoKit and CommonCrypto are Apple's, which needs
  no documentation; the plist key, never also the build setting); the connect
  screen's footer (Layout, `ContentView`), for guidelines 1.5, 2.1 and
  5.1.1(i); the website in `site/` and `Scripts/release.sh` (Layout); the two
  docs, with the Remote Access switch (the cuts for a 1.0 without it).
- Confirmed by Noah on 2026-09-25 (the site is live): the site at `https://getsill.app`
  (`site/CNAME`, `SillLinks.swift`, both docs), the contact address
  `support@getsill.app` (the privacy and support pages, the README and the
  metadata; Cloudflare Email Routing forwards it to Noah), and the Mac download
  at `/download` (`site/download.html`, which links the newest GitHub Release's
  `Sill.zip` and is never edited per release). The checklist's Placeholders
  table has the commands that change each everywhere.
- The merge: the footer sits under main's connect screen (Add a Mac…, the
  Remote rows, the card, the leading anchor, the Duo's top half, the column at
  the top while a field has the keyboard). The branch drew the column twice,
  under a ViewThatFits of a form that fits and one that scrolls; with main's
  card that meant two cards, each with its camera and fields, and a new one
  whenever the fit changed (the card folds its words while a field has the
  keyboard). Now one scroll view holds the one column whatever the fit
  (`ColumnOverFooter`, measuring a hidden copy of the footer), and a scrolling
  column fades over 12 pt with 12 pt clear before the footer (the branch: 24
  and 12), both inside the 24 pt gap that a column that fits keeps. At 710×1000
  the column stays in main's top half, the footer along the bottom. README
  and CLAUDE.md keep both sides.
- Verified on the merge: iOS Debug and Release for the simulator and Debug for
  a device, only the StreamClient capture warning; no package source differs
  from ba91136; both built Info.plists read `"ITSAppUsesNonExemptEncryption" =>
  false` (Xcode's ProcessInfoPlistFile takes `iOSClient/Info.plist`), with
  `PrivacyInfo.xcprivacy` at the bundle root. Harness photos of the merge and
  of main's own build, compared pixel by pixel: 1000x710, 710x1000, 500x710 and
  710x500 on an iPad, 440x956 and 956x440 on an iPhone 17 Pro Max, default and
  accessibility-extra-large text, the cases looking, methods, denied, remote
  and addmac. In 54 of the 60 the title is where main puts it and only the
  footer's pixels differ. The six others follow the rule: methods at 710x500
  and at 956x440 scroll above the footer (the column 16 pt from the top), and
  remote at 956x440 rises 17 pt (27 at the larger text). The title's x never
  changes, and nothing overlaps the footer.
- Verified before the merge (the commits say how): Release builds with the key
  in the built Info.plist beside the manifest; the footer's photos against its
  parent commit (the column never moved), an accessibility dump (three links,
  the dots hidden) and Support opening its page; the site's static checks
  (tags, links, CSP, headings, the Remote Access markers and their cut gate);
  release.sh's refusals and its functions (33 checks, a fake keychain), never a
  real run; the placeholder commands on a scratch copy.
- After the merge, review findings fixed: every page's brand and Home links
  were `./`, which opens nothing from the folder (WebKit from file://: 8 of
  the 28 header and footer links dead; with `index.html`, all 28 land on their
  page, and each answers 200 from `python3 -m http.server`). A column that
  rose to keep the gap could reach the very top, while one that scrolls has
  16 pt above it, so at the switch it jumped: methods at 710 wide scrolled with
  its title 19.5 pt down at 510 pt tall and, one point taller, rose flush (the
  title 4 pt down). Now it rises no higher than 16 pt from the top, the same
  as scrolling: photographed at every height from 500 to 540, the title stays
  19.5 pt down up to 526 and then moves 1 pt a point (at the larger text, up
  to 535); the 60 photos above are pixel for pixel the merge's. The export
  compliance key needed no change: the target generates its Info.plist from
  `iOSClient/Info.plist` plus the build settings (GENERATE_INFOPLIST_FILE with
  INFOPLIST_FILE), and clean Debug and Release builds of the result, for the
  simulator and for a device, all carry `ITSAppUsesNonExemptEncryption` false
  and `PrivacyInfo.xcprivacy` at the bundle root, with only the StreamClient
  capture warning; `swift build -c release` builds, and again is a no-op. The
  real app on the iPhone simulator (Bonjour listed this Mac; nothing
  connected): the footer above the home indicator, at both text sizes.
- Main moved on while this ran: PR #11 (encoder recovery) is b50e224, not
  merged here; it overlaps this branch only in CLAUDE.md and README.md.
- **Untested, for Noah:** the decisions: the domain, the contact address, and
  whether 1.0 keeps Remote Access, which main has had since ba91136 (the
  audit advised a 1.0 without it before it merged; the metadata's switch lists
  the cuts). On a device: the footer's links open Safari (the pages are not
  served yet), VoiceOver reads the footer once, after the rows (its measuring
  copy is hidden from it), the card's fields with a hardware keyboard (the
  column at the top, the footer in view) and the software one (the footer
  under it), and a phone held sideways, which only the harness drew here
  (956x440). The release: the Developer ID
  certificate, notary credentials, release.sh for real, a first launch on a
  Mac that never had Sill, the site on GitHub Pages with its DNS record, the
  App Store Connect record (the checklist's part 1). The description's claims
  not yet seen on a device: the cable on an iPhone, Pencil hover, 120 fps.

**Follow-best-path merged with main after remote access (2026-09-25, branch
`follow-best-path`: merge of main at ba91136, PR #13, into 8e1e4e3, PR #12,
then main at b50e224, PR #11, merged at f863c74; neither a rebase; PR #12 is
main's cea195c).** A session at home follows the best path as the next entry
says; remote access works as its entries say. Where the two meet:
- A remote session (a saved Mac dialed through the remote door,
  `Session.route` `.remote`) is no candidate for the moves:
  `DiscoveryPolicy.PathInput.remote` (StreamClient sets it from the session's
  route) makes `pathPlan` keep it where it is whatever its path and the
  browser say, as it keeps a Direct session ("path: kept: a remote session
  moves only by the remote reconnect", `Keep.remote`). Its route word stays
  nil (#13), its end is never carried on by a move (`rescue` asks the plan),
  and it still never moves home to the network (a later step).
- The end of a session: `endSession` hands over to #13's `sessionEnded` (the
  words, `reconnect` by Mac ID or Bonjour name, the remote dial), which
  replaced `reconnectTo`. `connectionLost` first lets a move carry the session
  on (`rescue`: the stream screen stays), except after a goodbye (kind 22,
  "quit" at home: the session ends at once with its words, not after a
  rescue's dial to a Mac that is going; the reconnect waits too, see the
  review fixes below) and when this device closed the connection itself
  (`end`: a message no Sill sends). #13's `reconnectIfListed` never runs
  beside a move (`moveUnderWay`: a move, or a session one carries on, which
  stays `connected` until the move takes over or ends it). #13's liveness (no
  byte for 6 s) now ends a stranded cable connection too; the rescue then
  decides as for any other end. A connection already closed sends no pings
  (the fix-up after the merge): while a move carried its session on, it was
  still the session's, and its liveness reported it lost four times a second
  until the move ended (log lines, and `connectionLost` calls that did nothing).
- Dials: one row dial, #13's `dial(_:macID:)`, which carries prefer-cable's
  wired dial and its fallback; the moves keep theirs (`startMove` with
  `wiredDial`, or this branch's `wifiDial`), both for network rows only now
  that a row has a route (a Remote row is not Direct either) and an optional
  endpoint. `FoundMac.wifi` joined #13's initializer; `adopt` (a remote dial's
  winner) forgets the path state as `connect` does; `-SillPathTest`'s
  addresses go through #13's address parser first, then the split at the last
  colon.
- `SessionLink` is this branch's (hold, adopt, unhold, the chained fences):
  main had not changed it since 76366e8. `DiscoveryPolicy` is the union, plus
  the remote rule.
- Verified without devices: iOS Debug and Release for the simulator and Debug
  for the iPad (build only, not installed), only the old `StreamClient`
  capture warning; `swift build -c release`, and clean, only the CaptureProbe
  warning (Sources, Package.swift and Scripts were ba91136's byte for byte).
  Pure checks against the merged files:
  this branch's policy check 277 of 277 and its 61 mutants; main's 187 of 187,
  its 25 mutants (D1's text made unique: `wifiInterface` has the same guard)
  and the 20 older ones; the remote rule's 9 checks on top of the 277 (286:
  a 12,288-case grid, a model) and 9 mutants of it, 70 of 70 with the 61;
  remote access's rules check 64 of 64 and 35 of 35; the fence check's 12
  modes and 16 of 16 mutants. On a simulator of its own against the merged
  `SillHost --synthetic`, one host at a time (21 hosts, the longest 49 s):
  this branch's 18 scenarios as before the merge (refused-cable's other
  launch now a Python stand-in, so one real host suffices); remote access's
  pairing by link, a remote session by address that the plan keeps where it
  is (its "path: kept: a remote session…", no route word, no move) and, its
  host gone and back, the ordinary end and an automatic remote redial, no
  rescue; and close-slow (the connection closed over the cable, the cable's
  dial never answering, the row as listed never sending a list: the session
  ends 7.5 s later with #13's words), 66 of 66 checks. close-slow on the merge
  commit's own build printed "connection silent for 6 s: lost" seven times,
  0.25 s apart, until the move ended; with the fix-up, never. The first run
  stopped after four scenarios when Noah's iPad connected to Sill.app: that
  host had passed the check before it started and ran 24 s beside his stream,
  so the runner (`scratchpad/integrate-12/sim/simmerge.py`) now also kills its
  host the moment Sill.log shows a device connecting.
- Then main at b50e224 (PR #11, encoder recovery) merged at f863c74. Only
  CLAUDE.md conflicted: both Current-step entries kept, the best-path ones
  first; README merged by itself. Sources, Package.swift, Scripts and
  `HostSettingsPanel.swift` (its software-encoder callout) are b50e224's byte
  for byte, every other iOS file ed6b378's. Verified on f863c74's tree (the
  review's runs): iOS Debug for the simulator, only the old `StreamClient`
  capture warning; 70 harness photos at 1000x710 equal to b50e224's but for
  two spinners (connect-pairing, settings-pending: 176 and 178 px); the policy
  check 286 of 286 and 70 of 70 mutants, main's 187 of 187 and 25 of 25, the
  20 older mutants; remote access's rules check 64 of 64 and 35 of 35; the
  fence check's modes and 19 of 19 mutants. Not run on it: Release and device
  builds, and the simulator scenarios against its `SillHost --synthetic`,
  which now has b50e224's encoder recovery (the 21 hosts above ran ba91136's).
- Review fixes after the merges. After goodbye "quit" the reconnect no longer
  dials the Mac's row at once. The row outlives the goodbye by about a second
  (a receiver keeps a record 1 s past its goodbye, RFC 6762 §10.1; a stand-in
  for Sill.app's Quit, browsed on this Mac: gone 1.05–1.22 s after the
  connection ended, 11 of 11), and `sessionEnded` ran `reconnectIfListed` in
  the same main-queue turn, which took it (over the cable for a Wired row):
  "Reconnecting to ‹Mac›…" replaced "‹Mac› quit Sill." before it was drawn,
  and the dial waited on a Mac that was going (#13 alone did the same at
  home). Now a row listed since before the goodbye is left alone for 3 s
  (`DiscoveryPolicy.quitWait`; `reconnectRow`'s `quitAt` and `networkSince`,
  from `Reconnect.afterQuit` and `sightings`): the words stay; the row listed
  again (Sill is back) is taken at once by the usual rules (a Direct row after
  its own 6 s), and one still listed at 3 s (Sill relaunched within that
  second, a lost goodbye packet) is taken then. Any other end is as before.
  Verified: the policy check 310 of 310 (the merge's 286, and 24 for the
  rule: its cases, a grid of 17,820 against the old rule, a model of the
  glue) and the rule's 10 mutants; iOS Debug for the simulator, only the old
  `StreamClient` capture warning. No simulator scenario can show it: the
  synthetic hosts do not advertise, so no row lingers after their goodbye,
  and a session by address has no Bonjour name to reconnect by. DEBUG:
  `-SillMoveTest to:HOST:PORT` split HOST:PORT at its last colon itself, so
  `to:[::1]:P` listed the name "[::1]", which never connected (each try given
  up after 5 s); it now reads it as `-SillConnect` does (`address(_:)`: the
  address parser, then the split), and Build and run below names `other:PORT`
  and `-SillWiredTest` too. Verified on a simulator of its own against
  `SillHost --synthetic` built from the same tree (b50e224's host code), one
  host at a time (9 hosts, the longest 18 s;
  `scratchpad/integrate-12/apply-fixes/sim/simapply.py`): `to:[::1]:P`,
  `to:::1:P` and `to:fe80::…%en0:P` from 127.0.0.1 each list the address and
  move (the host sees the second connection; the scoped one reads its route
  again at the hand-over), and, as before, `-SillMoveTest 1`, a move's wired
  test, a plain session, close-slow (#13's words) and remote access's host
  gone and back (the session's end and the remote redial, which the quit fix
  runs through): 32 of 32 checks. The runner's app is signed to run locally:
  unsigned, the simulator gives it no keychain, and pairing stops at the
  device key (-34018) before it prints anything. Comments and docs: the
  harness contract in `ContentView` names `-SillSettingsEnd 1`,
  `-SillDeviceKeySE 1` and `-Sill.directWirelessMacs`, says the pairing
  arguments run under `-SillLive 1` too, and which remote settings cases are
  away from home (no route word) and which at home (Wi-Fi); `-SillWiredTest`'s
  comment says network rows (a Remote row is not Direct either);
  `address(argument:)` no longer repeats `address(_:)`'s paragraph. Left as
  it is here: README's "four source files", which main's PR #15 replaced
  (docs/DEVELOPMENT.md there says "its source files"). Verified on the last
  tree, comments only since the simulator run: iOS Debug and Release for the
  simulator and Debug for a device (generic, unsigned), only the old
  `StreamClient` capture warning; `swift build -c release`, only the
  CaptureProbe warning; on the same DiscoveryPolicy, SessionLink,
  RemoteDialPolicy, SavedMacs and StreamProtocol: the policy check 310 of 310
  and 80 of 80 mutants, main's 187 of 187 and 25 of 25, the 20 older mutants,
  remote access's rules check 64 of 64 and 35 of 35, the fence check's 14
  modes and 19 of 19 mutants. The branch still merges into main (1f3072a,
  after PRs #14 and #15) without a conflict.
- **Untested, for Noah:** the entries below on the merged build, and: a remote
  session at home with the cable plugged in stays remote (the console's "path:
  kept: a remote session…", the card's "through Tailscale"); Sill.app's Quit
  while the iPad streams over the cable gives "‹Mac› quit Sill." at once and
  keeps it, with no "dialing ‹Mac› on anpi0 (wired)" on the console before
  the row is listed again or 3 s have passed, and reopening Sill reconnects
  over the cable.

**The session follows the best path (2026-09-25, branch `follow-best-path` from
main at 76366e8, after PRs #9 and #10).** Noah's tests: plugging the cable in
left a Wi-Fi session on Wi-Fi until he reconnected (a TCP connection keeps its
interface), and pulling it hung the session a while, then the connect screen,
then Wi-Fi. A live session now follows the best path its Mac is reachable on,
the cable over Wi-Fi over Direct (`DiscoveryPolicy.pathPlan`, pure;
`StreamClient.followBestPath`), by the move from AWDL's make-before-break
hand-over (the new connection's first window list must carry the same
`launchID`). Up: once the network browser has listed the session's Mac on a
wired interface for 2 s (`cableSettle`, counted again after a move off it),
the Mac is dialled on it beside the Wi-Fi session (the wired dial; not ready in
2.5 s, or waiting or failing, and the session stays on Wi-Fi) and handed over
with the fence, and the readout says Wired. Down: when the cable's path is
gone (iOS says so: the connection not viable, back to waiting, or a path
update that is not satisfied and names the Mac's address; or the browser has
dropped the cable and either an unsatisfied update names only the service or
no pong has come back for 1 s, `pongSilence`), the Mac is dialled at once on
the Wi-Fi interface it is listed on, or was within 5 s (`wifiFresh`; the row as
listed after 2.5 s), what the device sends waits meanwhile
(`SessionLink.hold`) and goes out first on the new connection with no fence
(`adopt`), and the old connection is force-cancelled so nothing of it lands
late; a path that comes back calls the move off (`unhold`). A connection
already dead over the cable is made again at once (`reconnectNow`): over the
cable when the browser still lists it and iOS said nothing of its path (the
Mac closed it), as a tap on its Wired row dials it (the row as listed after
2.5 s), else over Wi-Fi the same way; the stream screen stays, no retry timer,
and if the Mac stopped the stream meanwhile (zero devices) the new
connection's first list picks the source again (the Desktop for a window that
went). Never Wi-Fi to Wi-Fi, never off a working cable (a browser blink alone
never moves it: its pongs keep coming), never off a Direct session but to the
network, at most one move per 5 s each way (`pathHysteresis`; up, 10, 20, 40,
then 60 s after moves to the cable that did not complete, `upWait`, and never
again to a listing of the cable that reached another Mac or launch until it is
listed afresh); with no Wi-Fi to go to, the ordinary end and reconnect.
DEBUG console: "path: the cable appeared: moving the session to anpi0", "path:
the cable went away: moving to Wi-Fi on en0", "path: the cable went away with
the connection: reconnecting over Wi-Fi on en0 now", "path: kept: …", and what
iOS said ("path: the session's connection is not viable…", "path: iOS says the
session's path is unsatisfied…"); `-SillPathTest` drives it in the simulator
(ContentView's contract). Verified: the policy check at 253 (187 plus 66: the
plan at every boundary, a 20,480-case grid, a model of plugs, pulls, blinks,
silence and a loose cable), 48 of 48 mutants caught (25 plus 23); the fence
check's eight modes (new: hold, holdclosed, unhold, adoptfence), six mutants of
the new SessionLink code caught; in the simulator against `SillHost
--synthetic`, dialling this Mac's own `fe80::…%en0` ("Wi-Fi") and
`fe80::…%en14` (the USB cable to the iPad, "Wired"): the cable listed at 3 s,
moved about 2 s later with the fence down in 1–2 ms; the path reported gone,
on Wi-Fi 10–20 ms later without a fence; the connection cut, carried on over
Wi-Fi in 10–20 ms with no connect screen and the Desktop picked again; the
cable dropped with pongs silent, moved at the 1 s mark, with pongs flowing,
kept; a loose cable moved up at 3.7, 8.9, 13.9 s and down at 4.6, 9.6, 14.6 s;
no Wi-Fi, the ordinary end; the move from AWDL and PR #10's wired-dial
fallbacks unchanged. **Untested, for Noah:** the real plug and pull on the
iPad while streaming. Plugged in: a few seconds later "path: the cable
appeared", the readout's Wired, and the host's "Client connected: …%anri0" (or
`%en14`) then "Client left" for the Wi-Fi one. Pulled: within about a second
the readout's Wi-Fi with no connect screen and the host's "Client connected"
over Wi-Fi (`%en0`, or the iPad's Wi-Fi IPv4 address; the cable's connection
leaves by itself, at the latest by eviction 4 s on); and which signal iOS gave
first (the console's "path:" lines), since a pull's own signals have never
been seen on a device. And on the cable, another app for over 4 s (the Mac
evicts the suspended iPad), then back to Sill: "path: the connection went
away, the cable did not", the host's "Client connected" over the cable again,
and no hop to Wi-Fi.

Review fixes (2026-09-25). A connection over the cable that dies while the
browser still lists the cable and iOS said nothing of its path was closed by
the Mac (it evicts a device that stops reading, an iPad suspended in the
background for 4 s): it is made again over the cable, where before it went to
Wi-Fi and came back to the cable 2 s later. A move to the cable could land
while the move from AWDL's fence was still up (that move can take 7.5 s, and
the next move up counts from its start), and its hand-over replaced the first
fence: what the first fence held was lost (a release sent then left the
button down), its AWDL connection was never closed, and `hold` was refused
while a fence stood. `SessionLink` now keeps a list of fences and a hold apart
from them: what waits goes out only once no fence and no hold stands, a hold
taken during a fence outlasts it (a cable pulled right after a move landed on
it), and each old connection is handed back for closing only once what waited
has gone out, its viewport first (`Released.close`), so the Mac never counts
only devices without one. A move up keeps its fence even when iOS has said
the old connection's path is gone (a report can pass; the 3 s timeout covers
a dead path), and a connection ready again after waiting clears `waiting` and
starts no second read loop. A listing of the cable that reached another Mac
or launch is not tried again while it lasts (`refusedCable`), and moves up
that do not complete wait 10, 20, 40, then 60 s (`upWait`), where before they
went every 5 s for as long as the cable stayed in. `-SillPathTest` gained
`close` (the connection closed, the row as it is) and `direct` (the session
counts as one over AWDL). Verified: the policy check at 277 (the 253, whose
grid now also spans refused listings and failed moves up, plus 24: the
reconnect over the cable, the refused listing, `upWait`, models of an
eviction on the cable and of moves up failing each way), 61 of 61 mutants
caught (48 plus 13); the fence check's twelve modes (new: twofences,
twomoves, holdfence, holdadopt; the `SessionLink` before the fixes fails
three: 27 inputs lost with 41 inversions, and two holds refused), 16 of 16
mutants of the new code caught; iOS Debug for the simulator and the iPad
(build only) and Release for the simulator, only the old `StreamClient`
warning; in a simulator of its own (another agent's UI tests had the shared
one) against `SillHost --synthetic`: the connection closed over the cable,
reconnected over the cable in 10 ms with no Wi-Fi hop; the cable's dial never
answering, on Wi-Fi 2.5 s later, then moves up 5, 15 and 35 s after, each
given up; a cable that connects but sends no list, and one refused at once,
the same back-off; a cable that reaches another launch, one try, and one more
once listed afresh; behind delay proxies (2 s and 3.5 s each way), the move to
the cable landing 1.5 s before the move from "AWDL"'s fence was down, the two
fences down by their timeouts, then everything that waited out on the cable
and both old connections closed; the earlier scenarios unchanged.

**The 33 fps plateau (2026-09-25, branch `encoder-two-in-flight` from
`encoder-recovery` at 4fe37d4, with main at 32d532b merged in and the review's
fixes after it: the next section's last bullets).** A Retina Desktop stream
(3024×1964, hardware encoder) sat at 30–36 fps in a third of the logged seconds
of Noah's home streams at 40 Mbps (7,445 of 22,081 seconds with 50 or more
frames captured and none idle), and nearly always over Tailscale at 4 and 15
Mbps; every such second read like
`cap.complete 56 enc.mailboxDrop 24 enc.out 33 net.sent 33`. An investigation
and a verifier (read-only: Sill.log and the kernel's AppleAVE2 log) found:
- The network held nothing back (`net.dropped` 0, `net.sent` = `enc.out`);
  nothing after the encoder waits. The whole loss was the mailbox.
- The hardware encoder falls into a slow state, often after a few seconds of
  fewer frames (a mostly still screen; once while scrolling at 38 fps) and at
  any bitrate (4, 15, 40 and 150 Mbps): a frame takes 29–30 ms from submit to
  output, and the HeartBeat's C/F (read as the engine's time per frame) 14–15
  ms, against 9 at 57 fps. Sessions started fast (7.5–9 ms a frame in their
  first windows, one at 12.3); 1512×982 never plateaued (6 ms a frame). With
  one frame inside VideoToolbox the output rate is one over the turnaround:
  33 fps.
- The HeartBeat needs `--predicate 'sender == "AppleAVE2"'` with `--info
  --debug`; `eventMessage CONTAINS "AppleAVE2"` returns only firmware lines.
  Per session and 5 s window it gives frames submitted | completed and three
  cumulative counters (C/F: the third's delta over frames;
  `Scripts/encoder-check/hbparse.py` prints it).
- 33 = 1000/30 matching the 30 ms tick timer is a coincidence (`net.tick` 33
  beside `enc.out` 55 on the cable).

The branch first let two frames into the hardware encoder at once, on the
reading that part of the 29 ms might overlap, then only under a test switch
after review (its commits 63a365b–e68408f have the design, the review and runs
on an engine shared with the Claude app's iOS Simulator panel, where two inside
gained nothing: 35.7 against 35.6 fps, capture to output 36 → 64 ms). Sharing
alone reads like the slow state in the stats line: in those runs a synthetic
Retina stream with one inside, beside the panel alone (15:43:39–15:44:09),
read ~32 fps with ~27 drops a second, and Noah's Retina Desktop beside it
33–36 fps (the operational rule in "The hardware encoder: busy, not stuck").
The HeartBeat tells them apart: it lists the panel's session beside Sill's,
and its C/F, the engine's figure, read 9.5–10.6 ms there against 14.0 for the
slow state alone. The deciding run had the engine alone:

Measured alone (2026-09-25, 20:16–21:04; no device connected, and each kept
run's HeartBeat lists only its own session): the CLI host built from e68408f
streaming the real Desktop at 3024×1964, 60 fps and 40 Mbps (Pro) to a loopback
test client, on this M2 Pro (Mac14,9, one encode engine) on AC power. Motion
came from a scratch window scrolling text-like content 6 pt a frame over a
static backdrop (57–60 frames captured a second; still, the menu bar clock
gives about one), each frame's encode call and output were timed by an
interposer on `VTCompressionSessionEncodeFrameWithOutputHandler`
(`DYLD_INSERT_LIBRARIES`), and C/F came from the HeartBeat. Schedules: 4 s of
motion, then 5, 10 or 20 s still (or 15 s with a step every 0.3 s), then 35 s
of motion (90 s once), for the slow state; 35 s of motion from the start for
the fast state. One and two frames inside (the switch,
`SILL_TEST_ENCODER_IN_FLIGHT=2`), in alternating pairs.
- What the slow state is. A fresh session's turnaround (submit to output) is
  8.7–9.2 ms for its first ~4 s, then ~16.2 ms at the same 57 fps, just under
  the frame interval, with C/F 9.0 throughout. About a second into a quiet
  phase an isolated frame takes 29 ms instead of 16 (the last 16 ms frame
  0.6–1.4 s in, the first 29 ms one 1.0–2.4 s in; in all 16 runs), and once
  motion resumes every frame does: 28.8–29.0 ms (median; p95 29.0–29.6), C/F
  14.0, 34.3–34.7 fps out of 57 captured with ~23 `enc.mailboxDrop` a second, in
  every second (35 of 35 s; 90 of 90 s in the long run). Motion from the start
  never went slow (57.3–57.5 fps, no drops). Capture to output
  (ScreenCaptureKit's timestamp to the output handler): median 39.7 ms (p95 51)
  slow, 17.6 ms (25) fast. C/F is weak evidence of a slower clock on its own:
  its counter grew 481–485 a second in the slow runs and 516 in the fast ones,
  so C/F moves with the frame rate.
- What two inside did. In the slow state 35.5–44.3 fps (mean 42.1, against 34.5
  with one), never above 49 in any second and never back to the fast state, in
  35 s or in 90 s. VideoToolbox served the second frame only after the first:
  it waited inside for a whole service time (22–28 ms) and came out that long
  after it, in order (0 of 40,774 outputs reordered); at the slow level two
  inside served one frame per 28.2 ms against 28.9 with one. The only gain was
  the engine stepping up once, 3.4–4.4 s into the motion, from 28.2 to 23–25.5
  ms a frame (40–45 fps), in 6 of 8 runs (one was on the faster step from its
  first second, one never stepped: 35.5 fps), which one inside never did. It
  cost 17–27 ms from capture to output per pair (median 39.7 → 59.4 ms, p95 51
  → 68.5; the turnaround 28.9 → 45–56 ms), which Sill's frame age, taken after
  the encoder, cannot show. In the fast state it gained and lost nothing
  (57.3–57.5 fps either way, +0.2 ms at the median). The harness (the real
  `HEVCEncoder` with synthetic frames, no ScreenCaptureKit: 3 s at 60 fps, 6 s
  of a frame every 0.3 s, 20 s at 60 fps) agreed: one inside 34–35 fps and a
  latency median of 35–38 ms, two inside 37–38 fps and 62–65 ms, no step in
  20 s.
- Dropped (the bar set before the run was ~55 fps, and ~8 fps for ~20 ms of
  latency is the wrong trade: latency beats quality). The switch and every
  path that served a second frame are gone: the mailbox's second place, the
  gate that kept a second frame out until the session had let go of one, the
  watchdog's clock restarted behind a returned frame, the re-check's test
  keeping two inside, the capture's reasoning about three surfaces. The
  re-check's test sends one frame at a time again, as a stream does.
- Observed, not verified as mechanisms: with one inside the slow state is a
  stable equilibrium (the engine is fed exactly what it completes; 90 s of
  motion never moved it); the engine paces itself to the rate it sees (9 → 16
  ms at 57 fps with C/F unchanged); at the slow levels the turnaround is about
  twice C/F. In two runs discarded for sharing, another agent's independent
  3024×1904 session on the engine lifted Sill's one-inside session to 49–57
  fps at C/F ~6 ms, and it fell back to ~34 when that load paused: load, not a
  second frame of the same stream, moves the engine. Next to try: the engine's
  power state or rate control (`EnableLowLatencyRateControl`, "The hardware
  encoder: busy, not stuck" below), not pipelining. Tried first instead, and
  kept: a new session (below). Resolution: Standard avoids the plateau too
  (57 fps with no drops at 1512×982).
- Not measured: Sill.app (the CLI only), 120 fps, other bitrates, a device,
  other chips (a Max has two encode engines), real content beyond the
  scrolling window.

What the branch keeps:
- `EncoderMailbox` (pure; Foundation and CoreMedia): `HEVCEncoder`'s
  bookkeeping as one type under its lock, one frame inside for every session:
  the frame inside (its id, its watchdog clock, whether `submit` has handed it
  over), the one-slot mailbox, `dead`, the timestamp fix and the keyframe flag
  (at 4fe37d4 eight variables). Behaviour as at 4fe37d4, edge cases included:
  `abandon` and the teardown count only a frame handed over (`outstandingID`
  then), so a frame let in and still on `encodeQueue` when the session dies,
  which never goes in, is not reported stalled, and a live session with one
  drains, as `inFlight` did.
- The order fix: a frame let in is queued on `encodeQueue` before the lock that
  let it in is released, and `requestKeyframe` sets the flag, decides whether
  the window is still and admits its re-encode in one hold. At 4fe37d4 those
  were two holds, and a repaint landing between them went into VideoToolbox
  ahead of the stale re-encode, so the device kept the older picture until the
  next repaint and `lastFrame` fell back to it (a reviewer saw it in about one
  in five coincidences of a request and a repaint, with nothing forced; the
  encoder check forces it by holding the requesting thread 4 ms after its first
  unlock: the older picture last in 10 of 10 trials before the fix, 0 now).
- The keyframe's second look: a keyframe asked for within 50 ms of the last
  repaint of a window that then stays still is looked at again
  (`keyframeCheck`, on the watchdog's queue, 60 ms after that repaint): the
  last frame is re-encoded if the flag is still set, the session is live, no
  frame is on its way to carry the flag (`EncoderMailbox.frameOnItsWay`:
  waiting in the mailbox, or let in and still on `encodeQueue`) and the window
  has not repainted. At 4fe37d4 such a request only set the flag: a device
  joining (`onClientConnected`) waited on black, and one whose delta was
  dropped (`net.dropped`, then `onKeyframeNeeded`) on a stale picture, until
  the window next repainted. On the hardware
  (`Scripts/encoder-check/verify-hardware.sh keyframe`: 6 sessions at
  3024×1964 and 40 Mbps, a request 5, 20 or 40 ms after a burst's last frame,
  then still): 4fe37d4 answered none, this branch all six, the keyframe out
  70–73 ms after the last frame (19:52–19:54) and, after the rework, 76–78 ms
  (22:02–22:03, the engine alone).
- The checks. `Scripts/encoder-check/run.sh` runs those that never touch an
  encoder (it refuses any binary that links VideoToolbox): the mailbox check,
  the real `EncoderMailbox.swift` against a stand-in VideoToolbox in virtual
  time through a copy of `HEVCEncoder`'s glue (S1–S17: 9 ms a frame 60 fps;
  30 ms 33.3 fps with 26.7 mailbox drops a second and a latency median of
  36.7 ms; 40 ms 25 fps; random turnarounds with refusals, second notices,
  rate-control drops and keyframe requests, every frame settled once; a stuck
  frame, `SILL_TEST_ENCODER_HANG`, slow and blocked encode calls, `abandon`,
  the teardown, keyframes and timestamps), and its mutants (`mutants.py`, each
  must fail it); the probe check, the real `EncoderProbe.swift` against a
  stand-in encoder in real time (one frame inside at most, 33 fps at 30 ms a
  frame, a stuck frame counted and reported back, `SILL_TEST_PROBE_HOLD=0.08`
  ~11 fps); the encoder check, the real `HEVCEncoder.swift` against
  `encoder/FakeVT.swift` in real time (every kind of session holds one frame at
  most and prints nothing when made, what a stuck encoder keeps, the order
  race, the keyframe's second look). `verify-hardware.sh` runs the hardware
  steps (parity, stream, harness, probe, keyframe) against 4fe37d4 built from
  `git archive`, each only while `no-device.sh` finds no device connected to
  Sill.app.
- Verified after the two-inside paths were removed (2026-09-25, 21:30–22:05):
  a clean `swift build -c release` from `git archive` (only the old
  CaptureProbe warning); the mailbox check, 38,256 checks, and 27 of 27 mutants
  caught; the probe check (19 checks and the hold) and the encoder check (75);
  a differential check (scratch, not in the repository) of `EncoderMailbox`
  against a transcription of 4fe37d4's bookkeeping, through 100,000 random
  sequences of the glue's events (admissions, hand-overs, outputs and
  refusals, second notices, watchdog ticks, keyframe requests, `abandon`),
  every outcome equal in 56,082,887 comparisons, while the type as it was
  before (a frame on `encodeQueue` counted as inside) failed it; the keyframe
  step above; the CLI against origin/main (1f3072a) and against this branch
  merged into it (`git merge-tree`: only CLAUDE.md and README.md conflict),
  each built from `git archive`, no device connected, each run's HeartBeat
  listing only the host's own sessions: `--synthetic` idle for 35 s identical
  masked and sorted (7 lines; in order too), and with a loopback client
  streaming the synthetic Desktop for 22 s identical (40 lines) but for one
  `enc.mailboxDrop` in the first streaming second of one of origin/main's two
  runs.
- **Untested, for Noah:** a device joining a still window gets its picture
  within about 0.1 s (the keyframe's second look has run only in the checks and
  the hardware harness).

**A new session for the slow state (2026-09-25, 22:24–22:39; c27d6df,
b3042de, dd0dc15).** The solo measurement read the slow state as a session's,
not the engine's: every fresh session started fast, and the slow state set in
only after about a second of sparse frames into an existing one. So a stream
whose session has settled in it gets a new session in place, on by default
(`HEVCEncoder.replacesSlowSessions`):
- The rule (`EncoderSlowState`, pure, Foundation only): a session that has run
  fast (a frame back in under 25 ms; turnaround is hand-over to output, by the
  mailbox's own clock) and now, over the last 2 s, gets at least 45 frames a
  second from the capture in each half of that window while the median
  turnaround of what came back is at least 25 ms and at least 1.5 times the
  fastest frame the session has returned, is replaced, at most once per 10 s
  (a new session that could not be made counts too). The new session is timed
  on its frames after its first (a keyframe) while the motion that set off the
  swap lasts: a frame counts only if the capture before its hand-over came
  within 0.1 s of the one before that and 45 came in the second before it, and
  the first frame without motion ends the timing. The verdict comes at 30
  timed frames, when the timing ends, or at the first frame back 2 s after the
  swap: their median if at least 5, else none (the picture went still). One no
  faster (its median at least 0.8 of the replaced session's: then the engine
  is slow, as beside another app) ends the replacing for that stream. A
  session that never ran fast (a size the engine is simply slow at) is never
  replaced; probes and the software encoder never are.
- The swap (`HEVCEncoder`): the new session is made with the stream's settings
  on a queue of its own while the old one goes on (the kernel opened it 39–42
  ms before it took over); `submit` hands it the next frame with a forced
  keyframe, whose parameter sets go out with it; the old one holds no frame by
  then (one inside at a time). `submit` completes it before the new session's
  first frame goes in, which waits for its last output handler to return, so
  that frame reaches `onEncoded` before the new keyframe (each session calls
  back on its own queue, and that handler lets the next frame in before it
  hands its own frame on: a callback thread descheduled for longer than the
  keyframe takes would put an old delta after it on the device), then
  invalidates it off the queue.
  The mailbox, its ids, the watchdog and the capture carry on. One line once
  the new session's first frames are back, e.g. "Encoder (hardware HEVC
  3024×1964): frames took 29 ms each (31 fps out of 51 captured); a new
  session takes 9 ms (a 329 kB keyframe, 28 ms between frames).", or "…
  takes 28 ms, no faster, so this stream keeps it and gets no other (…)".
  Nothing else prints and no counter changes.
- With encoder-recovery: a frame's clock starts at its hand-over, as before,
  so making a session counts against no frame, and the watchdog, `onHung`,
  the software fallback and the re-check never see a swap (the encoder check's
  E7: no `onHung`, no `enc.hung`, no hang or stalled line; none in the
  hardware runs either). A new session that hangs is a hang like any other:
  the watchdog gives up on it 1.5–2 s after the swap and the stream falls
  back, and the old session, retired holding nothing, is not reported
  stalled. A waiting new session is dropped when the stream's session dies
  (the watchdog, `abandon`), with the encoder, or when it is made after the
  encoder went.
- `SILL_TEST_ENCODER_RECYCLE=1` or `0` overrides the constant for one process
  (an A/B from one binary; a "TEST:" line says so).

Measured alone on the engine with the solo measurement's method (its scripts,
guards and motion window, copied): the CLI built from c27d6df by `git
archive`, the real Desktop at 3024×1964, 60 fps and 40 Mbps to a loopback
test client, this M2 Pro on AC power. No device connected (Sill.log's last
connect 18:50:52; the guard before and after every run), no user input
(HIDIdleTime rising through every run), and each run's HeartBeat listing only
its own sessions (the stream's and, switched on, its replacement, both
3024×1968 at 40 Mbps and priority 0) besides one-frame 256×256 launch probes.
Schedule: 4 s of motion, 10 s still, 35 s of motion, the switch on and off
alternating, three runs each; the fast state: 35 s of motion from the start,
two runs each. Figures are the resumed motion less its first 2 s:

| | fps out (min–max) | drops/s | turnaround med / p95 ms | capture→output med / p95 ms | C/F ms |
|---|---|---|---|---|---|
| on | 57.3, 57.3, 57.2 (55–59) | 0 | 16.3–16.6 / 16.7–17.4 | 17.4–17.6 / 25.0–25.5 | 8.7–9.0 |
| off | 34.5, 34.5, 34.2 (33–36) | 22.7–23.2 | 29.0–29.1 / 29.2–29.8 | 39.5–39.8 / 51.1–51.7 | 13.9–14.0 |
| fast, on | 57.2, 57.0 (54–59) | 0, 0.2 | 16.3 / 16.7–17.4 | 18.5 / 25.1–28.2 | 9.0 |
| fast, off | 57.3, 57.2 (55–59) | 0 | 16.3–16.4 / 16.7 | 17.5–17.7 / 25.1–25.2 | 9.0 |

- Each run switched on replaced its session once, 1.80, 1.83 and 1.85 s into
  the motion. The new session's first frame, a forced keyframe of 247, 322 and
  369 KiB (the stream's first keyframe was 280–372 KiB, the 4 s safety
  keyframes 437–772 KiB, a delta frame ~30 KiB), came out 30.2, 27.8 and
  27.5 ms after the old session's last frame: the slow state's own spacing
  just before (29.6, 29.1, 29.0 ms), so no frame waits longer than a slow one
  did. Its next 30 frames took 9.5, 9.3 and 9.0 ms (median), then ~16 ms paced
  to the capture, as a fresh session does. The second holding the swap put
  out 46–54 frames, every later one 55–59. The parameter sets were byte for
  byte the stream's first ones (one hash across 11–12 sets), so a device's
  display layer has nothing to flush.
- Motion from the start never set it off (one session in each fast run).
  "fast, on" run b's 1–2 drops a second over four seconds came with the
  loopback ping's maxima at 6–8 ms and the turnaround steady at 16 ms: the
  host, not the encoder.
- One more run switched on, with two still spells (4 s motion, 10 s still,
  15 s motion, 10 s still, 15 s motion): replaced twice, 1.8 s into each
  resumed motion and 25 s apart, keyframes of 261 and 324 KiB, 26 ms between
  frames each time, then 9.0 and 9.8 ms a frame and 55–59 fps.
- Kept, on by default: the slow state is a session's, a new session starts
  fast, and the price is one keyframe smaller than the 4 s safety one with no
  wait beyond the slow state's own.
- The checks: `run.sh slowstate` (798 checks: the rule at its edges, and
  streams in virtual time through a stand-in for the glue) and
  `mutants-slowstate` (20 of 20 caught); the encoder check's E7, the real
  `HEVCEncoder` against FakeVT (97 checks switched on, 12 off); the rest as
  before (the mailbox 38,256 and 27 of 27 mutants, the probe 19 and the hold).
  The CLI against origin/main (1f3072a), each built from `git archive`
  (dd0dc15 here), no device connected, each run's HeartBeat only its own
  sessions: `--synthetic` idle for 35 s identical masked and sorted (7 lines;
  in order too but for where the installed-apps line lands). With a loopback
  client streaming the synthetic Desktop for 22 s (origin/main four times,
  this branch six, alternating as another session's hosts allowed): no new
  kind of line, no new stats key, no "Encoder" or "TEST:" line, and one
  stream session each (nothing replaced). Which counters a second lists
  varies from run to run in both builds: with the first streaming second and
  the client's last left out, origin/main's four runs and three of this
  branch's six are identical; the other three differ by 6 and 2 mailbox drops
  in the seconds after a start that fell 80 ms before a stats tick, by one
  mailbox drop, and by `cursor.shape` in two seconds (the Mac's cursor
  changed).
- Not measured: Sill.app (the CLI only; the same core), a device (the keyframe
  over Wi-Fi, its decode), 120 fps, other bitrates, a shared engine (a new
  session there should be judged no faster and kept: the checks only), a size
  the engine is slow at (never replaced: the checks only; since the review
  fixes, one hardware run at 6880×2880, below), other chips, other content
  than the scrolling window.
- Merged with main at 32d532b (2026-09-26; one merge commit, not a rebase):
  since 4fe37d4 main gained remote access (#13), encoder-recovery itself
  (#11), follow-best-path (#12, #16), App Store readiness (#14), the public
  README (#15) and GitHub Actions (#17). Git stopped only on CLAUDE.md and
  README.md; the sources merged by themselves (this branch changed only a
  comment in `StreamCoordinator`, which main also changed). README.md is
  main's, the public front page; this branch's slow-stream bullet and its
  Resolution note moved to `docs/DEVELOPMENT.md`, "What to try if it's
  slow", as the Public README entry asks. CLAUDE.md keeps main's newer copy
  of "The hardware encoder: busy, not stuck", with this branch's sentence on
  the Simulator panel in its operational rule, and these two sections moved
  from after it to just before it; the Layout and Build and run keep both
  sides.
- Review fixes (2026-09-26, after the merge; 78f0459, d1d673c, 5217f55,
  0138d6a):
  - The order at the swap: `submit` completes the old session before the new
    one's first frame goes in ("The swap" above). The review found the old
    session's last delta reaching `onEncoded` after the new keyframe whenever
    its callback thread was held about as long as the keyframe took: with
    FakeVT, and on this Mac's hardware with the handler held on purpose (at
    20 ms and more at 1280×800, 40 ms and more at 3024×1964); a Mac decoder
    given that order failed every frame until the next keyframe. With the
    wait the order held 8 of 8 on the hardware, the wait ending 0.07–0.13 ms
    after the handler. E7 now holds the old session's handlers 20 and 40 ms:
    the order holds, and a copy without the wait fails at both, 3 runs of 3.
  - The rule ("The rule" above): slow against the session's own fastest
    frame, no faster against the session replaced, only frames in motion
    timed, the input per second as documented. The review's hardware runs of
    62f2c16: at 6880×2880 and 60 fps (the Desktop of a 3440×1440 display at
    scale 2; 24.65 ms at best, 25.5 at the median) the session was replaced
    2.02 s in for nothing in both runs (a keyframe, a 52–59 ms wait, "no
    faster"); at 3024×1964, with the motion stopping at the swap and 4
    repaints a second after, the new session was judged "no faster" on sparse
    frames (29–30 ms from 0.56 s on) though it ran 15 ms a frame once motion
    came back, and the stream then stayed at 34 fps for good. The review
    suggested twice the fastest frame; it is 1.5, since the slow state is only
    1.8 times the paced fast state (29 ms against 16), and a session whose
    best frames came paced or sparse would never be replaced at twice.
  - The mailbox and slow-state checks moved to `Tests/checks`
    (`encoder-mailbox`, `encoder-slowstate`), which CI runs, their mutants in
    its mutants matrix; `Scripts/encoder-check/run.sh` runs them as before,
    with the real-time probe and encoder checks, which stay out of CI.
  - Verified (2026-09-26, 00:20–01:03), without the hardware: the mailbox
    check 38,256 and 27 of 27 mutants; the probe check 19 and the hold; the
    encoder check with FakeVT 111 switched on and 12 off; the slow-state check
    1,207 (798 before; 62f2c16's rule fails 77 of the new cases) and 29 of 29
    mutants; `Tests/checks/run-all.sh`, all eleven (112 s); a clean `swift
    build -c release` of 0138d6a from `git archive` (only the CaptureProbe
    warning). With the hardware, no device connected (the guard before, every
    2 s during and after each run) and each run's HeartBeat listing only its
    own sessions: the CLI against origin/main (32d532b), both from `git
    archive`, idle 35 s identical masked and sorted (7 lines), and with a
    loopback client streaming the synthetic Desktop for 22 s identical (40
    lines; nothing replaced). The harness with 0138d6a's `HEVCEncoder` and
    synthetic moving bars: the review's schedule at 3024×1964 and 40 Mbps (3 s
    motion, 6 s of a frame every 0.3 s, motion until the swap, 3 s at 4 frames
    a second, 3 s motion, 6 s at one every 0.3 s, 7 s motion) swapped 1.77 s
    into the motion and said at once "… and the picture went still before it
    could be timed."; the motion after ran 15.1 ms a frame (56 fps); after the
    second still spell 29 ms for 2 s, then a second swap 13.78 s after the
    first ("a new session takes 9 ms") and 59–61 fps. At 6880×2880 and 15
    Mbps, 12 s of motion from the start: no replace (24.64 ms at best, 32.8 at
    the median, the engine slowing to ~33 ms after about 4.5 s, as the review
    saw).
  - Not measured: the order fix or the new rule in Sill.app or SillHost with
    ScreenCaptureKit and real content, the iPad's decoder at a swap, other
    sizes, rates and bitrates.
- **Untested, for Noah:** stream the Retina Desktop from Sill.app to the iPad,
  leave the screen still for a few seconds, then scroll: about 2 s into the
  scroll the log shows one "Encoder (hardware HEVC …): frames took 29 ms each
  …; a new session takes 9 ms …" line and `enc.out` climbs back to
  `cap.complete` with no `enc.mailboxDrop`; on the iPad the picture does not
  flash or go black at that moment and the frame age does not jump. A scroll
  that stops about 2 s in, as that line would come, gives "… the picture went
  still before it could be timed." instead, and the next scroll after a still
  spell gets another new session. Beside the Simulator panel (another app
  encoding), at most one "no faster" line per stream.

**The hardware encoder: busy, not stuck (2026-09-24; fixed 2026-09-25, branch
`encoder-recovery` from main at 76366e8, with main at ba91136 merged in: the
bullet before the last).** Sill.app's watchdog fired twice on 2026-09-24 and
both times the host stayed on the software encoder until it relaunched, which
was Noah's poor frame rate (~3 h at 1512×982, 46–55 fps with motion, 6–46 fps
at the end, through 18 settings changes the fallback's caps made useless). The
kernel's AppleAVE2 log (every hardware session's open with its size, bitrate
and firmware "Priority", and a HeartBeat every 5 s listing each session's
frames submitted | completed) shows neither was a wedge:
- 19:00:21 (40 Mbps, the Retina desktop at 60 fps, a 61 s old session): the
  iOS Simulator's screen recorder (SimRenderServer, what `simctl io
  recordVideo` drives: H.264 2064×2752 of the iPad Pro 13" simulator, 38 Mbps,
  priority 80) shared the one encoder engine with Sill and an agent's `SillHost
  --synthetic` (both priority 0). Sill fell to 7–8 fps, then its frame waited
  ~8.6 s; the invalidate blocked 7.06 s, off-thread, and the frame completed
  0.3 s after the other SillHost process died. A fresh 256×256 probe answered
  within 270 ms with the recorder still running, while the next stream-size
  sessions stalled again (0.3–9.5 s).
- 23:30:04 (150 Mbps, a 36 s old session, running 57–58 fps alone): the
  recorder opened a session at 23:29:45.2 and Sill fell from 58 to 22 fps in
  that second, then ran 13–45 fps; a frame waited ~1.8 s and completed (the
  invalidate took 0.17 s). A near miss at 23:27:54 (57 → 2–34 fps) came from
  the same recorder. The render and the benchmarks named at the time ran later.
- 424 hardware HEVC sessions from 17:40 to 02:30: 47 overlapped a recorder
  session and 7 of those stalled (median 39 fps); the other 377 had no stall
  (median 60), including a priority-0 H.264 2064×2752 benchmark beside HEVC
  3024×1968 at 40–150 Mbps (both 28–46 fps, a fair share). Ruled out: the
  bitrate (hang 1 was at 40 Mbps), 120 fps (both at 60), session churn (22
  bitrate restarts ran clean) and invalidating with a frame inside (both
  frames completed). No "Frame POC timed out" line, the 2026-09-22 signature,
  anywhere in the period (the log store no longer has 09-22's AppleAVE2 lines).
- Priorities, measured with one 256×256 frame per configuration: real-time
  HEVC and H.264 0, not real-time 0, `EnableLowLatencyRateControl` 60 (RCMode
  20), the recorder 80. No public key sets it. One engine on this M2 Pro:
  unthrottled HEVC 3024×1968 runs ~105–115 fps (~650 MP/s), so the Retina
  desktop at 60 fps takes 55–65 % of it and any other encode costs Sill frames
  without a hang (a 3024×1904 test beside Noah's 1512×982 desktop: both at
  57–60 fps for ~4 s, then both at ~50, 2026-09-25). A Retina desktop at 120 fps
  (~713 MP/s) exceeds it alone (untested).
- A bitrate change still needs a new session (measured 2026-09-25, 1512×948 at
  60 fps, blocky noise): VideoToolbox takes AverageBitRate and DataRateLimits
  on a live session and reads them back, but the hardware HEVC rate control
  does not follow: raised 8 → 40 Mbps the output stayed at 9.6 Mbps for 5 s,
  across an IDR and a forced keyframe (a session made at 40: 28 Mbps); lowered
  40 → 8 it dropped 41 of the next 60 frames. Hardware H.264 the same. The
  software encoder follows (7.9 → 19.5 Mbps in 2 s) and so does low-latency
  rate control (8 → 38 Mbps within 1 s). `restartNeeded` keeps the bitrate.
- `VTCompressionSessionInvalidate` waits for a frame still inside (17 ms for a
  3024×1898 frame in flight, whose output handler runs first).

What the host does now:
- The fallback is temporary. `enterSoftwareFallback` (a hardware hang, or the
  launch probe) says "… (busy or stuck); switching to the software encoder at
  half scale until the hardware keeps up again (next check in 30 s)." While a
  device is connected (an idle host opens no session; the task ends with the
  last device) `recheckLoop` tests the hardware at the size the stream would
  have on it (the running one's at full scale, else the Desktop's):
  `EncoderProbe.throughput` sends a moving pattern through a quiet session (no
  line, no counter: the stats line's `enc.out` is the menu's fps), one frame
  at a time like a stream, on a user-initiated GCD thread, and measures the
  rate the last 7 of 10 frames come back at; its 3 frames are drawn before
  the session opens and reused, and the first pass over them is left out
  (~110 ms at 3024×1904 when the engine is free, ~120 fps; ~290 ms at
  6016×3384, ~39 fps). At the rate a return needs or more
  (`EncoderProbe.returnBar`: 0.75 of the stream's rate, 60 at most, the
  software encoder's cap, so 45 fps; but never more than 0.75 of what the
  engine does alone at the test's size, from the best pixel rate any test
  measured this run, 400 MP/s until one has) `hardwareIsBack` waits out a
  switch, clears the flag and restarts a running stream on the hardware, like
  a settings change (no focus change): "Hardware encoder is back (121 fps at
  3024×1896 in a test, 45 needed); restarting the stream on it." (or "the
  next stream uses it"). Slower: "Hardware encoder answers but is busy (8 fps
  at 3024×1896 in a test, under the 45 fps a return needs; another app is
  using it); next check in 60 s". No frame in 1 s: "Hardware encoder still
  not answering after N ms; next check in 60 s". Either doubles the interval,
  up to 300 s; so does a hang within 5 min of a return; a return that lasted
  10 min resets it to 30 s. The first device after none gets a check at once
  when the last is 30 s old, so its stream starts on the hardware (a software
  start ~20 ms before is replaced). A hang reported by an encoder no newer
  than the last return (`HEVCEncoder.serial`) is stale and ignored. One loop
  and one test at a time: `stopRecheck` only cancels, and the task clears
  `recheckTask` once its loop has ended, so a device that connects during a
  test gets no second loop beside it (the ending task's tail starts one); a
  test that ends with no device left is dropped without a line or a backoff.
- Why a rate at the stream's size and not one small frame: at 03:26 on
  2026-09-25, with another agent's Simulator recording (priority 80) and a
  second SillHost on the engine, a 256×256 frame answered in 72 ms, the
  stream went back to the hardware and ran at 12 fps there (it had run at ~57
  on the software encoder), and no watchdog fires for a slow stream. Noah's
  own Sill.app sat at 8–18 fps in the same minutes, and at 03:32:02 it fell
  back once more (16, then 2 fps, then the watchdog), which the old build
  keeps until it relaunches.
- Why the bar follows the size (review, 2026-09-25): a fixed 45 fps asked more
  than a free engine gives a large frame. Measured with the engine free (Noah's
  Sill.app on the software encoder), as the probe was (frames drawn inside the
  timing, utility QoS) and as it is: 6016×3384, a Retina 6K Desktop, 37 and
  39 fps; 5120×2880 50 and 53; 3024×1904 115 and 121. So a host streaming a 6K
  Desktop read "busy" at every check and stayed on the software encoder for
  good. Now the first check there needs 15 fps (400 MP/s assumed) and, learned
  from its test, the next 29; a starved session got a sixth of the free rate
  or less, so busy still reads busy.
- The session given up on reports on its way out: "Encoder (hardware HEVC
  3024×1898): the stalled frame came back after 3.0 s; the encoder was busy,
  not stuck." A stuck one never lets go, so it never prints.
- Probes whose frame never comes back each hold a blocked thread; with 8 out
  (`maxStuckProbes`, after 22–28 min of failed checks) the re-check stops
  probing and says once that the encoder is stuck and a restart of the Mac
  fixes it, and the menu shows "Hardware Encoder Stuck". A late frame counts
  out again (`EncoderProbe.onStalledProbeBack`): under 8, the host says "a
  check's frame came back after N s, so it is not stuck; checks resume",
  clears the menu's line at once (a device connected or not) and, with a
  device connected, checks at once instead of when the held-back loop wakes
  (300 s).
- Copy: the menu's "Hardware Encoder Busy — Streaming with the software
  encoder, up to 60 fps, until it is free again." (one line, 373 pt: a menu
  item's subtitle does not wrap, the old one was 422 pt) or "Hardware Encoder
  Stuck — … Restarting the Mac fixes this."; the Streaming pane says the same
  at length; `HostSettingsState.softwareEncoder`'s doc. The device's callout
  says "‹Mac›’s hardware encoder is busy or not responding, so for now streams
  run at up to 60 fps at Standard." (it said "until the Mac restarts"; it
  promises neither now, as hosts before this change keep the fallback until
  they relaunch), and goes away by itself when the host clears the flag.
- Test hooks, read once and inert without them: `SILL_TEST_ENCODER_HANG=N`
  (the first N hardware stream sessions hold frame 90 for 3 s before it goes
  in: a busy engine; it prints a "TEST:" line), `SILL_TEST_PROBE_HOLD=S` (every
  frame of every probe waits S s: 0.08 a starved engine, 2 a busy one, a huge
  S a stuck one), `SILL_TEST_RECHECK_SECONDS=N` (intervals N to 10 N instead
  of 30 to 300) and `SILL_TEST_PROBE_SIZE=WxH` (the re-check tests that size,
  as for a Retina 5K or 6K Desktop on a smaller screen).
- Diagnosis: `/usr/bin/log show --start '2026-09-24 18:55' --end '2026-09-24
  19:05' --style compact --predicate 'sender == "AppleAVE2" AND (eventMessage
  CONTAINS "HeartBeat" OR eventMessage CONTAINS "Resolution:" OR eventMessage
  CONTAINS "AVE : open" OR eventMessage CONTAINS "AVE : close")'` (a session
  whose completed count stops while its submitted one is ahead is starved;
  "Priority: 80" beside it is the recorder), plus `process ==
  "VTEncoderXPCService" AND eventMessage CONTAINS "videoencoder.peer"` to map
  sessions (the next "AVE : open") to client PIDs.
- Operational rule, from the same logs: while Noah streams, agents do not run
  `simctl io recordVideo`, SillHost streams, ReelRenderer or encoder benchmarks;
  each shares the one engine, and the recorder outranks Sill. The Claude app's
  iOS Simulator panel counts too: `claude-ios-sim` encodes the simulator's
  screen at priority 60 (~62 fps at 2064×2752), and Noah's Retina Desktop fell
  from 57 to 33–36 fps beside it (33–34 for its first 40 s), and to 11–18 fps
  while another agent's priority-80 recording of that simulator ran as well
  (8–17 with a SillHost besides; 2026-09-25, 15:14–15:24).
- Not in this change: `EnableLowLatencyRateControl` would put Sill at priority
  60 (above every default session, still below the recorder's 80) and follows
  live bitrate changes, but it changes the bitstream and rate control (frames
  dropped at 8 Mbps in the rate test): a flagged experiment with iPad tests.
Verified headless (the synthetic host; hardware runs kept to seconds, Noah's
Sill.app streaming beside them): clean build (only the old CaptureProbe
warning); the CLI against 76366e8 built from `git archive`, masked and
sorted: idle identical, and with a client and a bitrate change identical but
for `enc.mailboxDrop` counts, which follow the other encoder users of the
moment (either build had them); `SILL_TEST_ENCODER_HANG=1` with a client: the
hang at 1.5 s, the fallback, 1512×948, "came back after 3.0 s", back 30.0 s
later (114 fps in the test) and 3024×1898 on the hardware at 60 fps for 67 s,
the client getting frames every second but the hang's; `=2`, while another
agent's Simulator recording and SillHost came and went: the check at 30 s
"busy (25 fps …); next check in 60 s", back 60 s later at 114 fps, the
second hang 3 s after the return and "next check in 120 s"; with
`SILL_TEST_PROBE_HOLD=0.08` while the recorder and another SillHost really
shared the engine (the test's own hardware stream ran at 16 fps): "busy
(7 fps …)" at 30 s and "(8 fps …)" 60 s later, no return; the client leaving
during a fallback: no session from the host in the kernel log for 40–45 s
(the next check was due after 30), then a client again: the test at the
Desktop's size (112 fps) and back ~100 ms after its stream started on the
software encoder; `SILL_TEST_PROBE_HOLD=100000 SILL_TEST_RECHECK_SECONDS=1`
with a client picking nothing: the launch fallback, then checks 1, 2, 4, 8,
10, 10 and 10 s apart, all unanswered, and the stuck line after the 8th
unanswered probe (the launch one and 7 checks); `SILL_TEST_PROBE_HOLD=2`:
unanswered probes, each back 2 s later, never stuck; previews against
76366e8: only menu.txt (the copy and a new `software-encoder-stuck` sample,
its cards equal to the busy one's) and the General pane's "Running from" path
differ.
Review fixes (2026-09-25), verified headless: the host builds with no warning,
iOS Debug with only the old `StreamClient` one; `returnBar` checked on its own
(swiftc, 100,011 checks: 45 at Retina laptop sizes, also at 120 fps, 15 and 29
at 6K, a free engine always passes, always the lower of the two shares), four
mutants caught (the fixed 45, the engine term without its share, no 60 fps
cap, an assumed rate above this engine); the CLI against 76366e8 (`git
archive`), masked and sorted: idle identical, with a client and a bitrate
change identical (a first pair differed by one `enc.mailboxDrop` in the
base's first second); `SILL_TEST_ENCODER_HANG=1`: back 30.1 s after the
fallback ("121 fps at 3024×1896 in a test, 45 needed"), the client getting
frames every second but the hang's (40–57 fps on the software encoder, 60 on
the hardware); `=2` with `SILL_TEST_PROBE_SIZE=6016x3384
SILL_TEST_RECHECK_SECONDS=5`: "39 fps at 6016×3384 in a test, 15 needed", the
second hang and "next check in 10 s", then "39 fps …, 29 needed"; the
verifier's overlap run (`SILL_TEST_PROBE_HOLD=1000
SILL_TEST_RECHECK_SECONDS=4`, a device leaving during a test and another
arriving): one line, "next check in 8 s" (it was two, 8 then 16 s), none when
nobody comes back, and the second device's own check 8 s later;
`SILL_TEST_PROBE_HOLD=70 SILL_TEST_RECHECK_SECONDS=1`: the stuck line at
65.0 s, the launch probe's frame back at 70.2 s, "a check's frame came back
after 70.0 s, so it is not stuck; checks resume" and a check at once; with
the device gone by then, the same line at 70.2 s and the next device checked
the moment it connected.
- Merged with main at ba91136 (2026-09-25: PR #13, remote access; one merge
  commit, not a rebase). Git stopped only on `Scripts/sillclient.py`, and both
  sides stay: main's remote-door flags and LINK line, this branch's `kB=` each
  second. Checked by hand in every file both sides changed: `StreamCoordinator`
  has main's routes, kind 21, the kind 17 cap, Sill's own windows kept off the
  Desktop and the goodbye at quit beside the fallback and the re-check; the
  re-check runs while any device is connected, at home or through the remote
  door (both register in `StreamServer.clients`, which `onClientCountChanged`
  counts), and a return restarts the stream through `select` like any other
  restart (`switching` is set before main's new wait for Sill's own app). The
  menu lists the encoder's item (Busy or Stuck) before main's "Remote Access
  Can’t Start"; `HostStatus`, `HostSettings.swift` (the `softwareEncoder` doc
  beside the seven presets), `SettingsPanes`, `DebugHooks` (both sides'
  samples), README and the device's panel (this branch's callout beside main's
  route line and slow-link callout) keep both sides' changes. Verified: a clean
  `swift build -c release` (only the CaptureProbe warning); iOS Debug for the
  simulator and for a device (generic, signed, not installed; only the
  StreamClient capture warning); `make-app.sh` without `--install`; the
  return-bar check on the merged `EncoderProbe`, 100,011 checks, its four
  mutants caught; previews from the bundle against main's (built from `git
  archive`, both run from one path): identical but menu.txt (Busy for Not
  Responding, and the `software-encoder-stuck` sample) and that sample's two
  cards, equal to the busy one's. Not run at the merge: the CLI's output
  against main's (idle 35 s and a Desktop pick, masked and sorted) and the
  `SILL_TEST_ENCODER_HANG=1` run (the fallback, the stalled-frame line, the
  return ~30 s later), both kept off the hardware encoder because Noah's iPad
  was streaming from Sill.app the whole time.
- **Untested, for Noah:** a build of this branch in /Applications
  (`Scripts/make-app.sh --install --open` from this branch, which now carries
  remote access too, or from main, which has it since b50e224; only a new
  build comes back by itself). Then, with the iPad streaming the Desktop,
  `xcrun simctl io booted recordVideo /tmp/x.mov` on a booted iPad Pro 13"
  simulator: the frame rate drops, and within a minute or so "switching to the
  software encoder" and "the stalled frame came back" (the menu: "Hardware
  Encoder Busy"); while it records, "answers but is busy" at each check, 30,
  60, 120 s apart; stop the recording (Ctrl-C) and at the next check "Hardware
  encoder is back" and the full resolution on the iPad. Also a window stream
  and the virtual display through a return, and a 120 fps stream (the test
  asks for 45 fps at its size). On a Mac with a Retina 5K or 6K display, a
  return while the Desktop streams ("… in a test, N needed", N under 45 at
  6K). New with the merge: the iPad through the remote door (Tailscale) through
  a fallback and a return, the re-check running for it as for a device at home.

**Remote access merged with main (2026-09-25, branch `remote-access`: merge
0f7f50d of main at 76366e8 into 7f5f19d, not a rebase; the fix-up after it is
ee922db, the review's fixes 7200334–e8c7490).** Main's PRs #6–#10 (the Direct
Wireless fixes, the connect screen's Wired/Wi-Fi/Direct, the quality presets,
the route in Settings, prefer-cable) now sit beside remote access. Where the
two meet:
- Presets: seven, ascending, Low (4 Mbps) first, then Efficient 8, Balanced 15,
  High 25, Pro 40, Ultra 80, Extreme 150; main's 200 Mbps cap. A device may pick
  all seven (`SettingsChoices`); a host from before either change refuses the
  new ones and an older device shows them as Custom.
- The Mac card: `HostStatusSnapshot.Device.route` is main's home link
  (ClientLink: Wired, Wi-Fi, Direct) and `remoteRoute` the remote door's label
  ("through Tailscale", "over the internet", "by address"). `StatusText.routeWord`
  is the one place the card picks the word: the remote label first (its link
  would read Wi-Fi for a session over the internet), on the device's row and,
  while it is the only device, the source row after the Mbps, with no-break
  spaces so a wrap never splits it. `remoteDeviceCount` counts `remoteRoute`.
- StreamServer: the remote door's register-at-ready and origin gate carry main's
  link, read at registration and on path updates (a remote session gets none);
  Direct Wireless off disconnects only home clients on peer-to-peer Wi-Fi (the
  remote door never listens there, and who reaches it is Remote Access's).
- The device: `FoundMac` has the remote branch's route (network, direct,
  remote) and Mac ID with main's `method` and `wired`; a row ends in "Remote" or
  its method word (`FoundMac.word`, also for VoiceOver). `StreamClient.route`
  stays main's link word (the readout); a remote session's way in is
  `remoteRoute` (the route line, the 60 fps request, the slow-link callout), and
  it has no link word. The reconnect is the remote branch's (`reconnect`, saved
  Macs by Mac ID, then remote dials) with main's Direct-row rule (`directWait`,
  and `networkGrace` from the sightings; a remote dial's `networkGrace` counts
  from the same moment, the saved Mac's row going, in `savedSightings`, the
  sightings by Mac ID); every row dial, a tap's or the reconnect's, goes
  through `dial`, so a "Wired" row dials the cable first. The move to the
  network keeps its SessionLink fence and sets the session's route to network.
  `-SillConnect` takes `[::1]:P` (the address parser) and
  `fe80::…%en0:P` (split at the last colon). In the project file main's
  SessionLink keeps A015/F015 and DeviceIdentity moved to A01D/F01D.
- Verified without devices: `swift build` (only the CaptureProbe warning), iOS
  Debug and Release for the simulator and Debug for the iPad (only the
  StreamClient capture warning), `make-app.sh` without `--install`. Pure checks
  against the merged files: main's policy check 187 of 187 (main's own count
  at 76366e8) with 45 of 45 mutants (its 25, and the 20 older ones re-applied as
  text); the remote rules, RemoteDialPolicy and SavedMacs 60 of 60, 33 of 33;
  AddressList and PairingWindow 41, 15 of 15; OriginPolicy 66, 10 of 10; the
  protocol 188 and its 8 openssl cross-checks, 20 of 20; ClientLink 89, 14 of
  14; the SessionLink fence in its four modes, 5 of 5; the ledger check
  extended to seven presets (Low's own block, and an older host refusing Low,
  Ultra and Extreme in the random model) 90 with 5,000 runs, 3 of 3; the wire
  read and written across a9cc248, main, 7f5f19d and the merge, 16 of 16. The
  CLI's output, idle 35 s and with one client, masked and sorted, is main's and
  7f5f19d's. Previews against main differ only in the remote branch's own
  (36 files, and menu.txt's Low, Remote Access… and Pair iPhone or iPad…);
  against 7f5f19d only in main's (the route words, "still", the Streaming
  footer, the presets, the still-window card) and the remote-device card's
  source row, which now ends in "through Tailscale". Live on loopback: Extreme
  restarts at 150 Mbps and 200 is refused; Direct Wireless on and off keeps the
  port; pairing, a paired session and an unpaired key refused at the remote
  door; both doors at once, where Direct Wireless off (the en0 stand-in)
  disconnects a home client on this Mac's en0 link-local address and not a
  remote session from the same address, and the remote door's port never
  changes (a build without the remote-session guard fails this); the home
  door's caps and origin gate; the bare app's `-SillSetAfter` bitrate, Direct
  Wireless and Remote Access (one Settings line each, one restart in all),
  saved across a relaunch. On a simulator of its own: by address, the route
  word read; `-SillMoveTest 1` moved and fenced; `-SillPairURL` pairing and a
  remote session; the host gone and back, redialled remotely.
- Review of the merge (2026-09-25, after 3a7b501). Fixed: a lost saved Mac's
  automatic remote dial counts `networkGrace` from the moment its network row
  went (`StreamClient.savedSightings`, DiscoveryPolicy.sightings by Mac ID); it
  read `networkLastListed`, the last browser change while the Mac was listed
  (often the connect), so a Mac that blinked off the network at home was dialled
  through the remote door 3 s after the loss, and a remote session that wins
  that race is never moved home (the bug was on 7f5f19d already). The move's
  probe (main's `probeMove`) takes §3.7's caps (frames 32 MiB, anything else
  4 MiB: it closes, which ends the move) and, like `readPayload`, never keeps a
  message cut short. The panel's route line keeps its route whole when it wraps,
  as ee922db does on the card: at xxLarge on the 340 pt panels "Connected" /
  "through Tailscale · 48 ms", where the merge's no-break space before the "·"
  alone gave "Connected through" / "Tailscale · 48 ms". Two stale doc comments.
  Verified: a clean release build of the result (only the CaptureProbe warning),
  iOS Debug for the simulator (only the capture warning); the remote rules check
  64 of 64 (four new: the sightings by Mac ID, and the dial after an hour
  listed) with 35 of 35 mutants (two new, on the leave), main's policy check 187
  with its 25 and the 20 old mutants; an event model of the reconnect on these
  files: with the row gone at the loss the first remote dial moves from +3.2 s
  to +10.0 s (Sill quitting: +8.0 to +11.0 s), what the by-name sightings give;
  the probe copied verbatim into a loopback harness: Sill's traffic probed as
  before, an SSH banner and a 1.7 GB frame header closed at once (before, both
  held the move until its 5 s ran out, the second with the harness at 534 MB), a
  window list cut short and then the stream's end no longer taken as the Mac's;
  the CLI's output idle and with a client, masked and sorted, main's; on a
  simulator of its own `-SillMoveTest 1` and `to:` this Mac's `fe80::…%en0`
  (moved and fenced, the second gaining "Wi-Fi" at the hand-over),
  `-SillPairURL` pairing, a remote session and its automatic redial; 63 photos
  of the route line (seven layouts, three text sizes) identical to 3a7b501's but
  for the six at xxLarge on the 340 pt panels, and long VPN names wrap at the
  route's words, never inside one. The review's reruns on 3a7b501, none failing:
  on the simulator S4 and S5 13 of 13, S7 against a9cc248's host, S8 in short
  host runs (typed pairing through the relay, 60 fps through a VPN route and 120
  by address, the 300 ms callout), testS3OutsideLink and the three RF2 UI tests
  (the link test's Mac A a stand-in, not a second host), `-SillConnect` by this
  Mac's `fe80::…%en0` ("Wi-Fi") and `-SillMoveTest to:` it; the host gates
  H7–H12, H10(f) on the bare app, H15, H17 and a variant with `--remote` through
  Direct Wireless off (a fresh tag, only the scoped home client disconnected,
  the remote session streaming on), H18 and H19, and H14 (no base run), H16 and
  H20 shortened to keep each host under 60 s; main's Direct Wireless gates
  nohook, burst and appfail (the app's failed replacement disconnects the en0
  stand-in and keeps a paired remote session from the same address; a build
  without the guard fails it).
- **Untested, for Noah:** everything the entries below leave for the devices,
  now on the merged build, and in particular a remote session's card on the
  real menu (the label on the source row is a merge decision), a "Wired" row's
  reconnect after a loss (it goes through `dial` now), and the move to the
  network with remote access on. The grace: at home with a paired Mac and
  Remote Access on, quit Sill.app while the iPad streams and reopen it 7–10 s
  later; the iPad should come back on the home door (the host logs no remote
  client).

**Remote access (2026-09-24/25, branch `remote-access` from `a9cc248`; the plan,
its open questions and the results are in `docs/remote-access-plan.md`).** Bring
your own VPN (Tailscale, WireGuard into the home network) or, behind a switch
of its own, a port forward: a device paired once reaches the Mac from anywhere.
Every open question took its default. Steps 1–8 are committed, and so are the
fixes of step 9's first review round (below); the rest of step 9 is next.
- Two doors. The home door (today's plain TCP listener, Bonjour, unchanged for
  old iOS builds) now admits only this Mac's own networks, loopback and Direct
  Wireless (`OriginPolicy`), with caps (1 MiB messages, 4 kind-17 changes a
  second, a clean device name). The remote door (`RemoteServer`, port 7455) is
  TLS 1.3 only, both ends self-signed P-256 keys pinned by SPKI SHA-256, ALPN
  `sill/1` for a paired key, `sill-pair/1` only while a pairing window is
  open; pre-auth caps (8 pending, 2 per source, backoff after 5 of its own
  refusals), 8 sessions, remote clients evicted after 8 s of silence, forced
  keyframes at least 2 s apart. Kinds 18 (the signed MacInfo: Mac ID, name,
  addresses), 19/20 (one pairing request and its answer), 21 (Pair This iPad…,
  home door only) and 22 (goodbye) are skipped by older readers; the TXT record
  carries a recognition tag (`r`) only paired devices can read.
- Pairing: the Mac's window shows a QR code (`sill://pair?…`, pinned to the
  Mac's key) and a 12-digit code (Damm check digit; PBKDF2 600k), 5 minutes,
  single use, five wrong tries, and the address to type with the code:
  Tailscale's MagicDNS name and its IPv4 under it ("or 100.101.102.103"), else a
  Tailscale IP (100.64/10, else fd7a:115c:a1e0::/48), else this network's
  address with any other VPN's IP under it ("or 10.8.0.6"). Another VPN never
  takes this network's place, since NordVPN's or WARP's address answers from
  nowhere; which of the two goes first is Noah's call. `PairingWindowAddress`
  decides, pure (Noah, 2026-09-25: from an iPhone's hotspot this network's
  address answered nothing, the Tailscale name and address both paired;
  checked with swiftc, 80 checks and 35 of 35 mutants, and photographed as the
  previews' `pairing-novpn`, `pairing-othervpn` and `pairing-longname`).
  Sill.app: Settings › Remote Access (a fifth tab: the switch, the addresses,
  the port, paired devices, the internet switch with the router's answer, the
  address name, sleep), the menu's Remote Access… and Pair iPhone or iPad…,
  identity in the login keychain (`KeychainIdentityStore`; label "Sill Remote
  Access", service `me.saffer.sill.remote`), idle sleep held off while a
  device is connected remotely. The CLI's `--remote` uses a throwaway identity
  per run.
- iOS: `DeviceIdentity` (a Keychain key, this device only), `SavedMacs`,
  `RemoteDialPolicy` + `RemoteConnector` (the dial order, happy-eyeballs 1 s
  apart, every failure's words), Remote rows after the network's 3 s, the
  reconnect order after a loss, liveness on every route; the connect screen's
  "Add a Mac…" card (the VisionKit scanner or the typed address and code),
  `sill://pair` links only ever confirmed, Pair This iPad… as an overlay over
  the stream, the panel's route line ("Connected through Tailscale · 48 ms"),
  its Away from home group and the slow-link callout; the Low preset (4 Mbps,
  first of the seven on both sides) and 60 fps away from home.
- Verified without Noah's devices: the plan's H1–H24 headless (the CLI's
  output byte for byte, the pure checks with mutants, the doors' refusals and
  caps, no plaintext on the wire, no code or secret in any log, a 2 Mbps
  +150 ms relay with no eviction and the base's keyframe rate), the app's
  persistence and previews, and on the simulator S1–S8: about 200 photos at
  the Duo sizes, phones and larger text, taps and accessibility as XCUITests,
  live pairing (QR, typed, an outside link confirmed first), reconnects,
  every failure's words, an older host, and a slow link (60 fps through a VPN
  route; the callout at +300 ms).
- Review fixes (step 9, the plan's "Review fixes (step 9)"): a pick never
  streams Sill's own windows (the virtual display's lookup skips them; the
  Desktop looks for Sill among every window when the on-screen look missed it);
  the internet switch counts only while Remote Access is on; Remove changes
  nothing when the keychain cannot be written, and the pane says so; a spent
  code shows no QR; kind 18 lists no addresses before the Mac's first look,
  and a device keeps its saved ones on an empty or Remote-Access-off kind 18;
  an overlay pairing ties the session only to the same Mac (by its signed kind
  18) and takes that kind 18's addresses; the scanner never restarts a pairing
  by itself (after a failure, the same code only from a tap); a link confirmed
  over the stream keeps the overlay for its outcome; the overlay's typed path
  says "Enter the Code from ‹Mac›" and moves up while typing; the status line
  is announced; saved Macs are cleared only when no device key exists at all.
  Checked headless, on the simulator with three new XCUITests against live
  hosts, and against the pre-fix build (which fails them).
- **Untested, for Noah (R0–R13; the plan's Results say exactly what):** R0 the
  probes (the Secure Enclave key, the login keychain identity with your OK, the
  router probe, the scanner on the iPad, with a failed pairing's code held
  until tapped); R1 Tailscale setup and pairing,
  timed; R2 away on the hotspot; R3 leaving home mid-stream; R4 Wi‑Fi to
  cellular; R5 Tailscale off at either end; R6 sleep; R7 removing the iPad
  while it streams; R8 a rebuild keeps port, Mac ID and pairing; R9 Pair This
  iPad… at home; R10 the port forward; R11 Direct Wireless at the café; R12
  VoiceOver and a hardware keyboard (Esc never reaches an app in the iPadOS 27
  simulator; only ⌘. was tested); R13 mixed builds. Also the pairing window's
  Address row, live (only its offscreen previews were seen): with this build's
  Sill.app, Pair iPhone or iPad… reads this Mac's MagicDNS name with "or" and
  its Tailscale IPv4 muted under it (what `SillHost --print-reachability`
  lists); with the window open, Tailscale off on the Mac gives 10.128.0.34
  alone and a window 18 pt shorter, and back on the name and the "or" line
  return (the IPv4 alone for a few seconds, until MagicDNS answers, is
  expected; note it if it stays); each line selects without "or" and pastes
  (Universal Clipboard) or types into Enter Code Instead (a code works once:
  New Code, or reopen the window, for a second try); VoiceOver reads the "or"
  line as one element. And a decision: beside a VPN that is not
  Tailscale (NordVPN, WARP, a work VPN, your own WireGuard) the window shows
  this network's address with that VPN's IP under it; the other order, or
  this network's address alone, is one line in `PairingWindowAddress.choose`.
- Known: the simulator iPad Pro 13" is shared with other work, so a test that
  installs the app there can replace someone else's build (the iPad Pro 11"
  was used for S8); an unsigned simulator build cannot use the keychain on a
  fresh simulator (-34018): build it ad hoc signed (`CODE_SIGN_IDENTITY=-`).

**Quality presets (2026-09-24, branch `quality-presets` from main at
ad7fba2).** Noah's decisions: Maximum is renamed Pro; two presets above it,
Ultra (80 Mbps) and Extreme (150 Mbps), for the USB cable or very fast Wi-Fi;
the bitrate knob's cap goes from 100 to 200 Mbps per 60 fps (a 120 fps stream
still gets double, so Extreme at 120 fps is 300 Mbps); no Unlimited.
- `QualityPreset` (StreamProtocol's HostSettings.swift): Efficient 8,
  Balanced 15, High 25, Pro 40, Ultra 80, Extreme 150 Mbps per 60 fps,
  declared in ascending order, which is the order of the status menu's Quality
  submenu, Settings › Streaming and the device's Quality menu (all build from
  `allCases`). The raw values are the bitrates, so the rename changes nothing
  stored or sent: a Mac on 40 Mbps shows Pro. `QualityPreset.fastLinkNote` is
  the one sentence both ends add to their Quality footers ("Ultra and Extreme
  need the USB cable or very fast Wi-Fi; if the picture lags, step down."); the
  menu's Quality subtitle is unchanged.
- `HostConfig.validated()` clamps to 1–200 Mbps, so a launch argument or a
  hand-set default above that runs at 200 ("Custom — 200 Mbps"). A device still
  sets only presets: `DeviceSettings.accepted` checks `SettingsChoices`, which
  follows the presets, so it takes 80 and 150 unchanged, and refuses 200 or
  250 from a test client rather than clamping them. Kinds 16/17 unchanged.
- Mixed builds: a host from before this change refuses Ultra and Extreme from
  a newer device (the row goes back; VoiceOver hears "‹Mac› kept its
  setting"); an older device shows a newer Mac's 80 or 150 Mbps as "Custom —
  N Mbps", read-only, and 40 as "Maximum — 40 Mbps".
- Verified without a device: clean builds (only the old CaptureProbe and
  `StreamClient` warnings); the CLI's synthetic output, idle and with a client,
  equals ad7fba2's (masked and sorted; unmasked only timings and ports
  differ); a test client's Extreme then Ultra restart the stream at 150 and 80
  Mbps ("Settings from sillclient: bitrate 15 → 150 Mbps per 60 fps"), Extreme
  at 120 fps runs at 300 Mbps, and 200 and 250 Mbps are refused with the value
  unchanged in the answer; the bare app runs `-SillSetAfter` and `-bitrate`
  250 Mbps at 200 ("Settings: bitrate 15 → 200 Mbps per 60 fps", devices told
  200) and saves a device's Extreme across a relaunch; the hardware encoder
  takes and reads back AverageBitRate up to 400 Mbps at 3024×1898; previews
  against ad7fba2 differ only in menu.txt's Quality rows and the Streaming
  pane's footer; the ledger check (H2) with the six raw values and 5,000
  random runs; the panel in the simulator at 1000×710 and 500×710 (also at
  xxLarge text), menu open and closed, picking Extreme, and live against this
  host (a restart at 150 Mbps) and against ad7fba2's (refused, back to
  Balanced); the harness's `vdstream` case, now Extreme at 120 fps (300 Mbps,
  the longest readout), at all four sizes and at xLarge and xxLarge text: the
  readout wraps at xxLarge, and at 710×500 already at xLarge; the header and
  Disconnect stay put and the rows scroll.
- **Untested, for Noah:** Ultra and Extreme on the iPad over the USB cable and
  over Wi-Fi, streaming a busy window (the synthetic pattern compresses to
  under 1 Mbps whatever the target): watch the frame age in the host's
  `client …` lines and the menu's device row, and step down if it climbs.

**Direct Wireless Connection (2026-09-24, branch `direct-wireless` from
`ipad-host-settings` at 35a1238; the plan and its measurements are in
`docs/direct-wireless-plan.md`).** Noah's decision: AWDL off by default on both
ends, and an opt-in host setting named Direct Wireless Connection in the Mac's
Settings and menu and in the device's panel. `includePeerToPeer` on the host's
NWListener made its Bonjour registration include AWDL, which the kernel counts
as an AWDL service ("Enabling AWDL due to Mdns"); the Mac's one radio then left
its Wi-Fi channel up to ~97 ms every 524 ms (see the trackpad-stutter section).
- Wire: `StreamSettings.directWireless` and `HostSettingsChange.directWireless`,
  optional: nil is a host without the setting, which gets no row, and the
  device ledger's rule 9 never sends a field the host did not report. Kinds
  16/17 stay compatible both ways (old device: ignores the key; old host: the
  device sees nil).
- Host: `HostConfig.directWireless`, off in `standard` (the CLI and a fresh or
  updated Sill.app), accepted from a device on every host, and absent from
  `restartNeeded`: it is the listener's. `StreamServer` builds the listener
  with `makeListener(peerToPeer:port:)`, with the setting when it is given
  before `start()`; after that `setPeerToPeer` replaces the listener live on
  its queue: cancel, wait for `.cancelled`, bind the same port at once with no
  service, advertise 1.5 s later (re-registering the same name within
  milliseconds of dropping an AWDL registration orphaned the awdl0 record for
  minutes; 0.25 s and more never did). Accepted connections are independent of
  the listener, so streaming devices never notice; one line per applied change
  ("Direct wireless on: listening on port P again, advertised again."). Except
  when it turns off: once that replacement is advertised (or has failed for
  good), every device still on peer-to-peer Wi-Fi is disconnected, one line
  each ("Direct wireless off: disconnecting iPad (…) at fe80::…%awdl0.N, which
  was connected over peer-to-peer Wi-Fi; it can reconnect over the network."),
  because an open awdl0 socket keeps the kernel's AWDL up (Noah's sessions,
  2026-09-24: off changed nothing while the iPad was on awdl0). `ClientLink`
  reads the route from the endpoint's scope (`%awdl0`/`%llw0`; AWDL has only
  link-local addresses); other clients are untouched, and a burst that ends on
  disconnects nobody. Requests coalesce (newest wins), and late callbacks of a
  replaced listener are inert. No `.cancelled` within 1 s or the same port
  refused: any port, with a line; both refused: the existing listener-failure
  rule (the app shows "Not Visible on the Network" and keeps running, the CLI
  exits 1), and the next toggle retries. CLI: `--direct-wireless` prints one
  startup line; without it the output is the branch point's byte for byte
  (masked and sorted).
- Sill.app: Settings › General "Direct wireless connection" right after
  "Visible on your network as", and a "Direct Wireless Connection" item at the
  top of the status menu's second group, absolute like Virtual Display. Saved
  under `directWireless`; an existing install has no key, so it comes up off.
  The status menu's card ends each device's row in how it reaches this Mac
  (Noah, 2026-09-24, branch `connection-route-in-settings`: "next to bitrate"),
  and while exactly one device is connected the source row too, after the Mbps:
  "Wired" (the cable's anri0, or any wired Ethernet interface), "Wi-Fi" or
  "Direct" (awdl0, llw0), else no word (loopback, a VPN, a path that says two
  things). `ClientLink.route` reads this Mac's side of the device's own
  connection, by the witnesses `runsPeerToPeer` uses (so Direct is exactly what
  turning Direct Wireless off disconnects): the address's scope, typed by the
  address itself, else the path's interfaces when they all agree (a connection
  to this Mac's own address lists en0 and lo0: no word). Read when the client is
  ready and on each path update, shown only (`HostStatusSnapshot.Device.route`);
  no wire change. Each end names its own link, so an iPad on Wi-Fi streaming
  from a Mac on Ethernet says "Wi-Fi" while the card says "Wired". A still
  picture's rate reads "120 fps, still", as wide as a one-digit count ("5 of
  120 fps"): "120 fps, nothing changing" (the plan's copy) plus the word
  wrapped the row only while still, and the open menu, which resizes the card
  on every change, jumped a line each time a window stopped or started
  changing. The wording is Noah's call. Over 405 layouts (three sizes, 60 and
  120 fps, 8 to 200 Mbps, each word or none, each suffix, the real StatusCard)
  a row's line count never changes between still and changing unless the
  count's own digits change it (16 layouts, all without a word; with "nothing
  changing" 198 did); the `still-window` preview is the widest case the menu
  offers. Verified: the link check at 89 (PR #6's 40 plus 49;
  `swiftc -package-name sill`), 14 mutants caught; the real host in a scratch
  package (loopback, `fe80::1%lo0` and `::1` clients: no word; with the lo0
  stand-in, Direct on the device rows and on the source row only while one is
  connected); previews: only the five cards with a device, the new
  `still-window` and their menu.txt lines differ from a1484f9; the CLI
  identical to a1484f9 (masked).
- iOS: the network browser and connections to the Macs it lists never use
  peer-to-peer. A nearby (peer-to-peer) browser runs only while not connected,
  and only when a Mac this device last saw with the setting on
  (`Sill.directWirelessMacs`, from each state, keyed by the Bonjour name the
  connection was made to, which is what the browsers list: the window list's
  "Mac" stays "Mac" when Bonjour renames a clash "Mac (2)"; a connection by
  address teaches nothing) is missing from the network 3 s after the connect
  screen began looking, or after Search Nearby (offered when nothing is listed
  after 3 s; once it runs, a muted "Also looking nearby" of the button's height
  takes the button's place whatever the status line says, VoiceOver announces
  it, and the idle status adds "and nearby" only when no hint shows); once
  started it runs until a connection is ready (`DiscoveryPolicy`, pure, checked
  with swiftc). A Mac seen only over awdl/llw is a "Direct" row, the one kind
  connected with peer-to-peer; a Mac the network lists is always a network row,
  so at home nothing takes AWDL. Each row ends in where the device sees its
  Mac (`DiscoveryPolicy.method`; Noah, 2026-09-24, branch
  `connection-method-labels`): "Wired" if the network browser saw it on a wired
  Ethernet interface, else "Wi-Fi" on a Wi-Fi one that is not peer-to-peer,
  "Direct" for a Direct row, else no word; never the Wi-Fi network's name,
  which needs the Access Wi-Fi Information entitlement and Location access,
  and Sill asks for neither. The word follows the browser as interfaces come
  and go (the cable in or out), and the DEBUG console says what it was read
  from ("discovery: <Mac>: Wired, seen on …"). A row that says "Wired" is
  dialled over the cable (Noah, 2026-09-25, branch `prefer-cable`: unpinned,
  with Wi-Fi and the cable both up, the same tap reached the Mac over `%en0`
  at 7 ms one time and over `%en14` at 1 ms another): a tap, an automatic
  reconnect and a move from AWDL resolve its Bonjour service on the first
  wired interface the browser saw it on (`DiscoveryPolicy.dialInterface`;
  anpi0 on the iPad, which the Mac logs as `%anri0`, 1–2 ms; en2 gives
  `%en14`), and a dial not ready within 2.5 s (`wiredWait`), or failing or
  waiting (at once), gives way to the row as listed, unconstrained, once,
  which can take Wi-Fi (DEBUG console: "dialing <Mac> on anpi0 (wired)",
  "wired dial did not connect in 2.5 s; dialing unconstrained";
  `-SillWiredTest HOST:PORT` runs that fallback in the simulator). The route
  is the Settings panel's (branch
  `connection-route-in-settings`): its readout ends in how this session's own
  connection reaches the Mac, "… · 15 Mbps · Wi-Fi", "Wired" or "Direct"
  (`DiscoveryPolicy.route`, `StreamClient.route`): the interface the Mac's
  address is scoped to (the cable and AWDL carry only link-local addresses),
  else the one this device's own address is on (an IPv4 connection's remote
  address has no scope), else the path's interfaces when they all agree, else
  no word (the simulator's path to its own Mac is lo0 alone). Read at
  `.ready`, again at a move's hand-over, and on those path updates of the
  session connection that describe it, satisfied and naming the Mac's IP
  address (`DiscoveryPolicy.describesFlow`, `sessionRoute`); any other update
  keeps the word. A connection to a Bonjour row also gets updates for the
  service's resolution, which name the service instead of an address and list
  "en0 (wifi), en0 (wifi)", the device's default route, whatever link carries
  the connection: on 2026-09-25, on the cable with Wi-Fi on, they turned a
  session's right "Wired" into "Wi-Fi" while its connection stayed on en2 (the
  Mac saw it on `%en14` at 1–3 ms throughout). The DEBUG console prints
  "session: <word>, read from …" and, for each update it skips, "session: kept
  <word>; ignored a path update without an address (for <service>): …".
  "Direct" there replaced the
  header's "Connected directly" line (the footer's warning and the switch's
  hint stay), and a no-break space before each "·" makes a wrap at larger
  text fall after one. The Mac's card names its own side the same way (see
  Sill.app above), so the two can differ (an iPad on Wi-Fi, a Mac on
  Ethernet). Verified: the policy check at 155 (138 plus 17 for the route),
  eight mutants of it caught; photos of the panel cases `default` (Wi-Fi),
  `wired`, `directlink` (Direct), `noroute` and `vdstream` at 1000x710 and
  500x710, and at accessibility-extra-large also at 710x500 (the readout wraps
  after a "·", never truncates, never splits "Wi-Fi"); live against a
  synthetic host: by 127.0.0.1 no word, by this Mac's `fe80::…%en0` "Wi-Fi",
  and `-SillMoveTest to:` from the first to the second gains "Wi-Fi" at the
  hand-over. What each end calls the cable (2026-09-25): iPadOS names its ends
  anpi0 and en2 and types both as wired Ethernet (the connect screen's row
  says "Wired", seen on anpi0, en2 and en0, and a session over it reads the
  Mac's address on en2); macOS names its end en14 (anri0 on other days; both
  up that night), wired Ethernet too (the simulator's browser saw both).
  The fix for the updates above, verified on the iPad: the policy check at 174
  (155 plus 19), 18 mutants caught (the route's 8 plus 10); "session: Wired,
  read from the Mac's address on en2" at `.ready` (a row resolved on en2 and
  tapped by a scratch build, and `-SillConnect` to the Mac's en14 address) and
  at a move's hand-over from awdl0, the host on `%en14` each time; a row's
  unscoped updates after
  `.ready` logged as ignored with the word kept (that session ran over Wi-Fi,
  `%en0` on the host: with Wi-Fi healthy the race took en0 in all three
  unscoped tries, and the night's cable session came right after an eviction
  on Wi-Fi). Until branch
  `follow-best-path` a session over the cable ended when it was pulled and came
  back over Wi-Fi, "Wi-Fi" on both ends, and plugged back in, an established
  Wi-Fi session stayed on Wi-Fi (TCP does not move) until the next connection;
  now it follows the cable (the step above). On
  the device, also compare each word with the host's "Client connected:
  fe80::…%anri0" line (`%anri0` or `%enN`: the cable; `%en0`: this Mac's
  Wi-Fi). Verified on the simulator: the policy check at 138, eight mutants
  caught; the `methods` and `nearby` cases at 1000x710 and 500x710; the rows'
  VoiceOver labels ("Mac Studio, Wired"); the live row for this Mac, "Wi-Fi"
  (lo0 loopback, en0 wifi). Reconnects match the name exactly ("MacBook
  Pro" and "MacBook Pro (2)" are two Macs) and take the network row at once, a
  Direct row only once it has stayed Direct for 6 s and the network last listed
  that Mac 10 s ago or more (`NetworkSightings`): a listener swap makes the
  network row blink for a few seconds, a Mac back on the shared network (Sill
  relaunched, the Mac awake) registers there and on AWDL together and the
  nearby browser can report awdl0 first, and mDNS is lost to radios that leave
  the channel. A tap is never held back. A session over AWDL moves to the
  network once the network browser (it keeps running while connected) has
  listed the same Mac for 2 s without a break: a network connection opens beside
  the direct one, and once its first window list names the same host it takes
  the session over (make before break: the Mac never drops to zero devices, so
  the stream and a staged window stay; the ledger, the Desktop rule and the
  panel's two seconds start afresh as on any connection, and the viewport goes
  out on the new one before the old closes); one that fails or has not shown its
  host in 5 s changes nothing, and the next try waits 10 s
  (`DiscoveryPolicy.moveToNetwork`, `StreamClient.moveToNetworkIfListed`). The
  same host: `WindowList.launchID`, a random ID each host launch puts in every
  window list (optional; hosts without it on both ends go by the name, as
  before), because a Bonjour name can belong to two Macs that share no link;
  a listing found to be another Mac is not tried again while it lasts
  (`sameHost`, `refusedListing`). The hand-over keeps what the device sends in
  order (`SessionLink`): the Mac never orders one connection against another,
  and a release sent on the fast one could overtake its press still in flight
  on AWDL (the button stays down, every later move drags), so the network
  connection is read at once but nothing goes out until a fence ping sent on
  the direct one after everything else comes back (the Mac echoes a ping only
  after reading all before it); messages wait in order meanwhile, one direct
  round trip, at most 3 s, or until the direct connection closes.
  On 2026-09-24 the iPad twice reconnected over AWDL at home (15:37:25,
  15:43:17) after an eviction on en0 and stayed there for minutes at rtt maxima
  ~265 ms. Local Network access denied (the network browser waits with
  PolicyDenied): the status says "To find your Mac, allow Local Network for
  Sill in Settings.", with no hint and no nearby search. The panel's last group
  is the row (never disabled), after the closing footer, with "Direct" ending
  the header's readout while this device's own connection runs over AWDL,
  and then, while the switch shows on, a warning in its footer and hint
  ("turning this off disconnects it"). The connect screen's column is anchored
  leading now, so its title no longer jumps
  sideways when a row or the hint appears; it is still centred vertically, so
  it moves up by half of what they add.
- Verified without permissions (the plan's H0–H15 and S1–S4): the kernel's
  AWDL service count (ValidSvc, baseline 2 from Noah's PR #4 Sill.app) rises by
  2 exactly for a registration made with the AWDL flag: `dns-sd -includeAWDL -R`
  and `SillHost --synthetic --direct-wireless` (test type) both 2 → 4, while
  `dns-sd -R`, the suffix form `dns-sd -R … -includeAWDL` (a TXT record, no
  flag) and the default host stay at 2; off, the test registration never
  appears on awdl0 (index 16), on it does 1.1 s after launch and leaves no
  orphan; live on and off under a streaming client: the same port throughout,
  frames every second, no restart, the awdl0 record added 2.6 s after on and
  removed 1.3 s after off; 55 connections across a replacement all accepted;
  five toggles in 0.4 s give one replacement; mixed with a bitrate change, one
  restart and one replacement; the fallbacks (SILL_TEST_SWAP_FAIL); the bare
  app saves it from -SillSetAfter and from a device and relaunches with it on;
  previews: only the General pane and menu.txt changed (one unchecked item per
  sample); the ledger check (43 checks, 5,000 random runs, 1,227 against a host
  without the field, three mutants caught) and the policy check (40); iOS
  Debug and Release with only the old warning; photos of the connect screen
  (looking, hint, nearby) and the panel (default, direct, directlink,
  nodirect, cli; scrolled) at the four Duo sizes and larger text; taps (Search
  Nearby, the switch); live by address against both synthetic hosts (the
  device's change: three host lines, same port, frames keep coming; a Mac-side
  change shows in the open panel; the app saves 1 then 0); the normal app on
  the simulator: no nearby search without memory, and with a remembered Mac
  that is missing it starts 3.8 s after launch (ValidSvc +1 until it quits)
  while the real Mac on the network stays a plain row. Review (one pass by the
  implementer, three lenses: wire and hard rules, the replacement's
  concurrency, the device UI), then adversarial re-runs of H2–H8 on the final
  build plus: a burst that ends where it started never turns AWDL on (ValidSvc
  constant, no awdl0 row) while 139 of 139 connections across two replacements
  are served; after a total listener failure the next toggle retries; the
  device toggling on then off while streaming (two replacements, same port,
  frames throughout, ends off on both sides). A second review's fixes (the
  plan's "Review fixes"), verified: clean builds; the CLI identical again;
  previews differ from the step before only in the Permissions panes; the
  policy check at 68 (the home race, the café case, denied; six mutants
  caught) and a replay of the status rule (13 states); photos of the connect
  cases (looking, hint, nearby, denied) and of Search Nearby tapped at the four
  sizes (the title does not move); the panel's warning goes when its switch
  is tapped off; an address connection to a host with it on writes no memory.
- Fixes after Noah's first sessions (2026-09-24, branch `direct-wireless-fixes`
  from a9cc248; the plan's last section has the log, the causes with line
  numbers and every check). W5 is answered: off never ended a direct session
  (its open awdl0 socket kept AWDL up), and now the host disconnects it; the
  reconnect and the move above keep a Mac on the network off AWDL; Control
  Center's Wi-Fi switch leaves the radio on for AirDrop, so a direct session
  survives it (only Settings › Wi-Fi or another network ends the shared
  route). Verified headless: the CLI identical to 22209db; `ClientLink` 40
  checks, five mutants caught; end to end with a link-local en0 client standing
  in for awdl0 (`SILL_TEST_PEER_TO_PEER_INTERFACE`): disconnected 1.5 s after
  off with one line, the loopback client streaming on, untouched without the
  variable, nobody disconnected by an off-on burst, disconnected also when the
  app's replacement fails; the policy check at 98 (blinks of 1.5, 4 and 7 s
  never take Direct, absent 10 s takes it at 10.0 s, the move at exactly 2 s,
  the café at 6 s, a 15:43 replay), seven mutants caught; on the simulator
  (`-SillMoveTest 1|refused`) the move hands over with the host streaming
  throughout (1 → 2 → 1 clients, no Desktop restart), a panel change after it
  is answered, and a refused network row leaves the session direct. Review
  fixes (the plan's "Review fixes of the move"): the hand-over fenced
  (`SessionLink`), the host checked by launch ID, and a move given up at 5 s
  ends before its connection is cancelled, so a late `.ready` cannot adopt it.
  Verified: the CLI identical again; the fence against a stand-in Mac whose
  first connection lags 120 ms (600 inputs from two threads, in order and
  complete; the old hand-over reordered 64; released by timeout and by the old
  connection closing), five mutants caught; the policy check at 111, five
  mutants caught; on the simulator the move behind a 150 ms delay proxy waits
  301 ms for its fence, then rtt 302 → 1 ms; `other:PORT` (another synthetic
  host) is refused at its first list and not tried again, the session streaming
  on; the panel shows the Mac's state after a move.
- **Untested, for Noah (the plan's W1–W9):** W1 the payoff: both builds
  installed, `/usr/bin/log stream --style compact --predicate 'process ==
  "kernel" AND (eventMessage CONTAINS "abling AWDL" OR eventMessage CONTAINS
  "ValidSvc")'` shows "Disabling AWDL due to no services and no active
  sockets" once the old Sill is gone (unless AirDrop, Sidecar or Universal
  Control hold it), and five minutes on a still window with trackpad strokes
  keep the `rtt m/M` maxima near the LAN's, with no ~100 ms spikes. W2 on from
  the iPad panel while streaming: no restart, one "listening on port N again"
  (same N), the Mac's Settings and menu follow, `defaults read
  me.saffer.sill.mac directWireless` is 1, "Enabling AWDL due to Mdns" and the
  maxima rise; off from the menu two minutes later and they fall back. W3 with
  it on, the iPad on the iPhone's hotspot and the Mac at home: within 3–5 s a
  "Direct" row; connected, the host logs `%awdl0`, and the panel's readout
  and the iPad's row on the Mac's card both end in "Direct" (the plan still
  says the header's "Connected directly"); note frame age and rtt. W4
  first use (reinstall, café
  conditions): the hint and Search Nearby after 3 s, then "Also looking
  nearby", the Mac as Direct; a relaunch there searches nearby by itself; once
  with Don't Allow on the Local Network alert: the status asks for Local
  Network and no hint shows, and allowing it in Settings brings the list back.
  W5 again (answered from the sessions; now with the fix): connected directly
  (the iPad on the iPhone's hotspot, the Mac at home), off from the Mac or the
  panel gives the "disconnecting … %awdl0" line within ~2 s, the iPad on its
  connect screen, and "Disabling AWDL" about 30 s later. W6 home → café while
  streaming with it on: reconnects directly within ~10 s without a tap (10 s
  since the network last listed the Mac); café → home (rejoin the home Wi-Fi
  while streaming directly): a second "Client connected" on `%en0`, then
  "Client left" for the `%awdl0` one, the picture never stops, the panel's
  readout goes from "Direct" to "Wi-Fi" (the plan: the header loses "Connected
  directly"), and the Mac's card shows the iPad twice for a moment (Direct,
  Wi-Fi), then once, Wi-Fi (drag and type through the move: no button stays
  down, no letters swap); and relaunching Sill.app at home, the iPad
  reconnects over the network (the host logs no `%awdl0`). The blink: at home
  with it on and the iPad streaming, quit and reopen Sill.app a few times, at
  once and after 15 s: the iPad comes back on `%en0` (on `%awdl0` only if the
  network takes over 6 s to list the Mac, and then it moves to `%en0` ~2 s
  after it does). Control Center: connected directly with its Wi-Fi switch
  off, the session goes on; off on the Mac then ends it. W7 relaunch Sill.app
  with it on: `dns-sd -t 3 -includeAWDL -B _sill._tcp local` lists one
  instance on awdl0, no "(2)". W8 the CLI with and without
  `--direct-wireless`. W9 mixed builds (PR #4 iPad with this host, this iPad
  with PR #4's Sill.app: both connect on the LAN, the latter with no row) and
  VoiceOver ("Mac mini, Direct", the hint, Search Nearby and its announcement,
  the row).
- Known, not fixed here: the simulator's browsers run in the Mac's
  mDNSResponder, so a nearby search on the simulator turns the Mac's AWDL on:
  never measure latency with a simulator sitting on the connect screen.
  Security: with it on, anyone within radio range running Sill can
  find and connect to the Mac until pairing (M5); the host-settings plan's §9
  payload cap and a kind 17 rate limit matter more with it on. It is the first
  device-writable setting that widens who can reach the Mac, against that
  plan's "a device sets stream quality, never network exposure": revisit it
  with pairing. A Mac is known by its Bonjour name for a reconnect, so another
  Mac of the same name running Sill on the device's network would be joined
  (pairing again; the move checks the launch ID, which a reconnect cannot, as
  the host may have relaunched). The host can print "Client left" twice for a
  connection that ends with a reset, as the direct one after a move may.

**iPad host settings (2026-09-23, branch `ipad-host-settings` from
`menu-bar-app`, rebased onto its e89add6; the plan and its reasoning are in
`docs/ipad-host-settings-plan.md`).** A device changes the Mac's five streaming
settings the way the Sill menu does: Quality (bitrate), Resolution (capture
scale), Frame Rate limit, Prioritize Speed, Virtual Display. Defaults taken for
the plan's open questions: Settings replaces Leave in every bar's last slot and
Disconnect moves to the panel's pinned foot (Q1); Sill.app saves a device's
change like a menu click (Q2); the virtual display has full menu parity, so
turning it off from a device brings the window home and forward (Q3).
- Wire: kind 16 `.hostSettings` (host → device, JSON `HostSettingsState`: the
  target settings, `persistent`, `virtualDisplayAvailable`,
  `virtualDisplayNote`, `softwareEncoder`, the running `stream`, and
  `answering` in the reply to one change) and kind 17 `.changeSettings` (device
  → host, JSON `HostSettingsChange`: only the fields one control changed,
  absolute values, a token strictly increasing per device process). Types,
  `SettingsChoices` and `QualityPreset` (moved from the app) are in
  `Sources/StreamProtocol/HostSettings.swift`. No ack, refresh or version
  kinds: a kind 16 on this connection means the host supports settings. Fields
  added later must be optional, never renamed or retyped, no enums.
- Host: `StreamCoordinator.setTarget` (synchronous; replaced `apply`)
  validates, forces the virtual display off without the AppKit loop, compares
  with the target (`pendingConfig ?? config`), publishes, and schedules the
  pipeline work in a Task, so a burst is one restart. The `.changeSettings`
  handler has no await: it keeps exactly the Mac menu's values
  (`DeviceSettings.accepted`; the virtual display on only under the AppKit
  loop, off always), logs "Settings from ‹device›: …" and "… refused: …", and
  answers that device alone. The state is a pure function of the target and
  the `HostStatus` snapshot, and both publish (`setTarget`,
  `HostStatus.onChange`), deduplicated, so the once-a-second stats send
  nothing; every device also gets it right after its window list. Nothing new
  prints unless a device sends kind 17 (the CLI's output is unchanged). A pick
  that lands during a restart of the active source now runs after it
  (`pickArrivedWhileSwitching`, newest wins, the restarted source itself
  dropped); during a switch to another source it is still dropped (the device's
  automatic Desktop request must not override a pick).
- Sill.app: `HostSettings.onChange` calls `setTarget` synchronously, so the
  target equals `settings.config` at every main-actor turn, and
  `onDeviceSettingsChange` lays a device's change over `settings.config`: saved
  (only the keys it changed), shown live in Settings and in the menu when it
  next opens. The CLI sets no hook: a device's change lasts until SillHost quits
  (`persistent: false` says so on the device).
- iOS: `HostSettingsLedger` (pure logic) holds the Mac's last state on this
  connection with this device's unanswered picks over it: a pick sends only what
  changes what is shown, nothing before the first state; an answer clears only
  the picks carrying its token (60 → 120 → 60 never shows 120); a refused pick
  goes back with the warning haptic and an announcement; a pick unanswered after
  max(4 s, 4 × RTT) goes back with "‹Mac› didn’t answer. Try again."; reset on
  tear-down, never persisted. `HostSettingsPanel` mirrors the Apps drawer on the
  trailing edge, lined up with the Settings button: 360 pt under the landscape
  bar (340 on the outer display), in portrait wholly in the lower half under the
  window bar; no dim (a clear catcher closes it without clicking the Mac);
  pinned header (the Mac's name, what runs, Done with Esc/⌘.) and Disconnect
  foot, the middle scrolling when short. Opening it takes the keyboard down
  (`InputOverlayProxy.setKeyboard`, so no key reaches the Mac) and closing puts
  it back. Only a control's action ever sends (`StreamClient.changeSettings`).
- Verified without permissions (the plan's H0–H21, S1, S2, S5, S6): clean
  builds (only the old CaptureProbe warning; iOS Debug and Release only the old
  `StreamClient` capture warning); the CLI's output masked and sorted equals
  the branch point and its idle stdout is unchanged; `sillclient.py` shows one
  kind 16 after the first window list and one when the Desktop starts, accept /
  no-op / refusals / partial / a burst of three (one restart) / two clients /
  rapid pairs 0–300 ms (at most two restarts) / reconnect / malformed and
  tokenless changes / 20 s idle (two states, CPU as before) / the toggle on the
  `--virtual-display` host (no restart); the bare app saves a device's change,
  keeps it across a relaunch, sends a `-SillSetAfter` change to the device,
  lets the device and the Mac change different keys at once, and every
  `-SillSetAfter` change still gives one "Settings:" and at most one restart;
  previews byte-identical; the ledger check (28 scenarios, 5,000 random runs
  with two mutants caught); the queued pick with a race client that sends the
  pick while the restart runs (before: 8 of 8 picks lost; now 24 of 24 stop the
  stream after one restart); 38 simulator photos of the panel (four Duo sizes
  × eight cases, iPad mini and iPhone sizes, accessibility-extra-large); taps
  through the harness; live by address against both synthetic hosts (the
  device's change logged, one restart, saved by the app; a Mac-side change
  shown; Disconnect); against the branch-point host the panel says to update
  and the client sends no kind 17.
- Review fixes (2026-09-23, after the rebase onto e89add6): the pick timeout
  reads the new `linkStats` (the worst round trip of the last second that
  measured one, kept through seconds without a pong); a pick queued behind a
  restart goes through the same rule as a fresh one (`handlePick`), so a
  restart that starts before its Task runs no longer drops it; a staged window
  that the virtual display turning off sends home comes forward whichever
  select commits that change (`cameHome`); the device holds back its automatic
  Desktop request when the user picked or launched something while it waited
  out a closed window (the race that remains, older devices and a pick sent
  before the device heard of the close, is written down at `handlePick`); the
  status menu's Virtual Display item sets the value it showed instead of
  toggling, so a click on a menu left open while a device changed it never
  undoes that change; in the panel the readout wraps instead of cutting off and
  "On the virtual display" is a line of its own, Done's tap area is 44 pt tall,
  and the speed switch is "Prioritize Encoding Speed" (the Mac's name) in its
  own group under the Mac's explanation; `sillclient.py` checks every argument
  before connecting; HostSettings.swift lists every place a new setting must
  go. Verified: the CLI's output against e89add6's (masked; idle, 35 s idle,
  the Desktop, `--virtual-display`); H4–H21 again, previews byte-identical;
  the race that lost 5 of 6 queued picks to a rate-change restart now loses 0
  of 10; 46 photos (a new `vdstream` case at every size and at larger text);
  iOS Debug and Release with only the old warning; taps 7 pt above and
  8 pt below Done close the panel; in portrait the header stays put while the
  panel opens (the Quality value moves 2 pt; it slid 32); against a fake host
  that never answers, a pick times out after 4.3 s with prompt pongs and 8.3 s
  with pongs held 2 s; against one that closes the watched window, the Desktop
  request follows 2 s later unless the user picks, and then never comes.
- **Untested, for Noah:** D1–D11 (the plan's §7.4): the panel's values
  against the Mac's menu and status card with a real window; every control from
  the iPad (one restart each; the Mac's Settings window follows; saved in
  `me.saffer.sill.mac` and after a relaunch); the virtual display on and off
  from the iPad, also full screen; a Mac-menu change showing in the open panel;
  two devices at once; `SillHost` without and with `--virtual-display`;
  reconnecting after a change made while away; the 60 fps note and Low Power
  Mode on the iPad mini; a Magic Keyboard (keys stop while the panel is open,
  Esc closes it and does not reach the Mac, keys come back); VoiceOver (modal,
  focus on the Mac's name, the escape gesture); a pick right after a change,
  and five minutes with the panel closed (frame age and RTT unchanged). Also
  rotating with the panel open and Reduce Motion (fade only), which the
  harness cannot drive; not run here: S3 (no Accessibility Inspector) and S4
  (no way to press a hardware Esc in the simulator from here). Also the Mac
  menu's Virtual Display item clicked after the iPad changed it while the menu
  was open (it should do what the item showed), and turning the virtual
  display off while another change is restarting a staged window (the window
  should still come forward).
- Known, not fixed here: in the layout harness, bringing up the software
  keyboard flips the fake screen into the portrait layout (the same at the
  branch point; the harness only). A Mac menu that is already open keeps its
  old checkmarks until reopened (every item sets the value it shows, so a
  click there never inverts a device's change).

**Sill.app, the menu bar host (2026-09-23, branch `menu-bar-app`; the plan and
its background are in `docs/menu-bar-app-plan.md`).** The same host as the CLI,
as an LSUIElement app. A status item whose glyph (drawn from AppIcon.svg:
idle, connected, streaming, attention) and menu card show the network, each
device with its fps, frame age and RTT, and the stream; a menu with Virtual
Display, Frame Rate, Quality, Resolution, Launch at Login (SMAppService),
Permissions, Show Log…, Settings… and Quit. Settings is an AppKit window with
four SwiftUI panes (General, Streaming, Virtual Display, Permissions), kept off
the virtual display; the Log window shows HostLog's last 5,000 lines, and
`~/Library/Logs/Sill/Sill.log` has them all. SwiftPM builds the `SillMenuBar`
executable; `Scripts/make-app.sh` wraps it (Packaging/Info.plist, an icon
compiled by actool from design/AppIcon.svg), signs it with the Apple Development
identity and, with `--install`, replaces /Applications/Sill.app. Bundle ID
`me.saffer.sill.mac`. Settings persist (`defaults read me.saffer.sill.mac`)
and apply live: `StreamCoordinator.setTarget` hands a new `HostConfig` to the next
`select`, which takes it between pipelines; a change restarts the stream once,
or not at all when nothing running depends on it (the virtual display toggle
restarts only a window stream, and sends a staged window home first). Virtual
display off by default in both the CLI and the app.
- Rules. Host code is the `SillHostCore` library (folder `Sources/SillHost`),
  reached with `package` access; make it `public` only if an Xcode target ever
  needs it (M5 CloudKit). Never `MainActor.assumeIsolated` in core code: under
  the CLI's dispatchMain the main queue drains on a worker thread and it traps;
  hop with `Task { @MainActor }`. The modal-loop rule (AppDelegate's doc
  comment): never start NSMenu.popUp, a runModal or a terminate that can answer
  .terminateLater from a Task, an async continuation or a main-queue block, only
  from AppKit target/action, SwiftUI Button actions or a run-loop Timer; errors
  show inline, never in alerts. The CLI's stdout stays byte-identical: core
  `print`s go through the shadow in HostLog.swift, which records nothing until
  the app configures it. App Nap: while a device is connected the app holds a
  latency-critical activity (napping would coalesce the 30 ms keepalive ticks).
- TCC: a grant belongs to the bundle ID plus the designated requirement
  (identifier + Apple anchor + the certificate's CN), so rebuilds signed with
  the same Apple Development identity keep it; ad hoc would lose it on every
  rebuild. Terminal's grants for the CLI don't carry over, and running
  Contents/MacOS/Sill from Terminal makes Terminal responsible. The app asks
  for nothing at launch (no Accessibility alert, no window list before Screen
  Recording is granted); Settings opens on Permissions until both are allowed
  or the user closes it. Allow… shows each system alert once
  (`askedScreenRecording`/`askedAccessibility` in the defaults), then opens
  System Settings, so recovering from a `tccutil reset` also deletes those two
  keys (docs/DEVELOPMENT.md, Permissions).
- Build facts. SwiftPM's default build system links without SDKROOT, so its
  executables record the deployment target as their SDK (`xcrun vtool
  -show-build`: sdk 14.0), and macOS 26+ draws such an app in the pre-26 look.
  make-app.sh writes the bundle's executable with vtool, recording the SDK in
  use (27.0 here) as Xcode would; the CLI and the bare SillMenuBar keep 14.0.
  It signs by the identity's SHA-1 hash (a renewed certificate with the same
  name makes the name ambiguous to codesign), and `--release` refuses anything
  but a Developer ID Application signature. NSTabViewController selects its
  first tab while `NSWindow(contentViewController:)` builds the window, so the
  Settings tab is saved only from an on-screen selection and from `show`.
- In the app only: regular mode trusts `NSWorkspace.frontmostApplication` (the
  AppKit loop runs), and turning the virtual display off brings the returning
  window forward (a product call).
- Verified without permissions: clean build (only the old CaptureProbe
  warning); the CLI's output matches the pre-change baseline line for line
  (sorted, digits masked) at 60 fps, exits 130/143 on the flag path; the bare
  app streams the test pattern at 60 fps, each `-SillSetAfter` change gives one
  "Settings:" line and at most one restart (virtual display on while the
  Desktop streams: none), Quit exits 0 through `releaseForQuit`, a saved setting
  survives a relaunch, idle CPU 0.0 %; the Settings and Log windows open and
  render; make-app.sh signs with the Apple Development identity, the designated
  requirement survives a rebuild, the icon renders as a native squircle, and
  the signed bundle streams and creates a virtual display under the hardened
  runtime. After the SDK fix the bundle (sdk 27.0) still streams at 60 fps,
  exits 143 on SIGTERM and creates and removes a virtual display, and its
  panes render in the macOS 26 look (the Streaming pane matches the design
  draft); `--release` refuses a missing, ad hoc or Apple Development identity;
  a stub harness showed the Settings tab now survives a relaunch.
- **Untested, for Noah:** N1–N12 in the plan: first run and the grants, the
  menu's live rows with the iPad, every control while streaming a real window
  (virtual display on and off, also full screen), Settings placement, Launch
  at Login, quitting with a staged window, App Nap and latency against the CLI,
  regular-mode input, revoking Screen Recording, the Log window, the CLI and
  the app side by side. Also the live menu and Settings window in the macOS 26
  look that the SDK fix turned on (only offscreen renders were checked), and
  Settings reopening on the last tab after a relaunch.
- Known, not fixed here: the CLI's synthetic mode still prints "Advertising
  _sill._tcp" although it no longer advertises.

Milestone 3, scaling and the virtual display. Two paths exist; adopt the second.

- **Fallback (shipped):** the Aa control, in every bar since 2026-09-22, is a
  button that unfolds into a linear slider while touched (camera-zoom style):
  five detents, 0.5× to 1.5× in 0.25 steps, neighbours fade, the value is
  applied once on release. The client sends its stream-panel size and wanted
  scale (`Viewport`); the host resizes the real Mac window through
  Accessibility (`WindowSizer`) to panel ÷ scale points, so text renders at
  that scale on the device. Until the slider is first touched the scale is nil
  and the Mac window is left alone (the control shows 1×). Harness:
  `-SillScaleOpen 1` photographs the unfolded state.
- **Virtual display (implemented 2026-09-22 behind `--virtual-display`, off by
  default; Noah flips the default after trying it).** With the flag, SillHost
  runs `NSApplication.run()` (activation policy `.prohibited`: no Dock icon,
  never activatable) instead of `dispatchMain()`, because only under the AppKit
  loop does the creating process see the display's modes. `select(.window)`
  asks `VirtualStage` to create one `CGVirtualDisplay` ("Sill", 2×, at the
  stream's rate),
  move the window onto it with Accessibility (`WindowSizer.placement/move/
  restore`; AX writes never activate or raise anything), and capture it with
  `SCContentFilter(display:including:[app])` cropped by `sourceRect` to the
  window's rectangle, so the device sees the window plus the app's own menus,
  popovers and sheets (separate windows, invisible to window capture) and
  nothing else. Deselect,
  switch, last client leaving, display lost, Ctrl-C/kill/hangup
  (`HostShutdown`) and `atexit` put the window back at its original frame and
  destroy the display. Any failure logs "Virtual display fallback …" and
  streams the real window as before.
  Full screen (2026-09-23): a staged window that enters a full-screen Space
  fills the display and refuses moves, so `prepare` detects it (AXFullScreen
  or ≥98 % coverage), captures the display cropped to the panel's aspect
  around its middle (where apps letterbox video), and holds that until the
  catalog's next poll sees the window leave full screen. "Still full screen" is
  AppKit's AXFullScreen flag (the frame sits short of the display mid-Space);
  a window leaving full screen is off every list for ~1 s, so the catalog
  gives it three polls and `prepare` waits 1.5 s before calling it gone; a
  switch away first takes the window out of full screen
  (`leaveFullScreenIfNeeded`) so it can go home. The band is encoded at the
  panel's size, not the display's. Entering and leaving each take up to one
  2 s poll to show.
  Geometry (pure functions in `VirtualStage`): window = panel ÷ Aa scale in Mac
  points (Off counts as 1.0; no viewport → the window's own size). The display
  is an *envelope*, a square of the panel's longer edge ÷ 0.5 plus the menu
  bar, reused while the wanted window fits, so rotation and Aa steps re-place
  the window and restart the pipeline without recreating the display; the
  device always gets exactly the window's rectangle. Deviation from the
  "sized to the panel" brief; `VirtualStage.envelope` returning `windowSize`
  restores the literal behaviour.
  Verified without permissions: default path byte-for-byte unchanged (~55 fps
  synthetic, plain SIGINT death); flag path streams the synthetic Desktop at
  ~55 fps under the AppKit loop and exits 130/143/129 with the window restored;
  `--virtual-display-selftest` creates a 1000×700@2× display in ~150 ms,
  online after ~250 ms, destroyed in ~60 ms, no permission needed for the
  display itself. Three review lenses plus adversarial verification found and
  fixed: a stale display reference after the grow path, placement recorded
  only after the first move (a Ctrl-C mid-staging lost the window), a failed
  pipeline start leaving the stage staged, a last-client-left during a switch
  being dropped, and `.cannotComplete` mistaken for "window gone".
  Learned: without Screen Recording, `SCShareableContent` never returns while
  a virtual display exists, so every SCK call on these paths is bounded
  (`WindowCatalog.shareableContent(…timeout:)`) and `prepare` refuses to make
  a display without the permission.
  Learned (2026-09-23): the window list shows an AX move only once the app
  commits it, a few to tens of ms after the AX writes return (more for an app
  slow to lay out); the AX frame reads the new frame at once. So the eviction
  scan right after a switch found the window just sent home still listed on
  the display, matched no AX window to that frame and printed "A System
  Settings window sits on the virtual display and could not be matched…"
  (twice, both false alarms: the window went home). Fixed: `releaseWindow`
  keeps the element (`lastReleased`) and the scan judges that window by its
  live AX frame: home, skipped; still overlapping (Messages kept a wider
  frame, a 24 pt strip), evicted and centred by its live size. The warning now
  names the window ID and listed frame. Probe on its own off-screen window,
  scan at once: the old logic warned in 21 of 30 scans, the new in none, and
  picked the overlapping window for eviction 20 of 20. Not yet run with real
  windows.
  Fixed (2026-09-23): `prepare`'s settle loop read only the window list and
  stopped after three identical reads 20 ms apart, counted from the frame
  before the move, so a pure resize the app commits late (1Password, Electron:
  between 45 ms and ~0.45 s) looked settled at once and the old frame became
  the crop until the catalog's next poll re-selected (~0.4 s of wrong crop).
  Now it reads the AX frame once after the writes. A new size there means
  stillness counts only once the listed size has left the old one, the list
  showing AX's frame ends the wait, and the deadline is 1 s; the old size (a
  refusal) counts stillness at once within 0.5 s, as before. A wait that runs
  out appends "; not settled by the deadline" to "Moved …", whose "from" is
  now the frame before the move (it printed the home frame). A restart that
  asks for the same rectangle as the last placement (the request fitted to the
  usable area, so a Dock arriving on the display still gets the window
  re-fitted) finds a clamped window where it was left and skips the move.
  Step (6) run verbatim in a harness: a probe window whose commit trails its
  frame by 80/150/300 ms was cropped at the old frame every time before, at
  the new one in 104/181/341 ms now; a refusal still settles in ~50 ms; a
  clamped restart takes 0 ms and no move; simulated, a Dock arriving between
  two restarts still gets the window re-fitted. Known limit: an app whose AX
  frame lags too (it applies the size after answering the write) still reads
  as a refusal, and its old frame stays the crop until a catalog poll (2 s;
  one that lands mid-switch is ignored) re-selects.
  **Untested, for Noah** (Screen Recording + Accessibility on the terminal):
  (a) `swift run -c release SillHost --virtual-display`, pick a window: the
  log shows "Virtual display … created", "Moved …", "Capturing … of virtual
  display", and the frame fills the panel edge to edge at Aa 1× with the title
  bar as the top edge; System Settings › Displays shows one "Sill" display.
  (b) Cover the window's old spot, switch Spaces, open Mission Control: the
  device keeps updating. (c) Deselect, pick Desktop, quit the iOS app, Ctrl-C
  mid-stream: each prints "Restored …" then "Removed virtual display", the
  window is back within 2 pt, no "Sill" display remains. (d) Rotate and cycle
  Aa while staged: one "Capture started" per change, no new display created.
  (e) The 1Password Aa step that showed the stale crop (staged at Aa 0.5,
  then 1×): the first "Moved … to" shows the asked 1117×610 and "Capture
  started" reads 2234×1220, with no second capture ~0.4 s later.
  If the picture is offset or black, the escape hatch is the last line of
  `VirtualStage.prepare`: return the `desktopIndependentWindow` filter with a
  nil `sourceRect` (window capture on the virtual display ran at 59 fps in the
  probe).

**Bar controls (2026-09-23).** Press and hold a thumbnail: macOS's three lights
appear over it (close, minimize, full screen → `.windowCommand` = kind 15, JSON
`WindowCommand`; the host presses the window's own buttons through
Accessibility, using the staged element on the virtual display). Keep holding
and move: the lights go, the thumbnail lifts and drags into a new slot, Home
Screen style; the arrangement is the device's own (`StreamClient.windowOrder`,
persisted per Mac, host order for the rest). A "Leave" button disconnected
(since the host settings step the last slot is Settings, with Disconnect in its
panel's foot). The device asks for the Desktop whenever the host reports nothing
streaming (at most every 10 s), so a fresh connection starts on the Desktop and
the drawer no longer opens by itself. When the watched window has closed it
waits 2 s first, and asks for nothing if the user picked or launched something
meanwhile (the host cannot tell that request from a Desktop tap). Harness:
`-SillWindowMenu 1` keeps the first thumbnail's lights open.

**Frame rate follows the device (2026-09-22).** `Viewport.fps` carries the
device's wanted rate: `UIScreen.maximumFramesPerSecond` (120 on ProMotion, 60
on the iPad mini), or 60 while Low Power Mode is on; the client re-sends on
`NSProcessInfoPowerStateDidChange` and `UIScreen.modeDidChangeNotification`.
The host keeps each client's rate (`clientFPS`, cleared on disconnect) and runs
the stream at the highest, capped by `maxFPS` and by 60 on the software
encoder; `fps` is re-read at every select;
a changed rate restarts the pipeline (capture interval, encoder session and
the virtual display's refresh all follow it), and bitrate scales with it.
Verified synthetically: 120 → "120 fps, 30 Mbps", drop to 60 mid-stream
restarts at 60 within a frame; `--virtual-display-selftest 120` comes online
at 120 Hz. Not yet measured on a ProMotion device or with the hardware encoder
(the software encoder manages ~22 fps at 1512×948 when asked for 120, which is
why it exists only as a fallback). `CADisableMinimumFrameDurationOnPhone` is
set so ProMotion iPhones render above 60.

**Trackpad stutter (fixed 2026-09-22), three causes, all measured:**
1. The device's Wi-Fi radio dozes when the downlink goes quiet, and every next
   packet then waits up to ~300 ms (iPad ping RTT sawtooth 5→100→200→300 ms with
   nothing streaming; the loopback simulator stays at 0). A trackpad stroke over a
   static window starts from a dozing link, so its first frames bunch up. The host
   now sends an empty `.tick` every 30 ms (~0.5 KB/s) while a source is live or a
   client sent input in the last 3 s, and both ends use the `.interactiveVideo`
   service class. Verified: RTT flat at 6–11 ms over 20 s with a static window.
2. A periodic IDR every 4 s (1–2 MB at 3024×1898) showed as a 50–100 ms
   RTT/frame-age spike every 4 s. Keyframes are on demand (connect, dropped
   delta, switch); the periodic safety interval is 4 s (`fps * 4`); a 30 s try was reverted while bisecting the freeze.
3. The only pointer the user could see was the Mac cursor baked into the video,
   so it moved as unevenly as the video arrived. The client now draws its own
   arrow sprite (`HEVCDisplayView`, a CALayer, no implicit animation, fed by
   `StreamClient.renderPointer`, not @Published) for the trackpad and Pencil
   hover; the host leaves the Mac cursor out of the video for good
   (`showsCursor` false at capture start; reconfiguring a running SCStream
   wedged it) and streams its shape as `.cursorShape`. Since 2026-09-27
   (branch `pointer-visibility`) the sprite also shows the Mac's own pointer
   while the Mac, or another device, moves it (kind 26, at the tick or the
   stream's rate), and this device's own only for the portrait trackpad (the
   Pencil's with Q2's flip). The trackpad also lost UIKit's ~10 pt start-of-
   stroke dead zone (a zero-duration long-press tracker drives the first
   movement) and gained Force-Touch-style haptics on click/drag (iPhone only:
   iPads have no Taptic Engine).
Dead-client eviction is time-based (no frame drained for 4 s, none in the first
8 s after connect): the frame-count rule evicted the simulator at full Retina.
A client evicted while the Mac is still advertised now retries on a timer.
Learned (2026-09-23; this replaces the caveat on (1)): the RTT spikes left with
ticks flowing come from AWDL, and Sill turns AWDL on itself. `includePeerToPeer
= true` on the host's NWListener (`StreamServer`) and the iPad's NWBrowser and
NWConnection (`StreamClient`), there since the first commit, makes the kernel
enable AWDL as `_sill._tcp` registers ("Enabling AWDL due to Mdns"; off ~3 s
after Sill quits). The Mac's one radio then leaves the Wi-Fi channel on a
512 TU schedule (kernel: infra 72 % while streaming, 48 % or 0 % around
switches). A 20 Hz ping from the Mac to its gateway stalls up to ~97 ms once
every 524 ms (p90 48 ms, 17 % over 10 ms; with AWDL off, p90 4 ms and max
13 ms). The same Bonjour service registered with the AWDL flag gave p90
67.5 ms with 32 % of pings delayed, against 3.9 ms without the flag. An rtt
sample that lands in a stall reads baseline plus 0–100 ms. AWDL carries none
of Sill's data (the connection is on en0). Ticks keep the radio awake but not
on the channel, and every earlier RTT reading, those in (1) and (2) included,
ran with AWDL on. The fix is applied (2026-09-24, Direct Wireless Connection
in the current step): `includePeerToPeer` is off by default on both sides and
comes back only for a Mac whose owner turns the setting on, and on the device
during a nearby search (Search Nearby, or a Mac last seen with the setting on
missing from the network), which stops once connected; the iPad side still
needs a device run. Secondary: `inflight > 2` counts only what
Network.framework has not handed to the socket, so after a switch the socket
buffer (autotuned up to 4 MB) can hold ~200 ms of frames ahead of pongs (frame
age 188–229 ms, no `net.dropped`). Client measurement, reworked 2026-09-23
(it sampled frame age every 15th frame and repeated the last value in a
slower second, sent one rtt sample per report, and ran its fps and ping
timers in the main run loop's default mode, so both stopped while a scroll
tracked): the client now takes the age of every frame and pings every 0.25 s
(stamped with the monotonic clock), both on dispatch timers on its network
queue, and closes a one-second window each second. Each report carries that
second's median in the old `ClientStats` fields, -1 for a second without a
sample (a still window streams no frames), and its max in two new optional
fields. The host still logs every other report, now as
`frame age 9/24 ms, rtt 7/80 ms` (the last second's median over the worst
since the previous line, "–" for no sample; an older client prints one
value), and the menu's device row and the HUD show "–" the same way.

**Frozen stream, 2026-09-22 evening — the Mac's hardware video encoder wedged.**
Every new HEVC session (and later H.264) accepted one frame and never returned
it, even from a fresh process with synthetic frames (`SillHost
--encoder-selftest`, `CaptureProbe --synthetic`). The old encoder called
VideoToolbox synchronously on the capture queue, so the stuck call froze
ScreenCaptureKit, then `stopCapture`, then the coordinator's `switching` flag,
and every later selection was silently ignored. The wedge held for about
three hours and then cleared on its own at ~22:30 (a fresh hardware session
encoded again while the orphaned sessions in the old encoder-service process
were still logging their 4 s timeouts), so a reboot is the sure fix, not the
only one. Protections now in the host:
- At launch the host pushes one 256×256 frame through a hardware session
  (`EncoderProbe`, ~100 ms when healthy, 1 s deadline). No answer means the
  host starts on the software encoder at once and says so, instead of hanging
  the first stream for 1.5 s and restarting it.
- `HEVCEncoder` feeds VideoToolbox from its own queue behind a one-slot
  mailbox (`EncoderMailbox`): the capture queue never waits; one frame at a
  time is inside VideoToolbox (two at once was measured and dropped: Current
  step, "The 33 fps plateau"); a watchdog on a separate queue declares the
  session hung after 1.5 s and calls `onHung`. A stream whose session settles
  in the hardware's slow state gets a new session in place
  (`EncoderSlowState`; Current step, "A new session for the slow state").
- The coordinator then restarts the source on the software encoder at half
  scale (slow, ~10 fps under load, but live) and says so in the log; three
  software hangs stop the stream instead of looping. Since 2026-09-25 that
  lasts only until a re-check finds the hardware keeping up (Current step,
  "The hardware encoder: busy, not stuck"); before, it lasted until the host
  relaunched.
- Presentation timestamps are forced monotonic; a keyframe request re-encodes
  the last frame only when the window is static.
- Never reconfigure a running SCStream (`updateConfiguration` also wedged it);
  the Mac cursor is left out of the video for good and the device draws it,
  with the Mac's live cursor shape streamed as `.cursorShape`.
- Regular mode raises the picked window on select (2026-09-23, Noah: the Mac
  must show the picked window): app activated, window raised and made key,
  before capture starts. Picks only (switcher, command line, an app launched
  from the device); the host's own restarts (resize, rate change, encoder
  fallback) leave focus alone. The virtual display never touches Mac focus on
  select; a pick that falls back to the real window counts as regular mode.
  Interacting works like a real click in both modes: a click, keystroke or
  typed text activates the app through Accessibility only
  (`NSRunningApplication.activate` is refused from a background process, and
  a Launch Services "open" of a running app counts as opening it, which
  switched on Noah's Work Focus automation, so it is never used; an app that
  refuses AX simply stays back), input held until it is up (at most 0.6 s) so
  the first click lands; on the regular path a window covered at the click or
  scroll point is also raised. Input that arrives mid-switch is delivered but raises nothing
  (`active` still names the old window, and raising it would cover the pick).
  Ghost "LayerProbeParent" windows that SwiftUI apps spawn per new display
  are filtered from the catalog.
Verified 2026-09-22 with `--synthetic` against the still-wedged encoder: hang
detected at 1.5 s, software restart, 55–59 fps out, the iPad decoding it fine.
Diagnosis tools: `swift run -c release CaptureProbe <window> [s] [--encode]
[--synthetic] [--software] [--h264] [--lowres]` (capture vs encode, hardware vs
software) and `sample <pid> 2` (a wedged encode shows as
VTCompressionSessionEncodeFrameWithOutputHandler → RemoteVideoEncoder).

Still open: the unexplained one-off stall where new clients received no catalog
(2026-09-22, hardened since, never reproduced). Keep the connect-path logging.
Known: a streamed window covered by another window on the Mac freezes on the
device (macOS stops repainting it) until the device picks it again or clicks
or scrolls in it, which raises it. `--virtual-display` removes the freeze for
good.

## Milestone 2 (input and window control) — done 2026-09-22

- Client → host input: tap/click, finger pan → scroll with trackpad gesture
  phases and client-generated momentum (host sets CGEvent scroll/momentum
  phases so apps rubber-band and fling), long-press right-click, Pencil as the
  mouse with hover, software keyboard as Unicode text, hardware keys and
  ⌘/⌃/⌥ chords as HID usages. Portrait laptop layout: stream on top, key row
  (esc, tab, latching modifiers, arrows, keyboard; Spotlight = ⌘Space only while
  the Desktop is the source, since Spotlight's panel is its own window) and a
  relative trackpad. Picked app is brought forward; window follows moves;
  resize restarts the pipeline.
- Latency, measured 2026-09-22 on 5 GHz Wi-Fi to the iPad mini via the client
  stats the host logs: frame age (host encode → device receive) 8–10 ms,
  ping RTT 6–9 ms with rare spikes. Adding capture (≤1 refresh), encode and
  decode+display (1–2 refreshes) puts glass-to-glass at roughly 40–60 ms,
  within the v1 bar. Not photographed with the stopwatch method yet.
- Host footprint (release build, `ps`): idle with no client 0.0 % CPU, 36 MB,
  one heartbeat line per 30 s and no ScreenCaptureKit calls; connected with
  nothing selected 0.0–0.1 %; streaming a Retina window ~3 %. Capture stops when
  the last client leaves.
- Diagnostics: `-SillHUD 1` (DEBUG) overlays fps · frame age · rtt · frame size
  on the device; the client reports the same to the host every second and the
  host prints `client <device>: …`.
- Learned: `_AXUIElementGetWindow` is private, so AX windows are matched by
  title then frame; apps enforce minimum sizes, the host streams what it got.

## Milestone 1 (latency spike) — done 2026-09-22

- Mac host builds and runs from `swift build -c release`: window listing,
  ScreenCaptureKit capture, VideoToolbox HEVC encode, Bonjour advertisement,
  TCP fan-out to clients.
- iOS client is a real Xcode project (`iOSClient/Sill.xcodeproj`), builds
  clean, runs on Noah's iPad Mini (the test device: iPad scalability plus a
  Duo-like aspect ratio).
- End to end verified on Wi-Fi: ~58 fps captured, encoded and sent with zero
  drops at 3024×1898 (Retina capture of a 1512×949 window), 15 Mbps.
- Bugs found and fixed along the way: SCStream aborting with `CGS_REQUIRE_INIT`
  when set up off the main thread in a CLI tool; the whole pipeline being
  released when the startup Task finished (one frame, then silence); clients
  that connected to a static window never receiving a keyframe.
- Host prints a per-second stats line (captured/encoded/sent/dropped) so a
  stalled stage is visible without a debugger.
- Toolchain on Noah's Mac: Xcode 27 selected as developer dir, license
  accepted, first-launch packages installed. No signing identities existed;
  Noah signs with his own team in Xcode.
- Learned: ScreenCaptureKit delivers frames only when the window repaints, and
  macOS stops repainting fully covered windows, so a streamed window buried
  behind others on the Mac freezes on the device. Inherent to window capture;
  the virtual-display plan in milestone 3 sidesteps it.
- Not measured: the latency number itself (see above).

## Layout

- `Package.swift` — SwiftPM. Products: `StreamProtocol` (shared wire format,
  iOS + macOS), `SillHost` (the CLI, target `SillHostCLI`) and `SillMenuBar`
  (Sill.app's executable). `SillHostCore` (the host, folder `Sources/SillHost`)
  is a library target with no product, so the iOS project never sees it.
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, with the host's per-launch `launchID`; `WindowInfo`,
  `AppInfo`, `StreamSource`) and image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset` (Low, Efficient, Balanced, High, Pro, Ultra, Extreme). Remote access:
  `Remote.swift` (kinds 18–22's payloads: `MacAddress`, `MacInfo`,
  `SignedMacInfo`, `PairRequest`, `PairResult`, `Goodbye`), `RemoteTLS.swift`
  (the one TLS 1.3 builder for both doors' ends and the tests),
  `RemoteIdentity.swift` (SPKI fingerprints, the Mac ID, the hand-built
  certificate, keys), `Pairing.swift` (`PairingCode`, `PairingProof`,
  `RecognitionTag`, `PairLink`), `AddressParser.swift`, `SafeText.swift`.
  `Compatibility.swift` — `SillProtocol.current` (1), `SillVersion` (tags,
  bundles and the wire's versions, compared part by part) and `Hello` (kind 23,
  the device's first message); `Goodbye` (Remote.swift) carries `message`,
  `minimumVersion` and `reconnect` too, and `WindowList` the host's
  `hostVersion` and `protocol`. `Pointer.swift` — `MacPointer` (kind 26, host
  → device: where the Mac's pointer is in the streamed frame while this device
  is not moving it, and `seen`, the input messages the host had read on the
  connection).
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang and re-checks the
  hardware until it can go back (`recheckLoop`), stops capture when the last
  client leaves, takes live settings between pipelines (`setTarget`, from the
  app and from devices' kind 17, at most four a second per connection,
  answered and published as kind 16; a pick made during a restart runs after
  it), keeps each connection's route (home or the remote door's: kind 21 only
  from near the Mac, Direct Wireless never from away), sends kind 18 with the
  catalog, says goodbye (kind 22) at quit, and writes `HostStatus`),
  `HostConfig` (the knobs: maxFPS, captureScale, bitrate per 60 fps,
  prioritizeSpeed, virtualDisplay, directWireless, remoteAccess, remotePort,
  internetAccess; `standard` is the CLI's values and the app's defaults),
  `HostStatus` (the snapshot the app shows, pushed on events; `onChange`
  publishes the devices' settings state), `DeviceSettings` (what a device may
  set, `HostConfig` ↔ wire), `HostLog` (the print shadow, the app's ring and
  log file),
  `WindowCatalog` (polls windows and thumbnails only while a client is
  connected; icons; installed apps in the background),
  `WindowCapture` (ScreenCaptureKit), `SyntheticCapture` (test pattern for
  `--synthetic`), `HEVCEncoder` (VideoToolbox with one frame inside, a
  one-slot mailbox behind it and a hang watchdog; hardware or software; says
  whether a stalled frame came back; gives a stream whose session settled in
  the slow state a new one), `EncoderSlowState` (when that is, and whether the
  new session ran faster; pure, `Tests/checks/encoder-slowstate`),
  `EncoderMailbox` (its bookkeeping: the frame inside with its watchdog
  clock, the mailbox, the watchdog's test, timestamps and keyframe requests;
  pure, `Tests/checks/encoder-mailbox`), `EncoderProbe` (one small frame
  through a hardware session at launch; for the re-check a short quiet run at
  the stream's size, one frame at a time like a stream, the rate it keeps and
  the rate a return needs), `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes, and turned off, the devices on peer-to-peer Wi-Fi
  disconnected; the test-only SILL_TEST_SERVICE_TYPE, SILL_TEST_SWAP_FAIL,
  SILL_TEST_PEER_TO_PEER_INTERFACE and SILL_TEST_LOOPBACK), `ClientLink`
  (which route a client came by, from its endpoint's scope, and the menu card's
  word for it: Wired, Wi-Fi, Direct or none; pure, checked on its own with
  `swiftc -package-name sill`, which its `package` access needs),
  `InputInjector` (CGEvents: pointer, scroll with phases, text with modifier
  flags cleared explicitly (a ⌘Space before typing otherwise tainted the text
  events and Spotlight ignored them), HID keys),
  `WindowSizer` (Accessibility resize for the Aa scale; `placement/move/
  restore` for the virtual display), `VirtualDisplay` (private-API wrapper),
  `VirtualStage` (`--virtual-display`: owns the display and the moved window,
  geometry, prepare/release, emergency restore), `HostShutdown` (signal
  sources + atexit, installed only with the flag in the CLI, always in the app;
  `releaseForQuit` for the app's Quit), `VirtualDisplaySelfTest`
  (`--virtual-display-selftest`), `Stats` (1 s lines while active, 30 s
  heartbeat when idle). Remote access: `OriginPolicy` + `InterfaceSnapshot`
  (who may use which door; pure), `RefusalSummary` (one refusal line a minute),
  `HostIdentity` (the `IdentityStore` protocol, `MemoryIdentityStore`, the TEST
  ONLY `FileIdentityStore`, `PairedDevice`, the lock-protected trust snapshot
  the door reads on the network queue), `KeychainIdentityStore` (Sill.app's),
  `PairingWindow` (pure), `RemoteServer` (the remote door), `Reachability`,
  `AddressList` (pure) and `RouterAddress` (read-only NAT-PMP/PCP),
  `RemoteAccess` (main actor; ties them together, signs kind 18).
  `DeviceGate` (the device floor, "0" in every build so far, and a refusal's
  words and log lines; pure, checked with swiftc; the gate itself, which runs
  only above "0", is StreamServer's, with the TEST ONLY
  SILL_TEST_MIN_DEVICE_VERSION and SILL_TEST_GOODBYE).
  The Mac's pointer: `PointerControl` (who moves it, the Mac or the device
  whose input the host read last, with the settle for Sill's own motion; the
  fraction kind 26 carries; pure, `Tests/checks/pointer-control`) and
  `PointerWatch` (the host's sampling of it: PointerControl under a lock, the
  streamed source's rectangle, a regular-mode window's bounds re-read on
  `sill.pointer`, the TEST ONLY scripted pointer `TestPointerPath` and
  `PointerTestHooks`; `Tests/checks/pointer-watch`). StreamServer samples it at
  each tick, and at the stream's frame rate while it moves over the source and
  some device is sent it (`PointerWatch.samplerInterval`), and sends kind 26
  to every device not moving it; InputInjector notes each pointer and scroll
  post just before it and, on a synthetic host, posts nothing (`in.dry`).
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding),
  `HostSettings` (UserDefaults; the presets are StreamProtocol's
  `QualityPreset`), `StatusItemController` (+ `MenuBuilder`), `StatusText`
  (all status copy), `StatusCard`, `StatusGlyph`, `SettingsWindow` +
  `SettingsPanes`, `Permissions`, `LoginItem`, `LogWindow`, `MainMenu` (key
  equivalents), `DebugHooks`, `AppLog` (its print shadow), `RemoteAccessPane`
  (Settings › Remote Access), `PairDeviceWindow` (the QR code and the typed
  code), `PairingWindowAddress` (the address that window gives to type:
  Tailscale's name and IPv4 first, another VPN's IP only under this network's
  address; pure, checked with swiftc), `UpdatePolicy` (the update check's rules
  and words; pure, checked with swiftc) and `UpdateChecker` (main actor; asks
  GitHub's releases feed and times the checks; compiles on its own with swiftc).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only), and `ExportOptions-appstore.plist`, how the iOS
  app's archive is exported for App Store Connect. `Scripts/release-ios.sh`
  makes the iOS app's build: the Release archive (automatic signing on team
  9B2KKVM937, or none with `--sign-at-export` and `--unsigned`), the export
  (destination export; `--upload` adds a second one whose destination is
  upload), the .ipa checked (version and build, the export compliance key,
  the Local Network, Bonjour and camera entries, the privacy manifest, an
  Apple Distribution signature, an App Store profile, no get-task-allow, the
  required-reason APIs against the manifest), `--bump`, `--api-key`,
  `--print-version` and `--privacy-report`; it refuses any Xcode but 27,
  with `--bump` or `--upload` a working tree with changes (new files in
  iOSClient and Sources/StreamProtocol count), and an App Store address in
  `SillLinks.swift` that isn't one, and sourced it only defines its
  functions (docs/release-checklist.md, TestFlight). `Scripts/make-app.sh`
  builds, iconizes, signs and installs the bundle; `Scripts/release.sh`
  (M6) makes the downloads from it:
  `make-app.sh --release`, `make-dmg.sh --prepare` (the image's tool and
  background, before anything goes to Apple), a zip (`ditto -c -k
  --keepParent`), Apple's notary service (`notarytool submit --wait`, the
  profile in `SILL_NOTARY_PROFILE`), the ticket stapled, the zip made again
  with the ticket inside, and a copy unpacked from it checked with `stapler
  validate` and `spctl` ("Notarized Developer ID"); then the disk image of the
  stapled app (`make-dmg.sh --sign`), notarized on its own, stapled, and
  checked (`hdiutil verify`, `stapler validate`, `spctl -t open --context
  context:primary-signature` as "Notarized Developer ID", mounted `-nobrowse`
  in `$TMPDIR` and the Sill.app inside checked as the zip's copy); it prints
  `.build/Sill-<version>.dmg` and `.zip` with their SHA-256. A dry run makes
  the image too, from the app before stapling, signed with the same identity.
  It refuses to start, before building, without a
  Developer ID Application identity (`SILL_SIGN_IDENTITY`, checked against the
  keychain) or the profile, or on a HEAD without the tag v‹version› (the
  update check's), or with `SILL_RELEASE_TAG` (the release workflow sets it)
  not `v<CFBundleShortVersionString>` or naming another commit (`--check-tag`
  checks only that), and `--dry-run` stops before notarytool (the profile and
  the tag only warned about: it sets `SILL_RELEASE_DRY_RUN=1`, with which
  `make-app.sh --release` builds an untagged commit); it refuses a build
  without Assets.car and AppIcon.icns. `--publish` makes the GitHub Release in
  `SILL_RELEASE_REPO` (default Saffsanity/sill, the only repository the update
  check reads), asks `gh api repos/<repo>` whether it can reach the repository
  (`gh auth status` asks GET /user, which the Actions token can't answer), and
  refuses to start unless origin's tag v‹version› names HEAD (gh would make a
  missing tag from the default branch's tip; not asked in the release
  workflow, whose checkout is that tag and keeps no credentials); in
  Saffsanity/sill it passes gh `--verify-tag`, anywhere else it warns that no
  Sill.app will offer the release. It uploads `Sill.dmg`, `Sill.dmg.sha256`,
  `Sill.zip` and `Sill.zip.sha256` (the zip kept for now: the site's links name
  it until a release carries the image). Sourced, it only defines its functions.
  `Scripts/make-dmg.sh --sign IDENTITY APP DMG` (`-` for ad hoc) makes the
  image: an HFS+ volume "Sill" (not APFS: Finder names the background by an
  HFS+ alias record, and Finder-made and current third-party images are
  HFS+) with the app (`ditto`), a link to /Applications, `.background/`
  (design/DMGBackground.svg rendered by Quick Look at 1x and 2x, cropped,
  joined by tiffutil into one TIFF; cached in `.build/dmg`) and
  `.VolumeIcon.icns` (the app's AppIcon.icns, with the root's custom-icon
  flag); its window laid out by a `.DS_Store` that `Scripts/dmg-layout`
  (Swift, compiled into `.build/dmg`; DSStore.swift, FinderAlias.swift,
  DMGLayout.swift) writes without Finder and reads back (`check`): 660 x 432
  points, the picture's 400 and macOS 27's 32-point title bar
  (`DMGLayout.titleBar`; `Tests/checks/dmg-layout` checks the writer); converted
  to ULFO (LZFSE, read-only), signed (identifier `me.saffer.sill.dmg`, a
  timestamp unless ad hoc) and checked mounted (exactly five items at the
  root, the link, the layout, the app byte for byte). Mounts are `-nobrowse`
  in a new folder in `$TMPDIR`: mounted under the home folder, fseventsd
  writes `.fseventsd` onto the image as it unmounts. `--prepare` only builds
  the tool and the background. Sourced, it only defines its functions.
  `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line,
  and each second's frames with their kB (the encoder's output);
  `--host`, `--device`, `--big-payload`, `--flood`, `--stop-ping@T`,
  `--stop-read@T`, `--pairing-wanted@T`; the remote door with `--tls
  --identity=DIR`, `--pair-url`, `--pair-code`, `--pin=FP|none` and
  `--expect-tls-fail`, printing kinds 18, 20 and 22; the Mac's pointer with
  `--pointer` (each kind 26), `--move=X,Y@T`, `--tap=X,Y@T`, `--key=USAGE@T`
  and `--input=JSON@T` (a literal kind 8), the input flags only to a
  `--synthetic` host on this Mac (lsof and ps); every argument is checked
  before it connects, and a bad one exits 2). `Scripts/sillrelay.py` is a
  shaping passthrough relay (`--listen 0 --to HOST:PORT [--delay-ms N]
  [--rate-mbps R] [--blackhole-after S] [--record PREFIX]`; TLS passes
  through).
  `Scripts/encoder-check/` holds the encoder's checks ("The 33 fps plateau"):
  `run.sh` builds and runs those that never touch an encoder (the probe and
  encoder checks, which run in real time with tight bounds and so stay out of
  CI, and through `Tests/checks/encoder-mailbox` and `encoder-slowstate` the
  mailbox and slow-state checks and their mutants; it refuses any binary that
  links VideoToolbox), and `verify-hardware.sh` the hardware runs against a
  base commit built from `git archive` (parity, stream, harness, probe,
  keyframe), each only while `no-device.sh` finds no device connected to
  Sill.app; outputs go to `.build/encoder-check/`.
  through). `sillclient.py --hello=VER[,PROTO]` (or `none`) sends a device's
  hello first, and kind 22's new fields are printed. `Scripts/sillfeed.py PORT`
  is a fake GitHub releases feed for the update check's tests (`--tag`,
  `--status`, `--etag`, `--draft`, `--prerelease`, `--html-url`, `--body`,
  `--big`, `--slow`, `--reset`, `--redirect`, `--set-cookie`,
  `--all-headers`; `GET /__control?key=value` changes them while it runs).
- `site/` — the website, for GitHub Pages at the domain in `site/CNAME`:
  `index.html`, `download.html` (links the newest GitHub Release's `Sill.zip`
  and `Sill.zip.sha256`; never edited per release), `privacy.html` (the policy
  App Store Connect and the app link to), `support.html`, `style.css` (system
  fonts, light and dark) and `icon.svg` (a copy of design/AppIcon.svg). No
  scripts and nothing loaded from elsewhere: every page's
  Content-Security-Policy is `default-src 'none'`. Links are relative and
  name a file (`download.html`; Home is `index.html`, since `./` opens nothing
  from the folder), so it renders from the folder; GitHub Pages also serves
  each page without `.html`, the form the app and App Store Connect use
  (`/download`, `/privacy`, `/support`). Remote Access paragraphs sit between
  `<!-- Remote Access` and `<!-- /Remote Access -->`, to cut for a release
  without it. `docs/release-checklist.md` is the order of work: the one-time
  setup (Developer ID, notary credentials, hosting and DNS, the App Store
  Connect record) and every release's steps.
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one;
  `FoundMac` rows; connection, parsing, reconnect, the move of a session over
  AWDL to the network, a live session following the best path
  (`followBestPath`: to the cable, to Wi-Fi, made again over either), ping,
  generic `send`, and the pointer: kind 26 judged on its queue, `renderPointer`,
  `setOwnPointer`, `sendFromKeyRow`, a hand-over's carry-over),
  `SessionLink` (the session's connection and the one door out
  to the Mac; the moves' fenced hand-overs, which chain, and the hold of a move
  off a lost path: `handOver`, `hold`, `adopt`, `unhold`; the input messages
  counted for the session's connection, `inputsOnSession`, which a kind 26's
  `seen` is judged against; Foundation and Network only, checked with swiftc),
  `DiscoveryPolicy` (when to look nearby, the rows and the word each ends in,
  the session's route word for the Settings panel,
  when a reconnect may take a Direct row, when a session over AWDL moves to
  the network, when a live session at home moves to the cable or to Wi-Fi or is
  made again (`pathPlan`, `upWait`; never a remote one), the memory of Macs with
  Direct Wireless on, the Remote rows and when a lost saved Mac is dialed away
  from home; pure, checked with swiftc), `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display), `PortraitStreamScreen` (laptop
  layout: stream, compact bar, key rows, trackpad), `InputOverlay` (direct touch,
  Pencil, keyboard, scroll momentum; each input says what drew this device's
  pointer), `TrackpadView` (the portrait pad: its cursor a `PadCursor`, from the
  anchor; a recognizer that only counts fingers), `HEVCDisplayView` (shared
  display view, the one pointer sprite + DEBUG HUD), `DiagnosticsHUD` (client
  stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with rows ending in
  Wired, Wi-Fi, Direct or Remote, the hint and Search Nearby, Add a Mac…, and
  a footer along the bottom, "Needs the free Sill app on your Mac." with links
  to the download, support and the privacy policy, which open in Safari (one
  line while they fit, else the download link over the other two, as wide as
  the column); the column stays where it would be without the footer
  (centred; in the top half on the Duo's 710×1000, the footer still along the
  bottom; at the top while a field has the keyboard), rises only to keep 24 pt
  clear of the footer, never closer than 16 pt to the top, and scrolls above
  it, 16 pt from the top, when even that does not fit (a 12 pt fade, then
  12 pt clear, both inside the gap); one scroll view
  whatever the fit (`ColumnOverFooter`, measuring a hidden copy of the
  footer), so a fit that changes never builds the card anew (its fields, the
  camera); + DEBUG harness, and `InputScript`, `-SillInputScript`'s steps),
  `SillLinks`
  (the site's addresses, written once; getsill.app is live since 2026-09-25;
  and the App Store address for a Mac's update notice, a placeholder until the
  App Store Connect record exists),
  `MockCatalog` (harness data and the settings cases), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel; the route line, Away
  from home, the slow-link callout). Remote access: `DeviceIdentity`,
  `SavedMacs` (pure), `RemoteDialPolicy` (pure), `RemoteConnector`,
  `StreamClient+Remote` (pairing, remote dials, the reconnect order, links),
  `AddMacCard` (the card, the fields, `EscapeKey`), `CodeScanner` (VisionKit),
  `PairingOverlay` (Pair This iPad…), `GoodbyePolicy` (the words and the
  reconnect after a session ends, a Mac's notice included; pure, checked with
  swiftc), `PointerPresence` (the rules of the one pointer sprite: the Mac's
  arrow while the Mac or another device moved it last, this device's own only
  for the portrait trackpad; a kind 26's freshness; the network queue's feed
  with a hand-over's carry-over; the key row keeping what shows; the portrait
  pad's cursor; pure, `Tests/checks/pointer-presence`; pbxproj A301/F301).
  `PrivacyInfo.xcprivacy`, a resource of the target, is the privacy manifest:
  it declares UserDefaults (CA92.1) and `systemUptime` (35F9.1), and any new
  use of a required-reason API (file dates, disk space, `mach_absolute_time`,
  active keyboards) must add its category and reason there before the next
  upload. New files need their four pbxproj entries by hand.
  Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.
- `docs/DEVELOPMENT.md` — building, running and testing from source; the
  README's developer material until 2026-09-25, so a plan's "README" means a
  section there: the toolchain, make-app.sh, Sill.app's menu and Quality, the
  CLI's flags, the iOS project, Permissions (the TCC reset), settings from a
  device, Direct Wireless, remote access (setup, troubleshooting, reset), the
  test tools in brief (Build and run below has them all), measuring latency,
  troubleshooting (slow, frozen, the encoder), releasing, known limitations.
- `README.md` — the public front page: the site's lede, links to getsill.app
  and its download, support and privacy pages, a commented App Store badge
  slot, requirements, how it works, tips, building from source in brief,
  contributing, the license. `LICENSE` — the Apache License 2.0.
  `.github/FUNDING.yml` — the Sponsor button: GitHub Sponsors (a `ko_fi:`
  line joins it once there is a Ko-fi handle). Tip links live there, in the
  README's Tips and on the site, never in the iOS app. `SECURITY.md` — how to
  report a vulnerability (support@getsill.app, never a public issue) and what
  is in scope. `.github/ISSUE_TEMPLATE/` — issue forms: a bug report, an idea,
  a question, no blank issue. `.gitignore` also leaves out signing keys,
  profiles, keychains and design/reel/.
- `.github/workflows/` — GitHub Actions on the `xcode-27` runner (macOS 27
  with Xcode 27, a public preview; the only image with Xcode 27). `ci.yml`:
  pull requests and pushes to main that touch more than documents, the site or
  the design files, and by hand; `swift build -c release`,
  `Tests/checks/run-all.sh`, the iOS app for the generic simulator (Debug,
  arm64, `CODE_SIGNING_ALLOWED=NO`), and the CLI's paths that exit before the
  host starts (`--internet` alone, exit 2; `--print-reachability`); by hand
  with "mutants", each check's mutants in a job of its own. `release.yml`: a
  pushed tag `v*`, or by hand with one; verify only (the tag, the checks,
  `make-app.sh` signed ad hoc, zipped, and `make-dmg.sh`'s image of it, ad hoc
  too, as two artifacts) unless the repository
  variable `SILL_SIGN_IN_CI` is `true`, then the Developer ID .p12 into a
  temporary keychain, the notary key stored as a profile in it, `release.sh
  --publish`, Apple's notary logs kept as an artifact (`include-hidden-files:
  true`: upload-artifact skips whatever is under a folder whose name starts
  with a dot, `.build` included), and the keychain deleted in an always()
  step. Secrets,
  variables, rotation and costs: docs/release-checklist.md, "Releasing from
  GitHub Actions". `testflight.yml`: by hand only; `release-ios.sh
  --unsigned` without an App Store Connect key, `--sign-at-export` with one
  (the secrets `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID`,
  `SILL_TESTFLIGHT_KEY_P8`, an Admin key: cloud signing, no certificate or
  profile stored), and `--upload` too when the variable `SILL_TESTFLIGHT_IN_CI`
  is `true`; the .ipa is the artifact for 14 days (docs/release-checklist.md,
  "TestFlight from GitHub Actions"). `.github/actions/select-xcode` —
  selects the newest Xcode of the `version` asked for (27) whose folder is
  not a beta and prints `xcodebuild -version`; without one, CI warns and
  takes the newest Xcode there and a release (`fallback: false`) fails (CI
  only: it runs `sudo xcode-select`). The runner's `bash` is 3.2: try `run:`
  steps with `/bin/bash`. Actions are pinned by commit hash.
- `Tests/checks/` — the pure checks, a folder each: `main.swift`, `run.sh`
  (compiles the app's files it names with swiftc into `.build/checks/<name>/`
  and runs; `--mutants` runs `mutants.py`, passing only when every mutant is
  caught), and `build.sh` where a check compiles a module (StreamProtocol's
  sources with `import StreamProtocol` stripped): `addresses`, `clientlink`,
  `compatibility`, `device-gate`, `dmg-layout` (Scripts/dmg-layout's
  `.DS_Store` and alias writer, against Finder's own layout of the file,
  make-dmg.sh's layout arguments and the SVG's size and edge),
  `encoder-mailbox`, `encoder-slowstate`, `fence`, `goodbye`, `ledger`,
  `origin`, `pairing-address`, `pointer-control`, `pointer-presence`,
  `pointer-watch`, `policy`, `protocol`, `remote-rules`, `update-policy` (the
  two encoder checks refuse a binary that links VideoToolbox). `run-all.sh
  [--mutants] [-v] [name…]` runs them and exits with the number that failed
  (a folder whose `run.sh` is not executable fails); `common.sh` is sourced by
  each `run.sh`; `README.md` lists what each compiles and the checks that
  belong to open branches. A change to a checked file updates its check (and
  a mutant's pattern) in the same commit.

## Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
swift run -c release SillHost --synthetic  # Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --encoder-selftest   # is the hardware encoder alive? 5 s, exits
swift run -c release SillHost --virtual-display   # picked windows stream from their own HiDPI display (off by default)
swift run -c release SillHost --virtual-display-selftest   # create/destroy one display, report what sees it
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi (AWDL): devices without a shared network (off by default)
swift run -c release SillHost --remote      # the remote door for this run on any free port (--remote=PORT), a throwaway identity; the code and link print here
swift run -c release SillHost --remote --internet   # also admit paired devices from outside this Mac's networks and VPNs
swift run -c release SillHost --print-reachability  # the addresses a device would get away from home, then exit
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000   # a device's settings change
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # a scripted pointer on the test pattern, on 127.0.0.1 alone, never the hardware encoder
python3 Scripts/sillclient.py PORT 6 desktop --pointer --move=0.25,0.25@3   # each kind 26 as it arrives; input goes only to a --synthetic host
Tests/checks/run-all.sh                 # every pure check, as CI runs them (~2 min; --mutants adds the mutants, most of an hour)
Scripts/make-app.sh                     # .build/Sill.app, signed with the Apple Development identity (~2 s unchanged)
Scripts/make-app.sh --install --open    # Noah: replace /Applications/Sill.app (a running one quits first), launch it
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release   # M6
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh [--dry-run]   # M6: the notarized download (docs/release-checklist.md)
Scripts/release-ios.sh                  # the iOS app for App Store Connect: archive, export .build/ios/export/Sill.ipa, check it; uploads nothing
Scripts/release-ios.sh --bump --upload  # Noah: the next build to TestFlight (docs/release-checklist.md, TestFlight; --privacy-report, --print-version)
Scripts/make-dmg.sh --sign - .build/Sill.app .build/Sill.dmg   # the download's disk image of any build, ad hoc (release.sh makes the real one)
python3 -m http.server 8000 --directory site   # the website at http://localhost:8000
Scripts/encoder-check/run.sh            # the encoder checks that never touch an encoder (safe while Sill.app streams)
SILL_TEST_ENCODER_RECYCLE=0 swift run -c release SillHost   # =0 keeps every hardware session, =1 replaces one in the slow state, as by default (A/B on the real Desktop: --synthetic moves every frame and never reaches the slow state)
Scripts/encoder-check/verify-hardware.sh harness   # USES THE HARDWARE ENCODER; skips each run while a device is connected
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording: the CLI's belongs to Terminal (or
whatever launched it), Sill.app's to Sill itself.
Sill.app: the log is `~/Library/Logs/Sill/Sill.log` (`tail -F`, not `-f`: at
10 MB it moves to Sill.1.log; Show Log… in the menu); settings are `defaults
read me.saffer.sill.mac` (maxFPS, captureScale, bitrate, prioritizeSpeed,
virtualDisplay, directWireless, updateCheck; the update check keeps
updateLastCheck, updateETag, updateLatestTag and updateLatestURL), and a launch
argument such as `-maxFPS 60` or `-updateCheck 0` overrides one for one run. A device's change from its Settings panel is saved there too, like a
menu click; the CLI keeps a device's change until SillHost quits. Test arguments for the bare binary (`.build/release/SillMenuBar`,
defaults domain `SillMenuBar`; delete it after): `--synthetic` (test pattern,
off Bonjour; the port is in the "Status: Test Pattern Mode" line),
`-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`,
`-SillQuitAfter <s>`, `-SillRenderPreviews <dir>` (panes, cards, glyphs,
menu.txt; no permission needed). The update check, in the bare binary (which
has no version and never checks without these) and the app: `-SillUpdateFeed
http://127.0.0.1:P/latest` (a feed on this Mac only: 127.0.0.1, ::1 or
localhost; `Scripts/sillfeed.py P` serves one; test pattern mode checks only
such a feed), `-SillUpdateVersion 0.3.0`, `-SillUpdateNow 1` (one check at
start, as Check Now), `-SillUpdateInterval <s>` (24 h become s seconds, the
retry s/24), `-SillPrintMenuAfter <s>` (the status menu as it would open, and
Settings › General's update line, in the log), `-SillSetAfter '<s>
updateCheck=0'`. Never run a test against GitHub. To make Sill.app check again at
its next launch: `for k in updateLastCheck updateETag updateLatestTag
updateLatestURL; do defaults delete me.saffer.sill.mac $k; done`. Render previews from
`.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only the
bundle's copy records the real SDK (make-app.sh sets it with vtool; see Current
step), and the bare binary draws the pre-26 look. `--encoder-selftest` and
`--virtual-display-selftest` work in the app too.
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi (or with the Mac's Direct Wireless Connection on).
AWDL, headless and without touching a running Sill.app: the synthetic hosts do
not advertise, but `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers them as
"Sill test ‹pid›" under that test type (never `_sill._tcp`, so no device sees
them) with the listener's own peer-to-peer flag, and prints which one it got;
`SILL_TEST_SWAP_FAIL=port|all` makes a replacement's same-port (and any-port)
bind fail; `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` counts a client scoped to that
interface as one on peer-to-peer Wi-Fi, so a test client on the Mac's own en0
link-local address (`ifconfig en0`, `fe80::…%en0`; Python's socket takes it)
stands in for a device on awdl0 when Direct Wireless turns off (a local
connection to the Mac's own awdl0 address never became ready, so awdl0 cannot
be tested headless); all three are honoured only by a host that does not
advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
registration that includes AWDL a second time on awdl0's index (`python3 -c
'import socket; print(socket.if_nametoindex("awdl0"))'`, 16 here). dns-sd
options go before the command: `dns-sd -R … -includeAWDL` registers a TXT
record "-includeAWDL" and sets no flag. The kernel's count of AWDL services:
`/usr/bin/log show --last 1m --style compact --predicate 'process == "kernel"
AND eventMessage CONTAINS "BonJourTrig"'` ("ValidSvc N" once a second; a
registration with AWDL adds 2, a peer-to-peer browse 1); `log` is a zsh
builtin, hence `/usr/bin/log`, and `process == "kernel"` keeps the log tool's
own line out. Enable and disable lines ("Enabling AWDL due to Mdns") show only
when nothing else holds AWDL. Keep AWDL-on tests under 20 s and on test types.
Remote access, headless: TEST ONLY variables, honoured only by a host that
does not advertise: `SILL_TEST_REMOTE_DIR=<dir>` (the identity and trust list
in a 0700 directory instead of memory or the keychain; the bare app's
`-SillPairAfter <s>` leaves `pairing.url` and `pairing.code` there, 0600, never
printed), `SILL_TEST_PAIRING_TTL=<s>`, `SILL_TEST_BACKOFF_SECONDS=<s>`,
`SILL_TEST_ORIGIN=vpn|internet` (loopback counts as that origin) and
`SILL_TEST_NO_ROUTER=1` (never ask the router; set it on every headless host).
The Mac's pointer, headless: every synthetic host is a dry run (its input is
counted as `in.dry`, never posted, and activates or raises nothing) and never
reads the real pointer. TEST ONLY, honoured only by a synthetic host (anywhere else one
line says it is ignored): `SILL_TEST_POINTER_PATH=<file>` is a scripted
pointer on the test pattern, lines `T X Y` (seconds since the stream's first
sample, points in the 1512×949 pattern, outside allowed; `#` comments; at most
10,000 steps and 1 MiB, a bad file refused whole with one line): the test
pattern then has a pointer, a test client's input lands in the pattern's space
and a dry-run pointer event moves the scripted pointer (the newer of it and a
step wins); `SILL_TEST_SOFTWARE_ENCODER=1` starts on the software encoder, with
no launch probe and no re-check, so a test never touches the hardware encoder
(60 fps at most: a 120 fps sampler test needs the hardware, and so the
no-device check).
The device floor, headless: `SILL_TEST_MIN_DEVICE_VERSION=1.2` raises the floor
of a host that does not advertise (a device below it, or one that sends no
hello, gets kind 22 "update" and is closed; a value that does not parse is
ignored with one line), and `SILL_TEST_GOODBYE='<JSON Goodbye>'` makes its
refusals send that payload instead (a reason the device does not know).
The bare app takes `-remoteAccess 1 -remotePort P`, `-SillSetAfter '3
remotePort=P2'`, `-SillPairAfter <s>` and `-SillUnpairAfter <s>`; its
`-SillRenderPreviews` adds the Remote Access pane's states and the pairing
window's. A session through a shaped link: `python3 Scripts/sillrelay.py
--listen 0 --to 127.0.0.1:P --delay-ms 150 --rate-mbps 2`, then
`sillclient.py RELAYPORT 90 desktop --tls --identity=$T/a --stats` after
`--pair-url=URL` once. Never let a test binary take a connection from another
machine: the Application Firewall prompts. `SILL_TEST_LOOPBACK=1`, honoured only
by a host that does not advertise, makes both doors of a test host listen on
127.0.0.1 alone ("Test listener: loopback only …"; `lsof` lists
`127.0.0.1:PORT`); a device on this Mac, the simulator included, and the test
clients reach it by 127.0.0.1. Reset the app's remote settings with
`for k in remoteAccess remotePort internetAccess remoteAddressName
remoteDevicesSeen; do defaults delete me.saffer.sill.mac $k; done`.
Debug harness (simulator, no Duo simulator exists yet): launch arguments
`-SillLayout 1000x710` (inner landscape) / `710x1000` / `500x710` / `710x500`
(outer), `-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect|wired|noroute` (the mock Mac's settings; it answers a pick
after 0.35 s; the readout's route is Wi-Fi except `directlink` Direct, `wired`
Wired, `noroute` none, and `remote`, `remoteinternet` and `remoteslow` none,
where the route line says how),
`-SillConnectCase looking|hint|nearby|methods|denied|update|notice` (the connect screen in a discovery
state; `methods` has a row ending in each word, none, and long names; `update` a
Mac's refusal with "Update Sill in the App Store" when `-SillAppStoreURL
https://apps.apple.com/app/id000000000` gives it an address, `notice` a goodbye
reason the device does not know; the mock never browses) and remote access's `remote|addmac|addcode|addcodeerror|
pairing|remotedial|remotefail|camera|externalpair` (`-SillRemoteFailure
vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|
remoteoff` picks remotefail's words), the settings cases `remote|remoteinternet|
remoteslow|remotepair|remoteoff|noremote`, `-SillSettingsEnd 1` (the panel
scrolled to its end), `-SillScanOverlay 1` (Pair This iPad…'s overlay),
`-SillPointer mac@X,Y|device@X,Y|hidden|pencil@X,Y` (the pointer sprite in one
of docs/pointer-visibility-plan.md's states over the mock's frame, which it
draws as a dim rectangle; `-SillPencilPointer 1` is Q2's flip), and in
the normal app and under `-SillLive 1` `-SillPairURL '<sill://pair…>'` (pair
at launch, no confirmation), `-SillPairCode <12 digits> -SillPairAddress host:port`,
`-SillDialSaved 1`, `-SillForgetMacs 1`, `-Sill.savedMacs '<JSON>'` (one run;
`'[]'` empties), `-SillRemoteRoute vpn|internet` (a loopback session counts as
that route), `-SillHelloVersion <v>` (the version the hello gives, against a
host's floor), `-SillScreenFPS 120` (a 120 Hz screen) and `-SillDeviceKeySE 1`
(a Secure Enclave device key, R0-a); `xcrun simctl openurl <udid>
'sill://pair…'` shows the link's confirmation after the system's "Open in
Sill?". `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator), `-SillMoveTest
1|refused|other:PORT|to:HOST:PORT` (with `-SillConnect`: that session counts as
direct and a second later the same address, or its port 1, or its port PORT, or
HOST:PORT, is listed as the Mac's network row, so the move to the network runs
against a synthetic host; `other:` with a second synthetic host on PORT is
another launch, refused at its first window list and not tried again, and with
`-SillConnect` through a delay proxy to the first host's own PORT the fence
waits out the proxy's round trip; `to:` reads HOST:PORT as `-SillConnect` does,
`[::1]:P` too, and this Mac's `fe80::…%en0` address from `127.0.0.1` shows the
panel's route word change at the hand-over; the console's "discovery: …" and
"session: …" lines, `xcrun simctl launch --console-pty`, say what happened),
`-SillWiredTest HOST:PORT` (a wired dial's fallback under test:
`-SillConnect`'s dial, a network row's and a move's go to HOST:PORT first,
`192.0.2.1:9` giving way after 2.5 s and `127.0.0.1:1` at once), `-SillPathTest
'<spec>'` (with `-SillConnect`: the session's Mac listed as a network row whose
cable and Wi-Fi come and go on cue, so the session follows the best path for
real; the spec is ContentView's contract, the console's "path: …" lines say
what happened), `-SillInputScript '<t> <step>; …'` (with `-SillLive 1`: input
with no finger, t seconds after the session's first window list: `down`, `pad
DX,DY`, `lift` and `click` on the portrait pad, `tap X,Y` on the stream at a
frame fraction, `key USAGE` a hardware key, `row USAGE` a key of the portrait
key row; the console's "input script: …" and "pointer: …" lines say what
happened; it runs only when the session was dialled by `-SillConnect` to a
loopback address, `127.0.0.1:P`, `::1:P` or `localhost:P`, and the host's first
window list has no version: Sill.app's always has, and would post the input to
this Mac, so the console says "input script: refused: …" and nothing is sent;
point it only at `--synthetic` hosts. `[::1]:P` never reaches the app:
UserDefaults reads a launch argument that starts with `[` as a property list
and drops it). A fake screen wider than the
simulator but fitting on its side (1133x744 on an upright iPad Pro 13") is
drawn a quarter turn clockwise; `sips -r 270` the screenshot.

## Compatibility floor

The first public builds (Sill for iPhone and iPad from the App Store, Sill.app from GitHub) set it
for good. Sill.app changes only when its user downloads a new version (its update check only points
at one), and a device can stay on an old version (automatic updates off, an iOS the next version
dropped). So every later host keeps serving devices from the first public build on, and every later
device keeps working with Macs from the first public build on, or each says why
(docs/update-notice-plan.md):
- Kept as they are: the home door as Sill.app 1.0 ships it, TLS with pairing at home
  (docs/home-pairing-plan.md, branch `home-pairing`, in progress; it ships before 1.0, Noah
  2026-09-25), not today's plain-TCP `_sill._tcp` door, which only development builds and the CLI
  keep; the 14-byte header; kinds 0–23 and their payloads (HEVC with ParameterSets; the JSON of
  Switcher, Input, Viewport, HostSettings, Remote and Compatibility); the ping echo; a kind 16
  within 2 s of the first window list; kind 22's `reason`, `message` and `reconnect`.
- Additive only (HostSettings.swift's rules): new fields optional, never renamed or retyped; kind
  numbers never reused; no new case in an enum an older peer decodes. `StreamSource` keeps its
  three cases (a new source goes in an optional field, with `active` still one of the three). A new
  `InputEvent` case, scroll phase or window command goes only to a host that said it takes it (a
  kind or a field only newer hosts send), and a gesture ends with a scroll phase the first build
  knows.
- A device is refused, never served wrong. A host that can no longer serve older devices raises
  `DeviceGate.minimumDeviceVersion` ("0" today) by the plan's §4.6, and they get kind 22 "update"
  before anything else. A device from 2026-09-25 on that receives it shows the host's message word
  for word, with its App Store link, and does not reconnect; older development builds cannot. At
  the TLS home door only devices from home pairing on receive it (Decided, below).
- Every device says hello first (kind 23: its version, build, protocol and name), and every host's
  window list gives its version and protocol (`hostVersion`, nil from SillHost and from Macs
  before 2026-09-25). A later device facing an older Mac tells what it lacks from these and from
  which kinds and fields arrive, and says "Update Sill on ‹Mac›", as the Settings panel already
  does for a Mac without kind 16.
- `SillProtocol.current` (1) rises only with a change an older peer cannot skip, and the floor
  rises with it.
- Decided (Noah, 2026-09-25; the plan's open question 14): home pairing ships before 1.0, so the
  floor is the TLS home door with pairing, and no 1.0 device speaks plain TCP to Sill.app. The
  hello goes first inside TLS at both doors, through `serve`'s gate: whichever of this branch and
  `home-pairing` lands second puts the gate in home-pairing's `Door`, one place for both doors,
  and settles `SillProtocol` against home pairing's ALPN (`sill/1`; a later generation `sill/2`):
  if 1.0's TLS home door is protocol 1, pairing on the home door leaves the examples of what
  raises it (Compatibility.swift, the plan's §3.2 and §4.6). Builds from before home pairing,
  this one included, dial plain TCP and say hello in plaintext: at the TLS door they get a failed
  handshake and EOF, never kind 22 "update", and redial. Only development and TestFlight builds
  are that old, so no plaintext path or sniffer answers them.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0, LICENSE since PR #15 (MPL-2.0 only if Noah switches
  before the repository is public; paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization, audio.
