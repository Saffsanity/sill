**TestFlight tooling (2026-09-26, branch `testflight-tooling` from main at
150f781).** Noah: "help me do the 4 opens for TestFlight" (the App Store
Connect record, screenshots, the 0.5 archive and upload, the placeholder and
the site). This branch makes those minutes of work: the upload tooling and
the record field by field. Nothing was uploaded and no record was created
here; on 2026-09-26 the record was made ("Sill – Mac Streaming", Apple ID
6816359860, PR #27), and 0.5 (1), built from b37f47a, was uploaded.
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
- **Untested, for Noah:** TestFlight on the devices, any run on GitHub
  (unsigned first, then with the key), signing through an API key, and the
  Organizer's privacy report PDF. The record and the upload are done (above).
