# Releasing Sill

The order of work for putting the iOS app in the App Store and Sill for Mac on the web: part 1
once, part 2 on every release. The texts and answers App Store Connect asks for, ready to paste,
are in `docs/app-store-metadata.md` ("metadata §N" below). The pages are in `site/` (plain HTML,
no build step), `Scripts/release.sh` makes the notarized Mac downloads (the disk image `Sill.dmg`,
with `Scripts/make-dmg.sh`, and the zip `Sill.zip`), and `Scripts/release-ios.sh` the iOS app's
build for App Store Connect (TestFlight, below).

## Placeholders

The domain and the support address are Noah's (confirmed 2026-09-25), and the App Store address
came with the App Store Connect record (2026-09-26). Each lives in the places listed.

| What | Now | Where |
|---|---|---|
| The site's domain | getsill.app (bought at Cloudflare 2026-09-25; live) | `site/CNAME`, the iOS app's links (`iOSClient/SillLinks.swift`), `README.md`, `docs/DEVELOPMENT.md`, `docs/app-store-metadata.md`, `Scripts/release.sh`, this file |
| The support address | `support@getsill.app` (Cloudflare Email Routing, 2026-09-25) | `site/privacy.html`, `site/support.html`, `README.md`, `docs/app-store-metadata.md`, this file |
| The current Mac build | none in the page: it links `releases/latest/download/Sill.dmg` and `Sill.dmg.sha256` (since Sill for Mac 0.3.1, PR #33), which GitHub redirects to the newest release; `release.sh --publish` uploads them under those names, with `Sill.zip` and `Sill.zip.sha256` beside them for older links | `site/download.html` (never edited per release, part 2) |
| The App Store address | `https://apps.apple.com/app/id6816359860`, the record's Apple ID (PR #27, 2026-09-26). Live since 2026-10-08 (0.5; 0.5.1 since 2026-10-10), so a Mac's update notice, the site and the README link a page that answers | `iOSClient/SillLinks.swift` (`appStoreText`; `release-ios.sh` stops on a line that isn't an App Store address) |

To change one, with the new value in place of `<address>` or `<domain>`: the first command
changes the support address, the second the domain everywhere, the address's own included.

```
grep -rl 'support@getsill\.app' site README.md docs/app-store-metadata.md docs/release-checklist.md | xargs sed -i '' 's#support@getsill\.app#<address>#g'
grep -rl 'getsill\.app' site iOSClient docs Scripts README.md | xargs sed -i '' 's#getsill\.app#<domain>#g'
```

## Part 1: once

### 1. A Developer ID certificate

Only the Account Holder can make one.

- [ ] Xcode › Settings › Accounts › your team › Manage Certificates… › + › Developer ID
      Application. Xcode makes the private key and puts both in your login keychain. (Or
      developer.apple.com › Certificates, Identifiers & Profiles › + › Developer ID Application,
      with a certificate request from Keychain Access.)
- [ ] Check: `security find-identity -v -p codesigning` lists
      `Developer ID Application: … (9B2KKVM937)`.
- [ ] Back it up: Keychain Access › My Certificates › the certificate › Export… as a .p12 with a
      password, kept outside the repo. Apple limits how many you can make. Sill's designated
      requirement names the team, not the certificate, so a later certificate from the same team
      keeps everyone's Screen Recording and Accessibility permissions.
- Your own Mac keeps its permissions as long as its builds stay Apple Development, so keep
  `SILL_SIGN_IDENTITY` out of your shell profile (§2). A Developer ID build has a different
  designated requirement: opening one on this Mac asks for both permissions again. Try each
  release on another Mac or user account instead (part 2).

### 2. Notary credentials

Stored in your keychain under one profile name. Either:

- [ ] An App Store Connect API key: App Store Connect › Users and Access › Integrations › App
      Store Connect API › Team Keys › +, access Developer. Download the .p8 (Apple lets you
      download it only once) and keep it outside the repo, then run
      `xcrun notarytool store-credentials sill-notary --key <path to AuthKey_KEYID.p8> --key-id <KEYID> --issuer <issuer ID>`.
- [ ] Or an app-specific password: account.apple.com › Sign-In and Security › App-Specific
      Passwords, then `xcrun notarytool store-credentials sill-notary --apple-id <your Apple ID> --team-id 9B2KKVM937`
      and paste the password when asked.

Give both to the release command, never to your shell profile. `make-app.sh` signs every build
with `SILL_SIGN_IDENTITY` when it is set, `--install` included, so an exported Developer ID
identity would re-sign your everyday Sill.app, and macOS would ask for Screen Recording and
Accessibility again.

```
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh --dry-run
```

To type them once, put the two lines `export SILL_SIGN_IDENTITY=…` and
`export SILL_NOTARY_PROFILE=sill-notary` in a file of their own, such as `~/.sill-release`, and
run `(. ~/.sill-release && Scripts/release.sh --dry-run)`. The parentheses keep them out of your
shell.

- [ ] Rehearse with that command: `--dry-run` checks the setup, builds, signs and zips, makes the
      disk image `.build/Sill-<version>.dmg` signed with the same identity, and stops before
      anything goes to Apple. When something is missing it says what, and builds nothing. It
      builds any commit and only warns that HEAD lacks the release's tag (part 2), which a real
      run refuses to build without. `spctl -a -vv -t open --context context:primary-signature
      .build/Sill-<version>.dmg` then says `source=Unnotarized Developer ID`, which a real run's
      notarization turns into `Notarized Developer ID`. Last rehearsed 2026-09-27 on main at
      643af6b (PRs #34 to #36 in), in a fresh worktree: exit 0 in 54 s, Sill 0.3.1 (391) for
      arm64 with the hardened runtime, a timestamp and no entitlements, `Sill-0.3.1.zip` and
      `Sill-0.3.1.dmg` of 3.0 MB each, the image's window and signature as make-dmg.sh checks
      them, no keychain prompt, and only the warning that HEAD lacks the tag.
- [ ] Look at the disk image once, on this Mac (it isn't notarized, so nowhere else): double-click
      `.build/Sill-<version>.dmg`. Its window should show Sill on the left and Applications on the
      right with the arrow between them and "To install Sill, drag it to Applications." under it,
      no toolbar or sidebar, all white to the window's edges, and the Sill disk in the Finder's
      sidebar with Sill's icon. The window is sized for macOS 27's 32-point title bar
      (`DMGLayout.titleBar`): after a two-finger scroll inside it, everything should settle back
      where it was (a window a few points too short for its picture stays scrolled by those
      points). Switch the Mac to Dark Mode (System Settings › Appearance) and look again: the
      names under the two icons must still be readable on the white picture (if the Finder draws
      them white there, design/DMGBackground.svg needs a change before the page links the image).
      Eject it, and don't drag this copy to Applications: a Developer ID build asks for Screen
      Recording and Accessibility again (part 1 §1).

### 3. The website

Preview it with `python3 -m http.server 8000 --directory site` and http://localhost:8000.

Before it goes public (Saffsanity/sill went public on 2026-09-26, after the sweep of PR #24; the
unchecked items below were done that day or record what was decided):

- [x] Done 2026-09-25: `support@getsill.app` reaches Noah's mailbox (Cloudflare Email Routing,
      below). Apple wants real contact details behind the Support URL (guideline 1.5).
- [ ] Remote Access: the pages describe it (PR #13, on main since ba91136). For a release without
      it, delete each block from `<!-- Remote Access` to `<!-- /Remote Access -->`. Then this must
      print nothing: `grep -n -i -E 'remote access|vpn|tailscale|port you forward' site/*.html |
      grep -v '“Sill Remote Access”'` (that is the keychain item's name, which stays). Pairing and
      the camera are no longer Remote Access's: every device pairs since pairing at home (PR #37),
      so the pages describe both outside the blocks.
- [x] Done 2026-09-26: the repository is public with its LICENSE (Apache-2.0, since PR #15), and
      `index.html` says "Free and open source" with the GitHub link, `support.html` links the
      issues, and the README shows its CI badge. Sill for Mac already says "free and open source"
      (`NSHumanReadableCopyright` in `Packaging/Info.plist`, and the footnote in Settings,
      `SettingsPanes.swift`). If the repository is still private at the first Developer ID
      release, decide whether those wait too.
- [x] `download.html` links the newest GitHub Release; nothing per release (part 2).

Hosting: GitHub Pages. On GitHub Free it serves only public repositories, and from a branch it
serves the root or `/docs`, never `/site`. So:

- [x] Done 2026-09-25: the public repository Saffsanity/sill-site holds a copy of `site/`, with
      Pages on (main, / root) and the custom domain set. Republish when `site/` changes, right
      after the release whose builds the change describes (part 2, the last item):
- Words on main for a release not out yet are marked: the clipboard's (PR #78) between
  `<!-- Clipboard` and `<!-- /Clipboard -->`, privacy.html's item on the device's request for the
  picture again after it was interrupted (PR #93, kind 44) between `<!-- Keyframe` and
  `<!-- /Keyframe -->`, the display wake's (PR #151, support.html's paragraph on Sill waking a
  sleeping display) between `<!-- Display wake` and `<!-- /Display wake -->`,
  support.html's paragraph on other languages and dictation (PR #147, issue #138) between
  `<!-- Other languages` and `<!-- /Other languages -->`, the sound's (PR #94, Send
  Audio, a beta) between `<!-- Sound` and `<!-- /Sound -->`, the connect screen's tiles'
  (PR #117, privacy.html's items on the tiles' pictures and group names and on the request
  for the picture once more as you disconnect) between `<!-- Tiles` and `<!-- /Tiles -->`,
  Reverse Scrolling's (PR #159: privacy.html's item and support.html's section) between
  `<!-- Reverse Scrolling` and `<!-- /Reverse Scrolling -->`, support.html's item on the
  pairing window and screen sharing (PR #157, Sill for Mac's Show the pairing window to screen
  sharing) between `<!-- Pairing window` and `<!-- /Pairing window -->`, support.html's
  paragraph that Virtual Display is on unless you turn it off (PR #236, Sill for Mac's default
  since 2026-10-27) between `<!-- Virtual Display` and `<!-- /Virtual Display -->`, support.html's
  paragraph on Aa's Off and Aa dimmed over the Desktop (PR #181, issue #179) between `<!-- Aa Off`
  and `<!-- /Aa Off -->`, the thumbnail hold's (PR #248, issue #113: privacy.html's item and
  support.html's section) between `<!-- Thumbnail hold` and `<!-- /Thumbnail hold -->`, and
  support.html's sentence that Sill for Mac names a firewall that blocks it, in its menu and its
  Settings (PR #250; the item's command before it holds for the builds out too), between
  `<!-- Firewall` and `<!-- /Firewall -->`. A republish before those
  releases (for words that hold for the builds already out, such as support.html's on a Mac asleep
  or restarted, or on a black picture) deletes the blocks of each release not out yet in the
  sill-site copy after the rsync below (the perl lines, one per marker) and puts privacy.html's
  date back to the one last published; then `grep -n -i clipboard ../sill-site/*.html` prints only
  privacy.html's log line ("which devices share the clipboard", true of the builds out too, as
  "what you copy" in its lede and "never what you copy" in both log lines are), and
  `grep -n -i keyframe ../sill-site/*.html`,
  `grep -n "wakes your Mac’s display" ../sill-site/*.html`,
  `grep -n -i -E 'dictation|Control-Space' ../sill-site/*.html`,
  `grep -n -i -E 'sound|send audio' ../sill-site/*.html`,
  `grep -n -i -E 'tiles|group name' ../sill-site/*.html`,
  `grep -n -i 'reverse scrolling' ../sill-site/*.html`,
  `grep -n -i 'screen sharing' ../sill-site/*.html`,
  `grep -n 'Virtual Display is on unless' ../sill-site/*.html`,
  `grep -n 'Aa starts at Off' ../sill-site/*.html`,
  `grep -n "hold a window’s thumbnail" ../sill-site/*.html` and
  `grep -n 'Devices Can’t Connect' ../sill-site/*.html` print nothing. The release that ships each
  deletes its markers in `site/` and keeps the words.
- Once sill is public, it can serve the site itself: `git subtree push --prefix site origin gh-pages`,
  then Settings › Pages › gh-pages, / (root). Retire sill-site then.

```
git clone https://github.com/Saffsanity/sill-site.git ../sill-site     # once
rsync -a --delete --exclude .git --exclude .github --exclude .nojekyll site/ ../sill-site/   # when the site changes
perl -0pi -e 's/[ \t]*<!-- Clipboard:.*?<!-- \/Clipboard -->\n//gs' ../sill-site/*.html   # only before the clipboard's release
perl -0pi -e 's/[ \t]*<!-- Keyframe:.*?<!-- \/Keyframe -->\n//gs' ../sill-site/*.html   # only before the keyframe request's release (PR #93)
perl -0pi -e 's/[ \t]*<!-- Display wake:.*?<!-- \/Display wake -->\n//gs' ../sill-site/*.html   # only before the display wake's release
perl -0pi -e 's/[ \t]*<!-- Other languages:.*?<!-- \/Other languages -->\n//gs' ../sill-site/*.html   # only before the release of other languages and dictation
perl -0pi -e 's/[ \t]*<!-- Sound:.*?<!-- \/Sound -->\n//gs' ../sill-site/*.html   # only before the sound's release
perl -0pi -e 's/[ \t]*<!-- Tiles:.*?<!-- \/Tiles -->\n//gs' ../sill-site/*.html           # only before the tiles' release
perl -0pi -e 's/[ \t]*<!-- Reverse Scrolling:.*?<!-- \/Reverse Scrolling -->\n//gs' ../sill-site/*.html   # only before Reverse Scrolling's release
perl -0pi -e 's/[ \t]*<!-- Pairing window:.*?<!-- \/Pairing window -->\n//gs' ../sill-site/*.html   # only before the release with PR #157
perl -0pi -e 's/[ \t]*<!-- Virtual Display:.*?<!-- \/Virtual Display -->\n//gs' ../sill-site/*.html   # only before the release that turns Virtual Display on by default
perl -0pi -e 's/[ \t]*<!-- Aa Off:.*?<!-- \/Aa Off -->\n//gs' ../sill-site/*.html   # only before the release with PR #181 (Aa's Off)
perl -0pi -e 's/[ \t]*<!-- Thumbnail hold:.*?<!-- \/Thumbnail hold -->\n//gs' ../sill-site/*.html   # only before the thumbnail hold's release (PR #248)
perl -0pi -e 's/[ \t]*<!-- Firewall:.*?<!-- \/Firewall -->\n//gs' ../sill-site/*.html   # only before the release that names a firewall that blocks Sill
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

sill-site has two files of its own that `site/` lacks, `.nojekyll` and `.github/FUNDING.yml` (its
Sponsor button); the two excludes keep `--delete` off them.

- [x] Domain, done 2026-09-25: getsill.app at Cloudflare, with A records to GitHub Pages
      (185.199.108.153, .109, .110, .111), the matching AAAA records (2606:50c0:8000::153 to
      8003::153), and Email Routing forwarding support@ to Noah's mailbox. Since 2026-09-27 the
      records are DNS only (Cloudflare's proxy is off, so the site may serve video, which
      Cloudflare's free plan forbids), `www` is a CNAME to saffsanity.github.io, and GitHub serves
      the pages with its own certificate for both names (expiring 2026-12-26; GitHub renews it).
- [x] Done 2026-09-27: with the proxy off, Cloudflare's SSL/TLS mode, Always Use HTTPS and Email
      Address Obfuscation no longer touch the site (the pages' `<!--email_off-->` comments stay,
      inert), and the domain is verified for the Saffsanity GitHub account (the TXT record
      `_github-pages-challenge-Saffsanity`, which stays).
- [x] Done 2026-09-27: Enforce HTTPS is on in sill-site's Settings › Pages.
- [ ] In a private window: https://getsill.app/, `/download`, `/privacy` and `/support` all
      load. GitHub Pages serves `privacy.html` at `/privacy`, the form the app and App Store
      Connect use.

### 4. The App Store Connect record

Field by field, with the values and in the order App Store Connect asks: TestFlight §1 below.

- [x] Done 2026-09-26: New App (metadata §1): iOS, bundle ID me.saffer.sill, SKU sill-ios. "Sill"
      was taken, so the record was made as "Sill – Window Streaming" and is now "Sill – Mac
      Streaming" (PR #28), Apple ID 6816359860.
- [ ] App Information (metadata §2): category, content rights, the age rating (every answer
      none: 4+) and the EU trader status (Business › Agreements › Compliance › Digital Services
      Act).
- [ ] Pricing and Availability (metadata §3): free; not available on Apple silicon Macs or
      Apple Vision Pro.
- [ ] App Privacy (metadata §4): Privacy Policy URL `https://getsill.app/privacy`, and "No,
      we do not collect data from this app", published as Data Not Collected. The privacy policy
      and the app's privacy manifest say the same.
- [ ] The first version, 0.5 (metadata §5 and §9): its Version field says 0.5 (App Store Connect
      proposes 1.0), Support URL `https://getsill.app/support`, the description, keywords and
      screenshots.
- [ ] For a build without Remote Access, paste the local-only keywords, What's New
      and review notes, leave out the description's "Away from home" bullet, and film no shot 11
      (metadata, the Remote Access switch). Then nothing you paste mentions Remote Access, a VPN
      or Tailscale. Pairing and the camera stay: every device pairs since PR #37.
- [ ] Export compliance (metadata §6): nothing to answer. The app's Info.plist says NO
      (`ITSAppUsesNonExemptEncryption`), so the uploaded build must not show Missing Compliance.
- [ ] App Review Information (metadata §7 and §8): contact, notes, the video.
- [ ] Version Release: Manually release this version, so an approval waits for the Mac download.
- [x] Done 2026-09-26 (PR #27): `iOSClient/SillLinks.swift` gives
      `https://apps.apple.com/app/id6816359860`, so a Mac that needs a newer Sill on the device
      shows "Update Sill in the App Store" under its notice (TestFlight §2).

### 5. The keychain provisioning profile (for the hardened identity keychain)

Recommended before the first public build (docs/keychain-plan.md): it moves Sill's remote‑access
identity (the Mac's key, the trust list, Require pairing) from the legacy login keychain to the
data‑protection keychain, which no other process can pre‑create or read. Without it, a release
still builds and runs — it keeps the identity in the login keychain, and `make-app.sh --release`
and `release.sh` say so in the log. Landing it before the first public build means new installs
write straight to the strong keychain and only your own dev Macs need the reset below.

- [x] **Made 2026-09-27** on developer.apple.com (Certificates, Identifiers & Profiles): the App ID
      "Sill for Mac", `me.saffer.sill.mac`, and the Developer ID provisioning profile **"Sill
      Developer ID"**, UUID `18e9509f-5498-4533-ba59-293461a61a0d`, platform macOS, team
      9B2KKVM937, all Macs, for the Developer ID Application certificate (SHA‑1 `42424F38…71D8D6`).
      It grants `com.apple.application-identifier` `9B2KKVM937.me.saffer.sill.mac`,
      `com.apple.developer.team-identifier` 9B2KKVM937 and `keychain-access-groups`
      `9B2KKVM937.*`, which covers the group `9B2KKVM937.me.saffer.sill.mac`. It expires
      **2044‑09‑22** (Apple issues them for 18 years).
- Where it lives: `Packaging/embedded.provisionprofile` (git‑ignored; the copy make-app.sh embeds),
      backed up as `~/Library/Developer/Xcode/UserData/Provisioning Profiles/18e9509f-5498-4533-ba59-293461a61a0d.provisionprofile`
      and as the download, `~/Downloads/Sill_Developer_ID.provisionprofile`; all three byte for
      byte the same (SHA‑256 `4f9f99b0…d996ed65`). It holds no secret (Apple's signature, the
      public certificate, the entitlements), and the developer site downloads it again at any time.
      `SILL_PROVISION_PROFILE` points make-app.sh at another copy.
- Check: `security cms -D -i Packaging/embedded.provisionprofile` prints its plist; a Mac profile
      names the app `Entitlements › com.apple.application-identifier` (`application-identifier` is
      the iOS key, and an app signed with it is killed at launch: docs/keychain-plan.md §9b).
      `make-app.sh --release` prints `identity keychain: data-protection keychain (access group
      9B2KKVM937.me.saffer.sill.mac)`. It refuses, before it writes an app that macOS would kill
      at launch, a profile that doesn't grant what `Packaging/SillRelease.entitlements` asks for
      (the application identifier, the team, the keychain group, and any entitlement added to
      that file later), doesn't list the certificate that signed the build, has expired, or
      doesn't decode. Proved with this profile on 2026‑09‑27 (docs/keychain-plan.md §9b): the
      build launches, and only an entitled build reads the group.
- [ ] **By 2027‑02‑01: the certificate, then the profile.** The profile outlives the certificate it
      lists: the Developer ID Application certificate ends on 2027‑02‑01, with the Apple CA that
      issued it ("Developer ID Certification Authority", 2012–2027). Apple says a build signed with a
      secure timestamp before then keeps launching (not something this Mac can test yet); a build
      after it needs a new Developer ID certificate (§1) and then the profile with it: on the
      developer site, edit "Sill Developer ID" to use the new certificate (or make a new Developer ID
      profile for `me.saffer.sill.mac`), download it, and replace
      `Packaging/embedded.provisionprofile` and the backups. Until then make-app.sh refuses: "lists
      the certificates […], not the one that signed this build".
- To make one again from nothing (another team, a lost account): on developer.apple.com register
      the explicit App ID `me.saffer.sill.mac`, then a provisioning profile of type Developer ID
      for macOS with that App ID and the Developer ID Application certificate, and download it. (The
      plan's other way, `xcodebuild -allowProvisioningUpdates` from a throwaway macOS target with
      Keychain Sharing, registers the same things from Xcode and may prompt for your Apple Account;
      a background or CI run must not do either.)
- One team, two certificates: both identities on this Mac are team **9B2KKVM937** (the
      Apple Development certificate's name ends in HG877AGTQ7, your own member ID, not a team). The
      profile lists only the Developer ID certificate, so only the Developer ID build carries the
      profile and the access group; a development build (make-app.sh's default) must **not** — it
      keeps `SillDebug.entitlements` and the login keychain. Signed with the Apple Development
      certificate, the same entitlements and this profile, a build is killed at launch (measured
      2026‑09‑27).
- Profile validity: Gatekeeper checks the profile at **every launch**, so an expired one stops the
      app launching. `make-app.sh` refuses an expired profile and warns within 30 days. A
      **missing** profile is the safe fallback — the release builds on the login keychain with a log
      line — but an **expired** one is an error, not a fallback, because it would already be
      embedded.
- Releases from GitHub Actions: the runner has no `Packaging/embedded.provisionprofile` (it is
      git‑ignored), so a release the release workflow makes ships on the login keychain, and its log
      says so. To harden those too, the workflow needs the profile (a secret written to that path
      before `release.sh`, or the file committed, which holds no secret): not done yet
      (docs/keychain-plan.md §10).
- No auto‑migration (the security review, docs/keychain-plan.md §9a): an entitled build never reads
      the login keychain, so a dev Mac that used remote access on the legacy store gets a **fresh**
      key and Mac ID on its first hardened launch (any device paired to it re‑pairs). Remote access
      is off by default and home pairing has not shipped publicly, so this is near zero. To start
      clean, delete the legacy items by hand — `for a in recognition-key paired-devices
      require-pairing; do security delete-generic-password -s me.saffer.sill.remote -a $a; done`, and
      the "Sill Remote Access" key in Keychain Access — and re‑pair. On a Mac you own, never in CI.

### 6. Homebrew

Sill for Mac is a cask, `sill`, in Sill's own tap. Homebrew's main repository (homebrew/cask)
comes later, when the cask qualifies (below).

- [x] Done 2026-10-14: the public repository
      [Saffsanity/homebrew-sill](https://github.com/Saffsanity/homebrew-sill) is the tap
      `saffsanity/sill`. It holds `Casks/sill.rb` (the release's `Sill.dmg` by its version and
      SHA-256, `depends_on arch: :arm64` and `depends_on macos: :sonoma` as the app's own
      Info.plist and binary say, a livecheck on the latest GitHub release, and a `zap` for
      `~/Library/Logs/Sill` and `~/Library/Preferences/me.saffer.sill.mac.plist`, all Sill leaves
      outside the keychain), a README and Sill's license. Its workflow is the one `brew tap-new`
      writes, for casks only (`brew test-bot --only-cleanup-before`, `--only-setup` and
      `--only-tap-syntax`: style, `readall` and `audit`), and `brew audit --cask --online
      --strict`, which downloads the image and checks its SHA-256, the version against the
      latest release and the minimum macOS against the app. It runs on pull requests and on
      pushes to main.
- Installing: `brew install --cask saffsanity/sill/sill` taps it and trusts that one cask. Since
      Homebrew 6 a cask from a tap that isn't Homebrew's own loads only once it is trusted: after
      `brew tap saffsanity/sill` alone, `brew install --cask sill` stops at "Refusing to load cask
      saffsanity/sill/sill from untrusted tap saffsanity/sill" until `brew trust --cask
      saffsanity/sill/sill`.
- On this Mac, never install the cask into /Applications, where Sill.app runs: give `brew install
      --cask` an `--appdir` of a scratch folder (Homebrew remembers it, and `brew uninstall`
      removes the app from there), and never `brew uninstall --zap`, which trashes the running
      Sill's settings and log.
- [ ] Homebrew's main repository, so that `brew install --cask sill` works with no tap. On
      2026-10-14 `brew audit --cask --new --online --strict saffsanity/sill/sill` failed one rule
      alone: "GitHub repository too new (22 days old, 30 days required)". Saffsanity/sill was made
      on 2026-09-22, so that passes from 2026-10-22. Two more rules run only in homebrew/cask's
      own checks: the homepage's domain must be 30 days old (getsill.app was registered on
      2026-09-25, so from 2026-10-25), and a pull request from the repository's owner is a
      self-submission, which needs 90 forks, 90 watchers or 225 stars instead of 30, 30 or 75
      (on 2026-10-14: 228 stars, 8 forks, 1 watcher, so it holds only while the stars stay at 225
      or more). The earliest day is 2026-10-25.
- The pull request is Noah's own. Homebrew's rules for AI-assisted pull requests
      ([Responsible AI Usage](https://docs.brew.sh/Responsible-AI-Usage), and the template's last
      checkbox): no commit names an AI as author or co-author (no `Co-Authored-By` trailer), the
      description names the tool, the author has reviewed it all, the `zap` paths included, and
      answers every question and review comment himself, without AI; a contributor who isn't a
      maintainer may have one AI-assisted pull request open at a time.
- The steps ([How to Open a Homebrew Pull Request](https://docs.brew.sh/How-To-Open-a-Homebrew-Pull-Request)):
      fork Homebrew/homebrew-cask, `brew tap --force homebrew/cask`, add the fork as a remote of
      `$(brew --repository homebrew/cask)`, and on a branch from `origin/HEAD` copy the tap's cask to
      `Casks/s/sill.rb` with the version then current. Run `brew audit --cask --new --online
      --strict sill`, `brew style --fix --cask sill`, `HOMEBREW_NO_INSTALL_FROM_API=1 brew install
      --cask --appdir=<a scratch folder> sill`, `brew uninstall --cask sill` and `brew lgtm
      --online`; then one commit and a pull request, both titled "sill <version> (new cask)", the
      template's boxes ticked only for what was run.
- Once it merges: in the tap, delete `Casks/sill.rb` and add `tap_migrations.json` with
      `{ "sill": "homebrew/cask" }`, in one commit, "sill: migrate to homebrew/cask", so a Mac
      that installed from the tap moves over at its next `brew update`. Then
      `site/download.html`, the README, the tap's README and part 2's Homebrew item say `brew
      install --cask sill`.

## Part 2: every release

- [ ] Versions: one number for both apps. From 0.5.1 on, a release's Sill for Mac and Sill for
      iPhone and iPad carry the same version (Noah, 2026-10-09: "I want the release in the
      GitHub to line up with the app version, I want all versions to be 0.5.1"), set together
      in the release's pull request: Sill for Mac's `CFBundleShortVersionString` in
      `Packaging/Info.plist`, and the iOS app's MARKETING_VERSION in both configurations of
      `iOSClient/Sill.xcodeproj` (target Sill › General). The tag is `v` + that number, and the
      GitHub Release, its assets (`.build/Sill-<version>.dmg`), TestFlight's version and the App
      Store's all say it. The build numbers stay each app's own: Sill for Mac's is the commit
      count, which make-app.sh stamps in; the iOS app's, CURRENT_PROJECT_VERSION in both
      configurations, keeps counting across versions (0.5 had builds 1 to 3, 0.5.1 starts at
      4), so a build number names one upload whatever its version. Put the device build's number
      in the same pull request as the version, so the tag below names the commit that both come
      from; `release-ios.sh --upload` then needs no `--bump` (while the nightlies run, the device
      build's number is the commit count instead, never committed: the iOS item below, and
      Nightlies). Before 0.5.1 the two counted
      apart (Sill for Mac 0.3.0, 0.3.1 and 0.4.0 beside Sill for iPhone and iPad 0.5; there was
      never a Sill for Mac 0.4.1). A release that changes only one app is Noah's call: both at
      the new number, or the other left at its last (nothing in the code compares the two).
      main carries the next release's number, both apps together, from soon after the last
      release on: 0.5.5 since 2026-10-29 (PR #244), ahead of 0.5.1 on
      the App Store and on GitHub. App Store Connect takes no new build of a version it has
      released (its train is closed), so every build of main for TestFlight needs the next
      number; and Sill.app's update check compares only release tags with the version it runs,
      so a build of main saying 0.5.5 is offered nothing until a release newer than 0.5.5 exists.
      The release's tag then names a commit of main that already says its number.
- [ ] A Mac release and a device build that need each other (a change to the home door or the wire
      that older builds on the other side can't follow): the release notes say which versions go
      together, the device build is uploaded first (App Store Connect takes 5 to 30 minutes to
      process it, and nobody can install it before), its What to Test goes on as soon as it shows
      in TestFlight (internal testers with automatic distribution get it the moment it is
      processed), one device tries it from TestFlight against a Mac that runs a build of the same
      commit (processed is not tested, and the builds tried before it are usually Debug ones),
      the Mac release is published once that works, and the site is republished right after (the
      Download button gives the newest release's Sill.dmg the moment it is published, so the
      pages' words should follow within minutes). A device with the new build and a Mac without
      its release is the gentler half of the gap: whichever side can say what to update must be
      the one that arrives first.
- [ ] Tag that commit `v` + the release's version, both apps', and push the tag: `git tag -a v0.5.1
      -m "Sill 0.5.1: …"` and `git push origin v0.5.1` for 0.5.1 (v0.3.0, v0.3.1 and v0.4.0 are
      annotated tags on merge commits of main: v0.4.0 on its release pull request's, #41, v0.3.1 on
      #32's, and v0.3.0 on main's head that day, #20's). `make-app.sh --release` builds only the
      commit carrying it, and `release.sh --publish` refuses to start until origin's tag names that
      commit, then makes the GitHub Release for it. Every Sill.app's update check reads the releases
      of Saffsanity/sill alone (`UpdatePolicy.feed`) and compares the newest published one's tag
      (not a draft, not a prerelease) with the version it runs: Saffsanity/sill is public (since
      2026-09-26), so within a day of a release there every older Sill.app offers it (Check Now in
      Settings › General asks at once). A private repository's releases answer the check with a 404,
      and then no Sill.app offers anything.
- [ ] The release command from part 1 §2, without `--dry-run`. It builds, notarizes, staples and
      zips, checks a copy unpacked from the zip the way Gatekeeper will, then puts the stapled app
      in the disk image (`Scripts/make-dmg.sh`, signed with the same identity), has Apple notarize
      the image too, staples its ticket and checks it (`hdiutil verify`, `stapler validate`,
      `spctl`'s open context as "Notarized Developer ID", and the Sill.app inside it as the zip's
      copy was checked). It prints both files' paths and SHA-256 and where Apple's two notary logs
      are (`.build/Sill-<version>-notary-log.json`, `…-dmg-notary-log.json`). It warns when a log
      lists issues: read them. Two submissions, so it waits for Apple twice.
- [ ] Try the disk image as someone new to Sill would, on another Mac or a new macOS user account,
      with the quarantine flag a download sets: before publishing, the real run's
      `.build/Sill-<version>.dmg` sent there by AirDrop (which sets it too); once published, the
      image downloaded from the release (a release published in one `--publish` run is tried
      then). Open it, drag Sill to Applications in its window, open it, allow the permissions and
      stream to a device. For 1.0 this is the reviewer's path: film it for the review video
      (metadata §8).
- [ ] Publish: `Scripts/release.sh --publish` (with the same two variables), or a pushed tag with
      the release workflow ("Releasing from GitHub Actions" below), creates the GitHub Release
      `v<version>` in Saffsanity/sill with the assets `Sill.dmg`, `Sill.dmg.sha256`, `Sill.zip` and
      `Sill.zip.sha256`; before it builds, `--publish` checks that origin has the tag and that it
      names HEAD (the workflow's checkout is the commit its run was started for, with every tag,
      and it stops when the tag no longer names it). The site's Download button links
      `releases/latest/download/<name>`, which GitHub redirects to the newest release, so
      download.html is never edited per release (its one exception, the move to Sill.dmg, is done:
      below). Anonymous downloads and the update check need a public repository, which
      Saffsanity/sill is since 2026-09-26. While it was private,
      `SILL_RELEASE_REPO=Saffsanity/sill-site` was the way out (with download.html's three GitHub
      links pointed there too); release.sh still warns that no Sill.app offers a release published
      anywhere but Saffsanity/sill, so leave `SILL_RELEASE_REPO` unset (in `~/.sill-release` and as
      a repository variable). One way or the other for a version: pushing the tag, which a local
      `--publish` needs first, also starts the release workflow. With `SILL_SIGN_IN_CI` set to
      `true` that run publishes the release once Noah approves it (Releasing from GitHub Actions ›
      What a tag does), so don't also run `--publish` here (whichever comes
      second stops at "already exists"); without it the run only verifies (macOS minutes either
      way). Neither the variable nor any secret is set on 2026-09-27, so a pushed tag only verifies.
- [ ] Release notes: `--publish` gives the release a one-line body (the version, the build and
      both SHA-256). Replace it with the release's notes, keeping that line as their last, with
      `gh release edit v<version> --repo Saffsanity/sill --notes-file <notes>` (as for v0.3.0 and
      v0.3.1): what is new, the requirements, which device builds go with it, and how to check the
      download. The update check opens the release's page, so this is what every Sill.app that
      offers the update shows first.
- [ ] Check what was published, signed out: `gh release view v<version> --json assets` lists the
      four assets; `curl -sSLo` each of Sill.dmg and Sill.zip from
      `https://github.com/Saffsanity/sill/releases/latest/download/<name>`, `shasum -c` against its
      `.sha256`, `spctl -a -vv -t open --context context:primary-signature` on the image and
      `spctl -a -vv -t exec` on the Sill.app inside each ("Notarized Developer ID"), and the app's
      `CFBundleShortVersionString` and `CFBundleVersion`.
- [ ] Homebrew: bump the cask once the release is published (its `Sill.dmg` must answer). In the
      tap (part 1 §6), from a Mac that has it tapped and the cask trusted: `brew bump-cask-pr
      --no-fork --version <version> --sha256 <SHA-256> saffsanity/sill/sill`, the SHA-256 the one in
      the release's `Sill.dmg.sha256`, commits `sill <version>` on a branch of the tap, pushes it
      and opens a pull request there; merge it when its `brew test-bot` run is green (it downloads
      the image and checks the SHA-256, and the version against the latest release). By hand it is
      the same two lines, `version` and `sha256` in `Casks/sill.rb`, a commit `sill <version>` and
      a pull request. Then `brew update` and `brew upgrade --cask sill` offer the release. Once the
      cask is in Homebrew's main repository there is nothing to do: BrewTestBot opens the bump
      there within about three hours of the release, since the cask has a livecheck, and `brew
      bump-cask-pr sill` refuses to; check that it merged (`brew info --cask sill`).
- [x] Done 2026-09-27 with Sill for Mac 0.3.1 (PR #33; sill-site 39754b9): the download page
      moved to Sill.dmg, after the release that carries it was published and its
      `releases/latest/download/Sill.dmg` answered.
- [ ] Keep `Sill.zip` in every release for now: `release.sh --publish` uploads it beside the disk
      image, so the page's zip links keep working until it moves, and so do links that name
      `Sill.zip` elsewhere (v0.3.0's notes, pages people saved). Every Sill.app's update check
      opens the release's page, which lists both. Dropping the zip later is one line in
      `publish_release` (and its `.sha256`), for a release after the page has moved, never while
      download.html still links it.
- [x] Done 2026-09-26 with v0.3.0 (sill-site e4046a1): the first release, and the site
      republished right after Saffsanity/sill went public, so the button shows.
- [ ] iOS: `Scripts/release-ios.sh --bump --upload` (a new version's first upload without `--bump`:
      the release's pull request sets its version and build number); TestFlight §4 below. With the
      build number already committed in the release's pull request (the first item),
      `Scripts/release-ios.sh --upload` from the tagged commit. Or in Xcode: Any iOS Device, Product
      › Archive, then the Organizer's Validate App and Distribute App › App Store Connect › Upload.
      The privacy report: `Scripts/release-ios.sh --privacy-report`, and the Organizer's Generate
      Privacy Report for the PDF; both should list the privacy manifest's API categories. While
      the nightlies run (Nightlies, below), App Store Connect already has builds of the version
      numbered by commit count, far above the committed number: submit the nightly build of the
      tagged commit itself, or upload from the tag with `--build-number "$(git rev-list --count
      HEAD)"`, not `--bump`.
- [ ] TestFlight: internal testers get the build without review. An external group sends the
      first build through Beta App Review with the same notes and video: a cheap rehearsal
      (TestFlight §5 to §7 below). Every build has its own What to Test (TestFlight › the build ›
      Test Details): what changed since the build before, from the release notes (metadata §5).
- [ ] Review notes (metadata §7): describe what is new in this version specifically (guideline
      2.3.1(a)), and What's New (metadata §5).
- [ ] Submit for review with manual release. Release once the Mac download is live.
- [ ] If what Sill does or keeps changed, update `site/` too, with the privacy policy's date, and
      republish it (part 1 §3) right after the release is published: the pages describe the builds
      people can download, so words for a newer build wait for it, and words for the old one go
      with it. Since 2026-09-27 the published pages are v0.4.0's `site/`: privacy.html's line
      for the link report (PR #39, on main since 2026-10-08) and the away sentences of
      support.html and index.html go out with 0.5.1, with the privacy page's date.

### The pairing release: Sill for Mac 0.4.0 with Sill for iPhone and iPad 0.5 (2)

Pairing at home (PR #37) made the home door TLS 1.3 with pairing, and neither side works at home with
the other's older release (docs/home-pairing-plan.md §3.4, read again against the code on
2026-09-27):

- A device from before it (TestFlight's 0.5 (1), from b37f47a, or a build of main before PR #37) at
  Sill for Mac 0.4.0: it dials plain TCP, and the door fails the handshake (-9836) within
  milliseconds and closes. The device reads a TLS alert and EOF, shows its stream screen for a
  moment (build 1 counts a session from TCP's ready), then "‹Mac› disconnected. Sill will reconnect
  when it can reach it." (for a Mac it never saved, "…It will reconnect when the Mac is back."),
  and its reconnect dials the listed row again at once, over and over, for as long as both run:
  nothing spaces the tries while the Mac is listed (its 2 s timer only covers a Mac that is not),
  so it can flicker several times a second. Nobody has watched it on a device; the plan's "every
  2 s" was read from that timer. No notice can reach it through a failed handshake. The Mac's menu
  says "An iPhone or iPad Needs Sill Updated" from a source's third plain try within a minute, for
  10 minutes; those tries never start the door's backoff, so the updated device gets in at once.
  Remote Access still serves it (the remote door was TLS already), away from home.
- 0.5 (2), or any Release build from PR #37 on, at Sill for Mac 0.3.1 or earlier: that Sill
  advertises no `p` in its TXT record, a plain door, and a Release build never dials one (no
  downgrade). The row reads "Update Sill", and a tap dials nothing and says "‹Mac› runs an older
  Sill. Update Sill on the Mac to connect." The Mac sees nothing; its update check offers 0.4.0
  once it is published. A Debug build dials a plain door until it has seen that Mac speak TLS.
- Both new: every device pairs once, with the code over Wi-Fi or by itself over the cable, one
  paired for Remote Access before too. Keychain hardening (PR #42) keeps a release's identity, trust
  list and Require pairing in the data-protection keychain and never reads 0.3.1's login-keychain
  items (no migration, docs/keychain-plan.md §9a), so a Mac that ran 0.3.1 with Remote Access
  starts 0.4.0 with a new key and Mac ID and none of its pairings. A device paired at home learns the Mac's addresses for afar only in a session at home while Remote Access
  is on (the Mac lists them only then); without them a dial away says only that the Mac didn't
  answer.

So the device build goes first (it says what to update), then the Mac, in this order, once PRs
#37, #38, #42 and #43 are on main and Noah has tried main's build, one device of it a Release build as
TestFlight's is (a Debug build dials a plain door it has not seen speak TLS, and shows the tour only
when asked):

- [ ] The release's pull request (branch `release-next`): main merged in, the words that waited for
      the three (the site's pages, the README's How it works, the metadata, this section),
      `CFBundleShortVersionString` 0.4.0 and `CURRENT_PROJECT_VERSION` 2; CI green; merged.
- [ ] Tag its merge commit: `git tag -a v0.4.0 -m "Sill for Mac 0.4.0: pairing at home"` and
      `git push origin v0.4.0` (the release workflow verifies it: neither `SILL_SIGN_IN_CI` nor a
      secret is set).
- [ ] From that commit, `Scripts/release-ios.sh --upload`: 0.5 (2) to App Store Connect. As soon as
      it shows under TestFlight, its What to Test (the build › Test Details): internal testers
      with automatic distribution get it the moment it is processed (5 to 30 minutes, and an
      email).
- [ ] Once it is processed, one device installs it from TestFlight and connects at home to a Mac
      that runs this release's code (Noah's build of main from his trial will do: the release
      commit adds only words and the two version numbers): the Release build's first session at
      the new door. If that fails, stop here, with only an internal TestFlight build out: fix,
      and the next device build is 3.
- [ ] Stage the site: the tagged pages rsynced into the sill-site clone (part 1 §3) and committed,
      not pushed yet.
- [ ] The keychain profile in place: `Packaging/embedded.provisionprofile` (git-ignored; part 1 §5,
      "Sill Developer ID"). This release must be built with it: `make-app.sh --release`, which
      release.sh runs, prints `identity keychain: data-protection keychain (access group
      9B2KKVM937.me.saffer.sill.mac)` and release.sh "Identity keychain: data-protection". Without
      it the build falls back to the login keychain and says so: stop, since the notes tell users
      their Mac's keys moved. The rehearsal (`release.sh --dry-run`) shows the same lines first.
- [ ] Then `Scripts/release.sh --publish` from the same commit (part 1 §2's variables), the notes
      over its one-line body (`gh release edit v0.4.0 --notes-file …`), the site's commit pushed
      at once (the Download button gives the new release's Sill.dmg the moment it is published,
      and the pages should say what it does), and the check of what was published, signed out.
- [ ] The Beta App Description (TestFlight §6).
- [ ] Noah's devices: Sill from TestFlight on the iPad and the iPhone, then Sill for Mac from the
      download on a Mac that runs a release (not the Apple Development build on this Mac, part 1
      §1). The iPad, paired for Remote Access on 2026-09-25, pairs once more (the Mac's new key,
      above), and so does the iPhone, with the code or over the cable; each reaches the Mac away
      from home once it has connected at home with Remote Access on.
- [ ] Not before 0.4.0 is the download: 0.5 (2) to an external group or App Review, which use the
      Sill for Mac that getsill.app/download gives.

### The away release: Sill for Mac and Sill for iPhone and iPad 0.5.1 (4)

The first release with one version for both apps (the first item of part 2). It brings away from
home (PR #39: a session through a VPN starts at Low · Standard, the Mac says when the link can't
keep up, a session away moves home by itself) and, on the device, the old record of a Mac set up
again retiring itself (PR #46), and the iPhone Duo (PR #47, the iOS 27.1 SDK: the layouts follow
the hinge, so the device build needs Xcode 27.1 or later). PRs #44 and #45, merged after the tag
v0.4.0, went to TestFlight as 0.5 (3) and are in it too.

Unlike the pairing release, neither half strands the other (docs/remote-bundle-plan.md, P13; read
from the code, not tried on a device): Sill for Mac 0.5.1 serves 0.5 (2) and (3), which get the
away quality when away but no header line or link notice (kind 16's `away` and `link` are
optional), and 0.5.1 (4) works with Sill for Mac 0.4.0, without the away quality or the notice
(the move home goes to 0.4.0's TLS home door, pinned). So the order matters less: the device build
first still gives App Store Connect its processing time while the Mac is notarized, and the notes,
What to Test and What's New say which part needs which (the away quality and the link's notice
come from the Mac).

- [ ] The release's pull request (branch `release-0.5.1`, a draft until the go): the versions
      (0.5.1, build 4), the site's lines (support's and index's away sentences, the privacy
      policy's date), the README's Good to know, the metadata (the description's Away bullet,
      the review notes' sentence, the version 0.5.1 (4) and its What's New), this section. Main
      merged in again first if another pull request landed meanwhile (PR #47, iPhone Duo, is
      expected to). CI green; merged.
- [ ] Before the tag: Noah's device test of away from home (CLAUDE.md, PR #39's P4 to P13). A
      claim it disproves comes out of the notes, What to Test, the site, the README and the
      metadata first. The privacy policy's "Last updated" is the day the site goes out.
- [ ] Tag the merge commit: `git tag -a v0.5.1 -m "Sill 0.5.1: away from home"` and `git push
      origin v0.5.1` (the release workflow verifies it).
- [ ] From the tag, `Scripts/release-ios.sh --upload`: 0.5.1 (4), the first build of the version
      0.5.1 (TestFlight opens the version by itself; App Store Connect's record needs nothing for
      that). Its What to Test as soon as it shows.
- [ ] The keychain profile in place and the rehearsal, as for the pairing release
      (`release.sh --dry-run` says "identity keychain: data-protection keychain (access group
      9B2KKVM937.me.saffer.sill.mac)" and Sill 0.5.1), then `Scripts/release.sh --publish` from
      the tag, the notes over its one-line body (`gh release edit v0.5.1 --notes-file …`), the
      site republished at once, and the check of what was published, signed out.
- [ ] The App Store, once 0.5 is Ready for Distribution (App Store Connect adds a version only
      then): the version 0.5.1 on the record (the + beside iOS App; 0.5's metadata is copied into
      it), its What's New (metadata §5), the description's Away bullet, the review notes'
      sentence (metadata §7), build 0.5.1 (4), and Submit for Review with manual release. Not
      before Sill for Mac 0.5.1 is the download: App Review uses the Mac that
      getsill.app/download gives, and the description's away claims are the Mac's.

## TestFlight

Sill for iPhone and iPad reaches testers, then the App Store, through App Store Connect.
`Scripts/release-ios.sh` makes the build and uploads it from this Mac; the rest is App Store
Connect's pages, in this order. The texts to paste are in `docs/app-store-metadata.md`. Nothing here
costs money: uploads and TestFlight come with the Apple Developer Program.

Already done (2026-09-26): the bundle ID is registered (Xcode's automatic signing made it; the
developer portal calls it "XC me saffer sill"), and the first export, `release-ios.sh`'s rehearsal,
made a cloud-managed Apple Distribution certificate, whose private key stays with Apple, and the
App Store profile "iOS Team Store Provisioning Profile: me.saffer.sill". Then the record (§1, "Sill
– Mac Streaming", Apple ID 6816359860), its address in the app (§2, PR #27), and the first build,
0.5 (1), uploaded with `release-ios.sh --upload` from b37f47a (§4), for internal testers.

### 1. The app's record

- [ ] Apps › + › New App:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Sill – Mac Streaming`, with an en dash (metadata §2): "Sill" was taken, and the record, first "Sill – Window Streaming", has this name since 2026-09-26 (PR #28) |
| Primary Language | English (U.S.) |
| Bundle ID | `me.saffer.sill`, listed as "XC me saffer sill - me.saffer.sill" |
| SKU | `sill-ios` (never shown; can't change) |
| User Access | Full Access |

- [ ] Then in the record. The reasons, and the long texts, are metadata §2 to §7; the version
      page's texts, screenshots and App Review Information wait for the App Store (part 1 §4):

| Where | Field | Value |
|---|---|---|
| App Information | Subtitle | `Remote display for your Mac` |
| App Information | Category | Primary: Utilities. Secondary: Productivity |
| App Information | Content Rights | No: Sill doesn't contain, show or access third-party content |
| App Information | Age Ratings › Set Up Age Ratings | Every item none, No or unchecked, Unrestricted Web Access included; Age Categories and Override: Not Applicable; Age Suitability URL empty. Result: 4+ (metadata §2 has each step) |
| App Information | Apple ID | Nothing to type: read the number for step 2 |
| App Privacy | Privacy Policy URL | `https://getsill.app/privacy` |
| App Privacy | User Privacy Choices URL | Empty |
| App Privacy | Data collection | Get Started › "No, we do not collect data from this app" › Save, then Publish: the page says Data Not Collected |
| Pricing and Availability | Price | Free |
| Pricing and Availability | Availability | All countries and regions |
| Pricing and Availability | iPhone and iPad Apps on Apple Silicon Mac | Uncheck "Make this app available" |
| Pricing and Availability | iPhone and iPad Apps on Apple Vision Pro | Uncheck "Make this app available on Apple Vision Pro" |
| Business › Agreements › Compliance › Digital Services Act | Trader status | "This is not a trader account": free, no in-app purchase, no ads (metadata §2; look again when the tip jar comes; not legal advice) |
| The version page, "1.0 Prepare for Submission" | Version | `0.5`. App Store Connect names a new app's first version 1.0, and only a build whose version matches can be added to it (for the App Store, not for TestFlight) |
| The version page | Support URL, Marketing URL | `https://getsill.app/support`, `https://getsill.app` |
| Nowhere | Export compliance | Nothing to answer: the build says `ITSAppUsesNonExemptEncryption` NO (metadata §6), so no build waits on Missing Compliance |

- [ ] If developer.apple.com or App Store Connect asks the Account Holder to accept an updated
      agreement, accept it first: until then it can refuse new records and uploads.

### 2. The App Store address in the app

- [x] Done 2026-09-26 (PR #27, 6816359860). With the Apple ID from App Information (a number such
      as 6712345678), before the first upload:

```
sed -i '' 's#APP_STORE_URL_PLACEHOLDER#https://apps.apple.com/app/id<Apple ID>#' iOSClient/SillLinks.swift
git commit -m "iOS: the App Store address, for a Mac's update notice" iOSClient/SillLinks.swift
```

A Mac that needs a newer Sill on the device then shows "Update Sill in the App Store" under its
notice. The address answers only once the app is on the App Store. Until the line changes,
`release-ios.sh` warns at every build, and a line that is neither the placeholder nor an App Store
address (the number left out, say) stops it before it builds.

### 3. The site

- [ ] App Store Connect links the privacy policy and the support page, and the App Privacy answers
      and the policy must agree. Since the first Mac release (v0.3.0, 2026-09-26),
      Saffsanity/sill-site holds all of `site/`, download.html included, and is republished with
      part 1 §3's rsync (never with `--exclude download.html` any more, which kept that page at
      "being prepared" until then; still without touching sill-site's own `.nojekyll` and
      `.github`), right after each release whose builds the pages describe (part 2, the last
      item). Since 2026-09-27 GitHub serves the pages itself (Cloudflare's proxy is off, part 1
      §3), so getsill.app's copies are sill-site's byte for byte, `<!--email_off-->` comments
      included.

```
rsync -a --delete --exclude .git --exclude .github --exclude .nojekyll site/ ../sill-site/
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

- [ ] In a private window: https://getsill.app/privacy shows "Update check", and /support shows
      support@getsill.app.

### 4. The build

```
Scripts/release-ios.sh                    # archive, export .build/ios/export/Sill.ipa and check it; nothing uploaded
Scripts/release-ios.sh --upload           # the same, then the upload: 0.5 (1), the first build (done 2026-09-26, b37f47a)
Scripts/release-ios.sh --bump --upload    # every later upload of a version: the build number + 1, committed alone
Scripts/release-ios.sh --privacy-report   # what the archive's privacy manifest declares, and its required-reason APIs
```

- It needs Xcode 27.1 or a later Xcode 27 selected (it refuses any other: since the iPhone Duo's
  layouts, the app needs the iOS 27.1 SDK, and it checks that the .ipa's app was built with it,
  docs/iphone-duo-plan.md) and the Apple Account of team 9B2KKVM937 in Xcode › Settings ›
  Accounts, which signs and uploads. Uploading takes Account Holder, Admin, App
  Manager or Developer; signing with the cloud-managed certificate takes Account Holder or Admin
  (or the permission Access to Cloud Managed Distribution Certificate in Users and Access). Or an
  App Store Connect API key instead, kept outside the repository:
  `--api-key <path>/AuthKey_<Key ID>.p8 --api-issuer <Issuer ID>`. Every export signs through the
  key, which takes the Admin role: any other key, the notary key of part 1 §2 (Developer)
  included, gets "Cloud signing permission error". Nothing is stored: only the key's path goes to
  xcodebuild.
- It prints one line per step, and xcodebuild's output goes to `.build/ios/*.log` (`-v` shows it
  too). Before any upload it checks the exported .ipa: the version and build the project says,
  `ITSAppUsesNonExemptEncryption` NO, the Local Network, Bonjour and camera entries, the privacy
  manifest, an Apple Distribution signature, an App Store profile and no get-task-allow; and it
  warns when the binary uses a required-reason API the manifest doesn't declare, which App Store
  Connect refuses (ITMS-91053). A failure names what usually fixes it: an account to add, the app
  record to create, `--bump`.
- Build numbers: App Store Connect takes each number once per version, and the export keeps the
  project's (`manageAppVersionAndBuildNumber` NO in `Packaging/ExportOptions-appstore.plist`), so
  every build there names one commit. `--bump` and `--upload` refuse a working tree with changes
  (new files count in `iOSClient` and `Sources/StreamProtocol`, which the build takes whole; a
  build that stays here only warns). `--bump` adds 1 to `CURRENT_PROJECT_VERSION` in both
  configurations and commits that alone; push it with the rest.
  A new version: `MARKETING_VERSION` in both configurations (Xcode › target Sill › General ›
  Version), the same number as Sill for Mac's (part 2's first item), committed in the release's
  pull request with the next build number: the numbers keep counting across versions (0.5.1's
  first build is 4, after 0.5's 1 to 3) rather than starting again at 1.
- The rehearsal on 2026-09-26 (main at 6f2a934, whose iOS app is 150f781's): archive and export in
  49 s, Sill.ipa 2.0 MB, signed "Apple Distribution: NOAH WILLIAM SAFFER (9B2KKVM937)" (cloud
  managed), the App Store profile until 2027-09-26, entitlements `application-identifier`
  9B2KKVM937.me.saffer.sill, `beta-reports-active` true, get-task-allow false, no keychain or
  Apple Account prompt. Again on 2026-09-27 (main at 643af6b, PRs #30 to #36 in): 46 s, Sill.ipa
  2.5 MB, the same certificate and profile, the required-reason APIs SystemBootTime
  (`systemUptime`) and UserDefaults, both declared, and only the known `StreamClient` capture
  warning in the archive's log.
- The privacy report: xcodebuild has no command for it, so `--privacy-report` prints what the report
  is made of (the manifests, and the required-reason APIs the binary uses). The PDF: `open
  .build/ios/Sill.xcarchive` (Xcode shows it in Window › Organizer › Archives), Control-click it ›
  Generate Privacy Report. Keep it with the App Privacy answers.
- After an upload, App Store Connect processes the build, usually within half an hour, and emails
  when it's done; it then shows under TestFlight as 0.5 (1), or whichever build it is. Give it its
  What to Test there (the build › Test Details): what changed since the build before.

### 5. Internal testers

- [ ] TestFlight › Internal Testing › + : a group such as `Internal`, with automatic distribution
      on, and the testers: members of the team in App Store Connect (up to 100), Noah included.
      No review: every processed build reaches them. An external group can exist only once an
      internal one does.
- [ ] On the iPad and an iPhone: TestFlight from the App Store, signed in with the tester's Apple
      Account, then Sill from the invitation. A build stays installable for 90 days.

### 6. Test Information, for external testers

- [ ] TestFlight › Additional › Test Information, English (U.S.):

| Field | Value |
|---|---|
| Beta App Description | The block below (665 characters) |
| Feedback Email | `support@getsill.app` |
| Marketing URL | `https://getsill.app` |
| Privacy Policy URL | `https://getsill.app/privacy` |
| Beta App Review Information: First Name, Last Name, Phone Number, Email | Noah, Saffer, a number starting with + and the country code, `support@getsill.app` (or your own; App Review only) |
| Sign-in required | Unchecked: there is no account |
| Review Notes | Metadata §7's notes (under the 4,000 bytes allowed; §10 there has the count), Remote Access part included while the build has it |
| License Agreement | Apple's standard: leave it |

```text
Sill puts your Mac on your iPhone and iPad. Pick any window, or the whole desktop, and use it with touch, a trackpad, a keyboard or Apple Pencil.

It needs the free Sill for Mac 0.4.0 or later, from https://getsill.app/download, on a Mac with Apple silicon and macOS 14 or later. Open Sill for Mac and allow Screen Recording and Accessibility, then open Sill on your iPhone or iPad on the same Wi-Fi and tap your Mac. The first time, pair: scan the code your Mac shows, or type it. Over a USB cable, it pairs by itself.

To send feedback, take a screenshot while you use Sill, or use Send Beta Feedback in TestFlight. Write to support@getsill.app for anything else.
```

### 7. External testers and Beta App Review

- [ ] TestFlight › External Testing › + : a group such as `Beta`. Add Builds › the newest build of
      the version, and its What to Test (metadata §5). Submit Review.
- Beta App Review looks at the first build of a version in full (later builds of the same version
  may not need it), up to six builds a day. It needs what App Review needs: Sill for Mac
  downloadable at https://getsill.app/download (it is, since v0.3.0 on 2026-09-26; the build
  under review must work with the Sill for Mac that page offers), the notes, and the contact.
  Test internally first: that needs none of it.
- Once approved: invite testers by email, or turn on a public link (Open to Anyone, with a tester
  limit if you like, up to 10,000).
  The public beta group's link, on since 2026-10-29: https://testflight.apple.com/join/6v7nqyn3 (the README, the download
  page and the nightly pre-release's notes carry it; a new link means changing all three).

### 8. Screenshots, for the App Store

TestFlight needs none; the App Store version does. Metadata §9 is the plan: the sizes, the five
screens of each set, the capture commands and what may appear in the picture. The session:

- [ ] When: once the build you will submit is on TestFlight, from the same commit (§9 builds it
      for the simulator, Release).
- [ ] Stage the Mac first (§9's list: rename it, Do Not Disturb on both, only Notes, Weather,
      Clock, Calculator or TextEdit with sample text), and disconnect every other device.
- [ ] iPhone 6.9" (the iPhone 18 Pro Max simulator, 1320 × 2868), then iPad 13" (iPad Pro 13-inch
      (M5), 2064 × 2752): five each, the app in use first, JPEG without alpha.
- [ ] On a fresh install the first-run tour dims the screen about a second after the Mac's
      picture, unless something is touched: take it once (or click the picture at once) before
      the first screenshot.
- [ ] Never `simctl io … recordVideo` while Sill.app streams: the recorder takes the video encoder
      from Sill (screenshots are fine).
- [ ] Upload them on the version page (iPhone 6.9" Display, iPad 13" Display) with the rest of
      metadata §5, §7 and §8 when you submit.

### TestFlight from GitHub Actions

`.github/workflows/testflight.yml` runs only by hand, and only from main: Actions › TestFlight ›
Run workflow (GitHub lists it once it is on main). It never runs on a push or a pull request. Its
job runs in the environment `nightly` (Releasing from GitHub Actions › Secrets and variables,
below), which only main may use, so GitHub refuses a run from any other branch or a tag before it
starts, and the key below is that environment's. To send a branch to TestFlight, upload it from
this Mac with `release-ios.sh --bump --upload`.
It selects the newest Xcode 27 that is not a beta, and `release-ios.sh` refuses one before 27.1.
The `xcode-27` image had only `Xcode_27.1_beta.app` (27A9269) until October 2026; on 2026-10-29 it
had `Xcode_27.1.app` (27A9275), which the runs 40825231452 and 40843967209 took. The nightlies
(below) upload through the same key every night.

- Without the key below (none in the environment `nightly`: a notice says so):
  `release-ios.sh --unsigned`. The Release archive is built without signing and checked;
  `Sill-<version>-<build>-unsigned.ipa` is the artifact for 14 days, to look inside only. No
  secret is read.
- With the key: `release-ios.sh --sign-at-export`. The runner has no development certificate, so
  the archive is built without signing, and the export signs it through the key with the same
  cloud-managed certificate as here and the App Store profile, which Xcode makes or fetches. No
  certificate, private key or profile is kept in the secrets: an archive made without
  signing exports with the same entitlements (tried here on 2026-09-26 with the Apple Account;
  through the key on 2026-10-29: run 40825231452, and 40843967209 with the build number given).
  `Sill-<version>-<build>.ipa` is the artifact for 14 days. Nothing is uploaded, unless:
- the repository variable `SILL_TESTFLIGHT_IN_CI` is `true` and the commit is on main's own line,
  as a run from main always is: the run also uploads, as `--upload` does here. The mode step still
  checks main's line before an upload, and exports with a notice otherwise (below), should the
  environment ever let another ref in.

The build number is the commit count (`git rev-list --count HEAD`), given with `--build-number`
for the run only, as the nightlies' is: nothing to bump or commit first. Along main's first-parent
line every commit's count is its own, but another branch's commit can have the count of a later
commit of main (a branch four commits ahead of main has the count main gets by merging a pull
request of three commits: the three and the merge), and the nightly of that commit would then find
"its" build in App Store Connect and give the branch's to TestFlight's groups (reproduced with the
workflows' own run blocks in the review of 2026-10-29). So uploads go only from main's line; to send a branch to TestFlight,
upload it from this Mac with `release-ios.sh --bump --upload` (a committed number, far below the
counts). Run 40843967209 (branch `nightly-builds` at e59499f9, whose project says 4, before the
environment kept the workflow to main) exported 0.5.1 (987), App Store-signed.

| Name | Kind | What it holds |
|---|---|---|
| `SILL_TESTFLIGHT_KEY_ID` | secret of the environment `nightly` | The Key ID of an App Store Connect API key with the Admin role (Users and Access › Integrations › App Store Connect API › Team Keys › +). Cloud signing refuses any other role. |
| `SILL_TESTFLIGHT_ISSUER_ID` | secret of the environment `nightly` | The Issuer ID above the keys (the same for every key of the team). |
| `SILL_TESTFLIGHT_KEY_P8` | secret of the environment `nightly` | The key file `AuthKey_<Key ID>.p8`, in base64. Apple lets you download it once. |
| `SILL_TESTFLIGHT_IN_CI` | variable (the repository's) | `true` also uploads, here (a commit on main's own line only) and in the nightlies. Absent or anything else: export only. |

The environment `nightly` first (Releasing from GitHub Actions › Secrets and variables, step 1); the
three secrets are part of its step 2, and the repository keeps no copy (its step 3). The variable
goes on after an export-only run has passed:

```
gh secret set SILL_TESTFLIGHT_KEY_ID --env nightly
gh secret set SILL_TESTFLIGHT_ISSUER_ID --env nightly
base64 -i <backup folder>/AuthKey_YYYYYYYYYY.p8 | gh secret set SILL_TESTFLIGHT_KEY_P8 --env nightly
gh variable set SILL_TESTFLIGHT_IN_CI --body true
```

An Admin key can do nearly all an Admin can in App Store Connect, managing users included, so it
is a bigger secret than the notary key: keep the .p8 where part 1 keeps its backups, give it to this
repository only, and revoke it (Users and Access › Integrations) when TestFlight from CI isn't in
use; a revoked key stops at once. Uploading from this Mac with `release-ios.sh --upload` needs no
key at all. A run takes about 5 minutes of macOS time (What it costs, below).

## Nightlies

`.github/workflows/nightly.yml` (2026-10-29; issue #134) builds main every night it moved, at 09:17
UTC, and when run by hand: Actions › Nightly › Run workflow, or `gh workflow run nightly.yml`. GitHub
lists a workflow, and runs it by hand or on a schedule, only once its file is on main.

What a nightly is:

- Sill for Mac: main's head built as a release is, by `Scripts/release.sh --nightly`:
  `make-app.sh --release` (Developer ID, the hardened runtime, the Developer ID provisioning profile
  embedded), but universal (`SILL_UNIVERSAL=1`: Apple silicon and Intel, #62 and #88), as the first
  nightly was (by hand, 2026-10-29) and as Noah told #62 the next version's download will be, where
  a release so far is Apple silicon only; notarized and stapled, checked as Gatekeeper will check it, in a zip and a disk image
  named `Sill-nightly-<yyyymmdd>-<sha7>.dmg` and `.zip`, each with its `.sha256`, on the pre-release
  [`nightly`](https://github.com/Saffsanity/sill/releases/tag/nightly). One pre-release for all
  the nights: its tag `nightly` moves to each night's commit, its notes say what a nightly is, list the
  newest files with their SHA-256, give Sill for iPhone and iPad's public beta link (release.sh's
  `nightly_testflight_link`: every night's notes replace the last, so a new link is changed there
  too, as in the README and the download page), list the pull requests merged since the last release
  tag and the earlier nightlies, and end with the commit's sha in a comment. It keeps the seven
  newest nightlies' files (`SILL_NIGHTLY_KEEP`) and deletes older ones. Never "latest", never a plain
  release, no tag per night. A release with the tag `nightly` that isn't a pre-release is never
  touched. The first nightly was published by hand on 2026-10-29 (0.5.5 (987), universal, the tag at
  150479b5, notes without the sha comment): the workflow's first night takes that pre-release over,
  keeps its four files among the seven, moves the tag and replaces its notes (checked with the stand-in
  gh in the review of 2026-10-29).
- Sill for iPhone and iPad: the same commit; `Scripts/asc.swift groups` lists the app's TestFlight
  groups through the App Store Connect key (reads only, in a verify-only run too), then
  `release-ios.sh --sign-at-export --upload --build-number <commit count>` through the key (cloud
  signing, as TestFlight from GitHub Actions above), then `Scripts/asc.swift distribute`: it waits for App Store Connect to process
  the build (a look a minute, 90 minutes at most), gives it What to Test, and gives it to TestFlight's
  groups (below). A night run again by hand finds its build in App Store Connect and only gives it its
  groups again.
- Versions: what main says (0.5.5 since 2026-10-29, the pre-release number, part 2's first item; the store release will be 0.6.0), with the commit count as
  the build number on both apps, as in "Sill 0.5.5 (990)". Never committed: make-app.sh has always
  stamped the count into the Mac's bundle, and `--build-number` gives it to xcodebuild for the run.
  Only commits on main's first-parent line are uploaded with their count (the nightlies, and
  testflight.yml, which runs from main alone and checks its line before an upload), so a build
  number of the version in App Store Connect names one commit of main, and a night run again finds
  its own build there. From this Mac, give `--build-number` the count only for a commit of main's
  line too.
- The words: `Scripts/nightly-notes.sh` writes them once a night for both apps, from the pull
  requests on main's first-parent line since the newest tag `v<version>` (merges and squashes), their
  titles from GitHub: Markdown for the pre-release (no @mention, so nobody is notified every night),
  plain text within App Store Connect's 4,000 characters for What to Test ("… and N more" with the
  pre-release's address when the list is longer).
- Built only when main moved: on a schedule, a night whose main is the commit in the pre-release's
  sha comment builds nothing. By hand it always builds.

The two kinds of TestFlight group:

- Every internal group (App Store Connect users, no review) gets every nightly. A group with
  automatic distribution gets it by itself, and asc.swift leaves it alone.
- The public beta group, the external group with the public link on, gets nightlies only while the
  repository variable `SILL_NIGHTLY_PUBLIC_BETA` is `true`. It is unset at first: Noah tries a nightly
  in his Insiders group first (2026-10-29: "hold off on giving the testflight build to public beta
  until I try it out in Insiders first tomorrow"). Without it no external group is ever touched and
  nothing goes to Beta App Review; the job's log says which groups got the build and that the public
  beta didn't. asc.swift takes `--public-beta` only with the variable's value in its environment too.
  With it, the build goes to that group and to Beta App Review when TestFlight waits for a submission:
  the first build of a version is reviewed in full (it needs §6's Test Information), a later build of
  the version is submitted the same way and usually approved within minutes. While another build of
  the version is still in review, the submission waits for the next nightly (a warning in the job).

For a nightly tester:

- Pairing: a nightly is signed by the same Developer ID team, with the same bundle ID and the same
  provisioning profile as the release, so it reads the same data-protection keychain items (part 1
  §5): the same Mac ID, key and paired devices. A device paired with the release stays paired with a
  nightly, and back. The settings (`me.saffer.sill.mac`) and the Screen Recording and Accessibility
  permissions (granted to the bundle ID and the designated requirement, which names the team) carry
  over too. That is why a nightly refuses to build without the profile.
- The update check never offers a nightly: it reads only
  `https://api.github.com/repos/Saffsanity/sill/releases/latest`, which never lists a pre-release
  (`UpdatePolicy.feed`), refuses an answer that says `prerelease` anyway (`UpdatePolicy.release`), and
  "nightly" is no version. A nightly Sill.app says 0.5.5 with its build number, so the update check offers it the 0.6.0 release once that is published, like everyone else's.
- Going back: on the Mac, quit Sill, download the release from https://getsill.app/download and
  replace Sill in Applications; nothing to set up again. On a device, TestFlight › Sill › Previous
  Builds installs an earlier build, and the App Store installs the release over a TestFlight build
  (Apple doesn't promise an app's data across that switch: if Sill forgets the Mac, pair it again).
  A TestFlight build stops opening after 90 days.

The variables, repository variables (Settings › Secrets and variables › Actions › Variables; `gh
variable set NAME --body true`, `gh variable delete NAME`), none set at first:

| Name | `true` | Unset |
|---|---|---|
| `SILL_NIGHTLY` | the schedule builds | the schedule does nothing (by hand still builds) |
| `SILL_SIGN_IN_CI` | Sill for Mac signed, notarized and published on the pre-release; also release.yml's publish job on a pushed tag (with the profile since the same pull request) | ad hoc artifacts only |
| `SILL_TESTFLIGHT_IN_CI` | the iOS build uploaded and given to the internal groups; also testflight.yml's upload | signed through the key and exported, nothing uploaded |
| `SILL_NIGHTLY_PUBLIC_BETA` | the public beta group too, through Beta App Review | internal groups only |

A run by hand with "Verify only" ticked builds as if none were set; a run from any other branch
builds nothing (decide says so: both builds run in the environment `nightly`, which only main may
use). The secrets are the environment `nightly`'s nine (Releasing from GitHub Actions › Secrets and
variables: only main may use it, with no reviewer, so a night runs unattended; none is a repository
secret), among them `SILL_PROVISION_PROFILE`, the Developer ID profile of part 1 §5 in base64
(`base64 -i Packaging/embedded.provisionprofile | gh secret set SILL_PROVISION_PROFILE --env
nightly`): no secret inside, but a secret keeps it out of the tree; the workflow decodes it to
`Packaging/embedded.provisionprofile` under another name than make-app.sh's `SILL_PROVISION_PROFILE`
(a path there), and deletes it at the end. An environment without its secrets gives empty strings:
with `SILL_SIGN_IN_CI` on, the Mac job stops before it builds and names the missing ones; with
`SILL_TESTFLIGHT_IN_CI` on, so does the iOS job; otherwise the Mac job builds ad hoc and the iOS
job unsigned, with a notice that the environment has no App Store Connect key.

Stopping them: `gh variable delete SILL_NIGHTLY` stops the schedule, `gh workflow disable
nightly.yml` stops the workflow; delete `SILL_TESTFLIGHT_IN_CI` to stop the uploads,
`SILL_NIGHTLY_PUBLIC_BETA` to keep them to the internal groups, `SILL_SIGN_IN_CI` to stop the Mac's
(and the release workflow's signing). A build already on TestFlight stays installable until it is
expired (TestFlight › the build › Expire Build). The pre-release can be deleted on GitHub: the next
nightly makes it again.

A release after nightlies: the version is already on main (part 2's first item), so tag the commit.
Sill for Mac: with `SILL_SIGN_IN_CI` on, as the nightlies need it, pushing the tag starts release.yml's
publish job, which waits for Noah's approval in the environment `release` (GitHub notifies him; the
run's page › Review deployments › release › Approve and deploy, once the run is his tag on the
commit he tagged: What a tag does) and then builds, notarizes and publishes the
release itself, the profile embedded; don't also
run `release.sh --publish` from this Mac (it would find the release there and stop). The pre-release
stays beside the release, never "latest". Sill for iPhone and iPad: App Store Connect already has
builds of the version numbered by commit count (987 and up), and the committed
CURRENT_PROJECT_VERSION (4) is far below them, so either submit the nightly build of the tagged
commit itself (that commit, App Store-signed, processed and tested), or upload from the tag with
`--build-number "$(git rev-list --count HEAD)"`, above every nightly before it. Then, before the
next night, move main to the next version (part 2's first item, a pull request like PR #244): once
the version is released, App Store Connect takes no new build of it (its train is closed), so until
main says the next number every nightly's upload is refused and the iOS job fails, while Sill for
Mac's nightlies keep the released number.

The first run, for Noah:

1. Done 2026-10-29 (PR #243, on main at 150479b5): the app's binary uses
   `UITextInputMode.activeInputModes` (#147's Control-Space rule), which App Store Connect refuses
   undeclared (ITMS-91053; `release-ios.sh` warned in runs 40825231452 and 40843967209), and
   `iOSClient/PrivacyInfo.xcprivacy` now declares `NSPrivacyAccessedAPICategoryActiveKeyboards`
   with 54BD.1. `release-ios.sh`'s check of run 40843967209's binary against main's manifest
   declares every required-reason API it uses (ActiveKeyboards, SystemBootTime, UserDefaults).
2. Merge "Version 0.5.5 for both apps": App Store Connect takes no new build of 0.5.1, which it has
   released.
3. Merge "Nightly builds".
4. The environments, before anything runs with them and before any variable: Releasing from GitHub
   Actions › Secrets and variables, steps 1 to 3. The environments `release` (`v*` tags, Noah's
   approval) and `nightly` (main), with their rules, checked; the secrets set in each from the same
   sources as the repository's (six in `release`, nine in `nightly`); then the nine repository
   secrets deleted (`gh secret list` prints nothing). Until then the repository's secrets reach a run
   on any branch or tag.
5. `gh workflow run nightly.yml -f verify_only=true` (or Run workflow with "Verify only" ticked).
   Check decide's summary (the notes and What to Test), the Mac job's artifacts
   `Sill-nightly-<date>-<sha7>-adhoc.zip` and `.dmg`, the iOS job's `Sill-0.5.5-<count>.ipa`
   ("Signed for App Store Connect and checked … Nothing was uploaded") and its summary's "TestFlight's
   groups": `Scripts/asc.swift groups` reads them through the key (nothing else), so this run already
   shows the key works with App Store Connect's API and which groups the nightlies will go to, and
   that the key now comes from the environment `nightly` (the repository has none: with no key the job
   would say "The environment nightly has no App Store Connect API key" and build unsigned).
6. `gh variable set SILL_SIGN_IN_CI --body true` and `gh variable set SILL_TESTFLIGHT_IN_CI --body
   true`. Not `SILL_NIGHTLY_PUBLIC_BETA`.
7. `gh workflow run nightly.yml`. Check the pre-release (the night's four files beside the first
   nightly's, the notes with the public beta link, "Pre-release"), the
   Mac job's log ("Identity keychain: data-protection", twice "Notarized Developer ID"), the disk image
   on a second Mac (downloaded, so quarantined: it opens, the drag, Sill opens, the iPad still
   paired), the iOS job's last step ("Assigned build … to: Insiders", "Public beta: not given") and
   TestFlight on the iPad (the build with its What to Test).
8. `gh variable set SILL_NIGHTLY --body true`: every night from the next 09:17 UTC on.
9. Once a nightly has worked in Insiders: `gh variable set SILL_NIGHTLY_PUBLIC_BETA --body true`
   (§6's Test Information filled in first). The next nightly goes to the public beta group and to Beta
   App Review; the first build of a version is reviewed in full.

What it costs: nothing, in a public repository. A night is three jobs on `xcode-27`: about 2 minutes
to decide, 25 to 45 for Sill for Mac (the checks, the build, two notarizations), and 10 for Sill for
iPhone and iPad plus App Store Connect's processing, which the job waits out (usually 10 to 40
minutes). Apple charges nothing for notarization or TestFlight.

## Releasing from GitHub Actions

Two workflows run on GitHub's own Macs. `.github/workflows/ci.yml` checks every pull request and
every push to `main` (not a change to documents, the site or the design files alone): it builds
the Mac side with `swift build -c release`, runs the pure checks (`Tests/checks/run-all.sh`),
builds the iOS app for the simulator without signing, and runs the CLI where it needs no capture or
encoder. `.github/workflows/release.yml` runs when a tag `v<version>` is pushed, or by hand (Actions
› Release › Run workflow) with such a tag. Both use no secret until you turn signing on, and then
only release.yml's publish job, in the environment `release` (Secrets and variables). A third,
`.github/workflows/testflight.yml`, runs only by hand: TestFlight from GitHub Actions, above. A
fourth, `.github/workflows/nightly.yml`, builds both apps from main every night it moved: Nightlies,
above.

### Why the download link did not work before 2026-09-26

- There was no release until v0.3.0, published on 2026-09-26. The site's button links
  `releases/latest/download/Sill.zip`, which GitHub redirects to the newest release's file of that
  name.
- Until 2026-09-26 the repository was private, and GitHub serves a private repository's release
  files only to people signed in with access to it, so everyone else got a 404 even once v0.3.0
  existed. Saffsanity/sill is public now (the decision at launch: the history stays as it is), so
  the link works; the alternative, publishing in the public Saffsanity/sill-site with
  `SILL_RELEASE_REPO` and `SILL_RELEASE_TOKEN`, was not needed.

### What a tag does

- [ ] The version: `CFBundleShortVersionString` in `Packaging/Info.plist`, committed and on `main`.
- [ ] `git tag v0.3.0 <that commit> && git push origin v0.3.0`, with the same version. The tag must
      be on a commit that has `release.yml`, so nothing before this change. `Scripts/release.sh
      --check-tag` stops the run when the tag and the version differ, or the tag names another
      commit.
- Without the variable `SILL_SIGN_IN_CI`: verify only. The run checks the tag, runs the pure
  checks, builds Sill.app with `Scripts/make-app.sh` (signed ad hoc, as the runner has no identity),
  fails if the icon is missing, makes the disk image from it with `Scripts/make-dmg.sh` (ad hoc
  too), and keeps `Sill-<version>-adhoc.zip` and `Sill-<version>-adhoc.dmg` as the run's two
  artifacts for 14 days. They are for trying out only (the image, to look at its window): not
  Developer ID, not notarized. Nothing is published.
- With `SILL_SIGN_IN_CI` set to `true`: sign and publish, in the environment `release` (Secrets and
  variables, below). The job waits for Noah's approval before it starts: GitHub notifies him, and
  the run's page › Review deployments › release › Approve and deploy lets it go (Reject fails the
  run). Approve only the tag you pushed, on the commit you tagged: the run's page names who pushed
  it, the tag and its commit (`git rev-list -n 1 v<version>` here gives the one you tagged). The
  job builds that commit, the run's own (`github.sha`), not whatever the tag names when it starts,
  and stops before anything is built or signed if the tag has moved or gone since the run began:
  a tag moved after your look would otherwise build and sign another commit, and your `git
  rev-list` would not see it (`git fetch --tags` never moves a tag you already have). A move is a
  push too, and usually starts a run of its own under the name of whoever moved the tag: reject
  that one unless it was you. Any
  `v*` tag pushed by anyone with write access waits there the same way, the workflow's own checks
  are that tag's, and the approval is all that stands between it and a release that every
  Sill.app's update check offers (What the environments don't do, below). By hand, start it from
  the tag itself (Run workflow › Use workflow from › Tags › the tag, with the same tag as the
  input): the environment refuses a run from a branch, and the job's
  first step a run from another tag. That first step also stops the run, naming them, when the
  environment lacks any of its six secrets. Then the same checks, then the Developer ID
  certificate goes into a temporary keychain with a random password, the notary key into a profile
  in it (`notarytool store-credentials`, which validates the key with Apple first), the Developer ID
  provisioning profile (`SILL_PROVISION_PROFILE`) into `Packaging/embedded.provisionprofile`, so the
  release keeps its identity in the data-protection keychain as a release from this Mac does, and
  `Scripts/release.sh --publish` runs with `SILL_RELEASE_TAG` set: it builds, notarizes, staples,
  checks a copy unpacked from the zip the way Gatekeeper will, makes, notarizes, staples and checks
  the disk image, and creates the GitHub Release with `Sill.dmg`, `Sill.zip` and their `.sha256`
  files. Apple's answers and logs for both submissions (the zip's and the image's) are the run's
  artifact `notary-v<version>` for 30 days: when the job's log says a notary log lists issues, read
  them there, since the run has published the release by then. (The step needs
  `include-hidden-files: true`: without it upload-artifact skips everything under `.build` and
  keeps nothing, as it did before the disk image.) The last step deletes the keychain and the key
  files whatever happened. The runner image already carries Apple's Developer ID intermediate
  certificate.
- Then the rest of part 2 as usual: try the disk image on another Mac, and for the first release
  that carries it, move the download page to it.
- A failed run can be re-run from its page. A version that is already released is refused
  before anything is built or sent to Apple (`release.sh --publish` asks GitHub first, as it asks
  whether its token reaches the repository): bump the version. Deleting that release and its tag
  frees the version only for a release that isn't immutable: GitHub never lets an immutable
  release's tag be used again, even after the release is deleted.

### Secrets and variables

Settings › Environments and Settings › Secrets and variables › Actions, or `gh` from the
repository's folder. Nothing here ever goes in the repository, a commit message or a shell profile.

The secrets live in two environments, and none is a repository secret. A repository secret reaches
every workflow run on any branch or tag pushed here (never a fork's pull request), and a workflow
runs by hand from any ref with that ref's own scripts, so anyone who could push a branch could run
a copy of a script with the Developer ID key or the Admin App Store Connect key on disk (the
security scan of 2026-10-18, findings 5 and 6). An environment's secrets reach only the jobs that
name it, from the refs it allows. Environments with rules need a public repository on GitHub Free,
which Saffsanity/sill is since 2026-09-26.

- `release`: release.yml's publish job. Only a tag `v*` may use it, and Noah is its required
  reviewer: a release waits for his click (What a tag does, above). Six secrets: the five
  `SILL_DEVELOPER_ID_*` and `SILL_NOTARY_*` ones, and `SILL_PROVISION_PROFILE`; and
  `SILL_RELEASE_TOKEN` should it ever be used.
- `nightly`: nightly.yml's Sill for Mac and Sill for iPhone and iPad jobs, and testflight.yml's job.
  Only the branch `main` may use it, with no reviewer, so a night runs unattended. Nine secrets: the
  same six and the App Store Connect key's three (TestFlight from GitHub Actions, above).

GitHub refuses a job whose ref its environment doesn't allow, before the job starts: a release by
hand runs from its tag, testflight.yml only from main, and nightly.yml's decide job builds nothing
on any other ref (so the run ends quietly, not refused). An environment without its secrets gives
the workflow empty strings, not an error, so each job checks first and names the environment and
the missing secrets when the run needs them. A run that names an environment that does not exist
makes it, with no rule and no secret: so the environments come first, with their rules, before any
run uses them. A workflow file from before this change (an older tag or branch) names no
environment and reads repository secrets: so the repository keeps none.

Before `SILL_SIGN_IN_CI` goes on, and before the nightlies' first run (Nightlies › The first run,
step 4), in this order:

1. The two environments, with their rules, then a look at them. With `gh` (written from GitHub's
   REST reference, "Create or update an environment" and "Create a deployment branch policy", on
   2026-10-29; not run here, as no repository was at hand to try them on), from the repository's
   folder; 19507835 is Saffsanity's user ID (`gh api users/Saffsanity --jq .id`), and
   `prevent_self_review` stays false because Noah is the one who pushes the tag and the one who
   approves:

   ```
   gh api -X PUT repos/Saffsanity/sill/environments/release --input - <<'EOF'
   {"prevent_self_review": false, "reviewers": [{"type": "User", "id": 19507835}],
    "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
   EOF
   gh api -X POST repos/Saffsanity/sill/environments/release/deployment-branch-policies -f name='v*' -f type=tag
   gh api -X PUT repos/Saffsanity/sill/environments/nightly --input - <<'EOF'
   {"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
   EOF
   gh api -X POST repos/Saffsanity/sill/environments/nightly/deployment-branch-policies -f name=main -f type=branch
   ```

   Or by hand: Settings › Environments › New environment `release`, Required reviewers: Noah,
   Deployment branches and tags: Selected branches and tags › Add deployment branch or tag rule ›
   Ref type Tag, `v*`; then `nightly`, no reviewer, Selected branches and tags › Ref type Branch,
   `main`. Either way, look:

   ```
   gh api repos/Saffsanity/sill/environments --jq '.environments[] | {name, reviewers: [.protection_rules[] | select(.type == "required_reviewers") | .reviewers[].reviewer.login], refs: .deployment_branch_policy}'
   gh api repos/Saffsanity/sill/environments/release/deployment-branch-policies --jq '.branch_policies[] | "\(.type) \(.name)"'
   gh api repos/Saffsanity/sill/environments/nightly/deployment-branch-policies --jq '.branch_policies[] | "\(.type) \(.name)"'
   ```

   `release` with the reviewer `Saffsanity`, `nightly` with none, both with
   `"custom_branch_policies": true`; then `tag v*` alone, and `branch main` alone. A `refs` of `null`
   lets any branch or tag in: fix that before going on.
   A POST answered 404 found its environment without `custom_branch_policies` (the PUT before it
   didn't take); one answered 303 found the rule there already. The look's commands, which only
   read, ran on 2026-10-29 against other public repositories' environments (a tag rule with a
   required reviewer, a `main` branch rule), so their filters fit what GitHub answers; the PUTs
   and POSTs above have run nowhere.
2. The secrets in each environment, from the same sources as the repository's were (GitHub never
   shows a secret again). `gh secret set` without a value asks for it, so the password lands in no
   shell history; the two lists at the end print the names, six for `release` and nine for
   `nightly`. These blocks hold no `#` comments: zsh, as it starts (no `interactivecomments`),
   would hand a comment's words to `gh` as arguments.

   ```
   for env in release nightly; do
     base64 -i <backup folder>/DeveloperID.p12 | gh secret set SILL_DEVELOPER_ID_P12 --env "$env"
     gh secret set SILL_DEVELOPER_ID_P12_PASSWORD --env "$env"
     gh secret set SILL_NOTARY_KEY_ID --env "$env"
     gh secret set SILL_NOTARY_ISSUER_ID --env "$env"
     base64 -i <backup folder>/AuthKey_ABC123DEFG.p8 | gh secret set SILL_NOTARY_KEY_P8 --env "$env"
     base64 -i Packaging/embedded.provisionprofile | gh secret set SILL_PROVISION_PROFILE --env "$env"
   done
   gh secret set SILL_TESTFLIGHT_KEY_ID --env nightly
   gh secret set SILL_TESTFLIGHT_ISSUER_ID --env nightly
   base64 -i <backup folder>/AuthKey_YYYYYYYYYY.p8 | gh secret set SILL_TESTFLIGHT_KEY_P8 --env nightly
   gh secret list --env release
   gh secret list --env nightly
   ```
3. The repository's copies deleted. An environment's secret wins over a repository secret of the
   same name inside its jobs, but the repository's would still reach every other run. The list at
   the end prints nothing:

   ```
   for name in SILL_DEVELOPER_ID_P12 SILL_DEVELOPER_ID_P12_PASSWORD SILL_NOTARY_KEY_ID SILL_NOTARY_ISSUER_ID \
       SILL_NOTARY_KEY_P8 SILL_PROVISION_PROFILE SILL_TESTFLIGHT_KEY_ID SILL_TESTFLIGHT_ISSUER_ID SILL_TESTFLIGHT_KEY_P8; do
     gh secret delete "$name"
   done
   gh secret list
   ```
4. Then the variables, repository variables as before: `SILL_SIGN_IN_CI` (below) after a
   verify-only run has passed, and the nightlies' (Nightlies › The first run).

What the environments don't do: they don't protect main or the tags. A `v*` tag or a commit on main
can still be pushed by anyone with write access to the repository: Noah alone today, and so any
token of his (the `gh` signed in on this Mac has the `repo` and `workflow` scopes). A release waits
for Noah's approval whoever pushed its tag. A nightly doesn't wait, and `nightly` holds the same
Developer ID and notary keys as `release`, and the Admin App Store Connect key: a commit on main
reaches all of them at the next run from main (the schedule, or nightly.yml or testflight.yml by
hand), with no approval (the review of 2026-10-29 ran that route through the workflows' own steps),
and with them the nightly Mac job's token, which can publish any release (`contents: write`), one
the update check offers included. So the approval keeps a tag from publishing a release unseen, not
a commit on main. A ruleset on main that requires a pull request stops a direct push but not a
merged pull request, unless an approval is required too, and GitHub never lets a pull request's
author approve it: with Noah alone it holds only against someone else's write access. A ruleset
keeping `v*` tags to Noah keeps other people's tags from reaching his approval at all, and one
that restricts updates and deletions of `v*` tags keeps any tag where it was pushed: a tag moved
after its run began stops that run, but one moved while the job builds still gets the release,
its files the approved commit's build and its tag and source archives the other commit's. An
administrator can still bypass an environment's rules (GitHub's default), which is Noah.

| Name | Kind | What it holds |
|---|---|---|
| `SILL_SIGN_IN_CI` | variable (the repository's) | `true` turns on signing and publishing. Absent or anything else: verify only. |
| `SILL_DEVELOPER_ID_P12` | secret of `release` and `nightly` | The Developer ID Application certificate with its private key, exported as a .p12 (part 1 §1), in base64. |
| `SILL_DEVELOPER_ID_P12_PASSWORD` | secret of `release` and `nightly` | The password given when exporting that .p12. |
| `SILL_NOTARY_KEY_ID` | secret of `release` and `nightly` | The App Store Connect API key's Key ID (part 1 §2, the API key). |
| `SILL_NOTARY_ISSUER_ID` | secret of `release` and `nightly` | The Issuer ID shown above the keys in App Store Connect. |
| `SILL_NOTARY_KEY_P8` | secret of `release` and `nightly` | The key file `AuthKey_<Key ID>.p8`, in base64. |
| `SILL_PROVISION_PROFILE` | secret of `release` and `nightly` | The Developer ID provisioning profile (part 1 §5), in base64: the release and the nightlies embed it. |
| `SILL_RELEASE_REPO` | variable, optional | `owner/name` of another repository to publish in, such as `Saffsanity/sill-site`. Default: this one, with the run's own token. |
| `SILL_RELEASE_TOKEN` | secret of `release`, optional | Only with `SILL_RELEASE_REPO`: a fine-grained personal access token for that one repository, with Contents read and write. |

The workflow takes only an App Store Connect API key, not the app-specific password that part 1 §2
also allows. The keychain, its password, the profile name `sill-notary` and the token for this
repository's own release are made by each run and gone at its end. `SILL_SIGN_IN_CI` goes on last,
after steps 1 to 3 and a verify-only run that passed:

```
gh variable set SILL_SIGN_IN_CI --body true
```

`<backup folder>` is where part 1 keeps the exported .p12 and .p8: outside the repository (these
commands run in it, so a bare file name would be read from there) and not in Downloads.
`.gitignore` leaves out `*.p12`, `*.p8` and `AuthKey_*` in case one lands in the repository
anyway.

### Rotating them

Each secret lives in every environment that holds it (the table above), so set it again in each:
`--env release` and `--env nightly` for the six, `--env nightly` for the App Store Connect key's
three, never without `--env` (a repository secret would reach every run again).

- The Developer ID certificate, before it expires or if its key may have leaked: make a new one
  (part 1 §1), export it with a new password, and set both `SILL_DEVELOPER_ID_P12` and
  `SILL_DEVELOPER_ID_P12_PASSWORD` again, in both environments. Sill's designated requirement names
  the team, not the certificate, so users keep their permissions. Revoke the old certificate at
  developer.apple.com only if the key leaked: revoking it can also stop copies already signed with it
  from opening.
- The notary key: in App Store Connect › Users and Access › Integrations › App Store Connect API,
  make a new key, set the three `SILL_NOTARY_*` secrets in both environments, run a release (or
  `store-credentials` locally) to see it validate, then revoke the old key there; a revoked key stops
  working at once.
- `SILL_RELEASE_TOKEN`: fine-grained tokens expire. Make a new one before that (github.com ›
  Settings › Developer settings › Personal access tokens), set it in `release`, and delete the old
  one.
- After a suspected leak of any of them: revoke first, then replace, then look at the repository's
  Actions runs and releases for anything you didn't start.
- Turning signing off again: delete the variable `SILL_SIGN_IN_CI` (or set it to `false`). The
  secrets can stay.

### What it costs

GitHub's prices on 2026-09-25 ([runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing),
[Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)):

- A public repository, as Saffsanity/sill is since 2026-09-26: nothing. Standard GitHub-hosted
  runners, `xcode-27` included, are free and unlimited there.
- A private repository, as Saffsanity/sill was until then: each run's minutes count against the
  account's included minutes (2,000 a month on GitHub Free, 3,000 on Pro). Count a macOS minute
  as about ten of them: GitHub's billing pages no longer print the multiplier table they used to
  (macOS 10, Linux 1), but they still speak of minute multipliers, and today's prices keep that
  ratio ($0.062 a macOS minute against $0.006 for Linux). So plan on roughly 200 macOS minutes a
  month on Free and 300 on Pro. After that, $0.062 a minute, rounded up per job, and only with a
  payment method on file: without one, runs stop when the included minutes are used up.
- To be sure nothing is ever charged while the repository is private (zero operating costs is a
  hard rule): with no payment method on file, nothing can be. With one, add a budget: Settings ›
  Billing and licensing › Budgets and alerts › New budget, product Actions, $0, and tick "Stop
  usage when budget limit is reached" where the form offers it (where it doesn't, GitHub says the
  budget always stops usage; [budgets](https://docs.github.com/en/billing/how-tos/set-up-budgets)).
  Once the included minutes are gone, runs then wait for the next month. The same page's
  "Included usage alerts" mail you at 90% and 100% of them.
- The TestFlight workflow (by hand only) takes about 5 minutes a run, under 10: some 50 included
  minutes, or about $0.30 once they are gone.
- One CI run takes about 10 minutes (under 15): about $0.60 once the included minutes are gone,
  and about 100 included minutes before that, so the month's included minutes cover some 15 to 20
  runs on Free. Each push to a pull request (drafts too) is a run, so a busy day of pushes can
  use a week's share; making the repository public ends the question. A verify-only release
  takes about the same (the disk image adds well under a minute). A signed release also waits for
  Apple's notary service twice (the zip, then the disk image), usually 15 to 30 minutes in all.
  The mutants (CI started by hand with "mutants" ticked) run a job for each of the 32 checks with
  mutants, about four hours of macOS time in all (their scripts took 205 minutes here on
  2026-09-27, several at once; each job also checks out and selects Xcode, and is rounded up to
  the minute): some 2,400 included minutes, more than Free's month, or about $15.
- Storage is small: the build cache stays within the 10 GB each repository gets for caches, and
  the artifacts (a zip and a disk image of about 3 MB each for 14 days, the notary logs for 30, a
  TestFlight .ipa of about 2 MB for 14 days) within the 500 MB of artifact storage on GitHub Free.

### The runner image

All four workflows run on `xcode-27`, the newest macOS image GitHub offers and the only one with
Xcode 27, which Sill is built with: macOS 27.0 with Xcode 27.0 (the default), 27.1 and a 27.2 beta
in September 2026 (image 20261006.0244: `Xcode_27.app` 27.0 27A266a, `Xcode_27.1_beta.app` 27.1
27A9269, `Xcode_27.2_beta_2.app` 27.2 27B5028f). GitHub calls it a public preview, so jobs can wait in a queue longer and
software on it can change. `macos-latest` is macOS 26 with Xcode 26.0.1 to 26.6, and `macos-15`
has Xcode 16.0 to 16.4 and 26.0.1 to 26.3; Sill has not been built with those. A step
(`.github/actions/select-xcode`, asked for version 27) selects the newest Xcode 27 that is not a
beta and prints `xcodebuild -version`: on today's image that is Xcode 27.0 (27A266a), since the
image installs 27.1 under a name that says beta. CI's build job takes it for the Mac side (SwiftPM,
the pure checks, the CLI) and, right before the iOS app, asks again for version 27.1 with
`allow-beta`: the newest 27.1 that is not a beta, else its newest release candidate or beta (with
a notice; today `Xcode_27.1_beta.app`), because the iOS app needs the iOS 27.1 SDK
(docs/iphone-duo-plan.md). The mutants job asks for 27. On an image without an Xcode 27, CI warns
and builds with the newest Xcode there, and the release and TestFlight workflows stop: a release
is built with Xcode 27 or not at all, and an App Store build with Xcode 27.1 or later
(`release-ios.sh` refuses an older one), so TestFlight from GitHub Actions waits for a 27.1 that
is not a beta. When GitHub replaces the
preview with a regular macOS 27 image, change `runs-on` in the three files. The image's `bash` is
3.2, macOS's own, and runs every `run:` step: write steps it can parse (it ends a `$(` at the `)`
of a `case` pattern inside it) and try them with `/bin/bash`, not zsh.
