#!/bin/bash
# Prints every check: its name, "mutants" when it has a mutants.py, and what it checks, from the
# **Checks:** paragraph of its own README.md. Nothing keeps this list by hand: it is read from the
# folders each time, so it is never stale and no two branches edit it.
#
#   Tests/checks/list.sh              one line a check, cut to the terminal's width
#   Tests/checks/list.sh --markdown   a Markdown table: check, mutants, what it checks, what it compiles
#   Tests/checks/list.sh NAME...      only these, whole
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
markdown=0
names=()
for arg in "$@"; do
    case "$arg" in
        --markdown) markdown=1 ;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        -*) echo "usage: Tests/checks/list.sh [--markdown] [check ...]" >&2; exit 2 ;;
        *) names+=("$arg") ;;
    esac
done
whole=1
if [ ${#names[@]} -eq 0 ]; then
    whole=0
    for dir in "$here"/*/; do
        if [ -f "$dir/run.sh" ]; then names+=("$(basename "$dir")"); fi
    done
fi

# The first paragraph that starts with **LABEL:** in a README, without the label, on one line.
para() {
    awk -v label="**$2:** " '
        index($0, label) == 1 { on = 1; $0 = substr($0, length(label) + 1) }
        on && $0 == "" { exit }
        on { printf "%s%s", (n++ ? " " : ""), $0 }
    ' "$1"
}

width="${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}"
if [ "$markdown" = 1 ]; then
    echo "| Check | Mutants | What it checks | Compiles |"
    echo "|---|---|---|---|"
fi
status=0
for name in "${names[@]}"; do
    readme="$here/$name/README.md"
    mutants=""
    if [ -f "$here/$name/mutants.py" ]; then mutants="mutants"; fi
    if [ ! -f "$readme" ]; then
        what="(no README.md: every check describes itself in one)"
        compiles=""
        status=1
    else
        what="$(para "$readme" Checks)"
        compiles="$(para "$readme" Compiles)"
    fi
    if [ "$markdown" = 1 ]; then
        printf '| `%s` | %s | %s | %s |\n' "$name" "${mutants:-no}" "${what//|/\\|}" "${compiles//|/\\|}"
    elif [ "$whole" = 1 ]; then
        printf '%s%s\n  Checks: %s\n  Compiles: %s\n' "$name" "${mutants:+ (mutants)}" "$what" "$compiles"
    else
        line="$(printf '%-20s %-8s %s' "$name" "$mutants" "$what")"
        printf '%s\n' "${line:0:$width}"
    fi
done
exit "$status"
