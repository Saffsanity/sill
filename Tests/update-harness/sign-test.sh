#!/bin/bash
# G6 (docs/one-click-update-plan.md §11): Scripts/sign-update.sh against a stand-in `gh` (this file writes it
# into .build) serving the genuine v0.6.1 from .build/updater-scratch/release-v0.6.1, with a throwaway key in
# a file and the signer installed in a scratch folder (SILL_SIGNER_DIR). Nothing is uploaded anywhere: the
# stand-in records what would have gone. Never the login keychain (every step passes --key-file).
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
# The stand-in: `api repos/R/releases/tags/T`, `release download T --repo R --pattern P... --dir D`,
# `release upload T FILE --repo R [--clobber]`, from and into $GH_STANDIN_ASSETS; every call logged.
set -euo pipefail
echo "gh $*" >> "$GH_STANDIN_LOG"
assets="$GH_STANDIN_ASSETS"
if [ "$1" = api ]; then
    python3 -I - "$assets" "$2" <<'PY'
import hashlib, json, os, sys
assets, path = sys.argv[1], sys.argv[2]
tag = path.rsplit("/", 1)[-1]
items = []
for name in sorted(os.listdir(assets)):
    data = open(os.path.join(assets, name), "rb").read()
    items.append({"name": name, "size": len(data), "state": "uploaded", "digest": "sha256:" + hashlib.sha256(data).hexdigest(),
                  "browser_download_url": "https://github.com/Saffsanity/sill/releases/download/%s/%s" % (tag, name)})
print(json.dumps({"tag_name": tag, "draft": False, "prerelease": False, "assets": items}))
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
export PATH="$out/bin:$PATH" GH_STANDIN_ASSETS="$out/assets" GH_STANDIN_LOG="$out/gh.log" SILL_SIGNER_DIR="$out/signer"
sign="$root/Scripts/sign-update.sh"
failures=0
expect() {  # expect ok|fail "what" command...
    local want=$1 what=$2; shift 2
    if "$@" > "$out/last.log" 2>&1; then got=ok; else got=fail; fi
    if [ "$got" = "$want" ]; then echo "  ok: $what"; else echo "  FAIL: $what (expected $want)"; sed 's/^/    /' "$out/last.log"; failures=$((failures + 1)); fi
}
echo "== sign-test"
expect fail "no signer installed yet" "$sign" --public-key --key-file "$out/key"
expect ok "the signer installed (from this checkout, in the scratch folder)" "$sign" --install-signer --yes
expect ok "a throwaway key in a file" "$sign" --new-key --key-file "$out/key"
pub="$(sed -n 's/^public key \([A-Za-z0-9+\/=]*\) .*/\1/p' "$out/last.log")"
[ -n "$pub" ] || { echo "  FAIL: no public key printed"; failures=$((failures + 1)); }
expect fail "a second key never overwrites the first" "$sign" --new-key --key-file "$out/key"
expect fail "a zip that isn't GitHub's" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --zip "$genuine/Sill.zip.sha256" --yes
expect fail "a SHA-256 that isn't GitHub's" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --expect-sha256 "$(printf '0%.0s' {1..64})" --yes
expect fail "no zip known (none built here for 0.6.1)" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --yes
expect ok "the release signed, uploaded and read back" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --zip "$genuine/Sill.zip" --yes
[ -f "$out/assets/Sill.zip.manifest" ] || { echo "  FAIL: nothing uploaded"; failures=$((failures + 1)); }
expect ok "the uploaded manifest verifies with the key" "$out/signer/update-manifest" verify "$out/assets/Sill.zip.manifest" --key "$pub"
grep -q "tag v0.6.1, version 0.6.1, build 1388, Sill.zip 5920002 bytes" "$out/last.log" || { echo "  FAIL: the manifest's fields"; cat "$out/last.log"; failures=$((failures + 1)); }
grep -q "cdhash arm64 d5feca97b4d531345aefab17bb8b588358f2975f" "$out/last.log" || { echo "  FAIL: the arm64 cdhash"; failures=$((failures + 1)); }
expect fail "another key does not verify it" "$out/signer/update-manifest" verify "$out/assets/Sill.zip.manifest" --key "$(python3 -I -c 'import base64,os; print(base64.b64encode(os.urandom(32)).decode())')"
expect fail "signed already, without --replace" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --zip "$genuine/Sill.zip" --yes
expect ok "signed again with --replace" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --zip "$genuine/Sill.zip" --yes --replace
printf 'x' >> "$out/signer/update-manifest"
expect fail "a signer changed after it was installed" "$sign" v0.6.1 --key-file "$out/key" --expect-key "$pub" --zip "$genuine/Sill.zip" --yes --replace
grep -c '^uploaded ' "$out/gh.log" | sed 's/^/  uploads recorded: /'
[ "$failures" = 0 ] && echo "sign-test: all passed" || { echo "sign-test: $failures failed"; exit 1; }
