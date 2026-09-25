#!/bin/bash
# Builds Sill.app, the menu bar Mac host, from this SwiftPM package.
#
#   Scripts/make-app.sh                    .build/Sill.app, signed with your Apple Development identity
#   Scripts/make-app.sh --install          …then replace /Applications/Sill.app (a running copy quits first)
#   Scripts/make-app.sh --install --open   …and launch it: Noah's one command after any change
#   SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release
#                                          (M6; refused unless HEAD carries the tag v‹version› and
#                                          the signature is Developer ID)
#   SILL_INSTALL_DIR=~/Applications Scripts/make-app.sh --install   (another install folder)
#
# Why a script: SwiftPM builds executables, not app bundles, and everything the host needs from
# macOS belongs to an app bundle. Screen Recording, Accessibility, Local Network and Login Items
# are granted to the CFBundleIdentifier plus the code's designated requirement. So: swift build,
# wrap the SillMenuBar executable with Packaging/Info.plist and an icon compiled from
# design/AppIcon.svg, sign the whole bundle last, verify.
#
# Grants survive rebuilds only with a real identity: its designated requirement names the bundle ID
# and the certificate, not this binary. Ad hoc ("-") is a hash of this exact build, so every
# rebuild would silently lose Screen Recording and Accessibility.
set -euo pipefail
cd "$(dirname "$0")/.."

install=0; open_app=0; release=0
for arg in "$@"; do
    case "$arg" in
        --install) install=1 ;;
        --open) open_app=1 ;;
        --release) release=1 ;;
        *) echo "usage: $0 [--install] [--open] [--release]" >&2; exit 2 ;;
    esac
done
# --release is for notarization, which accepts only a Developer ID Application signature and says
# so only after the upload. The default identity is Apple Development, so without
# SILL_SIGN_IDENTITY stop now, before building; the signature itself is checked after signing.
if [ "$release" = 1 ] && [ -z "${SILL_SIGN_IDENTITY:-}" ]; then
    echo "error: --release needs SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)'" >&2
    exit 2
fi
# A release is built only from the commit its tag names: the tag is "v" + Packaging/Info.plist's
# CFBundleShortVersionString (v0.4.0 for 0.4.0), and every Sill.app's update check compares the
# latest release's tag on GitHub with the version it runs (Sources/SillMenuBar/UpdatePolicy.swift).
if [ "$release" = 1 ]; then
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
    tags="$(git tag --points-at HEAD 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
    if ! git tag --points-at HEAD 2>/dev/null | grep -qx "v$version"; then
        echo "error: --release builds only a commit tagged v$version (HEAD is tagged '${tags:-nothing}'): the update check compares the release's tag with this version." >&2
        exit 2
    fi
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Packaging/Info.plist)"

swift build -c release --product SillMenuBar
bin="$(swift build -c release --product SillMenuBar --show-bin-path)"
app=.build/Sill.app
stage=.build/Sill.app.partial      # assembled aside, so a failed run never leaves half a bundle
rm -rf "$stage"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
# The executable, with the SDK it was compiled against recorded in it. SwiftPM links without
# SDKROOT, so the linker records the deployment target (14.0) as the SDK, and macOS 26 and later
# then draw the whole app in the look of a pre-26 app (Settings' sections, buttons, pop-ups and
# segmented controls). vtool writes the copy with the build version an Xcode build would have:
# minos from the binary, sdk from the SDK in use. The signature this breaks is replaced below.
minos="$(xcrun vtool -show-build "$bin/SillMenuBar" | awk '$1 == "minos" && !found { print $2; found = 1 }')"
xcrun vtool -set-build-version macos "${minos:?vtool reported no deployment target for $bin/SillMenuBar}" \
    "$(xcrun --sdk macosx --show-sdk-version)" -output "$stage/Contents/MacOS/Sill" "$bin/SillMenuBar"
cp Packaging/Info.plist "$stage/Contents/Info.plist"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$stage/Contents/Info.plist"
printf 'APPL????' > "$stage/Contents/PkgInfo"

# The icon. design/AppIcon.svg is the iOS art, a full-bleed square. macOS 26+ masks and lights a
# full-bleed icon itself when it comes from an asset catalog, but shows a legacy .icns shrunk
# inside a grey tile (seen on macOS 27). So Quick Look renders the SVG (design/README.md's own
# tool), the render becomes the one layer of an Icon Composer document, and actool, the compiler
# Xcode uses, turns that into Assets.car (macOS 26+) plus an AppIcon.icns masked for macOS 14–15.
# A layered Packaging/AppIcon.icon made in Icon Composer (the SVG's four groups) wins when it
# exists. Cached in .build/icon until the SVG, that document or this script changes.
icon_out="$PWD/.build/icon"   # absolute: actool resolves relative paths in its helper's directory, not ours
if [ ! -f "$icon_out/compiled/Assets.car" ] || [ design/AppIcon.svg -nt "$icon_out/compiled/Assets.car" ] \
   || [ "$0" -nt "$icon_out/compiled/Assets.car" ] \
   || { [ -d Packaging/AppIcon.icon ] && [ -n "$(find Packaging/AppIcon.icon -newer "$icon_out/compiled/Assets.car" 2>/dev/null)" ]; }; then
    rm -rf "$icon_out"; mkdir -p "$icon_out/compiled"
    if [ -d Packaging/AppIcon.icon ]; then
        doc="$PWD/Packaging/AppIcon.icon"
    else
        doc="$icon_out/AppIcon.icon"
        mkdir -p "$doc/Assets"
        qlmanage -t -s 1024 -o "$icon_out" "$PWD/design/AppIcon.svg" >/dev/null 2>&1 || true
        mv "$icon_out/AppIcon.svg.png" "$doc/Assets/Sill.png" 2>/dev/null || true
        cat > "$doc/icon.json" <<'JSON'
{
  "fill" : { "solid" : "srgb:0.00000,0.00000,0.00000,1.00000" },
  "groups" : [ { "layers" : [ { "image-name" : "Sill.png", "name" : "Sill" } ] } ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON
    fi
    if [ -f "$doc/icon.json" ] && { [ "$doc" = "$PWD/Packaging/AppIcon.icon" ] || [ -f "$doc/Assets/Sill.png" ]; }; then
        xcrun actool --compile "$icon_out/compiled" --platform macosx --minimum-deployment-target 14.0 \
            --app-icon AppIcon --output-partial-info-plist "$icon_out/partial.plist" "$doc" >/dev/null \
            || echo "warning: actool could not compile the icon; Sill.app gets the generic icon" >&2
    else
        echo "warning: Quick Look did not render design/AppIcon.svg; Sill.app gets the generic icon" >&2
    fi
fi
cp "$icon_out"/compiled/* "$stage/Contents/Resources/" 2>/dev/null || true

# SILL_SIGN_IDENTITY (a name, part of one, or a SHA-1 hash), else the first Apple Development
# identity in the keychain, by its SHA-1 hash: codesign refuses a name that two valid
# certificates share, as they do after an early renewal until the old one expires. Either of them
# keeps the grants, because the designated requirement names the leaf certificate's common name,
# which a renewal keeps. (`|| true`: no keychain or no match must fall through to the ad hoc
# warning below, not end the script under `set -e`.)
identity="${SILL_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $2; exit }' || true)}"
if [ -z "$identity" ]; then
    identity="-"
    echo "warning: no Apple Development identity in the keychain; signing ad hoc. Screen Recording and" >&2
    echo "         Accessibility will have to be granted again after every rebuild." >&2
fi
if [ "$release" = 1 ]; then
    # Developer ID: hardened runtime and a secure timestamp (notarization needs both), no get-task-allow.
    codesign --force --options runtime --timestamp --sign "$identity" "$stage"
else
    # get-task-allow lets lldb and Xcode's Attach to Process attach to the hardened app.
    codesign --force --options runtime --timestamp=none --entitlements Packaging/SillDebug.entitlements --sign "$identity" "$stage"
fi
codesign --verify --strict "$stage"
# Who signed it, read from the signature: the leaf certificate's name, empty for ad hoc.
signer="$(codesign -dv --verbose=2 "$stage" 2>&1 | sed -n 's/^Authority=//p' || true)"
signer="${signer%%$'\n'*}"
if [ "$release" = 1 ] && [[ "$signer" != "Developer ID Application: "* ]]; then
    rm -rf "$stage"
    echo "error: --release is for notarization, which accepts only a Developer ID Application signature;" >&2
    echo "       this one is '${signer:-ad hoc}'. Nothing was replaced." >&2
    exit 1
fi
rm -rf "$app"
mv "$stage" "$app"
echo "Built $app, version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") ($build_number), signed by: ${signer:-ad hoc}"
codesign -d -r- "$app" 2>&1 | sed -n 's/^# *designated => /  designated requirement: /p; s/^designated => /  designated requirement: /p'

dest="${SILL_INSTALL_DIR:-/Applications}/Sill.app"
if [ "$install" = 1 ]; then
    # An iPad build of the iOS client installed on this Mac would also be a Sill.app: never replace
    # anything that is not this app.
    if [ -e "$dest" ]; then
        existing="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$dest/Contents/Info.plist" 2>/dev/null || true)"
        if [ "$existing" != "$bundle_id" ]; then
            echo "error: $dest is not the Mac host (bundle ID '${existing:-unknown}', expected '$bundle_id'); leaving it alone." >&2
            exit 1
        fi
    fi
    # Quit a running Sill.app first. SIGTERM goes through HostShutdown, which puts a staged window
    # back. The pattern matches Mac bundles only: the iOS Simulator's Sill.app is flat, and
    # `pkill -x Sill` would kill it too.
    if pgrep -f 'Sill\.app/Contents/MacOS/Sill' >/dev/null; then
        pkill -TERM -f 'Sill\.app/Contents/MacOS/Sill' || true
        for _ in $(seq 1 50); do pgrep -f 'Sill\.app/Contents/MacOS/Sill' >/dev/null || break; sleep 0.1; done
    fi
    rm -rf "$dest"
    ditto "$app" "$dest"
    # One registered Sill: LaunchServices (the login item, `open -b`, Spotlight) must not pick the
    # copy in .build.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$app" 2>/dev/null || true
    echo "Installed $dest"
fi
if [ "$open_app" = 1 ]; then
    if [ -d "$dest" ]; then open "$dest"; else echo "error: $dest is not installed; run with --install" >&2; exit 1; fi
fi
