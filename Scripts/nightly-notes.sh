#!/bin/bash
# The words of a nightly (docs/release-checklist.md, "Nightlies"): the pull requests merged into main
# since the last release tag, for the pre-release's notes on GitHub and for TestFlight's What to Test.
#
#   Scripts/nightly-notes.sh --markdown FILE --whats-new FILE [--repo OWNER/NAME]
#
# The pull requests are the ones whose merge is on main's first-parent line between the newest tag
# v<version> that HEAD contains (v0.5.1, say; never "nightly") and HEAD: a merge commit "Merge pull
# request #N from …" or a squashed one ending "(#N)". Their titles and authors come from GitHub
# (gh pr list, with GH_TOKEN in a workflow); a number GitHub doesn't answer for keeps a title made
# from the commit. Nothing here writes anywhere but the two files.
#
# SILL_NIGHTLY_DATE (YYYYMMDD, UTC; default today) is the night's date, as release.sh --nightly names
# the Mac's files. The build number is the commit count (git rev-list --count HEAD), Sill for Mac's
# and the iOS app's alike; each app's version is its own file's (Packaging/Info.plist, the iOS
# project's MARKETING_VERSION).
#
# Titles are other people's text: control characters are dropped, "@" gets a zero-width space after
# it in the Markdown (GitHub would otherwise mention, and notify, whoever a title names, every night
# the notes are written again), "<" and ">" are written as entities, and authors are written without
# "@". What to Test stays within App Store Connect's 4,000 characters (counted here in bytes, which
# is never fewer): the list ends with "… and N more" and the pre-release's address when it would not.
set -euo pipefail

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

say() { printf '==> %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# The newest tag v<digits and dots> that HEAD contains, by version, or nothing.
last_release_tag() {
    git tag --merged HEAD --list 'v[0-9]*' --sort=-v:refname 2>/dev/null \
        | grep -E '^v[0-9]+(\.[0-9]+)*$' | head -n 1 || true
}

# The pull requests merged on main's first-parent line in $1..HEAD (all of HEAD's line without $1),
# newest first, one "<number><tab><title from the commit>" a line.
merged_from_git() {
    local range="$1"
    git log --first-parent --format='%s' ${range:+"$range"} | awk '
        /^Merge pull request #[0-9]+ from / {
            n = $4; sub(/^#/, "", n); from = $6
            if (!(n in seen)) { seen[n] = 1; printf "%s\tPull request #%s (%s)\n", n, n, from }
            next
        }
        match($0, /\(#[0-9]+\)$/) {
            n = substr($0, RSTART + 2, RLENGTH - 3); title = substr($0, 1, RSTART - 1); sub(/[ \t]+$/, "", title)
            if (!(n in seen)) { seen[n] = 1; printf "%s\t%s\n", n, title }
        }'
}

# Control characters out (tabs and newlines among them), runs of spaces as one.
plain() {
    LC_ALL=C tr -d '\000-\010\013-\037\177' | tr '\t\n' '  ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//'
}

# For Markdown: the plain text with @ broken (no mention), < and > as entities.
markdown_safe() {
    plain | LC_ALL=C sed -e $'s/@/@\xe2\x80\x8b/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

main() {
    local markdown="" whats_new="" repo="${GITHUB_REPOSITORY:-Saffsanity/sill}"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --markdown) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; markdown="$2"; shift ;;
            --whats-new) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; whats_new="$2"; shift ;;
            --repo) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; repo="$2"; shift ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        shift
    done
    if [ -z "$markdown" ] && [ -z "$whats_new" ]; then usage >&2; exit 2; fi
    case "$markdown" in ""|/*) ;; *) markdown="$PWD/$markdown" ;; esac
    case "$whats_new" in ""|/*) ;; *) whats_new="$PWD/$whats_new" ;; esac
    cd "$(dirname "${BASH_SOURCE[0]}")/.."

    local date="${SILL_NIGHTLY_DATE:-$(date -u +%Y%m%d)}"
    [[ "$date" =~ ^[0-9]{8}$ ]] || fail "SILL_NIGHTLY_DATE is '$date', not YYYYMMDD"
    local day="${date:0:4}-${date:4:2}-${date:6:2}"
    local head short build mac_version ios_version tag range tag_date
    head="$(git rev-parse HEAD)"
    short="${head:0:7}"
    build="$(git rev-list --count HEAD)"
    mac_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
    ios_version="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION = "?([^";]*)"?;[[:space:]]*$/\1/p' iOSClient/Sill.xcodeproj/project.pbxproj | sort -u | head -n 1)"
    tag="$(last_release_tag)"
    range="${tag:+$tag..HEAD}"
    say "The night of $day: $short, build $build; Sill for Mac $mac_version, Sill for iPhone and iPad ${ios_version:-?}; merged since ${tag:-the first commit}"

    # The pull requests, newest first: "<number><tab><title><tab><author>".
    local from_git titles="" merged="" number title author fallback count=0
    from_git="$(merged_from_git "$range")"
    if [ -n "$from_git" ]; then
        tag_date="$( { git log -1 --format=%cs "${tag:-HEAD}" 2>/dev/null || true; } | head -n 1)"
        # A day before the tag's commit, so a merge on that day in another time zone is still asked for.
        tag_date="$(date -j -u -v-1d -f '%Y-%m-%d' "${tag_date:-2026-01-01}" '+%Y-%m-%d' 2>/dev/null || echo "${tag_date:-2026-01-01}")"
        if ! titles="$(gh pr list --repo "$repo" --state merged --base main --limit 1000 --search "merged:>=$tag_date" \
                --json number,title,author --jq '.[] | [.number, .title, .author.login] | @tsv' 2>/dev/null)"; then
            echo "warning: gh couldn't list $repo's merged pull requests; the titles come from the commits" >&2
            titles=""
        fi
        while IFS=$'\t' read -r number fallback; do
            [ -n "$number" ] || continue
            title="$(awk -F '\t' -v n="$number" '$1 == n { print $2; exit }' <<<"$titles")"
            author="$(awk -F '\t' -v n="$number" '$1 == n { print $3; exit }' <<<"$titles")"
            merged="$merged$number"$'\t'"${title:-$fallback}"$'\t'"$author"$'\n'
            count=$((count + 1))
        done <<<"$from_git"
    fi
    local since="${tag#v}"
    since="${since:-the first commit}"

    if [ -n "$markdown" ]; then
        {
            if [ "$count" = 0 ]; then
                echo "### Nothing merged into main since ${tag:-the first commit}"
            else
                echo "### Merged into main since ${tag:+Sill }$since ($count pull request$([ "$count" = 1 ] || echo s))"
                echo
                while IFS=$'\t' read -r number title author; do
                    [ -n "$number" ] || continue
                    printf -- '- %s (#%s%s)\n' "$(printf '%s' "$title" | markdown_safe)" "$number" \
                        "$( [ -n "$author" ] && printf ' by %s' "$(printf '%s' "$author" | plain | tr -d '@')" )"
                done <<<"$merged"
            fi
        } >"$markdown"
        say "Wrote the notes for GitHub: $markdown ($count pull requests)"
    fi

    if [ -n "$whats_new" ]; then
        local head_text tail_text body="" line candidate more=0 shown=0 limit=4000
        local more_line="… and 999 more: https://github.com/Saffsanity/sill/releases/tag/nightly"
        head_text="Nightly build of main: Sill ${ios_version:-$mac_version} ($build), commit $short, $day. It is not a release and can break. Some changes need Sill for Mac's nightly of the same date: https://github.com/Saffsanity/sill/releases/tag/nightly"
        tail_text="Feedback: take a screenshot while you use Sill, or Send Beta Feedback in TestFlight, or write to support@getsill.app."
        if [ "$count" = 0 ]; then
            body="Nothing merged into main since $since: the same as the last nightly, built again."
        else
            body="Merged since $since:"
            while IFS=$'\t' read -r number title author; do
                [ -n "$number" ] || continue
                line="• $(printf '%s' "$title" | plain) (#$number)"
                candidate="$body"$'\n'"$line"
                # The whole text with this line and room for a "… and N more" line, in bytes.
                if [ "$(printf '%s\n\n%s\n%s\n\n%s\n' "$head_text" "$candidate" "$more_line" "$tail_text" | LC_ALL=C wc -c | tr -d ' ')" -gt "$limit" ]; then
                    more=$((count - shown))
                    break
                fi
                body="$candidate"
                shown=$((shown + 1))
            done <<<"$merged"
            if [ "$more" -gt 0 ]; then
                body="$body"$'\n'"… and $more more: https://github.com/Saffsanity/sill/releases/tag/nightly"
            fi
        fi
        printf '%s\n\n%s\n\n%s\n' "$head_text" "$body" "$tail_text" >"$whats_new"
        say "Wrote What to Test: $whats_new ($(LC_ALL=C wc -c <"$whats_new" | tr -d ' ') bytes; $shown of $count pull requests listed)"
    fi
}

# Sourced (to test its functions), the script only defines them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
