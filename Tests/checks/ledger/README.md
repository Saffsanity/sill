# `ledger`

**Checks:** the device's settings ledger against a model host, scenarios and 5,000 random runs (some against a host without sound: Send Audio never sent there; some against a host from the sound's beta, which refuses a device's Send Audio: the switch goes back; some against a host from before 2026-10-29, which takes Direct Wireless from any session). Rule 10 (2026-10-29): Direct Wireless never sent on a session the Mac says is not paired (`sessionPaired` false), on or off, the rest of a pick still sent; sent as before to a Mac that does not say; each connection's own state, devices paired during their session and removed, and a test client's pick refused and answered with the Mac's value

**Compiles:** `iOSClient/HostSettingsLedger.swift`, `Sources/StreamProtocol/HostSettings.swift`
