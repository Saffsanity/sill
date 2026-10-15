# Clipboard sharing between the Mac and the device (issue #64): the plan

Branch `clipboard` from main at 985a733, worktree `/Users/noah/Downloads/winstream-clipboard`.
Issue #64 asks for the clipboard both ways. The triage of 2026-10-13
(`~/Downloads/sill-handoff/triage/2026-10-13-open-items.md`, Enhancements) recommends it next, text
first, with two decisions for Noah: whether it is on by default, and a switch on the Mac. The open
pull request #66 (a Mac client) carries a clipboard of its own on kind 32 with the shape `{text,
image}`; this change takes the same number and shape so that #66 can rebase onto it, and writes its
own code (#66's host sends password managers' copies and gives the Mac's owner no switch).

## The problem

- Mac to device: nothing. Text copied on the Mac cannot be pasted on the iPhone or iPad unless both
  are signed in to the same Apple Account with Handoff on and close together (Universal
  Clipboard), which does not reach a device on another account, nor one away from home through
  Tailscale.
- Device to Mac: only typing. A paste into the stream's keyboard goes to the Mac as one text event,
  which the host types a character at a time (`InputInjector.swift`, the `.text` case): slow for
  long text, and the Mac's clipboard never holds it, so it cannot be pasted twice or into another
  app.
- iOS 16 and later ask "Allow Paste?" whenever an app reads the pasteboard on its own. Reading
  `UIPasteboard.general.changeCount` and `hasStrings` does not ask; a read through the system's
  Paste control (`UIPasteControl`, SwiftUI's `PasteButton`) does not ask either, because the tap is
  the person's consent.

## The design

### Wire (StreamProtocol, additive)

- **Kind 32 `clipboard`, both ways, JSON `Clipboard`** (`Sources/StreamProtocol/Clipboard.swift`):
  `text: String?`, `image: Data?` (reserved for a later generation; #66 sends PNG or JPEG there, a
  host of this generation ignores it and a device sends none), and `stop: Bool?` (device to host:
  this device's Share Clipboard went off, send it nothing more). Every field optional and left out
  when nil.
- **`WindowList.clipboard: Int?`**: 1 when the host takes and sends text (`ClipboardPolicy.generation`);
  nil from every host before this change, and from a host whose Share clipboard with devices is off.
  A device sends kind 32 only to a host whose list says 1 or more. A later generation (images) says
  2, and a device sends images only to a host that says so. An older device never subscribes, so it
  is never sent a kind 32; an older host skips the kind (`.unknown`).
- **Caps** (`Clipboard.maxTextBytes`, `ClipboardPolicy.maxPayload`): text at most 256 KB of UTF-8
  (262,144 bytes) either way, and the whole JSON at most 1 MiB either way: the host closes a device's
  message over 1 MiB (`StreamMessage.maxClientPayload`), and a device a host's over 4 MiB
  (`maxOtherHostPayload`), so the smaller cap serves both directions. Swift's JSON escapes a control
  character as six bytes, so 256 KB of text can exceed 1 MiB as JSON; such text is not sent.
- Kinds 29, 30 and 31 stay free: 29 is the audio plan's (docs/audio-plan.md on the `audio-plan`
  branch), 30 and 31 #66's side streams.
- **What a subscription takes.** `{}` is text alone: a host sends `image` only to a connection whose
  subscription carries a later field saying it takes images (`"accepts":2`, the generation, say),
  never to one that subscribed with `{}`, which drops it (the review's finding: #66's host sends an
  image to every subscriber, which every iPhone and iPad of this generation would drop, after carrying
  up to about 3.5 MB of base64 over a 4 Mbps away link). The compatibility floor says so.
- **#66 and this shape.** Same number, same `text` and `image`. #66's list key is `clipboard: Bool?`
  (`true`), which a decoder of `Int?` refuses (and the whole window list with it), so #66 changes it to
  `Int?` when it rebases; no build with #66's Bool was ever released. #66's host reads a kind 32 with
  neither text nor image as a subscription, as this one does; `stop` is new, and #66's viewer, which
  never sends it, keeps working.

### Rules (pure: `Sources/StreamProtocol/ClipboardPolicy.swift`, checked by `Tests/checks/clipboard`)

One file for both ends, in StreamProtocol because both compile it (the host as SillHostCore's
dependency, the device through the local package).

- **What a device's kind 32 means to the host** (`fromDevice`): `stop: true` stops; text (not
  empty, at most 256 KB) is set on the Mac's clipboard and subscribes; neither text nor `stop` (an
  image alone included) subscribes; empty text subscribes and sets nothing; text over the cap is
  refused (and subscribes nothing); JSON that does not decode is ignored.
- **Whether the host sends a change of its pasteboard** (`hostLooks`, then `hostSends`): never an item
  marked by a password manager or another app as concealed or transient: `org.nspasteboard.ConcealedType`
  and `org.nspasteboard.TransientType` (nspasteboard.org's conventions, which 1Password, Bitwarden,
  KeePassXC and Strongbox use for passwords and one-time codes), and the three older markers clipboard
  managers also skip (`org.nspasteboard.AutoGeneratedType`, `de.petermaurer.TransientPasteboardType`,
  `com.agilebits.onepassword`); never what came from another of the person's devices through
  Universal Clipboard (`com.apple.is-remote-clipboard`: reading it would fetch it from that device,
  and macOS shows that it is pasting from it, for every copy made there; those devices have it
  already); never what this host wrote itself (its change count, or its own marker
  `me.saffer.sill.clipboard` naming its launch); only a change with text, not empty, at most 256 KB,
  whose JSON fits. A marker's types are read before any data, so neither a password manager's text
  nor another device's is ever read.
- **The rate** (`hostReceives`, after the review): what a device's message asks is decided first; a
  subscription or text is taken at most 4 times in any second (`admits`), the rest refused (`rate`); a
  stop is always taken and counts nothing, nor does a refusal (`countsAgainstRate`).
- **macOS's paste privacy** (`MacAccess`, `hostLooks`, `accessStep`, `accessLine`, after the review):
  NSPasteboard's `accessBehavior` (macOS 15.4 and later) read as allowed, not asked yet, asks or denied
  (a value this build does not know as asks); the host reads its pasteboard only while macOS allows
  every read, and what was copied while it did not is never sent.
- **Who a device's text goes to**: every subscriber but its sender (`forward`).
- **The device's subscription** (`deviceSubscription`): subscribe while the Mac says 1 or more, the
  switch is on and this connection has not; stop when it has and the switch is off; nothing otherwise.
  A connection forgets its subscription when the Mac stops saying it (Share clipboard with devices
  turned off), so it subscribes again when the Mac says it again.
- **Whether the device writes the Mac's text** (`deviceWrites`): only with the switch on, from a Mac that
  says 1 or more, text not empty and within the cap, and not the text this device sent while its
  clipboard still holds it (its change count unchanged since the send: the Mac's echo, which a host of
  this change never sends, but a later one could).
- **A Paste's receipt** (`receiptLength`, `receiptWait`, after the review): "Sent" only once a ping sent
  after the text comes back, its payload 16 random bytes; none within max(4 s, 4 × the worst round trip),
  "Didn’t reach ‹Mac›. Try Paste again." and the copy not dealt with.
- **The chip's time** (`chipCounts`, after the review): its 20 s run only while it is on screen, Sill is
  active and VoiceOver is off.
- **The chip** (`offersChip`): connected, the Mac says 1 or more, the switch on, the device's clipboard
  has text (`hasStrings`), and its change count is not the one Sill last handled (sent, wrote from the
  Mac, or dismissed). When Sill becomes active, or when a session's first list says 1 or more within
  15 s after Sill became active (`looksAtSessionStart`: an app switch long enough for the Mac to evict
  the suspended device brings a reconnect first). Shown for 20 s at most (`chipLifetime`).
- **The words** (`Copy`): the chip's title, subtitle and spoken label, the confirmation, the too-long
  line, the Settings group's switch, row and footnotes, and the host's two log lines.

### Host (`Sources/SillHost/HostClipboard.swift`, main actor)

- **Setting.** `HostConfig.shareClipboard`, on in `standard`. Sill.app: Settings › General, "Share
  clipboard with devices", saved as `shareClipboard` like the other settings (`HostSettings`), with a
  one-line footnote. The CLI: on, as the app; `--no-clipboard` turns it off for the run. The Mac's
  alone, like Remote Access: absent from `StreamSettings`, `HostSettingsChange`,
  `DeviceSettings.accepted`, `applying` and `restartNeeded`. `setTarget` applies it at once, not between
  pipelines (a privacy switch must not wait for a restart): off drops every subscription and stops
  the look, and either way the window lists go out again with `clipboard` set or left out.
- **Subscribing.** Any kind 32 from a device subscribes it (an empty one is what a device sends at
  connect when its switch is on); `stop` unsubscribes. One line each, never per copy:
  "Clipboard: iPad (iPad14,1) shares the clipboard." and "Clipboard: iPad (iPad14,1) stopped sharing
  the clipboard." A device that leaves is forgotten without a line. With the setting off, a kind 32
  is ignored without a word or an answer.
- **The look.** While at least one device subscribes, `NSPasteboard.general.changeCount` four times a
  second on the main actor (a `Task.sleep` loop: the CLI's `dispatchMain` never runs `RunLoop.main`
  timers). The first subscriber's arrival takes the count as it stands: what was on the clipboard
  then is never sent, only what is copied while a device shares it. A change the rules take goes to
  every subscriber as `{"text": …}`.
- **A device's text.** `prepareForNewContents(with: .currentHostOnly)` (so Universal Clipboard does
  not carry it to the person's other devices, the device included), one item with the text and the
  marker, the change count kept, and the text forwarded to every other subscriber.
- **Limits.** At most 4 subscriptions and texts a second per connection (a tap sends one); the rest,
  and text over the cap, ignored with one line a minute (`RefusalSummary`). A stop is never limited. Contents are never logged. Stats keys
  `clip.sent` (messages sent) and `clip.recv` (texts taken), only in seconds they happen.
- **macOS's paste privacy** (after the review). The look reads NSPasteboard.general only while
  `MacClipboard.access()` says macOS allows every read (`accessBehavior` `.alwaysAllow`, or a macOS
  before 15.4); otherwise it reads nothing, not even the change count, and when reads are allowed again
  the count is taken as seen. One line when macOS's answer changes ("Clipboard: macOS asks before Sill
  reads the clipboard, so what is copied on this Mac stays here. …"). A device's text is still written
  (the count from `prepareForNewContents`). Settings › General (`ClipboardSection`): under the switch,
  while macOS asks or denies, the reason, what to do and "Allow in System Settings…", which opens
  Privacy & Security › Paste from Other Apps (`Privacy_Pasteboard`); while macOS has not asked about
  Sill yet, Sill is not listed there (NSPasteboard.h), so the button first makes one read on that click
  (`MacClipboard.askOnce`, off the main thread, the text dropped) for macOS to ask. `PermissionsModel`
  reads the state with the permissions.
- **Test hosts.** A synthetic host never reads or writes this Mac's clipboard, as it never reads the
  real pointer: it uses a pasteboard of its own, `me.saffer.sill.test.<pid>`, or the one
  `SILL_TEST_PASTEBOARD=<name>` names (TEST ONLY), said once at its first subscription.
  `SILL_TEST_CLIPBOARD_LOG=1` (TEST ONLY) prints each decision with the text's size, never the text.
  `SILL_TEST_CLIPBOARD_ACCESS` (TEST ONLY) gives its pasteboard macOS's answer: a word, or a file
  holding one, read at each look.

### Device

- **Settings panel, This iPad group** (first, before the gestures): "Share Clipboard"
  (`Sill.shareClipboard`, on by default, stored on the device), shown only while the Mac says 1 or
  more; under it, while on, the row "Paste on ‹Mac›" with the system Paste button; a footnote.
- **Mac to device.** A kind 32's text is written to `UIPasteboard.general` with `.localOnly` (Universal
  Clipboard does not carry it back to the Mac) and a 10-minute expiration; its change count becomes
  the handled one, so the chip never offers the Mac's own text back.
- **Device to Mac.** Sill never reads the pasteboard by itself. The chip "Paste on ‹Mac›" (subtitle:
  then press ⌘V there) with the system Paste button and a dismiss button appears near the bar: under
  the bar at the stream panel's top trailing corner sideways (its bottom corner while the link's line
  shows at the top), at the picture's bottom trailing corner, just above the window bar or row 1, held
  upright. It hides while the Settings panel, the Apps list, the pairing overlay, the tour, a
  thumbnail's lights or the Aa ruler is open; its 20 s run only while it shows with Sill active, and
  not at all under VoiceOver; VoiceOver is told when it first shows ("Paste on ‹Mac› is available,
  near the bar.").
  A tap on Paste sends the text as kind 32, then a ping with a random 16-byte payload through the same
  door; its pong (the receipt) shows "Sent to ‹Mac›’s clipboard. Press ⌘V there." for 3 s (spoken by
  VoiceOver) and counts the copy as dealt with; no receipt within max(4 s, 4 × the worst round trip)
  shows "Didn’t reach ‹Mac›. Try Paste again." and offers the chip again. Text over 256 KB is not sent
  ("Too long to send…"). The same Paste is in the Settings group whenever it shows.
- **Subscription.** An empty kind 32 at the session's first window list that says 1 or more (and on a
  move's new connection), with the switch on; `{"stop": true}` when the switch goes off.
- `-SillClipboardChip 1` and `-SillClipboardNote sent|long|notsent` (DEBUG) put the chip and the note
  on the harness's mock; the mock Mac says `clipboard` 1 in every settings case but `legacy`.
  `-SillSettingsScript '<t> paste TEXT'` sends TEXT as the Paste control hands it over, and
  `-SillSettingsCloseAt <s>` closes the panel `-SillSettings 1` opened (live, DEBUG).

## Open questions, with the default taken

1. **On by default?** On, on the Mac and on the device (the task). Both have a switch, and the
   privacy policy says what travels. The review's note, for Noah: with both on, a device that updates
   subscribes at connect, so every Mac copy made while it is connected (an app's own included, such
   as a terminal that copies on select) replaces what was on the device's clipboard (a photo, say),
   and that text expires 10 minutes later, leaving the device's clipboard empty, for people who never
   use the feature. A longer or no expiry, or off by default on the device, is one line each
   (`ClipboardPolicy.deviceExpiry`, `StreamClient.clipboardOn`).
2. **What a new subscriber gets.** Nothing that was on the clipboard before; only copies made while
   a device shares it. Connecting never sends an old copy (a password from an hour ago).
3. **The device's switch off mid-session.** `stop`, an optional field beyond `{text, image}`: without it
   the Mac's copies would still travel to a device that only drops them.
4. **Which markers.** The two the task names, plus the three older ones clipboard managers skip.
5. **⌘V.** Not sent for the person: the text goes to the Mac's clipboard and they paste where they
   want (a paste sent with it could land in the wrong window).
6. **Universal Clipboard.** Both of Sill's writes are local (`.currentHostOnly`, `.localOnly`), so neither
   bounces. What reaches the Mac through Universal Clipboard is not sent on (found while building:
   reading it would fetch it from the other device for every copy made there). A Mac copy that also
   reaches the iPad through Universal Clipboard can bring the chip once (the device cannot read its
   own clipboard to compare without asking): known, for Noah.
7. **Text over 256 KB.** A Mac copy stays on the Mac, silently (one TEST ONLY line); the device says
   "too long" when Paste is tapped.
8. **The chip's lifetime.** 20 s, the dismiss button or a tap; each counts as handled for that change
   count, which is kept across launches (`Sill.clipboardHandled`), so a relaunch does not offer old
   text again.
9. **Split View and windows beside Sill.** Copying in an app beside Sill does not make Sill become
   active, so the chip waits for Sill's next activation; the Settings group's Paste works any time.
10. **Who can subscribe.** Any device the doors admit: the devices that can already see the Mac's
    screen and type on it. With Require pairing off that is anyone on the network with Sill; the
    privacy page already says so for the screen.
11. **Rich text, images, files.** Text only (generation 1). Rich text copies send their plain text.
12. **macOS's paste privacy** (after the review). The default: read only while macOS allows every read,
    never in the background while it asks (its alert at every copy) or denies; Settings › General says
    why and opens Paste from Other Apps, asking once first while macOS has not asked about Sill. The
    device is not told (no wire change): its footnote still says the Mac's copies are ready while the
    Mac keeps them. A later field in the window list could say so.
13. **The receipt** (after the review). A ping after the text, no wire change and no answer from the
    host: it says the Mac read the text, not that the pasteboard took it (a Mac whose Share clipboard
    with devices went off in that moment, or past the rate, which a tap never reaches).
14. **The chip under VoiceOver** (after the review). No time limit while VoiceOver is on (it stays until
    Paste or Dismiss); hidden, it waits.
15. **The site's words before the release** (after the review). Kept with this pull request, as the other
    features' are, between `<!-- Clipboard` markers that a republish before the release cuts
    (docs/release-checklist.md, part 1 §3); the README describes main's code, as #39's did.

## Test plan

- **C1** `Tests/checks/clipboard`: the rules above, case by case and against small models, with mutants
  (each must be caught), in CI's mutants matrix.
- **C2** `protocol`, `compatibility` and `pointer-control` read kind 32 (the kind table, the window list's
  `clipboard`, its JSON both ways, an older list), with their mutants; `away-quality` takes
  `shareClipboard` in `standard` and `changes(to:)`.
- **H1** `swift build -c release`; the iOS app Debug and Release for the generic simulator and Debug for
  a generic device (`CODE_SIGNING_ALLOWED=NO`): only the known warnings.
- **H2** The CLI against origin/main, both from `git archive`, `--synthetic`, idle 35 s and a client
  picking the Desktop, masked and sorted: identical; a client that never subscribes adds no line.
- **H3** Live on loopback (`SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1`,
  `SILL_TEST_PASTEBOARD`, a scratch probe writing and reading that pasteboard): a subscriber gets a
  copy; a concealed one and a transient one are not sent; `--copy` sets the host's pasteboard (read
  back) and is not echoed; two clients each get the other's copy; `--no-clipboard`: no `clipboard` in
  the list, a subscription and a copy ignored; `stop`; the rate cap; oversize text.
- **S1** A private simulator against the same host: photos of the This iPad group (on, off, with the
  note) and of the chip in each layout; the device's switch; the Mac's text arriving (`simctl pbpaste`);
  the chip after a copy in the simulator (`simctl pbcopy`, then Sill leaving and coming back); Paste on
  the Mac through the chip by a real tap, the host's pasteboard read back; VoiceOver's labels.

## Results

What differs from the plan above, each found while building or testing:
- The host also skips what came from another device through Universal Clipboard
  (`com.apple.is-remote-clipboard`): reading such an item fetches it from that device (macOS shows it
  pasting from there), for every copy made on the iPhone.
- An empty pasteboard waits for its contents (`ClipboardPolicy.hostWaits`, up to a second): an app
  that copies clears the pasteboard, which moves the change count, and then writes, which does not;
  a look between the two took the count as dealt with and the copy was never sent. Found live (a
  test copy lost, the bare app's run); a probe writing 50 to 550 ms after its clear lost 9 of 12
  copies against the build before and none against this one (12 of 12). A copy written more than a
  second after its clear is still lost (none seen).
- The pasteboard is read and written on a queue of its own (`HostClipboard.Board`), one call at a
  time and in order, not on the main actor, where devices' input is handled: a read of text an app
  only promised waits on that app.
- The device looks once when the app and its scene become active together (both notifications
  came).

- **C1** `Tests/checks/clipboard`: 197 checks, among them two random models (the device's
  subscription against a host's view of it, 5,000 sessions; a host with three devices against what
  each must receive, 2,000 runs, plain copies, the five markers, Universal Clipboard's, the host's own
  writes with and without its recorded count, an app that clears, is looked at and then writes), and
  its mutants, every one caught (the count is in Progress); in CI's mutants matrix.
- **C2** `protocol` 192 checks (+ the 8 cross-checks) and 24 of 24 mutants (a renumbered clipboard
  among them); `compatibility` 102 and 22 of 22 (WindowList's new parameter in two patterns, three new
  mutants); `pointer-control` 157 and 33 of 33 (32 in its kind table); `away-quality` 71 and 19 of 19
  (`shareClipboard` in `standard`, its log words, never moved by a device's change, a HostConfig made
  with it off).
- **H1** `swift build -c release`: only the CaptureProbe warning. The iOS app, Debug and Release for
  the generic simulator and Debug for a generic device (`CODE_SIGNING_ALLOWED=NO`): BUILD SUCCEEDED,
  only the StreamClient capture warning (StreamClient.swift:3456, main's 3430, the same code).
- **H2** origin/main's CLI and this branch's, both from `git archive`, `--synthetic` on loopback with
  the software encoder: idle 35 s side by side identical masked and sorted (7 lines; a first pair run
  one after the other differed by one 30 s heartbeat, which timing gives either); a client picking
  the Desktop for 15 s that never subscribes: every line identical in order but the `[1s]` stats lines,
  whose counters vary between runs of either build, and no line about the clipboard.
- **H3** live on loopback (`SILL_TEST_PASTEBOARD`, a probe writing and reading that pasteboard with
  `NSPasteboard(name:)`), against the final build (and the slow-copy probe above): a subscriber gets a Mac copy, and not what was on the
  clipboard before it subscribed; a ConcealedType, TransientType, AutoGeneratedType, 1Password and old
  transient copy, an image, 300 KB, empty text and a Universal Clipboard copy are none sent
  ("marked" ×5, noText, tooLong, empty, remote); a device's text with a newline and a ✓ sets the
  pasteboard (31 bytes, the marker naming the launch, read back) and is not echoed; two devices each
  get the other's text and a Mac copy, never their own; `stop` ("stopped sharing"), then a copy does
  not arrive; ten kind 32 at once, four taken ("1 from devices sending more than 4 a second" at once,
  the rest a minute later); 262,145 bytes refused, 262,144 taken; JSON that does not decode ignored;
  `clip.recv` 4 and `clip.sent` 5 in all, as sent. `--no-clipboard`: no `clipboard` in the list, a
  subscription and a copy ignored, the pasteboard unchanged, no line. The bare app (a renamed copy,
  so its defaults domain was its own, deleted after; `-requirePairing NO`, a TLS client with `--pin=none`):
  `-SillSetAfter '5 shareClipboard=0; 9 shareClipboard=1'` gave "Settings: share clipboard on → off"
  and "off → on", the list without and with `clipboard`, the copy made while off never looked at, a
  new subscription and a copy after, and `shareClipboard` saved.
- **S1** a private iPad Pro 13-inch simulator (iOS 27.0; 27.1 has no iPad), deleted after. Run again
  against the final host: the Mac's text on the device, the chip, Paste through XCUITest's tap. Harness photos
  of the chip sideways, upright, on the cover both ways, in the book and laptop poses, beside the link's
  line, at accessibility XL, in the phone's arrangement (`-SillIdiom phone`), the notes, and the
  Settings group on, off, with the note, legacy and at accessibility XL; seven screens that should not
  change (sideways, upright, the cover both ways, the drawer, the Settings panel's top, the legacy
  group) pixel for pixel main's build. Live against the synthetic host (`-SillConnect`,
  `-SillNoAutoDesktop 1`, nothing streamed): "Clipboard: Sill clipboard iPad (iPad17,4 simulator)
  shares the clipboard."; a Mac copy read back on the device (`simctl pbpaste`: "Mac copy for the iPad
  ✓"); a copy on the device (`simctl pbcopy`), Sill sent home and back by XCUITest (a scratch UI test
  project): "the chip"; XCUITest's real tap on the chip's Paste (UIPasteControl) set the host's
  pasteboard to the 41-byte text with the marker, and the note "Sent to …"; Dismiss, then home and
  back: no chip for that copy; the device's switch off from the panel by XCUITest: "stopped sharing",
  a Mac copy not written, the Paste row gone and the off footnote; on again: "shares", copies arrive.
  VoiceOver, from the accessibility tree: the chip's words one static text ("Paste on ‹Mac›. Sends
  the text you copied on this iPad to ‹Mac›’s clipboard. Then press Command-V there."), the
  system's button "Paste", "Dismiss", the switch "Share Clipboard". Two findings there, fixed: the
  harness's mock offered the chip from the simulator's own clipboard (now only by
  `-SillClipboardChip 1`), and the chip's words lacked the static text trait. `simctl pbcopy` reads
  stdin as Mac Roman without a UTF-8 locale (a ✓ became "‚úì" before Sill saw it): the tool's, not
  Sill's.
- This Mac's own clipboard was never read or written: every test used named pasteboards, the
  simulator's pasteboard (no Simulator.app running, so nothing synced), and a read of
  `NSPasteboard.general.changeCount` alone before and after (317 throughout).

### The review (2026-10-14) and what changed

An adversarial review of 7e6468a reran the gates (all held) and found eight things; each was checked
against the code first, and all eight were taken, one commit per theme:

1. **A stop lost to the rate (should-fix; c2d7b6a).** HostClipboard applied the 4-a-second rate to
   every kind 32 before reading it, so a `{"stop":true}` that was the fifth in a second was refused
   and the device stayed subscribed. Reproduced on loopback against 7e6468a: subscribe, then stop,
   `{}`, stop, `{}`, stop at 2.0 to 2.4 s: "1 from devices sending more than 4 a second", and a Mac copy
   at 5 s reached the client ("clipboard at 5.180s: 32 bytes 'copied after the switch went off'").
   Now `hostReceives` decides first and rates only subscriptions and texts: the same run gives a third
   "stopped sharing" and nothing at 5 s; five texts in a second still set four (the pasteboard holds the
   fourth, one ignored line), and a stop right after them is taken. Check: the sequence, the rate's
   edges and model 1b (5,000 quick sessions through `hostReceives`: never subscribed at the host while
   the device's switch is off); five mutants, the review's ordering among them.
2. **macOS's paste privacy (should-fix; 210ba4b).** Sill.app read NSPasteboard.general at every copy
   and never looked at `accessBehavior`; NSPasteboard.h (the macOS 27 SDK) says the general pasteboard
   asks at each programmatic read by default once that is on (`.default`, then `.ask`), lists an app
   in Privacy & Security › Paste from Other Apps only after its first alert, and returns nothing while
   denied. Now the look reads only while macOS allows every read (`MacAccess`, `hostLooks`; before macOS
   15.4 there is no such setting), reads nothing otherwise, and takes the count as seen when reads come
   back (`accessStep`); one line when the answer changes (`accessLine`). Settings › General's
   `ClipboardSection`: an orange line, what to do, and "Allow in System Settings…", which opens
   `Privacy_Pasteboard` and, while macOS has not asked about Sill, first makes one read on that click
   so that macOS asks and lists it. On this Mac (macOS 27.0.1) apps read `.alwaysAllow` (the review read
   2 from an ad hoc app), so nothing changes today. Live on loopback with TEST ONLY
   `SILL_TEST_CLIPBOARD_ACCESS` read from a file: denied, then asks, then allowed, then not asked, each
   with its line; the copies made while denied and while asked never went, the one made after reads came
   back went at 9.03 s, and a device's text was written while not asked. Previews of the section in
   each state (`pane-clipboard-*`). Check: the mapping, the steps, the lines, the words, and model 2
   with macOS's answer changing; ten mutants.
3. **The floor's image rule (162b00a).** CLAUDE.md's floor, Clipboard.swift and this plan now say that
   `{}` is text alone and a host sends `image` only to a subscription that says it takes images
   (`"accepts":2`, say). #66's host sends an image to every subscriber; it follows this as it rebases.
4. **"Sent" before the Mac had it (768f207).** A Paste said "Sent to ‹Mac›’s clipboard" and counted the
   copy as dealt with as it handed kind 32 over, while the connection could be dead without its end read
   (Sill back from another app after the Mac evicted it, a network change, a Mac asleep). Now a ping
   with 16 random bytes follows the text through the same door; its pong is the receipt ("Sent…", the
   haptic, the copy dealt with); none in max(4 s, 4 × the worst round trip) gives "Didn’t reach ‹Mac›.
   Try Paste again." and the chip again; a late receipt still counts. No wire change. Live on the
   simulator: a Paste (`-SillSettingsScript '3 paste …'`) to the test host gave "its receipt awaited for
   4.0 s", then "the Mac has read it", and the host's pasteboard held the 32 bytes with the launch's
   marker; through `sillrelay.py --blackhole-after 3`, a Paste at 3 s gave "no receipt in time: did not
   reach the Mac" and the chip again, and the host got nothing. Check: the length (never a ping's 8) and
   the wait; three mutants.
5. **The chip unannounced, and running out unseen (2eb0fb2, a371cb6).** Its 20 s ran under the Settings
   panel, the Apps list, the tour (on a fresh install the tour covers the first session's chip a second
   in), a thumbnail's lights or the Aa ruler, and for someone using VoiceOver, and then counted the copy
   as dealt with. Now `chipCounts`: only while it shows, Sill active and VoiceOver off; VoiceOver is
   told when it first shows ("Paste on ‹Mac› is available, near the bar."). Live on the simulator: the
   chip offered, the Settings panel over it 1.5 s in ("waits, 18.3 s left"), the panel closed at 12 s
   ("runs, 18.3 s left"), then "time is up"; Sill sent to Settings.app 6 s in ("waits, 14.6 s left") and
   back at 14 s ("runs, 14.6 s left"), then "time is up"; with `-SillVoiceOver 1` it stayed 30 s. Check:
   the rule's eight cases; three mutants. A session that ends with the chip showing now forgets that it
   showed (a371cb6).
6. **On by default replaces the device's clipboard (documented).** Noah's call: open question 1 says
   what it does to people who never use the feature, and Untested has the steps.
7. **Copy (d5b22a7).** Settings › General's footnote now says only copies a password manager marks as
   concealed stay, and that a device's text comes with Paste; support.html and privacy.html say "Sill
   never reads your iPhone or iPad’s (device’s) clipboard by itself". A mutant puts the old words back.
8. **The site's words before the release (f8355aa).** Kept with this pull request, as #79's and #75's
   are, inside `<!-- Clipboard: … -->` blocks (support.html's section, privacy.html's three items), and
   docs/release-checklist.md part 1 §3 says how a republish before the release cuts them (a perl line,
   the date put back). A copy cut that way differs from main's pages only in the date and in words true
   of the builds out too. support.html also gains the line for macOS's paste privacy.

Verified after the fixes (the code at a371cb6):
- `Tests/checks/clipboard` 259 checks; its mutants, 72 of 72 caught (the 50 before and 22 new; 39 min under other
  agents' load). `Tests/checks/run-all.sh`: all 41
  passed (7 min 05 s).
- `swift build -c release` from `git archive` of a371cb6: 42.9 s, only the CaptureProbe warning. The iOS
  app from the same archive, Debug and Release for the generic simulator and Debug for a generic device
  (`CODE_SIGNING_ALLOWED=NO`, arm64): BUILD SUCCEEDED (18 s, 36 s, 17 s), only the known StreamClient
  capture warning (StreamClient.swift:3469, main's 3430). Its Debug build on the private simulator: a
  Paste's receipt again, the host's pasteboard holding the 38 bytes with the launch's marker.
- H2 again, origin/main's CLI against this branch's, both from `git archive`: idle 35 s side by side
  identical masked and sorted (7 lines); a client picking the Desktop for 15 s that never subscribes:
  identical in order without the `[1s]` lines (35 lines each), no clipboard line.
- Harness photos on a private iPad Pro 13-inch (iOS 27.0, deleted after): the chip sideways and upright,
  a Paste's note, the Settings group and the stream: byte for byte the reviewed build's (7e6468a); the
  new note, "Didn’t reach Mac mini. Try Paste again.", sideways and upright.
- Sill.app's previews from the final bare binary against the reviewed build's: 130 files byte for byte
  but the General pane (its footnote), and 10 new (the clipboard section in each of macOS's answers, and
  with the switch off). Copies are in `~/Downloads/sill-handoff/clipboard/photos/review/`.
- Not rerun: the XCUITest tap on the system Paste control (the receipt was driven through
  `sendClipboard`, the code the control's tap reaches), the bare app's switch, the phone's arrangement
  and the Duo's poses (no layout changed). macOS's alert itself: nothing here reads the real clipboard.

## Untested, for Noah

On the iPad mini and the iPhone 15 Pro with this branch's builds and this Sill.app:
1. At home: copy a sentence in TextEdit; it pastes in Notes on the iPad. Copy in Notes, switch back to
   Sill: the chip "Paste on ‹Mac›" (above the window bar upright, under the bar sideways); tap
   Paste, then ⌘V in TextEdit. Sill.log has "Clipboard: iPad (…) shares the clipboard." and no line
   per copy.
2. Through Tailscale, away: the same.
3. A password copied in 1Password, and one in Apple's Passwords app, never reaches the iPad (and
   nothing in Sill.log); if the Passwords app's copy arrives, it does not mark it concealed: say so.
4. Universal Clipboard (the same Apple Account, Handoff on): copy on the Mac: the iPad has it, and the
   chip may come once offering it back (known); copy on the iPhone: Sill does not pass it on.
5. Settings › General's switch while the iPad streams: the This iPad group loses its rows, copies stop;
   on again, they come back.
6. VoiceOver on the iPad: when the chip shows, "Paste on ‹Mac› is available, near the bar."; the chip's
   words, Paste with its hint, Dismiss; it stays until Paste or Dismiss; "Sent to ‹Mac›’s clipboard"
   spoken once the Mac has it.
7. Split View or a window beside Sill: a copy there brings no chip until Sill becomes active again
   (known); the Settings group's Paste works any time.
8. On the iPhone: the chip above row 1, the success haptic once the Mac has the text.
9. macOS's paste alert (the review's finding 2), with this Sill.app: `defaults write me.saffer.sill.mac
   EnablePasteboardPrivacyDeveloperPreview -bool yes`, Quit Sill from its menu and open it again, connect
   the iPad. Settings › General shows "macOS asks before Sill reads the clipboard, so what you copy here
   stays on this Mac." under the switch; copy in TextEdit: no alert, nothing arrives, and Sill.log has
   the line once. Click Allow in System Settings…: macOS's alert (note its words and buttons), then
   Privacy & Security › Paste from Other Apps with Sill listed; set Allow: the orange line goes (within a
   second while Settings shows), a copy in TextEdit arrives on the iPad, and Sill.log says "macOS lets Sill
   read the clipboard again". Set Deny: "macOS doesn’t let Sill read the clipboard…", copies stay, and a
   Paste from the iPad still sets the Mac's clipboard. Then `defaults delete me.saffer.sill.mac
   EnablePasteboardPrivacyDeveloperPreview` and open Sill again.
10. The receipt (finding 4): copy in Notes, stay away from Sill about 10 s (the Mac lets the suspended
    iPad go after 4 s), come back and tap Paste on the chip at once: either "Sent to ‹Mac›’s clipboard"
    and ⌘V on the Mac pastes it, or "Didn’t reach ‹Mac›. Try Paste again." and the chip comes back once
    the session is up again; never "Sent" while ⌘V pastes something else.
11. On by default (finding 6, open question 1): copy a photo on the iPad, then with Sill connected copy
    text on the Mac: the photo is gone from the iPad's clipboard; 10 minutes later the iPad's clipboard
    is empty. Say whether either should change.

## Progress

- 2026-10-14: plan written (ab3c777); the wire, the rules and their checks (f97a7ec); the host
  (fde48de) and the test client (edf8fd5); the device (7a36e2a); the Universal Clipboard skip and the
  single look (44d38c4); the docs (922345d); the pasteboard on its own queue and the wait for an
  empty pasteboard (317480b); comments (5615d96). Pull request #78.
- Final, on 5615d96: `Tests/checks/run-all.sh` all 41 passed (422 s); `Tests/checks/clipboard`
  197 checks and 50 of 50 mutants; a clean `swift build -c release` from `git archive` (50 s, only
  the CaptureProbe warning); the iOS app three ways (only the StreamClient warning); CI's "Build and
  check" passed on the pull request (8 min 16 s). The private simulator is deleted.
- 2026-10-14, after the review (Results, "The review"): a stop never lost to the rate (c2d7b6a); the
  Mac's clipboard read only while macOS allows it, with Settings › General's section (210ba4b); the
  Mac's footnote and the site's sentences (d5b22a7); the floor's image rule (162b00a); "Sent" only on
  the Mac's receipt (768f207); the chip's time while it shows, and VoiceOver told (2eb0fb2, a371cb6);
  the site's words marked for the release (f8355aa); these docs.
- Final, after the review: `Tests/checks/run-all.sh` all 41 passed (7 min 05 s); `Tests/checks/clipboard`
  259 checks and 72 of 72 mutants; `swift build -c release` and the iOS app three ways from `git
  archive` of a371cb6 (only the known warnings); the live runs and photos in Results. The private
  simulator is deleted.
