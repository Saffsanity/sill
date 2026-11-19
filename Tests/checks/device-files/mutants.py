"""DeviceFiles and uplink-ledger mutants (iOSClient/DeviceFiles.swift, iOSClient/SessionLink.swift): each must compile
and make device-files/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
D = "iOSClient/DeviceFiles.swift"
L = "iOSClient/SessionLink.swift"
M = [
    # The window and the uplink ledger
    ("the window ignored", D, "guard let action = o.sender.next(window: window(now: Self.clock())) else { return }",
     "guard let action = o.sender.next(window: Int.max) else { return }"),
    ("the person's input never narrows the window", D, "let active = FileFlow.active(lastInput: link.lastInputAt, now: now)", "let active = false"),
    ("a file goes whatever the connection holds", L, "    static func filesMayGo(pending: Int, fenced: Bool, held: Bool) -> Bool {\n        !fenced && !held && pending == 0",
     "    static func filesMayGo(pending: Int, fenced: Bool, held: Bool) -> Bool {\n        !fenced && !held"),
    ("a file goes while held", L, "        !fenced && !held && pending == 0", "        !fenced && pending == 0"),
    ("a file goes while fenced", L, "        !fenced && !held && pending == 0", "        !held && pending == 0"),
    ("a completion from an earlier connection counts", L, "        guard epoch == self.epoch else { return false }\n", ""),
    ("room said while something is left", L, "        guard roomWanted, total == 0 else { return false }", "        guard roomWanted else { return false }"),
    ("room said again and again", L, "        guard roomWanted, total == 0 else { return false }\n        roomWanted = false\n",
     "        guard roomWanted, total == 0 else { return false }\n"),
    ("another connection keeps the old counts", L, "            epoch += 1\n            pending = [Int](repeating: 0, count: Lane.allCases.count)\n",
     "            epoch += 1\n"),
    ("a file's message waits in `waiting` instead", L, "            ledger.wantRoom()\n            return .later\n",
     "            ledger.wantRoom()\n            waiting.append(data)\n            return .sent\n"),
    ("inputs not stamped", L, "        if Self.isInput(data) { lastInput = ProcessInfo.processInfo.systemUptime }\n", ""),
    ("a message that found no room dropped", D, "                case .later: return\n", "                case .later: o.held = nil; return\n"),
    # The clock's look and a send's `.gone` both notice a connection that is no longer the session's: either alone does.
    ("a lost connection never noticed", D,
     ["                case .gone: perform(o.sender.stop(.lost, tellPeer: false), o); return\n",
      "        if link.connection !== o.connection {\n            perform(o.sender.stop(.lost, tellPeer: false), o)\n            return\n        }\n"],
     ["                case .gone: return\n", ""]),
    ("the clock never tries again", D, "        if o.snapshot.acked != o.sender.ackedTotal { o.snapshot.acked = o.sender.ackedTotal; publish(o, now: now) }\n        pump(o)\n",
     "        if o.snapshot.acked != o.sender.ackedTotal { o.snapshot.acked = o.sender.ackedTotal; publish(o, now: now) }\n"),
    # Reading and hashing
    ("a short read sent", D, "              let data = try? r.handle.read(upToCount: count), data.count == count else { return nil }",
     "              let data = try? r.handle.read(upToCount: count) else { return nil }"),
    ("a part not hashed", D, "        o.hash.update(data: data)\n", ""),
    ("the hash carried into the next file", D, "                o.hash = SHA256()\n", ""),
    ("a part read from the start of its file again", D, "        r.at += UInt64(count)\n", ""),
    # Stops and what they leave
    ("the person's Cancel not told to the Mac", D,
     "                if let payload = t.payload { link.send(Self.message(.fileTransfer, payload)) }\n            case .sendPart, .sendEnd:",
     "                _ = t\n            case .sendPart, .sendEnd:"),
    ("the Mac's cancel ignored", D, "                perform(o.sender.peerCancelled(t.reason), o, message: t.message)", "                break"),
    ("Sill's own copies kept", D, "        for s in sources where s.ownCopy { Self.deleteOwnCopy(s.url) }\n    }\n\n    /// A copy of Sill's own",
     "    }\n\n    /// A copy of Sill's own"),
    ("a folder sent", D, "            if (try? s.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {",
     "            if false {"),
    ("too many offered anyway", D, "guard !tooMany, !tooBig, let payload = offer.payload else {", "guard !tooBig, let payload = offer.payload else {"),
    ("a second send replaces the running one", D, "guard preparing == nil, out == nil, !sources.isEmpty else {", "guard !sources.isEmpty else {"),
    ("acks never move the window", D, "                perform(o.sender.acked(file: t.file, offset: t.offset, now: now), o)\n", ""),
    # Files from the Mac (DeviceFiles' incoming side and DeviceInbox).
    ("an offer saying asked taken at its word", D,
     "let asked = FilePolicy.askedFor(o, pick: pick?.transfer, pickedAt: pick?.at, now: now) && pick?.connection === connection",
     "let asked = o.asked"),
    ("Ask Before Receiving Files ignored", D, "askBefore: context.askBefore, askedFor: asked)", "askBefore: false, askedFor: asked)"),
    ("a second offer from the Mac taken while one runs", D, "FilePolicy.deviceAnswers(o, receiving: inn != nil,", "FilePolicy.deviceAnswers(o, receiving: false,"),
    ("acks never sent", D, "                // On the person's lane: an ack never waits behind anything of a file.\n                if let payload = t.payload { link.send(Self.message(.fileTransfer, payload)) }\n",
     "                // On the person's lane: an ack never waits behind anything of a file.\n"),
    ("a file kept without its hash checked", D, "guard p.written == size, Base64URL.encode(Data(p.hash.finalize())) == sha256 else { throw Failure.damaged }",
     "guard p.written == size else { throw Failure.damaged }"),
    ("a received part not hashed", D, "        p.hash.update(data: bytes)\n", ""),
    ("a received file kept 0600", D, "        guard fchmod(p.fd, 0o644) == 0 else { throw Self.failure(errno) }\n", ""),
    ("a receive's partials kept at a stop", D, "            case .deletePartials:\n                if let part = i.part { inbox.discard(part) }",
     "            case .deletePartials:\n                if let part = i.part, false { inbox.discard(part) }"),
    ("the device's Cancel of a receive not told", D, "            if let i = inn { perform(i.receiver.stop(.cancelled, tellPeer: true), i); return }",
     "            if let i = inn { perform(i.receiver.stop(.cancelled, tellPeer: false), i); return }"),
    ("a receive's lost connection never noticed", D, "            if link.connection !== i.connection { perform(i.receiver.stop(.lost, tellPeer: false), i) }\n            else {",
     "            if false { perform(i.receiver.stop(.lost, tellPeer: false), i) }\n            else {"),
    ("the answered pick never cleared", D, "        if asked, let p = pick { serial = p.serial; pick = nil }", "        if asked, let p = pick { serial = p.serial }"),
    ("the Mac's word on a pick ignored", D,
     "                    endPick(t.reason ?? FileReason.nothingChosen.rawValue, byPeer: true, tellPeer: false, message: t.message); return\n",
     "                    return\n"),
    ("the device's stop of a pick not told", D, "        if tellPeer, let payload = FileTransfer.cancel(transfer: p.transfer, reason: .cancelled).payload {",
     "        if false, let payload = FileTransfer.cancel(transfer: p.transfer, reason: .cancelled).payload {"),
]
sys.exit(0 if module.mutate("device-files", M, sys.argv[1]) else 1)
