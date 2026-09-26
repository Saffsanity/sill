#!/bin/bash
# Makes the Sill.app people download: built and signed with Developer ID, notarized by Apple, the
# ticket stapled, zipped, and checked the way Gatekeeper will check it on someone else's Mac.
#
#   SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary \
#     Scripts/release.sh             build, zip, notarize, staple, zip again, verify
#   Scripts/release.sh --dry-run     the same checks, build and first zip, then stops before
#                                    notarytool and prints what a real run would do next
#   Scripts/release.sh --publish     everything, then a GitHub Release (tag v<version>) with the
#                                    assets Sill.zip and Sill.zip.sha256, which the site's download
#                                    page links under those fixed names (needs gh, signed in, and
#                                    the tag pushed: origin's v<version> must name HEAD)
#
# SILL_SIGN_IDENTITY names a Developer ID Application identity in your keychain: its name, part of
# it, or its SHA-1 hash, as for make-app.sh. SILL_NOTARY_PROFILE is the profile name you gave
# `xcrun notarytool store-credentials` (a dry run only warns when it is missing).
# docs/release-checklist.md says how to get both, and what to do with the zip.
#
# --publish makes the release in SILL_RELEASE_REPO, by default Saffsanity/sill: the one repository
# whose releases every Sill.app's update check reads (Sources/SillMenuBar/UpdatePolicy.swift,
# `feed`). A release anywhere else can be downloaded, but no Sill.app offers it, and the script
# warns before it builds and again as it publishes.
#
# Why each step:
# - make-app.sh --release signs with the hardened runtime and a secure timestamp and without
#   get-task-allow, which notarization requires, and refuses any signature but Developer ID, and
#   any HEAD but the commit tagged v<version> (Packaging/Info.plist's CFBundleShortVersionString),
#   the tag every Sill.app's update check compares with the version it runs. A dry run only
#   warns about the tag: it rehearses on any commit, and its zip is never notarized.
# - ditto -c -k --keepParent is the zip Apple's notarization docs use; it keeps the bundle intact.
# - Notarization is Apple's automated malware scan, not App Review. Apple also publishes the
#   ticket online, but stapling puts it inside the app, so Gatekeeper finds it on a Mac that is
#   offline.
# - The zip is made again after stapling: the first one, the one sent to Apple, has no ticket.
# - Last, a copy unpacked from the final zip must pass `stapler validate` and `spctl` as
#   "Notarized Developer ID": that zip is exactly what people download.
# - --publish checks origin's tag before it builds: `gh release create` makes a tag the release's
#   repository lacks from its default branch's tip, so the release (and its source archives) would
#   name another commit than the one built, and pushing the real tag later would be refused. In
#   Saffsanity/sill it also passes --verify-tag, so gh itself refuses a tag that isn't there.
set -euo pipefail

usage() {
    cat <<'USAGE'
usage: Scripts/release.sh [--dry-run | --publish]

  SILL_SIGN_IDENTITY='Developer ID Application: … (TEAMID)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh
      builds Sill.app with make-app.sh --release, zips it, has Apple notarize it, staples the
      ticket, zips it again, checks the zip's copy with stapler and spctl, and prints the zip's
      path and SHA-256 for site/download.html.
  --dry-run
      the same checks, build and first zip; stops before notarytool and prints the rest.
  --publish
      after the checks, creates the GitHub Release v<version> in $SILL_RELEASE_REPO
      (default Saffsanity/sill) with Sill.zip and Sill.zip.sha256, the names the site links.
      Refused, before building, unless origin has the tag v<version> and it names HEAD
      (git push origin v<version>). Every Sill.app's update check reads only Saffsanity/sill's
      releases: one published anywhere else can be downloaded, but no Sill.app offers it.

The one-time setup (certificate, notary credentials) is in docs/release-checklist.md.
USAGE
}

say() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# The valid code-signing identities in the keychain, one per line: "<SHA-1><tab><name>".
signing_identities() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^ *[0-9][0-9]*) \([0-9A-Fa-f]\{40\}\) "\(.*\)"$/\1	\2/p' || true
}

# The identities codesign would take for $1: the one with that SHA-1 hash, or every identity whose
# name contains it.
identities_matching() {
    local wanted="$1"
    if [[ "$wanted" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        signing_identities | awk -F'\t' -v h="$wanted" 'toupper($1) == toupper(h)'
    else
        signing_identities | awk -F'\t' -v n="$wanted" 'index($2, n) > 0'
    fi
}

# Everything a run needs before it builds, checked at once so that one run names every gap.
# Prints one problem per line, and nothing when all is well. $1 is 1 for a dry run, $2 is 1 for
# --publish.
preflight_problems() {
    local dry_run="$1" publish="${2:-0}" identity="${SILL_SIGN_IDENTITY:-}" profile="${SILL_NOTARY_PROFILE:-}"
    local matches count others tool version tags
    if [ -z "$identity" ]; then
        echo "SILL_SIGN_IDENTITY is not set. Set it to your Developer ID Application identity, as in SILL_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'."
    else
        matches="$(identities_matching "$identity")"
        count="$(printf '%s' "$matches" | grep -c . || true)"
        others="$(printf '%s\n' "$matches" | awk -F'\t' 'NF > 1 && index($2, "Developer ID Application: ") != 1 { print $2 }')"
        if [ "$count" -eq 0 ]; then
            echo "No valid signing identity in your keychain matches SILL_SIGN_IDENTITY ('$identity'). 'security find-identity -v -p codesigning' lists the ones there are; a Developer ID Application certificate counts only with its private key in the login keychain."
        elif [ -n "$others" ]; then
            echo "SILL_SIGN_IDENTITY ('$identity') matches '${others%%$'\n'*}', which is not a Developer ID Application identity. Notarization accepts only Developer ID Application signatures."
        elif [ "$count" -gt 1 ]; then
            echo "SILL_SIGN_IDENTITY ('$identity') matches $count identities, and codesign refuses an ambiguous name. Use the SHA-1 hash of one of them: $(printf '%s\n' "$matches" | awk -F'\t' '{ printf "%s%s (%s)", sep, $1, $2; sep = ", " }')."
        fi
    fi
    if [ "$dry_run" = 0 ] && ! head_is_release_tag; then
        version="$(plist_value CFBundleShortVersionString Packaging/Info.plist)" || version="<version>"
        tags="$(git tag --points-at HEAD 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || true)"
        echo "HEAD is not tagged v$version (it is tagged '${tags:-nothing}'). A release is built only from the commit tagged v + Packaging/Info.plist's CFBundleShortVersionString, which every Sill.app's update check compares with the version it runs: commit the version, then git tag v$version and git push origin v$version."
    fi
    if [ "$dry_run" = 0 ] && [ "$publish" = 1 ] && version="$(plist_value CFBundleShortVersionString Packaging/Info.plist)"; then
        remote_tag_problem "$version"
    fi
    if [ "$dry_run" = 0 ]; then
        if [ -z "$profile" ]; then
            echo "SILL_NOTARY_PROFILE is not set. Store your notary credentials once with 'xcrun notarytool store-credentials sill-notary', then set SILL_NOTARY_PROFILE=sill-notary."
        fi
        for tool in notarytool stapler; do
            xcrun --find "$tool" >/dev/null 2>&1 \
                || echo "xcrun can't find $tool. Select Xcode as the developer directory: sudo xcode-select -s /Applications/Xcode.app"
        done
    fi
}

# Whether HEAD carries the tag a release needs: v + Packaging/Info.plist's CFBundleShortVersionString.
head_is_release_tag() {
    local version
    version="$(plist_value CFBundleShortVersionString Packaging/Info.plist)" || return 1
    # grep reads all of it (no -q): an early exit could fail the pipeline under pipefail. -F: the
    # dots are dots.
    git tag --points-at HEAD 2>/dev/null | grep -Fx "v$version" >/dev/null
}

# Why --publish can't use origin's tag v$1, or nothing: origin must have it, naming HEAD. gh makes
# a tag the release's repository lacks from the default branch's tip, so a tag left unpushed would
# publish a release, and source archives, of another commit than the one built.
remote_tag_problem() {
    local version="$1" lines remote head
    if ! lines="$(git ls-remote --tags origin "refs/tags/v$version" "refs/tags/v$version^{}" 2>/dev/null)"; then
        echo "Couldn't read origin's tags (git ls-remote origin failed). --publish needs the tag v$version on origin, naming HEAD: git push origin v$version."
        return 0
    fi
    # An annotated tag's commit is its peeled line (^{}); a lightweight tag's is its own.
    remote="$(awk -v t="refs/tags/v$version" '$2 == (t "^{}") { peeled = $1 } $2 == t { plain = $1 } END { print (peeled != "" ? peeled : plain) }' <<<"$lines")"
    head="$(git rev-parse HEAD 2>/dev/null)" || head=""
    if [ -z "$remote" ]; then
        echo "origin has no tag v$version. --publish makes the GitHub Release of the pushed tag, and gh would otherwise create the tag from the default branch's tip, not from this commit: git push origin v$version."
    elif [ "$remote" != "$head" ]; then
        echo "origin's tag v$version names ${remote:0:12}, not HEAD (${head:0:12}), so the release would name another commit than the one built. Publish from the commit origin's tag names, or correct the tag on origin first."
    fi
}

# The one repository whose releases every Sill.app's update check reads
# (Sources/SillMenuBar/UpdatePolicy.swift, `feed`).
feed_repo=Saffsanity/sill

# Whether $1, a repository as gh takes it ([HOST/]OWNER/REPO, or its URL), is `feed_repo`.
is_feed_repo() {
    local r want
    r="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    want="$(printf '%s' "$feed_repo" | tr '[:upper:]' '[:lower:]')"
    r="${r#https://}"; r="${r#http://}"; r="${r%/}"; r="${r%.git}"
    [ "$r" = "$want" ] || [ "$r" = "github.com/$want" ]
}

# A release anywhere but `feed_repo` can be downloaded, but no Sill.app offers it. Said before a
# --publish run builds, and again as it publishes.
feed_warning() {
    if ! is_feed_repo "$1"; then
        echo "warning: the release goes to $1, not $feed_repo. It can be downloaded there, but no Sill.app will offer it: every Sill.app's update check reads only $feed_repo's releases (docs/release-checklist.md, part 2, Publish)." >&2
    fi
}

# What notarization requires of the signature, read back from the built app. make-app.sh has
# already refused anything but Developer ID; this also catches a signing change there.
check_signature() {
    local app="$1" details
    codesign --verify --strict --deep "$app" || fail "codesign can't verify $app"
    details="$(codesign -dvvv "$app" 2>&1)"
    grep -q '^Authority=Developer ID Application: ' <<<"$details" || fail "$app is not signed with Developer ID"
    grep -q '^CodeDirectory .*flags=.*runtime' <<<"$details" || fail "$app is not signed with the hardened runtime"
    grep -q '^Timestamp=' <<<"$details" || fail "$app has no secure timestamp"
    if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'get-task-allow'; then
        fail "$app carries the get-task-allow entitlement, which notarization refuses"
    fi
}

# Gatekeeper's verdict on one copy of the app: a valid stapled ticket, and "Notarized Developer ID".
check_gatekeeper() {
    local target="$1" verdict
    xcrun stapler validate "$target" || fail "no valid ticket is stapled to $target"
    verdict="$(spctl -a -vv -t exec "$target" 2>&1)" || { printf '%s\n' "$verdict" >&2; fail "Gatekeeper rejects $target"; }
    printf '%s\n' "$verdict"
    grep -q '^source=Notarized Developer ID' <<<"$verdict" || fail "Gatekeeper accepts $target, but not as notarized Developer ID"
}

# One top-level value of a plist file, or a failure (PlistBuddy reports a missing file, an empty
# answer or a missing key on stdout, so its output counts only when it succeeds).
plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

unpacked=""   # the zip's copy being checked; removed on exit
cleanup() { if [ -n "$unpacked" ]; then rm -rf "$unpacked"; fi; }

main() {
    local dry_run=0 publish=0 arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=1 ;;
            --publish) publish=1 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
    done
    cd "$(dirname "${BASH_SOURCE[0]}")/.."

    local problems
    problems="$(preflight_problems "$dry_run" "$publish")"
    if [ -n "$problems" ]; then
        {
            echo "error: Scripts/release.sh can't start:"
            printf '%s\n' "$problems" | sed 's/^/  - /'
            echo "The one-time setup is in docs/release-checklist.md. Nothing was built."
        } >&2
        exit 2
    fi
    if [ "$publish" = 1 ]; then
        feed_warning "${SILL_RELEASE_REPO:-$feed_repo}"
    fi
    if [ "$dry_run" = 1 ] && [ -z "${SILL_NOTARY_PROFILE:-}" ]; then
        echo "warning: SILL_NOTARY_PROFILE is not set; a real run needs it (docs/release-checklist.md)." >&2
    fi
    if [ "$dry_run" = 1 ] && ! head_is_release_tag; then
        echo "warning: HEAD is not tagged v$(plist_value CFBundleShortVersionString Packaging/Info.plist || echo '<version>'); a real run needs that tag (docs/release-checklist.md, part 2)." >&2
    fi
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        echo "warning: the working tree has uncommitted changes. Release from a commit: the build number is the commit count, so a build of that commit without these changes has the same number." >&2
    fi

    say "Building and signing Sill.app (Scripts/make-app.sh --release)"
    if [ "$dry_run" = 1 ]; then
        SILL_RELEASE_DRY_RUN=1 Scripts/make-app.sh --release
    else
        Scripts/make-app.sh --release
    fi

    local app=.build/Sill.app version build zip
    # Read as make-app.sh's last line reads it: the version from Packaging/Info.plist, and the
    # build number (the commit count) it stamped into the bundle.
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
    zip=".build/Sill-$version.zip"
    check_signature "$app"
    say "Sill $version ($build) for $(lipo -archs "$app/Contents/MacOS/Sill"). The site says Apple silicon: change that if this ever lists x86_64."

    say "Zipping $app into $zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"

    if [ "$dry_run" = 1 ]; then
        cat <<DRY

Dry run: stopped before notarization. $zip is signed but not notarized, so don't publish it.
A real run goes on with:
  xcrun notarytool submit $zip --keychain-profile "${SILL_NOTARY_PROFILE:-<SILL_NOTARY_PROFILE>}" --wait --output-format plist
  xcrun notarytool log <submission id> --keychain-profile "${SILL_NOTARY_PROFILE:-<SILL_NOTARY_PROFILE>}" .build/Sill-$version-notary-log.json
  xcrun stapler staple $app
  ditto -c -k --keepParent $app $zip   (again, now with the ticket inside)
  xcrun stapler validate and spctl -a -vv -t exec, on $app and on a copy unpacked from $zip
  shasum -a 256 $zip
DRY
        exit 0
    fi

    local profile="$SILL_NOTARY_PROFILE" result=".build/Sill-$version-notary.plist"
    local log=".build/Sill-$version-notary-log.json" status id submitted=0
    rm -f "$result" "$log"
    say "Sending $zip to Apple's notary service and waiting for its answer (usually a few minutes)"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait --output-format plist >"$result" || submitted=$?
    status="$(plist_value status "$result")" || status=""
    id="$(plist_value id "$result")" || id=""
    if [ -n "$id" ]; then
        # Apple's log lists every issue, and its warnings even when the submission is accepted.
        if xcrun notarytool log "$id" --keychain-profile "$profile" "$log" >/dev/null 2>&1; then
            echo "Apple's notary log: $log"
        else
            echo "warning: couldn't fetch the notary log; try: xcrun notarytool log $id --keychain-profile \"$profile\"" >&2
        fi
    fi
    if [ "$status" != "Accepted" ]; then
        echo "notarytool answered (exit status $submitted):" >&2
        sed 's/^/  /' "$result" >&2
        if [ -f "$log" ]; then
            grep -E '"(message|path|severity)"' "$log" | head -40 | sed 's/^ */  /' >&2 || true
        fi
        fail "notarization ended with status '${status:-unknown}'. Nothing was stapled."
    fi
    if [ -f "$log" ] && ! grep -Eq '"issues"[[:space:]]*:[[:space:]]*null' "$log"; then
        echo "warning: the notary log lists issues; read $log before publishing." >&2
    fi

    say "Stapling the ticket to $app"
    xcrun stapler staple "$app"

    say "Zipping the stapled app into $zip"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"

    say "Checking $app, and a copy unpacked from $zip"
    trap cleanup EXIT
    unpacked="$(mktemp -d "${TMPDIR:-/tmp}/sill-release.XXXXXX")"
    ditto -x -k "$zip" "$unpacked"
    check_gatekeeper "$app"
    check_gatekeeper "$unpacked/Sill.app"

    local sha
    sha="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
    echo
    echo "Sill $version ($build) is notarized, stapled and zipped:"
    shasum -a 256 "$zip"
    if [ "$publish" = 1 ]; then
        publish_release "$zip" "$version" "$build" "$sha"
    else
        echo "Next (docs/release-checklist.md): Scripts/release.sh --publish creates the GitHub Release"
        echo "v$version with Sill.zip and Sill.zip.sha256, which https://getsill.app/download links."
        echo "It refuses to start until origin has the tag: git push origin v$version."
        echo "  SHA-256  $sha"
    fi
}

# The GitHub Release the site's download page links: tag v<version>, assets named exactly Sill.zip and
# Sill.zip.sha256 so /releases/latest/download/<name> keeps working release after release.
publish_release() {
    local zip="$1" version="$2" build="$3" sha="$4"
    local repo="${SILL_RELEASE_REPO:-$feed_repo}" dir asset verify=""
    command -v gh >/dev/null || fail "gh is not installed (brew install gh), or not on PATH"
    gh auth status >/dev/null 2>&1 || fail "gh is not signed in: run gh auth login"
    if gh release view "v$version" --repo "$repo" >/dev/null 2>&1; then
        fail "release v$version already exists in $repo; bump the version in Packaging/Info.plist first"
    fi
    # The release's tag is the pushed one (the preflight checked origin's): in the feed's repository
    # gh must find it there too, and never make it from the default branch. Another repository never
    # holds the source's tags, so there gh makes one, which nothing reads.
    if is_feed_repo "$repo"; then verify=1; else feed_warning "$repo"; fi
    dir="$(mktemp -d "${TMPDIR:-/tmp}/sill-publish.XXXXXX")"
    asset="$dir/Sill.zip"
    cp "$zip" "$asset"
    (cd "$dir" && shasum -a 256 Sill.zip > Sill.zip.sha256)
    say "Creating the GitHub Release v$version in $repo"
    if ! gh release create "v$version" "$asset" "$dir/Sill.zip.sha256" --repo "$repo" ${verify:+--verify-tag} \
        --title "Sill $version" \
        --notes "Sill for Mac $version ($build), notarized. SHA-256 of Sill.zip: $sha. Download at https://getsill.app/download"; then
        rm -rf "$dir"
        fail "gh release create failed for v$version in $repo (its message is above). If it left a draft release there, delete it before trying again."
    fi
    rm -rf "$dir"
    echo "Published: https://github.com/$repo/releases/tag/v$version"
    if [ -n "$verify" ]; then
        echo "The site's Download button already points at the newest release."
    else
        echo "The site's Download button links $feed_repo's newest release: point site/download.html's three links at $repo while releases go there."
    fi
}

# Sourced (to test its functions), the script only defines them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
