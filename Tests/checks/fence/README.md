# `fence`

**Checks:** the session's fenced hand-overs, hold, adopt, unhold and a new session dropping a hand-over, against a stand-in Mac on loopback: 600 numbered inputs arrive complete and in order, whatever the machine's speed (each step waits for what it needs, not a set time); the inputs counted for the session's connection, which the Mac's pointer reports are judged by, equal those the stand-in read there (every mode, and `count` step by step); the move home from the remote door's TLS to the home door's (TLS since pairing at home), fenced, and with the remote connection gone mid-move; and the microphone's packets (`sendMicrophone`, docs/microphone-plan.md §3.3), never queued behind a fence and capped by what is still unsent, while its offer waits in order behind the fence

**Compiles:** `iOSClient/SessionLink.swift`, `Sources/StreamProtocol/*.swift`
