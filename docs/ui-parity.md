# UI parity: the Android, Windows and Linux apps against the Apple ones

The request (2026-10-18): "Audit the existing UI components, styling tokens, and layout structures
for the currently supported platforms, then align the new Windows, Linux and Android UI
implementations to match them with 1:1 visual and functional parity", reusing the existing tokens
and primitives, adapting each platform's own conventions, with state and animation behaving the
same, and no layout regression on the Apple platforms. Then: "support all foldable phones,
including the new 4:3 Z Fold 8."

## The rule

The Apple apps are the design's source of truth and nothing under `iOSClient/`, `Sources/` or
`Package.swift` changed for this. The other apps never copy a number or a word by hand: they read
the iOS app's own, generated or checked by a tool, so a change on the iOS side fails CI until the
other side follows.

- The clients (Android, Windows) match the iOS and iPadOS app.
- The PC hosts (Linux, Windows) match Sill.app, the Mac's menu bar app.

## How the iOS app's design reaches the other apps

`clients/design/` (run by CI's core job: `clients/design/generate.sh --verify`):

- `extract_tokens.py` reads the iOS app's Swift at anchored places and writes
  `core/ui/Tokens.kt`: the palette (`Palette`, `LightColors`), the bar and portrait metrics
  (`BarMetrics`, `PortraitMetrics`, the phone's from `PhonePortraitLayout`), every literal size,
  radius, alpha and duration the screens draw with (`object Ui`), and the animation curves
  (`Motion`: SwiftUI's easeOut/easeInOut and springs by duration and bounce).
- `swift/main.swift` compiles the iOS app's pure layout code as it is with swiftc (also on Linux):
  `PhonePortraitLayout.swift`, `HostSettingsLedger.swift` with `HostSettings.swift`, and
  `DuoPosture.swift`, and dumps what they compute over grids of sizes, keyboards, pictures and folds
  into `core/src/test/resources/sill/ui-vectors.json`. The Kotlin ports are held to it
  (`UiParityTest`, `DuoPostureTest`).
- `check_copy.py`: every word in the core's `Copy` and `PanelCopy` must still be in the iOS
  sources (`PlatformCopy` holds the few with no iOS counterpart: a pasted pairing link where iOS
  scans a code).

`clients/core/src/main/kotlin/me/saffer/sill/core/ui/` (pure Kotlin, used by Android and the
desktop):

- `Tokens.kt` (generated), `Design.kt` (colours, sizes, the type ramp, the curves' maths).
- `PhonePortraitLayout.kt`, `DuoPosture.kt` (`FoldInfo`): line-for-line ports.
- `StreamLayout.kt`: which arrangement a screen gets (landscape bar, the halves, the phone's),
  every rect of it, the connect column, the Aa ruler's steps.
- `StreamUi.kt`: the stream screen's state machine (drawer, Settings panel, keyboard before and
  after Settings or Menus, the ruler, the window lights, latched keys), the same transitions as
  `StreamScreen`'s.
- `SettingsPanel.kt`: `SettingsLedger` (`HostSettingsLedger`), the panel's words.
- `KeyRow.kt`, `Trackpad.kt` (`PadTracker`: TrackpadSurface's relative pointer, slop, taps, hold
  then drag, two-finger scroll with its coast, latched modifiers), `Symbols.kt` (the SF Symbols
  drawn as plain vectors: SF Symbols may only ship on Apple's platforms), `Copy.kt`.

A settings change takes its token from the session alone (`SillSession.changeSettings { token ->
ledger.pick(...) }`), so the ledger and the Mac's answer always agree.

## Android (`clients/android`)

At parity, from the shared layer: always dark on black, 1 pt = 1 dp, the type capped at the iOS
app's largest size; the connect screen (rows, Add a Host… as a card in the column, the footer); the
stream screen at `StreamLayout`'s rects: the landscape bar, the window strip (halo, badge, fade;
hold for the lights, keep holding to reorder, with the iOS springs), the Aa ruler, the Apps
drawer, the Settings panel with Disconnect at its foot, the phone's rows, keys and trackpad, the
tablet's halves; animations on the iOS curves (with animations off in the system's settings, only
fades).

Keep Screen On (2026-10-19, both apps): the Settings panel's This iPhone, iPad, phone or tablet
group ends with it, on by default, `Sill.keepScreenOn`, never sent to the Mac. While it is on and the
stream screen shows, the screen never dims or locks by itself: iOS's idle timer off (`ScreenAwake`, a
claim per stream screen, so two windows count), Android's `FLAG_KEEP_SCREEN_ON` on the stream's
window. Off, Auto-Lock and the screen timeout apply as elsewhere. Its words are `PanelCopy`'s and the
iOS app's (check_copy.py).

Android's own: edge-to-edge insets; system gesture exclusion over the strip, the trackpad and the
ruler; every target at least 48 dp (the 44 pt caps take the gap beside them); Back closes the
ruler, the lights, the drawer, the panel, then goes home with the session kept; a hardware
keyboard's Esc closes what is open; TalkBack names from `Copy`; haptics where iOS has them.

### Foldables

`FoldReader` reads the fold with no AndroidX: the platform's own window extensions
(`androidx.window.extensions`, an optional shared library of the system image, reached by
reflection), else Samsung's older sidecar, else the hinge-angle sensor. `FoldMapping` turns that
into the iOS app's `FoldInfo`, with the iOS rules after it:

- Half-open (the book pose, the laptop or tabletop pose, a flip phone in Flex mode): the band,
  at least the Duo's 40 pt thick, clipped to the view. Nothing interactive sits on it; the laptop
  pose splits the halves at the real fold; the book pose keeps the bar, cards and overlays off it.
- A foldable open flat: no band, the picture takes its own shape (the Duo open flat).
- No fold to report (an ordinary phone or tablet, a Fold on its cover screen, a closed hinge): the
  iOS app's inferred rule, what every iPhone and iPad gets, so a tablet's halves split at the
  middle exactly as an iPad's do.

Two cases the iPhone Duo never meets: a fold across a screen held sideways (a Fold in tabletop, a
Flip half-open) splits the halves at it when the controls fit under it, and a fold down an upright
screen keeps the halves on their pages. `FoldablesTest` checks real foldables' sizes in each
posture (which arrangement, nothing on the band or off screen, 48 dp targets): Galaxy Z Fold 8
(4:3 inner display; its size in dp guessed until measured), Z Fold 5 and 6, Pixel Fold, Pixel 9 Pro
Fold, OnePlus Open, Z Flip 5 and 6, Razr. A Flip's cover screen is too small for a picture
(documented there).

Rendered without a device (2026-10-18): the activities drawn by Robolectric's native graphics (the
framework's own drawing on the JVM, a scratch harness, not committed) at phone, tablet and foldable
sizes. It found a crash at every launch on Android 11 and later (`Look.edgeToEdge` read the window's
insets controller before its decor existed) and rows of paired Macs without their way in, both fixed.

### The Mac's menus (Android and the Windows client)

`MacMenuState` (core/ui) is the iOS app's MacMenuState rule for rule (the top level, one fetch per
menu with the title it was shown under, an answer settling only its token, a new tree settling the
rest with "The menus changed…", the timeout max(4 s, 4 × the worst round trip), stale apps, presses
never for a disabled row, sections, "‹n› more on the Mac", a top-level menu asking by what it
showed); `MacMenus` runs it on the UI's thread with the tokens and the timeout. The session
subscribes at its first window list, as the iOS app does, and the stream layouts already held the
Menus slot: the button now shows while the Mac sends a top level or a note. Each menu is read from
the Mac when it opens, never cached. Android: a PopupMenu of the top level; a menu replaces it with
its own, headed by its title (Android's own submenus do so), sections as group dividers, a check
for a mark, the shortcut as text after the title. The Windows client: a cascading Swing menu,
"Loading…" until the Mac answers, the shortcut at the right of each row. `MacMenuStateTest` (the
rules, and subscribe, open and choose against the model Mac) and `:desktop:uiTest` (the menu's
titles, File read from the Mac, Save chosen there) check it.

### Not at parity on Android

The first-run tour, Pair This Device's overlay over a stream, the clipboard chip,
Larger Picture, the Settings panel's route word and its Away from home section, and the Mac's
cursor shapes (a plain arrow).

## The Windows client (`clients/desktop`, `clients/swing-ui`)

`clients/swing-ui` holds the controls drawn from the core's tokens, with no client types, so the
PC host reuses them: the bar button, key cap, Aa button and its ruler, the window strip with its
lights menu, the row list, the Apps drawer, the Settings panel and its rows (menu picker,
segmented control, switch, footnote, callout), the trackpad well (driving `PadTracker`), the dim
behind sheets, a dark text field, dark scrollbars, and `Animator` on the core's curves. The stream
window places every control at `StreamLayout.of(...)`'s rect (the landscape bar, and the halves in
a tall window), opens and closes everything through `StreamUi`, and shows the `SettingsLedger`'s
view; the connect window is the iOS connect screen with Add a Host… as a card in the column.

Windows' own: the native frame and its buttons kept; Esc closes the ruler, the lights, the drawer,
the panel, then goes to the Mac; Tab moves through the bar with a focus ring only then; 1 pt = 1
logical pixel (Java2D's per-monitor scaling), the video and thumbnails at device pixels; a minimum
window of 632×440; 120 fps asked of a Mac on a display of 100 Hz or more.

Checked: `:desktop:uiTest` under Xvfb at 100 % and 200 % (every control's rect against the layout,
the palette's colours at 100 %, the drawer, panel, lights, ruler and trackpad driven, input reaching
the model Mac, Disconnect), screenshots in `clients/desktop/build/ui-shots/` (CI keeps them).

Not at parity: the title bar stays the system's light one (a dark one needs DwmSetWindowAttribute,
native code on JDK 17); three- and four-finger gestures, the pairing row's highlight.

Device checks: W7 the window at 100 %, 150 % and 200 % on real Windows, and moved between monitors
of different scaling; W8 Narrator through the bar and the panel; W9 a precision touchpad's two-
finger scroll over the picture.

## The PC hosts (`clients/host-core`, `clients/host`)

The Windows and Linux hosts match Sill.app, the Mac's menu bar app, adapted to a PC's tray:

- `HostStatusText` (host-core, pure): StatusText.swift's headline order, the source row ("W×H · N
  of M fps · X Mbps", "M fps, still", the route with one device), the device rows ("–" for a second
  without a sample), shortName, middleTruncated(44), the tooltip, the glyph, "‹device› Wants to
  Pair", with "this PC" for "this Mac". `HostMenu`: MenuBuilder's order (the card, attention items,
  Frame Rate, Quality, Resolution, Launch at Login, Pair a Device…, Show Log…, Settings…, Quit);
  what a PC host has no counterpart for (the virtual display, Direct Wireless, Remote Access,
  macOS's permissions, the update offer) is left out.
- `QrCode` (host-core): byte mode, level M as CIQRCodeGenerator's default, versions 1–40, the
  standard's masks; identical module for module to python-qrcode 8.0 on real pairing links
  (`src/test/qr/generate.py`, `qr-vectors.json`).
- `host/ui`: the tray click opens a borderless popup with the 300 pt card and the menu (22 pt rows,
  subtitles, checkmarks, submenus, Ctrl shortcuts, the accent highlight, arrows and Enter, Esc or
  a lost focus closes it); with no tray, the same in a "Sill Host" window. Settings: General,
  Devices, Streaming as 520 pt grouped forms with switches, in Sill.app's words. The pairing window:
  440 pt, the QR code at whole device pixels per module, the code at 22 pt monospaced, its states
  (waiting, asked by a device, a wrong code, expired, stopped, paired), brought forward when a
  device asks. The log window. Colours are macOS 26's, as Sill.app's own previews draw them
  (measured from `-SillRenderPreviews`: the window white or #171717, a group's rows 3 % over it with
  no stroke, buttons filled at 8 % with no stroke, groups 10 pt round), light or dark as the PC is
  set (Windows' AppsUseLightTheme, GNOME's color-scheme; dark otherwise). They were macOS 14's
  (a grey window, white rows and white buttons, each with a hairline) until this was compared
  side by side with Sill.app's previews.
- Share clipboard with devices (Settings › General, on by default, as Sill.app's): off, the window
  list stops offering the clipboard and nothing is read or sent. A copy a password manager marks as
  concealed is never read, judged by its formats before any text, as Sill.app's ClipboardPolicy:
  "ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore" and
  "CanIncludeInClipboardHistory" holding 0 on Windows, "x-kde-passwordManagerHint" holding "secret"
  on X11, and the nspasteboard.org markers (`ClipboardConcealedTest`: another process owns the
  clipboard with the marker beside the text, as the password manager would; before this the PC
  host sent every copy, passwords included).

Checked: host-core's tests; `HostUiTest` under Xvfb (the widths, row heights, menu order and words,
the hover highlight, every QR module's pixel at 1x and 2x in both appearances, each control
changing the host, a device's ask bringing the window forward; screenshots kept by CI); the
packaged host's self-test.

Not at parity: the update section and renaming a paired device (no backing feature on the PC host
yet); the card's digits are not tabular (Java2D cannot turn that font
feature on); the window chrome is the system's.

Device checks: H8 the tray popup's place and focus on Windows 11 and on a GNOME and a KDE desktop;
H9 the dark/light reading and Launch at Login on each; H10 an iPhone scanning the pairing window's
QR code.

## Device checks (none of this has run on a device or an emulator)

- F1: on a Galaxy Z Fold 8, whether the window extensions report the fold (`adb logcat -s
  SillFold`): its bounds and state open flat, half-open both ways, and on the cover.
- F2: the book pose sideways: the bar clear of the crease; the laptop pose upright: the picture
  above, the trackpad below; flat: the iPad's halves at the picture's shape.
- F3: a Z Flip in Flex mode: the picture above the fold, the controls below.
- F4: folding and unfolding mid-stream: one viewport per change, the session kept.
- F5: a plain Android tablet upright: the halves at the middle, as an iPad's.
- F6: TalkBack through the bar, the strip's actions and the panel; Back's order.
