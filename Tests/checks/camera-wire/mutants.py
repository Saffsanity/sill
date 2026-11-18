"""Mutants of kind 46's wire (Camera.swift, kind 16's CameraState in HostSettings.swift): each copies
Sources/StreamProtocol, applies one mutation, compiles it with the check and expects it to fail.
usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    # The caps, at their edges.
    ("a format at the cap dropped", "Camera.swift", "guard payload.count <= maxFormatPayload,", "guard payload.count < maxFormatPayload,"),
    ("a demand at the cap dropped", "Camera.swift", "guard payload.count <= maxDemandPayload,", "guard payload.count < maxDemandPayload,"),
    ("a frame past the cap read", "Camera.swift", "guard payload.count <= maxFramePayload, payload.count > CameraFrame.headerBytes", "guard payload.count > CameraFrame.headerBytes"),
    ("a frame without data read", "Camera.swift", "payload.count > CameraFrame.headerBytes else", "payload.count >= CameraFrame.headerBytes else"),
    ("a frame's data cap one byte larger", "Camera.swift", "public static let maxDataBytes = 262_144", "public static let maxDataBytes = 262_145"),
    ("a format written past the cap", "Camera.swift", "return d.count <= Self.maxFormatPayload ? d : nil", "return d"),
    ("a demand written past the cap", "Camera.swift", "return d.count <= Self.maxDemandPayload ? d : nil", "return d"),
    # Refused, never cut.
    ("a frame of too much data cut", "Camera.swift", "guard !data.isEmpty, data.count <= Self.maxDataBytes, CameraCodec.epochs.contains(epoch) else { return nil }", "guard !data.isEmpty, CameraCodec.epochs.contains(epoch) else { return nil }"),
    ("a frame without data written", "Camera.swift", "guard !data.isEmpty, data.count <= Self.maxDataBytes,", "guard data.count <= Self.maxDataBytes,"),
    ("an epoch past 65,535 wrapped", "Camera.swift", "d.appendBigEndian(UInt16(epoch))", "d.appendBigEndian(UInt16(truncatingIfNeeded: epoch))"),
    ("a format written outside its bounds", "Camera.swift", "        case .format(let f):\n            guard f.isValid else { return nil }\n", "        case .format(let f):\n"),
    ("a demand written outside its bounds", "Camera.swift", "        case .demand(let r):\n            guard r.isValid else { return nil }\n", "        case .demand(let r):\n"),
    # The layout.
    ("the epoch read a byte late", "Camera.swift", "let epoch = Int(d.readBigEndian(UInt16.self, at: 1))", "let epoch = Int(d.readBigEndian(UInt16.self, at: 2))"),
    ("the seq read as the epoch's", "Camera.swift", "let seq = d.readBigEndian(UInt32.self, at: 3)", "let seq = UInt32(d.readBigEndian(UInt16.self, at: 1))"),
    ("the header two bytes short", "Camera.swift", "public static let headerBytes = 7", "public static let headerBytes = 5"),
    ("a frame's keyframe flag lost", "Camera.swift", "return StreamMessage(kind: .camera, timestamp: captured, isKeyframe: keyframe, payload: payload)", "return StreamMessage(kind: .camera, timestamp: captured, isKeyframe: false, payload: payload)"),
    ("a frame stamped when written", "Camera.swift", "return StreamMessage(kind: .camera, timestamp: captured, isKeyframe: keyframe, payload: payload)", "return StreamMessage(kind: .camera, timestamp: Date().timeIntervalSince1970, isKeyframe: keyframe, payload: payload)"),
    ("a frame through message()", "Camera.swift", "        if case .frame = m { return nil }   // a frame carries its capture time: `frameMessage`\n", ""),
    ("type 3 read as a format", "Camera.swift", "    public static let typeDemand: UInt8 = 3", "    public static let typeDemand: UInt8 = 4"),
    # The bounds.
    ("odd sides taken", "Camera.swift", "sides.contains(v) && v % 2 == 0", "sides.contains(v)"),
    ("a side of 1922 taken", "Camera.swift", "public static let sides = 16...1920", "public static let sides = 16...1922"),
    ("a side of 14 taken", "Camera.swift", "public static let sides = 16...1920", "public static let sides = 14...1920"),
    ("0 fps taken", "Camera.swift", "public static let rates = 1...30", "public static let rates = 0...30"),
    ("60 fps taken", "Camera.swift", "public static let rates = 1...30", "public static let rates = 1...60"),
    ("a format's fps unchecked", "Camera.swift", "        if let fps, !CameraCodec.rates.contains(fps) { return false }\n        if let epoch,", "        if let epoch,"),
    ("a format's epoch unchecked", "Camera.swift", "        if let epoch, !CameraCodec.epochs.contains(epoch) { return false }\n", ""),
    ("a format's bitrate unchecked", "Camera.swift", "        if let bitrate, !CameraCodec.bitrates.contains(bitrate) { return false }\n        guard let codec", "        guard let codec"),
    ("a demand's token may be negative", "Camera.swift", "        if let token, token < 0 { return false }\n", ""),
    ("a demand's ceiling unchecked", "Camera.swift", "        if let maxBitrate, !CameraCodec.bitrates.contains(maxBitrate) { return false }\n", ""),
    ("a demand read outside its bounds", "Camera.swift", "let r = Wire.decode(CameraDemand.self, from: Data(payload.dropFirst())), r.isValid else { return nil }", "let r = Wire.decode(CameraDemand.self, from: Data(payload.dropFirst())) else { return nil }"),
    ("a format read outside its bounds", "Camera.swift", "let f = Wire.decode(CameraFormat.self, from: Data(payload.dropFirst())), f.isValid else { return nil }", "let f = Wire.decode(CameraFormat.self, from: Data(payload.dropFirst())) else { return nil }"),
    # An epoch whole.
    ("any codec an epoch", "Camera.swift", "return codec == CameraCodec.hevc && width != nil", "return width != nil"),
    ("an epoch without its parameter sets", "Camera.swift", "&& epoch != nil && parameterSets != nil", "&& epoch != nil"),
    ("an epoch without its rate", "Camera.swift", "height != nil && fps != nil && epoch != nil", "height != nil && epoch != nil"),
    ("two parameter sets taken", "Camera.swift", "(3...16).contains(p.sets.count)", "(2...16).contains(p.sets.count)"),
    ("seventeen parameter sets taken", "Camera.swift", "(3...16).contains(p.sets.count)", "(3...17).contains(p.sets.count)"),
    ("a NAL length of 3 taken", "Camera.swift", "[1, 2, 4].contains(p.nalUnitHeaderLength)", "(1...4).contains(p.nalUnitHeaderLength)"),
    ("an empty parameter set taken", "Camera.swift", " && p.sets.allSatisfy { !$0.isEmpty }", ""),
    ("bytes after the sets taken", "Camera.swift", "\n            && p.encoded() == d", ""),
    ("1,025 bytes of sets taken", "Camera.swift", "public static let maxParameterSetBytes = 1024", "public static let maxParameterSetBytes = 1025"),
    # How this build reads strings.
    ("a later pause read as itself", "Camera.swift", "return Self.pauses.contains(pause) ? pause : Self.unavailable", "return pause"),
    ("a later pause read as waiting", "Camera.swift", "return Self.pauses.contains(pause) ? pause : Self.unavailable", "return Self.pauses.contains(pause) ? pause : Self.waiting"),
    ("thermal left out of the pauses", "Camera.swift", "busy, scanner, thermal, denied, unavailable]", "busy, scanner, denied, unavailable]"),
    ("any position but front the back", "Camera.swift", "raw == positionBack ? positionBack : positionFront", "raw == positionFront || raw == nil ? positionFront : positionBack"),
    ("a later state read as idle", "HostSettings.swift", "public var knownState: String { Self.states.contains(state) ? state : Self.off }", "public var knownState: String { Self.states.contains(state) ? state : Self.idle }"),
    ("wanted while idle too", "HostSettings.swift", "public var wanted: Bool { state == Self.inUse }", "public var wanted: Bool { state == Self.inUse || state == Self.idle }"),
    ("kind 46 as 253", "StreamMessage.swift", "    case camera = 46 ", "    case camera = 253 "),
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
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
