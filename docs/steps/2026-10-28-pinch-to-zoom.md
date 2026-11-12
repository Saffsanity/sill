**Pinch to zoom (2026-10-28/29, addhumal's PR #196 with maintainer edits; issue #65).** Noah's decisions of
2026-10-19/20: pinch to zoom, not a slider; Photos-like, centred on the point between the fingers, the Mac's cursor
not involved; a slight pinch out stays zoomed and only a pinch all the way out (or a lift within 2 % of it) gives the
whole picture back; cap 5×. `StreamZoom` (pure, `Tests/checks/stream-zoom`, 105 checks and 30 mutants) owns the zoom
and the two-finger stroke; InputOverlay maps every touch and scroll through it so taps, clicks, the Pencil, hover and
scrolls land on what shows under the finger; `ZoomedStreamView` scales the picture; three fingers stay the Mac's
gestures and undo a zoom they interrupt; a turn or another layout keeps the zoom, another source resets it; nothing
is sent. Harness: `-SillZoom`, `-SillHitTest`, the input script's `pinch` and `touch`; the touch rig's zoom strokes
(`RIG_ONLY=zoom`). Verified (the verdict in the handoff): the check and mutants, run-all 56, the touch rig 72 of 72
against main, photos at 1×, 2.5×, 5× and after a full pinch out. Untested, for Noah: on the iPad and iPhone, the pinch
following the fingers, a two-finger scroll at 1×, moving a zoomed picture, taps and the Pencil landing under the
finger, three-finger gestures over a zoomed picture, a turn, Larger Picture, ProMotion smoothness, VoiceOver.
