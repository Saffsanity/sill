#!/bin/bash
# Signs tonight's nightly for Update Now (docs/one-click-update-plan.md §16; docs/release-checklist.md,
# Nightlies). The nightly key is not the update key: it is a GitHub Actions secret of the environment
# `nightly` (SILL_NIGHTLY_UPDATE_KEY), held for nightly.yml alone, and Sill trusts it only for the nightly
# channel and only while "Use nightly builds" is on (`UpdateManifest.nightlyKeys`). A manifest it signs has its
# own first line ("Sill nightly 1"), which no Sill ever reads as a release's.
#
#   Scripts/sign-nightly.sh --new-key --key-file PATH
#       Noah, once, on his Mac: makes the nightly key in a new file of mode 0600 (on an encrypted disk image,
#       never in the repository, ~/Downloads or the handoff folder) and prints its public key and key ID.
#       Never the keychain, never the update key's file.
#   Scripts/sign-nightly.sh --key-file PATH --zip .build/Sill-nightly-<yyyymmdd>-<sha7>.zip --out DIR
#       nightly.yml, after `release.sh --nightly --publish`: reads the notarized zip's app (its version, build,
#       SillChannel, SillCommit and every slice's cdhash), refuses an app that isn't a nightly of this very
#       commit, signs a "Sill nightly 1" manifest for the zip under its fixed name, reads it back with the
#       public keys compiled into this commit (`nightlyKeys`: none, or another key, and no Sill would take it),
#       and leaves DIR/Sill-nightly.zip and DIR/Sill-nightly.zip.manifest for the upload (the zip first).
#
# The signer is compiled from the three files the release signer is built from (Compatibility.swift,
# UpdateManifest.swift, Scripts/update-manifest.swift), into a temporary folder; it reads the key only from the
# file given, never the keychain.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
mode=sign keyfile="" zip="" out=""
while [ $# -gt 0 ]; do
    case "$1" in
        --new-key) mode=new-key ;;
        --key-file) keyfile="$2"; shift ;;
        --zip) zip="$2"; shift ;;
        --out) out="$2"; shift ;;
        *) echo "sign-nightly: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
die() { echo "sign-nightly: $*" >&2; exit 1; }
[ -n "$keyfile" ] || die "--key-file PATH: the nightly key lives in a file (in CI, the secret written to one), never the keychain"

work="$(mktemp -d "${TMPDIR:-/tmp}/sill-nightly-sign.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/src"
cp "$root/Sources/StreamProtocol/Compatibility.swift" "$work/src/Compatibility.swift"
sed '/^import StreamProtocol$/d' "$root/Sources/SillMenuBar/UpdateManifest.swift" > "$work/src/UpdateManifest.swift"
cp "$root/Scripts/update-manifest.swift" "$work/src/main.swift"
xcrun swiftc -O "$work/src"/*.swift -o "$work/update-manifest" > "$work/build.log" 2>&1 \
    || { cat "$work/build.log" >&2; die "the signer did not compile"; }
signer="$work/update-manifest"

if [ "$mode" = new-key ]; then
    # Not exec: the trap removes the compiled signer once it has made the key.
    "$signer" new-key --nightly --key-file "$keyfile"
    exit 0
fi

[ -f "$keyfile" ] || die "no key in $keyfile"
[ -n "$zip" ] && [ -f "$zip" ] || die "--zip: tonight's notarized zip (.build/Sill-nightly-<yyyymmdd>-<sha7>.zip)"
[ -n "$out" ] || die "--out DIR: where Sill-nightly.zip and its manifest go"
mkdir -p "$out"

# The public keys this commit's Sill trusts for nightlies: the base64 strings of its nightlyKeys line.
keys=()
for k in $(grep -m1 'static let nightlyKeys' "$root/Sources/SillMenuBar/UpdateManifest.swift" | grep -oE '"[A-Za-z0-9+/=]+"' | tr -d '"'); do
    keys+=(--key "$k")
done
[ "${#keys[@]}" -gt 0 ] || die "this commit's Sill has no nightly key (UpdateManifest.nightlyKeys is empty), so no Sill would take a signed nightly"

echo "== the app in $zip"
mkdir "$work/unpacked"
ditto -x -k --noqtn --norsrc --noextattr "$zip" "$work/unpacked"
[ "$(ls -A "$work/unpacked")" = "Sill.app" ] || die "the zip holds more than Sill.app: $(ls -A "$work/unpacked" | tr '\n' ' ')"
app="$work/unpacked/Sill.app"
plist="$app/Contents/Info.plist"
value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
[ "$(value CFBundleIdentifier)" = me.saffer.sill.mac ] || die "not me.saffer.sill.mac"
[ "$(value SillChannel)" = nightly ] || die "the app isn't a nightly (no SillChannel = nightly in its Info.plist): release.sh --nightly makes one"
commit="$(git -C "$root" rev-parse --verify HEAD)"
[ "$(value SillCommit)" = "$commit" ] || die "the app was built from $(value SillCommit), not from this commit $commit"
version="$(value CFBundleShortVersionString)"
build="$(value CFBundleVersion)"
cdargs=()
for arch in $(lipo -archs "$app/Contents/MacOS/Sill"); do
    case "$arch" in arm64|x86_64) ;; *) die "a slice Update Now doesn't know: $arch" ;; esac
    h="$(codesign -dvvv --arch "$arch" "$app" 2>&1 | sed -n 's/^CDHash=//p')"
    [[ "$h" =~ ^[0-9a-f]{40}$ ]] || die "no cdhash for $arch"
    cdargs+=(--cdhash "$arch=$h")
done
cp "$zip" "$out/Sill-nightly.zip"
size="$(stat -f %z "$out/Sill-nightly.zip")"
sha="$(shasum -a 256 "$out/Sill-nightly.zip" | cut -d' ' -f1)"
echo "  Sill $version ($build) of $commit, $size bytes, SHA-256 $sha, ${cdargs[*]}"

echo "== signing with the nightly key"
"$signer" nightly --version "$version" --build "$build" --commit "$commit" --asset Sill-nightly.zip --size "$size" --sha256 "$sha" \
    "${cdargs[@]}" --out "$out/Sill-nightly.zip.manifest" --key-file "$keyfile"
# Read back as the Sills of this commit will: with the keys compiled in, never the one that signed.
"$signer" verify-nightly "$out/Sill-nightly.zip.manifest" "${keys[@]}" | sed 's/^/  /' \
    || die "the manifest doesn't verify with this commit's nightlyKeys: the secret isn't the key whose public half is compiled in"
echo "Signed: $out/Sill-nightly.zip and $out/Sill-nightly.zip.manifest (upload the zip first, then the manifest)"
