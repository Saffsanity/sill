# `pointer-watch`

**Checks:** the host's sampling of the Mac's pointer around PointerControl: nothing read without a geometry, and a synthetic host never reading the real pointer; the fraction and inside per geometry; the kind 26 each device is sent (nothing to the one driving); a regular-mode window's bounds and on-screen flag re-read on a queue of its own (after a move at most every 0.1 s while a device is sent the pointer, every 2 s anyway), never waited for, a stale answer dropped and an owed one run; Sill's own motion; the frame interval and when the frame-rate sampler runs (over the source, a device sent it, faster than the tick); the TEST ONLY scripted pointer (its file, its clock, a dry run's move against its steps) and the software-encoder hook, with their lines

**Compiles:** `Sources/SillHost/PointerWatch.swift` with `PointerControl.swift`, `Stats.swift` and `Sources/StreamProtocol` (`build.sh`, `-package-name sill`)
