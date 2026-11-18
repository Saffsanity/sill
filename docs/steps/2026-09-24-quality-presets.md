**Quality presets (2026-09-24, branch `quality-presets` from main at
ad7fba2).** Noah's decisions: Maximum is renamed Pro; two presets above it,
Ultra (80 Mbps) and Extreme (150 Mbps), for the USB cable or very fast Wi-Fi;
the bitrate knob's cap goes from 100 to 200 Mbps per 60 fps (a 120 fps stream
still gets double, so Extreme at 120 fps is 300 Mbps); no Unlimited.
- `QualityPreset` (StreamProtocol's HostSettings.swift): Efficient 8,
  Balanced 15, High 25, Pro 40, Ultra 80, Extreme 150 Mbps per 60 fps,
  declared in ascending order, which is the order of the status menu's Quality
  submenu, Settings › Streaming and the device's Quality menu (all build from
  `allCases`). The raw values are the bitrates, so the rename changes nothing
  stored or sent: a Mac on 40 Mbps shows Pro. `QualityPreset.fastLinkNote` is
  the one sentence both ends add to their Quality footers ("Ultra and Extreme
  need the USB cable or very fast Wi-Fi; if the picture lags, step down."); the
  menu's Quality subtitle is unchanged.
- `HostConfig.validated()` clamps to 1–200 Mbps, so a launch argument or a
  hand-set default above that runs at 200 ("Custom — 200 Mbps"). A device still
  sets only presets: `DeviceSettings.accepted` checks `SettingsChoices`, which
  follows the presets, so it takes 80 and 150 unchanged, and refuses 200 or
  250 from a test client rather than clamping them. Kinds 16/17 unchanged.
- Mixed builds: a host from before this change refuses Ultra and Extreme from
  a newer device (the row goes back; VoiceOver hears "‹Mac› kept its
  setting"); an older device shows a newer Mac's 80 or 150 Mbps as "Custom —
  N Mbps", read-only, and 40 as "Maximum — 40 Mbps".
- Verified without a device: clean builds (only the old CaptureProbe and
  `StreamClient` warnings); the CLI's synthetic output, idle and with a client,
  equals ad7fba2's (masked and sorted; unmasked only timings and ports
  differ); a test client's Extreme then Ultra restart the stream at 150 and 80
  Mbps ("Settings from sillclient: bitrate 15 → 150 Mbps per 60 fps"), Extreme
  at 120 fps runs at 300 Mbps, and 200 and 250 Mbps are refused with the value
  unchanged in the answer; the bare app runs `-SillSetAfter` and `-bitrate`
  250 Mbps at 200 ("Settings: bitrate 15 → 200 Mbps per 60 fps", devices told
  200) and saves a device's Extreme across a relaunch; the hardware encoder
  takes and reads back AverageBitRate up to 400 Mbps at 3024×1898; previews
  against ad7fba2 differ only in menu.txt's Quality rows and the Streaming
  pane's footer; the ledger check (H2) with the six raw values and 5,000
  random runs; the panel in the simulator at 1000×710 and 500×710 (also at
  xxLarge text), menu open and closed, picking Extreme, and live against this
  host (a restart at 150 Mbps) and against ad7fba2's (refused, back to
  Balanced); the harness's `vdstream` case, now Extreme at 120 fps (300 Mbps,
  the longest readout), at all four sizes and at xLarge and xxLarge text: the
  readout wraps at xxLarge, and at 710×500 already at xLarge; the header and
  Disconnect stay put and the rows scroll.
- **Untested, for Noah:** Ultra and Extreme on the iPad over the USB cable and
  over Wi-Fi, streaming a busy window (the synthetic pattern compresses to
  under 1 Mbps whatever the target): watch the frame age in the host's
  `client …` lines and the menu's device row, and step down if it climbs.
