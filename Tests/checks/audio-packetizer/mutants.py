"""H3 (docs/audio-plan.md): each mutant changes Sources/SillHost/AudioPacketizer.swift in one place, is
compiled with the check (main.swift) and must fail it. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(WT, "Sources/SillHost/AudioPacketizer.swift")
MUTANTS = [
    # The packet size and the stamps
    ("512 for any multiple of 256", "frames > 0 && frames % 512 == 0 ? 512 : 480", "frames > 0 && frames % 256 == 0 ? 512 : 480"),
    ("the priming's sign", "hostTime: time(ofFrame: index * framesPerPacket - priming)", "hostTime: time(ofFrame: index * framesPerPacket + priming)"),
    ("no priming", "hostTime: time(ofFrame: index * framesPerPacket - priming)", "hostTime: time(ofFrame: index * framesPerPacket)"),
    ("every stamp from the first anchor", "for a in anchors.dropFirst() where a.frame <= frame { anchor = a }", ""),
    ("anchors pruned a block early", "while anchors.count >= 2, anchors[1].frame <= next {", "while anchors.count >= 2, anchors[1].frame <= next + framesPerPacket {"),
    # Continuity
    ("the tolerance half a chunk", "let tolerance = 0.25 * Double(frames) / sampleRate", "let tolerance = 0.5 * Double(frames) / sampleRate"),
    ("the tolerance a fifth of a chunk", "let tolerance = 0.25 * Double(frames) / sampleRate", "let tolerance = 0.2 * Double(frames) / sampleRate"),
    ("an early chunk is jitter", "if let expected, abs(chunk.hostTime - expected) <= tolerance {", "if let expected, chunk.hostTime - expected <= tolerance {"),
    ("the next chunk expected from the last expectation", "expected = chunk.hostTime + Double(frames) / sampleRate", "expected = (expected ?? chunk.hostTime) + Double(frames) / sampleRate"),
    # Gaps
    ("a gap that starts no segment", "            fifo.removeAll(keepingCapacity: true)\n            anchors.removeAll(keepingCapacity: true)\n            segmentFrames = 0\n            blocksMade = 0\n", ""),
    ("the tail kept across a gap", "            fifo.removeAll(keepingCapacity: true)\n            anchors.removeAll", "            anchors.removeAll"),
    ("zeros filled into a gap", "            fifo.removeAll(keepingCapacity: true)\n", "            fifo.append(contentsOf: [Float](repeating: 0, count: framesPerPacket * channels))\n"),
    ("a gap not counted", "            if expected != nil { gaps += 1 }\n", ""),
    ("the segment's first block not marked", "segmentStart: index == 0,", "segmentStart: false,"),
    ("another format taken", "chunk.channels == channels && chunk.sampleRate == sampleRate", "chunk.channels == channels"),
    # AudioSourceRule
    ("an ended stream never restarted", "case .ended: return now - lastStartAt >= retryInterval ? .start : .keep", "case .ended: return .keep"),
    ("an ended stream restarted at once", "case .ended: return now - lastStartAt >= retryInterval ? .start : .keep", "case .ended: return .start"),
    ("a running one restarted", "case .starting, .running: return .keep", "case .starting, .running: return .start"),
    ("the retry at 5 s", "static let retryInterval: TimeInterval = 10", "static let retryInterval: TimeInterval = 5"),
    ("an app told apart by its name", "case (.app(let p, _), .app(let q, _)): return p == q", "case (.app(let p, let n), .app(let q, let m)): return p == q && n == m"),
    ("an ended source kept when none is wanted", "if wanted == .none { return current == .none && phase == .idle ? .keep : .stop }", "if wanted == .none { return current == .none || phase == .ended ? .keep : .stop }"),
    # PCMLayout
    ("big endian taken", "guard formatID == linearPCM, channels >= 1, flags & flagIsBigEndian == 0 else { return nil }", "guard formatID == linearPCM, channels >= 1 else { return nil }"),
    ("the interleaved flag read backwards", "interleaved: flags & flagIsNonInterleaved == 0)", "interleaved: flags & flagIsNonInterleaved != 0)"),
    ("16-bit scaled by 32,767", "Int16.self)) / 32_768", "Int16.self)) / 32_767"),
    ("mono not doubled", "let right = channels >= 2 ? 1 : 0", "let right = 0"),
    # The tally
    ("silence not counted", "        if isSilent { silent += 1 }\n", ""),
    ("the tally's tolerance a whole buffer", "if off <= 0.25 * Double(frames) / sampleRate { worstJitter", "if off <= 1.5 * Double(frames) / sampleRate { worstJitter"),
]
orig = open(SRC).read()
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        path = os.path.join(t, "AudioPacketizer.swift")
        open(path, "w").write(orig.replace(old, new, 1))
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", path, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
