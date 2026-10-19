#!/bin/bash
# Writes clients/core/src/test/resources/sill/vectors.json from the real Sources/StreamProtocol, and
# with --check also decodes what the Kotlin core wrote (clients/core/build/kotlin-wire.json, from its
# tests) with the Mac's types. Needs swiftc (Xcode on a Mac, or swift.org's toolchain on Linux).
#   clients/wire-vectors/generate.sh            regenerate the vectors (commit the result)
#   clients/wire-vectors/generate.sh --verify   regenerate into .build and fail if the committed file differs
#   clients/wire-vectors/generate.sh --check    decode the Kotlin core's encodings with the Mac's types
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="$root/.build/wire-vectors"
mkdir -p "$out"
cd "$root"
# Swift's Dictionary order is random per process unless this is set, and JSONEncoder on Linux
# writes keys in that order: set, the file is the same at every run.
export SWIFT_DETERMINISTIC_HASHING=1
# Every StreamProtocol file that needs only Foundation, as it is; Remote.swift without SignedMacInfo's
# signing (strip_remote.py). The four that need Security, CryptoKit or Network have their own vectors
# in Tests/checks/protocol, which the Kotlin tests repeat.
files=()
for f in Sources/StreamProtocol/*.swift; do
    case "$(basename "$f")" in
        Pairing.swift|RemoteIdentity.swift|RemoteTLS.swift|Remote.swift) ;;
        *) files+=("$f") ;;
    esac
done
python3 "$here/strip_remote.py" Sources/StreamProtocol/Remote.swift "$out/Remote.swift"
swiftc -O "${files[@]}" "$out/Remote.swift" "$here/main.swift" -o "$out/vectors" 2>&1 | grep -v "^$" || true
[ -x "$out/vectors" ] || { echo "generate.sh: the generator did not compile" >&2; exit 1; }
committed="$root/clients/core/src/test/resources/sill/vectors.json"
case "${1:-}" in
    --check)
        "$out/vectors" decode "$committed" "$root/clients/core/build/kotlin-wire.json" ;;
    --verify)
        "$out/vectors" generate "$out/vectors.json"
        # By content: another Swift release may write JSON keys in another order.
        if python3 "$here/same_vectors.py" "$out/vectors.json" "$committed"; then echo "vectors.json matches Sources/StreamProtocol"
        else echo "vectors.json is stale: run clients/wire-vectors/generate.sh and commit it" >&2; exit 1; fi ;;
    "")
        mkdir -p "$(dirname "$committed")"
        "$out/vectors" generate "$committed" ;;
    *) echo "usage: generate.sh [--verify|--check]" >&2; exit 2 ;;
esac
