# Immersive on an iPad with a hardware keyboard — the plan

2026-10-18. Branch `immersive` from origin/main at 5c323e6. Proposed by a contributor (Pearse
Taggart), from a PRD written against main on 2026-10-17; no issue yet. It carries the iPhone's
Larger Picture idea (issue #58, PR #79, docs/larger-picture-plan.md) to the iPad, which #79 left
unchanged. It builds on the host half of PR #156 (dr-apple, "Desktop in full screen on a display of
the device's own size"), carried here as a commit of its own under dr-apple's name: if #156 lands
first, a rebase drops that commit and nothing else changes.

## The problem

On an iPad Pro with a Magic Keyboard, sideways, the stream screen is `TopBar` (86 pt,
`BarMetrics.regular`) over `contentArea`, which insets the stream 8 pt and rounds it 12 pt, under
the status bar. With a keyboard and trackpad attached most of the bar is redundant, and on iPadOS
26 and later the Mac app's menus are in the iPad's own menu bar too. Someone using the iPad as a thin
client to a Mac wants the Mac's picture on the whole display, and the bar back only when asked for.

The Desktop has a second problem: it keeps the Mac screen's shape (16:10 or 16:9), so on a 4:3 iPad
it letterboxes whatever the layout does. Only the Mac can fix that, by giving the Desktop a display
of the iPad's shape, which is what #156's host side does.

## Decision

### In one paragraph

Settings › This iPad gains **Immersive** (off by default; `Sill.immersive`,
`StreamClient.immersiveKey`, never sent; offered on an iPad only, `immersiveOffered`). With it on, a
hardware keyboard attached, the iPad sideways, something streaming, VoiceOver off and Sill filling
the screen (`ImmersivePolicy.applies`), the landscape stream screen drops the bar, the inset, the
frame, the status bar and the home indicator, and the panel is the whole screen: one viewport, and
the Mac refits a window as after a rotation. ⌃⌥⌘B or a swipe down from the top edge brings the bar
back over the picture without resizing it; it hides after 4 s untouched, or on ⌃⌥⌘B again. The
revealed bar has an **Exit** button that turns the switch off at once. While the Desktop streams,
the viewport also says `deviceDesktop`, and a host that has #156's `DeviceDesktop` makes a display of
the iPad's size the Mac's main display, so the Desktop fills the iPad with no letterbox.

### The rule

1. Immersive applies only with all of: the switch on (as it was when Settings opened, while Settings
   is open: `immersiveHeld`, as `largerPictureHeld`), a hardware keyboard attached
   (`HardwareKeyboardMonitor`), the iPad sideways (`.innerLandscape`), a window or the Desktop
   streaming (nothing streaming keeps the bar, so a first picture never lands in a layout that then
   flips: Larger Picture's rule 12), VoiceOver off, and Sill's scene filling the screen
   (`ImmersivePolicy.fills`: not a Stage Manager or Split View window).
2. Three states (`ImmersivePolicy.State`): `off`, main's layout; `immersed`, no bar and the panel the
   whole screen; `revealed`, the bar over that same panel. Only a move between `off` and the other
   two changes the panel's size. Revealing and hiding never send a viewport.
3. One view tree in all three (`landscape(…immersive:)`): the bar is drawn over a spacer of its own
   height when off, so toggling never rebuilds the stream's input view and the hardware keyboard's
   hold survives.
4. ⌃⌥⌘B (`ImmersivePolicy.isToggle`: HID 0x05 with control, option and command) toggles `immersed` and `revealed`, through both
   a `UIKeyCommand` (priority over system behaviour) and `pressesBegan`, de-duplicated, and never
   reaches the Mac while Immersive applies. When it does not apply, the chord is the Mac's.
5. A downward drag that starts within 20 pt of the top edge reveals the bar
   (`ImmersivePolicy.revealsFromEdge`, `edgeZone`, judged from the touch's landing point). The top edge's system
   gestures are deferred while Immersive applies, so the first swipe is Sill's, not Notification
   Centre's.
6. Anything that opens over the stream (Settings, pairing, the tour, the Apps drawer, Menus, the Aa
   ruler, a thumbnail's lights) holds the bar revealed until it closes; the last one closing leaves it
   up for the full 4 s.
7. Exit (the revealed bar only, between Desktop and Settings) closes Settings if open, then turns the
   switch off: the layout goes back to main's in one motion and one viewport.
8. The Desktop while Immersive applies: the viewport carries `deviceDesktop: true`; leaving Immersive
   or picking a window sends one without it. An older host ignores the key and letterboxes as before.

## Open questions (the default is taken unless Noah says otherwise)

1. The shortcut. ⌃⌘F is macOS's Enter Full Screen and stays the Mac's; ⌃⌥⌘B is the default.
2. Immersive needs a hardware keyboard. Touch-only Immersive would hide the trackpad's controls.
   Default: keyboard only.
3. Portrait, whose key row and trackpad could go with a keyboard attached. Default: later.
4. The device desktop makes a virtual display the Mac's MAIN display while it streams: the menu bar,
   the Dock and windows move to it, and back when it goes. That is #156's design (Screen Sharing's
   High Performance mode does the same). Default: taken with #156; a host setting could refuse it.
5. iPadOS-reserved chords (⌘Tab, ⌘Space, ⌘H) never reach `pressesBegan`. Out of scope.

## Results

- `Tests/checks/immersive`: 71 checks, 37 of 37 mutants caught (in CI's matrix).
  `Tests/checks/run-all.sh`, all 45; `protocol` and `compatibility` with `deviceDesktop`.
- The iOS app Debug for the simulator and for a device, Release for the simulator; `swift build -c
  release`; known warnings only.
- The touch rig against main's: 72 of 72 (the top edge's scenarios behind `-D IMMERSIVE`).
- Harness photos with the switch off against main's build (iPad Pro 13" simulator, mock Mac):
  sideways, sideways with no keyboard and the switch on, upright, upright with the drawer:
  identical. Sideways with the drawer open: within 16/255 at the edges of three thumbnail badges
  (anti-aliasing), the same in two runs of each build. Settings: the new Immersive row and
  footnote.
- Harness, iPad Pro 13" simulator, `-SillLayout 1376x1032`, live against a host on loopback:
  switch off, `viewport: 1360×930`, main's layout; on with `-SillHardwareKeyboard 1`, one
  `viewport: 1376×1032 … device desktop`, the host's "Device desktop 1376×1032 pt @2× … main" and
  "Streaming the device's own desktop … 2752×2064"; ⌃⌥⌘B revealed and the bar hid itself after 4 s
  with no new viewport and no capture restart; Exit, `immersive: Exit: the switch off`, one
  `viewport: 1360×930`; quitting removed the display and the real one was main again.
- On an M4 iPad Pro 13" with the Magic Keyboard against `SillHost --virtual-display --pairing`
  from this branch (2026-10-18): the Desktop edge to edge, the bar on demand, Exit back to the
  standard layout.

## Untested

- Rotation and an Aa step while immersed on the Desktop (the host should remake its display).
- Two devices at once, one immersed on the Desktop.
- Stage Manager and Split View on a device (judged by `fills`; tested only by the harness bypass).
- VoiceOver on a device.
- Sill.app (rather than the CLI host) from this branch.
