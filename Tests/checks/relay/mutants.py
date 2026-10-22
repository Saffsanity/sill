"""Reach from Anywhere mutants (Relay.swift, Remote.swift's MacInfo.relay, StreamMessage.swift's kinds,
RemoteDialPolicy.withRelay): each must compile and make relay/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
R = "Sources/StreamProtocol/Relay.swift"
M_ = "Sources/StreamProtocol/Remote.swift"
K = "Sources/StreamProtocol/StreamMessage.swift"
D = "iOSClient/RemoteDialPolicy.swift"
P = "Sources/StreamProtocol/Pairing.swift"
M = [
    ("relayInvite on 33", K, "    case relayInvite = 60 ", "    case relayInvite = 33 "),
    ("relayJoin on 62", K, "    case relayJoin = 61 ", "    case relayJoin = 62 "),
    ("a fingerprint of any length", R, "        s.utf8.count == 32 && s.utf8.allSatisfy", "        s.utf8.count >= 32 && s.utf8.allSatisfy"),
    ("uppercase hex taken", R, "($0 >= 0x61 && $0 <= 0x66) }", "($0 >= 0x61 && $0 <= 0x66) || ($0 >= 0x41 && $0 <= 0x46) }"),
    ("a domain without a dot", R, "guard !s.isEmpty, s.utf8.count <= 253, s.contains(\".\") else { return false }", "guard !s.isEmpty, s.utf8.count <= 253 else { return false }"),
    ("a domain label may start with a hyphen", R, "label.first != \"-\", label.last != \"-\",", "label.last != \"-\","),
    ("an empty label taken", R, "guard (1...63).contains(label.utf8.count)", "guard (0...63).contains(label.utf8.count)"),
    ("uppercase domains taken", R, "($0 >= 0x61 && $0 <= 0x7a) || $0 == 0x2d", "($0 >= 0x61 && $0 <= 0x7a) || ($0 >= 0x41 && $0 <= 0x5a) || $0 == 0x2d"),
    ("an empty key taken", R, "relay.isWellFormed && !key.isEmpty && key.utf8.count <= Self.maxKeyLength", "relay.isWellFormed && key.utf8.count <= Self.maxKeyLength"),
    ("a key of any length", R, "    public static let maxKeyLength = 512", "    public static let maxKeyLength = 1 << 20"),
    ("spaces in a key", R, "allSatisfy { $0.value > 0x20 && $0.value < 0x7f }", "allSatisfy { $0.value >= 0x20 && $0.value < 0x7f }"),
    ("an invite's relay unchecked", R, "relay.isWellFormed && !key.isEmpty", "!key.isEmpty"),
    ("host: unpaired keys get one", R, "        guard paired, relayReady else { return false }", "        guard relayReady else { return false }"),
    ("host: before the tailnet is up", R, "        guard paired, relayReady else { return false }", "        guard paired else { return false }"),
    ("host: no spacing", R, "        if let sinceLast, sinceLast < inviteSpacing { return false }\n", ""),
    ("host: spacing inclusive", R, "sinceLast < inviteSpacing { return false }", "sinceLast <= inviteSpacing { return false }"),
    ("device: asks unpinned", R, "        guard pinned, !askedThisSession, let offered", "        guard !askedThisSession, let offered"),
    ("device: asks again", R, "        guard pinned, !askedThisSession, let offered", "        guard pinned, let offered"),
    ("device: asks for a malformed offer", R, "let offered, offered.isWellFormed else { return false }\n        return joined", "let offered else { return false }\n        return joined"),
    ("device: asks for the tailnet it joined", R, "        return joined != offered.fingerprint", "        return true"),
    ("device: takes unasked", R, "        guard asked, invite.isWellFormed, let offered", "        guard invite.isWellFormed, let offered"),
    ("device: takes a malformed key", R, "        guard asked, invite.isWellFormed, let offered", "        guard asked, let offered"),
    ("device: takes another relay's", R, "        return invite.relay == offered", "        return invite.relay.fingerprint == offered.fingerprint"),
    ("device: takes any tailnet", R, "        return invite.relay == offered", "        return true"),
    ("the label is another", R, "    public static let serviceName = \"Sill Relay\"", "    public static let serviceName = \"HeadFwd\""),
    ("MacInfo drops relay", M_, "        self.addresses = addresses; self.relay = relay", "        self.addresses = addresses"),
    ("relay: last swapped for first", D, "        if lastWorked == relayKey { out.insert(relay, at: 0) } else { out.append(relay) }", "        out.insert(relay, at: 0)"),
    ("relay: never first", D, "        if lastWorked == relayKey { out.insert(relay, at: 0) } else { out.append(relay) }", "        out.append(relay)"),
    ("relay: listed twice", D, "        var out = ordered.filter { $0.key != relay.key }", "        var out = ordered"),
    ("relay: port 0 dialed", D, "        guard let forwarder, forwarder.port > 0 else { return ordered }", "        guard let forwarder else { return ordered }"),
    ("relay: counts as lan", D, "kind: MacAddress.vpn, via: RelayPolicy.serviceName)", "kind: MacAddress.lan, via: RelayPolicy.serviceName)"),
    ("isRelay: any loopback", D, "c.via == RelayPolicy.serviceName && c.host.hasPrefix(\"127.\")", "c.host.hasPrefix(\"127.\")"),
    ("relay key is the port", D, "    static let relayKey = \"relay\"", "    static let relayKey = \"127.0.0.1|62000\""),
    ("link: relay never written", P, '            items += [("r", relay.relay.domain), ("f", relay.relay.fingerprint), ("t", relay.key)]\n', ""),
    ("link: relay never read", P, "            if invite.isWellFormed { relay = invite }", "            _ = invite"),
    ("link: init keeps a malformed relay", P, "        self.relay = relay.flatMap { $0.isWellFormed ? $0 : nil }", "        self.relay = relay"),
]
module.mutate("relay", M, sys.argv[1] if len(sys.argv) > 1 else os.getcwd())
