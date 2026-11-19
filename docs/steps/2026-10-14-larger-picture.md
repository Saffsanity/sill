**Larger Picture on an iPhone held upright (2026-10-14, branch `larger-picture` from main at 985a733,
PR #79; issue #58, promised to rosstex; docs/larger-picture-plan.md has the rule, the numbers, the
open questions with their defaults, the results and the review's fixes).** "The menu and touchpad
take up more than half of the vertical space." Device only: no wire change, nothing on the host.
Since Noah's test on his iPhone 15 Pro (2026-10-15: "when in Desktop mode, there is negative space
on the bottom, seemingly because of the Mac aspect ratio. Can we disable this feature when Desktop
mode is active?") it applies only while a window streams (the bullet "Only while a window streams").
- Settings › This iPhone: **Larger Picture** (off by default; `Sill.largerPicture`,
  `StreamClient.largerPictureKey`, never sent; offered only on an iPhone without a hinge whose
  picture it makes larger: the environment's `largerPictureOffered`, from
  `PhonePortraitLayout.offersLargerPicture(screen:)`, judged upright whichever way the phone is
  held). With it on, a phone held upright (`PhonePortraitLayout(size:keyboard:)`) has, while a
  window streams, no thumbnails' row; the picture's room is every point that keeps the key row
  10 pt above the software keyboard (H − K − 152: 18 Pro Max 424×265 → 424×422, 15 Pro 377×235 →
  377×340, SE 359×224 → 359×262); the trackpad is the keyboard's footprint, so nothing moves when it comes up;
  row 1 takes the Menus button after Apps while the Mac sent menus (`buttonsBesideMenus`); the pane
  is the picture's own shape at the top of the room (`pane(video:)`), the viewport the whole room
  (one new viewport per switch: the Mac fits a window to it once Aa is set, or on the virtual
  display), the trackpad's span the picture's shape (`trackpadSpan(video:)`). Windows come from Apps
  (an open app again shows its next window) and Menus › Window. The Apps drawer opens above row 1,
  over the room (`drawer`), so no keyboard covers it, the Mac's or its search field's, and VoiceOver
  reads it after row 1 (PortraitStreamScreen's `AfterRow1`). A change of the switch shows when the
  Settings panel closes (`StreamScreen.largerPictureHeld`), so the panel never moves under the
  finger. Sideways, on an iPad and switched off, everything is main's.
- Only while a window streams (Noah's test, 2026-10-15; the plan's rule 12, open questions 12 to 14,
  Results "The Desktop keeps the standard arrangement"): one pure function of the switch and of
  what streams, `PhonePortraitLayout.largerPicture(switchOn:streaming:)` (`Streaming`: nothing,
  desktop, window; StreamScreen maps `client.active` and computes `largerPictureNow`), put in front
  of `keyboard(for:largerPicture:foldable:)`, so the arrangement, its viewport and the tour's
  targets, words and room all follow it. The Desktop keeps the standard arrangement (Aa never
  resizes it: on the 15 Pro its 377×244 frame left 96 pt of the 377×340 room black, on the Pro Max
  147 of 422), and so does nothing streaming (connecting; a window closed, until the Desktop the
  device asks for; a pick that failed), so the Desktop's first picture never arrives into a layout
  that then flips; the Mac never reports nothing between two windows. The Settings panel holds the
  arrangement (Larger Picture in effect when it opened), so a change of what streams while it is
  open waits for it to close too; its footnote: "Held upright, a window’s picture takes the place of
  the window thumbnails and reaches down to where the keyboard comes up. The Desktop keeps the
  thumbnails. … A change applies when you close Settings." A switch between the Desktop and a window
  sends a new viewport (twice, the source change's repeat and the arrangement's, the second a no-op
  on the Mac): with Aa set the Mac fits a window picked from the Desktop to the 16:10 pane, then to
  the room, one restart at most, as a rotation's. A thumbnail's lights close when the arrangement
  changes under them (they hang from the strip). The Duo's cover as before. Verified: `phone-portrait`
  484 checks and 73 of 73 mutants (5 of the rule), `tour` 111,189 and 84 of 84 (4 of the rule, in
  PhonePortraitLayout.swift); the three iOS builds, only the known `StreamClient` warning
  (StreamClient.swift:3436); `run-all.sh`, all 40; on a private 18 Pro Max simulator, harness photos
  at its own stream screen and the 15 Pro's: the Desktop and nothing with the switch on pixel for
  pixel the switch off (plain, drawer, ruler, the tour's bar card; Settings but the switch), a window
  pixel for pixel the branch's before the change (Settings but the footnote); live against a
  synthetic host with a test client switching between the Desktop and a test window of the agent's
  own: `viewport: 424×422 pt` with the window, `424×265` with the Desktop, one restart on the first
  pick with Aa at 1× (none on the second, none back to the Desktop), none without Aa.
- Only where it is larger (`largerPictureGains`: the room taller than today's picture and row 1's
  six buttons 44 pt or more, `minButtonWidth`): Display Zoom's 320 pt (an SE, a mini, a 6.1-inch
  iPhone; a 6.1-inch one's room would be 304×173 against today's 304×190) keeps today's layout and
  has no switch; the zoomed 6.7-inch and 6.9-inch phones take it with the estimate (unmeasured).
- The keyboard K, measured on every iPhone size the iOS 27 simulators have and estimated from the
  stream screen's shape and width (`keyboardHeight(for:)`): 233 with a Home button; with Face ID 320
  from 414 pt wide, 301 from 390, 310 from 375 (the minis; the 11 Pro's is 301), 320 narrower. The
  portrait plan's SE (216) was wrong: its keyboard is 233, so the usual arrangement's SE key row is
  24 pt under it (the plan said 7). On the iPhone Duo none (`keyboard(for:largerPicture:foldable:)`,
  a hinge): the switch hidden, the cover as it was (its keyboard never measured).
- The tour: `TourTarget.apps` (row 1's Apps); without thumbnails (`thumbnails:` on `targets` and
  `copy`) the bar card lights Apps, Aa and Keyboard and its first row is about Apps; upright cards
  are placed against the picture's room (`TourPolicy.place`'s `room`, TourOverlay's), so a card
  stands under a short picture with its tail at row 1. TourLayout stays `.phone` (switching is no
  turn). DEBUG: `-Sill.largerPicture 1`, `-SillVideoSize WxH`, `-SillLargerPictureToggle`,
  `-SillDrawerSearch <text>`, `-SillAXDump` (the accessibility tree's order; a private simulator's
  `ApplicationAccessibilityEnabled` first), the console's `trackpad:` and `keyboard:` lines.
- The review (2026-10-14; five findings, all holding, one commit per theme): the drawer, under row
  1, kept only its search field above a keyboard (62 pt on every phone): now above row 1 (77abae3,
  d6322a9); Display Zoom made the picture smaller: now rule 10 (0e9aa0e); six 42 pt buttons at
  320 pt: gone with it; the switch moved 118 to 157 pt from under the finger: now it applies as
  Settings closes (0cbe883); docs. Not done: a Large Content Viewer on row 1's Menus button, a
  UIKit pull-down in every bar on main too (needs a device).
- Verified (the plan's Results): the three iOS builds, only the known `StreamClient` warning;
  `swift build -c release`; `run-all.sh`, all 40; `phone-portrait` 401 checks and 68 of 68
  mutants, `tour` 111,079 and 80 of 80; before the review, harness photos with the switch off
  against main's build (25 of 33 identical, the rest the lights' wiggle and the panel's new row),
  59 with it on (the bare layout within 1 px at 3x), live on 14 iPhone simulators against a
  synthetic host (the key row 10 pt above the real keyboard, one viewport per switch); after it,
  13 harness photos against main's (10 identical, 2 the simulator's home indicator, 1 the panel's
  scroll indicator: Display Zoom's 320 pt, the Duo's cover, sideways and the switch off as main's),
  live on the 18 Pro Max, the 15 Pro and the SE the whole drawer above the Mac's keyboard and its
  search field's, to the pixel, the switch flipped with Settings open moving nothing until it
  closed (then one viewport), and VoiceOver's order with the drawer open: row 1, then the drawer.
  Photos in `~/Downloads/sill-handoff/larger-picture/` (`review-fixes/` for the review's).
- **Untested, for Noah (the plan's P list), on the iPhone 15 Pro with this build:** with the switch
  on, the Desktop as with it off (no black under it), a window picked: Larger Picture as it appears
  (with Aa set the window grows into the room a moment later), the Desktop again: the thumbnails
  back, a window closed on the Mac: the thumbnails back, then the Desktop; Settings ›
  This iPhone › Larger Picture on and off with Notes and Chrome streaming (the change as Settings
  closes; a 16:10 window keeps its shape, black under it; Aa, then any size, fits it to the taller
  picture; a window taller than 16:10 gains at once); the keyboard up and down (esc to shift 10 pt
  above it, nothing moves, row 1's Keyboard takes it down; with a Debug build Xcode's console
  prints `keyboard: up, 301 pt tall …`); windows from Apps (an open app twice) and from Menus ›
  Window; Apps with the keyboard up, and a search in it (the whole list above the keyboard);
  rotation both ways; the tour on a fresh install with the switch on; VoiceOver's order, the drawer
  open too; an input method's keyboard (a candidate bar can cover the key row, never row 1); Display
  Zoom on (Settings › Display & Brightness › Display Zoom): no switch on a 6.1-inch iPhone; the
  Menus button in row 1 at an accessibility text size (a long press: no Large Content Viewer yet).
  On iOS 17 or 18, if an iPhone with one is at hand, the keyboard's height (every height here is
  iOS 27's). On a Duo from October 23: no switch, the cover as before.
