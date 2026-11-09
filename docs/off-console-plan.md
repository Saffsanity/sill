# This account while another user is on the screen: the plan

Branch `off-console-stream` from main at f224323d. Issue #316 (junkaiman), after #211 and PR #271 (a locked
Mac, shipped in 0.6.0). Noah's decision (2026-11-09): "For #316, do the first solution as you stated", the
first of the three ways in addhumal's comment on the issue: an opt-in switch on the Mac, off by default, that
brings back 0.5.5's stream of this session while another user holds the Mac's screen, with the device saying
plainly that the picture is not the Mac's screen.

## The case

junkaiman's Mac has two accounts. A, the auto-login user, runs Sill. B, a service account, gets a GUI session
at boot from a Screen Sharing (RFB) login to the Mac itself, which makes B the console's owner, so A's session
is off the console from the start, every boot. Sill is his only way in. Sill for Mac 0.5.5 streamed A's own
desktop there (ScreenCaptureKit captures an off-console session's own displays and windows: Noah's own log of
2026-10-30 and 31, build 1232, 18 to 52 frames a second). 0.6.0 refuses, by PR #271's rule (`LockPolicy`: off
console, a black placeholder and nothing else), and the device says "Another user started controlling this
Mac. Log in to your account to reactivate screen sharing with Sill.", which he cannot do from afar. He asks for
the switch in Sill's Settings on the Mac (so it can be turned on from a session already off the console, by
Screen Sharing into it or `defaults write`) and for the device to say what the picture is.

What macOS allows from an off-console session, measured by PR #271 from build 1232 and the system's logs:
display and window captures deliver frames of this session; posted input reaches nothing visible (macOS gives
synthesized events to the console's session); Accessibility actions work (a window's close) and so do
NSWorkspace launches; a CGVirtualDisplay never comes online and joins the console's display set; the sound
captured is the whole Mac's, the console user's too; DisplayWake's declaration lights the console's display;
the pointer and the cursor shape are the console's.

## The rule

A new setting, the Mac's alone: **Show this account while another user is on the screen**
(`HostConfig.offConsoleView`; Sill.app's Settings › Devices, saved as `offConsoleView` in me.saffer.sill.mac;
SillHost's `--off-console-view`). Off by default in Sill.app and the CLI. No device sets it: it is absent from
`StreamSettings`, `HostSettingsChange`, `DeviceSettings.accepted`, `applying` and `restartNeeded`, as Share
clipboard and Remote Access are. Applied at once (`setTarget`), never by a restart of its own.

With it off nothing changes anywhere: every reading, list, line and frame is 0.6.0's.

With it on, while the Mac reads **off console** (another user's session, the login window, or nobody on the
console) and the console's own witness says so (below), the devices get **the off-console view**: this
session's own desktop and windows, to look at, and nothing they send acts on it.

| | off console, 0.6.0 (and the switch off) | the off-console view |
|---|---|---|
| The picture | the placeholder (a black still, no capture) | the Desktop's display (this session's own desktop), or a window picked |
| Windows: listed, picked, captured, thumbnails | no | yes, captured where they are (never on Sill's virtual display) |
| Icons and the installed apps | withheld | sent (the drawer's open apps need the icons) |
| Acting on a window: raised and made key at a pick, sized by Aa, its buttons (kind 15), its app's menus (read and chosen) | no | **no**: each is an Accessibility action in this session, which a person at the device cannot follow through |
| Launches (kind 7) | no | **no**: an app opened where nobody can use it, its first window picked |
| Sound | no | **no**: off console the sound captured is the whole Mac's, the other user's too |
| Clipboard | no | **no**: nothing can be copied or pasted in this session meanwhile, so it has nothing to carry, and a device's text would land where nobody pastes |
| The Mac's pointer (26) and cursor shape (14) | no | **no**: both are the console's, another user's |
| Gestures (28) | no | **no**: posted chords land nowhere, as all input |
| Sill's virtual display | none | **none**: one never comes online off console and joins the other user's displays |
| Input (8) | nobody's, but the up of what is held | the same: nobody's (macOS posts nothing into this session) |
| Display activity (DisplayWake) | never | **never**: it would light the other user's screen and reset their idle timer |

In short: the switch widens what is **shown** in that one state, never what **acts**. Nothing is shown that
0.5.5 did not show (it showed all of the above and more), and nothing is typed, clicked, raised, sized,
pressed, launched or posted.

### When the view applies: the console's own witness, never a notification or the session dictionary

`LockPolicy.consoleTaken(witnesses)`: the console's user (SCDynamicStore, State:/Users/ConsoleUser, watched and
read at each look) is another user, loginwindow or nobody, or a test host's file says 2. Not a switch-away
notification (any process can post one: a spurious one must never turn a locked screen into a shown desktop),
not the session dictionary (read at start and to confirm an unlock: a stale "off console" could outlast the
return to the console while the screen is locked), not an unreadable or unread console witness (unknown counts
as locked, never as shown). `LockPolicy.offConsoleView(reading:established:consoleTaken:switchOn:)` is true only
when all four hold: the switch on, the gate established, its reading off console, and the console taken. So:

- **This session's own locked screen on the console stays exactly as 0.6.0 has it**: the reading is screen
  locked there, never off console, and the view never applies. The lock screen streams, a paired device types
  at it.
- A note that comes before the console's user changes (a user switch's notifications can lead it) gives 0.6.0's
  placeholder for that moment; the view follows the console's witness.
- Back on the console: the console's witness is this user at once, so the view ends at once, before the settle
  that holds an unlock 2 s; the lock screen or the placeholder (0.6.0's) meanwhile, never this session's desktop.

### The gate

`LockGate` keeps, beside the reading, the switch (`setOffConsoleView`, from the coordinator's target) and the
console's witness (`consoleTaken`, from SessionLock's every look), so the server, on its network queue, sends
by `LockPolicy.withheld(kind, picture:, reading:, offConsoleView:)` from the moment either changes: in the view,
the display's and a window's frames, thumbnails, icons and the app list go; the sound, the clipboard, the
pointer and the cursor shape never. SessionLock calls `onChange` when the view starts or ends as when the
reading changes, and prints its line.

### A device's requests

`LockPolicy.decide(_:reading:paired:offConsoleView:)`, each request judged at its arrival's reading and at now's
(the view as it is now), the stricter answer winning: in the view a window pick is taken (a restart, never a
raise), the Desktop and nothing as ever, and a launch, a window's buttons, a menu fetched or chosen, a gesture, a
device's clipboard text and input are refused as off console. A pick that arrived while the screen was locked
is refused even if the view applies when it is handled. With the switch off every decision is 0.6.0's (the
check proves it for every request, reading and pairing).

### The stream

- Going off console with the view: the window that streamed goes on streaming (a staged one leaves Sill's
  virtual display first and streams where it is, as a restart); the Desktop's placeholder gives way to the
  display; nothing streaming with a device connected starts the Desktop (`enforceLock`). A capture that stops
  at the user switch (the displays change) is asked for again by the device as today (the Desktop at once; a
  window stays listed, so its thumbnail picks it again).
- The view ends while still off console (the switch turned off, or the console's witness no longer says so):
  0.6.0's placeholder, at once (the server's gate first, then the coordinator).
- Back on the console: 0.6.0's way from off console (the lock screen while locked, the window that streamed
  back after the unlock).

### What the devices are told (wire, additive)

- `WindowList.offConsoleView: Bool?`, true only beside `locked` and `offConsole` while the view applies; left
  out otherwise, so every other list is byte for byte 0.6.0's.
- `Hello.offConsoleView: Int?`, 1 from a device that shows the view (this build on); nil from every device
  before. The host sends the view's list (with windows and `offConsoleView`) only to a device whose hello said
  so, and 0.6.0's locked list (no windows) to every other (`StreamServer.broadcastList`, per connection, as
  kind 16 already is): **an older device behaves as with 0.6.0** (0.6.0's cover and empty drawer; a device from
  before 0.6.0, which reads neither key, an empty bar). The frames are one stream for every device: a 0.6.0
  device keeps them under its opaque cover; one from before 0.6.0 shows them, as it showed 0.5.5's, its taps
  dropped. **An older Mac sends nothing new**: the device behaves as 0.6.0's.

### The device

At a list with `offConsoleView`: no cover and no blank (the picture is live), the windows and their thumbnails
as ever, and:

- over the stream, where the link's line goes (it takes the line's place while it lasts, and shows while
  nothing is open over the stream): "Your account’s own desktop, not this Mac’s screen. Taps and keys reach it
  once your account is back on the screen." (three lines at most); VoiceOver hears it once when it comes;
- the Settings panel's header and the Apps drawer (above its open apps, no All apps): "Another user is on this
  Mac’s screen. You’re seeing your account’s own desktop and windows, not the screen. Taps, keys and opening
  apps wait until your account is back on it.";
- Aa dimmed (no window is sized), with VoiceOver's hint "Available once your account is back on this Mac’s
  screen."; the Menus button and Paste gone (the list has no `clipboard` and the Mac's menus no app), as at a
  locked Mac;
- the tour waits for the view to end.
Input still goes (the host drops it, one line a minute), as under 0.6.0's off-console cover.

### The Mac

- The log (SessionLock's line at the change): "Locked: another user, or the login window, is on this Mac's
  screen; devices see this session's own desktop and windows instead, and nothing they send is posted, until it
  is back." With the switch off, 0.6.0's line. When the view starts or ends while the Mac stays off console,
  the matching one of the two lines.
- The status card (seen in this session's own menu bar, through the stream or Screen Sharing): the header as
  ever and, while the view applies, the subtitle "Another user is on this Mac’s screen. Devices see this
  account, and can’t click or type in it."

## Open questions, with the default taken

1. **The pane and the words.** Settings › Devices, after Show the pairing window to screen sharing (both are for
   a Mac used from afar), "Show this account while another user is on the screen", with a footnote of what it
   does and cannot do. No menu item (junkaiman: "and in the menu, if you like"): a switch set once. Default
   taken; Noah may move it.
2. **Windows, or the Desktop alone.** Windows too (the task's "desktop and windows", 0.5.5's), captured where
   they are. A covered window may show its last picture until it repaints (macOS stops repainting covered
   windows, and nothing raises it in the view).
3. **Raise and Aa in the view.** Neither (Accessibility actions in a session nobody at the device can use).
   0.5.5 raised a picked window; the view does not.
4. **Display wake.** Never in the view. If a two-account Mac shows this session's picture black while the
   console's display sleeps, the follow-up would be to declare activity, which lights the other user's screen:
   Noah's call then.
5. **Older devices.** 0.6.0's list and cover (the hello says who can show the view), the frames shared.
6. **The installed apps.** Sent (the drawer shows only the open ones in the view); launches refused.
7. **The status menu.** No item; the card's subtitle only.

## Gates

- `Tests/checks/lock-policy` extended (the view's allowance against every reading with the switch on and off,
  `consoleTaken` over every witness combination, the gate, the requests with the stricter of arrival and now,
  the lists both ways, `reconciles`, `Restore`, the lines, the device's words and cover, and the coordinator's
  glue with the switch in its directed and random sessions), and its mutants, in CI's matrix as before.
- `Tests/checks/run-all.sh`; `swift build -c release` from a clean copy; the iOS app, Debug and Release for the
  simulator and Debug for a device.
- H2: the CLI against main, idle and with a test client, masked and sorted: identical (the switch off).
- Previews from the bare binary: identical to main's but the Devices pane's new section and a card sample.
- Live on loopback test hosts (`--synthetic --off-console-view`, `SILL_TEST_LOCKED_FILE` 2,
  `SILL_TEST_LOCK_IGNORE_MAC=1`): the test pattern's frames go on off console with the switch, the placeholder
  without; a viewer's list carries `offConsoleView`, an older client's does not; input dropped; no sound,
  clipboard or pointer; a notification alone (`SILL_TEST_LOCK_NOTE`) never shows the view; the switch flipped
  while off console. Not here: a real second account (this Mac cannot switch users), window capture off
  console (test hosts never ask ScreenCaptureKit).
- Photos from the harness (`-SillMacLocked view`) at an iPad's and an iPhone's size and a large text size.

## Untested, for Noah and junkaiman

On a Mac with two accounts, Sill.app from this branch with the switch on, an iPad or iPhone from this branch:
1. junkaiman's boot state: B takes the console by a Screen Sharing login at boot; A's paired device connects:
   A's desktop streams with the line over it; its windows pick; taps and keys do nothing; Sill.log has the view's
   "Locked:" line. Then the console back to A (fast user switch from the VNC client): within a second or two the
   lock screen or A's windows, as with 0.6.0.
2. A fast user switch mid-stream (a window streaming, then B): the window or the Desktop goes on with the line;
   switch back: the lock screen, then the window after the unlock.
3. The console's display asleep (`pmset displaysleepnow` from B, or the Mac's own timer) while A is shown:
   whether A's picture stays live (open question 4).
4. The switch turned off while A is shown: the cover at once; on again: A's desktop back.
5. A device on 0.6.0 against this Sill.app in the view: 0.6.0's cover, an empty bar.
