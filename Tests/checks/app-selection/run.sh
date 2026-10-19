#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
# Run the production launch handler and pending-selection resolver with deterministic app,
# catalog and capture stand-ins. No workspace activation, Accessibility, or capture occurs.
python3 - "$out/main.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('Sources/SillHost/StreamCoordinator.swift').read_text()
start = source.index('        case .launchApp:', source.index('switch message.kind'))
end = source.index('        case .editableFocus:', start)
launch = source[start:end].split('\n', 2)[2]
start = source.index('    private func selectPendingAppWindow()')
end = source.index('    private func windowsChanged(', start)
resolver = source[start:end].replace('    private func', '    func')
start = source.index('    private func handlePick(')
end = source.index('    /// Streams `source`', start)
picks = source[start:end].replace('    private func', '    func')
harness = pathlib.Path('Tests/checks/app-selection/main.swift').read_text()
pathlib.Path(sys.argv[1]).write_text(harness.replace('/* LAUNCH */', launch).replace('/* RESOLVER */', resolver).replace('/* PICKS */', picks))
PY
swiftc -O -parse-as-library "$out/main.swift" -o "$out/check"
"$out/check"
# Extract the real Apps row and client selection methods, compiling with the real wire types.
# VisionOS conditionals are selected; DEBUG-only UI harness branches are omitted.
python3 - "$out/client.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('iOSClient/StreamClient.swift').read_text()
def method(start, end):
    a = source.index(start)
    return source[a:source.index(end, a)].replace('    private func', '    func')
client = method('    func select(_ source:', '    /// The bar\'s long-press menu:')
client += method('    func launch(bundleID:', '    /// Send one input event to the Mac.')
# Keep source selection and launch timer syntax, but replace wall-clock scheduling with a
# no-op in this deterministic harness; expiry itself is exercised with an expired intent.
a = client.index('        DispatchQueue.main.asyncAfter(')
b = client.index('        choicesSent += 1', a)
client = client[:a] + client[b:]
rowSource = pathlib.Path('iOSClient/StreamScreen.swift').read_text()
a = rowSource.index('    private func show(_ app: OpenApp)')
b = rowSource.index('\n}\n', a)
row = rowSource[a:b].replace('    private func', '    func')
def vision(text):
    result, enabled = [], [True]
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('#if '):
            enabled.append(enabled[-1] and stripped == '#if os(visionOS)')
        elif stripped == '#else': enabled[-1] = enabled[-2] and not enabled[-1]
        elif stripped == '#endif': enabled.pop()
        elif enabled[-1]: result.append(line)
    return '\n'.join(result)
harness = pathlib.Path('Tests/checks/app-selection/client.swift').read_text()
pathlib.Path(sys.argv[1]).write_text(harness.replace('/* CLIENT */', vision(client)).replace('/* ROW */', vision(row)))
# Both automatic Desktop branches must pass the common guard; delayed closures also retain
# their existing choices-generation fence. Disconnect must discard the pending client intent.
assert source.index('if self.awaitingAppSelection(active:') < source.index('if list.active == .none, !Self.noAutoDesktop')
assert 'self.choicesSent == choices' in source
assert 'pendingAppSelection = nil\n        lastAutoDesktop = .distantPast' in source
PY
swiftc -O -parse-as-library Sources/StreamProtocol/*.swift "$out/client.swift" -o "$out/client-check"
"$out/client-check"
