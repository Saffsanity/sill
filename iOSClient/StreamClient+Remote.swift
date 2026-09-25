import Foundation
import Network
import CryptoKit
import UIKit
import StreamProtocol

// Remote access on the device (docs/remote-access-plan.md §7): pairing, saved Macs, remote dials,
// the session gate (a remote session is connected at its first window list), kinds 18, 20 and 22,
// the reconnect order after a loss, and sill://pair links. Main thread unless a function says
// otherwise; the stored state lives in StreamClient.swift.

/// Pairing as the Add a Mac card and the overlay show it.
enum PairingPhase: Equatable {
    case idle
    /// "Pairing with Mac mini…", "Pairing with 100.101.102.103…".
    case working(String)
    /// Shown inline, under the field it belongs to.
    case failed(PairingProblem)
    /// The Mac is saved ("Paired with Mac mini."); a session follows, except from the overlay.
    case paired(String)
}

/// Why a pairing did not happen, in the words of §7.8.
enum PairingProblem: Equatable {
    enum Field { case address, code, card }

    case address
    case zone
    case codeLength
    case codeTypo
    case wrongCode(triesLeft: Int)
    case notPairing(String)
    case stopped(String)
    case expired
    case proofFailed(String)
    case nothingAnswered(String)
    case notSill(String)
    case localNetwork(String)
    case notALink
    case noKey(String)

    var field: Field {
        switch self {
        case .address, .zone, .nothingAnswered, .notSill, .localNetwork: return .address
        case .codeLength, .codeTypo, .wrongCode, .expired, .stopped: return .code
        case .notPairing, .proofFailed, .notALink, .noKey: return .card
        }
    }

    var text: String {
        switch self {
        case .address: return "That doesn’t look like an address. Try 100.101.102.103 or mac.example.net."
        case .zone: return "Remove the part after %: it only works on this network."
        case .codeLength: return "A code has 12 digits."
        case .codeTypo: return "That code has a typo. Check it against your Mac."
        case .wrongCode(let left):
            return "That code didn’t work. Check the code on your Mac. \(left) tr\(left == 1 ? "y" : "ies") left."
        case .notPairing(let mac): return "\(mac) isn’t pairing right now. On your Mac, choose Pair iPhone or iPad… first."
        case .stopped(let mac):
            return "\(mac) stopped pairing after too many wrong codes. Choose Pair iPhone or iPad… on your Mac for a new code."
        case .expired: return "This code expired. Choose Pair iPhone or iPad… on your Mac for a new one."
        case .proofFailed(let host):
            return "Pairing didn’t finish: the Mac at \(host) couldn’t show it knows the code. Pair from the same network as your Mac, or scan the code instead."
        case .nothingAnswered(let host): return "Nothing answered at \(host). Check the address, and that Sill is open on your Mac."
        case .notSill(let host): return "Something answered at \(host), but it isn’t Sill, or its Sill is too old to pair."
        case .localNetwork(let host): return "To reach \(host), allow Local Network for Sill in Settings."
        case .notALink: return "That’s not a Sill code."
        case .noKey(let reason): return "This \(StreamClient.deviceWord) couldn’t make its key (\(reason))."
        }
    }
}

/// The status line's words for a remote dial that failed and for a goodbye (§7.8).
enum RemoteCopy {
    static func dialFailure(_ failure: RemoteDialPolicy.Failure, mac: String, candidate: RemoteDialPolicy.Candidate?,
                            vpnName: String?, device: String) -> String {
        let at = candidate?.display ?? "its address"
        switch failure {
        case .wrongMac:
            return "This isn’t the \(mac) this \(device) paired with. If Sill was set up again on it, forget it here and pair again."
        case .revoked:
            return "\(mac) no longer accepts this \(device). Pair it again from Sill’s Settings on the Mac."
        case .remoteOff:
            return "\(mac) turned off Remote Access."
        case .busy:
            return "\(mac) is already serving 8 devices."
        case .refused:
            return "\(mac) answered, but Sill isn’t accepting remote connections there. Check that Sill is open and Remote Access is on. If you changed its port, connect at home once."
        case .vpnOff:
            let name = candidate.flatMap { vpnLabel($0) }
            return name.map { "\($0) looks off on this \(device). Turn it on, then tap \(mac)." }
                ?? "Your VPN looks off on this \(device). Turn it on, then tap \(mac)."
        case .nameNotFound:
            let host = candidate?.host ?? "its name"
            return RemoteDialPolicy.isTailscaleName(host) ? "This \(device) can’t look up \(host). Is Tailscale on?"
                                                        : "This \(device) can’t look up \(host)."
        case .localNetwork:
            return "To reach \(at), allow Local Network for Sill in Settings."
        case .notSill:
            return "Something answered at \(at), but it isn’t Sill. Your home’s internet address may have changed."
        case .noAnswer:
            if let c = candidate, c.kind == MacAddress.internet, !c.isName {
                return "\(mac) didn’t answer at \(at). If your home’s internet address changed, connect at home once to update it, or add an address name on the Mac."
            }
            return vpnName.map { "\(mac) didn’t answer. It may be asleep, or \($0) may be off on the Mac." } ?? "\(mac) didn’t answer. It may be asleep."
        }
    }

    /// A VPN address's service name when it carries one ("Tailscale", "Home WireGuard").
    static func vpnLabel(_ c: RemoteDialPolicy.Candidate) -> String? {
        guard c.kind == MacAddress.vpn || RemoteDialPolicy.isVPNAddress(c.host) else { return nil }
        if !c.via.isEmpty, !c.via.hasPrefix("VPN ("), !["Router", "Address name", "IPv6", "This Mac"].contains(c.via) { return c.via }
        return RemoteDialPolicy.isVPNAddress(c.host) ? "Tailscale" : nil
    }
}

extension StreamClient {
    /// "iPhone" or "iPad", for copy about this device.
    static var deviceWord: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }

    /// DEBUG builds keep 127.0.0.1 for the simulator's tests against a host on this Mac.
    static var keepsLoopback: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: Saved Macs

    func savedMac(_ macID: String) -> SavedMac? { savedMacs.first { $0.macID == macID } }

    /// "Mac mini", or "Mac mini (2)" for the second of that name.
    func displayName(_ macID: String) -> String {
        SavedMacs.displayNames(savedMacs)[macID] ?? savedMac(macID)?.name ?? "Mac"
    }

    /// Writes the list, except in a DEBUG run seeded with `-Sill.savedMacs` (for that run alone).
    func persistSavedMacs() {
        if !savedMacsSeeded { UserDefaults.standard.set(SavedMacs.encode(savedMacs), forKey: SavedMacs.defaultsKey) }
        recomputeMacs()
        updateDiscovery()
    }

    /// Forget: the record only. The Mac lists this device until it is removed there, and the
    /// status line says so.
    func forget(_ macID: String) {
        let name = savedMac(macID) != nil ? displayName(macID) : (macs.first { $0.macID == macID }?.name ?? "the Mac")
        if reconnect?.macID == macID { reconnect = nil }
        savedMacs.removeAll { $0.macID == macID }
        savedSightings.since[macID] = nil
        savedSightings.leftAt[macID] = nil
        persistSavedMacs()
        status = "Forgot \(name). It still lists this \(Self.deviceWord) until you remove it in Sill’s Settings on the Mac."
    }

    /// The card's Cancel while a pairing dial runs: it stops, nothing is saved.
    func cancelPairing() {
        pairingAttempt += 1          // a "busy" retry still waiting stays cancelled
        pairingDial?.cancel()
        pairingDial = nil
        // Only a change publishes: Cancel's shortcut runs inside a view update, where a needless
        // publish draws SwiftUI's "Publishing changes from within view updates" warning.
        if pairing != .idle { pairing = .idle }
    }

    /// At launch: saved Macs without this device's key (a restore from a backup: the key is
    /// ThisDeviceOnly) are useless, and cleared, but only when the Keychain says the key is not
    /// there (DeviceIdentity.knownMissing). DEBUG: `-SillForgetMacs 1` clears them and the key;
    /// `-SillPairURL`, `-SillPairCode` with `-SillPairAddress`, and `-SillDialSaved 1` start a
    /// pairing or a remote dial as the UI would, without the link's confirmation.
    func startRemote() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillForgetMacs") {
            savedMacs = []
            DeviceIdentity.forget()
            persistSavedMacs()
            print("remote: saved Macs and the device key forgotten")
        }
        #endif
        if !savedMacs.isEmpty, DeviceIdentity.knownMissing() {
            savedMacs = []
            persistSavedMacs()
        }
        #if DEBUG
        let d = UserDefaults.standard
        if let url = d.string(forKey: "SillPairURL") {
            if case .success(let link) = PairLink.parse(url) { pair(link: link, overlay: false) } else { pairing = .failed(.notALink) }
        } else if let code = d.string(forKey: "SillPairCode"), let address = d.string(forKey: "SillPairAddress") {
            pairTyped(code: code, address: address, overlay: false)
        } else if d.bool(forKey: "SillDialSaved"), let first = savedMacs.first {
            dialSaved(first.macID, why: .launchArgument)
        }
        #endif
    }

    // MARK: This device's path

    /// Watches the device's path, to tell "the Mac blinked" from "this device left home" after a
    /// loss (DiscoveryPolicy.remoteDialDue).
    func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            DispatchQueue.main.async {
                guard let self, signature != self.pathSignature else { return }
                self.pathSignature = signature
                if self.reconnect != nil { self.reconnectIfListed() }
            }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }

    static func signature(of path: NWPath) -> String {
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.sorted().joined(separator: ",")
        return "\(path.status)|\(interfaces)|\(path.isExpensive)"
    }

    /// This device's IPv4 networks (address and prefix), for the dial order's "a subnet this device
    /// shares".
    static func localIPv4Networks() -> [(address: [UInt8], prefix: Int)] {
        var out: [(address: [UInt8], prefix: Int)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = entry.pointee
            guard let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), let mask = i.ifa_netmask,
                  i.ifa_flags & UInt32(IFF_UP) != 0, i.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let bytes = withUnsafeBytes(of: a) { Array($0) }
            out.append((bytes, UInt32(bigEndian: m).nonzeroBitCount))
        }
        return out
    }

    // MARK: Remote dials

    /// Dials a saved Mac at its saved addresses (§7.5). A tap on its Remote row, Connect Remotely
    /// on its network row, the session after a pairing, the automatic reconnect, `-SillDialSaved`.
    func dialSaved(_ macID: String, why: DialReason) {
        guard let mac = savedMac(macID), let pin = mac.fingerprintData else { return }
        let name = displayName(macID)
        guard let identity = DeviceIdentity.existing() else {
            status = "This \(Self.deviceWord) has no key for \(name). Pair it again."
            return
        }
        cancelRemoteDial()
        if let old = connection, !connected {      // a home connection still coming up
            connection = nil
            old.cancel()
        }
        hostName = name
        status = why == .automatic ? "Reconnecting to \(name) remotely…" : "Connecting to \(name) remotely…"
        let candidates = RemoteDialPolicy.order(mac.allAddresses, remotePort: mac.remotePort, lastWorked: mac.lastWorked,
                                                localIPv4: Self.localIPv4Networks())
        #if DEBUG
        print("remote: dialing \(name) (\(macID)) \(why): \(candidates.map(\.key))")
        #endif
        let connector = RemoteConnector(candidates: candidates, mode: .session(pin: pin), identity: identity, queue: queue)
        remoteDial = connector
        connector.onWinner = { [weak self, weak connector] winner in
            DispatchQueue.main.async {
                guard let self, let connector, self.remoteDial === connector else { winner.connection.cancel(); return }
                self.remoteDial = nil
                self.remoteWinner(winner, macID: macID, why: why)
            }
        }
        connector.onFailed = { [weak self, weak connector] failed in
            DispatchQueue.main.async {
                guard let self, let connector, self.remoteDial === connector else { return }
                self.remoteDial = nil
                self.remoteDialFailed(macID: macID, why: why, failure: failed.failure, candidate: failed.candidate)
            }
        }
        connector.start()
    }

    #if DEBUG
    /// `-SillRemoteRoute vpn|internet`: a remote session to a test host on loopback counts as one
    /// through Tailscale or over the internet, so the simulator can check the 60 fps request and
    /// the slow-link callout (S8).
    static var testRoute: RemoteRoute? {
        switch UserDefaults.standard.string(forKey: "SillRemoteRoute") {
        case "vpn": return .vpn("Tailscale")
        case "internet": return .internet
        default: return nil
        }
    }
    #else
    static var testRoute: RemoteRoute? { nil }
    #endif

    func cancelRemoteDial() {
        remoteDial?.cancel()
        remoteDial = nil
    }

    /// The first attempt to reach `.ready`: the session connection, not yet `connected`: with TLS
    /// 1.3 the device is ready before the Mac has judged its key, so its first window list decides.
    private func remoteWinner(_ w: RemoteConnector.Winner, macID: String, why: DialReason) {
        // Through a tunnel: the address's VPN service name when it has one ("Tailscale"), else "your
        // VPN" (a LAN address reached through a VPN into the home network, an unnamed tunnel).
        let c0 = w.candidate
        let service = c0.kind == MacAddress.vpn && !c0.via.isEmpty && !c0.via.hasPrefix("VPN (") ? c0.via : nil
        let route: RemoteRoute = Self.testRoute ?? (w.usedTunnel ? .vpn(service) : (c0.kind == MacAddress.internet ? .internet : .address))
        #if DEBUG
        print("remote: \(w.candidate.key) is ready (\(route.phrase)); waiting for the window list")
        #endif
        let c = w.connection
        adopt(c, session: Session(route: .remote(route), macID: macID, bonjourName: nil, candidate: w.candidate, why: why))
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.connection === c, !self.connected else { return }
            self.connectionLost(c, end: .noWindowList)
            c.cancel()
        }
        firstListDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + RemoteDialPolicy.firstListDeadline, execute: deadline)
    }

    /// A remote session's first window list: now it is connected (the Mac admitted this device).
    func remoteSessionReady() {
        guard let s = session, case .remote(let r) = s.route, !connected else { return }
        firstListDeadline?.cancel()
        firstListDeadline = nil
        afterPairingWatch?.cancel()
        afterPairingWatch = nil
        reconnect = nil
        connected = true
        remoteRoute = r
        askedNearby = false
        connectedAt = Date()
        status = "Connected to \(hostName)"
        if case .paired = pairing { pairing = .idle }
        resetLiveness()
        if let id = s.macID, let i = savedMacs.firstIndex(where: { $0.macID == id }) {
            savedMacs[i].lastWorked = s.candidate?.key ?? savedMacs[i].lastWorked
            savedMacs[i].lastConnectedAt = Date()
            savedMacs[i].lastRoute = r.saved
            persistSavedMacs()
        }
        #if DEBUG
        print("remote: connected to \(hostName) \(r.phrase)")
        #endif
        updateDiscovery()
    }

    /// Every attempt failed, or the winner failed before its window list. An automatic dial tries
    /// again (2, 4, 8, then every 10 s) unless the Mac answered for good; anything else says why.
    func remoteDialFailed(macID: String, why: DialReason, failure: RemoteDialPolicy.Failure, candidate: RemoteDialPolicy.Candidate?) {
        let name = displayName(macID)
        #if DEBUG
        print("remote: dial of \(name) failed: \(failure)\(candidate.map { " (\($0.key))" } ?? "")")
        #endif
        let vpn = savedMac(macID)?.allAddresses.compactMap { a -> String? in
            RemoteCopy.vpnLabel(RemoteDialPolicy.Candidate(host: a.host, port: a.port ?? 7455, kind: a.kind, via: a.via))
        }.first
        let words = RemoteCopy.dialFailure(failure, mac: name, candidate: candidate, vpnName: vpn, device: Self.deviceWord)
        switch why {
        case .automatic:
            guard var r = reconnect, r.macID == macID else { return }
            switch failure {
            case .revoked, .wrongMac, .remoteOff:
                r.remoteAllowed = false          // the Mac answered for good; its rows still count
                status = words
            default:
                r.remoteFailures += 1
                r.nextRemoteAt = ProcessInfo.processInfo.systemUptime + DiscoveryPolicy.remoteRetryDelay(afterFailures: r.remoteFailures)
                status = "Reconnecting to \(name) remotely…"
            }
            reconnect = r
            reconnectIfListed()
        case .afterPairing:
            afterPairingWatch?.cancel()
            afterPairingWatch = nil
            pairing = .idle
            status = failure == .remoteOff ? words : "\(name) is saved. Tap it to connect."
        case .tap, .connectRemotely, .launchArgument:
            status = words
        }
        discoveryChanged()
    }

    /// The connection ended (StreamClient.connectionLost). The Mac's own words first: a notice
    /// (GoodbyePolicy: a reason this build does not know) ends any session, a remote dial's winner
    /// before its window list included, with those words and a reconnect only when the Mac asks for
    /// one. Otherwise a remote dial whose winner never delivered its window list failed as a dial;
    /// a session that ran goes back to the connect screen with the words its end deserves, and a
    /// reconnect: the network row, the Direct row, then (a saved Mac) its saved addresses (§7.4).
    func sessionEnded(error: NWError?, end: RemoteDialPolicy.End?) {
        let s = session
        let goodbye = self.goodbye
        firstListDeadline?.cancel()
        firstListDeadline = nil
        let saved = s?.macID.flatMap { savedMac($0) }
        let name = saved.map { displayName($0.macID) } ?? hostName
        if let goodbye, GoodbyePolicy.isNotice(goodbye) {
            endWithNotice(goodbye, session: s, saved: saved, name: name)
            return
        }
        if let s, s.route.isRemote, !connected, let id = s.macID {
            let how: RemoteDialPolicy.End = end ?? goodbye.map { .goodbye($0.reason) } ?? error.map { e in
                if case .tls(let st) = e { return .tlsAfterReady(st) }
                return RemoteConnector.end(of: e)
            } ?? .posix(ECONNRESET)
            let failure = s.candidate.flatMap { RemoteDialPolicy.classify(how, candidate: $0, usedTunnel: nil) } ?? .noAnswer
            tearDown(status: status, restartSearch: false)
            remoteDialFailed(macID: id, why: s.why ?? .tap, failure: failure, candidate: s.candidate)
            return
        }
        let outcome = GoodbyePolicy.outcome(goodbye, mac: name, device: Self.deviceWord, saved: saved != nil)
        tearDown(status: outcome.text)
        reconnect = outcome.reconnect ? lostReconnect(session: s, saved: saved, name: name, remoteAllowed: outcome.remoteAllowed) : nil
        updateDiscovery()
        if outcome.reconnect {
            scheduleReconnectRetry()
            reconnectIfListed()
        }
    }

    /// A session ended by a notice (GoodbyePolicy): the Mac's words as the status line, spoken like
    /// every ended session's line (ConnectScreen), and no reconnect unless the Mac asked for one:
    /// nothing dials that Mac again until the person taps its row. A remote session refused before
    /// its first window list never left the connect screen, so its Remote rows stay (the search is
    /// not restarted), and an after-pairing dial's watch ends with its card going idle; the remote
    /// dial's failure rules, which would say "isn’t accepting remote connections" and redial, are
    /// not asked.
    private func endWithNotice(_ goodbye: Goodbye, session s: Session?, saved: SavedMac?, name: String) {
        let outcome = GoodbyePolicy.outcome(goodbye, mac: name, device: Self.deviceWord, saved: saved != nil)
        tearDown(status: outcome.text, restartSearch: connected)
        notice = Notice(text: outcome.text, storeLink: outcome.storeLink)
        if s?.why == .afterPairing {
            afterPairingWatch?.cancel()
            afterPairingWatch = nil
            pairing = .idle
        }
        reconnect = outcome.reconnect ? lostReconnect(session: s, saved: saved, name: name, remoteAllowed: outcome.remoteAllowed) : nil
        #if DEBUG
        print("session: the Mac said goodbye (\(goodbye.reason.isEmpty ? "unreadable" : goodbye.reason)): “\(outcome.text)”; \(outcome.reconnect ? "reconnecting" : "not reconnecting")")
        #endif
        discoveryChanged()
        if outcome.reconnect { scheduleReconnectRetry() }
    }

    /// The automatic reconnect after a session with this Mac ended on its own (§7.4).
    private func lostReconnect(session s: Session?, saved: SavedMac?, name: String, remoteAllowed: Bool) -> Reconnect {
        let bonjour = s?.bonjourName ?? saved?.bonjourName
        return Reconnect(macID: saved?.macID, bonjourName: bonjour, name: name,
                         lostAt: ProcessInfo.processInfo.systemUptime, pathAtLoss: pathSignature,
                         remoteAllowed: remoteAllowed,
                         rememberedDirect: bonjour.map { directWirelessMacs.contains($0) } ?? false)
    }

    /// The automatic reconnect's look, at every browser change, path change and due time
    /// (§7.4): the Mac's network row at once (over its cable first when it says "Wired": `dial`);
    /// its Direct row only once that has stayed Direct for `directWait` and the network last listed
    /// the Mac `networkGrace` ago or more (DiscoveryPolicy.reconnectRow: its row blinks off while its
    /// listener is replaced, and a Mac back at home can show on awdl0 first); then, for a saved
    /// Mac, a remote dial when DiscoveryPolicy.remoteDialDue says so, again after 2, 4, 8, then
    /// every 10 s, and none 120 s after the loss. A row that appears while an automatic remote dial
    /// has no window list yet takes over from it; an established remote session is never moved.
    /// Unsaved Macs keep the old rule, by exact Bonjour name: two Macs can share a computer name
    /// ("MacBook Pro" and "MacBook Pro (2)"), and stripping the suffix would rejoin the wrong one.
    @discardableResult
    func reconnectIfListed() -> Bool {
        reconnectCheck?.cancel()
        reconnectCheck = nil
        guard !connected, var r = reconnect else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let dialingAutomatically = remoteDial != nil || session?.why == .automatic
        guard connection == nil || dialingAutomatically else { return false }
        func matches(_ m: FoundMac) -> Bool {
            if let id = r.macID, let rowID = m.macID { return rowID == id }
            return r.bonjourName == m.name
        }
        let network = macs.first { $0.route == .network && matches($0) }
        let direct = macs.first { $0.route == .direct && matches($0) }
        // The network's sightings are by the name it lists: the Direct row's, else the name last
        // used with the Mac.
        let listedName = direct?.name ?? r.bonjourName
        let choice = DiscoveryPolicy.reconnectRow(network: network, direct: direct,
                                                  directSince: direct.flatMap { directSince[$0.name] },
                                                  networkLeftAt: listedName.flatMap { sightings.leftAt[$0] }, now: now)
        if let mac = choice.take, mac.endpoint != nil {
            if dialingAutomatically, let c = connection { connection = nil; c.cancel(); tearDown(status: status, restartSearch: false) }
            cancelRemoteDial()
            reconnect = r        // kept until the row's connection is ready
            dial(mac, macID: mac.macID ?? r.macID)
            status = mac.direct ? "Reconnecting to \(r.name) directly…" : "Reconnecting to \(r.name)…"
            return true
        }
        var wake = choice.recheckAt
        if let id = r.macID, r.remoteAllowed, savedMac(id) != nil, !dialingAutomatically {
            if now >= r.lostAt + DiscoveryPolicy.redialWindow {
                r.remoteAllowed = false
                reconnect = r
                status = "Stopped trying to reach \(r.name). Tap it to try again."
            } else {
                let due = DiscoveryPolicy.remoteDialDue(listed: network != nil || direct != nil, lostAt: r.lostAt,
                                                        networkLeftAt: savedSightings.leftAt[id], rememberedDirect: r.rememberedDirect,
                                                        pathChangedSinceLoss: pathSignature != r.pathAtLoss, now: now)
                if due.dial, now >= r.nextRemoteAt {
                    dialSaved(id, why: .automatic)
                    return true
                }
                let next = due.dial ? r.nextRemoteAt : due.recheckAt
                wake = [wake, next, r.lostAt + DiscoveryPolicy.redialWindow].compactMap { $0 }.min()
            }
        }
        if let at = wake {
            let work = DispatchWorkItem { [weak self] in self?.reconnectIfListed() }
            reconnectCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, at - now), execute: work)
        }
        return false
    }

    /// A tap on a saved Mac's network row menu: Connect Remotely, a remote dial at home, to test
    /// the VPN path.
    func connectRemotely(_ macID: String) {
        reconnect = nil
        dialSaved(macID, why: .connectRemotely)
    }

    // MARK: Kind 18

    /// Who this connection's Mac is. Verified against a saved pin, it refreshes that Mac (name,
    /// port, addresses, only when newer) and names the session's Mac; unverified, it is shown in
    /// the panel's Away from home group and never saved.
    func receiveMacInfo(_ signed: SignedMacInfo, endpoint: NWEndpoint?) {
        if macInfoAt == nil { macInfoAt = Date() }
        guard let (info, fingerprint) = signed.verified() else {
            macInfo = signed.unverifiedInfo()
            macInfoVerified = nil
            macInfoSaved = false
            return
        }
        macInfo = info
        macInfoVerified = (info, fingerprint)
        guard let i = savedMacs.firstIndex(where: { $0.macID == info.macID && $0.fingerprintData == fingerprint }) else {
            macInfoSaved = false
            return
        }
        macInfoSaved = true
        session?.macID = info.macID
        var mac = SavedMacs.refreshed(savedMacs[i], info: info, fingerprint: fingerprint, allowLoopback: Self.keepsLoopback) ?? savedMacs[i]
        // The Bonjour name of a network or Direct connection to it: how a host without the tag is
        // still recognised.
        if case .service(let name, _, _, _)? = endpoint { mac.bonjourName = name }
        if mac != savedMacs[i] {
            savedMacs[i] = mac
            persistSavedMacs()
        }
    }

    // MARK: Pairing

    /// "Pair This iPad…": asks the Mac this device is connected to at home to show its code.
    func requestPairingCode() {
        send(.pairingWanted, payload: Data())
    }

    /// The overlay's typed path: the address of this connection's Mac, from its kind 18, preferring
    /// a LAN address in a subnet this device shares (it is at home), with the Mac's remote port.
    func overlayAddress() -> String? {
        guard let info = macInfo, !info.addresses.isEmpty else { return nil }
        let order = RemoteDialPolicy.order(info.addresses, remotePort: info.remotePort, lastWorked: nil,
                                           localIPv4: Self.localIPv4Networks())
        let local = Self.localIPv4Networks()
        let shared = order.first { c in
            RemoteDialPolicy.IPv4.parse(c.host).map { a in local.contains { RemoteDialPolicy.IPv4.sameNetwork(a, $0.address, prefix: $0.prefix) } } ?? false
        }
        guard let pick = shared ?? order.first else { return nil }
        return ParsedAddress(host: pick.host, port: pick.port, kind: pick.isIPv6 ? .ipv6 : (pick.isName ? .name : .ipv4)).text
    }

    /// A sill://pair link from outside the app: shown for confirmation, never acted on by itself (a
    /// poster or a message could otherwise add a look-alike "Mac" that collects keystrokes).
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "sill" else { return }
        switch PairLink.parse(url.absoluteString) {
        case .success(let link):
            pendingLink = link
            #if DEBUG
            print("remote: a link to pair with \(link.name) is waiting for the confirmation")
            #endif
        case .failure:
            pairing = .failed(.notALink)
        }
    }

    func confirmPendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        pair(link: link, overlay: connected)
    }

    func cancelPendingLink() { pendingLink = nil }

    /// The typed path: the address and the code as typed, checked here first (a typo never uses up
    /// one of the Mac's five tries, and nothing is sent).
    func pairTyped(code codeText: String, address addressText: String, overlay: Bool) {
        let address: ParsedAddress
        switch AddressParser.parse(addressText) {
        case .success(let a): address = a
        case .failure(.pairingLink):
            if case .success(let link) = PairLink.parse(addressText) { pair(link: link, overlay: overlay) } else { pairing = .failed(.notALink) }
            return
        case .failure(.zone): pairing = .failed(.zone); return
        case .failure: pairing = .failed(.address); return
        }
        switch PairingCode.check(codeText) {
        case .failure(.length): pairing = .failed(.codeLength)
        case .failure(.typo): pairing = .failed(.codeTypo)
        case .success(let code): pair(code: code, address: address, overlay: overlay)
        }
    }

    /// A code the scanner read, in the card or the overlay, found or tapped: a pairing starts only
    /// when RemoteDialPolicy.scanStartsPairing says so (never over one that runs; after a failure,
    /// the same code only from a tap).
    func scanned(_ link: PairLink, tapped: Bool, overlay: Bool) {
        var busy = false, failed = false
        switch pairing {
        case .working, .paired: busy = true
        case .failed: failed = true
        case .idle: break
        }
        guard RemoteDialPolicy.scanStartsPairing(busy: busy, failed: failed, secret: link.secret,
                                                 lastScanned: lastScannedSecret, tapped: tapped) else { return }
        pair(link: link, overlay: overlay, scanned: true)
    }

    /// After a failed scan, the scanner's caption says a tap on the code tries again.
    var scanRetryNeedsTap: Bool {
        if case .failed = pairing { return lastScannedSecret != nil }
        return false
    }

    /// The QR path: the link's addresses one at a time, pinned to its key.
    func pair(link: PairLink, overlay: Bool, scanned: Bool = false) {
        let addresses = link.addresses.map(RemoteDialPolicy.address(for:))
        let candidates = RemoteDialPolicy.order(addresses, remotePort: link.port, lastWorked: nil, localIPv4: Self.localIPv4Networks())
        startPairing(candidates: candidates, pin: link.fingerprint, key: { _ in PairingProof.qrKey(secret: link.secret) },
                     method: PairRequest.qr, macName: link.name, port: link.port, addresses: addresses, typed: nil,
                     overlay: overlay, scannedSecret: scanned ? link.secret : nil, busyRetried: false)
    }

    /// The typed path: one address, any P-256 key, bound into the proof with K from the code.
    func pair(code: String, address: ParsedAddress, overlay: Bool) {
        let a = RemoteDialPolicy.address(for: address)
        let port = address.port ?? HostConfigDefaults.remotePort
        let candidates = [RemoteDialPolicy.Candidate(host: a.host, port: port, kind: a.kind, via: a.via)]
        startPairing(candidates: candidates, pin: nil, key: { fp in PairingProof.codeKey(code: code, macFingerprint: fp) },
                     method: PairRequest.code, macName: nil, port: port, addresses: [], typed: a,
                     overlay: overlay, scannedSecret: nil, busyRetried: false)
    }

    // swiftlint-free by hand: the steps of one pairing, kept together. `scannedSecret`: the code's
    // secret when the scanner started it (see `scanned`), nil for a typed code or a confirmed link.
    private func startPairing(candidates: [RemoteDialPolicy.Candidate], pin: Data?, key: @escaping (Data) -> SymmetricKey?,
                              method: String, macName: String?, port: Int, addresses: [MacAddress], typed: MacAddress?,
                              overlay: Bool, scannedSecret: Data?, busyRetried: Bool) {
        lastScannedSecret = scannedSecret
        pairingAttempt += 1
        let attempt = pairingAttempt
        let identity: RemoteIdentity
        do { identity = try DeviceIdentity.loadOrCreate() } catch {
            pairing = .failed(.noKey("\(error)"))
            return
        }
        pairingDial?.cancel()
        let shown = macName ?? candidates.first?.display ?? "your Mac"
        pairing = .working("Pairing with \(shown)…")
        #if DEBUG
        print("remote: pairing with \(shown) (\(method)) at \(candidates.map(\.key))")
        #endif
        let connector = RemoteConnector(candidates: candidates, mode: .pairing(pin: pin), identity: identity, queue: queue)
        pairingDial = connector
        let retry: (Double) -> Void = { [weak self] after in
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                guard let self, self.pairingAttempt == attempt else { return }   // cancelled, or another pairing began
                self.startPairing(candidates: candidates, pin: pin, key: key, method: method, macName: macName, port: port,
                                  addresses: addresses, typed: typed, overlay: overlay, scannedSecret: scannedSecret, busyRetried: true)
            }
        }
        // On `queue`: the exchange runs there; its outcome hops to the main thread.
        connector.onWinner = { [weak self, weak connector] w in
            guard let self, let connector else { w.connection.cancel(); return }
            self.exchange(w, identity: identity, method: method, key: key) { outcome in
                DispatchQueue.main.async {
                    guard self.pairingDial === connector else { return }
                    self.pairingDial = nil
                    switch outcome {
                    case .saved(let result, let keyUsed):
                        self.paired(result, key: keyUsed, winner: w, identity: identity, method: method, linkName: macName, port: port,
                                    addresses: addresses, typed: typed, overlay: overlay)
                    case .refused(let r):
                        if r.reason == PairResult.busy, !busyRetried {
                            retry(max(0.2, min(r.retryAfter ?? 1, 10)))      // once, silently
                            return
                        }
                        self.pairing = .failed(Self.problem(for: r, mac: macName ?? w.candidate.display))
                    case .notPairing:
                        self.pairing = .failed(.notPairing(macName ?? "The Mac at \(w.candidate.display)"))
                    case .noProof:
                        self.pairing = .failed(.proofFailed(w.candidate.display))
                    }
                }
            }
        }
        connector.onFailed = { [weak self, weak connector] failed in
            DispatchQueue.main.async {
                guard let self, let connector, self.pairingDial === connector else { return }
                self.pairingDial = nil
                let host = failed.candidate?.display ?? shown
                switch failed.failure {
                case .refused, .revoked:
                    // Nothing listening (Remote Access off and no pairing window), or a door that
                    // turned the pairing away in its handshake.
                    self.pairing = .failed(.notPairing(macName ?? "The Mac at \(host)"))
                case .notSill, .wrongMac: self.pairing = .failed(.notSill(host))
                case .localNetwork: self.pairing = .failed(.localNetwork(host))
                default: self.pairing = .failed(.nothingAnswered(host))
                }
            }
        }
        connector.start()
    }

    private enum ExchangeOutcome {
        case saved(PairResult, SymmetricKey)
        case refused(PairResult)
        case notPairing
        case noProof
    }

    /// One pairing connection's exchange, on `queue`: kind 19 with proof_D, kind 20 back within 15 s,
    /// proof_M checked against the key and both fingerprints from this TLS session. Closes it.
    private func exchange(_ w: RemoteConnector.Winner, identity: RemoteIdentity, method: String,
                          key makeKey: @escaping (Data) -> SymmetricKey?, done: @escaping (ExchangeOutcome) -> Void) {
        let c = w.connection
        let fpMac = w.fingerprint, fpDevice = identity.fingerprint
        var finished = false
        let queue = self.queue
        func finish(_ outcome: ExchangeOutcome) {
            guard !finished else { return }
            finished = true
            c.cancel()
            done(outcome)
        }
        c.stateUpdateHandler = { state in
            if case .failed(let e) = state { queue.async { finish(RemoteDialPolicy.isPeerRefusal(e) ? .notPairing : .noProof) } }
        }
        queue.asyncAfter(deadline: .now() + RemoteDialPolicy.pairingReplyDeadline) { finish(.noProof) }
        // K from the code takes a PBKDF2 of 600,000 rounds: off the network queue, which may be
        // carrying a home session's frames at the same time (the overlay).
        DispatchQueue.global(qos: .userInitiated).async {
            guard let key = makeKey(fpMac) else { queue.async { finish(.noProof) }; return }
            queue.async {
                guard !finished else { return }
                let proof = PairingProof.deviceProof(key: key, deviceFingerprint: fpDevice, macFingerprint: fpMac)
                let request = PairRequest(method: method, proof: Base64URL.encode(proof), name: UIDevice.current.name,
                                          model: ClientStatsReporter.hardwareIdentifier)
                let message = StreamMessage(kind: .pairRequest, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                            payload: Wire.encode(request))
                c.send(content: message.serialized(), completion: .contentProcessed { _ in })
                c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { data, _, _, error in
                    guard let data, let header = StreamMessage.parseHeader(data), header.kind == .pairResult,
                          header.payloadLength > 0, header.payloadLength <= StreamMessage.maxPairingPayload else {
                        finish(error.map { RemoteDialPolicy.isPeerRefusal($0) } == true ? .notPairing : .noProof)
                        return
                    }
                    c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { data, _, _, error in
                        guard let data, let result = Wire.decode(PairResult.self, from: data) else {
                            finish(error.map { RemoteDialPolicy.isPeerRefusal($0) } == true ? .notPairing : .noProof)
                            return
                        }
                        guard result.ok else { finish(.refused(result)); return }
                        // Nothing is saved unless the Mac proved it knows the same key, for the
                        // keys of this very session, and names itself by that key.
                        guard let proofM = result.proof.flatMap(Base64URL.decode),
                              PairingProof.isValidMacProof(proofM, key: key, macFingerprint: fpMac, deviceFingerprint: fpDevice),
                              result.macID == MacID.make(fingerprint: fpMac),
                              result.recognitionKey.flatMap(Base64URL.decode)?.count == 32 else {
                            finish(.noProof)
                            return
                        }
                        finish(.saved(result, key))
                    }
                }
            }
        }
    }

    private static func problem(for r: PairResult, mac: String) -> PairingProblem {
        switch r.reason {
        case PairResult.code?: return .wrongCode(triesLeft: max(0, r.triesLeft ?? 0))
        case PairResult.expired?: return .expired
        case PairResult.stopped?: return .stopped(mac)
        case PairResult.busy?: return .notPairing(mac)
        default: return .notPairing(mac)       // "closed", or a reason this build does not know
        }
    }

    /// Kind 20 ok and proof_M checked: the Mac is saved, then a session is dialed (except from the
    /// overlay, where the home session simply goes on).
    private func paired(_ r: PairResult, key: SymmetricKey, winner w: RemoteConnector.Winner, identity: RemoteIdentity, method: String,
                        linkName: String?, port: Int, addresses: [MacAddress], typed: MacAddress?, overlay: Bool) {
        guard let macID = r.macID, let recognition = r.recognitionKey else { return }
        let name = SafeText.label(r.name ?? linkName ?? "Mac").isEmpty ? "Mac" : SafeText.label(r.name ?? linkName ?? "Mac")
        var mac = SavedMac(macID: macID, fingerprint: Base64URL.encode(w.fingerprint), name: name, recognitionKey: recognition,
                           remotePort: port, addresses: SavedMacs.filtered(addresses, allowLoopback: Self.keepsLoopback),
                           typedAddresses: typed.map { SavedMacs.filtered([$0], allowLoopback: Self.keepsLoopback) },
                           infoIssuedAt: 0, bonjourName: nil, lastWorked: w.candidate.key, pairedAt: Date(), method: method,
                           lastConnectedAt: nil, lastRoute: nil)
        // Paired over a session at home (the overlay): that session's Mac is the one just paired
        // only when its kind 18 is signed by the key just paired. Then the session is with a saved
        // Mac, the record learns its Bonjour name, and it takes that kind 18's addresses: the typed
        // path knew only the address it dialed, and the Mac sends no new kind 18 for a pairing.
        // Another Mac's code or link, paired over this stream, is saved as the card saves it:
        // naming this session after that Mac made its end read as that Mac's, and the reconnect
        // went to that Mac.
        var sameMac = false
        if overlay, let s = session, !s.route.isRemote, let v = macInfoVerified, v.fingerprint == w.fingerprint, v.info.macID == macID {
            sameMac = true
            mac.bonjourName = s.bonjourName
            mac = SavedMacs.refreshed(mac, info: v.info, fingerprint: v.fingerprint, allowLoopback: Self.keepsLoopback) ?? mac
            session?.macID = macID
        }
        savedMacs = SavedMacs.adding(mac, to: savedMacs)
        persistSavedMacs()
        pairing = .paired(displayName(macID))
        #if DEBUG
        print("remote: paired with \(name) (\(macID)), proof_M checked, pin saved\(overlay ? (sameMac ? "; this session's Mac" : "; not this session's Mac") : "")")
        #endif
        if overlay {
            if sameMac { macInfoSaved = true }
            return
        }
        dialSaved(macID, why: .afterPairing)
        let watch = DispatchWorkItem { [weak self] in
            guard let self, !self.connected else { return }
            self.cancelRemoteDial()
            if let c = self.connection { self.connection = nil; c.cancel(); self.tearDown(status: self.status, restartSearch: false) }
            self.pairing = .idle
            self.status = "\(self.displayName(macID)) is saved. Tap it to connect."
            self.discoveryChanged()
        }
        afterPairingWatch?.cancel()
        afterPairingWatch = watch
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watch)
    }
}

/// The remote port devices assume when a typed address has none (the host's HostConfig is not
/// visible here).
enum HostConfigDefaults {
    static let remotePort = 7455
}

extension RemoteDialPolicy {
    /// The Mac turned this device's key away in the handshake: -9825 (it does not know the key)
    /// or -9829 (no certificate). On a pairing connection it means no pairing window is open.
    static func isPeerRefusal(_ error: NWError) -> Bool {
        if case .tls(let s) = error { return s == -9825 || s == -9829 }
        return false
    }
}
