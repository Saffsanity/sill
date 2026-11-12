**The Settings panel's Quality row shows the quality's name, and its menu the rates (2026-11-12, branch
`quality-row-one-line` from main at 919e05a).** Noah: "the 'Quality' setting on iPhone in landscape takes 2
lines when 'Extreme - 150 Mbps' is selected. Is there a way to have it stay on one line?", and of showing
the name alone: "Yep, seems like just showing the Mbps in the menu itself would work to solve this". The
iOS app's Settings panel only: no wire change, nothing on the Mac.
- Why: a row puts its control beside its title when both fit and under it when they do not
  (`AdaptiveRow`, a `ViewThatFits`), which is right for larger text. The Quality menu's label was the
  quality with its rate, and "Extreme — 150 Mbps" is the one long enough not to fit beside "Quality" in
  the panel of an iPhone on its side, so that row alone stacked.
- What: the row shows the quality's name alone ("Extreme"; "12 Mbps" for a bitrate set by hand on the
  Mac: `QualityPreset.name(forBitrate:)`), in every layout, and the menu lists each quality with its
  rate as before (`QualityPreset.title`). It is the picker's `currentValueLabel`, which is iOS 18's: on
  iOS 17 the row shows the whole title and stacks as it did. The running stream's rate is still in the
  panel's readout at its top.
- Verified: harness photos on the agents' Duo simulator against main, 8 cases (an iPhone on its side and
  upright at Extreme, at the default and at a bitrate set by hand; the Duo flat and its cover; larger
  text): every case differs from main only at the row. On an iPhone on its side main stacks "Quality"
  over "Extreme — 150 Mbps"; here the row reads "Quality … Extreme" on one line and Frame Rate comes
  into view. Noah had it on his iPhone 15 Pro and iPad mini in a try build (2026-11-12).
- Not verified: iOS 17 (no device or simulator of it here); by the code it shows the whole title as before.
