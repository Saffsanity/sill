#!/bin/bash
# The pictures Settings' App Icon group shows (iOSClient/AppIconPicker.swift, AppIconChoice.previewImageName):
# each Icon Composer document in Packaging/ (AppIcon.icon, AppIconCommunity.icon, …) rendered by Icon
# Composer's own tool in its iOS Default look, the squircle and the glass included, into
# iOSClient/Assets.xcassets/<name>Preview.imageset. Run it after changing a document, and commit what it
# writes; Tests/checks/app-icon checks each choice has its picture (docs/app-icons-plan.md).
#
#   Scripts/app-icon-previews.sh             render every document's preview
#   Scripts/app-icon-previews.sh --looks DIR also every look (iOS and macOS: Default, Dark, ClearLight,
#                                            ClearDark, TintedLight, TintedDark) of each, 1024 px, into DIR
#
# Needs Xcode 26 or later (Icon Composer.app inside it); reads the documents, writes only those files.
set -euo pipefail
cd "$(dirname "$0")/.."

looks=""
case "${1:-}" in
    --looks) looks="${2:?--looks needs a folder}" ;;
    "") ;;
    *) echo "usage: $0 [--looks DIR]" >&2; exit 2 ;;
esac

ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ictool" ] || { echo "error: no Icon Composer in $(xcode-select -p)/../Applications (Xcode 26 or later)" >&2; exit 1; }

# 96 pt at 3x: the tile's picture grows with the text size from 60 pt, up to the third accessibility size.
size=288
for doc in Packaging/*.icon; do
    name="$(basename "$doc" .icon)"
    set_dir="iOSClient/Assets.xcassets/${name}Preview.imageset"
    mkdir -p "$set_dir"
    "$ictool" "$PWD/$doc" --export-image --output-file "$PWD/$set_dir/${name}Preview.png" --platform iOS \
        --rendition Default --width "$size" --height "$size" --scale 1 >/dev/null
    cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "${name}Preview.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
    echo "$set_dir/${name}Preview.png"
    if [ -n "$looks" ]; then
        mkdir -p "$looks/$name"
        for platform in iOS macOS; do
            for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
                "$ictool" "$PWD/$doc" --export-image --output-file "$looks/$name/$platform-$rendition.png" \
                    --platform "$platform" --rendition "$rendition" --width 1024 --height 1024 --scale 1 >/dev/null
            done
        done
        echo "$looks/$name: 12 looks"
    fi
done
