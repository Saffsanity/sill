# Sill on the App Store: metadata and review material

Everything App Store Connect asks for the iOS app, in the order it asks, ready
to paste, and what App Review needs to try it: the review notes, the demo video
and the screenshots. Only the iOS app (bundle ID `me.saffer.sill`) goes through
App Store Connect. Sill for Mac ships outside it, as a Developer ID download.

Every text block below was measured against its limit (see "Checked for this
file" at the end). Paste blocks keep their line breaks.

## Values this file assumes

Noah confirmed the site and the contact address on 2026-09-25; Remote Access
in 1.0 is still his call. The paste blocks below repeat them literally, and
the command under the table changes every copy in this file.

| What | Value | Status |
|---|---|---|
| Site | `https://getsill.app` | Noah's (bought 2026-09-25); the site is live. |
| Support URL | `https://getsill.app/support` | The page is `site/support.html`, which gives the contact address. The same link as `SillLinks.support` in the app (guideline 1.5). |
| Privacy Policy URL | `https://getsill.app/privacy` | `site/privacy.html`; the same link as `SillLinks.privacy` in the app. |
| Mac download | `https://getsill.app/download` | `site/download.html`; the same link as `SillLinks.download` in the app. |
| Contact address | `support@getsill.app` | Noah's: Cloudflare Email Routing forwards it to his mailbox (2026-09-25). |
| Mac requirement | Apple silicon, macOS 14 or later | Today's Sill.app is arm64 only; `LSMinimumSystemVersion` is 14.0. If the release build becomes universal, take "with Apple silicon" out of the description and the review notes. |
| App Store Connect record | "Sill – Mac Streaming", Apple ID 6816359860, SKU `sill-ios` | Created 2026-09-26 (section 1). Build 0.5 (1), from b37f47a, is on TestFlight for internal testers. |
| Remote Access in 1.0 | Undecided: main has it since ba91136 (PR #13) | Noah decides, before anything is pasted, whether 1.0 keeps it or ships without it (the audit's advice, given before it merged). |

To change the domain or the contact address in this file, with both values
filled in (the address first: the domain's expression would change it too):

```sh
sed -i '' -e 's#support@getsill\.app#THE.REAL.ADDRESS#g' -e 's#getsill\.app#NEW.DOMAIN#g' docs/app-store-metadata.md
```

The app's own copy of the site and of the download, support and privacy links
is `iOSClient/SillLinks.swift`.

**Remote Access switch.** The blocks below describe a 1.0 that includes Remote
Access (PR #13, on main since ba91136). Guideline 2.3.1(a) forbids describing
what the build lacks, so if 1.0 ships without it, make every one of these cuts:

| Where | Cut |
|---|---|
| Description | Delete the bullet that starts "Away from home". |
| Keywords | Use the local-only line. |
| Review notes | Delete from `REMOTE ACCESS` to the end (the local-only size is given). |
| What's New | Use the local-only line. |
| Demo video | Skip shot 11. |
| Site | Delete every block marked `<!-- Remote Access`. Step 3 of the release checklist has the check. |
| Export compliance | Nothing changes: the key stays NO either way. |

## Before you submit

These texts are only true once these are:

- The paste blocks match the build. Main has had Remote Access since
  ba91136; the audit, before that, advised a 1.0 without it. For a build
  without it, make every cut in the Remote Access switch above, the site's
  included.
- The support, privacy and download URLs load in a private window, signed out.
  The support page shows a way to reach you (guideline 1.5).
- Sill for Mac at the download URL is Developer ID signed, notarized and
  stapled, and opens on a Mac that never had it.
- The build carries `PrivacyInfo.xcprivacy` and the export compliance key
  (section 6).
- The version record's Version is the build's: the first App Store version
  is 0.5 (Noah, 2026-09-26; `MARKETING_VERSION` in both configurations of
  the Sill target since PR #19). App Store Connect names a new app's first
  version 1.0, and only a build whose version matches can be added to it, so
  set the record's Version to 0.5 (section 5).
- Every claim in the description has been seen working on a device. Still
  open: the menus (PR #36's P1 to P13: the Menus button, the iPad's menu bar
  on iPadOS 26), the Mac's pointer on the device (PR #31's P1 to P12), the
  first-run tour (PR #35's P1 to P16), the USB cable on an iPhone (verified
  on the iPad mini only; if it fails, write "a USB cable (iPad)"), Apple
  Pencil hover, and 120 frames per second, which no device has shown yet (the
  iPad mini is 60 Hz). For that one, stream a moving window, then the whole
  desktop, to a ProMotion iPhone or iPad. Sill.app's log should say
  "Streaming … 120 fps", and its `client …` lines for the device, or the
  device's row in the Sill menu, should stay near 120 fps. If they don't,
  delete the bullet "Up to 120 frames per second…". If 120 holds only for
  some sources, say which in the bullet.
- The screenshots come from the build you submit.

The app record (section 1) exists since 2026-09-26: "Sill" was taken, so it
holds "Sill – Mac Streaming".

## 1. New app record

Apps › + › New App:

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Sill – Mac Streaming` (Noah’s pick on 2026-09-26; "Sill" was taken in App Store Connect; section 2) |
| Primary Language | English (U.S.) |
| Bundle ID | `me.saffer.sill` (Xcode's automatic signing on team 9B2KKVM937 should have registered it; if the menu lacks it, add it under Certificates, Identifiers & Profiles. It can't change after the first upload.) |
| SKU | `sill-ios` (never shown; can't change) |
| User Access | Full Access |

## 2. App Information

### Name

```text
Sill
```

No live app is called exactly Sill (the audit searched the App Store on
2026-09-25; the closest is "Sill Notes", released 2026-09-15), but a name held
by an unreleased app record doesn't show in search. If App Store Connect
refuses it, use this (2 to 30 characters, no Apple product name in the name
itself):

```text
Sill – Mac Streaming
```

(Noah chose "Sill – Mac Streaming" on 2026-09-26; "Sill – Window Streaming" was the
fallback this file first proposed.)

The dash is an en dash (U+2013). The Home Screen label stays "Sill" whatever
the store name is (`CFBundleDisplayName`). Keep other apps' names, Sidecar
included, out of the name, the subtitle and the keywords (2.3.7), and keep
"Windows" out of the name: in a remote display app it reads as Microsoft's
(5.2.1).

### Subtitle (30 characters at most)

```text
Remote display for your Mac
```

### Category

- Primary: Utilities
- Secondary: Productivity

### Content Rights

"Does your app contain, show, or access third-party content?" **No.** Sill
ships no third-party content. What it shows is the user's own Mac, drawn by
apps the user runs there. ("Yes, and I have the rights" would also be
defensible; don't change the answer later without a reason.)

### Age rating

App Information › Age Ratings › Set Up Age Ratings. Every answer is none, which
gives **4+**:

| Step | Item | Answer |
|---|---|---|
| In-App Controls | Parental Controls, Age Assurance | Leave unchecked |
| Capabilities | Unrestricted Web Access | Leave unchecked (see below) |
| Capabilities | User-Generated Content, Social Media, Messaging and Chat, Advertising | Leave unchecked |
| Mature Themes | Profanity or Crude Humor, Horror/Fear Themes, Alcohol, Tobacco, or Drug Use or References | None |
| Medical or Wellness | Medical or Treatment Information, Health or Wellness Topics | None |
| Sexuality or Nudity | Mature or Suggestive Themes, Sexual Content or Nudity, Graphic Sexual Content and Nudity | None |
| Violence | Cartoon or Fantasy Violence, Realistic Violence, Prolonged Graphic or Sadistic Realistic Violence, Guns or Other Weapons | None |
| Chance-Based Activities | Gambling, Simulated Gambling, Contests, Loot Boxes | None (No) |
| Age Categories and Override | | Not Applicable |
| Age Suitability URL | | Leave empty |

Unrestricted Web Access: Sill has no browser of its own. It shows the user's
own Mac, and a browser there is the Mac's app. That is how the category
answers: Jump Desktop, RealVNC Viewer, Screens 5, AnyDesk, TeamViewer, Windows
App and Mirage were all 4+ on 2026-09-25. Checking the box would make Sill 16+.
Either passes review; pick one and keep it across updates.

### EU Digital Services Act (trader status)

Business › Agreements › Compliance › Digital Services Act › Complete Compliance
Requirements (Account Holder or Admin). Every developer declares a status, even
one who skips the EU, and Apple can't decide it for you.

- For 1.0 (free, no in-app purchase, no ads), "This is not a trader account"
  is defensible. Apple's own example of a likely non-trader is a hobbyist who
  made the app with no intent to commercialize it. EU customers are then told
  that EU consumer rights don't apply to contracts with you.
- Look again when the tip jar arrives. Revenue from in-app purchases is the
  first factor Apple lists. A trader's address or P.O. box, phone number and
  email are verified and shown on EU product pages, so set up a P.O. box and a
  project address (the support address) before switching.
- Not legal advice. The factors are on Apple's "Manage European Union Digital
  Services Act trader requirements" page.

## 3. Pricing and Availability

- Price: Free.
- Availability: all countries and regions. The export compliance answer needs
  no French declaration (section 6).
- iPhone and iPad Apps on Apple Silicon Mac: **uncheck** "Make this app
  available". Otherwise the iPad app shows up in the Mac App Store, where
  people look for Sill for Mac, and on a Mac it would only stream that Mac to
  itself.
- iPhone and iPad Apps on Apple Vision Pro: **uncheck** "Make this app
  available on Apple Vision Pro". Nobody has tried it there.

## 4. App Privacy

- Privacy Policy URL: `https://getsill.app/privacy`
- User Privacy Choices URL: leave empty.
- Get Started › "No, we do not collect data from this app" › Save › Publish.
  The product page then says **Data Not Collected**.

Why that is the right answer. Apple: "'Collect' refers to transmitting data off
the device in a way that allows you and/or your third-party partners to access
it for a period longer than what is necessary to service the transmitted
request in real time." Sill sends data only to the user's own Mac, which the
developer can't reach:

- Once a second, a stats report: frame rate, frame age, round trip, and the
  device's name and model, for example `iPad (iPad14,1)`. iOS gives apps a
  generic name ("iPad"), so the model is what tells devices apart. It goes to
  the Mac the device is connected to, which shows it in its menu and writes it
  in its own log on that Mac (`~/Library/Logs/Sill`).
- Taps, pointer moves, scrolls, keys, typed text, the menu items chosen and
  the panel size go to the same Mac. The Mac sends back the picture, window
  titles, thumbnails, app icons, its name, the menus of the app in use (their
  titles, and a menu's items when the device opens it) and where its own
  pointer is over the picture.
- Kept on the device only: each Mac's thumbnail order, the names of Macs
  seen with Direct Wireless Connection on, and which steps of the first-run
  tour were seen (or that it was skipped). With Remote Access: the device's
  key and the saved Macs' addresses (Keychain and app storage), and camera
  frames, which are read for the pairing code and never saved or sent.
- No analytics, crash reporting, ads, third-party SDKs or servers, and no
  tracking. The iOS app makes no request of its own to anything but the Mac:
  there is no `URLSession` and no web view in it or in StreamProtocol, on main
  or on the remote-access branch. Its web links (`SillLinks`) open in Safari.

Keep three things saying the same: this label, `PrivacyInfo.xcprivacy`
(tracking false, no collected data types) and the privacy policy page. Answer
again before adding crash reporting, analytics, a server of any kind, or
anything that sends data somewhere other than the user's Mac.

## 5. The first version (0.5)

### Promotional text (170 characters at most; editable any time without review)

```text
Free, with no account and no servers. Use any window on your Mac, or the whole desktop, from your iPhone or iPad with touch, a trackpad, a keyboard or Apple Pencil.
```

### Description (4,000 characters at most)

```text
Sill puts your Mac on your iPhone and iPad. Pick any window, or the whole desktop, and use it with touch, a trackpad, a keyboard or Apple Pencil. Your apps keep running on your Mac. Sill shows them and sends back what you do.

Sill needs the free Sill for Mac on the Mac you want to use. Get it at getsill.app. It runs on a Mac with Apple silicon and macOS 14 or later.

Get started
• Open Sill for Mac and allow Screen Recording and Accessibility.
• Open Sill on your iPhone or iPad. Your Mac shows up in the list. Tap it.
• Pick a window from the Apps list, or tap Desktop to see the whole screen.
• The first time, a short tour shows you the controls.

Made for touch
• Tap to click. Touch and hold to right-click. Drag to scroll.
• Apple Pencil works as a mouse, with hover on iPad models that support it.
• Hold your device upright for a laptop layout: the picture on top, a trackpad and a row of keys below.
• Type with the on-screen keyboard or a hardware keyboard. Shortcuts work too.
• Use the menus of the app you’re in: tap Menus in the bar, or on iPad with iPadOS 26 or later, use the menu bar at the top of the screen.
• Switch windows from live thumbnails in the bar. Touch and hold one to close, minimize or go full screen. Drag it to reorder.
• When the mouse moves on your Mac, its pointer shows on your iPhone or iPad too.
• Aa makes text larger or smaller.

Smooth and sharp
• Up to 120 frames per second on displays that support it.
• Set quality, resolution and frame rate from your iPhone or iPad.

Your Mac, your network
• Connect over Wi-Fi, or over a USB cable.
• Mac nearby but on another network? Turn on Direct Wireless Connection on the Mac and connect straight to it.
• Away from home, pair your device once and reach your Mac through your own VPN. Only paired devices can connect this way, and the connection is encrypted.
• While Sill for Mac is open, any iPhone or iPad with Sill on the same network can connect to it. Use it on networks you trust.

Private
• No account, no ads, no tracking.
• Sill has no servers and collects no data. The picture and what you type go between your devices and your Mac, and to no one else.

Good to know
• Sill shows one window, or the whole desktop, at a time.
• Sill doesn’t play sound from your Mac.
• Sill for Mac comes from getsill.app, not the Mac App Store.
```

Local-only build: delete the bullet that starts "Away from home".

Before the source is public with a LICENSE file, don't call Sill open source
anywhere in the listing (2.3.1(a)). Once it is, a line such as "Sill is free
and open source." can join "Private".

The bullet "While Sill for Mac is open, any iPhone or iPad with Sill on the same
network can connect to it" is true on main and on the remote-access branch,
whose home connection stays open to devices on the Mac's networks. It stays
until pairing covers the local network too. Leaving it out would make the
listing sound safer than the app is.

Apple's trademark rules keep its product names singular and never possessive
in public copy, here and on the site: "sound from your Mac" and "Mac computers
with Apple silicon", not "your Mac’s sound" or "Macs". The review notes aren't
public.

### Keywords (100 bytes at most, commas, no spaces)

```text
desktop,screen,window,streaming,mirror,control,access,trackpad,keyboard,pencil,wireless,usb,vpn
```

Local-only build:

```text
desktop,screen,window,streaming,mirror,control,access,trackpad,keyboard,pencil,wireless,usb,cable
```

The name, the subtitle and the developer name are already searchable, so
"Sill", "remote", "display" and "Mac" aren't repeated. No other app's or
company's name.

### Other version fields

| Field | Value |
|---|---|
| Support URL | `https://getsill.app/support` |
| Marketing URL (optional) | `https://getsill.app` |
| Version | 0.5 (App Store Connect proposes 1.0 for a new app; the build says 0.5) |
| Copyright | `2026 Noah Saffer` (App Store Connect adds the ©) |
| App Previews | None for the first version. They are optional, and the sizzle reel can't be one: 2.3.4 allows only captures of the app itself, and previews run 15 to 30 seconds. |
| Screenshots | Section 9 |
| Version Release | Manually release this version, so an approval can't go live before the Mac download and the site are up |
| Build | The Release archive with the privacy manifest and the export compliance key |

### What's New

App Store Connect doesn't show this field for an app's first version; it is
required from the second on. Use it as the pattern for a TestFlight build's
"What to Test", the site and 1.1. TestFlight asks for What to Test for every
build (the build › Test Details): for a later build, say what changed since
the build before, as the release notes do.

```text
The first version of Sill. Use any window on your Mac, or the whole desktop, on your iPhone or iPad, with touch, a trackpad, a keyboard or Apple Pencil. Connect over Wi-Fi or a USB cable, directly when you share no network, or through your own VPN once paired.
```

Local-only build:

```text
The first version of Sill. Use any window on your Mac, or the whole desktop, on your iPhone or iPad, with touch, a trackpad, a keyboard or Apple Pencil. Connect over Wi-Fi or a USB cable, or directly when you share no network.
```

## 6. Export compliance (encryption)

**The key is in the app.** `iOSClient/Info.plist` sets
`ITSAppUsesNonExemptEncryption` to NO (`<false/>`). That is correct with
Remote Access and without it. With the key, uploads skip the encryption
questions, TestFlight builds included. Don't also add the build setting
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` to the project: use one, not
both.

- The home connection uses no encryption. Both ends open plain TCP
  (`NWParameters(tls: nil, tcp: tcp)`, iOSClient/StreamClient.swift:870 and
  Sources/SillHost/StreamServer.swift:347), and the iOS app makes no HTTPS
  requests. Before Remote Access, the iOS app and StreamProtocol imported no
  CryptoKit, CommonCrypto or Security at all.
- Remote Access (PR #13, on main since ba91136) adds TLS 1.3 through
  Network.framework (`sec_protocol_options`,
  Sources/StreamProtocol/RemoteTLS.swift), P-256 keys and ECDSA signatures
  (Security, CryptoKit), and HMAC-SHA256 and PBKDF2 for the pairing code
  (CryptoKit, CommonCrypto). All of it is encryption within
  Apple's operating system. Apple's reference, "Export compliance
  documentation for encryption", lists "Your app uses encryption limited to
  that within the Apple operating system" as needing no documentation in App
  Store Connect. So the key stays NO.
- Without the key, App Store Connect asks "What type of encryption algorithms
  does your app implement?" The answer is "None of the algorithms mentioned
  above". The other choices are for proprietary algorithms, or standard ones
  the app implements itself instead of Apple's.
- Look again only if Sill ever ships its own cipher code or a third-party
  crypto library.
- Apple adds that an app with exempt encryption "might" need a year-end
  self-classification report to the U.S. government. BIS's rule of March 29,
  2021 dropped that report for mass-market end items such as application
  software (mass-market components still file it). That is about the Remote
  Access build only. Not legal advice.

## 7. App Review Information

| Field | Value |
|---|---|
| Sign-in required | Unchecked. There is no account. |
| Contact | Noah Saffer, a phone number starting with + and the country code, and an email you read (`support@getsill.app` or your own; App Review only) |
| Notes | The block below |
| Attachment | The demo video (section 8) |

### Notes (4,000 bytes at most)

Plain ASCII on purpose, so every character is one byte.

```text
WHAT SILL IS
Sill is a remote display for the user's own Mac. The iPhone and iPad app shows any window, or the whole desktop, of a Mac running the free Sill for Mac, and sends touch, trackpad, keyboard and Apple Pencil input back to it. Every app runs and draws on the Mac. The iOS app only shows the picture and sends input. Its Apps list shows only apps already installed on that Mac.

There is no account, no sign-in, no in-app purchase, no ads and no server. The app talks only to the user's own Mac, which it finds with Bonjour on the local network.

WHAT YOU NEED
- A Mac with Apple silicon and macOS 14 or later.
- An iPhone or iPad on the same Wi-Fi network as the Mac.
- Sill for Mac, free: https://getsill.app/download (Developer ID, notarized).

SET UP THE MAC (about 2 minutes)
1. Download Sill for Mac from the link above, move Sill to Applications and open it (click Open if macOS asks). It lives in the menu bar, with no Dock icon, and opens its Settings on Permissions.
2. Screen Recording (so Sill can show windows): click Allow..., turn on Sill in System Settings, then click Quit & Reopen when macOS offers it (or Relaunch Sill in Sill's Settings).
3. Accessibility (so the device can click and type): click Allow... and turn on Sill in System Settings.
4. If macOS asks whether Sill may find devices on your local network, click Allow.
The Permissions pane then says "You're all set."

CONNECT
5. Open Sill on the iPhone or iPad. Tap Allow when it asks for Local Network access.
6. The Mac appears under "Connect to a Mac" within a few seconds. Tap it. The Mac's desktop appears.

WHAT TO TRY
- The first time your Mac's picture shows, a short tour points out the controls. Take the Tour in Settings shows it again.
- Apps (magnifying glass): pick an open window, or search the list and open an app.
- Tap to click. Drag to scroll. Touch and hold to right-click. Apple Pencil works as a mouse.
- Keyboard: type into the window. A hardware keyboard works too, with shortcuts.
- Menus (in the bar; on iPad with iPadOS 26 or later also the menu bar at the top of the screen): the menus of the app on the Mac. Choose an item and the Mac does it.
- Move the mouse on the Mac: its pointer shows on the device too.
- Aa: touch and slide to change the text size.
- Window thumbnails in the bar: tap to switch. Touch and hold for the window's close, minimize and full screen buttons. Keep holding and drag to reorder.
- Desktop: the whole Mac screen.
- Hold the device upright (portrait): a laptop layout with a trackpad and a row of keys.
- Settings (gear, last in the bar): the Mac's Quality, Resolution and Frame Rate. The Sill menu on the Mac shows the same values. Disconnect is at the bottom.

IF THE MAC DOES NOT APPEAR
Some networks (guest, office, hotel) keep devices from seeing each other. Then either connect an iPad to the Mac with a USB-C cable (the Mac's row then says "Wired"), or turn on Direct Wireless Connection in the Sill menu on the Mac and tap Search Nearby on the device. That connects without a shared network.

VIDEO
The attached video, filmed with a camera, shows a Mac and an iPad together: setup, streaming, touch and keyboard input, and the Settings panel.

REMOTE ACCESS
On the Mac, choose Remote Access... in the Sill menu, turn on Remote Access and click Pair iPhone or iPad... A code appears. On the device, tap Add a Mac... on the connect screen and point the camera at the code (allow camera access when asked), or tap Enter Code Instead and type it. The camera only reads that code. After pairing, the device can reach the Mac from another network through the user's own VPN, for example the same VPN (such as Tailscale) on the Mac and the device. To try it, pair on the same network, then move the device to cellular or a hotspot with the VPN on. Only paired devices can connect this way, and the connection is encrypted. The attached video shows this too.
```

Local-only build: delete from `REMOTE ACCESS` to the end.

## 8. Demo video

App Review asks for "a video, not a screen recording" when an app needs
hardware they may not have. Sill needs a Mac, so film the Mac and the device
together with a camera:

- A phone on a tripod, landscape, 1080p. The Mac's screen and the device
  together in frame and readable. Close enough to read the Mac's menu bar.
- One continuous take per shot, trimmed only. No music, no effects. Short
  captions are fine.
- About 3 to 4 minutes. Export H.264 MP4 and attach it under App Review
  Information. Not the sizzle reel: it is simulator footage with title cards.
- Do Not Disturb on the Mac and the device. Nothing from the privacy list in
  section 9 on either screen, or on the desk.

| # | Shot | What must be visible |
|---|---|---|
| 1 | The Mac and an iPad side by side | Both screens on, Sill not yet installed |
| 2 | Download Sill for Mac from the download page, move it to Applications, open it | The page, the file, Sill opening its Settings on Permissions |
| 3 | Screen Recording: Allow…, the switch in System Settings, Quit & Reopen | The System Settings switch turning on |
| 4 | Accessibility: Allow…, the switch; the pane says "You're all set." | Both permissions allowed |
| 5 | Open Sill on the iPad, Allow Local Network, the Mac appears, tap it | The Mac found without typing anything; the Mac's desktop on the iPad |
| 6 | Apps, pick Notes (a note written for the shoot); then Menus, Format, and a style for a line | The same window on both screens; the style chosen on the iPad applied on the Mac |
| 7 | Touch: tap to click, drag to scroll, touch and hold for a right-click menu; Apple Pencil moving the pointer, with hover if the iPad supports it | Each action landing on the Mac at the same moment |
| 8 | Keyboard: type a sentence into the note | The letters appearing on the Mac too |
| 9 | Turn the iPad upright: the laptop layout; move the pointer with the trackpad, click, two-finger scroll; switch windows from a thumbnail; touch and hold one for its window buttons | The trackpad driving the Mac's pointer |
| 10 | Settings (the gear): change Quality, show the same value in the Sill menu on the Mac, then Disconnect | The panel and the Mac's menu agreeing; the iPad back on "Connect to a Mac" |
| 11 | Only for a build with Remote Access: Remote Access… in the Sill menu, Pair iPhone or iPad…, Add a Mac… on the iPad, the camera reading the code, "Paired with …"; then the iPad on cellular or a hotspot with the VPN on, connecting and streaming | The code scanned, then the stream with the iPad off the Mac's network |
| 12 | The same Mac on an iPhone: connect, pick a window, type a word | The app on iPhone too |

Optional, if time allows: an iPad on a USB-C cable (the row says "Wired"), and
Direct Wireless Connection with Search Nearby when the iPad has no shared
network.

## 9. Screenshots

### Required sets

| Set | Accepted sizes | Simulator |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 portrait, 2868 × 1320 landscape | iPhone 18 Pro Max (or 17 Pro Max): 1320 × 2868 at 3x |
| iPad 13" | 2064 × 2752 portrait, 2752 × 2064 landscape | iPad Pro 13-inch (M5): 2064 × 2752 at 2x |

One to ten per set, JPEG or PNG, **no alpha channel**. App Store Connect scales
these down for smaller devices, so no 6.5" set is needed while the 6.9" set
exists. iPhone Duo sizes are listed but uploads aren't open yet; add them in an
update. Screenshots can only change with a new version once one is approved.

### Which screens

Five per set, the app in use first (2.3.3).

| # | iPhone 6.9" | iPad 13" |
|---|---|---|
| 1 | Laptop layout, portrait: a Notes window on top, the key row and trackpad below | A window streaming, landscape: Notes with sample text, the bar with thumbnails |
| 2 | A window streaming, landscape: Weather for a city that isn't home | The Apps drawer open, landscape: "Open now", "All apps", the search field |
| 3 | The Apps drawer open | The Settings panel open, landscape: Quality, Resolution, Frame Rate |
| 4 | The Settings panel open | Laptop layout, portrait: the trackpad and the key row |
| 5 | The connect screen, portrait, with the Mac listed | The connect screen with the Mac listed |

### How to capture them

Use the real app in the simulator, connected to Sill.app on this Mac. The
simulator's Bonjour browsing runs in the Mac's own mDNSResponder, so the app in
the simulator finds Sill.app exactly as a device on the network would. The
layout harness (`-SillLayout` and the other `-Sill…` launch arguments) draws a
fake screen with a black picture: it is for checking layouts, not for App Store
screenshots.

1. Stage the Mac with the privacy list below, and disconnect every other
   device. The Mac streams one picture to every connected device, so a pick in
   the simulator also changes what the iPad shows.
2. Build the version you submit, Release, for the simulator:

   ```sh
   cd ~/Downloads/winstream   # the checkout you submit from
   xcodebuild -project iOSClient/Sill.xcodeproj -scheme Sill -configuration Release \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/Desktop/sill-shots/build \
     ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
   APP=~/Desktop/sill-shots/build/Build/Products/Release-iphonesimulator/Sill.app
   ```

3. Boot the simulator, give it a clean status bar, install and launch:

   ```sh
   SIM="iPhone 18 Pro Max"      # later: SIM="iPad Pro 13-inch (M5)"
   xcrun simctl boot "$SIM"; open -a Simulator
   xcrun simctl status_bar "$SIM" override --time 9:41 --dataNetwork wifi --wifiMode active \
     --wifiBars 3 --cellularMode notSupported --batteryState discharging --batteryLevel 100
   xcrun simctl install "$SIM" "$APP"
   xcrun simctl launch "$SIM" me.saffer.sill
   ```

4. In Simulator, click the Mac's row, then set up each screen with the mouse.
   Device › Rotate Left (⌘←) turns it to landscape. I/O › Keyboard › Toggle
   Software Keyboard (⌘K) shows the on-screen keyboard. On a fresh install the
   first-run tour dims the screen about a second after the Mac's picture shows,
   unless something is touched: click the picture at once to go without it, or
   take the tour once, before the screenshots.
5. Capture each one and turn it into a JPEG without alpha:

   ```sh
   cd ~/Desktop/sill-shots
   xcrun simctl io "$SIM" screenshot --mask=ignored raw.png
   sips -s format jpeg -s formatOptions best raw.png --out iphone-1-laptop.jpg
   sips -g pixelWidth -g pixelHeight -g hasAlpha iphone-1-laptop.jpg
   ```

   The simulator's PNG has an alpha channel (it did with and without
   `--mask=ignored`), which App Store Connect refuses; the JPEG has none. A
   landscape shot must read 2868 × 1320 (iPhone) or 2752 × 2064 (iPad). If one
   comes out upright with the picture on its side, turn it with `sips -r 90` or
   `sips -r 270`, whichever puts it right.
6. Afterwards: `xcrun simctl status_bar "$SIM" clear`, and quit Sill in the
   simulator so it stops streaming.

Good to know:

- The connect row's link word and the Settings panel's readout show what the
  simulator sees, not what a device would. The row said "Wired" on 2026-09-25
  because the Mac's cable link to the iPad was up. Both are real UI.
- Never `simctl io … recordVideo` while Sill.app streams. The simulator's
  recorder takes the Mac's video encoder at a higher priority and starves
  Sill's stream. Screenshots are fine.
- The simulator has no Apple Pencil hover. Leave Pencil to the demo video.

### What may appear in the picture

Everything in the stream is Noah's Mac. Stage it like a set.

Never in frame:

- The Mac's name if it holds yours. The connect screen and the Settings panel
  show it ("Noah's MacBook Pro" today). For the shoot, rename the Mac (Sill's
  Settings › General › Change It in Sharing Settings…), for example to
  "MacBook Pro", quit and reopen Sill.app so Bonjour carries the new name, and
  change it back after.
- Mail, Messages, Photos, Contacts, and Calendar or Reminders with real items.
- A browser with your tabs, bookmarks, history or accounts.
- Password managers, Terminal (your user name is in the prompt), code editors
  with private code, and Finder windows with your files or your home folder.
- Tailscale and other VPN menus or admin pages (they show tailnet names and
  addresses), Sill's log (device names and addresses), and System Settings
  panes that show your Apple Account.
- Notifications: turn on Do Not Disturb on the Mac and on the device.
- Wi-Fi network names, your location (Weather's "My Location", Maps), desktop
  files, and a wallpaper with people or your home.
- Other companies' apps and logos (VS Code, Blender, Chrome and the like).
  You need the rights to what a screenshot shows (2.3.9).

Safe:

- Weather for a well-known city that isn't home.
- Clock: world clocks for a few big cities, a timer.
- Notes with sample text written for the shoot, such as a packing list or a
  recipe, with fictional names only.
- Calculator, and TextEdit with sample text.

## 10. Checked for this file

- Limits, measured on the blocks in this file by a script: name 4 characters;
  fallback 23; subtitle 27 of 30; promotional text 164 of 170;
  description 2,062 (local-only 1,906) of 4,000 characters; keywords
  95 bytes (local-only 97) of 100, each
  keyword at least three characters, no spaces, no repeats; review notes
  3,553 bytes (local-only 2,845) of 4,000, all ASCII;
  What's New 260 and 226 characters.
- Again on 2026-09-27, after the tour (PR #35), the menus (PR #36) and the
  Mac's pointer (PR #31) joined the description and the review notes, with
  another script (it reads the blocks as 0.3.1 had them 3 to 6 lower than
  the counts above: description 2,056, review notes 3,550; keywords and
  What's New the same): description 2,332 (local-only 2,176) of 4,000
  characters; review notes 3,906 bytes (local-only 3,199) of 4,000, all
  ASCII; the rest unchanged. Pairing at home (PR #37) must fit in the 94
  bytes left, or the notes lose words elsewhere.
- The encryption key, now in `iOSClient/Info.plist`: Release builds of this
  branch for the simulator and for a device each have
  `"ITSAppUsesNonExemptEncryption" => false` in the built Sill.app's
  Info.plist, with the privacy manifest beside it. The device binary linked
  neither Security nor CryptoKit, and its one TLS-named symbol was
  `NWParameters(tls:tcp:)`, called with `tls: nil`. Only the known
  StreamClient capture warning. With main's Remote Access merged in (ba91136),
  the Release simulator and Debug device builds still have the key and the
  manifest; the binary now links Security and CryptoKit, Apple's, and no
  library of Sill's own (`otool -L`: only /System/Library and /usr/lib).
- The capture path: that Release build on the iPhone 18 Pro Max simulator
  listed the real Sill.app on this Mac within 10 seconds, with no connection
  made. `simctl io … screenshot` gave 1320 × 2868; the PNG had an alpha channel
  with and without `--mask=ignored`, and `sips -s format jpeg -s formatOptions
  best` removed it. The `status_bar override` above gave 9:41, Wi-Fi and a full
  white battery. The simulator was shut down and the app removed afterwards.
  Not tried: rotated captures, the iPad simulator (in use by other work; its
  2064 × 2752 size is from its device profile) and a connected stream (it
  would have streamed from Noah's Sill.app while he used it).
- Main (76366e8): no TLS, no crypto import and no web address in the iOS app
  or StreamProtocol. The remote-access branch (cb0ec55, merged into main as
  ba91136): TLS 1.3, Security, CryptoKit and CommonCrypto, all Apple's, and no
  `URLSession` or web address.
- The UI names in the review notes and the shot list match the code: the
  connect screen, the bars (Apps, Keyboard, Desktop, Settings), the panel, the
  Mac's Permissions pane and menu, and on remote-access "Add a Mac…",
  "Remote Access…", "Pair iPhone or iPad…" and "Enter Code Instead".
- No em-dashes in this file; no email address in it.

## Sources

Apple pages as fetched on 2026-09-25 for the App Store audit (kept in the
session scratchpad under `appstore/rules/`):

- App Review Guidelines (last updated June 8, 2026): 1.5, 2.1(a), 2.3.1(a),
  2.3.3, 2.3.4, 2.3.7, 2.3.9, 4.2.7, 5.1.1(i), 5.2.1.
- App Store Connect Help: App information; Platform version information;
  Screenshot specifications; Upload app previews and screenshots; Age ratings
  values and definitions; Set an app age rating; Manage app privacy; Overview
  of export compliance; Export compliance documentation for encryption;
  Manage European Union Digital Services Act trader requirements.
- App privacy details on the App Store (the definition of "collect").
- Documentation: ITSAppUsesNonExemptEncryption; Complying with encryption
  export regulations.
- [Apple Developer Forums thread 810791](https://developer.apple.com/forums/thread/810791),
  "Tips from App Review" (the video).

Looked up for this file on 2026-09-25:

- [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
  (Apple): the three kinds of encryption and the documents each needs.
- The questionnaire's wording as developers quote it:
  [FlutterFlow community](https://community.flutterflow.io/integrations/post/what-type-of-encryption-algorithms-does-your-app-implement-qKlOtGBHI00ivbq),
  [Garmin developer forum](https://forums.garmin.com/developer/connect-iq/f/discussion/326979/how-to-answer-encryption-question-on-apple-app-store-submission).
- The BIS rule of March 29, 2021, as summarized by
  [Venable](https://www.venable.com/insights/publications/2021/03/export-administration-rules-are-revised-to-elim)
  and [Wilson Sonsini](https://www.wsgr.com/en/insights/us-department-of-commerces-bureau-of-industry-and-security-relaxes-several-classification-and-reporting-requirements-for-encryption-items.html).
