import CoreGraphics
import Foundation

// Checks PrivacyModePolicy (Sources/SillMenuBar/PrivacyModePolicy.swift; issues #133 and #141):
// which displays receive a black privacy shield window during a session, and when Sill blanks the
// physical displays or locks the Mac after the last connected device disconnects.

typealias Policy = PrivacyModePolicy
var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL line \(line): \(what())") }
}
func same<T: Equatable>(_ got: T, _ want: T, _ what: String, line: Int = #line) {
    check(got == want, "\(what): got \(got), want \(want)", line: line)
}

// MARK: 1. Display filtering (physical displays only, never Sill's virtual display or empty frames)

let builtIn = Policy.Screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), sillVirtual: false)
let external = Policy.Screen(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), sillVirtual: false)
let virtual = Policy.Screen(id: 99, frame: CGRect(x: -4000, y: 0, width: 1920, height: 1080), sillVirtual: true)
let zeroW = Policy.Screen(id: 3, frame: CGRect(x: 0, y: 0, width: 0, height: 900), sillVirtual: false)
let zeroH = Policy.Screen(id: 4, frame: CGRect(x: 0, y: 0, width: 900, height: 0), sillVirtual: false)

same(Policy.shieldScreens([builtIn, virtual, external, zeroW, zeroH]), [builtIn, external],
     "only physical screens with positive width and height get a shield")
same(Policy.shieldScreens([virtual]), [], "virtual display alone gives no shield")
same(Policy.shieldScreens([]), [], "no displays gives no shield")

// MARK: 2. Launch with 0 devices: never blanks and never locks, even with both switches on

do {
    var state = Policy.State()
    let step = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 0,
                            consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(step.shieldActive, false, "0 devices at launch: no shield")
    same(step.shouldLock, false, "0 devices at launch: never locks")
    same(step.logLines, [], "0 devices at launch: no log lines")
}

// MARK: 3. Toggling lockOnDisconnect with 0 devices connected: never locks

do {
    var state = Policy.State()
    _ = state.update(privacyMode: false, lockOnDisconnect: false, connectedDevices: 0,
                     consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    let step = state.update(privacyMode: false, lockOnDisconnect: true, connectedDevices: 0,
                            consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(step.shouldLock, false, "turning lockOnDisconnect on while idle does not lock")
    same(step.logLines, [], "turning lockOnDisconnect on while idle logs nothing")
}

// MARK: 4. Connect -> blank display -> second device connects -> first leaves -> last leaves -> restore + lock

do {
    var state = Policy.State()
    let s1 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s1.shieldActive, true, "1st device connects: shield active")
    same(s1.shouldLock, false, "1st device connects: does not lock")
    same(s1.logLines, ["Privacy mode: blanking the display while a device is connected."],
         "1st device on 1 screen: singular log line")

    // Status tick with same 1 device: no duplicate log line.
    let s1b = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                           consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s1b.shieldActive, true, "still 1 device: shield stays active")
    same(s1b.logLines, [], "still 1 device: no duplicate log line")

    // 2nd device connects: still active, no log line, no lock.
    let s2 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 2,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s2.shieldActive, true, "2 devices: shield stays active")
    same(s2.shouldLock, false, "2 devices: no lock")
    same(s2.logLines, [], "2 devices: no log line")

    // 1st device leaves (1 still connected): does NOT lock or unblank.
    let s3 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s3.shieldActive, true, "2 -> 1 device: shield stays active")
    same(s3.shouldLock, false, "2 -> 1 device: not the last device, so no lock")
    same(s3.logLines, [], "2 -> 1 device: no log line")

    // Last device leaves (1 -> 0): restores display AND locks the unlocked console once.
    let s4 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 0,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s4.shieldActive, false, "last device leaves: shield down")
    same(s4.shouldLock, true, "last device leaves with lockOnDisconnect: locks")
    same(s4.logLines, [
        "Privacy mode: restored the display.",
        "Privacy mode: locking this Mac after the last device disconnected.",
    ], "last device leaves: logs restore then lock")

    // Subsequent status tick at 0 devices: does NOT lock again.
    let s5 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 0,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s5.shieldActive, false, "idle tick after disconnect: shield stays down")
    same(s5.shouldLock, false, "idle tick after disconnect: does not lock a second time")
    same(s5.logLines, [], "idle tick after disconnect: no log line")
}

// MARK: 5. Multiple physical displays wording, and 0 physical displays (headless Mac)

do {
    var state = Policy.State()
    let s1 = state.update(privacyMode: true, lockOnDisconnect: false, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 2, shuttingDown: false)
    same(s1.shieldActive, true, "2 physical screens: shield active")
    same(s1.logLines, ["Privacy mode: blanking 2 displays while a device is connected."],
         "2 physical screens: plural log line")
}

do {
    var state = Policy.State()
    let s1 = state.update(privacyMode: true, lockOnDisconnect: false, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 0, shuttingDown: false)
    same(s1.shieldActive, false, "0 physical screens (headless): no shield window needed")
    same(s1.logLines, [], "0 physical screens: no blanking log line")
}

// MARK: 6. Toggling privacyMode while a device is connected

do {
    var state = Policy.State()
    let s1 = state.update(privacyMode: false, lockOnDisconnect: false, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s1.shieldActive, false, "privacyMode off while connected: no shield")
    same(s1.logLines, [], "privacyMode off while connected: no log")

    let s2 = state.update(privacyMode: true, lockOnDisconnect: false, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s2.shieldActive, true, "turning privacyMode on mid-session: shield goes up")
    same(s2.logLines, ["Privacy mode: blanking the display while a device is connected."],
         "turning privacyMode on mid-session: logs blanking")

    let s3 = state.update(privacyMode: false, lockOnDisconnect: false, connectedDevices: 1,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s3.shieldActive, false, "turning privacyMode off mid-session: shield goes down")
    same(s3.logLines, ["Privacy mode: restored the display."],
         "turning privacyMode off mid-session: logs restore")
}

// MARK: 7. Lock on disconnect when console is already locked, or when shuttingDown

do {
    var state = Policy.State()
    _ = state.update(privacyMode: false, lockOnDisconnect: true, connectedDevices: 1,
                     consoleUnlocked: false, physicalScreens: 1, shuttingDown: false)
    let s2 = state.update(privacyMode: false, lockOnDisconnect: true, connectedDevices: 0,
                          consoleUnlocked: false, physicalScreens: 1, shuttingDown: false)
    same(s2.shouldLock, false, "already-locked console: does not lock again on disconnect")
    same(s2.logLines, [], "already-locked console: no lock log line")
}

do {
    var state = Policy.State()
    _ = state.update(privacyMode: true, lockOnDisconnect: false, connectedDevices: 1,
                     consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    let s2 = state.update(privacyMode: true, lockOnDisconnect: false, connectedDevices: 0,
                          consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    same(s2.shieldActive, false, "disconnect with lockOnDisconnect off: shield down")
    same(s2.shouldLock, false, "disconnect with lockOnDisconnect off: does not lock")
    same(s2.logLines, ["Privacy mode: restored the display."],
         "disconnect with lockOnDisconnect off: restores display only")
}

do {
    var state = Policy.State()
    _ = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                     consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    let quit = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                            consoleUnlocked: true, physicalScreens: 1, shuttingDown: true)
    same(quit.shieldActive, false, "shuttingDown while connected: shield down")
    same(quit.shouldLock, false, "shuttingDown while connected: does not lock")
    same(quit.logLines, ["Privacy mode: restored the display."], "shuttingDown while connected: restores display")
}

do {
    var state = Policy.State()
    _ = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 1,
                     consoleUnlocked: true, physicalScreens: 1, shuttingDown: false)
    let quit0 = state.update(privacyMode: true, lockOnDisconnect: true, connectedDevices: 0,
                             consoleUnlocked: true, physicalScreens: 1, shuttingDown: true)
    same(quit0.shieldActive, false, "shuttingDown at 0 devices: shield stays down")
    same(quit0.shouldLock, false, "shuttingDown at 0 devices: does not lock the Mac on Quit")
}

// MARK: 8. Copy strings

check(!Policy.Copy.sectionHeader.isEmpty, "section header")
check(!Policy.Copy.blankToggle.isEmpty, "blank toggle title")
check(!Policy.Copy.lockToggle.isEmpty, "lock toggle title")
check(!Policy.Copy.footnote.isEmpty, "footnote")

if failures > 0 {
    print("privacy-mode: \(failures) of \(checks) failed")
    exit(1)
}
print("privacy-mode: all \(checks) checks passed")
