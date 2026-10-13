# Spike: forwarding the host's notifications and Dock bounces to Sill Viewer

Feasibility, and two small pieces built on it (the last section). Every probe was a throwaway outside
the repository and has been removed. Measured on macOS 27.0.1 (26A434), Accessibility granted to the
process that ran the probes (Sill.app has the same permission), 2026-10-12; the Dock bounce again on
2026-10-13, also on a second Mac (macOS 27.0).

The question: can the host (Sill.app) learn when an app shows a notification or bounces its Dock icon,
so Sill Viewer (and the Dock icon helper it makes per remote app, `SillDockProxy`) can show it on the
viewing Mac?

## Answer

| | Verdict |
|---|---|
| Notification banners (app, title, body) | **Works** through Accessibility on `com.apple.notificationcenterui`, about 120 ms after the post, no extra permission beyond the Accessibility the host already has. Only banners that are shown: a passive or Focus-silenced notification is invisible. |
| Dock bounces | **Works** through LaunchServices: the bouncing app's information carries `LSWantsAttention` 1 while it asks for attention. Read with two private (exported) LaunchServices calls, no permission at all. Nothing public, nothing through Accessibility. |
| Showing it on the viewer under the remote app's name and icon | **Works** with an ad hoc signed copy of the helper, one permission prompt per copy (per bundle ID). A click reaches the copy. |

Recommendation at the end.

## 1. Notification Center banners through Accessibility

Setup: an `AXObserver` on the `com.apple.notificationcenterui` process with every notification name I
could find (48 names; all 48 accepted), plus a second probe that re-read the whole tree every 100 ms, while
a throwaway app (ad hoc signed, its own bundle ID) posted `UNUserNotification`s.

What a banner looks like in the tree:

```
AXWindow  Subrole=AXSystemDialog  Title="Notification Center"
  ...
    AXGroup  Subrole=AXNotificationCenterBanner  Identifier=<UUID>
             Description="<app name>, <title>, <subtitle>, <body>"
      AXStaticText  Identifier=title  Value=<title>
      AXStaticText  Identifier=body   Value=<body>
```

- **Readable:** app name (display name, only in `Description`), title, subtitle, body. The group's
  `Identifier` is a UUID that stays the same across every event for that banner, so it is the dedupe key.
  There is no bundle ID in the tree: the app is known by its display name only (two apps with one name
  are indistinguishable; the icon is not exposed).
- **Latency:** post to `AXCreated` of the Notification Center window 120–125 ms (three runs: 124, 123,
  120). The banner's contents were already in the tree when that first event fired, so one tree read in
  the handler is enough. `AXWindowCreated` follows 28–50 ms later; `AXLayoutChanged` fires several
  times after.
- **A second banner while one is up** does not create a window: it arrives as `AXLayoutChanged` on the
  existing window, 0.6 s and 1.1 s after the posts in a run that posted every 0.5 s (the stacking
  animation). So the handler must walk the tree on layout changes too, not only on window creation.
- **Grouped** (three notifications with one `threadIdentifier`): three separate banners, each with its own
  UUID and text. Grouping affects the Notification Center list, not the banners, so nothing changes for
  a reader.
- **Time-sensitive** (`interruptionLevel = .timeSensitive`): shown as a banner, read the same way.
- **Passive** (`.passive`): no banner, zero Accessibility events, nothing in the tree. The notification
  went straight to the list. A **Focus-silenced** notification is delivered the same way (not tested:
  it needs the user to switch a Focus on), so expect it to be invisible to this method.
- **Persistent (alert-style) notifications:** *not tested.* The style is a per-app user setting in System
  Settings; I did not change system settings. The tree has a distinct `AXNotificationCenterAlert` subrole,
  which is what the permission prompt itself used (its group carried the prompt's text as `title` and
  `body` static texts, readable 51 ms after creation), so the reading code would need to accept both
  subroles. How an alert is dismissed, and whether it repeats on a re-post, is open.
- **One case I could not explain:** in the first run the posting app was frontmost when it posted and
  `usernoted` logged "Presenting … as banner", yet the observer saw nothing in 80 s. Every later run
  (app launched in the background) was seen. Whether Notification Center suppresses the banner for the
  frontmost app, or the tree does not show it, is open.
- **The tree is full of personal data.** The Notification Center process also hosts the widget panel, and
  its tree (232 lines at rest) lists a location, weather, tasks, calendar entries and device names. A
  reader must pick out banner groups by subrole and read nothing else, and must never log the tree.

### Fragile across macOS versions

- Everything above is undocumented: the process name, the `AXNotificationCenterBanner` and
  `AXNotificationCenterAlert` subroles, the `title` and `body` identifiers and the comma-joined
  `Description`. Tested on 27.0.1 only. Match on subrole and identifier, never on titles or
  descriptions (the Notification Center app's own title is localized: "Notification Centre" in en-GB).
- The `Description` join is ambiguous when a title or body contains a comma; read the `title` and
  `body` static texts instead and use `Description` only for the app name.
- Failure mode is silent: a macOS update that renames a subrole produces no events, not an error. The
  reader needs a self-test (post a known notification from Sill itself and expect to see it) and a way to
  say "notifications unavailable" in the menu.

## 2. Dock bounces

Measured again on 2026-10-13 (macOS 27.0.1, and 27.0 on a second Mac), after the first pass (below) found
nothing.

- **The first pass misread its own probe.** `requestUserAttention` returns a request ID counting from 0,
  so the 0 it got was the first request, not a refusal; -1 is the refusal, given while the app is the
  active one (AppKit checks that first and returns). A bundled, signed app launched with `open -g`
  bounces on its first call; no window and no earlier activation are needed. `.informationalRequest`
  bounces once (about 1 s), `.criticalRequest` until `cancelUserAttentionRequest` or the app is
  activated.
- **What the request is.** Stepped through in the probe's own process with lldb:
  `-[NSApplication requestUserAttention:]` calls HIServices' `_SetApplicationDesiresAttention` with the
  kind (100) and the app's LaunchServices ASN, which is one synchronous Mach message to the Dock
  (`dispatch_mach_send_and_wait_for_reply`). No distributed notification, no XPC, no WindowServer
  property, no CoreDock call. The Dock keeps the state in the app's LaunchServices information, which
  is updated by the time the call returns.
- **The signal: `LSWantsAttention`.** `_LSCopyRunningApplicationArray(-1)` lists the running apps'
  ASNs and `_LSCopyApplicationInformation(-1, asn, nil)` each one's information dictionary (both
  exported, found with `dlsym`). The key is absent until an app first asks, 1 while it asks, 0 after.
  Polled every 50 ms by a plain process with no Accessibility, Screen Recording or any other
  permission:
  - a critical request: 1 at once, 0 when cancelled about 3 s later (on the second Mac: 1 at 45.571,
    0 at 48.713);
  - an informational one: 1, then 0 about 1 s later (51.856, 52.838), the bounce's own length;
  - the app activated: 0 within about 65 ms.
  So a reader tells a one-time bounce from one that repeats until the user looks.
- **Session.** The calls read the caller's own login session: over ssh they list nothing, and
  `launchctl asuser` is refused without root. Sill.app runs in the user's session, so it reads what the
  Dock does.
- **Cost and fragility.** Polling every app's dictionary costs tens of microseconds a sample; a push
  exists (`LSApplicationWorkspace addObserver:`, private and undocumented) but was not tried. The two
  calls and the key are private and undocumented (fine outside the App Store, which Sill.app is), and
  a rename would fail silently, as banner reading would: a self-test (Sill bounces a helper of its own
  and expects to read it) covers it the same way.
- **Not used:** `_GetApplicationDesiresAttention` reads the same state but is not exported. Nothing
  changes in the Dock's Accessibility tree during a bounce (its geometry included: the bounce is drawn
  by the render server), and no `NSWorkspace` notification, `NSRunningApplication` property or
  distributed notification carries it.
- **Not yet tried with a real app's bounce** on the host (the probes were small AppKit apps); every
  AppKit app, Electron's `app.dock.bounce` included, goes through the same call.

### The first pass (2026-10-12), for the record

The Dock's Accessibility notifications (only 4 of 48 accepted), a wildcard distributed notification
observer and the unified log showed nothing, and the probe's request ID 0 was taken for a failure.

## 3. Viewer side: posting under the remote app's name

Setup: a second throwaway app made as the real helper copies are: bundle ID per app, display name = the
remote app's name, a badged-style `AppIcon.icns` in Resources, ad hoc signed, living under
`~/Library/Application Support` (the folder Sill Viewer keeps its copies in).

- **Works:** `UNUserNotificationCenter` posting from the ad hoc copy produced a banner whose
  `Description` began with the copy's name ("Remote Probe App, …"), with the text sent by the host.
  (The banner's icon was not photographed; Notification Center takes it from the app bundle, which the
  helper already writes the badged icon into. A badge change after the copy is made is not reflected in
  the banner icon until the bundle's icon is rewritten.)
- **Where the copy lives matters.** The same ad hoc app in a scratch folder under the system temporary
  directory was rejected by `usernoted` ("Failed to find or validate client of identifier …") and
  `requestAuthorization` failed at once with "Notifications are not allowed", no prompt, even after
  `lsregister -f -R -trusted`. Moved to `~/Library/Application Support` it validated at once. The helper
  copies are already there, but a copy made anywhere else would silently never notify.
- **Permission prompt, per copy.** Each distinct bundle ID raised its own prompt the first time it asked
  (three IDs, three prompts). The prompt is a Notification Center banner, not a modal alert: it goes away
  by itself, and a prompt left unanswered (I quit the app while it was showing) was recorded as denied:
  the next launch found status 1 (denied) and showed no prompt. Once denied, only the user in System
  Settings › Notifications can fix it. Consequences: one prompt per remote app, so ask lazily (when that
  app's first notification arrives, never for every app at launch), and tell the user in Sill Viewer
  what the prompt is for; keep a bundle ID stable (`<viewer prefix>.dock.<slug>` as now) or the user is
  asked again.
- **A click reaches the copy.** I performed `AXPress` on the banner (no pointer input): the copy's
  `userNotificationCenter(_:didReceive:)` ran 2 ms later with the default action identifier and the
  `userInfo` I had attached, so a window ID or app ID in `userInfo` gets to the helper, which can post its
  existing "focus" ask to Sill Viewer. A real pointer click was not tried, and neither was a click when
  the copy has quit (macOS documents relaunching the app for the response). The copy only runs while
  Sill Viewer has a window of that app, so for an app with no window here the viewer must launch the
  helper first or post the notification itself.
- The banner also offers Show Details and Close; the delegate gets no callback for Close.

## Privacy notes

- **Notification text is content from the host Mac's user.** Message previews, one-time codes, calendar
  and mail subjects. Forwarding it moves it across the paired TLS session (encrypted and
  pinned) to every viewer connected, then into the viewing Mac's Notification Center, which keeps a
  history there and obeys that Mac's Focus and lock screen settings, not the host's. Viewers see a
  notification the host user may have meant to keep to their own screen.
- **Opt-in, per app, off by default;** Settings on the host, with an allow list by app name. Not a toggle
  per viewer only: the host owner decides what leaves the host. Lock-screen and "show previews" rules
  of the host are not visible to the reader, so treat text as always preview-visible.
- **Do not log it.** Sill.log and the app's log window must never hold a title or body (they are
  copied into bug reports); log counts and app names only. No persistence on the host.
- **Read as little as possible.** Banner groups only (see above: the same tree holds widget data); cap
  lengths and pass text through the existing `SafeText` before it is sent; never forward the
  permission prompts of unrelated apps.
- **Forged notifications:** any app on the host can post text that looks like another app's, because the
  tree carries only the display name. A viewer should show the app name the host reported and not
  trust it for decisions; nothing in a notification may ever trigger an action on the viewer other than
  bringing that app's window forward.
- **No Full Disk Access** is needed or wanted for this route; it exists only to avoid reading the
  notification database.

## Recommendation

1. **Build banner forwarding, opt-in.** It works on the one macOS tested, needs no new permission on the
   host (Sill.app already has Accessibility), and is cheap: an observer on one process, a tree read on
   `AXWindowCreated` and `AXLayoutChanged`, dedupe by banner UUID. Gate it with a self-test and a visible
   "unavailable" state, because breakage will be silent after an OS update. Add a wire field gated by a
   window-list flag like the others (a new kind, additive), and accept that passive, Focus-silenced and
   frontmost-app notifications will not come through. Say so in the setting's footnote.
2. **Post on the viewer from the existing per-app helper copy,** asking for permission lazily, per app, at
   the first notification, with a clear in-app explanation; for an app with no helper running, have
   Sill Viewer launch it, with a fallback of Sill Viewer posting under its own name. Put the remote
   window or app ID in `userInfo` and bring the app's windows forward on a click.
3. **Build bounce forwarding** on `LSWantsAttention`: the host polls it (every 250 ms is enough) for the
   apps whose windows a Mac viewer shows, sends informational or critical (a window-list field, gated
   like `badges`), and the app's Dock icon here makes the same request and cancels it when the host's
   flag clears. Until then, a badge that rises bounces the icon once (built, below).
4. **Still to test before building** (needs the user or a second Mac): alert-style (persistent)
   notifications; a Focus on; the frontmost-app banner I could not see; a real pointer click and a click
   on a helper that has quit; the banner icon; behaviour on macOS 14 to 26; and the cost of the tree read
   with many windows open.

## Built in this branch

- **Badges in Sill Viewer's menu.** Each app in the menu bar icon's menu carries its Dock badge from the
  other Mac (`NSMenuItemBadge`: a count, or the label as it is). Seen live with two real apps' badges
  and a test app counting up every 15 s.
- **A rising badge bounces the app's Dock icon here once.** `SillDockProxy` makes an informational request
  when a count grows or a badge appears; not for the first state it hears, nor for a badge that falls or
  goes. Seen with the test app: its helper's `LSWantsAttention` went 1, then 0 about 1 s later, at each
  of three rises 14–16 s apart.

