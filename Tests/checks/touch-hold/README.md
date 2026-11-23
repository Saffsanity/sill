# `touch-hold`

**Checks:** the picture's touch and hold in Direct Touch (issue #178), behind this device's Hold, Then Drag (PR #292: its key `Sill.holdThenDrag`, on unless turned off since Noah's 2026-11-20, its title and the words under it): off, a right click at once where the hold began, as before, and its moves, lift and cancel send nothing; a change of the switch takes the next hold. On, lifted within 8 pt of where it was pressed, a right click there at the lift; moved past 8 pt (the distance, not each axis), the left button down where it was pressed, each move, and the button up where it lifts; never a second button down, a cancel mid-drag the button up where the finger was last and no click, nothing before a hold or after its end, the next hold afresh; then 20,000 random holds, a quarter with the switch off, against a model (no button ever left down, nothing held after a hold)

**Compiles:** `iOSClient/TouchHold.swift`
