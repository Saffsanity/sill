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
  lines). The sweep's report has the commands. Since: public on 2026-09-26
  with its history as it is (Noah), Apache-2.0 kept, and PR #26 made the
  held-back edits (sill-site republished with them). On 2026-09-27 the
  repository has secret scanning, push protection, private vulnerability
  reporting and the Actions allow-list (selected actions, pinned by SHA) on;
  still open: rulesets for main and the v* tags (none yet) and immutable
  releases (off).
