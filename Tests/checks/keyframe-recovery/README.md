# `keyframe-recovery`

**Checks:** when the device asks the Mac for a keyframe (kind 44) after its picture was interrupted (issue #101): one ask per interruption while its keyframe is due, asked again when none came within its wait (4 s, or four round trips), so a Mac that never answers is asked after 4, 8 and 16 s, then every 32 s; a keyframe the layer's flush threw away as the picture back and lost again; a trip to the background owing the ask again and starting the spacing at 2 s, keyframes shown while away never repeats; only while Sill is active and something streams; 2 s apart at least, an ask held back going at the time it is due (not a rounding later); a picture that fails again within 10 s of its keyframe waiting 4, 8, 16, then 32 s; a keyframe with nothing open and a clock gone back; then 20,000 random sessions against a model of the event history (never stuck while open, active and streaming)

**Compiles:** `iOSClient/KeyframeRecovery.swift` alone (`swiftc`)
