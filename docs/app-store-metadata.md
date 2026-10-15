# Sill on the App Store: metadata and review material

Everything App Store Connect asks for the iOS app, in the order it asks, ready
to paste, and what App Review needs to try it: the review notes, the demo video
and the screenshots. Only the iOS app (bundle ID `me.saffer.sill`) goes through
App Store Connect. Sill for Mac ships outside it, as a Developer ID download.

Every text block below was measured against its limit (see "Checked for this
file" at the end). Paste blocks keep their line breaks.

## Values this file assumes

Noah confirmed the site and the contact address on 2026-09-25; Remote Access
is in every version since 0.5. The paste blocks below repeat them literally,
and the command under the table changes every copy in this file.

| What | Value | Status |
|---|---|---|
| Site | `https://getsill.app` | Noah's (bought 2026-09-25); the site is live. |
| Support URL | `https://getsill.app/support` | The page is `site/support.html`, which gives the contact address. The same link as `SillLinks.support` in the app (guideline 1.5). |
| Privacy Policy URL | `https://getsill.app/privacy` | `site/privacy.html`; the same link as `SillLinks.privacy` in the app. |
| Mac download | `https://getsill.app/download` | `site/download.html`; the same link as `SillLinks.download` in the app. |
| Contact address | `support@getsill.app` | Noah's: Cloudflare Email Routing forwards it to his mailbox (2026-09-25). |
| Mac requirement | Apple silicon, macOS 14 or later | Today's Sill.app is arm64 only; `LSMinimumSystemVersion` is 14.0. If the release build becomes universal, take "with Apple silicon" out of the description and the review notes. |
| App Store Connect record | "Sill – Mac Streaming", Apple ID 6816359860, SKU `sill-ios` | Created 2026-09-26 (section 1). Builds 0.5 (1) to (3) went to TestFlight; 0.5 (3) went to App Review as the first version, live 2026-10-08; 0.5.1 (4), the version both apps share from Sill for Mac 0.5.1 on, live 2026-10-10 (section 5). |
| Remote Access | In every version since 0.5, and in Sill for Mac since 0.3.0 (PR #13) | The live listing names it; the Remote Access switch below is only for a build without it. |

To change the domain or the contact address in this file, with both values
filled in (the address first: the domain's expression would change it too):

```sh
sed -i '' -e 's#support@getsill\.app#THE.REAL.ADDRESS#g' -e 's#getsill\.app#NEW.DOMAIN#g' docs/app-store-metadata.md
```

The app's own copy of the site and of the download, support and privacy links
is `iOSClient/SillLinks.swift`.

**Remote Access switch.** The blocks below describe the app as shipped since
0.5, with Remote Access; for a build without it, make every one of these cuts,
since guideline 2.3.1(a) forbids describing what the build lacks.
Pairing and the camera stay either way: since pairing at home (PR #37, Sill for
Mac 0.4.0 with build 0.5 (2)) every device pairs, at home too.

| Where | Cut |
|---|---|
| Description | Delete the bullet that starts "Away from home". |
| Keywords | Use the local-only line. |
| Review notes | Delete the REMOTE ACCESS (optional) paragraph (the local-only size is given). |
| What's New | Use the local-only line. |
| Demo video | Skip shot 11. |
| Site | Delete every block marked `<!-- Remote Access`. Step 3 of the release checklist has the check. |
| Export compliance | Nothing changes: the key stays NO either way. |

## Before you submit

These texts are only true once these are:

- The paste blocks match the build. They describe the app as shipped since
  0.5, with Remote Access; for a build without it, make every cut in the
  Remote Access switch above, the site's included.
- The support, privacy and download URLs load in a private window, signed out.
  The support page shows a way to reach you (guideline 1.5).
- Sill for Mac at the download URL is Developer ID signed, notarized and
  stapled, and opens on a Mac that never had it.
- Guideline 4.2.7 (as Apple published it on 2026-09-27) binds a remote desktop
  app that mirrors specific software rather than the whole host: the local
  network only (a), and software rendered on the host (b). Sill mirrors the
  whole Mac (the Desktop, any window, an Apps list of what is installed),
  which is how the audit of 2026-09-25 read it. A reviewer who reads it the
  other way would question Remote Access and the Mac's menus shown in the
  device's own menus (PR #36): the review notes say plainly that the device
  shows the Mac app's menus and that the Mac runs them.
- Sill for Mac at the download URL has pairing at home (PR #37: 0.4.0 and
  later; 0.3.1, the download until 2026-09-27, does not). A Release build of
  the iOS app never connects to an older Sill for Mac: its row reads "Update
  Sill", and App Review could not connect at all. For 0.5.1, Sill for Mac
  0.5.1 is the download first: the away quality and the notice when the link
  can't keep up, which the description and the review notes name, come from
  the Mac.
- The build carries `PrivacyInfo.xcprivacy` and the export compliance key
  (section 6).
- The version record's Version is the build's: the first App Store version
  is 0.5 (Noah, 2026-09-26; `MARKETING_VERSION` in both configurations of
  the Sill target since PR #19). App Store Connect names a new app's first
  version 1.0, and only a build whose version matches can be added to it, so
  set the record's Version to 0.5 (section 5). The second version is 0.5.1,
  the number both apps share from this release on (Noah, 2026-10-09): App
  Store Connect adds a version only once the current one is Ready for
  Distribution (the + beside iOS App), and copies its metadata into it.
- Every claim in the description has been seen working on a device. Still
  open: pairing at home (PR #37's P1 to P16: the code over Wi-Fi, the cable
  pairing by itself, Remove), three-finger gestures (PR #38's P1 to P13), the
  menus (PR #36's P1 to P13: the Menus button, the iPad's menu bar
  on iPadOS 26), the Mac's pointer on the device (PR #31's P1 to P12), the
  first-run tour (PR #35's P1 to P16), away from home (PR #39's P4 to P13:
  Low · Standard, the link's callout, the move home), the USB cable on an
  iPhone (verified on the iPad mini only; if it fails, write "a USB cable
  (iPad)"), Apple Pencil hover, and 120 frames per second, which no device
  has shown yet (the iPad mini is 60 Hz). For that one, stream a moving window, then the whole
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

The App Store shows "Remote Mac window management" (28 of 30) with 0.5.1,
which reads like a window-tiling utility; paste this one at the next version
(the subtitle changes only with a version).

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
- Taps, pointer moves, scrolls, three-finger gestures, keys, typed text, the
  menu items chosen and the panel size go to the same Mac. The Mac sends back the picture, window
  titles, thumbnails, app icons, its name, the menus of the app in use (their
  titles, and a menu's items when the device opens it) and where its own
  pointer is over the picture.
- The clipboard (from the version after 0.5.1, docs/clipboard-plan.md), while
  Share Clipboard is on in both apps: text copied on the Mac comes to the
  device's clipboard (local only, for 10 minutes), and text the person sends
  with Paste goes to the Mac's. Only to and from the user's own Mac, so the
  answer stays the same; the app reads the clipboard only through the
  system's Paste control, never by itself.
- Pairing (once per device, at home or for Remote Access) sends the device's
  public key, name and model to that Mac, which keeps them in its list of
  paired devices (Sill for Mac's Settings › Devices, where they can be
  removed).
- Kept on the device only: each Mac's thumbnail order, the names of Macs
  seen with Direct Wireless Connection on, which steps of the first-run
  tour were seen (or that it was skipped), whether three-finger gestures and
  Share Clipboard are on, and the clipboard's change count Sill last handled
  (never its contents); the device's key and the paired
  Macs, each with its key's fingerprint, its name and, with Remote Access, its
  addresses (Keychain and app storage); and camera frames, which are read for
  the pairing code and never saved or sent.
- No analytics, crash reporting, ads, third-party SDKs or servers, and no
  tracking. The iOS app makes no request of its own to anything but the Mac:
  there is no `URLSession` and no web view in it or in StreamProtocol, on main
  or on the remote-access branch. Its web links (`SillLinks`) open in Safari.

Keep three things saying the same: this label, `PrivacyInfo.xcprivacy`
(tracking false, no collected data types) and the privacy policy page. Answer
again before adding crash reporting, analytics, a server of any kind, or
anything that sends data somewhere other than the user's Mac.

## 5. The version page (0.5, then 0.5.1)

### Promotional text (170 characters at most; editable any time without review)

```text
Free, with no account and no servers. Use any window on your Mac, or the whole desktop, from your iPhone or iPad with touch, a trackpad, a keyboard or Apple Pencil.
```

### Description (4,000 characters at most)

The App Store shows another description with 0.5.1 (3,302 characters,
beginning "Sill shows a window from your Mac, or its whole desktop…"), which
this file doesn't hold. Paste this block at the next version: it has what that
one leaves out, the Mac requirement, iPhone Duo, away from home and no sound
among them.

```text
Sill puts your Mac on your iPhone and iPad. Pick any window, or the whole desktop, and use it with touch, a trackpad, a keyboard or Apple Pencil. Your apps keep running on your Mac. Sill shows them and sends back what you do.

Sill needs the free Sill for Mac on the Mac you want to use. Get it at getsill.app. It runs on a Mac with Apple silicon and macOS 14 or later.

Get started
• Open Sill for Mac and allow Screen Recording and Accessibility.
• Open Sill on your iPhone or iPad. Your Mac shows up in the list. Tap it. The first time, scan the code your Mac shows.
• Pick a window from the Apps list, or tap Desktop to see the whole screen.
• The first time, a short tour shows you the controls.

Made for touch
• Tap to click. Touch and hold to right-click. Drag to scroll.
• Apple Pencil works as a mouse, with hover on iPad models that support it.
• Hold your device upright for a laptop layout: the picture on top, a trackpad and a row of keys below. On iPhone, turn on Larger Picture to give a window’s picture more of the screen.
• On iPhone Duo, open it flat and your Mac fills the inner display. Half open, it’s a laptop: the picture above the fold, a trackpad and keys below. Closed, Sill runs on the cover display.
• Type with the on-screen keyboard, or on a hardware keyboard as soon as you connect, with shortcuts and Esc. A trackpad or a mouse scrolls the window under the pointer.
• Swipe and pinch with three fingers for Mission Control, App Exposé, Spaces, Apps and Show Desktop.
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
• Pair each device with your Mac once by scanning a code. Over a USB cable it pairs by itself. By default your Mac lets in only the devices you paired, and every connection is encrypted.
• Away from home, reach your Mac through your own VPN. Sill starts at a quality a slower connection can carry, tells you when the connection can’t keep up, and moves back to your home network by itself when you get home.

Private
• No account, no ads, no tracking.
• Sill has no servers and collects no data. The picture and what you type go between your devices and your Mac, and to no one else.
• Sill is free and open source (Apache 2.0): https://github.com/Saffsanity/sill

Good to know
• Sill shows one window, or the whole desktop, at a time.
• Sill doesn’t play sound from your Mac.
• Sill for Mac comes from getsill.app, not the Mac App Store.
```

Local-only build: delete the bullet that starts "Away from home".

**For the next version, not 0.5.1** (the clipboard, docs/clipboard-plan.md: it ships with the next
submission of both apps, and needs Sill for Mac from the same release): add this bullet to "Made for
touch", after the one that starts "Type with":

```text
• Copy text on your Mac and paste it on your iPhone or iPad. To paste on your Mac what you copied on your device, tap Paste in Sill, then press ⌘V on your Mac. Copies a password manager marks as concealed stay on your Mac.
```

The source is public under the Apache License 2.0 (since 2026-09-26), so the
listing may call Sill open source, as the live description does and the last
bullet of "Private" does.

The pairing bullet says "By default" because Require pairing, in Sill for
Mac's Settings › Devices, can be turned off: then any device on the Mac's
network can connect, still encrypted. Before pairing at home (PR #37) a bullet
here said that any iPhone or iPad with Sill on the same network could connect;
this text is for a build with pairing at home, the first one to App Review, with
a Sill for Mac that has it at the download URL (Before you submit).

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
| Version | 0.5.1 for the second version, the same number as Sill for Mac 0.5.1. The first was 0.5 (App Store Connect proposed 1.0 for a new app; the build said 0.5) |
| Copyright | `2026 Noah Saffer` (App Store Connect adds the ©) |
| App Previews | None for the first version. They are optional, and the sizzle reel can't be one: 2.3.4 allows only captures of the app itself, and previews run 15 to 30 seconds. |
| Screenshots | Section 9 |
| Version Release | Manually release this version, so an approval can't go live before the Mac download and the site are up |
| Build | 0.5.1 (4) for 0.5.1 (0.5 had 0.5 (3)): the Release archive with the privacy manifest and the export compliance key |

### What's New

App Store Connect doesn't show this field for an app's first version; it is
required from the second on, so 0.5.1 (4) is the first to have it: what
changed since 0.5, as the release notes say it. TestFlight asks for What to
Test for every build (the build › Test Details): for a later build, say what
changed since the build before.

```text
Made for iPhone Duo. Open it flat and your Mac fills the inner display. Half open, it’s a laptop: the picture above the fold, a trackpad and keys below. Closed, Sill runs on the cover display. Nothing you touch sits on the fold.

Away from home, Sill now starts at a quality a slower connection can carry, tells you when the connection can’t keep up and offers a quality it can, and moves your session back to your home network by itself when you get home. Also fixed: if your Mac showed twice away from home after Sill for Mac 0.4.0 gave it a new key, the row that didn’t work now connects, and the other goes. For the away quality and the notice, update Sill for Mac to 0.5.1 from getsill.app: from this release on, both apps share one version number.
```

Local-only build (0.5.1's other changes are all away from home's):

```text
Made for iPhone Duo. Open it flat and your Mac fills the inner display. Half open, it’s a laptop: the picture above the fold, a trackpad and keys below. Closed, Sill runs on the cover display. Nothing you touch sits on the fold.

Sill for iPhone and iPad and Sill for Mac now share one version number: this is 0.5.1, with Sill for Mac 0.5.1 from getsill.app.
```

The next version's, a draft: what changed on the device since 0.5.1 (4), as its release notes say it,
a paragraph a change (the same in the local-only build).

```text
Larger Picture, in Settings on iPhone: held upright, a window’s picture takes the place of the window thumbnails and reaches down to where the keyboard comes up. Set a window’s text size with Aa and your Mac makes it as tall as the picture. The Desktop keeps the usual layout.

With a keyboard attached to your iPhone or iPad, what you type goes to your Mac as soon as its picture shows, Esc included, without the Keyboard button. Two fingers on a trackpad, or a mouse’s scroll wheel, now scroll the window under the pointer.

Fixed: after Sill sat in the background for hours, it could stop finding your Mac until you closed and reopened it. Sill now looks again when you come back, keeps trying for a few minutes while your Mac doesn’t answer (when it’s asleep, say), and connects when it does.
```

Esc and scrolling with a trackpad or a mouse showed on the iPad through Universal Control on 2026-10-15
(docs/hardware-keyboard-plan.md, "Words that wait for a device"), so their words are in: this draft, the
description's keyboard bullet, README's How it works and the support page.

## 6. Export compliance (encryption)

**The key is in the app.** `iOSClient/Info.plist` sets
`ITSAppUsesNonExemptEncryption` to NO (`<false/>`). That is correct with
Remote Access and without it. With the key, uploads skip the encryption
questions, TestFlight builds included. Don't also add the build setting
`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` to the project: use one, not
both.

- Every connection to the Mac is TLS 1.3 through Network.framework
  (`sec_protocol_options`, Sources/StreamProtocol/RemoteTLS.swift, which the
  device's `DeviceTLS` in iOSClient/StreamClient+Home.swift builds on), each
  end pinned to the other's key: away from home since Remote Access (PR #13,
  ba91136), and at home since pairing at home (PR #37). A Release build never
  opens a plain connection; only a Debug build still dials an older Sill for
  Mac's plain TCP door (`NWParameters(tls: nil, tcp: tcp)`,
  `DeviceTLS.plain`). The iOS app makes no HTTPS requests. Before Remote
  Access, the iOS app and StreamProtocol imported no CryptoKit, CommonCrypto
  or Security at all.
- Besides TLS: P-256 keys and ECDSA signatures (Security, CryptoKit), and
  HMAC-SHA256 and PBKDF2 for the pairing code (CryptoKit, CommonCrypto). All
  of it is encryption within Apple's operating system. Apple's reference,
  "Export compliance documentation for encryption", lists "Your app uses
  encryption limited to that within the Apple operating system" as needing no
  documentation in App Store Connect. So the key stays NO.
- Without the key, App Store Connect asks "What type of encryption algorithms
  does your app implement?" The answer is "None of the algorithms mentioned
  above". The other choices are for proprietary algorithms, or standard ones
  the app implements itself instead of Apple's.
- Look again only if Sill ever ships its own cipher code or a third-party
  crypto library.
- Apple adds that an app with exempt encryption "might" need a year-end
  self-classification report to the U.S. government. BIS's rule of March 29,
  2021 dropped that report for mass-market end items such as application
  software (mass-market components still file it). Since pairing at home that
  is about every build, not only one with Remote Access. Not legal advice.

## 7. App Review Information

| Field | Value |
|---|---|
| Sign-in required | Unchecked. There is no account. |
| Contact | Noah Saffer, a phone number starting with + and the country code, and an email you read (`support@getsill.app` or your own; App Review only) |
| Notes | The block below |
| Attachment | The screen recording (section 8) |

### Notes (4,000 bytes at most)

Plain ASCII on purpose, so every character is one byte.

```text
PURPOSE AND AUDIENCE
Sill is a general-purpose remote desktop for the user's own Mac: it mirrors the whole Mac (the Desktop button) or any window of any app the user picks. It lets people use their Mac from their iPhone or iPad. It shows any Mac window, or the whole desktop, on the device and sends touch, trackpad, keyboard and Apple Pencil input back, so a Mac app can be used from another room, the couch or away from home, with no cloud service. It is for people who own a Mac and an iPhone or iPad. Every app runs and draws on the Mac; the iOS app shows the picture, lists the menu items of the Mac app in front so they can be chosen by touch (choosing one performs it on the Mac), and sends input. Its Apps list shows only apps already installed on that Mac.

ACCOUNTS AND PURCHASES
None: no account, no sign-in, no in-app purchase, no ads. No demo account is needed.

EXTERNAL SERVICES
None. The app talks only to the user's own Mac, found with Bonjour on the local network, over TLS 1.3 after a one-time pairing. Optional Remote Access uses a VPN the user already runs (such as Tailscale) or a port the user forwards; Sill runs no server. No analytics, AI, payment or login service.

REGIONS
The app works the same in every region, with no regional differences.

REGULATED OR THIRD-PARTY MATERIAL
Not applicable. Sill shows only the user's own Mac and its apps.

NO VPN FUNCTIONALITY
Sill creates, configures and operates no VPN and uses no Network Extension (no NEVPNManager, tunnel or proxy provider, no such entitlement). Only Network.framework, for TCP with TLS 1.3 to the user's own Mac. "VPN" appears only because a user may optionally reach their Mac through a VPN they already run themselves (such as Tailscale); Sill just connects to the Mac's address over the network the device has and names that connection. It collects no user information through VPN or anything else, and shares nothing with third parties.

WHAT YOU NEED
- A Mac with Apple silicon and macOS 14 or later.
- An iPhone or iPad on the same Wi-Fi network.
- Sill for Mac 0.5.1 or later, free: https://getsill.app/download (Developer ID, notarized).

SET UP THE MAC (about 2 minutes)
1. Download Sill for Mac, move it to Applications and open it. It lives in the menu bar and opens its Settings on Permissions.
2. Screen Recording: click Allow..., turn on Sill in System Settings, then click Quit & Reopen.
3. Accessibility: click Allow... and turn on Sill.
4. If macOS asks about the local network, click Allow. The pane then says "You're all set."

CONNECT AND PAIR (once per device)
5. Open Sill on the iPhone or iPad and allow Local Network access.
6. The Mac appears under "Connect to a Mac", marked "Not paired". Tap it.
7. The Mac shows a QR code and a 12-digit code. Scan it with the device's camera, or tap Enter Code Instead and type it. The Mac's desktop appears. Over a USB-C cable the device pairs by itself while the Mac is unlocked.

WHAT TO TRY
- Apps (magnifying glass): pick a window, or search and open an app.
- Tap to click, drag to scroll, touch and hold to right-click. Apple Pencil works as a mouse.
- Three fingers: swipe up for Mission Control, spread for Show Desktop.
- Keyboard, Menus, Aa (text size), window thumbnails, Desktop.
- Hold the device upright for a laptop layout with a trackpad and keys.
- Settings (gear): Quality, Resolution and Frame Rate; Disconnect at the bottom.

IF THE MAC DOES NOT APPEAR
Guest or office networks can keep devices apart: use a USB-C cable, or turn on Direct Wireless Connection in the Sill menu and tap Search Nearby.

REMOTE ACCESS (optional)
In the Sill menu choose Remote Access... and turn it on while the device is connected. The device can then reach the Mac from another network through the user's own VPN. It starts at a lower quality for slower links.

VIDEO
The attached screen recording (a physical device, latest OS) starts at launch: pairing, streaming a window, input, menus, Settings.
```

Local-only build: delete the REMOTE ACCESS (optional) paragraph.

These are the notes as App Store Connect holds them since App Review's
questions about 0.5, which they answer (purpose and audience, accounts,
external services, regions, no VPN functionality); a new version starts with
them. For 0.5.1 this block adds the last sentence of REMOTE ACCESS, "It starts
at a lower quality for slower links." (47 bytes), and asks for Sill for Mac
0.5.1 in WHAT YOU NEED, whose away quality that sentence describes: check that
App Store Connect's copy has both.

## 8. Demo video

For 0.5, App Review asked for a screen recording captured on a physical
device running the latest OS, starting at the app's launch: that is the
attachment (pairing, streaming a window, input, menus, Settings). If App Review
asks to see the Mac as well, film the Mac and the device together with a
camera:

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
| 5 | Open Sill on the iPad, Allow Local Network, the Mac appears ("Not paired"), tap it: the Mac's pairing window comes up, the iPad's camera reads its code | The Mac found without typing anything; the code scanned once; the Mac's desktop on the iPad |
| 6 | Apps, pick Notes (a note written for the shoot); then Menus, Format, and a style for a line | The same window on both screens; the style chosen on the iPad applied on the Mac |
| 7 | Touch: tap to click, drag to scroll, touch and hold for a right-click menu; Apple Pencil moving the pointer, with hover if the iPad supports it | Each action landing on the Mac at the same moment |
| 8 | Keyboard: type a sentence into the note | The letters appearing on the Mac too |
| 9 | Turn the iPad upright: the laptop layout; move the pointer with the trackpad, click, two-finger scroll; three fingers up for Mission Control and down again; switch windows from a thumbnail; touch and hold one for its window buttons | The trackpad driving the Mac's pointer; Mission Control opening and closing on the Mac |
| 10 | Settings (the gear): change Quality, show the same value in the Sill menu on the Mac, then Disconnect | The panel and the Mac's menu agreeing; the iPad back on "Connect to a Mac" |
| 11 | Only for a build with Remote Access: the iPad, paired in shot 5, connected at home; Remote Access… in the Sill menu, turned on while it is connected (its Settings panel then says how it reaches the Mac away from home); then the iPad on cellular or a hotspot with the VPN on, connecting and streaming | The stream with the iPad off the Mac's network, with no second pairing |
| 12 | The same Mac on an iPhone: pair it (tap the Mac, scan the code), pick a window, type a word | The app on iPhone too |

Optional, if time allows: an iPad on a USB-C cable (the row says "Wired"; an
iPad not yet paired pairs by itself there, and the Mac shows a notice with
Remove), and Direct Wireless Connection with Search Nearby when the iPad has no
shared network.

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

Six per set in the listing with 0.5.1, the app in use first (2.3.3), each
with its caption drawn in:

| # | iPhone | iPad |
|---|---|---|
| 1 | Your Mac, in your hand. | Your Mac, on your iPad. |
| 2 | Launch any Mac app. | Laptop mode. |
| 3 | Every window, one tap away. | Sharp and smooth. |
| 4 | Laptop mode. | Pair once. Private always. |
| 5 | Sharp and smooth. | Launch any Mac app. |
| 6 | Pair once. Private always. | Every window, one tap away. |

The first plan, five per set, before the captions:

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

4. Pair the simulator once. It runs on this Mac, and Sill for Mac never opens
   its pairing window for a device on the Mac itself, so choose Pair iPhone or
   iPad… in the Sill menu first, then click the Mac's row in Simulator, click
   Enter Code Instead in the card that opens (the simulator has no camera) and
   type the 12 digits the Mac's window shows; the Mac's desktop then appears.
   Set up each screen with the mouse.
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
6. Afterwards: `xcrun simctl status_bar "$SIM" clear`, quit Sill in the
   simulator so it stops streaming, and remove the simulator in Sill's
   Settings › Devices on the Mac.

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
  description 2,060 (local-only 2,005) of 4,000 characters; keywords
  95 bytes (local-only 97) of 100, each
  keyword at least three characters, no spaces, no repeats; review notes
  3,553 bytes (local-only 2,845) of 4,000, all ASCII;
  What's New 260 and 226 characters.
- Again on 2026-09-27, after the tour (PR #35), the menus (PR #36) and the
  Mac's pointer (PR #31) joined the description and the review notes, with
  another script (it reads the blocks as 0.3.1 had them 3 to 6 lower than
  the counts above: description 2,056, review notes 3,550; keywords and
  What's New the same): description 2,332 (local-only 2,176) of 4,000
  characters; review notes 3,926 bytes (local-only 3,219) of 4,000, all
  ASCII; the rest unchanged.
- With pairing at home (PR #37) and the gestures (PR #38), for the release of
  Sill for Mac 0.4.0 with build 0.5 (2), the same script: description 2,437
  (local-only 2,382) of 4,000 characters; review notes 3,948
  bytes (local-only 3,592) of 4,000, all ASCII, after they lost the
  Mac menu's agreeing values, a clause on encryption in WHAT SILL IS and
  REMOTE ACCESS, the pairing that REMOTE ACCESS no longer needs and a sentence
  of IF THE MAC DOES NOT APPEAR, and gained the three-finger gestures and the
  rule that Remote Access is turned on while the paired device is connected
  (a device learns the Mac's addresses only from a session with Remote Access
  on); the rest unchanged.
- For 0.5.1 (4) with Sill for Mac 0.5.1, PR #39's away from home, PR #46 and
  the iPhone Duo text, the same script: description 2,792 (local-only 2,571)
  of 4,000 characters; review notes 3,995 bytes (local-only 3,592) of 4,000,
  all ASCII; What's New 753 and 358 characters; the rest unchanged.
- After the launch review (2026-10-11), with the open-source bullet in the
  description and App Store Connect's notes in section 7, the same way:
  description 2,872 (local-only 2,651) of 4,000 characters; review notes
  3,952 bytes (local-only 3,709) of 4,000, all ASCII; the rest unchanged.
- With a hardware keyboard and trackpad (#67, #68; the bullet that starts
  "Type with the on-screen keyboard" and the next version's What's New), the
  same way: description 2,899 (local-only 2,678) of 4,000 characters; the next
  What's New 138 characters; the rest unchanged. With the words that wait for
  a device (Esc, and scrolling with a trackpad or a mouse): 2,963 (local-only
  2,742) and 247.
- With those words in (2026-10-15, after Noah's Universal Control test), the
  description block as it stands here, Larger Picture's sentence included:
  3,044 characters; its keyboard paragraph of the next What's New 247.
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
- No em-dashes in this file; its only email address is support@getsill.app.
- Pairing at home (PR #37, 2026-09-27): the description, the review notes,
  the export compliance, the privacy answers, the demo video and the
  screenshot steps describe it, since every connection at home is TLS with
  pairing from then on and a Release build never connects to an older Sill for
  Mac. The names in them match the code: "Not paired" (the row), "Enter Code
  Instead" (the home card, as Add a Mac…'s), "Pair iPhone or iPad…" and
  Settings › Devices (the Mac), and an ask from the Mac itself (the simulator)
  gets no window by itself (`DoorPolicy.ask`).

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
