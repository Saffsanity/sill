"""H3 (step 1) record-field mutants (PairedDevice, SavedMac): each must compile and make home-records/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
H = "Sources/SillHost/HostIdentity.swift"
S = "iOSClient/SavedMacs.swift"
M = [
    ("cableDevice required (older lists no longer decode)", H, ["    package var cableDevice: String?\n", "        self.cableDevice = cableDevice\n"],
     ["    package var cableDevice: String\n", "        self.cableDevice = cableDevice ?? \"\"\n"]),
    ("the init drops cableDevice", H, "        self.cableDevice = cableDevice\n", ""),
    ("displayMethod: cable unknown", H, "        case PairResult.cable: return \"over the USB cable\"\n", ""),
    ("displayMethod: code worded as the QR code", H, "        case PairRequest.code: return \"with a code\"", "        case PairRequest.code: return \"with the QR code\""),
    ("displayMethod: an unknown method called a code", H, "        default: return nil\n        }\n    }", "        default: return \"with a code\"\n        }\n    }"),
    ("homeTLS required (older records no longer decode)", S, ["    var homeTLS: Bool?\n", "            next.homeTLS = nil\n"],
     ["    var homeTLS: Bool = false\n", "            next.homeTLS = false\n"]),
    ("revoked required", S, "    var revoked: Bool?\n", "    var revoked: Bool = false\n"),
    ("adding forgets homeTLS", S, "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n", ""),
    ("adding carries homeTLS from any Mac", S, "if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }",
     "if list.contains(where: { $0.homeTLS == true }) { mac.homeTLS = true }"),
    ("adding keeps revoked", S, "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n",
     "        if list.contains(where: { $0.macID == mac.macID && $0.homeTLS == true }) { mac.homeTLS = true }\n        if list.contains(where: { $0.macID == mac.macID && $0.revoked == true }) { mac.revoked = true }\n"),
    # Step 4.
    ("seenOverTLS marks every Mac", S, "            guard ids.contains(mac.macID) else { return mac }\n            var next = mac\n            next.homeTLS = true",
     "            var next = mac\n            next.homeTLS = true"),
    ("seenOverTLS reports a change that is none", S, "        guard list.contains(where: { ids.contains($0.macID) && $0.homeTLS != true }) else { return nil }",
     "        guard list.contains(where: { ids.contains($0.macID) }) else { return nil }"),
    ("revoking marks every Mac", S, "            guard mac.macID == id else { return mac }\n            var next = mac\n            next.revoked = true",
     "            var next = mac\n            next.revoked = true"),
    ("revoking twice", S, "        guard list.contains(where: { $0.macID == id && $0.revoked != true }) else { return nil }",
     "        guard list.contains(where: { $0.macID == id }) else { return nil }"),
    ("forgettingHomeTLS sets false", S, "            next.homeTLS = nil\n", "            next.homeTLS = false\n"),
    ("forgettingHomeTLS forgets nothing", S, "            next.homeTLS = nil\n", ""),
]
sys.exit(0 if module.mutate("home-records", M, sys.argv[1]) else 1)
