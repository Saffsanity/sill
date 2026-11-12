#!/bin/bash
# The step files (docs/steps/<date>-<branch>.md): each piece of work's notes in a file of its own,
# written by the branch that does the work (CLAUDE.md, "Steps").
#
#   Scripts/steps.sh new [BRANCH]     make docs/steps/<today>-<branch>.md for this branch (or BRANCH)
#                                     with its first line to fill in, unless the branch has one already
#   Scripts/steps.sh list [N]         the newest N step files first (default 10), with their titles
#   Scripts/steps.sh find WHAT        the step files that name WHAT: a pull request's number (349 or
#                                     #349), a branch, or any words
#
# Only reads, but for `new`, which writes one file and nothing else (no commit).
set -euo pipefail
cd "$(dirname "$0")/.."
steps=docs/steps

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

title() {   # a step file's title: its bold first words, else its first line, cut to 100 characters
    head -n 3 "$1" | tr '\n' ' ' | sed -e 's/^\*\*//' -e 's/\*\*.*//' -e 's/^## //' | cut -c1-100
}

case "${1:-}" in
    new)
        branch="${2:-$(git rev-parse --abbrev-ref HEAD)}"
        if [ "$branch" = HEAD ] || [ -z "$branch" ]; then
            echo "error: not on a branch: give its name, Scripts/steps.sh new BRANCH" >&2; exit 2
        fi
        slug="$(printf '%s' "$branch" | tr 'A-Z/' 'a-z-' | tr -c 'a-z0-9.\n-' '-')"
        existing="$(ls "$steps" 2>/dev/null | grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}-${slug}\.md$" || true)"
        if [ -n "$existing" ]; then
            echo "$steps/$existing (this branch's, already there)"; exit 0
        fi
        file="$steps/$(date +%Y-%m-%d)-$slug.md"
        base="$(git merge-base HEAD origin/main 2>/dev/null | cut -c1-7 || true)"
        printf '**%s (%s, branch `%s` from main at %s).** \n' \
            "TITLE: what it does, in plain words" "$(date +%Y-%m-%d)" "$branch" "${base:-?}" > "$file"
        echo "$file: fill in the title and the notes (what, why, the decisions, what was verified, what is untested for Noah)"
        ;;
    list)
        n="${2:-10}"
        ls "$steps" | grep -E '^[0-9]{4}-' | sort -r | head -n "$n" | while read -r f; do
            printf '%-58s %s\n' "$f" "$(title "$steps/$f")"
        done
        ;;
    find)
        [ $# -ge 2 ] || { usage >&2; exit 2; }
        what="${2#\#}"
        if printf '%s' "$what" | grep -qE '^[0-9]+$'; then
            pattern="#${what}([^0-9]|$)"
        else
            pattern="$(printf '%s' "$2" | sed 's/[][\.*^$/]/\\&/g')"
        fi
        { ls "$steps" | grep -F -- "$2" || true; grep -lE -- "$pattern" "$steps"/*.md 2>/dev/null | xargs -n1 basename || true; } \
            | grep -v '^README.md$' | sort -ru | while read -r f; do
                printf '%-58s %s\n' "$f" "$(title "$steps/$f")"
            done
        ;;
    -h|--help|"")
        usage
        ;;
    *)
        usage >&2; exit 2
        ;;
esac
