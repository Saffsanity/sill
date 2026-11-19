"""CameraHostPolicy mutants (Sources/SillHost/CameraHostPolicy.swift): each must compile and make
camera-host/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/CameraHostPolicy.swift"
T = "Sources/SillHost/CameraTestHook.swift"
M = [
    # Who may.
    ("refusal: a locked Mac takes the camera", F, "        if !unlocked { return .locked }\n", ""),
    ("refusal: an unpaired key takes it", F, "        if !s.paired || s.key == nil { return .unpaired }", "        if s.key == nil { return .unpaired }"),
    ("refusal: the switch off takes it", F, "        if !switchOn { return .off }\n", ""),
    ("refusal: a refusal's line every time", F, "        if now - (s.refusalLineAt[r] ?? -.infinity) >= Self.refusalLineSpacing {", "        if now - (s.refusalLineAt[r] ?? -.infinity) >= 0 {"),
    # The holder.
    ("a claim takes nothing from a holder", F, "        if f.claim == true, holder != key {", "        if f.claim == true, holder == nil {"),
    ("an offer takes the camera from its holder", F, "        } else if holder == nil {\n            holder = key\n        }", "        } else {\n            holder = key\n        }"),
    ("a holder kept without its offer", F, "        if let h = holder, offers[h] == nil { holder = nil }\n", ""),
    ("a freed camera to the oldest offer", F, "                .max { ($0.value.since, $0.key) < ($1.value.since, $1.key) }", "                .min { ($0.value.since, $0.key) < ($1.value.since, $1.key) }"),
    ("a claim never refreshes the offer's place", F, "            if f.claim == true { o.since = now }\n", ""),
    ("the grace three times as long", F, "        if let left = o.leftAt { return now - left < Self.grace }", "        if let left = o.leftAt { return now - left < Self.grace * 3 }"),
    ("an offer stands for ever once the camera is back", F, "        return o.said >= availableSince || now - availableSince < Self.grace", "        return true"),
    # Wanted, kind 16, the demand.
    ("wanted without an app", F, "        guard refusal(id) == nil, app != nil, let key", "        guard refusal(id) == nil, let key"),
    ("another said as idle", F, "        if let h = holder, h != s.key { return CameraState(state: CameraState.another, holder: holderName) }\n", ""),
    ("inUse without the app's name", F, "        if wanted(id) { return CameraState(state: CameraState.inUse, app: app?.name) }", "        if wanted(id) { return CameraState(state: CameraState.inUse) }"),
    ("no keyframe when wanted anew", F, "            if w { sendDemand(id, keyframe: !(sessions[id]?.wasWanted ?? false), at: now, into: &out) }", "            if w { sendDemand(id, keyframe: false, at: now, into: &out) }"),
    ("a size change asks nothing", F, "        guard keyframe || s.demand != d else { return }", "        guard keyframe else { return }"),
    ("a demand to a device that reads none", F, "        guard s.reads else { return }\n        token += 1", "        token += 1"),
    ("away at the home size", F, "        if s.away, w > Self.awayMaxWidth || h > Self.awayMaxHeight {", "        if false, w > Self.awayMaxWidth || h > Self.awayMaxHeight {"),
    ("away at the home bitrate", F, "        let ceiling = s.away ? min(Self.awayMaxBitrate, Self.homeBitrate(width: w, height: h, fps: fps)) : Self.homeBitrate(width: w, height: h, fps: fps)",
     "        let ceiling = Self.homeBitrate(width: w, height: h, fps: fps)"),
    ("the app's rate past 30", F, "        let fps = min(max(a.fps, CameraCodec.rates.lowerBound), CameraCodec.rates.upperBound)", "        let fps = a.fps"),
    ("a keyframe asked at every failed decode", F, "now - (keyframeAskedAt[key] ?? -.infinity) >= Self.keyframeSpacing {", "now - (keyframeAskedAt[key] ?? -.infinity) >= 0 {"),
    # Epochs, frames and rates.
    ("an old epoch kept when no longer wanted", F, "                if sessions[id]?.wasWanted == true { sessions[id]?.epoch = nil }\n", ""),
    ("frames of any epoch", F, "        guard sessions[id]?.epoch?.epoch == epoch else { return (false, [.count(\"cam.dropped.epoch\")]) }\n", ""),
    ("frames from a session not wanted", F, "        guard wanted(id) else { return (false, [.count(\"cam.dropped.notWanted\")]) }\n", ""),
    ("no frame rate", F, "        guard countWithinRate(id, frames: true, at: now) else { return (false, [.count(\"cam.dropped.rate\")]) }\n", ""),
    ("59 frames a second", F, "ok = s.framesThisSecond <= Self.maxFramesPerSecond", "ok = s.framesThisSecond < Self.maxFramesPerSecond"),
    ("no format rate", F, "        guard countWithinRate(id, frames: false, at: now) else { out.append(.count(\"cam.dropped.rate\")); return }\n", ""),
    # What Sill Camera shows; the bitrates.
    ("the device shown while locked", F, "        let f: Feed = !available ? .unavailable :", "        let f: Feed = !switchOn ? .unavailable :"),
    ("a pause not shown", F, "holder.map { .device(name: name(ofKey: $0), pause: offers[$0]?.pause) } ?? .waiting", "holder.map { .device(name: name(ofKey: $0), pause: nil) } ?? .waiting"),
    ("1080p at the 720p rate", F, "        return min(4_000_000, max(300_000, Int(rate.rounded())))", "        return min(2_500_000, max(300_000, Int(rate.rounded())))"),
    # The TEST ONLY hook.
    ("the hook taken by any host", T, "        guard testHost else { return (nil, \"\\(variable) ignored: only a --synthetic test host takes it, never Sill.app.\") }\n", ""),
    ("odd sides in a script", T, "guard w >= 16, w <= 1920, w % 2 == 0, h >= 16, h <= 1920, h % 2 == 0 else { return nil }", "guard w >= 16, w <= 1920, h >= 16, h <= 1920 else { return nil }"),
    ("a script in the order written", T, "        return steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\\.element)", "        return steps"),
]
sys.exit(0 if module.mutate("camera-host", M, sys.argv[1]) else 1)
