**The hold before a thumbnail's lights (2026-10-29, branch `thumbnail-hold-stepper` from main at 35a9c47, PR #248; issue #113,
promised on the issue as "lower the time … and have it be user adjustable").** Noah, 2026-10-29: "The hold time should
be patched and editable with a slider in settings (one of those fancy ones with the +/- buttons that increment by 0.1
seconds, ideally the timer can go from 0.2s to 3s or something like that." Device only: no wire change, never sent.
- `ThumbnailHold` (pure, `Tests/checks/thumbnail-hold`, 82 checks and 32 mutants, in CI's matrix): 0.2 to 2 s in
  tenths, 0.5 s unless changed (it was a fixed 1.5 s; iOS's own long press, which the reporter cites), counted in whole
  tenths so no sum of steps drifts; `Sill.thumbnailHold` (a Double; `-Sill.thumbnailHold 0.3`'s string too); the words.
- WindowStrip reads it at launch and on each change (every bar: sideways, an iPad's window bar, a phone's row 2), and
  HoldDragOverlay gives the long press already on screen the new length; the drag to another slot starts from the
  same hold. Its 12 pt (a scroll before the hold) and 8 pt (the lift after it), and the picture's 0.45 s right click,
  are unchanged. DEBUG: the console's `thumbnails: hold 0.5 s` at the first read and each change.
- Settings › This iPad (or iPhone), after Reverse Scrolling: Hold to Show Window Controls, its length ("0.5 s") and
  the system's stepper (− dimmed at 0.2, + at 3), the title beside them while it has room for its three lines with
  every word whole (`ThumbnailHold.titleLines`; ViewThatFits and a small Layout, `WrappingTitle`), else over them, and
  the row never wider than the panel offers it; one adjustable VoiceOver element,
  "Hold to show window controls, 0.5 seconds" (iOS 27's stepper alone is two buttons read with the whole label), its
  footnote next. `-SillSettingsScroll hold`. Site words (support's section, privacy's item) marked `<!-- Thumbnail
  hold`; the next What's New's paragraph. Not taken from the branch `thumbnail-hold` (2026-10-20, 1 to 5 s, never a
  pull request): its pressed state from touch-down and its fix of the lights' VoiceOver labels; #164 (addhumal, a
  picker of five lengths) predates Noah's stepper.
- Verified: the three iOS builds and `swift build -c release`, only the known warnings; `run-all.sh`, all 57; on a
  private iPhone Duo simulator (iOS 27.1, the cover display: the harness draws 1000x710 at 0.65, turned), with a driver
  injected into the Debug app (the touch rig's synthesized touches; the scratchpad's, not committed): a press at the
  default began the hold 0.505 s after touch-down and showed the lights, 0.35 s was a tap; at 0.2 s 0.205 and a 0.1 s
  tap; at 3 s 3.008 and nothing at 2.75; main's build 1.510 and nothing at 1.3; a change while the strip showed (1.2
  s) reached the thumbnails at once; drags to another slot at 0.5 and 0.2 s; a swipe across the strip still scrolls at
  both; VoiceOver's swipe up and down a tenth each way, held at 0.2 and 3 s. Photos at 1000x710, 710x1000 and 500x710,
  default and accessibility-extra-large: the bars and the panel's top main's to the pixel but one switch's knob edge
  (9 px at Δ1), the panel above the new row within Δ1. Live against a loopback synthetic host (no screen, software
  encoder): the row changed five times, nothing reached the host.
- The review (2026-10-29; the report's "The review"; an earlier pass, cut off after its first two commits, then this
  one): three findings, each reproduced on a private iPhone Duo simulator (iOS 27.1) against ae3d412's and main's
  builds and fixed in a commit of its own. In a narrow panel the title squeezed beside the stepper (an iPad window as
  narrow as Slide Over, 320x951, and a 320 pt iPhone, 320x693: four lines at the default size, seven at xxLarge with
  "Win-dow" and "Con-trols"; the cover on its side at xxLarge: four); it stacks now (eb56ca7; the check's 82 and 32
  with it). On the cover upright at xxLarge the row came to 298.333 pt in 298 (its lines rounded to the pixel at the
  edge of fitting) and `rowFrame`'s frame, a maximum alone, passed that on: every row of the panel and its edge a
  third of a point over, the panel's top 17,442 px from main's (accessibility frames 298.333 against 298); the row's
  frame now takes what it is offered (3152061). A comment still said 1.5 s (661624a). Re-run on the final code: the
  three iOS builds clean, only the known warning; `run-all.sh`, all 57 (493 s); the check 82 and 32 of 32 mutants;
  `swift build -c release`, only the CaptureProbe warning; photos in the Duo's six poses against main's build (the
  bars, the panel's top and the panel above the new row main's, but for Δ1–2 that retakes show as noise or as 148 px
  at Δ1 on the halves' switch, as before), the narrow panels stacked, the row elsewhere ae3d412's to the pixel but for
  the cover upright at xxLarge, its panel's edge main's again; the rig on every bar (sideways, the halves, a 320 pt
  iPad window's sliver of a thumbnail, the laptop and book poses, the cover upright and on its side): the hold began
  0.505–0.507 s into the press, 0.205 at 0.2 s, 3.009 at 3 s, main 1.505; VoiceOver's steps and ends, the stepper's
  taps, a relaunch keeping 0.6 s, a Mac without kind 16; live through a recording relay, the row changed seven times
  and the device sent only pings and its stats meanwhile.
- **Untested, for Noah:** on the iPad and iPhone, a thumbnail's lights at half a second and the drag after them;
  Settings › This iPad's stepper from 0.2 to 2 s and a hold at each end; a swipe across the strip at 0.2 s (no lights);
  VoiceOver's reading and its swipes; the row at the largest text sizes (the panel stops at xxLarge: the title in three
  lines beside the stepper, over it in a narrow panel, an iPad window in Slide Over or a phone with Display Zoom); Voice
  Control, Switch Control and Full Keyboard Access on the row (one adjustable element: its − and + are no elements of
  their own); a Magic Keyboard trackpad's or a mouse's click and hold on a thumbnail.
