#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
python3 - "$out/check.swift" <<'PY'
import pathlib, sys
root = pathlib.Path('.')
s = (root/'Sources/SillHost/VirtualStage.swift').read_text()
snapshot = s[s.index('private enum EmergencySnapshot {'):].replace('AXUIElement', 'String')
c = (root/'Sources/SillHost/StreamCoordinator.swift').read_text()
a = c.index('    package var stagedWindowIsFullScreen: Bool')
b = c.index('    /// Whether `id` is a Sill virtual display', a)
methods = c[a:b].replace('package ', '')
harness = '''import Foundation
import CoreGraphics
struct Placement { let element: String; let windowID: UInt32 }
class Stage { var placement: Placement? }
enum WindowSizer {
 static var fullscreen: Set<String> = ["full"]
 static var toggled: [String] = []
 static func isFullScreen(_ element: String) -> Bool { fullscreen.contains(element) }
 enum Action { case fullScreen }
 static func perform(_ action: Action, element: String) -> Bool { toggled.append(element); fullscreen.remove(element); return true }
 static func liveBounds(of id: UInt32) -> CGRect? { CGRect(x: 0, y: 0, width: 800, height: 600) }
}
class Coordinator {
 let stage = Stage()
 var independentCoordinators: [Int: Coordinator] = [:]
/* METHODS */
}
/* SNAPSHOT */
let a = UUID(), b = UUID(), frame = CGRect(x: 1, y: 2, width: 3, height: 4)
EmergencySnapshot.set(("A", frame), for: a)
EmergencySnapshot.set(("B", frame), for: b)
EmergencySnapshot.set(nil, for: a)
assert(EmergencySnapshot.takeAll().map { $0.0 } == ["B"], "releasing A must preserve B's emergency restore")
assert(EmergencySnapshot.takeAll().isEmpty, "emergency restores consumed once")
EmergencySnapshot.set(("A", frame), for: a)
EmergencySnapshot.set(("B", frame), for: b)
assert(Set(EmergencySnapshot.takeAll().map { $0.0 }) == ["A", "B"], "all simultaneous windows restored")
let root = Coordinator(), normal = Coordinator(), full = Coordinator()
normal.stage.placement = Placement(element: "normal", windowID: 1)
full.stage.placement = Placement(element: "full", windowID: 2)
root.independentCoordinators = [1: normal, 2: full]
assert(root.stagedWindowIsFullScreen)
assert(!root.stagedWindowSettled)
root.beginLeavingFullScreenForQuit()
assert(WindowSizer.toggled == ["full"], "a fullscreen sibling must not toggle a normal window into fullscreen")
assert(root.stagedWindowSettled)
assert(!root.stagedWindowIsFullScreen)
print("virtual-stage-sessions: 8 actual-source ownership and fullscreen quit assertions passed")
'''
pathlib.Path(sys.argv[1]).write_text(harness.replace('/* METHODS */', methods).replace('/* SNAPSHOT */', snapshot))
PY
swiftc "$out/check.swift" -o "$out/check"
"$out/check"
