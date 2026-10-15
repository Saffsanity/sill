#!/bin/bash
# Sill Viewer, the Mac client (Sources/MacClient): .build/Sill Viewer.app, from `swift build`.
#   Scripts/make-client-app.sh             release build, signed with your Developer ID
#   Scripts/make-client-app.sh --debug     debug build (DEBUG launch arguments such as -SillConnect)
#   Scripts/make-client-app.sh --notarize  …then notarized and stapled (.build/Sill Viewer.zip too)
#   Scripts/make-client-app.sh --open      …and open it
# Signing: SILL_SIGN_IDENTITY (a name or SHA-1), else the first Developer ID Application identity,
# else the first Apple Development one, else ad hoc. A real identity keeps the login keychain's
# device key and the privacy grants (Local Network, Accessibility) across rebuilds and copies to
# another Mac: both name the signature's designated requirement, which an ad hoc signature changes
# with every build. Notarizing uses the notarytool profile SILL_NOTARY_PROFILE (sill-notary). The icon is Sill.app's, taken
# from .build/Sill.app when Scripts/make-app.sh has built it.
set -euo pipefail
cd "$(dirname "$0")/.."
config=release; open_after=0; notarize=0
for a in "$@"; do
    case "$a" in
        --debug) config=debug ;;
        --open) open_after=1 ;;
        --notarize) notarize=1 ;;
        *) echo "usage: $0 [--debug] [--notarize] [--open]" >&2; exit 2 ;;
    esac
done
swift build -c "$config" --product SillClient
swift build -c "$config" --product SillDockProxy
app=".build/Sill Viewer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/SillClient" "$app/Contents/MacOS/SillClient"
cp Packaging/Client-Info.plist "$app/Contents/Info.plist"
# The Dock icon helper (Sources/SillDockProxy), copied and renamed per remote app at run time.
helper="$app/Contents/Helpers/SillDockProxy.app"
mkdir -p "$helper/Contents/MacOS"
cp ".build/$config/SillDockProxy" "$helper/Contents/MacOS/SillDockProxy"
cat > "$helper/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SillDockProxy</string>
	<key>CFBundleIdentifier</key><string>me.saffer.sill.client.dock</string>
	<key>CFBundleName</key><string>Sill Dock Icon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$app/Contents/Info.plist"
if [ -f .build/Sill.app/Contents/Resources/AppIcon.icns ]; then
    cp .build/Sill.app/Contents/Resources/AppIcon.icns "$app/Contents/Resources/"
    [ -f .build/Sill.app/Contents/Resources/Assets.car ] && cp .build/Sill.app/Contents/Resources/Assets.car "$app/Contents/Resources/"
else
    echo "note: no icon (run Scripts/make-app.sh once to make Sill.app's)" >&2
fi
ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
identity="${SILL_SIGN_IDENTITY:-$(echo "$ids" | awk '/"Developer ID Application: / { print $2; exit }')}"
[ -n "$identity" ] || identity="$(echo "$ids" | awk '/"Apple Development: / { print $2; exit }')"
[ -n "$identity" ] || { identity="-"; echo "warning: no signing identity; signing ad hoc" >&2; }
# The helper first (a nested bundle is sealed into its parent's signature), then the app.
if [ "$identity" = "-" ]; then
    codesign --force --options runtime --timestamp=none --sign - "$helper"
    codesign --force --options runtime --timestamp=none --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$helper"
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
echo "Signed by: $(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [ "$notarize" = 1 ]; then
    [ "$config" = release ] || { echo "error: --notarize is for the release build (a debug build carries test hooks)" >&2; exit 1; }
    profile="${SILL_NOTARY_PROFILE:-sill-notary}"
    zip=".build/Sill Viewer.zip"
    rm -f "$zip"; ditto -c -k --keepParent "$app" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"; ditto -c -k --keepParent "$app" "$zip"
    spctl -a -vv -t exec "$app"
fi
echo "Built $app ($config, $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"))"
[ "$open_after" = 1 ] && open "$app"
exit 0
