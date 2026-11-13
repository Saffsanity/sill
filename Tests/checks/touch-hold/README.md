# `touch-hold`

**Checks:** the picture's touch and hold in Direct Touch (issue #178): lifted within 8 pt of where it was pressed, a right click there at the lift; moved past 8 pt (the distance, not each axis), the left button down where it was pressed, each move, and the button up where it lifts; never a second button down, a cancel mid-drag the button up where the finger was last and no click, nothing before a hold or after its end, the next hold afresh; then 20,000 random holds against a model (no button ever left down)

**Compiles:** `iOSClient/TouchHold.swift`
