# Releasing Sill

The order of work for putting the iOS app in the App Store and Sill for Mac on the web: part 1
once, part 2 on every release. The texts and answers App Store Connect asks for, ready to paste,
are in `docs/app-store-metadata.md` ("metadata §N" below). The pages are in `site/` (plain HTML,
no build step), and `Scripts/release.sh` makes the notarized Mac download.

## Placeholders

Noah hasn't confirmed these yet. Each lives in the places listed, and one command changes them all.

| What | Now | Where |
|---|---|---|
| The site's domain | getsill.app (bought at Cloudflare 2026-09-25; live) | `site/CNAME`, the iOS app's links (`iOSClient/SillLinks.swift`), `docs/app-store-metadata.md`, this file |
| The support address | `support@getsill.app` (Cloudflare Email Routing, 2026-09-25) | `site/privacy.html`, `site/support.html`, `docs/app-store-metadata.md` |
| The current Mac build | none: the page links `releases/latest/download/Sill.zip` and `Sill.zip.sha256`, which `release.sh --publish` uploads under those names | `site/download.html` (never edited per release, part 2) |
| The App Store address | `APP_STORE_URL_PLACEHOLDER`: until it is replaced, a Mac's update notice on the device shows no "Update Sill in the App Store" link (its words still say what to do) | `iOSClient/SillLinks.swift` (`appStoreText`; part 1 §4 says when) |

With the real values in place of `<domain>` and `<address>`:

```
grep -rl 'sill\.saffer\.me' site iOSClient docs | xargs sed -i '' 's#sill\.saffer\.me#<domain>#g'
grep -rl support@getsill.app site docs/app-store-metadata.md | xargs sed -i '' 's#support@getsill.app#<address>#g'
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

Before it goes public:

- [ ] Replace `support@getsill.app` (above) with an address someone reads. Apple wants real
      contact details behind the Support URL (guideline 1.5).
- [ ] Remote Access: the pages describe it (PR #13, on main since ba91136). For a release without
      it, delete each block from `<!-- Remote Access` to `<!-- /Remote Access -->`. Then this must
      print nothing: `grep -n -i -E 'remote access|vpn|tailscale|camera|pair' site/*.html`.
- [ ] Open source: the site doesn't say it while Saffsanity/sill is private. Once the repository is
      public with a LICENSE (Apache-2.0 or MPL-2.0, docs/BRIEF.md), follow the comments in
      `index.html` and `support.html`: put "open source" back on the home page and turn the
      commented GitHub links into real ones. Sill for Mac already says "free and open source"
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
rsync -a --delete --exclude .git site/ ../sill-site/                    # whenever the site changes
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

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
- [ ] Version 1.0 (metadata §5 and §9): Support URL `https://getsill.app/support`, the
      description, keywords and screenshots.
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
      shows the Apple ID). A Mac that needs a newer Sill on the device then shows "Update Sill in
      the App Store" under its notice.

## Part 2: every release

- [ ] Versions: Sill for Mac's is `CFBundleShortVersionString` in `Packaging/Info.plist`; its
      build number is the commit count, which make-app.sh stamps in. The iOS app's are
      MARKETING_VERSION and CURRENT_PROJECT_VERSION in `iOSClient/Sill.xcodeproj` (target Sill ›
      General). Commit.
- [ ] Tag that commit `v` + Sill for Mac's version and push the tag: `git tag v0.4.0` and
      `git push origin v0.4.0` for 0.4.0. `make-app.sh --release` builds only the commit carrying
      it, `release.sh --publish` makes the GitHub Release for it, and every Sill.app's update check
      compares the newest published release's tag (not a draft, not a prerelease) with the version
      it runs: within a day of the release, every older Sill.app offers it.
- [ ] The release command from part 1 §2, without `--dry-run`. It builds, notarizes, staples and
      zips, checks a copy unpacked from the zip the way Gatekeeper will, and prints the zip's
      path, its SHA-256 and where Apple's notary log is. It warns when the log lists issues: read
      them.
- [ ] Try the zip as someone new to Sill would: on another Mac or a new macOS user account,
      download it from where it will live (so it gets the quarantine flag), unzip it, open it,
      allow the permissions and stream to a device. For 1.0 this is the reviewer's path: film it
      for the review video (metadata §8).
- [ ] Publish: `Scripts/release.sh --publish` (with the same two variables) creates the GitHub Release
      `v<version>` in Saffsanity/sill with the assets `Sill.zip` and `Sill.zip.sha256`. The site's
      Download button links `releases/latest/download/Sill.zip`, which GitHub redirects to the newest
      release, so download.html is never edited. The repository must be public for anonymous
      downloads; until it is, set `SILL_RELEASE_REPO=Saffsanity/sill-site` and point the button there.
- [ ] The first release only: the published copy of download.html says the build is being prepared;
      republish `site/` (the rsync below) so the button shows. Then, in a private window, download
      it from https://getsill.app/download and compare its `shasum -a 256` with `Sill.zip.sha256`.
- [ ] iOS: in Xcode pick Any iOS Device, then Product › Archive. In the Organizer: Validate App,
      then Distribute App › App Store Connect › Upload. Generate Privacy Report there should list
      the privacy manifest's API categories.
- [ ] TestFlight: internal testers get the build without review. An external group sends the
      first build through Beta App Review with the same notes and video: a cheap rehearsal.
- [ ] Review notes (metadata §7): describe what is new in this version specifically (guideline
      2.3.1(a)), and What's New (metadata §5).
- [ ] Submit for review with manual release. Release once the Mac download is live.
- [ ] If what Sill does or keeps changed, update `site/` too, with the privacy policy's date.
