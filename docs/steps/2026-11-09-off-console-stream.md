**This account while another user is on the screen (2026-11-09, branch `off-console-stream` from main at
f224323d; issue #316, junkaiman's; the rule, the open questions with the default taken for each, the gates and
the steps for a Mac with two accounts are in `docs/off-console-plan.md`).** Noah: "For #316, do the first
solution as you stated": an opt-in on the Mac, off by default, that brings back 0.5.5's stream of this session
while another user holds the screen, the device saying plainly that it is not the Mac's screen.
- The switch: Settings › Devices, "Show this account while another user is on the screen" (`HostConfig.offConsoleView`,
  `offConsoleView` in me.saffer.sill.mac, `SillHost --off-console-view`, `-SillSetAfter '<s> offConsoleView=1'`); the
  Mac's alone (no device sets it), applied at once by `setTarget` (the lock's gate first). Off: everything is 0.6.0's.
- The rule (`LockPolicy`, pure, `Tests/checks/lock-policy`): the off-console view applies only with the switch on, the
  gate's reading established and off console, and the console's own witness (SCDynamicStore: another user, loginwindow
  or nobody; a test host's file 2) saying so (`consoleTaken`, `offConsoleView(...)`): never a notification or the
  session dictionary, so a locked screen on the console stays 0.6.0's (the lock screen, a paired device typing). It
  shows the display, windows (captured where they are, never on Sill's virtual display), thumbnails, icons and the
  installed apps (`offConsoleViewAllowed`); nothing acts (`Allowed.actsOnWindows`: no raise, Aa size, window button or
  menu; no input, launch, gesture), and nothing of the console's goes (no sound, clipboard, pointer, cursor shape,
  virtual display or display wake). `LockGate` keeps the switch and the console's witness (SessionLock sets it at each
  look); requests are judged at arrival and now with the view (`decide(_:arrived:now:…)`, `stricter`).
- Wire (additive): `WindowList.offConsoleView` (with `locked` and `offConsole`) and `Hello.offConsoleView` (1 from a
  device that shows it); the host sends the view's list (its windows) only to such a device
  (`StreamServer.broadcastList`/`sendList`, per connection; a hello read after the first list gets it again), every
  other device 0.6.0's locked list. The frames are one stream: a 0.6.0 device keeps them under its opaque cover.
- Device: no cover and no blank for a view list; over the stream "Your account’s own desktop, not this Mac’s screen.
  Taps and keys reach it once your account is back on the screen." (LinkLineView, three lines), announced once; the
  Settings panel's header and the drawer's line (`LockedMac.viewPanelLine`), open apps only; Aa dimmed with its own
  hint; no tour meanwhile. Harness `-SillMacLocked view`. Mac: SessionLock's line "Locked: another user, or the login
  window, is on this Mac's screen; devices see this session's own desktop and windows instead, but nothing they send
  reaches it until it is back." (the view starting or ending off console says one of the two lines), a start line when
  on, the card's subtitle "Another user is on this Mac’s screen. Devices see this account, and can’t click or type in
  it." `sillclient.py --off-console-view`.
- Verified (the plan's Results): `lock-policy` 1,360 of 1,360 (184 mutants written, not run here); CI's Build and check
  green on the pull request (#340); `live.py view` 26 of 26 on loopback test hosts (the pattern streams on in the view to
  both clients, the viewer's list says `offConsoleView`, the older client's is the locked list, no sound, input and
  clipboard dropped; without the switch or by a notification alone, the placeholder). Not run: H2, the device's photos,
  the iOS Release and device builds, the mutants.
- **Untested, for Noah and junkaiman (the plan's 1–5, a Mac with two accounts):** junkaiman's boot state (B takes the
  console from an RFB login at boot; A's device sees A's desktop and windows with the line, taps do nothing; the
  console back to A: as 0.6.0); a fast user switch mid-stream; the console's display asleep while A shows (open
  question 4); the switch off and on while shown; a 0.6.0 device against this Sill.app.
