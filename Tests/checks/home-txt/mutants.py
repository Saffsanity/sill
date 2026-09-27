"""H3 (step 1) protocol mutants (HomeDoorTXT, the new wire values, the RemoteTLS overload): each must compile and make
home-txt/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
P = "Sources/StreamProtocol/Pairing.swift"
R = "Sources/StreamProtocol/Remote.swift"
T = "Sources/StreamProtocol/RemoteTLS.swift"
M = [
    ("an unknown value reads as open", P, "        return value == \"0\" ? .open : .pairingRequired\n    }\n\n    /// The door a received",
     "        return value == \"1\" ? .pairingRequired : .open\n    }\n\n    /// The door a received"),
    ("no p reads as pairing required", P, "        guard let value = txt[key] ?? txt[key.uppercased()] else { return .plain }", "        guard let value = txt[key] ?? txt[key.uppercased()] else { return .pairingRequired }"),
    ("keys case-sensitive", P, "        guard let value = txt[key] ?? txt[key.uppercased()] else { return .plain }", "        guard let value = txt[key] else { return .plain }"),
    ("P before p", P, "        guard let value = txt[key] ?? txt[key.uppercased()] else { return .plain }", "        guard let value = txt[key.uppercased()] ?? txt[key] else { return .plain }"),
    ("the values swapped", P, "public static func value(requirePairing: Bool) -> String { requirePairing ? \"1\" : \"0\" }",
     "public static func value(requirePairing: Bool) -> String { requirePairing ? \"0\" : \"1\" }"),
    ("the record read through its dictionary", P, "        switch record.getEntry(for: key) {\n        case nil: return .plain\n        case .string(let value)?: return value == \"0\" ? .open : .pairingRequired\n        default: return .pairingRequired          // no value, an empty one, or bytes\n        }",
     "        return door(record.dictionary)"),
    ("a valueless p in a record reads as plain", P, "        default: return .pairingRequired          // no value, an empty one, or bytes", "        default: return .plain"),
    ("a record's unknown value reads as open", P, "        case .string(let value)?: return value == \"0\" ? .open : .pairingRequired", "        case .string(let value)?: return value == \"1\" ? .pairingRequired : .open"),
    ("the key is P", P, "    public static let key = \"p\"", "    public static let key = \"P\""),
    ("ask spelled Ask", R, "public static let qr = \"qr\", code = \"code\", ask = \"ask\"", "public static let qr = \"qr\", code = \"code\", ask = \"Ask\""),
    ("cable not kept by the init", R, "self.model = model; self.cable = cable", "self.model = model"),
    ("cable false sent when the device did not say", R, "self.model = model; self.cable = cable", "self.model = model; self.cable = cable ?? false"),
    ("method not kept by the init", R, "self.retryAfter = retryAfter; self.method = method", "self.retryAfter = retryAfter"),
    ("the reasons misspelled", R, "public static let shown = \"shown\", openOnMac = \"openOnMac\", locked = \"locked\"", "public static let shown = \"shown\", openOnMac = \"openonmac\", locked = \"locked\""),
    ("pairingRequired misspelled", R, "public static let pairingRequired = \"pairingRequired\"", "public static let pairingRequired = \"pairing-required\""),
    ("the overload ignores peer-to-peer", T, "        p.includePeerToPeer = peerToPeer\n", "        p.includePeerToPeer = false\n"),
    ("the overload drops the video class", T, "    public static func parameters(tls: NWProtocolTLS.Options, tcp: NWProtocolTCP.Options, peerToPeer: Bool) -> NWParameters {\n        let p = NWParameters(tls: tls, tcp: tcp)\n        p.serviceClass = .interactiveVideo\n",
     "    public static func parameters(tls: NWProtocolTLS.Options, tcp: NWProtocolTCP.Options, peerToPeer: Bool) -> NWParameters {\n        let p = NWParameters(tls: tls, tcp: tcp)\n"),
    ("the remote door becomes peer-to-peer", T, "parameters(tls: tls, tcp: tcpOptions(dialing: dialing), peerToPeer: false)", "parameters(tls: tls, tcp: tcpOptions(dialing: dialing), peerToPeer: true)"),
    ("the overload takes the remote door's TCP", T, "        let p = NWParameters(tls: tls, tcp: tcp)\n", "        let p = NWParameters(tls: tls, tcp: tcpOptions(dialing: false))\n"),
    ("message not kept by the init", R, "        self.message = message\n    }", "    }"),
    ("a known reason shows the Mac's message", R, "guard !ok, !(reason.map { Self.knownReasons.contains($0) } ?? false) else { return nil }",
     "guard !ok else { return nil }"),
    ("an ok shows its message", R, "guard !ok, !(reason.map { Self.knownReasons.contains($0) } ?? false) else { return nil }",
     "guard !(reason.map { Self.knownReasons.contains($0) } ?? false) else { return nil }"),
    ("the Mac's words shown uncleaned", R, "        let text = SafeText.label(message ?? \"\", limit: 300)", "        let text = message ?? \"\""),
    ("a reason missing from the known ones", R, "[code, closed, expired, stopped, busy, shown, openOnMac, locked]", "[code, closed, expired, stopped, busy, shown, openOnMac]"),
]
sys.exit(0 if module.mutate("home-txt", M, sys.argv[1]) else 1)
