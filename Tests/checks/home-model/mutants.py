"""H3 (step 4) home-model mutants: each must compile and make home-model/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "iOSClient/DiscoveryPolicy.swift"
S = "iOSClient/SavedMacs.swift"
W = "Sources/SillHost/PairingWindow.swift"
M = [
    ("the card's closed words say a tap is enough (as before the review)", F,
     "            \"That code no longer works. On the Mac, choose Pair iPhone or iPad\\u{2026} in the Sill menu, then tap \\(mac) again.\"",
     "            \"That code no longer works. Tap \\(mac) for a new one.\""),
    ("the card's stopped words say a tap is enough (as before the review)", F,
     "            \"\\(mac) stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad\\u{2026} in the Sill menu, then tap \\(mac) again.\"",
     "            \"\\(mac) stopped pairing after too many wrong codes. Tap \\(mac) for a new code.\""),
    ("an expired window quiets again", W, "case .cancelled, .stopped: return true\n        case .used, .expired, .withdrawn, .none: return false",
     "case .cancelled, .stopped, .expired: return true\n        case .used, .withdrawn, .none: return false"),
    ("homeRefusal: expired read as closed", F, "        case \"expired\"?: return .expired\n", ""),
    ("homeEnd: removed misspelt", F, "        if goodbye == \"removed\" { return .removed }", "        if goodbye == \"remove\" { return .removed }"),
    ("homeEnd: pairingRequired misspelt", F, "        if goodbye == \"pairingRequired\" { return .pairingRequired }", "        if goodbye == \"pairingrequired\" { return .pairingRequired }"),
    ("askAnswer: the cable's method misspelt", F, "guard method == \"cable\", askedCable", "guard method == \"usb\", askedCable"),
    ("askAnswer: shown misspelt", F, "        case \"shown\"?: return .shown", "        case \"show\"?: return .shown"),
    ("askAnswer: busy misspelt", F, "        case \"busy\"?: return .busy(", "        case \"Busy\"?: return .busy("),
    ("rowWord: a revoked Mac dialed pinned", F, "            if saved && !revoked && !newKey { return .method(method) }", "            if saved && !newKey { return .method(method) }"),
    ("homeDial: a homeTLS Mac dialed plain in DEBUG", F, "            return debug && !homeTLS ? .plain : .updateSill", "            return debug ? .plain : .updateSill"),
    ("adding forgets homeTLS", S, "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n", ""),
    ("seenOverTLS marks nothing", S, "            next.homeTLS = true\n            return next\n        }\n    }\n\n    /// `revoked`",
     "            return next\n        }\n    }\n\n    /// `revoked`"),
    ("revoking marks nothing", S, "            next.revoked = true\n", ""),
    # A Mac set up again with a new key (Noah, 2026-09-27).
    ("markingNewKey marks nothing", S, "            next.newKey = true\n", ""),
    ("markingNewKey marks again", S, "$0.macID == id && $0.newKey != true", "$0.macID == id"),
    ("replacingNewKey drops an unmarked Mac", S, "$0.macID == old && $0.newKey == true", "$0.macID == old"),
    ("replacingNewKey drops the Mac just paired", S, "        guard old != new, list.contains", "        guard list.contains"),
    ("replacingNewKey drops the marked Mac before the new one is saved", S, "        guard old != new, list.contains(where: { $0.macID == new }),", "        guard old != new,"),
    ("replacingNewKey keeps the marked Mac", S, "        return list.filter { $0.macID != old }", "        return list"),
    ("recognize: any tag names the first Mac", S, "        return list.first { mac in mac.recognitionKeyData.map { RecognitionTag.matches(tag, recognitionKey: $0) } ?? false }?.macID",
     "        return list.first?.macID"),
]
sys.exit(0 if module.mutate("home-model", M, sys.argv[1]) else 1)
