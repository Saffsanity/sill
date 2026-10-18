# The Full-Screen Viewer on an iPhone

A second arrangement for the iPhone's stream screen, as a VNC viewer has it: the Mac's picture
takes the whole screen and zooms, and the whole screen is the trackpad. Off by default (Settings ›
This iPhone › Full-Screen Viewer); with it off everything is as on main. Device only: no wire
change, nothing on the Mac.

## Why

On an iPhone the arrangements give the picture a part of the screen: upright a 16:10 pane over the
rows and the trackpad (docs/iphone-portrait-plan.md), Larger Picture's room above the keyboard
(docs/larger-picture-plan.md), sideways the bar over the picture. A Retina window's text at the
pane's 377 × 235 pt (an iPhone 15 Pro) is small, and nothing on the phone magnifies it but Aa, which
resizes the window on the Mac. A viewer that zooms the picture on the phone leaves the Mac's window
as it is and lets the person look closely at one part of it.

## What it does

- **The picture** fits the screen (letterboxed, `ViewerCamera.fitted`), held upright or sideways.
  Pinch zooms it, 1× to 8×, about the fingers: the point of the frame under them stays under them
  while they move, so a pinch zooms and pans at once (`ViewerCamera.pinch`). Along an axis where the
  picture is smaller than the screen it is centred; where it is larger its edge never leaves the
  screen's (`rect`).
- **Panning** follows the pointer: once the pointer comes within 44 pt of a side (a quarter of a
  small screen at most) along an axis where the picture is larger than the screen, the picture moves
  under it until the pointer is 44 pt in again, or the frame's own edge is reached (`follow`).
- **The trackpad** is the whole screen: `TrackpadSurface` as on the portrait trackpad (drag moves
  the pointer, tap clicks, two fingers scroll with their coast, two-finger tap right-clicks, press
  and hold drags, three fingers are the Mac's gestures), with two additions that only the viewer
  sets: the pointer's travel divided by the zoom (`travelScale`: zoomed in, a stroke moves the
  pointer as far on the screen as at 1×), and a pinch (`onPinch`) that takes a two-finger stroke over
  once the fingers have spread or closed by 8 % (`pinchCommit`): the scroll it had begun ends there
  without a coast, and the rest of the stroke zooms. Nothing else of the surface changes, and with
  `onPinch` nil (every other layout) it never sees a pinch.
- **The bar** at the top, over the picture: Windows (the Desktop and the window strip, with its
  held thumbnail's lights), Apps (the drawer), the Mac's Menus while it sends them, Keyboard, Keys
  (the key row's twelve caps, scrolling), Fill or Fit (`toggleFill`: the zoom at which the picture
  covers the screen, centred on the pointer, and back), Settings, and Hide, which leaves a tab at
  the top centre that brings it back (`Sill.viewerBarShown`).
- **Settings › This iPhone** has the switch (`Sill.viewerMode`, never sent) and a footnote. While it
  is on, Larger Picture's row is not offered (it arranges a screen the viewer replaces).
- **Not with the viewer:** the first-run tour (its cards point at the arrangements' controls), and
  the iPhone Duo's inner display (a hinge reported: the Duo keeps its layouts, docs/iphone-duo-plan.md).

## Open questions (the default taken)

1. On by default? **Off**: it changes how every touch works (no tap where the finger is; the
   pointer moves relatively), so it is the person's choice.
2. The switch applies at once, with the Settings panel open (the panel is drawn by the other
   arrangement after it). Larger Picture holds its change until the panel closes
   (`largerPictureHeld`); the viewer could do the same. **At once** for now.
3. The tour in the viewer: **none**. Its cards would need their own targets in the bar.
4. Sideways too, or upright only? **Both**: the picture is larger sideways, and the bar fits.
5. Double-tap to Fill or Fit, as photo viewers do? **No**: a double tap is the Mac's double-click.

## Results

- `Tests/checks/viewer-camera` (CI's matrix): pinned cases on an iPhone 15 Pro and 17 Pro Max,
  upright and sideways, a 16:10 and a tall frame (fit, fill, the edge push, a pinch that zooms and
  pans, Fit again, before the first frame, a frame arriving and a rotation while zoomed), then
  2,000 seeded random sessions of 40 steps with the rules checked after each: 466,423 checks; 19 of
  19 mutants caught. It found, before the change was kept, a fitted picture 393.0000001 pt wide on a
  393 pt screen that the edge push then moved (`ViewerCamera.slack`).
- The iOS app, Debug for the simulator, with only the known `StreamClient` warning (built with
  Xcode 27.0 and `DuoPostureReader`'s hinge calls left out for that SDK alone; CI builds it whole
  with 27.1).
- Live on a private iPhone 18 Pro Max simulator (iOS 27.0, deleted after) against `SillHost
  --synthetic` on loopback with the software encoder (`-SillConnect`, `-Sill.viewerMode 1`): the
  picture fitted and, with `-SillViewerZoom 2.5` (DEBUG), zoomed with Fit in the bar; the harness's
  Settings panel with the switch and the drawer under the bar.

## Untested, on an iPhone

- Pinch to zoom and back, with the pointer moving: no stray scroll on the Mac at the pinch's start
  (the 8 % before it commits), no click at its end.
- One-finger strokes zoomed in: the pointer as fine as the zoom, the picture following at the
  edges, smoothly, in both directions; a drag (press and hold) that runs into the edge.
- Fill and Fit upright and sideways; rotation while zoomed; a window picked while zoomed (another
  shape).
- The software keyboard up over the picture; Keys' latched modifiers with a click; Menus; the
  window strip's lights and drag.
- VoiceOver in the bar (each button labelled), and the hidden bar's tab.
- Five minutes zoomed in on a busy window: frame age and rtt as without the viewer.
