// #140 in the remote-rules check: a saved Mac gone after Sill was force-quit, so the code had to be
// scanned at every launch. The device's launch, a pairing, a SIGKILL and the next launch, as
// StreamClient (init, startRemote, paired, storeSavedMacs) and DeviceIdentity (knownMissing,
// loadOrCreate, makeKey) chain the rules, through a stand-in Keychain and UserDefaults with each way
// either can fail. The glue is a copy (the real one touches the Keychain); the rules are the app's
// own: DeviceKeyPolicy, and SavedMacs' encode, decode and adding. Called from main.swift.
//
// What it shows: only the launch's clearing empties the list, and only when the Keychain says the
// key is not there; a key the Keychain does not give back is never paired with (before: a pairing
// that served one launch, then the Mac gone and one more key of this device on the Mac at every
// launch, #140's pattern); a failed read never makes a second key; a lost UserDefaults write, the
// story of #224's mirror, would lose the Mac once and pair the same key again.
import Foundation

// MARK: The stand-in phone

private let duplicate: Int32 = -25299, locked: Int32 = -25308, refusedNow: Int32 = -34018


private struct Phone {
    typealias K = DeviceKeyPolicy
    var tags: [Data]
    var keys: [Data: [Data]] = [:]          // the Keychain: fingerprints under each tag, kept across launches
    var defaults: String?                   // UserDefaults' Sill.savedMacs, kept across launches
    var previousDefaults: String?
    // How the Keychain and UserDefaults fail (all truthful by default).
    var launchAnswer: K.Answer?             // what the launch's status query says, when not the truth
    var readAnswer: K.Answer?               // what a read at a pairing says, when not the truth
    var keepsMade = true                    // SecKeyCreateRandomKey(kSecAttrIsPermanent) keeps the key it returns
    var keepsAdded = true                   // SecItemAdd keeps it
    var findable = true                     // a kept key is found again by the tag query
    var unreadableDefaults = false          // UserDefaults unreadable at launch (before the first unlock)
    var losesLastWrite = false              // the SIGKILL loses the last write (never seen; #224's story)
    // The process.
    var cached: Data?
    var saved: [SavedMac] = []
    var serial: UInt8 = 0
    var lastError: String?
    var cleared = 0
    var clearedWithAKey = false             // a launch cleared while some tag had a key the query finds
    // The Mac: this device's keys it trusts (re-pairing a key replaces its record).
    var macTrusts: [Data] = []

    init(tags: [Data]) { self.tags = tags }

    func truth(_ tag: Data) -> K.Answer { findable && !(keys[tag] ?? []).isEmpty ? .found : .notFound }
    var tag: Data { tags[0] }

    /// StreamClient.init, then startRemote's clearing (DeviceIdentity.knownMissing).
    mutating func launch() {
        cached = nil
        saved = SavedMacs.decode(unreadableDefaults ? nil : defaults)
        if !saved.isEmpty, K.clearsSavedMacs(tags.map { launchAnswer ?? truth($0) }) {
            if tags.contains(where: { truth($0) == .found }) { clearedWithAKey = true }
            saved = []
            store()
            cleared += 1
        }
    }

    mutating func store() { previousDefaults = defaults; defaults = SavedMacs.encode(saved) }

    /// DeviceIdentity.loadOrCreate and makeKey.
    mutating func loadOrCreate() -> Data? {
        if let cached { return cached }
        switch K.load(readAnswer ?? truth(tag)) {
        case .use:
            guard let k = keys[tag]?.first else { lastError = "no key given back"; return nil }
            cached = k
            return k
        case .fail(let status):
            lastError = "the Keychain didn’t answer: \(status)"
            return nil
        case .make:
            serial += 1
            let k = Data(repeating: serial, count: 32)
            if keepsMade { keys[tag, default: []].append(k) }
            var added: Int32?
            for _ in 0..<2 {
                let back: K.Answer = findable && (keys[tag] ?? []).contains(k) ? .found : (readAnswer ?? .notFound)
                switch K.made(readBack: back, added: added) {
                case .use:
                    cached = k
                    return k
                case .add:
                    if (keys[tag] ?? []).contains(k) { added = duplicate }
                    else if keepsAdded { keys[tag, default: []].append(k); added = 0 }
                    else { added = refusedNow }
                case .fail(let status):
                    keys[tag]?.removeAll { $0 == k }      // deleted again by its reference, never left beside the paired one
                    lastError = "the Keychain didn’t keep it: \(status)"
                    return nil
                }
            }
            lastError = "the Keychain didn’t keep it"
            return nil
        }
    }

    /// paired(): the key first (a pairing that cannot start sends nothing), then the Mac trusts
    /// it, and the record is written at once (storeSavedMacs), before the session.
    @discardableResult mutating func pair(_ mac: SavedMac) -> Bool {
        lastError = nil
        guard let k = loadOrCreate() else { return false }
        macTrusts.removeAll { $0 == k }
        macTrusts.append(k)
        saved = SavedMacs.adding(mac, to: saved)
        store()
        return true
    }

    mutating func kill() {
        if losesLastWrite { defaults = previousDefaults }
        cached = nil
        saved = []
    }

    /// A restore from another device's backup: UserDefaults travel, the ThisDeviceOnly key does not.
    mutating func restoredElsewhere() { keys = [:]; cached = nil }

    var listed: Bool { !saved.isEmpty }
    /// The key a dial would use (DeviceIdentity.existing) is one the Mac trusts.
    var admitted: Bool {
        let k = cached ?? (truth(tag) == .found ? keys[tag]?.first : nil)
        return listed && k.map { macTrusts.contains($0) } == true
    }
    var keysUnderTag: Int { keys[tag]?.count ?? 0 }
}


func launchModel() {
    typealias K = DeviceKeyPolicy
    let realTag = Data("me.saffer.sill.device-key".utf8), seTag = Data("me.saffer.sill.device-key.se".utf8)

    // MARK: The rules, case by case

    check("launch: the saved Macs go only when every tag says there is no key (a restore from another device's backup)",
          K.clearsSavedMacs([.notFound]) && K.clearsSavedMacs([.notFound, .notFound]))
    check("launch: a key under any tag keeps them (a DEBUG run whose Secure Enclave tag alone has none)",
          !K.clearsSavedMacs([.found]) && !K.clearsSavedMacs([.found, .notFound]) && !K.clearsSavedMacs([.notFound, .found]))
    check("launch: a read that failed is no proof (-25308 while locked, -34018), under any tag",
          !K.clearsSavedMacs([.failed(locked)]) && !K.clearsSavedMacs([.notFound, .failed(refusedNow)])
          && !K.clearsSavedMacs([.failed(refusedNow), .notFound]))
    check("launch: no tag asked, nothing cleared", !K.clearsSavedMacs([]))
    check("load: the key found is used, a key made only when there is none", K.load(.found) == .use && K.load(.notFound) == .make)
    check("load: any other answer fails with its status, never a second key", K.load(.failed(locked)) == .fail(locked)
          && K.load(.failed(refusedNow)) == .fail(refusedNow))
    check("made: given back, used at once or after the add", K.made(readBack: .found, added: nil) == .use && K.made(readBack: .found, added: 0) == .use)
    check("made: not given back, added once", K.made(readBack: .notFound, added: nil) == .add && K.made(readBack: .failed(locked), added: nil) == .add)
    check("made: still not given back after the add: fails with the add's status, else not found",
          K.made(readBack: .notFound, added: duplicate) == .fail(duplicate) && K.made(readBack: .notFound, added: 0) == .fail(K.itemNotFound)
          && K.itemNotFound == -25300)
    check("made: a read-back that failed after the add fails with its own status", K.made(readBack: .failed(locked), added: 0) == .fail(locked)
          && K.made(readBack: .failed(locked), added: duplicate) == .fail(locked))

    let fp = Data((0..<32).map { UInt8($0 &* 7 &+ 1) })
    let theMac = SavedMac(macID: MacID.make(fingerprint: fp), fingerprint: Base64URL.encode(fp), name: "MacBook Pro",
                          recognitionKey: Base64URL.encode(Data(repeating: 9, count: 32)), remotePort: 7455,
                          addresses: [MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale")], typedAddresses: nil,
                          infoIssuedAt: 0, bonjourName: nil, lastWorked: "100.101.102.103|7455",
                          pairedAt: Date(timeIntervalSince1970: 1_800_000_000), method: "qr", lastConnectedAt: nil, lastRoute: nil)
    /// Launches the person makes: each finds the Mac listed, or scans the code again, then Sill is force-quit.
    func rounds(_ p: inout Phone, _ n: Int) -> (pairings: Int, cleared: Int) {
        var pairings = 0
        for _ in 0..<n {
            p.launch()
            if !p.listed, p.pair(theMac) { pairings += 1 }
            p.kill()
        }
        p.launch()
        return (pairings, p.cleared)
    }

    // MARK: A launch, a pairing, a SIGKILL, the next launch, each way the Keychain and UserDefaults fail

    var p = Phone(tags: [realTag])
    p.launch(); p.pair(theMac); p.kill(); p.launch()
    check("#140 model: nothing fails: after the SIGKILL the Mac is listed and its dial admitted with the key it paired",
          p.listed && p.admitted && p.keysUnderTag == 1 && p.macTrusts.count == 1)
    var r = rounds(&p, 3)
    check("#140 model: nothing fails: three more force-quits, no pairing again, the Mac trusts one key of this device",
          r.pairings == 0 && r.cleared == 0 && p.macTrusts.count == 1)

    p = Phone(tags: [realTag]); p.launch(); p.pair(theMac); p.kill(); p.restoredElsewhere(); p.launch()
    check("#140 model: restored from another device's backup: the saved Mac goes at launch (the key did not travel)",
          !p.listed && p.cleared == 1)
    p.pair(theMac); p.kill(); p.launch()
    check("#140 model: restored: the next pairing makes a key the launch after keeps, listed and admitted",
          p.listed && p.admitted && p.cleared == 1 && p.keysUnderTag == 1)

    p = Phone(tags: [realTag]); p.keepsMade = false; p.keepsAdded = false
    p.launch()
    check("#140 model: a key the Keychain neither keeps nor adds is never paired with: the pairing fails with errSecItemNotFound",
          !p.pair(theMac) && p.lastError == "the Keychain didn’t keep it: -34018" && p.macTrusts.isEmpty && !p.listed)
    r = rounds(&p, 3)
    check("#140 model: never kept: no launch pairs, the Mac never trusts a key of this device that it would lose (before: absent at every relaunch, one more key on the Mac each time)",
          r.pairings == 0 && p.macTrusts.isEmpty && p.keysUnderTag == 0)

    p = Phone(tags: [realTag]); p.keepsMade = false
    p.launch(); p.pair(theMac); p.kill(); p.launch()
    check("#140 model: a key SecKeyCreateRandomKey did not keep but SecItemAdd does: listed and admitted after the SIGKILL",
          p.listed && p.admitted && p.keysUnderTag == 1)

    p = Phone(tags: [realTag]); p.findable = false
    p.launch()
    check("#140 model: a key kept but never found again by the tag query: the pairing fails (the add says it is there: -25299)",
          !p.pair(theMac) && p.lastError == "the Keychain didn’t keep it: -25299" && p.macTrusts.isEmpty)

    for status in [locked, refusedNow] {
        p = Phone(tags: [realTag]); p.launch(); p.pair(theMac); p.kill()
        p.launchAnswer = .failed(status); p.launch()
        check("#140 model: the launch's query fails (\(status)): the saved Mac stays", p.listed && p.cleared == 0)
    }

    p = Phone(tags: [realTag, seTag]); p.launch(); p.pair(theMac); p.kill(); p.launch()
    check("#140 model: DEBUG, the Secure Enclave tag has no key and the real one has: the saved Mac stays", p.listed && p.admitted && p.cleared == 0)
    p.kill(); p.restoredElsewhere(); p.launch()
    check("#140 model: DEBUG, neither tag has a key: cleared", !p.listed && p.cleared == 1)

    p = Phone(tags: [realTag]); p.launch(); p.pair(theMac); p.kill(); p.launch()
    p.saved = []                                      // the person pairs again (Forget, then the code)
    p.readAnswer = .failed(refusedNow)
    check("a pairing whose read fails (-34018) with a key kept fails, and puts no second key under the tag",
          !p.pair(theMac) && p.lastError == "the Keychain didn’t answer: -34018" && p.keysUnderTag == 1)
    p.readAnswer = nil
    check("then a pairing whose read works uses the kept key, the one the Mac knows", p.pair(theMac) && p.macTrusts.count == 1 && p.keysUnderTag == 1)

    p = Phone(tags: [realTag]); p.losesLastWrite = true
    p.launch(); p.pair(theMac); p.kill(); p.launch()
    check("#224's story, a SIGKILL that loses the write (never seen: measured kept 0.1 s after the pairing): absent once",
          !p.listed && p.cleared == 0)
    p.losesLastWrite = false
    p.pair(theMac); p.kill(); p.launch()
    check("#224's story: the next pairing pairs the same key again: the Mac lists this device once (not #140's pattern, a new key each time)",
          p.listed && p.admitted && p.macTrusts.count == 1 && p.keysUnderTag == 1)

    p = Phone(tags: [realTag]); p.launch(); p.pair(theMac); p.kill(); p.unreadableDefaults = true; p.launch()
    check("UserDefaults unreadable at a launch: nothing listed then, nothing cleared, and the next launch has the Mac again",
          !p.listed && p.cleared == 0 && { var q = p; q.kill(); q.unreadableDefaults = false; q.launch(); return q.listed && q.admitted }())

    // MARK: Random lives against the invariants

    var seed: UInt64 = 0x140_224
    func next(_ n: Int) -> Int {          // a fixed sequence, so a failure is the same every run
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 33) % UInt64(n))
    }
    var lives = 0, violations = 0, sawClear = 0, sawRefused = 0, sawKept = 0
    for _ in 0..<4000 {
        var q = Phone(tags: next(4) == 0 ? [realTag, seTag] : [realTag])
        var restores = 0, keysMade = Set<Data>()
        var ok = true
        q.launch()
        for _ in 0..<12 {
            switch next(9) {
            case 0, 1: q.launch()
            case 2, 3:
                let before = q.keysUnderTag, fresh = q.cached == nil
                if q.pair(theMac) {
                    // A pairing that read the Keychain is made only with a key it gives back (one in
                    // memory already serves the rest of the launch, as DeviceIdentity's cache does).
                    ok = ok && (!fresh || (q.cached.map { (q.keys[q.tag] ?? []).contains($0) } == true && q.truth(q.tag) == .found))
                    keysMade.insert(q.cached!)
                } else {
                    sawRefused += 1
                    ok = ok && q.keysUnderTag <= max(before, 1)
                }
            case 4: q.kill(); q.launch()
            case 5: q.restoredElsewhere(); restores += 1
            case 6: q.launchAnswer = [nil, .failed(locked), .failed(refusedNow)][next(3)]
            case 7: q.readAnswer = [nil, nil, .failed(locked), .failed(refusedNow)][next(4)]
            default:
                q.keepsMade = next(3) != 0; q.keepsAdded = next(3) != 0; q.findable = next(5) != 0
            }
            // Never two keys under the tag, whatever failed.
            ok = ok && q.keysUnderTag <= 1
            // The Mac trusts at most one key of this device per key the device made and kept.
            ok = ok && q.macTrusts.count <= restores + 1 && Set(q.macTrusts).isSubset(of: keysMade)
        }
        // A launch cleared the saved Macs only when no tag had a key the query finds.
        ok = ok && !q.clearedWithAKey
        // With the Keychain and UserDefaults truthful from now on, a saved Mac survives the SIGKILL.
        q.launchAnswer = nil; q.readAnswer = nil; q.findable = true; q.keepsMade = true; q.keepsAdded = true
        q.unreadableDefaults = false; q.losesLastWrite = false
        q.launch()
        let had = q.listed || q.pair(theMac)
        q.kill(); q.launch()
        ok = ok && (!had || (q.listed && q.admitted))
        sawClear += q.cleared > 0 ? 1 : 0
        sawKept += q.listed ? 1 : 0
        lives += 1
        if !ok { violations += 1 }
    }
    check("#140 model: \(lives) random lives (pairings, SIGKILLs, restores, every Keychain fault): never two keys under the tag, never a pairing with a key the Keychain does not give back, the Mac trusting no key the device did not keep, a clearing only without a key, and once truthful again the Mac kept across a SIGKILL",
          violations == 0 && sawClear > 0 && sawRefused > 0 && sawKept > 0)
}
