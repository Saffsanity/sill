# `pairing-sharing`

**Checks:** whether screen sharing shows the pairing window (issue #108): Settings › Devices' switch alone decides it, hidden while off and shown while on, whoever opened the window (the Mac's user or a device's ask), through one window's session; what the window server is told for each (`.none` hidden, `.readOnly`, AppKit's default, shown); the Log's two lines, which carry no digit

**Compiles:** `Sources/SillMenuBar/PairingWindowSharing.swift` (`build.sh`; AppKit imported for `NSWindow.SharingType` alone, no window)
