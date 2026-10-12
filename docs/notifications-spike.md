# Spike: forwarding the host's notifications and Dock bounces to Sill Viewer

Feasibility only. Nothing here is in Sill; every probe was a throwaway outside the repository and has
been removed. Measured on macOS 27.0.1 (26A434), one Mac, Accessibility granted to the process that ran
the probes (Sill.app has the same permission), 2026-10-12.

The question: can the host (Sill.app) learn when an app shows a notification or bounces its Dock icon,
so Sill Viewer (and the Dock icon helper it makes per remote app, `SillDockProxy`) can show it on the
viewing Mac?

## Answer

| | Verdict |
|---|---|
| Notification banners (app, title, body) | **Works** through Accessibility on `com.apple.notificationcenterui`, about 120 ms after the post, no extra permission beyond the Accessibility the host already has. Only banners that are shown: a passive or Focus-silenced notification is invisible. |
| Dock bounces | **No signal found.** Nothing public and nothing through Accessibility. |
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

- **AX notifications on the Dock process:** of 48 names, `AXObserverAddNotification` accepted only 4:
  `AXCreated`, `AXUIElementDestroyed`, `AXFocusedUIElementChanged` and `AXSelectedChildrenChanged`
  (the other 44 returned `kAXErrorNotificationUnsupported`, -25207). While an app launched and quit, the
  Dock fired `AXCreated` and `AXUIElementDestroyed` for its item and nothing else.
- **A bounce fired nothing.** I could not get a visible bounce from my own probe: `requestUserAttention`
  returned request id 0 (the call's "not made" value) for both informational and critical requests,
  with the app inactive, hidden or launched in the background, so this spike adds no bounce
  measurement of its own. The known result stands: a Dock item's attributes do not change during a bounce
  (an earlier throwaway that did bounce showed only `AXParent`'s pointer differing).
- **Other public signals:** a wildcard (`nil` name) `DistributedNotificationCenter` observer received
  nothing at all on this macOS, even for a notification I posted myself; a named observer for the same
  post worked. So there is no sniffing distributed notifications; only known names work, and I know of
  none for attention requests. The unified log for the Dock, the posting app and WindowServer had no line
  about a request during the attempts.
- **Nearest substitutes that exist today:** the Dock badge (`AXStatusLabel`, already forwarded) and
  banners. Together they cover most of what a bounce means (something new needs attention); the bounce
  alone for an app that shows neither is not readable.

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
3. **Do not build bounce forwarding.** There is no signal to read. If a stand-in is wanted, forward a
   Dock badge increase (already read) as a "needs attention" hint on the helper's Dock icon.
4. **Still to test before building** (needs the user or a second Mac): alert-style (persistent)
   notifications; a Focus on; the frontmost-app banner I could not see; a real pointer click and a click
   on a helper that has quit; the banner icon; behaviour on macOS 14 to 26; and the cost of the tree read
   with many windows open.
