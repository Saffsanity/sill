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
#   Scripts/sign-update.sh v0.6.2 --run 123456     the same for a release the release workflow built in run 123456
#   Scripts/sign-update.sh --audit [--notify]      every release on GitHub, drafts and pre-releases included,
#                                                  against what this signer signed: says, and exits 1, when a
#                                                  manifest or a Sill.zip isn't in the record (a release Noah
#                                                  didn't sign), or a release it names isn't listed
#   Scripts/sign-update.sh --pulled v0.6.2         mark a release you pulled from GitHub in the record
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
# release workflow built in a run he approved, --run with that run's number: the run's own record on GitHub
# must name his tag's commit as the one it built (`head_sha`; the third security pass's R1′: an app's
# SillCommit is its own build's word, so a tag moved for the run and back passes every other check), started by
# a pushed tag or Run workflow on this repository's own code (N11 c), and the zip is the one that run kept as its
# artifact. A release CI published that he did not approve (T4: the
# `nightly` environment needs no approval and its token can publish) has neither, and is refused. Either way
# the app must name, in its signed Info.plist (SillCommit, make-app.sh), the commit his own tag names, and
# GitHub's tag must name it too (the second security pass's R1), and it must not be a nightly (SillChannel,
# N10 e). Before it signs, it shows what changed in the updater's own files since the last release he signed
# and asks, whatever --yes says (R2: the record pins the trust constants, not the code that uses them).
# GitHub's copy must equal it, and is also checked as
# release-checklist.md checks a download: Sill.zip.sha256 and GitHub's digest; exactly one Sill.app;
# codesign --verify --strict --deep with Sill's pinned requirement and `notarized`; stapler validate;
# spctl's "Notarized Developer ID"; the version is the tag's. Then the manifest (tag, version, build, size,
# SHA-256, each slice's cdhash as codesign reads it) is signed by the installed signer, which asks Noah in
# person first (Touch ID or his password, the prompt naming the tag, the size and the whole SHA-256), read
# back with the recorded keys, shown, and uploaded as Sill.zip.manifest once the answer is yes.
#
# Every manifest it signs goes in the signing record (signed.txt beside the signer: the time, the tag, the
# manifest's SHA-256 and the zip's). `--audit` reads the Sill.zip.manifest of every release on GitHub that
# carries one, drafts and pre-releases too (the third security pass's AU1: one turned into either around the
# audit's run would otherwise pass unseen), and checks each against that record: one that verifies with a key
# the record trusts but that this signer never made is a release Noah didn't sign (a leaked update key), which
# every Sill would install, by itself two days after it first finds it (docs/one-click-update-plan.md §15.4).
# Run several times a day (his choice: the LaunchAgent in docs/release-checklist.md part 1 §7, every few hours
# from when it was loaded, no time written anywhere), with --notify it posts a notification when it finds one
# and whenever it couldn't run (an expired gh login, no network): an audit never fails in silence. The record
# and the audit guard against a key that leaked off this Mac, not against someone in control of this Mac or
# of Noah's account here, who also controls signed.txt, this script and the LaunchAgent.
#
# Options: --zip PATH, --run ID, --key-file PATH (a key in a file of mode 0600 instead of the login keychain:
# no in-person prompt, for tests and the rehearsal), --repo OWNER/NAME (default Saffsanity/sill), --source DIR
# (the checkout whose tag is read and whose files the signer is built from; by default this script's own),
# --yes (no question before building the signer or the upload; the updater's changes are asked about anyway),
# --replace (a manifest is already there), --notify (with --audit). SILL_SIGNER_DIR (TEST ONLY, with
# --key-file, or --audit) puts the signer elsewhere than ~/Library/Application Support/Sill Update Signer;
# SILL_SIGN_TEST_BUILT_FROM (TEST ONLY, with SILL_SIGNER_DIR and the tests' key alone, UpdateManifest.testKeySeed,
# which no Sill trusts: never a real key restored to a file, N10 m) stands for the commit the app names (the
# genuine v0.6.1 the test signs predates SillCommit), and is compared with the tag's commit as the app's own would be.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
repo="Saffsanity/sill" tag="" keyfile="" yes=0 replace=0 mode="sign" zip="" run_id="" source="$root" notify=0
while [ $# -gt 0 ]; do
    case "$1" in
        --install-signer) mode="install-signer" ;;
        --new-key) mode="new-key" ;;
        --public-key) mode="public-key" ;;
        --audit) mode="audit" ;;
        --pulled) mode="pulled" ;;
        --notify) notify=1 ;;
        --key-file) keyfile="$2"; shift ;;
        --repo) repo="$2"; shift ;;
        --source) source="$(cd "$2" && pwd)"; shift ;;
        --yes) yes=1 ;;
        --replace) replace=1 ;;
        --zip) zip="$2"; shift ;;
        --run) run_id="$2"; shift ;;
        v*) tag="$1" ;;
        *) echo "sign-update: unknown argument $1" >&2; exit 2 ;;
    esac
    shift
done
last_error="" alarm_sent=0 cleanup=()
die() { last_error="$*"; echo "sign-update: $*" >&2; exit 1; }
# A notification (with --audit --notify), its words without quotes or backslashes for AppleScript's string.
notify_audit() {
    local words; words="$(printf '%s' "$1" | tr -d '"\\' | cut -c1-220)"
    osascript -e "display notification \"$words\" with title \"Sill update audit\"" > /dev/null 2>&1 || true
}
# The folders made for this run go at the end, whatever the end; and an audit with --notify that didn't end clean
# says so, whatever stopped it (the third security pass's AU1: an expired gh login or no network must not pass in
# silence).
on_exit() {
    local rc=$?
    for d in ${cleanup[@]+"${cleanup[@]}"}; do rm -rf "$d"; done
    if [ "$mode" = audit ] && [ "$notify" = 1 ] && [ "$rc" != 0 ] && [ "$alarm_sent" = 0 ]; then
        notify_audit "The audit couldn't run: ${last_error:-it stopped with status $rc}. Run Scripts/sign-update.sh --audit in Terminal to see why."
    fi
}
trap on_exit EXIT
pinned='anchor apple generic and identifier "me.saffer.sill.mac" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "9B2KKVM937"'
signer_dir="${SILL_SIGNER_DIR:-$HOME/Library/Application Support/Sill Update Signer}"
signer="$signer_dir/update-manifest"
anchors_file="$signer_dir/trust.txt"
record="$signer_dir/signed.txt"
keyargs=(); [ -n "$keyfile" ] && keyargs=(--key-file "$keyfile")

# SILL_SIGNER_DIR is the tests' (with a key in a file): never the keychain's key.
if [ -n "${SILL_SIGNER_DIR:-}" ] && [ -z "$keyfile" ] && [ "$mode" != install-signer ] && [ "$mode" != audit ] && [ "$mode" != pulled ]; then
    die "SILL_SIGNER_DIR is for tests, with --key-file"
fi
if [ -n "${SILL_SIGN_TEST_BUILT_FROM:-}" ] && [ -z "${SILL_SIGNER_DIR:-}" ]; then
    die "SILL_SIGN_TEST_BUILT_FROM is for tests, with SILL_SIGNER_DIR"
fi
# The updater's own files and the ones that steer it: what R2 shows the changes of since the last release signed
# (the third security pass's R2: AppModel wires the offer, the devices, the hold and the daily check; SettingsPanes
# is the only caller of the two switches' setters; Compatibility.swift is SillVersion's order; StreamServer holds
# new sessions for the install).
updater_files=('Sources/SillMenuBar/Update*.swift' Sources/SillMenuBar/AppUpdater.swift Sources/SillMenuBar/AutoUpdateStore.swift
               Sources/SillMenuBar/AppDelegate.swift Sources/SillMenuBar/AppModel.swift Sources/SillMenuBar/SettingsPanes.swift
               Sources/StreamProtocol/Compatibility.swift Sources/SillHost/StreamServer.swift Packaging Scripts/make-app.sh
               Scripts/release.sh Scripts/sign-update.sh Scripts/update-manifest.swift)

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
    cleanup+=("$src")
    echo "The signer is built from these files of $(git -C "$source" rev-parse --short HEAD)$(git -C "$source" diff --quiet -- "${files[@]}" "$source/Scripts/sign-update.sh" || echo ' (with changes not committed)'):"
    for f in "${files[@]}"; do
        name="$(basename "$f")"; [ "$name" = update-manifest.swift ] && name=main.swift
        cp "$f" "$src/$name.orig"
        echo "  $(shasum -a 256 "$src/$name.orig" | cut -d' ' -f1)  ${f#$source/}"
        sed '/^import StreamProtocol$/d' "$src/$name.orig" > "$src/$name"
        rm "$src/$name.orig"
    done
    echo "and this script, which chooses what it signs and is installed beside the signer for --audit (read it too):"
    cp "$here/sign-update.sh" "$src/sign-update.sh"
    echo "  $(shasum -a 256 "$src/sign-update.sh" | cut -d' ' -f1)  Scripts/sign-update.sh"
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
    # The whole output read first: `grep -q` stops reading at its match, and under pipefail codesign's SIGPIPE
    # would then fail the pipe however the flags read.
    flags="$(codesign -dv "$signer.new" 2>&1 || true)"
    grep -q 'flags=.*runtime' <<< "$flags" || { rm -f "$signer.new"; die "the signer has no hardened runtime"; }
    mv -f "$signer.new" "$signer"
    shasum -a 256 "$signer" | cut -d' ' -f1 > "$signer.sha256"
    mv -f "$src/trust.txt" "$anchors_file"
    mv -f "$src/sign-update.sh" "$signer_dir/sign-update.sh"
    chmod 755 "$signer_dir/sign-update.sh"
    touch "$record"; chmod 600 "$record"
    echo "Installed $signer ($(cat "$signer.sha256")), with the hardened runtime, and the trust above in $anchors_file."
    echo "The keychain trusts the signer that made the update key. When a signer installed later first uses it, the"
    echo "keychain asks once: allow it only right after you ran --install-signer here yourself; any other time, deny."
    echo "Every signature with the keychain's key also asks you in person (Touch ID or your password)."
    exit 0
fi

# The installed signer, unchanged since it was installed, with the hardened runtime, and its trust record.
[ -x "$signer" ] && [ -f "$signer.sha256" ] || die "no signer installed: Scripts/sign-update.sh --install-signer (after reading its files)"
[ "$(shasum -a 256 "$signer" | cut -d' ' -f1)" = "$(cat "$signer.sha256")" ] || die "the installed signer changed since it was installed: install it again"
flags="$(codesign -dv "$signer" 2>&1 || true)"
grep -q 'flags=.*runtime' <<< "$flags" || die "the installed signer has no hardened runtime (an older install): install it again"
[ -f "$anchors_file" ] || die "the installed signer has no trust record (an older install): install it again"

case "$mode" in
    new-key) exec "$signer" new-key ${keyargs[@]+"${keyargs[@]}"} ;;
    public-key) exec "$signer" public-key ${keyargs[@]+"${keyargs[@]}"} ;;
esac

# The test-only SILL_SIGN_TEST_BUILT_FROM goes with the tests' key alone, which anyone can make and no Sill trusts
# (UpdateManifest.testKeySeed): never with a real key restored to a file (the third security pass's N10 m).
if [ -n "${SILL_SIGN_TEST_BUILT_FROM:-}" ]; then
    [ -n "$keyfile" ] || die "SILL_SIGN_TEST_BUILT_FROM is for tests, with --key-file and the tests' key"
    test_id="$("$signer" test-key-id)"
    key_id="$("$signer" public-key --key-file "$keyfile" | sed -n 's/.*(key ID \([0-9a-f]*\)).*/\1/p')"
    [ -n "$test_id" ] && [ "$key_id" = "$test_id" ] || die "SILL_SIGN_TEST_BUILT_FROM is taken only with the tests' key (key ID $test_id), never another: this key is ${key_id:-unreadable}"
fi

# --audit: every release on GitHub against the signing record (A1), drafts and pre-releases included (the third
# security pass's AU1), read with a login GitHub lists drafts to (`permissions.push`). It names:
# - a Sill.zip.manifest not in the record (one that verifies with a recorded key is a release Noah didn't sign), and
#   one larger than any Sill reads (4 KiB), not downloaded (the fourth security pass's N11 g);
# - a Sill.zip not in the record, by GitHub's digest (AU2: its manifest renamed or gone hides nothing), on any release
#   whose version is at or above the lowest the record names (older ones predate the update key);
# - a release the record names that GitHub doesn't list, unless marked pulled (--pulled), and a listing with no
#   release at all (N11 b: a short or empty answer passes nothing).
# Reads only: the repository's permissions, GitHub's release listing and each Sill.zip.manifest by its asset id (a
# draft's has no download address), a few KB each.
if [ "$mode" = audit ]; then
    command -v gh >/dev/null || die "gh is not installed"
    keys=()
    for k in $(trusted_keys < "$anchors_file"); do keys+=(--key "$k"); done
    [ -f "$record" ] || touch "$record"
    dir="$(mktemp -d)"
    cleanup+=("$dir")
    push="$(gh api "repos/$repo" | jq -r '.permissions.push // false')" || die "can't read $repo"
    [ "$push" = true ] || die "this gh login can't push to $repo, and GitHub lists drafts only to one that can: the audit can't see them (gh auth status)"
    gh api --paginate "repos/$repo/releases?per_page=100" > "$dir/releases.json" || die "can't list $repo's releases"
    # One line a release: its tag, its state, its Sill.zip's digest, its Sill.zip.manifest's asset id and size ("-": none).
    jq -r -s 'add // [] | .[] | . as $r
              | ([.assets[] | select(.name == "Sill.zip")] | first) as $z
              | ([.assets[] | select(.name == "Sill.zip.manifest")] | first) as $m
              | [$r.tag_name, (if $r.draft then "a draft" elif $r.prerelease then "a pre-release" else "published" end),
                 (if $z then ($z.digest // "none") else "-" end), (if $m then ($m.id | tostring) else "-" end),
                 (if $m then ($m.size | tostring) else "-" end)]
              | @tsv' "$dir/releases.json" > "$dir/releases" || die "can't read $repo's release listing"
    # The record: the tags signed here (a line each manifest: time, tag, the manifest's SHA-256, the zip's), the ones
    # marked pulled (time, tag, "pulled"), and the lowest version signed.
    awk 'NF == 4 && $2 ~ /^v[0-9]/ { print $2 }' "$record" | sort -u > "$dir/signed-tags"
    awk 'NF == 3 && $3 == "pulled" { print $2 }' "$record" | sort -u > "$dir/pulled-tags"
    vcmp='function vcmp(a, b,   x, y, i, n, m, p, q) { sub(/^v/, "", a); sub(/^v/, "", b); n = split(a, x, "[.]"); m = split(b, y, "[.]");
              for (i = 1; i <= (n > m ? n : m); i++) { p = (i <= n ? x[i] + 0 : 0); q = (i <= m ? y[i] + 0 : 0); if (p < q) return -1; if (p > q) return 1 }
              return 0 }'
    floor="$(awk "$vcmp"' { if (low == "" || vcmp($1, low) < 0) low = $1 } END { print low }' "$dir/signed-tags")"
    alarms=0 n=0
    alarm() { echo "  $*"; alarms=$((alarms + 1)); }
    [ -s "$dir/releases" ] || alarm "GitHub listed no release in $repo: a listing that can't be right, so nothing could be checked."
    while IFS=$'\t' read -r t state digest id size; do
        if [ "$id" != - ]; then
            n=$((n + 1))
            if ! [[ "$id" =~ ^[0-9]{1,20}$ ]]; then
                alarm "$t ($state): a Sill.zip.manifest with an asset id that isn't one"
            elif ! [[ "$size" =~ ^[0-9]{1,9}$ ]] || [ "$size" -gt 4096 ]; then
                alarm "$t ($state): a Sill.zip.manifest of $size bytes, more than any Sill reads (4 KiB), not downloaded. Nobody signs one so large: look at the release."
            else
                f="$dir/$id.manifest"
                gh api -H "Accept: application/octet-stream" "repos/$repo/releases/assets/$id" > "$f" || die "can't download $t's Sill.zip.manifest ($state)"
                m="$(shasum -a 256 "$f" | cut -d' ' -f1)"
                if awk -v t="$t" -v m="$m" '$2 == t && $3 == m { found = 1 } END { exit !found }' "$record"; then
                    echo "  $t ($state): signed here ($(awk -v t="$t" -v m="$m" '$2 == t && $3 == m { print $1; exit }' "$record"))"
                elif [ "${#keys[@]}" -gt 0 ] && "$signer" verify "$f" "${keys[@]}" > "$f.verify" 2>&1; then
                    alarm "$t ($state): NOT IN YOUR SIGNING RECORD, and it verifies with your update key: every Sill would install it once it is the latest release. If you didn't sign it, pull it now (docs/release-checklist.md, part 1 §7)."
                    sed 's/^/    | /' "$f.verify"
                else
                    alarm "$t ($state): NOT IN YOUR SIGNING RECORD; it doesn't verify with your update key, so no Sill installs it, but Update Now is broken for it."
                fi
            fi
        fi
        # AU2: the zip itself, whatever became of its manifest, on a release of the update key's time.
        if [ "$digest" != - ] && [ -n "$floor" ] && [[ "$t" =~ ^v[0-9]+(\.[0-9]+){0,7}$ ]] \
           && [ "$(awk "$vcmp"' BEGIN { print vcmp(ARGV[1], ARGV[2]) }' "$t" "$floor")" -ge 0 ]; then
            z="${digest#sha256:}"
            if ! [[ "$digest" == sha256:* && "$z" =~ ^[0-9a-f]{64}$ ]]; then
                alarm "$t ($state): a Sill.zip whose digest GitHub doesn't give ($digest), so it can't be compared with your signing record."
            elif ! awk -v t="$t" -v z="$z" '$2 == t && $4 == z { found = 1 } END { exit !found }' "$record"; then
                alarm "$t ($state): CARRIES A Sill.zip THAT ISN'T IN YOUR SIGNING RECORD (SHA-256 $z), whatever its manifest is called. If you published it just now, sign it; if not, pull it now (docs/release-checklist.md, part 1 §7)."
            fi
        fi
    done < "$dir/releases"
    # N11 b: every release signed here is still listed (a short answer, or one deleted), unless marked pulled.
    cut -f1 "$dir/releases" | sort -u > "$dir/listed-tags"
    while IFS= read -r t; do
        grep -qxF -- "$t" "$dir/listed-tags" || grep -qxF -- "$t" "$dir/pulled-tags" \
            || alarm "$t: IN YOUR SIGNING RECORD BUT NOT ON GITHUB: deleted, or a listing that misses it. If you pulled it, mark it: Scripts/sign-update.sh --pulled $t."
    done < "$dir/signed-tags"
    if [ "$alarms" = 0 ]; then
        echo "Audit: all $n signed releases in $repo (drafts and pre-releases included) are in your signing record, every Sill.zip since ${floor:-the first signed release} is too, and every release you signed is listed."
        exit 0
    fi
    echo "Audit: $alarms thing(s) in $repo aren't what this signer signed or recorded." >&2
    if [ "$notify" = 1 ]; then
        notify_audit "$alarms thing(s) in $repo weren't signed or recorded by your signer. Run Scripts/sign-update.sh --audit in Terminal."
        alarm_sent=1
    fi
    exit 1
fi

# --pulled vX: a release you pulled from GitHub (deleted) stays in the signing record; this marks it, so the audit
# no longer asks where it went. Only the record changes.
if [ "$mode" = pulled ]; then
    [[ "$tag" =~ ^v[0-9]+(\.[0-9]+){0,7}$ ]] || die "a tag like v0.6.2 (got '$tag')"
    awk -v t="$tag" 'NF == 4 && $2 == t { found = 1 } END { exit !found }' "$record" 2>/dev/null || die "$tag isn't in your signing record"
    if [ "$yes" = 0 ]; then
        read -r -p "Mark $tag as pulled from GitHub, so the audit stops asking where it went? [y/N] " answer
        [ "$answer" = y ] || [ "$answer" = Y ] || die "nothing marked"
    fi
    printf '%s %s pulled\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tag" >> "$record"
    echo "Marked $tag as pulled in $record."
    exit 0
fi

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

# R1: your tag's commit, and GitHub's tag naming the same one (a moved tag there is never signed).
commit="$(git -C "$source" rev-parse --verify -q "$tag^{commit}")" || die "no tag $tag in $source"
echo "== $tag on GitHub against yours ($commit)"
remote="$(gh api "repos/$repo/git/ref/tags/$tag" | jq -r '.object.type + " " + .object.sha')" || die "no tag $tag in $repo"
for _ in 1 2 3; do
    [ "${remote%% *}" = tag ] || break
    remote="$(gh api "repos/$repo/git/tags/${remote##* }" | jq -r '.object.type + " " + .object.sha')" || die "can't read $repo's tag $tag"
done
[ "$remote" = "commit $commit" ] || die "$repo's tag $tag names ${remote##* }, not your $tag's $commit: nothing signed (a moved tag; docs/one-click-update-plan.md §12d, R1)"

# R2: what changed in the updater's own files since the last release signed here.
last="$(awk -v t="$tag" '$2 != t && $2 ~ /^v[0-9]/ { l = $2 } END { print l }' "$record" 2>/dev/null || true)"
if [ -n "$last" ] && git -C "$source" rev-parse --verify -q "$last^{commit}" > /dev/null; then
    echo "== the updater's own files since $last, the last release you signed"
    changes="$(git -C "$source" diff --stat "$last" "$tag" -- "${updater_files[@]}")"
    if [ -n "$changes" ]; then
        sed 's/^/  /' <<<"$changes"
        echo "  (all of it: git -C \"$source\" diff $last $tag -- ${updater_files[*]})"
        # Asked whatever --yes says (the third security pass's R2): these lines run on every Sill that installs this.
        answer=""
        read -r -p "Have you read these changes, which every Sill runs once it has this release? [y/N] " answer || true
        [ "$answer" = y ] || [ "$answer" = Y ] || die "nothing signed: read the updater's changes first"
    else
        echo "  none"
    fi
fi

work="$source/.build/update-sign"
mkdir -p "$work"
# R1′ (the third security pass): a release the release workflow built is signed only from the run Noah approved,
# by GitHub's own record of it: the commit it built must be his tag's, and the zip is the one it kept.
if [ -n "$run_id" ]; then
    [[ "$run_id" =~ ^[0-9]{1,20}$ ]] || die "--run takes the run's number (the digits at the end of its page's address)"
    [ -z "$zip" ] || die "--run takes the zip from the run's artifact: no --zip with it"
    echo "== run $run_id in $repo"
    run_json="$(gh api "repos/$repo/actions/runs/$run_id")" || die "no run $run_id in $repo"
    [ "$(jq -r '.path // empty' <<<"$run_json")" = ".github/workflows/release.yml" ] || die "run $run_id is not the release workflow's: nothing signed"
    [ "$(jq -r '.status + " " + (.conclusion // "")' <<<"$run_json")" = "completed success" ] || die "run $run_id didn't finish successfully: nothing signed"
    [ "$(jq -r '.head_branch // empty' <<<"$run_json")" = "$tag" ] || die "run $run_id wasn't started for $tag: nothing signed"
    # The fourth security pass's N11 c: a pushed tag or Run workflow, on this repository's own code (head_sha decides;
    # these make a mistake visible).
    run_event="$(jq -r '.event // empty' <<<"$run_json")"
    [ "$run_event" = push ] || [ "$run_event" = workflow_dispatch ] || die "run $run_id was started by ${run_event:-nothing it names}, not a pushed tag or Run workflow: nothing signed"
    run_repo="$(jq -r '.head_repository.full_name // empty' <<<"$run_json")"
    [ "$run_repo" = "$repo" ] || die "run $run_id built ${run_repo:-no repository}'s code, not $repo's: nothing signed"
    run_sha="$(jq -r '.head_sha // empty' <<<"$run_json")"
    [ "$run_sha" = "$commit" ] || die "run $run_id built ${run_sha:-no commit}, not your $tag's $commit: nothing signed (a tag moved for the run and back; docs/one-click-update-plan.md §12e, R1′)"
    echo "  it built $run_sha, your $tag's commit"
    run_dir="$(mktemp -d "$work/run-$run_id.XXXXXX")"
    cleanup+=("$run_dir")
    gh run download "$run_id" --repo "$repo" --name "sill-zip-$tag" --dir "$run_dir" > /dev/null \
        || die "run $run_id has no artifact sill-zip-$tag (release.yml keeps the published zip as one for 30 days)"
    zip="$run_dir/Sill-$version.zip"
    [ -f "$zip" ] && [ ! -L "$zip" ] || die "run $run_id's artifact holds no Sill-$version.zip"
fi
[ -n "$zip" ] || zip="$source/.build/Sill-$version.zip"
[ -f "$zip" ] || die "no zip of $version built on this Mac at $zip. Sign only a release you built here (release.sh --publish), or one the release workflow built in a run you approved (--run with its number): a build CI made unapproved is never signed (docs/one-click-update-plan.md T4)."
sha_expected="$(shasum -a 256 "$zip" | cut -d' ' -f1)"
echo "== the zip you know: $zip, SHA-256 $sha_expected"

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
cleanup+=("$dir")
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
plist="$app/Contents/Info.plist"
# A nightly is never signed as a release (the third security pass's N10 e): a nightly of the tag's commit would
# otherwise pass every other check.
channel="$(/usr/libexec/PlistBuddy -c 'Print :SillChannel' "$plist" 2>/dev/null || true)"
[ -z "$channel" ] || die "the app is a $channel build (SillChannel in its Info.plist): a release is never signed from one"
codesign --verify --strict --deep --verbose=2 -R "=$pinned and notarized" "$app" 2>&1 | sed 's/^/  /'
xcrun stapler validate "$app" >/dev/null || die "the app has no valid stapled ticket"
assessment="$(spctl -a -t exec -vv "$app" 2>&1 || true)"
grep -q "source=Notarized Developer ID" <<< "$assessment" || die "spctl does not say Notarized Developer ID"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "me.saffer.sill.mac" ] || die "not me.saffer.sill.mac"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version" ] || die "the app's version is not $version"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"

# R1: built from your tag's very commit (make-app.sh writes it, the code signature seals it).
built_from="${SILL_SIGN_TEST_BUILT_FROM:-$(/usr/libexec/PlistBuddy -c 'Print :SillCommit' "$plist" 2>/dev/null || true)}"
if [ "$built_from" != "$commit" ]; then
    [ -n "$built_from" ] || built_from="no commit it names (no SillCommit in its Info.plist)"
    die "the app was built from $built_from, not from $tag's $commit: nothing signed (docs/one-click-update-plan.md §12d, R1)"
fi
echo "  built from $commit, the commit of your $tag and of GitHub's"
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
# The signing record (A1), before anything is uploaded: --audit compares GitHub's manifests with it.
printf '%s %s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tag" "$(shasum -a 256 "$dir/Sill.zip.manifest" | cut -d' ' -f1)" "$sha" >> "$record"
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
