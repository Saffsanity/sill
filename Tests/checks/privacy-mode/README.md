# `privacy-mode`

**Checks:** when Sill blanks the Mac's physical displays with a black shield window while a device is connected and when it locks the Mac after the last connected device leaves (#133, #141): physical displays only (never Sill's virtual display or a zero-area frame), state transitions across connect, multiple devices, disconnect, settings toggles and app shutdown, and the log lines (addhumal's check from pull request #184, its table row moved here when main merged in)

**Compiles:** `Sources/SillMenuBar/PrivacyModePolicy.swift` (`build.sh`)
