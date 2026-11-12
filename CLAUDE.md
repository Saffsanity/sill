# Sill

Open-source, free app that streams individual Mac app windows to iPhone and iPad
(designed for iPhone Duo first), with a free Mac companion. Tip jar, no
subscription, no servers. Read `docs/BRIEF.md` before doing product-level work.

Formerly winstream; the folder still carries the old name.

## Steps

What each piece of work did (a branch, a release, a finding) is in `docs/steps/`, one file each,
named `<date>-<branch>.md` with the date the work began, so the newest are last by name:
`Scripts/steps.sh list` prints the newest first (or `ls docs/steps | sort -r | head`);
`Scripts/steps.sh find 349` finds a pull request's (or `grep -l '#349' docs/steps/*`), and
`ls docs/steps/*keep-vpn*` a branch's. Before starting, read the step file of the work you continue
and the newest few.

A branch writes its notes in its own step file (`Scripts/steps.sh new` makes it), never in this
file, so no two branches edit the same lines for their notes. Until 2026-11-12 the notes were this
file's "Current step", newest first; they moved word for word, and `docs/steps/README.md` lists them
in that order. A code comment that cites `CLAUDE.md, "<title>"` (or "Current step") means the step
file with that title: `grep -l '<title>' docs/steps/*`. A branch opened before the move runs
`python3 Scripts/migrate-notes.py` once, right after merging main (the script's header says how).

Rules found in the steps that hold for all work (each where it is written):
- While Noah streams, nothing that shares the Mac's one video encoder: no `simctl io recordVideo`,
  SillHost stream, ReelRenderer or encoder benchmark, and no Simulator panel in the Claude app
  (docs/steps/2026-09-24-encoder-recovery.md, "Operational rule").
- Host code: `SillHostCore`'s `package` access, never `MainActor.assumeIsolated` in core code, the
  modal-loop rule, the CLI's byte-identical stdout, App Nap; TCC and the signing identity
  (docs/steps/2026-09-23-menu-bar-app.md, "Rules." and "TCC:").
- ScreenCaptureKit sends frames only when a window repaints, so a covered window freezes on the
  device (docs/steps/2026-09-22-milestone-1.md, "Learned"), and AWDL takes the Mac's radio off its
  Wi-Fi channel (docs/steps/2026-09-22-trackpad-stutter.md).
- Simulators: harness photos on the agents' own pair only, through `Scripts/harness-photos.sh`, which
  keeps the rules itself (one booted at a time, inside the heavy lock, never one Noah made, nothing
  that reaches a Mac); no agent makes or deletes a simulator of its own for photos
  (docs/steps/2026-11-12-tooling-speedup.md).

## Layout

- `Package.swift` — SwiftPM. Products: `StreamProtocol` (shared wire format,
  iOS + macOS), `SillHost` (the CLI, target `SillHostCLI`) and `SillMenuBar`
  (Sill.app's executable). `SillHostCore` (the host, folder `Sources/SillHost`)
  is a library target with no product, so the iOS project never sees it.
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions, HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, with the host's per-launch `launchID` and, while the Mac is
  locked, `locked` and `offConsole`; `WindowInfo`, `AppInfo`, `StreamSource`),
  `LockedMac` (the device's words for a locked Mac: why, the drawer's and the
  panel's line, the cover over the stream and its "Unlocking…", checked with the
  host's LockPolicy) and image blob framing. `Viewport.swift` —
  `Viewport` (kind 9: the device's panel, Aa's scale and its rate),
  `ClientStats` (with `lateSince`, a host's count of a device's late sound
  packets, which never traps), `CursorShapeBlob`, and `ViewportBounds` (what a
  host takes of a viewport: each side 1 to 16384 points, a scale 0.25 to 4 or
  none, any other refused; what a device sends, `held`; and `whole`, a number
  for a log line as Int() printed it, without its trap; pure,
  `Tests/checks/viewport-bounds`).
  (`WindowList`, with the host's per-launch `launchID` and what it takes and does:
  `gestures`, `clipboard`, `keyRepeat`; `WindowInfo`, `AppInfo`, `StreamSource`) and
  image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset` (Low, Efficient, Balanced, High, Pro, Ultra, Extreme). Remote access:
  `Remote.swift` (kinds 18–22's payloads: `MacAddress`, `MacInfo`,
  `SignedMacInfo`, `PairRequest` (with pairing at home's methods `ask` and
  `cancel`, `cable` and `v`), `PairResult` (its `method`, the ask's reasons
  `shown`, `openOnMac` and `locked`, and `message`), `Goodbye` (with
  `pairingRequired`)), `RemoteTLS.swift` (the one TLS 1.3 builder for both
  doors' ends and the tests; `serverALPNs`, the two a host offers for good),
  `RemoteIdentity.swift` (SPKI fingerprints, the Mac ID, the hand-built
  certificate, keys), `Pairing.swift` (`PairingCode`, `PairingProof`,
  `RecognitionTag`, `PairLink`, and `HomeDoorTXT`, the home door's TXT key
  `p`), `AddressParser.swift`, `SafeText.swift`.
  `Compatibility.swift` — `SillProtocol.current` (1), `SillVersion` (tags,
  bundles and the wire's versions, compared part by part) and `Hello` (kind 23,
  the device's first message); `Goodbye` (Remote.swift) carries `message`,
  `minimumVersion` and `reconnect` too, and `WindowList` the host's
  `hostVersion` and `protocol`. `MacMenu.swift` — the Mac's menus (kinds 24,
  25 and 27): `MacMenu` (a top level, or the answer to one fetch or press),
  `MacMenuItem`, `FetchMenu` (with the title the device showed for the menu)
  and `PressMenuItem`. `Pointer.swift` —
  `MacPointer` (kind 26, host → device: where the Mac's pointer is in the
  streamed frame while this device is not moving it, and `seen`, the input
  messages the host had read on the connection). `Gesture.swift` —
  `TrackpadGesture` (kind 28, device → host: a three- or four-finger gesture
  by name, and its fingers), sent only to a host whose `WindowList.gestures`
  is 1 or more. `Clipboard.swift` — `Clipboard` (kind 32, both ways: `text`,
  `image` reserved for a later generation, a device's `stop`) and its 256 KB
  cap; `ClipboardPolicy.swift` — the clipboard's rules for both ends (what a
  device's message asks of the host and the rate, which a stop never meets;
  which change of the Mac's pasteboard the host sends and to whom, and only
  while macOS allows every read (`MacAccess`); the device's subscription,
  which text from the Mac it writes, a Paste's receipt, the chip and its time,
  every word; pure, `Tests/checks/clipboard`). `Audio.swift` — the Mac's sound
  (kind 43, host → device; 29 to 31 and 33 to 42 are PR #66's):
  `AudioMessage`, type 1 a JSON `AudioFormat` (codec, rate, channels, packet
  size, priming, bitrate, epoch, cookie, what it is of), type 2 binary
  `AudioPackets` (epoch, seq, the segment flag, 1–255 packets); `AudioCodec`
  ("aac-eld", and `choose`: the first of a device's `Hello.audio` the host
  makes); only to a device whose hello lists one. `ScrollDirection.swift` —
  which way a scroll on the device moves the Mac's content: the device's
  Reverse Scrolling (issue #143, `Sill.reverseScroll`, never sent) turns a
  finger's drag over the picture and two fingers on the on-screen trackpad
  around, their coast too, never a connected trackpad's or mouse's scroll
  events (iPadOS's own Natural Scrolling set those); pure,
  `Tests/checks/protocol`. Kind 44, `keyframeRequest` (device → host, no
  payload: this device's picture was interrupted and waits for a keyframe;
  issue #101), has no type of its own.
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang and re-checks the
  hardware until it can go back (`recheckLoop`), stops capture when the last
  client leaves, takes live settings between pipelines (`setTarget`, from the
  app and from devices' kind 17, at most four a second per connection,
  answered and published as kind 16; a pick made during a restart runs after
  it), keeps each connection's route (home or the remote door's: kind 21 only
  from near the Mac, Direct Wireless never from away), sends kind 18 with the
  catalog, says goodbye (kind 22) at quit, sends the streamed app's menus to
  the devices that ask (`MenuMirror`; a window source's app made active and
  its window key first, as a click does: `focusForMenus`), answers a device's
  keyframe request (kind 44) with `HEVCEncoder.requestKeyframe`, at most one a
  second per connection, never a restart (a synthetic host ignores the first n
  with the TEST ONLY SILL_TEST_KEYFRAME_IGNORE=<n>, as a Mac from before kind 44
  ignores every one), and writes `HostStatus`),
  `HostConfig` (the knobs: maxFPS, captureScale, bitrate per 60 fps, the
  away pair awayBitrate and awayCaptureScale, prioritizeSpeed, virtualDisplay,
  directWireless, remoteAccess, remotePort, internetAccess, requirePairing,
  sendAudio, shareClipboard; `standard` is the CLI's values, `app` Sill.app's
  defaults, the same with the virtual display and Send Audio on (2026-10-27); `effective(away:)`), `HostClipboard` (the clipboard's host side: who
  subscribed, the look at the pasteboard's change count four times a second
  while one has and macOS allows every read, a device's text written
  `.currentHostOnly` with this launch's marker and passed to the others, one
  line a subscription and none per copy; a synthetic host's own pasteboard,
  the TEST ONLY SILL_TEST_PASTEBOARD, SILL_TEST_CLIPBOARD_LOG and
  SILL_TEST_CLIPBOARD_ACCESS; `MacClipboard`, macOS's paste privacy for the
  look and for Settings › General's `ClipboardSection`),
  `AwayPolicy` (who counts as away, when the away quality is the target, its
  two lines; pure, `Tests/checks/away-quality`), `LinkJudge` (each device's
  link judged once a second from the sweep: fine, behind, stalled, the carried
  rate, the suggestion, the host's lines, and which restarts judge afresh
  (`judgedAfresh`); pure, `Tests/checks/link-judge`),
  `HostStatus` (the snapshot the app shows, pushed on events; `onChange`
  publishes the devices' settings state; `firewall`, the macOS firewall's
  verdict), `FirewallRule` (what the macOS firewall's read-only answers mean
  for this host: a rule that blocks the running executable or its bundle, or
  Block all incoming connections, keeps devices out; Settings › General's
  line with the Terminal command that unblocks it, the menu's subtitle, the
  log's lines; the TEST ONLY SILL_TEST_FIREWALL's canned answers; pure,
  `Tests/checks/firewall`) and `FirewallCheck` (asks `socketfilterfw` five
  read-only questions, a process each, no privileges: at launch, when the
  listener comes up, when Sill.app's status menu or General opens, when a
  device gets in while the verdict says none can), `DeviceSettings` (what a device may
  set, `HostConfig` ↔ wire), `HostLog` (the print shadow, the app's ring and
  log file),
  `WindowCatalog` (polls windows and thumbnails only while a client is
  connected; icons; installed apps in the background; when its last look
  landed, `lookAge`), `CatalogLook` (whether a capture may be built from that
  look or the catalog looks again first: its display no longer active, none, no
  look, or older than two polls; the Desktop's lines and its one more try's;
  pure, `Tests/checks/catalog-look`; the black screen of 2026-10-28),
  `CatalogWindows` (which of ScreenCaptureKit's on-screen windows it lists: an
  app's own, by owner, layer, size and process, and no helper's:
  LayerProbeParent, macOS's own interface (Stage Manager's WindowManager, the
  Dock, Control Center, SystemUIServer, Notification Center, the screenshot
  tools), a tool's untitled window; one log line per owner it leaves out, #114;
  pure, `Tests/checks/catalog-windows`), `InstalledApps`
  (where those are found: each applications folder and the folders inside it,
  at any depth (#135's), never inside a bundle, another package or a
  framework, and never through a link inside a scanned folder (one given that
  is itself a link is followed), #76; pure, `Tests/checks/installed-apps`),
  `WindowCapture` (ScreenCaptureKit; its line names the scale it captures at),
  `CaptureScale` (the pixel scale a capture runs at: the Resolution knob held to
  the display's own, ScreenCaptureKit's `pointPixelScale` for the filter, so a
  window on a 1x display fills its picture and nothing is upscaled; and
  `InputLanding`, where a device's position lands on the Mac: at most the
  source's last pixel row and column at its display's scale; and
  `VirtualDisplaySize`, the size of Sill's virtual display, no side under 800
  points, which macOS kept at 2x (an iPhone's 754×784 came up at 1x), and of
  the window on it, 1 to 65536 points a side, the most a host takes, so a
  full-screen window's crop keeps the panel's shape (`windowSize`); pure,
  `Tests/checks/capture-scale`), `SyntheticCapture` (test pattern for
  `--synthetic`; SILL_TEST_PATTERN=noise adds a square of noise,
  SILL_TEST_PATTERN=picture:<path> shows a still picture instead,
  SILL_TEST_STILL_AFTER=<s> sends no frame from s seconds on, as a window that
  stopped changing), `HEVCEncoder` (VideoToolbox with one frame inside, a
  one-slot mailbox behind it and a hang watchdog; hardware or software; says
  whether a stalled frame came back; gives a stream whose session settled in
  the slow state a new one), `EncoderSlowState` (when that is, and whether the
  new session ran faster; pure, `Tests/checks/encoder-slowstate`),
  `EncoderMailbox` (its bookkeeping: the frame inside with its watchdog
  clock, the mailbox, the watchdog's test, timestamps and keyframe requests;
  pure, `Tests/checks/encoder-mailbox`), `EncoderProbe` (one small frame
  through a hardware session at launch; for the re-check a short quiet run at
  the stream's size, one frame at a time like a stream, the rate it keeps and
  the rate a return needs), `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  a remote client's frames paced by the bytes its connection has not taken
  (`paceRemote`, docs/remote-bundle-plan.md §3); one sweep a second closing
  every client's second into its LinkJudge (`onClientLinkChanged`), the judges
  reset only at another quality (`resetLinks`, apart from `resetForNewStream`);
  `send(each:)`, kind 16 per connection; a session `closeSessions` cuts off
  marked revoked as it is told goodbye, its receive loop then handing on only a
  key's or a button's up (`onClientRevoked`, RevokedInput); a locked Mac's
  gate (`lockGate`, LockPolicy.withheld) read on its queue for every message,
  frames tagged with what they show (`broadcast(_:picture:)`), each message
  handed on with the reading at its arrival, an icon or app list it withheld
  reported (`onCatalogWithheld`); the test-only SILL_TEST_REMOTE_ORIGIN;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes, and turned off, the devices on peer-to-peer Wi-Fi
  disconnected; the test-only SILL_TEST_SERVICE_TYPE, SILL_TEST_SWAP_FAIL,
  SILL_TEST_PEER_TO_PEER_INTERFACE and SILL_TEST_LOOPBACK), `ClientLink`
  (which route a client came by, from its endpoint's scope, and the menu card's
  word for it: Wired, Wi-Fi, Direct or none; pure, checked on its own with
  `swiftc -package-name sill`, which its `package` access needs),
  `InputInjector` (CGEvents: pointer and scroll where InputLanding lands them, scroll with phases, text with modifier
  flags cleared explicitly (a ⌘Space before typing otherwise tainted the text
  events and Spotlight ignored them), HID keys as KeyStrokes gives them, each
  device's keys let go when it leaves (and a cut-off device's buttons) and every
  key and button at the host's end, the check after each key's up, a button's
  up with nowhere to land where the pointer is; the TEST ONLY input log),
  `KeyStrokes` (a device's key as the
  device's keys let go when it leaves and every key and button at the host's
  end, the check after each key's up, a button's up with nowhere to land where
  the pointer is; a held key's repeats, as KeyRepeat steps them (a Task on the
  main actor), each a key down with the autorepeat flag; the TEST ONLY input
  log), `KeyRepeat` (a device's key held down repeated as the Mac's own keyboard
  repeats a key, #162: after NSEvent's keyRepeatDelay, at its keyRepeatInterval,
  every key but the modifiers, Caps Lock, fn and the media keys, the last key
  pressed alone, the flags in force at each repeat, stopped at its up, another
  key, text, a gesture's shortcut, the device leaving, the host's end and input
  with nowhere to land, waiting while input is held for an activation and while
  the device is quiet half a second (StreamServer.lastHeard), its first repeat
  only once the device is heard no earlier than `firstWord` (0.3 s) before it
  (a key only tapped whose up a stall holds back never repeats); `generation`, said
  in every window list as `keyRepeat`, so a device sends a hardware keyboard's
  characters as keys; pure, `Tests/checks/key-repeat`), `KeyStrokes` (a device's key as the
  Mac's: its virtual key, and the flags each event carries from the modifier
  keys the devices hold down, so a key's up leaves only what is held;
  `KeyUpCheck`, whether an up took its modifiers out of the HID state table;
  `DroppedInput`, what of input with nowhere to land still goes;
  `RevokedInput`, what still goes of a device the Mac no longer serves, or of
  one that left while its input was held: the up of what it holds down, and
  the buttons a cut-off device holds as it leaves (`buttonsLetGo`); pure,
  `Tests/checks/key-strokes`),
  `WindowSizer` (Accessibility resize for the Aa scale, returning what it did,
  `Fit`; `placement/move/restore` for the virtual display; `AXWindows`,
  WindowRestore's reads and writes through Accessibility; `perform`, a window's
  lights (kind 15), each element with a timeout, Close's button 1 s, and what
  came of it, `CommandOutcome`: done, refused or no answer in time, its words
  per action), `WindowRestore` (a
  window Sill sized for a device goes back when it stops streaming: each fit's
  record and `movedSince`, the decision at the stop, the sequences that fit a
  window and put it back over `WindowRestore.Access` (`fit`, `stop`,
  `stageHome`), `keepsStreaming` and `coversDisplay` for a window off the list
  on its way into or out of full screen, the ledger, the lines; pure,
  `Tests/checks/window-restore`), `VirtualDisplay` (private-API wrapper; its
  `TypeEncoding` says which type encodings the runtime may report for each method
  it calls, a `BOOL` return spelled "B" or "c" (#87, #62); pure,
  `Tests/checks/virtual-display-api`, which also runs `Runtime.method`'s decision
  and the `applySettings:` call, through `methodProblem` and `applySettings(_:to:)`,
  on classes it makes at run time),
  `VirtualStage` (`--virtual-display`: owns the display and the moved window,
  geometry, prepare/release, emergency restore), `HostShutdown` (signal
  sources + atexit, installed only with the flag in the CLI, always in the app;
  `releaseForQuit` for the app's Quit; `installKeyRelease` for the CLI's
  default path: a device's keys let go and a sized window goes back, then the
  signal's own end),
  `VirtualDisplaySelfTest`
  (`--virtual-display-selftest`), `Stats` (1 s lines while active, 30 s
  heartbeat when idle). Remote access: `OriginPolicy` + `InterfaceSnapshot`
  (who may use which door; pure), `RefusalSummary` (one refusal line a minute),
  `HostIdentity` (the `IdentityStore` protocol, `MemoryIdentityStore`, the TEST
  ONLY `FileIdentityStore`, `PairedDevice`, the lock-protected trust snapshot
  the door reads on the network queue), `KeychainIdentityStore` (Sill.app's),
  `PairingWindow` (pure), `RemoteServer` (the remote door), `Reachability`,
  `AddressList` (pure) and `RouterAddress` (read-only NAT-PMP/PCP),
  `RemoteAccess` (main actor; ties them together, signs kind 18; owns
  pairing for both doors: the ask, the cable's devices, Require pairing,
  Remove at both doors). Pairing at home (docs/home-pairing-plan.md): `Door`
  (admission at a TLS door, one class behind both listeners: the places
  waiting for admission and their deadlines, the backoff and its line, the
  verify block, the device gate, one pairing request per `sill-pair/1`
  connection; `RemoteServer` keeps the remote door's listener), `DoorPolicy`
  (who each door admits, the ask rule's six steps, `afterGate`,
  `isTestHost`: a host that does not advertise and is not Sill.app's own
  executable; `Places`, what waiting for admission costs an address and its
  IPv6 /64, and the places kept for addresses that proved a paired key; pure,
  `Tests/checks/door-policy`), `CableLink`
  Remove at both doors; names the sessions each cut-off closes to the
  coordinator as it decides, `onCutOff`, and says whether a session that
  registers later is still served, `stillServes`). Pairing at home (docs/home-pairing-plan.md): `Door`
  (admission at a TLS door, one class behind both listeners: the pending
  caps, the backoff, the verify block, the device gate, one pairing request
  per `sill-pair/1` connection; `RemoteServer` keeps the remote door's
  listener), `DoorPolicy` (who each door admits, the ask rule's six steps,
  `afterGate`, `stillServes` (a session registered behind a change that cut
  it off), `isTestHost`: a host that does not advertise and is not
  Sill.app's own executable; pure, `Tests/checks/door-policy`), `CableLink`
  (whether a connection came over the USB cable to an iPhone or iPad, from
  InterfaceSnapshot's IOKit reading, and the device's ID; pure,
  `Tests/checks/cable-link`), `CableReport` (`--print-cable`), `SessionLock`
  (this Mac's console, docs/locked-mac-plan.md: the witnesses on its own queue
  `sill.lock`, never the main actor: the console's user in the dynamic store and
  notify(3)'s screen state, both watched, the session dictionary bounded and off
  main; Sill.app's notifications, `.deliverImmediately`, whose handler sets the
  reading; `gate`, set the moment the reading changes; `onChange`, `devices`;
  the TEST ONLY SILL_TEST_LOCKED, SILL_TEST_LOCKED_FILE, SILL_TEST_LOCK_NOTIFY,
  SILL_TEST_LOCK_NOTE and SILL_TEST_LOCK_LOG), `LockPolicy` (a locked Mac: the
  three readings and the witnesses' rule, unknown counting as locked; `Reader`,
  the settle before an unlock; what each reading allows; what the server's gate
  withholds; each request at each reading; the window list; the placeholder's
  size; `reconciles`; `Restore`, the window that comes back; the lines; and
  `LockGate`, the reading every queue reads; pure, `Tests/checks/lock-policy`;
  the coordinator's `lockChanged`, `enforceLock`, `afterUnlock`,
  `lockedMidSwitch` and `lockDecision`), `StillCapture` (SyntheticCapture.swift:
  a locked Mac's placeholder, one black frame, no ScreenCaptureKit), `TestHooks` (the door and pairing hooks a host that
  is not a test host ignores, one line each), `AskLimits` (PairingWindow.swift:
  one device-opened window at a time, three in 10 minutes, the quiet after
  the Mac's Cancel or a stop, an IPv6 asker's by its /64; `Tests/checks/ask-limits`) and
  `RequirePairingValue` (HostIdentity.swift: Require pairing's record, off
  only with the Mac's own signature). StreamServer's home door is plain (the
  CLI without --pairing), TLS (`Door(.home)`, `p` in its TXT record) or
  closed (no identity: fail closed), `HomeDoorMode`.
  `DeviceGate` (the device floor, "0" in every build so far, and a refusal's
  words and log lines; pure, checked with swiftc; the gate itself, which runs
  only above "0", is StreamServer's, with the TEST ONLY
  SILL_TEST_MIN_DEVICE_VERSION and SILL_TEST_GOODBYE).
  The Mac's menus (docs/menu-bar-plan.md): `MenuFormat` (a shortcut as the
  Mac draws it, "⇧⌘S", "fn ⌃F"; an item and a top-level menu as sent; pure),
  `MenuPolicy` (`MenuPath`, the ids; `MenuCache`, a menu's read kept 1 s,
  answering only under the title it was read under; `ShownTitle`;
  `RequestRate`; `RequestDeadline`, when a request can no longer be answered
  in time for its device; `SubmenuRecord`, the submenus a version has read at
  their places; `PressDecision`, only a leaf whose title now is the one shown;
  `TopLevel`; the refusals' words and log lines; pure; both checked by
  `Tests/checks/menus`), `MenuReader` (every Accessibility call for menus, on
  its own queue `sill.menus`: the top level, one menu's items under the title
  shown, walks checked against the version's record, a press; a 1 s timeout
  per element, 1.5 s a menu, and no item begun that would end past the
  request's deadline), `MenuMirror` (main actor: the target, the version, the
  subscribers (only they are served), one request at a time with its
  deadline, the cache and the kept elements; a cut-off device's waiting
  requests neither read nor made, `clientRevoked`; the TEST ONLY
  SILL_TEST_MENU_PID, honoured only by a synthetic host, makes a process's
  menus the test pattern's) and `MenuSelfTest` (`--menu-selftest[=APP]`,
  read-only).
  The Mac's pointer: `PointerControl` (who moves it, the Mac or the device
  whose input the host read last, with the settle for Sill's own motion; the
  fraction kind 26 carries; pure, `Tests/checks/pointer-control`) and
  `PointerWatch` (the host's sampling of it: PointerControl under a lock, the
  streamed source's rectangle, a regular-mode window's bounds re-read on
  `sill.pointer`, the TEST ONLY scripted pointer `TestPointerPath` and
  `PointerTestHooks`; `Tests/checks/pointer-watch`). StreamServer samples it at
  each tick, and at the stream's frame rate while it moves over the source and
  some device is sent it (`PointerWatch.samplerInterval`), and sends kind 26
  to every device not moving it; InputInjector notes each pointer and scroll
  post just before it and, on a synthetic host, posts nothing (`in.dry`).
  Trackpad gestures: `GestureChords` (kind 28's gesture as the Mac's own
  shortcut for its action, the first of its shortcuts that is on; the view
  Sill's last gesture opened, which the opposite gesture closes; the log line;
  the TEST ONLY `SILL_TEST_HOTKEYS` table; pure, `Tests/checks/gesture-chords`)
  and `SymbolicHotKeys` (the Mac's Keyboard Shortcuts read through SkyLight's
  two getters at each gesture, read-only); the coordinator takes four a second
  per connection, waits for a switch in flight, queues the chord behind held
  input, and on a host that does not advertise posts none (`in.gestureDry`);
  `InputInjector.chord` posts it (`in.gesture`), its key up with the HID
  state table's flags from before it (`KeyStrokes.chord`;
  `in.gestureModifiersLeft` if some stay).
  The Mac's sound (docs/audio-plan.md; a beta since 2026-10-20): `AudioPipeline` (the source it follows
  from `active`'s didSet, one transition at a time; on `sill.audio` the
  packetizer, the encoder, the epochs and the stamps; the status and kind 16's
  note; `prepare`, AAC-ELD's codec loaded once off `sill.audio` when Send Audio
  is on), `AudioCapture` (ScreenCaptureKit's audio-only stream of one app, or of
  every app but Sill's, bounded start and stop, the running stream under a
  lock; never run by a test),
  `SyntheticAudio` (a synthetic host's test tone; the TEST ONLY
  `SILL_TEST_AUDIO_CHUNK` and `SILL_TEST_AUDIO_PAUSE`), `TestTone` (440 Hz and a
  click at each whole second of the stamps' clock; pure), `AudioPacketizer`
  (blocks, stamps and segments, `AudioSourceRule`, `PCMLayout`,
  `AudioBufferTally`; pure, `Tests/checks/audio-packetizer`) and `AudioEncoder`
  (AAC-ELD, AudioToolbox only; `Tests/checks/audio-codec`). StreamServer sends
  kind 43 to the devices that play it on a send path of its own
  (`broadcastAudio`: never `inflight`; its bytes in every client's `pendingBytes`
  and `takenThisSecond`, so each device's LinkJudge sees them; `paceRemote`
  drops only frames).
  A sleeping display (issue #134): `DisplayWake` (which of a device's messages
  are a person at it, so the host declares user activity on the Mac for it, as
  a key press would: a session's connect every time, kinds 7, 8, 15, 25 and 28
  only 5 s or more after the last declaration, never a pick or any other kind,
  nor a bare pointer move within 2 s after the host's own stream restart or new
  frame size (`streamChanged`); a test host counts `disp.wakeDry` instead; what
  DisplayActivity says, `Report`: "Woke the display for …" only when the
  display read asleep before and on 0.5 s after, once for one wake, else
  "Declared activity for …" once a minute at most, and the refusal's, once; the
  TEST ONLY `SILL_TEST_USER_ACTIVE`; pure, with StreamMessage.swift and
  Input.swift, `Tests/checks/display-wake`) and `DisplayActivity`
  (IOPMAssertionDeclareUserActivity with kIOPMUserActiveLocal, or Remote under
  the TEST ONLY switch, on its own queue, the main display's sleep state read
  just before it and 0.5 s after, `disp.wake`; nothing held: the display sleeps
  again by the Mac's own setting); the coordinator's `handle` forwards every
  message to the rule (`deviceActive`), and `parameterSetsSent` its stream
  changes.
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint; `--pairing` (the home
  door's TLS with pairing required, a throwaway identity, the code and link
  on its own stdout), `--print-cable` and `--no-clipboard`.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding), `AppIdentity`
  (whether this launch is Sill.app itself, by its signing identifier, signature and bundle
  wherever it runs from, or the bare binary, the one test host; pure but for its reader,
  `Tests/checks/test-host`),
  `HostSettings` (UserDefaults; the presets are StreamProtocol's
  `QualityPreset`), `StatusItemController` (+ `MenuBuilder`), `StatusText`
  (all status copy), `StatusCard`, `StatusGlyph`, `SettingsWindow` (its
  height capped to the screen, issue #59) + `SettingsPanes`,
  `SettingsWindowFit` (how tall Settings may be on its screen and where it
  goes; pure, `Tests/checks/settings-window`), `Permissions`, `LoginItem`,
  `LogWindow`, `MainMenu` (key
  equivalents), `DebugHooks`, `AppLog` (its print shadow), `DevicesPane`
  (Settings › Devices: Require pairing, Show the pairing window to screen
  sharing, the paired devices, Remove and rename), `RemoteAccessPane`
  (Settings › Remote Access), `PairDeviceWindow` (the QR code and the typed
  code; the window a device's ask opens, and the cable notice),
  `PairingWindowSharing` (whether screen sharing shows that window: hidden
  unless Settings › Devices' switch is on, whoever opened it, and the
  window's `NSWindow.SharingType` for each, `.none` or `.readOnly`; issue #108;
  pure, `Tests/checks/pairing-sharing`), `PairingWindowAddress` (the address that window gives to type:
  Tailscale's name and IPv4 first, another VPN's IP only under this network's
  address; pure, checked with swiftc), `UpdatePolicy` (the update check's rules
  and words; pure, checked with swiftc) and `UpdateChecker` (main actor; asks
  GitHub's releases feed and times the checks; compiles on its own with swiftc).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only), the release's (`SillRelease.entitlements`:
  `com.apple.application-identifier`, the team and the keychain group, signed
  in only with `embedded.provisionprofile`, the Developer ID profile, which is
  git-ignored; docs/keychain-plan.md), and `ExportOptions-appstore.plist`, how
  the iOS app's archive is exported for App Store Connect. `Scripts/release-ios.sh`
  makes the iOS app's build: the Release archive (automatic signing on team
  9B2KKVM937, or none with `--sign-at-export` and `--unsigned`), the export
  (destination export; `--upload` adds a second one whose destination is
  upload), the .ipa checked (version and build, the export compliance key,
  the Local Network, Bonjour and camera entries, the privacy manifest, an
  Apple Distribution signature, an App Store profile, no get-task-allow, the
  required-reason APIs against the manifest), `--bump`, `--api-key`,
  `--print-version`, `--privacy-report`, `--build-number N` (xcodebuild's
  `CURRENT_PROJECT_VERSION=N` for the run, never written to the project: the
  nightly's and testflight.yml's commit count) and `--whats-new FILE` (with
  `--upload` and `--api-key`, What to Test once processed, through
  `Scripts/asc.swift`); it refuses any Xcode before 27.1
  or after 27 (the iOS 27.1 SDK the iPhone Duo's layouts need; the app it
  checks must say DTPlatformVersion 27.1 or later),
  with `--bump` or `--upload` a working tree with changes (new files in
  iOSClient and Sources/StreamProtocol count), and an App Store address in
  `SillLinks.swift` that isn't one, and sourced it only defines its
  functions (docs/release-checklist.md, TestFlight). `Scripts/make-app.sh`
  builds, iconizes, signs and installs the bundle (with `SILL_UNIVERSAL=1`
  arm64 and x86_64, each in its own scratch path under `.build/universal`,
  joined with lipo, #62; off by default here, on in the nightlies and, since
  0.6.0, in release.yml's publish job, so releases are universal; `release.sh`'s
  `check_signature` reads every slice);
  `Scripts/release.sh`
  (M6) makes the downloads from it:
  `make-app.sh --release`, `make-dmg.sh --prepare` (the image's tool and
  background, before anything goes to Apple), a zip (`ditto -c -k
  --keepParent`), Apple's notary service (`notarytool submit --wait`, the
  profile in `SILL_NOTARY_PROFILE`), the ticket stapled, the zip made again
  with the ticket inside, and a copy unpacked from it checked with `stapler
  validate` and `spctl` ("Notarized Developer ID"); then the disk image of the
  stapled app (`make-dmg.sh --sign`), notarized on its own, stapled, and
  checked (`hdiutil verify`, `stapler validate`, `spctl -t open --context
  context:primary-signature` as "Notarized Developer ID", mounted `-nobrowse`
  in `$TMPDIR` and the Sill.app inside checked as the zip's copy); it prints
  `.build/Sill-<version>.dmg` and `.zip` with their SHA-256. A dry run makes
  the image too, from the app before stapling, signed with the same identity.
  It refuses to start, before building, without a
  Developer ID Application identity (`SILL_SIGN_IDENTITY`, checked against the
  keychain) or the profile, or on a HEAD without the tag v‹version› (the
  update check's), or with `SILL_RELEASE_TAG` (the release workflow sets it)
  not `v<CFBundleShortVersionString>` or naming another commit (`--check-tag`
  checks only that), and `--dry-run` stops before notarytool (the profile and
  the tag only warned about: it sets `SILL_RELEASE_DRY_RUN=1`, with which
  `make-app.sh --release` builds an untagged commit); it refuses a build
  without Assets.car and AppIcon.icns. `--publish` makes the GitHub Release in
  `SILL_RELEASE_REPO` (default Saffsanity/sill, the only repository the update
  check reads), asks `gh api repos/<repo>` whether it can reach the repository
  (`gh auth status` asks GET /user, which the Actions token can't answer), and
  refuses to start unless origin's tag v‹version› names HEAD (gh would make a
  missing tag from the default branch's tip; not asked in the release
  workflow, whose checkout is the run's own commit with every tag, stopping
  when its tag moved, and keeps no credentials); in
  Saffsanity/sill it passes gh `--verify-tag`, anywhere else it warns that no
  Sill.app will offer the release. It uploads `Sill.dmg`, `Sill.dmg.sha256`,
  `Sill.zip` and `Sill.zip.sha256` (the zip kept for older links: the download
  page names the image since 0.3.1). Sourced, it only defines its functions.
  `release.sh --nightly [--dry-run | --publish]` (docs/release-checklist.md,
  "Nightlies"): main's head built, signed, notarized and checked as a release,
  without the tag rule (make-app.sh's `SILL_RELEASE_NIGHTLY=1`) and only with
  the Developer ID profile, as `.build/Sill-nightly-<yyyymmdd>-<sha7>.dmg` and
  `.zip` (`SILL_NIGHTLY_DATE`, UTC); `--publish` puts them and their `.sha256`
  on the rolling pre-release `nightly` (made when missing, its tag moved to
  the commit, never latest, `SILL_NIGHTLY_KEEP` newest nightlies kept, its notes
  `SILL_NIGHTLY_NOTES` or nightly-notes.sh's, ending in the commit's sha in a
  comment that `nightly_last_sha` reads for the skip rule).
  `Scripts/nightly-notes.sh --markdown F --whats-new F`: a night's words for both
  apps, the pull requests merged on main's first-parent line since the newest
  tag `v<version>` (titles from `gh pr list`, else the commits), Markdown without
  @mentions for the pre-release, What to Test within 4,000 bytes.
  `Scripts/asc.swift` (Foundation and CryptoKit; compiled with swiftc or run as a
  script): App Store Connect's API for TestFlight with an ES256 token from the
  .p8 key (`groups`, `build-state`, `whats-new`, `distribute`: wait for
  processing up to 90 minutes, What to Test (`distribute` only to a build with
  none, in any language, unless `--replace-whats-new`; `whats-new` always
  replaces), every internal group, the public
  beta group only with `--public-beta` and `SILL_NIGHTLY_PUBLIC_BETA=true` in its
  environment, Beta App Review only right after that); the token goes only to
  api.appstoreconnect.apple.com (or a stand-in on 127.0.0.1 in tests:
  `Tests/checks/asc`) and is never printed.
  `Scripts/make-dmg.sh --sign IDENTITY APP DMG` (`-` for ad hoc) makes the
  image: an HFS+ volume "Sill" (not APFS: Finder names the background by an
  HFS+ alias record, and Finder-made and current third-party images are
  HFS+) with the app (`ditto`), a link to /Applications, `.background/`
  (design/DMGBackground.svg rendered by Quick Look at 1x and 2x, cropped,
  joined by tiffutil into one TIFF; cached in `.build/dmg`) and
  `.VolumeIcon.icns` (the app's AppIcon.icns, with the root's custom-icon
  flag); its window laid out by a `.DS_Store` that `Scripts/dmg-layout`
  (Swift, compiled into `.build/dmg`; DSStore.swift, FinderAlias.swift,
  DMGLayout.swift) writes without Finder and reads back (`check`): 660 x 432
  points, the picture's 400 and macOS 27's 32-point title bar
  (`DMGLayout.titleBar`; `Tests/checks/dmg-layout` checks the writer); converted
  to ULFO (LZFSE, read-only), signed (identifier `me.saffer.sill.dmg`, a
  timestamp unless ad hoc) and checked mounted (exactly five items at the
  root, the link, the layout, the app byte for byte). Mounts are `-nobrowse`
  in a new folder in `$TMPDIR`: mounted under the home folder, fseventsd
  writes `.fseventsd` onto the image as it unmounts. `--prepare` only builds
  the tool and the background. Sourced, it only defines its functions.
  `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--raw9=JSON@T` (a literal viewport, kind 9),
  `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line,
  and each second's frames with their kB (the encoder's output);
  `--host`, `--device`, `--big-payload`, `--flood`, `--stop-ping@T`,
  `--stop-read@T`, `--pairing-wanted@T`, `--keyframe@T` (kind 44); the remote door with `--tls
  --identity=DIR`, `--pair-url`, `--pair-code`, `--pin=FP|none` and
  `--expect-tls-fail`, printing kinds 18, 20 and 22; pairing at home with
  `--pair-ask[=cable]`, `--then-code=FILE`, `--pair-hold=S`, `--pair-cancel`,
  `--pair-v=N` and `--expect-pair=R`; the Mac's pointer with
  `--pointer` (each kind 26), `--move=X,Y@T`, `--tap=X,Y@T`, `--key=USAGE[,HOLD]@T`
  and `--input=JSON@T` (a literal kind 8), the input flags only to a
  `--synthetic` host on this Mac (lsof and ps); trackpad gestures with
  `--gesture=NAME[,FINGERS]@T` and `--raw28=JSON@T` (kind 28), likewise only to
  a `--synthetic` host on this Mac; the Mac's menus with
  `--menus` (the subscription; each kind 24 on one line),
  `--fetch=ID[xN][,TITLE]@T` (the title the menu was shown under, by default
  the one listed for the id), `--press=ID[,TITLE]@T`, `--raw25=JSON@T`,
  `--raw27=JSON@T` and
  `--expect-menus=TITLE[,…]`, the fetches and presses only with
  SILL_TEST_MENU_PID in its own environment (against any other host they
  would open and choose the menus of whatever app is in front); every
  argument is checked before it connects, and a bad one exits 2).
  `Scripts/menufixture.swift` (TEST ONLY) is the menu gates' app: an AppKit
  menu bar of known menus (Probe's marks, shortcuts, a disabled item, a
  retitled one, a slow action, Deep three levels, 300 and 600 items), the
  prohibited policy so it can never take the front, its windows off every
  display (the label's, and Slow Close, whose close holds its main thread 4 s
  and keeps it open, as a close asking about unsaved changes does), every
  delegate call and action logged (an action also as "PRESS
  'item' in 'menu'"), SIGUSR1 and SIGUSR2 giving Probe › Rebuilt a new NSMenu,
  SIGHUP inserting an item at the top of Probe in place and SIGALRM giving
  Probe a new NSMenu; `menufixture label PID` reads its label over
  Accessibility. `Scripts/menu-check/run.sh` runs the real MenuReader and
  MenuMirror against it with no host and no encoder (safe while Sill.app
  streams; it needs Accessibility for whatever runs it, and an unlocked screen),
  and its `close` step WindowSizer's Close (with WindowRestore.swift, which
  WindowSizer needs since #75) against Slow Close: back within 1 s, as no answer.
  `Scripts/audio/` is the
  encoder-free sound harness (docs/audio-plan.md H5, H6, H8): `build.sh` makes
  `.build/audio/host` (the working tree's StreamServer and the sound's host
  files with `main.swift`: fake frames, the test tone, both doors on
  127.0.0.1) and `.build/audio/audiocheck` (`Scripts/audiocheck.swift`, the
  harness's device: every kind 43 decoded with iOSClient/AudioDecoder.swift and
  each click found at its stamp), refusing a binary that links a media
  framework but AudioToolbox; `run.sh [--cases a,b]` runs the gate cases and
  `summarize.py` judges them.
  `Scripts/restore-probe/run.sh` (TEST ONLY; issue #57) drives the real
  `WindowSizer.resize` and a fitted window's way back (WindowRestore's `fit`
  and `stop` through `WindowSizer.AXWindows`) against a window of its own
  (`owner.swift`, built into a bundle that never activates and ordered behind
  every window), frames before, during and after, fourteen steps (its app
  stopped with SIGSTOP at a fit and at a stop among them); the front app must
  not change. It needs Accessibility, Screen Recording and an unlocked screen,
  and exits 2 saying which is missing. `Scripts/lock-check/` (TEST ONLY;
  docs/locked-mac-plan.md): `live.py OUT [poll|start|notify|paired|all]` runs
  synthetic test hosts on loopback (each under 60 s) through locks, a switch to
  another user, the unlock's settle, the flap and a start while locked, with the
  TEST ONLY lock hooks and test clients that save what they receive
  (`sillclient.py --dump`), and prints a verdict per rule; `frames.swift` (`build.sh`: with StreamProtocol, into
  `.build/lock-check/frames`) decodes the saved keyframes on VideoToolbox's
  software decoder and prints each one's size and luma, so the placeholder's
  black is measured. `Scripts/sillrelay.py` is a
  shaping passthrough relay (`--listen 0 --to HOST:PORT [--delay-ms N]
  [--rate-mbps R] [--blackhole-after S] [--record PREFIX]`; TLS passes
  through). `Scripts/pacing/` is the remote pacing harness
  (docs/remote-bundle-plan.md §3 and §11): `build.sh [BASE]` makes two
  throwaway packages under `.build/pacing`, BASE's StreamServer.swift (default
  origin/main) and the working tree's, each with its neighbours (the Door's
  files too since pairing at home, and `PACING_SERVE_BEFORE_HOME_PAIRING` for a
  BASE from before it, whose `serve` takes no hello) and fed fake
  frames by `main.swift` (no encoder: a binary that links a media framework is
  refused; on cue, new sizes, a still window or a restart); `run.sh [--full]
  [--cases a,b] [--repeat N] [--base REF] [--list]`
  runs each case on both, host → `bottleneck.py` (a downlink rate on a virtual
  clock, a delay, a finite queue, rate changes) or `Scripts/sillrelay.py` →
  `device.py` (the device's reader, pings, stats and liveness;
  `--liveness-bytes` for MessageReader's rule), everything on 127.0.0.1 and
  each run only while the load average is under 20; `summarize.py` prints the
  table and each case's gate.
  `Scripts/encoder-check/` holds the encoder's checks ("The 33 fps plateau"):
  `run.sh` builds and runs those that never touch an encoder (the probe and
  encoder checks, which run in real time with tight bounds and so stay out of
  CI, and through `Tests/checks/encoder-mailbox` and `encoder-slowstate` the
  mailbox and slow-state checks and their mutants; it refuses any binary that
  links VideoToolbox), and `verify-hardware.sh` the hardware runs against a
  base commit built from `git archive` (parity, stream, harness, probe,
  keyframe), each only while `no-device.sh` finds no device connected to
  Sill.app; outputs go to `.build/encoder-check/`.
  `sillclient.py --hello=VER[,PROTO]` (or `none`) sends a device's hello
  first (`--hello-delay=S` S seconds after the connection is up, for a change
  made while a host's device gate holds it), and kind 22's new fields are
  printed. `Scripts/sillfeed.py PORT`
  is a fake GitHub releases feed for the update check's tests (`--tag`,
  `--status`, `--etag`, `--draft`, `--prerelease`, `--html-url`, `--body`,
  `--big`, `--slow`, `--reset`, `--redirect`, `--set-cookie`,
  `--all-headers`; `GET /__control?key=value` changes them while it runs).
- `site/` — the website, for GitHub Pages at the domain in `site/CNAME`:
  `index.html`, `download.html` (links the newest GitHub Release's `Sill.dmg`
  and `Sill.dmg.sha256`; never edited per release), `privacy.html` (the policy
  App Store Connect and the app link to), `support.html`, `contribute.html` (how to sponsor,
  the public sponsors and the contributors by name, the rules for a pull request; linked from
  every page's header and footer, README's Tips and Contributing, FUNDING.yml's custom link and
  the issue chooser; its names refreshed with each release, docs/release-checklist.md), `terms.html` (the terms of service: the
  Apache license, Apple's EULA for the App Store copy, no warranty, no fees;
  linked in every footer), `style.css` (system
  fonts, light and dark) `icon.svg` (a copy of design/AppIcon.svg) and `preview.jpg` (the
  1200 × 630 share image that the Open Graph and Twitter card tags in every
  page's head name). No
  scripts and nothing loaded from elsewhere: every page's
  Content-Security-Policy is `default-src 'none'`. Links are relative and
  name a file (`download.html`; Home is `index.html`, since `./` opens nothing
  from the folder), so it renders from the folder; GitHub Pages also serves
  each page without `.html`, the form the app and App Store Connect use
  (`/download`, `/privacy`, `/support`). Remote Access paragraphs sit between
  `<!-- Remote Access` and `<!-- /Remote Access -->`, to cut for a release
  without it. `docs/release-checklist.md` is the order of work: the one-time
  setup (Developer ID, notary credentials, hosting and DNS, the App Store
  Connect record) and every release's steps.
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one,
  each made again after the background and after a failure (`cameForward`,
  `rebuildBrowser`); `FoundMac` rows; connection, parsing, reconnect, the move of a session over
  AWDL to the network, a live session following the best path
  (`followBestPath`: to the cable, to Wi-Fi, made again over either), a remote
  session's move home (`moveHomeIfListed`, `MoveKind.fromRemote`), ping,
  generic `send`, and the pointer: kind 26 judged on its queue, `renderPointer`,
  `setOwnPointer`, `sendFromKeyRow`, a hand-over's carry-over),
  `SessionLink` (the session's connection and the one door out
  to the Mac; the moves' fenced hand-overs, which chain, and the hold of a move
  off a lost path: `handOver`, `hold`, `adopt`, `unhold`; the input messages
  counted for the session's connection, `inputsOnSession`, which a kind 26's
  `seen` is judged against; Foundation and Network only, checked with swiftc),
  `MessageReader` (the session's reader: each header, then the payload in
  pieces of at most 256 KB, every piece a sign of life for the liveness check;
  Network and StreamProtocol only, checked with swiftc),
  `DiscoveryPolicy` (when to look nearby, the rows and the word each ends in,
  the session's route word for the Settings panel,
  when a reconnect may take a Direct row, when a session over AWDL moves to
  the network, when a live session at home moves to the cable or to Wi-Fi or is
  made again (`pathPlan`, `upWait`; a remote one only home: `moveHome`, over
  TLS pinned to the saved Mac's key: `moveHomeTrust`, to a row chosen and
  refused by row: `moveHomeRow`, `HomeRows`, its kind 18 held to the floor taken
  as the move starts: `HomeMoveInfo`), the memory of Macs with
  Direct Wireless on, the Remote rows and when a lost saved Mac is dialed away
  from home; when a browser is made again and what the rows show meanwhile
  (`rebuildBrowser`, `browserFailures`, `browserResults`), when the automatic
  reconnect dials a row that stays listed and its line (`redialRow`,
  `reconnectLine`), and when the device asks for the Desktop by itself
  (`autoDesktop`; issue #69); pairing at home's rows and words, a tap's dial, the device's
  cable check and how a session at home ends: `rowWord`, `homeDial`,
  `onCable`, `rowMac`, `reconnectEnd`, `macInfoNamesSession`,
  `removalRevokes`; the TXT record each row is read with, its result's own or else the last one that
  result carried while the same browser lists it, forgotten once it leaves and when a browser is made
  again (`rowRecords`, `RowRecordKey`: the cable pulled, 2026-10-27); pure, checked with swiftc),
  `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display, and `DuoLayout.phoneArrangement`,
  the idiom: which arrangement `.outerPortrait` draws; `DuoLayout.isPortrait`,
  the laptop layouts, where the trackpad's pointer shows), `PortraitStreamScreen`
  (portrait in two arrangements: the halves, the picture over the window bar,
  the key row and the trackpad, at the inner display's size and, for an iPad
  window narrower than 600 pt, the compact one with the key row in two lines;
  and a phone held upright, from `PhonePortraitLayout`; the key row's two sets,
  twelve and six), `PhonePortraitLayout` (a phone upright, `.outerPortrait` on
  an iPhone, as rects from the stream screen's size: the picture's fixed 16:10
  pane, row 1's five buttons in their band, the strip, six caps, the trackpad
  and its vertical span, the Aa ruler, the drawer and the Settings panel across
  row 1, and the dim, and the Menus button ending the strip's row (`menus`,
  `stripBesideMenus`; no Sound button anywhere since 2026-10-27); with Larger
  Picture's keyboard (`keyboard`, from
  `keyboardHeight(for:)`, only while a window streams: `largerPicture(switchOn:
  streaming:)` and `Streaming`, and only where it is larger: `largerPictureGains`,
  `offersLargerPicture(screen:)`) no strip, the room over the keyboard, Menus in
  row 1 (`buttonsBesideMenus`), the drawer above row 1, the pane at the
  picture's shape (`pane(video:)`) and its span (`trackpadSpan(video:)`); pure,
  `Tests/checks/phone-portrait`), `DuoPosture`
  (the iPhone Duo's posture and the rules that follow from it, docs/iphone-duo-plan.md:
  `FoldInfo`, inferred before iOS 27.1 or the fold's band; the laptop pose's
  split at the real fold and open flat's at the picture's shape, the book
  pose's bar, one page for a card (on its targets' page), the connect column
  and the room above the laptop pose's fold, the pairing overlay and the
  window lights; the stream screen's status bar (hidden on the inner display
  in every pose); the hinge from the fold before its first report; the
  harness's stand-in and the displays' safe areas; pure, `Tests/checks/duo`;
  pbxproj AB01/FB01), `DuoPostureReader` (iOS 27.1: `onHingeChange` at the
  app's root into `\.duoEnvironment`, `DuoPosture.read`, the `.division`
  region as a screen's own GeometryReader sees it; StreamScreen hands it to
  its layouts as `\.duoFold` and hides the status bar with `duoStatusBar`;
  AB02/FB02),
  `InputOverlay` (direct touch, Pencil, keyboard, scroll momentum; each input
  says what drew this device's pointer; hardware keys through `ForwardedKeys`,
  the characters too while `KeyTyping` says the Mac types them, let go when the
  overlay stops taking keys; Esc's key commands; the iPad's
  trackpad's and a wheel's scroll pans beside the finger pan, one scroll path
  (`scroll(_:at:translation:velocity:from:)`, a finger's drag in Reverse
  Scrolling's direction, `ScrollDirection`); a `UITextInput` since #138: an
  input method's composition over the picture, sent once chosen, dictation and
  its corrections, ⌃Space to iPadOS with keyboards in two languages, Scribble
  declined, what is composed sent first and what was typed forgotten when the
  Mac's caret may move (`forgetTyped`, from `StreamClient.onCaretMayMove`, before
  it goes out: a pick, a launch, a window's button and a menu item follow the
  queued input, `sendAfterInput`), and what came before a Return or a Tab it types
  made final (`TextComposition.fence`), what was typed kept;
  `InputOverlayProxy`, who holds
  the keyboard, carrying out `HardwareKeyboardPolicy`; `HardwareKeyboardMonitor`,
  GameController's keyboard), `TextComposition` (what the input view holds for
  iPadOS's text system: the composition, what was typed since the Mac's caret
  last moved, corrections as backspaces and text, none from a range taken before
  a forget or a trim (`generation`) and none that would change what went before
  a Return or a Tab typed (`fence`, `refusal`), what the text system selects of it
  replaced by its next edit (`selection`: Korean's syllables built again);
  `TextInputRules`, which input
  moves the Mac's caret (no typed text, a Return or a Tab among it), where a
  Return or a Tab typed ends (`endOfReturnOrTab`) and whose ⌃Space it is;
  `KeyTyping`, who types a hardware keyboard's characters: the Mac, as keys,
  when it says `keyRepeat`, for a keyboard in the Latin alphabet whose input
  method composes nothing (`composingLatin`: Vietnamese, Hawaiian) with
  nothing composed or latched, else iPadOS's text system (#162's letters); pure,
  `Tests/checks/text-composition`; pbxproj AC0138/FC0138), `HardwareKeyboardPolicy` (when the stream's input
  view holds the keyboard for a hardware keyboard and when it is the person's
  own; and `PointerScroll`, where a trackpad's or a wheel's scroll goes, the
  pointer's place as it began, and its readings added up; pure,
  `Tests/checks/hardware-keyboard`; pbxproj AC01/FC01), `DeviceIdlePolicy` (when Sill
  holds the device's own auto-lock off: while a window the person can see streams,
  until 10 minutes after the person last used it, and what counts as the person's
  use; pure, `Tests/checks/device-idle`; pbxproj AE30/FE30; StreamScreen's
  `DeviceIdleTimer` carries it out, PR #230), `KeyChords`
  (`KeyModifiers`; a
  shortcut with its modifiers' own keys pressed around it, the Spotlight key's
  ⌘Space, the trackpad's modifier keys around a click; `ForwardedKeys`, a
  hardware key's up after its down, its way (a key, or the text system's)
  decided at the down by `KeyTyping` (`characterUsages`; a letter with Caps Lock
  on carries Shift, `carried`), and Esc's key command sent once beside
  pressesBegan; `HeldCap`, the portrait key row's esc, tab and arrows down from
  a finger's touch to its release, so the Mac repeats them (#162); pure,
  `Tests/checks/key-strokes` with the
  host's KeyStrokes), `TrackpadView` (the relative pad: its
  cursor a `PadCursor`, from the anchor; a recognizer that only counts fingers;
  `verticalSpan`, a phone's width ÷ 1.6; its two-finger scroll and coast in
  Reverse Scrolling's direction, `ScrollDirection`; and the DEBUG input test), `StreamZoom` (pinch to zoom on
  the picture, 1× to 5× around the point between the fingers, Photos-like, and `StreamZoom.Stroke`, which two
  fingers belong to; pure, `Tests/checks/stream-zoom`; `StreamZoomModel` and `ZoomedStreamView` in
  HEVCDisplayView.swift scale the picture inside the pane's clip; StrokeObserver's `onTouch` feeds it; every
  touch and scroll lands through it: PR #196, issue #65), `ThumbnailHold` (how long a window's thumbnail is
  held before its lights show and its drag can start: 0.2 to 2 s in tenths, 0.5 s unless changed, the words
  of the Settings panel's stepper; pure, `Tests/checks/thumbnail-hold`; WindowStrip and HoldDragOverlay
  in StreamScreen.swift take it, issue #113), `VersionLabel` (this app's version and build as its bundle says
  them, CFBundleShortVersionString and CFBundleVersion cleaned: "Sill 0.6.2 (1400)", spoken "Sill version 0.6.2,
  build 1400"; pure, `Tests/checks/version-label`; pbxproj AE01/FE01; `VersionLine` in ContentView.swift shows it,
  with Copy on a long press, at the bottom of the connect screen's footer and as the Settings panel's last line),
  `HEVCDisplayView` (shared display view, the one pointer sprite + DEBUG HUD;
  the picture's interruptions on the network queue: `checkLayer` flushes a layer
  that failed, could not decode a frame or needs a flush to decode again, at each
  frame, at its notifications and when the window becomes active, and says so,
  `onNeedsKeyframe`, then `onPictureBack`, both, back first, for a keyframe the
  flush throws away; DEBUG `-SillLayerFail` and `-SillKeyframeLost`),
  `KeyframeRecovery` (when the device asks the Mac for a keyframe, kind 44,
  after its picture was interrupted: one ask per interruption while its keyframe
  is due, again when none came within `answerWait`, max(4 s, 4 round trips);
  only while the picture's window is active and something streams; 2 s apart,
  4 to 32 s for a picture that keeps failing or a Mac that never answers, 2 s
  again after a trip away; pure, `Tests/checks/keyframe-recovery`; pbxproj
  AC11/FC11),
  `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with rows ending in
  Wired, Wi-Fi, Direct or Remote, the hint and Search Nearby, Add a Mac…, and
  a footer along the bottom, "Needs the free Sill app on your Mac." with links
  to the download, support and the privacy policy, which open in Safari (one
  line while they fit, else the download link over the other two, as wide as
  the column); the column stays where it would be without the footer
  (centred; in the top half on the Duo's 710×1000, the footer still along the
  bottom; at the top while a field has the keyboard), rises only to keep 24 pt
  clear of the footer, never closer than 16 pt to the top, and scrolls above
  it, 16 pt from the top, when even that does not fit (a 12 pt fade, then
  12 pt clear, both inside the gap); one scroll view
  whatever the fit (`ColumnOverFooter`, measuring a hidden copy of the
  footer), so a fit that changes never builds the card anew (its fields, the
  camera); in the footer, at its trailing edge on a line it already has wherever
  it fits there, this app's version (`VersionLine`; docs/version-label-plan.md);
  + DEBUG harness, and `InputScript`, `-SillInputScript`'s steps),
  `SillLinks`
  (the site's addresses, written once; getsill.app is live since 2026-09-25;
  and the App Store address for a Mac's update notice, the App Store Connect
  record's since PR #27),
  `MockCatalog` (harness data and the settings cases), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel; the route line, Away
  from home, the away line in the header, the link's callout and its button,
  the footnote, the slow-link callout for older Macs; its last line this app's
  version, `VersionLine`), `AwayCopy` (every
  string of away from home and the link on the device, which callout shows,
  and `LinkLine`, the stream screen's line over time; pure,
  `Tests/checks/away-copy`; pbxproj A801/F801). Remote access: `DeviceIdentity`
  (the device key in the Keychain, carrying out `DeviceKeyPolicy`),
  `SavedMacs` (pure; `homeTLS` and `revoked` for pairing at home; the VPN
  addresses a later list lacks, `remembering` and `remembered`, 90 days, four;
  with `DeviceKeyPolicy`, the device key's rules: when the launch clears the saved
  Macs, when a key is made, when a key made is used; `Tests/checks/remote-rules`'
  `launch.swift`, #140),
  `RemoteDialPolicy` (pure: the dial order, a remembered address's second group,
  what a failure means, `failed`, and `RemoteCopy`'s words), `RemoteConnector`, `StreamClient+Remote`
  (pairing, remote dials, the reconnect order, links), `StreamClient+Home`
  (pairing at home: `DeviceTLS`, the one TLS builder for every connection to
  a Mac, the session gate at the first window list, the ask, the cable's
  proof-less ok, the proofs sent to a row, how a session at home ends;
  pbxproj A601/F601), `AddMacCard` (the card, the fields, `EscapeKey`; the
  home card for a row), `CodeScanner` (VisionKit),
  `PairingOverlay` (Pair This iPad…), `GoodbyePolicy` (the words and the
  reconnect after a session ends, a Mac's notice included; pure, checked with
  swiftc). The Mac's menus (docs/menu-bar-plan.md §7): `MacMenuState` (one
  connection's view: the top level, the menus asked for and the choices sent,
  each opened menu's completion settled exactly once, the rows and sections;
  pure, `Tests/checks/menu-state`), `MacMenuElements` (the one builder of
  `UIMenuElement`s for the iPad's bar and the button: uncached deferred
  elements, `UIAction` leaves with the Mac's shortcut as the subtitle, never a
  `UIKeyCommand` or `UICommand`), `SillAppDelegate` (`SillApp`'s
  `@UIApplicationDelegateAdaptor`; only `buildMenu(with:)`) with `MacMenuBar`
  (where the Mac's menus go in the iPadOS 26 bar, once per build, every
  anchor looked up first), `MacMenuHub` (whose session the bar shows: the
  app's one window's while exactly one window scene is connected, none with
  two or more; from each scene's `WindowSessionObserver`; asks for a rebuild)
  and `MacMenuButton` (the bars' Menus button: the bar's look, and
  `MacMenuTrigger`'s clear UIButton with the pull-down over it; `fits`, where
  a bar holds it and still a whole thumbnail).
  `PointerPresence` (the rules of the one pointer sprite: the Mac's
  arrow while the Mac or another device moved it last, this device's own only
  for the portrait trackpad; a kind 26's freshness; the network queue's feed
  with a hand-over's carry-over; the key row keeping what shows; the portrait
  pad's cursor; pure, `Tests/checks/pointer-presence`; pbxproj A301/F301),
  `TrackpadGestures` (which stroke on the glass goes silent and which arms,
  the gesture decided as one of its three fingers lifts, and whether it goes
  to the Mac; pure, `Tests/checks/gestures`; pbxproj A701/F701) and, in
  InputOverlay.swift, `StrokeObserver` (the recognizer on both surfaces that
  feeds it every direct touch and takes none). The clipboard:
  `StreamClient+Clipboard` (the subscription at the first window list that
  says `clipboard` and on a move's new connection, `stop` when the switch goes
  off, the Mac's text written `.localOnly` for 10 minutes, the chip's look when
  Sill becomes active and its time while it shows, Paste's send and its
  receipt, a ping whose pong says the Mac read it; pbxproj AC64/FC64) and `ClipboardChip`
  (the chip and `ClipboardPasteButton`, the system's Paste control;
  AD64/FD64); StreamScreen places the chip, the Settings panel's This iPad
  group has Share Clipboard and Paste on ‹Mac›. The
  first-run tour: `TourPolicy` (its steps and targets per layout, the halves,
  a phone's rows and sideways; when it shows by itself, what it remembers and
  the tour's version (`version`, 2 since 0.6; `upgraded`, an older memory
  cleared once), what a session decided and the reconnect's, a rotation
  mid-run, the crease, where the card goes, every word, with `TourFeatures`,
  what this Mac and this device have, and "New:" (`newPrefix`, `TourSpan.isNew`);
  pure, Foundation and CoreGraphics, `Tests/checks/tour`) and `TourOverlay`
  (the dim with the lit cutout and its ring, the card placed by a Layout, the
  "New:" drawn in the accent, the targets' preference in the stream screen's
  named space `sill.screen`, `TourStore` for `Sill.tourSeen`,
  `Sill.tourSkipped` and `Sill.tourVersion` (the upgrade, in Release and under
  `-SillTourState saved` only), `TouchWatcher`, a recognizer on the window that counts
  every touch and takes none, and DEBUG `TourDebug`); StreamScreen runs it
  (targets, the rule's inputs, `tourFeatures`, the layer above the layouts and
  under the pairing overlay, Take the Tour from the Settings panel's last row),
  and MacMenuButton reports the Menus button as the target `menus`. The
  connect screen's tiles and groups (issue #116, PR #117): `ConnectionList`
  (rows or tiles, `Sill.connectionStyle`, tiles by default since 2026-10-27
  (`defaultStyle`; a stored choice always wins); when a session's
  end keeps a picture, `takesPreview`: only with tiles, from the session's own
  window in front, for a saved Mac; the saved Mac a row stands for, `tileMac`:
  its tag's or record's, else the one it is taken for by name, so every row
  of one Mac (Wired, Wi-Fi, Direct, Remote) shows its one picture and is listed
  under its group; what a launch or a change of style does,
  `previewPlan`: the list hides the pictures and keeps their files, tiles show
  them again, only the files of Macs no longer saved go; the picture's size,
  `previewPixels`, 640 pixels wide at most, and `looksBlack`;
  `keepsDecodedPicture`; whether Disconnect asks the Mac for a keyframe
  first, `freshPicture`, every Mac whatever version it says; group names,
  `Sill.macGroups`, and the sections' order; a superseded record's group; the
  pictures' file names; pure, with KeyframeRecovery's spacing,
  `Tests/checks/connection-list`; pbxproj AF01/FF01). ConnectScreen draws them
  (the switch beside the title, the tiles, a saved Mac's Group menu and New
  Group…), StreamClient+Remote keeps them (`savePreview` with complete file
  protection in Library/Caches/SillPreviews, `syncPreviews` at launch and at a
  change of style; only Remove Preview Picture and Forget delete a Mac's),
  and StreamClient takes the picture: the session's last keyframe with its
  parameter sets (`lastKeyframe`, on the network queue, one frame, dropped at
  `tearDown`), decoded at the session's end by `KeyframePicture` (a
  VTDecompressionSession of its own, off the main thread, 1 s at most;
  pbxproj AF02/FF02), never a snapshot of the screen, which a device draws
  black where the video is; Disconnect waits up to 300 ms for a fresh keyframe
  first (kind 44, every Mac; one that skips it, Sill for Mac 0.5.1, costs that
  pause, its picture the keyframe kept).
  `AudioDecoder` (AAC-ELD to a buffer per channel, one packet at a time;
  AudioToolbox only), `AudioPlayout` (the sound's timing; pure,
  `Tests/checks/audio-playout`), `AudioOutput` (its queue, the decoder and the
  engine; no video frame handed to its queue before the session's first format, the last 32 kept
  for the guard) and `StreamClient+Audio` (this device's mute, `soundMuted`, the Settings panel's
  Mute; `macHasSound`, whether it shows): pbxproj AA01–AA04; the host's `audio-codec` check and
  the sound harness's device compile AudioDecoder too. The Settings panel (`HostSettingsPanel`)
  holds the sound's two switches: the Mac's group's Send Audio (for every device, with a "Beta"
  tag) and Mute right under it; no bar has a Sound button (Noah, 2026-10-27).
  `Info-Debug.plist` is the Debug configuration's Info.plist: Info.plist's
  keys, with `_silltest._tcp` beside `_sill._tcp` for the harness's
  `-SillServiceType` (Release declares `_sill._tcp` alone).
  `PrivacyInfo.xcprivacy`, a resource of the target, is the privacy manifest:
  it declares UserDefaults (CA92.1), `systemUptime` (35F9.1) and the active
  keyboards (54BD.1: `UITextInputMode.activeInputModes`, which decides whether ⌃Space is
  iPadOS's keyboard switch or the Mac's, #138; found by release-ios.sh's check on 2026-10-29,
  which refuses an export App Store Connect would refuse, ITMS-91053), and any new use of a
  required-reason API (file dates, disk space, `mach_absolute_time`) must add its category
  and reason there before the next upload. New files need their four pbxproj entries by hand.
  Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.
- `docs/steps/` — what each piece of work did: one file per branch, release or finding,
  `<date>-<branch>.md` (the date its work began), written by the branch that does the work and by
  nobody else (CLAUDE.md, "Steps"); `README.md` lists the ones that were this file's "Current step"
  until 2026-11-12, in their old order, frozen. `Scripts/steps.sh` makes this branch's (`new`), lists
  the newest (`list`) and finds one (`find 349`); `Scripts/migrate-notes.py` moves the notes of a
  branch opened before then out of CLAUDE.md, the checks' table and ci.yml once it merges main.
- `docs/DEVELOPMENT.md` — building, running and testing from source; the
  README's developer material until 2026-09-25, so a plan's "README" means a
  section there: the toolchain, make-app.sh, Sill.app's menu and Quality, the
  CLI's flags, the iOS project, Permissions (the TCC reset), settings from a
  device, Direct Wireless, pairing at home (the cable, Require pairing, older
  builds, starting over), remote access (setup, troubleshooting, reset), the
  test tools in brief (Build and run below has them all), measuring latency,
  troubleshooting (slow, frozen, the encoder), releasing, known limitations.
- `README.md` — the public front page: the site's lede, links to getsill.app
  and its download, support, privacy and terms pages, the App Store badge
  (live since 2026-10-10), requirements, how it works, tips, building from
  source in brief,
  contributing, the license. `LICENSE` — the Apache License 2.0.
  `design/screenshots/` — the README's screenshots: the App Store's iPad set at
  half size. Their raw URLs go to open-source app lists: keep the names.
  `.github/FUNDING.yml` — the Sponsor button: GitHub Sponsors (a `ko_fi:`
  line joins it once there is a Ko-fi handle). Tip links live there, in the
  README's Tips and on the site, never in the iOS app. `SECURITY.md` — how to
  report a vulnerability (support@getsill.app, never a public issue) and what
  is in scope. `.github/ISSUE_TEMPLATE/` — issue forms: a bug report, an idea,
  a question, no blank issue. `.gitignore` also leaves out signing keys,
  profiles, keychains and design/reel/.
- `.github/workflows/` — GitHub Actions on the `xcode-27` runner (macOS 27
  with Xcode 27, a public preview; the only image with Xcode 27). `ci.yml`:
  pull requests and pushes to main that touch more than documents or the site
  (`design/` counts: `dmg-layout` reads its SVG), and by hand; `swift build -c release`,
  `Tests/checks/run-all.sh`, the iOS app for the generic simulator (Debug,
  arm64, `CODE_SIGNING_ALLOWED=NO`; with Xcode 27.1, its beta while the image
  has no 27.1 release), and the CLI's paths that exit before the
  host starts (`--internet` alone, exit 2; `--print-reachability`); by hand
  with "mutants", each check's mutants in a job of its own (up to 120 minutes), the checks read
  from the folders by `Tests/checks/mutant-checks.py`, which stops the run on a list that is empty
  or leaves one out. `release.yml`: a
  pushed tag `v*`, or by hand with one; verify only (the tag, the checks,
  `make-app.sh` signed ad hoc, zipped, and `make-dmg.sh`'s image of it, ad hoc
  too, as two artifacts) unless the repository
  variable `SILL_SIGN_IN_CI` is `true`, then, in the environment `release`
  (only `v*` tags, Noah its required reviewer; its first step names a missing
  secret and refuses a run by hand not started from its tag; it checks out
  the run's own commit, `github.sha`, and stops when the tag no longer names
  it), the Developer
  ID .p12 into a temporary keychain, the notary key stored as a profile in it, the Developer ID
  profile decoded from `SILL_PROVISION_PROFILE` into
  `Packaging/embedded.provisionprofile` (since the nightlies), `release.sh
  --publish`, Apple's notary logs kept as an artifact (`include-hidden-files:
  true`: upload-artifact skips whatever is under a folder whose name starts
  with a dot, `.build` included), and the keychain deleted in an always()
  step. Secrets,
  variables, rotation and costs: docs/release-checklist.md, "Releasing from
  GitHub Actions". `testflight.yml`: by hand from main only (the environment
  `nightly`); `release-ios.sh
  --unsigned` without an App Store Connect key, `--sign-at-export` with one
  (the secrets `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID`,
  `SILL_TESTFLIGHT_KEY_P8`, an Admin key: cloud signing, no certificate or
  profile stored), and `--upload` too when the variable `SILL_TESTFLIGHT_IN_CI`
  is `true` and the commit is on main's first-parent line (another branch's
  count can be a later nightly's), the build number the commit count
  (`--build-number`); the .ipa is
  the artifact for 14 days (docs/release-checklist.md, "TestFlight from GitHub
  Actions"). `nightly.yml`: 09:17 UTC while the variable `SILL_NIGHTLY` is
  `true`, and by hand (`verify_only`); decide (the skip rule against the
  pre-release's sha, the date, the build number, the notes once), Sill for Mac
  (`release.sh --nightly --publish` with `SILL_SIGN_IN_CI`, else ad hoc
  artifacts), Sill for iPhone and iPad (`release-ios.sh --build-number`, the
  upload with `SILL_TESTFLIGHT_IN_CI`, then `asc.swift distribute`: every
  internal group, the public beta group only while `SILL_NIGHTLY_PUBLIC_BETA` is
  `true`, the night's notes replacing What to Test only on a build that run
  uploaded, `--replace-whats-new` after the upload step's `uploaded=true`); only main builds: both jobs run in the environment `nightly` (only
  main, no reviewer), which holds the nine secrets, none of them a repository
  secret (docs/release-checklist.md, "Nightlies", "Secrets and variables").
  `.github/actions/select-xcode` —
  selects the newest Xcode of the `version` asked for (27; CI's build 27.1)
  whose folder is not a beta and prints `xcodebuild -version`; with
  `allow-beta: 'true'` (CI's build alone, never a build for App Store
  Connect), a version with no release yet takes its newest release candidate
  or beta; without one, CI warns and takes the newest Xcode there and a
  release (`fallback: false`) fails (CI only: it runs `sudo xcode-select`). The runner's `bash` is 3.2: try `run:`
  steps with `/bin/bash`. Actions are pinned by commit hash.
- `Tests/checks/` — the pure checks, a folder each, which says what it checks and what it compiles in
  its own `README.md`: `main.swift`, `run.sh` (compiles the app's files it names with swiftc into
  `.build/checks/<name>/` and runs; `--mutants` runs `mutants.py`, passing only when every mutant is
  caught), and `build.sh` where a check compiles a module (StreamProtocol's sources with `import
  StreamProtocol` stripped), or a `module.txt` naming the files `module.py` compiles as one module.
  `list.sh` prints every check with what it checks (no table is kept by hand); `run-all.sh
  [--mutants] [-v] [name…]` runs them and exits with the number that failed (a folder whose `run.sh`
  is not executable fails); `common.sh` is sourced by each `run.sh`; `mutant-checks.py` gives CI the
  checks with mutants, read from the folders; `repo-rules` fails a check folder without its
  README.md, a static mutants list in ci.yml, and a step entry written back into CLAUDE.md;
  `HISTORY.md` is the old README with its table, frozen. A change to a checked file updates its
  check (and a mutant's pattern) in the same commit.
- `Tests/touchrig/` — the touch rig (docs/trackpad-gestures-plan.md §9.2): the
  real `TrackpadView.swift` and `InputOverlay.swift` in a scratch simulator
  app, driven with synthesized touches (`TouchSynth`, private UIKit calls, test
  only, never in the app), every event logged; `run.sh [--rev REV] [--switch
  off] NAME` builds and runs it on a simulator of its own
  (`SILL_TOUCHRIG_SIM`), `compare.py` judges a run against the surfaces
  before, and a stroke made right after a gesture against the same stroke
  made fresh.
- `Tests/duorig/` — TEST ONLY, private interfaces, simulator only: folds and
  turns the iPhone Duo simulator with Device Hub's own events (usage page
  0xFF61, usage 0x5B, an IOCFSerialize dictionary from
  `com.apple.Virtualization.VirtualMachines`), posted from a virtual HID
  service inside the simulator (`xcrun simctl spawn`); `run.sh build`, `run.sh
  UDID pose <closed-upright|closed-side|flat-portrait|flat-landscape|laptop|book>`,
  `run.sh UDID shot <pose> FILE.png`, `hinge`, `orient`, `watch`; only a
  booted iPhone Duo simulator, by UDID (its README).
- `Tests/keyrig/` — TEST ONLY, private interfaces, simulator only: a hardware
  keyboard and a mouse for the iOS Simulator, key presses, pointer moves and
  wheel scrolls posted from a virtual HID device inside the simulator (`xcrun
  simctl spawn`, as duorig), which UIKit routes as a real one's
  (pressesBegan, key commands, the text system, GameController, hover, scroll
  pans); `run.sh build`, `run.sh UDID keys SPEC` (`wait:S` among its steps holds
  a key: `13:down,wait:2,13:up`), `run.sh UDID point SCRIPT`;
  only a booted simulator of your own, by UDID (its README has what it showed:
  after its keys UIKit there counts a hardware keyboard for good).
- `Scripts/harness-photos/` — the DEBUG harness photographed on the agents' shared simulators,
  never one an agent makes for itself: `Scripts/agent-simulators.sh create` makes them once ("Sill
  agents Duo", iPhone Duo on iOS 27.1, and "Sill agents iPad", iPad Pro 13-inch (M5) on iOS 27.0,
  whose 27.1 runtimes take only the Duo) and `list` shows their state and size;
  `Scripts/harness-photos.sh CASES [--commit REV] [--baseline REV] [--device duo|ipad] [--repo DIR]`
  builds each commit's committed tree once (cached by commit and Xcode build in
  `~/Library/Caches/SillAgents`, one shared DerivedData), boots one of them inside the heavy lock,
  takes a photo per case (a name and launch arguments a line, `example.cases`), compares a baseline's
  pixel for pixel (`pixeldiff.swift`: how many pixels, by how much, where; a picture of the
  differences) and shuts it down. It refuses another name than "Sill agents …", any other booted
  simulator, a case without `-SillLayout` or with `-SillLive` or anything that dials or sends input,
  a Duo size or `-SillHinge` on the iPad, and building or a first boot under 25 GB free; it never
  taps or types and needs no `no-device.sh` (no host, no encoder, stills only).

## Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
swift run -c release SillHost --synthetic  # Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --encoder-selftest   # is the hardware encoder alive? 5 s, exits
swift run -c release SillHost --virtual-display   # picked windows stream from their own HiDPI display (off by default in the CLI; on in Sill.app)
swift run -c release SillHost --virtual-display-selftest   # create/destroy one display, report what sees it ([Hz] [WxH] after it: `60 800x830`)
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi (AWDL): devices without a shared network (off by default)
swift run -c release SillHost --audio       # Send Audio (a beta) for this run: the streamed app's sound to devices that play it (with --synthetic, a test tone; off by default; a device's Settings panel turns it on or off too)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 .build/release/SillHost --synthetic --audio   # the test tone on loopback; sillclient.py PORT 8 desktop --hello=0.6 --audio counts it
Scripts/audio/run.sh                        # the encoder-free sound harness and its gates (~7 min; no encoder, capture, speaker or device)
swift run -c release SillHost --remote      # the remote door for this run on any free port (--remote=PORT), a throwaway identity; the code and link print here
swift run -c release SillHost --remote --internet   # also admit paired devices from outside this Mac's networks and VPNs
swift run -c release SillHost --print-reachability  # the addresses a device would get away from home, then exit
swift run -c release SillHost --pairing     # the home door speaks TLS, pairing required, a throwaway identity; the code and link print here (with --remote, one pairing for both doors)
swift run -c release SillHost --print-cable # what the cable rule reads on each interface, and whether the console is unlocked; read-only, then exit
swift run -c release SillHost --menu-selftest=TextEdit   # the menus a device would be sent for that app (a pid, or the start of its name), read once; read-only
python3 Scripts/sillclient.py PORT 5 none --pair-ask --then-code=$T/code --identity=$T/a   # a device's ask at a TLS home door, then the code the host printed (saved in $T/code)
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000   # a device's settings change
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_STILL_AFTER=3 .build/release/SillHost --synthetic   # the Desktop still from 3 s on: a device's picture comes back only through its keyframe request
python3 Scripts/sillclient.py PORT 8 desktop --keyframe@3   # kind 44: "Keyframe for …" on the host, and the summary's "keyframes at" shows the one it brought
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_STILL_AFTER=3 SILL_TEST_KEYFRAME_IGNORE=1 .build/release/SillHost --synthetic   # the first keyframe request ignored, as a Mac from before kind 44 ignores every one: the device asks again 4 s later
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_NO_SCREEN=1 SILL_TEST_DESKTOP_FAIL=2 .build/release/SillHost --synthetic   # the first 2 Desktop starts fail, as ScreenCaptureKit's did on 2026-10-28 (1: the host's one more try streams; 2: a device asks again 10 s later)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # a scripted pointer on the test pattern, on 127.0.0.1 alone, never the hardware encoder
python3 Scripts/sillclient.py PORT 6 desktop --pointer --move=0.25,0.25@3   # each kind 26 as it arrives; input goes only to a --synthetic host
SILL_TEST_INPUT_LOG=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # prints each event a dry run would post ("Test input: key 49 up (none)")
python3 Scripts/sillclient.py PORT 3 desktop --input='{"key":{"hidUsage":44,"down":true,"modifiers":1048576}}@1' --input='{"key":{"hidUsage":44,"down":false,"modifiers":1048576}}@1.05' --tap=0.5,0.5@1.5   # an older device's Spotlight key, then a tap
python3 Scripts/sillclient.py PORT 6 desktop --key=80,1.2@2   # ← held 1.2 s (pinging four a second, as a device): with the input log, "Test input: key 123 down (none)", repeats from 0.5 s on ("… repeat (none)", 30 a second on this Mac), then its up
python3 Scripts/sillclient.py PORT 8 none --gesture=swipeUp@3 --gesture=swipeDown@4   # a synthetic host logs "Gesture from …: swipe up → Mission Control (shortcut 108: key 160, fn) (not posted: a test host)"
SILL_TEST_LOOPBACK=1 SILL_TEST_HOTKEYS='108=off,173=off' .build/release/SillHost --synthetic   # TEST ONLY: the gestures read this table (over macOS 27's own; `defaults` alone) instead of this Mac's shortcuts
swift run -c release SillHost --no-clipboard  # share nothing of the clipboard with devices (on by default, as in Sill.app)
swift run -c release SillHost --off-console-view   # show this account while another user is on the screen (off by default, as in Sill.app's Settings › Devices): docs/off-console-plan.md
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_PASTEBOARD=me.saffer.sill.test.x SILL_TEST_CLIPBOARD_LOG=1 .build/release/SillHost --synthetic   # the clipboard on a pasteboard of its own (never this Mac's), each decision printed with sizes
SILL_TEST_NO_SCREEN=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 .build/release/SillHost --synthetic   # TEST ONLY: ScreenCaptureKit never asked (no window list, no thumbnails), so a host an agent runs asks macOS for no screen recording
SILL_TEST_FIREWALL=executable SILL_TEST_NO_SCREEN=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 .build/release/SillHost --synthetic   # TEST ONLY: the macOS firewall's answers canned (executable|bundle|both|all|off|allowed|unreadable, or a file holding one, read at each check): "Firewall: the macOS firewall blocks Sill’s executable, …"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate; …/socketfilterfw --listapps; …/socketfilterfw --getappblocked PATH   # the firewall, read-only as any user; never --unblockapp, --add, --remove or --set* (they change it, with sudo)
python3 Scripts/sillclient.py PORT 6 none --clipboard --copy=hello@2 --expect=clipboard=none   # subscribe, send text as a device's Paste does; each kind 32 printed
SILL_TOUCHRIG_SIM='Sill touchrig' Tests/touchrig/run.sh new && Tests/touchrig/run.sh --rev origin/main base && Tests/touchrig/compare.py .build/touchrig/base.log .build/touchrig/new.log   # the surfaces under synthesized touches
Tests/checks/run-all.sh                 # every pure check, as CI runs them (~5 min; --mutants adds the mutants, well over an hour)
Tests/checks/list.sh                    # every check and what it checks, from each folder's README.md (no table is kept by hand)
Scripts/steps.sh new | list | find 349  # the step files (docs/steps): this branch's, the newest first, a pull request's
python3 Scripts/migrate-notes.py        # once, in a branch opened before 2026-11-12, right after `git merge origin/main` stops
Scripts/agent-simulators.sh create      # once: the agents' simulators "Sill agents Duo" (iOS 27.1) and "Sill agents iPad" (iOS 27.0), shut down
Scripts/harness-photos.sh Scripts/harness-photos/example.cases --baseline origin/main   # harness photos of HEAD (committed) on the agents' Duo, pixel for pixel against main's, in the heavy lock
Scripts/pacing/run.sh                   # remote pacing and the link's judge, this tree against origin/main, no encoder, all on loopback (~25 min; --full ~45; --list)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_ORIGIN=vpn SILL_TEST_PATTERN=noise .build/release/SillHost --synthetic --remote   # an away session whose stream follows its quality
Scripts/make-app.sh                     # .build/Sill.app, signed with the Apple Development identity (~2 s unchanged)
Scripts/make-app.sh --install --open    # Noah: replace /Applications/Sill.app (a running one quits first), launch it
SILL_UNIVERSAL=1 Scripts/make-app.sh    # .build/Sill.app for Apple silicon and Intel (arm64 and x86_64), as releases are since 0.6.0 (#62): twice the build time
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release   # M6
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh [--dry-run]   # M6: the notarized download (docs/release-checklist.md)
Scripts/release-ios.sh                  # the iOS app for App Store Connect: archive, export .build/ios/export/Sill.ipa, check it; uploads nothing
Scripts/release-ios.sh --bump --upload  # Noah: the next build to TestFlight (docs/release-checklist.md, TestFlight; --privacy-report, --print-version)
Scripts/make-dmg.sh --sign - .build/Sill.app .build/Sill.dmg   # the download's disk image of any build, ad hoc (release.sh makes the real one)
python3 -m http.server 8000 --directory site   # the website at http://localhost:8000
Scripts/encoder-check/run.sh            # the encoder checks that never touch an encoder (safe while Sill.app streams)
Scripts/menu-check/run.sh               # the menus' reader and mirror against Scripts/menufixture.swift, no host, no encoder (needs Accessibility)
Scripts/restore-probe/run.sh            # TEST ONLY: a window Sill sized goes back, against a window of its own (needs Accessibility, Screen Recording, an unlocked screen)
Tests/duorig/run.sh UDID pose book && Tests/duorig/run.sh UDID shot book book.png   # TEST ONLY: fold and photograph an iPhone Duo simulator (laptop, flat-portrait, flat-landscape, closed-upright, closed-side)
Tests/keyrig/run.sh UDID keys 29,04,e3:down,1a,e3:up && Tests/keyrig/run.sh UDID point 'move 300,200|wheel -3'   # TEST ONLY: Esc, a and ⌘W from a hardware keyboard, then a wheel's notch, inside a simulator of your own
SILL_TEST_ENCODER_RECYCLE=0 swift run -c release SillHost   # =0 keeps every hardware session, =1 replaces one in the slow state, as by default (A/B on the real Desktop: --synthetic moves every frame and never reaches the slow state)
Scripts/encoder-check/verify-hardware.sh harness   # USES THE HARDWARE ENCODER; skips each run while a device is connected
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording: the CLI's belongs to Terminal (or
whatever launched it), Sill.app's to Sill itself.
Sill.app: the log is `~/Library/Logs/Sill/Sill.log` (`tail -F`, not `-f`: at
10 MB it moves to Sill.1.log; Show Log… in the menu); settings are `defaults
read me.saffer.sill.mac` (maxFPS, captureScale, bitrate, prioritizeSpeed,
virtualDisplay, directWireless, sendAudio, shareClipboard, updateCheck,
showPairingWindowToScreenSharing; the update check keeps
updateLastCheck, updateETag, updateLatestTag and updateLatestURL), and a launch
argument such as `-maxFPS 60` or `-updateCheck 0` overrides one for one run. A device's change from its Settings panel is saved there too, like a
menu click; the CLI keeps a device's change until SillHost quits. Test arguments for the bare binary (`.build/release/SillMenuBar`,
defaults domain `SillMenuBar`; delete it after): `--synthetic` (test pattern,
off Bonjour; the port is in the "Status: Test Pattern Mode" line),
`-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`,
`-SillQuitAfter <s>`, `-SillRenderPreviews <dir>` (panes, cards, glyphs,
menu.txt; no permission needed), and for the Settings window's height
`-SillSettingsAfter '<s> <tab>|close|report|end|height=<points>[; …]'` (opens it,
then prints its frame, the pane's whole height and how much shows),
`-SillTestScreenHeight <points>` and `-SillSettingsShot <dir>`
(docs/DEVELOPMENT.md, Test arguments for the bare app). The update check, in the bare binary (which
has no version and never checks without these) and the app: `-SillUpdateFeed
http://127.0.0.1:P/latest` (a feed on this Mac only: 127.0.0.1, ::1 or
localhost; `Scripts/sillfeed.py P` serves one; test pattern mode checks only
such a feed), `-SillUpdateVersion 0.3.0`, `-SillUpdateNow 1` (one check at
start, as Check Now), `-SillUpdateInterval <s>` (24 h become s seconds, the
retry s/24), `-SillPrintMenuAfter <s>` (the status menu as it would open, and
Settings › General's update line, in the log), `-SillSetAfter '<s>
updateCheck=0'`. Never run a test against GitHub. To make Sill.app check again at
its next launch: `for k in updateLastCheck updateETag updateLatestTag
updateLatestURL; do defaults delete me.saffer.sill.mac $k; done`. Render previews from
`.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only the
bundle's copy records the real SDK (make-app.sh sets it with vtool; see Current
step), and the bare binary draws the pre-26 look. `--encoder-selftest` and
`--virtual-display-selftest` work in the app too.
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi (or with the Mac's Direct Wireless Connection on).
AWDL, headless and without touching a running Sill.app: the synthetic hosts do
not advertise, but `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers them as
"Sill test ‹pid›" under that test type (never `_sill._tcp`, so no device sees
them) with the listener's own peer-to-peer flag, and prints which one it got;
`SILL_TEST_SWAP_FAIL=port|all` makes a replacement's same-port (and any-port)
bind fail; `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` counts a client scoped to that
interface as one on peer-to-peer Wi-Fi, so a test client on the Mac's own en0
link-local address (`ifconfig en0`, `fe80::…%en0`; Python's socket takes it)
stands in for a device on awdl0 when Direct Wireless turns off (a local
connection to the Mac's own awdl0 address never became ready, so awdl0 cannot
be tested headless); all three are honoured only by a host that does not
advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
registration that includes AWDL a second time on awdl0's index (`python3 -c
'import socket; print(socket.if_nametoindex("awdl0"))'`, 16 here). dns-sd
options go before the command: `dns-sd -R … -includeAWDL` registers a TXT
record "-includeAWDL" and sets no flag. The kernel's count of AWDL services:
`/usr/bin/log show --last 1m --style compact --predicate 'process == "kernel"
AND eventMessage CONTAINS "BonJourTrig"'` ("ValidSvc N" once a second; a
registration with AWDL adds 2, a peer-to-peer browse 1); `log` is a zsh
builtin, hence `/usr/bin/log`, and `process == "kernel"` keeps the log tool's
own line out. Enable and disable lines ("Enabling AWDL due to Mdns") show only
when nothing else holds AWDL. Keep AWDL-on tests under 20 s and on test types.
Remote access, headless: TEST ONLY variables, honoured only by a host that
does not advertise: `SILL_TEST_REMOTE_DIR=<dir>` (the identity and trust list
in a 0700 directory instead of memory or the keychain; the bare app's
`-SillPairAfter <s>` leaves `pairing.url` and `pairing.code` there, 0600, never
printed), `SILL_TEST_PAIRING_TTL=<s>`, `SILL_TEST_BACKOFF_SECONDS=<s>` (the backoff a TLS door
gives an address whose connections waited unadmitted or were refused, five failures in a minute:
a test client's `--pair-hold`s, refused handshakes or connections it keeps closing, from 127.0.0.1,
meet it, "Home door backed off 127.0.0.1 for 300 s: …"), `SILL_TEST_ORIGIN=vpn|internet` (loopback
counts as that origin),
`SILL_TEST_REMOTE_ORIGIN=vpn|internet|lan` (the same at the remote door alone, so
one loopback host serves a device away and one at home: away from home's
H8 and S4; without it a loopback client at the remote door is a relay on this
Mac, away from home (issue #326), and `lan` makes it this network, at home, "by
address", as every loopback client there was before) and `SILL_TEST_NO_ROUTER=1` (never ask the router; set it on every
headless host). Away from home and the link, headless (docs/remote-bundle-
plan.md, PR B): `SILL_TEST_PATTERN=picture:<path>` gives a synthetic host a
still picture for its Desktop (any image ImageIO reads, filling the frame:
photographs of a device, docs/iphone-duo-plan.md); `SILL_TEST_PATTERN=noise`
gives it a square of noise, so its stream follows the quality (on the software encoder about 14
frames a second, 3.6 Mbit/s at Low and 10.6 at Balanced), for a test of the
link through `sillrelay.py --rate-mbps 5`; `sillclient.py` prints `away=` and
`link=` on each kind 16, and `--expect` knows `awayBitrate`,
`awayCaptureScale`, `homeBitrate`, `homeCaptureScale`, `thisConnectionAway`,
`awayRunning` and `linkState`.
The Mac's pointer, headless: every synthetic host is a dry run (its input is
counted as `in.dry`, never posted, and activates or raises nothing) and never
reads the real pointer. TEST ONLY, honoured only by a synthetic host (anywhere else one
line says it is ignored): `SILL_TEST_POINTER_PATH=<file>` is a scripted
pointer on the test pattern, lines `T X Y` (seconds since the stream's first
sample, points in the 1512×949 pattern, outside allowed; `#` comments; at most
10,000 steps and 1 MiB, a bad file refused whole with one line): the test
pattern then has a pointer, a test client's input lands in the pattern's space
and a dry-run pointer event moves the scripted pointer (the newer of it and a
step wins); `SILL_TEST_NO_SCREEN=1` makes the window catalog leave ScreenCaptureKit alone (an empty
window list, no thumbnails, no display lookup), so a test host with a client connected asks
macOS for no screen recording: every ScreenCaptureKit call counts against the responsible app's
grant (Claude's, for a host an agent runs), and macOS reminds the person once a month and after
every rebuilt binary; set it on every headless host whose test needs no real window.
`SILL_TEST_SOFTWARE_ENCODER=1` starts on the software encoder, with
no launch probe and no re-check, so a test never touches the hardware encoder
(60 fps at most: a 120 fps sampler test needs the hardware, and so the
no-device check); `SILL_TEST_INPUT_LOG=1` prints each event the dry run would
post, "Test input: key 49 down (command)" with the flags it was made with, and
a pointer or scroll event with those the last keyboard event would have left
in the HID state table, a button's with where it goes ("Test input: left mouse
down (none) at 756,474"), a scroll's with its point deltas, phase and place
("Test input: scroll dy -12 dx 0, gesture changed (none) at 833,442": positive
dy moves the content down, so the sign shows which way a device's scroll went,
and every event of one scroll lands at one place), and each
check a key's up arms ("Test input: key 55
up: the table read again in 0.25 s for command"): what a device's keys and
buttons leave for its next click (KeyStrokes), without posting anything; and
where a device the Mac stops serving stops landing input ("Test input: iPad is
no longer served: only the up of a key or a button it holds down goes from
here on.", RevokedInput).
A sleeping display, headless: a test host declares no user activity and counts
`disp.wakeDry` where a real one would declare (`sillclient.py`'s connect, a tap,
a key; never a pick, nor a move right after a restart). TEST ONLY
`SILL_TEST_USER_ACTIVE=remote`, taken by every real host and Sill.app too
(`open --env SILL_TEST_USER_ACTIVE=remote /Applications/Sill.app`, Sill quit
first), declares `kIOPMUserActiveRemote` instead of Local; it acts on this Mac's
display, so it is Noah's to try (docs/DEVELOPMENT.md, A sleeping display).
The device floor, headless: `SILL_TEST_MIN_DEVICE_VERSION=1.2` raises the floor
of a host that does not advertise (a device below it, or one that sends no
hello, gets kind 22 "update" and is closed; a value that does not parse is
ignored with one line), and `SILL_TEST_GOODBYE='<JSON Goodbye>'` makes its
refusals send that payload instead (a reason the device does not know).
Pairing at home, headless: `SillHost --synthetic --pairing` (the bare app's
home door always speaks TLS, as Sill.app's does) with `SILL_TEST_REMOTE_DIR`,
`SILL_TEST_NO_ROUTER=1`, `SILL_TEST_SOFTWARE_ENCODER=1` and
`SILL_TEST_LOOPBACK=1`; the CLI prints its code and link, and again after each
ask. The door and pairing hooks are TEST ONLY and honoured only by a test host
(DoorPolicy.isTestHost: one that does not advertise and is not Sill.app's own
executable; anywhere else TestHooks prints one "ignored" line for each set),
and so are the ones above (SILL_TEST_SERVICE_TYPE and the rest):
`SILL_TEST_CABLE_INTERFACE=<if>` counts a client scoped to that interface as
one on the cable to an "iPad" (serial TEST) and lets this Mac's own address
there through, so a client at this Mac's link-local address on it
(`sillclient.py --host=fe80::…%<if> --pair-ask=cable`) stands in for a device
on the cable, and the simulator's `-SillCableTest 1` for the device's side
(lo0's `fe80::1%lo0` keeps such a test on this Mac; it needs a listener there,
which SILL_TEST_LOOPBACK's 127.0.0.1 alone is not); `SILL_TEST_LOCKED=1` makes
this session's screen locked for the run, and `SILL_TEST_LOCKED_FILE=<path>`
read at each look (once a second while a device is connected): `1` the screen
locked, `2` off console (another user), anything else nothing, so `echo 1 > $F`,
`echo 2 > $F` and `echo 0 > $F` lock, switch and unlock a running test host
(docs/locked-mac-plan.md: a black placeholder, no windows, apps, menus, gestures,
sound, clipboard, pointer or cursor shape, input only from a paired session at a
locked screen and from nobody off console, the unlock after a 2 s settle);
`SILL_TEST_LOCK_NOTIFY=<me.saffer.sill.test.…>` reads the screen's lock state
from a notify name of the test's own (set it with notify_set_state and
notify_post: the CLI's immediate path), `SILL_TEST_LOCK_NOTE='<s> <name>; …'`
delivers loginwindow's or NSWorkspace's notifications to SessionLock's handler on
cue (nothing posted: never post those names, other apps hear them), and
`SILL_TEST_LOCK_LOG=1` prints each look's witnesses; `sillclient.py`'s list line
says `locked=1` and `offConsole=1`, `--dump=DIR` saves what arrived when with the
parameter sets and keyframes, and `--raw7` and `--raw15` send a launch and a
window's button; `Scripts/lock-check/live.py OUT [poll|start|notify|paired|all]` runs a
test host through all of it and decodes the keyframes (`build.sh` first);
`SILL_TEST_ASK_QUIET=<s>` shortens the 10 minutes of quiet
after the Mac's Cancel or a stop; `SILL_TEST_ASK_FROM_THIS_MAC=1` skips the
ask rule's step for an ask from this Mac itself (answered `openOnMac` unless a
window is open, and lighting no menu item), so a test client on this Mac opens
windows; `SILL_TEST_REQUIRE_PAIRING=0` (the CLI's) turns Require pairing off
at `--pairing`'s door for the run, so an unpaired device's session can be
tried (`sillclient.py --tls --identity=DIR --pin=none`). The bare app takes
`-requirePairing NO`, `-SillSetAfter '<s> requirePairing=0|1'`,
`-SillCancelPairingAfter '<s>[; <s> …]'` (the window closed as its Cancel
does), `-SillCableNoticeAfter <s>` (the cable notice for a sample device) and
`-SillMenuAfter '<s>[; <s> …]'` (the status menu in the
log, line by line). Sill.app itself ignores every `-Sill…After` hook,
`-requirePairing` and `SILL_TEST_REMOTE_DIR` with one line each (any process
can start it with arguments and its grants); `-SillRenderPreviews`,
`-SillLogFile` and the encoder's variables still work there. Require pairing
and the trust list live in the login keychain (service
`me.saffer.sill.remote`, accounts `paired-devices` and `require-pairing`,
beside the key "Sill Remote Access"), never in UserDefaults; Settings ›
Devices' Remove forgets one device, and deleting those items makes this Mac
new to every device. Two hosts under one Bonjour name (a Mac that took
another's name, the security scan's finding 3): run each without
SILL_TEST_SERVICE_TYPE (whose registration is "Sill test ‹pid›") and advertise
it in turn with `dns-sd -i lo0 -R "Studio f3" _silltest._tcp local PORT
r=<16 base64url characters> p=0`, on lo0 alone (on every interface the
simulator dials this Mac's other addresses first, which a loopback host never
answers); the bare `SillMenuBar --synthetic -requirePairing NO`, under a name
of its own and with `-SillLogFile`, is an open door.
The Mac's menus, headless: `swiftc -O Scripts/menufixture.swift -o
$T/menufixture -framework AppKit`, then `$T/menufixture serve $T/fixture.log
60` (it exits by itself, 120 s at most, and can never take the front) and a
synthetic host with `SILL_TEST_MENU_PID=<its pid>` (honoured only by a host
that does not advertise; "Test menus: …" at start): the test pattern's menus
are then the fixture's, read and pressed without activating it. `python3
Scripts/sillclient.py PORT 20 desktop --menus --fetch=4@3 --press=4.0@5` (with
SILL_TEST_MENU_PID in the client's environment too) prints each kind 24 on a
line, and `$T/menufixture label PID` what the last press set ("A"); `kill
-HUP` inserts an item at the top of Probe in place (the ids below it move: the
host's next read of a moved place moves the version), `-ALRM` gives Probe a
new menu, and `-USR1`/`-USR2` give Probe › Rebuilt one.
`--menu-selftest=menufixture` reads it. Presses go only to the fixture, and a
real app's menus are read only with `--menu-selftest=TextEdit`, never a bare
`--menu-selftest` (the frontmost app); the plan's §10 has the gates.
The bare app takes `-remoteAccess 1 -remotePort P`, `-SillSetAfter '3
remotePort=P2'`, `-SillPairAfter <s>` and `-SillUnpairAfter <s>`; its
`-SillRenderPreviews` adds the Remote Access pane's states and the pairing
window's. A session through a shaped link: `python3 Scripts/sillrelay.py
--listen 0 --to 127.0.0.1:P --delay-ms 150 --rate-mbps 2`, then
`sillclient.py RELAYPORT 90 desktop --tls --identity=$T/a --stats` after
`--pair-url=URL` once. Never let a test binary take a connection from another
machine: the Application Firewall prompts. `SILL_TEST_LOOPBACK=1`, honoured only
by a host that does not advertise, makes both doors of a test host listen on
127.0.0.1 alone ("Test listener: loopback only …"; `lsof` lists
`127.0.0.1:PORT`); a device on this Mac, the simulator included, and the test
clients reach it by 127.0.0.1. Reset the app's remote settings with
`for k in remoteAccess remotePort internetAccess remoteAddressName
remoteDevicesSeen; do defaults delete me.saffer.sill.mac $k; done`.
Debug harness (simulator; the iPhone Duo's from the iOS 27.1 runtime, folded
by Tests/duorig): launch arguments `-SillLayout 951x669` (inner landscape) /
`669x951` / `466x678` / `678x466` (the cover), each with the safe area its
display gives Sill, the status bar's strip included but on the stream screen
upright with `-SillHinge half` or `flat` (`-SillSafeArea T,L,B,R` sets
another; the first guesses, `1000x710` / `710x1000` / `500x710` / `710x500`,
have none), `-SillHinge
closed|half|flat` (the hinge and a 40 pt fold across the middle of the longer
side; without it the harness knows no hinge, even on the Duo's simulator),
`-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillMacMenu
code|blender|long|stale|noaccess|none|slow|timeout|refuse` (the mock Mac's
menus; `code` by default, VS Code's ten), `-SillMenusOpen 1` (the Menus
pull-down opens after launch) or `-SillMenusOpen 'File/Open Recent'` (opens
on that menu, each level fetched on the way), `-SillMenuPress 'File/Save'`
(chooses that item once the menus are in; both live too, but only on the test
app's menus through a test host: `-SillConnect` to a loopback address, no host
version, menufixture's top level; anything else prints "refused"),
`-SillMenusAt <s>` and `-SillMenusCloseAfter <s>` (when the pull-down opens,
and closes after it), and on an iPad `-SillMenuBarLayout perMenu|replace|one`,
`-SillMenuDump 1` (the main menu's root after each build, on the console),
`-SillMenuBuildTwice 1` and `-SillMenuNoView 1` (the insertion's guards),
`-SillSecondWindow 1` (a second window 2 s after launch: the bar then gets
none of the Mac's menus; the console's "menus: …" and "menubar: …" lines say
what happened), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect|wired|noroute` (the mock Mac's settings; it answers a pick
after 0.35 s; the readout's route is Wi-Fi except `directlink` Direct, `wired`
Wired, `noroute` none, and `remote`, `remoteinternet` and `remoteslow` none,
where the route line says how), away from home's and the link's settings cases
`away|awaymixed|awayhome|linkbehind|linkmixed|linklow|linkstalled` (the header's
away line, the footnote, the callout; `linkstalled` shows none) and
`-SillLinkLine behind` (the mock reports the link behind: the stream's line),
the Mac's sound's `-SillSound on|muted` (the mock Mac sends it, Send Audio on:
Mute off or on; the mock plays nothing) and settings cases
`sound|soundoff|soundnote|nosound` (the Send Audio switch on, off, on with the
Mac's note, or a Mac without sound: the switch off and disabled, "Update
Sill…", no Mute; `default` is Send Audio off with Mute), `-SillSettingsScroll
sound|mute` (the panel at the Send Audio row, or at the Mute row under it), and in
the normal app and under `-SillLive 1` `-SillSoundSink manual|device` (manual
rendering, no output device: the simulator's default in every build; `device`
plays through the Mac's speakers, never in a gate) with `-SillSoundVolume 0`,
`-SillSoundToggle <s>[,<s>…]` (Mute flipped at those seconds),
`-SillSoundSwitchAt <s>` (Mute on, then off a second later) and
`-SillSettingsScript`'s `set sendAudio=1|0` (the device's Send Audio switch); the
console's "audio: …" lines say what happened (the format, the engine and its
latencies, a line a second, each jump with its size and cause, and in manual
rendering where each click of a synthetic host's test tone was heard),
`-SillSettingsScript '<t> set K=V[,K=V] | suggestion | disconnect; …'` (a live
session to a synthetic host on loopback: the panel's controls, the link
callout's button and Disconnect, t seconds after the first window list), `-SillMoveHomeTest to:HOST:PORT|refused|
other:PORT` (with `-SillDialSaved 1`: the saved Mac listed as a network row a
second into the remote session at a door that speaks TLS, so the move home
runs against a synthetic `--remote --pairing` host with SILL_TEST_REMOTE_ORIGIN
and SILL_TEST_REMOTE_DIR, dialed pinned to the saved Mac's key), `-SillDialSaved
remotely` (as Connect Remotely: never moves home),
`-SillConnectCase looking|hint|nearby|methods|denied|update|notice` (the connect screen in a discovery
state; `methods` has a row ending in each word, none, and long names; `update` a
Mac's refusal with "Update Sill in the App Store" when `-SillAppStoreURL
https://apps.apple.com/app/id000000000` gives it an address, `notice` a goodbye
reason the device does not know; the mock never browses) and remote access's `remote|addmac|addcode|addcodeerror|
pairing|remotedial|remotefail|camera|externalpair` (`-SillRemoteFailure
vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|
remoteoff` picks remotefail's words), the settings cases `remote|remoteinternet|
remoteslow|remotepair|remoteoff|noremote`, `-SillSettingsEnd 1` (the panel
scrolled to its end), `-SillSettingsScroll gestures` (the panel scrolled to its
This iPad group; the mock Mac takes gestures in every case but `legacy`; `reverse`
to its Reverse Scrolling switch; `hold` to its Hold to Show Window Controls stepper),
`-Sill.trackpadGestures 0` (the device's Three-Finger Gestures off for one run,
in the normal app too), `-Sill.reverseScroll 1` (its Reverse Scrolling on for one
run, in the normal app too), `-Sill.thumbnailHold 0.3` (the thumbnails' hold at 0.3 s
for one run, in the normal app too; the console's `thumbnails: hold 0.3 s` when a bar
first reads it and at each change), `-Sill.largerPicture 1` (its Larger Picture on for one run,
in effect while a window streams, as the mock does but with `-SillActive desktop|none`;
the console's `larger picture: …` line says what the rule made of it;
`-SillVideoSize WxH` the mock's frame, `-SillLargerPictureToggle <s>[,<s>…]` the
switch at those seconds), `-SillVoiceOver 1` (that group as with VoiceOver on:
its footnote says the rows do the gestures), `-SillScanOverlay 1` (Pair This
iPad…'s overlay; `-SillOverlayLine asking|shown|openonmac|locked|noanswer` the
line its ask's answer sets; under `-SillLive 1` it opens over the live session
and asks), pairing at home's connect cases `homerows|homeasking|homecard|homecode|
homecodeerror|homelocked|homeopenonmac|homerevoked|homecabledone|homeolder|
pairingrequired` and settings cases `paired|pairedoff|openpair`, the connect
case `asleep` (issue #69: a saved Mac's row listed, the reconnect's line after
three dials of it that did not connect), `-SillBrowserFail N` (the normal app
and `-SillLive 1`: each of the first N network browsers is reported failed with
-65569, as iOS reports a suspended app's, half a second after it starts, so it
is made again after 1, 2, 4… s; the console's "browser: …" lines, and the
reconnect's "reconnect: …"), `-SillLayerFail <s>[,<s>…]` (the normal app and
`-SillLive 1`: at each of these seconds after the launch's first picture a frame
that cannot decode goes onto the display layer, so the picture's recovery runs
for real, issue #101; the console's "display: …" and "keyframe: …" lines; against
a host with SILL_TEST_STILL_AFTER the picture comes back only through the ask, and
with SILL_TEST_KEYFRAME_IGNORE=<n> the first n asks go unanswered and are made
again), `-SillKeyframeLost <n>` (with `-SillLayerFail`: the first n keyframes
that end a wait are thrown away by the layer's flush, as though it still read
failed, so the picture counts as back and lost again and the next ask waits a
repeat's 4 s),
`-SillPointer mac@X,Y|device@X,Y|hidden|pencil@X,Y` (the pointer sprite in one
of docs/pointer-visibility-plan.md's states over the mock's frame, which it
draws as a dim rectangle; `-SillPencilPointer 1` is Q2's flip),
`-SillClipboardChip 1` and `-SillClipboardNote sent|long|notsent` (the clipboard's
chip and a Paste's note on the mock's stream, docs/clipboard-plan.md; the mock Mac
shares its clipboard in every settings case but `legacy`; live, `-SillSettingsScript
'<t> paste TEXT'` sends TEXT as the Paste control hands it over, and
`-SillSettingsCloseAt <s>` closes the panel `-SillSettings 1` opened),
`-SillMacLocked 1|2|unlocking` (the mock Mac's screen locked, switched to another
user, or just unlocked: no windows, apps or clipboard, the cover over the stream,
the drawer's and the panel header's line, docs/locked-mac-plan.md), and in
the normal app and under `-SillLive 1` `-SillPairURL '<sill://pair…>'` (pair
at launch, no confirmation, at the link's own addresses only: a confirmed link
tries the home rows first, which `-SillTapRow` and `-SillHomeLink` below reach),
`-SillPairCode <12 digits> -SillPairAddress host:port`,
`-SillDialSaved 1`, `-SillForgetMacs 1`, `-Sill.savedMacs '<JSON>'` (one run;
`'[]'` empties), `-SillRemoteRoute vpn|internet` (a loopback session counts as
that route), `-SillHelloVersion <v>` (the version the hello gives, against a
host's floor), `-SillScreenFPS 120` (a 120 Hz screen) and `-SillDeviceKeySE 1`
(a Secure Enclave device key, R0-a); for pairing at home (the normal app and
`-SillLive 1`), `-SillServiceType _silltest._tcp` (the browsers look for the
test type, so a test host registered with SILL_TEST_SERVICE_TYPE is a real
row with its TXT record and no real Mac is; only the Debug build's
Info-Debug.plist declares it), `-SillHomeDoor paired|open|plain` (what a
`-SillConnect` address counts as, since an address has no TXT record:
`plain`, the default, dials it plainly as before; `paired` pins the one saved
Mac, else asks; `open` an open door), `-SillCableTest 1` (this device's path
counts as the cable), `-SillForgetHomeTLS 1` (forget which Macs were seen over
TLS, to dial another branch's older Sill.app plainly), `-SillTapRow <name
prefix>` (tap that row once it is listed), `-SillHomeCode <digits>` and
`-SillHomeLink <sill://pair…>` (the home card's code or scan once the Mac
answers `shown`), `-SillOverlayCode <digits>` (Pair This iPad…'s ask, then
that code, on a TLS session at home) and `-SillNoAutoDesktop 1` (the device
never picks the Desktop by itself: a live gate streams nothing); `xcrun
simctl openurl <udid> 'sill://pair…'` shows the link's confirmation after the
system's "Open in Sill?". `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator), `-SillMoveTest
1|refused|other:PORT|to:HOST:PORT` (with `-SillConnect`: that session counts as
direct and a second later the same address, or its port 1, or its port PORT, or
HOST:PORT, is listed as the Mac's network row, so the move to the network runs
against a synthetic host; `other:` with a second synthetic host on PORT is
another launch, refused at its first window list and not tried again, and with
`-SillConnect` through a delay proxy to the first host's own PORT the fence
waits out the proxy's round trip; `to:` reads HOST:PORT as `-SillConnect` does,
`[::1]:P` too, and this Mac's `fe80::…%en0` address from `127.0.0.1` shows the
panel's route word change at the hand-over; the console's "discovery: …" and
"session: …" lines, `xcrun simctl launch --console-pty`, say what happened),
`-SillWiredTest HOST:PORT` (a wired dial's fallback under test:
`-SillConnect`'s dial, a network row's and a move's go to HOST:PORT first,
`192.0.2.1:9` giving way after 2.5 s and `127.0.0.1:1` at once), `-SillPathTest
'<spec>'` (with `-SillConnect`: the session's Mac listed as a network row whose
cable and Wi-Fi come and go on cue, so the session follows the best path for
real; the spec is ContentView's contract, the console's "path: …" lines say
what happened), `-SillInputScript '<t> <step>; …'` (with `-SillLive 1`: input
with no finger, t seconds after the session's first window list: `down`, `pad
DX,DY`, `lift` and `click` on the portrait pad, `padscroll DX,DY` two fingers
scrolling it with their coast, `tap X,Y` on the stream at a frame fraction,
`drag DX,DY` a finger dragged over it (a scroll, with its coast), `key USAGE` a
hardware key, `type TEXT` the on-screen keyboard's typing (TEXT handed to the input
view as `insertText`), `row USAGE` a key of the portrait
key row, `gesture NAME[,FINGERS]` a three-finger gesture through
`StreamClient.sendGesture`, `esc [MODS]` Esc through the stream's key command
(only while the input view takes Esc), `scroll DX,DY` a connected trackpad's
two-finger scroll with its coast, `wheel DX,DY` a wheel's plain deltas, `keyboard
attach|detach` a hardware keyboard coming or going, `orient landscape|portrait`
the scene turned (an iPhone's); the console's "input script: …" and "pointer: …" lines say what
happened; it runs only when the session was dialled by `-SillConnect` to a
loopback address, `127.0.0.1:P`, `::1:P` or `localhost:P`, and the host's first
window list has no version: Sill.app's always has, and would post the input to
this Mac, so the console says "input script: refused: …" and nothing is sent;
point it only at `--synthetic` hosts; `[::1]:P` works too: the argument domain
drops a launch argument that starts with `[`, and StreamClient.init registers
`-SillConnect`'s, `-SillWiredTest`'s and `-SillPairAddress`'s from the command
line). The first-run tour, in the mock, under `-SillLive 1` and in
the normal app: `-SillTourState fresh|landscape|done|skipped|saved` turns the
automatic tour on (a Debug build never shows it by itself otherwise; `saved`
reads and writes `Sill.tourSeen`, `Sill.tourSkipped` and `Sill.tourVersion`,
an older memory cleared once as a Release build does, the others last one run
and `landscape` the sideways steps; without `saved` no Debug build writes the
version), `-SillTour touch|bar|sharing|settings|laptop` starts it at that step, and the
stand-ins `-SillTourPress next@S|skip@S`, `-SillTourActivityAt S` (the app
run's first session only), `-SillTakeTourAt S` (Settings, then its Take the
Tour) and
`-SillTourVoiceOver 1`; `-SillOrientation landscape|portrait` asks the normal
app's scene for that orientation (a phone simulator sideways with its real
safe areas); the console's "tour: …" lines say what happened, a card's
line gives its frame and tail, and "tour: card …" its rows (how many New) and
what they looked at (TourFeatures). `xcrun simctl launch --console-pty` streams the
console; `--stdout=PATH` writes inside the simulated device's own file system.
A fake screen wider than the
simulator but fitting on its side (1133x744 on an upright iPad Pro 13") is
drawn a quarter turn clockwise; `sips -r 270` the screenshot. One that fits
neither way (the Duo's or an iPad's size on an iPhone simulator) is drawn
scaled down and laid out at its own size ("harness: 710x1000 drawn at 0.62");
a phone's whole stream screen on that phone (440x894 on an 18 Pro Max, 402x812
on an 18 Pro) reaches into the simulator's safe area and runs its trackpad past
its bottom edge: photograph it on a larger simulator, or in the normal app.
`-SillKeyboard 1` raises the software keyboard for real in a live session (the
mock only lights the button), `-SillKeyboardToggle <s>[,<s>…]` toggles it at
those seconds as the Keyboard button does, and in a live session (the normal
app with `-SillConnect`, or `-SillLive 1`) `-SillDrawer 1`, `-SillSettings 1`
and `-SillScaleOpen 1` open theirs 1.5 s after the stream starts
(`-SillDrawerSearch <text>`: the open drawer searches with its field's keyboard
up; the Aa ruler only while a window streams: over a synthetic host's Desktop
Aa is dimmed and the console says the ruler stays closed;
`-SillScaleScript '<s> <scale|off>[; …]'` sets Aa's value at those seconds as
the ruler's release does, whatever streams, so a synthetic host's `[1s]` lines
show `win.fitOff` for a scale then Off). The console
prints `viewport: 386×241 pt, scale off, 60 fps` for each viewport sent, and on
a phone upright `trackpad: …, vertical span …` and, once the keyboard has moved,
`keyboard: up, 301 pt tall, its top at …; the key row ends 10 pt above it`.
`-SillAXDump <s>` lists the stream screen's accessibility elements in the
tree's order (VoiceOver's), on a private simulator once `xcrun simctl spawn
UDID defaults write com.apple.Accessibility ApplicationAccessibilityEnabled
-bool true`.
A hardware keyboard (docs/hardware-keyboard-plan.md): a simulator's GameController
always counts the simulator's own keyboard, so the stream's input view takes the
keyboard by itself there (an empty input view: nothing drawn); `-SillHardwareKeyboard
1|0` says a keyboard is attached or not for the run instead. The console prints
`keyboard: …` for what HardwareKeyboardPolicy does and `hwkey: usage 41 down via
pressesBegan (none): to the Mac` (or `keyCommand`) for every hardware key the input
view sees; `-SillKeyProbe 1` adds GameController's own view of each key,
`-SillEscViaCommand 1` hands Esc on from pressesBegan so its key commands take it,
and `-SillTurnAt <s>[,<s>…]` turns an iPhone's scene mid-session (iPadOS's windowing
refuses). `Tests/keyrig` presses real keys (and holds them, `wait:S`) and turns a
wheel inside the simulator; after its keys UIKit there counts a hardware keyboard,
so a fresh simulator is the one that shows the software keyboard. Each hardware
key's down line ends in who types its characters (`; the Mac types: en-US`, `;
iPadOS types: zh-Hant`: KeyTyping), and the simulator takes another language's
keyboards from `-AppleLanguages '(zh-Hant-TW, en-US)' -AppleLocale zh_TW` (or
ja-JP, ru-RU…), not from its `AppleKeyboards` preference. A test host's Desktop takes input only with
`SILL_TEST_POINTER_PATH` (else it has nowhere to land).
`-SillIdiom pad` draws a screen taller than wide and narrower than 600 pt as
an iPad does (the compact halves) rather than as a phone, so an iPhone
simulator photographs it (`phone` the other way round; the normal app too).
`-SillInputTest 1`, with `-SillConnect` on this Mac's loopback: once, the
portrait key row taps cmd, esc, shift and ctrl through its caps' action, then
the trackpad checks that a touch at its centre lands on it, strokes, taps with
the latched keys held and scrolls, through its own code, and in every layout
the stream's input view sends Esc and ⇧Esc through its key command, a
trackpad's scroll with its coast and a wheel's ("input test: …"); a
synthetic host counts what it gets as `in.dry` and posts nothing, but a real
host (Sill.app, SillHost without `--synthetic`) posts it on this Mac and the
test does not look at which host it reached, so point it only at a synthetic
host, or put a relay in front that reads the device's frames (the 14-byte
header: kind, then the payload's length at bytes 10–13) and drops kind 8
(`sillrelay.py` passes everything).

## Compatibility floor

The first public builds (Sill for iPhone and iPad from the App Store, Sill.app from GitHub) set it
for good. Sill.app changes only when its user downloads a new version (its update check only points
at one), and a device can stay on an old version (automatic updates off, an iOS the next version
dropped). So every later host keeps serving devices from the first public build on, and every later
device keeps working with Macs from the first public build on, or each says why
(docs/update-notice-plan.md):
- Kept as they are: the home door as Sill.app 1.0 ships it, TLS with pairing at home
  (docs/home-pairing-plan.md, branch `home-pairing`; it ships before 1.0, Noah 2026-09-25), not
  the plain-TCP `_sill._tcp` door, which only development builds and the CLI without `--pairing`
  keep; the ALPNs `sill/1` and `sill-pair/1`, which every host offers for good at both doors
  (`RemoteTLS.serverALPNs`: a later generation's `sill/2` only ever goes beside them); the 14-byte
  header; kinds 0–28, 32 and 44 and their payloads (HEVC with ParameterSets; the JSON of Switcher,
  Input, Viewport, HostSettings, Remote, Compatibility, Pointer, MacMenu, Gesture and Clipboard;
  44, a device's keyframe request after its picture was interrupted, empty, which a host from
  before skips; 29 to 31 and 33 to 42 stay free, pull request #66's, and 43 is the Mac's sound's,
  below), inside `sill/1` at both doors (19 and 20 on their own `sill-pair/1` connection, the
  next bullet); the ping echo; a viewport (kind 9) within `ViewportBounds`, each side 1 to
  16384 points and a text scale 0.25 to 4 or none: every device build's is, a host from
  2026-10-29 on refuses any other whole (security scan, finding 4), so a later device keeps
  within them; a
  kind 16 within 2 s of the first window list, one per connection since Sill for Mac 0.5.1 (away
  from home, docs/remote-bundle-plan.md §4): its `settings` the pair that connection's controls
  set (the away quality for a device away), and its optional `away` (AwayQuality, from a host with
  an identity: Sill.app, SillHost --remote or --pairing) and `link` (LinkReport, only while a link
  does not keep up; its `state` a string,
  which a device reads as keeping up when it does not know it); kind 22's `reason`, `message` and
  `reconnect`; the
  Mac's menus as MacMenu.swift has them (docs/menu-bar-plan.md §3):
  a kind 27 without an id is the device's subscription, and only a subscriber is served (another
  connection's fetches and choices are answered "The menus changed…", nothing read or pressed); an
  id is a path of child indexes that names one item for every device within one version, and a
  request of another version is answered with that note and never acted on; a fetch and a choice
  carry the title the device showed, and the host reads or presses only while the item there still
  has it; a device's tokens come back in `answering`; the fields as they are (MacMenu's `version`,
  `app`, `bundleID`, `menus`, `answering`, `menu`, `items`, `more`, `pressed`, `stale`, `note`;
  MacMenuItem's `id`, `title`, `separator`, `enabled`, `mark`, `key`, `submenu`; FetchMenu's and
  PressMenuItem's `version`, `id`, `title`, `token`); a trackpad gesture (kind 28, Gesture.swift)
  goes only to a host whose window list says `gestures` 1 or more, as one of its six names with
  `fingers`, and a later generation of gestures says 2 and goes only to a host that says so; the
  clipboard (kind 32, Clipboard.swift, docs/clipboard-plan.md) goes from a device only to a host
  whose window list says `clipboard` 1 or more (an Int: 1 is text, a later generation with images
  says 2), and from a host only to a connection that sent a kind 32 and no `stop` since: any kind
  32 subscribes, `{"stop":true}` ends it, `text` (at most 256 KB, the JSON at most 1 MiB) becomes
  the receiver's clipboard, `image` is reserved for that later generation; a subscription says what
  the device takes, `{}` being text alone, so a host sends `image` only to a connection whose
  subscription carries a later field saying it takes images (`"accepts":2`, say), never to one that
  sent `{}`; a hardware keyboard's characters (letters, digits, Space, Delete…) go to a host as keys
  only when its window list says `keyRepeat` 1 or more (it repeats a key held between its down and its
  up, #162), to any other through iPadOS's text system as they always did; a locked Mac's window list
  (docs/locked-mac-plan.md): `locked` true with no windows and no `clipboard` while the Mac is locked or
  another user, the login window or nobody is on its console, and `offConsole` true in that second case,
  both left out otherwise, so an unlocked list is what it was; a device that knows them says why the list
  is empty, and while locked a host sends no picture of the Mac (a placeholder frame at most), which also
  replaces the last picture of a device from before them, but off console with its user's switch on (Show this
  account while another user is on the screen, docs/off-console-plan.md), when it streams this session's own desktop
  and windows to every device and sends a device whose hello says `offConsoleView` 1 the list with its windows and
  `offConsoleView` true (every other device the locked list: a later host keeps both keys' meanings); the Mac's sound (kind 43, Audio.swift), once a public build ships it, a beta or not:
  its two types (a JSON AudioFormat, then packets whose layout never changes: a new layout is a new
  type), AudioFormat's fields, the hello's `audio`, `sendAudio` and `audioNote`, kind 43 only to a
  device whose hello lists a codec the host makes, and the reader's caps, which a later host keeps
  within (a device drops a message past them whole): a format at most 4 KB, a packets message at
  most 16 KB (`AudioMessage.parse`), so a host that batches packets never puts more than 16 KB in
  one message.
- Pairing as 1.0 does it (docs/home-pairing-plan.md §3): the Bonjour TXT keys `r` (the recognition
  tag) and `p` ("1" pairing required, "0" open, no `p` a plain door, any other value read as "1");
  a `sill-pair/1` connection is exactly one kind 19, with no hello (the device gate judges sessions
  only), and one kind 20, then the Mac closes it; kind 19's methods `qr`, `code` and, at the home
  door, `ask` and `cancel` (the remote door answers both `closed`), at `v` 1: a host answers any other `v`
  `closed` without counting a try, so a later method or proof format comes with a later `v`, never
  as a new method at 1, which a 1.0 host counts as a wrong code; kind 20's reasons `code`,
  `closed`, `expired`, `stopped`, `busy` and, after an ask, `shown`, `openOnMac` and `locked`, with
  their meanings (`PairResult.knownReasons`: a later reason comes with its `message`, which 1.0
  devices show as it is); an ok without a proof only as `method` "cable", to an ask that claimed
  the cable; and pairing is never refused for the device's age.
- Additive only (HostSettings.swift's rules): new fields optional, never renamed or retyped; kind
  numbers never reused; no new case in an enum an older peer decodes. `StreamSource` keeps its
  three cases (a new source goes in an optional field, with `active` still one of the three). A new
  `InputEvent` case, scroll phase or window command goes only to a host that said it takes it (a
  kind or a field only newer hosts send), and a gesture ends with a scroll phase the first build
  knows.
- A device is refused, never served wrong. A host that can no longer serve older devices raises
  `DeviceGate.minimumDeviceVersion` ("0" today) by the plan's §4.6, and they get kind 22 "update"
  before anything else. A device from 2026-09-25 on that receives it shows the host's message word
  for word, with its App Store link, and does not reconnect; older development builds cannot. At
  the TLS home door only devices from home pairing on receive it (Decided, below). Kind 22 reaches
  a 1.0 device only inside a `sill/1` session, so such a host still completes that device's
  `sill/1` handshake and reads its hello through the gate before refusing it: a host that stopped
  offering `sill/1` would leave it a failed handshake (-9838), "disconnected" and a redial every
  few seconds, for ever.
- Every device says hello first (kind 23: its version, build, protocol and name), and every host's
  window list gives its version and protocol (`hostVersion`, nil from SillHost and from Macs
  before 2026-09-25). A later device facing an older Mac tells what it lacks from these and from
  which kinds and fields arrive, and says "Update Sill on ‹Mac›", as the Settings panel already
  does for a Mac without kind 16.
- `SillProtocol.current` (1) rises only with a change an older peer cannot skip, and the floor
  rises with it.
- Decided (Noah, 2026-09-25; the plan's open question 14): home pairing ships before 1.0, so the
  floor is the TLS home door with pairing, and no 1.0 device speaks plain TCP to Sill.app.
  Settled at the merge of main into `home-pairing` (2026-09-27, d11aa60; home pairing landed
  second): the hello goes first inside TLS at both doors, and the device gate runs in `Door`, once
  the key is admitted, one place for both TLS doors (`StreamServer.gate`; the CLI's plain door
  without `--pairing` runs it at `.ready`); what changed while it held a session (the key removed,
  Require pairing on, Remote Access or internet access off, the session limit, Direct Wireless
  off) is judged again by `DoorPolicy.afterGate`, with the goodbye and the line that change's own
  close gives. 1.0's TLS home door is `SillProtocol` 1 with ALPN `sill/1`, as the remote door is:
  pairing on the home door is part of protocol 1, no longer an example of what raises it
  (Compatibility.swift, docs/update-notice-plan.md §3.2 and §4.6), and a later generation raises
  both: `sill/2` is offered beside `sill/1` and `sill-pair/1`, never instead of them (the first
  bullet). Builds from before home
  pairing dial plain TCP and say hello in plaintext: at the TLS door they get a failed handshake
  and EOF, never kind 22 "update", and redial. Only development and TestFlight builds are that
  old, so no plaintext path or sniffer answers them.

## Conventions

- Swift, Apple frameworks only. No third-party dependencies unless a decision
  in `docs/BRIEF.md` says so. Zero operating costs is a hard rule.
- Threading in the spike is by hand: capture queue → VT callback thread →
  network queue. Keep it explicit and commented rather than reaching for actors
  until the design settles.
- HEVC, no B-frames, real-time mode. AV1 is out (no hardware encode on Apple
  silicon as far as we know).
- Latency beats quality. Drop frames before queuing them.
- Don't add features the current milestone doesn't need.

## Decisions already made (don't relitigate without asking Noah)

- Free app, tip jar, open source. Not paid, not subscription.
- iCloud auto-pairing (same Apple Account, Mac just appears) for milestone 5.
  Bonjour only for the spike.
- Native feel is the bar: Flighty-level polish, iOS conventions, Duo layouts.
- License: Apache-2.0, LICENSE since PR #15, kept when the repository went
  public on 2026-09-26 (paid plan is gone, so no GPL/CLA needed).
- v1 out of scope: hole punching, multi-window, layout customization. Audio is in scope since
  2026-09-27 (Noah: "Audio: the plan is done and parked as a v2 feature by your earlier decision",
  first in what he wanted worked on; docs/audio-plan.md, docs/BRIEF.md), and in, as a beta, since
  2026-10-20 (Noah, about PR #94: "merge as beta support"): Send Audio, off by default. Since
  2026-10-27 (Noah: "Sound should be a toggle in the settings menu") the Mac's menu and Settings and
  a device's Settings panel set it for every device, and each device's Mute is its own; no Sound
  button in the bar.
