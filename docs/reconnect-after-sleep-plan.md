# Finding the Mac again after hours idle: the plan

2026-10-14. Branch `reconnect-after-sleep` (worktree `/Users/noah/Downloads/winstream-reconnect`)
from origin/main at 985a733; line numbers are at 985a733. Issue #69. Written from the triage
(`~/Downloads/sill-handoff/triage/2026-10-13-open-items.md`, "#69") and a read of
`StreamClient.swift`, `StreamClient+Remote.swift`, `StreamClient+Home.swift`, `DiscoveryPolicy.swift`,
`ContentView.swift` and the host's `StreamCoordinator.swift`. Device code, the support page and the
docs; no wire change, nothing on the Mac.

**The report (#69, 2026-10-13, Sill 0.5.1 on both, iPadOS, Wi-Fi):** "User couldn't get the app
to work after sitting dormant for a few hours. He had to login to my Mac and close and restart the
app on my iPad before it would reconnect."

## What happens today (each checked in the code)

1. **The Bonjour browser is made once and never again.** `ContentView`'s `onAppear`
   (ContentView.swift:46) calls `startBrowsing()`, which refuses a second browser while one exists
   (StreamClient.swift:837). A failed browser only changes the status line ("Browse failed: …",
   StreamClient.swift:869-870) and is never made again; the nearby browser has no state handler at
   all (StreamClient.swift:887-900). iOS takes away the mDNSResponder connection of an app it
   suspends (`kDNSServiceErr_DefunctConnection`, -65569, Apple DTS), so after hours in the
   background the rows are what the browser last saw: a row of a Mac that went is dialled, and a
   Mac that came back (its Sill relaunched after the Mac restarted, say) is never listed again; a
   saved one shows as Remote, and a tap says it "didn't answer. It may be asleep." Only a relaunch
   of the app makes a new browser. That is the report's "close and restart the app".
2. **The automatic reconnect gives up after about 11 s while the Mac's row stays listed.** A listed
   row is dialled at once and nothing else is scheduled (DiscoveryPolicy.swift:320). A dial that is
   not ready in 5 s is let go (StreamClient.swift:1412-1420), and its comment says "tearDown's
   discoveryChanged looks again", which is not so: `tearDown` (StreamClient.swift:2849-2913) never
   calls `discoveryChanged` or `reconnectIfListed`. The retry timer's chain ends at its first look
   that dials (StreamClient.swift:2842). So: a dial at the loss, one more at the chain's 6 s, each
   let go 5 s later, then silence under "Reconnecting to ‹Mac›…". A Bonjour Sleep Proxy (an Apple TV
   or a HomePod) keeps a sleeping Mac's record, so the row never leaves and no browse event comes
   when the Mac wakes.
   Found while reading it: a reconnect dial that ends otherwise (`.waiting`, then cancelled after
   5 s; `.failed`; no window list within 10 s of a TLS `.ready`) goes through `sessionEnded` as if a
   session had ended. That makes a new `Reconnect` (its loss, its remote dials' timing and its
   `afterQuit` start again), flips the status line ("Waiting for…", "‹Mac› disconnected. Sill will
   reconnect…", "Reconnecting to…") and dials again at once: a row whose dial waits (a stale row,
   a Mac whose port is closed) is dialled every 5 s for good.
3. **A Desktop stream the Mac stops is not asked for again.** When ScreenCaptureKit stops a
   capture, the host selects nothing and says so (StreamCoordinator.swift:442-445). The device asks
   for the Desktop by itself only when it was watching nothing, or a window that closed
   (StreamClient.swift:3416-3437, `default: break`): a stopped Desktop stays stopped until the host
   happens to send another window list, or the person picks something. Whether macOS stops a
   capture when the display sleeps or the Mac locks (R6) is not known: it needs Noah's display to
   sleep.
4. **Nothing tells the person why.** The support page's "Your Mac isn't listed"
   (site/support.html:50-56) never mentions a sleeping or restarted Mac; sleep appears only under
   Remote Access. Sill never keeps a Mac awake at home (only a remote device holds idle sleep off),
   and after a restart it runs only once someone logs in, with Launch at Login on.

## The change

### 1. The browsers, made again (`DiscoveryPolicy`: `rebuildBrowser`, `browserFailures`, `browserResults`)

- **On the return from the background** (`UIApplication.willEnterForegroundNotification` after a
  `didEnterBackgroundNotification`), the network browser is made again, and the nearby one if it
  runs: a browser made before the suspension may hold a connection iOS made defunct without saying
  so yet.
- **On `.failed`** (any error; the defunct connection is -65569), the browser is cancelled and made
  again after 1, 2, 4, 8, 16, then 30 s (`browserRetry`), counted by failures in a row; a browser
  that ran 30 s (`browserStable`) before it failed starts the count again, and so does the return
  from the background. Never in the background: a browser made there is suspended with the app, and
  the return makes it anyway. The nearby browser gets the same state handler.
- **What is kept:** the old browser's results stay beside the new one's for `rebuildSettle` (3 s, the
  network's first word, `networkFirst`) from the new browser's start, a name in both taken from the
  new one; then the new one's alone. A Mac that stays listed never leaves the rows, so its sightings
  by name keep their times (`NetworkSightings.since` and `leftAt`, which hold back a Direct row and a
  remote dial for `networkGrace`; `quitWait`'s `networkSince`; `directSince`), and the reconnect's
  count of dials of a listing (below) is not reset by a rebuild. A Mac that went leaves 3 s after the
  rebuild. While a failed browser waits to be made again, the rows stay as they are (a settle still
  running does not end then, and a result the failed browser still delivers only joins them).
- **Its interfaces are the new browser's** as soon as it lists the name (the review, 2026-10-14). A
  first report that lists the Mac on Wi-Fi alone takes the cable out of `PathSightings` until a
  later report lists it again, and the cable's settle (`wiredSince`, with the refused listing and
  the moves up's back-off keyed to it) then counts from that report: a session on Wi-Fi waiting to
  move up waits up to `cableSettle` more. A working session over the cable stays on it: no ping went
  out while the app was suspended, so the return stamps its pong as it resets liveness
  (`StreamClient.resetLiveness`), and `pathGone` waits for the silence mark (1 s), by which time its
  pongs are back. Without the stamp the pong from before the trip would move it to Wi-Fi at the
  first report, and back once the cable had settled again. Keeping the old interfaces beside a
  name's new ones until the settle ends was the other way; it is not taken, as it would keep a
  cable pulled during the suspension listed for 3 s, and a session that died with it would be
  dialled on the cable first.
- The failed browse's status line goes: the browser is made again, and the console says so
  ("browser: the network browser failed (…); making it again in 1 s", "browser: rebuilt the network
  browser (back from the background)", "browser: the new network browser has settled: …").
- DEBUG `-SillBrowserFail N`: each of the first N network browsers is reported failed with
  -65569 half a second after it starts, as iOS reports a suspended app's, so the `.failed` path
  and its back-off run in the simulator (whose browsers use the Mac's own mDNSResponder, which never
  defuncts an app it does not know is suspended).

### 2. The reconnect keeps trying while the row stays listed (`DiscoveryPolicy`: `redialRow`, `reconnectLine`)

- The automatic reconnect dials a listed row of its Mac at once, then, while that listing lasts
  and the dials do not connect, again 5, 10, 20, then every 30 s after the last dial started
  (`reconnectRetry`), only in the foreground. The count is the listing's (the row's
  `sightings.since`, or `directSince` for a Direct row): the row going and coming back (the Mac's
  Sill relaunched, its record renewed) is dialled at once; so is the first look after the return
  from the background, which starts the count again.
- After 3 dials that did not connect (`reconnectQuietAfter`, about 20 s) the status line says
  "‹Mac› isn’t answering. It may be asleep. Sill keeps trying, or tap it to try now." and keeps
  saying it through the later dials (VoiceOver hears it once). After 12 (`reconnectDials`, about
  4.6 minutes) the dials stop: "Stopped trying to reach ‹Mac›. Tap it to try again.", the remote
  path's words; a new listing or the return to the foreground starts again. Each dial through a
  sleep proxy may wake the Mac (Wake on Demand; whether it does is Noah's test), so the dials are
  spaced and bounded.
- A tap dials at once, as before (`connect(to:)` clears the reconnect).
- A reconnect dial let go after 5 s now looks again (the comment's intent), and one that ends any
  other way before it connects (waiting, failed, no window list) counts as one dial of the listing
  and keeps the reconnect: no new `Reconnect`, no flip of the status line ("Waiting for ‹Mac›…" is
  a tap's line, not the reconnect's), no dial at once.
- The retry timer's chain lives while a reconnect is wanted, one chain at a time (a token), each
  look the rule's.
- What does not change: the order (the network row, the Direct row after its waits, then a saved
  Mac's remote dial while no row lists it), the remote dial's 2, 4, 8, 10 s and its 120 s window,
  `quitWait`, a row that waits for a tap.

### 3. A stopped Desktop asked for again (`DiscoveryPolicy.autoDesktop`)

The device's rule for a window list that says nothing streams, moved into the policy and checked:
nothing watched before (the connection's first list, or a stream that never started), the Desktop
at once; **the Desktop it was watching (new)**, the Desktop at once; a window that has gone, the
Desktop after 2 s plus the worst round trip unless the person chose something meanwhile (as
before); a window still listed (a pick that failed), nothing: the person's to retry. Never within
10 s of the last automatic request (as before), so a Mac that cannot start the Desktop is asked at
most every 10 s, as it already was at its next window list. No host change.

### 4. The words

- site/support.html, "Your Mac isn’t listed" (outside the Remote Access markers, which stay as they
  are): a bullet for a sleeping Mac (Sill may not be able to wake it; keep it awake in System
  Settings › Energy, Energy Saver on macOS 14, or Battery on a laptop, while you use Sill from another
  room) and one for a Mac that restarted (Sill opens only once someone logs in, with Launch at Login
  on: in the Sill menu, or Sill’s Settings › General). Whether Sill wakes a sleeping Mac is not
  known: through a Bonjour Sleep Proxy with Wake for network access on, a dial may (Wake on Demand,
  the reason for the bound above); with none it should not. So the words say only that it may not
  (the review found the first draft's "Sill can’t wake a sleeping Mac" at odds with that reason).
  Noah's sleep-proxy test settles them: if a dial wakes the Mac and connects, the bullet can say
  "With an Apple TV or HomePod at home and Wake for network access on, your Mac can wake when Sill
  connects; otherwise keep it awake in …".
- README.md's Good to know: the same two, in a sentence each.
- docs/app-store-metadata.md: a line for the next version's What's New.
- docs/DEVELOPMENT.md: the reconnect's behaviour, `-SillBrowserFail`, Known limitations.

## Open questions, with the default taken

1. Make the browser again on every return from the background, or only after a failure or a long
   time away? **Every return** (cheap: one browse, its cached answers in milliseconds; the defunct
   connection is not always reported).
2. Which notification? **`willEnterForeground`, after `didEnterBackground`**: `didBecomeActive`
   also fires after Control Center or an alert, when nothing was suspended.
3. How long the old results stay beside the new browser's: **3 s** (`networkFirst`). Shorter risks a
   Mac answering late leaving the rows for a moment; longer keeps a Mac that went.
4. The back-off and the bound: **5, 10, 20, then 30 s; 12 dials** (about 4.6 minutes), then "Stopped
   trying…". A dial through a sleep proxy may wake the Mac (Wake on Demand; untested), so it is
   never a fast loop, and never in the background.
5. The quiet line after **3** dials. Its words are the plan's; Noah may prefer others.
6. The return from the background starts the count again (the person is there): **yes**.
7. The failed browse's "Browse failed: …" line: **gone**; the browser is made again.
8. The Desktop re-ask: **done**, under the 10 s spacing that already bounds the automatic Desktop.
9. "Keep this Mac awake while Sill is open": **not here** (a product call; the triage's half day).
   The support page says how to keep the Mac awake.

## Test plan

- `Tests/checks/policy`: cases and mutants for every new rule (`browserRetryDelay`,
  `browserFailures`, `rebuildBrowser`, `browserResults`, `redialRow`, `reconnectLine`,
  `autoDesktop`), and models over time: a host stopped for 20 s (dials at 0, 5, 15; back at 20, the
  next dial connects at 35), a sleep proxy that never answers (12 dials, the quiet line, then
  "Stopped trying"), a new listing mid-way, the background, a rebuild that keeps a Mac's sightings.
  The other checks that compile DiscoveryPolicy.swift (`home-device`, `home-model`,
  `remote-rules`) and their mutants again.
- Builds: the iOS app Debug and Release for the generic simulator and Debug for a generic device
  (`CODE_SIGNING_ALLOWED=NO`); `swift build -c release`; `Tests/checks/run-all.sh`.
- On a private simulator ("Sill reconnect", deleted after), the Debug app with `-SillServiceType
  _silltest._tcp` against `SillHost --synthetic --pairing` registered with
  `SILL_TEST_SERVICE_TYPE=_silltest._tcp`, on loopback, the software encoder, no router: pair, stream,
  `kill -STOP` the host for 20 s, `kill -CONT`. main's build: two "letting it go" lines, then
  silence under "Reconnecting…". This build: the dials at 0, 5, 15 and 35 s, the session back
  without a tap. A longer stop for the quiet line.
- The browser: the app sent to the background and back (another app launched, then Sill), the
  console's "browser: rebuilt" line, the rows unchanged; `-SillBrowserFail 3` for the `.failed`
  path (1, 2, 4 s).
- The Desktop re-ask: a stand-in Mac (Python, loopback, a plain door) that sends a list with the
  Desktop streaming, then one with nothing: this build asks for the Desktop, main's does not.
- Photos: the connect screen with the quiet line (a new harness case, `-SillConnectCase asleep`) at
  the Duo's sizes and a phone's, at the default and the largest text.

## Results

All on 2026-10-14, on a private simulator, "Sill reconnect" (iPad mini (A17 Pro), iOS 27.0; deleted
after), with the Debug app built ad hoc (`CODE_SIGN_IDENTITY=-`, so the simulator gives it a
keychain), against `SillHost --synthetic --pairing` on 127.0.0.1 alone (SILL_TEST_LOOPBACK,
SILL_TEST_SOFTWARE_ENCODER, SILL_TEST_NO_ROUTER, SILL_TEST_SERVICE_TYPE=_silltest._tcp, its identity
and trust list in SILL_TEST_REMOTE_DIR), the app with `-SillServiceType _silltest._tcp -SillTapRow
"Sill test"`, so the host was a real Bonjour row and its reconnect a row's. The device was paired
once, with the code at the host's remote door (`--remote` for that run only): this Mac's console was
locked, so the host answered the ask "locked", as it should. Times are from the console (each line
stamped as it came) and the host's log; the loss is the device's "connection silent for 6 s".

- **main (985a733), the repro**: streaming, then `kill -STOP` on the host for 20 s. The loss 6.2 s
  after the stop; dials at +0 and +6.3 s, each "not ready in 5.0 s (preparing); letting it go and
  looking again"; then nothing for the 62.8 s after the host was continued, under "Reconnecting to
  Noah’s MacBook Pro…", and the host saw no connection. As the triage read it.
- **This branch, the same run**: the loss 6.0 s after the stop; dials at +0, +5.3, +15.3 and
  +35.3 s; the fourth connected at +35.3 s, without a tap. The third began 0.14 s before the host
  was continued, which then refused it over its pre-auth cap of two pending connections from one
  source ("1 over the limit": the two dials the device had cancelled were still in its listen
  backlog), an artifact of SIGSTOP. "‹Mac› isn’t answering. It may be asleep. Sill keeps trying, or
  tap it to try now." from +20.5 s.
- **The bound**: the host stopped for 300 s. Dials at +0, 5.3, 15.3, 35.3, 65.3, 95.8, 125.8, 155.8,
  186.0, 216.4, 246.7 and 276.8 s (the rule's 0, 5, 15, 35, then every 30 s, with the let-go's
  0.25 s and the timers' slack); the quiet line at +20.5 s; "Stopped trying to reach Noah’s MacBook
  Pro. Tap it to try again." at +281.8 s, and no dial after it, also once the host was back at
  +299.5 s (no new listing: the bound's price, open question 4). Sill sent to the background (the
  Settings app) at +360.9 s and back at +371.1 s: "browser: rebuilt the network browser (back from
  the background); ["Sill test 2676"] kept beside it for 3 s", a dial at once, connected 40 ms later.
- **The return from the background while streaming** (the Settings app for 15 s): the host had
  dropped the suspended app; on the return the device found the connection silent, the browser was
  made again with the row kept beside it, and the reconnect dialled at once: the session was back
  0.1 s after the return, and the new browser settled 3.0 s later with the row. No rebuild at launch.
- **The browser after a failure** (`-SillBrowserFail 3`): failures 0.45, 2.03 and 4.66 s after
  launch; made again 1.05, 2.12 and 4.21 s after each (the rule's 1, 2, 4); the fourth browser
  settled 3.13 s after it was made; the host's row listed throughout (one "discovery:" line). The
  first build let the second rebuilt browser's settle run out while it waited for its next rebuild,
  so the rows read for a moment from a browser that had failed: fixed in 03ca390 (a failure keeps
  the rows as they are), and the run then had one settle, the last browser's.
- **The Desktop asked for again** (a stand-in Mac in Python on 127.0.0.1, a plain door, dialled by
  `-SillConnect`, sending a list with the Desktop streaming and 3 s later one with nothing): this
  branch asked for the Desktop 10 ms after the second list ("session: the Mac stopped the Desktop;
  asking for it again"); main's build asked for nothing in the 12 s after it, as the stand-in sent
  no further list. Main asks again only with the Mac's next window list, which a Mac sends when a
  window opens, closes or changes (the review saw main's build ask 3 ms after a later list): so 0.5.1
  brings a stopped Desktop back at the Mac's next change of windows, and this build at once.
- **Not provoked here**: the defunct connection itself. The simulator's apps use this Mac's
  mDNSResponder, which does not know an iOS app is suspended; `-SillBrowserFail` and the return
  from the background stand in for it. R6 (whether macOS stops a capture when the display sleeps or
  the Mac locks) needs Noah's display to sleep.
- **Photos** (`-SillConnectCase asleep`): the new line at 951×669, 669×951, 466×678, 678×466 and
  744×1133, at the default text size and at accessibility-extra-large: it wraps to two lines and
  reads whole beside the rows; the connect case `homerows` at 951×669, 669×951 and 466×678 pixel for
  pixel main's build (0 pixels differ). The live photos show this Mac's name and windows and stay
  out of the repository.
- **Checks and builds**: below, in Progress.
- **Found, and left as it is** (older than this branch, the same on main): on the return from the
  background the ping timer, on the network queue, can run before the main queue's
  willEnterForeground handler resets liveness, so a session whose connection is still alive (a short
  trip away, under the Mac's 4 s eviction) is called "silent for 10 s" and ended; the reconnect then
  brings it back at once (0.1 s here), with a flash of the connect screen. A ping tick that comes
  long after the last one (the app was suspended) could reset liveness itself.
- **The review** (2026-10-14, after 1c4b921: an adversarial pass that ran the builds, every check and
  mutant and the live runs again on a simulator of its own) found four things, each checked against
  the code here and fixed in a commit of its own:
  - *The words on waking a sleeping Mac* (should-fix, 1798232). The home-side words "Sill can’t wake
    a sleeping Mac" (support.html, README, DEVELOPMENT.md, §4) were at odds with the reason this
    branch gives for the 12-dial bound, that a dial through a Bonjour Sleep Proxy may wake the Mac,
    and neither is verified; Sill.app's own comment on App Nap (AppModel.swift) already says a device
    at home can wake its Mac that way. The words now say Sill may not be able to wake it, so keep it
    awake (§4 has the wording for after Noah's sleep-proxy test). The Remote Access lines stay: no
    sleep proxy sits on a VPN path.
  - *A rebuild keeps a Mac by name, not by interface* (f39b875). §1 claimed the cable's settle
    survived a rebuild; it does only when the new browser's first report lists the cable. When that
    report lists the Mac on Wi-Fi alone, a working cable session back from a short trip would move
    to Wi-Fi, and back once the cable had settled again, because its pong dated from before the
    trip (`pathGone`; the review's pure demo, no cable here). The return now stamps the pong as it resets liveness
    (`resetLiveness`), `sleep.swift` has the model, and §1 says what a rebuild keeps.
  - *0.5.1 and a stopped Desktop* (37ed3de). CLAUDE.md said 0.5.1 never asks for it again; it asks
    with the Mac's next window list (the Desktop's run above).
  - *"Both browsers"* (0e8a098). DEVELOPMENT.md and ContentView's harness contract said the return
    from the background makes both browsers again; it makes the network browser again, and the
    nearby one only while it runs, as `cameForward`'s comment now says too.
- **The review's own runs** on 1c4b921 agreed with the ones above (the 20 s stop back at the third
  dial without a tap; the 300 s stop's 12 dials, quiet line and "Stopped trying…"; `-SillBrowserFail
  3`; the Desktop; `policy` 158 of 158 mutants and the other three checks' 124, 21 and 72), and ran
  two paths these runs had not: a reconnect dial that ends before it connects (`sessionEnded`'s new
  branch), against a TLS stand-in holding the test host's key that completes the handshake and never
  sends a window list, advertised under the session's Bonjour name: "the dial of … did not connect
  (closed)", dials at +0, 7.2, 17.2, 37.3 and 67.4 s, the quiet line after the third, a steady status
  line (main's build: "disconnected", then a new dial about every 6 s, 13 connections in 75 s); and a
  row whose port resets each handshake (main: two dials, then stuck; this branch: 0, 5, 15, 35 s and
  the quiet line).
- **After the review's fixes** (2026-10-14, on 0e8a098 and the record after it): the iOS app Debug for
  the generic simulator as CI builds it, Release for the generic simulator and Debug for a generic
  device, unsigned, each only the known `StreamClient` capture warning (StreamClient.swift:3662);
  `swift build -c release` from a clean build folder, 41.1 s, only the CaptureProbe warning;
  `Tests/checks/run-all.sh`, all 40 passed (1,004 s on a Mac loaded by other work); `Tests/checks/policy`
  446 cases (441, and the cable model's 5) and 158 of 158 mutants (53 min on that loaded Mac); `home-device` 182, `home-model` 62 and
  `remote-rules` 123 cases, their files unchanged, and their mutant patterns in DiscoveryPolicy.swift
  (124, 10 and 17) each found as often as at 1c4b921 and on main: the fixes change only a comment
  there. Live, on a private simulator ("Sill reconnect-fix 69", iPad mini (A17 Pro), iOS 27.0, deleted
  after), the Debug app built ad hoc against `SillHost --synthetic` (a plain door on 127.0.0.1 alone,
  the software encoder, no router, registered as a `_silltest._tcp` row), found as a row and
  streaming: four trips to the background (the Settings app for 2.3, 2.3, 2.3 and 15 s); each return
  made the network browser again with the row kept beside it, settled 3.05 to 3.13 s later, and the
  session went on over the one connection the host saw throughout (no "connection silent", no "Client
  left" until the host was stopped at the end, when the reconnect dialled at once). That session has
  no route word (loopback), so the pong stamp itself changes nothing there; the cable case is Noah's.

## Progress

- 2026-10-14: the plan (211e98c); the browsers made again, the reconnect kept alive, the Desktop
  asked for again, with `Tests/checks/policy`'s `sleep.swift` and 28 mutants (83f96ba); a failure
  keeps the rows as they are (03ca390); the runs above; the support page, README, the App Store
  text for the next version, DEVELOPMENT.md and CLAUDE.md; PR #77.
- Checks on the files before the review: `Tests/checks/policy` 441 cases (392 and 49 new) and 158 of
  158 mutants (130 and 28 new); the other checks that compile DiscoveryPolicy.swift, whose mutants'
  patterns occur as often as on main: `home-device` 182 cases and 124 of 124 mutants, `home-model` 62
  and 21 of 21, `remote-rules` 123 and 72 of 72; `Tests/checks/run-all.sh`, all 40 passed (493 s).
- Builds: the iOS app Debug for the generic simulator as CI builds it (`CODE_SIGNING_ALLOWED=NO
  ARCHS=arm64`), Release for the generic simulator and Debug for a generic device, unsigned: only
  the known `StreamClient` capture warning (StreamClient.swift:3662, the closure main has at 3430);
  `swift build -c release`: only the CaptureProbe warning. CI's "Build and check" passed on the PR
  (run 38486135118, 8 min 39 s).
- 2026-10-14, the review's fixes: 1798232 (the words on waking a sleeping Mac), f39b875 (the pong
  stamped on the return, the cable model, what a rebuild keeps), 37ed3de (0.5.1 and a stopped
  Desktop), 0e8a098 (the nearby browser made again only while it runs), then this record with the
  CLAUDE.md entry and the pull request's text; the numbers are in Results, "After the review's fixes".
