#!/bin/bash
# P1 (docs/camera-plan.md §13.4): Sill.app with Sill Camera inside, as Scripts/make-app.sh builds it with
# SILL_CAMERA_EXTENSION=1, signed ad hoc into a folder of its own (SILL_APP_OUT), and checked: the extension's place and
# name; its Info.plist (its identifier under the app's, SYSX, its executable, Core Media I/O's Mach service name, the
# usage words, the app's version, build and macOS floor); the Mach service name inside the extension's app group; its
# entitlements (the App Sandbox and that group, nothing else) and the app's (no system-extension.install in a build that
# is not Developer ID, so it can't activate it); both signatures, strictly, the app's deep; the app's seal covering the
# extension (a changed byte in a copy of it fails the app's check); the hardened runtime on both; the same slices in
# both (arm64 and x86_64 with --universal). It never copies anything to /Applications, never activates or runs what it
# built, and installs nothing: the bundle is removed after its checks (--keep keeps it in OUT).
#   Scripts/camera-check/package.sh [--universal] [--keep] [OUT]   (OUT: .build/camera-check by default)
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
universal=0; keep=0; out=""
for a in "$@"; do
    case "$a" in
        --universal) universal=1 ;;
        --keep) keep=1 ;;
        -*) echo "usage: $0 [--universal] [--keep] [OUT]" >&2; exit 2 ;;
        *) out="$a" ;;
    esac
done
out="${out:-$root/.build/camera-check}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
case "$out" in
    /Applications|/Applications/*|"$HOME/Applications"|"$HOME/Applications/"*) echo "refused: $out is an Applications folder" >&2; exit 2 ;;
esac
app="$out/Sill.app"
cam_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Packaging/CameraExtension-Info.plist)"
ext="$app/Contents/Library/SystemExtensions/$cam_id.systemextension"
installed_before="$(stat -f %m /Applications/Sill.app 2>/dev/null || echo none)"
passed=0; failed=0
judge() { if [ "$1" = 0 ]; then passed=$((passed + 1)); echo "ok   $2"; else failed=$((failed + 1)); echo "FAIL $2"; fi; }
is() { [ "$1" = "$2" ]; echo $?; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

rm -rf "$app" "$app.partial" "$out/tamper"
echo "building $app (ad hoc, $([ "$universal" = 1 ] && echo "arm64 and x86_64" || echo "this Mac's architecture")); the log is $out/make-app.log"
both=""
if [ "$universal" = 1 ]; then both=1; fi
env SILL_CAMERA_EXTENSION=1 SILL_SIGN_IDENTITY=- SILL_APP_OUT="$app" SILL_UNIVERSAL="$both" \
    Scripts/make-app.sh > "$out/make-app.log" 2>&1 || { tail -30 "$out/make-app.log"; echo "FAIL make-app.sh"; exit 1; }
grep -E '^Built |Sill Camera:' "$out/make-app.log" || true

# The place and the name.
judge "$( [ -d "$ext" ]; echo $?)" "Sill Camera at Contents/Library/SystemExtensions/$cam_id.systemextension"
judge "$(is "$(ls "$app/Contents/Library/SystemExtensions" | xargs)" "$cam_id.systemextension")" "the only thing in SystemExtensions"
app_id="$(plist "$app/Contents/Info.plist" CFBundleIdentifier)"
info="$ext/Contents/Info.plist"
judge "$(is "$(plist "$info" CFBundleIdentifier)" "$app_id.camera")" "its identifier, $cam_id, under the app's ($app_id)"
judge "$(is "$(plist "$info" CFBundlePackageType)" SYSX)" "a system extension's package type (SYSX)"
exe="$ext/Contents/MacOS/$(plist "$info" CFBundleExecutable)"
judge "$( [ -f "$exe" ] && [ -x "$exe" ]; echo $?)" "its executable, $(basename "$exe")"
mach="$(plist "$info" CMIOExtension:CMIOExtensionMachServiceName)"
judge "$(is "$mach" "9B2KKVM937.$cam_id")" "Core Media I/O's Mach service name: $mach"
judge "$( [ -n "$(plist "$info" NSSystemExtensionUsageDescription)" ]; echo $?)" "the usage words macOS shows (NSSystemExtensionUsageDescription)"
for key in CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    judge "$(is "$(plist "$info" "$key")" "$(plist "$app/Contents/Info.plist" "$key")")" "the app's $key ($(plist "$info" "$key"))"
done

# Entitlements, read from the signatures.
codesign -d --entitlements - --xml "$ext" > "$out/ext-entitlements.plist" 2>/dev/null || true
codesign -d --entitlements - --xml "$app" > "$out/app-entitlements.plist" 2>/dev/null || true
ents="$out/ext-entitlements.plist"
judge "$(is "$(plist "$ents" com.apple.security.app-sandbox)" true)" "Sill Camera is sandboxed (com.apple.security.app-sandbox)"
group="$(plist "$ents" com.apple.security.application-groups:0)"
judge "$(is "$group" "9B2KKVM937.$cam_id")" "its app group: $group"
judge "$(is "$(plist "$ents" com.apple.security.application-groups:1)" "")" "one app group"
judge "$( [ -n "$group" ] && [ "${mach#"$group"}" != "$mach" ]; echo $?)" "the Mach service name begins with that app group"
keys="$(plutil -convert json -o - "$ents" 2>/dev/null | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))' 2>/dev/null || true)"
judge "$(is "$keys" "com.apple.security.app-sandbox com.apple.security.application-groups")" "nothing else in its entitlements ($keys)"
judge "$( ! grep -q 'system-extension.install' "$out/app-entitlements.plist"; echo $?)" "an ad hoc Sill.app does not ask for system-extension.install, so it can't activate Sill Camera"

# The signatures.
judge "$(codesign --verify --strict "$ext" >/dev/null 2>&1; echo $?)" "Sill Camera's signature, strictly"
judge "$(codesign --verify --strict --deep "$app" >/dev/null 2>&1; echo $?)" "the app's signature, strictly and deep"
for code in "$app" "$ext"; do
    details="$(codesign -dvvv "$code" 2>&1 || true)"
    judge "$(grep -q '^CodeDirectory .*flags=.*runtime' <<<"$details"; echo $?)" "$(basename "$code"): the hardened runtime"
    judge "$(grep -q '^Signature=adhoc' <<<"$details"; echo $?)" "$(basename "$code"): signed ad hoc"
done
mkdir -p "$out/tamper"
ditto "$app" "$out/tamper/Sill.app"
printf '\n' >> "$out/tamper/Sill.app/Contents/Library/SystemExtensions/$cam_id.systemextension/Contents/Info.plist"
judge "$( ! codesign --verify --strict --deep "$out/tamper/Sill.app" >/dev/null 2>&1; echo $?)" "a changed byte in Sill Camera breaks the app's signature (the app seals it)"
rm -rf "$out/tamper"

# The slices.
app_archs="$(lipo -archs "$app/Contents/MacOS/$(plist "$app/Contents/Info.plist" CFBundleExecutable)" | tr ' ' '\n' | sort | xargs)"
ext_archs="$(lipo -archs "$exe" | tr ' ' '\n' | sort | xargs)"
judge "$(is "$ext_archs" "$app_archs")" "the app's slices in Sill Camera ($ext_archs)"
if [ "$universal" = 1 ]; then
    judge "$(is "$ext_archs" "arm64 x86_64")" "both architectures (SILL_UNIVERSAL=1)"
fi

# Nothing installed.
judge "$(is "$(stat -f %m /Applications/Sill.app 2>/dev/null || echo none)" "$installed_before")" "/Applications/Sill.app untouched"
if [ "$keep" = 1 ]; then echo "kept: $app"; else rm -rf "$app"; echo "removed $app"; fi
echo "P1: $passed of $((passed + failed)) ok"
[ "$failed" = 0 ]
