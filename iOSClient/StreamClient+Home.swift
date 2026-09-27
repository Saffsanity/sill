import Foundation
import Network
import Security
import CryptoKit
import UIKit
import StreamProtocol

// Pairing at home on the device (docs/home-pairing-plan.md §7): the one TLS builder every
// connection to a Mac goes through, the session gate over TLS (a session at home is connected at
// its first window list, as a remote one is), the ask a tap on an unpaired row makes, the cable's
// proof-less ok, the proofs sent to the row (the home card, Pair This iPad…, an outside link), and
// how a session at home over TLS ends. Main thread unless a function says otherwise; the stored
// state lives in StreamClient.swift, and the pure rules in DiscoveryPolicy.

/// Every connection this device opens to a Mac speaks TLS through here (§7.2), at home and away:
/// TLS 1.3 from RemoteTLS with this device's certificate, the Mac's key checked against a pin, or
/// any P-256 key where there is none yet (an open door's first connection, an ask, the typed
/// pairing path from afar). Plain TCP remains only for a plain door, which only a DEBUG build ever
/// dials (DiscoveryPolicy.homeDial).
enum DeviceTLS {
    /// The TLS options of one connection: `alpn` is `sill/1` for a session, `sill-pair/1` for
    /// pairing; `pin` the Mac's key, or nil for any P-256 key (a key of another kind matches
    /// nothing). RemoteConnector's dials from afar use them too.
    static func options(identity: RemoteIdentity, alpn: String, pin: Data?, queue: DispatchQueue) -> NWProtocolTLS.Options {
        RemoteTLS.options(identity: identity.tls, role: .client(alpn: alpn), verify: { fp in
            guard let fp else { return false }
            return pin.map { $0 == fp } ?? true
        }, queue: queue)
    }

    /// A connection to a Mac's home door: those TLS options over the device's home TCP (no Nagle;
    /// a connect timeout for a pairing dial), the video service class, and peer-to-peer (AWDL) only
    /// for a Direct row (RemoteTLS.parameters). `ipv6Only` for the ask's dial over a row's wired
    /// interface: the cable counts only over IPv6 link-local, at both ends.
    static func home(identity: RemoteIdentity, alpn: String, pin: Data?, peerToPeer: Bool, queue: DispatchQueue,
                     ipv6Only: Bool = false, connectTimeout: Int? = nil) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        if let connectTimeout { tcp.connectionTimeout = connectTimeout }
        let params = RemoteTLS.parameters(tls: options(identity: identity, alpn: alpn, pin: pin, queue: queue), tcp: tcp,
                                          peerToPeer: peerToPeer)
        if ipv6Only, let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v6 }
        return params
    }

    /// A plain door's connection, as before pairing at home: TCP without Nagle, the interactive
    /// video class, and peer-to-peer only for a Direct row. Only a DEBUG build dials one.
    static func plain(peerToPeer: Bool) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = peerToPeer
        // Wi-Fi QoS: video + pointer traffic is latency-sensitive; the access point and the radio
        // treat this class (WMM video) with shorter queues than best-effort.
        params.serviceClass = .interactiveVideo
        return params
    }

    /// Parameters that never connect: TLS whose verify block trusts no key, so the handshake ends
    /// before this device sends anything. For a connection of a TLS session should this device's
    /// key be unreadable (it cannot be: the session's first connection was made with it, and the
    /// identity stays in memory): that connection then fails as any failed one does, and nothing
    /// ever goes out in plain.
    static func refusing(peerToPeer: Bool, queue: DispatchQueue) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(false) }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return RemoteTLS.parameters(tls: tls, tcp: tcp, peerToPeer: peerToPeer)
    }
}

/// A pairing connection to a Mac's home door (§7.5): TLS with `sill-pair/1`, pinned to `pin` or
/// taking any P-256 key, to each target in turn until one is ready. A target is a row as a tap
/// dials it: its wired interface first, IPv6 only (the cable counts only over IPv6 link-local, at
/// both ends), then, that dial not ready within DiscoveryPolicy.wiredWait or unable to go on, the
/// row as listed; or one endpoint. Each dial gives up after RemoteTLS.dialTimeout. A pairing is
/// single-use, so one connection at a time. Every callback on `queue`, which the winner keeps.
final class HomeDialer {
    struct Target: Equatable {
        let endpoint: NWEndpoint
        /// The row as listed, after a wired `endpoint`; nil for any other target.
        var fallback: NWEndpoint? = nil
        /// A Direct row.
        var peerToPeer = false
        /// The row (FoundMac.id) it dials; nil for an address or the session's own connection.
        var row: String? = nil
        /// What the DEBUG console calls it.
        let label: String
    }

    struct Winner {
        let connection: NWConnection
        let target: Target
        /// The endpoint that answered: the wired one, or the row as listed.
        let endpoint: NWEndpoint
        /// The Mac's key as this connection saw it.
        let fingerprint: Data
    }

    /// No target was ready: the TLS status each dial that had one ended with (-9808: this device's
    /// pin refused the key there).
    struct Failed {
        let statuses: [Int32]
    }

    /// On `queue`, once.
    var onWinner: ((Winner) -> Void)?
    /// On `queue`, once, when no target was ready.
    var onFailed: ((Failed) -> Void)?

    private let targets: [Target]
    private let pin: Data?
    private let identity: RemoteIdentity
    private let queue: DispatchQueue
    // On `queue`.
    private var index = 0
    private var current: NWConnection?
    private var onFallback = false
    private var finished = false
    private var timer: DispatchWorkItem?
    private var statuses: [Int32] = []

    init(targets: [Target], pin: Data?, identity: RemoteIdentity, queue: DispatchQueue) {
        self.targets = targets
        self.pin = pin
        self.identity = identity
        self.queue = queue
    }

    func start() {
        queue.async { [self] in dialTarget() }
    }

    /// Stops the dial in flight; nothing is called back afterwards. Any thread.
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            timer?.cancel()
            current?.stateUpdateHandler = nil
            current?.cancel()
            current = nil
        }
    }

    // MARK: On `queue`

    private func dialTarget() {
        guard !finished else { return }
        guard index < targets.count else { finish(); return }
        onFallback = false
        let t = targets[index]
        dial(t.endpoint, ipv6Only: t.fallback != nil,
             wait: t.fallback != nil ? DiscoveryPolicy.wiredWait : Double(RemoteTLS.dialTimeout) + 2)
    }

    private func dial(_ endpoint: NWEndpoint, ipv6Only: Bool, wait: Double) {
        let t = targets[index]
        let c = NWConnection(to: endpoint, using: DeviceTLS.home(identity: identity, alpn: RemoteTLS.pairingALPN, pin: pin,
                                                                 peerToPeer: t.peerToPeer, queue: queue, ipv6Only: ipv6Only,
                                                                 connectTimeout: RemoteTLS.dialTimeout))
        current = c
        c.stateUpdateHandler = { [weak self] state in self?.changed(c, endpoint, state) }
        c.start(queue: queue)
        timer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.finished, self.current === c else { return }
            self.ended(c, status: nil)
        }
        timer = item
        queue.asyncAfter(deadline: .now() + wait, execute: item)
    }

    private func changed(_ c: NWConnection, _ endpoint: NWEndpoint, _ state: NWConnection.State) {
        guard !finished, current === c else { return }
        switch state {
        case .ready:
            guard let fp = RemoteTLS.peerFingerprint(c) else { ended(c, status: nil); return }
            finished = true
            timer?.cancel()
            c.stateUpdateHandler = nil
            current = nil
            onWinner?(Winner(connection: c, target: targets[index], endpoint: endpoint, fingerprint: fp))
        case .waiting(let e), .failed(let e):
            ended(c, status: RemoteTLS.status(of: e))
        case .cancelled:
            ended(c, status: nil)
        default:
            break
        }
    }

    /// The dial in flight is over without a winner: the row as listed after a wired dial, else the
    /// next target.
    private func ended(_ c: NWConnection, status: Int32?) {
        if let status { statuses.append(status) }
        #if DEBUG
        print("home dial: \(targets[index].label)\(onFallback ? " (as listed)" : "") ended\(status.map { " (\($0))" } ?? "")")
        #endif
        current = nil
        c.stateUpdateHandler = nil
        c.cancel()
        if let fallback = targets[index].fallback, !onFallback {
            onFallback = true
            dial(fallback, ipv6Only: false, wait: Double(RemoteTLS.dialTimeout) + 2)
            return
        }
        index += 1
        dialTarget()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        onFailed?(Failed(statuses: statuses))
    }
}

/// A tap on a row that pairs first (§7.5): where the ask went and what the Mac answered. The home
/// card follows it: its scanner or its code field once the Mac shows a code (`shown`).
struct HomeAsk: Equatable {
    enum Phase: Equatable {
        /// The ask is on its way (kind 19 "ask", kind 20 back within 15 s).
        case asking
        /// The Mac shows its code: scan it or type it (`StreamClient.pairHome`).
        case shown
    }

    /// Where the ask goes: the row as a tap dials it (its wired interface first), or an address
    /// (DEBUG `-SillConnect`).
    let target: HomeDialer.Target
    /// What the words call the Mac: the row's name.
    let name: String
    /// The row says Wired over the cable: "Pairing with Mac mini over the cable…".
    let cableRow: Bool
    /// A saved Mac that removed this device: the ask and the proofs are pinned to its key.
    let savedID: String?
    /// The row's TXT tag named that saved Mac (the wrong-Mac words are for such a row).
    let tagNamed: Bool
    /// Rows of that Mac a pin failure already tried (§7.6).
    var tried: [String] = []
    /// The ask's attempt (`pairingAttempt`): an answer to an older one is dropped.
    var attempt = 0
    var phase = Phase.asking
    /// Once the Mac answered: the key the ask saw, the endpoint that answered (the cable's, or the
    /// row as listed), and whether the ask said `cable: true`.
    var askedKey: Data?
    var answered: NWEndpoint?
    var claimedCable = false
}

extension StreamClient {
    /// DEBUG builds dial a plain door (a Mac never seen with `p`); a Release build never does
    /// (DiscoveryPolicy.homeDial).
    static var debugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// This device's key, made now at its first TLS dial (§7.2: before pairing at home it was made
    /// at the first pairing); nil with the status line saying why.
    func deviceIdentity() -> RemoteIdentity? {
        do {
            return try DeviceIdentity.loadOrCreate()
        } catch {
            status = PairingProblem.noKey("\(error)").text
            return nil
        }
    }

    /// The parameters of a session connection at home with `trust` (§7.2): TLS `sill/1` pinned as
    /// the trust says (DiscoveryPolicy.pin), or plain for a plain door. Nil, with the status line
    /// saying why, when a TLS dial finds no key and none can be made.
    func sessionParameters(_ trust: DiscoveryPolicy.HomeTrust, peerToPeer: Bool) -> NWParameters? {
        let pin: Data?
        switch DiscoveryPolicy.pin(trust) {
        case .plainTCP: return DeviceTLS.plain(peerToPeer: peerToPeer)
        case .anyKey: pin = nil
        case .key(let key): pin = key
        }
        guard let identity = deviceIdentity() else { return nil }
        return DeviceTLS.home(identity: identity, alpn: RemoteTLS.sessionALPN, pin: pin, peerToPeer: peerToPeer, queue: queue)
    }

    /// A browse result's home door, from its TXT record's `p` (HomeDoorTXT, entry by entry: a bare
    /// `p` reads as "1"), as DiscoveryPolicy spells it.
    static func door(of result: NWBrowser.Result) -> DiscoveryPolicy.HomeDoor {
        guard case .bonjour(let txt) = result.metadata else { return .plain }
        switch HomeDoorTXT.door(txt) {
        case .plain: return .plain
        case .pairingRequired: return .pairingRequired
        case .open: return .open
        }
    }

    // MARK: The session gate over TLS

    /// A session at home over TLS: its first window list says the Mac admitted this device's key,
    /// so it is connected now, as a remote one is (§7.2). A saved Mac's session also teaches that
    /// its home door speaks TLS (`homeTLS`: no plain dial of it ever again). Main thread.
    func homeSessionReady() {
        guard let s = session, !s.route.isRemote, !connected, s.home?.tls == true else { return }
        firstListDeadline?.cancel()
        firstListDeadline = nil
        afterPairingWatch?.cancel()
        afterPairingWatch = nil
        if case .paired = pairing { pairing = .idle }
        #if DEBUG
        print("home: connected to \(hostName) over TLS, \(s.macID != nil ? "a saved Mac" : "an open door")")
        #endif
        markConnected(endpoint: s.endpoint, name: hostName)
        if let id = s.macID, let next = SavedMacs.seenOverTLS([id], in: savedMacs) {
            savedMacs = next
            persistSavedMacs()
        }
        #if DEBUG
        // `-SillOverlayCode <digits>`: Pair This iPad… as the overlay runs it, once, on this session
        // (kind 21, then the code typed): the gates drive no UI, and the Mac's window must show that
        // code (the bare app's -SillPairAfter).
        if let code = UserDefaults.standard.string(forKey: "SillOverlayCode"), !overlayCodeTyped {
            overlayCodeTyped = true
            print("harness: Pair This \(Self.deviceWord)… with the code, over this session")
            requestPairingCode()
            pairOverlayTyped(code: code, mac: hostName)
        }
        #endif
    }

    /// A TLS session's first window list must come within 10 s of `.ready`, as a remote one's.
    func awaitFirstList(_ c: NWConnection) {
        firstListDeadline?.cancel()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.connection === c, !self.connected else { return }
            self.connectionLost(c, end: .noWindowList)
            c.cancel()
        }
        firstListDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + RemoteDialPolicy.firstListDeadline, execute: deadline)
    }

    /// How a session at home over TLS ended (§7.6, DiscoveryPolicy.homeEnd): the Mac removed this
    /// device, now asks devices to pair, or another key answered as the saved Mac. True when it
    /// said the words and chose what follows (never the ordinary reconnect); false for every other
    /// end, which `sessionEnded` words as before. A saved Mac whose pin failed has its other rows
    /// dialed first, pinned: a stranger replaying its tag makes a row that looks like it, and the
    /// words would tell the user to forget the real Mac. A row the reconnect took by its Bonjour
    /// name alone is skipped from then on, without those words. Main thread.
    func homeSessionEnded(_ s: Session?, error: NWError?, goodbye: String?) -> Bool {
        guard let s, !s.route.isRemote else { return false }
        let end = DiscoveryPolicy.homeEnd(trust: s.home, goodbye: goodbye, tls: error.flatMap { RemoteTLS.status(of: $0) })
        let saved = s.macID.flatMap { savedMac($0) }
        let name = saved.map { displayName($0.macID) } ?? hostName
        #if DEBUG
        if end != .other { print("home: the session ended: \(end) (\(goodbye ?? error.map { "\($0)" } ?? "no reason"))") }
        #endif
        switch end {
        case .other:
            return false
        case .removed:
            if let id = saved?.macID, let next = SavedMacs.revoking(id, in: savedMacs) {
                savedMacs = next
                persistSavedMacs()
            }
            endAtHome(DiscoveryPolicy.HomeCopy.removed(mac: name, device: Self.deviceWord))
        case .pairingRequired:
            endAtHome(DiscoveryPolicy.HomeCopy.pairingRequired(mac: name, device: Self.deviceWord))
        case .wrongKey:
            let tried = s.row.map { $0.tried + [$0.id] } ?? []
            if let mac = saved, let pin = mac.fingerprintData,
               let next = DiscoveryPolicy.nextPinnedRow(macID: mac.macID, tried: tried, rows: homeRows()),
               let row = macs.first(where: { $0.id == next }) {
                #if DEBUG
                print("home: another key answered at \(s.row?.id ?? "the address"); dialing \(row.name) pinned")
                #endif
                tearDown(status: status, restartSearch: false)
                dialRow(row, macID: mac.macID, trust: .saved(pin: pin), tagNamed: row.macID != nil, tried: tried, tap: s.row?.tapped ?? false)
                return true
            }
            guard s.row?.tagNamed ?? true else {
                // A row taken by its Bonjour name alone is not that Mac: the reconnect skips it from
                // now on and goes on without it; a tap says what happened, and reconnects nothing.
                pinRefusedRows.formUnion(tried)
                guard s.row?.tapped == true else { return false }
                endAtHome(RemoteCopy.dialFailure(.wrongMac, mac: name, candidate: nil, vpnName: nil, device: Self.deviceWord))
                return true
            }
            endAtHome(RemoteCopy.dialFailure(.wrongMac, mac: name, candidate: nil, vpnName: nil, device: Self.deviceWord))
        }
        return true
    }

    private func endAtHome(_ words: String) {
        reconnect = nil
        tearDown(status: words)
        updateDiscovery()
    }

    /// Each network or Direct row's id and the saved Mac its TXT tag named.
    /// (Not the rows taken by their Bonjour name: `FoundMac.savedByName`.)
    func homeRows() -> [(id: String, macID: String?)] {
        macs.filter { $0.route != .remote }.map { (id: $0.id, macID: $0.macID) }
    }

    // MARK: The ask (§7.5)

    /// A tap on a row that pairs first (DiscoveryPolicy.homeDial's `.ask`): `sill-pair/1` to the
    /// row as a tap dials it, kind 19 "ask" with `cable: true` when this device's own check says the
    /// connection runs over the USB cable, and kind 20 within 15 s. `savedID`: a saved Mac that
    /// removed this device, whose key the ask and the proofs are pinned to; otherwise any key, and
    /// the one the ask saw is kept (`askedKey`).
    func ask(_ mac: FoundMac, savedID: String?, tagNamed: Bool, tried: [String] = []) {
        guard let endpoint = mac.endpoint else { return }
        let wired = wiredDial(for: mac)
        let target = HomeDialer.Target(endpoint: wired?.endpoint ?? endpoint, fallback: wired != nil ? endpoint : nil,
                                       peerToPeer: mac.direct, row: mac.id, label: wired?.via ?? mac.name)
        startAsk(HomeAsk(target: target, name: mac.name, cableRow: mac.homeWord == .pairsOverCable, savedID: savedID,
                         tagNamed: tagNamed, tried: tried))
    }

    func startAsk(_ start: HomeAsk, busyRetried: Bool = false) {
        guard let identity = deviceIdentity() else { return }
        homeDialer?.cancel()
        pairingDial?.cancel()
        pairingDial = nil
        cancelRemoteDial()
        if let old = connection, !connected {      // a session connection still coming up
            connection = nil
            old.cancel()
        }
        pairingAttempt += 1
        let attempt = pairingAttempt
        var ask = start
        ask.attempt = attempt
        ask.phase = .asking
        homeAsk = ask
        if pairing != .idle { pairing = .idle }
        hostName = ask.name
        status = DiscoveryPolicy.HomeCopy.pairing(mac: ask.name, cable: ask.cableRow)
        let pin = ask.savedID.flatMap { savedMac($0)?.fingerprintData }
        #if DEBUG
        print("home: asking \(ask.name) to pair at \(ask.target.label)\(pin != nil ? ", pinned to its saved key" : "")")
        #endif
        let dialer = HomeDialer(targets: [ask.target], pin: pin, identity: identity, queue: queue)
        homeDialer = dialer
        let deviceName = UIDevice.current.name
        dialer.onWinner = { [weak self, weak dialer] w in
            guard let self, let dialer else { w.connection.cancel(); return }
            let check = self.cableCheck(w.connection)
            #if DEBUG
            print("home: \(check.console)")
            #endif
            self.homeExchange(w, identity: identity, deviceName: deviceName, method: PairRequest.ask, cable: check.cable ? true : nil,
                              key: nil) { outcome in
                DispatchQueue.main.async {
                    guard self.homeDialer === dialer, self.pairingAttempt == attempt else {
                        // Cancelled while the ask was on its way, and the Mac showed a code for it
                        // meanwhile: that code can go too.
                        if case .answer(let r, _) = outcome, r.reason == PairResult.shown {
                            self.withdrawAsk(at: HomeDialer.Target(endpoint: w.endpoint, peerToPeer: w.target.peerToPeer,
                                                                   row: w.target.row, label: w.target.label), key: w.fingerprint)
                        }
                        return
                    }
                    self.homeDialer = nil
                    self.asked(outcome, winner: w, claimed: check.cable, busyRetried: busyRetried)
                }
            }
        }
        dialer.onFailed = { [weak self, weak dialer] failed in
            DispatchQueue.main.async {
                guard let self, let dialer, self.homeDialer === dialer, self.pairingAttempt == attempt else { return }
                self.homeDialer = nil
                self.askFailed(failed)
            }
        }
        dialer.start()
    }

    /// The Mac's answer to the ask (DiscoveryPolicy.askAnswer). Main thread.
    private func asked(_ outcome: HomeExchange, winner w: HomeDialer.Winner, claimed: Bool, busyRetried: Bool) {
        guard var ask = homeAsk else { return }
        guard case .answer(let r, _) = outcome else {
            homeAsk = nil
            status = DiscoveryPolicy.HomeCopy.noAnswer(mac: ask.name)
            return
        }
        let answer = DiscoveryPolicy.askAnswer(ok: r.ok, method: r.method, hasProof: r.proof != nil, reason: r.reason,
                                               retryAfter: r.retryAfter, askedCable: claimed,
                                               macIDMatches: r.macID == MacID.make(fingerprint: w.fingerprint),
                                               recognitionKeyBytes: r.recognitionKey.flatMap(Base64URL.decode)?.count)
        #if DEBUG
        print("home: \(ask.name) answered the ask: \(answer)")
        #endif
        switch answer {
        case .pairedOverCable:
            homeAsk = nil
            guard let id = savePairedAtHome(r, fingerprint: w.fingerprint, method: PairResult.cable, name: ask.name,
                                            bonjourName: Self.bonjourName(ask.target.fallback ?? ask.target.endpoint)) else { return }
            status = DiscoveryPolicy.HomeCopy.pairedOverCable(mac: displayName(id))
            sessionAfterHomePairing(id, target: ask.target)
        case .shown:
            ask.phase = .shown
            ask.askedKey = w.fingerprint
            ask.answered = w.endpoint
            ask.claimedCable = claimed
            homeAsk = ask
            status = DiscoveryPolicy.HomeCopy.showing(mac: ask.name, device: Self.deviceWord)
            #if DEBUG
            // The harness types the code or scans the link the card would (the simulator has no camera,
            // and these gates drive no UI).
            let d = UserDefaults.standard
            if let code = d.string(forKey: "SillHomeCode") {
                print("harness: typing the code into the home card")
                pairHome(code: code)
            } else if let url = d.string(forKey: "SillHomeLink"), case .success(let link) = PairLink.parse(url) {
                print("harness: scanning the link in the home card")
                scanned(link, tapped: true, overlay: false)
            }
            #endif
        case .openOnMac, .refused:
            homeAsk = nil
            // A refusal this build does not know shows the Mac's own words when it sent some
            // (PairResult.message); else, as `openOnMac`, the way that always works: the Mac's menu.
            status = (answer == .refused ? r.unknownReasonMessage : nil) ?? DiscoveryPolicy.HomeCopy.openOnMac(mac: ask.name)
        case .locked:
            homeAsk = nil
            status = DiscoveryPolicy.HomeCopy.locked(mac: ask.name)
        case .busy(let after):
            guard !busyRetried else {
                homeAsk = nil
                status = DiscoveryPolicy.HomeCopy.openOnMac(mac: ask.name)
                return
            }
            let attempt = ask.attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let self, let again = self.homeAsk, again.attempt == attempt, self.pairingAttempt == attempt else { return }
                self.startAsk(again, busyRetried: true)
            }
        case .invalid:
            homeAsk = nil
            status = DiscoveryPolicy.HomeCopy.proofFailed(mac: ask.name)
        }
    }

    /// Nothing answered the ask. A saved Mac's pinned ask that met another key (-9808) tries the
    /// other rows its tag names, then says so in the remote path's words (§7.6). Main thread.
    private func askFailed(_ failed: HomeDialer.Failed) {
        guard let ask = homeAsk else { return }
        homeAsk = nil
        if failed.statuses.contains(DiscoveryPolicy.pinRefused), let id = ask.savedID {
            let tried = ask.tried + [ask.target.row].compactMap { $0 }
            // Rows taken by their Bonjour name alone whose key was another's: not that Mac.
            pinRefusedRows.formUnion(tried.filter { id in macs.first { $0.id == id }.map { $0.macID == nil } ?? false })
            if let next = DiscoveryPolicy.nextPinnedRow(macID: id, tried: tried, rows: homeRows()),
               let row = macs.first(where: { $0.id == next }) {
                self.ask(row, savedID: id, tagNamed: ask.tagNamed, tried: tried)
                return
            }
            status = RemoteCopy.dialFailure(.wrongMac, mac: displayName(id), candidate: nil, vpnName: nil, device: Self.deviceWord)
            return
        }
        status = DiscoveryPolicy.HomeCopy.noAnswer(mac: ask.name)
    }

    /// Cancel on the home card (and a new tap, and the Add a Mac card's Cancel): the ask or the
    /// proof in flight stops, and nothing is saved. The ask's own status line ("Pairing with Mac
    /// mini…", "Mac mini is showing a code…") goes with it, back to the idle one, which
    /// updateDiscovery keeps in step with the search; any other line (a failure's) stays. A session
    /// that connects clears an ask too (`idleStatus` false: its own line follows).
    func cancelHomeAsk(idleStatus: Bool = true) {
        homeDialer?.cancel()
        homeDialer = nil
        guard let ask = homeAsk else { return }
        pairingAttempt += 1
        homeAsk = nil
        // The Mac showed a code for this ask: it can go now, rather than stay up its 5 minutes.
        if ask.phase == .shown, let key = ask.askedKey, let answered = ask.answered {
            withdrawAsk(at: askedTarget(ask, answered), key: key)
        }
        if idleStatus, status == DiscoveryPolicy.HomeCopy.pairing(mac: ask.name, cable: ask.cableRow)
            || status == DiscoveryPolicy.HomeCopy.showing(mac: ask.name, device: Self.deviceWord) {
            status = Self.lookingOnNetwork
            updateDiscovery()
        }
    }

    /// The Cancel of an ask the Mac answered "shown" (§7.5): kind 19 "cancel" on a `sill-pair/1`
    /// connection to where the ask was answered, pinned to the key that answered, so the window it
    /// opened closes (withdrawn) instead of staying up for its 5 minutes with a live code. Nothing
    /// waits for it and nothing follows from its answer (always "closed"): the Mac closes only a
    /// window this device's own ask opened and that is still the home door's alone. Main thread.
    func withdrawAsk(at target: HomeDialer.Target, key: Data) {
        guard let identity = try? DeviceIdentity.loadOrCreate() else { return }
        homeWithdrawal?.cancel()
        let dialer = HomeDialer(targets: [target], pin: key, identity: identity, queue: queue)
        homeWithdrawal = dialer
        let deviceName = UIDevice.current.name
        #if DEBUG
        print("home: telling \(target.label) its code is no longer needed")
        #endif
        dialer.onWinner = { [weak self, weak dialer] w in
            guard let self, let dialer else { w.connection.cancel(); return }
            self.homeExchange(w, identity: identity, deviceName: deviceName, method: PairRequest.cancel, cable: nil, key: nil) { _ in
                DispatchQueue.main.async { if self.homeWithdrawal === dialer { self.homeWithdrawal = nil } }
            }
        }
        dialer.onFailed = { [weak self, weak dialer] _ in
            DispatchQueue.main.async { if let self, self.homeWithdrawal === dialer { self.homeWithdrawal = nil } }
        }
        dialer.start()
    }

    // MARK: Proofs at the home door (§7.5)

    /// The home card's typed code: checked here first (a typo never uses up one of the Mac's five
    /// tries), then `sill-pair/1` to the connection the ask reached, pinned to the key it saw, kind
    /// 19 `code` with proof_D from the PBKDF2 key.
    func pairHome(code text: String) {
        guard let ask = homeAsk, ask.phase == .shown, let key = ask.askedKey, let answered = ask.answered else { return }
        switch PairingCode.check(text) {
        case .failure(.length): pairing = .failed(.codeLength)
        case .failure(.typo): pairing = .failed(.codeTypo)
        case .success(let code):
            homeProof(targets: [askedTarget(ask, answered)], pin: key, method: PairRequest.code,
                      key: { fp in PairingProof.codeKey(code: code, macFingerprint: fp) },
                      name: ask.name, overlay: false, link: nil, scannedSecret: nil)
        }
    }

    /// The ask's answered endpoint as a target: the same Mac, pinned to the key it showed.
    private func askedTarget(_ ask: HomeAsk, _ answered: NWEndpoint) -> HomeDialer.Target {
        HomeDialer.Target(endpoint: answered, peerToPeer: ask.target.peerToPeer, row: ask.target.row, label: ask.name)
    }

    /// Where Pair This iPad… pairs over a session at home that speaks TLS (§7.5): the session's own
    /// connection's endpoint, pinned to the key the session saw, never kind 18's addresses (a
    /// window a device opened starts no remote door). Nil over a plain session and a remote one,
    /// which pair as before.
    var sessionPairingTarget: (target: HomeDialer.Target, key: Data)? {
        guard connected, let s = session, !s.route.isRemote, let trust = s.home, let c = connection,
              case .key(let key) = DiscoveryPolicy.pin(trust) else { return nil }
        return (HomeDialer.Target(endpoint: c.endpoint, peerToPeer: connectedDirectly, row: s.row?.id, label: "this session's Mac"), key)
    }

    /// This session runs at home over TLS: Pair This iPad… pairs at its own door, whatever the
    /// Mac's Remote Access says (the Settings panel's Away from home, DiscoveryPolicy.awayFromHome).
    /// DEBUG: the harness's settings cases say so instead (`mockHomeTLS`).
    var sessionAtHomeOverTLS: Bool {
        #if DEBUG
        if let mock = mockHomeTLS { return mock }
        #endif
        return sessionPairingTarget != nil
    }

    /// Pair This iPad…'s typed code: over a TLS session at home, on the session's row; over any
    /// other, through the connection's kind 18 address as before.
    func pairOverlayTyped(code text: String, mac: String) {
        guard let t = sessionPairingTarget else {
            guard let address = overlayAddress() else {
                pairing = .failed(.notPairing(mac))
                return
            }
            pairTyped(code: text, address: address, overlay: true)
            return
        }
        switch PairingCode.check(text) {
        case .failure(.length): pairing = .failed(.codeLength)
        case .failure(.typo): pairing = .failed(.codeTypo)
        case .success(let code):
            homeProof(targets: [t.target], pin: t.key, method: PairRequest.code,
                      key: { fp in PairingProof.codeKey(code: code, macFingerprint: fp) },
                      name: mac, overlay: true, link: nil, scannedSecret: nil)
        }
    }

    /// A pairing link at home, scanned in the home card or over a stream, or confirmed from outside
    /// the app (§7.5): to the connection the ask reached when the link names the key it saw (over a
    /// stream, the session's own); else every home row with `p`, pinned to the link's key, one at a
    /// time (DiscoveryPolicy.linkRows: the Mac whose code it is answers, a look-alike cannot); then,
    /// none answering, the link's own addresses, as before (a window a device opened lists none:
    /// "Nothing answered…").
    func pairLinkAtHome(_ link: PairLink, overlay: Bool, scanned: Bool) {
        let secret = scanned ? link.secret : nil
        let qr: (Data) -> SymmetricKey? = { _ in PairingProof.qrKey(secret: link.secret) }
        if let ask = homeAsk, ask.phase == .shown, let key = ask.askedKey, key == link.fingerprint, let answered = ask.answered {
            homeProof(targets: [askedTarget(ask, answered)], pin: key, method: PairRequest.qr, key: qr,
                      name: ask.name, overlay: false, link: nil, scannedSecret: secret)
            return
        }
        if overlay, let t = sessionPairingTarget, t.key == link.fingerprint {
            homeProof(targets: [t.target], pin: t.key, method: PairRequest.qr, key: qr,
                      name: macName.isEmpty ? link.name : macName, overlay: true, link: nil, scannedSecret: secret)
            return
        }
        let asked = homeAsk.flatMap { a in a.askedKey.map { (key: $0, row: a.target.row) } }
        let ids = DiscoveryPolicy.linkRows(linkKey: link.fingerprint, askedKey: asked?.key, askedRow: asked?.row,
                                           rows: macs.filter { $0.route != .remote }.map { (id: $0.id, door: $0.door) }) ?? []
        let targets = ids.compactMap { id in macs.first { $0.id == id } }.compactMap { mac -> HomeDialer.Target? in
            guard let endpoint = mac.endpoint else { return nil }
            let wired = wiredDial(for: mac)
            return HomeDialer.Target(endpoint: wired?.endpoint ?? endpoint, fallback: wired != nil ? endpoint : nil,
                                     peerToPeer: mac.direct, row: mac.id, label: wired?.via ?? mac.name)
        }
        guard !targets.isEmpty else {
            pair(link: link, overlay: overlay, scanned: scanned)
            return
        }
        homeProof(targets: targets, pin: link.fingerprint, method: PairRequest.qr, key: qr, name: link.name, overlay: overlay,
                  link: link, scannedSecret: secret)
    }

    /// A proof at the home door: `sill-pair/1` to each target in turn, pinned to `pin`, kind 19
    /// `qr` or `code` with proof_D; kind 20 ok with proof_M checked and naming that key: saved
    /// (`homeTLS`, the Bonjour name), then a pinned session on the row, or over a stream the
    /// session goes on, now with a saved Mac. No target answering: a link's own addresses
    /// (`link`), else the words. `busy`: one silent retry.
    private func homeProof(targets: [HomeDialer.Target], pin: Data, method: String, key makeKey: @escaping (Data) -> SymmetricKey?,
                           name: String, overlay: Bool, link: PairLink?, scannedSecret: Data?, busyRetried: Bool = false) {
        guard let identity = deviceIdentity() else { return }
        lastScannedSecret = scannedSecret
        homeDialer?.cancel()
        pairingDial?.cancel()
        pairingDial = nil
        pairingAttempt += 1
        let attempt = pairingAttempt
        if var ask = homeAsk { ask.attempt = attempt; homeAsk = ask }
        pairing = .working("Pairing with \(name)\u{2026}")
        #if DEBUG
        print("home: pairing with \(name) (\(method)) at \(targets.map(\.label)), pinned")
        #endif
        let dialer = HomeDialer(targets: targets, pin: pin, identity: identity, queue: queue)
        homeDialer = dialer
        let deviceName = UIDevice.current.name
        let retry: (Double) -> Void = { [weak self] after in
            DispatchQueue.main.asyncAfter(deadline: .now() + after) {
                guard let self, self.pairingAttempt == attempt else { return }   // cancelled, or another pairing began
                self.homeProof(targets: targets, pin: pin, method: method, key: makeKey, name: name, overlay: overlay, link: link,
                               scannedSecret: scannedSecret, busyRetried: true)
            }
        }
        dialer.onWinner = { [weak self, weak dialer] w in
            guard let self, let dialer else { w.connection.cancel(); return }
            self.homeExchange(w, identity: identity, deviceName: deviceName, method: method, cable: nil, key: makeKey) { outcome in
                DispatchQueue.main.async {
                    guard self.homeDialer === dialer, self.pairingAttempt == attempt else { return }
                    self.homeDialer = nil
                    self.proved(outcome, winner: w, identity: identity, method: method, name: name, overlay: overlay,
                                busyRetried: busyRetried, retry: retry)
                }
            }
        }
        dialer.onFailed = { [weak self, weak dialer] _ in
            DispatchQueue.main.async {
                guard let self, let dialer, self.homeDialer === dialer, self.pairingAttempt == attempt else { return }
                self.homeDialer = nil
                if let link {
                    #if DEBUG
                    print("home: no row answered for \(link.name)'s key; pairing through the link's addresses")
                    #endif
                    self.pair(link: link, overlay: overlay, scanned: scannedSecret != nil)
                    return
                }
                self.pairing = .failed(overlay ? .noAnswerOverStream(name) : .homeNoAnswer(name))
            }
        }
        dialer.start()
    }

    /// The Mac's answer to a proof at the home door. Main thread.
    private func proved(_ outcome: HomeExchange, winner w: HomeDialer.Winner, identity: RemoteIdentity, method: String, name: String,
                        overlay: Bool, busyRetried: Bool, retry: (Double) -> Void) {
        // Over a stream (Pair This iPad…) no row can be tapped: its words say what to do there.
        let proofFailed: PairingProblem = overlay ? .proofFailedOverStream(name) : .homeProofFailed(name)
        guard case .answer(let r, let key) = outcome else {
            pairing = .failed(proofFailed)
            return
        }
        guard r.ok else {
            if r.reason == PairResult.busy, !busyRetried {
                retry(max(0.2, min(r.retryAfter ?? 1, 10)))      // once, silently
                return
            }
            pairing = .failed(Self.homeProblem(for: r, mac: name, overStream: overlay))
            return
        }
        // Nothing is saved unless the Mac proved it knows the same key, for the keys of this very
        // connection, and names itself by that key.
        guard let key, let proofM = r.proof.flatMap(Base64URL.decode),
              PairingProof.isValidMacProof(proofM, key: key, macFingerprint: w.fingerprint, deviceFingerprint: identity.fingerprint),
              r.macID == MacID.make(fingerprint: w.fingerprint), r.recognitionKey.flatMap(Base64URL.decode)?.count == 32 else {
            pairing = .failed(proofFailed)
            return
        }
        // Over a stream whose Mac is the one just paired, the session is now with a saved Mac and
        // the record takes that session's verified kind 18 (its addresses and port).
        let sessionKey: Data? = session.flatMap { $0.home }.flatMap { if case .key(let k) = DiscoveryPolicy.pin($0) { return k }; return nil }
        let sameMac = overlay && connected && sessionKey == w.fingerprint
        let info = sameMac ? macInfoVerified.flatMap { $0.fingerprint == w.fingerprint ? $0.info : nil } : nil
        guard let id = savePairedAtHome(r, fingerprint: w.fingerprint, method: method, name: name,
                                        bonjourName: sameMac ? session?.bonjourName : Self.bonjourName(w.target.fallback ?? w.target.endpoint),
                                        info: info) else { return }
        pairing = .paired(displayName(id))
        #if DEBUG
        print("home: paired with \(displayName(id)) (\(id)) at the home door, proof_M checked, pin saved\(overlay ? (sameMac ? "; this session's Mac" : "; not this session's Mac") : "")")
        #endif
        if overlay {
            if sameMac {
                session?.macID = id
                session?.home = .saved(pin: w.fingerprint)
                macInfoSaved = true
            }
            return
        }
        homeAsk = nil
        sessionAfterHomePairing(id, target: w.target)
    }

    /// A refused proof at the home door: the home card's words (DiscoveryPolicy.homeRefusal), which
    /// send the person back to the Mac's row only where a tap gets a new code ("expired"), else to
    /// the Sill menu on the Mac first; over a stream (`overStream`, Pair This iPad…), where there is
    /// no row, the remote path's, which send them to the Sill menu on the Mac.
    static func homeProblem(for r: PairResult, mac: String, overStream: Bool = false) -> PairingProblem {
        if overStream { return problem(for: r, mac: mac) }
        // A reason this build does not know, with the Mac's own words for it: those, not a guess.
        if let words = r.unknownReasonMessage { return .macSaid(words) }
        switch DiscoveryPolicy.homeRefusal(reason: r.reason, triesLeft: r.triesLeft) {
        case .wrongCode(let left): return .wrongCode(triesLeft: left)
        case .stopped: return .homeStopped(mac)
        case .expired: return .homeExpired(mac)
        case .closed: return .homeClosed(mac)
        }
    }

    /// Kind 20 ok, checked: the Mac saved as the remote path saves it, plus what the home door
    /// teaches: `homeTLS` (its door speaks TLS: no plain dial of it ever again) and the Bonjour name
    /// (§7.5). The port and addresses come from the session's first kind 18, or from `info`, the
    /// verified kind 18 of a session with this very Mac. Returns its Mac ID.
    private func savePairedAtHome(_ r: PairResult, fingerprint: Data, method: String, name fallbackName: String,
                                  bonjourName: String?, info: MacInfo? = nil) -> String? {
        guard let macID = r.macID, let recognition = r.recognitionKey else { return nil }
        let label = SafeText.label(r.name ?? fallbackName)
        var mac = SavedMac(macID: macID, fingerprint: Base64URL.encode(fingerprint), name: label.isEmpty ? "Mac" : label,
                           recognitionKey: recognition, remotePort: HostConfigDefaults.remotePort, addresses: [], typedAddresses: nil,
                           infoIssuedAt: 0, bonjourName: bonjourName, lastWorked: nil, pairedAt: Date(), method: method,
                           lastConnectedAt: nil, lastRoute: nil, homeTLS: true, revoked: nil)
        if let info { mac = SavedMacs.refreshed(mac, info: info, fingerprint: fingerprint, allowLoopback: Self.keepsLoopback) ?? mac }
        savedMacs = SavedMacs.adding(mac, to: savedMacs)
        persistSavedMacs()
        return macID
    }

    /// After a pairing at home: a pinned session on the row the pairing went to (its wired
    /// interface first, as a tap dials it), or at the address (DEBUG `-SillConnect`); no session
    /// within 10 s leaves the Mac as a saved row.
    private func sessionAfterHomePairing(_ macID: String, target: HomeDialer.Target) {
        guard let pin = savedMac(macID)?.fingerprintData else { return }
        let name = displayName(macID)
        if let id = target.row, let row = macs.first(where: { $0.id == id }), row.endpoint != nil {
            dialRow(row, macID: macID, trust: .saved(pin: pin), tagNamed: row.macID != nil)
        } else {
            connect(to: target.fallback ?? target.endpoint, name: name, peerToPeer: target.peerToPeer, macID: macID,
                    trust: .saved(pin: pin))
        }
        let watch = DispatchWorkItem { [weak self] in
            guard let self, !self.connected else { return }
            if let c = self.connection { self.connection = nil; c.cancel(); self.tearDown(status: self.status, restartSearch: false) }
            self.pairing = .idle
            self.status = "\(self.displayName(macID)) is saved. Tap it to connect."
            self.discoveryChanged()
        }
        afterPairingWatch?.cancel()
        afterPairingWatch = watch
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watch)
    }

    /// A Bonjour row's service name, for the saved record; nil for an address.
    static func bonjourName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    // MARK: The exchange

    enum HomeExchange {
        /// Kind 20, and the key the proof was made with (nil for the ask).
        case answer(PairResult, SymmetricKey?)
        /// The connection failed, closed, or no kind 20 came within 15 s.
        case noAnswer
    }

    /// One pairing connection's exchange at home, on `queue`: kind 19, then kind 20 within 15 s;
    /// the connection is closed after. `key`, for a proof (`qr`, `code`), is made from the Mac's key
    /// as this connection saw it, off the network queue, which may be carrying a session's frames
    /// (the typed path's PBKDF2 takes 90–160 ms); nil for the ask, which carries no proof. `cable`
    /// only on the ask. `deviceName` is read on the main thread by the caller.
    private func homeExchange(_ w: HomeDialer.Winner, identity: RemoteIdentity, deviceName: String, method: String, cable: Bool?,
                              key makeKey: ((Data) -> SymmetricKey?)?, done: @escaping (HomeExchange) -> Void) {
        let c = w.connection
        let fpMac = w.fingerprint, fpDevice = identity.fingerprint
        var finished = false
        let queue = self.queue
        func finish(_ outcome: HomeExchange) {
            guard !finished else { return }
            finished = true
            c.cancel()
            done(outcome)
        }
        c.stateUpdateHandler = { state in
            if case .failed = state { queue.async { finish(.noAnswer) } }
        }
        queue.asyncAfter(deadline: .now() + RemoteDialPolicy.pairingReplyDeadline) { finish(.noAnswer) }
        let send: (SymmetricKey?) -> Void = { key in
            guard !finished else { return }
            let proof = key.map { Base64URL.encode(PairingProof.deviceProof(key: $0, deviceFingerprint: fpDevice, macFingerprint: fpMac)) } ?? ""
            let request = PairRequest(method: method, proof: proof, name: deviceName,
                                      model: ClientStatsReporter.hardwareIdentifier, cable: cable)
            let message = StreamMessage(kind: .pairRequest, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                        payload: Wire.encode(request))
            c.send(content: message.serialized(), completion: .contentProcessed { _ in })
            c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { data, _, _, _ in
                guard let data, let header = StreamMessage.parseHeader(data), header.kind == .pairResult,
                      header.payloadLength > 0, header.payloadLength <= StreamMessage.maxPairingPayload else {
                    finish(.noAnswer)
                    return
                }
                c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { data, _, _, _ in
                    guard let data, let result = Wire.decode(PairResult.self, from: data) else {
                        finish(.noAnswer)
                        return
                    }
                    finish(.answer(result, key))
                }
            }
        }
        guard let makeKey else {
            send(nil)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let key = makeKey(fpMac) else { queue.async { finish(.noAnswer) }; return }
            queue.async { send(key) }
        }
    }

    // MARK: The cable, as this device sees it (§7.5)

    /// §7.5's check over the ask's ready connection (on `queue`): the Mac's address and the
    /// interface it is scoped to, from the connection's path, against this device's own addresses
    /// (DiscoveryPolicy.onCable). DEBUG `-SillCableTest 1` counts this device's path as the cable:
    /// the simulator has no cable of its own.
    func cableCheck(_ c: NWConnection) -> DiscoveryPolicy.CableCheck {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillCableTest") {
            return DiscoveryPolicy.CableCheck(cable: true, console: "cable: yes (-SillCableTest)")
        }
        #endif
        guard case .hostPort(let host, _)? = c.currentPath?.remoteEndpoint else {
            return DiscoveryPolicy.CableCheck(cable: false, console: "cable: no, the path names no address")
        }
        switch host {
        case .ipv6(let a):
            return DiscoveryPolicy.onCable(mac: [UInt8](a.rawValue), scope: a.interface.map(Self.policyInterface), own: Self.ownAddresses())
        case .ipv4(let a):
            return DiscoveryPolicy.onCable(mac: [UInt8](a.rawValue), scope: nil, own: Self.ownAddresses())
        default:
            return DiscoveryPolicy.CableCheck(cable: false, console: "cable: no, the Mac has a name, not an address")
        }
    }

    /// This device's addresses on interfaces that are up (getifaddrs), each with its interface:
    /// IPv4 and IPv6, a link-local IPv6 one with the scope the kernel embeds in it
    /// (DiscoveryPolicy.unscoped drops it).
    static func ownAddresses() -> [(interface: String, address: [UInt8])] {
        var out: [(interface: String, address: [UInt8])] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = entry.pointee
            guard let addr = i.ifa_addr, i.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: i.ifa_name)
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                let a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                out.append((name, withUnsafeBytes(of: a) { Array($0) }))
            case AF_INET6:
                let a = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                out.append((name, withUnsafeBytes(of: a) { Array($0) }))
            default:
                break
            }
        }
        return out
    }
}
