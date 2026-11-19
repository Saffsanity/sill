"""Mutants of the device's rules for recording the stream (#284): RecordingPolicy.swift, RecordingClock.swift (with its
RecordingTimeline) and RecordedSound.swift, in iOSClient. Each changes one of them in one place, is compiled with the
check as one module (../module.py) and must make the check fail. The check stops before its random recordings when a
case above them already failed (SILL_CHECK_STOP_EARLY), so most mutants take a compile.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import module

os.environ["SILL_CHECK_STOP_EARLY"] = "1"
R = "iOSClient/RecordingPolicy.swift"
C = "iOSClient/RecordingClock.swift"
S = "iOSClient/RecordedSound.swift"
M = [
    # Rule 1: offered.
    ("the count from 4", R, "    static let countFrom = 3\n", "    static let countFrom = 4\n"),
    ("the start's floor 1 GB", R, "static let startFloor: Int64 = 1_500_000_000", "static let startFloor: Int64 = 1_000_000_000"),
    ("Start's floor not reached at it", R, "return free >= startFloor", "return free > startFloor"),
    ("space unknown refuses", R, "        guard let free = freeBytes else { return true }", "        guard let free = freeBytes else { return false }"),
    ("Cancel reads Stop", R, "        case .counting: return .cancel", "        case .counting: return .stop"),
    ("Start without a session", R, "            guard connected else { return .startDimmed(.notConnected) }\n", ""),
    ("Start before the picture", R, "            guard streaming, pictureCame else", "            guard streaming else"),
    ("Record Sound on without Send Audio's word", R, "return sendAudio == true ? .shown : .dimmed", "return sendAudio != false ? .shown : .dimmed"),
    ("sound with either", R, "        switchOn && sendAudio == true", "        switchOn || sendAudio == true"),
    # Rule 2: the count and the asks.
    ("a fourth step to the count", R, "guard elapsed >= 0, elapsed < countFrom else", "guard elapsed >= 0, elapsed <= countFrom else"),
    ("the Mac's spacing 2 s", R, "    static let hostSpacing: TimeInterval = 1\n", "    static let hostSpacing: TimeInterval = 2\n"),
    ("the spacing's edge held", R, "now >= last, now < last + hostSpacing { return .at(", "now >= last, now <= last + hostSpacing { return .at("),
    ("a clock gone back holds the ask", R, "if let last = lastAsk, now >= last, now < last + hostSpacing", "if let last = lastAsk, now < last + hostSpacing"),
    ("the recovery never awaited", R, "        if let due = recoveryDueUntil, now < due { return .awaitRecovery }\n", ""),
    ("the recovery awaited at its end", R, "if let due = recoveryDueUntil, now < due {", "if let due = recoveryDueUntil, now <= due {"),
    ("two asks while Starting…", R, "    static let startAsks = 3\n", "    static let startAsks = 2\n"),
    ("a fourth ask", R, "        if asks < startAsks {", "        if asks <= startAsks {"),
    ("give up after 20 s", R, "    static let startGiveUp: TimeInterval = 10\n", "    static let startGiveUp: TimeInterval = 20\n"),
    ("give up a moment late", R, "        guard now < end else { return .giveUp }", "        guard now <= end else { return .giveUp }"),
    ("an ask due at the give-up made", R, "            if due < end { return .askAt(due) }", "            if due <= end { return .askAt(due) }"),
    ("an overdue ask scheduled in the past", R, "let due = max((lastAsk ?? now) + wait, now)", "let due = (lastAsk ?? now) + wait"),
    # Rule 3: where the movie starts.
    ("the pre-roll ignored", R, "        if keyframeSinceAsk { return .atLight(.sinceAsk) }\n", ""),
    ("the last keyframe with a frame since", R, "if lastKeyframeKept, framesSinceKeyframe == 0 {", "if lastKeyframeKept, framesSinceKeyframe <= 1 {"),
    ("the pre-roll's limit 16 MB", R, "    static let prerollLimit = 32 << 20\n", "    static let prerollLimit = 16 << 20\n"),
    ("the pending bound 16 MB", R, "    static let pendingLimit = 32 << 20\n", "    static let pendingLimit = 16 << 20\n"),
    ("the pre-roll keeps old chains", R, "                // Only the newest keyframe's chain is of use: the light's picture is decoded from it.\n                frames = []\n", ""),
    ("the pre-roll's limit never reached", R, "            guard bytes + size <= limit else {", "            guard bytes + size < limit else {"),
    ("new sets keep the pre-roll", R, "        mutating func newSource() {\n            frames = []\n            bytes = 0\n            waiting = true\n",
     "        mutating func newSource() {\n"),
    # Rule 5: the chain.
    ("a frame delivered twice is written", R, "            if recentStamps.contains(stamp) { return .duplicate }\n", ""),
    ("every loss asks", R, "            defer { whole = false }\n            return whole", "            defer { whole = false }\n            return true"),
    ("one stamp remembered", R, "        static let stampsKept = 8\n", "        static let stampsKept = 1\n"),
    # Rule 6: parts and names.
    ("the same sets end a part", R, "        return current != incoming", "        return true"),
    ("parts named from 1", R, "        var n = max(part, 1)", "        var n = 1"),
    ("12-hour single digits", R, 'at \\(two(c.hour)).', 'at \\(c.hour ?? 0).'),
    ("fragments every 8 s", R, "    static let fragmentInterval: TimeInterval = 4\n", "    static let fragmentInterval: TimeInterval = 8\n"),
    # Rule 8: what ends it.
    ("Picture in Picture goes on", R, "case .appToBackground, .sceneToBackground, .pictureInPicture: return .leftScreen",
     "case .appToBackground, .sceneToBackground: return .leftScreen\n        case .pictureInPicture: return nil"),
    ("a new size ends it", R, "case .move, .macLocked, .otherUser, .newSize,", "case .newSize: return .stop\n        case .move, .macLocked, .otherUser,"),
    # Rule 9: space.
    ("the stop's floor 500 MB", R, "    static let stopFloor: Int64 = 1_000_000_000\n", "    static let stopFloor: Int64 = 500_000_000\n"),
    ("the warning's floor 2 GB", R, "    static let warnFloor: Int64 = 3_000_000_000\n", "    static let warnFloor: Int64 = 2_000_000_000\n"),
    ("the warning at 3 minutes", R, "    static let warnMinutes = 5.0\n", "    static let warnMinutes = 3.0\n"),
    ("a stop at the floor itself", R, "        guard freeBytes >= stopFloor else { return .stop }", "        guard freeBytes > stopFloor else { return .stop }"),
    ("low only when both", R, "guard freeBytes < warnFloor || minutes < warnMinutes else", "guard freeBytes < warnFloor && minutes < warnMinutes else"),
    ("0 minutes left", R, "min(max(shown, 1), mostMinutes)", "min(shown, mostMinutes)"),
    ("minutes rounded up", R, "Int(minutes.rounded(.down))", "Int(minutes.rounded())"),
    ("the rate's window 10 s back included", R, "samples.filter { $0.time > now - rateWindow", "samples.filter { $0.time >= now - rateWindow"),
    # Rule 10: the light.
    ("no container share", R, "        return frames + sound + Int64(Double(frames) * containerShare)", "        return frames + sound"),
    ("an hour as 60:00", R, "return s >= 3600 ?", "return s > 3600 ?"),
    ("1000 MB", R, "        if mb < 1000 { return \"\\(mb) MB\" }", "        if mb <= 1000 { return \"\\(mb) MB\" }"),
    ("every note says one movie", R, 'return movies == 1 ? "Saved to \\(folder)."', 'return movies >= 1 ? "Saved to \\(folder)."'),
    # Rule 11: the Mac is told.
    ("false sent", R, "    static func recordingField(_ reports: Bool) -> Bool? { reports ? true : nil }",
     "    static func recordingField(_ reports: Bool) -> Bool? { reports }"),
    ("the finish not reported", R, "        case .starting, .recording, .finishing: return true", "        case .starting, .recording: return true\n        case .finishing: return false"),
    ("0.5.1 takes asks", R, "            if a != b { return a > b }\n        }\n        return false", "            if a != b { return a > b }\n        }\n        return true"),
    # Rule 4: the clock.
    ("the floor over 5 s", C, "    static let floorWindow = 10\n", "    static let floorWindow = 5\n"),
    ("a step after two", C, "    static let stepFrames = 3\n", "    static let stepFrames = 2\n"),
    ("a step past 2 s", C, "    static let stepLimit: Double = 1\n", "    static let stepLimit: Double = 2\n"),
    ("no step forward", C, "if above >= Self.stepFrames || floor - d > Self.stepLimit, let last {", "if above >= Self.stepFrames, let last {"),
    ("no step back", C, "if above >= Self.stepFrames || floor - d > Self.stepLimit, let last {", "if floor - d > Self.stepLimit, let last {"),
    ("a step goes on from the last at once", C, "correction = last.mac + max(0, arrival - last.arrival) - stamp", "correction = last.mac - stamp"),
    ("the floor kept across a step", C, "                buckets = []\n                self.floor = nil\n", ""),
    ("pictures before the last written", C, "        if let written = lastWritten, t < written + Self.tick { t = written + Self.tick }\n", ""),
    ("the light without the floor", C, "        let at = arrival - floor + correction\n", "        let at = arrival + correction\n"),
    ("a keyframe's anchor without the correction", C, "        anchor = stamp + correction\n    }", "        anchor = stamp\n    }"),
    ("the stop before the last picture", C, "        return max(at, written + Self.tick)", "        return at"),
    ("the stop without the correction", C, "            mac = arrival - floor + correction\n", "            mac = arrival - floor\n"),
    ("the sound without the correction", C, "        return stamp + correction - anchor\n", "        return stamp - anchor\n"),
    # The timeline.
    ("no ask after a picture not written", C, "        chain.lost() ? [.askKeyframe] : []", "        chain.lost() ? [] : []"),
    ("a later part's 0:00 at the first's", C, "            actions += openPart(at: t)\n", "            actions += openPart(at: 0)\n"),
    ("the sound left behind the picture", C, "            let writes = sound!.follow(picture: t - partStart)\n", "            let writes: [RecordedSound.Write] = []\n"),
    ("a delta sets the movie's 0:00", C, "            guard isKeyframe, sets != nil else {\n                clock.seed(", "            guard sets != nil else {\n                clock.seed("),
    # Not a mutant: `chain.restart()` at a part's close is unobservable, since only a keyframe opens a part (take's
    # guard), so a delta between parts is dropped either way.
    ("the last keyframe at its stamp's time", C, "            actions.append(.picture(id: k.id, at: 0))", "            actions.append(.picture(id: k.id, at: clock.place(clock.seed(stamp: k.stamp, arrival: k.arrival), arrival: k.arrival)))"),
    # Rule 7: the sound.
    ("the drift limit 40 ms", S, "    static let driftLimit = 0.020\n", "    static let driftLimit = 0.040\n"),
    ("the sound's lag 1 s", S, "    static let soundLag = 0.5\n", "    static let soundLag = 1.0\n"),
    ("fades of 10 ms", S, "    static let fadeFrames = 240\n", "    static let fadeFrames = 480\n"),
    ("duplicates played", S, "        guard !seen.contains(key) else { return (.skip, []) }\n", ""),
    ("16 packets remembered", S, "    static let dedupeCount = 256\n", "    static let dedupeCount = 16\n"),
    ("the priming played", S, "            from = min(max(format.primingFrames, 0), fpp)\n", "            from = 0\n"),
    ("a segment placed without its priming", S, "            position = RecordingClock.frames(time) + Int64(from)\n", "            position = RecordingClock.frames(time)\n"),
    ("every next seq follows", S, "               abs(Double(position - last.end)) <= Self.driftLimit * Double(Self.rate) {", "               true {"),
    ("a join played", S, "        guard start || follows else {", "        guard start || follows || true else {"),
    ("no fade in after a trim", S, "            count -= overlap\n            fadeIn = true\n", "            count -= overlap\n"),
    ("the tail never faded before a jump", S, "            writes.append(.tail(fadeOut: byStamp || position != end))", "            writes.append(.tail(fadeOut: false))"),
    ("the tail never faded before silence", S, "            writes.append(.tail(fadeOut: true))\n            held = 0\n        }\n        writes.append(.silence(",
     "            writes.append(.tail(fadeOut: false))\n            held = 0\n        }\n        writes.append(.silence("),
    ("no silence to the stop", S, "        var writes = fill(to: RecordingClock.frames(time))\n", "        var writes: [Write] = []\n"),
]
sys.exit(0 if module.mutate("recording", M, sys.argv[1]) else 1)
