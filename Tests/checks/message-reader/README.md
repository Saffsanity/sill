# `message-reader`

**Checks:** the session's reader against a stand-in Mac on loopback: 2,000 random messages in random chunks delivered byte for byte and in order, payloads read in pieces of at most 256 KB with every piece reported (liveness counts bytes), the end mid-message and with the last bytes, the caps, and a stop between messages, mid-payload and at a message the end came with

**Compiles:** `iOSClient/MessageReader.swift`, `Sources/StreamProtocol/StreamMessage.swift`
