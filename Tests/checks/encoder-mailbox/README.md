# `encoder-mailbox`

**Checks:** HEVCEncoder's frames on their way into VideoToolbox (one inside, the one-slot mailbox, the watchdog's clock, timestamps, keyframe requests, `abandon`, the teardown) through a copy of HEVCEncoder's glue around a stand-in for VideoToolbox, in virtual time; a binary that links VideoToolbox is refused

**Compiles:** `Sources/SillHost/EncoderMailbox.swift`
