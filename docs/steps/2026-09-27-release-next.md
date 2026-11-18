**Sill for Mac 0.4.0 with Sill for iPhone and iPad 0.5 (2) (2026-09-27, branch `release-next` from
main at 643af6b, main merged in once PRs #37, #38, #42 and #43 were on it; #39, away from home, deferred to 0.4.1;
PR #41).** Noah: "Once all are
merged I want to try the latest build", then the go. The first release that needs both apps at
once: pairing at home (#37) made the home door TLS 1.3 with pairing, so a device from before it
cannot connect to 0.4.0 at home (a plain dial, a failed handshake, and a redial at once while the
Mac is listed, so a flicker that can come several times a second; the Mac's menu says "An iPhone
or iPad Needs Sill Updated"), and 0.5 (2), a Release build, dials no plain door
(Sill for Mac 0.3.1 and earlier: "Update Sill", nothing dialed). docs/release-checklist.md, "The
pairing release", has the order: the device build uploaded first, its What to Test as it shows,
one device on it against a Mac with the release's code once it is processed, the site staged, the
Mac release, the site pushed at once, and no external group or App Review before 0.4.0 is the
download.
- Versions: Sill for Mac 0.4.0 (the build number the commit count at the tag), Sill for iPhone and
  iPad 0.5 (2) (0.5 was never submitted, so it stays the App Store's first version; App Store
  Connect takes each build number once per version), both in the release's pull request, so the
  annotated tag v0.4.0 names the commit both came from.
- Docs (true on main at 643af6b, committed before the merges): the checklist brought up to date (the
  record "Sill – Mac Streaming", Apple ID 6816359860; 0.5 (1) from b37f47a; the dmg page move and the
  first release done; notes over `--publish`'s one-line body; the check of what was published; What
  to Test per build; one device trying a device build before the Mac release it goes with; the
  site republished right after the release it describes, and hosted by GitHub itself since
  2026-09-27, Cloudflare's proxy off), the App Store
  metadata with the tour, the menus and the Mac's pointer, the privacy policy with the menus and the
  pointer. At release time, what waited for #37, #38, #42 and #43: the privacy policy (pairing records,
  the device key, TLS everywhere, Require pairing), support's Pairing, the home, download and Remote
  Access paragraphs, the README's How it works and Good to know, the metadata's pairing (the review
  notes' CONNECT AND PAIR, 3,948 bytes of 4,000), every device pairing once more after the Mac
  updates (#42: a new key in the data-protection keychain, no migration), the Spotlight fix (#43), the checklist's "The pairing release". A review of
  the drafts against the code (2026-09-27) corrected them before they went in: a device paired at
  home learns the Mac's addresses for afar only in a session at home with Remote Access on (the
  review notes, shot 11, support, index, the README and the notes say so; until then its Remote
  row says only "didn’t answer"); with Require pairing off a device takes any Mac key, so the key
  check is between paired ends; the Mac sends its addresses only with Remote Access on; the cable's
  code keeps a second key of one device from pairing by itself; the log names the gestures; no
  gesture claim for macOS 14 or 15 (never tried there); the liveness fix is the device's.
- Rehearsed on main at 643af6b (2026-09-27): `release.sh --dry-run` 54 s (0.3.1 (391), the zip and
  the image 3.0 MB each, spctl "Unnotarized Developer ID"), `release-ios.sh` 46 s (0.5 (1), Sill.ipa
  2.5 MB, Apple Distribution, the App Store profile, both required-reason APIs declared).
- **Untested, for Noah:** the published pair on his devices (TestFlight's 0.5 (2) first, then Sill
  for Mac 0.4.0 from the download on another Mac or user account: the iPad paired for Remote Access
  pairs once more, as the iPhone does, with the code or over the cable), and the open
  device tests of #31, #35, #36, #37, #38, #42 and #43 that the App Store's claims wait for.
