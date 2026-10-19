#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
python3 - "$out/main.swift" <<'PY'
import pathlib, sys
client = pathlib.Path('iOSClient/StreamClient.swift').read_text()
host = pathlib.Path('Sources/SillHost/StreamCoordinator.swift').read_text()
def block(source, start, end):
    a = source.index(start)
    return source[a:source.index(end, a)]
receiver = block(client, '                if let source = self.pendingSpatialSource {', '                // The first list after a move without a fence:')
receiver = receiver.replace('                #endif\n', '').replace('DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)', 'Scheduler.pending.append(timeout)')
clear = block(client, '    private func cancelSpatialSourceTimeout()', '    /// Scene closure cancels only')
select = block(client, '    func select(_ source: StreamSource)', '    /// Asks the host to stream this source:')
select = select.replace('        #if os(visionOS)\n', '').replace('        #endif\n', '')
launch = block(client, '    func launch(bundleID: String)', '    /// Send one input event').replace('        #if os(visionOS)\n', '').replace('        #endif\n', '')
# Route the app-selection deadline through the same deterministic scheduler as scene seeds.
launch = launch.replace('DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in', 'Scheduler.pending.append(DispatchWorkItem { [weak self] in').replace('        }\n        choicesSent += 1', '        })\n        choicesSent += 1')
bootstrap = block(host, '                        child.catalog.start()', '                    } catch {')
broadcast = block(host, '    private var spatialCatalogReady = false', '    private func sendCatalog(').replace('    private ', '    ')
send_guard = block(host, '    private func sendCatalog(to connection:', '        let now').replace('    private ', '    ').replace('NWConnection', 'Connection') + '        server.broadcast(listMessage())\n    }\n'
harness = pathlib.Path('Tests/checks/vision-scene-opening/main.swift').read_text()
for key, value in [('RECEIVER', receiver), ('CLEAR', clear), ('SELECT', select), ('BOOTSTRAP', bootstrap), ('BROADCAST', broadcast), ('SEND_GUARD', send_guard), ('LAUNCH', launch)]:
    harness = harness.replace('/* '+key+' */', value)
pathlib.Path(sys.argv[1]).write_text(harness)
PY
swiftc -O -parse-as-library "$out/main.swift" -o "$out/check"
"$out/check"
