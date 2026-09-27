"""H4 (docs/audio-plan.md): each mutant changes the encoder, the decoder or the test tone in one place, is
compiled with the check (main.swift) and must fail it. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
FILES = {
    "AudioEncoder.swift": "Sources/SillHost/AudioEncoder.swift",
    "AudioPacketizer.swift": "Sources/SillHost/AudioPacketizer.swift",
    "TestTone.swift": "Sources/SillHost/TestTone.swift",
    "AudioDecoder.swift": "iOSClient/AudioDecoder.swift",
}
MUTANTS = [
    ("the bitrate 64 kbps", "AudioEncoder.swift", "var rate = UInt32(bitrate)", "var rate = UInt32(64_000)"),
    ("512 frames whatever was asked", "AudioEncoder.swift", "out.mFramesPerPacket = UInt32(framesPerPacket)", "out.mFramesPerPacket = 512"),
    ("the priming read as 0", "AudioEncoder.swift", "self.priming = Int(prime.leadingFrames)", "self.priming = 0"),
    ("the encoder never reset", "AudioEncoder.swift", "        AudioConverterReset(converter)\n", "        _ = converter\n"),
    ("the decoder never reset", "AudioDecoder.swift", "        AudioConverterReset(converter)\n", "        _ = converter\n"),
    # AudioToolbox's ELD decoder takes the frame length from the cookie (the AudioSpecificConfig) when it
    # has one, and from the format without it: dropping either alone changes nothing (two equivalent
    # mutants, not here). Without both it no longer knows the stream.
    ("the decoder without its cookie, told 512 frames", "AudioDecoder.swift", "input.mFramesPerPacket = UInt32(framesPerPacket)",
     "input.mFramesPerPacket = 512; let cookie = Data()"),
    ("a frame short", "AudioDecoder.swift", "            let n = Int(frames)\n", "            let n = Int(frames) - 1\n"),
    ("the click 3 frames late", "TestTone.swift", "let wall = wallAtFrame0 + Double(k) / sampleRate", "let wall = wallAtFrame0 + Double(k - 3) / sampleRate"),
    ("stamps without the priming", "AudioPacketizer.swift", "hostTime: time(ofFrame: index * framesPerPacket - priming)", "hostTime: time(ofFrame: index * framesPerPacket)"),
]
caught = 0
for name, file, old, new in MUTANTS:
    text = open(os.path.join(WT, FILES[file])).read()
    if text.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        paths = []
        for f, rel in FILES.items():
            path = os.path.join(t, f)
            body = open(os.path.join(WT, rel)).read()
            open(path, "w").write(body.replace(old, new, 1) if f == file else body)
            paths.append(path)
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *paths, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:110] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
