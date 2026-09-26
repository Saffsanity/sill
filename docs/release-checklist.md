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
- [ ] Publish: `Scripts/release.sh --publish` (with the same two variables), or a pushed tag with
      the release workflow ("Releasing from GitHub Actions" below), creates the GitHub Release
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

## Releasing from GitHub Actions

Two workflows run on GitHub's own Macs. `.github/workflows/ci.yml` checks every pull request and
every push to `main` (not a change to documents, the site or the design files alone): it builds
the Mac side with `swift build -c release`, runs the pure checks (`Tests/checks/run-all.sh`),
builds the iOS app for the simulator without signing, and runs the CLI where it needs no capture or
encoder. `.github/workflows/release.yml` runs when a tag `v<version>` is pushed, or by hand (Actions
› Release › Run workflow) with such a tag. Both use no secret until you turn signing on.

### Why the download link doesn't work yet

- There is no release. The site's button links `releases/latest/download/Sill.zip`, which GitHub
  redirects to the newest release's file of that name, and `Scripts/release.sh --publish` has
  never run, so there is nothing to redirect to.
- The repository is private, and GitHub serves a private repository's release files only to people
  signed in with access to it. Everyone else gets a 404 even once a release exists. Either make
  Saffsanity/sill public (the plan at launch), or publish in the public Saffsanity/sill-site: the
  variable `SILL_RELEASE_REPO` and the secret `SILL_RELEASE_TOKEN` below, and `download.html`'s
  three links changed to point there.

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
  (`release.sh` checks): bump the version, or delete that release and its tag first.

### Secrets and variables

Settings › Secrets and variables › Actions, or `gh` from the repository's folder. Nothing here
ever goes in the repository, a commit message or a shell profile.

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
base64 -i DeveloperID.p12 | gh secret set SILL_DEVELOPER_ID_P12
gh secret set SILL_DEVELOPER_ID_P12_PASSWORD        # asks for the value; nothing lands in the shell history
gh secret set SILL_NOTARY_KEY_ID
gh secret set SILL_NOTARY_ISSUER_ID
base64 -i AuthKey_ABC123DEFG.p8 | gh secret set SILL_NOTARY_KEY_P8
gh variable set SILL_SIGN_IN_CI --body true         # after a verify-only run has passed
```

Keep the exported .p12 and .p8 where part 1 keeps its backups, outside the repository, and not in
Downloads.

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
  account's included minutes (2,000 a month on GitHub Free, 3,000 on Pro), and a macOS minute
  counts as about ten of them (GitHub's docs call it a minute multiplier; macOS costs $0.062 a
  minute against Linux's $0.006). So roughly 200 macOS minutes a month are included on Free and
  300 on Pro. After that, $0.062 a minute, rounded up per job, and only with a payment method on
  file: without one, runs stop when the included minutes are used up.
- To be sure nothing is ever charged while the repository is private (zero operating costs is a
  hard rule): Settings › Billing and licensing › Budgets and alerts › New budget, for Actions,
  $0. A personal account's budget always stops usage at its limit
  ([budgets](https://docs.github.com/en/billing/how-tos/set-up-budgets)), so once the included
  minutes are gone, runs wait for the next month instead. Each push to a pull request is a run,
  so a busy day of pushes can use a week's share; making the repository public ends the question.
- One CI run takes about 10 minutes (under 15): about $0.60 once the included minutes are gone.
  A verify-only release about the same. A signed release also waits for Apple's notary service,
  usually 15 to 30 minutes in all. The mutants (CI started by hand with "mutants" ticked) take an
  hour or more of macOS time across their eight jobs.
- Storage is small: the build cache stays within the 10 GB each repository gets for caches, and
  the artifacts (a zip of about 2 MB for 14 days, the notary log for 30) within the 500 MB of
  artifact storage on GitHub Free.

### The runner image

Both workflows run on `xcode-27`, the newest macOS image GitHub offers and the only one with Xcode
27, which Sill is built with: macOS 27.0 with Xcode 27.0 (the default), 27.1 and a 27.2 beta in
September 2026. GitHub calls it a public preview, so jobs can wait in a queue longer and software
on it can change. `macos-latest` is macOS 26 with Xcode 26.0.1 to 26.6, and `macos-15` has Xcode
16.0 to 16.4 and 26.0.1 to 26.3; Sill has not been built with those. A step selects the newest
Xcode that is not a beta (`.github/actions/select-xcode`) and prints `xcodebuild -version`: on
today's image that is Xcode 27.0 (27A266a), the same build as on Noah's Mac, since the image
installs 27.1 under a name that says beta. When GitHub replaces the preview with a regular macOS 27 image, change
`runs-on` in both files.
