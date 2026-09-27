"""H3 (step 4) home-model mutants: each must compile and make home-model/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "iOSClient/DiscoveryPolicy.swift"
S = "iOSClient/SavedMacs.swift"
M = [
    ("homeEnd: removed misspelt", F, "        if goodbye == \"removed\" { return .removed }", "        if goodbye == \"remove\" { return .removed }"),
    ("homeEnd: pairingRequired misspelt", F, "        if goodbye == \"pairingRequired\" { return .pairingRequired }", "        if goodbye == \"pairingrequired\" { return .pairingRequired }"),
    ("askAnswer: the cable's method misspelt", F, "guard method == \"cable\", askedCable", "guard method == \"usb\", askedCable"),
    ("askAnswer: shown misspelt", F, "        case \"shown\"?: return .shown", "        case \"show\"?: return .shown"),
    ("askAnswer: busy misspelt", F, "        case \"busy\"?: return .busy(", "        case \"Busy\"?: return .busy("),
    ("rowWord: a revoked Mac dialed pinned", F, "            if saved && !revoked { return .method(method) }", "            if saved { return .method(method) }"),
    ("homeDial: a homeTLS Mac dialed plain in DEBUG", F, "            return debug && !homeTLS ? .plain : .updateSill", "            return debug ? .plain : .updateSill"),
    ("adding forgets homeTLS", S, "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n", ""),
    ("seenOverTLS marks nothing", S, "            next.homeTLS = true\n            return next\n        }\n    }\n\n    /// `revoked`",
     "            return next\n        }\n    }\n\n    /// `revoked`"),
    ("revoking marks nothing", S, "            next.revoked = true\n", ""),
    ("recognize: any tag names the first Mac", S, "        return list.first { mac in mac.recognitionKeyData.map { RecognitionTag.matches(tag, recognitionKey: $0) } ?? false }?.macID",
     "        return list.first?.macID"),
]
sys.exit(0 if module.mutate("home-model", M, sys.argv[1]) else 1)
