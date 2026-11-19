"""Mutants of the microphone's wire and rules (Microphone.swift, MicrophonePolicy.swift, and kind 48's and kind
16's lines in StreamMessage.swift and HostSettings.swift): each copies Sources/StreamProtocol, applies one
mutation, compiles it with the check and expects it to fail.
usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
MP = "MicrophonePolicy.swift"
MW = "Microphone.swift"
MUTANTS = [
    # The wire.
    ("kind 48 as 250", "StreamMessage.swift", "case microphone = 48", "case microphone = 250"),
    ("the end as type 4", MW, "public static let typeEnd: UInt8 = 3", "public static let typeEnd: UInt8 = 4"),
    ("an end with bytes after it taken", MW, "return payload.count == 1 ? .end : nil", "return .end"),
    ("a format past the cap read", MW, "guard payload.count <= maxFormatPayload,\n", "guard payload.count <= maxFormatPayload + 1024,\n"),
    ("a format past the cap written", MW, "return d.count > 1 && d.count <= Self.maxFormatPayload ? d : nil", "return d.count > 1 ? d : nil"),
    ("two channels taken", MW, "if let v = f.channels, v != MicrophoneCodec.channels { return false }\n", ""),
    ("44.1 kHz taken", MW, "if let v = f.sampleRate, v != MicrophoneCodec.sampleRate { return false }\n", ""),
    ("an epoch without a cookie taken", MW, "&& f.primingFrames != nil && f.epoch != nil && f.cookie != nil", "&& f.primingFrames != nil && f.epoch != nil"),
    ("an empty cookie taken", MW, "public static let cookieBytes = 1...256", "public static let cookieBytes = 0...256"),
    ("the claim never written", MW, "try c.encodeIfPresent(claim, forKey: .claim)\n", ""),
    ("the pause never read", MW, "pause = try c.decodeIfPresent(String.self, forKey: .pause)", "pause = nil"),
    ("an unknown pause read as background", MW, "return Self.pauses.contains(pause) ? pause : Self.unavailable", "return Self.pauses.contains(pause) ? pause : Self.background"),
    ("256 packets written", MW, "guard (1...AudioPackets.maxCount).contains(p.packets.count),", "guard (1...300).contains(p.packets.count),"),
    ("packets stamped with nothing", MW, "StreamMessage(kind: .microphone, timestamp: captured,", "StreamMessage(kind: .microphone, timestamp: 0,"),
    ("the codec chosen in the device's order", MW, "return taken.first { makes.contains($0) }", "return makes.first { taken.contains($0) }"),
    ("a later state read as idle", "HostSettings.swift", "public var knownState: String { Self.states.contains(state) ? state : Self.off }", "public var knownState: String { Self.states.contains(state) ? state : Self.idle }"),
    ("offers taken while refused", "HostSettings.swift", "public var takesOffers: Bool { [Self.idle, Self.another, Self.inUse].contains(state) }", "public var takesOffers: Bool { [Self.idle, Self.another, Self.inUse, Self.refused].contains(state) }"),
    ("the list's microphone never kept", "Switcher.swift", "    public var microphone: Int?\n", "    public var microphone: Int? { get { nil } set {} }\n"),
    # The device.
    ("offers without the permission", MP, "d.switchOn && d.permission == .granted && macTakes(d)", "d.switchOn && macTakes(d)"),
    ("offers from a window not chosen", MP, "macTakes(d) && d.chosen && (d.state", "macTakes(d) && (d.state"),
    ("records in the background", MP, "        if !d.foreground { return MicrophoneFormat.background }\n", ""),
    ("records during a call", MP, "        if d.interrupted { return MicrophoneFormat.busy }\n", ""),
    ("records while idle", MP, "offers(d) && pause(d) == nil && d.state?.wanted == true && codec(d) != nil", "offers(d) && pause(d) == nil && codec(d) != nil"),
    ("kind 48 to a Mac that says 0", MP, "(d.list ?? 0) >= MicrophoneCodec.generation", "(d.list ?? 0) >= 0"),
    ("kind 48 to a locked Mac", MP, ">= MicrophoneCodec.generation && !d.locked", ">= MicrophoneCodec.generation"),
    ("no end when the switch goes off", MP, "if offered, !d.switchOn || d.permission == .denied {", "if false {"),
    ("an end at every step while inUse", MP, "} else if d.state?.wanted == true, !endedInUse {", "} else if d.state?.wanted == true {"),
    ("no end for an inUse it will not record", MP, "} else if d.state?.wanted == true, !endedInUse {", "} else if false {"),
    ("the claim never spent", MP, "return ([.format(MicrophoneFormat(claim: claimOwed ? true : nil, pause: pause))], claimOwed)", "return ([.format(MicrophoneFormat(claim: claimOwed ? true : nil, pause: pause))], false)"),
    ("the window used first", MP, "if (w.lastUsedAt ?? -.infinity) > (b.lastUsedAt ?? -.infinity) { best = w }", "if (w.lastUsedAt ?? -.infinity) < (b.lastUsedAt ?? -.infinity) { best = w }"),
    ("300 ms unsent", MP, "public static let maxUnsentSeconds = 0.2", "public static let maxUnsentSeconds = 0.3"),
    # The Mac.
    ("an unpaired session's offer taken", MP, "if !s.paired || s.key == nil { return .unpaired }", "if s.key == nil { return .unpaired }"),
    ("an offer without a claim takes it", MP, "if holder == nil || (f.claim == true && holder != key) {", "if holder != key {"),
    ("a claim ignored", MP, "if holder == nil || (f.claim == true && holder != key) {", "if holder == nil {"),
    ("the grace never over", MP, "guard let o = offers[key], let left = o.leftAt, now - left >= Self.grace else { continue }", "guard let o = offers[key], let left = o.leftAt, now - left >= Self.grace * 100 else { continue }"),
    ("wanted without an app", MP, "guard unlocked, refusal(id, at: now) == nil, appUses, let key", "guard unlocked, refusal(id, at: now) == nil, let key"),
    ("wanted while locked", MP, "guard unlocked, refusal(id, at: now) == nil, appUses, let key", "guard refusal(id, at: now) == nil, appUses, let key"),
    ("a state while locked", MP, "guard let s = sessions[id], unlocked else { return nil }", "guard let s = sessions[id] else { return nil }"),
    ("twice the sound a second", MP, "public static let maxSoundPerSecond = 1.5", "public static let maxSoundPerSecond = 3.0"),
    ("eleven offers a second", MP, "public static let maxOffersPerSecond = 10", "public static let maxOffersPerSecond = 11"),
    ("seven epochs a minute", MP, "public static let maxEpochsPerMinute = 6", "public static let maxEpochsPerMinute = 7"),
    ("refused for no time", MP, "sessions[id]?.refusedUntil = now + Self.refusedFor", "sessions[id]?.refusedUntil = now"),
    ("packets of any epoch", MP, "guard let s = sessions[id], s.epoch?.format.epoch == epoch else", "guard let s = sessions[id] else"),
    ("an end from any session of the device", MP, "guard let key = sessions[id]?.key, offers[key]?.session == id else { break }\n                out += withdraw(key, why: .stopped, at: now)", "guard let key = sessions[id]?.key else { break }\n                out += withdraw(key, why: .stopped, at: now)"),
    ("the oldest offer succeeds", MP, "if best == nil || o.since > best!.since", "if best == nil || o.since < best!.since"),
    ("no took-over line", MP, "                    out.append(.line(Copy.tookOver(name: o.name, from: p.name)))\n", ""),
    ("a removed device kept for the grace", MP, "                if offers[key] != nil { out += withdraw(key, why: .removed, at: now) }\n", ""),
    ("an old epoch kept", MP, "                if !wanted(id, at: now) { sessions[id]?.epoch = nil }\n", ""),
    ("the live line at every move", MP, "if liveSaid?.key != next.key || liveSaid?.epoch != next.epoch {", "if true {"),
    ("silent after 1 s", MP, "public static let silenceAfter: Double = 2", "public static let silenceAfter: Double = 1"),
    ("names not cleaned", MP, "sessions[id] = Session(key: key, paired: paired, name: Self.clean(name))", "sessions[id] = Session(key: key, paired: paired, name: name)"),
    ("the list says 1 with Sill Microphone not set up", MP, "public var advertised: Int { switchOn && ready ? MicrophoneCodec.generation : 0 }", "public var advertised: Int { switchOn ? MicrophoneCodec.generation : 0 }"),
    ("refusal lines every time", MP, "if r != .refused, now - (s.refusalLineAt[r] ?? -.infinity) >= Self.refusalLineSpacing {", "if r != .refused {"),
]
caught = 0
for name, file, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), src)
        path = os.path.join(src, file); text = open(path).read()
        if text.count(old) != 1:
            print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
        open(path, "w").write(text.replace(old, new, 1))
        files = [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.endswith(".swift")]
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *files, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
            code, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            code, out = -1, "FAIL timed out"
        failed = [l for l in out.splitlines() if l.startswith("FAIL")]
        if code != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
