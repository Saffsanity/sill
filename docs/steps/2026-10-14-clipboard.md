**The clipboard both ways (2026-10-14, branch `clipboard` from main at 985a733; issue #64; PR #78;
the plan, its open questions with the default taken for each, the results and the review's fixes are
in `docs/clipboard-plan.md`).** Noah: work on the clipboard (after #67/#68, #69, #59, #57, #58), text
first. Wire, host and device; additive.
- Wire: kind 32 `clipboard`, both ways, JSON `Clipboard {text, image, stop}` (Clipboard.swift): pull
  request #66's number and shape (`image` reserved for a later generation; `stop`, a device's switch
  going off, is this change's); `WindowList.clipboard: Int?` (1: text), so #66's `Bool` becomes an
  Int as it rebases (a Bool does not decode). A device sends kind 32 only to a host that says 1 or
  more; any kind 32 subscribes, and `{}` is text alone: a host sends `image` only to a subscription
  that says it takes images (the floor; #66's host sends one to every subscriber). Text at most
  256 KB of UTF-8, the JSON at most 1 MiB either way. Kinds 29–31 stay free (#66's; the sound, once planned at 29, is 43).
- Rules, pure, both ends: `ClipboardPolicy` (StreamProtocol). Never sent: one from another device through Universal Clipboard
  (`com.apple.is-remote-clipboard`: reading it fetches it from there, found while building), the
  host's own write; types are judged before any data is read. A device's subscriptions and texts are
  rated 4 a second, its stop never (`hostReceives`).
- Host: `HostClipboard` (main actor; the pasteboard read and written on a queue of its own,
  `Board`, so a slow read never holds up input): the look at the change count four times a second
  while a device subscribes (Task.sleep, not a RunLoop timer), and only while macOS allows every read
  (`MacClipboard.access`, NSPasteboard's `accessBehavior`, macOS 15.4 and later: while it would ask,
  an alert at every copy, or denies, nothing is read, nothing copied meanwhile is sent, one line when
  that changes); an empty pasteboard waits up to a second for its contents (`hostWaits`: found live,
  9 of 12 slow copies lost before, none now); what was on the clipboard when the first subscribed is
  never sent; a device's text written `.currentHostOnly` with this launch's marker and passed to the
  other subscribers; one line per subscription or stop ("Clipboard: iPad (iPad14,1) shares the
  clipboard."), none per copy, never contents; `clip.sent`/`clip.recv`. `HostConfig.shareClipboard`
  (on): Settings › General's `ClipboardSection`, "Share clipboard with devices" (`shareClipboard`),
  and while macOS asks or denies, why and "Allow in System Settings…" (Paste from Other Apps,
  `Privacy_Pasteboard`; one read on that click first while macOS has not asked about Sill, so it is
  listed); the CLI's `--no-clipboard`; the Mac's alone, applied at once by `setTarget`. A synthetic
  host shares a pasteboard of its own (TEST ONLY `SILL_TEST_PASTEBOARD`, `SILL_TEST_CLIPBOARD_LOG=1`,
  `SILL_TEST_CLIPBOARD_ACCESS`), never this Mac's clipboard.
- Device: `StreamClient+Clipboard` (subscription, `stop`, the Mac's text written `.localOnly` with a
  10-minute expiration, the handled change count `Sill.clipboardHandled`) and `ClipboardChip`: when
  Sill becomes active (or a session starts within 15 s after) with new text on the clipboard
  (`changeCount`, `hasStrings`: no prompt), "Paste on ‹Mac›" / "Then press ⌘V there." with the
  system's Paste control (`PasteButton`, UIPasteControl) and Dismiss; its 20 s run only while it
  shows with Sill active, never under VoiceOver, which is told when it first shows (`chipCounts`);
  under the bar sideways (bottom corner while the link's line shows), above the window bar or row 1
  upright. A Paste is "Sent to ‹Mac›’s clipboard" only once a ping sent after the text comes back (a
  16-byte random payload, the receipt; none in max(4 s, 4 × the worst round trip): "Didn’t reach
  ‹Mac›. Try Paste again." and the chip again). Settings › This iPad: Share Clipboard
  (`Sill.shareClipboard`, on) and Paste on ‹Mac›, while the Mac says it. Harness:
  `-SillClipboardChip 1`, `-SillClipboardNote sent|long|notsent`; live, `-SillSettingsScript '<t> paste
  TEXT'` and `-SillSettingsCloseAt <s>`.
- The review (2026-10-14, eight findings, all taken; the plan's "The review"): the stop lost to the rate
  and macOS's paste privacy (the two should-fixes), the floor's image rule, "Sent" before the Mac had it,
  the chip unannounced and running out unseen, the Mac's footnote and the support page's sentence, the
  site's words marked `<!-- Clipboard` for the release (docs/release-checklist.md part 1 §3 cuts them
  for a republish before it), and on-by-default's effect on the device's clipboard left to Noah (open
  question 1).
- Verified (the plan's Results): `Tests/checks/clipboard` 259 checks and 72 of 72 mutants (in CI's matrix);
  `Tests/checks/run-all.sh` all 41; `swift build -c release` from `git archive` (only the CaptureProbe
  warning); the iOS app Debug and Release for the simulator and Debug for a device (only the
  StreamClient capture warning); H2 against origin/main (idle identical masked and sorted; a client that
  never subscribes, no new line); live on loopback (the review's stop sequence: the copy went to the
  client against 7e6468a, not against this build; the rate on texts; macOS's four answers through a
  file, copies made while it asked or denied never sent, one made after reads came back sent); on a
  private iPad simulator, the receipt and its absence through a relay that stops forwarding, the chip
  waiting under the Settings panel, through an app switch and under VoiceOver's stand-in, harness photos
  byte for byte the reviewed build's but the new note. Earlier (7e6468a): the XCUITest tap on the
  chip's Paste, two devices, every marker, the bare app's switch. This Mac's own clipboard was never
  read or written.
- **Untested, for Noah:** on the iPad and iPhone with this Sill.app, at home and through Tailscale:
  copy in TextEdit, paste on the device; copy in Notes, back to Sill, Paste on the chip, ⌘V on the
  Mac; a password copied in 1Password and in the Passwords app arrives like any copy since 2026-10-29 (it never did before; Sill.log has no
  line for it); Universal Clipboard on (same Apple Account): the chip may come once for the Mac's own
  copy (known), an iPhone copy is not passed on; Settings › General's switch live; VoiceOver on the
  chip (its announcement, no time limit); Split View (the chip waits for Sill's next activation; the
  panel's Paste works). From the review: macOS's paste alert through `defaults write
  me.saffer.sill.mac EnablePasteboardPrivacyDeveloperPreview -bool yes` (the plan's step 9: the
  orange line, Allow in System Settings…, Allow and Deny, then `defaults delete` it); Paste right
  after 10 s away from Sill ("Sent" only when ⌘V pastes it); on by default replacing a photo on the
  device's clipboard, and that clipboard empty 10 minutes later (say whether either should change).
- **Paste right away (2026-10-29, branch `clipboard-autopaste` from main at 35a9c47, PR #242; the
  plan's "Paste right away").** Noah, trying #241: "still doesn't automatically Cmd+V is that coming
  later?". No wire change; the device's alone but for one change on the Mac since the review (below):
  with Settings › This iPad's "Paste on ‹Mac› Right Away" on (under Share Clipboard;
  `Sill.pasteRightAway`, on by default, never sent), a Paste's receipt also presses ⌘V on the Mac
  (`ClipboardPolicy.pastesOnReceipt`: only a receipt in time, only while something streams, only while
  the Mac's last list says it shares its clipboard, never while the tour shows; `KeyChord.paste`, ⌘'s
  own key around V, through `sendFromKeyRow`), 50 ms after the receipt (`pasteDelay`: the host
  writes the text on its Board queue while it echoes the ping at once; on loopback a ⌘V right behind
  the receipt came before the write in 99 of 100 of a test client's pastes and 21 of 25 of the app's,
  up to 14 ms early, and with 50 ms in none of 125); then "Pasted on ‹Mac›.", without ⌘V today's
  words; the chip "Where the cursor is.". The other way stays the person's (no iOS app pastes into
  another). Harness:
  `-SillClipboardNote pasted`, `-Sill.pasteRightAway 0`, DEBUG `-SillPasteDelay <s>`. Verified:
  `Tests/checks/clipboard` 285 checks and 91 of 91 mutants, `key-strokes` 359 (`KeyChord.paste` leaves
  nothing held) and 86 of 86; `run-all.sh` all 56; the three iOS builds and `swift build -c
  release`, only the known warnings; live on a private iPad simulator against a loopback synthetic host:
  the write, then "key 55 flags changed (command)", "key 9 down (command)", "key 9 up (command)", "key
  55 flags changed (none)"; the switch off, the write and no key; through a relay that stops
  forwarding, neither and "Didn’t reach"; harness photos in
  `~/Downloads/sill-handoff/device-tests/2026-10-29/autopaste/`; CI's Build and check passed on
  89f2c21.
- The review (2026-10-29, the plan's "The review"; six findings, each reproduced, then fixed in a commit
  of its own): a Mac whose Share clipboard with devices went off while a Paste was on its way dropped
  the text but echoed the receipt, and ⌘V pasted what it held before (a scratch host turning the
  switch off on a signal, a relay adding 1 s): the rule takes the Mac's last list (`hostClipboard`,
  2d9428a); the tour's hold, only in the glue and unchecked, is the rule's (`tourShows`, d435e8c); the
  chip "Where the cursor is." ("It goes where the cursor is." was cut short on 375 and 393 pt iPhones at
  xLarge text, 1ddadb9); under the Dvorak layout Paste presses ⌘K (V's place; the layouts' own data):
  Known, the support page, open question 16 (3dc8596); `-SillSettingsScroll clipboard` for the Paste row
  and footnote at 500x710 (734825d); and the Mac's one change, `HostClipboard`'s Board writes a device's
  text before `received` returns (1d8cf03): a main actor busy as the text arrived (a host's first
  stream start held it 70 to 150 ms) took the text and the keys back to back, and V came within half
  a millisecond of the write's end, before it in 4 of 25, now never. Re-run: `clipboard` 285 and 91 of
  91 at the head, 342 and 94 of 94 after; `key-strokes` 359 and 86 of 86; `run-all.sh` all 56 after;
  the three iOS builds, `swift build -c release` (from `git archive` of the head: 46.7 s, the
  CaptureProbe warning), the PR's live runs, the race (the app at 50 ms 0 of 25, at 0 ms 15 of 25), 11
  of the 12 photos byte for byte; the review's photos in `review/`; CI's Build and check on 694d600.
  **Untested, for Noah** (the plan's ten): a paste into TextEdit, Notes and a Terminal at their
  cursor, the switch off, a paste with no text field in front, VoiceOver's words, Universal Clipboard
  on, through Tailscale, the Settings panel's Paste row, a Paste as soon as the chip shows after Sill
  comes back and right after a pick, a Mac with the Dvorak layout (⌘K; open question 16 is Noah's
  call). The PR's description predates the review.
