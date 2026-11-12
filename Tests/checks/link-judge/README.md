# `link-judge`

**Checks:** each device's link as the host judges it once a second: a short second, behind at 3 short of 5 and fine after 5 clean, stalled after 3 s with bytes waiting, none taken and nothing heard, a restart's reset and which restarts judge afresh (another bitrate, rate or resolution, or no stream; never one that keeps the quality), the carried rate (a mean of the measured seconds) and when it is reported again, the suggestion at 60 and 120 fps, the host's lines; a model against 20,000 random runs

**Compiles:** `Sources/SillHost/LinkJudge.swift` with StreamProtocol's `HostSettings.swift` (`build.sh`)
