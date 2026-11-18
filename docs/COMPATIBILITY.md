# Compatibility floor

What every later host and device keeps: CLAUDE.md's "Compatibility floor" until 2026-11-18,
moved here word for word. CLAUDE.md keeps its headline rules, in short.

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
