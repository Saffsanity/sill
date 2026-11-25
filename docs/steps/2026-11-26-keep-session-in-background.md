**A trip to the background keeps the session, and a reconnect goes back to what was showing (2026-11-26, branch `keep-session-in-background` from main at 22ab5a3; supersedes #152's approach on today's main).**

What: going to the Home Screen on an iPhone, or to another Space on an iPad, ended the session: iOS
suspended Sill at once, the Mac let the silent device go (4 s at home, 8 s away), and on the return the
automatic reconnect connected again but started on the Desktop, so the person picked their window again,
which read as starting over. Picture in Picture keeps Sill running, but is not what a person wants for a
short trip away.

Device code only (`iOSClient/StreamClient.swift`, `StreamClient+Remote.swift`); no wire change.
- `backgroundGrace`: as Sill goes to the background with a session (and without Picture in Picture
  keeping it running), the time iOS grants is asked for (`beginBackgroundTask`), so the connection, its
  pings and its reads go on and the Mac keeps the device. Ended on the return (willEnterForeground), at
  the session's end (`tearDown`), and when iOS's time runs out: the session then ends cleanly from this
  side through `endSessionInBackground` (#379's), whose reconnect waits for the return
  (`reconnectAtReturn`), so the Mac stops capturing at once and a remote dial never runs in the
  background.
- `watchedAtLoss`: what the session that ended (on its own, with a reconnect, or in the background)
  showed. The automatic reconnect's session sets it as `resumeSource` (`sessionConnected`), which the
  first window list picks again when nothing streams, the Desktop for a window that closed. A tap clears
  it (a tap starts afresh), as does a session that ends with no reconnect.

Verified: `xcodebuild -scheme Sill -destination 'generic/platform=iOS Simulator'` builds.
Untested for Noah: on a device, a trip to the Home Screen of a few seconds and of longer than iOS's time
(about 30 s), at home and away; an iPad's Space switch and Stage Manager; Picture in Picture on (no
grace asked); a window closed on the Mac while away (the Desktop on the return); the picture's first
frames after the return (KeyframeRecovery asks for a keyframe as the picture comes back).
