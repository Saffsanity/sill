# `pinch-routing`

**Checks:** who a two-finger pinch on the stream's picture belongs to (Pinch Behavior, Zoom Stream or Zoom App): the picture's zoom, the Mac's own pinch (`InputEvent.magnify`) or nobody's, from fingers or the iPad's trackpad and whether the Mac takes the pinch; all eight combinations, then the properties the three callers rely on (the trackpad ignores the stored choice; a Zoom App kept for a Mac that cannot take the pinch never costs the picture its zoom)

**Compiles:** `iOSClient/PinchRouting.swift`
