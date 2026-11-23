# The app icon in Liquid Glass, and a choice of icon

2026-11-18, branch `app-icons`, made from `settings-pane` (the whole-screen Settings, itself on main at 8dbbb50,
0.6.3) because the App Icon group sits in that pane's part for this device, beside the version.

Noah, 2026-11-18: "instead of merging https://github.com/Saffsanity/sill/pull/386/changes, I want you to take the
original Sill icon and convert it to an Icon Composer document so the system draws it in Liquid Glass. Also, add a
an app icon switcher in the version settings that is a full pane (being worked on right now) that allows the user
to either 1) use the updated icon 2) use the one provided in this commit under community 3) generate a Genmoji or
use an emoji and 4) upload their own .svg or icon composer document."

## What is built, and what is not

- **1, the original in Liquid Glass**: `Packaging/AppIcon.icon`, the primary icon of both apps.
- **2, the community's**: grub-basket's Icon Composer document from #386, byte for byte, at
  `Packaging/AppIconCommunity.icon`, an alternate icon of Sill for iPhone and iPad, credited by login.
- **3 and 4 are not built.** iOS changes an app's Home Screen icon only to one compiled into the app:
  `UIApplication.setAlternateIconName` takes the name of an icon the bundle declares (`CFBundleAlternateIcons`,
  which the asset compiler writes from the build's icons), and there is no way to hand iOS a picture at run time,
  so an emoji, a Genmoji, an uploaded SVG or an uploaded `.icon` cannot become Sill's icon. (A Shortcuts "Add to
  Home Screen" bookmark can wear any picture, but it is a shortcut that opens Shortcuts first, not Sill's icon;
  the App Library, Settings, Spotlight and notifications keep the real one.) Noah has been told and offered more
  icons bundled in the app instead; of the drawings he saw (Noah, 2026-11-18): "let's just avoid the closest to
  apple's line for this release. Also, when we eventually have a UI for selecting icons, let's have categories that
  you scroll through ideally". Those come in a later change. The design leaves room for them: a later icon is a
  case in `AppIconChoice`, its document, its preview and its name in the build's alternates, and
  `Tests/checks/app-icon` names whichever is missing.
- **Sill for Mac keeps one icon**, the original in Liquid Glass. macOS has no alternate icons for apps: changing a
  signed app's own icon means writing a custom icon into its bundle (as Finder's Get Info does), which leaves the
  bundle no longer as it was signed, and Update Now replaces the bundle anyway; the one icon an app may change while
  it runs is its Dock tile's, and Sill, a menu bar app, has none.

## A. The original in Liquid Glass

`design/AppIcon.svg` rebuilt at its own coordinates as an Icon Composer document: the dark gradient (#1a1a1c to
black, top to bottom) as the document's fill; two layer groups, front to back:

| Group | Layers, front to back | Glass | Shadow | Translucency |
|---|---|---|---|---|
| iPad | `window` (the streamed window: white card, the blue title bar, its three lights, three lines), `ipad-screen` (the screen and the camera), `ipad` (the slate body) | the body only | neutral, 1.0 | off |
| iMac | `imac-screen` (the screen), `imac` (the space grey body, neck and foot, one silhouette) | the body only | neutral, 0.5 | off |

- Each layer is a 1024 × 1024 SVG cut from `AppIcon.svg` with the same transforms (the iMac group's 56-unit shift,
  the iPad's −5° about (520, 392)). The original's gloss (a white gradient down the iMac's body at half opacity and
  down the iPad at 0.8) is drawn into the layers' own fills, clipped to them, so every colour matches the flat icon:
  sampled from ictool's render against Quick Look's of the SVG, the iMac's bezel #96989f against #96989d, its chin
  #61626b against #61626a, the screen's top #403f42 against #424345, the iPad's bezel #878b90 against #888a91, the
  title bar #b4c8ff against #b3c8ff.
- What the system draws now is left out of the layers: the white rims (the glass's specular edges take their
  place), the drop shadows and the blurred shadow under the iPad (the groups' shadows; the iPad's at full strength,
  so it still lifts off the iMac's chin).
- Translucency is off in both groups: on, the black background showed through the bodies and darkened the iMac's
  grey by a fifth (its chin #4b4b53 against #5f5f69), and the iPad's white screen to #e6e7e8; the original's
  bodies are opaque.
- Clear and Tinted (the "tinted" appearance): the iMac's body gets a lighter fill there alone, a grey gradient
  (#e0e0e6 to #9e9ea8), so the iMac reads; with its own mid grey it nearly vanished in Tinted Dark. Default and
  Dark keep the original's colours; the original is a dark icon, so Dark is the same picture.
- `design/AppIcon.svg` and `site/icon.svg` stay the flat original.
- Renders of every look, iOS and macOS (Default, Dark, Clear Light, Clear Dark, Tinted Light, Tinted Dark), are made
  by `Scripts/app-icon-previews.sh --looks DIR`; this run's are in Noah's handoff folder (`next/app-icons/renders`).

## B. The community icon

grub-basket's `Packaging/AppIcon.icon` from #386 (commit be5113f1; unchanged in the pull request's later commits),
its seven files byte for byte, at `Packaging/AppIconCommunity.icon`, in a commit authored by them. Nothing else of
#386 comes in: its menu bar glyph, site, disk image and design changes stay with that pull request.

## B2. The windowsill (joannou)

joannou's `Packaging/AppIconWindowsill.icon`, a second alternate, offered after this plan: a Mac's window lit green at
night (#76FB4B on a near-black green gradient, #1F2E1D to #060906), its three lights and the title bar's edge cut out
of it, and a cat sitting on the sill with its back to us, looking in, cut out of the window too; the sill a slim bar
under it. Two groups, both glass, neutral shadows at 0.5, translucency off: the window, then the sill. The fill has a
dark specialization (a shade darker), so Default and Dark are the same night; Clear and Tinted are the system's
own, and the cat holds in each (rendered with ictool in all six looks). Wired as the community's is: a case in
`AppIconChoice` (`windowsill`, "Windowsill", "by joannou"), the document a resource (A1C4/F1C4), its name second in
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in both configurations, and its preview,
`AppIconWindowsillPreview`, rendered as `Scripts/app-icon-previews.sh` does (288 px, iOS Default). It adds about
2.4 MB per device download as the community's does: the simulator build's Assets.car is 15.0 MB (both idioms)
against 10.1 MB with two icons. Its subject is the app's, a Mac's window, under the same name (2.3.8, below).

## C. The switcher (Sill for iPhone and iPad)

- **The build**: both documents are resources of the iOS target (`folder.iconcomposer.icon`, as #386 wired its
  one); `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` and `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES =
  AppIconCommunity` in both configurations, which Xcode 27 passes to actool as `--alternate-app-icon`; the asset
  catalog's flat `AppIcon.appiconset` is gone, so the name AppIcon is the document's alone. Verified in the
  simulator build CI makes: its Info.plist's `CFBundleIcons` and `CFBundleIcons~ipad` both have
  `CFBundlePrimaryIcon` AppIcon and `CFBundleAlternateIcons` AppIconCommunity, and its Assets.car holds each
  icon's layered stack (iOS 26 and later draw the glass from it) and its 1024-pixel Any, Dark and Tintable
  pictures for iOS 17 and 18, for iPhone and iPad.
- **The cost**: that Assets.car is 10.1 MB (both idioms) against main's 0.58 MB; App Store thinning sends a device
  one idiom, about 5 MB: 2.6 MB the original in glass, 2.4 MB the community's. The pictures are what actool makes
  of any Icon Composer icon, the same with an iOS 26 deployment target (measured: it keeps the 1024-pixel pictures
  too); #386's document alone compiles to about the same.
- **The rule** (`AppIconChoice`, pure, `Tests/checks/app-icon` with 52 mutants): the original is the primary icon
  (no alternate name) and the standard, first in the list; the community's is the alternate AppIconCommunity,
  credited "by grub-basket"; the Home Screen's icon is read from iOS's alternate icon name, which iOS keeps across
  launches and updates, and a name this build does not ship reads as the original (iOS shows the primary icon
  when the bundle lacks the alternate, as developers report of updates that dropped one; not tried here);
  a tap asks iOS for that icon unless it is set already, judged against the name itself, so Original clears an
  unknown name; the group shows only where iOS can change the icon. The check also reads the repository: both
  configurations' icon names exactly the choices', each document a resource with every layer it names, no icon
  set of the same name, each preview, and Sill for Mac's icon the original.
- **The picker** (`AppIconPicker`): Settings, this device's part, after Take the Tour and right above the version
  line: a small "App Icon" title, the pictures in the panel's group style (each icon's Default look at 60 pt,
  growing with the text size to 96 pt, its word under it, "by grub-basket" under the community's), the one the Home Screen
  shows ringed in the accent and checked, and under the group "The icon Sill shows on this iPad’s Home Screen.
  You can switch back to Original here whenever you’re connected to a Mac." (Settings is a session's, so the way
  back needs a Mac connected; until the review of #390 it said Original was "always here", which held only in a
  session.) A tap asks iOS, which shows its own alert ("You have changed the icon for “Sill”."); while iOS
  answers the pictures wait; a refusal shows an orange line under them. VoiceOver: each
  icon one button, "Community icon, by grub-basket", selected when it is the one. The pictures are a grid that
  wraps, so more icons fit. The previews are each document's iOS Default look rendered by ictool at 288 pixels
  (`Scripts/app-icon-previews.sh`, committed beside the documents).
- **The toggle rule** (Noah, 2026-11-18, "Anything that it would make sense to add a toggle to you should add a
  toggle"): the choice is a picker, and the original stays unless the person picks the other; nothing changes for
  anyone who never opens it.
- **DEBUG**: `-SillAppIcon original|community|<name>` stands in for iOS's alternate icon name in the harness (a
  tap moves the stand-in alone), `-SillAppIconFailed 1` shows the refusal's line, `-SillAppIconSet
  original|community` makes a tap's real call a second after the group appears (iOS's alert in a photo of the
  harness's own simulator, and the icon iOS kept at the next launch), `-SillSettingsScroll appicon` opens Settings
  at the group. The console says what happened ("app icon: …").

## App Review

The rule is **the last sentence of guideline 2.3.8**: an app's name and icons, alternate icons among them, are to be
"similar to avoid creating confusion". Nothing else in Apple's App Review Guidelines (last updated October 16, 2026;
read 2026-11-18) is about alternate icons. Guideline 4.6 was (a change only at the person's request, a setting to go
back to the original, icons related to the app's content, no automatic or serial changes), but it is now marked as
intentionally omitted; this plan cited it until the review of #390. Apple's Human Interface Guidelines (App icons,
on alternate app icons) say the same in design terms: each alternate stays closely related to the app's content
and experience and is not one people could take for another app; on iPhone and iPad each has its own dark, clear
and tinted looks; and each is reviewed like the primary icon.

- **Against 2.3.8 and the HIG**: both icons show what Sill does, a Mac's window carried to an iPhone or iPad, under
  the same name, and both are Icon Composer documents, so each has every look. They differ in drawing as well as
  colour: the original is a solid grey iMac with an iPad tilted in front, on black; the community icon draws the Mac
  as a white outline with a dashed gap where the window was, and an iPhone on its side holding the window, on blue
  with a coral title bar. That difference is the one risk: a reviewer could cite 2.3.8. If one does, removing the
  community icon is one case in `AppIconChoice` and one build setting.
- **Good practice kept, not a guideline now** (4.6's old terms): both icons ship in the app, and nothing is
  downloaded or generated; the icon changes only when the person taps one in Settings, and iOS confirms each change
  with its alert; nothing changes it on its own, on a schedule or from the Mac; Original is first in the list, so
  the way back is one tap in any session (Settings is a session's: see the Defaults, 2).
- **More bundled icons** (the alternative Noah was offered for choices 3 and 4; a later change) meet the same
  sentence: the further one strays from the original's subject, a Mac's window on an iPhone or iPad, the likelier a
  reviewer cites 2.3.8.

Proposed words for the review notes (the notes were 3,988 of 4,000 bytes at 0.6.2, so a sentence must go to make
room): "Settings › App Icon (Settings is the gear in a session's bar) switches Sill's Home Screen icon between the
original and a community-designed alternate that ships in the app; only a tap changes it, iOS confirms each change,
and Original, first in the list, switches it back."

## Words for elsewhere (proposed, not published)

- What's New, Sill for iPhone and iPad: "Sill's icon is now drawn in Liquid Glass, in light, dark, clear and tinted.
  And there's a second icon to choose in Settings › App Icon: the community icon by grub-basket."
- Sill for Mac's notes: "Sill's icon is now drawn in Liquid Glass."
- A comment on #386 (for Noah to post): "Thank you, @grub-basket, for this icon and for making it an Icon Composer
  document. Sill keeps its original icon as the default, now redrawn in Liquid Glass too, and yours ships beside it
  as the Community icon: Settings › App Icon on iPhone and iPad, credited to you by name, with your commit and
  authorship kept (#390). The menu bar glyph, site, disk image and design changes don't come with it, since the
  original stays Sill's face on the Mac and the site, so I'll close this pull request once #390 merges. Thank you
  again."

## Defaults taken for Noah to confirm

1. The names: "Original" and "Community", the credit "by grub-basket" (the login, no @) under the community's.
2. The place: this device's part of Settings, after Take the Tour, right above the version line, with its own
   "App Icon" title and a footnote. Settings opens only in a session, so the icon can be changed, and changed back,
   only while connected to a Mac: someone who picked Community and can no longer reach a Mac (sold, off, or away
   without Remote Access) gets Original back only by deleting and reinstalling Sill. The footnote says the way back
   is "here whenever you’re connected to a Mac". Not built, yours to ask for: the group on the connect screen too,
   for example under its version line.
3. The pictures show each icon's Default look, not the person's Home Screen style (dark, clear or tinted).
4. The original's glass: the gloss kept in the fills, rims and shadows the system's, translucency off, a lighter
   iMac in Clear and Tinted.
5. Sill for Mac: the original in Liquid Glass, no choice.
6. grub-basket's document kept byte for byte, its watchOS circle entry included (harmless: no watch app).
7. About 5 MB more per device download for the two icons in glass (2.4 MB of it the community's).
8. The App Store's icon: the primary, the original in glass (App Store Connect takes it from the build).
9. The toggle rule: the choice is a picker, and the original stays unless the person picks the other, so nothing
   changes for anyone who never opens it.

## Verified

- ictool renders of both documents in every look, iOS and macOS, looked at beside the original's Quick Look
  render, the colours sampled; actool compiles both for iphoneos (17.0) and macosx (14.0) without a warning; the
  Mac's AppIcon.icns from make-app.sh's own actool call shows the original in glass on the macOS grid.
- CI's build, locally through heavy.sh: `swift build -c release`, `Tests/checks/run-all.sh`, the iOS app for the
  generic simulator (Debug, arm64, unsigned), SillHost's `--internet` refusal; the built app's Info.plist and
  Assets.car as above.
- `Tests/checks/app-icon` (78 cases) and its 52 mutants (34 of the source, 18 of the wiring in a copy of the files
  it reads).
- The review of #390 (three findings, each confirmed): the App Review section rests on 2.3.8 and the HIG, read from
  Apple's pages on 2026-11-18 (4.6 is omitted there); the footnote and every "always offered" say the way back is
  in a session, since `HostSettingsPanel` is made only by `StreamScreen`, which `ContentView` shows only while
  `client.connected`; and the merge order below, since the repository does not delete merged branches
  (`delete_branch_on_merge` false), so GitHub will not move this pull request's base to main by itself. CI's
  build again, locally through heavy.sh at 967e0526 (with `settings-pane`'s 988b3a08 merged): `swift build -c
  release`, `Tests/checks/run-all.sh` (76 checks, all passed), the iOS app for the generic simulator (its
  Info.plist's alternate icon for iPhone and iPad as before), `SillHost --internet` exiting 2. Harness photos of
  967e0526 on the agents' Duo (iOS 27.1): the new footnote under the pictures on the inner display, an iPhone
  upright and the cover, and with `-SillSettingsEnd 1` an upright iPhone's pane reaching the version and
  Disconnect (`settings-pane`'s review fixed the end that stopped short before).
- Harness photos of the group on the agents' Duo (iOS 27.1) and iPad, against `settings-pane`: every arrangement
  of the pane, each mark, the refusal, large type, right to left; the stream screens pixel for pixel the
  baseline's. With `-SillAppIconSet community`, iOS's own alert on the simulator ("You have changed the icon for
  “Sill”.", the community icon in it), and at the next launch the icon iOS kept, read as Community; then the
  original set back the same way. So the alternate declared by an Icon Composer document is one iOS 27.1 sets.
- GitHub's CI passed on the pull request at each head before the review round (19b5be75, a649177c, daa4c6a9,
  26047fd3, 9d2829f0); the review round's run is in the pull request's description.

## What only Noah can try

1. On a real iPhone or iPad with iOS 26 or 27: the Home Screen shows the original in glass; in Settings › Display
   & Brightness (or the Home Screen's Edit › Customize), Dark, Clear and Tinted show their looks.
2. In a session, Settings › App Icon › Community: iOS's alert, then the Home Screen, the App Library, Spotlight,
   Settings and a notification show the community icon; back with Original.
3. The same on an iPhone or iPad with iOS 17 or 18, if one is at hand (the flattened pictures).
4. Sill for Mac built with make-app.sh (`--install --open`, his own command): Finder, Login Items and Privacy &
   Security show the original in glass, under macOS 27's icon styles too; the disk image's volume icon.
5. A TestFlight upload (`Scripts/release-ios.sh --upload`): App Store Connect accepts the build with its
   alternate icon, and the store's icon is the original in glass.
6. The review notes' sentence, and the comment on #386.
7. The merge order. #390's base is `settings-pane`, and GitHub moves a base to main only when that branch is
   deleted after its merge, which this repository does not do by itself. So: merge #393 (`settings-pane`) into
   main first, with a merge commit as main's merges are; then move #390's base by hand, `gh pr edit 390 --repo
   Saffsanity/sill --base main` (or delete the `settings-pane` branch, and GitHub moves it); check that #390 shows
   only the icon work against main; and only then merge #390. Merged while its base is still `settings-pane`, the
   icon work would land in `settings-pane`, not main, though #390 would show as merged.
