# `audio-packetizer`

**Checks:** how the Mac's sound becomes packet-sized blocks (docs/audio-plan.md §4.3): the packet size from the first chunk, the stamps against each chunk's anchor (a jitter oracle), the continuity tolerance, gaps that end a segment with nothing flushed or filled, a format change; `AudioSourceRule`'s table; `PCMLayout`'s conversions; the first minute's tally

**Compiles:** `Sources/SillHost/AudioPacketizer.swift`
