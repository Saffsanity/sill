import Foundation
import CryptoKit

// Files and photos between a device and the Mac (docs/files-plan.md §5, §6 and §10), against Sources/StreamProtocol
// compiled into this binary as one module (module.txt): kind 34 (#66's FileChunk) and kind 49 (FileTransfer) on the
// wire, the window list's `files` and the hello's `files`; FilePolicy's rules at each edge and in their order;
// FileNames on hostile names and 20,000 random ones; FileFlow's windows; the two ledgers (FileReceiver, FileSender)
// case by case, then against each other through a model of the connection, 5,000 transfers each way; every word.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: @autoclosure () -> String, line: Int = #line) {
    check(a == b, "\(what()): got \(a), expected \(b)", line: line)
}
typealias P = FilePolicy
typealias N = FileNames
typealias F = FileFlow
typealias R = FileReceiver
typealias S = FileSender
typealias C = FilesCopy
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
func header(_ kind: UInt8) -> StreamHeader? { StreamMessage.parseHeader(Data([kind]) + Data(count: 9) + Data([0, 0, 0, 2])) }
struct RNG {
    var x: UInt64
    mutating func next() -> UInt64 { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x }
    mutating func int(_ n: Int) -> Int { n <= 1 ? 0 : Int(next() % UInt64(n)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

// MARK: - The kinds

check(StreamMessageKind.fileChunk.rawValue == 34 && StreamMessageKind(rawValue: 34) == .fileChunk, "kind 34 is fileChunk (#66's number)")
check(StreamMessageKind.fileTransfer.rawValue == 49 && StreamMessageKind(rawValue: 49) == .fileTransfer, "kind 49 is fileTransfer")
check(header(34)?.kind == .fileChunk && header(49)?.kind == .fileTransfer, "both headers parse")
check([35, 36, 37, 38, 39, 40, 41, 42, 48].allSatisfy { StreamMessageKind(rawValue: $0) == nil && header($0)?.kind == .unknown },
      "35 to 42 stay #66's and 48 the microphone's: not this build's")

// MARK: - Kind 34: #66's layout, byte for byte

let part = FileChunk.pack(id: 0x0102_0304, name: "", total: 10, offset: 4, bytes: Data([9, 8, 7]))
eq(Array(part), [1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 4, 9, 8, 7], "a part with an empty name, byte for byte")
eq(FileChunk.headerBytes, 22, "22 bytes around the name")
eq(FileChunk.maxBytes, 512 * 1024, "#66's 512 KiB a part")
if let u = FileChunk.unpack(part) {
    check(u.id == 0x0102_0304 && u.name.isEmpty && u.total == 10 && u.offset == 4 && u.bytes == Data([9, 8, 7]), "it unpacks")
} else { check(false, "the part did not unpack") }
let named = FileChunk.pack(id: 7, name: "report.pdf", total: 10, offset: 4, bytes: Data([1, 2, 3, 4, 5, 6]))
check(FileChunk.unpack(named).map { $0.name == "report.pdf" && $0.offset == 4 && $0.bytes.count == 6 } == true, "a name given is read (and ignored by its reader)")
check(FileChunk.unpack(Data([1, 2, 3])) == nil, "a short part does not unpack")
check(FileChunk.unpack(Data([0, 0, 0, 1, 0, 9]) + Data(count: 10)) == nil, "a part whose name runs past its end does not unpack")
check(FileChunk.unpack(Data([0, 0, 0, 1, 0, 0]) + Data(count: 16)).map { $0.bytes.isEmpty && $0.total == 0 } == true, "a part with no bytes unpacks")
let sliced = (Data([0xFF]) + part).dropFirst()
check(FileChunk.unpack(Data(sliced)).map { $0.offset == 4 && $0.bytes == Data([9, 8, 7]) } == true, "a part read from a slice")
let big = FileChunk.pack(id: 1, name: String(repeating: "é", count: 900), total: 1, offset: 0, bytes: Data([1]))
check(FileChunk.unpack(big).map { $0.bytes == Data([1]) && $0.name.utf8.count == 1024 } == true, "a name over 1024 bytes is cut to 1024 when packed")

// MARK: - Kind 49: FileTransfer's JSON

let files = [FileTransfer.File(id: 7, name: "a.pdf", size: 12, type: "com.adobe.pdf"), FileTransfer.File(id: 9, name: "b", size: 0)]
eq(json(FileTransfer.offer(transfer: 5, files: files)),
   #"{"files":[{"id":7,"name":"a.pdf","size":12,"type":"com.adobe.pdf"},{"id":9,"name":"b","size":0}],"op":"offer","transfer":5}"#,
   "an offer, nil fields left out")
eq(json(FileTransfer.offer(transfer: 5, files: [files[1]], drop: .init(x: 0.25, y: 0.5))),
   #"{"drop":{"x":0.25,"y":0.5},"files":[{"id":9,"name":"b","size":0}],"op":"offer","transfer":5}"#, "an offer with a drop")
eq(json(FileTransfer.accepted(transfer: 5)), #"{"accept":true,"op":"answer","transfer":5}"#, "an answer's yes")
eq(json(FileTransfer.refused(transfer: 5, reason: .locked)), #"{"accept":false,"op":"answer","reason":"locked","transfer":5}"#, "an answer's no")
eq(json(FileTransfer.ack(transfer: 5, file: 7, offset: 65536)), #"{"file":7,"offset":65536,"op":"ack","transfer":5}"#, "an ack")
eq(json(FileTransfer.end(transfer: 5, file: 7, sha256: "x")), #"{"file":7,"op":"end","sha256":"x","transfer":5}"#, "an end")
eq(json(FileTransfer.done(transfer: 5, kept: ["a.pdf", "b"], place: "Downloads › Sill")),
   #"{"kept":["a.pdf","b"],"op":"done","place":"Downloads › Sill","transfer":5}"#, "a done")
eq(json(FileTransfer.cancel(transfer: 5, reason: .stalled)), #"{"op":"cancel","reason":"stalled","transfer":5}"#, "a cancel")
eq(json(FileTransfer.pick(transfer: 5)), #"{"op":"pick","transfer":5}"#, "a pick")
eq(FileOp.allCases.map(\.rawValue), ["offer", "answer", "ack", "end", "done", "cancel", "pick"], "the seven ops")
eq(FileReason.allCases.map(\.rawValue), ["off", "notPaired", "locked", "busy", "tooMany", "tooBig", "noRoom", "rate", "declined",
                                         "noAnswer", "stalled", "damaged", "lost", "cantSave", "cantRead", "nothingChosen", "background",
                                         "cancelled"],
   "the eighteen reasons")
for op in FileOp.allCases {
    let t = FileTransfer(op: op.rawValue, transfer: 1)
    check(FileTransfer.parse(t.payload ?? Data()) == t && FileTransfer.parse(t.payload ?? Data())?.knownOp == op, "\(op) round-trips")
}
let later = FileTransfer.parse(Data(#"{"op":"resume","transfer":3,"from":9}"#.utf8))
check(later != nil && later?.knownOp == nil && later?.transfer == 3, "an op from a later build decodes and is not known (ignored)")
let laterReason = FileTransfer.parse(Data(#"{"op":"cancel","transfer":3,"reason":"quota","message":"Over the quota."}"#.utf8))
check(laterReason?.knownReason == nil && laterReason?.message == "Over the quota.", "a reason from a later build decodes with its words")
check(FileTransfer.parse(Data(#"{"transfer":3}"#.utf8)) == nil, "no op: not a FileTransfer")
check(FileTransfer.parse(Data(#"{"op":"offer","transfer":-1}"#.utf8)) == nil, "a negative transfer does not decode")
check(FileTransfer.parse(Data("[1]".utf8)) == nil && FileTransfer.parse(Data()) == nil, "not JSON: nil")
eq(FileTransfer.maxPayload, 512 * 1024, "512 KiB of JSON at most")
check(FileTransfer.maxPayload < StreamMessage.maxClientPayload, "under the host's 1 MiB for a device's message")
let huge = FileTransfer(op: "cancel", transfer: 1, message: String(repeating: "x", count: FileTransfer.maxPayload))
check(huge.payload == nil, "a message over the cap is never sent")
check(FileTransfer.parse(Data(#"{"op":"cancel","message":""#.utf8) + Data(repeating: 0x61, count: FileTransfer.maxPayload) + Data(#""}"#.utf8)) == nil,
      "one received over the cap is refused")
let fullOffer = FileTransfer.offer(transfer: UInt32.max, files: (0..<P.maxFiles).map {
    FileTransfer.File(id: UInt32.max - UInt32($0), name: N.clean(String(repeating: "あ", count: 300)) , size: P.maxBytes, type: "public.data")
})
check((fullOffer.payload?.count ?? .max) < FileTransfer.maxPayload / 2, "500 files with the longest cleaned names fit in half the cap (\(fullOffer.payload?.count ?? -1) bytes)")
struct OlderReader: Decodable { var op: String }
check(Wire.decode(OlderReader.self, from: FileTransfer.offer(transfer: 1, files: files).payload ?? Data())?.op == "offer", "a reader of op alone skips the rest")

// The window list's `files` and the hello's: additive.
var list = WindowList(macName: "Mac mini", windows: [], active: .desktop, launchID: "L", hostVersion: "0.7.0", protocol: 1)
check(!json(list).contains("files"), "a list without it leaves the key out")
list.files = P.takes
check(json(list).contains(#""files":1"#), "a host that takes files says files 1")
check(Wire.decode(WindowList.self, from: Wire.encode(list))?.files == 1, "files round-trips")
struct ListBefore: Decodable { var macName: String; var clipboard: Int? }
check(Wire.decode(ListBefore.self, from: Wire.encode(list))?.macName == "Mac mini", "a device from before skips files")
check(Wire.decode(WindowList.self, from: Data(#"{"macName":"M","windows":[],"active":{"desktop":{}}}"#.utf8)).map { $0.files == nil } == true,
      "a host from before: files nil")
check(Wire.decode(WindowList.self, from: Data(#"{"macName":"M","windows":[],"active":{"desktop":{}},"fileDrop":true}"#.utf8)).map { $0.files == nil } == true,
      "#66's and #189's fileDrop is not files")
eq(P.takes, 1, "takes: 1"); eq(P.gives, 2, "gives: 2"); eq(P.deviceTakes, 1, "a device that takes files: 1")
var hello = Hello(appVersion: "0.7.0")
check(!json(hello).contains("files"), "a hello without it leaves the key out")
hello = Hello(appVersion: "0.7.0", files: P.deviceTakes)
check(json(hello).contains(#""files":1"#) && Wire.decode(Hello.self, from: Wire.encode(hello))?.files == 1, "a device that takes files says files 1")
check(Wire.decode(Hello.self, from: Data(#"{"appVersion":"0.6.2"}"#.utf8))?.files == nil, "a device from before: nil")
struct HelloBefore: Decodable { var appVersion: String?; var audio: [String]? }
check(Wire.decode(HelloBefore.self, from: Wire.encode(hello))?.appVersion == "0.7.0", "a host from before skips it")

// MARK: - An offer, as a receiver reads it

check(P.offer(FileTransfer.offer(transfer: 5, files: files)).map { $0.transfer == 5 && $0.files == files && $0.total == 12 && $0.drop == nil && !$0.asked } == true,
      "an offer reads: its files, their total")
check(P.offer(FileTransfer(op: "offer", files: files)) == nil, "no transfer: not an offer")
check(P.offer(FileTransfer(op: "offer", transfer: 5)) == nil, "no files: not an offer")
check(P.offer(FileTransfer.offer(transfer: 5, files: [])) == nil, "no file: not an offer")
check(P.offer(FileTransfer.offer(transfer: 5, files: [files[0], files[0]])) == nil, "one id twice: not an offer")
check(P.offer(FileTransfer(op: "answer", transfer: 5, files: files)) == nil, "another op: not an offer")
check(P.offer(FileTransfer.offer(transfer: 5, files: [.init(id: 1, name: "a", size: .max), .init(id: 2, name: "b", size: 2)]))?.total == .max,
      "a total past UInt64 saturates")
check(P.offer(FileTransfer.offer(transfer: 5, files: files, drop: .init(x: .nan, y: 0.5)))?.drop == nil, "a drop that is not a number: saved, never dropped")
check(P.offer(FileTransfer.offer(transfer: 5, files: files, drop: .init(x: 2, y: -1)))?.drop == .init(x: 2, y: -1), "a drop off the picture is the drop rule's to judge")
check(P.offer(FileTransfer.offer(transfer: 5, files: files, asked: true))?.asked == true, "asked")

// MARK: - The device offers

eq(P.deviceOffers(connected: false, hostFiles: 1, hostVersion: "0.7", locked: false, sessionPaired: true, sending: false), .hidden, "not connected")
eq(P.deviceOffers(connected: true, hostFiles: 1, hostVersion: "0.7", locked: true, sessionPaired: true, sending: false), .hidden, "a locked Mac")
eq(P.deviceOffers(connected: true, hostFiles: nil, hostVersion: nil, locked: false, sessionPaired: true, sending: false), .hidden, "the CLI: nothing")
eq(P.deviceOffers(connected: true, hostFiles: nil, hostVersion: "0.6.2", locked: false, sessionPaired: true, sending: false), .older, "an older Sill")
eq(P.deviceOffers(connected: true, hostFiles: 0, hostVersion: "0.7", locked: false, sessionPaired: true, sending: false), .off, "its switch off")
eq(P.deviceOffers(connected: true, hostFiles: 1, hostVersion: "0.7", locked: false, sessionPaired: false, sending: false), .notPaired, "unpaired")
eq(P.deviceOffers(connected: true, hostFiles: 1, hostVersion: "0.7", locked: false, sessionPaired: nil, sending: false), .notPaired, "no kind 16 yet")
eq(P.deviceOffers(connected: true, hostFiles: 2, hostVersion: "0.7", locked: false, sessionPaired: true, sending: true), .busy, "a transfer of its own runs")
eq(P.deviceOffers(connected: true, hostFiles: 1, hostVersion: nil, locked: false, sessionPaired: true, sending: false), .yes, "yes (a version or not)")
eq(P.deviceOffers(connected: true, hostFiles: 3, hostVersion: "0.9", locked: false, sessionPaired: true, sending: false), .yes, "a later generation: yes")
eq(P.deviceOffers(connected: true, hostFiles: -1, hostVersion: "0.7", locked: false, sessionPaired: true, sending: false), .off, "below 1: off")

// MARK: - The Mac answers

let offer2 = P.offer(FileTransfer.offer(transfer: 5, files: files))!
var spaceAsked = 0
func answer(_ o: P.Offer = offer2, share: Bool = true, paired: Bool = true, locked: Bool = false, rate: Bool = true,
            device: Int = 0, mac: Int = 0, free: UInt64? = 10_000_000_000) -> FileReason? {
    P.answer(o, shareFiles: share, paired: paired, locked: locked, rateAdmits: rate, runningFromDevice: device, runningOnMac: mac,
             freeSpace: { spaceAsked += 1; return free })
}
eq(answer(), nil, "everything passes: accept")
eq(answer(share: false, paired: false, locked: true, rate: false, device: 1, free: 0), .off, "the switch first")
eq(answer(paired: false, locked: true, rate: false, device: 1, free: 0), .notPaired, "then the trust list")
eq(answer(locked: true, rate: false, device: 1, free: 0), .locked, "then the lock")
eq(answer(rate: false, device: 1, free: 0), .rate, "then the rate")
eq(answer(device: 1, free: 0), .busy, "then another transfer from this device")
eq(answer(mac: P.macTransfers, free: 0), .busy, "or four on the Mac")
eq(answer(mac: P.macTransfers - 1), nil, "three on the Mac: one more")
let many = P.offer(FileTransfer.offer(transfer: 6, files: (0...P.maxFiles).map { .init(id: UInt32($0), name: "f", size: 1) }))!
let enough = P.offer(FileTransfer.offer(transfer: 6, files: (1...P.maxFiles).map { .init(id: UInt32($0), name: "f", size: 1) }))!
eq(answer(many, free: 0), .tooMany, "501 files")
eq(answer(enough), nil, "500 files")
let tooBig = P.offer(FileTransfer.offer(transfer: 7, files: [.init(id: 1, name: "a", size: P.maxBytes), .init(id: 2, name: "b", size: 1)]))!
let atMost = P.offer(FileTransfer.offer(transfer: 7, files: [.init(id: 1, name: "a", size: P.maxBytes)]))!
eq(answer(tooBig, free: 0), .tooBig, "100 GB and a byte")
eq(answer(atMost, free: P.maxBytes + P.keepFree), nil, "100 GB with 2 GB left")
eq(answer(atMost, free: P.maxBytes + P.keepFree - 1), .noRoom, "a byte short of leaving 2 GB")
eq(answer(free: 12 + P.keepFree), nil, "the total and 2 GB: room")
eq(answer(free: 12 + P.keepFree - 1), .noRoom, "a byte less: no room")
eq(answer(free: nil), nil, "free space unreadable: the write's own failure says so")
spaceAsked = 0
_ = answer(share: false); _ = answer(locked: true); _ = answer(rate: false); _ = answer(many)
eq(spaceAsked, 0, "the free space is read only when everything else passed")
_ = answer()
eq(spaceAsked, 1, "and then once")
eq(P.maxFiles, 500, "500 files"); eq(P.maxBytes, 100_000_000_000, "100 GB"); eq(P.keepFree, 2_000_000_000, "2 GB left free")
eq(P.offerRate, 2, "two offers a second"); eq(P.macTransfers, 4, "four transfers on the Mac")
eq(P.answerWait, 60, "60 s to answer"); eq(P.stallLimit, 30, "30 s without progress"); eq(P.panelLimit, 180, "3 minutes for a pick")
eq(P.pickSpacing, 5, "5 s between a device's picks")

// The rate.
var arrivals: [Double] = []
var taken: [Bool] = []
for t in [0.0, 0.1, 0.2, 0.3, 0.999, 1.0, 1.05, 1.1, 1.2] {
    let a = P.admits(arrivals: arrivals, now: t); taken.append(a.taken); arrivals = a.kept
}
eq(taken, [true, true, false, false, false, true, false, true, false], "two a second, the second measured from each taken")
arrivals = []
for i in 0..<10_000 { arrivals = P.admits(arrivals: arrivals, now: Double(i) * 0.0001).kept }
check(arrivals.count <= P.offerRate, "a flood keeps at most two arrivals (\(arrivals.count))")

// The device answers; the Mac offers; a pick.
eq(P.deviceAnswers(offer2, receiving: false, askBefore: true, askedFor: false), .ask, "Ask Before Receiving Files on: ask")
eq(P.deviceAnswers(offer2, receiving: false, askBefore: false, askedFor: false), .accept, "off: accept")
let asked = P.offer(FileTransfer.offer(transfer: 5, files: files, asked: true))!
eq(P.deviceAnswers(asked, receiving: false, askBefore: true, askedFor: true), .accept, "files it asked for: at once")
eq(P.deviceAnswers(asked, receiving: false, askBefore: true, askedFor: false), .ask, "an offer that says asked, not judged so: asked about")
eq(P.deviceAnswers(asked, receiving: true, askBefore: false, askedFor: true), .refuse(.busy), "another running: busy")
eq(P.deviceAnswers(many, receiving: false, askBefore: false, askedFor: false), .refuse(.tooMany), "501 files")
eq(P.deviceAnswers(tooBig, receiving: false, askBefore: false, askedFor: false), .refuse(.tooBig), "past 100 GB")
// Whether an offer answers this device's own pick (askedFor): it says asked, names the pick's transfer, and came in time.
check(P.askedFor(asked, pick: 5, pickedAt: 100, now: 100 + P.panelLimit + P.pickSlack), "asked, its pick's transfer, in time: asked for")
check(!P.askedFor(asked, pick: 5, pickedAt: 100, now: 100.001 + P.panelLimit + P.pickSlack), "past the panel's time and the crossing: asked about")
check(!P.askedFor(asked, pick: 6, pickedAt: 100, now: 101), "another transfer than the pick's: asked about")
check(!P.askedFor(asked, pick: nil, pickedAt: nil, now: 101), "no pick of this device's: asked about")
check(!P.askedFor(asked, pick: 5, pickedAt: nil, now: 101), "a pick with no time: asked about")
check(!P.askedFor(P.offer(FileTransfer.offer(transfer: 5, files: files))!, pick: 5, pickedAt: 100, now: 101), "the pick's transfer, not saying asked: asked about")
eq(P.panelLimit + P.pickSlack, 210, "a pick's answer within 3 minutes and 30 s")
// The device's Get Files row and the receiving switches (deviceGets): only where the Mac gives files.
eq(P.deviceGets(connected: true, hostFiles: 2, locked: false, sessionPaired: true, receiving: false), .yes, "a Mac that gives files: yes")
eq(P.deviceGets(connected: true, hostFiles: 3, locked: false, sessionPaired: true, receiving: false), .yes, "a later generation: yes")
eq(P.deviceGets(connected: true, hostFiles: 1, locked: false, sessionPaired: true, receiving: false), .hidden, "a Mac that only takes files: no row")
eq(P.deviceGets(connected: true, hostFiles: 0, locked: false, sessionPaired: true, receiving: false), .hidden, "its switch off: no row (the send rows say why)")
eq(P.deviceGets(connected: true, hostFiles: nil, locked: false, sessionPaired: true, receiving: false), .hidden, "an older Mac or the CLI: no row")
eq(P.deviceGets(connected: true, hostFiles: 2, locked: true, sessionPaired: true, receiving: false), .hidden, "a locked Mac: no row")
eq(P.deviceGets(connected: false, hostFiles: 2, locked: false, sessionPaired: true, receiving: false), .hidden, "not connected")
eq(P.deviceGets(connected: true, hostFiles: 2, locked: false, sessionPaired: false, receiving: false), .notPaired, "unpaired")
eq(P.deviceGets(connected: true, hostFiles: 2, locked: false, sessionPaired: nil, receiving: false), .notPaired, "no kind 16 yet")
eq(P.deviceGets(connected: true, hostFiles: 2, locked: false, sessionPaired: true, receiving: true), .busy, "a transfer from the Mac runs")
eq(P.macOffers(helloFiles: 1, paired: true, locked: false, shareFiles: true, sendingToDevice: false), nil, "the Mac may offer")
eq(P.macOffers(helloFiles: 1, paired: true, locked: false, shareFiles: false, sendingToDevice: false), .off, "its switch off")
eq(P.macOffers(helloFiles: nil, paired: true, locked: false, shareFiles: true, sendingToDevice: false), .off, "a device from before")
eq(P.macOffers(helloFiles: 1, paired: false, locked: false, shareFiles: true, sendingToDevice: false), .notPaired, "unpaired")
eq(P.macOffers(helloFiles: 1, paired: true, locked: true, shareFiles: true, sendingToDevice: false), .locked, "locked")
eq(P.macOffers(helloFiles: 1, paired: true, locked: false, shareFiles: true, sendingToDevice: true), .busy, "already sending to it")
eq(P.takesPick(helloFiles: 1, paired: true, locked: false, shareFiles: true, sendingToDevice: false, panelUp: true, lastClosed: nil, now: 9), .busy, "a panel up")
eq(P.takesPick(helloFiles: 1, paired: true, locked: false, shareFiles: true, sendingToDevice: false, panelUp: false, lastClosed: 5, now: 9.99), .rate, "closed 4.99 s ago")
eq(P.takesPick(helloFiles: 1, paired: true, locked: false, shareFiles: true, sendingToDevice: false, panelUp: false, lastClosed: 5, now: 10), nil, "closed 5 s ago")
eq(P.takesPick(helloFiles: 1, paired: true, locked: true, shareFiles: true, sendingToDevice: false, panelUp: false, lastClosed: nil, now: 9), .locked, "locked")

// MARK: - Names

let hostile: [(String, String)] = [
    ("report.pdf", "report.pdf"), ("../x", "File..-x"), ("a/b", "a-b"), ("a:b", "a-b"), ("a\u{0}b", "a-b"),
    ("line\nbreak.txt", "linebreak.txt"), ("tab\there", "tabhere"), ("\u{7F}del\u{85}", "del"), ("cv\u{202E}fdp.exe", "cvfdp.exe"),
    ("in\u{2066}vis\u{2069}ible", "invisible"), ("zero\u{200B}width\u{FEFF}", "zerowidth"), ("lrm\u{200E}rlm\u{200F}alm\u{061C}", "lrmrlmalm"),
    ("soft\u{AD}hyphen", "softhyphen"), ("a\u{2028}b\u{2029}c", "abc"), (".hidden", "File.hidden"), ("..", "File"), (".", "File"),
    ("...", "File"), ("  spaced  ", "spaced"), ("trailing.", "trailing"), ("dots...", "dots"), ("   ", "File"), ("", "File"),
    ("\u{202E}", "File"), (" .profile", "File.profile"), ("e\u{301}", "\u{E9}"), ("\u{1F600}.png", "\u{1F600}.png"),
    ("Apple \u{F8FF}", "Apple \u{F8FF}"), ("CON", "CON"), ("a\u{0}", "a-"),
]
for (raw, want) in hostile { eq(N.clean(raw), want, "clean(\(raw.debugDescription))") }
let japanese = String(repeating: "書", count: 90) + ".pdf"
let cleanJ = N.clean(japanese)
check(cleanJ.utf8.count <= N.maxBytes && cleanJ.hasSuffix(".pdf") && cleanJ.hasPrefix("書書"), "a 274-byte Japanese name: cut to \(cleanJ.utf8.count) bytes, .pdf kept")
eq(cleanJ.utf8.count, 199, "65 characters of 3 bytes and .pdf")
let emoji = String(repeating: "👩🏽‍💻", count: 30) + ".mov"
let cleanE = N.clean(emoji)
check(cleanE.utf8.count <= N.maxBytes && cleanE.hasSuffix(".mov") && !cleanE.unicodeScalars.contains("\u{200D}"), "an emoji name: the joiners gone, cut whole, .mov kept")
let longExt = "a." + String(repeating: "x", count: 300)
check(N.clean(longExt).utf8.count <= N.maxBytes && N.clean(longExt).hasPrefix("a.xx"), "an extension over 16 bytes is cut with the rest")
let ext16 = String(repeating: "b", count: 250) + "." + String(repeating: "e", count: 16)
check(N.clean(ext16).hasSuffix("." + String(repeating: "e", count: 16)) && N.clean(ext16).utf8.count == N.maxBytes, "a 16-byte extension kept whole")
let ext17 = String(repeating: "b", count: 250) + "." + String(repeating: "e", count: 17)
check(!N.clean(ext17).contains(".") && N.clean(ext17).utf8.count == N.maxBytes, "a 17-byte extension is cut with the rest")
let giant = "a" + String(repeating: "\u{301}", count: 150) + ".txt"
check(N.clean(giant) == "File.txt", "one character larger than the room: File and its extension, never .txt (\(N.clean(giant)))")
let giantNoExt = "a" + String(repeating: "\u{301}", count: 150)
eq(N.clean(giantNoExt), "File", "one character larger than the room and no extension: File")
let cutAtDot = String(repeating: "c", count: 199) + ".." + String(repeating: "z", count: 40)
check(!N.clean(cutAtDot).hasSuffix(".") && N.clean(N.clean(cutAtDot)) == N.clean(cutAtDot), "a cut that ends at a dot is trimmed")
let nfd = "Cafe\u{301}.txt", nfc = "Caf\u{E9}.txt"
// Swift's String == compares by canonical equivalence: the bytes say whether a name was made NFC.
eq(Array(N.clean(nfd).utf8), Array(N.clean(nfc).utf8), "NFD and NFC twins clean to one name, byte for byte (NFC)")
eq(N.maxBytes, 200, "200 bytes"); eq(N.maxExtensionBytes, 16, "16-byte extensions"); eq(N.fallback, "File", "File")

// unique: case-insensitively against a folder, as APFS by default.
var folder = Set<String>()
func takenIn(_ name: String) -> Bool { folder.contains(name.lowercased()) }
var got: [String] = []
for n in ["a.pdf", "A.pdf", "a.pdf", "a", "a", "b.tar.gz", "b.tar.gz"] {
    if let u = N.unique(N.clean(n), taken: takenIn) { got.append(u); folder.insert(u.lowercased()) }
}
eq(got, ["a.pdf", "A 2.pdf", "a 3.pdf", "a", "a 2", "b.tar.gz", "b.tar 2.gz"], "numbers, case-insensitively")
check(N.unique("x", taken: { _ in true }) == nil, "none free after the tries: nil")
eq(N.unique("x.txt", taken: { $0 != "x 9999.txt" }), "x 9999.txt", "the last number tried")
eq(N.uniqueTries, 9_999, "9,999 numbers")

// 20,000 random names against the rule's properties.
var rng = RNG(x: 0x0F11_E5A5_F11E_5000)
let pieces: [String] = ["a", "Z", "1", " ", ".", "..", "/", ":", "\u{0}", "\n", "\t", "\u{7F}", "\u{85}", "\u{202E}", "\u{2066}", "\u{200B}",
                        "\u{200D}", "\u{FEFF}", "\u{2028}", "\u{301}", "e", "é", "書", "😀", "👩🏽‍💻", "\u{E0067}", "ﷺ", "\u{F8FF}", "\u{3000}",
                        "\u{A0}", "-", "_", "~", "pdf", "tar", ".gz", "\u{1F1FA}\u{1F1F8}"]
var nameBroken: String?
var uniqueFolder = Set<String>()
for i in 0..<20_000 {
    var raw = ""
    for _ in 0..<rng.int(i % 50 == 0 ? 400 : 40) { raw += pieces[rng.int(pieces.count)] }
    let c = N.clean(raw)
    let scalars = Array(c.unicodeScalars)
    var why: String?
    if c.isEmpty { why = "empty" }
    else if c.utf8.count > N.maxBytes { why = "\(c.utf8.count) bytes" }
    else if c.utf8.first == UInt8(ascii: ".") { why = "hidden" }
    else if c.contains("/") || scalars.contains("\u{0}") || c.contains(":") { why = "not one component" }
    else if scalars.contains(where: { [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) }) { why = "an invisible character" }
    else if scalars.first!.properties.isWhitespace || scalars.last!.properties.isWhitespace || scalars.last == "." { why = "untrimmed" }
    else if N.clean(c) != c { why = "not idempotent: \(N.clean(c).debugDescription)" }
    else if Array(c.utf8) != Array(c.precomposedStringWithCanonicalMapping.utf8) { why = "not NFC" }
    if let why, nameBroken == nil { nameBroken = "\(raw.debugDescription) → \(c.debugDescription): \(why)" }
    if let u = N.unique(c, taken: { uniqueFolder.contains($0.lowercased()) }) {
        if uniqueFolder.contains(u.lowercased()) || u.utf8.count > 255 { nameBroken = nameBroken ?? "unique gave \(u) twice or too long" }
        uniqueFolder.insert(u.lowercased())
    }
}
check(nameBroken == nil, "20,000 random names: one component, ≤ 200 bytes, never hidden or empty, nothing invisible, trimmed, NFC, idempotent, unique: \(nameBroken ?? "")")

// MARK: - The window

eq(F.chunkBytes, 64 * 1024, "64 KiB a part")
eq(F.window(away: false, active: false, linkBehind: false), 512 * 1024, "home, idle: 512 KiB")
eq(F.window(away: false, active: true, linkBehind: false), 128 * 1024, "home, active: 128 KiB")
eq(F.window(away: true, active: false, linkBehind: false), 128 * 1024, "away, idle: 128 KiB")
eq(F.window(away: true, active: true, linkBehind: false), 64 * 1024, "away, active: 64 KiB")
for away in [false, true] { for active in [false, true] {
    eq(F.window(away: away, active: active, linkBehind: true), 64 * 1024, "the link behind: 64 KiB (away \(away), active \(active))")
} }
check(F.window(away: false, active: false, linkBehind: false) >= F.chunkBytes && F.tight >= F.chunkBytes, "every window holds a part")
eq(F.active(lastInput: nil, now: 5), false, "no input: idle")
eq(F.active(lastInput: 4.01, now: 5), true, "input 0.99 s ago: active")
eq(F.active(lastInput: 4, now: 5), false, "input 1 s ago: idle")
check(F.maySend(inFlight: 0, count: 600_000, window: 64), "nothing in flight: one part goes whatever the window")
check(F.maySend(inFlight: 448 * 1024, count: 64 * 1024, window: 512 * 1024), "to the window's edge")
check(!F.maySend(inFlight: 448 * 1024 + 1, count: 64 * 1024, window: 512 * 1024), "a byte past it: wait")
check(F.hostMaySend(pendingBytes: 64 * 1024, needsKeyframe: false, keyframesInFlight: 0, sinceFrame: 0), "64 KiB waiting: send")
check(!F.hostMaySend(pendingBytes: 64 * 1024 + 1, needsKeyframe: false, keyframesInFlight: 0, sinceFrame: 0), "more waiting: hold")
check(!F.hostMaySend(pendingBytes: 64 * 1024 + 1, needsKeyframe: false, keyframesInFlight: 0, sinceFrame: nil), "more waiting, nothing streams: hold")
check(!F.hostMaySend(pendingBytes: 0, needsKeyframe: true, keyframesInFlight: 0, sinceFrame: 0.2), "a device waiting for a keyframe while frames go: hold")
check(!F.hostMaySend(pendingBytes: 0, needsKeyframe: true, keyframesInFlight: 0, sinceFrame: 0.999), "and 0.999 s after the last frame: hold")
check(F.hostMaySend(pendingBytes: 0, needsKeyframe: true, keyframesInFlight: 0, sinceFrame: 1.0), "no frame for a second: the wait is not the picture's, send")
check(F.hostMaySend(pendingBytes: 0, needsKeyframe: true, keyframesInFlight: 0, sinceFrame: nil), "no frame since the stream began (nothing picked): send")
check(F.hostMaySend(pendingBytes: 0, needsKeyframe: false, keyframesInFlight: 0, sinceFrame: 30), "a still picture, its keyframe had: send")
check(!F.hostMaySend(pendingBytes: 0, needsKeyframe: false, keyframesInFlight: 1, sinceFrame: 0), "a keyframe on its way: hold")
check(!F.hostMaySend(pendingBytes: 0, needsKeyframe: false, keyframesInFlight: 1, sinceFrame: nil), "a keyframe on its way, whatever streams: hold")
eq(F.keyframeWait, 1.0, "a second without frames")

// MARK: - The receiver, case by case

func sha(_ d: Data) -> String { Base64URL.encode(Data(SHA256.hash(data: d))) }
let goodSHA = sha(Data("x".utf8))
func two() -> R {
    R(offer: P.offer(FileTransfer.offer(transfer: 9, files: [.init(id: 1, name: "../a.pdf", size: 100_000), .init(id: 2, name: "b", size: 0)]))!,
      place: "Downloads › Sill", now: 0)
}
var r = two()
eq(r.files.map(\.name), ["File..-a.pdf", "b"], "names cleaned as offered")
eq(r.phase, .asking, "asking at first")
eq(r.part(id: 1, total: 100_000, offset: 0, count: 10, now: 1), [], "a part before the answer: nothing written")
eq(r.bytesWritten, 0, "nothing")
eq(r.accept(now: 1), [.send(.accepted(transfer: 9)), .open(1)], "accept: the answer, the first file opened")
eq(r.accept(now: 1), [], "accepting twice does nothing")
eq(r.part(id: 1, total: 100_000, offset: 0, count: 65_536, now: 2), [.write(1, offset: 0, count: 65_536), .send(.ack(transfer: 9, file: 1, offset: 65_536))],
   "a part: written, then acknowledged")
eq(r.end(file: 1, sha256: goodSHA, now: 2), [.deletePartials, .send(.cancel(transfer: 9, reason: .damaged)), .stopped("damaged", byPeer: false)],
   "an end before the file is whole: damaged")
func receiving() -> R { var x = two(); _ = x.accept(now: 0); _ = x.part(id: 1, total: 100_000, offset: 0, count: 65_536, now: 1); return x }
let damagedOut: [R.Action] = [.deletePartials, .send(.cancel(transfer: 9, reason: .damaged)), .stopped("damaged", byPeer: false)]
r = receiving(); eq(r.part(id: 2, total: 0, offset: 0, count: 1, now: 2), damagedOut, "a part of the next file first: damaged")
r = receiving(); eq(r.part(id: 7, total: 100_000, offset: 65_536, count: 10, now: 2), damagedOut,
                    "a part of a file not offered, with this file's total and offset: damaged")
r = receiving(); eq(r.part(id: 1, total: 99_999, offset: 65_536, count: 10, now: 2), damagedOut, "another total: damaged")
r = receiving(); eq(r.part(id: 1, total: 100_000, offset: 65_535, count: 10, now: 2), damagedOut, "a gap or an overlap: damaged")
r = receiving(); eq(r.part(id: 1, total: 100_000, offset: 65_537, count: 10, now: 2), damagedOut, "a gap: damaged")
r = receiving(); eq(r.part(id: 1, total: 100_000, offset: 65_536, count: 34_465, now: 2), damagedOut, "past the size: damaged")
r = receiving(); eq(r.part(id: 1, total: 100_000, offset: 65_536, count: 0, now: 2), damagedOut, "an empty part: damaged")
r = R(offer: P.offer(FileTransfer.offer(transfer: 9, files: [.init(id: 1, name: "a", size: 2_000_000)]))!, place: "p", now: 0)
_ = r.accept(now: 0)
eq(r.part(id: 1, total: 2_000_000, offset: 0, count: FileChunk.maxBytes + 1, now: 1),
   [.deletePartials, .send(.cancel(transfer: 9, reason: .damaged)), .stopped("damaged", byPeer: false)], "a part over 512 KiB: damaged")
r = R(offer: P.offer(FileTransfer.offer(transfer: 9, files: [.init(id: 1, name: "a", size: 2_000_000)]))!, place: "p", now: 0)
_ = r.accept(now: 0)
eq(r.part(id: 1, total: 2_000_000, offset: 0, count: FileChunk.maxBytes, now: 1).count, 2, "512 KiB exactly: taken")
r = receiving()
eq(r.part(id: 1, total: 100_000, offset: 65_536, count: 34_464, now: 3).count, 2, "the rest")
eq(r.end(file: 1, sha256: "not base64url!", now: 3), damagedOut, "an end whose hash is not a SHA-256: damaged")
r = receiving(); _ = r.part(id: 1, total: 100_000, offset: 65_536, count: 34_464, now: 3)
eq(r.end(file: 1, sha256: Base64URL.encode(Data(count: 31)), now: 3), damagedOut, "31 bytes is not a SHA-256")
r = receiving(); _ = r.part(id: 1, total: 100_000, offset: 65_536, count: 34_464, now: 3)
eq(r.end(file: 2, sha256: goodSHA, now: 3), damagedOut, "the end of another file: damaged")
r = receiving(); _ = r.part(id: 1, total: 100_000, offset: 65_536, count: 34_464, now: 3)
eq(r.end(file: 1, sha256: goodSHA, now: 3), [.finish(1, sha256: goodSHA)], "whole: finish it")
var r2 = r
eq(r2.finished(1, .damaged, now: 4), damagedOut, "its hash or size differs: damaged")
r2 = r
eq(r2.finished(1, .failed(.noRoom), now: 4), [.deletePartials, .send(.cancel(transfer: 9, reason: .noRoom)), .stopped("noRoom", byPeer: false)], "a full volume")
eq(r.finished(2, .kept("x"), now: 4), [], "a finish of another file: nothing")
eq(r.finished(1, .kept("a.pdf"), now: 4), [.open(2)], "kept: the next file opened")
eq(r.part(id: 2, total: 0, offset: 0, count: 1, now: 4), damagedOut.map { $0 }, "a part of a 0-byte file: damaged")
r = receiving(); _ = r.part(id: 1, total: 100_000, offset: 65_536, count: 34_464, now: 3); _ = r.end(file: 1, sha256: goodSHA, now: 3)
_ = r.finished(1, .kept("a.pdf"), now: 4)
eq(r.end(file: 2, sha256: sha(Data()), now: 5), [.finish(2, sha256: sha(Data()))], "a 0-byte file: its end at once")
eq(r.finished(2, .kept("b 2"), now: 5), [.send(.done(transfer: 9, kept: ["a.pdf", "b 2"], place: "Downloads › Sill")), .completed(["a.pdf", "b 2"])],
   "the last kept: done, with the names as kept and the place")
eq(r.phase, .done, "done")
eq(r.stop(.locked, tellPeer: true), [], "a stop after done: the files stay")
eq(r.peerCancelled("lost"), [], "a cancel after done: nothing")
r = receiving()
eq(r.peerCancelled("stalled"), [.deletePartials, .stopped("stalled", byPeer: true)], "the sender's cancel: partials deleted")
eq(r.part(id: 1, total: 100_000, offset: 65_536, count: 10, now: 9), [], "a part after it: nothing written")
r = receiving()
eq(r.peerCancelled(nil), [.deletePartials, .stopped("lost", byPeer: true)], "a cancel with no reason: lost")
r = receiving()
eq(r.stop(.lost, tellPeer: false), [.deletePartials, .stopped("lost", byPeer: false)], "the connection gone: nothing sent")
r = two()
eq(r.decline(.declined), [.send(.refused(transfer: 9, reason: .declined)), .stopped("declined", byPeer: false)], "declined")
eq(r.accept(now: 3), [], "accepting after a decline does nothing")
r = two()
eq(r.tick(now: P.answerWait - 0.001), [], "asking 59.999 s")
eq(r.tick(now: P.answerWait), [.deletePartials, .send(.cancel(transfer: 9, reason: .noAnswer)), .stopped("noAnswer", byPeer: false)], "asking 60 s: no answer")
r = receiving()
eq(r.tick(now: 1 + P.stallLimit - 0.001), [], "29.999 s since the last part")
eq(r.tick(now: 1 + P.stallLimit), [.deletePartials, .send(.cancel(transfer: 9, reason: .stalled)), .stopped("stalled", byPeer: false)], "30 s: stalled")

// MARK: - The sender, case by case

let entries = [S.Entry(id: 1, size: 200_000), S.Entry(id: 2, size: 0), S.Entry(id: 3, size: 70_000)]
var s = S(transfer: 4, files: entries, now: 0)
eq(s.phase, .offering, "offering at first")
eq(s.next(window: 1 << 20), nil, "nothing goes before the answer")
eq(s.answered(.refused(transfer: 4, reason: .locked), now: 1), [.stopped("locked", byPeer: true)], "refused: stopped with its reason")
s = S(transfer: 4, files: entries, now: 0)
eq(s.answered(FileTransfer(op: "answer", transfer: 4, accept: false), now: 1), [.stopped("declined", byPeer: true)], "refused without a reason: declined")
s = S(transfer: 4, files: entries, now: 0)
eq(s.answered(FileTransfer(op: "answer", transfer: 4), now: 1), [.stopped("declined", byPeer: true)], "an answer without accept: no")
s = S(transfer: 4, files: entries, now: 0)
eq(s.answered(.accepted(transfer: 4), now: 1), [], "accepted")
let w = 128 * 1024
eq(s.next(window: w), .sendPart(1, offset: 0, count: 65_536), "the first part")
eq(s.next(window: w), .sendPart(1, offset: 65_536, count: 65_536), "the second, to the window's edge")
eq(s.next(window: w), nil, "the window full")
eq(s.inFlight, 131_072, "128 KiB in flight")
eq(s.acked(file: 1, offset: 65_536, now: 2), [], "an ack")
eq(s.next(window: w), .sendPart(1, offset: 131_072, count: 65_536), "the window moved")
_ = s.acked(file: 1, offset: 196_608, now: 2)
eq(s.next(window: w), .sendPart(1, offset: 196_608, count: 3_392), "the file's last bytes")
eq(s.next(window: w), .sendEnd(1), "its end")
eq(s.next(window: w), .sendEnd(2), "a 0-byte file: its end at once")
eq(s.next(window: w), .sendPart(3, offset: 0, count: 65_536), "the next file")
eq(s.next(window: w), .sendPart(3, offset: 65_536, count: 4_464), "its last bytes, within the window (3,392 + 65,536 + 4,464)")
eq(s.next(window: w), .sendEnd(3), "the last end")
eq(s.phase, .finishing, "finishing")
eq(s.next(window: w), nil, "nothing more")
eq(s.done(.done(transfer: 4, kept: ["a", "b", "c"], place: "p")), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)],
   "a done before every byte is acknowledged: damaged")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
while let a = s.next(window: 1 << 30) { if case .sendPart = a { continue } }
eq(s.acked(file: 1, offset: 200_001, now: 1), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)],
   "an ack past a file's size, though within what was sent")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
while let a = s.next(window: 1 << 30) { if case .sendPart = a { continue } }
eq(s.acked(file: 8, offset: 1, now: 1), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)], "an ack of no file")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
_ = s.next(window: w)
eq(s.acked(file: 1, offset: 65_537, now: 1), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)], "an ack past what was sent")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
_ = s.next(window: w); _ = s.next(window: w); _ = s.acked(file: 1, offset: 100_000, now: 1)
eq(s.acked(file: 1, offset: 99_999, now: 1), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)], "an ack going back")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
_ = s.next(window: w); _ = s.acked(file: 1, offset: 65_536, now: 1)
eq(s.acked(file: 1, offset: 65_536, now: 1), [], "the same ack twice: fine")
eq(s.acked(file: nil, offset: 1, now: 1), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)], "an ack without a file")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
while s.next(window: 1 << 30) != nil {}
_ = s.acked(file: 3, offset: 70_000, now: 5)
eq(s.done(.done(transfer: 4, kept: ["a", "b"], place: "p")), [.send(.cancel(transfer: 4, reason: .damaged)), .stopped("damaged", byPeer: false)],
   "a done that names two of three files: damaged")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
while s.next(window: 1 << 30) != nil {}
_ = s.acked(file: 3, offset: 70_000, now: 5)
let doneMessage = FileTransfer.done(transfer: 4, kept: ["a", "b", "c"], place: "p")
eq(s.done(doneMessage), [.completed(doneMessage)], "done")
eq(s.stop(.lost, tellPeer: false), [], "a stop after done: nothing")
s = S(transfer: 4, files: entries, now: 0)
eq(s.tick(now: P.answerWait - 0.001), [], "59.999 s without an answer")
eq(s.tick(now: P.answerWait), [.send(.cancel(transfer: 4, reason: .noAnswer)), .stopped("noAnswer", byPeer: false)], "60 s: no answer")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 10); _ = s.next(window: w)
eq(s.tick(now: 10 + P.stallLimit - 0.001), [], "29.999 s without an ack")
eq(s.tick(now: 10 + P.stallLimit), [.send(.cancel(transfer: 4, reason: .stalled)), .stopped("stalled", byPeer: false)], "30 s: stalled")
s = S(transfer: 4, files: entries, now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
eq(s.peerCancelled("noRoom"), [.stopped("noRoom", byPeer: true)], "the receiver's cancel")
eq(s.next(window: w), nil, "nothing after it")
s = S(transfer: 4, files: [S.Entry(id: 1, size: 10)], now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
eq(s.next(window: 1), .sendPart(1, offset: 0, count: 10), "a window smaller than a part: the first still goes")
eq(s.next(window: 1), .sendEnd(1), "then its end")
s = S(transfer: 4, files: [S.Entry(id: 1, size: 65_537)], now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
eq([s.next(window: 1 << 20), s.next(window: 1 << 20), s.next(window: 1 << 20)], [.sendPart(1, offset: 0, count: 65_536), .sendPart(1, offset: 65_536, count: 1), .sendEnd(1)],
   "65,537 bytes: a part, its last byte, its end")
s = S(transfer: 4, files: [S.Entry(id: 1, size: 1_000_000)], now: 0); _ = s.answered(.accepted(transfer: 4), now: 0)
_ = s.next(window: w); _ = s.acked(file: 1, offset: 65_536, now: 20)
eq(s.tick(now: 49.999), [], "an ack at 20 s: no stall until 50 s")
eq(s.tick(now: 50), [.send(.cancel(transfer: 4, reason: .stalled)), .stopped("stalled", byPeer: false)], "30 s after the last ack: stalled")

// MARK: - The two ledgers against each other

/// The model's file contents: byte i of file `id` is (id + i) mod 251.
func content(_ id: UInt32, _ size: UInt64) -> Data { Data((0..<Int(size)).map { UInt8((Int(id) + $0) % 251) }) }
enum Carried { case part(UInt32, UInt64, UInt64, Data), msg(FileTransfer) }
var modelBroken: String?
var completed = 0, cancelledRuns = 0, refusedRuns = 0, damagedSeen = 0, outOfOrderSeen = 0, undisturbed = 0
for direction in ["device → Mac", "Mac → device"] {
    for run in 0..<5_000 {
        func broke(_ why: String) { if modelBroken == nil { modelBroken = "\(direction) run \(run): \(why)" } }
        let n = 1 + rng.int(rng.chance(0.1) ? 12 : 4)
        var ids = Set<UInt32>()
        var offered: [FileTransfer.File] = []
        for _ in 0..<n {
            var id = UInt32(1 + rng.int(1_000_000)); while ids.contains(id) { id += 1 }
            ids.insert(id)
            let size = [UInt64(0), 1, 65_535, 65_536, 65_537, 200_000, UInt64(rng.int(300_000))][rng.int(7)]
            offered.append(.init(id: id, name: ["a", "../b", ".c", "d.pdf"][rng.int(4)], size: size))
        }
        var now = 0.0
        let transfer = UInt32(run)
        var sender = S(transfer: transfer, files: offered.map { S.Entry(id: $0.id, size: $0.size) }, now: now)
        let offerMessage = FileTransfer.offer(transfer: transfer, files: offered)
        guard let o = P.offer(offerMessage) else { broke("the model's offer did not read"); continue }
        var receiver = R(offer: o, place: "Downloads › Sill", now: now)
        var toReceiver: [Carried] = [.msg(offerMessage)], toSender: [Carried] = []
        var staged: [UInt32: Data] = [:]          // the receiver's staging files
        var kept: [UInt32: Data] = [:]            // kept files, by id
        var opened = Set<UInt32>()
        var corrupt = Set<UInt32>()               // files one of whose parts the model damaged on the way
        var hashes: [UInt32: SHA256] = [:]        // the sender's running hash, by file
        var contents: [UInt32: Data] = [:]        // each file's bytes, made once
        func bytesOf(_ id: UInt32, _ size: UInt64) -> Data {
            if let d = contents[id] { return d }
            let d = content(id, size); contents[id] = d; return d
        }
        let locked = rng.chance(0.1), paired = !rng.chance(0.1), shareOn = !rng.chance(0.05)
        let askBefore = rng.chance(0.5)
        var connectionUp = true
        var disturbed = false                     // anything that may rightly stop it: then it need not complete
        var window = [64 * 1024, 128 * 1024, 512 * 1024, 1][rng.int(4)]
        func runReceiver(_ actions: [R.Action]) {
            for a in actions {
                switch a {
                case .send(let t): if connectionUp { toSender.append(.msg(t)) }
                case .open(let id):
                    if opened.contains(id) { broke("opened \(id) twice") }
                    opened.insert(id); staged[id] = Data()
                case .write: broke("a write outside a part")
                case .finish(let id, let claimed):
                    let data = staged[id] ?? Data()
                    let entry = receiver.files.first { $0.id == id }!
                    let result: R.Finish = (UInt64(data.count) != entry.size || sha(data) != claimed) ? .damaged
                        : (rng.chance(0.01) ? .failed(.cantSave) : .kept(entry.name))
                    if case .failed = result { disturbed = true }
                    if case .kept = result {
                        kept[id] = data; staged[id] = nil
                        if corrupt.contains(id) { broke("kept a file the model damaged") }
                    }
                    if result == .damaged { damagedSeen += 1 }
                    runReceiver(receiver.finished(id, result, now: now))
                    return                                   // `finish` is always the last action
                case .deletePartials: staged = [:]
                case .completed(let names):
                    if names.count != offered.count || kept.count != offered.count { broke("completed with \(kept.count) of \(offered.count) kept") }
                case .stopped: break
                }
            }
        }
        func runSender(_ actions: [S.Action]) {
            for a in actions {
                switch a {
                case .send(let t): if connectionUp { toReceiver.append(.msg(t)) }
                case .sendPart(let id, let offset, let count):
                    if sender.inFlight > UInt64(max(window, F.chunkBytes)) { broke("\(sender.inFlight) in flight, the window \(window)") }
                    let size = offered.first { $0.id == id }!.size
                    var bytes = bytesOf(id, size).subdata(in: Int(offset)..<(Int(offset) + count))
                    hashes[id, default: SHA256()].update(data: bytes)
                    if rng.chance(0.005) { bytes[0] ^= 0xFF; corrupt.insert(id); disturbed = true }
                    if connectionUp {
                        toReceiver.append(.part(id, size, offset, bytes))
                        if rng.chance(0.001) { toReceiver.append(.part(id, size, offset, bytes)); disturbed = true }   // a part sent twice: out of order
                    }
                case .sendEnd(let id):
                    let digest = Base64URL.encode(Data((hashes[id] ?? SHA256()).finalize()))
                    if connectionUp { toReceiver.append(.msg(.end(transfer: transfer, file: id, sha256: digest))) }
                case .completed, .stopped: break
                }
            }
        }
        func deliverToReceiver() {
            guard !toReceiver.isEmpty else { return }
            switch toReceiver.removeFirst() {
            case .part(let id, let total, let offset, let bytes):
                let was = receiver.takesParts
                let wasWritten = receiver.files.first { $0.id == id }?.written
                let acts = receiver.part(id: id, total: total, offset: offset, count: bytes.count, now: now)
                if !was, !acts.isEmpty { broke("a part acted on while not receiving") }
                if case .write(let wid, let woff, let wcount)? = acts.first {
                    if wid != id || woff != offset || wcount != bytes.count || staged[wid].map({ UInt64($0.count) }) != woff { broke("a write out of place") }
                    if rng.chance(0.003) { disturbed = true; runReceiver(receiver.stop(.cantSave, tellPeer: true)); return }   // the write failed: the rest skipped
                    staged[wid, default: Data()].append(bytes)
                    runReceiver(Array(acts.dropFirst()))
                } else {
                    if was, let w0 = wasWritten, w0 != offset { outOfOrderSeen += 1 }
                    runReceiver(acts)
                }
            case .msg(let t):
                switch t.knownOp {
                case .offer?:
                    if direction == "device → Mac" {
                        let why = P.answer(o, shareFiles: shareOn, paired: paired, locked: locked, rateAdmits: true,
                                           runningFromDevice: 0, runningOnMac: 0, freeSpace: { nil })
                        if let why { refusedRuns += 1; disturbed = true; runReceiver(receiver.decline(why)) }
                        else {
                            if locked || !paired || !shareOn { broke("accepted while locked, unpaired or off") }
                            runReceiver(receiver.accept(now: now))
                        }
                    } else {
                        switch P.deviceAnswers(o, receiving: false, askBefore: askBefore, askedFor: false) {
                        case .accept: runReceiver(receiver.accept(now: now))
                        case .refuse(let why): disturbed = true; runReceiver(receiver.decline(why))
                        case .ask:
                            switch rng.int(3) {                       // Accept, Decline, or nobody (the clock decides)
                            case 0: runReceiver(receiver.accept(now: now))
                            case 1: disturbed = true; runReceiver(receiver.decline(.declined))
                            default: disturbed = true
                            }
                        }
                    }
                case .end?: runReceiver(receiver.end(file: t.file, sha256: t.sha256, now: now))
                case .cancel?: runReceiver(receiver.peerCancelled(t.reason))
                default: break
                }
            }
        }
        func deliverToSender() {
            guard !toSender.isEmpty, case .msg(let t) = toSender.removeFirst() else { return }
            switch t.knownOp {
            case .answer?: runSender(sender.answered(t, now: now))
            case .ack?: runSender(sender.acked(file: t.file, offset: t.offset, now: now))
            case .done?: runSender(sender.done(t))
            case .cancel?: runSender(sender.peerCancelled(t.reason))
            default: break
            }
        }
        func tick(_ dt: Double) {
            if dt >= P.stallLimit, !(sender.isOver && receiver.isOver) { disturbed = true }
            now += dt; runSender(sender.tick(now: now)); runReceiver(receiver.tick(now: now))
        }
        var steps = 0
        while steps < 3_000, !(sender.isOver && receiver.isOver && toReceiver.isEmpty && toSender.isEmpty) {
            steps += 1
            switch rng.int(100) {
            case 0..<40: deliverToReceiver()
            case 40..<68: deliverToSender()
            case 68..<88: if let a = sender.next(window: window) { runSender([a]) }
            case 88..<92: window = [64 * 1024, 128 * 1024, 512 * 1024, 1][rng.int(4)]
            case 92..<97: tick([0.01, 0.5, 5, 31, 61][rng.int(5)])
            case 97: disturbed = true; runSender(sender.stop(.background, tellPeer: true))      // the sender's person cancels
            case 98: disturbed = true; runReceiver(receiver.stop([.locked, .notPaired, .off][rng.int(3)], tellPeer: true))   // a lock, a cut-off, the switch
            default:
                if connectionUp, rng.chance(0.3) {                                                   // the connection is gone
                    disturbed = true
                    connectionUp = false
                    toReceiver = []; toSender = []
                    runSender(sender.stop(.lost, tellPeer: false)); runReceiver(receiver.stop(.lost, tellPeer: false))
                }
            }
            if case .cancelled = receiver.phase, !staged.isEmpty { broke("partials left after a stop") }
        }
        // Drain: deliver everything with the window wide open, then let the clock run out; three times.
        for _ in 0..<3 {
            var guardSteps = 0
            while guardSteps < 200_000, !toReceiver.isEmpty || !toSender.isEmpty || sender.phase == .sending {
                guardSteps += 1
                deliverToReceiver(); deliverToSender()
                if let a = sender.next(window: 512 * 1024) { runSender([a]) }
                else if toReceiver.isEmpty, toSender.isEmpty { break }
            }
            tick(61)
        }
        if !sender.isOver || !receiver.isOver { broke("not over after the clock ran out: \(sender.phase), \(receiver.phase)") }
        if !disturbed, sender.phase != .done { broke("nothing stopped it, yet it did not complete: \(sender.phase), \(receiver.phase)") }
        if !disturbed { undisturbed += 1 }
        if sender.phase == .done {
            completed += 1
            if receiver.phase != .done { broke("the sender done, the receiver \(receiver.phase)") }
            for f in offered where kept[f.id] != bytesOf(f.id, f.size) { broke("file \(f.id) kept wrong") }
        } else { cancelledRuns += 1 }
        if case .cancelled = receiver.phase, !staged.isEmpty { broke("partials left at the end") }
        if receiver.phase == .done, kept.count != offered.count { broke("done with \(kept.count) of \(offered.count)") }
    }
}
check(modelBroken == nil, "10,000 transfers through the model: never past the window, never written unaccepted or out of place, never kept damaged, partials gone at every stop, every one over, done only with every file kept: \(modelBroken ?? "")")
check(completed > 1_000 && cancelledRuns > 1_000 && refusedRuns > 100 && damagedSeen > 10 && outOfOrderSeen > 5 && undisturbed > 500,
      "the model reached every ending (\(completed) done, \(cancelledRuns) stopped, \(refusedRuns) refused, \(damagedSeen) damaged, \(outOfOrderSeen) out of order, \(undisturbed) undisturbed)")

// MARK: - The words

for reason in FileReason.allCases {
    let line = C.reasonLine(reason.rawValue, mac: "Mac mini", device: "iPad", name: "a.pdf")
    check(!line.isEmpty && line.hasSuffix(".") && !line.contains("‹") && !line.contains("  "), "\(reason)'s line: \(line)")
    check(C.logReason(reason.rawValue) != C.logReason("nonsense"), "\(reason) has its own words in the log")
}
eq(C.reasonLine("locked", mac: "Mac mini", device: "iPad"), "Mac mini is locked. Unlock it to send files.", "locked")
eq(C.reasonLine("notPaired", mac: "Mac mini", device: "iPad"), "Files go only between paired devices.", "notPaired")
eq(C.reasonLine("off", mac: "Mac mini", device: "iPad"), "Mac mini doesn’t take files now.", "off")
eq(C.reasonLine("busy", mac: "Mac mini", device: "iPad"), "Another transfer with Mac mini is still going. Try again when it’s done.", "busy")
eq(C.reasonLine("tooMany", mac: "M", device: "D"), "That’s more than 500 files. Send fewer at a time.", "tooMany")
eq(C.reasonLine("tooBig", mac: "M", device: "D"), "That’s more than 100 GB. Send less at a time.", "tooBig")
eq(C.reasonLine("noRoom", mac: "Mac mini", device: "D"), "There isn’t enough room on Mac mini for these files.", "noRoom")
eq(C.reasonLine("rate", mac: "M", device: "D"), "Too many at once. Try again in a moment.", "rate")
eq(C.reasonLine("declined", mac: "M", device: "iPad"), "iPad declined the files.", "declined")
eq(C.reasonLine("noAnswer", mac: "M", device: "iPad"), "Nobody answered on iPad.", "noAnswer")
eq(C.reasonLine("stalled", mac: "M", device: "D"), "The transfer stopped moving. Send it again.", "stalled")
eq(C.reasonLine("damaged", mac: "M", device: "D", name: "a.pdf"), "“a.pdf” didn’t arrive whole. Send it again.", "damaged")
eq(C.reasonLine("damaged", mac: "M", device: "D"), "The file didn’t arrive whole. Send it again.", "damaged without a name")
eq(C.reasonLine("lost", mac: "Mac mini", device: "D"), "The connection to Mac mini ended. Send it again.", "lost")
eq(C.reasonLine("cantSave", mac: "Mac mini", device: "D", name: "a.pdf"), "Mac mini couldn’t save “a.pdf”.", "cantSave")
eq(C.reasonLine("cantRead", mac: "M", device: "iPad", name: "a.pdf"), "Sill couldn’t read “a.pdf” on this iPad.", "cantRead")
eq(C.reasonLine("background", mac: "M", device: "D"), "Sending stopped when Sill left the screen. Send it again.", "background")
eq(C.reasonLine("cancelled", mac: "M", device: "D"), "The transfer was stopped.", "cancelled")
eq(C.stoppedLine("cancelled", device: "iPad", byPeer: true), "Files: iPad cancelled (its person stopped it).", "a person's cancel in the log")
eq(C.reasonLine("quota", mac: "Mac mini", device: "D", message: "Over\nthe \u{202E}quota."), "Over the quota.", "a reason not known: its words, cleaned")
eq(C.reasonLine("quota", mac: "Mac mini", device: "D"), "Mac mini couldn’t take the files.", "a reason not known, no words")
eq(C.size(0), "0 bytes", "0 bytes"); eq(C.size(1), "1 byte", "1 byte"); eq(C.size(999), "999 bytes", "999 bytes")
eq(C.size(1_000), "1.0 KB", "1.0 KB"); eq(C.size(12_345_678), "12 MB", "12 MB"); eq(C.size(1_234_567), "1.2 MB", "1.2 MB")
eq(C.size(100_000_000_000), "100 GB", "100 GB")
eq(C.savedLine(files: 2, bytes: 12_300_000, device: "iPad", folder: "Downloads/Sill", seconds: 4.06),
   "Files: saved 2 files (12 MB) from iPad in Downloads/Sill in 4.1 s.", "the saved line")
eq(C.offeredLine(files: 1, bytes: 1, device: "iPad"), "Files: iPad offers 1 file (1 byte).", "the offered line")
eq(C.stoppedLine("lost", device: "iPad", byPeer: false), "Files: the transfer from iPad stopped (the connection ended).", "a stop's line")
eq(C.stoppedLine("background", device: "iPad", byPeer: true), "Files: iPad cancelled (Sill left the screen).", "a cancel's line")
eq(C.refusedLine(["notPaired": 2, "locked": 1, "off": 0]), "Files: refused 3 offers from devices: not paired (2), locked (1).", "the refusals' line")
eq(C.refusedLine(["rate": 1]), "Files: refused 1 offer from devices: too many offers (1).", "one refusal")
eq(C.refusedLine(["quota": 2, "busy": 1]), "Files: refused 3 offers from devices: busy (1), other (2).", "a category not known")
eq(C.defaultPlace, "Downloads › Sill", "the place")
for line in [C.savedLine(files: 1, bytes: 1, device: "iPad", folder: "Downloads/Sill", seconds: 1), C.offeredLine(files: 1, bytes: 1, device: "iPad"),
             C.stoppedLine("damaged", device: "iPad", byPeer: false)] {
    check(line.hasPrefix("Files: ") && !line.contains("\n"), "a log line begins with the feature: \(line)")
}

// MARK: - The device's words (iOSClient/FilesCopy+Device.swift) and its rows

typealias DC = DeviceFilesCopy
eq(DC.rows(.hidden), DC.Rows(shown: false, enabled: false), "hidden: no rows")
eq(DC.rows(.yes), DC.Rows(shown: true, enabled: true), "yes: the rows, enabled")
for o in [P.Offering.older, .off, .notPaired, .busy] { eq(DC.rows(o), DC.Rows(shown: true, enabled: false), "\(o): shown, disabled") }
eq(DC.footnote(.hidden, mac: "Mac mini", device: "iPad"), nil, "hidden: no footnote")
eq(DC.footnote(.notPaired, mac: "Mac mini", device: "iPad"), "Files go only between paired devices. Pair this iPad with Mac mini to send files.", "unpaired")
eq(DC.footnote(.off, mac: "Mac mini", device: "iPad"), "Mac mini doesn’t take files now. Turn on Share files with devices in Sill’s Settings on Mac mini.", "off")
eq(DC.footnote(.older, mac: "Mac mini", device: "iPad"), "To send files, update Sill on Mac mini.", "older")
check(DC.footnote(.yes, mac: "Mac mini", device: "iPad")?.contains("Downloads › Sill on Mac mini") == true
      && DC.footnote(.busy, mac: "Mac mini", device: "iPad") == DC.footnote(.yes, mac: "Mac mini", device: "iPad"), "yes and busy: where they go")
eq(DC.sendFiles(mac: "Mac mini"), "Send Files to Mac mini…", "the files row"); eq(DC.sendPhotos(mac: "Mac mini"), "Send Photos to Mac mini…", "the photos row")
func shot(_ phase: OutgoingFiles.Phase, names: [String] = ["IMG_1204.heic"], total: UInt64 = 1_000, acked: UInt64 = 0) -> OutgoingFiles {
    OutgoingFiles(serial: 1, phase: phase, names: names, total: total, acked: acked, since: 0)
}
eq(DC.title(shot(.preparing), mac: "Mac mini", device: "iPad"), "Getting “IMG_1204.heic” ready…", "preparing")
eq(DC.title(shot(.preparing, names: ["a", "b", "c"]), mac: "Mac mini", device: "iPad"), "Getting 3 files ready…", "preparing three")
eq(DC.title(shot(.sending), mac: "Mac mini", device: "iPad"), "Sending “IMG_1204.heic” to Mac mini", "sending")
eq(DC.title(shot(.offering, names: ["a", "b"]), mac: "Mac mini", device: "iPad"), "Sending 2 files to Mac mini", "offering two")
eq(DC.detail(shot(.offering), mac: "Mac mini"), "Waiting for Mac mini…", "waiting for the answer")
eq(DC.detail(shot(.sending, acked: 425), mac: "Mac mini"), "42%", "42%")
eq(DC.detail(shot(.finishing, acked: 999), mac: "Mac mini"), "99%", "never 100% before the Mac wrote every byte")
eq(DC.detail(shot(.done(.done(transfer: 1, kept: ["a"], place: "x"))), mac: "M"), nil, "no detail once over")
eq(DC.percent(1), "100%", "100%"); eq(DC.percent(.nan), "0%", "not a number: 0%"); eq(DC.percent(-1), "0%", "below 0: 0%")
eq(shot(.sending, total: 0).fraction, 0, "no bytes: 0 while it runs"); eq(shot(.done(.done(transfer: 1, kept: [], place: "x")), total: 0).fraction, 1, "and 1 once done")
eq(DC.title(shot(.done(.done(transfer: 1, kept: ["IMG_1204.heic"], place: "Downloads › Sill"))), mac: "Mac mini", device: "iPad"),
   "Saved in Downloads › Sill on Mac mini.", "saved")
eq(DC.title(shot(.done(.done(transfer: 1, kept: ["a", "b"], place: "Desktop\n\u{202E}")), names: ["a", "b"]), mac: "Mac mini", device: "iPad"),
   "Saved 2 files in Desktop on Mac mini.", "saved two, the Mac's place cleaned")
eq(DC.title(shot(.done(FileTransfer(op: "done", transfer: 1, kept: ["a"]))), mac: "Mac mini", device: "iPad"),
   "Saved in Downloads › Sill on Mac mini.", "no place from the Mac: the default")
eq(DC.title(shot(.stopped(reason: "cancelled", message: nil, byPeer: false, name: nil)), mac: "Mac mini", device: "iPad"), "Sending stopped.", "own Cancel")
eq(DC.title(shot(.stopped(reason: "cancelled", message: nil, byPeer: true, name: nil)), mac: "Mac mini", device: "iPad"),
   "Mac mini stopped the transfer.", "the Mac's person stopped it")
eq(DC.title(shot(.stopped(reason: DC.folderReason, message: nil, byPeer: false, name: "Holiday")), mac: "M", device: "iPad"),
   "“Holiday” is a folder. Sill sends files, not folders.", "a folder")
eq(DC.title(shot(.stopped(reason: "locked", message: nil, byPeer: true, name: nil)), mac: "Mac mini", device: "iPad"),
   "Mac mini is locked. Unlock it to send files.", "the shared reasons")
eq(DC.title(shot(.stopped(reason: "quota", message: "Over quota.", byPeer: true, name: nil)), mac: "Mac mini", device: "iPad"), "Over quota.",
   "a reason not known: the Mac's words")
check(!DC.warns(shot(.stopped(reason: "cancelled", message: nil, byPeer: false, name: nil))) && DC.warns(shot(.stopped(reason: "cancelled", message: nil, byPeer: true, name: nil)))
      && DC.warns(shot(.stopped(reason: "lost", message: nil, byPeer: false, name: nil))) && !DC.warns(shot(.sending)), "a warning but for the person's own Cancel")
eq(DC.spoken(shot(.sending, acked: 500), mac: "Mac mini", device: "iPad"), "Sending “IMG_1204.heic” to Mac mini, 50%", "spoken")
eq(DC.announcement(shot(.offering), mac: "Mac mini", device: "iPad"), "Sending “IMG_1204.heic” to Mac mini.", "announced at the start")
eq(DC.announcement(shot(.sending), mac: "Mac mini", device: "iPad"), nil, "not while it runs")
check(DC.announcement(shot(.stopped(reason: "lost", message: nil, byPeer: false, name: nil)), mac: "Mac mini", device: "iPad") != nil, "announced at a stop")
check(shot(.sending).isOver == false && shot(.stopped(reason: "lost", message: nil, byPeer: false, name: nil)).isOver, "isOver")
check(!OutgoingFiles.holdsMoves(nil) && OutgoingFiles.holdsMoves(shot(.preparing)) && OutgoingFiles.holdsMoves(shot(.finishing))
      && !OutgoingFiles.holdsMoves(shot(.done(.done(transfer: 1, kept: [], place: "x")))), "the session's moves wait while a transfer runs, and only then")

// MARK: - Files from the Mac, the device's words (iOSClient/FilesCopy+Device.swift)

eq(DC.getFiles(mac: "Mac mini"), "Get Files from Mac mini…", "the Get Files row")
eq(DC.askBeforeTitle, "Ask Before Receiving Files", "the ask switch"); eq(DC.photosTitle, "Save Photos and Videos to Photos", "the photos switch")
eq(DC.receiveFootnote(askBefore: true, photos: false, mac: "Mac mini", device: "iPad"),
   "Files from Mac mini are in the Files app, in On My iPad › Sill. Sill asks before saving files Mac mini sends you; files you get with Get Files come at once.",
   "the footnote, asking")
eq(DC.receiveFootnote(askBefore: false, photos: true, mac: "Mac mini", device: "iPhone"),
   "Files from Mac mini are in the Files app, in On My iPhone › Sill. Files Mac mini sends you are saved without asking. Photos and videos from Mac mini go to your Photos library.",
   "the footnote, not asking, photos to Photos")
eq(DC.folderName(mac: "Mac mini"), "From Mac mini", "the folder"); eq(DC.folderName(mac: ""), "From Mac", "no name: From Mac")
eq(DC.folderName(mac: "../Noah's\n:Mac."), "From File..-Noah's-Mac", "a Mac's name cleaned as a file's: one component, never hidden")
eq(DC.place(mac: "Mac mini"), "Files › Sill › From Mac mini", "the place the Mac is told")
for (name, photo) in [("IMG_1204.HEIC", true), ("a.heic", true), ("clip.mov", true), ("v.mp4", true), ("p.png", true), ("x.jpg", true),
                      ("doc.pdf", false), ("a.zip", false), ("noext", false), ("heic", false), (".heic", false)] {
    eq(DC.isPhotoOrVideo(name), photo, "a photo or a video by its extension: \(name)")
}
func inc(_ phase: IncomingFiles.Phase, names: [String] = ["IMG_1204.heic"], total: UInt64 = 2_400_000, written: UInt64 = 0, since: Double = 0,
         asked: Bool = false) -> IncomingFiles {
    IncomingFiles(serial: 1, phase: phase, names: names, total: total, written: written, since: since, asked: asked)
}
eq(DC.incomingTitle(inc(.asking), mac: "Mac mini", device: "iPad"), "Mac mini wants to send you “IMG_1204.heic” (2.4 MB).", "the question")
eq(DC.incomingTitle(inc(.asking, names: ["a", "b", "c"], total: 3), mac: "Mac mini", device: "iPad"), "Mac mini wants to send you 3 files (3 bytes).", "three")
eq(DC.incomingTitle(inc(.receiving), mac: "Mac mini", device: "iPad"), "Receiving “IMG_1204.heic” from Mac mini", "receiving")
eq(DC.incomingDetail(inc(.receiving, written: 1_019_999)), "42%", "its percentage, rounded down")
eq(DC.incomingDetail(inc(.asking)), nil, "no percentage while asked"); eq(DC.incomingDetail(inc(.done(["a"]))), nil, "nor once over")
eq(DC.incomingTitle(inc(.done(["IMG_1204 2.heic"])), mac: "Mac mini", device: "iPad"), "“IMG_1204 2.heic” from Mac mini is in Files › Sill.", "kept, by its name as kept")
eq(DC.incomingTitle(inc(.done(["a", "b"]), names: ["a", "b"]), mac: "Mac mini", device: "iPad"), "2 files from Mac mini are in Files › Sill.", "two kept")
func stop(_ r: String, byPeer: Bool = false, name: String? = nil) -> IncomingFiles.Phase { .stopped(reason: r, message: nil, byPeer: byPeer, name: name) }
eq(DC.incomingTitle(inc(stop("cancelled")), mac: "Mac mini", device: "iPad"), "Receiving stopped.", "own Cancel")
eq(DC.incomingTitle(inc(stop("cancelled", byPeer: true)), mac: "Mac mini", device: "iPad"), "Mac mini stopped the transfer.", "the Mac's person stopped it")
eq(DC.incomingTitle(inc(stop("noRoom", name: "big.mov")), mac: "Mac mini", device: "iPad"), "There isn’t enough room on this iPad for “big.mov”.", "this device full")
eq(DC.incomingTitle(inc(stop("noRoom", byPeer: true)), mac: "Mac mini", device: "iPad"), "There isn’t enough room on Mac mini for these files.", "the Mac's noRoom: its words")
eq(DC.incomingTitle(inc(stop("cantSave")), mac: "Mac mini", device: "iPad"), "Sill couldn’t save “IMG_1204.heic” on this iPad.", "could not save here")
eq(DC.incomingTitle(inc(stop("lost")), mac: "Mac mini", device: "iPad"), "The connection to Mac mini ended before “IMG_1204.heic” came.", "lost")
eq(DC.incomingTitle(inc(stop("damaged", byPeer: false, name: "a.pdf")), mac: "M", device: "iPad"), "“a.pdf” didn’t arrive whole.", "damaged")
eq(DC.incomingTitle(inc(stop("locked", byPeer: true)), mac: "Mac mini", device: "iPad"), "Mac mini locked, so the transfer stopped.", "the Mac locked")
eq(DC.incomingTitle(inc(stop("background")), mac: "Mac mini", device: "iPad"), "Receiving stopped when Sill left the screen.", "Sill left the screen")
eq(DC.incomingTitle(inc(.stopped(reason: "quota", message: "Over\nquota.", byPeer: true, name: nil)), mac: "Mac mini", device: "iPad"), "Over quota.",
   "a reason not known: the Mac's words, cleaned")
check(!DC.incomingEndShown(inc(stop("declined"))) && !DC.incomingEndShown(inc(stop("noAnswer"))) && DC.incomingEndShown(inc(stop("declined", byPeer: true)))
      && DC.incomingEndShown(inc(stop("lost"))) && DC.incomingEndShown(inc(.done(["a"]))), "no end shown for this device's own Decline or a question nobody answered")
check(!DC.incomingWarns(inc(stop("cancelled"))) && DC.incomingWarns(inc(stop("cancelled", byPeer: true))) && DC.incomingWarns(inc(stop("lost")))
      && !DC.incomingWarns(inc(.done(["a"]))) && !DC.incomingWarns(inc(.receiving)), "a warning but for the person's own Cancel")
eq(DC.incomingAnnouncement(inc(.asking), mac: "Mac mini", device: "iPad"), "Mac mini wants to send you “IMG_1204.heic”.", "the question announced")
eq(DC.incomingAnnouncement(inc(.receiving), mac: "Mac mini", device: "iPad"), "Receiving “IMG_1204.heic” from Mac mini.", "the start announced")
eq(DC.incomingAnnouncement(inc(stop("declined")), mac: "Mac mini", device: "iPad"), nil, "this device's own Decline: nothing")
check(DC.incomingAnnouncement(inc(.done(["a"])), mac: "Mac mini", device: "iPad") != nil, "the end announced")
eq(DC.saveToPhotos(count: 1), "Save to Photos", "Save to Photos"); eq(DC.saveToPhotos(count: 3), "Save 3 to Photos", "Save 3 to Photos")
eq(DC.photosLine(.saved(1)), "Saved to Photos.", "saved"); eq(DC.photosLine(.saved(2)), "Saved 2 to Photos.", "saved two")
eq(DC.photosLine(.denied), "Sill can’t add to Photos. Allow it in Settings › Privacy & Security › Photos.", "denied")
eq(DC.photosLine(.failed("a.heic")), "Photos couldn’t take “a.heic”.", "refused by Photos")
eq(inc(.done(["a.heic", "b.pdf", "c.mov"]), names: ["a.heic", "b.pdf", "c.mov"]).photos, ["a.heic", "c.mov"], "Save to Photos takes the photos and videos")
eq(inc(.receiving, names: ["a.heic"]).photos, [], "nothing to save before it is kept")
eq(inc(.receiving, total: 0).fraction, 0, "no bytes: 0 while it runs"); eq(inc(.done([]), total: 0).fraction, 1, "and 1 once done")
eq(inc(.receiving, total: 10, written: 30).fraction, 1, "never past 1")
check(!IncomingFiles.holdsMoves(nil) && IncomingFiles.holdsMoves(inc(.asking)) && IncomingFiles.holdsMoves(inc(.receiving))
      && !IncomingFiles.holdsMoves(inc(.done(["a"]))) && !IncomingFiles.holdsMoves(inc(stop("lost"))), "a transfer from the Mac holds the moves while it runs")
check(DC.movesWait(out: nil, incoming: inc(.receiving)) && DC.movesWait(out: shot(.sending), incoming: nil) && !DC.movesWait(out: nil, incoming: nil)
      && !DC.movesWait(out: shot(.done(.done(transfer: 1, kept: [], place: "x"))), incoming: inc(.done([]))), "the moves wait for either direction")
// The chip: a question first, then a transfer to the Mac, then one from it, then whichever ended last.
let goingOut = shot(.sending), doneOut = OutgoingFiles(serial: 1, phase: .stopped(reason: "lost", message: nil, byPeer: false, name: nil),
                                                       names: ["a"], total: 1, acked: 0, since: 5)
eq(DC.chip(out: nil, incoming: nil), .none, "nothing")
eq(DC.chip(out: goingOut, incoming: inc(.asking)), .incoming, "a question from the Mac over a transfer to it")
eq(DC.chip(out: goingOut, incoming: inc(.receiving)), .outgoing, "a transfer to the Mac over one from it")
eq(DC.chip(out: doneOut, incoming: inc(.receiving)), .incoming, "one from the Mac over an ended one to it")
eq(DC.chip(out: doneOut, incoming: inc(.done(["a"]), since: 6)), .incoming, "both ended: the later")
eq(DC.chip(out: doneOut, incoming: inc(.done(["a"]), since: 4)), .outgoing, "both ended: the later, the other way")
eq(DC.chip(out: nil, incoming: inc(stop("declined"), since: 9)), .none, "this device's own Decline: no chip")
eq(DC.chip(out: doneOut, incoming: inc(stop("declined"), since: 9)), .outgoing, "nor over another's end")

print("files: \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
