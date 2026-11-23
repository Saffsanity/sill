# `audio-packetizer`

**Checks:** how the Mac's sound becomes packet-sized blocks (docs/audio-plan.md §4.3): the packet size from the first chunk, the stamps against each chunk's anchor (a jitter oracle), the continuity tolerance, gaps that end a segment with nothing flushed or filled, a format change; `AudioSourceRule`'s table, an app's display in `AudioKey`, and the pipeline's own retry (#365): its wait, `retryIn` (10 s after the last start, doubling with each failure in a row to at most 160 s), and the count of failures in a row, `failures`; `PCMLayout`'s conversions; the first minute's tally

**Compiles:** `Sources/SillHost/AudioPacketizer.swift`
