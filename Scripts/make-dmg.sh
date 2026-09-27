#!/bin/bash
# Makes Sill.dmg, the disk image Sill for Mac is downloaded in: its window shows Sill.app beside a
# link to Applications, over a background with an arrow from the one to the other, so installing is
# the drag every Mac app asks for. Scripts/release.sh makes it from the notarized, stapled app and
# signs it with the same Developer ID; the release workflow's verify job, from the ad hoc app.
#
#   Scripts/make-dmg.sh --sign IDENTITY APP DMG
#       IDENTITY is a Developer ID Application identity as codesign takes it (its name, part of it,
#       or its SHA-1 hash), or - to sign ad hoc (the release workflow's verify job has no identity).
#       APP is a signed Sill.app; DMG the image to write, replaced if it exists.
#   Scripts/make-dmg.sh --prepare
#       only compiles the layout tool and renders the background (both cached in .build/dmg), so
#       release.sh finds a problem with either before it sends anything to Apple.
#
# What goes in, and why:
# - HFS+ (hdiutil's "Mac OS Extended", without a journal: nothing writes to a download), not APFS.
#   Finder names the background picture by an alias that expects HFS+ ("H+", 32-bit file IDs, the
#   volume's creation date as HFS+ keeps it), and the images this layout was checked against are
#   all HFS+: a Finder-made installer image of 2023, Claude's of September 2026 (the same .DS_Store
#   blocks as Finder's) and Apple's own Game Porting Toolkit 4.0 image. Every macOS Sill runs on (14
#   and later) mounts either, and APFS brings nothing a small read-only image uses.
# - ULFO, read-only and compressed with LZFSE, Apple's own compressor: it decompresses fastest, and
#   Sill's image is about 3 MB (ULMO, LZMA, would save about 0.4 MB; UDZO, zlib, is for Macs older
#   than OS X 10.11). hdiutil verify checks its checksum.
# - The window's layout is a .DS_Store that Scripts/dmg-layout/ (Swift, compiled here into
#   .build/dmg) writes from the numbers below, without Finder: laying it out through Finder would
#   take AppleScript, which asks for Automation permission, and a logged-in session showing the
#   window. dmg-layout then reads it back from the finished image (`check`): the records, the
#   background's alias leading to the picture wherever the image is mounted, the picture's sizes,
#   the volume icon. Window: design/DMGBackground.svg's 660 x 400 points plus macOS 27's 32-point
#   title bar (DMGLayout.titleBar says why), icon view, no toolbar, sidebar or status bar, 128-point
#   icons, Sill.app at (170, 180) and Applications at (490, 180), the ends of the SVG's arrow;
#   .background and .VolumeIcon.icns placed below the window, for anyone who shows hidden files.
#   Tests/checks/dmg-layout checks the layout tool's .DS_Store and alias against these numbers.
# - The background: design/DMGBackground.svg, rendered by Quick Look at 660 and 1320 pixels wide
#   (design/README.md's tool; the app icon is made the same way), cropped to the picture (Quick Look
#   renders into a square), joined by tiffutil into one TIFF that holds both, so the window is sharp
#   on Retina screens. Cached in .build/dmg until the SVG, this script or dmg-layout changes.
# - The volume's icon: the app's AppIcon.icns (make-app.sh's, masked like the app icon) as
#   .VolumeIcon.icns, with the custom-icon flag on the volume's root.
# - The image is signed last (codesign, identifier me.saffer.sill.dmg), then checked: hdiutil
#   verify, codesign --verify, and mounted read-only: exactly Sill.app, Applications (a link to
#   /Applications), .background, .VolumeIcon.icns and .DS_Store at its root, the layout, and a
#   Sill.app that passes codesign --verify --deep --strict and is byte for byte the APP given
#   (the stapled ticket included). release.sh then has Apple notarize the image and staples it.
#
# The image is attached without Finder seeing it (-nobrowse) and mounted in a new folder in the
# temporary folder (-mountrandom), never at /Volumes/Sill, which a copy someone has open may hold.
# The temporary folder also keeps .fseventsd off the image: macOS's fseventsd writes its event log
# into a volume mounted under the home folder as it unmounts (seen under .build on macOS 27, never
# under $TMPDIR or /private/tmp), and the check below refuses any file it didn't put there.
set -euo pipefail

volume_name=Sill
window=660x400          # design/DMGBackground.svg's size: the window's content, in points
position=200,120        # the window's top-left corner on the screen
icon_size=128
text_size=12
edge=ffffff             # the SVG's every edge: shown where the window is larger than the picture
layout=(
    --window "$window" --position "$position" --icon-size "$icon_size" --text-size "$text_size"
    --background .background/background.tiff --background-color "$edge"
    --item Sill.app=170,180 --item Applications=490,180
    --hidden .background --hidden .VolumeIcon.icns
)
expected_root=".DS_Store .VolumeIcon.icns .background Applications Sill.app"

say() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# This script, wherever it was started from: the background's cache follows its changes.
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

usage() {
    sed -n '2,14p' "$self" | sed 's/^# \{0,1\}//'
}

tool=.build/dmg/dmg-layout
mounts=""              # the folder the image is mounted in while it's made and checked (in $TMPDIR)
attached=()            # devices to detach on the way out

# hdiutil with a second and third try: on a busy machine (a CI runner, Spotlight looking at a new
# volume) create, attach, detach and convert can fail once with "Resource busy".
hdiutil_retrying() {
    local try output
    for try in 1 2 3; do
        if output="$(hdiutil "$@" 2>&1)"; then
            printf '%s\n' "$output"
            return 0
        fi
        sleep 2
    done
    printf '%s\n' "$output" >&2
    return 1
}

# Attaches the image $1 (read-write with $2 = rw) and sets `device` and `mounted`.
attach() {
    local image="$1" mode="${2:-ro}" output line
    local options=(-nobrowse -noautoopen -noverify -mountrandom "$mounts")
    if [ "$mode" = rw ]; then options+=(-readwrite); else options+=(-readonly); fi
    # The output also holds macOS 27's warning that attach -nobrowse is deprecated for `diskutil
    # image attach`; only the /dev/disk lines are read.
    output="$(hdiutil_retrying attach "${options[@]}" "$image")" || fail "hdiutil can't attach $image"
    # The image's own device (the first /dev/disk line, whatever the image holds) is recorded before
    # anything else is checked, so the way out detaches it even when no HFS+ volume turned up.
    device="$(printf '%s\n' "$output" | awk -F'\t' '$1 ~ /^\/dev\/disk/ { sub(/[ \t]+$/, "", $1); print $1; exit }')"
    if [ -n "$device" ]; then attached+=("$device"); fi
    line="$(printf '%s\n' "$output" | awk -F'\t' '$2 ~ /Apple_HFS/ { print; exit }')"
    mounted="$(printf '%s' "$line" | awk -F'\t' '{ print $NF }')"
    if [ -z "$device" ] || [ -z "$line" ] || [ ! -d "$mounted" ]; then
        printf '%s\n' "$output" >&2
        fail "hdiutil attached $image but mounted no HFS+ volume"
    fi
}

detach() {
    local device="$1" try
    for try in 1 2 3 4 5; do
        if hdiutil detach "$device" -quiet 2>/dev/null; then break; fi
        if [ "$try" = 5 ]; then hdiutil detach "$device" -force -quiet || return 1; fi
        sleep 1
    done
    local kept=() d
    for d in ${attached[@]+"${attached[@]}"}; do [ "$d" != "$device" ] && kept+=("$d"); done
    attached=(${kept[@]+"${kept[@]}"})
}

cleanup() {
    local d
    for d in ${attached[@]+"${attached[@]}"}; do hdiutil detach "$d" -force -quiet 2>/dev/null || true; done
    if [ -n "$mounts" ]; then rmdir "$mounts" 2>/dev/null || true; fi
}

# The layout tool, compiled when a source is newer than it.
build_tool() {
    local source stale=0
    for source in Scripts/dmg-layout/*.swift; do
        if [ ! -x "$tool" ] || [ "$source" -nt "$tool" ]; then stale=1; fi
    done
    if [ "$stale" = 1 ]; then
        mkdir -p .build/dmg
        xcrun swiftc -O -o "$tool.partial" Scripts/dmg-layout/*.swift || fail "Scripts/dmg-layout didn't compile"
        mv "$tool.partial" "$tool"
    fi
}

# .build/dmg/background.tiff from design/DMGBackground.svg: Quick Look renders it at 1x and 2x into
# squares, dmg-layout crops each to the picture, tiffutil joins them (the 2x marked 144 dpi).
render_background() {
    local svg=design/DMGBackground.svg out=.build/dmg/background.tiff work=.build/dmg/background
    local width="${window%x*}" height="${window#*x}"
    # Made again only when one of them is newer than it (whole seconds: a render in the second the
    # tool was built still counts).
    if [ -f "$out" ] && ! [ "$svg" -nt "$out" ] && ! [ "$self" -nt "$out" ] && ! [ "$tool" -nt "$out" ]; then return 0; fi
    rm -rf "$work" "$out"
    mkdir -p "$work/1x" "$work/2x"
    qlmanage -t -s "$width" -o "$work/1x" "$PWD/$svg" >/dev/null 2>&1 || true
    qlmanage -t -s "$((width * 2))" -o "$work/2x" "$PWD/$svg" >/dev/null 2>&1 || true
    if [ ! -f "$work/1x/DMGBackground.svg.png" ] || [ ! -f "$work/2x/DMGBackground.svg.png" ]; then
        fail "Quick Look didn't render $svg (qlmanage -t -s $width -o $work/1x $svg shows why)"
    fi
    "$tool" crop "$work/1x/DMGBackground.svg.png" "$work/background.png" "${width}x${height}"
    "$tool" crop "$work/2x/DMGBackground.svg.png" "$work/background@2x.png" "$((width * 2))x$((height * 2))"
    local joined
    joined="$(tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out "$out.partial" 2>&1)" \
        || { printf '%s\n' "$joined" >&2; fail "tiffutil couldn't join the 1x and 2x backgrounds"; }
    mv "$out.partial" "$out"
    rm -rf "$work"
}

megabytes() { awk -v b="$1" 'BEGIN { printf "%.1f MB", b / 1000000 }'; }

main() {
    local identity="" set_identity=0 prepare=0 args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --sign) [ $# -ge 2 ] || { usage >&2; exit 2; }; identity="$2"; set_identity=1; shift 2 ;;
            --prepare) prepare=1; shift ;;
            -h|--help) usage; exit 0 ;;
            -*) usage >&2; exit 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done
    if [ "$prepare" = 1 ]; then
        if [ "$set_identity" = 1 ] || [ ${#args[@]} -ne 0 ]; then usage >&2; exit 2; fi
        cd "$(dirname "$self")/.."
        build_tool
        render_background
        echo "The disk image's layout tool and background are ready ($tool, .build/dmg/background.tiff)."
        return 0
    fi
    if [ "$set_identity" = 0 ] || [ -z "$identity" ] || [ ${#args[@]} -ne 2 ]; then usage >&2; exit 2; fi
    local app="${args[0]}" dmg="${args[1]}"
    # Absolute paths before leaving the caller's folder.
    [ -d "$app" ] || fail "$app is not an app bundle"
    app="$(cd "$app" && pwd)"
    mkdir -p "$(dirname "$dmg")"
    dmg="$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")"
    cd "$(dirname "$self")/.."

    [ -f "$app/Contents/Info.plist" ] || fail "$app has no Contents/Info.plist"
    [ -f "$app/Contents/Resources/AppIcon.icns" ] || fail "$app has no AppIcon.icns for the volume's icon (make-app.sh's warning says why)"
    codesign --verify --strict "$app" 2>/dev/null || fail "$app is not validly signed (codesign --verify --strict $app)"
    local version build
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || echo '?')"

    build_tool
    render_background

    local work=.build/dmg/work
    rm -rf "$work"
    mkdir -p "$work"
    trap cleanup EXIT
    mounts="$(mktemp -d "${TMPDIR:-/tmp}/sill-dmg.XXXXXX")"

    # Room for the app, the picture and the icon; the compressed image doesn't keep the free space.
    local kilobytes megs
    kilobytes="$(du -sk "$app" | awk '{ print $1 }')"
    megs=$((kilobytes / 1024 + 16))
    say "Making the disk image: Sill $version ($build) beside Applications, on $window points of background"
    hdiutil_retrying create -ov -size "${megs}m" -fs HFS+ -volname "$volume_name" -nospotlight -type UDIF \
        "$work/rw.dmg" >/dev/null || fail "hdiutil can't create a ${megs} MB HFS+ image"
    attach "$work/rw.dmg" rw
    local writable="$mounted" writable_device="$device"
    ditto "$app" "$writable/Sill.app"
    ln -s /Applications "$writable/Applications"
    mkdir "$writable/.background"
    cp .build/dmg/background.tiff "$writable/.background/background.tiff"
    cp "$app/Contents/Resources/AppIcon.icns" "$writable/.VolumeIcon.icns"
    "$tool" write "$writable" "${layout[@]}" >/dev/null
    detach "$writable_device" || fail "hdiutil can't detach the image being made ($writable_device)"

    hdiutil_retrying convert -ov "$work/rw.dmg" -format ULFO -o "$work/Sill.dmg" >/dev/null || fail "hdiutil can't compress the image"
    rm -f "$work/rw.dmg"

    # Signed: Developer ID with a secure timestamp, as notarization requires; ad hoc without one.
    local timestamp=--timestamp
    if [ "$identity" = - ]; then timestamp=--timestamp=none; fi
    codesign --force --sign "$identity" "$timestamp" --identifier me.saffer.sill.dmg "$work/Sill.dmg" \
        || fail "codesign can't sign the image with '$identity'"

    say "Checking the image"
    check_image "$work/Sill.dmg" "$app"
    mv "$work/Sill.dmg" "$dmg"
    rm -rf "$work"
    local signer bytes
    signer="$(codesign -dvv "$dmg" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    bytes="$(stat -f %z "$dmg")"
    echo "Made $dmg ($(megabytes "$bytes")), signed by: ${signer:-ad hoc}"
}

# The finished image, as someone who downloads it gets it. $1 the image, $2 the app that went in.
check_image() {
    local image="$1" app="$2" details root signer
    hdiutil verify "$image" >/dev/null 2>&1 || fail "hdiutil verify: $image's checksum is wrong"
    codesign --verify --strict "$image" 2>/dev/null || fail "codesign can't verify $image"
    details="$(codesign -dvv "$image" 2>&1)"
    grep -q '^Format=disk image' <<<"$details" || fail "$image's signature is not a disk image's"
    signer="$(sed -n 's/^Authority=//p' <<<"$details" | head -1)"
    if [ -n "$signer" ] && ! grep -q '^Timestamp=' <<<"$details"; then fail "$image has no secure timestamp"; fi

    attach "$image" ro
    root="$(ls -A "$mounted" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
    [ "$root" = "$(tr ' ' '\n' <<<"$expected_root" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" ] \
        || fail "the image holds '$root', not '$expected_root'"
    [ -L "$mounted/Applications" ] && [ "$(readlink "$mounted/Applications")" = /Applications ] \
        || fail "the image's Applications is not a link to /Applications"
    "$tool" check "$mounted" "${layout[@]}"
    codesign --verify --deep --strict "$mounted/Sill.app" 2>/dev/null || fail "the image's Sill.app doesn't pass codesign --verify --deep --strict"
    diff -r "$app" "$mounted/Sill.app" >/dev/null || fail "the image's Sill.app differs from $app"
    local volume
    volume="$(df -k "$mounted" | awk 'NR == 2 { printf "%.1f MB used of %.1f MB", $3 / 1024, $2 / 1024 }')"
    echo "Sill.app is $app's, byte for byte, and passes codesign; the volume: $volume; the image's signature: ${signer:-ad hoc}."
    detach "$device" || fail "hdiutil can't detach $image"
}

# Sourced (to test its functions), the script only defines them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
