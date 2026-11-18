**The device's auto-lock while a window streams (2026-10-29, PR #230 from addhumal's
`device-idle-timer`, finished with maintainer edits; towards #134).** Device only: no wire change,
nothing on the Mac. The decision #151's rework left for its own PR (below: "it is its own decision").
- The rule (`DeviceIdlePolicy`, pure, `iOSClient/DeviceIdlePolicy.swift` (pbxproj AE30/FE30);
  `Tests/checks/device-idle`, 19 checks and 9 of 9 mutants, in CI's matrix): Sill holds the device's
  own auto-lock off (`UIApplication.isIdleTimerDisabled`) while one of its windows the person can see
  (its scene foreground active) streams (connected, a source streaming), until `idleLimit`, 10
  minutes (a product default), after the person last used it: input sent to the Mac, one of the
  stream screen's controls (`noteAction`), the moment it began streaming or came to the front. A
  picture being read or watched does not lock; a device left alone still locks by its own Auto-Lock
  setting, 10 minutes later than it would have, and its session ends as before.
- `DeviceIdleTimer` (StreamScreen.swift, main thread): each window's `WindowSessionObserver`
  (MacMenuHub.swift) gives its session and its UIWindow, both weak, so a window that closed leaves
  nothing, whether or not its stream screen ran its onDisappear; every look lists the windows afresh
  (each scene's activationState read then); it looks again at the scene notifications, a session's
  `connected` and `active` changes, the person's use while nothing holds (`used`), and when the hold
  would end (a timer). DEBUG: the console's `idle:` lines, `-SillIdleLimit <s>`.
- Changed from the PR as opened: its policy lived in HardwareKeyboardPolicy.swift with its cases in
  `hardware-keyboard` (both back as main has them); it kept an entry per client, updated from the
  stream screen's `onChange`s, so a window closed mid-session while another was in front kept its
  entry holding (pruned only once no scene was in front), and its `UIScene.didDisconnectNotification`
  observer removed only clients that no longer streamed, never the one it was for; it held auto-lock
  off for as long as a window streamed, so a device left alone never locked and kept the Mac
  streaming, lit and black once the Mac's display slept by its own setting (Noah's objection in the
  #151 rework); and its body's "the Mac's display sleeps and stops capture" does not hold (issue
  #134's black windows stream on, and a stopped capture is followed by the device's own Desktop
  request).
- Known: the Mac's display can still sleep before the 10 minutes are up (its own setting, counted
  from the same input): the device then shows black, lit, until a tap (with PR #228 on the Mac, one
  that clicks nothing). The device cannot tell; the host saying so would be a wire change.
- Verified (2026-10-29, on addhumal's head, which contains main at 6c5b5d24): the check and its mutants;
  `run-all.sh`, all 56; the iOS app Debug and Release for the simulator and Debug for a device, only
  the known `StreamClient` capture warning; live on a private iPad simulator (iOS 27.0, deleted
  after) against a loopback synthetic host on the software encoder, `-SillIdleLimit 10`: held 1.2 s
  in as the Desktop streamed, the device's own again at 11.2 s, held again at each of two
  `-SillInputScript` taps (14.8 s, 30.8 s) and let go 10 s after each, let go as the session ended;
  with `-SillSecondWindow 1` the hold followed the windows' scenes (let go as the second came forward,
  held again as one streamed in front).
- The verification's N1, fixed in `integration-0-6-1-fixes` (2026-11-09): what the device did by itself
  counted as the person's use, so a link or a Mac that kept dropping held the device awake for good (the
  automatic reconnect and a stream the device asked for again reset "began streaming", and the
  pointer's re-centre counted as input). Now `DeviceIdlePolicy.lastUse` of `Uses` (input the person
  sent: `StreamClient.lastPersonInputAt`, which `sendInput(_:byPerson: false)` leaves alone for the
  re-centre; a control; `personSessionAt`, from `DeviceIdlePolicy.sessionStart` in
  `StreamClient.sessionConnected(reconnected:)`, the tour's flag: the automatic reconnect carries the
  session start before it; the window's coming to the front). `device-idle` 48 checks and 17 of 17
  mutants (the rule before held the three N1 lives for good).
- **Untested, for Noah** (the iPad, a Debug build from this branch for the console's `idle:` lines,
  Settings › Display & Brightness › Auto-Lock at 1 minute): streaming and left untouched the iPad stays
  lit, and locks about 11 minutes after the last touch (`-SillIdleLimit 60` in the scheme for 2); a
  touch or a key re-arms it; Sill in the background, or another app in front in Split View, lets the
  iPad lock by its own setting; two Sill windows side by side, one streaming: lit, and closing the
  streaming one lets it lock; Low Power Mode (its 30 s Auto-Lock) the same; whether staying lit is
  wanted at all (Noah's call; the limit is one constant).
