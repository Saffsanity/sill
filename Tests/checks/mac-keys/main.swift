import AppKit

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; print("FAIL \(what())") }
}

// The client's keycode → usage is the host's usage → keycode, turned round, and both are whole.
let host = KeyStrokes.virtualKeys
let client = MacKeyMap.hidUsages
check(client.count == host.count, "the client knows \(client.count) keys, the host \(host.count)")
for (keyCode, usage) in client {
    check(host[usage] == keyCode, "keycode \(keyCode) goes as usage \(usage), which the host posts as \(host[usage].map(String.init) ?? "nothing")")
}
for (usage, keyCode) in host {
    check(client[keyCode] == usage, "the host posts usage \(usage) as keycode \(keyCode), which the client sends as \(client[keyCode].map(String.init) ?? "nothing")")
}
check(Set(client.values).count == client.count, "two keycodes share a usage")

// A modifier key's flag is the one the host holds while that key is down.
let hostFlag: [UInt64: NSEvent.ModifierFlags] = [KeyStrokes.control: .control, KeyStrokes.shift: .shift,
                                                 KeyStrokes.option: .option, KeyStrokes.command: .command]
for (keyCode, flag) in MacKeyMap.modifierFlag {
    guard let usage = client[keyCode] else { check(false, "modifier keycode \(keyCode) has no usage"); continue }
    if flag == .capsLock { check(usage == 0x39, "caps lock's keycode \(keyCode) goes as \(usage)"); continue }
    let held = KeyStrokes.modifierKeys[usage].flatMap { hostFlag[$0] }
    check(held == flag, "modifier keycode \(keyCode): the client reads \(flag.rawValue), the host holds \(held?.rawValue ?? 0)")
}
for (usage, _) in KeyStrokes.modifierKeys {
    let keyCode = host[usage]!
    check(MacKeyMap.modifierFlag[keyCode] != nil, "the host's modifier usage \(usage) (keycode \(keyCode)) is no modifier here")
}

// The wire's modifier bits: what the host turns into its flags, and nothing more.
let all: [NSEvent.ModifierFlags] = [.capsLock, .shift, .control, .option, .command, .function, .numericPad, .help]
for mask in 0..<(1 << all.count) {
    var flags: NSEvent.ModifierFlags = []
    for (i, f) in all.enumerated() where mask & (1 << i) != 0 { flags.insert(f) }
    let wire = MacKeyMap.wireModifiers(flags)
    var expected: UInt64 = 0
    if flags.contains(.capsLock) { expected |= KeyStrokes.capsLock }
    if flags.contains(.shift) { expected |= KeyStrokes.shift }
    if flags.contains(.control) { expected |= KeyStrokes.control }
    if flags.contains(.option) { expected |= KeyStrokes.option }
    if flags.contains(.command) { expected |= KeyStrokes.command }
    check(KeyStrokes.flags(fromDevice: wire) == expected, "flags \(flags.rawValue): the host reads \(KeyStrokes.flags(fromDevice: wire)), not \(expected)")
    check(wire & ~UInt64(0x1F_0000) == 0, "flags \(flags.rawValue) send bits beyond the five: \(String(wire, radix: 16))")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
