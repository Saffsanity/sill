**Frame rate follows the device (2026-09-22).** `Viewport.fps` carries the
device's wanted rate: `UIScreen.maximumFramesPerSecond` (120 on ProMotion, 60
on the iPad mini), or 60 while Low Power Mode is on; the client re-sends on
`NSProcessInfoPowerStateDidChange` and `UIScreen.modeDidChangeNotification`.
The host keeps each client's rate (`clientFPS`, cleared on disconnect) and runs
the stream at the highest, capped by `maxFPS` and by 60 on the software
encoder; `fps` is re-read at every select;
a changed rate restarts the pipeline (capture interval, encoder session and
the virtual display's refresh all follow it), and bitrate scales with it.
Verified synthetically: 120 → "120 fps, 30 Mbps", drop to 60 mid-stream
restarts at 60 within a frame; `--virtual-display-selftest 120` comes online
at 120 Hz. Not yet measured on a ProMotion device or with the hardware encoder
(the software encoder manages ~22 fps at 1512×948 when asked for 120, which is
why it exists only as a fallback). `CADisableMinimumFrameDurationOnPhone` is
set so ProMotion iPhones render above 60.
