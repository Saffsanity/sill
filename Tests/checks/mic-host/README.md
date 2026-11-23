# `mic-host`

**Checks:** a test host's Sill Microphone, TEST ONLY (`Sources/SillHost/MicrophoneTestHook.swift`, docs/microphone-plan.md §10.2): `SILL_TEST_MIC_SINK` (`dry` or `file:PATH`, refused with one line anywhere but a test host and for any other value), `SILL_TEST_MIC_APP`, `SILL_TEST_MIC_SETUP` and `SILL_TEST_MIC_LOG` (each refused alone with one line), the words of each line, what the two files say (an app uses it unless the file is missing, empty or `0`; set up unless `missing` or `notloaded`), and the file sink's WAV header byte for byte (48 kHz mono 32-bit float), never trapping

**Compiles:** `Sources/SillHost/MicrophoneTestHook.swift`
