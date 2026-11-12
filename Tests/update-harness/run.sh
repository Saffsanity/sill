#!/bin/bash
# Update Now's mechanism end to end (docs/one-click-update-plan.md §11, G2), against scratch bundles
# only: UpdateInstaller and the pure files compiled with this harness's main.swift by swiftc; test apps
# (a tiny executable, signed ad hoc as me.saffer.sill.updater-test, versions 0.9 to 1.2) made here; a
# stand-in for GitHub (server.py) on 127.0.0.1; every hostile case refused for its reason with the
# installed copy's tree unchanged. With the genuine v0.6.1 zip from a read-only `gh release download`
# in .build/updater-scratch/release-v0.6.1, also the production trust (with this run's own update key)
# against Sill's real signature. Everything lives in .build/update-harness and is removed at the end
# unless --keep. Never /Applications, never a keychain, never Sill's defaults, never a launch of an app
# through Launch Services: the watcher's cases run the test app's own executable (launch.sh below).
#   Tests/update-harness/run.sh [--keep]
#   Tests/update-harness/mutants.py                one-line mutants of UpdateInstaller.swift; each must fail it
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/update-harness"
keep=0; [ "${1:-}" = "--keep" ] && keep=1
rm -rf "$out"; mkdir -p "$out"/{apps,zips,srv/assets,genuine,cases}
server=""
cleanup() {
    [ -n "$server" ] && kill "$server" 2>/dev/null || true
    for m in "$out"/mnt-*; do [ -d "$m" ] && hdiutil detach "$m" -force -quiet 2>/dev/null || true; done
    [ "$keep" = 1 ] || rm -rf "$out"
}
trap cleanup EXIT

echo "== building the harness"
T="$out/src"; mkdir -p "$T"
cp "$root"/Sources/StreamProtocol/*.swift "$T"/
# SILL_HARNESS_SOURCES: a copy of Sources/SillMenuBar with one change (mutants.py); the app's own by default.
sources="${SILL_HARNESS_SOURCES:-$root/Sources/SillMenuBar}"
for f in UpdatePolicy UpdateInstallPolicy UpdateManifest UpdateArchive UpdateAutoPolicy UpdateInstaller; do
    sed '/^import StreamProtocol$/d' "$sources/$f.swift" > "$T/$f.swift"
done
cp "$here/main.swift" "$T/main.swift"
# Named so its staging folders (NSIRD_updharness_…) are its own: the clean-up goes by the process name.
swiftc -O "$T"/*.swift -o "$out/updharness"

echo "== the test apps"
cat > "$out/updtest.swift" <<'SWIFT'
import Foundation
// The harness's stand-in app: prints its name, or sleeps (a process running from the bundle), first saying
// whether its own bundle is writable to it (access W_OK), as Sill's check of where it runs asks of itself.
let args = CommandLine.arguments
if args.count > 2, args[1] == "sleep", let s = Double(args[2]) {
    let bundle = URL(fileURLWithPath: args[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let ok = access(bundle.path, W_OK) == 0
    print("UpdTest running from \(bundle.lastPathComponent): its own bundle \(ok ? "writable" : "not writable (" + String(cString: strerror(errno)) + ")") to it")
    fflush(stdout)
    Thread.sleep(forTimeInterval: s)
}
// The watcher's cases (review 3, point 6): a new copy that proves itself (writes the started note's token
// after a while, then runs on), and the copy the watcher starts after a put-back (says which version it is).
if args.count > 4, args[1] == "started", let delay = Double(args[4]) {
    Thread.sleep(forTimeInterval: delay)
    try? (args[3] + "\n").write(toFile: args[2], atomically: true, encoding: .utf8)
    Thread.sleep(forTimeInterval: 6)
}
if args.count > 2, args[1] == "mark" {
    let info = URL(fileURLWithPath: args[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
    let version = (NSDictionary(contentsOf: info)?["CFBundleShortVersionString"] as? String) ?? "?"
    try? ("launched \(version)\n").write(toFile: args[2], atomically: true, encoding: .utf8)
}
print("UpdTest")
SWIFT
swiftc -O "$out/updtest.swift" -o "$out/updtest-bin"
# make_app LABEL VERSION BUILD [IDENTIFIER] [NOTE]
make_app() {
    local dir="$out/apps/$1" version=$2 build=$3 id=${4:-me.saffer.sill.updater-test} note=${5:-$1}
    local app="$dir/UpdTest.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$out/updtest-bin" "$app/Contents/MacOS/UpdTest"
    printf 'note %s\n' "$note" > "$app/Contents/Resources/note.txt"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>UpdTest</string>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>$build</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
    codesign -s - -i "$id" --options runtime --force "$app" 2>/dev/null
}
make_app installed 1.0 10
make_app v0.9 0.9 9
make_app v1.1 1.1 11
make_app v1.1b 1.1 11 me.saffer.sill.updater-test other-build
make_app v1.2 1.2 12
make_app other 1.1 11 me.saffer.sill.updater-other
make_app tampered-resource 1.1 11
printf 'changed after signing\n' > "$out/apps/tampered-resource/UpdTest.app/Contents/Resources/note.txt"
make_app tampered-executable 1.1 11
python3 -I -c "
import sys
p = sys.argv[1]
b = bytearray(open(p, 'rb').read()); b[len(b) // 2] ^= 0xFF; open(p, 'wb').write(b)" "$out/apps/tampered-executable/UpdTest.app/Contents/MacOS/UpdTest"

echo "== the zips"
for label in v0.9 v1.1 v1.1b v1.2 other tampered-resource tampered-executable; do
    (cd "$out/apps/$label" && ditto -c -k --keepParent UpdTest.app "$out/zips/$label.zip")
done
for c in plain appledouble traversal absolute link-escape link-through-link case-duplicate setuid not-a-bundle second-top; do
    python3 -I "$here/make-zip.py" "$out/apps/v1.1" "$out/zips/hostile-$c.zip" "$c"
done

genuine="$root/.build/updater-scratch/release-v0.6.1/Sill.zip"
if [ -f "$genuine" ]; then
    echo "== the genuine v0.6.1 and its variants (never launched)"
    g="$out/genuine"
    for v in plain tampered adhoc unstapled installed; do
        mkdir -p "$g/$v"
        ditto -x -k --norsrc --noextattr --noqtn "$genuine" "$g/$v/"
    done
    printf 'X' | dd of="$g/tampered/Sill.app/Contents/Resources/AppIcon.icns" bs=1 seek=4000 conv=notrunc 2>/dev/null
    codesign -f -s - --preserve-metadata=identifier,entitlements,flags,runtime "$g/adhoc/Sill.app" 2>/dev/null
    codesign -f -s - --preserve-metadata=identifier,entitlements,flags,runtime "$g/installed/Sill.app" 2>/dev/null
    rm "$g/unstapled/Sill.app/Contents/CodeResources"
    cp "$genuine" "$g/plain.zip"
    for v in tampered adhoc unstapled; do (cd "$g/$v" && ditto -c -k --keepParent Sill.app "$g/$v.zip"); done
fi

# The watcher's launcher here (Sill.app's is /usr/bin/open): the put-back copy's own executable, which says
# which version it is; never Launch Services.
cat > "$out/launch.sh" <<'SH'
#!/bin/sh
"$1/Contents/MacOS/UpdTest" mark "$(/usr/bin/dirname "$1")/launched.txt" &
SH
chmod +x "$out/launch.sh"

echo "== the stand-in for GitHub on 127.0.0.1"
echo '{}' > "$out/srv/control.json"
python3 -I "$here/server.py" "$out/srv" "$out/port" &
server=$!
for _ in $(seq 50); do [ -f "$out/port" ] && break; sleep 0.1; done
[ -f "$out/port" ] || { echo "the server did not start" >&2; exit 1; }

echo "== the cases"
"$out/updharness" "$out"
