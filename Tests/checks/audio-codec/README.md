# `audio-codec`

**Checks:** the Mac's sound through AAC-ELD in memory (docs/audio-plan.md H4): the test tone through the packetizer, the encoder and the decoder, every decoded sample placed by its packet's stamp, each click at its whole second at 480 and 512 frames a packet and across gaps; a segment starting clean on both ends; a late join; one packet a block; the bitrate; and a device's microphone (docs/microphone-plan.md §3.4): mono at 64 kbps from a capture buffer's 4,800 frames, ten packets each, every click at its second, a lost buffer a clean new segment, a mono decoder's one buffer given as both

**Compiles:** `Sources/SillAudio/AudioEncoder.swift`, `AudioPacketizer.swift` and `AudioDecoder.swift` with `Sources/SillHost/TestTone.swift`; a binary that links a media framework but AudioToolbox is refused
