"""FileHub mutants (Sources/SillHost/FileHub.swift): each must compile and make file-hub/main.swift fail.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/FileHub.swift"
M = [
    ("the lock at arrival ignored", F, "LockPolicy.decide(.files(cancels: cancels), arrived: arrived, now: gate.reading,",
     "LockPolicy.decide(.files(cancels: cancels), arrived: gate.reading, now: gate.reading,"),
    ("a part's lock never judged", F,
     "            // A part that came while the Mac read locked, or is handled while it does, writes nothing.\n            if refusedLocked(arrived, cancels: false) { stop(id, .locked, tellPeer: true); return }\n",
     "            // A part that came while the Mac read locked, or is handled while it does, writes nothing.\n"),
    ("an unpaired session's offer taken", F, "let paired = context.peers[id]?.paired == true", "let paired = context.peers[id] != nil"),
    ("the switch going off stops nothing", F, "                if !new.share { stop(id, .off, tellPeer: true) }", "                if false { stop(id, .off, tellPeer: true) }"),
    ("a session no longer paired keeps its transfer", F,
     "                else if new.peers[id]?.paired != true { stop(id, .notPaired, tellPeer: true) }\n", ""),
    ("a session no longer listed keeps its transfer", F,
     "                else if new.peers[id] == nil { stop(id, .lost, tellPeer: false) }\n", ""),
    ("partials kept at a stop", F, "            case .deletePartials:\n                if let s = i.staging { i.store.discard(s) }",
     "            case .deletePartials:\n                if let s = i.staging, false { i.store.discard(s) }"),
    ("the free space never read", F, "freeSpace: { [self] in testFree ?? store.freeSpace() })", "freeSpace: { nil })"),
    ("busy never judged", F, "runningFromDevice: incoming[id] == nil ? 0 : 1,", "runningFromDevice: 0,"),
    ("the rate never counted", F, "        arrivals[id] = rate.kept\n        guard let o = FilePolicy.offer(t)", "        guard let o = FilePolicy.offer(t)"),
    ("a quit stops nothing", F, "            for id in Set(incoming.keys).union(outgoing.keys) { stop(id, .lost, tellPeer: true) }\n            if pick != nil",
     "            if pick != nil"),
    ("a malformed offer left unanswered", F, "guard let o = FilePolicy.offer(t) else { refuse(transfer, .damaged, to: c); return }",
     "guard let o = FilePolicy.offer(t) else { return }"),
    # The Mac's files to a device.
    ("parts past the window", F, "guard let action = o.sender.next(window: window(id, o.connection)) else { return }",
     "guard let action = o.sender.next(window: Int.max) else { return }"),
    ("the person's input never narrows the Mac's window", F, "let active = FileFlow.active(lastInput: lastInput(c), now: Self.clock())", "let active = false"),
    ("away read as home", F, "return FileFlow.window(away: peer?.away == true,", "return FileFlow.window(away: false,"),
    ("a part handed before the last went", F, "        while outgoing[id] === o, !o.awaitingRoom {", "        while outgoing[id] === o {"),
    ("the server's room never waited for", F, "                o.awaitingRoom = true\n", ""),
    ("an offer to a device whose hello takes no files", F, "FilePolicy.macOffers(helloFiles: peer?.takesFiles == true ? FilePolicy.deviceTakes : nil,",
     "FilePolicy.macOffers(helloFiles: FilePolicy.deviceTakes,"),
    ("an offer while locked", F, "locked: lockedNow, shareFiles: context.share, sendingToDevice: outgoing[id] != nil) {",
     "locked: false, shareFiles: context.share, sendingToDevice: outgoing[id] != nil) {"),
    # Not "the regular-file test removed" alone: Foundation gives no size for a folder, a named pipe, a socket or a
    # device (tried 2026-11-19), so the size's test backs it and that mutant cannot be told apart. Both removed:
    ("a folder or a named pipe offered", F, "v.isRegularFile == true,\n                  let size = v.fileSize, size >= 0,",
     "true,\n                  let size = Optional(v.fileSize ?? 0), size >= 0,"),
    ("a Mac's file not hashed", F, "        o.hash.update(data: data)\n", ""),
    ("the hash carried into the Mac's next file", F, "                o.hash = SHA256()\n", ""),
    ("a short read of the Mac's file sent", F, "let data = try? r.handle.read(upToCount: count), data.count == count else { return nil }",
     "let data = try? r.handle.read(upToCount: count) else { return nil }"),
    ("a file the Mac cannot read stops without a word", F, "perform(o.sender.stop(.cantRead, tellPeer: true), o, id: id)",
     "perform(o.sender.stop(.cantRead, tellPeer: false), o, id: id)"),
    ("a device's word while locked moves the Mac's transfer", F,
     "                // A device's word that came while the Mac read locked moves nothing (the lock stops the transfer).\n                if refusedLocked(arrived, cancels: false) { stop(id, .locked, tellPeer: true); return }\n",
     ""),
    ("a stop leaves the Mac's transfer", F, "        if let o = outgoing[id] { perform(o.sender.stop(reason, tellPeer: tellPeer), o, id: id) }\n", ""),
    ("the Mac's sending not counted as running", F, "let count = incoming.count + outgoing.count", "let count = incoming.count"),
    ("a pick shown where the Mac gives none", F, "shareFiles: context.share && context.gives,", "shareFiles: context.share,"),
    ("two panels at once", F, "panelUp: pick != nil,", "panelUp: false,"),
    ("a pick's answer not asked", F, "asked: transfer == nil ? nil : true)", "asked: nil)"),
    ("nothing chosen left unanswered", F, "                sendMessage(.cancel(transfer: transfer, reason: .nothingChosen), connection)\n", ""),
    ("a closed pick's late answer offered", F, "            guard let p = pick, p.id == id, p.transfer == transfer else { return }",
     "            if let p = pick, p.id != id || p.transfer != transfer { return }"),
    ("a lock leaves the panel up", F, "            if pick != nil { closePick(reason, tellPeer: tellPeer) }\n", ""),
]
sys.exit(0 if module.mutate("file-hub", M, sys.argv[1]) else 1)
