# `audio-codec`

**Checks:** the Mac's sound through AAC-ELD in memory (docs/audio-plan.md H4): the test tone through the packetizer, the encoder and the decoder, every decoded sample placed by its packet's stamp, each click at its whole second at 480 and 512 frames a packet and across gaps; a segment starting clean on both ends; a late join; one packet a block; the bitrate

**Compiles:** `Sources/SillHost/AudioEncoder.swift`, `AudioPacketizer.swift` and `TestTone.swift` with `iOSClient/AudioDecoder.swift`; a binary that links a media framework but AudioToolbox is refused
