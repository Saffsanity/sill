"""Mutants of CameraStream.swift (iOSClient; docs/camera-plan.md §6.1 points 4 to 8, §6.2): each must compile and make
camera-stream/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "iOSClient/CameraStream.swift"
M = [
    # Encoders and epochs
    ("a picture generation 1 cannot carry is encoded", F, "guard let plan, let step, CameraCodec.validSide(width), CameraCodec.validSide(height) else { return [] }",
     "guard let plan, let step else { return [] }"),
    ("a new size keeps the encoder", F, "if encoderStale || encoder.map({ $0.width != width || $0.height != height }) ?? true {",
     "if encoderStale || encoder == nil {"),
    ("a new rate keeps the encoder", F, "if let was, was.fps != next.fps || was.position != next.position { encoderStale = true }",
     "if let was, was.position != next.position { encoderStale = true }"),
    ("a new camera keeps the encoder", F, "if let was, was.fps != next.fps || was.position != next.position { encoderStale = true }",
     "if let was, was.fps != next.fps { encoderStale = true }"),
    ("a new target bitrate makes a new encoder", F, "if let was, was.fps != next.fps || was.position != next.position { encoderStale = true }",
     "if let was, was.fps != next.fps || was.position != next.position || was.bitrate != next.bitrate { encoderStale = true }"),
    ("a stop keeps the encoder", F, "            encoder = nil\n            return [.noEncoder]", "            return [.noEncoder]"),
    ("a new target waits for the next encoder", F, "return encoder == nil ? [] : [.bitrate(s.current)]", "return []"),
    ("an encoder at the target, not the steps' bitrate", F, "out.append(.encoder(e, bitrate: step.current))", "out.append(.encoder(e, bitrate: plan.bitrate))"),
    ("an older encoder's frame goes", F, "guard let e = encoder, e.serial == serial, let plan else { return [] }", "guard let e = encoder, let plan else { return [] }"),
    ("epochs never go round", F, "nextEpoch = (nextEpoch + 1) % (CameraCodec.epochs.upperBound + 1)\n        seq = 0", "nextEpoch = nextEpoch + 1\n        seq = 0"),
    ("the numbers never move", F, "        seq &+= 1\n", "        seq &+= 0\n"),
    # The format before an epoch's first frame
    ("an epoch's frames without its format", F, "        if announced == nil {\n            guard keyframe", "        if false {\n            guard keyframe"),
    ("an epoch opened by a frame that is no keyframe", F, "guard keyframe, let ps = parameterSets?.encoded(), CameraCodec.validParameterSets(ps) else {",
     "guard let ps = parameterSets?.encoded(), CameraCodec.validParameterSets(ps) else {"),
    ("parameter sets outside generation 1 open an epoch", F, "guard keyframe, let ps = parameterSets?.encoded(), CameraCodec.validParameterSets(ps) else {",
     "guard keyframe, let ps = parameterSets?.encoded() else {"),
    ("the format says the front camera whatever is used", F, "CameraFormat(position: CameraCodec.position(plan.position),", "CameraFormat(position: CameraCodec.positionFront,"),
    ("the format without the encoder's bitrate", F, "parameterSets: ps, bitrate: step?.current)))", "parameterSets: ps, bitrate: nil)))"),
    ("new parameter sets keep the epoch", F, "        if keyframe, let ps = parameterSets?.encoded(), let was = announced, ps != was { openEpoch(owingKeyframe: false) }\n", ""),
    ("the same parameter sets open a new epoch", F, "let was = announced, ps != was { openEpoch(owingKeyframe: false) }",
     "let was = announced, ps == was || ps != was { openEpoch(owingKeyframe: false) }"),
    # Keyframes
    ("no keyframe at a new encoder", F, "        if owingKeyframe { keyframeOwed = true }\n", ""),
    ("new parameter sets owe another keyframe", F, "        if owingKeyframe { keyframeOwed = true }\n", "        keyframeOwed = true\n"),
    ("a skip forces a keyframe", F, "            second.skipped += 1\n            return out", "            second.skipped += 1\n            keyframeOwed = true\n            return out"),
    ("after a drop a frame that is no keyframe goes", F, "guard pacing.sends(keyframe: keyframe, fenced: fenced), keyframe || !awaitingKeyframe else {",
     "guard pacing.sends(keyframe: keyframe, fenced: fenced) else {"),
    ("a keyframe never ends the wait", F, "        if keyframe { awaitingKeyframe = false }\n", ""),
    ("a drop owes no keyframe", F, "        second.dropped += 1\n        keyframeOwed = true\n        awaitingKeyframe = true", "        second.dropped += 1\n        awaitingKeyframe = true"),
    ("asks honoured more than once a second", F,
     "        guard CameraPolicy.keyframe(newEpoch: false, demanded: true, lastDemandedAt: lastAskAt, droppedSince: false, at: now) else { return }\n", ""),
    ("an ask ignored", F, "        lastAskAt = now\n        keyframeOwed = true\n", "        lastAskAt = now\n"),
    ("a frame the link refused forces nothing", F, "        guard encoder != nil else { return }\n        dropped()\n", "        guard encoder != nil else { return }\n"),
    ("a refusal with no encoder counts", F, "        guard encoder != nil else { return }\n        dropped()\n", "        dropped()\n"),
    ("a failed encode forces nothing", F, "        guard encoder?.serial == serial else { return }\n        dropped()\n", "        guard encoder?.serial == serial else { return }\n"),
    ("another encoder's failure counts", F, "        guard encoder?.serial == serial else { return }\n        dropped()\n", "        dropped()\n"),
    # The budget and the cap
    ("the budget ignored", F, "guard pacing.encodes(fenced: uplink.fenced, unsent: uplink.unsent, takenLastSecond: uplink.takenLastSecond) else {",
     "guard !uplink.fenced else {"),
    ("a frame goes at a fence", F, "guard pacing.sends(keyframe: keyframe, fenced: fenced), keyframe", "guard pacing.sends(keyframe: keyframe, fenced: false), keyframe"),
    ("a frame past the cap goes", F, "guard data.count <= CameraFrame.maxDataBytes else {", "guard data.count <= CameraFrame.maxDataBytes + 1 else {"),
    ("a frame past the cap keeps the bitrate", F, "            s.second(dropped: true, at: now)\n", ""),
    ("an empty frame goes", F, "        guard !data.isEmpty else {\n            dropped()\n            return []\n        }\n", ""),
    # The bitrate's steps and a second's numbers
    ("the bitrate never steps down", F, "st.second(dropped: s.skipped + s.dropped > 0, at: now)", "st.second(dropped: false, at: now)"),
    ("a skip never steps it down", F, "st.second(dropped: s.skipped + s.dropped > 0, at: now)", "st.second(dropped: s.dropped > 0, at: now)"),
    ("a second's numbers never start again", F, "        let s = second\n        second = Second()\n", "        let s = second\n"),
    ("frames counted without their header", F, "second.bytes += CameraFrame.headerBytes + data.count", "second.bytes += data.count"),
]
sys.exit(0 if module.mutate("camera-stream", M, sys.argv[1]) else 1)
