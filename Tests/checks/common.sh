# Sourced by every Tests/checks/<name>/run.sh once it has set `here` (its own folder).
#
# Sets `root` (the repository: every path in a check's compile line starts there), `name` (the
# check's folder name) and `out` (.build/checks/<name>: its binary, data and logs; .build is
# git-ignored), makes `out`, and changes to `root`. Gives `run_mutants`.
set -euo pipefail
root="$(cd "$here/../../.." && pwd)"
name="$(basename "$here")"
out="$root/.build/checks/$name"
mkdir -p "$out"
cd "$root"

# run_mutants COMMAND [ARG...]: runs a check's mutants script. Each mutant changes the checked source
# in one place, compiles it with the check and must make the check fail. The script's last word is
# a count, "12 of 12 mutants caught" or "mutants caught: 12 of 12", and some scripts exit 0 whatever
# it says, so the count decides: every mutant caught and a zero exit, or this returns 1.
run_mutants() {
    local log="$out/mutants.log" status summary=""
    set +e
    PYTHONUNBUFFERED=1 "$@" 2>&1 | tee "$log"   # unbuffered: each mutant's line as it is judged
    status=${PIPESTATUS[0]}
    set -e
    summary="$(grep -E '[0-9]+ of [0-9]+ mutants caught|mutants caught: [0-9]+ of [0-9]+' "$log" | tail -n 1 || true)"
    if [[ "$summary" =~ ([0-9]+)\ of\ ([0-9]+) ]] && [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] && [ "$status" -eq 0 ]; then
        echo "$name: every mutant caught (${BASH_REMATCH[1]} of ${BASH_REMATCH[2]})"
        return 0
    fi
    echo "$name: mutants FAILED (exit status $status; ${summary:-no count printed}); the log is $log" >&2
    return 1
}
