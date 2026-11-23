**Words Noah promised on the site: #316's way back in, and three contributors' credit (2026-11-18, branch `promises-words` from main at 8dbbb50).**
Noah, 2026-11-18: "also work on anything I promised would come in 0.6.x or 0.7 that hasnt been finished yet". The
promises that are words, not features, from the inventory in ~/Downloads/sill-handoff/next/promises/INVENTORY.md
(rows 6 and 10).
- `site/support.html`, "Your Mac is locked": a third paragraph, after the switch's, as Noah promised on #316
  (2026-11-12: "I'll add the recovery route to the support page next to the switch's description"). Sill can't bring
  your account back to the screen (macOS asks for the password at the login window, which nothing Sill sends
  reaches, his reasoning on the issue); Screen Sharing from another Mac or a VNC app can, and has to be on
  beforehand (System Settings › General › Sharing). Checked against `LockPolicy` (input from nobody off console),
  `LockedMac`'s words, junkaiman's test of 2026-11-11 (the console back to his account, everything back with no
  reconnect) and macOS 27.2.1's own Screen Sharing (`ScreenSharing.framework`'s session choice, "Curtain Mode is
  unavailable at Login Window": it works at the login window).
- `site/contribute.html`: Hunter Ahlquist among the contributors (his stale-hover fix, issue #81, landed through
  #335 with his Co-authored-by and shipped in 0.6.1); a paragraph thanking Ash Hopkins (#66, Sill Viewer) and MAREI
  (#89, Sill for Android), whose pull requests are open and not part of Sill. Noah promised all three
  acknowledgement (#81, 2026-10-18 and 19; #90 and #66, 2026-10-18). How to credit unmerged work is his call.
- Not here: the release notes' line for Hunter (a draft for 0.6.3's notes, in the handoff's promises/drafts), the
  site's republish (sill-site, Noah's), the comments on #316 and #81 (drafts, his to post).
- Verified: both pages parse with every tag closed; their new links are the pull requests and profiles named.
  Untested for Noah: how the pages look once published.
