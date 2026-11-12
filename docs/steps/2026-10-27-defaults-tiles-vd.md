**Tiles, Virtual Display and Send Audio on by default (2026-10-27, branch `defaults-tiles-vd` from main at
3c257485, fast-forwarded to 3b546374 (#234) before its first commit; PR #236).** Noah, 2026-10-27:
"make tiles not list the default behavior of the app. Also have Virtual Desktop on by default. Of
course, if a user changes a setting remember their choice for future sessions as you do now. Make
this a separate PR after #117 merges." Later that morning, testing #235: "Send Audio should be on
by default, and mute should be off by default." No wire change.
- Sill.app's Send Audio is on by default too (`HostConfig.app.sendAudio`; the CLI's `--audio` still
  opts in; a saved `sendAudio` wins, so a Mac whose user turned it off stays off): the menu's
  checkmark and Settings › Streaming's switch start on; README's Good to know, support.html's Sound
  section and privacy.html say so. Mute on the device was off by default already (#235).
- The device: the connect screen shows tiles unless its person chose the list
  (`ConnectionList.defaultStyle`, `storedStyle`: a stored `Sill.connectionStyle`, "list" or "tiles",
  always wins; nothing stored, or a value no build writes, reads as tiles). ConnectScreen keeps the
  key optional (`@AppStorage … String?`), so the rule alone decides, as StreamClient's
  `connectionStyle` already did. So a picture of each saved Mac's screen is kept by default
  (`takesPreview`, unchanged: only with tiles), and Disconnect asks for its fresh keyframe by default
  (300 ms at most before the connect screen with Sill for Mac 0.5.1, which skips kind 44). The switch
  beside the title always shows, whichever style is on and whether or not a Mac is listed (Noah,
  2026-10-27: "The list/tiles switch should always show"; #117 showed it for tiles alone, which with
  tiles the default took it away under the finger of someone with no saved Mac who chose the list).
  DEBUG: `-SillStyleToggleAt <s>[,<s>…]` toggles the style as
  the switch does (`toggleStyle`); the console's `connect:` lines.
- The Mac: Sill.app registers `HostConfig.app` (HostSettings), the CLI's `standard` with the virtual
  display on. Registered, never written: a `virtualDisplay` key set from the menu, Settings ›
  Virtual Display or a device always wins (a Mac that turned it off stays off; this Mac's own keys read 1 for
  both on 2026-10-27, set by hand, so nothing changes here), and `-virtualDisplay 0` turns it off for one run. The CLI keeps `standard`: `--virtual-display`
  opt-in, its stdout byte for byte. The menu's checkmark and the pane's switch follow `config`; no
  pane names the default.
- The virtual display at 1x, the caveat of that decision: not in the session of 2026-10-26/27.
  Beside the 2560×1440 display at 1x every staged capture that night read "scale 2.0" (`filter
  (1456.0, 1486.0)`, `(2560.0, 1486.0)`, `(2560.0, 2264.0)`); its "scale 1.0" captures were real
  windows and the Desktop on that display (#233's case). Sill.log's 1x displays were five earlier
  ones (2026-09-26, 09-28, 10-08 twice, 10-15), each asked with both sides under 800 points, 754×784
  or 762×792: an iPhone held upright (its 377- or 381-point picture doubled for Aa's smallest step)
  and the menu bar, beside the Mac's own Retina display too, so the main display's scale played no
  part. macOS listed the 2x mode asked for, `selectRequestedMode` asked for it every half second,
  and the display stayed at 800×832 points at 1x until the stage's 3 s wait ran out ("online 3312
  ms"): the pick waited 3 s more, and the staged window was captured at 2x from a 1x display (eleven
  captures `filter (800.0, 832.0) scale 1.0`). Every display with a side of 800 points or more came
  up at 2x (754×979, 838×792, 900×800, 1000×784, 848×878 and larger). The fix, `VirtualDisplaySize`
  (pure, in CaptureScale.swift, checked by `Tests/checks/capture-scale`): every side 800 to 4096
  points, so an iPhone upright gets 800×830; VirtualStage's `envelope` and `ensureDisplay` use it.
  The creation line prints the mode the display came up at (`VirtualDisplay.currentScale`; it said
  "@2×" whatever came up), and `--virtual-display-selftest [Hz] [WxH]` makes another size.
- Words: README (How it works: the connect screen's tiles, On iPhone, Text size and the virtual
  display with it on by default; Good to know), site/support.html (a section, "A window left your
  Mac’s screen", whose sentence on the default is marked `<!-- Virtual Display` for its release; "It
  says Not paired"), site/privacy.html (the tiles' items: kept unless the list is chosen; "touch and
  hold it"; dated October 27, 2026; the virtual display needs no word there, Accessibility "so Sill
  can move and size the window it shows" says it already), docs/release-checklist.md (the marker,
  its perl line and grep), docs/app-store-metadata.md (the description's "Your Mac shows up.", 3,032
  characters; the next What's New's tiles paragraph, 232, the draft 1,805), docs/DEVELOPMENT.md, the
  checks README.
- Verified: `swift build -c release`, only the CaptureProbe warning; `Tests/checks/run-all.sh`, all
  55 (562 s); mutants: connection-list 162 checks and 76 of 76, capture-scale 148 and 39 of 39,
  away-quality 96 and 30 of 30 (after #235's merge: its acceptance mutants and the app defaults'), virtual-display-api (VirtualDisplay.swift changed) 17 of 17; H2
  against main at 3b546374 from `git archive`, `--synthetic` on loopback (software encoder, no
  router, no screen): idle 35 s identical masked and sorted (8 lines), with `sillclient.py PORT 8
  desktop` identical (23 lines; a first pair differed only in which counters three stats lines
  listed, `cursor.shape` among them); the bare SillMenuBar `--synthetic` (domain deleted before and
  after): no key, "Virtual display: private CGVirtualDisplay API present…" and "✓ Virtual Display";
  `-SillSetAfter '2 virtualDisplay=0'`, one "Settings: virtual display on → off" and the key 0; a
  relaunch, off; `-virtualDisplay 1`, on for the run, the key still 0; main's binary with no key,
  off; previews from both bare binaries at one path, 146 files each, only `menu.txt` (the
  update-available sample's ✓ Virtual Display and ✓ Send Audio (Beta)), `pane-virtualDisplay-light.png`,
  `-dark.png`, `pane-streaming-light.png` and `-dark.png` differ, each pane only in its switch; the iOS app
  with Xcode 27.1 (27A9275), Debug for the generic simulator as CI builds it, Release for the
  simulator, Debug for a device, only the known StreamClient capture warning
  (StreamClient.swift:4110); on a private iPhone Duo simulator on iOS 27.1 (its cover display), the
  29 connect cases at 466×678 and 951×669 against main's Debug build: this build with nothing stored
  and main's with tiles stored, 57 of 58 pixel for pixel (the 58th the pairing case's spinner, which
  differs from itself); this build with the list stored and main's with nothing stored, 44 of 58, the
  rest the switch beside the title, which this build always shows (the verifier's photos of 04c9f226;
  the author's, before 70423d1a, had the switch only with a saved Mac listed); the normal app, a fresh install against a synthetic host
  registered as `_silltest._tcp`: tiles, toggled to the list (stored "list"), a relaunch the list,
  toggled back (stored "tiles"), a relaunch tiles, the key read from the app's container plist
  (`simctl spawn … defaults read <container>/Library/Preferences/me.saffer.sill.plist`; the domain by
  name reads elsewhere); `SillHost --virtual-display-selftest 60 800x830` once, at 05:05 with this
  Mac idle 601 s and no device connected: online at the requested mode in 446 ms, 1600×1660 px @2×,
  a 30-point menu bar, gone 158 ms after (its HID move reset the idle time). Not run: Sill.app,
  anything with a device, a staged window on 800×830.
- **Untested, for Noah:** on the iPad with this build, a fresh install (Sill deleted first) shows
  tiles; once a Mac is paired the switch beside the title shows; to the list, quit Sill from the app
  switcher and reopen: the list; back to tiles, reopen: tiles; an install that chose the list keeps it.
  On a Mac whose `virtualDisplay` was never set (another Mac or user account, or, with Sill quit,
  `defaults delete me.saffer.sill.mac virtualDisplay sendAudio`; this Mac's read 1, set by hand, so it
  is on here already): the menu shows ✓ Virtual Display and ✓ Send Audio (Beta), a device hears the
  Mac's sound at once (beside the Mac it doubles every sound a moment late until Mute), a window
  picked moves onto the virtual display (Sill.log "Virtual
  display … @2× id …: created", "Moved …", "Capturing … of virtual display") and comes back at
  Disconnect; the switch turned off stays off after a relaunch. With the iPhone 15 Pro upright and
  the virtual display on, a pick's display is "Virtual display 800×830 pt @2×" with no "online but not
  at" line, and the window's text crisp.
