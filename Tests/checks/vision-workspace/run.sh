#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
python3 - "$out/main.swift" <<'PY'
import pathlib, sys
client = pathlib.Path('iOSClient/StreamClient.swift').read_text()
def block(start, end):
    a = client.index(start)
    return client[a:client.index(end, a)]
receiver = block('                if let workspace = self.pendingSpatialWorkspace {', '                if let source = self.pendingSpatialSource {')
request = block('    private func requestSpatialWorkspaceSource(', '    func cancelSpatialRestoreForForgottenMac(').replace('private func', 'func').replace('NWConnection', 'Connection')
for text in ['receiver', 'request']:
    value = locals()[text]
    import re
    value = re.sub(r'DispatchQueue.main.asyncAfter\(deadline: \.now\(\) \+ (?:3|10), execute: timeout\)', 'Scheduler.pending.append(timeout)', value)
    locals()[text] = value
presentation = block('    func noteSpatialPresentationSize(', '    /// Only existing admitted pairings may reconnect.')
harness = pathlib.Path('Tests/checks/vision-workspace/main.swift').read_text().replace('/* RECEIVER */', receiver).replace('/* REQUEST */', request).replace('/* PRESENTATION */', presentation)
pathlib.Path(sys.argv[1]).write_text(harness)
PY
swiftc -O Sources/StreamProtocol/*.swift visionOSClient/VisionWorkspace.swift "$out/main.swift" -o "$out/check"
"$out/check"
