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
    ("the rate never counted", F, "        arrivals[id] = rate.kept\n", ""),
    ("a quit stops nothing", F, "            for id in Array(incoming.keys) { stop(id, .lost, tellPeer: true) }\n            if cleaned.contains",
     "            if cleaned.contains"),
    ("a malformed offer left unanswered", F, "guard let o = FilePolicy.offer(t) else { refuse(transfer, .damaged, to: c); return }",
     "guard let o = FilePolicy.offer(t) else { return }"),
]
sys.exit(0 if module.mutate("file-hub", M, sys.argv[1]) else 1)
