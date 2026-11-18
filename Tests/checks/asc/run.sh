#!/bin/bash
# Scripts/asc.swift, the nightly's tool for App Store Connect's TestFlight API, whole (it is a script),
# against standin.py: a stand-in App Store Connect on 127.0.0.1 that checks every token's ES256
# signature with openssl, with throwaway P-256 keys made here for each run. Every run of asc is under
# sandbox-exec with only loopback allowed, so nothing it does, nor a mutant of it, reaches Apple or
# any other host (checked first: a connection elsewhere is refused). The token, the groups, the build's
# states, the wait, What to Test (a build that has its own keeps it unless --replace-whats-new: the
# nightly of 2026-11-09 replaced build 1304's), the groups given, the public beta's two locks, Beta App
# Review, retries, pages, redirects and usage. From the nightly's harness of 2026-10-29 (PR #246).
#   Tests/checks/asc/run.sh                  compile and run the check
#   Tests/checks/asc/run.sh --binary PATH    run it against an asc already compiled (mutants.py's)
#   Tests/checks/asc/run.sh --mutants        one-place mutants of asc.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
if [ "${1:-}" = "--binary" ]; then
    asc="$2"
else
    asc="$out/asc"
    rm -f "$asc"
    swiftc -O Scripts/asc.swift -o "$asc"
fi
set +e

work="$out/work"
keys="$out/keys"
rm -rf "$work" "$keys"; mkdir -p "$work" "$keys"
( cd "$keys" && openssl ecparam -genkey -name prime256v1 -noout -out ec.pem && openssl pkcs8 -topk8 -nocrypt -in ec.pem -out AuthKey_TESTKEY123.p8 \
    && openssl ec -in ec.pem -pubout -out pub.pem && openssl ecparam -genkey -name prime256v1 -noout -out other.pem \
    && openssl pkcs8 -topk8 -nocrypt -in other.pem -out AuthKey_OTHERKEY12.p8 ) >/dev/null 2>&1 \
    || { echo "FAIL: openssl didn't make the throwaway keys"; exit 1; }
unset GITHUB_ACTIONS SILL_NIGHTLY_PUBLIC_BETA   # the same words here and in CI; a scenario sets them itself
KID=TESTKEY123
ISS=69a6de70-1111-2222-3333-444455556666
# Loopback only: no other address, and no name lookups (mDNSResponder's socket is outbound too).
sandbox='(version 1)(allow default)(deny network-outbound)(allow network-outbound (remote ip "localhost:*"))'
pass=0; failed=0
check() { # name, then a command that must succeed
    local name="$1"; shift
    if "$@"; then pass=$((pass + 1)); else failed=$((failed + 1)); echo "FAIL: $name" >&2; fi
}

# 0. The sandbox the runs of asc go under refuses a connection to any address but loopback.
sandbox-exec -p "$sandbox" python3 -I -c "
import socket, sys
s = socket.socket(); s.settimeout(3)
try:
    s.connect(('192.0.2.1', 9)); sys.exit(1)   # TEST-NET-1: never reached even when this fails
except PermissionError:
    sys.exit(0)
except OSError:
    sys.exit(1)
"
check "the sandbox refuses a connection elsewhere (EPERM)" [ $? = 0 ]
if [ "$failed" != 0 ]; then echo "asc.swift against the stand-in: the sandbox does not hold; nothing run"; exit 1; fi

server_pid=""
start() { # scenario flags for standin.py
    rm -f "$work/port" "$work/log.jsonl" "$work/state.json"; touch "$work/log.jsonl"
    python3 -I "$here/standin.py" --port-file "$work/port" --log "$work/log.jsonl" --state "$work/state.json" \
        --pubkey "$keys/pub.pem" --kid "$KID" --iss "$ISS" "$@" &
    server_pid=$!
    for _ in $(seq 1 100); do [ -s "$work/port" ] && break; sleep 0.1; done
    port="$(cat "$work/port" 2>/dev/null)"
    [ -n "$port" ] || { echo "FAIL: the stand-in didn't start ($*)"; stop; exit 1; }
    base="http://127.0.0.1:$port"
}
stop() { [ -n "$server_pid" ] && { kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; }; server_pid=""; }
trap stop EXIT
run() { # name of the run, then asc's arguments; leaves out/err/status in work/<name>.*
    local name="$1"; shift
    sandbox-exec -p "$sandbox" "$asc" "$@" >"$work/$name.out" 2>"$work/$name.err"
    echo $? >"$work/$name.status"
}
status_is() { [ "$(cat "$work/$1.status")" = "$2" ] || { echo "  $1: exit $(cat "$work/$1.status"), wanted $2" >&2; sed 's/^/    /' "$work/$1.err" >&2; return 1; }; }
has() { grep -F -q -- "$2" "$work/$1.out" "$work/$1.err" || { echo "  $1: no '$2' in its output" >&2; return 1; }; }
hasnt() { ! grep -F -q -- "$2" "$work/$1.out" "$work/$1.err" || { echo "  $1: '$2' in its output" >&2; return 1; }; }
# log EXPR: EXPR over E, the requests the stand-in saw; S, what it holds now; HAND and WN, the texts.
log() { python3 -I - "$work/log.jsonl" "$work/state.json" "$1" <<'PY'
import json, sys
entries = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
held = json.load(open(sys.argv[2]))
expr = sys.argv[3]
HAND = "What to Test in 0.6.1 (1304): the Duo's laptop pose with the keyboard up, and the Pencil's lift.\nThank you!"
WN = 'Nightly 0.6.0 (983)\n\nChanges since 0.5.1:\n• Pinch to zoom (#196)'
ok = eval(expr, {'E': entries, 'S': held, 'HAND': HAND, 'WN': WN, 'len': len, 'any': any, 'all': all, 'set': set, 'sorted': sorted})
if not ok:
    print('  log check failed: ' + expr, file=sys.stderr)
    for e in entries:
        print('    %s %s %s %s' % (e['method'], e['path'], e['jwt_ok'], json.dumps(e['body'])[:120]), file=sys.stderr)
    print('    held: ' + json.dumps(held)[:400], file=sys.stderr)
sys.exit(0 if ok else 1)
PY
}
no_token_printed() { # the run's output never holds a token the stand-in saw
    python3 -I - "$work/log.jsonl" "$work/$1.out" "$work/$1.err" <<'PY'
import json, sys
tokens = {json.loads(l)['token'] for l in open(sys.argv[1]) if l.strip()}
text = open(sys.argv[2]).read() + open(sys.argv[3]).read()
bad = [t for t in tokens if t and (t in text or t.split('.')[2] in text)]
sys.exit(1 if bad else 0)
PY
}
common=(--key-file "$keys/AuthKey_TESTKEY123.p8" --key-id "$KID" --issuer "$ISS")
printf 'Nightly 0.6.0 (983)\n\nChanges since 0.5.1:\n• Pinch to zoom (#196)\n' >"$work/whats-new.txt"
fast=(--poll-seconds 0 --wait-minutes 0.3 --retry-seconds 0)
dist=(distribute "${common[@]}" --version 0.6.0 --build 983 --whats-new "$work/whats-new.txt")
# What a run sent to the build's localizations (none but the look when it kept the build's own).
writes="[(e['method'], e['path']) for e in E if 'betaBuildLocalizations' in e['path'] and e['method'] != 'GET']"

# 1. groups: every request carries a token the stand-in verifies; four groups listed.
start
run groups groups "${common[@]}" --api-base "$base"
check "groups exit 0" status_is groups 0
check "groups lists Insiders" has groups "internal 'Insiders'"
check "groups lists Team as automatic" has groups "internal 'Team' (automatic distribution: every build)"
check "groups lists the public link" has groups "external 'Public Beta' (public link)"
check "groups: every token verified" log "len(E) >= 2 and all(e['jwt_ok'] for e in E)"
check "groups: ES256 header with the kid" log "all(e['jwt_header'] == {'alg': 'ES256', 'kid': 'TESTKEY123', 'typ': 'JWT'} for e in E)"
check "groups: claims iss, aud, a 15-minute exp" log "all(e['jwt_claims']['iss'] == '$ISS' and e['jwt_claims']['aud'] == 'appstoreconnect-v1' and e['jwt_claims']['exp'] - e['jwt_claims']['iat'] == 900 for e in E)"
check "groups: only GETs" log "all(e['method'] == 'GET' for e in E)"
check "groups: the bundle ID filter, and the other app ignored" log "E[0]['path'] == '/v1/apps' and E[0]['query']['filter[bundleId]'] == 'me.saffer.sill' and any(e['path'] == '/v1/betaGroups' and e['query']['filter[app]'] == '6816359860' for e in E)"
check "groups: no token printed" no_token_printed groups
stop

# 2. build-state: missing before App Store Connect lists it, then PROCESSING, then VALID.
start --appear-after 1 --processing 1
run state1 build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983
run state2 build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983
run state3 build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983
check "build-state missing" [ "$(cat "$work/state1.out")" = missing ]
check "build-state PROCESSING" [ "$(cat "$work/state2.out")" = PROCESSING ]
check "build-state VALID" [ "$(cat "$work/state3.out")" = VALID ]
check "build-state filters version and build" log "all(e['query'].get('filter[version]') == '983' and e['query'].get('filter[preReleaseVersion.version]') == '0.6.0' for e in E if e['path'] == '/v1/builds')"
stop

# 3. distribute without the public beta: Insiders only; Team left to its automatic distribution;
#    no external group, no Beta App Review; What to Test made (the build had none).
start
run internal "${dist[@]}" --api-base "$base" "${fast[@]}"
check "internal exit 0" status_is internal 0
check "internal: waited through not listed and processing" has internal "is not listed yet"
check "internal: processed" has internal "is processed"
check "internal: Insiders given" has internal "Internal group 'Insiders': given build 983 of 0.6.0"
check "internal: Team left to automatic distribution" has internal "Internal group 'Team': gets every build by itself"
check "internal: public beta not given, says why" has internal "Public beta: not given to 'Public Beta': the repository variable SILL_NIGHTLY_PUBLIC_BETA is not true"
check "internal: summary" has internal "Assigned build 983 of 0.6.0 to: Insiders; by automatic distribution: Team."
check "internal: exactly one group POST, to Insiders" log "[e['path'] for e in E if e['method'] == 'POST' and e['path'].startswith('/v1/betaGroups/')] == ['/v1/betaGroups/g-insiders/relationships/builds']"
check "internal: the build in the body" log "[e['body'] for e in E if e['path'] == '/v1/betaGroups/g-insiders/relationships/builds'] == [{'data': [{'type': 'builds', 'id': 'b-983'}]}]"
check "internal: no external group touched" log "not any('g-public' in e['path'] or 'g-friends' in e['path'] for e in E)"
check "internal: no Beta App Review" log "not any(e['path'] == '/v1/betaAppReviewSubmissions' for e in E)"
check "internal: What to Test made in en-US" log "[e['body']['data']['attributes'] for e in E if e['path'] == '/v1/betaBuildLocalizations' and e['method'] == 'POST'] == [{'locale': 'en-US', 'whatsNew': WN}]"
check "internal: says it set What to Test" has internal "What to Test set (English (U.S.), 64 characters)"
check "internal: What to Test before the groups" log "[i for i, e in enumerate(E) if e['path'] == '/v1/betaBuildLocalizations'][0] < [i for i, e in enumerate(E) if e['path'].endswith('/relationships/builds')][0]"
check "internal: groups listed before the wait" log "[i for i, e in enumerate(E) if e['path'] == '/v1/betaGroups'][0] < [i for i, e in enumerate(E) if e['path'] == '/v1/builds'][0]"
check "internal: every token verified" log "all(e['jwt_ok'] for e in E)"
check "internal: no token printed" no_token_printed internal
stop

# 4. --public-beta without SILL_NIGHTLY_PUBLIC_BETA=true: refused before any request.
start
run refused "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "refused exit 2" status_is refused 2
check "refused says why" has refused "--public-beta is refused unless the environment also says SILL_NIGHTLY_PUBLIC_BETA=true"
check "refused: not one request" log "len(E) == 0"
SILL_NIGHTLY_PUBLIC_BETA=false run refused2 "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "refused with the variable false: exit 2" status_is refused2 2
SILL_NIGHTLY_PUBLIC_BETA=TRUE run refused3 "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "refused with TRUE (not true): exit 2" status_is refused3 2
check "refused, refused2, refused3: still not one request" log "len(E) == 0"
stop

# 5. With both: Insiders and the public beta group, then Beta App Review once; Friends untouched.
start
SILL_NIGHTLY_PUBLIC_BETA=true run public "${dist[@]}" --api-base "$base" --public-beta "${fast[@]}"
check "public exit 0" status_is public 0
check "public: Public Beta given" has public "Public beta group 'Public Beta' (public link): given build 983 of 0.6.0 (SILL_NIGHTLY_PUBLIC_BETA is true)"
check "public: submitted" has public "Submitted build 983 of 0.6.0 for Beta App Review"
check "public: summary" has public "Assigned build 983 of 0.6.0 to: Insiders, Public Beta; by automatic distribution: Team."
check "public: group POSTs Insiders then Public Beta" log "[e['path'] for e in E if e['method'] == 'POST' and e['path'].startswith('/v1/betaGroups/')] == ['/v1/betaGroups/g-insiders/relationships/builds', '/v1/betaGroups/g-public/relationships/builds']"
check "public: one submission, after the public group" log "[e['body'] for e in E if e['path'] == '/v1/betaAppReviewSubmissions'] == [{'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': {'data': {'type': 'builds', 'id': 'b-983'}}}}}] and [i for i, e in enumerate(E) if e['path'] == '/v1/betaAppReviewSubmissions'][0] > [i for i, e in enumerate(E) if e['path'] == '/v1/betaGroups/g-public/relationships/builds'][0]"
check "public: Friends untouched" log "not any('g-friends' in e['path'] for e in E)"
check "public: no token printed" no_token_printed public
stop

# 6. Two external groups with a public link: refused before the wait, nothing assigned.
start --scenario two-public
SILL_NIGHTLY_PUBLIC_BETA=true run twopublic "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "two public exit 1" status_is twopublic 1
check "two public says so" has twopublic "--public-beta: 2 external groups with the public link on"
check "two public: no build asked for, nothing posted" log "not any(e['path'] == '/v1/builds' or e['method'] != 'GET' for e in E)"
stop
start --scenario no-public
SILL_NIGHTLY_PUBLIC_BETA=true run nopublic "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "no public exit 1" status_is nopublic 1
check "no public says 0" has nopublic "--public-beta: 0 external groups with the public link on"
check "no public: nothing posted" log "not any(e['method'] != 'GET' for e in E)"
stop

# 7. A group named with --public-beta-group (external, without a public link) is the one given.
start
SILL_NIGHTLY_PUBLIC_BETA=true run named "${dist[@]}" --api-base "$base" --public-beta --public-beta-group Friends "${fast[@]}"
check "named exit 0" status_is named 0
check "named: Friends given, Public Beta not" log "[e['path'] for e in E if e['method'] == 'POST' and e['path'].startswith('/v1/betaGroups/')] == ['/v1/betaGroups/g-insiders/relationships/builds', '/v1/betaGroups/g-friends/relationships/builds']"
run named2 "${dist[@]}" --api-base "$base" --public-beta-group Friends
check "--public-beta-group without --public-beta: exit 2" status_is named2 2
stop

# 8. An en-US What to Test already there: changed (PATCH), not made again, with --replace-whats-new.
start --scenario existing-localization
run patch "${dist[@]}" --api-base "$base" --replace-whats-new --poll-seconds 0 --wait-minutes 0.3
check "patch exit 0" status_is patch 0
check "patch: PATCH l-1, no POST" log "$writes == [('PATCH', '/v1/betaBuildLocalizations/l-1')]"
check "patch: the text" log "[e['body']['data'] for e in E if e['method'] == 'PATCH'] == [{'type': 'betaBuildLocalizations', 'id': 'l-1', 'attributes': {'whatsNew': WN}}]"
check "patch: the build holds it" log "S['localizations'] == [{'id': 'l-1', 'locale': 'en-US', 'whatsNew': WN}]"
stop

# 9. A build App Store Connect could not process: exit 1, nothing given, no What to Test.
start --scenario invalid
run invalid "${dist[@]}" --api-base "$base" --poll-seconds 0 --wait-minutes 0.3
check "invalid exit 1" status_is invalid 1
check "invalid says so" has invalid "App Store Connect could not process build 983 of 0.6.0 (INVALID)"
check "invalid: nothing posted" log "not any(e['method'] != 'GET' for e in E)"
stop

# 10. A build that never shows: the wait runs out (0.05 min), exit 1.
start --scenario never
run never "${dist[@]}" --api-base "$base" --poll-seconds 1 --wait-minutes 0.05
check "never exit 1" status_is never 1
check "never says the wait ran out" has never "App Store Connect has not finished processing build 983 of 0.6.0 after 3 s"
check "never: polled about once a second" log "2 <= len([e for e in E if e['path'] == '/v1/builds']) <= 4"
check "never: nothing posted" log "not any(e['method'] != 'GET' for e in E)"
stop

# 11. A revoked key: 401 with the hint, no token printed.
start --scenario revoked
run revoked groups "${common[@]}" --api-base "$base" --retry-seconds 0
check "revoked exit 1" status_is revoked 1
check "revoked: App Store Connect's words and the hint" has revoked "App Store Connect answered HTTP 401: Authentication credentials are missing or invalid. Provide a properly configured and signed bearer token. [NOT_AUTHORIZED] The key, its Key ID or the Issuer ID is wrong, or the key was revoked"
check "revoked: no token printed" no_token_printed revoked
check "revoked: not retried" log "len(E) == 1"
stop

# 12. Another key than the one App Store Connect knows: the stand-in's signature check refuses it.
start
run wrongkey groups --key-file "$keys/AuthKey_OTHERKEY12.p8" --key-id "$KID" --issuer "$ISS" --api-base "$base" --retry-seconds 0
check "wrong key exit 1" status_is wrongkey 1
check "wrong key: the signature refused" log "len(E) == 1 and not E[0]['jwt_ok'] and E[0]['jwt_reason'].startswith('signature')"
check "wrong key: no token printed" no_token_printed wrongkey
stop

# 13. A 429 (Retry-After 0) and a 500: tried again, then fine.
start --scenario throttle --scenario flaky
run flaky "${dist[@]}" --api-base "$base" "${fast[@]}"
check "flaky exit 0" status_is flaky 0
check "flaky: said it tried again" has flaky "HTTP 429; trying again"
check "flaky: and after the 500" has flaky "HTTP 500; trying again"
check "flaky: /v1/apps asked twice" log "len([e for e in E if e['path'] == '/v1/apps']) == 2"
stop

# 14. Pages of one: every group and the app still found; a next link elsewhere is never followed.
start --page-size 1
run pages "${dist[@]}" --api-base "$base" --poll-seconds 0 --wait-minutes 0.3
check "pages exit 0" status_is pages 0
check "pages: four groups over four pages" log "len([e for e in E if e['path'] == '/v1/betaGroups']) == 4"
check "pages: the app on the second page" log "len([e for e in E if e['path'] == '/v1/apps']) == 2"
check "pages: Insiders given" has pages "Internal group 'Insiders': given build 983"
stop
start --page-size 1 --scenario bad-next
run badnext groups "${common[@]}" --api-base "$base"
check "bad next exit 1" status_is badnext 1
check "bad next says so" has badnext "next page is not on 127.0.0.1; not following it with the token"
check "bad next: one request only" log "len(E) == 1"
stop

# 15. Another build of the version in review: a warning, the build stays with the group, exit 0.
start --scenario review-conflict
SILL_NIGHTLY_PUBLIC_BETA=true GITHUB_ACTIONS=true run conflict "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "conflict exit 0" status_is conflict 0
check "conflict: a warning annotation" has conflict "::warning::Beta App Review submission: App Store Connect answered HTTP 409"
stop
start --scenario already-approved
SILL_NIGHTLY_PUBLIC_BETA=true run approved "${dist[@]}" --api-base "$base" --public-beta --poll-seconds 0 --wait-minutes 0.3
check "approved exit 0" status_is approved 0
check "approved: nothing submitted" log "not any(e['path'] == '/v1/betaAppReviewSubmissions' for e in E)"
check "approved: says so" has approved "Beta App Review: nothing to submit; the build is BETA_APPROVED"
stop

# 16. Usage: another API host, a bad key file, an SEC1 key, malformed IDs, version and build.
start
run evil groups "${common[@]}" --api-base https://evil.example
check "another host exit 2" status_is evil 2
run evil2 groups "${common[@]}" --api-base http://api.appstoreconnect.apple.com
check "plain http to Apple's host exit 2" status_is evil2 2
run evil3 groups "${common[@]}" --api-base https://api.appstoreconnect.apple.com.evil.example
check "a lookalike host exit 2" status_is evil3 2
run evil4 groups "${common[@]}" --api-base "http://user:pw@127.0.0.1:$port"
check "credentials in the base exit 2" status_is evil4 2
printf 'not a key\n' >"$work/notakey.p8"
run notakey groups --key-file "$work/notakey.p8" --key-id "$KID" --issuer "$ISS" --api-base "$base"
check "not a key exit 2" status_is notakey 2
run sec1 groups --key-file "$keys/ec.pem" --key-id "$KID" --issuer "$ISS" --api-base "$base"
check "an SEC1 file exit 2" status_is sec1 2
run badkid groups --key-file "$keys/AuthKey_TESTKEY123.p8" --key-id 'ABC"}' --issuer "$ISS" --api-base "$base"
check "a malformed Key ID exit 2" status_is badkid 2
run badiss groups --key-file "$keys/AuthKey_TESTKEY123.p8" --key-id "$KID" --issuer 'x' --api-base "$base"
check "a malformed Issuer ID exit 2" status_is badiss 2
run badver build-state "${common[@]}" --api-base "$base" --version 'latest' --build 983
check "a malformed version exit 2" status_is badver 2
run badbuild build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build '983;rm'
check "a malformed build exit 2" status_is badbuild 2
run nowhatsnew distribute "${common[@]}" --api-base "$base" --version 0.6.0 --build 983
check "distribute without --whats-new exit 2" status_is nowhatsnew 2
: >"$work/empty.txt"
run emptywhatsnew distribute "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --whats-new "$work/empty.txt"
check "an empty What to Test exit 2" status_is emptywhatsnew 2
run unknown groups "${common[@]}" --api-base "$base" --frobnicate
check "an unknown option exit 2" status_is unknown 2
check "usage errors: not one request" log "len(E) == 0"
stop

# 17. A What to Test over 4,000 characters: cut at a line, with the link, and a warning.
python3 -I -c "
import sys
lines = ['Nightly 0.6.0 (983)'] + ['• A change with a long title that goes on and on, number %d (#%d)' % (i, 100 + i) for i in range(120)]
open(sys.argv[1], 'w').write('\n'.join(lines))
" "$work/long.txt"
start
run long whats-new "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --whats-new "$work/long.txt" --poll-seconds 0 --wait-minutes 0.3
check "long exit 0" status_is long 0
check "long: a warning" has long "What to Test was"
check "long: what was sent fits and ends with the link" log "[len(e['body']['data']['attributes']['whatsNew'].encode('utf-16-le')) // 2 <= 4000 and e['body']['data']['attributes']['whatsNew'].endswith('… and more: https://github.com/Saffsanity/sill/releases/tag/nightly') for e in E if e['path'] == '/v1/betaBuildLocalizations' and e['method'] == 'POST'] == [True]"
stop

# 18. Export compliance missing: exit 1, nothing given.
start --scenario compliance
run compliance "${dist[@]}" --api-base "$base" --poll-seconds 0 --wait-minutes 0.3
check "compliance exit 1" status_is compliance 1
check "compliance says so" has compliance "TestFlight holds build 983 of 0.6.0 for export compliance"
check "compliance: nothing posted" log "not any(e['method'] != 'GET' for e in E)"
stop

# 19. No internal group at all: a warning, and still no external group without the public beta.
start --scenario no-internal
run nointernal "${dist[@]}" --api-base "$base" --poll-seconds 0 --wait-minutes 0.3
check "no internal exit 0" status_is nointernal 0
check "no internal: warned" has nointernal "The app has no internal TestFlight group"
check "no internal: no group posted" log "not any(e['path'].endswith('/relationships/builds') for e in E)"
stop

# 20. No app with that bundle ID.
start --scenario no-app
run noapp groups "${common[@]}" --api-base "$base"
check "no app exit 1" status_is noapp 1
check "no app says so" has noapp "App Store Connect lists no app with the bundle ID me.saffer.sill"
stop

# 21. A redirect: not followed (the token would go with it), exit 1.
start --scenario redirect
run redirect groups "${common[@]}" --api-base "$base" --retry-seconds 0
check "redirect exit 1" status_is redirect 1
check "redirect says so" has redirect "App Store Connect answered HTTP 302"
check "redirect: not followed" log "len(E) == 1 and E[0]['path'] == '/v1/apps'"
stop

# 22. The review of 2026-10-29: the environment true without --public-beta gives internal groups only;
#     an internal group named as the public beta is refused; build-state prints INVALID; a refused key
#     stops build-state with nothing on stdout.
start
SILL_NIGHTLY_PUBLIC_BETA=true run envonly "${dist[@]}" --api-base "$base" "${fast[@]}"
check "envonly exit 0" status_is envonly 0
check "envonly: Insiders only" log "[e['path'] for e in E if e['method'] == 'POST' and e['path'].startswith('/v1/betaGroups/')] == ['/v1/betaGroups/g-insiders/relationships/builds']"
check "envonly: no external group, no review" log "not any('g-public' in e['path'] or 'g-friends' in e['path'] or e['path'] == '/v1/betaAppReviewSubmissions' for e in E)"
check "envonly: says the public beta was not given" has envonly "Public beta: not given"
stop
start
SILL_NIGHTLY_PUBLIC_BETA=true run internalnamed "${dist[@]}" --api-base "$base" --public-beta --public-beta-group Insiders --poll-seconds 0 --wait-minutes 0.3
check "an internal group named as the public beta: exit 1" status_is internalnamed 1
check "internalnamed: nothing posted" log "not any(e['method'] != 'GET' for e in E)"
stop
start --scenario invalid --appear-after 0 --processing 0
run stateinvalid build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983
check "build-state of an INVALID build prints INVALID" [ "$(cat "$work/stateinvalid.out")" = INVALID ]
stop
start --scenario revoked
run staterevoked build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --retry-seconds 0
check "build-state with a refused key: exit 1" status_is staterevoked 1
check "build-state with a refused key: nothing on stdout" [ ! -s "$work/staterevoked.out" ]
stop

# What to Test (2026-11-09): build 1304 was uploaded by hand with What to Test of its own; that night's
# nightly found it in App Store Connect, left the upload as designed, and its distribute step replaced
# the text with the night's notes. distribute now keeps a build's What to Test unless
# --replace-whats-new, which the nightly passes only for a build its own run uploaded.

# 23. The night of 2026-11-09 again: the build's own text kept, nothing written, the groups given.
start --scenario hand-text
run kept "${dist[@]}" --api-base "$base" "${fast[@]}"
check "kept exit 0" status_is kept 0
check "kept: says so" has kept "What to Test left as it is: the build has its own already (English (U.S.), 107 characters); distribute replaces it only with --replace-whats-new"
check "kept: never says it set it" hasnt kept "What to Test set"
check "kept: looked once, wrote nothing" log "$writes == [] and len([e for e in E if e['path'] == '/v1/builds/b-983/betaBuildLocalizations']) == 1"
check "kept: looked only once the build was processed" log "[i for i, e in enumerate(E) if 'betaBuildLocalizations' in e['path']][0] > [i for i, e in enumerate(E) if e['path'].endswith('/buildBetaDetail')][-1]"
check "kept: the build still holds its own" log "S['localizations'] == [{'id': 'l-1', 'locale': 'en-US', 'whatsNew': HAND}]"
check "kept: Insiders still given" log "S['members']['g-insiders'] == ['b-983']"
check "kept: summary" has kept "Assigned build 983 of 0.6.0 to: Insiders; by automatic distribution: Team."
stop

# 24. A build the nightly's own run uploaded (--replace-whats-new): replaced as before.
start --scenario hand-text
run replaced "${dist[@]}" --api-base "$base" --replace-whats-new "${fast[@]}"
check "replaced exit 0" status_is replaced 0
check "replaced: PATCH l-1 only" log "$writes == [('PATCH', '/v1/betaBuildLocalizations/l-1')]"
check "replaced: the night's text" log "S['localizations'] == [{'id': 'l-1', 'locale': 'en-US', 'whatsNew': WN}]"
check "replaced: says so" has replaced "What to Test set (English (U.S.), 64 characters)"
stop

# 25. A build with none: made, with or without --replace-whats-new, the same request.
for flag in "" --replace-whats-new; do
    start
    run "fresh$flag" "${dist[@]}" --api-base "$base" $flag "${fast[@]}"
    check "fresh ($flag) exit 0" status_is "fresh$flag" 0
    check "fresh ($flag): one POST, en-US, the file's text" log "$writes == [('POST', '/v1/betaBuildLocalizations')] and [e['body'] for e in E if e['method'] == 'POST' and e['path'] == '/v1/betaBuildLocalizations'] == [{'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US', 'whatsNew': WN}, 'relationships': {'build': {'data': {'type': 'builds', 'id': 'b-983'}}}}}]"
    check "fresh ($flag): says so" has "fresh$flag" "What to Test set (English (U.S.), 64 characters)"
    stop
done

# 26. An en-US localization with no text (empty, null, white space only) counts as none: filled in.
for scenario in empty-localization null-localization blank-localization; do
    start --scenario "$scenario"
    run "$scenario" "${dist[@]}" --api-base "$base" "${fast[@]}"
    check "$scenario exit 0" status_is "$scenario" 0
    check "$scenario: PATCH l-1 with the file's text" log "$writes == [('PATCH', '/v1/betaBuildLocalizations/l-1')] and S['localizations'] == [{'id': 'l-1', 'locale': 'en-US', 'whatsNew': WN}]"
    stop
done

# 27. Text in another language only counts too: kept; with --replace-whats-new, en-US made beside it.
start --scenario other-locale
run otherkept "${dist[@]}" --api-base "$base" "${fast[@]}"
check "other language exit 0" status_is otherkept 0
check "other language: kept, named" has otherkept "What to Test left as it is: the build has its own already (en-GB, 19 characters)"
check "other language: nothing written" log "$writes == [] and S['localizations'] == [{'id': 'l-2', 'locale': 'en-GB', 'whatsNew': 'Colour and the Duo.'}]"
stop
start --scenario other-locale
run otherreplaced "${dist[@]}" --api-base "$base" --replace-whats-new "${fast[@]}"
check "other language, replacing: en-US made, en-GB as it was" log "$writes == [('POST', '/v1/betaBuildLocalizations')] and S['localizations'] == [{'id': 'l-2', 'locale': 'en-GB', 'whatsNew': 'Colour and the Duo.'}, {'id': 'l-new', 'locale': 'en-US', 'whatsNew': WN}]"
stop
start --scenario other-locale --scenario hand-text
run bothkept "${dist[@]}" --api-base "$base" "${fast[@]}"
check "both languages: English (U.S.) named first" has bothkept "What to Test left as it is: the build has its own already (English (U.S.), 107 characters)"
check "both languages: nothing written" log "$writes == []"
stop
start --scenario other-locale --scenario empty-localization
run otherempty "${dist[@]}" --api-base "$base" "${fast[@]}"
check "en-GB's text and an empty en-US: kept, nothing written" log "$writes == []"
check "en-GB's text and an empty en-US: en-GB named" has otherempty "(en-GB, 19 characters)"
stop

# 28. whats-new always replaces: how a build's text is set, or put back, by hand (build 1304's was).
start --scenario hand-text
run restore whats-new "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --whats-new "$work/whats-new.txt" "${fast[@]}"
check "whats-new exit 0" status_is restore 0
check "whats-new: PATCH l-1 with the file's text" log "$writes == [('PATCH', '/v1/betaBuildLocalizations/l-1')] and S['localizations'] == [{'id': 'l-1', 'locale': 'en-US', 'whatsNew': WN}]"
check "whats-new: no group touched" log "not any(e['path'].endswith('/relationships/builds') for e in E)"
stop

# 29. --replace-whats-new goes with distribute alone, and takes no value: refused before any request.
start
run replacewn whats-new "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --whats-new "$work/whats-new.txt" --replace-whats-new
check "--replace-whats-new with whats-new: exit 2" status_is replacewn 2
check "--replace-whats-new with whats-new: says why" has replacewn "--replace-whats-new goes with distribute"
run replacegroups groups "${common[@]}" --api-base "$base" --replace-whats-new
check "--replace-whats-new with groups: exit 2" status_is replacegroups 2
run replacestate build-state "${common[@]}" --api-base "$base" --version 0.6.0 --build 983 --replace-whats-new
check "--replace-whats-new with build-state: exit 2" status_is replacestate 2
run replacevalue "${dist[@]}" --api-base "$base" --replace-whats-new=yes
check "--replace-whats-new=yes: exit 2" status_is replacevalue 2
check "--replace-whats-new refused: not one request" log "len(E) == 0"
stop

echo "asc.swift against the stand-in: $pass passed, $failed failed"
[ "$failed" = 0 ]
