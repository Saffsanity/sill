"""(integrate-12: follow-best-path's 61 mutants, unchanged, and R1-R9 of the merge's remote rule, against the merged file and policy-merge/main.swift.) Each mutant of DiscoveryPolicy's session route (P: route, S: sessionRoute/describesFlow), of the wired dial (D: dialInterface, W: wiredWait), of following the best path (F: pathPlan, pathGone, PathSightings, freshWifi, wifiInterface, rank) and of its review fixes (G: the reconnect over the cable, the refused listing, upWait) must fail the policy check. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "policy")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/DiscoveryPolicy.swift")
orig = open(SRC).read()
MUTANTS = {
    "P1 first path interface wins": ("guard let first = each.first, each.allSatisfy({ $0 == first }) else { return nil }",
                                     "guard let first = each.first else { return nil }"),
    "P2 scope ignored": ("if let scope { return method(of: scope) }", "_ = scope"),
    "P3 peer-to-peer checked after the type": ("        if isPeerToPeer(interface.name) { return .direct }\n        switch interface.type {\n        case .wiredEthernet: return .wired\n        case .wifi: return .wifi\n",
                                               "        switch interface.type {\n        case .wiredEthernet: return .wired\n        case .wifi: return isPeerToPeer(interface.name) ? .direct : .wifi\n"),
    "P3b peer-to-peer never Direct": ("        if isPeerToPeer(interface.name) { return .direct }\n        switch interface.type {", "        switch interface.type {"),
    "P4 unknown types as Wi-Fi": ("case .cellular, .loopback, .other: return nil", "case .cellular, .loopback, .other: return .wifi"),
    "P5 wired Ethernet as Wi-Fi": ("        case .wiredEthernet: return .wired\n        case .wifi: return .wifi\n        case .cellular",
                                   "        case .wiredEthernet: return .wifi\n        case .wifi: return .wifi\n        case .cellular"),
    "P6 wordless interfaces ignored": ("let each = path.map(method(of:))", "let each = path.compactMap(method(of:))"),
    "P7 the scope only when it has a word": ("if let scope { return method(of: scope) }", "if let scope, let m = method(of: scope) { return m }"),
    # sessionRoute and describesFlow (the wired fix, 2026-09-25)
    "S1 every update read (the bug: describesFlow ignored)": ("        guard describesFlow else { return current }\n", ""),
    "S2 never re-read (always the current word)": ("        return route(scope: scope ?? local, path: path)\n", "        return current\n"),
    "S3 a fresh reading must also name the Mac": ("        fresh || (hasAddress && satisfied)\n", "        hasAddress && satisfied\n"),
    "S4 an update without the Mac's address counts": ("        fresh || (hasAddress && satisfied)\n", "        fresh || satisfied\n"),
    "S5 an unsatisfied update counts": ("        fresh || (hasAddress && satisfied)\n", "        fresh || hasAddress\n"),
    "S6 either witness counts": ("        fresh || (hasAddress && satisfied)\n", "        fresh || hasAddress || satisfied\n"),
    "S7 no update ever counts": ("        fresh || (hasAddress && satisfied)\n", "        fresh\n"),
    "S8 this device's address ignored": ("        return route(scope: scope ?? local, path: path)\n", "        return route(scope: scope, path: path)\n"),
    "S9 this device's address beats the Mac's scope": ("        return route(scope: scope ?? local, path: path)\n", "        return route(scope: local ?? scope, path: path)\n"),
    "S10 a reading with no word keeps the old one": ("        return route(scope: scope ?? local, path: path)\n", "        return route(scope: scope ?? local, path: path) ?? current\n"),
    # dialInterface and wiredWait (prefer-cable, 2026-09-25)
    "D1 a Direct row dialled on a wired interface": ("        guard !direct else { return nil }\n        return interfaces.first { $0.type == .wiredEthernet", "        return interfaces.first { $0.type == .wiredEthernet"),
    "D2 the first interface whatever its type": ("interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name",
                                                  "interfaces.first { !isPeerToPeer($0.name) }?.name"),
    "D3 the last wired interface": ("interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name",
                                     "interfaces.last { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name"),
    "D4 never pinned": ("        return interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name\n",
                        "        return nil\n"),
    "D5 Wi-Fi dialled too": ("interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name",
                             "interfaces.first { ($0.type == .wiredEthernet || $0.type == .wifi) && !isPeerToPeer($0.name) }?.name"),
    "D6 peer-to-peer names dialled": ("interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name",
                                      "interfaces.first { $0.type == .wiredEthernet }?.name"),
    "W1 the wired dial waits 5 s": ("    static let wiredWait = 2.5\n", "    static let wiredWait = 5.0\n"),
    # pathPlan, pathGone, PathSightings, wifiInterface (follow-best-path, 2026-09-25)
    "F1 the cable's settle ignored": ("        let settled = max(since, i.lastDown ?? since) + cableSettle\n",
                                      "        let settled = max(since, i.lastDown ?? since)\n"),
    "F2 no hysteresis up": ("            let due = max(settled, (i.lastUp ?? -.infinity) + upWait(failures: i.upFailures))\n", "            let due = settled\n"),
    "F3 no hysteresis down": ("        if let last = i.lastDown, i.now < last + pathHysteresis {\n", "        if let last = i.lastDown, i.now < last {\n"),
    "F4 Wi-Fi to Wi-Fi when Wi-Fi's path goes": ("        if route == .wifi { return .stay(gone ? .lost : .wifi, recheckAt: nil) }\n",
                                                 "        if route == .wifi && !gone { return .stay(.wifi, recheckAt: nil) }\n"),
    "F5 off a cable that works, to a listed Wi-Fi": ("        guard gone else {\n", "        guard gone || i.wifi != nil else {\n"),
    "F6 a Direct session moved to the cable": ("        if route == .direct { return .stay(.direct, recheckAt: nil) }\n", ""),
    "F7 reconnectNow without Wi-Fi": ("        guard let wifi = i.wifi else { return .stay(.noWifi, recheckAt: nil) }\n        if i.dead { return .reconnectNow(.wifi, interface: wifi) }\n",
                                      "        if i.dead { return .reconnectNow(.wifi, interface: i.wifi ?? \"en0\") }\n        guard let wifi = i.wifi else { return .stay(.noWifi, recheckAt: nil) }\n"),
    "F8 Wi-Fi still fresh at exactly 5 s": ("        if let left = s.wifiLeft[name], now - left.at < wifiFresh { return left.interface }\n",
                                            "        if let left = s.wifiLeft[name], now - left.at <= wifiFresh { return left.interface }\n"),
    "F9 pong silence while the browser lists the cable": ("        guard i.route == .wired, i.wired == nil else { return false }\n", "        guard i.route == .wired else { return false }\n"),
    "F10 a hint alone takes the session off the cable": ("        if i.dead || i.pathReported { return true }\n", "        if i.dead || i.pathReported || i.pathHinted { return true }\n"),
    "F11 a dead connection moved up": ("        if !i.dead, Method.wired.rank > route.rank, let wired = i.wired, let since = i.wiredSince {\n",
                                       "        if Method.wired.rank > route.rank, let wired = i.wired, let since = i.wiredSince {\n"),
    "F12 wifiInterface takes awdl0 or llw0": ("        return interfaces.first { $0.type == .wifi && !isPeerToPeer($0.name) }?.name\n",
                                              "        return interfaces.first { $0.type == .wifi }?.name\n"),
    "F13 a move down does not start the settle again": ("        let settled = max(since, i.lastDown ?? since) + cableSettle\n", "        let settled = since + cableSettle\n"),
    "F14 wiredSince starts again at every look": ("                next.wiredSince[entry.name] = previous.wiredSince[entry.name] ?? now\n",
                                                  "                next.wiredSince[entry.name] = now\n"),
    "F15 the Wi-Fi memory kept for one look only": ("        for (name, left) in previous.wifiLeft where next.wifi[name] == nil && next.wifiLeft[name] == nil && now - left.at < wifiFresh {\n            next.wifiLeft[name] = left\n        }\n", ""),
    "F16 freshWifi ignores the memory": ("        if let left = s.wifiLeft[name], now - left.at < wifiFresh { return left.interface }\n", ""),
    "F17 Wi-Fi ranked over the cable": ("            case .wired: return 2\n            case .wifi: return 1\n            case .direct: return 0\n",
                                        "            case .wired: return 1\n            case .wifi: return 2\n            case .direct: return 0\n"),
    "F18 no look again at the silence mark": ("            if i.wired == nil { return .stay(.cableUnlisted, recheckAt: i.lastPong + pongSilence) }\n",
                                              "            if i.wired == nil { return .stay(.cableUnlisted, recheckAt: nil) }\n"),
    "F19 the silence 2 s": ("    static let pongSilence = 1.0\n", "    static let pongSilence = 2.0\n"),
    "F20 the settle 1 s": ("    static let cableSettle = 2.0\n", "    static let cableSettle = 1.0\n"),
    "F21 the hysteresis 3 s": ("    static let pathHysteresis = 5.0\n", "    static let pathHysteresis = 3.0\n"),
    "F22 Wi-Fi fresh for 10 s": ("    static let wifiFresh = 5.0\n", "    static let wifiFresh = 10.0\n"),
    "F23 a dead session held back by the hysteresis": ("        if i.dead { return .reconnectNow(.wifi, interface: wifi) }\n        if let last = i.lastDown, i.now < last + pathHysteresis {\n            return .stay(.downTooSoon, recheckAt: last + pathHysteresis)\n        }\n",
                                                      "        if let last = i.lastDown, i.now < last + pathHysteresis {\n            return .stay(.downTooSoon, recheckAt: last + pathHysteresis)\n        }\n        if i.dead { return .reconnectNow(.wifi, interface: wifi) }\n"),
    # review fixes (follow-best-path, 2026-09-25)
    "G1 a dead cable session always over Wi-Fi (the finding)": ("        if i.dead, !i.pathReported, let wired = i.wired { return .reconnectNow(.wired, interface: wired) }\n", ""),
    "G2 over the cable again though iOS said its path went": ("        if i.dead, !i.pathReported, let wired = i.wired {", "        if i.dead, let wired = i.wired {"),
    "G3 a hint counts against the cable": ("        if i.dead, !i.pathReported, let wired = i.wired {", "        if i.dead, !i.pathReported, !i.pathHinted, let wired = i.wired {"),
    "G4 over the cable again only with Wi-Fi listed": ("        if i.dead, !i.pathReported, let wired = i.wired { return .reconnectNow(.wired, interface: wired) }\n        guard let wifi = i.wifi else { return .stay(.noWifi, recheckAt: nil) }\n",
                                                       "        guard let wifi = i.wifi else { return .stay(.noWifi, recheckAt: nil) }\n        if i.dead, !i.pathReported, let wired = i.wired { return .reconnectNow(.wired, interface: wired) }\n"),
    "G5 over the cable again, named by Wi-Fi's interface": ("return .reconnectNow(.wired, interface: wired) }", "return .reconnectNow(.wired, interface: i.wifi ?? wired) }"),
    "G6 a refused listing tried again": ("            if since == i.refusedCable { return .stay(.cableRefused, recheckAt: nil) }\n", ""),
    "G7 a refused listing blocks every listing": ("            if since == i.refusedCable {", "            if i.refusedCable != nil {"),
    "G8 no back-off": ("        min(pathHysteresis * Double(1 << min(max(failures, 0), 4)), upBackoffCap)\n", "        pathHysteresis\n"),
    "G9 a back-off without its cap": ("        min(pathHysteresis * Double(1 << min(max(failures, 0), 4)), upBackoffCap)\n", "        pathHysteresis * Double(1 << min(max(failures, 0), 4))\n"),
    "G10 the back-off a step ahead": ("        min(pathHysteresis * Double(1 << min(max(failures, 0), 4)), upBackoffCap)\n", "        min(pathHysteresis * Double(1 << min(max(failures, 0) + 1, 4)), upBackoffCap)\n"),
    "G11 the cap 30 s": ("    static let upBackoffCap = 60.0\n", "    static let upBackoffCap = 30.0\n"),
    "G12 the failures ignored by the plan": ("(i.lastUp ?? -.infinity) + upWait(failures: i.upFailures))", "(i.lastUp ?? -.infinity) + upWait(failures: 0))"),
    "G13 the back-off's reason always the hysteresis": ("(i.upFailures > 0 ? .cableFailing : .upTooSoon)", ".upTooSoon"),
    # the merge with main (PR #13, remote access): a remote session is no candidate for the moves
    "R1 the remote rule dropped": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n", ""),
    "R2 remote only when the route says nothing": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n",
                                                   "        if i.remote, i.route == nil { return .stay(.remote, recheckAt: nil) }\n"),
    "R3 remote checked after a route that says nothing and Direct": (
        "        if i.remote { return .stay(.remote, recheckAt: nil) }\n        guard let route = i.route else { return .stay(.routeUnknown, recheckAt: nil) }\n        if route == .direct { return .stay(.direct, recheckAt: nil) }\n",
        "        guard let route = i.route else { return .stay(.routeUnknown, recheckAt: nil) }\n        if route == .direct { return .stay(.direct, recheckAt: nil) }\n        if i.remote { return .stay(.remote, recheckAt: nil) }\n"),
    "R4 a dead remote session made again here": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n",
                                                 "        if i.remote, !i.dead { return .stay(.remote, recheckAt: nil) }\n"),
    "R5 a remote session looks again": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n",
                                        "        if i.remote { return .stay(.remote, recheckAt: i.now + pathHysteresis) }\n"),
    "R6 the remote reason is Direct's": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n",
                                         "        if i.remote { return .stay(.direct, recheckAt: nil) }\n"),
    "R7 the reason's words": ('            case .remote: return "a remote session moves only home, once the network lists its Mac"\n',
                              '            case .remote: return "over Direct, the session moves only to the network"\n'),
    "R8 every session remote by default": ("        var remote = false\n", "        var remote = true\n"),
    "R9 a remote session read as its route word (the flag ignored)": ("        if i.remote { return .stay(.remote, recheckAt: nil) }\n",
                                                                      "        if i.remote && i.route == .direct { return .stay(.remote, recheckAt: nil) }\n"),
    # moveHome (remote-bundle, H15)
    "H1 the move home tries a refused listing": ("        guard let since = listedSince, since != refusedListing else { return (false, nil) }\n        var due = since + moveAfter\n        if let last = lastAttempt, failures > 0 {",
                                                 "        guard let since = listedSince else { return (false, nil) }\n        var due = since + moveAfter\n        if let last = lastAttempt, failures > 0 {"),
    "H2 the move home waits upWait(0) with no failure": ("        if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }",
                                                         "        if let last = lastAttempt { due = max(due, last + upWait(failures: failures)) }"),
    "H3 the move home at > for >=": ("        if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }\n        return now >= due ? (true, nil) : (false, due)",
                                     "        if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }\n        return now > due ? (true, nil) : (false, due)"),
    "H4 the move home ignores failures": ("        if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }",
                                          "        if let last = lastAttempt, failures > 0 { due = max(due, last + moveAfter) }"),
    "H5 the move home at once, not after 2 s listed": ("        guard let since = listedSince, since != refusedListing else { return (false, nil) }\n        var due = since + moveAfter\n        if let last = lastAttempt, failures > 0 {",
                                                       "        guard let since = listedSince, since != refusedListing else { return (false, nil) }\n        var due = since\n        if let last = lastAttempt, failures > 0 {"),
    "H6 the move home backs off from the listing, not the last try": ("        if let last = lastAttempt, failures > 0 { due = max(due, last + upWait(failures: failures)) }",
                                                                     "        if let last = lastAttempt, failures > 0 { due = max(due, since + upWait(failures: failures)) }"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    assert orig.count(old) == 1, f"{name}: pattern found {orig.count(old)} times"
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:800]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:2]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
