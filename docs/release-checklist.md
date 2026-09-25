# Releasing Sill

The order of work for putting the iOS app in the App Store and Sill for Mac on the web: part 1
once, part 2 on every release. The texts and answers App Store Connect asks for, ready to paste,
are in `docs/app-store-metadata.md` ("metadata §N" below). The pages are in `site/` (plain HTML,
no build step), and `Scripts/release.sh` makes the notarized Mac download.

## Placeholders

Noah hasn't confirmed these yet. Each lives in the places listed, and one command changes them all.

| What | Now | Where |
|---|---|---|
| The site's domain | sill.saffer.me | `site/CNAME`, the iOS app's links (`iOSClient/SillLinks.swift`), `docs/app-store-metadata.md`, this file |
| The support address | `SUPPORT_EMAIL_PLACEHOLDER` | `site/privacy.html`, `site/support.html`, `docs/app-store-metadata.md` |
| The current Mac build | `SILL_VERSION_PLACEHOLDER`, `SILL_ZIP_URL_PLACEHOLDER`, `SILL_ZIP_SHA256_PLACEHOLDER` | `site/download.html` (set by hand on every release, part 2) |

With the real values in place of `<domain>` and `<address>`:

```
grep -rl 'sill\.saffer\.me' site iOSClient docs | xargs sed -i '' 's#sill\.saffer\.me#<domain>#g'
grep -rl SUPPORT_EMAIL_PLACEHOLDER site docs/app-store-metadata.md | xargs sed -i '' 's#SUPPORT_EMAIL_PLACEHOLDER#<address>#g'
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

### 3. The website

Preview it with `python3 -m http.server 8000 --directory site` and http://localhost:8000.

Before it goes public:

- [ ] Replace `SUPPORT_EMAIL_PLACEHOLDER` (above) with an address someone reads. Apple wants real
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
- [ ] `download.html` needs a real build first (part 2).

Hosting: GitHub Pages. On GitHub Free it serves only public repositories, and from a branch it
serves the root or `/docs`, never `/site`. So:

- [ ] While Saffsanity/sill is private: create a public repository, Saffsanity/sill-site, copy
      the folder into it (the commands below), then sill-site › Settings › Pages › Deploy from a
      branch › main, / (root).
- Once sill is public, it can serve the site itself: `git subtree push --prefix site origin gh-pages`,
  then Settings › Pages › gh-pages, / (root). Retire sill-site then.

```
git clone https://github.com/Saffsanity/sill-site.git ../sill-site     # once
rsync -a --delete --exclude .git site/ ../sill-site/                    # whenever the site changes
git -C ../sill-site add -A && git -C ../sill-site commit -m "Update the site" && git -C ../sill-site push
```

- [ ] Domain: first verify saffer.me for your account (github.com › Settings › Pages › Add a
      domain). It gives a TXT record to add at saffer.me's DNS host, and then nobody else can
      claim sill.saffer.me. Then add the record `sill  CNAME  saffsanity.github.io.` there.
      `site/CNAME` already names sill.saffer.me. `dig +short sill.saffer.me` shows the CNAME once
      it has spread.
- [ ] In the repository's Settings › Pages, tick Enforce HTTPS once GitHub has the certificate.
- [ ] In a private window: https://sill.saffer.me/, `/download`, `/privacy` and `/support` all
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
- [ ] App Privacy (metadata §4): Privacy Policy URL `https://sill.saffer.me/privacy`, and "No,
      we do not collect data from this app", published as Data Not Collected. The privacy policy
      and the app's privacy manifest say the same.
- [ ] Version 1.0 (metadata §5 and §9): Support URL `https://sill.saffer.me/support`, the
      description, keywords and screenshots.
- [ ] For a build without Remote Access, paste the local-only keywords, What's New
      and review notes, leave out the description's "Away from home" bullet, and film no shot 11
      (metadata, the Remote Access switch). Then nothing you paste mentions Remote Access, a VPN,
      Tailscale, pairing or camera access.
- [ ] Export compliance (metadata §6): nothing to answer. The app's Info.plist says NO
      (`ITSAppUsesNonExemptEncryption`), so the uploaded build must not show Missing Compliance.
- [ ] App Review Information (metadata §7 and §8): contact, notes, the video.
- [ ] Version Release: Manually release this version, so an approval waits for the Mac download.

## Part 2: every release

- [ ] Versions: Sill for Mac's is `CFBundleShortVersionString` in `Packaging/Info.plist`; its
      build number is the commit count, which make-app.sh stamps in. The iOS app's are
      MARKETING_VERSION and CURRENT_PROJECT_VERSION in `iOSClient/Sill.xcodeproj` (target Sill ›
      General). Commit.
- [ ] The release command from part 1 §2, without `--dry-run`. It builds, notarizes, staples and
      zips, checks a copy unpacked from the zip the way Gatekeeper will, and prints the zip's
      path, its SHA-256 and where Apple's notary log is. It warns when the log lists issues: read
      them.
- [ ] Try the zip as someone new to Sill would: on another Mac or a new macOS user account,
      download it from where it will live (so it gets the quarantine flag), unzip it, open it,
      allow the permissions and stream to a device. For 1.0 this is the reviewer's path: film it
      for the review video (metadata §8).
- [ ] Upload the zip. A GitHub Release keeps binaries out of git:
      `gh release create v<version> .build/Sill-<version>.zip --repo Saffsanity/<repo> --title "Sill <version>"`
      gives `https://github.com/Saffsanity/<repo>/releases/download/v<version>/Sill-<version>.zip`.
      Or put the zip in the site's repository next to download.html; each version then adds a
      few MB to it.
- [ ] In `site/download.html`, set the version, the link and the SHA-256 that release.sh printed.
      Publish the site. In a private window, download it from https://sill.saffer.me/download
      and compare its `shasum -a 256`.
- [ ] iOS: in Xcode pick Any iOS Device, then Product › Archive. In the Organizer: Validate App,
      then Distribute App › App Store Connect › Upload. Generate Privacy Report there should list
      the privacy manifest's API categories.
- [ ] TestFlight: internal testers get the build without review. An external group sends the
      first build through Beta App Review with the same notes and video: a cheap rehearsal.
- [ ] Review notes (metadata §7): describe what is new in this version specifically (guideline
      2.3.1(a)), and What's New (metadata §5).
- [ ] Submit for review with manual release. Release once the Mac download is live.
- [ ] If what Sill does or keeps changed, update `site/` too, with the privacy policy's date.
