# Localization

Sill uses English source strings as keys. Each app owns its catalogs in its main bundle:

- macOS: `Packaging/Localizable.xcstrings` and `Packaging/InfoPlist.xcstrings`
- iOS: `iOSClient/Localizable.xcstrings` and `iOSClient/InfoPlist.xcstrings`

To update the source strings in the Localizable catalogs, select a full Xcode installation and run:

```sh
Scripts/sync-localizations.sh       # both apps
Scripts/sync-localizations.sh mac   # macOS only
Scripts/sync-localizations.sh ios   # iOS only
```

The command builds into a fresh temporary directory with Swift string extraction enabled and merges all the app and package target data into each catalog in one pass. It requires the corresponding Apple SDKs and may take as long as clean builds. Review the resulting catalog diff, including removed or stale entries, and update the English, Simplified Chinese (`zh-Hans`), and Traditional Chinese (`zh-Hant`) translations. Ordinary app builds do not replace this explicit synchronization step for package source strings.

SwiftUI string literals are extracted automatically. For AppKit or a value held in a `String`, use `String(localized: "English text")` with a literal, rather than passing a variable as the localization key. Use interpolation within the localized string for names and numbers, and translate complete sentences instead of joining fragments. The compiler determines the catalog placeholders; do not guess them. Add comments where a translator needs context. Device names, user content, and protocol identifiers should remain unchanged.

The InfoPlist catalogs are maintained by hand: their keys are system property names, not Swift source strings. Update the corresponding catalog when changing a localized permission description or another localized Info.plist value. Do not synchronize them with the Swift extraction command.
