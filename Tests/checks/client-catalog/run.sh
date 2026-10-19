#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
# Exercise the actual receiver publication block with Combine, without UIKit/network setup.
python3 - "$out/main.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('iOSClient/StreamClient.swift').read_text()
start = source.index('                // A selection acknowledges the full catalog again')
end = source.index('                // The first list after a move without a fence:', start)
block = source[start:end]
harness = pathlib.Path('Tests/checks/client-catalog/main.swift').read_text()
pathlib.Path(sys.argv[1]).write_text(harness.replace('/* RECEIVER */', block))
PY
swiftc -O "$out/main.swift" -o "$out/check"
"$out/check"
