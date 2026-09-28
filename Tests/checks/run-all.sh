#!/bin/bash
# Runs the pure checks. Each folder's run.sh compiles the app's own source files it names together
# with its main.swift (swiftc; no Xcode project, no package build) and runs the result. Nothing here
# needs a device, Screen Recording, Accessibility, the video encoder or any network but loopback.
#
#   Tests/checks/run-all.sh                   every check (about five minutes on an M-series Mac)
#   Tests/checks/run-all.sh policy fence      only these
#   Tests/checks/run-all.sh --mutants [...]   also each check's mutants (slow: the lot takes well over an hour)
#   Tests/checks/run-all.sh -v [...]          show every check's whole output as it runs
#
# Each check's output goes to .build/checks/<name>/run.log (and mutants.log). A failing check's FAIL
# lines and last lines are printed here. The exit status is the number of checks that failed. Every
# folder with a run.sh is a check: one whose run.sh is not executable fails rather than being
# skipped, so a new check can't sit out CI unnoticed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
mutants=0 verbose=0
names=()
for arg in "$@"; do
    case "$arg" in
        --mutants) mutants=1 ;;
        -v|--verbose) verbose=1 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "usage: Tests/checks/run-all.sh [--mutants] [-v] [check ...]" >&2; exit 2 ;;
        *) names+=("$arg") ;;
    esac
done
if [ ${#names[@]} -eq 0 ]; then
    for dir in "$here"/*/; do
        if [ -f "$dir/run.sh" ]; then names+=("$(basename "$dir")"); fi
    done
fi
if [ ${#names[@]} -eq 0 ]; then
    echo "error: no checks: no Tests/checks/<name>/run.sh" >&2
    exit 1
fi

failed=()
summary=()
started=$SECONDS
for name in "${names[@]}"; do
    if [ ! -f "$here/$name/run.sh" ]; then
        echo "error: no check named '$name' (no Tests/checks/$name/run.sh)" >&2
        failed+=("$name")
        continue
    fi
    if [ ! -x "$here/$name/run.sh" ]; then
        echo "error: Tests/checks/$name/run.sh is not executable: chmod +x it (git keeps the bit)" >&2
        summary+=("$(printf '  FAILED  %4ss  %-26s run.sh is not executable' 0 "$name")")
        failed+=("$name")
        continue
    fi
    steps=(check)
    if [ "$mutants" = 1 ] && [ -f "$here/$name/mutants.py" ]; then steps+=(mutants); fi
    for step in "${steps[@]}"; do
        mkdir -p "$root/.build/checks/$name"
        if [ "$step" = check ]; then
            log="$root/.build/checks/$name/run.log"; label="$name"; args=()
        else
            log="$root/.build/checks/$name/mutants-run.log"; label="$name --mutants"; args=(--mutants)
        fi
        echo "==> $label"
        start=$SECONDS
        if [ "$verbose" = 1 ]; then
            "$here/$name/run.sh" ${args[@]+"${args[@]}"} 2>&1 | tee "$log"
            status=${PIPESTATUS[0]}
        else
            "$here/$name/run.sh" ${args[@]+"${args[@]}"} > "$log" 2>&1
            status=$?
        fi
        seconds=$((SECONDS - start))
        last="$(grep -v '^[[:space:]]*$' "$log" | tail -n 1 | cut -c1-110)"
        if [ "$status" -eq 0 ]; then
            summary+=("$(printf '  passed  %4ss  %-26s %s' "$seconds" "$label" "$last")")
        else
            summary+=("$(printf '  FAILED  %4ss  %-26s exit status %s' "$seconds" "$label" "$status")")
            failed+=("$label")
            if [ "$verbose" = 0 ]; then
                echo "---- $label failed (exit status $status); its FAIL lines:"
                grep -E '^(FAIL|MISSED)|NOT CAUGHT|NOT APPLIED|did not compile|DOES NOT COMPILE|error:' "$log" | head -n 40 || true
                echo "---- its last 25 lines ($log):"
                tail -n 25 "$log"
                echo "----"
            fi
        fi
    done
done

echo
echo "Pure checks, $((SECONDS - started)) s in all:"
if [ ${#summary[@]} -gt 0 ]; then printf '%s\n' "${summary[@]}"; fi
if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit "${#failed[@]}"
fi
echo "All passed."
