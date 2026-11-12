#!/bin/bash
# G6 (docs/one-click-update-plan.md §11): Scripts/sign-update.sh against a stand-in `gh` (this file writes it
# into .build) serving the genuine v0.6.1 from .build/updater-scratch/release-v0.6.1, with a throwaway key in
# a file and the signer installed in a scratch folder (SILL_SIGNER_DIR). Nothing is uploaded anywhere: the
# stand-in records what would have gone. Never the login keychain (every step passes --key-file), so the
# signer's in-person prompt is never shown.
# Review 3: the installed signer has the hardened runtime and no library loads into it (F1); a release is
# signed only when the trust its tag's Sill carries (its keys, the pinned requirement, Trust.release,
# Endpoints.github) is the trust recorded when the signer was installed, read here from a scratch git
# repository whose tag says each (F2); the key's backup words (F3).
# The second pass: the app must name the commit of the tag (SillCommit; the genuine v0.6.1 predates it, so the
# test stands in for it with SILL_SIGN_TEST_BUILT_FROM) and GitHub's tag must name it too (R1); the updater's
# changes since the last release signed are shown (R2); the signing record and --audit (A1).
#   Tests/update-harness/sign-test.sh [--keep]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/update-sign-test"
keep=0; [ "${1:-}" = "--keep" ] && keep=1
genuine="$root/.build/updater-scratch/release-v0.6.1"
[ -f "$genuine/Sill.zip" ] || { echo "sign-test: no genuine v0.6.1 zip in $genuine; nothing to test" >&2; exit 0; }
rm -rf "$out"; mkdir -p "$out"/{bin,assets,signer,other}
trap '[ "$keep" = 1 ] || rm -rf "$out"' EXIT
cp "$genuine/Sill.zip" "$genuine/Sill.zip.sha256" "$out/assets/"
cat > "$out/bin/gh" <<'GH'
#!/bin/bash
# The stand-in: `api repos/R/releases/tags/T`, `api [--paginate] repos/R/releases…` (v0.6.1, of $GH_STANDIN_ASSETS,
# and, with GH_STANDIN_EXTRA=published|prerelease|draft, a v0.7.0 carrying $GH_STANDIN_EXTRA_MANIFEST alone),
# `api -H 'Accept: application/octet-stream' repos/R/releases/assets/ID` (an asset's bytes), `api
# repos/R/git/ref/tags/T` (the tag in the scratch checkout $GH_STANDIN_REPO, or $GH_STANDIN_TAG_SHA; annotated
# with GH_STANDIN_TAG_ANNOTATED=1) and `api repos/R/git/tags/SHA`, `api repos/R/actions/runs/ID` (a run of
# $GH_STANDIN_RUN_PATH, $GH_STANDIN_RUN_CONCLUSION, $GH_STANDIN_RUN_BRANCH, $GH_STANDIN_RUN_SHA; the release
# workflow's, successful, for v0.6.1 and its commit by default), `run download ID --repo R --name N --dir D`
# ($GH_STANDIN_ARTIFACT as Sill-0.6.1.zip in the artifact sill-zip-v0.6.1), `release download T --repo R --pattern
# P... --dir D`, `release upload T FILE --repo R [--clobber]`; GH_STANDIN_FAIL=1 answers every call as an expired
# login does. Every call logged.
set -euo pipefail
echo "gh $*" >> "$GH_STANDIN_LOG"
assets="$GH_STANDIN_ASSETS"
[ "${GH_STANDIN_FAIL:-0}" = 1 ] && { echo "HTTP 401: Bad credentials (https://api.github.com/)" >&2; exit 1; }
if [ "$1" = api ]; then
    path=""; skip=0
    for a in "${@:2}"; do
        if [ "$skip" = 1 ]; then skip=0; continue; fi
        case "$a" in -H|--jq) skip=1 ;; -*) ;; *) path="$a" ;; esac
    done
    sha="${GH_STANDIN_TAG_SHA:-$(git -C "$GH_STANDIN_REPO" rev-parse "v0.6.1^{commit}")}"
    tagsha="$(git -C "$GH_STANDIN_REPO" rev-parse "v0.6.1^{commit}")"
    python3 -I - "$assets" "$path" "$sha" "${GH_STANDIN_TAG_ANNOTATED:-0}" "${GH_STANDIN_EXTRA:-}" "${GH_STANDIN_EXTRA_MANIFEST:-}" \
        "${GH_STANDIN_RUN_PATH:-.github/workflows/release.yml}" "${GH_STANDIN_RUN_CONCLUSION:-success}" "${GH_STANDIN_RUN_BRANCH:-v0.6.1}" \
        "${GH_STANDIN_RUN_SHA:-$tagsha}" <<'PY'
import hashlib, json, os, sys
assets, path, sha, annotated, extra, extra_manifest, run_path, conclusion, run_branch, run_sha = sys.argv[1:11]
if "/git/ref/tags/" in path:
    kind, target = ("tag", "a" * 40) if annotated == "1" else ("commit", sha)
    print(json.dumps({"ref": "refs/tags/" + path.rsplit("/", 1)[-1], "object": {"type": kind, "sha": target}}))
    sys.exit(0)
if "/git/tags/" in path:
    print(json.dumps({"object": {"type": "commit", "sha": sha}}))
    sys.exit(0)
if "/actions/runs/" in path:
    print(json.dumps({"id": int(path.rsplit("/", 1)[-1]), "path": run_path, "status": "completed", "conclusion": conclusion,
                      "head_branch": run_branch, "head_sha": run_sha}))
    sys.exit(0)
def release(tag, files, start, draft=False, prerelease=False):
    items = []
    for i, (name, file) in enumerate(files):
        data = open(file, "rb").read()
        items.append({"id": start + i, "name": name, "size": len(data), "state": "uploaded", "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                      "browser_download_url": "https://github.com/Saffsanity/sill/releases/download/%s/%s" % (tag, name)})
    return {"tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": items}
main = release("v0.6.1", [(n, os.path.join(assets, n)) for n in sorted(os.listdir(assets))], 100)
listing = [main]
if extra in ("published", "prerelease", "draft"):
    listing.append(release("v0.7.0", [("Sill.zip.manifest", extra_manifest)], 900, extra == "draft", extra == "prerelease"))
if "/releases/assets/" in path:
    wanted = int(path.rsplit("/", 1)[-1])
    for r in listing:
        for a, file in zip(r["assets"], [os.path.join(assets, n) for n in sorted(os.listdir(assets))] if r is main else [extra_manifest]):
            if a["id"] == wanted:
                sys.stdout.buffer.write(open(file, "rb").read())
                sys.exit(0)
    print("HTTP 404: Not Found", file=sys.stderr)
    sys.exit(1)
if "/releases/tags/" in path:
    print(json.dumps(main))
else:
    print(json.dumps(listing))
PY
    exit $?
fi
if [ "$1 $2" = "run download" ]; then
    shift 3
    name=""; dir="."
    while [ $# -gt 0 ]; do
        case "$1" in --name) name="$2"; shift ;; --dir) dir="$2"; shift ;; --repo) shift ;; esac
        shift
    done
    [ "$name" = sill-zip-v0.6.1 ] && [ -n "${GH_STANDIN_ARTIFACT:-}" ] && [ -f "$GH_STANDIN_ARTIFACT" ] || { echo "no artifact $name" >&2; exit 1; }
    mkdir -p "$dir"; cp "$GH_STANDIN_ARTIFACT" "$dir/Sill-0.6.1.zip"
    exit 0
fi
if [ "$1 $2" = "release download" ]; then
    shift 3
    patterns=(); dir="."
    while [ $# -gt 0 ]; do
        case "$1" in --pattern) patterns+=("$2"); shift ;; --dir) dir="$2"; shift ;; --repo) shift ;; esac
        shift
    done
    for p in "${patterns[@]}"; do cp "$assets/$p" "$dir/"; done
    exit 0
fi
if [ "$1 $2" = "release upload" ]; then
    cp "$4" "$assets/"
    echo "uploaded $(basename "$4")" >> "$GH_STANDIN_LOG"
    exit 0
fi
echo "stand-in gh: not taught $*" >&2; exit 2
GH
chmod +x "$out/bin/gh"
cat > "$out/bin/osascript" <<'OSA'
#!/bin/bash
echo "osascript $*" >> "$GH_STANDIN_LOG"
OSA
chmod +x "$out/bin/osascript"
export PATH="$out/bin:$PATH" GH_STANDIN_ASSETS="$out/assets" GH_STANDIN_LOG="$out/gh.log" SILL_SIGNER_DIR="$out/signer" GH_STANDIN_REPO="$out/scratch"
sign="$root/Scripts/sign-update.sh"
failures=0
expect() {  # expect ok|fail "what" command...
    local want=$1 what=$2; shift 2
    if "$@" > "$out/last.log" 2>&1; then got=ok; else got=fail; fi
    if [ "$got" = "$want" ]; then echo "  ok: $what"; else echo "  FAIL: $what (expected $want)"; sed 's/^/    /' "$out/last.log"; failures=$((failures + 1)); fi
}
echo "== sign-test"
zero="$(printf '0%.0s' {1..64})"
expect fail "no signer installed yet" "$sign" --public-key --key-file "$out/key"
expect ok "the signer installed (from this checkout, in the scratch folder)" "$sign" --install-signer --yes
grep -q "Compatibility.swift" "$out/last.log" && grep -q "UpdateManifest.swift" "$out/last.log" && grep -q "update-manifest.swift" "$out/last.log" \
    && ! grep -q "UpdateInstallPolicy.swift\|UpdateArchive.swift" "$out/last.log" \
    || { echo "  FAIL: the signer is built from three files (Compatibility, UpdateManifest, its main): $(grep '  [0-9a-f]\{64\}' "$out/last.log" | tr '\n' ' ')"; failures=$((failures + 1)); }
# F1: the hardened runtime, and a library given to it through DYLD_INSERT_LIBRARIES never loads.
grep -q 'flags=.*runtime' <<< "$(codesign -dv "$out/signer/update-manifest" 2>&1 || true)" && echo "  ok: the installed signer has the hardened runtime" \
    || { echo "  FAIL: the installed signer has no hardened runtime"; failures=$((failures + 1)); }
cat > "$out/mark.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void mark(void) {
    const char *p = getenv("MARK_FILE");
    if (p) { FILE *f = fopen(p, "w"); if (f) { fputs("loaded\n", f); fclose(f); } }
}
C
clang -dynamiclib "$out/mark.c" -o "$out/mark.dylib"
MARK_FILE="$out/marker" DYLD_INSERT_LIBRARIES="$out/mark.dylib" "$out/signer/update-manifest" verify /dev/null --key x > /dev/null 2>&1 || true
[ ! -f "$out/marker" ] && echo "  ok: a library given through DYLD_INSERT_LIBRARIES does not load into the signer" \
    || { echo "  FAIL: a library loaded into the installed signer"; failures=$((failures + 1)); }
expect fail "the scratch signer folder without a key file (never the keychain)" "$sign" --public-key
expect ok "a throwaway key in a file" "$sign" --new-key --key-file "$out/newkey"
grep -q '^public key [A-Za-z0-9+/=]* (key ID [0-9a-f]*)' "$out/last.log" || { echo "  FAIL: no public key printed"; failures=$((failures + 1)); }
expect fail "a second key never overwrites the first" "$sign" --new-key --key-file "$out/newkey"
# The tests' key (UpdateManifest.testKeySeed: anyone can make it, no Sill trusts it): the only key the test-only
# SILL_SIGN_TEST_BUILT_FROM goes with (the third security pass's N10 m).
expect ok "the tests' key in a file" "$out/signer/update-manifest" test-key --key-file "$out/key"
pub="$(sed -n 's/^public key \([A-Za-z0-9+\/=]*\) .*/\1/p' "$out/last.log")"
[ -n "$pub" ] || { echo "  FAIL: no public key printed for the tests' key"; failures=$((failures + 1)); }
other="$(python3 -I -c 'import base64,os; print(base64.b64encode(os.urandom(32)).decode())')"

# A scratch checkout whose tag v0.6.1 carries the trust under test (the genuine v0.6.1 zip stands for its build).
scratch="$out/scratch"
mkdir -p "$scratch/Sources/StreamProtocol" "$scratch/Sources/SillMenuBar" "$scratch/Scripts"
cp "$root/Sources/StreamProtocol/Compatibility.swift" "$scratch/Sources/StreamProtocol/"
cp "$root/Sources/SillMenuBar/UpdateManifest.swift" "$root/Sources/SillMenuBar/UpdateInstallPolicy.swift" "$scratch/Sources/SillMenuBar/"
cp "$root/Scripts/update-manifest.swift" "$root/Scripts/sign-update.sh" "$scratch/Scripts/"
git -C "$scratch" init -q
git -C "$scratch" -c user.name=t -c user.email=t@t add -A
git -C "$scratch" -c user.name=t -c user.email=t@t commit -q -m "no key"
keys_line() {  # keys_line KEY…: the releaseKeys line with those keys
    local list=""; for k in "$@"; do list="$list${list:+, }\"$k\""; done
    python3 -I - "$scratch/Sources/SillMenuBar/UpdateManifest.swift" "$list" <<'PY'
import re, sys
p, keys = sys.argv[1], sys.argv[2]
s = open(p).read()
s, n = re.subn(r"static let releaseKeys: \[String\] = \[.*\]", "static let releaseKeys: [String] = [" + keys + "]", s)
assert n == 1
open(p, "w").write(s)
PY
}
retag() {  # retag MESSAGE: commit the scratch checkout and move v0.6.1 to it
    git -C "$scratch" -c user.name=t -c user.email=t@t commit -q -am "$1"
    git -C "$scratch" tag -f v0.6.1 > /dev/null
}
keys_line "$pub"; retag "the key"
src=(--source "$scratch" --key-file "$out/key" --zip "$genuine/Sill.zip" --yes)
# The commit the app names (R1): the genuine v0.6.1 has no SillCommit, so the test stands for one, the tag's by
# default (BUILT_FROM for another).
signs() { SILL_SIGN_TEST_BUILT_FROM="${BUILT_FROM:-$(git -C "$scratch" rev-parse "v0.6.1^{commit}")}" "$sign" "$@"; }
# The question about the updater's changes (R2) is asked whatever --yes says: answered yes, or not at all.
with_y() { printf 'y\n' | "$@"; }
no_answer() { "$@" < /dev/null; }
notifications() { grep -c '^osascript -e display notification' "$out/gh.log" || true; }
expect fail "F2: the key added after the signer was installed (its trust was recorded with none)" signs v0.6.1 "${src[@]}"
grep -q "trusts something other than what you read" "$out/last.log" || { echo "  FAIL: the refusal's words"; cat "$out/last.log"; failures=$((failures + 1)); }
expect ok "the signer installed again from the checkout that carries the key" "$sign" --install-signer --source "$scratch" --yes
grep -q "$pub" "$out/signer/trust.txt" || { echo "  FAIL: the recorded trust lacks the key"; failures=$((failures + 1)); }
expect fail "a zip that isn't GitHub's" signs v0.6.1 --source "$scratch" --key-file "$out/key" --zip "$genuine/Sill.zip.sha256" --yes
expect fail "N10 m: SILL_SIGN_TEST_BUILT_FROM with a key that isn't the tests'" signs v0.6.1 --source "$scratch" --key-file "$out/newkey" --zip "$genuine/Sill.zip" --yes
grep -q "taken only with the tests' key" "$out/last.log" || { echo "  FAIL: N10 m's words"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "no zip known (none built here for 0.6.1)" signs v0.6.1 --source "$scratch" --key-file "$out/key" --yes
# R1: the app built from another commit, an app naming none, and GitHub's tag moved, each refused before signing.
BUILT_FROM="$(git -C "$scratch" rev-parse "v0.6.1^{commit}~1")" expect fail "R1: the app built from another commit than the tag's" signs v0.6.1 "${src[@]}"
grep -q "the app was built from .*, not from v0.6.1's" "$out/last.log" || { echo "  FAIL: R1's words"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "R1: an app that names no commit (the genuine v0.6.1 as it is)" "$sign" v0.6.1 "${src[@]}"
grep -q "no SillCommit in its Info.plist" "$out/last.log" || { echo "  FAIL: R1's words for no commit"; cat "$out/last.log"; failures=$((failures + 1)); }
GH_STANDIN_TAG_SHA="$(git -C "$scratch" rev-parse "v0.6.1^{commit}~1")" expect fail "R1: GitHub's tag moved to another commit" signs v0.6.1 "${src[@]}"
grep -q "names .*, not your v0.6.1's" "$out/last.log" || { echo "  FAIL: R1's words for a moved tag"; cat "$out/last.log"; failures=$((failures + 1)); }
[ ! -s "$out/signer/signed.txt" ] && echo "  ok: nothing in the signing record after the refusals" \
    || { echo "  FAIL: the record has lines after refusals"; failures=$((failures + 1)); }
expect ok "the release signed, uploaded and read back" signs v0.6.1 "${src[@]}"
grep -q " v0.6.1 $(shasum -a 256 "$out/assets/Sill.zip.manifest" | cut -d' ' -f1) $(shasum -a 256 "$genuine/Sill.zip" | cut -d' ' -f1)\$" "$out/signer/signed.txt" \
    && echo "  ok: the signing record names the tag, the manifest's SHA-256 and the zip's" || { echo "  FAIL: the signing record"; cat "$out/signer/signed.txt"; failures=$((failures + 1)); }
GH_STANDIN_TAG_ANNOTATED=1 expect ok "R1: an annotated tag on GitHub, read through to its commit" signs v0.6.1 "${src[@]}" --replace
grep -q "SHA-256 $(shasum -a 256 "$genuine/Sill.zip" | cut -d' ' -f1 | sed -E 's/(.{8})/\1 /g; s/ $//')" "$out/last.log" \
    || { echo "  FAIL: the whole SHA-256, grouped, before signing"; failures=$((failures + 1)); }
[ -f "$out/assets/Sill.zip.manifest" ] || { echo "  FAIL: nothing uploaded"; failures=$((failures + 1)); }
expect ok "the uploaded manifest verifies with the key" "$out/signer/update-manifest" verify "$out/assets/Sill.zip.manifest" --key "$pub"
grep -q "tag v0.6.1, version 0.6.1, build 1388, Sill.zip 5920002 bytes" "$out/last.log" || { echo "  FAIL: the manifest's fields"; cat "$out/last.log"; failures=$((failures + 1)); }
grep -q "cdhash arm64 d5feca97b4d531345aefab17bb8b588358f2975f" "$out/last.log" || { echo "  FAIL: the arm64 cdhash"; failures=$((failures + 1)); }
expect fail "another key does not verify it" "$out/signer/update-manifest" verify "$out/assets/Sill.zip.manifest" --key "$other"
expect fail "signed already, without --replace" signs v0.6.1 "${src[@]}"
expect ok "signed again with --replace" signs v0.6.1 "${src[@]}" --replace
# R1′: a release the release workflow built, signed from the approved run: GitHub's record of the commit it built
# must be the tag's, and the zip is its artifact.
run=(--source "$scratch" --key-file "$out/key" --run 4242 --yes --replace)
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" expect ok "R1′: signed from the approved run's artifact" signs v0.6.1 "${run[@]}"
grep -q "it built $(git -C "$scratch" rev-parse "v0.6.1^{commit}"), your v0.6.1's commit" "$out/last.log" \
    || { echo "  FAIL: R1′'s words for the run"; cat "$out/last.log"; failures=$((failures + 1)); }
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" GH_STANDIN_RUN_SHA="$(git -C "$scratch" rev-parse "v0.6.1^{commit}~1")" \
    expect fail "R1′: a run that built another commit (a tag moved for the run and back)" signs v0.6.1 "${run[@]}"
grep -q "built .*, not your v0.6.1's .*: nothing signed (a tag moved for the run and back" "$out/last.log" \
    || { echo "  FAIL: R1′'s words for another commit"; cat "$out/last.log"; failures=$((failures + 1)); }
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" GH_STANDIN_RUN_CONCLUSION=failure expect fail "R1′: a run that didn't succeed" signs v0.6.1 "${run[@]}"
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" GH_STANDIN_RUN_PATH=.github/workflows/nightly.yml expect fail "R1′: another workflow's run" signs v0.6.1 "${run[@]}"
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" GH_STANDIN_RUN_BRANCH=v0.6.0 expect fail "R1′: a run started for another tag" signs v0.6.1 "${run[@]}"
GH_STANDIN_ARTIFACT="" expect fail "R1′: a run without the zip's artifact" signs v0.6.1 "${run[@]}"
GH_STANDIN_ARTIFACT="$genuine/Sill.zip.sha256" expect fail "R1′: an artifact that isn't GitHub's zip" signs v0.6.1 "${run[@]}"
GH_STANDIN_ARTIFACT="$genuine/Sill.zip" expect fail "R1′: --run takes no --zip" signs v0.6.1 "${run[@]}" --zip "$genuine/Sill.zip"
# A1: the audit, every manifest on GitHub against the signing record.
expect ok "the audit: the release on GitHub is in the record" "$sign" --audit
grep -q "v0.6.1 (published): signed here" "$out/last.log" || { echo "  FAIL: the audit's words"; cat "$out/last.log"; failures=$((failures + 1)); }
cp "$out/assets/Sill.zip.manifest" "$out/recorded.manifest"
"$out/signer/update-manifest" sign --tag v0.6.1 --build 1388 --asset Sill.zip --size "$(stat -f %z "$genuine/Sill.zip")" \
    --sha256 "$(shasum -a 256 "$genuine/Sill.zip" | cut -d' ' -f1)" --cdhash arm64=d5feca97b4d531345aefab17bb8b588358f2975f \
    --out "$out/assets/Sill.zip.manifest" --key-file "$out/key" > /dev/null
expect fail "the audit: a manifest signed with the key outside the record (a leaked key's)" "$sign" --audit --notify
grep -q "v0.6.1 (published): NOT IN YOUR SIGNING RECORD, and it verifies with your update key" "$out/last.log" \
    || { echo "  FAIL: the audit's alarm"; cat "$out/last.log"; failures=$((failures + 1)); }
grep -q "^osascript -e display notification" "$out/gh.log" && echo "  ok: --notify posts a notification (a stand-in osascript)" \
    || { echo "  FAIL: no notification"; failures=$((failures + 1)); }
printf 'not a manifest\n' > "$out/assets/Sill.zip.manifest"
expect fail "the audit: a manifest no key signed" "$sign" --audit
grep -q "doesn't verify with your update key" "$out/last.log" || { echo "  FAIL: the audit's words for garbage"; cat "$out/last.log"; failures=$((failures + 1)); }
cp "$out/recorded.manifest" "$out/assets/Sill.zip.manifest"
expect ok "the audit again with the recorded manifest back" "$sign" --audit
# AU1: a release signed outside the record is seen as a pre-release and as a draft too, and an audit that can't run
# says so with --notify.
"$out/signer/update-manifest" sign --tag v0.7.0 --build 1500 --asset Sill.zip --size 6000000 --sha256 "$zero" \
    --cdhash arm64=d5feca97b4d531345aefab17bb8b588358f2975f --out "$out/v070.manifest" --key-file "$out/key" > /dev/null
for state in prerelease draft published; do
    before="$(notifications)"
    GH_STANDIN_EXTRA="$state" GH_STANDIN_EXTRA_MANIFEST="$out/v070.manifest" expect fail "AU1: a release outside the record, as $state" "$sign" --audit --notify
    grep -q "v0.7.0 (.*): NOT IN YOUR SIGNING RECORD, and it verifies with your update key" "$out/last.log" && [ "$(notifications)" -gt "$before" ] \
        && echo "  ok: AU1: named, and a notification ($state)" || { echo "  FAIL: AU1's words or notification ($state)"; cat "$out/last.log"; failures=$((failures + 1)); }
done
before="$(notifications)"
GH_STANDIN_FAIL=1 expect fail "AU1: gh can't list (an expired login)" "$sign" --audit --notify
[ "$(notifications)" -gt "$before" ] && grep -q "display notification .The audit couldn't run: can't list" "$out/gh.log" \
    && echo "  ok: AU1: an audit that couldn't run notifies" || { echo "  FAIL: no notification when the audit couldn't run"; tail -3 "$out/gh.log"; failures=$((failures + 1)); }
before="$(notifications)"
expect ok "the audit, clean, posts nothing" "$sign" --audit --notify
[ "$(notifications)" = "$before" ] && echo "  ok: a clean audit posts no notification" || { echo "  FAIL: a clean audit notified"; failures=$((failures + 1)); }
# R2: the updater's changes since the last release signed (a release v0.6.0 recorded at the commit before).
git -C "$scratch" tag -f v0.6.0 "v0.6.1^{commit}~1" > /dev/null
printf '%s v0.6.0 %s %s\n' 2026-11-01T00:00:00Z "$zero" "$zero" > "$out/record.tmp"; cat "$out/signer/signed.txt" >> "$out/record.tmp"
cp "$out/record.tmp" "$out/signer/signed.txt"
expect fail "R2: --yes doesn't answer the question about the updater's changes" no_answer signs v0.6.1 "${src[@]}" --replace
grep -q "nothing signed: read the updater's changes first" "$out/last.log" || { echo "  FAIL: R2's refusal"; cat "$out/last.log"; failures=$((failures + 1)); }
expect ok "R2: signed with the updater's changes since v0.6.0 shown and read" with_y signs v0.6.1 "${src[@]}" --replace
grep -q "the updater's own files since v0.6.0" "$out/last.log" && grep -q "UpdateManifest.swift" "$out/last.log" \
    && echo "  ok: R2 shows UpdateManifest.swift changed since v0.6.0" || { echo "  FAIL: R2's diff"; cat "$out/last.log"; failures=$((failures + 1)); }
# The list itself (updater_files), not the script at large: Compatibility.swift is named elsewhere in it too.
r2list="$(awk '/^updater_files=\(/,/\)$/' "$root/Scripts/sign-update.sh")"
for f in SillMenuBar/AppModel.swift SillMenuBar/SettingsPanes.swift StreamProtocol/Compatibility.swift SillHost/StreamServer.swift; do
    grep -q "Sources/$f" <<<"$r2list" || { echo "  FAIL: R2's list lacks $f"; failures=$((failures + 1)); }
done
# F2: one line slipped into the release's Sill.
keys_line "$pub" "$other"; retag "rotation support"
expect fail "F2: a second key in the release's Sill" signs v0.6.1 "${src[@]}" --replace
keys_line "$pub"; retag "back to one key"
sed -i '' 's/leaf\[subject.OU\] = \\"9B2KKVM937\\"/leaf[subject.OU] = \\"ABCDE12345\\"/' "$scratch/Sources/SillMenuBar/UpdateInstallPolicy.swift"; retag "another team"
expect fail "F2: another team in the pinned requirement" signs v0.6.1 "${src[@]}" --replace
git -C "$scratch" checkout -q HEAD~1 -- Sources/SillMenuBar/UpdateInstallPolicy.swift; retag "the team back"
sed -i '' 's#"https://api.github.com"#"https://api.githubusercontent.com"#' "$scratch/Sources/SillMenuBar/UpdateInstallPolicy.swift"; retag "another API host"
expect fail "F2: another host in Endpoints.github" signs v0.6.1 "${src[@]}" --replace
git -C "$scratch" checkout -q HEAD~1 -- Sources/SillMenuBar/UpdateInstallPolicy.swift; retag "the host back"
printf '\n// A comment that names releaseKeys changes no trust.\n' >> "$scratch/Sources/SillMenuBar/UpdateManifest.swift"
sed -i '' 's#^    /// The only Trust Sill.app uses.#    /// The only Trust Sill.app uses (a comment changed).#' "$scratch/Sources/SillMenuBar/UpdateInstallPolicy.swift"
retag "comments"
grep -q "a comment changed" "$scratch/Sources/SillMenuBar/UpdateInstallPolicy.swift" || { echo "  FAIL: the comment case changed nothing"; failures=$((failures + 1)); }
expect ok "comments change no trust" with_y signs v0.6.1 "${src[@]}" --replace
# The manifest's signed time, and a stop for the release (review 3, plan §15.4), with the key in the file.
grep -q '^signed 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$' "$out/assets/Sill.zip.manifest" \
    && echo "  ok: the manifest carries the time it was signed" || { echo "  FAIL: no signed line"; failures=$((failures + 1)); }
sha="$(sed -n 's/^sha256 //p' "$out/assets/Sill.zip.manifest")"
expect ok "a stop for v0.6.1" "$out/signer/update-manifest" stop --tag v0.6.1 --sha256 "$sha" --out "$out/Sill.zip.stop" --key-file "$out/key"
expect ok "the stop verifies with the key" "$out/signer/update-manifest" verify-stop "$out/Sill.zip.stop" --key "$pub"
grep -q "stop: tag v0.6.1, SHA-256 $sha" "$out/last.log" || { echo "  FAIL: the stop's fields"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "another key does not verify the stop" "$out/signer/update-manifest" verify-stop "$out/Sill.zip.stop" --key "$other"
expect fail "a manifest is no stop" "$out/signer/update-manifest" verify-stop "$out/assets/Sill.zip.manifest" --key "$pub"
# Use nightly builds (plan §16): the nightly key apart from the update key, both ways (T35, T36), and
# Scripts/sign-nightly.sh signing tonight's zip and reading it back with the commit's nightlyKeys.
c40="$(printf 'c%.0s' {1..40})"
expect fail "new-key --nightly never uses the keychain" "$out/signer/update-manifest" new-key --nightly
expect ok "the nightly key, in a file of its own" "$out/signer/update-manifest" new-key --nightly --key-file "$out/nightly.key"
grep -q "nightlyKeys (never releaseKeys)" "$out/last.log" || { echo "  FAIL: the nightly key's words"; cat "$out/last.log"; failures=$((failures + 1)); }
npub="$(sed -n 's/^public key \([A-Za-z0-9+\/=]*\) .*/\1/p' "$out/last.log")"
nargs=(--version 0.6.2 --build 1471 --commit "$c40" --asset Sill-nightly.zip --size 100 --sha256 "$zero" --cdhash "arm64=$c40")
expect fail "a nightly manifest never from the keychain" "$out/signer/update-manifest" nightly "${nargs[@]}" --out "$out/n.manifest"
expect ok "a nightly manifest with the nightly key" "$out/signer/update-manifest" nightly "${nargs[@]}" --out "$out/n.manifest" --key-file "$out/nightly.key"
expect ok "it verifies as a nightly" "$out/signer/update-manifest" verify-nightly "$out/n.manifest" --key "$npub"
expect fail "T36: a nightly's manifest is never a release's" "$out/signer/update-manifest" verify "$out/n.manifest" --key "$npub"
expect fail "T36: a release's manifest is never a nightly's" "$out/signer/update-manifest" verify-nightly "$out/assets/Sill.zip.manifest" --key "$pub"
expect fail "T35: the nightly key never verifies a release" "$out/signer/update-manifest" verify "$out/assets/Sill.zip.manifest" --key "$npub"
expect fail "the update key never verifies a nightly" "$out/signer/update-manifest" verify-nightly "$out/n.manifest" --key "$pub"
nscratch="$out/nscratch"
mkdir -p "$nscratch/Sources/StreamProtocol" "$nscratch/Sources/SillMenuBar" "$nscratch/Scripts"
cp "$root/Sources/StreamProtocol/Compatibility.swift" "$nscratch/Sources/StreamProtocol/"
cp "$root/Sources/SillMenuBar/UpdateManifest.swift" "$nscratch/Sources/SillMenuBar/"
cp "$root/Scripts/update-manifest.swift" "$root/Scripts/sign-nightly.sh" "$nscratch/Scripts/"
python3 -I - "$nscratch/Sources/SillMenuBar/UpdateManifest.swift" "$npub" <<'PY'
import re, sys
p, key = sys.argv[1], sys.argv[2]
s = open(p).read()
s, n = re.subn(r"static let nightlyKeys: \[String\] = \[.*\]", 'static let nightlyKeys: [String] = ["' + key + '"]', s)
assert n == 1
open(p, "w").write(s)
PY
git -C "$nscratch" init -q
git -C "$nscratch" -c user.name=t -c user.email=t@t add -A
git -C "$nscratch" -c user.name=t -c user.email=t@t commit -q -m "a nightly key"
ncommit="$(git -C "$nscratch" rev-parse HEAD)"
nightly_zip() {  # nightly_zip CHANNEL COMMIT OUT: the genuine v0.6.1 marked as a nightly (its seal no longer covers it: sign-nightly reads, it doesn't verify)
    rm -rf "$out/napp"; mkdir -p "$out/napp"
    ditto -x -k --noqtn --norsrc --noextattr "$genuine/Sill.zip" "$out/napp"
    [ -z "$1" ] || /usr/libexec/PlistBuddy -c "Add :SillChannel string $1" "$out/napp/Sill.app/Contents/Info.plist"
    [ -z "$2" ] || /usr/libexec/PlistBuddy -c "Add :SillCommit string $2" "$out/napp/Sill.app/Contents/Info.plist"
    rm -f "$3"; (cd "$out/napp" && ditto -c -k --keepParent Sill.app "$3")
}
nightly_zip nightly "$ncommit" "$out/Sill-nightly-20261112-abcdef0.zip"
expect ok "sign-nightly.sh signs tonight's zip" "$nscratch/Scripts/sign-nightly.sh" --key-file "$out/nightly.key" --zip "$out/Sill-nightly-20261112-abcdef0.zip" --out "$out/nout"
expect ok "its manifest verifies with the nightly key" "$out/signer/update-manifest" verify-nightly "$out/nout/Sill-nightly.zip.manifest" --key "$npub"
grep -q "nightly 0.6.1 (1388), commit $ncommit, Sill-nightly.zip" "$out/last.log" && cmp -s "$out/nout/Sill-nightly.zip" "$out/Sill-nightly-20261112-abcdef0.zip" \
    && echo "  ok: the manifest names tonight's version, build, commit and the zip under its fixed name" || { echo "  FAIL: the nightly manifest's fields"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "sign-nightly.sh refuses a release's app (no SillChannel)" "$nscratch/Scripts/sign-nightly.sh" --key-file "$out/nightly.key" --zip "$genuine/Sill.zip" --out "$out/nout2"
nightly_zip nightly "$zero" "$out/other-commit.zip"
expect fail "sign-nightly.sh refuses an app of another commit" "$nscratch/Scripts/sign-nightly.sh" --key-file "$out/nightly.key" --zip "$out/other-commit.zip" --out "$out/nout3"
expect fail "sign-nightly.sh refuses a key this commit's Sill doesn't carry (the update key's file)" "$nscratch/Scripts/sign-nightly.sh" --key-file "$out/key" --zip "$out/Sill-nightly-20261112-abcdef0.zip" --out "$out/nout4"
grep -q "doesn't verify with this commit's nightlyKeys" "$out/last.log" || { echo "  FAIL: the words for a key the commit doesn't carry"; cat "$out/last.log"; failures=$((failures + 1)); }
# sign-nightly.sh --new-key (Noah's step 1, plan §16.8): the key only in a new file of mode 0600, and the compiled
# signer removed after (the script waits for it rather than exec, so its trap runs).
mkdir -p "$out/newkey-tmp"
expect ok "sign-nightly.sh --new-key makes the nightly key in a new file" env TMPDIR="$out/newkey-tmp" "$nscratch/Scripts/sign-nightly.sh" --new-key --key-file "$out/nightly2.key"
grep -q "nightlyKeys (never releaseKeys)" "$out/last.log" && [ "$(stat -f %Lp "$out/nightly2.key")" = 600 ] && [ -z "$(ls -A "$out/newkey-tmp")" ] \
    && echo "  ok: its words, mode 0600, and no compiled signer left behind" || { echo "  FAIL: --new-key's file or its clean-up: $(ls -A "$out/newkey-tmp" | tr '\n' ' ')"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "sign-nightly.sh --new-key never replaces a key file" env TMPDIR="$out/newkey-tmp" "$nscratch/Scripts/sign-nightly.sh" --new-key --key-file "$out/nightly2.key"
[ -z "$(ls -A "$out/newkey-tmp")" ] && echo "  ok: nothing left behind after a refusal either" || { echo "  FAIL: a refusal left $(ls -A "$out/newkey-tmp")"; failures=$((failures + 1)); }
# N10 e (the third security pass): a nightly is never signed as a release, even one of the tag's own commit.
mkdir -p "$out/nassets"
nightly_zip nightly "$(git -C "$scratch" rev-parse "v0.6.1^{commit}")" "$out/nassets/Sill.zip"
(cd "$out/nassets" && shasum -a 256 Sill.zip > Sill.zip.sha256)
GH_STANDIN_ASSETS="$out/nassets" expect fail "N10 e: an app with SillChannel is never signed as a release" with_y signs v0.6.1 --source "$scratch" --key-file "$out/key" --zip "$out/nassets/Sill.zip" --yes
grep -q "a release is never signed from one" "$out/last.log" || { echo "  FAIL: N10 e's words"; cat "$out/last.log"; failures=$((failures + 1)); }
# F1: a signer without the hardened runtime (an older install) is refused.
cp "$out/signer/update-manifest" "$out/plain-signer"
codesign -s - -f "$out/plain-signer" 2> /dev/null
cp "$out/signer/update-manifest" "$out/hardened-signer"
cp "$out/plain-signer" "$out/signer/update-manifest"
shasum -a 256 "$out/signer/update-manifest" | cut -d' ' -f1 > "$out/signer/update-manifest.sha256"
expect fail "F1: a signer without the hardened runtime" signs v0.6.1 "${src[@]}" --replace
grep -q "no hardened runtime" "$out/last.log" || { echo "  FAIL: the refusal's words"; cat "$out/last.log"; failures=$((failures + 1)); }
cp "$out/hardened-signer" "$out/signer/update-manifest"
shasum -a 256 "$out/signer/update-manifest" | cut -d' ' -f1 > "$out/signer/update-manifest.sha256"
printf 'x' >> "$out/signer/update-manifest"
expect fail "a signer changed after it was installed" signs v0.6.1 "${src[@]}" --replace
# F3: the backup's words.
for doc in docs/release-checklist.md docs/one-click-update-plan.md; do
    grep -q "never Always Allow" "$root/$doc" && grep -q "Terminal.app" "$root/$doc" && echo "  ok: $doc says Allow, never Always Allow, in Terminal.app" \
        || { echo "  FAIL: $doc's backup words (F3)"; failures=$((failures + 1)); }
done
grep -c '^uploaded ' "$out/gh.log" | sed 's/^/  uploads recorded: /'
[ "$failures" = 0 ] && echo "sign-test: all passed" || { echo "sign-test: $failures failed"; exit 1; }
