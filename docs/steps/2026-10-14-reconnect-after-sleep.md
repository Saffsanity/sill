**Finding the Mac again after hours idle (2026-10-14, branch `reconnect-after-sleep` from main at
985a733, PR #77, issue #69; the plan, the causes with line numbers, the decisions, the results and the
review's fixes are in `docs/reconnect-after-sleep-plan.md`).** The report: after a few hours dormant
nothing reconnected until the Mac was logged in to and Sill relaunched on the iPad. Device code, the
support page and the docs; no wire change, nothing on the Mac.
- The browsers: iOS makes a suspended app's connection to mDNSResponder defunct (-65569), and the
  Bonjour browser was made once (`startBrowsing`), so after hours in the background the rows were
  what it saw then, and a failed browse only said "Browse failed: …". Now the network browser, and
  the nearby one if it runs, is made again on the return from the background
  (`StreamClient.cameForward`: willEnterForeground after didEnterBackground) and after a failure, 1,
  2, 4, 8, 16, then 30 s later and in the foreground only (`DiscoveryPolicy.rebuildBrowser`,
  `browserFailures`: one that ran 30 s is the first again). The old results stay beside the new
  browser's for 3 s (`browserResults`, `rebuildSettle` = `networkFirst`), and a failed browser's rows
  stay as they are until it is made again, so a Mac that stays listed keeps its sightings by name.
  Its interfaces are the new browser's; the return stamps the session's pong as it resets liveness
  (`resetLiveness`), so a cable session whose new browser first lists the Mac on Wi-Fi alone stays
  on the cable. No line for a failed browse.
- The reconnect: a listed row was dialled at once, a dial not ready in 5 s was let go and nothing
  looked again (`tearDown` never does, whatever the comment said), and the retry chain ended at its
  first dial: two dials, then "Reconnecting…" for good, also under a Bonjour Sleep Proxy's record of
  a sleeping Mac. A dial that waited or failed began a new `Reconnect` and dialled at once (every 5 s
  for good to a stale row). Now `reconnectIfListed` dials a listing of the row at once, then 5, 10,
  20 and every 30 s after the last started, 12 at most, in the foreground only
  (`DiscoveryPolicy.redialRow`; `Reconnect.rowListing`, `rowDials`, `lastRowDialAt`); the row listed
  afresh, the return from the background, or a tap starts again. The line (`reconnectLine`):
  "Reconnecting to ‹Mac›…", after 3 "‹Mac› isn’t answering. It may be asleep. Sill keeps trying, or
  tap it to try now.", after 12 "Stopped trying to reach ‹Mac›. Tap it to try again.". The let-go
  looks again; a reconnect dial that ends without a goodbye before it connects is one dial
  (`sessionEnded`); "Waiting for ‹Mac›…" is a tap's line only; the retry chain lives while a
  reconnect is wanted, one at a time.
- A Desktop the Mac stopped (its capture stopped, so the host selects nothing) is asked for again
  at once, under the old 10 s spacing (`DiscoveryPolicy.autoDesktop`); 0.5.1 asks only with the
  Mac's next window list, sent when a window opens, closes or changes.
- DEBUG `-SillBrowserFail N` (each of the first N network browsers reported failed with -65569 half
  a second after it starts) and `-SillConnectCase asleep`. The support page's "Your Mac isn’t listed"
  gains a sleeping Mac (Sill may not be able to wake it, so keep it awake: Energy, or Battery) and a
  restarted one (Sill opens after a login, with Launch at Login); README's Good to know, the next
  What's New (docs/app-store-metadata.md), DEVELOPMENT.md.
- The review (2026-10-14, after 1c4b921), four findings, each fixed in a commit of its own: the
  home-side words said Sill can't wake a sleeping Mac, at odds with the bound's own reason (a dial
  through a sleep proxy may wake it) and neither verified: now "may not be able to" (1798232); a
  rebuild keeps a Mac by name, not by interface, so a working cable session back from a short trip
  could move to Wi-Fi and back on its pong from before the trip: the stamp above, a model in
  `sleep.swift` (f39b875); "0.5.1 never does" ask for a stopped Desktop: it does, with the Mac's
  next window list (37ed3de); "both browsers" made again: the nearby one only while it runs
  (0e8a098). Its own runs agreed with the ones below and ran `sessionEnded`'s new branch live (a
  TLS stand-in that never sends a window list: dials at +0, 7.2, 17.2, 37.3, 67.4 s; main's build
  dialled about every 6 s).
- Verified (the plan's Results): on a private simulator against `SillHost --synthetic --pairing` as a
  `_silltest._tcp` row, the host stopped for 20 s: main's build dialled at +0 and +6.3 s after the
  loss and then nothing for the minute after the host came back; this branch dialled at +0, 5.3, 15.3
  and 35.3 s and the session came back without a tap. Stopped for 300 s: 12 dials at the rule's times,
  the quiet line at +20.5 s, "Stopped trying…" at +281.8 s and no dial after it; back from the
  background, a dial at once and the session in 40 ms. `-SillBrowserFail 3`: made again 1.05, 2.12 and
  4.21 s after each failure, the row listed throughout. The Desktop: asked for again 10 ms after a
  stand-in Mac said nothing streams. Photos of `asleep` at the Duo's four sizes and 744×1133, default
  and accessibility-extra-large; `homerows` pixel for pixel main's. After the review's fixes: four
  trips to the background (2.3, 2.3, 2.3, 15 s) on a private simulator, the browser made again each
  time, settled 3.05 to 3.13 s later, one host connection throughout; `Tests/checks/policy` 446 cases
  (models of a host stopped, a sleep proxy, a new listing, the background and a cable session across a
  rebuild) and 158 of 158 mutants (28 new); `home-device` 182, `home-model` 62, `remote-rules` 123,
  their mutant patterns as on main; `run-all.sh`, all 40; iOS Debug for the simulator (CI's command),
  Release for the simulator and Debug for a device, only the known `StreamClient` capture warning;
  `swift build -c release`, only the CaptureProbe one; CI green on 0e8a098.
- **Untested, for Noah:** the real overnight case on the iPad mini (Sill left streaming or on the
  connect screen for hours, the iPad locked; back: the console's "browser: rebuilt the network
  browser (back from the background)", the Mac's row as it is now, and the session back by itself if
  the Mac is awake with Sill open); a Mac asleep behind an Apple TV or HomePod (`dns-sd -B
  _sleep-proxy._udp` lists one; the Mac's "Wake for network access" on): the row stays, dials every
  5, 10, 20, 30 s, the quiet line, and whether a dial wakes the Mac and connects, which settles the
  support page's words (the plan's §4 has them for a yes); R6, whether macOS stops a capture when the
  display sleeps or the Mac locks (Sill.app streaming the Desktop, then `pmset displaysleepnow` or
  ⌃⌘Q: whether Sill.log says "Capture stopped: …", and whether the picture comes back by itself once
  the Mac is woken and unlocked: this build asks at once, 0.5.1 with the Mac's next window list); the
  nearby browser made again (Direct Wireless on, the iPad on the iPhone's hotspot, Sill sent to the
  background and back: the console's "browser: rebuilt the nearby browser (back from the
  background)", the Direct row kept), which no headless run here could do without turning on this
  Mac's AWDL; a session over the USB cable across a short trip to the background (streaming over the
  cable, Sill sent away for 2 s and back: no "path: the cable went away" on the console, no second
  "Client connected" in Sill.log), which no test host on loopback can show.
