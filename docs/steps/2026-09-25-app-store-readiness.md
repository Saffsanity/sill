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
  `Sill.dmg`, `Sill.zip` until 0.3.1, and is never edited per release). The
  checklist's Placeholders table has the commands that change each everywhere.
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
  merged here then (the branch took it with main at cea195c in 11e01cd, and PR #14
  merged at 2df7ad6); it overlaps this branch only in CLAUDE.md and README.md.
- **Untested, for Noah:** the decisions: the domain, the contact address, and
  whether 1.0 keeps Remote Access, which main has had since ba91136 (the
  audit advised a 1.0 without it before it merged; the metadata's switch lists
  the cuts). On a device: the footer's links open Safari (the site: live since
  2026-09-25), VoiceOver reads the footer once, after the rows (its measuring
  copy is hidden from it), the card's fields with a hardware keyboard (the
  column at the top, the footer in view) and the software one (the footer
  under it), and a phone held sideways, which only the harness drew here
  (956x440). The release: the Developer ID
  certificate, notary credentials, release.sh for real, a first launch on a
  Mac that never had Sill, the site on GitHub Pages with its DNS record, the
  App Store Connect record (the checklist's part 1). The description's claims
  not yet seen on a device: the cable on an iPhone, Pencil hover, 120 fps.
  Done since: the domain and the address (2026-09-25), the site at getsill.app,
  the Developer ID certificate, the notary credentials and release.sh for real
  (v0.3.0 and v0.3.1), and the App Store Connect record (2026-09-26).
