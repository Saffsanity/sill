#!/bin/bash
# Signs a published release for Update Now (docs/one-click-update-plan.md §4.8; docs/release-checklist.md,
# part 1 §7 and part 2). Run on Noah's Mac, in Terminal.app, never in CI: the update key never leaves this
# Mac's keychain (or the file given), and GitHub never holds it.
#
#   Scripts/sign-update.sh --install-signer        build the signer from this checkout, after reading the
#                                                  three files it is built from and the trust it records
#   Scripts/sign-update.sh --new-key               make the update key (once; prints its public key)
#   Scripts/sign-update.sh --public-key            the stored key's public key and key ID
#   Scripts/sign-update.sh v0.6.2                  check the published release, sign it, ask, upload
#
# The signer is the one program that ever holds the key. --install-signer copies the three files it is
# built from (Sources/StreamProtocol/Compatibility.swift, Sources/SillMenuBar/UpdateManifest.swift and
# Scripts/update-manifest.swift), shows them, builds from the copies, and signs the binary with the hardened
# runtime: the keychain lets that binary read the key without asking, so no library may be loaded into it
# and no debugger attached (review 3, F1). It also records the trust the checkout's Sill carries (its update
# keys, the pinned code requirement, Trust.release and Endpoints.github), which Noah reads with the files.
# A release is signed only when its tag's Sill carries exactly that trust: one line slipped into main must
# not hand another key, team or host the update key's approval (F2). After a change he has read (his public
# key in releaseKeys, a rotation), --install-signer again.
#
# What it signs is a zip Noah knows without GitHub: by default the one release.sh made on this Mac
# (.build/Sill-<version>.zip, which `release.sh --publish` uploaded), byte for byte; or, for a release the
# release workflow built in a run he approved, --expect-sha256 with the SHA-256 that run printed. A release
# CI published that he did not approve (T4: the `nightly` environment needs no approval and its token can
# publish) has neither, and is refused. GitHub's copy must equal it, and is also checked as
# release-checklist.md checks a download: Sill.zip.sha256 and GitHub's digest; exactly one Sill.app;
# codesign --verify --strict --deep with Sill's pinned requirement and `notarized`; stapler validate;
# spctl's "Notarized Developer ID"; the version is the tag's. Then the manifest (tag, version, build, size,
# SHA-256, each slice's cdhash as codesign reads it) is signed by the installed signer, which asks Noah in
# person first (Touch ID or his password, the prompt naming the tag, the size and the whole SHA-256), read
# back with the recorded keys, shown, and uploaded as Sill.zip.manifest once the answer is yes.
#
# Options: --zip PATH, --expect-sha256 HEX, --key-file PATH (a key in a file of mode 0600 instead of the
# login keychain: no in-person prompt, for tests and the rehearsal), --repo OWNER/NAME (default
# Saffsanity/sill), --source DIR (the checkout whose tag is read and whose files the signer is built from;
# by default this script's own), --yes (no question before the upload), --replace (a manifest is already
# there). SILL_SIGNER_DIR (TEST ONLY, with --key-file) puts the signer elsewhere than
# ~/Library/Application Support/Sill Update Signer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
repo="Saffsanity/sill" tag="" keyfile="" yes=0 replace=0 mode="sign" zip="" sha_expected="" source="$root"
while [ $# -gt 0 ]; do
    case "$1" in
        --install-signer) mode="install-signer" ;;
        --new-key) mode="new-key" ;;
        --public-key) mode="public-key" ;;
        --key-file) keyfile="$2"; shift ;;
        --repo) repo="$2"; shift ;;
        --source) source="$(cd "$2" && pwd)"; shift ;;
        --yes) yes=1 ;;
        --replace) replace=1 ;;
        --zip) zip="$2"; shift ;;
        --expect-sha256) sha_expected="$2"; shift ;;
        v*) tag="$1" ;;
        *) echo "sign-update: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
die() { echo "sign-update: $*" >&2; exit 1; }
pinned='anchor apple generic and identifier "me.saffer.sill.mac" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "9B2KKVM937"'
signer_dir="${SILL_SIGNER_DIR:-$HOME/Library/Application Support/Sill Update Signer}"
signer="$signer_dir/update-manifest"
anchors_file="$signer_dir/trust.txt"
keyargs=(); [ -n "$keyfile" ] && keyargs=(--key-file "$keyfile")

# SILL_SIGNER_DIR is the tests' (with a key in a file): never the keychain's key.
if [ -n "${SILL_SIGNER_DIR:-}" ] && [ -z "$keyfile" ] && [ "$mode" != install-signer ]; then
    die "SILL_SIGNER_DIR is for tests, with --key-file"
fi

# The trust a Sill carries, as its source says it: the code lines that name its update keys and its pinned
# code requirement, and Trust.release and Endpoints.github whole (comments left out: they change no trust).
# `trust DIR [REV]` reads the working tree of DIR, or REV's files in its git; fails when a part is missing.
trust() {
    local man pol keys req blocks
    if [ -n "${2:-}" ]; then
        man="$(git -C "$1" show "$2:Sources/SillMenuBar/UpdateManifest.swift" 2>/dev/null)" || return 1
        pol="$(git -C "$1" show "$2:Sources/SillMenuBar/UpdateInstallPolicy.swift" 2>/dev/null)" || return 1
    else
        man="$(cat "$1/Sources/SillMenuBar/UpdateManifest.swift")" || return 1
        pol="$(cat "$1/Sources/SillMenuBar/UpdateInstallPolicy.swift")" || return 1
    fi
    keys="$(printf '%s\n' "$man" | grep -E '^[[:space:]]*[^/[:space:]].*releaseKeys' || true)"
    req="$(printf '%s\n' "$pol" | grep -E '^[[:space:]]*[^/[:space:]].*pinnedRequirement' || true)"
    blocks="$(printf '%s\n' "$pol" | awk '/^extension UpdateInstallPolicy\.(Trust|Endpoints) \{/ { on = 1 } on { print } on && /^\}/ { on = 0 }' \
        | grep -vE '^[[:space:]]*//' || true)"
    grep -q 'static let releaseKeys' <<<"$keys" && grep -q 'static let pinnedRequirement' <<<"$req" \
        && grep -q 'static let release' <<<"$blocks" && grep -q 'static let github' <<<"$blocks" || return 1
    printf '%s\n%s\n%s\n' "$keys" "$req" "$blocks"
}
# The update keys a trust record lists: the base64 strings of its releaseKeys line.
trusted_keys() { grep -m1 'static let releaseKeys' | grep -oE '"[A-Za-z0-9+/=]+"' | tr -d '"' || true; }
# 64 hex digits in groups of eight, as the signer's prompt shows them.
grouped() { sed -E 's/(.{8})/\1 /g; s/ $//' <<<"$1"; }

if [ "$mode" = install-signer ]; then
    files=("$source/Sources/StreamProtocol/Compatibility.swift" "$source/Sources/SillMenuBar/UpdateManifest.swift"
           "$source/Scripts/update-manifest.swift")
    # Copied first, then hashed, shown and built from the copies: what is built is what was shown, whatever
    # happens to the checkout meanwhile.
    src="$(mktemp -d)"
    trap 'rm -rf "$src"' EXIT
    echo "The signer is built from these files of $(git -C "$source" rev-parse --short HEAD)$(git -C "$source" diff --quiet -- "${files[@]}" "$source/Scripts/sign-update.sh" || echo ' (with changes not committed)'):"
    for f in "${files[@]}"; do
        name="$(basename "$f")"; [ "$name" = update-manifest.swift ] && name=main.swift
        cp "$f" "$src/$name.orig"
        echo "  $(shasum -a 256 "$src/$name.orig" | cut -d' ' -f1)  ${f#$source/}"
        sed '/^import StreamProtocol$/d' "$src/$name.orig" > "$src/$name"
        rm "$src/$name.orig"
    done
    echo "and this script, which chooses what it signs (read it too):"
    echo "  $(shasum -a 256 "$here/sign-update.sh" | cut -d' ' -f1)  Scripts/sign-update.sh"
    trust "$source" > "$src/trust.txt" || die "can't find the trust in $source's Update Now sources (releaseKeys, pinnedRequirement, Trust.release, Endpoints.github)"
    echo "The trust every release you sign must carry, exactly (from the same checkout):"
    sed 's/^/  | /' "$src/trust.txt"
    if [ "$yes" = 0 ]; then
        read -r -p "Have you read them, and build the signer from them? [y/N] " answer
        [ "$answer" = y ] || [ "$answer" = Y ] || die "not built"
    fi
    mkdir -p "$signer_dir"
    chmod 700 "$signer_dir"
    rm -f "$signer.new"
    swiftc -O "$src"/*.swift -o "$signer.new" > "$src/build.log" 2>&1 || { cat "$src/build.log" >&2; rm -f "$signer.new"; die "the signer did not compile"; }
    # The hardened runtime: no DYLD_INSERT_LIBRARIES, no debugger, for the binary the key trusts (F1).
    codesign -s - -f -o runtime -i me.saffer.sill.update-signer "$signer.new" 2>/dev/null || { rm -f "$signer.new"; die "couldn't sign the signer with the hardened runtime"; }
    codesign -dv "$signer.new" 2>&1 | grep -q 'flags=.*runtime' || { rm -f "$signer.new"; die "the signer has no hardened runtime"; }
    mv -f "$signer.new" "$signer"
    shasum -a 256 "$signer" | cut -d' ' -f1 > "$signer.sha256"
    mv -f "$src/trust.txt" "$anchors_file"
    echo "Installed $signer ($(cat "$signer.sha256")), with the hardened runtime, and the trust above in $anchors_file."
    echo "The keychain trusts the signer that made the update key. When a signer installed later first uses it, the"
    echo "keychain asks once: allow it only right after you ran --install-signer here yourself; any other time, deny."
    echo "Every signature with the keychain's key also asks you in person (Touch ID or your password)."
    exit 0
fi

# The installed signer, unchanged since it was installed, with the hardened runtime, and its trust record.
[ -x "$signer" ] && [ -f "$signer.sha256" ] || die "no signer installed: Scripts/sign-update.sh --install-signer (after reading its files)"
[ "$(shasum -a 256 "$signer" | cut -d' ' -f1)" = "$(cat "$signer.sha256")" ] || die "the installed signer changed since it was installed: install it again"
codesign -dv "$signer" 2>&1 | grep -q 'flags=.*runtime' || die "the installed signer has no hardened runtime (an older install): install it again"
[ -f "$anchors_file" ] || die "the installed signer has no trust record (an older install): install it again"

case "$mode" in
    new-key) exec "$signer" new-key ${keyargs[@]+"${keyargs[@]}"} ;;
    public-key) exec "$signer" public-key ${keyargs[@]+"${keyargs[@]}"} ;;
esac

[[ "$tag" =~ ^v[0-9]+(\.[0-9]+){0,7}$ ]] || die "a tag like v0.6.2 (got '$tag')"
version="${tag#v}"
command -v gh >/dev/null || die "gh is not installed"

# The trust the tag's Sill carries must be the recorded one, exactly (F2).
echo "== the trust $tag's Sill carries"
release_trust="$(trust "$source" "$tag")" || die "can't read the trust in $tag's sources in $source (is the tag there? --source for another checkout)"
if [ "$release_trust" != "$(cat "$anchors_file")" ]; then
    echo "sign-update: $tag's Sill trusts something other than what you read when you installed the signer:" >&2
    diff <(cat "$anchors_file") <(printf '%s\n' "$release_trust") | sed 's/^/  /' >&2 || true
    die "nothing signed. If the change is yours (your key, a rotation), read it, check out $tag, run --install-signer, then sign again."
fi
keys=()
for k in $(trusted_keys < "$anchors_file"); do keys+=(--key "$k"); done
[ "${#keys[@]}" -gt 0 ] || die "$tag's Sill carries no update key, so no Sill would accept this"
echo "  the recorded trust: ${#keys[@]} update key(s), the pinned requirement, Trust.release and Endpoints.github"

if [ -z "$sha_expected" ]; then
    [ -n "$zip" ] || zip="$source/.build/Sill-$version.zip"
    [ -f "$zip" ] || die "no zip of $version built on this Mac at $zip. Sign only a release you built here (release.sh --publish), or one the release workflow built in a run you approved (--expect-sha256 with the SHA-256 it printed): a build CI made unapproved is never signed (docs/one-click-update-plan.md T4)."
    sha_expected="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
    echo "== the zip built on this Mac: $zip, SHA-256 $sha_expected"
fi
[[ "$sha_expected" =~ ^[0-9a-f]{64}$ ]] || die "--expect-sha256 takes 64 lowercase hex digits"

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

work="$source/.build/update-sign"
mkdir -p "$work"
dir="$(mktemp -d "$work/$tag.XXXXXX")"
trap 'rm -rf "$dir"' EXIT
echo "== downloading Sill.zip into $dir"
gh release download "$tag" --repo "$repo" --pattern Sill.zip --pattern Sill.zip.sha256 --dir "$dir"
sha="$(shasum -a 256 "$dir/Sill.zip" | cut -d' ' -f1)"
size="$(stat -f %z "$dir/Sill.zip")"
[ "$sha" = "$sha_expected" ] || die "GitHub's Sill.zip ($sha) is not the zip you know ($sha_expected): nothing signed"
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
for arch in $(lipo -archs "$app/Contents/MacOS/Sill"); do
    case "$arch" in arm64|x86_64) ;; *) die "a slice Update Now doesn't know: $arch" ;; esac
    h="$(codesign -dvvv --arch "$arch" "$app" 2>&1 | sed -n 's/^CDHash=//p')"
    [[ "$h" =~ ^[0-9a-f]{40}$ ]] || die "no cdhash for $arch"
    cdargs+=(--cdhash "$arch=$h")
done
echo "  Sill $version ($build), $size bytes"
echo "  SHA-256 $(grouped "$sha")"
echo "  ${cdargs[*]}"

echo "== signing"
[ -n "$keyfile" ] || echo "  Touch ID or your password next: allow only if the prompt's SHA-256 is the one above, which must be the one release.sh (or the approved run) printed."
"$signer" sign --tag "$tag" --build "$build" --asset Sill.zip --size "$size" --sha256 "$sha" "${cdargs[@]}" \
    --out "$dir/Sill.zip.manifest" ${keyargs[@]+"${keyargs[@]}"}
# Read back with the recorded keys: the keys the tag's Sill carries, and so the keys of every Sill that will
# install it unless this release brings a new one (a rotation: sign with the old key, part 1 §7).
"$signer" verify "$dir/Sill.zip.manifest" "${keys[@]}" | sed 's/^/  /'
sed 's/^/  | /' "$dir/Sill.zip.manifest"

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
