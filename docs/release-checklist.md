# Releasing Sill

The order of work for putting the iOS app in the App Store and Sill for Mac on the web: part 1
once, part 2 on every release. The texts and answers App Store Connect asks for, ready to paste,
are in `docs/app-store-metadata.md` ("metadata §N" below). The pages are in `site/` (plain HTML,
no build step), `Scripts/release.sh` makes the notarized Mac download, and `Scripts/release-ios.sh`
the iOS app's build for App Store Connect (TestFlight, below).

## Placeholders

The domain and the support address are Noah's (confirmed 2026-09-25); only the App Store address
still waits, for the App Store Connect record. Each lives in the places listed.

| What | Now | Where |
|---|---|---|
| The site's domain | getsill.app (bought at Cloudflare 2026-09-25; live) | `site/CNAME`, the iOS app's links (`iOSClient/SillLinks.swift`), `README.md`, `docs/DEVELOPMENT.md`, `docs/app-store-metadata.md`, `Scripts/release.sh`, this file |
| The support address | `support@getsill.app` (Cloudflare Email Routing, 2026-09-25) | `site/privacy.html`, `site/support.html`, `README.md`, `docs/app-store-metadata.md`, this file |
| The current Mac build | none: the page links `releases/latest/download/Sill.zip` and `Sill.zip.sha256`, which `release.sh --publish` uploads under those names | `site/download.html` (never edited per release, part 2) |
| The App Store address | `APP_STORE_URL_PLACEHOLDER`: until it is replaced, a Mac's update notice on the device shows no "Update Sill in the App Store" link (its words still say what to do), and `release-ios.sh` warns | `iOSClient/SillLinks.swift` (`appStoreText`; TestFlight §2 has the command) |

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

- [ ] Rehearse with that command: `--dry-run` checks the setup, builds, signs and zips, and stops
      before anything goes to Apple. When something is missing it says what, and builds nothing.
      It builds any commit and only warns that HEAD lacks the release's tag (part 2), which a real
      run refuses to build without.

### 3. The website

Preview it with `python3 -m http.server 8000 --directory site` and http://localhost:8000.

Before it goes public (Saffsanity/sill went public on 2026-09-26, after the sweep of PR #24; the
unchecked items below were done that day or record what was decided):

- [x] Done 2026-09-25: `support@getsill.app` reaches Noah's mailbox (Cloudflare Email Routing,
      below). Apple wants real contact details behind the Support URL (guideline 1.5).
- [ ] Remote Access: the pages describe it (PR #13, on main since ba91136). For a release without
      it, delete each block from `<!-- Remote Access` to `<!-- /Remote Access -->`. Then this must
      print nothing: `grep -n -i -E 'remote access|vpn|tailscale|camera|pair' site/*.html`.
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
      Pages on (main, / root) and the custom domain set. Republish whenever `site/` changes:
- Once sill is public, it can serve the site itself: `git subtree push --prefix site origin gh-pages`,
  then Settings › Pages › gh-pages, / (root). Retire sill-site then.

```
git clone https://github.com/Saffsanity/sill-site.git ../sill-site     # once
rsync -a --delete --exclude .git --exclude .github --exclude .nojekyll site/ ../sill-site/   # whenever the site changes
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

sill-site has two files of its own that `site/` lacks, `.nojekyll` and `.github/FUNDING.yml` (its
Sponsor button); the two excludes keep `--delete` off them.

- [x] Domain, done 2026-09-25: getsill.app at Cloudflare, with A records to GitHub Pages
      (185.199.108.153, .109, .110, .111), the matching AAAA records (2606:50c0:8000::153 to
      8003::153), and Email Routing forwarding support@ to Noah's mailbox. The records are proxied
      through Cloudflare, which serves the certificate, so GitHub's "Enforce HTTPS" stays off.
- [ ] Cloudflare: SSL/TLS mode "Full" and "Always Use HTTPS" on, so the hop to GitHub is encrypted
      and plain links redirect (.app is HTTPS-only in browsers anyway). Add `www CNAME
      saffsanity.github.io` if www should work. Optional: verify the domain for the GitHub account
      (github.com › Settings › Pages › Add a domain, a TXT record) so nobody else can claim it.
- [ ] Cloudflare rewrites visible email addresses unless they sit inside `<!--email_off-->`
      comments, which the pages now use; alternatively turn off Scrape Shield › Email Address
      Obfuscation.
- [ ] In the repository's Settings › Pages, tick Enforce HTTPS once GitHub has the certificate.
- [ ] In a private window: https://getsill.app/, `/download`, `/privacy` and `/support` all
      load. GitHub Pages serves `privacy.html` at `/privacy`, the form the app and App Store
      Connect use.

### 4. The App Store Connect record

Field by field, with the values and in the order App Store Connect asks: TestFlight §1 below.

- [ ] New App (metadata §1): iOS, name Sill, bundle ID me.saffer.sill, SKU sill-ios. Creating
      it reserves the name.
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
      (metadata, the Remote Access switch). Then nothing you paste mentions Remote Access, a VPN,
      Tailscale, pairing or camera access.
- [ ] Export compliance (metadata §6): nothing to answer. The app's Info.plist says NO
      (`ITSAppUsesNonExemptEncryption`), so the uploaded build must not show Missing Compliance.
- [ ] App Review Information (metadata §7 and §8): contact, notes, the video.
- [ ] Version Release: Manually release this version, so an approval waits for the Mac download.
- [ ] Once the record exists, before the first upload: in `iOSClient/SillLinks.swift`, replace
      `APP_STORE_URL_PLACEHOLDER` with `https://apps.apple.com/app/id<Apple ID>` (App Information
      shows the Apple ID; TestFlight §2 has the command). A Mac that needs a newer Sill on the
      device then shows "Update Sill in the App Store" under its notice.

## Part 2: every release

- [ ] Versions: Sill for Mac's is `CFBundleShortVersionString` in `Packaging/Info.plist`; its
      build number is the commit count, which make-app.sh stamps in. The iOS app's are
      MARKETING_VERSION and CURRENT_PROJECT_VERSION in `iOSClient/Sill.xcodeproj` (target Sill ›
      General). Commit.
- [ ] Tag that commit `v` + Sill for Mac's version and push the tag: `git tag v0.4.0` and
      `git push origin v0.4.0` for 0.4.0. `make-app.sh --release` builds only the commit carrying
      it, and `release.sh --publish` refuses to start until origin's tag names that commit, then
      makes the GitHub Release for it. Every Sill.app's update check reads the releases of
      Saffsanity/sill alone (`UpdatePolicy.feed`) and compares the newest published one's tag (not
      a draft, not a prerelease) with the version it runs: once Saffsanity/sill is public, within a
      day of a release there, every older Sill.app offers it. While the repository is private,
      GitHub answers the check with a 404 and no Sill.app offers anything.
- [ ] The release command from part 1 §2, without `--dry-run`. It builds, notarizes, staples and
      zips, checks a copy unpacked from the zip the way Gatekeeper will, and prints the zip's
      path, its SHA-256 and where Apple's notary log is. It warns when the log lists issues: read
      them.
- [ ] Try the zip as someone new to Sill would: on another Mac or a new macOS user account,
      download it from where it will live (so it gets the quarantine flag), unzip it, open it,
      allow the permissions and stream to a device. For 1.0 this is the reviewer's path: film it
      for the review video (metadata §8).
- [ ] Publish: `Scripts/release.sh --publish` (with the same two variables), or a pushed tag with
      the release workflow ("Releasing from GitHub Actions" below), creates the GitHub Release
      `v<version>` in Saffsanity/sill with the assets `Sill.zip` and `Sill.zip.sha256`; before it
      builds, `--publish` checks that origin has the tag and that it names HEAD (the workflow's
      checkout is that tag). The site's Download button links `releases/latest/download/Sill.zip`,
      which GitHub redirects to the newest release, so download.html is never edited. The
      repository must be public for anonymous downloads and for the update check. Until it is,
      `SILL_RELEASE_REPO=Saffsanity/sill-site` publishes there instead (point download.html's three
      GitHub links there too), and release.sh warns: a release in sill-site can be downloaded, but
      no Sill.app will offer it, so the download page's "it tells you when a new version is out"
      does not hold for it. Once sill is public: unset `SILL_RELEASE_REPO` (in `~/.sill-release`
      and the repository variable of that name too), point the links back at Saffsanity/sill, and
      publish the newest release there, so that every older Sill.app offers it. One way or the
      other for a version: pushing the tag, which a local `--publish` needs first, also starts the
      release workflow. With `SILL_SIGN_IN_CI` set to `true` that run publishes the release, so
      don't also run `--publish` here (whichever comes second stops at "already exists"); without
      it the run only verifies (macOS minutes either way).
- [ ] The first release only: the published copy of download.html says the build is being prepared;
      right after Saffsanity/sill goes public, republish `site/` (the rsync below) so the button
      shows (before that, the button and every GitHub link on the pages answer 404 to visitors).
      Then, in a private window, download it from https://getsill.app/download and compare its
      `shasum -a 256` with `Sill.zip.sha256`.
- [ ] iOS: `Scripts/release-ios.sh --bump --upload` (a new version's first upload without
      `--bump`, once `MARKETING_VERSION` says it); TestFlight §4 below. Or in Xcode: Any iOS
      Device, Product › Archive, then the Organizer's Validate App and Distribute App › App Store
      Connect › Upload. The privacy report: `Scripts/release-ios.sh --privacy-report`, and the
      Organizer's Generate Privacy Report for the PDF; both should list the privacy manifest's API
      categories.
- [ ] TestFlight: internal testers get the build without review. An external group sends the
      first build through Beta App Review with the same notes and video: a cheap rehearsal
      (TestFlight §5 to §7 below).
- [ ] Review notes (metadata §7): describe what is new in this version specifically (guideline
      2.3.1(a)), and What's New (metadata §5).
- [ ] Submit for review with manual release. Release once the Mac download is live.
- [ ] If what Sill does or keeps changed, update `site/` too, with the privacy policy's date.

## TestFlight

Sill for iPhone and iPad reaches testers, then the App Store, through App Store Connect.
`Scripts/release-ios.sh` makes the build and uploads it from this Mac; the rest is App Store
Connect's pages, in this order. The texts to paste are in `docs/app-store-metadata.md`. Nothing here
costs money: uploads and TestFlight come with the Apple Developer Program.

Already done (2026-09-26): the bundle ID is registered (Xcode's automatic signing made it; the
developer portal calls it "XC me saffer sill"), and the first export, `release-ios.sh`'s rehearsal,
made a cloud-managed Apple Distribution certificate, whose private key stays with Apple, and the
App Store profile "iOS Team Store Provisioning Profile: me.saffer.sill". Nothing was uploaded.

### 1. The app's record

- [ ] Apps › + › New App:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Sill` (if it's taken: `Sill – Window Streaming`, with an en dash; metadata §2) |
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

- [ ] With the Apple ID from App Information (a number such as 6712345678), before the first upload:

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
      and the policy must agree. On 2026-09-26 Saffsanity/sill-site held main's `site/` file for
      file (the policy's Update check section and the footer's GitHub links included) but for
      `download.html`, which says "being prepared" on purpose until the first Mac release (part 2),
      so TestFlight needs no republish. The pages getsill.app serves lack the `<!--email_off-->`
      comments only because Cloudflare takes them out. If `site/` changes before that release,
      republish it without the download page (and, as in part 1 §3, without touching sill-site's
      own `.nojekyll` and `.github`):

```
rsync -a --delete --exclude .git --exclude .github --exclude .nojekyll --exclude download.html site/ ../sill-site/
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

- [ ] In a private window: https://getsill.app/privacy shows "Update check", and /support shows
      support@getsill.app.

### 4. The build

```
Scripts/release-ios.sh                    # archive, export .build/ios/export/Sill.ipa and check it; nothing uploaded
Scripts/release-ios.sh --upload           # the same, then the upload: 0.5 (1), the first build
Scripts/release-ios.sh --bump --upload    # every later upload of 0.5: the build number + 1, committed alone
Scripts/release-ios.sh --privacy-report   # what the archive's privacy manifest declares, and its required-reason APIs
```

- It needs Xcode 27 selected (it refuses any other) and the Apple Account of team 9B2KKVM937 in
  Xcode › Settings › Accounts, which signs and uploads. Uploading takes Account Holder, Admin, App
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
  Version), committed; its builds may start again at 1.
- The rehearsal on 2026-09-26 (main at 6f2a934, whose iOS app is 150f781's): archive and export in
  49 s, Sill.ipa 2.0 MB, signed "Apple Distribution: NOAH WILLIAM SAFFER (9B2KKVM937)" (cloud
  managed), the App Store profile until 2027-09-26, entitlements `application-identifier`
  9B2KKVM937.me.saffer.sill, `beta-reports-active` true, get-task-allow false, no keychain or
  Apple Account prompt.
- The privacy report: xcodebuild has no command for it, so `--privacy-report` prints what the report
  is made of (the manifests, and the required-reason APIs the binary uses). The PDF: `open
  .build/ios/Sill.xcarchive` (Xcode shows it in Window › Organizer › Archives), Control-click it ›
  Generate Privacy Report. Keep it with the App Privacy answers.
- After an upload, App Store Connect processes the build, usually within half an hour, and emails
  when it's done; it then shows under TestFlight as 0.5 (1).

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
| Beta App Description | The block below (548 characters) |
| Feedback Email | `support@getsill.app` |
| Marketing URL | `https://getsill.app` |
| Privacy Policy URL | `https://getsill.app/privacy` |
| Beta App Review Information: First Name, Last Name, Phone Number, Email | Noah, Saffer, a number starting with + and the country code, `support@getsill.app` (or your own; App Review only) |
| Sign-in required | Unchecked: there is no account |
| Review Notes | Metadata §7's notes (about 3,550 characters of the 4,000 allowed), Remote Access part included while the build has it |
| License Agreement | Apple's standard: leave it |

```text
Sill puts your Mac on your iPhone and iPad. Pick any window, or the whole desktop, and use it with touch, a trackpad, a keyboard or Apple Pencil.

It needs the free Sill for Mac, from https://getsill.app/download, on a Mac with Apple silicon and macOS 14 or later. Open Sill for Mac and allow Screen Recording and Accessibility, then open Sill on your iPhone or iPad on the same Wi-Fi and tap your Mac.

To send feedback, take a screenshot while you use Sill, or use Send Beta Feedback in TestFlight. Write to support@getsill.app for anything else.
```

### 7. External testers and Beta App Review

- [ ] TestFlight › External Testing › + : a group such as `Beta`. Add Builds › 0.5 (1), and What to
      Test: metadata §5's What's New. Submit Review.
- Beta App Review looks at the first build of a version in full (later builds of the same version
  may not need it), up to six builds a day. It needs what App Review needs: Sill for Mac
  downloadable at https://getsill.app/download (not yet: no Mac release, and the repository is
  private; "Why the download link doesn't work yet" below), the notes, and the contact. Test
  internally first: that needs none of it.
- Once approved: invite testers by email, or turn on a public link (Open to Anyone, with a tester
  limit if you like, up to 10,000).

### 8. Screenshots, for the App Store

TestFlight needs none; the App Store version does. Metadata §9 is the plan: the sizes, the five
screens of each set, the capture commands and what may appear in the picture. The session:

- [ ] When: once the build you will submit is on TestFlight, from the same commit (§9 builds it
      for the simulator, Release).
- [ ] Stage the Mac first (§9's list: rename it, Do Not Disturb on both, only Notes, Weather,
      Clock, Calculator or TextEdit with sample text), and disconnect every other device.
- [ ] iPhone 6.9" (the iPhone 18 Pro Max simulator, 1320 × 2868), then iPad 13" (iPad Pro 13-inch
      (M5), 2064 × 2752): five each, the app in use first, JPEG without alpha.
- [ ] Never `simctl io … recordVideo` while Sill.app streams: the recorder takes the video encoder
      from Sill (screenshots are fine).
- [ ] Upload them on the version page (iPhone 6.9" Display, iPad 13" Display) with the rest of
      metadata §5, §7 and §8 when you submit.

### TestFlight from GitHub Actions

`.github/workflows/testflight.yml` runs only by hand: Actions › TestFlight › Run workflow, on a
branch or tag (GitHub lists it once it is on main). It never runs on a push or a pull request.

- Without the key below: `release-ios.sh --unsigned`. The Release archive is built without
  signing and checked; `Sill-<version>-<build>-unsigned.ipa` is the artifact for 14 days, to look
  inside only. No secret is read.
- With the key: `release-ios.sh --sign-at-export`. The runner has no development certificate, so
  the archive is built without signing, and the export signs it through the key with the same
  cloud-managed certificate as here and the App Store profile, which Xcode makes or fetches. No
  certificate, private key or profile is kept in the repository's secrets: an archive made without
  signing exports with the same entitlements (tried here on 2026-09-26 with the Apple Account;
  through a key, not yet). `Sill-<version>-<build>.ipa` is the artifact for 14 days. Nothing is
  uploaded, unless:
- the repository variable `SILL_TESTFLIGHT_IN_CI` is `true`: the run also uploads, as
  `--upload` does here. It takes the committed build number, so bump it here (`--bump`), push,
  then run the workflow.

| Name | Kind | What it holds |
|---|---|---|
| `SILL_TESTFLIGHT_KEY_ID` | secret | The Key ID of an App Store Connect API key with the Admin role (Users and Access › Integrations › App Store Connect API › Team Keys › +). Cloud signing refuses any other role. |
| `SILL_TESTFLIGHT_ISSUER_ID` | secret | The Issuer ID above the keys (the same for every key of the team). |
| `SILL_TESTFLIGHT_KEY_P8` | secret | The key file `AuthKey_<Key ID>.p8`, in base64. Apple lets you download it once. |
| `SILL_TESTFLIGHT_IN_CI` | variable | `true` also uploads. Absent or anything else: export only. |

```
gh secret set SILL_TESTFLIGHT_KEY_ID
gh secret set SILL_TESTFLIGHT_ISSUER_ID
base64 -i AuthKey_ABC123DEFG.p8 | gh secret set SILL_TESTFLIGHT_KEY_P8
gh variable set SILL_TESTFLIGHT_IN_CI --body true     # after an export-only run has passed
```

An Admin key can do nearly all an Admin can in App Store Connect, managing users included, so it
is a bigger secret than the notary key: keep the .p8 where part 1 keeps its backups, give it to this
repository only, and revoke it (Users and Access › Integrations) when TestFlight from CI isn't in
use; a revoked key stops at once. Uploading from this Mac with `release-ios.sh --upload` needs no
key at all. A run takes about 5 minutes of macOS time (What it costs, below).

## Releasing from GitHub Actions

Two workflows run on GitHub's own Macs. `.github/workflows/ci.yml` checks every pull request and
every push to `main` (not a change to documents, the site or the design files alone): it builds
the Mac side with `swift build -c release`, runs the pure checks (`Tests/checks/run-all.sh`),
builds the iOS app for the simulator without signing, and runs the CLI where it needs no capture or
encoder. `.github/workflows/release.yml` runs when a tag `v<version>` is pushed, or by hand (Actions
› Release › Run workflow) with such a tag. Both use no secret until you turn signing on. A third,
`.github/workflows/testflight.yml`, runs only by hand: TestFlight from GitHub Actions, above.

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
  fails if the icon is missing, and keeps `Sill-<version>-adhoc.zip` as the run's artifact for 14
  days. That zip is for trying out only: not Developer ID, not notarized. Nothing is published.
- With `SILL_SIGN_IN_CI` set to `true`: sign and publish. The same checks, then the Developer ID
  certificate goes into a temporary keychain with a random password, the notary key into a profile
  in it (`notarytool store-credentials`, which validates the key with Apple first), and
  `Scripts/release.sh --publish` runs with `SILL_RELEASE_TAG` set: it builds, notarizes, staples,
  checks a copy unpacked from the zip the way Gatekeeper will, and creates the GitHub Release with
  `Sill.zip` and `Sill.zip.sha256`. Apple's notary log is kept as an artifact for 30 days. The last
  step deletes the keychain and the key files whatever happened. The runner image already carries
  Apple's Developer ID intermediate certificate.
- Then the rest of part 2 as usual: try the zip on another Mac, and for the first release,
  republish `site/`.
- A failed run can be re-run from its page. A version that is already released is refused
  before anything is built or sent to Apple (`release.sh --publish` asks GitHub first, as it asks
  whether its token reaches the repository): bump the version. Deleting that release and its tag
  frees the version only for a release that isn't immutable: GitHub never lets an immutable
  release's tag be used again, even after the release is deleted.

### Secrets and variables

Settings › Secrets and variables › Actions, or `gh` from the repository's folder. Nothing here
ever goes in the repository, a commit message or a shell profile.

Until the repository is public, sign on this Mac instead (`Scripts/release.sh --publish`, with
`SILL_SIGN_IN_CI` unset). Repository secrets reach any workflow on any branch or tag pushed here
(never a fork's pull request), and an environment, which can keep them to release runs alone,
needs a public repository on GitHub Free. Once it is public, before `SILL_SIGN_IN_CI` goes on: an
environment `release` that only tags `v*` may deploy to, with Noah as its required reviewer,
holds the five secrets (`gh secret set NAME --env release`), and release.yml's publish job names
it (`environment: release`).

| Name | Kind | What it holds |
|---|---|---|
| `SILL_SIGN_IN_CI` | variable | `true` turns on signing and publishing. Absent or anything else: verify only. |
| `SILL_DEVELOPER_ID_P12` | secret | The Developer ID Application certificate with its private key, exported as a .p12 (part 1 §1), in base64. |
| `SILL_DEVELOPER_ID_P12_PASSWORD` | secret | The password given when exporting that .p12. |
| `SILL_NOTARY_KEY_ID` | secret | The App Store Connect API key's Key ID (part 1 §2, the API key). |
| `SILL_NOTARY_ISSUER_ID` | secret | The Issuer ID shown above the keys in App Store Connect. |
| `SILL_NOTARY_KEY_P8` | secret | The key file `AuthKey_<Key ID>.p8`, in base64. |
| `SILL_RELEASE_REPO` | variable, optional | `owner/name` of another repository to publish in, such as `Saffsanity/sill-site`. Default: this one, with the run's own token. |
| `SILL_RELEASE_TOKEN` | secret, optional | Only with `SILL_RELEASE_REPO`: a fine-grained personal access token for that one repository, with Contents read and write. |

The workflow takes only an App Store Connect API key, not the app-specific password that part 1 §2
also allows. The keychain, its password, the profile name `sill-notary` and the token for this
repository's own release are made by each run and gone at its end.

```
base64 -i <backup folder>/DeveloperID.p12 | gh secret set SILL_DEVELOPER_ID_P12
gh secret set SILL_DEVELOPER_ID_P12_PASSWORD        # asks for the value; nothing lands in the shell history
gh secret set SILL_NOTARY_KEY_ID
gh secret set SILL_NOTARY_ISSUER_ID
base64 -i <backup folder>/AuthKey_ABC123DEFG.p8 | gh secret set SILL_NOTARY_KEY_P8
gh variable set SILL_SIGN_IN_CI --body true         # after a verify-only run has passed
```

`<backup folder>` is where part 1 keeps the exported .p12 and .p8: outside the repository (these
commands run in it, so a bare file name would be read from there) and not in Downloads.
`.gitignore` leaves out `*.p12`, `*.p8` and `AuthKey_*` in case one lands in the repository
anyway.

### Rotating them

- The Developer ID certificate, before it expires or if its key may have leaked: make a new one
  (part 1 §1), export it with a new password, and set both `SILL_DEVELOPER_ID_P12` and
  `SILL_DEVELOPER_ID_P12_PASSWORD` again. Sill's designated requirement names the team, not the
  certificate, so users keep their permissions. Revoke the old certificate at developer.apple.com
  only if the key leaked: revoking it can also stop copies already signed with it from opening.
- The notary key: in App Store Connect › Users and Access › Integrations › App Store Connect API,
  make a new key, set the three `SILL_NOTARY_*` secrets, run a release (or `store-credentials`
  locally) to see it validate, then revoke the old key there; a revoked key stops working at once.
- `SILL_RELEASE_TOKEN`: fine-grained tokens expire. Make a new one before that (github.com ›
  Settings › Developer settings › Personal access tokens), set it, and delete the old one.
- After a suspected leak of any of them: revoke first, then replace, then look at the repository's
  Actions runs and releases for anything you didn't start.
- Turning signing off again: delete the variable `SILL_SIGN_IN_CI` (or set it to `false`). The
  secrets can stay.

### What it costs

GitHub's prices on 2026-09-25 ([runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing),
[Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions),
[hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)):

- A public repository: nothing. Standard GitHub-hosted runners, `xcode-27` included, are free and
  unlimited there.
- A private repository, as Saffsanity/sill is today: each run's minutes count against the
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
  takes about the same. A signed release also waits for Apple's notary service, usually 15 to 30
  minutes in all. The mutants (CI started by hand with "mutants" ticked) take about two hours of
  macOS time across their twelve jobs: some 1,200 included minutes, more than half of Free's
  month, or about $7.50.
- Storage is small: the build cache stays within the 10 GB each repository gets for caches, and
  the artifacts (a zip of about 2 MB for 14 days, the notary log for 30, a TestFlight .ipa of
  about 2 MB for 14 days) within the 500 MB of artifact storage on GitHub Free.

### The runner image

All three workflows run on `xcode-27`, the newest macOS image GitHub offers and the only one with
Xcode 27, which Sill is built with: macOS 27.0 with Xcode 27.0 (the default), 27.1 and a 27.2 beta
in September 2026. GitHub calls it a public preview, so jobs can wait in a queue longer and
software on it can change. `macos-latest` is macOS 26 with Xcode 26.0.1 to 26.6, and `macos-15`
has Xcode 16.0 to 16.4 and 26.0.1 to 26.3; Sill has not been built with those. A step
(`.github/actions/select-xcode`, asked for version 27) selects the newest Xcode 27 that is not a
beta and prints `xcodebuild -version`: on today's image that is Xcode 27.0 (27A266a), the same
build as on Noah's Mac, since the image installs 27.1 under a name that says beta. On an image
without an Xcode 27, CI warns and builds with the newest Xcode there, and the release and
TestFlight workflows stop: a release is built with Xcode 27 or not at all. When GitHub replaces the
preview with a regular macOS 27 image, change `runs-on` in the three files. The image's `bash` is
3.2, macOS's own, and runs every `run:` step: write steps it can parse (it ends a `$(` at the `)`
of a `case` pattern inside it) and try them with `/bin/bash`, not zsh.
