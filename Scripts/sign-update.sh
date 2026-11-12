#!/bin/bash
# Signs a published release for Update Now (docs/one-click-update-plan.md §4.3; docs/release-checklist.md,
# "Signing the release for Update Now"). Run on Noah's Mac, after the release is published, never in CI:
# the update key never leaves this Mac's keychain (or the file given), and GitHub never holds it.
#
#   Scripts/sign-update.sh v0.6.2                  check the published release, sign it, ask, upload
#   Scripts/sign-update.sh --new-key               make the update key (once; prints its public key)
#   Scripts/sign-update.sh --public-key            the stored key's public key and key ID
# Options: --key-file PATH (the key in a file of mode 0600 instead of the login keychain), --repo
# OWNER/NAME (default Saffsanity/sill), --yes (no question before the upload), --replace (a manifest
# is already there), --expect-key BASE64 (the key the app checks with, instead of the one in the tag's
# Sources/SillMenuBar/UpdateManifest.swift; for a release before the key is compiled in, and tests).
#
# What it checks before it signs, the way release-checklist.md checks a download: the release is
# published (not a draft, not a prerelease) with Sill.zip and Sill.zip.sha256; the zip's SHA-256 is the
# .sha256 file's and GitHub's digest; it unpacks to exactly Sill.app; codesign --verify --strict --deep
# with Sill's pinned requirement and `notarized`; stapler validate; spctl's "Notarized Developer ID";
# the version is the tag's; then it signs the manifest (tag, version, build, size, SHA-256, each slice's
# cdhash), reads it back with the key the tag's app carries, and uploads it as Sill.zip.manifest. Nothing
# is uploaded before every check passed and the answer is yes.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
repo="Saffsanity/sill" tag="" keyfile="" yes=0 replace=0 expect="" mode="sign"
while [ $# -gt 0 ]; do
    case "$1" in
        --new-key) mode="new-key" ;;
        --public-key) mode="public-key" ;;
        --key-file) keyfile="$2"; shift ;;
        --repo) repo="$2"; shift ;;
        --yes) yes=1 ;;
        --replace) replace=1 ;;
        --expect-key) expect="$2"; shift ;;
        v*) tag="$1" ;;
        *) echo "sign-update: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
die() { echo "sign-update: $*" >&2; exit 1; }
pinned='anchor apple generic and identifier "me.saffer.sill.mac" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "9B2KKVM937"'

# The tool, from this checkout's own definitions of the manifest and the cdhash.
work="$root/.build/update-sign"
mkdir -p "$work"
src="$(mktemp -d "$work/src.XXXXXX")"
cp "$root"/Sources/StreamProtocol/*.swift "$src"/
for f in UpdatePolicy UpdateInstallPolicy UpdateManifest UpdateInstaller UpdateArchive; do
    sed '/^import StreamProtocol$/d' "$root/Sources/SillMenuBar/$f.swift" > "$src/$f.swift"
done
cp "$here/update-manifest.swift" "$src/main.swift"
swiftc -O "$src"/*.swift -o "$work/update-manifest" 2>&1 | grep -E "error" && die "the tool did not compile"
rm -rf "$src"
tool="$work/update-manifest"
keyargs=(); [ -n "$keyfile" ] && keyargs=(--key-file "$keyfile")

case "$mode" in
    new-key) exec "$tool" new-key ${keyargs[@]+"${keyargs[@]}"} ;;
    public-key) exec "$tool" public-key ${keyargs[@]+"${keyargs[@]}"} ;;
esac

[[ "$tag" =~ ^v[0-9]+(\.[0-9]+){0,7}$ ]] || die "a tag like v0.6.2 (got '$tag')"
version="${tag#v}"
command -v gh >/dev/null || die "gh is not installed"

echo "== $tag in $repo"
release="$(gh api "repos/$repo/releases/tags/$tag")" || die "no release $tag in $repo"
[ "$(jq -r '.draft' <<<"$release")" = false ] || die "$tag is a draft: publish it first"
[ "$(jq -r '.prerelease' <<<"$release")" = false ] || die "$tag is a prerelease: Update Now never offers one"
for a in Sill.zip Sill.zip.sha256; do
    [ "$(jq -r --arg n "$a" '[.assets[] | select(.name == $n and .state == "uploaded")] | length' <<<"$release")" = 1 ] || die "$tag has no uploaded $a"
done
if [ "$(jq -r '[.assets[] | select(.name == "Sill.zip.manifest")] | length' <<<"$release")" != 0 ] && [ "$replace" = 0 ]; then
    die "$tag already has Sill.zip.manifest (--replace to sign it again)"
fi
digest="$(jq -r '.assets[] | select(.name == "Sill.zip") | .digest // empty' <<<"$release")"

dir="$(mktemp -d "$work/$tag.XXXXXX")"
trap 'rm -rf "$dir"' EXIT
echo "== downloading Sill.zip into $dir"
gh release download "$tag" --repo "$repo" --pattern Sill.zip --pattern Sill.zip.sha256 --dir "$dir"
sha="$(shasum -a 256 "$dir/Sill.zip" | cut -d' ' -f1)"
size="$(stat -f %z "$dir/Sill.zip")"
[ "$(cut -d' ' -f1 "$dir/Sill.zip.sha256")" = "$sha" ] || die "Sill.zip is not what Sill.zip.sha256 says"
[ -z "$digest" ] || [ "$digest" = "sha256:$sha" ] || die "Sill.zip is not what GitHub's digest says ($digest)"

echo "== checking the app in it"
mkdir "$dir/unpacked"
ditto -x -k --noqtn --norsrc --noextattr "$dir/Sill.zip" "$dir/unpacked"
[ "$(ls -A "$dir/unpacked")" = "Sill.app" ] || die "Sill.zip holds more than Sill.app: $(ls -A "$dir/unpacked" | tr '\n' ' ')"
app="$dir/unpacked/Sill.app"
codesign --verify --strict --deep --verbose=2 -R "=$pinned and notarized" "$app" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$app" >/dev/null || die "the app has no valid stapled ticket"
spctl -a -t exec -vv "$app" 2>&1 | grep -q "source=Notarized Developer ID" || die "spctl does not say Notarized Developer ID"
plist="$app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "me.saffer.sill.mac" ] || die "not me.saffer.sill.mac"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version" ] || die "the app's version is not $version"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
cdargs=()
while IFS= read -r line; do cdargs+=(--cdhash "$line"); done < <("$tool" cdhashes "$app")
[ "${#cdargs[@]}" -gt 0 ] || die "no cdhash read from the app"
echo "  Sill $version ($build), $size bytes, SHA-256 $sha"
echo "  ${cdargs[*]}"

echo "== signing"
"$tool" sign --tag "$tag" --build "$build" --asset Sill.zip --size "$size" --sha256 "$sha" "${cdargs[@]}" \
    --out "$dir/Sill.zip.manifest" ${keyargs[@]+"${keyargs[@]}"}
# Read back with the key the tag's app checks with (and the previous release's, which the update reaches).
keys=()
if [ -n "$expect" ]; then
    keys=(--key "$expect")
else
    source_keys="$(git -C "$root" show "$tag:Sources/SillMenuBar/UpdateManifest.swift" 2>/dev/null \
        | sed -n 's/.*static let releaseKeys: \[String\] = \[\(.*\)\].*/\1/p' | tr -d ' "' | tr ',' ' ')"
    for k in $source_keys; do keys+=(--key "$k"); done
    [ "${#keys[@]}" -gt 0 ] || die "$tag's app carries no update key, so no Sill would accept this (--expect-key to sign anyway)"
fi
"$tool" verify "$dir/Sill.zip.manifest" "${keys[@]}" | sed 's/^/  /'
cat "$dir/Sill.zip.manifest" | sed 's/^/  | /'

if [ "$yes" = 0 ]; then
    read -r -p "Upload Sill.zip.manifest to $tag in $repo? [y/N] " answer
    [ "$answer" = y ] || [ "$answer" = Y ] || die "not uploaded"
fi
clobber=(); [ "$replace" = 1 ] && clobber=(--clobber)
gh release upload "$tag" "$dir/Sill.zip.manifest" --repo "$repo" ${clobber[@]+"${clobber[@]}"}
mkdir "$dir/back"
gh release download "$tag" --repo "$repo" --pattern Sill.zip.manifest --dir "$dir/back"
cmp -s "$dir/Sill.zip.manifest" "$dir/back/Sill.zip.manifest" || die "the uploaded manifest is not the one signed"
echo "Uploaded and read back: $tag is signed for Update Now."
