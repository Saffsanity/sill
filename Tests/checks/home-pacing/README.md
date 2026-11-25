# `home-pacing`

**Checks:** a home client's frame pacing (`HomePacing`): the steady-state 2-message bound, paired `sendParameterSets` on every admitted keyframe, first-keyframe admission and recovery keyframe backpressure (`keyframesInFlight == 0`, `inflightFrames == 0`, `backlogBudget`), deferred recovery requests once the queue drains to `idleBytes` (above `audioCapHome`) with `keyframeSpacing` and sibling `inFlightKeyframeWait` across home clients (in `decide` and on `sweep`, retrying if a request went unanswered), follower deltas behind an in-flight Retina keyframe (`holdCap`, `backlogFloor`, `backlogSlack`, and `bytesTaken` on completion) without stacking a second non-first keyframe, stream restarts, the Personal Hotspot livelock against `main`'s rule, two-client still-window convergence, and a reference model across 20,000 seeded random runs

**Compiles:** `Sources/SillHost/HomePacing.swift` (`module.py`, `-package-name sill`)
