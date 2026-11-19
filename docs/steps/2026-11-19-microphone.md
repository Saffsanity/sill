**The microphone, first part: an iPhone's or iPad's microphone as an input on the Mac, the wire, both ends' rules, the Mac's receiving side up to Sill Microphone, and the device's capture and switch (2026-11-19, branch `microphone` from `sill-audio` at 98f234d5, which is main at eb48ac9 with #394).**
Noah, 2026-11-18: "Work on … microphone passthrough to Mac with toggle", and "Any tasks that were opened by me
that are mentioned above should have an agent assigned and wip". The plan is the handoff's
`next/microphone/plan.md` (to become docs/microphone-plan.md with its results), with the overview's rules
(`next/OVERVIEW.md` §1–§3) over it where they differ. Pull request #191 (addhumal), which played the device's
microphone through the Mac's speakers, is redone (the assessment's verdict): what it gave this work is the
idea of kind 43's two types the other way, and the name Share Microphone.

- **The wire (kind 48).** `Sources/StreamProtocol/Microphone.swift`: type 1 `MicrophoneFormat` (kind 43's
  AudioFormat keys with `claim` and `pause` beside them in one JSON object: the device's offer, and with a codec
  an epoch's format), type 2 kind 43's AudioPackets byte for byte (the header's stamp the capture time), type 3
  the end (the single byte 3). The window list's `microphone` (1: takes generation 1; 0: has it, off or not set
  up) and kind 16's per-connection `MicrophoneState` (`off`, `notReady`, `unpaired`, `refused`, `idle`,
  `another`, `inUse`, with `codecs` and `device`), the overview's §1.2 and §1.3: a device sends kind 48 only to a
  list that says 1 or more, and records only while kind 16 says `inUse`.
- **The rules (MicrophonePolicy).** Both ends and every word, pure, checked together
  (`Tests/checks/microphone`). The device offers while its switch is on with the permission given, the Mac takes
  it, and this window is the one used last; it records only while the Mac says `inUse` and Sill is in front with
  no call; it claims once after the person turns the switch on, and ends when it goes off. The Mac holds one
  device at a time by its paired key: a claim takes it, an offer alone only while nobody holds it, a move or
  reconnect within 10 s keeps it; unpaired devices, a locked Mac, the switch off or Sill Microphone missing
  refuse it; 10 offers a second, 6 recordings a minute and 1.5 s of sound a second are the limits.
