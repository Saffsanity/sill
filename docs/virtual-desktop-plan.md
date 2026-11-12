# The Virtual Desktop: the plan

2026-11-11. Branch `virtual-desktop-plan` (worktree `~/Downloads/wt-virtual-desktop`) from origin/main at dd6ea6a.
A plan only: no feature code. Line numbers are at dd6ea6a. Nothing was measured for it: no virtual display was made,
no display arrangement changed and the hardware encoder was not used; every number below is quoted from CLAUDE.md,
from Sill.log as CLAUDE.md records it, or from a contributor's report, and says which.

**"Virtual Desktop" is a working name.** Noah: "We can workshop the name but for now its a good placeholder." It is
written throughout as the name; the code keeps it in one place per app (§14), and §14 has the candidates to choose from.

**Noah's request (2026-11-11):**

> 1. Sill can have its own dedicated virtual desktop display, that by default is the same resolution and refresh rate
>    of the Mac's primary display, with customizable resolution and refresh rate (ideally can hit at least 4K 120Hz,
>    ideally the cap is whatever a particular Mac and its encoder can handle and what is allowed at the OS level). Sill
>    ships with this setting off by default.
> 2. For users with multiple monitors, the desktop button will toggle which desktop is being shown. E.g. I have Sill
>    virtual desktop enabled (the feature listed in #1) and have 2 monitors attached and the laptop is open, it will
>    default to my default monitor, then toggle through each monitor, then the virtual desktop.

**Agreed the same day** ("I agree with all of your suggestions. Virtual Desktop is a better name."): the name, which
must read as a different thing from the existing Virtual Display everywhere; one mechanism for every display Sill
makes to carry the Desktop, not a fourth; the encoder as the real limit; the Virtual Desktop existing only while a
device shows it, plus a short grace, never for the whole run of Sill; a third size choice, Match this device; the
Desktop button's cycle (the default monitor, each other monitor, then the Virtual Desktop), showing which one is up,
the choice remembered; the wire additive; four phases, each a pull request with its gates, #200 merging first as it
is; off by default, a Mac-side setting.

**Changed later that day:** "My only difference is that instead of measuring, choose one of the default display
resolution and refresh rate of the primary display or 4K 60Hz, whatever is less." So Sill measures nothing: no
capability stored, no probe run, no size offered or greyed by a measurement. The default is the main display's own
resolution and refresh rate, never more than 4K and never more than 60 Hz (§2). Custom sizes and rates stay, as the
person's own choice from a fixed list, with plain words about what a Mac may not hold (§3). The measurement script
this plan was first to deliver is dropped with it; the runs the build still needs on a real Mac (the existing self
test at each size, a window probe) are in each phase's gates, with the conditions they run under.

## The decisions that are Noah's (each has the default this plan takes until he says otherwise)

1. **What "whatever is less" means.** Default (a), the reading he was given: the size and the rate are each held to
   their own cap. The Virtual Desktop takes the main display's own mode, its picture held inside 3840 × 2160 pixels
   (its shape kept) and its rate to 60 Hz: a 14-inch MacBook Pro (3024 × 1964 pixels at 120 Hz) gives 3024 × 1964 at
   60. **(b)**, the other reading: whichever of the two whole modes is the lighter load, pixels times rate. The 14-inch's
   own mode is 713 million pixels a second (3024 × 1964 × 120), 4K at 60 is 498 million, so it would get 3840 × 2160 at
   60, a 16:9 desktop beside its 1.54:1 screen; so would an ultrawide at 144 Hz, a 60 Hz 5K display and most
   ProMotion Macs. A smaller variant of (a), **(a′)**: "4K" as a count of pixels (8.3 million) rather than a box. The
   16-inch MacBook Pro then keeps its own 1728 × 1117 points (3456 × 2234 pixels is 7.7 million, but its 2234 rows
   are more than 2160, so the box trims it to 1670 × 1080), and a 49-inch 5120 × 1440 ultrawide keeps its own (the
   box trims it to 3840 × 1080).
2. **The contributors' pull requests: build on their branches, or start fresh with credit.** Default: **phase 1 is
   built on #173** (addhumal's commits merged in as they are, with addhumal's own `reconcile-173-200` resolution
   against #200, and this plan's changes as maintainer commits on top, so the phase's merge marks #173 merged, as
   #223, #228 and #230 were); **#200 merges first as it is** and phase 2 moves it under the manager without changing
   what it does; **#312, #156 and #225 are credited, not merged**: phase 4 takes dr-apple's sizing and lifetime from
   #156/#312, lepeos's device-side rule from #312, and addhumal's sizing from #225, with `Co-authored-by` in the
   commits that take them, a line in the pull request and on contribute.html, and Noah closes them pointing at the
   phase. Their host halves make the device's display the Mac's main display and give it an identity of its own, both
   of which this plan does differently (§7, §9), so carrying their commits unchanged would mean merging code only to
   delete it. The other ways: every phase fresh from main with credit only (cleaner history; #173 not marked merged),
   or each contributor asked to rebase onto the plan (slowest, and the plan changes #173's order and label).
3. **What a device may change.** Default: **the Mac's alone**, as Share clipboard, Remote Access and the off-console
   view are. A device reaches the Virtual Desktop once it is on (a step is a pick, not a setting) and its Settings
   panel shows whether it is on and at what size, read-only; it cannot turn it on or change its size or rate. The
   Virtual Desktop adds a display to the Mac's own arrangement, where the person at the Mac can lose the pointer and
   windows: that is the Mac's environment, not the stream's quality. The precedent the other way: a device turns
   Virtual Display on and off today (full parity with the Mac's menu, 2026-09-23), and that moves windows off the
   Mac's screen too.
4. **Windows left on it, and the grace.** Default: **30 seconds** after the last device stopped showing it, Sill moves
   its windows to the main display (each at the same place relative to the screen, its size kept), removes it, and
   puts them back where they were when it comes back in the same run of Sill, unless the person at the Mac has moved
   or resized them meanwhile (§6). The other way: let macOS place them when the display goes, and nothing comes back.
   A longer grace means fewer display changes (#333's monitor that switches itself off at one) and a phantom display
   for longer; 30 s is what #344's fork chose for a reconnect.

And the name, whenever he likes (§14).

## The design on one page

- **The stops.** The Desktop shows one stop at a time: the Mac's main display first, then each other monitor in the
  order they sit (to the right of the main display, wrapping round to the leftmost; top to bottom where they stack),
  then the Virtual Desktop when its setting is on. A tap on the Desktop button while the Desktop streams moves the
  stream to the next stop; while a window streams, the button brings the Desktop back on the stop it last showed. The
  button shows which stop is up and that there is a next one. With one stop (one monitor and the setting off, a Mac
  with no working screen, a locked Mac, another user on the screen, a Mac from before this) it is today's button.
- **The Virtual Desktop.** A display of Sill's own, made when a device steps onto it and removed 30 s after no device
  shows it. By default it has the main display's resolution (its points and its pixel scale) and refresh rate, never
  more than 3840 × 2160 pixels (its shape kept) and never more than 60 Hz. Phase 3 lets the person choose another size
  and rate from a fixed list; phase 4 adds Match this device. Windows put there stay while it is shown; when it goes
  they move to the main display, and they come back when it does.
- **One manager.** Every display Sill makes is made, recognised, tracked and removed by one manager: the window
  stage's (Virtual Display) and the Desktop's. The Desktop's is one display with one identity in all its roles: #200's
  display for a Mac with no working screen, the Virtual Desktop, a matched one. The stage's stays a display of its own.
- **Nothing measured.** At run time the encoder does what it does today: a frame it is not ready for is dropped
  before it queues, a session that slows down for good is replaced, a stalled one hands the stream to the software
  encoder. The words say plainly that a larger size or 120 Hz may not keep its full frame rate on every Mac.
- **Additive wire.** The window list gains four optional fields (`desktopDisplays`, `desktopDisplay`, `desktopVirtual`,
  `desktopDisplayNames`) and the device gains kind 47 ("the next stop"), sent only to a host that lists two stops or
  more. `StreamSource` keeps its three cases: `.desktop` is the Desktop on whichever stop the host shows.

## What exists, and what each pull request gives

### Today (main at dd6ea6a)

- **The Desktop's display** is `WindowCatalog.display` (WindowCatalog.swift:304–306): the main display only while
  Virtual Display is on (`preferMainDisplay`, there so the Desktop never captures Sill's own display), else the first
  display ScreenCaptureKit lists, which is not always the main one: #345, an iPad used as an extended display shown
  instead of the main one. Its rectangle is where input lands (`currentSourceRect`, StreamCoordinator.swift:1661)
  and where the Mac's pointer is judged (`pointerGeometry`, :1706); its filter is also the Desktop's sound's
  (`makeAudioSource`, :2881).
- **The stream's rate** is the devices' (`wantedFPS`, :30: the highest any device asks, held to 24 and to the Mac's
  Frame Rate limit), never the shown display's: a 120 Hz iPad on a 60 Hz monitor's Desktop sets the encoder and its
  bitrate for 120 (Extreme: 300 Mbps) while the capture can deliver at most 60 (`startPipeline`, :2263–2296).
- **The window stage** (VirtualStage, the Virtual Display setting, on by default in Sill.app since 0.5.5): one
  `CGVirtualDisplay` named "Sill" (vendor 0x5111, product 0x0001, serial 1), at 2x, at the stream's rate, sized to an
  envelope of the device's panel (800 to 4096 points a side: VirtualDisplaySize), made when a window is staged and
  removed when none is.
- **What is measured about the private API** (CLAUDE.md; this M2 Pro on macOS 27 unless said): a 1000 × 700 @2x
  display made in about 150 ms, online after about 250 ms, removed in about 60 ms; online at 120 Hz
  (`--virtual-display-selftest 120`); 800 × 830 online at 2x in 446 ms; every display with both sides under 800 points
  came up at 1x (five in Sill.log); the largest Sill has made, 2560 × 2264 points at 2x (5120 × 4528 pixels), was
  captured at 2x (2026-10-26/27); without Screen Recording, ScreenCaptureKit's content call never returns while a
  virtual display exists, so none is made without it; one made while another user holds the console never comes
  online and joins that user's displays (docs/off-console-plan.md). Users ran the self test on two Intel Macs and the
  display came up (#87, a 2018 Mac mini on macOS 15.7.3; #62, an OpenCore i9 on macOS 26.7.1). #200 made 1800 × 1168
  @2x in 0.5 s on an M4 Pro with its lid closed.

### The pull requests and issues this plan covers

- **#173** (addhumal; open, conflicts with main): the Desktop button steps through the Mac's real displays (kind 47
  `nextDisplay`, `WindowList.desktopDisplays` and `desktopDisplay`, "Desktop 2"), the choice kept by the display's
  UUID, input on the display the capture runs on, back to the old display when the new one won't stream, the Mac's
  pointer to the new display's centre, refused while locked; `desktop-displays` 56 checks and 31 mutants;
  xiaofeng-han on three monitors: "working well". **Reused**, as phase 1's base: `DesktopDisplays` (resolve by UUID,
  next, `afterStep`, `landing`, `pointerTarget`), kind 47 and the two fields, the catalog's candidates and restart,
  `nextDesktopDisplay`, the lock rules and every check. **Changed**: the numbering (from the leftmost display becomes
  from the main display), the label ("Desktop 2" becomes the stop's label with dots, and a symbol of its own for the
  Virtual Desktop), the first stop with Virtual Display off (it keeps `displays.first`, so #345 stays), the capture
  while locked (the main display), kind 47 counted as a person at the device (§1).
- **#296** (addhumal; on top of #173): hold Desktop for a list of the displays by name (`desktopDisplayNames`, kind 47
  `{"number": n}`). **Reused**: `desktopDisplayNames` in phase 1, for VoiceOver; the list itself after phase 1, as its
  own pull request (Noah decided the tap; the hold is #273's ask).
- **#200** (addhumal; merging first, as it is): a Mac with no working screen (the lid closed and nothing attached, a
  Mac mini with no monitor, a closed lid whose monitors sleep) gets Sill's own display for the Desktop ("Sill Desktop",
  vendor 0x5111, product 0x0002, serial 2) at the built-in screen's last size (`lastBuiltInDisplayPoints`), kept
  between connections, gone when a real display is back and the lid opened or no device is connected; macOS's 1x
  stand-in ignored; the display reconfiguration callback; the Desktop following its display's size; the displays line
  at a lock and an unlock. **Reused**: all of it, its behaviour unchanged, moved under the manager in phase 2 as the
  Desktop display's headless role; its identity becomes the Virtual Desktop's (§7). **Replaced**: only its own
  `headlessDisplay` ownership.
- **#312** (lepeos; carries dr-apple's host half of #156 unchanged): under Hide Top Bar (#197) the device asks
  (`Viewport.deviceDesktop`) for a display of its own size, made the Mac's main display while the Desktop streams.
  **Reused** in phase 4: the size from the viewport divided by Aa (`DeviceDesktop.wantedSize`), the make, match and
  release life, `desktopCapture(on:)` with dr-apple's retry on the same display, and the device's rule that keeps the
  last full-screen size while an overlay brings the bar back (`TopBarVisibility.viewportSize`). **Not taken**: making
  it the main display, `Viewport.deviceDesktop` (Match is the Mac's setting and reads the viewport the device already
  sends), its identity (product 0x0002, serial 1, a third "Sill Desktop" beside #200's).
- **#156** (dr-apple): the same host half, plus a second tap on Desktop for full screen, a curtain over the Mac's own
  screens, the Mac's output muted while a device plays its sound, and picture and sound kept in step (`PictureClock`).
  **Reused**: `AudioPipeline.renew` if phase 1's sound still needs it (§10). **Not taken here**: the curtain and the
  mute (that is #133's privacy mode, #184), the full-screen tap (#92's decision is #197's toggle), `PictureClock`.
- **#225** (addhumal): with Virtual Display on and Aa set, the Desktop on the stage's own display at the device's shape
  (`DesktopVirtualDisplay`). **Reused**: its sizing in phase 4 (the panel divided by Aa, 800 to 4096). **Replaced**:
  the stage's display carrying the Desktop (§9).
- **#345** (bug, Nov 10): fixed by phase 1 (the cycle always starts on the main display).
- **#281** (Noah): a real Desktop on Sill's display, so Sill works as a monitor. This plan is it. Its open question,
  "an extra display or the main display while it streams", is answered by request 2: an extra one, the last stop;
  making it the main display is left for later (open question 15).
- **#91, #139, #273**: Noah's decision of 2026-10-19 on #91 (the tapping method; the button shows which desktop, a
  monitor or the virtual display, and that a tap moves to the next) is phase 1 and phase 2. #273's list is #296's.
- **#61, #298**: #200. **#212** (an ultrawide's black bars) and **#213** (a second desktop): phases 4 and 2.
- **#344** (Spectra3609's fork, a report, not a pull request): a display at the device's size made main, the Mac's
  displays mirrored and blacked out with `.forAppOnly`, a 30 s grace. Its M1 Max numbers are quoted in §12.
- **#122** (ashleigh-hopkins): a stream's rate capped by a fixed pixel-rate budget (520 million a second). Not part of
  this plan; with it a custom 4K at 120 Hz would run at 60 (open question 12). Its M2 Max number is quoted in §12.
- **#295** (addhumal, for #278): a stream held to 4096 pixels when the hardware encoder refuses its size (a 5K Intel
  iMac). Phase 3's sizes above 4096 pixels wide count on it, or on the software encoder.
- **#333** (an external monitor that switches itself off while Virtual Display is on): every display Sill makes or
  removes is a display change. A reason to make and remove the Virtual Desktop as seldom as the lifetime allows.
- **#226** (addhumal): independent streams per device. This plan assumes main's one stream; with #226, "showing"
  would count any stream on the stop.

## The rule

### 1. The stops, and the Desktop button's cycle

Pure, in StreamProtocol: #173's `DesktopDisplays`, kept under its name and grown, checked by its `desktop-displays`.

- **The real stops**: the active displays ScreenCaptureKit lists, but not Sill's own (vendor 0x5111, the stage's and
  the Desktop's, unless the Desktop's is the only display, below), not macOS's 1x stand-in (#200's `isStandIn`), and
  one stop per mirror set (a display that mirrors another, `CGDisplayMirrorsDisplay`, is left out). A Sidecar iPad,
  an AirPlay display or another app's virtual display is a monitor like any other.
- **The order**: the arrangement as System Settings › Displays draws it, left to right, then top to bottom (#173's
  sort by frame), turned so that the main display (`CGMainDisplayID`, the one with the menu bar) comes first. Each tap
  then moves one display to the right as they sit on the desk, wrapping to the leftmost after the rightmost and back to
  the main display after the last stop. #173 already steps to the right and wraps; what changes is where the cycle
  starts and how it counts: #173 numbers from the leftmost display (the built-in screen was "Desktop 3" in addhumal's
  own tests on #296, with two monitors above and to its left) and starts on `displays.first` while Virtual Display is
  off. Here "Desktop 1" is always the main display (Noah: "it will default to my default monitor"), and the numbers
  survive a sleep, where display IDs change (21 became 53, 2026-10-28). Not "the main display, then the rest left to
  right": with three monitors that jumps back over the main display.
- **The Virtual Desktop** is the last stop, while its setting is on and Sill can make it: the private API present, the
  AppKit loop running, Screen Recording granted, unlocked, this session on the console. While the Desktop's display is
  Sill's own in #200's headless role (no working screen), it is the only stop and there is no second.
- **The first stop of a session** is the main display: a device's own Desktop request at connect, or a tap. With
  Virtual Display on or off: #345's fix.
- **The choice is remembered by the Mac, for the session**: by the display's UUID for a monitor (#173), by its role for
  the Virtual Desktop; kept while any device is connected and for the grace (30 s) after the last one left. A Desktop
  asked for again within that span (after a window, a reconnect, a move to the cable) comes back to it; a session that
  starts later begins on the main display. Not per device: there is one stream, and the host is the one that knows its
  displays. A stop that goes (a monitor unplugged) sends the Desktop to the main display; the choice is kept, and the
  Desktop goes back to it if it comes back within the span (#173's). A step whose new stop does not stream (its start
  and the one more try both fail) goes back to the stop it was on (#173's `afterStep`).
- **A tap**: while the Desktop streams, kind 47, the next stop (a second tap while the switch runs is ignored, #173's);
  while a window streams, a pick of the Desktop (kind 6, as today), which shows the remembered stop.
- **Locked** (this session's screen): one stop, the main display, where the lock screen asks for the password as far
  as is known (item 4 of Noah's list checks it); the list leaves the fields out and kind 47 is refused (#173's lock
  rules); the remembered stop comes back after the unlock. The locked Desktop's capture follows `catalog.display`, so
  with #173 alone a device that had stepped to another monitor would go on showing that monitor's lock screen, which
  may not be the one that takes the password. **Off console**: one stop, the off-console view's display (this
  session's main display), and nothing moves the pointer.
- **The Mac's pointer** goes to the new stop's centre after a step, unless it is on it already (#173's
  `pointerTarget`), noted as Sill's own motion (`pointer.sillMoved()`), never off console (the stage's `mayWarp`).
  The device's pointer re-centres itself on the new frame size as today (`pointerFrameChanged`).
- **The rate on a stop**: the devices' rate, held to the stop's refresh rate when its display reports one
  (`CGDisplayModeGetRefreshRate` above 0): a 60 Hz monitor streams at 60, at the 60 fps bitrate, to a 120 Hz iPad. New,
  and it changes today's monitors too (above).
- **Kind 47 is a person at the device**: the device never sends it by itself, so it declares user activity
  (DisplayWake), as a window's button or a menu item does, and a stop that is asleep wakes. #173 had it not count.

**The button** (TopBar, PortraitStreamScreen's `desktopButton`, the phone's row 1). Phase 1 photographs it at every
bar size before the look is settled; this is the proposal:

- One stop, or a Mac from before this: today's button, `desktopcomputer` over "Desktop".
- Two stops or more: the symbol (`desktopcomputer` for a monitor, a dashed screen, `rectangle.dashed`, for the Virtual
  Desktop), over the label naming the stop ("Desktop 1", "Desktop 2", … and the Virtual Desktop's short name, §14),
  and under the symbol one small dot per stop, the shown one filled, while the Desktop streams: UIPageControl's
  convention, "there are more, and you are here". While a window streams, the label names the stop a tap brings back
  and the dots are hidden (that tap picks, it does not step). Seven stops or more: "3/7" in place of the dots. "Desktop
  2" fits every bar on one line (#173's photos at 1000×710, 710×500, 710×1000, 466×678 and 320×568).
- VoiceOver: the label "Desktop"; the value "Display 2 of 3, DELL U2723QE" or "Virtual Desktop, 3 of 3" (from
  `desktopDisplayNames`); the hint "Shows the next display." while the Desktop streams, else "Shows the Mac's
  desktop."; after its own tap the device announces the new value. The other devices' buttons follow the next window
  list, unannounced.

### 2. The Virtual Desktop's default size and rate

Pure: `VirtualDesktopSize.standard`, beside VirtualDisplaySize in CaptureScale.swift, checked by `virtual-desktop`.

From the main display's mode as the person set it in System Settings › Displays (its size in points, the "looks like"
size; its pixel scale, ScreenCaptureKit's `pointPixelScale` as CaptureScale reads it; its refresh rate), the Virtual
Desktop's mode (points, a scale of 1 or 2, the only two a virtual display has, a rate):

1. **Rate**: the main display's, at most 60. One that reports none (0) counts as 60.
2. **Scale**: the main display's: 1, or 2 for any Retina mode (macOS's scaled modes have a 2x backing store).
3. **Size**: the main display's points, when its pixels (points × scale) fit inside 3840 × 2160 turned to its
   orientation (a display taller than wide: 2160 × 3840). Else the points shrink evenly, at the same scale, until the
   pixels fit: the shape kept, the scale kept (never down to 1x), whole points.
4. **What Sill makes**: at 2x, each side at least 800 points (VirtualDisplaySize: macOS ran smaller ones at 1x), grown
   evenly when a size is under it; within VirtualDisplay's own bounds.
5. **No real main display** (#200's headless role): #200's own rule, unchanged: the built-in screen's last size, else
   the device's viewport, else 1920 × 1080, at 2x, at the stream's rate.

The size is taken when the display is made; a change of the main display's mode meanwhile applies the next time.

**"4K" in points and pixels.** The cap is on the Virtual Desktop's backing store, 3840 × 2160 pixels, which is what
ScreenCaptureKit captures and the encoder encodes. At 2x (Retina) that is a desktop that looks like 1920 × 1080
points; at 1x, 3840 × 2160 points with small text. A virtual display has no scaled modes, only 1x and 2x of one size,
so a 4K monitor set to "looks like 2560 × 1440" (a 5120 × 2880 backing store scaled down to its panel) gets a
Virtual Desktop that looks like 1920 × 1080 at 2x: its own pixel count, less room.

| The main display | Its mode | The Virtual Desktop |
|---|---|---|
| 14-inch MacBook Pro | looks like 1512 × 982 at 2x (3024 × 1964 px), 120 Hz | 1512 × 982 pt at 2x (3024 × 1964 px), 60 Hz |
| 16-inch MacBook Pro | 1728 × 1117 at 2x (3456 × 2234 px), 120 Hz | 1670 × 1080 pt at 2x (3340 × 2160 px), 60 Hz: 2234 rows are more than 2160 |
| 13-inch MacBook Air (M2) | 1470 × 956 at 2x (2940 × 1912 px), 60 Hz | itself |
| Studio Display (5K) | 2560 × 1440 at 2x (5120 × 2880 px), 60 Hz | 1920 × 1080 pt at 2x (3840 × 2160 px), 60 Hz |
| Pro Display XDR (6K) | 3008 × 1692 at 2x (6016 × 3384 px), 60 Hz | 1920 × 1080 pt at 2x (3840 × 2160 px), 60 Hz |
| 24-inch iMac (4.5K) | 2240 × 1260 at 2x (4480 × 2520 px), 60 Hz | 1920 × 1080 pt at 2x (3840 × 2160 px), 60 Hz |
| A 4K monitor set to look like 2560 × 1440 | 2560 × 1440 at 2x (5120 × 2880 backing), 60 Hz | 1920 × 1080 pt at 2x (3840 × 2160 px), 60 Hz |
| A 34-inch ultrawide | 3440 × 1440 at 1x, 144 Hz | 3440 × 1440 pt at 1x, 60 Hz |
| A 49-inch ultrawide | 5120 × 1440 at 1x, 120 Hz | 3840 × 1080 pt at 1x, 60 Hz (the pixel-count reading, (a′), keeps 5120 × 1440) |
| A 1080p monitor | 1920 × 1080 at 1x, 60 Hz | itself |
| Noah's docked main monitor (lid closed, 2026-10-27) | 2560 × 1440 at 1x | itself, at its rate up to 60 Hz |
| A 4K monitor turned upright | looks like 1080 × 1920 at 2x (2160 × 3840 px) | itself (the box turned) |
| No working screen (#200) | none | #200's: the built-in's last size at 2x, at the stream's rate |

### 3. Custom sizes and rates (phase 3)

The person's own choice, on the Mac (Settings › Displays › Virtual Desktop), from a fixed list; nothing measured,
nothing greyed.

- **Size**: "Same as main display (1512 × 982)", the default of §2; then, written as "looks like" points at Retina
  with their pixels: 1280 × 720 (2560 × 1440 pixels), 1440 × 900 (2880 × 1800), 1512 × 982 (3024 × 1964), 1728 × 1117
  (3456 × 2234), 1920 × 1080 (3840 × 2160, "4K"), 1920 × 1200 (3840 × 2400), 2560 × 1440 (5120 × 2880, "5K"), 3008 ×
  1692 (6016 × 3384, "6K"), 3840 × 2160 (7680 × 4320, "8K"); and at 1x, 1920 × 1080, 2560 × 1440 and 3440 × 1440. In
  phase 4, "Match the device" (§4).
- **Refresh rate**: "Same as main display, up to 60 Hz" (the default), 30, 60, 120 Hz.
- **The list's top is what macOS and the private API allow** (§13): Sill's own bounds are 4096 points a side at 2x
  (8192 pixels, VirtualDisplaySize.maxSide) and VirtualDisplay's 8192 points; the 8K entry sits at that edge. Phase 3's
  gate makes each entry with the existing self test, at 60 and 120 Hz, on every macOS it can reach, and drops what
  macOS will not bring up at 2x at its rate.
- **The words**, under the pickers and beside any choice above 4K or above 60 Hz: "Larger sizes and 120 Hz may not
  keep their full frame rate on every Mac. Sill drops frames rather than letting the picture fall behind. 120 Hz needs
  a ProMotion iPhone or iPad; an iPad mini shows 60." And beside a size over 4096 pixels wide: "Some Macs' video
  encoders take no picture wider than 4096 pixels; on those Sill streams it scaled down, or more slowly."
- What happens when the encoder cannot keep up is today's behaviour, unchanged (§12).

Open question 11: whether the first version offers choices above 4K at 60 at all (default: yes, in phase 3, since
Noah first asked for "at least 4K 120Hz").

### 4. Match this device (phase 4)

- The Virtual Desktop takes the shape of the picture's panel of the device in use, in that device's own points (a Mac
  point is a device point, so on every iPad its pixels are the iPad's pixels), divided by Aa's text scale when Aa is
  set (#225, #312), at 2x; grown evenly until each side is at least 800 points (§2's rule 4); held to the size cap (4K
  by default, the list's choice in phase 3); its rate the device's (120 on ProMotion), held to the rate choice (60 by
  default). An iPad Pro 13-inch held sideways with the bar hidden: 1376 × 1032 points at 2x, 2752 × 2064 pixels.
- **Whose shape, with several devices**: the device in use, the one whose input or step the host read last
  (PointerControl's controller), else the first to show it. Another device's viewport changes nothing; that device
  sees the picture fitted, with bars, as today.
- **When it changes**: once the device in use's viewport has kept a new size for 1 s (a rotation, the bar hidden or
  shown, #279's swipe), at most once every 3 s. The device keeps its viewport while an overlay comes and goes
  (#312's `TopBarVisibility.viewportSize`, carried with credit), so opening Settings never remakes the desktop. A change
  keeps the windows (§6), or changes the mode in place if phase 3 found that works.
- **Aa** sizes the Virtual Desktop in Match (default; Aa is dimmed on the Desktop today).
- Nothing new on the wire: Match reads the `width`, `height` and `scale` the device already sends (kind 9).

### 5. When the Virtual Desktop exists

Pure: `VirtualDesktopLife` (a clock and events in; make, keep, remove out), checked by `virtual-desktop`.

- **Made** when the Desktop is asked for on its stop (a step onto it, or the Desktop coming back to it within the
  session span), with the setting on, unlocked, on the console, Screen Recording granted, the private API present, the
  AppKit loop running, and not on a synthetic host.
- **Kept** while the stream shows it (the Desktop on it, a device connected), and for 30 s after it stops showing it:
  a step away, a window picked, the last device gone, a dropped connection. A reconnect or a quick look elsewhere comes
  back to the same desktop.
- **Removed**, its windows moved first (§6): 30 s after; at once when the person turns the setting off; at Quit; at
  once off console (it would join the other user's displays; macOS moves its windows); and when macOS removes it
  itself (its termination handler: a sleep, display arbitration), where the Desktop goes to the main display.
- **Locked** (this session's screen): never made; one that exists is kept past its 30 s until the unlock, so nothing
  changes the displays at the lock screen (#298, and #200's relock after a display change), and its 30 s count from the
  unlock.
- **#200's headless role** keeps #200's rules (made at the Desktop with no real display, at a locked screen too; kept
  between connections; gone once a real display is back and the lid opened or no device is connected), and it is the
  same display: when the last real display goes while the Virtual Desktop exists, it takes the headless role (macOS
  makes it the main display; no second display is made); when a real display comes back while a device shows it with
  the setting on, it stays as the Virtual Desktop, else #200's release.
- **Never**: a second Desktop display; a Virtual Desktop made for nobody.

### 6. Windows on it

Pure: `DesktopWindowLedger` (frames in, moves out), beside WindowRestore and using its tolerance and `movedSince`.

- **How windows get there.** The person at the Mac drags them across. From a device: macOS's own "Move to ‹display›"
  (the green button's menu, and the Window menu of many apps, which the Menus button mirrors), or a window opened while
  the device works there (where macOS opens it is to check, §"For Noah"). A device's own drag stops at the shown
  display's edge, since InputLanding holds the pointer to the source's rectangle, so it cannot drag a window from one
  stop to another. A "Move to" row in a thumbnail's lights (slrgt on #91) is open question 19.
- **When it goes**, Sill lists its windows as the stage's eviction does (`evictForeignWindows`: the window list,
  layer 0, not Sill's own, each matched to its Accessibility window by its frame), takes any in full screen out of
  full screen first (at most 2 s, as the stage's `leaveFullScreenIfNeeded`; one that will not leave is left to macOS),
  and moves each to the main display through Accessibility (no activation, as the stage's moves): the same place
  relative to the display's visible area, its size kept and held inside it (WindowRestore.keep). Then the display goes,
  and the Mac's pointer comes back to the main display if it was on it (as the stage's `releaseWindow`). The moves are
  synchronous, as the stage's teardown is, so Quit and the CLI's signals run them too. One line: "Virtual Desktop: no
  device has shown it for 30 s; moved 3 windows to Built-in Retina Display and removed it."
- **When it comes back** in the same run of Sill: each window still open and still where Sill put it (within 2 points)
  goes back to its place on it, scaled into the new size if the size changed. A window the person moved or resized on
  the Mac meanwhile is theirs and stays (if macOS itself moved a window back, Sill sees it moved and leaves it: no
  fight). One line: "Virtual Desktop: 2 of 3 windows back in their places (1 was moved on the Mac)."
- **Memory only**, as WindowRestore: nothing after Quit, a crash or `kill -9`. After a crash the display dies with the
  process and macOS moves its windows itself.
- **A window on it picked with Virtual Display on** is staged as any window; its way home is its place on the Virtual
  Desktop, or, when the Virtual Desktop has gone meanwhile, the main display (the stage's own rule for a home that is no
  home, `prepare` step 4b), and the ledger brings it back when the Virtual Desktop returns.

### 7. Its identity, and its place in the arrangement

- **One identity for the Desktop's display in all its roles** (headless, the Virtual Desktop, matched): #200's,
  vendor 0x5111, product 0x0002, serial 2, so a Mac that ran #200 keeps what macOS remembered of it. The stage keeps
  0x5111 / 0x0001 / 1. #156 and #312 used product 0x0002 with serial 1, a third identity: not taken. macOS remembers a
  display's arrangement and mode by vendor, product and serial (VirtualDisplay.swift's header), so a stable identity
  is what brings the person's own arrangement back each time it is made.
- **Its name in macOS** (System Settings › Displays, the Window menu's "Move to"): from the one constant, "Sill
  Virtual Desktop" while the name is a placeholder; #200's "Sill Desktop" becomes it in phase 2.
- **Where it sits**: where macOS puts a new display, and wherever the person moves it in System Settings › Displays ›
  Arrange, which macOS remembers for that set of displays. Sill sets no origin and never makes it the main display
  (#156 and #344's fork did; open question 15).
- **Its mode**: Sill selects the size it asked for with public CoreGraphics (`selectRequestedMode`), whatever macOS
  remembered.

### 8. What macOS does with it

As far as is known; each line is on the list for Noah's Mac.

- **Spaces**: with "Displays have separate Spaces" on (macOS's default) it has Spaces of its own and a menu bar of its
  own; with it off, one Space spans the displays and only the main display has a menu bar (the device then uses the
  Menus button, which mirrors the frontmost app's menus anyway).
- **Mission Control and the gestures** (GestureChords: Mission Control, App Exposé, Show Desktop, Apps) act on every
  display; the Spaces swipe (⌃← and ⌃→) acts on the display the pointer is on, which is the shown stop, since a step
  puts the pointer there.
- **Full screen**: an app made full screen on it gets a Space on it; when it goes, §6 takes it out of full screen first.
- **The Dock** stays where the person keeps it; macOS moves it to another display only for a pointer pushed against
  that display's bottom edge, and Sill's moves carry no mouse deltas (InputLanding's note): whether the Dock comes to
  the Virtual Desktop from a device is to check, and posting deltas at the edge is the fix if not.
- **The wallpaper**: macOS's default for a new display, then whatever the person sets for it.
- **The lock screen**: macOS covers every display; the password field is, as far as is known, on the main display,
  which is why the Desktop shows the main display while locked (§1; item 4 of Noah's list checks it).
- **Display sleep**: whether a virtual display sleeps with the Mac's panels (reads asleep, gives black frames) is not
  known; it is #228's own open item for the stage. A press on it is judged by DisplayWake's `pressLandsAsleep` as on
  any display.
- **Display changes**: System Settings › Displays lists it while it exists; a monitor or dock that renegotiates at each
  display change may switch itself off (#333).

### 9. One manager, two displays

- **The manager**, `SillDisplays` (main actor), owns every `CGVirtualDisplay` Sill makes: making it (VirtualDisplay),
  waiting until it is online at its mode, for AppKit's screen and for ScreenCaptureKit's listing (VirtualStage's
  `ensureDisplay` steps, moved here), its lost callback, removing it, the identities, telling the catalog which
  displays are Sill's (vendor 0x5111, #200's `displayKind`), the reconfiguration callback (#200's
  `watchDisplayChanges`), and the teardown at Quit and at the signals (HostShutdown). Two roles at most at once: the
  stage's and the Desktop's. The stage keeps its placement logic and asks the manager for its display.
- **Why two displays and not one**: the stage's display must hold the picked window alone (VirtualStage evicts every
  other window, and a covered window stops repainting, which is why the stage exists), sized to the device's panel
  envelope, remade as picks need, at the device's rate; the Virtual Desktop holds the person's windows at the main
  display's size for a session. One display for both would evict the person's windows or let them cover the staged
  one, and resize the Virtual Desktop at every pick. #225 put the Desktop on the stage's display; this plan does not.
- **One encoder engine**: main has one stream at a time, so the two are never captured or encoded together. Both exist
  at once only while one of them is in its grace (a window picked from the Virtual Desktop, say).

### 10. Input, the pointer, and what follows the Desktop's display

- **Input** lands as a fraction of the stop's rectangle in global points (`currentSourceRect`; InputInjector posts at
  any display's coordinates), the stop the capture runs on, never the one just chosen (#173's `landing`); InputLanding
  holds it to that display's last row and column of pixels.
- **The Mac's pointer**: PointerWatch judges it against the same rectangle (`.rect`). **The cursor shape** is global
  (NSCursor.currentSystem). **The Mac's menus** (MenuMirror) are the frontmost app's on every stop. **Gestures**: §8.
- **A click that wakes a display** (#228): `pressLandsAsleep` judges the display under the press, the Virtual Desktop
  or a monitor; the activity declaration (#151) is global; the "Woke the display" line reads the main display
  (`DisplayActivity.mainDisplayAsleep`), and phase 1 makes it read the shown stop's display.
- **Sound**: the Desktop's sound is every app's but Sill's whatever the display, so its filter is built on the main
  display, not on the shown stop, and a step never restarts it; renewed (#156's `AudioPipeline.renew`) only when that
  display goes.
- **The clipboard**: unchanged. **The lock gate** (LockPolicy, SessionLock): §1 and §5; `LockPolicy.list` leaves the
  new fields out while locked or off console. **The off-console view** (#340): one stop, never a Virtual Desktop.
- **Display wake** (#151, #228): unchanged. Whether a session on the Virtual Desktop lights the Mac's panels for
  nothing is the stage's open question too (open question 21).
- **Away from home**: the away quality (Low · Standard by default: 4 Mbps, captured at 1x) applies to every stop, so a
  Virtual Desktop that looks like 1920 × 1080 at 2x streams 1920 × 1080 pixels away. The display's own size never
  follows the network: windows would move.

### 11. Several devices

- **One stream**: a step by any device moves every device's picture; each device's button follows the next window list,
  and only the device that tapped hears the announcement.
- **An older device** sees whichever stop shows; its Desktop button picks the Desktop, on the remembered stop; it
  cannot step.
- **"Showing" the Virtual Desktop**: the stream on it and a device connected; the grace starts when the last device
  leaves or the stream leaves it.
- **Match**: the device in use (§4). **The rate**: the highest any device asks, held to the stop's refresh rate (§1).

### 12. The encoder at these sizes, and what happens when it cannot keep up

Background only: nothing here decides anything at run time.

- **Measured on this M2 Pro** (one encode engine; CLAUDE.md, 2026-09-25), one frame inside the encoder at a time, as a
  stream does, with the engine free: 3024 × 1904 at 115 to 121 fps; 5120 × 2880 at 50 to 53; 6016 × 3384 at 37 to 39;
  unthrottled HEVC at 3024 × 1968 about 105 to 115 fps, about 650 million pixels a second. 4K at 60 is 498 million
  pixels a second, its frame between the first two sizes; a 14-inch Retina desktop at 120 is 713 million, more than
  this engine.
- **Reported by contributors on their Macs, not measured here**: an M2 Max's fresh session at 3930 × 2188 returned 65
  fps at best, 14 to 17 ms a frame (#122); an M1 Max's hardware HEVC at 3168 × 2132 about 49 fps in a benchmark and 25
  to 38 fps live (#344); a 2020 Intel iMac's encoder takes nothing wider than 4096 pixels, so 5120 × 2880 fell to
  software (#62, #278).
- **So**: 4K at 60 is near the top of one stream on the Macs reported, and below it on some; 4K at 120 and 5K or more
  at 60 will run slower on most. A Mac with two encode engines (Max, Ultra) is no promise of more: whether one session
  uses both is not known here.
- **What Sill does when the encoder cannot keep up** (no change): the capture's frames go to a one-place mailbox, and
  a frame the encoder is not ready for replaces the one waiting (`enc.mailboxDrop`), so the picture stays current at a
  lower rate rather than falling behind; the network drops a frame before it queues and asks for a keyframe; a
  hardware session that settles in the slow state is replaced, at most once per 10 s (EncoderSlowState, only for a
  session that has returned a frame in under 25 ms: a 6K stream, about 26 ms a frame here even with the engine free,
  is never replaced); a frame that never comes back in 1.5 s moves the stream to the software encoder, captured at 1x
  and up to 60 fps, until a re-check finds the hardware keeping up again. Phase 3 checks the slow-state rule at the
  list's sizes.
- **Bitrate**: Quality's presets are per 60 fps, not per pixel. Bits per pixel per frame:

  | | 1920 × 1080 | 2560 × 1440 | 3024 × 1964 | 3840 × 2160 | 5120 × 2880 |
  |---|---|---|---|---|---|
  | Balanced (15 Mbps) | 0.12 | 0.068 | 0.042 | 0.030 | 0.017 |
  | Extreme (150 Mbps) | 1.2 | 0.68 | 0.42 | 0.30 | 0.17 |

  At Balanced a 4K Virtual Desktop gets about 70 % of the bits per pixel a 14-inch's own Retina screen gets, a 5K one
  about 40 %. The rate does not change these (a 120 fps stream gets twice the bitrate).

### 13. What "allowed at the OS level" means in practice

| | Known | Not known (and where it is found out) |
|---|---|---|
| The private API's size | VirtualDisplay takes 320 × 240 to 8192 × 8192 points, at 1x or 2x; VirtualDisplaySize holds the stage to 800 to 4096 points a side at 2x (8192 pixels); both sides under 800 came up at 1x; Sill made 2560 × 2264 at 2x (5120 × 4528 pixels) | The real ceiling on each macOS version (phase 3's gate) |
| HiDPI | The API's hiDPI flag gives a 1x and a 2x mode of one size; no 1.5x or 3x | |
| Refresh rate | A Double per mode; 60 and 120 came online (the self test) | Above 120 (no device needs it) |
| ScreenCaptureKit | Delivers at most the display's refresh; the stage's capture of Sill's display ran at 59 fps in the probe | 120 fps from a 120 Hz virtual display (phase 3) |
| The hardware encoder | HEVC Main, real time, the level chosen by VideoToolbox (AutoLevel). HEVC level 5.1 (ITU-T H.265, Annex A, Table A.8) is up to 8,912,896 luma samples a picture (4096 × 2176) at 534,773,760 a second, that size at 60; 5.2 the same at 120; 5K, 6K and 8K need level 6 (up to 35,651,584 a picture). 3840 × 2160 at 60 is 497,664,000 a second: level 5.1. Apple silicon took 6016 × 3384 here; an Intel iMac refused wider than 4096 (#62) | The largest size each Mac's hardware takes (a refused size is today's error path: the software encoder, or #295's hold) |
| The device | Its screen: 60 Hz (iPad mini, iPhones without ProMotion) or 120 (ProMotion); the stream runs at the highest rate any device asks | Whether each supported device decodes level 6 (5K, 6K, 8K) in real time; Sill already streams a 5K or 6K main display at its Retina size today, and nothing reported says either way |
| macOS versions | CGVirtualDisplay since macOS 11, looked up at run time (a missing or changed method is a thrown error, never a crash); x86_64's BOOL encoding handled (#87); macOS 27 makes a 1x stand-in for a Mac with no screen (#200) | What macOS 14 and 15 do in #200's case; how each version remembers a virtual display's arrangement |

### 14. The name

"Virtual Desktop" is a placeholder (Noah). The code keeps it in one place per app: `VirtualDesktopWords`, one file in
StreamProtocol that each app compiles as its own (one place on the Mac, one on the device, the same text), holds the
name, its short form for the Desktop button, the name macOS lists ("Sill " + the name), and every sentence that names
it (the menu's subtitle, the Settings footnote, the device's panel row, VoiceOver's value); the log's lines build on
`name`. A rename is one edit there, plus README, support.html and the
App Store text, which docs/release-checklist.md lists. The candidates, each read next to "Virtual Display": **Virtual
Desktop** says "a whole desktop" but is one word away from Virtual Display, and Noah himself called Virtual Display
"Virtual Desktop" on 2026-10-27 (HostConfig.app's doc quotes him: "have Virtual Desktop on by default"), so the two
are confused already; **Extra Desktop** is plain and says it adds to your screens, but "Desktop 2" is also macOS's
name for a Space in Mission Control; **Second Screen** is what people ask for (#213's "Second Desktop") but is the
third on a Mac with two monitors; **Sill Screen** says it is Sill's own and is what support.html already calls the
stage's display ("an invisible screen sized for your device"); **Device Desktop** (#156's name) says it is for the
device but reads like Match this device. Renaming Virtual Display instead (say "Window Stage", or "Windows on Their
Own Display") would free the pair, at the cost of a name users have had since Sill for Mac's first release.

## The wire (additive)

- **`WindowList`** (host → device; kind 2), optional, set after the initializer as `keyRepeat` is, left out with one
  stop, while locked or off console (`LockPolicy.list`), and by a synthetic host without its test hook:
  - `desktopDisplays: Int?`: how many stops, 2 or more (#173's name).
  - `desktopDisplay: Int?`: the stop the Desktop shows, or comes back to while a window streams, 1 to
    `desktopDisplays`, in the cycle's order (#173's name; its meaning now starts at the main display).
  - `desktopVirtual: Int?`: the Virtual Desktop's stop number while it is in the cycle (the last today; a number, not a
    flag, so a later host may put it elsewhere).
  - `desktopDisplayNames: [String]?`: each stop's name in that order (NSScreen's `localizedName`; the Virtual
    Desktop's from `VirtualDesktopWords`), for VoiceOver and a later list (#296's).
- **Kind 47 `nextDisplay`** (device → host): an empty payload, the next stop (#173's). Sent only to a host whose list
  says `desktopDisplays` 2 or more, only from the Desktop button while the Desktop streams. `{"number": n}` is
  reserved for #296's list. A host from before reads it as unknown and skips it. Kinds 45 and 46 stay with the open
  pull requests that hold them (the microphone, the pen, the camera).
- **`HostSettingsState.virtualDesktop`** (host → device; kind 16), optional, for the panel's read-only row: `on`, the
  size (`width`, `height`, `scale`), `hz`, and `choice` ("main", "custom" or "device"). Absent from `StreamSettings`
  and `HostSettingsChange` (decision 3).
- **Unchanged**: `StreamSource` (`.desktop` is the Desktop on the host's stop), `Viewport` (Match reads `width`,
  `height` and `scale`), `Hello`.
- **Mixed builds**: an older device never sends 47, shows today's button and sees whichever stop shows; an older Mac
  lists no stops, so a newer device sends nothing new. CLAUDE.md's compatibility floor gains kind 47 and the four
  fields once a public build ships them.

## The host

- **Phase 1**: `Sources/StreamProtocol/DesktopDisplays.swift` (#173's, grown: the order, the session span, the label,
  value and dots, the lock's one stop); `StreamMessage.swift` (kind 47); `Switcher.swift` (the four fields, three of
  them in phase 1); WindowCatalog (the candidates turned to the main display, mirror sets, #200's pool, the remembered
  stop and its span, `onDesktopDisplaysChanged`); StreamCoordinator (kind 47's `nextDesktopDisplay`; `desktopFrame`;
  the main display while locked; the rate held to the stop's refresh in `select`; the sound's filter on the main
  display; DisplayActivity's line on the shown display); LockPolicy (kind 47 refused, the fields left out); DisplayWake
  (kind 47 a person's request).
- **Phase 2**: `Sources/SillHost/SillDisplays.swift` (the manager); `VirtualDesktopSize` (in CaptureScale.swift);
  `VirtualDesktopLife.swift` and `DesktopWindowLedger.swift` (pure); VirtualStage (asks the manager for its display);
  #200's display moved under the manager (HeadlessDesktopPolicy unchanged); HostConfig `virtualDesktop` (off in
  `standard` and `app`; the Mac's alone: absent from StreamSettings, HostSettingsChange, DeviceSettings.accepted,
  `applying` and `restartNeeded`; applied at once by `setTarget`: off removes it with its windows moved, on adds the
  stop and makes nothing); StreamCoordinator (the Virtual Desktop's stop, its lifetime's clock, the ledger at removal
  and return, Quit); HostStatus (the card's source row); `VirtualDesktopWords`.
- **Phase 3**: HostConfig `virtualDesktopSize` and `virtualDesktopHz`; the list; a size change by a new mode in place,
  or a remake with the ledger; EncoderSlowState's checks at the large sizes.
- **Phase 4**: `VirtualDesktopSize.matched`; the device in use; the 1 s settle and the 3 s spacing; Aa on the Virtual
  Desktop.
- **The log**, built from the constant:
  - "Desktop: display 2 of 3 (DELL U2723QE), asked by iPad (iPad14,1)." (#173's)
  - "Desktop: Virtual Desktop (3 of 3), asked by iPad (iPad14,1)."
  - "Virtual Desktop 1512×982 pt @2× at 60 Hz id 7: made in 412 ms, as Built-in Retina Display (1512×982 at 2x, 120
    Hz), held to 60 Hz."
  - "Virtual Desktop: kept while this Mac is locked; it goes 30 s after the unlock unless a device shows it."
  - §6's two lines, and `vdesk.made`, `vdesk.removed`, `vdesk.windowsMoved`, `vdesk.windowsBack` and `desk.next` in the
    `[1s]` lines when they happen.

## Sill.app

- **Settings**: the tab "Virtual Display" becomes **"Displays"** (SettingsWindow.swift's title; `-SillSettingsAfter`
  takes "displays", with "virtual display" kept as another word for it), with two sections:
  - **Windows**: the existing switch, reworded "Move picked windows to a display of their own" (its key,
    `virtualDisplay`, unchanged), its footnote and status rows as today.
  - **Virtual Desktop**: the switch "Add a desktop for your devices" (`virtualDesktop`, off); the footnote: "Your
    iPhone or iPad gets a desktop of its own, after this Mac's screens: tap Desktop on the device to step to it. It is
    here only while a device shows it. Windows you move to it come back to your main screen 30 seconds after no device
    shows it, and return to it when it comes back."; the size and rate (phase 2: one line, "Same as your main display:
    1512 × 982 at 60 Hz"; phase 3: the pickers and their notes); the status (Available; Not available on this version
    of macOS: …; Needs Screen Recording; Showing on iPad (iPad14,1)).
- **The menu**: "Virtual Display" with the subtitle "Picked windows move to a display of their own" when it has nothing
  else to say; after it **"Virtual Desktop"** (checked), its subtitle "A desktop for your devices, after your screens",
  or "On iPad (iPad14,1): 1512 × 982, 60 Hz" while it exists.
- **The card's source row**: "Virtual Desktop · 1512×982 · 60 fps", "Desktop 2 of 3 · DELL U2723QE".

## The words outside the apps

Each inside a release marker in site/ (docs/release-checklist.md part 1 §3), as the house does for words that wait
for their release:

- **Phase 1**, support.html and README's How it works: "On a Mac with more than one screen, tap Desktop while it shows
  to step to the next screen, starting from your main one. The button shows which screen is up."
- **Phase 2**, support.html, a section "A desktop of its own for your iPhone or iPad": "Turn on Virtual Desktop in
  Sill for Mac (Settings › Displays), and after your Mac's screens your device can step to a desktop that is its own:
  the size of your main screen, up to 4K at 60 Hz. It is there only while a device shows it. Thirty seconds after none
  does, the windows on it move to your main screen, and they go back when it returns." README's Good to know gains its
  line beside the virtual display's. privacy.html's Accessibility line ("so Sill can move and size the window it
  shows") gains the windows Sill moves off the Virtual Desktop when it goes; nothing of it leaves the Mac.
- **Phase 3**: the support section gains the sizes, the rates and §3's sentence on what a Mac may not hold.

## The device

- **The Desktop button** (§1): StreamScreen's TopBar, PortraitStreamScreen's `desktopButton`, the phone's row 1.
- **StreamClient**: #173's `tapDesktop()` (kind 47 while the list says two stops or more and the Desktop streams, else
  `select(.desktop)`), the four fields, the announcement after its own tap.
- **The Settings panel**: a read-only row "Virtual Desktop", On or Off with its size, and the footnote "Set in Sill on
  the Mac." (decision 3).
- **Harness**: #173's `-SillDesktopDisplays 3,2` gains `v` (`-SillDesktopDisplays 4,4,v`: four stops, the fourth
  shown, the last one the Virtual Desktop).

## The CLI and the test hooks

- `SillHost --virtual-desktop` (phase 2; it runs the AppKit loop, as `--virtual-display` does),
  `--virtual-desktop=1920x1080@2:60` (phase 3), `--virtual-desktop=device` (phase 4). Off by default; without it the
  CLI's output is byte for byte main's (H2).
- TEST ONLY, honoured only by a synthetic host (TestHooks: one "ignored" line anywhere else; Sill.app never):
  - `SILL_TEST_DISPLAYS='Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0'`: the host
    lists these as stops (a name, points@scale:Hz:origin, the first the main display) and draws the test pattern with
    the stop's name and number; kind 47 steps through them; input lands in each one's own space under
    `SILL_TEST_INPUT_LOG`; the list's fields and lines as on a real Mac.
  - `SILL_TEST_VIRTUAL_DESKTOP=1`: the Virtual Desktop as a stop that makes no display, with its lifetime's lines.
  - `SILL_TEST_VD_GRACE=<s>`: the grace, in seconds.
  - `sillclient.py --next-display@T` and `--expect=desktopDisplay=…`.

## Phases, each a pull request with its gates

Every phase: one commit per theme; `Tests/checks/run-all.sh`; `swift build -c release` from a clean copy; the iOS app
Debug and Release for the simulator and Debug for a device; H2 (the CLI against main, idle and with a test client,
masked and sorted: identical); previews from the bare SillMenuBar binary (never a built Sill.app); its untested list
in the pull request and in CLAUDE.md's Current step. No phase makes a display, captures this Mac's screen or uses the
hardware encoder while a device is connected to Noah's Sill.app (`Scripts/encoder-check/no-device.sh`) or while the
Mac is in use (`ioreg -c IOHIDSystem | grep HIDIdleTime` under five minutes); the existing self test also moves the
pointer onto the display and back.

### Phase 1: the real monitors, with the button's label (towards #91, and #345)

- **Scope**: §1 without the Virtual Desktop's stop; the rate held to the stop's refresh rate; the sound on the main
  display; DisplayActivity's line on the shown display; the test hooks for fake stops.
- **Base**: #173 merged in with its commits (decision 2), on main with #200 in it, WindowCatalog's display choice as
  addhumal's `reconcile-173-200` has it (#173 chooses among #200's pool).
- **Commits**: the merge; the order and the first stop (the main display, the arrangement turned, mirror sets, #345);
  the session span; the button and VoiceOver; kind 47 as a person's request; the main display while locked; the rate;
  the sound; the hooks; the docs (README, support.html in a release marker, DEVELOPMENT.md, the checks README).
- **Gates**: `desktop-displays` grown (every arrangement of up to six displays with the main one anywhere, mirror sets,
  the stand-in and Sill's displays, 5,000 random arrangements and sessions: the order and the wrap, the session span, a
  stop unplugged and back, a stop that will not stream, landing during a switch, the pointer's target, the label,
  value and dots, locked and off console), its mutants in CI's matrix; `compatibility` (the fields, kind 47 skipped by
  an older reader); `lock-policy`; `display-wake`; the rate rule's check; live on loopback with `SILL_TEST_DISPLAYS`
  and sillclient.py: stepping and wrapping, the fields, input landing per stop (the dry run's log), the main display
  while locked (`SILL_TEST_LOCKED_FILE`), kind 47 refused locked, 60 fps on a 60 Hz stop with a 120 Hz client;
  harness photos of the button at 1000×710, 710×500, 710×1000, 466×678, 669×951, an iPhone's sizes and 320×568, at the
  default and an accessibility text size, the dots and "3/7".

### Phase 2: the Virtual Desktop at the main display's size

- **Scope**: §2's default, §5 to §11, the manager with #200 under it, the Mac's words, `--virtual-desktop`, the
  device's look for the Virtual Desktop's stop and the panel's row.
- **Gates**: `virtual-desktop` (§2 with every worked example as a case and random modes against the box and the
  800-point rule; the lifetime over random sessions: never two Desktop displays, none with no device past the grace,
  none made locked or off console, kept locked past the grace until the unlock, the headless role exactly #200's; the
  ledger: windows out and back, moved or resized ones left, closed ones forgotten, scaled into a new size), its
  mutants; `virtual-display-api` and `lock-policy` with #200's verdicts unchanged (its code moved, not changed); H2
  with #200's lines identical; previews of the Displays tab, the menu and the card; live on loopback with
  `SILL_TEST_VIRTUAL_DESKTOP=1` and a short grace (the stop, the lines, the grace across a reconnect, the setting off
  at once); harness photos of the Virtual Desktop's stop.
- **On a Mac at rest** (the conditions above, never Sill.app): the self test at the main display's default
  (`--virtual-display-selftest 60 1512x982` with the 14-inch's built-in screen as the main display; the self test makes
  2x displays, so phase 2 gives it a scale for a 1x main display such as the docked 2560 × 1440): online at its mode
  at 60 Hz; and a probe in the way of `Scripts/restore-probe` (a window of its own, a display with the Virtual
  Desktop's identity): the ledger moves the window off and back.

### Phase 3: custom sizes and rates

- **Scope**: §3, a size change in place or by a remake, the words, EncoderSlowState at large sizes, #295's part.
- **Gates**: the list against the API's bounds in `virtual-desktop`; on a Mac at rest, the self test at every entry
  at 60 and 120 Hz on each macOS reachable (14, 15, 26, 27), dropping what macOS will not make at 2x; one probe of
  whether a live display takes a new mode through `applySettings:`, and whether modes listed at creation switch with
  the public `CGConfigureDisplayWithDisplayMode` (deciding in place against a remake); the encoder's session start at
  each size (one frame, no stream, under the same conditions); EncoderSlowState's check at the 5K, 6K and 8K
  turnarounds; previews of the pickers and their notes.

### Phase 4: Match this device

- **Scope**: §4, the device in use, the settle and the spacing, Aa on the Virtual Desktop, #312's device-side hold
  (after #197), credit to dr-apple, lepeos and addhumal.
- **Gates**: `virtual-desktop`'s matched size (every device's panel in both orientations and at every text scale, held
  to 800 points and the cap); the device in use over random sessions of two and three devices; the settle; #312's
  phone-portrait cases (B6 to B10) carried; live on loopback with two sillclient.py viewports; harness photos.

## For Noah, on his Mac and devices (what waits for the hardware)

Phase 1 (the MacBook with the 2560×1440 and the 1920×1080 docked, the iPad and the iPhone):
1. Lid open: the Desktop starts on the main display; Desktop 1, 2, 3 and back, in the arrangement's order from the
   main display; the label, the dots, VoiceOver's value; a tap right after a step lands on the shown display.
2. Lid closed with the monitors: the main one (the 2560×1440) first, then the 1920×1080.
3. A monitor unplugged while it shows, and plugged back in.
4. ⌃⌘Q while Desktop 2 shows: the device shows the main display's lock screen, with the password field (is it on the
   main display?), and Desktop 2 again after the unlock.
5. A mirrored display (one stop) and a Sidecar iPad (a stop).
6. A 120 Hz iPad on the 60 Hz monitor: Sill.log's "Streaming … 60 fps".
7. The Spaces swipe on a monitor that is not the main one.
8. The Mac's sound across steps: no gap.

Phase 2:
9. Settings › Displays › Virtual Desktop on; step past the monitors: "Virtual Desktop … made"; System Settings ›
   Displays lists it; a menu bar and a wallpaper on it.
10. A window moved there (from the Mac; from the device, the Menus button's Window › Move to); step away and back
    within 30 s: it stays; wait 30 s: it is on the main display; step back: it returns.
11. Where macOS puts it in the arrangement; moved in Arrange, it is there the next time.
12. An app opened from the Apps drawer while the Virtual Desktop shows: which display its window opens on.
13. The Dock at its bottom edge, from the device.
14. ⌃⌘Q while it shows: kept, the lock screen from the main display; unlock; disconnect, 30 s, gone.
15. `pmset displaysleepnow` while it shows: its picture, and a tap on it.
16. Quit Sill.app while it shows: the windows on the main display, no display left; Force Quit: where macOS puts them.
17. Virtual Display on, a window on the Virtual Desktop picked, then the Desktop: back on the Virtual Desktop.
18. The monitor of #333's kind, if at hand: whether a step onto the Virtual Desktop switches it off.
19. The lid closed with nothing attached (#200), the setting on: one stop, Sill's display; the lid opened while a device
    shows it.

Phase 3:
20. Each size and rate on this M2 Pro: Sill.log's "Streaming … fps" and the menu's rate; 4K at 120 and 5K at 60.
21. An iPad mini at a 120 Hz Virtual Desktop: 60 shown.

Phase 4:
22. Match on the iPad sideways and upright, with and without Hide Top Bar: no black bars; a rotation; Settings opened
    (nothing remade); Aa.
23. Two devices: the one in use wins.

## Risks

- **The private API.** Any macOS release can rename or remove `CGVirtualDisplay`. Sill looks it up at run time and a
  missing or changed method is an error, never a crash: the Virtual Desktop's stop then leaves the cycle and Settings
  says "Not available on this version of macOS", as the Virtual Display pane does. Behaviour differs across versions
  (1x at small sizes on 27; the stand-in on 27 only, per #200; how modes are remembered).
- **Sill crashing with the display up**: the display dies with the process (it lives only while Sill holds the
  object); macOS moves its windows to a real display, where macOS likes; the ledger is memory only, so they do not come
  back; full-screen Spaces on it go to another display. Nothing persistent is left to undo: Sill never makes it the
  main display and sets no origin. One remembered entry per identity stays in macOS's display preferences (two
  identities, one each for the stage and the Desktop).
- **Display changes**: each make and removal is one; some monitors and docks switch off at one (#333); a closed-lid
  Mac may lock at one (#200, #298). The lifetime makes the Virtual Desktop once per showing and keeps it while locked.
- **The person at the Mac**: while it exists, the pointer can cross onto it and a window can be dragged there; it
  exists only while a device shows it, plus 30 s.
- **The encoder**: 4K at 60 is near the top on the Macs reported (§12); larger choices run slower, and the words say
  so. Macs with two engines: not known whether one stream uses both.
- **Intel Macs**: users reported the virtual display working on two (#87, #62) and a 4096-pixel width limit on one
  encoder (#62); the default's 3840 fits under it; larger custom sizes rely on #295 or the software encoder. Nobody on
  the project has an Intel Mac.
- **Screen Recording**: never a display without it (ScreenCaptureKit hangs while one exists).
- **The GPU**: an extra display is composited at its refresh rate while it exists; small, not measured; one more
  reason for the short lifetime.

## Open questions, with the default taken

1 to 4 are Noah's decisions at the top.

5. **The name**: "Virtual Desktop" until Noah picks one (§14).
6. **The order of the other monitors**: the arrangement turned to the main display (default); or the main display, then
   the rest left to right; or #173's plain left to right.
7. **The remembered stop**: by the Mac, for the session span (default); or across launches; or per device.
8. **The button's look**: the label with dots (default); or "Desktop 2/3"; or the label alone, as #173.
9. **Kind 47 as a person at the device** (it declares activity): yes (default); #173 said no.
10. **The grace**: 30 s (default).
11. **Choices above 4K at 60 in the first version**: yes, in phase 3 (default).
12. **#122's budget** (a custom 4K at 120 would run at 60): not adopted (default); the person's choice stands, and
    frames drop.
13. **Locked**: the main display's lock screen whatever the stop (default); or the stop shown.
14. **Kept while locked past the grace**: yes, until the unlock (default); or removed at 30 s.
15. **The Virtual Desktop as the Mac's main display** (#156, #344's fork, #281's question): not in these phases
    (default); with a privacy mode (#133, #184) it could come later.
16. **Its place**: wherever macOS puts it and the person arranges it (default); or Sill puts it away from the main
    display.
17. **Match's smallest side**: each side at least 800 points (default); or the longer side alone, as Sill.log suggests
    is enough (phase 4's first look).
18. **Aa on the Virtual Desktop**: in Match only (default).
19. **"Move to the Virtual Desktop" from a device**: not in these phases; macOS's own Move to, through the Menus button
    (default). A row in a thumbnail's lights later.
20. **#296's list** (hold Desktop for the displays by name): its own pull request after phase 1 (default), Noah's call.
21. **Display wake while the Virtual Desktop shows**: unchanged (default) until Noah's test shows whether its picture
    stays live with the panels asleep.
22. **The main display's mode changing while it exists**: applied the next time it is made (default).
23. **One identity for every device's Match**: yes (default); or one per device, so each remembers its own place.
24. **The CLI's flag**: `--virtual-desktop[=WxH@scale:Hz|device]` (default).

## Progress

- 2026-11-11: the plan written from main at dd6ea6a, #173, #296, #200, #312, #156, #225 and the issues above.
  Nothing built, nothing measured: no virtual display made, no display arrangement changed, the encoder not used.
