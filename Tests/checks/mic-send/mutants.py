"""Mutants of the device's microphone sender and capture (iOSClient/MicrophoneSender.swift, MicrophoneCapture.swift):
each must compile and make mic-send/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
S = "iOSClient/MicrophoneSender.swift"
C = "iOSClient/MicrophoneCapture.swift"
M = [
    ("the epoch not advanced", S, "            epoch = (epoch + 1) & 0xFFFF\n", "            epoch = epoch & 0xFFFF\n"),
    ("the epoch never wraps", S, "            epoch = (epoch + 1) & 0xFFFF\n", "            epoch = epoch + 1\n"),
    ("the seq never counts", S, "            seq &+= 1\n", ""),
    ("the encoder reset at every block", S, "            if b.segmentStart { encoder.reset() }", "            encoder.reset()"),
    ("stamps on the host clock", S, "if first == nil { first = (seq, b.hostTime + wallOffset, b.segmentStart) }",
     "if first == nil { first = (seq, b.hostTime, b.segmentStart) }"),
    ("five packets a message at most", S, "    static let maxPacketsPerMessage = 40", "    static let maxPacketsPerMessage = 5"),
    ("the Mac's sound's bitrate", S, "bitrate: MicrophoneCodec.bitrate,\n", "bitrate: 128_000,\n"),
    ("a format kept when stopped", S, "        encoder = nil\n        packetizer = nil\n        format = nil\n", "        encoder = nil\n        packetizer = nil\n"),
    ("the first packet's flag on every message", S, "let message = AudioPackets(epoch: epoch, seq: f.seq, segmentStart: f.segmentStart, packets: packets)",
     "let message = AudioPackets(epoch: epoch, seq: f.seq, segmentStart: true, packets: packets)"),
    ("no conversion", C, "        if rate != Double(MicrophoneCodec.sampleRate) {", "        if false {"),
    ("the epoch's format never sent", C, "        if let m = MicrophoneMessage.message(.format(f), now: Date().timeIntervalSince1970) { onMessage?(m, .format) }\n", ""),
    ("the format kept after the stop", C, "        formatLock.withLock { currentFormat = nil }\n", ""),
    ("the tone's click 4 ms late", C, "            if into < clickFrames {", "            if into >= clickFrames, into < 2 * clickFrames {"),
    ("the tone at -20 dBFS", C, "let tone = pow(10, -30.0 / 20), click", "let tone = pow(10, -20.0 / 20), click"),
]
sys.exit(0 if module.mutate("mic-send", M, sys.argv[1]) else 1)
