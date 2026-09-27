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
    # Require pairing's stored record, off only signed by this Mac's key (the security review, 2026-09-27).
    ("require pairing: a plain \"0\" reads off (as before the review)", H,
     "        guard let text = String(data: data, encoding: .utf8), text.hasPrefix(\"0.\"),",
     "        if data == Data(\"0\".utf8) { return false }\n        guard let text = String(data: data, encoding: .utf8), text.hasPrefix(\"0.\"),"),
    ("require pairing: any signature reads off", H, "        return !verify(offMessage(macID: macID), signature)\n", "        return false\n"),
    ("require pairing: the off message does not name the Mac", H,
     "    static func offMessage(macID: String) -> Data { Data(\"sill-require-pairing-off-v1\\n\\(macID)\".utf8) }",
     "    static func offMessage(macID: String) -> Data { Data(\"sill-require-pairing-off-v1\".utf8) }"),
    ("require pairing: off saved unsigned", H, "        return Data((\"0.\" + Base64URL.encode(signature)).utf8)\n",
     "        return Data(\"0\".utf8)\n"),
    ("require pairing: an empty signature saved", H, "        guard let signature = sign(offMessage(macID: macID)), !signature.isEmpty else { return nil }",
     "        guard let signature = sign(offMessage(macID: macID)) else { return nil }"),
]
sys.exit(0 if module.mutate("home-records", M, sys.argv[1]) else 1)
