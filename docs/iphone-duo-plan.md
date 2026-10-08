# iPhone Duo with the iOS 27.1 SDK — the plan

2026-10-08. Branch `duo-layout` (worktree `/Users/noah/Downloads/winstream-duo`) from origin/main at
e6b3265 (PR #46). Line numbers are at e6b3265. This document starts with the probe step's facts,
measured on the iOS 27.1 simulator's iPhone Duo with a scratch probe app and with today's Sill; the
build, review and finish steps add their parts below it.

**Noah's request and approvals (2026-10-08, as the main session relayed them):** research the iOS
27.1 SDK for iPhone Duo, then "use Opus 5.5 Max agents to adapt the app to use this SDK, then use the
simulator with iPhone Duo, make sure it works properly, then take screenshots of all poses", and
"ideally, the merge conflicts from PR #39 don't cause hours of merge jobs". Approved from mockups
(the "Sill on iPhone Duo" design artifact; the files are in the session's scratchpad,
`duo-mock/project/*.dc.html`, one per pose at the Duo's point sizes):

- **(a) Book pose** (the inner display sideways, half-folded, the fold down the middle): one stream
  across the fold, the picture crossing the curve as scrolling content may; nothing interactive on
  the fold's reserved region: the landscape bar's right group goes to its compact button width so
  Menus clears the band, and no thumbnail or button sits on it.
- **(b1) Laptop pose** (the inner display upright, half-folded): today's inner-portrait layout, the
  picture above the fold and the window bar, the key row and the trackpad below it, split at the
  fold's real frame from the SDK instead of at half the height.
- **(b2) Open flat, upright:** nothing pins the split; the picture pane takes the room at the
  streamed window's own aspect (16:10 until Aa) and the trackpad grows into the slack.
- **(c1) Closed, upright** (the cover display, compact width): the phone arrangement as on an
  iPhone, narrower by the strip the status bar and the camera take (the safe areas).
- **(c2) Closed, on its side:** the compact landscape layout.
- Open flat, sideways: today's landscape layout. Nothing else about Sill changes, and nothing on the
  wire (the compatibility floor in CLAUDE.md stays as it is).
- **(d)** TestFlight 0.5.1 waits until the iPhone Duo is in the wild (Oct 23+); nothing is uploaded.

## Facts

Measured 2026-10-08 (04:10–05:05 and 11:00–11:10) on this Mac (macOS 27.0, Apple M2 Pro) with Xcode
27.1 RC (27A9275), iOS Simulator SDK 27.1, the iOS 27.1 simulator runtime (24A94232), on a private
simulator "Sill duo" (1265B8BD-F5C7-44CA-86D2-1FB06B84B487) made from
`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`. The probe app (`DuoProbe`, scratch: a SwiftUI app
built with swiftc, deployment target 17.0, SDK 27.1, Info.plist keys as Sill's) printed what its
window sees on every change; durable copy in `/Users/noah/Downloads/sill-handoff/duo/probe/`
(DuoProbe.swift, build.sh, and the run logs quoted here).

### The device type

- `/Library/Developer/CoreSimulator/Profiles/DeviceTypes/iPhone Duo.simdevicetype`: product class
  V68, model iPhone19,4 (A3447), idiom phone, `IsLargeFormatPhone`, `DeviceCornerRadius` 59,
  `DeviceSupportsEnhancedMultitasking` false, Dynamic Island, runtime 27.1 or later only (made and
  paired by default from 27.1). The first boot reported "Data Migration Failed" and booted anyway.
- Two integrated displays: **LCD** ("primary", screen ID 1), the cover: 1398×2034 px at 3x =
  **466×678 pt**, 460 ppi, P3, corner radii 8 on the left and 59 on the right; **LCD-1**
  ("primary-1", screen ID 3), the inner: 2007×2853 px at 3x = **669×951 pt**, 460 ppi, sRGB, corner
  radius 55, native orientation 270 (it is sideways when the device is held upright). Both 60 Hz in
  the simulator. App Store Connect's iPhone Duo screenshot sizes are these: 1398×2034 / 2034×1398 and
  2007×2853 / 2853×2007 px.
- Device Hub (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`) replaces Simulator.app;
  its device view (`SharedFrameworks/DeviceKit.framework/…/CoreDevicePopDeviceKitExtension`) has the
  hinge slider ("closed", "partiallyOpen", "openFlat") and the orientation picker.

### What an app sees, pose by pose

One window scene; folding and unfolding move it to the other display (`windowScene.screen` changes,
the scene stays). Size classes: the inner display regular/regular both ways; the cover
compact/regular upright, compact/compact on its side. Screen scale 3 everywhere;
`maximumFramesPerSecond` 60 on both displays in the simulator. `UIDevice.userInterfaceIdiom` is
`.phone`. The device's orientation maps onto the inner display a quarter turn round: device portrait
→ inner landscapeLeft (book), device landscapeLeft → inner portrait (laptop), device landscapeRight →
inner **portraitUpsideDown** (Sill's Info.plist does not list it for iPhone: the inner display
ignores UISupportedInterfaceOrientations), device upside down → inner landscapeRight. On the cover:
device portrait → portrait, landscapeLeft → landscapeRight, landscapeRight → landscapeLeft.

With the status bar showing (today's Sill, below), window coordinates:

| pose (duorig) | hinge (onHingeChange) | interface | window | safe area | fold (`.division`) | occlusions, active | inactive |
|---|---|---|---|---|---|---|---|
| book | partiallyOpen 90.0° | landscapeLeft | 951×669 | right 84, bottom 34 | x 455.5, y 0, 40×669, margins left 20, right 20, active | status box (867, 0, 84×120) | camera (677.3, 21, 58×37) |
| laptop | partiallyOpen 90.0° | portrait | 669×951 | top 82, bottom 34 | x 0, y 455.5, 669×40, margins top 20, bottom 20, active | status box (535, 0, 134×82) | camera (21, 215.7, 37×58) |
| flat-landscape | fullyOpen 180.0° | landscapeLeft | 951×669 | right 84, bottom 34 | the same frame, inactive | status box (867, 0, 84×120) | camera (677.3, 21, 58×37) |
| flat-portrait | fullyOpen 180.0° | portrait | 669×951 | top 82, bottom 34 | the same frame, inactive | status box (535, 0, 134×82) | camera (21, 215.7, 37×58) |
| closed-upright | closed 0.0° | portrait | 466×678 | right 84, bottom 34 | none | camera (399.7, 29.3, 37×37); box (382, 0, 84×170) | — |
| closed-side | closed 0.0° | landscapeRight | 678×466 | left 84, bottom 34 | none | camera (29.3, 29.3, 37×37); box (0, 0, 84×82) | — |
| (cover, device landscapeRight) | closed 0.0° | landscapeLeft | 678×466 | right 84, bottom 34 | none | camera (611.7, 399.7, 37×37); box (594, 384, 84×82) | — |
| (inner, device landscapeRight) | partiallyOpen | portraitUpsideDown | 669×951 | top 82, bottom 34 | x 0, y 455.5, 669×40 | status box (535, 0, 134×82) | camera (611, 677.3, 37×58) |

With the status bar hidden (`.statusBar(hidden: true)` on the probe's root): the inner display's
strip is gone in every pose: safe area **bottom 34 only** (951×669 or 669×951 usable), no active
occlusion (the under-display camera stays an inactive region). The cover keeps its strip: upright
right 84 and bottom 34, the camera (399.7, 29.3, 37×37) and a box (382, 0, 84×82); on its side left 84
and bottom 34, the camera (29.3, 29.3, 37×37) and a box (0, 0, 84×82).

### The fold (reserved regions)

- One `.division` region on the inner display: 40 pt wide, centred on the crease at 475.5 (the
  middle of 951): its frame includes 20 pt margins each side of a zero-width line. Active only while
  `partiallyOpen` (90° and 174° alike); `fullyOpen` reports it inactive (only with
  `.includeInactive`); closed, the cover has none, even with `.includeInactive`.
- `GeometryProxy.reservedRegions` gives the same frames as UIKit's `UIView.reservedRegions` on the
  window, **in the proxy's own coordinate space and not clipped to it**: a reader inside the safe
  area (laptop, top inset 82, at global y 82) got the fold at y 373.5 (455.5 − 82), and a 635 pt tall
  reader in book pose got a 669 pt tall region.
- Occlusions: the status bar's box while it shows, and the camera; an inner-display camera is
  reported inactive (it occludes nothing while the camera is off).

### The hinge

- `onHingeChange` calls back once at launch, from `hinge: nil` to the current state ("old nil (no
  hinge) -> new closed 0.0°"), then on every change, several times with the same value while it
  settles (ten calls in 0.4 s at 118.3°).
- The angle an app reads is quantised: posted 90 → 90.0°, 120 → 118.3°, 150 → 146.7°, 175 → 170.3°,
  179 → 174.1°, 30 → 33.3°; the HID event itself carries the angle posted (120.000000).
- Status: 0 → closed; 90 to 179 → partiallyOpen; 180 → fullyOpen. Hysteresis from closed: a jump to
  90 or 180 opens, a jump to 30 stays closed, and steps of 5 to 15° every 4 s stayed `closed` up to
  165.6° and opened at 170.3°. Closing from open: `partiallyOpen` down to 23.9° (posted 20),
  `closed` at 14.4° (posted 10).
- The app moves to the inner display when the status leaves `closed` and to the cover when it
  returns to `closed`. Closing with only the Home Screen in front puts the simulated device to sleep
  (the cover's backlight off: SpringBoard "screen is off; Backlight mode: 1"); opening wakes it.
  Closing with an app in front keeps the app, on the cover.

### Rotation

- `requestGeometryUpdate` (Sill's DEBUG `-SillOrientation`): **refused on the inner display**,
  UISceneErrorDomain 101, "The current windowing mode does not allow for programmatic changes to
  interface orientation."; **honoured on the cover** (portrait → landscapeRight in 0.3 s).
- `xcrun devicectl device orientation set --device <UDID> landscapeLeft` answers "New Device
  Orientation: landscapeLeft" and changes nothing: SpringBoard takes a Duo's orientation from
  CoreMotion's MagicPose (per display: "deviceOrientationForCover", "deviceOrientationForInner").
  Device Hub's orientation picker (duorig `orient`) rotates both displays.

### SDK tiers

An app linked against the 27.0 SDK (the probe re-stamped with `vtool -set-build-version iossim 17.0
27.0`, as TestFlight 0.5 (3), built with Xcode 27.0, is) runs in a compatibility window: on the inner
display **871×669, sideways only** (device landscapeLeft left it sideways: no laptop pose), safe area
left 34, bottom 20, right 34, the status strip outside it; on the cover **386×678**, safe area bottom
34; no reserved region of either kind, no division even half-folded. Linked against 27.1 the window is
the whole display (951×669, 669×951, 466×678, 678×466) with the strips as safe areas.

### The APIs, as the 27.1 SDK declares them

- SwiftUICore: `@available(anyAppleOS 27.1, *) struct ReservedRegion: Hashable, Identifiable, Sendable`
  with `id: ID`, `kind: Kind`, `frame: CGRect`, `margins: EdgeInsets`, `isActive: Bool`;
  `Kind.occlusion`, `Kind.division`; `QueryOptions.includeInactive` (an `OptionSet` of `Int`);
  `GeometryProxy.reservedRegions(kind:options:layoutDirectionBehavior:)` (`options` defaults to
  `[]`, `layoutDirectionBehavior` to `.mirrors`) → `[ReservedRegion]`.
- SwiftUICore: `@available(anyAppleOS 27.1, *) struct DeviceHinge: Hashable, Sendable` with
  `status: Status` (`.closed`, `.partiallyOpen`, `.fullyOpen`) and `angle: Angle`;
  `struct DeviceHingeContext: Equatable, Sendable` with `hinge: DeviceHinge?`;
  `View.onHingeChange(isEnabled: Bool = true, _ action: @escaping (DeviceHingeContext,
  DeviceHingeContext) -> Void)`.
- UIKit: `UIView.reservedRegions(kind: UIView.ReservedRegion.Kind, options: …QueryOptions = [])`,
  `UIView.ReservedRegion` (`id`, `kind`, `frame`, `margins: UIEdgeInsets`, `isActive`), kinds
  `.occlusion`, `.division`, option `.includeInactive` (`UIViewReservedRegion.h`, iOS 27.1). The older
  `UIView._boundaryLayoutRegions` is unavailable ("Use reservedRegions(kind:) with .division").
- No hinge API in UIKit, and none in XCTest or `devicectl`.
- All of these are `if #available(iOS 27.1, *)`; the deployment target stays 17.0. With the 27.1 SDK
  the app builds (Debug, simulator) with only the known `StreamClient.swift:3067` capture warning.

### What the facts touch in today's Sill (e6b3265)

- **The status bar shows.** `UIStatusBarHidden` is in Info.plist, but appearance is
  view-controller-based (no `UIViewControllerBasedStatusBarAppearance` key) and only the harness
  hides it (ContentView.swift:424). On the inner display it takes 84 pt at the right sideways and
  82 pt at the top upright; hidden, the inner display is all Sill's but the 34 pt home indicator.
  The mockups drew a 44 pt strip sideways and none upright on the inner display, and 48 pt on the
  cover; the cover's real strip is 84 pt upright (right) and on its side (left or right), status bar
  or not.
- **The book pose's right group.** `BarMetrics.regular` (StreamScreen.swift:882): buttons 66 pt,
  gap 12, padding 22; `.compact`: 64, 12, 14. Five buttons (Menus, Aa, Keyboard, Desktop, Settings)
  are 378 pt regular and 368 compact. On 867 pt (status bar showing) the group starts at 467
  (regular) or 485 (compact), both on the band (455.5–495.5); on 951 pt (hidden) at 551 or 569,
  both clear. Without Menus (four buttons, 300 pt regular) it starts at 545 on 867 pt.
- `DuoLayout.of` (StreamScreen.swift:68) sorts every real size right: book and flat sideways
  867×669 (status bar showing; 951×669 hidden) → `.innerLandscape`; laptop and flat upright 669×869
  (669×951) → `.innerPortrait`; the cover upright 382×678 → `.outerPortrait` (the phone's
  arrangement, idiom phone); on its side 594×466 → `.outerLandscape`. The stream screen's
  GeometryReader keeps the safe area but the bottom (StreamScreen.swift:258).
- The inferred crease, `(height / 2)` of a portrait 600–740 pt wide and under 1100 tall:
  `PortraitStreamScreen.halves` (PortraitStreamScreen.swift:176), `ConnectLayout.topHalf`
  (AddMacCard.swift:19), `TourPolicy.crease` (TourPolicy.swift:341), PairingOverlay (top half,
  PairingOverlay.swift:63) and HostSettingsPanel (lower half, PortraitStreamScreen.swift:201). On the
  Duo upright (669×869 with the status bar) it falls at 434.5–435 local, 516.5–517 in the window, 41
  to 61 pt below the real fold (455.5–495.5); flat, there is no fold at all and the rule still
  splits.
- `StreamClient+Viewport.screenMaximumFPS` (StreamClient+Viewport.swift:75) reads the foreground
  scene's screen: right on the Duo, 60 on both displays here.

## Harness

- **duorig** (`Tests/duorig`, TEST ONLY, private interfaces, simulator only; its README has the
  details): Device Hub's hinge and orientation events, posted from inside the simulator.
  `Tests/duorig/run.sh build`, then `run.sh UDID pose <closed-upright|closed-side|flat-portrait|
  flat-landscape|laptop|book>` and `run.sh UDID shot <pose> FILE.png` (the cover when closed, else
  the inner display). The event, read from Device Hub's code (CoreDevicePopDeviceKitExtension,
  27A9275: the dictionary built at 0x21f9c–0x2205c, `IOCFSerialize(…, 1)` at 0x2c28c,
  `HIDVendorDefined.send(usagePage: 0xff61, usage: 0x5b, version: 0, data:)` at 0x2c620): usage page
  0xFF61, usage 0x5B, version 0, data an IOCFSerialize binary dictionary with `provider`
  "com.apple.Virtualization.VirtualMachines" (the brief had "com.apple.Virtualization"), `source`
  "hinge-slider-control", `type` "range", `value` the degrees (Double, 0…180); the orientation picker
  sends `source` "orientation-picker-control", `type` "enum", `value` portrait, pud, landscape-left,
  landscape-right, faceup or facedown. In the simulator the event becomes a HingeAngle event
  (IOHIDEvent type 44, from CoreMotion's DeviceStateRelay) and a MagicPose; `run.sh UDID watch`
  shows them.
- **The simulator**: `xcrun simctl create "Sill duo" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo
  com.apple.CoreSimulator.SimRuntime.iOS-27-1`, `xcrun simctl bootstatus <UDID> -b` (28 s). Photos:
  `xcrun simctl io <UDID> screenshot --display=primary` (the cover) or `--display=primary-1` (the
  inner); the PNG follows the interface orientation. Never `recordVideo`, never the Claude iOS
  Simulator panel.
- **Sill**: `xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -destination 'id=<UDID>'
  -configuration Debug -derivedDataPath <scratch>/duo/DerivedData CODE_SIGN_IDENTITY=- ARCHS=arm64
  build` (15 s warm), `xcrun simctl install <UDID> …/Debug-iphonesimulator/Sill.app`.
- **A test host**: `swift build -c release --product SillHost`, then
  `SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 .build/release/SillHost
  --synthetic` (127.0.0.1 alone, the software encoder; its port from `lsof -nP -iTCP -sTCP:LISTEN -a
  -p <pid>`; it stops at SIGTERM, not always at SIGINT). The app:
  `xcrun simctl launch --console-pty <UDID> me.saffer.sill -SillConnect 127.0.0.1:<port>
  -SillHomeDoor plain -SillServiceType _silltest._tcp` (`-SillServiceType` keeps real Macs off the
  connect screen); `-SillSettings 1` and `-SillTourState fresh -SillTour touch` open the panel and the
  tour. The synthetic host serves no menus: the Menus button needs `SILL_TEST_MENU_PID` and
  `Scripts/menufixture.swift` (Build and run in CLAUDE.md).
- **Privacy of live photos**: the synthetic host's catalogue is this Mac's real windows (thumbnails)
  and the Settings panel and the tour name this Mac ("Noah's MacBook Pro"). Keep live photos private;
  App Store photos come from the harness's mock (`-SillLayout`), which needs the Duo's sizes and a
  stand-in for the fold (the build step).
- **Gotchas**: a process in the simulator cannot open a file under `~/Downloads` (the open blocks in
  dyld), so `run.sh` runs duorig from the simulator's own `data/tmp`; launchd_sim refuses an ad hoc
  signature that claims private entitlements ("Security policy issue"), so duorig's entitlements are
  only in its `__TEXT,__entitlements` section.

The scripts that took the baseline are in `/Users/noah/Downloads/sill-handoff/duo/probe/`
(`baseline.sh`, `baseline-extra.sh`).

## Baseline: today's Sill on the Duo

Main at e6b3265, Debug, SDK 27.1, on "Sill duo" against the synthetic host on 127.0.0.1, the
Desktop's test pattern at 55–60 fps ("client Sill duo (iPhone19,4 simulator): 57 fps, frame age
0/1 ms, rtt 0/1 ms"). Photos in `/Users/noah/Downloads/sill-handoff/duo/baseline/`, named
`<screen>-<pose>.png`: `connect-*` and `stream-*` in all six poses, `settings-*` (the Settings panel)
in all six, `tour-*` (the tour's first card) in laptop, book and flat-portrait; 21 photos at the App
Store sizes. Viewports the app sent: 851×567 (flat-landscape and book), 653×419 (flat-portrait and
laptop), 366×228 (closed-upright), 578×372 (closed-side).

- **Book (a)**: the status bar's strip takes the right 84 pt, so the bar and the picture end at 867.
  The top bar's thumbnails run on through the fold band: the fourth (x ≈ 468–528) sits on 455.5–495.5
  (no Menus button here: the test host serves no menus; on 867 pt a five-button right group would
  start on the band whatever its width, above). The connect screen's column is centred across the
  fold: its words cross it and the footer's Privacy Policy link (x ≈ 439–523) lies on the band. The
  tour's card (253.5–613.5, Skip and Next) spans the fold; the Settings panel's leading edge
  (867 − 22 − 360 = 485) is 10 pt into the band. The picture crossing the fold is as approved.
- **Laptop (b1)**: the status bar's strip takes the top 82 pt. The split is the inferred crease, half
  of 869 (435): the picture pane runs from y 82 to 517 in the window and the picture, 8 pt inside
  it, to 509, so its lowest 53.5 pt lie on and just below the fold (455.5–495.5); the window bar
  starts at about 539, below the band. The connect column, the
  tour's card and the Settings panel keep to their halves of the inferred crease (above it, above it,
  below it), which happen to clear the real band.
- **Flat portrait (b2)**: drawn as the laptop pose (the same photos but for the hinge): the picture
  pinned at half the height, the connect column in the top half, the panel in the lower half,
  though nothing is folded.
- **Flat landscape**: today's landscape layout at 867 pt wide, the status strip at the right. As
  approved, but for the strip.
- **Closed, upright (c1)**: the phone's arrangement at 382 pt wide (the right 84 pt are the camera
  and status strip, the time and Wi-Fi drawn in it), the picture 366×228 (16:10); the trackpad's hint
  wraps to two lines. As approved.
- **Closed, on its side (c2)**: the compact landscape layout at 594 pt wide (the left 84 pt hold the
  camera). As approved.
- On every screen the status bar shows (the time and Wi-Fi in the strip), which is what makes the
  inner display's strips.

## The build: decisions

Each one a default the approval left open, reversible in a line or two (where is said).

1. **The status bar hides while the hinge is open** (`DuoPosture.hidesStatusBar`, applied at the
   app's root by `DuoPostureReader`): on the inner display Sill then has 951×669 and 669×951 but the
   home indicator, where the shown status bar kept an 84 pt strip at the side sideways and 82 pt at
   the top upright out of the safe area for a clock in its corner. It is what the 27.1 SDK's "the
   whole display" buys; the approved laptop and flat boards had no strip at the top; and the book
   pose's bar then clears the fold as it is. The cover keeps its status bar (its camera's strip is
   there either way), as an iPhone does. Off the Duo nothing changes: the modifier adds nothing
   unless the hinge is open. To keep the status bar, drop the `.background { … statusBarHidden }` in
   `DuoPostureReader`; the bar rule below then steps down by itself (at 867 pt: the compact width
   and 7 pt gaps, Menus at 497).
2. **Where the fold is, from the region; whether it is in the way, from the hinge.** Each screen
   reads the `.division` region with `.includeInactive` from its own GeometryReader (in that screen's
   space, clipped to it); the region is in the way exactly while the hinge is partly open, which is
   what iOS reports (the probe) and what redraws the screens (`onHingeChange` into the environment).
   Before iOS 27.1, and on a device whose hinge is nil, the posture is `unknown` and every rule is the
   inferred one, as before (`FoldInfo.inferred`).
3. **(a) The book pose's bar keeps its size where it can.** At 951 pt the regular right group (five
   buttons, Menus counted whether it shows or not, so nothing moves when the Mac's menus come and go)
   begins at 551, 55.5 pt past the fold, so it stays as it is, the same bar as open flat; the approved
   step to the compact width, then smaller gaps down to 6, comes in only where the group would reach
   the fold (`DuoPosture.bookBar`). The strip ends 12 pt short of the fold (343.5 pt: three
   thumbnails, scrolling), and a spacer holds the fold's band empty. The Settings panel is never wider
   than the room past the fold (360 at 951 pt, at 569), the drawer stays on the leading page (22–402).
4. **(b1) The laptop pose** splits at the fold's real band in whole points: the picture's pane above
   it (0–455), the window bar, keys and trackpad from 496; the drawer and the Settings panel hang
   from the bar, below the fold.
5. **(b2) Open flat upright**, the pane takes the picture's own shape across the width (the video's
   pixels: the synthetic Desktop's 1512×948 gives a 653×409 picture, a 16:10 one 653×408) and the
   trackpad the rest; never under 160 pt, always leaving the trackpad 200. While the Mac fits a
   window to the pane (a window with Aa set, or on the virtual display) the pane stays 16:10, so it
   never follows a shape it gave the window (an app's least size would shrink it step by step). The
   split is not animated: an iPad's halves keep exactly what they had.
6. **One page for what you touch**, not only the bar: in the book pose the connect screen's column
   and footer and the pairing overlay sit on the leading page; a tour card that would cross the fold
   goes onto the page its middle is on, against the fold, never wider than a page (439.5 at
   accessibility sizes); the window lights go onto a page beside the fold, and in the laptop pose
   below their thumbnail (above it they would sit on the fold, the window bar being just under it).
   Upright the connect column, the pairing overlay and the tour's cards stay above the fold (as they
   kept to the inferred top half before); open flat they use the whole height.
7. **(c1, c2) The cover** needed nothing: the phone's arrangement at 382×678 and the compact landscape
   bar at 594×466 already sit beside the camera's strip (its safe area).
8. **The harness**: `-SillLayout 951x669`, `669x951`, `466x678`, `678x466` with the safe areas the
   probe measured (status bar hidden on the inner display), and `-SillHinge closed|half|flat`, a
   stand-in fold in the fake display's named space; without `-SillHinge` the harness knows no hinge,
   even on the Duo's simulator. The first guesses (1000×710 …) work as before.

## The build: what changed

New files: `iOSClient/DuoPosture.swift` (the pure model and rules), `iOSClient/DuoPostureReader.swift`
(the hinge, the region, the environment keys `\.duoEnvironment` and `\.duoFold`, `BarMetrics.clearing`,
`PortraitMetrics.controlsHeight`, `StreamClient.duoPaneAspect`), `Tests/checks/duo` (run.sh,
main.swift, mutants.py). Project file: AB01/FB01 and AB02/FB02. Hooks, a few lines each:
`SillApp` (`.readsDuoPosture()`), `StreamScreen` (the posture read once and handed down;
`landscape(…fold:)`, TopBar's `stripWidth`; WindowLightsMenu; DuoLayout's notes), `PortraitStreamScreen`
(`halves`), `AddMacCard` (`ConnectLayout`'s `fold`, `topRoom`, `leadingPage`), `ContentView` (the
connect screen; the harness), `PairingOverlay`, `TourPolicy` and `TourOverlay`. CI and the App Store
build: `.github/actions/select-xcode` (`allow-beta`), `ci.yml` (27.1 with betas; `duo` in the mutants
matrix), `testflight.yml` (a note), `Scripts/release-ios.sh` (Xcode 27.1 or a later 27; the app it
checks must have been built with the iOS 27.1 SDK). Checks extended: `tour` (the Duo's real sizes and
folds), `phone-portrait` (the real cover). Nothing on the wire, nothing in the host.

## The build: results

Verified 2026-10-08 (11:20–13:00) on this Mac, Xcode 27.1 RC (27A9275), the "Sill duo" simulator:

- **Checks**: `duo` 251,723 checks, 54 of 54 mutants caught; `tour` 49,614 checks, 68 of 68 (its
  crease mutant follows the call into DuoPosture, five new ones); `phone-portrait` 165, 31 of 31;
  `Tests/checks/run-all.sh`, all 36 pass (333 s).
- **Builds**: iOS Debug for the Duo simulator, Release for the simulator (generic, arm64) and Debug for
  a generic device (CODE_SIGNING_ALLOWED=NO), each with only the known StreamClient capture warning;
  `swift build -c release`, only the CaptureProbe warning. The built app says DTPlatformVersion 27.1.
- **Live, every pose** (the app against `SillHost --synthetic` on 127.0.0.1 with the software encoder,
  `-SillConnect`, posed by duorig): photos at App Store sizes in
  `/Users/noah/Downloads/sill-handoff/duo/after/` — `stream-*`, `connect-*` and `settings-*` in all
  six poses, `tour-*` (book, laptop, flat-portrait) and `tourbar-*` (book, laptop, flat-portrait and
  the cover both ways). Private: they show this Mac's windows and its name. The console, pose by pose:
  "duo: stream screen: book, the fold x 455.5–495.5 in the way, 951×669" and viewports 935×567 (book
  and flat sideways: the status bar gone, 851×567 before), 653×439 (laptop: the pane above the fold),
  653×409 (flat upright: the picture's shape), 366×228 (the cover), 578×372 (the cover on its side).
  The bar in the book pose: the strip to 443.5, nothing from 455.5 to 551, Aa at 629; the tour's touch
  card at 95.5–455.5 and its bar card at 95.5, tail at 427.5; the Settings panel at 569–929.
- **The harness at the Duo's sizes** (`-SillHinge`, the mock Mac with its menus): photos in
  `/Users/noah/Downloads/sill-handoff/duo/mock/` — the stream, Settings and connect screens in all six
  poses, the tour (book, laptop, flat-portrait, the cover), the bar card, the drawer, the window
  lights (book: on the leading page; laptop: below the thumbnail) and the pairing overlay (book: the
  leading page; laptop: above the fold). With the Mac's menus the book pose's Menus button is at 551.
- **Nothing changes off the Duo**: the harness at 25 earlier cases (the guessed Duo's four sizes with
  the drawer, Settings, connect screens, Add a Mac, the pairing overlay, the tour, the Aa ruler; an
  iPad's 834×1194, 1194×834, 744×1133 and a 700×1000 window; a phone's 440×894 and 402×812),
  photographed on the Duo's simulator with main's build (e6b3265) and this branch's, twice: 24 and
  23 of 25 identical byte for byte, the others apart by Δ1 in 2 to 427 pixels, a different case each
  pass (anti-aliasing), and no harness case knew a hinge (an earlier pass, through a stale
  intermediate build that lacked the harness's override, differed on every portrait case; rebuilt,
  none did).
- **The merge with PR #39** (`remote-away` at c3d06f0): `git merge-tree` finds one conflict, ci.yml's
  mutants matrix line (take both lists: #39's `away-*` and `link-judge`, this branch's `duo`); with
  this document's commit CLAUDE.md's Current step also meets (both add an entry at the top: keep
  both). StreamScreen, PortraitStreamScreen, ContentView, the project file and Tests/checks/README.md
  merge by themselves, and the merged tree's iOS app builds (Debug, simulator) with only the known
  warning.
- **Seen, left**: while the device turns or folds, a frame can pair the new size with the old fold
  (the console shows it once: "laptop, the fold x 455.5–495.5 …"), and the next layout pass has the
  new one; closing, the inner display takes the status bar back for a moment before the window moves
  to the cover.

## For Noah, on an iPhone Duo (a build made with Xcode 27.1)

TestFlight 0.5 (3) was built with Xcode 27.0: on a Duo it runs in the compatibility window (871×669,
sideways only). These need a Debug or TestFlight build from this branch (release-ios.sh now refuses
Xcode 27.0):

- P1 Book pose, streaming a window with menus: the picture across the fold; no thumbnail, button,
  panel, card or menu on the fold; Menus, Aa, Keyboard, Desktop and Settings on the right page; the
  strip scrolls and ends short of the fold; hold the last visible thumbnail: its lights beside the
  fold, not on it; the Menus pull-down (iOS places it): whether it keeps off the fold.
- P2 Laptop pose: the picture above the fold, the bar from just under it; the lights below a held
  thumbnail; the drawer and Settings below the fold; Pair This iPhone… above it.
- P3 Open flat upright: the picture at the window's own shape, the trackpad taller; pick a 16:9 and a
  tall window (the pane follows); set Aa: the pane goes 16:10 and the window takes that shape.
- P4 Flat sideways: today's landscape at the full 951 pt; the status bar gone on the inner display,
  back on the cover.
- P5 The cover upright and on its side: the phone's arrangement and the compact bar beside the
  camera, as on an iPhone.
- P6 Fold and unfold while streaming (book → laptop → flat → closed and back): the session goes on,
  the layout follows within a frame or two, and the Mac's window keeps its size (unless Aa is set
  or it is on the virtual display, which fit it to each new pane).
- P7 The connect screen and Add a Mac… in the book and laptop poses (the column on the leading page,
  above the fold); the tour (Settings › Take the Tour) in each pose.
- P8 The screens' rates (120 Hz on the real displays?), and VoiceOver's order in the book pose.

## Left

- After PR #39 merges: its link line (`LinkLineView`, a capsule centred at the top of the stream)
  would sit across the book pose's fold; put it on a page with `DuoPosture.offTheFold`, as the tour's
  cards are.
- CI builds the iOS app with Xcode_27.1_beta.app until the xcode-27 image has a 27.1 release (the
  notice says so); TestFlight's workflow stops at release-ios.sh until then.
- (d) TestFlight 0.5.1 waits until the iPhone Duo is out (Oct 23+); nothing was uploaded.

## Progress

- 2026-10-08 Probe (this step): the worktree and the simulator made; the probe app and duorig built
  and run through every pose; today's Sill photographed in every pose; this document. Nothing of the
  app changed. The simulator "Sill duo" and the DerivedData in the session's scratchpad (`duo/`)
  stay for the next steps; the finish step deletes both.
- 2026-10-08 Build: the pure model and its check, the reader and the hooks, the tour's fold rules,
  the harness's Duo sizes and stand-in, CI and release-ios.sh on Xcode 27.1, this document's build
  sections; every pose photographed live and in the harness; the old harness sizes compared with
  main's build; the merge with PR #39 tried. The simulator and the scratch DerivedData stay for the
  review step; the finish step deletes both.
