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
# The stand-in: `api repos/R/releases/tags/T`, `api [--paginate] repos/R/releases…` (one release, v0.6.1, of
# $GH_STANDIN_ASSETS), `api repos/R/git/ref/tags/T` (the tag in the scratch checkout $GH_STANDIN_REPO, or
# $GH_STANDIN_TAG_SHA; annotated with GH_STANDIN_TAG_ANNOTATED=1) and `api repos/R/git/tags/SHA`,
# `release download T --repo R --pattern P... --dir D`, `release upload T FILE --repo R [--clobber]`, from and
# into $GH_STANDIN_ASSETS; every call logged.
set -euo pipefail
echo "gh $*" >> "$GH_STANDIN_LOG"
assets="$GH_STANDIN_ASSETS"
if [ "$1" = api ]; then
    path=""; for a in "${@:2}"; do case "$a" in -*) ;; *) path="$a" ;; esac; done
    sha="${GH_STANDIN_TAG_SHA:-$(git -C "$GH_STANDIN_REPO" rev-parse "v0.6.1^{commit}")}"
    python3 -I - "$assets" "$path" "$sha" "${GH_STANDIN_TAG_ANNOTATED:-0}" <<'PY'
import hashlib, json, os, sys
assets, path, sha, annotated = sys.argv[1:5]
if "/git/ref/tags/" in path:
    kind, target = ("tag", "a" * 40) if annotated == "1" else ("commit", sha)
    print(json.dumps({"ref": "refs/tags/" + path.rsplit("/", 1)[-1], "object": {"type": kind, "sha": target}}))
    sys.exit(0)
if "/git/tags/" in path:
    print(json.dumps({"object": {"type": "commit", "sha": sha}}))
    sys.exit(0)
tag = path.rsplit("/", 1)[-1] if "/releases/tags/" in path else "v0.6.1"
items = []
for name in sorted(os.listdir(assets)):
    data = open(os.path.join(assets, name), "rb").read()
    items.append({"name": name, "size": len(data), "state": "uploaded", "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                  "browser_download_url": "https://github.com/Saffsanity/sill/releases/download/%s/%s" % (tag, name)})
release = {"tag_name": tag, "draft": False, "prerelease": False, "assets": items}
print(json.dumps(release if "/releases/tags/" in path else [release]))
PY
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
expect ok "a throwaway key in a file" "$sign" --new-key --key-file "$out/key"
pub="$(sed -n 's/^public key \([A-Za-z0-9+\/=]*\) .*/\1/p' "$out/last.log")"
[ -n "$pub" ] || { echo "  FAIL: no public key printed"; failures=$((failures + 1)); }
expect fail "a second key never overwrites the first" "$sign" --new-key --key-file "$out/key"
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
expect fail "F2: the key added after the signer was installed (its trust was recorded with none)" signs v0.6.1 "${src[@]}"
grep -q "trusts something other than what you read" "$out/last.log" || { echo "  FAIL: the refusal's words"; cat "$out/last.log"; failures=$((failures + 1)); }
expect ok "the signer installed again from the checkout that carries the key" "$sign" --install-signer --source "$scratch" --yes
grep -q "$pub" "$out/signer/trust.txt" || { echo "  FAIL: the recorded trust lacks the key"; failures=$((failures + 1)); }
expect fail "a zip that isn't GitHub's" signs v0.6.1 --source "$scratch" --key-file "$out/key" --zip "$genuine/Sill.zip.sha256" --yes
expect fail "a SHA-256 that isn't GitHub's" signs v0.6.1 --source "$scratch" --key-file "$out/key" --expect-sha256 "$zero" --yes
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
# A1: the audit, every manifest on GitHub against the signing record.
expect ok "the audit: the release on GitHub is in the record" "$sign" --audit
grep -q "v0.6.1: signed here" "$out/last.log" || { echo "  FAIL: the audit's words"; cat "$out/last.log"; failures=$((failures + 1)); }
cp "$out/assets/Sill.zip.manifest" "$out/recorded.manifest"
"$out/signer/update-manifest" sign --tag v0.6.1 --build 1388 --asset Sill.zip --size "$(stat -f %z "$genuine/Sill.zip")" \
    --sha256 "$(shasum -a 256 "$genuine/Sill.zip" | cut -d' ' -f1)" --cdhash arm64=d5feca97b4d531345aefab17bb8b588358f2975f \
    --out "$out/assets/Sill.zip.manifest" --key-file "$out/key" > /dev/null
expect fail "the audit: a manifest signed with the key outside the record (a leaked key's)" "$sign" --audit --notify
grep -q "v0.6.1: NOT IN YOUR SIGNING RECORD, and it verifies with your update key" "$out/last.log" \
    || { echo "  FAIL: the audit's alarm"; cat "$out/last.log"; failures=$((failures + 1)); }
grep -q "^osascript -e display notification" "$out/gh.log" && echo "  ok: --notify posts a notification (a stand-in osascript)" \
    || { echo "  FAIL: no notification"; failures=$((failures + 1)); }
printf 'not a manifest\n' > "$out/assets/Sill.zip.manifest"
expect fail "the audit: a manifest no key signed" "$sign" --audit
grep -q "doesn't verify with your update key" "$out/last.log" || { echo "  FAIL: the audit's words for garbage"; cat "$out/last.log"; failures=$((failures + 1)); }
cp "$out/recorded.manifest" "$out/assets/Sill.zip.manifest"
expect ok "the audit again with the recorded manifest back" "$sign" --audit
# R2: the updater's changes since the last release signed (a release v0.6.0 recorded at the commit before).
git -C "$scratch" tag -f v0.6.0 "v0.6.1^{commit}~1" > /dev/null
printf '%s v0.6.0 %s %s\n' 2026-11-01T00:00:00Z "$zero" "$zero" > "$out/record.tmp"; cat "$out/signer/signed.txt" >> "$out/record.tmp"
cp "$out/record.tmp" "$out/signer/signed.txt"
expect ok "R2: signed with the updater's changes since v0.6.0 shown" signs v0.6.1 "${src[@]}" --replace
grep -q "the updater's own files since v0.6.0" "$out/last.log" && grep -q "UpdateManifest.swift" "$out/last.log" \
    && echo "  ok: R2 shows UpdateManifest.swift changed since v0.6.0" || { echo "  FAIL: R2's diff"; cat "$out/last.log"; failures=$((failures + 1)); }
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
expect ok "comments change no trust" signs v0.6.1 "${src[@]}" --replace
# The manifest's signed time, and a stop for the release (review 3, plan §15.4), with the key in the file.
grep -q '^signed 20[0-9][0-9]-[01][0-9]-[0-3][0-9]T[0-2][0-9]:[0-5][0-9]:[0-5][0-9]Z$' "$out/assets/Sill.zip.manifest" \
    && echo "  ok: the manifest carries the time it was signed" || { echo "  FAIL: no signed line"; failures=$((failures + 1)); }
sha="$(sed -n 's/^sha256 //p' "$out/assets/Sill.zip.manifest")"
expect ok "a stop for v0.6.1" "$out/signer/update-manifest" stop --tag v0.6.1 --sha256 "$sha" --out "$out/Sill.zip.stop" --key-file "$out/key"
expect ok "the stop verifies with the key" "$out/signer/update-manifest" verify-stop "$out/Sill.zip.stop" --key "$pub"
grep -q "stop: tag v0.6.1, SHA-256 $sha" "$out/last.log" || { echo "  FAIL: the stop's fields"; cat "$out/last.log"; failures=$((failures + 1)); }
expect fail "another key does not verify the stop" "$out/signer/update-manifest" verify-stop "$out/Sill.zip.stop" --key "$other"
expect fail "a manifest is no stop" "$out/signer/update-manifest" verify-stop "$out/assets/Sill.zip.manifest" --key "$pub"
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
