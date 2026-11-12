**The session follows the best path (2026-09-25, branch `follow-best-path` from
main at 76366e8, after PRs #9 and #10).** Noah's tests: plugging the cable in
left a Wi-Fi session on Wi-Fi until he reconnected (a TCP connection keeps its
interface), and pulling it hung the session a while, then the connect screen,
then Wi-Fi. A live session now follows the best path its Mac is reachable on,
the cable over Wi-Fi over Direct (`DiscoveryPolicy.pathPlan`, pure;
`StreamClient.followBestPath`), by the move from AWDL's make-before-break
hand-over (the new connection's first window list must carry the same
`launchID`). Up: once the network browser has listed the session's Mac on a
wired interface for 2 s (`cableSettle`, counted again after a move off it),
the Mac is dialled on it beside the Wi-Fi session (the wired dial; not ready in
2.5 s, or waiting or failing, and the session stays on Wi-Fi) and handed over
with the fence, and the readout says Wired. Down: when the cable's path is
gone (iOS says so: the connection not viable, back to waiting, or a path
update that is not satisfied and names the Mac's address; or the browser has
dropped the cable and either an unsatisfied update names only the service or
no pong has come back for 1 s, `pongSilence`), the Mac is dialled at once on
the Wi-Fi interface it is listed on, or was within 5 s (`wifiFresh`; the row as
listed after 2.5 s), what the device sends waits meanwhile
(`SessionLink.hold`) and goes out first on the new connection with no fence
(`adopt`), and the old connection is force-cancelled so nothing of it lands
late; a path that comes back calls the move off (`unhold`). A connection
already dead over the cable is made again at once (`reconnectNow`): over the
cable when the browser still lists it and iOS said nothing of its path (the
Mac closed it), as a tap on its Wired row dials it (the row as listed after
2.5 s), else over Wi-Fi the same way; the stream screen stays, no retry timer,
and if the Mac stopped the stream meanwhile (zero devices) the new
connection's first list picks the source again (the Desktop for a window that
went). Never Wi-Fi to Wi-Fi, never off a working cable (a browser blink alone
never moves it: its pongs keep coming), never off a Direct session but to the
network, at most one move per 5 s each way (`pathHysteresis`; up, 10, 20, 40,
then 60 s after moves to the cable that did not complete, `upWait`, and never
again to a listing of the cable that reached another Mac or launch until it is
listed afresh); with no Wi-Fi to go to, the ordinary end and reconnect.
DEBUG console: "path: the cable appeared: moving the session to anpi0", "path:
the cable went away: moving to Wi-Fi on en0", "path: the cable went away with
the connection: reconnecting over Wi-Fi on en0 now", "path: kept: …", and what
iOS said ("path: the session's connection is not viable…", "path: iOS says the
session's path is unsatisfied…"); `-SillPathTest` drives it in the simulator
(ContentView's contract). Verified: the policy check at 253 (187 plus 66: the
plan at every boundary, a 20,480-case grid, a model of plugs, pulls, blinks,
silence and a loose cable), 48 of 48 mutants caught (25 plus 23); the fence
check's eight modes (new: hold, holdclosed, unhold, adoptfence), six mutants of
the new SessionLink code caught; in the simulator against `SillHost
--synthetic`, dialling this Mac's own `fe80::…%en0` ("Wi-Fi") and
`fe80::…%en14` (the USB cable to the iPad, "Wired"): the cable listed at 3 s,
moved about 2 s later with the fence down in 1–2 ms; the path reported gone,
on Wi-Fi 10–20 ms later without a fence; the connection cut, carried on over
Wi-Fi in 10–20 ms with no connect screen and the Desktop picked again; the
cable dropped with pongs silent, moved at the 1 s mark, with pongs flowing,
kept; a loose cable moved up at 3.7, 8.9, 13.9 s and down at 4.6, 9.6, 14.6 s;
no Wi-Fi, the ordinary end; the move from AWDL and PR #10's wired-dial
fallbacks unchanged. **Untested, for Noah:** the real plug and pull on the
iPad while streaming. Plugged in: a few seconds later "path: the cable
appeared", the readout's Wired, and the host's "Client connected: …%anri0" (or
`%en14`) then "Client left" for the Wi-Fi one. Pulled: within about a second
the readout's Wi-Fi with no connect screen and the host's "Client connected"
over Wi-Fi (`%en0`, or the iPad's Wi-Fi IPv4 address; the cable's connection
leaves by itself, at the latest by eviction 4 s on); and which signal iOS gave
first (the console's "path:" lines), since a pull's own signals have never
been seen on a device. And on the cable, another app for over 4 s (the Mac
evicts the suspended iPad), then back to Sill: "path: the connection went
away, the cable did not", the host's "Client connected" over the cable again,
and no hop to Wi-Fi.

Review fixes (2026-09-25). A connection over the cable that dies while the
browser still lists the cable and iOS said nothing of its path was closed by
the Mac (it evicts a device that stops reading, an iPad suspended in the
background for 4 s): it is made again over the cable, where before it went to
Wi-Fi and came back to the cable 2 s later. A move to the cable could land
while the move from AWDL's fence was still up (that move can take 7.5 s, and
the next move up counts from its start), and its hand-over replaced the first
fence: what the first fence held was lost (a release sent then left the
button down), its AWDL connection was never closed, and `hold` was refused
while a fence stood. `SessionLink` now keeps a list of fences and a hold apart
from them: what waits goes out only once no fence and no hold stands, a hold
taken during a fence outlasts it (a cable pulled right after a move landed on
it), and each old connection is handed back for closing only once what waited
has gone out, its viewport first (`Released.close`), so the Mac never counts
only devices without one. A move up keeps its fence even when iOS has said
the old connection's path is gone (a report can pass; the 3 s timeout covers
a dead path), and a connection ready again after waiting clears `waiting` and
starts no second read loop. A listing of the cable that reached another Mac
or launch is not tried again while it lasts (`refusedCable`), and moves up
that do not complete wait 10, 20, 40, then 60 s (`upWait`), where before they
went every 5 s for as long as the cable stayed in. `-SillPathTest` gained
`close` (the connection closed, the row as it is) and `direct` (the session
counts as one over AWDL). Verified: the policy check at 277 (the 253, whose
grid now also spans refused listings and failed moves up, plus 24: the
reconnect over the cable, the refused listing, `upWait`, models of an
eviction on the cable and of moves up failing each way), 61 of 61 mutants
caught (48 plus 13); the fence check's twelve modes (new: twofences,
twomoves, holdfence, holdadopt; the `SessionLink` before the fixes fails
three: 27 inputs lost with 41 inversions, and two holds refused), 16 of 16
mutants of the new code caught; iOS Debug for the simulator and the iPad
(build only) and Release for the simulator, only the old `StreamClient`
warning; in a simulator of its own (another agent's UI tests had the shared
one) against `SillHost --synthetic`: the connection closed over the cable,
reconnected over the cable in 10 ms with no Wi-Fi hop; the cable's dial never
answering, on Wi-Fi 2.5 s later, then moves up 5, 15 and 35 s after, each
given up; a cable that connects but sends no list, and one refused at once,
the same back-off; a cable that reaches another launch, one try, and one more
once listed afresh; behind delay proxies (2 s and 3.5 s each way), the move to
the cable landing 1.5 s before the move from "AWDL"'s fence was down, the two
fences down by their timeouts, then everything that waited out on the cable
and both old connections closed; the earlier scenarios unchanged.
