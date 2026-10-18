# Window capture fit regression

Run `Tests/capture-fit/run.sh` on a Mac with Screen Recording access for the test process.
This opt-in integration test opens and captures only its own blank white window. It does not
connect to a device or capture the user's other windows. It is separate from the pure CI checks
because it needs WindowServer and ScreenCaptureKit access.

The test compiles the production `WindowCapture.swift` and samples luminance across actual
captured frames at 1×, 2×, and 4× output sizes, then after resizing the fixture. White must reach
the right and bottom of the output. With ScreenCaptureKit's default `scalesToFit = false`, a
request larger than the window's native pixels puts the window in the top-left of a black frame.
`Tests/capture-fit/run.sh --rev origin/main` exercises that pre-fix behavior and must fail.
