**Away from home (2026-09-27, branch `remote-away` from `remote-pacing` at
c564142, PR #39, stacked on PR #34, which merged during its review; main at
e6b3265 merged in on 2026-10-08, one merge commit, not rebased, so the pull
request goes to main; PR B of docs/remote-bundle-plan.md, whose "Results: PR B",
"Merged with main" and "The merge's review" have every number).** Items 2–4 of the away-from-home
bundle, on PR A's pacing: an away session starts low, the Mac says when the
link cannot carry the quality, and a session away comes home by itself. Home
sessions are as they were (H2: the CLI's output and kind 16 unchanged).
- Wire (additive; HostSettings.swift): kind 16 gains `away` (`AwayQuality`: the
  home and away pairs, whether this connection is away, whether the away pair
  runs) and `link` (`LinkReport`: "behind" or "stalled", frames withheld, the
  running bitrate, the carried rate, a suggestion), optional and per
  connection; `QualityPreset.name(forBitrate:)` and `shortTitle(bitrate:
  captureScale:)` ("Low · Standard"). Kind 17 and `HostSettingsChange` as
  they were.
- Host: `HostConfig` has a second pair, `awayBitrate` and `awayCaptureScale`
  (`standard`: Low · Standard), and `effective(away:)`. `AwayPolicy` (pure): a
  device is away when the remote door admitted it from a VPN or the internet
  ("by address" is home); the away pair runs while at least one device is
  connected and every one is away, and the flag stays while nobody is. "Away
  from home: every connected device is away; streaming at Low · Standard (4
  Mbps per 60 fps, points). The home quality stays Pro · Retina." or "Home
  quality again: a device connected at home (…); streaming at …", one restart
  each, a join's flip waiting for that device's first viewport (1 s at most).
  A device away sets the away pair (`applyingAway`); kind 16 is per connection.
- The link (`LinkJudge`, pure; StreamServer's sweep closes every client's
  second, at home too; the home branch only counts): short = ≥ 3 frames
  withheld and ≥ a tenth; behind at 3 short of 5, fine after 5 clean, stalled
  after 3 s with bytes waiting, none taken and nothing heard; a restart at
  another quality (bitrate, rate, resolution), or none, resets it (no line),
  and one that keeps it (a window picked, a rotation) keeps it; the carried rate is the mean over seconds ending with ≥ 16 KB
  waiting (3 needed), reported again when it moves 25 %; the suggestion is the
  highest preset under 70 % of it at the stream's fps (Low when none fits, one
  step down without a measure, Standard with Low from Retina). The
  coordinator's lines: "Link to iPad (iPad14,1): cannot carry Pro (withheld 52
  of 58 frames in the last second; the link carried about 6.4 Mbps);
  suggesting Low · Standard.", "… nothing has got through for 3 s …", "…
  keeping up again." A report about a bitrate a pick has just replaced is left
  out of kind 16. No Stats key.
- Sill.app: Settings › Streaming's "Away from home" section (saved as
  `awayBitrate`, `awayCaptureScale`); the menu's Quality subtitle "Away from
  home now: Low · Standard"; a device's card row "3 fps, the link can’t carry
  Pro · RTT 531 ms · through Tailscale" or "Nothing is getting through".
- Device (`AwayCopy`, `LinkLine`, pure): the panel's header "Away: Low ·
  Standard" or "Home quality: Pro · Retina (a device at home is connected)",
  a footnote, the link's callout with its button ("The link can’t carry Pro.
  Low · Standard is recommended." / "Use Low · Standard", 44 pt), nothing for
  stalled, the old round-trip callout only for a Mac without `away`; a line
  over the stream while nothing is open over it ("The link can’t keep up with
  Pro. Lower it in Settings."), gone 2 s after the report clears (at once when
  it clears while something is open over it), announced once a spell.
- The move home (`DiscoveryPolicy.moveHome`, StreamClient on PR #12's moves,
  `MoveKind.fromRemote`): a remote session (not Connect Remotely) whose saved
  Mac the network lists by Mac ID for 2 s moves to the home door: the home
  viewport first on the new connection, the probe (another launch refused at
  its window list; kind 18 signed by the saved key, at least as new as the
  session's), the fenced hand-over, the remote connection closed after;
  retries 10, 20, 40, then 60 s; a remote connection that dies meanwhile is
  carried by the move (held, adopted; picks not sent).
- TEST ONLY and DEBUG (Build and run): SILL_TEST_REMOTE_ORIGIN (the remote
  door alone counts loopback as a VPN or the internet), SILL_TEST_PATTERN=noise
  (a square of noise, so a test stream's size follows its quality),
  `-SillSettingsScript`, `-SillMoveHomeTest`, `-SillDialSaved remotely`,
  `-SillLinkLine behind` and seven settings cases; `sillclient.py`'s `away=`,
  `link=` and `--expect` keys; the pacing harness's link verdicts and cases.
- Verified (the plan's Results): every pure check (25), the new ones' mutants
  (away-wire 9, away-quality 16, link-judge 26, away-copy 17) and policy's
  (76, with H15's) and fence's (32 over 17 modes); H2 against origin/main's
  CLI; the pacing matrix against origin/main (every pacing gate, and the
  link's with the dip's and the stopped downlink's measured from the host's
  first second withholding frames); H7, H8, H9 on the bare app, H12 end to
  end, H16 previews, H17; the iOS app, Debug and Release; S1 (144 photos),
  S3 (the callout and the line live), S4 and S5 (the move home live, its
  retries, another launch refused once, Connect Remotely staying).
- Found, and left for Noah (the plan's open question 14): behind needs 3
  short seconds of 5, and under PR A's pacing a link only a little too slow
  loses frames in rounds (drop, drain, keyframe, deltas), which can leave fewer
  than 3 short in any 5: at 1.8 times over the link, 8 s to report (the gate
  was 6); on a milder one maybe never. The carried rate often goes unmeasured
  then, and the suggestion is one step down.
- Adversarial review (2026-09-27, after the pull request; the plan's "The
  adversarial review"), on a move home that races a loss, a Mac that
  relaunches, two Macs with one name, the away pair never reaching the saved
  home one, the notice's hysteresis, VoiceOver and copy. Two fixes, each with
  a check that fails without it: a restart that keeps the quality keeps the
  link's judgement (f882291: every window picked or rotation cleared the report
  and it came back 2.5–3 s later, after the line's 2 s linger, so the line
  returned and was spoken again; the pacing harness's `linkrestart` and an end
  to end run through a relay showed it; `LinkJudge.judgedAfresh`,
  `StreamServer.resetLinks`, the coordinator's `judgeLinks`); and a line whose
  report cleared off screen never comes back (a67dc48: the callout's button,
  then Done within 2 s, brought the cleared line up and VoiceOver said it). A
  new simulator run of a move home whose remote path dies 0.5 s in, with a
  panel pick meanwhile: carried over the move, no connect screen, the pick not
  sent, the host never changing a setting (9 of 9). Left, in the plan: the
  move home's kind 18 floor against a broadcast in the same milliseconds, the
  callout's "·" for VoiceOver (P8), and open question 15 (a still window counts
  as keeping up, so the line goes and comes back between reading and
  scrolling). Every gate again on the final build (the plan's numbers): H1,
  the 25 pure checks and the two changed checks' mutants, H2 14 of 14, the full
  pacing matrix (ext60 once one drop in its last second, then 3 of 3 clean),
  H7, H8, H9, H12, H16, H17, S3 at 2 Mbit/s 18 of 18 (at the plan's 3 Mbit/s it
  failed while another checkout's mutant run loaded the Mac and the software
  encoder kept 3 to 7 frames a second), S4 and S5 but the check the software
  encoder's watchdog restarts broke under that load, and S1 at two sizes.
- Merged with main at e6b3265 (2026-10-08; one merge commit; the plan's "Merged
  with main"): 21 files conflicted, each settled keeping both sides whole. Where
  they meet: the move home dials the TLS home door pinned to the saved Mac's key
  (`DiscoveryPolicy.moveHomeTrust`, new, pure: exactly when a tap's dial of
  that row would be pinned; a plain door, a Mac that removed this device or one
  with a new key keeps the session remote; never a plain dial, DEBUG or not),
  its hello first inside TLS, only to a row whose tag names the session's saved
  Mac (#44's `rowMac`), the session taking the move's trust and row at the
  hand-over (`session.home`, `session.row`; `homeTLS` marked); a pin refused on
  the move home refuses that row (never #44's `newKey`: the session holds
  the Mac's key through the remote door); the kind 18 floor taken as the move
  starts (`DiscoveryPolicy.HomeMoveInfo`), which fixes the review's broadcast race. Host:
  SILL_TEST_REMOTE_ORIGIN reaches `Door` (`remoteDoor: kind == .remote`) and
  TestHooks; StreamCoordinator, StreamServer and HostConfig keep both sides;
  the pacing harness defines LINK_JUDGE by what its StreamServer has. Device:
  the link's line also stays away under the tour's card; `awayhome` is a TLS
  session at home. Verified (the plan's numbers): the builds on Xcode 27.1
  (the App Store replaced 27.0 mid-run), only the known warnings; all 39 pure
  checks (`policy` 360); the mutants of the 27 checks whose files the merge
  changed, 952, every one caught (`policy`'s five new); H2 against main's CLI;
  H7 and H8 over the TLS doors, 16 of 16; on a private simulator against
  `SillHost --synthetic --remote --pairing`, 28 of 28: S4 (moved over the TLS
  home door, one restart at the home quality), `refused`'s back-off, another
  key refused by the pin once, another launch once, S5, and S4race (the
  remote path cut mid-move: carried, the pick not sent); the pacing harness
  against main, every gate passing with main's figures and the link's
  verdicts; Sill.app's previews main's but for the away section and the new
  cards; photos of the panel and the stream's line, the phone's included.
- The merge's review (2026-10-08; the plan's "The merge's review"): seven
  findings, two the same, each verified here and fixed in a commit of its own.
  The move home chose by the Mac's listing: a look-alike replaying the Mac's
  public tag at another key, listed first, had its pin refused and the refusal
  held the Mac's own row back while any row of it stayed listed (52 s on a
  private simulator), and a row with the tag and no `p` listed first stopped
  the move. Now by row (`DiscoveryPolicy.moveHomeRow`, `HomeRows`, pure): not
  refused, at a door a pinned dial takes, the fewest tries first; a row's
  refusal and tries forgotten once it is no longer listed; `moveHome` lost
  `refusedListing`. The kind 18 floor is a pure rule (`HomeMoveInfo`), checked:
  the broadcast race among `policy`'s cases, and mutant K1 the rule before the
  fix. Docs: kind 16's `away` comes from a host with an identity (SillHost
  `--pairing` alone sends it, nobody ever away); the plan's §4.4, §7.3, §10,
  P13 and open question 10 say the move home goes only to a TLS home door (a
  plain one: no move, the session stays remote). The fence check's move home
  is TLS to TLS. site/privacy.html names the link report (the 0.4.1 drafts'
  line). Verified: the builds (only the known warnings); `run-all.sh`, all 39
  (`policy` 392); the mutants of `policy` (130), `remote-rules` (72),
  `home-device` (124), `home-model` (21), `fence` (32) and `away-wire` (9),
  388, every one caught; on a private simulator 29 of 29 by row (a look-alike
  refused at its pin, then the Mac's own row moving home 70 ms after it was
  listed; a plain row first, three launches; a row that never answers first,
  twice) and the merge's S4 to S4race again, 28 of 28; the kind 18 race staged
  live (the bare SillMenuBar binary broadcasting a kind 18 every 0.25 s, the
  home door 0.8 s away): this build moved home 2 of 2, the rule before the fix
  refused the Mac's own row 2 of 2; CI's "Build and check" passed on the
  fixes' head (ea4de23).
- **Untested, for Noah (the plan's P4–P13; P1–P3 and P14 are PR A's and
  still open):** with Sill.app built from this branch on the Mac and this
  build on the iPad mini, away on the iPhone 15 Pro's hotspot through
  Tailscale, then home:
  - P4, away starts on Low and Standard: at home set Pro · Retina in the Mac's
    menu, then leave for the hotspot. The session through Tailscale starts at
    Low · Standard: Sill.log "Away from home: every connected device is away;
    streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality
    stays Pro · Retina.", the iPad's panel "Away: Low · Standard", and
    `defaults read me.saffer.sill.mac bitrate` still 40000000.
  - P5, the away choice: pick Balanced away: one restart at 15 Mbps,
    `awayBitrate` 15000000, the home bitrate unchanged; the next away session
    starts at Balanced.
  - P6, mixed: with the iPad away, connect the iPhone at home on Wi‑Fi: one
    restart, the iPad's header "Home quality: Pro · Retina (a device at home is
    connected)"; disconnect the iPhone: the away quality again, one restart.
  - P7, the Mac: Settings › Streaming shows both sections; the away pickers
    restart once while the iPad is away; the menu's Quality subtitle "Away
    from home now: …".
  - P8, the can't-keep-up message: away at Extreme on the hotspot, within
    about 5 s the panel's callout ("The link can’t carry Extreme. … is
    recommended.", its button "Use …"), the line over the stream ("The link
    can’t keep up with Extreme. Lower it in Settings."), one VoiceOver
    announcement, and the Mac's card "the link can’t carry Extreme"; the
    button: one restart, the callout and the line go. With the line up, pick
    another window and rotate: it stays, not spoken again; the button, then
    Done at once: no line, nothing spoken; how VoiceOver reads "Low ·
    Standard".
  - P9, a dip: cover the iPhone, or walk away from it, for 15 s: the line
    comes, then goes about 5 s after the link recovers; no reconnect.
  - P10, coming home: streaming away through Tailscale, join the home Wi‑Fi.
    Within about 5 s of the network listing the Mac the session moves back by
    itself over the Mac's TLS home door, pinned to its key: Sill.log "Client
    connected: …%en0" (never "Home door refused", no pairing asked), "Home
    quality again", then "Client left" for the Tailscale address; the route
    line gives way to "Wi‑Fi", one restart; drag and type through it (no button
    stays down, no letters swap); the Mac's card shows the iPad once. At the
    edge of the home Wi‑Fi, note how often it goes back and forth.
  - P11, coming home by the cable: an away session, then at home plug the
    cable in: the move goes to the cable ("Wired"; the Mac logs `%en14` or
    `%anri0`).
  - P12: Connect Remotely at home stays remote.
  - P13, mixed builds: PR #13's iPad against this Sill.app, away: Low ·
    Standard, its Quality Low, no header line. This iPad against Sill for Mac
    0.4.0 (main's: a TLS home door, no away quality): no header line, no
    callout, and the move home works, pinned; against 0.3.1 (a plain home
    door) the session stays remote.
  It merged (05f2bb8, 2026-10-08) and ships as Sill for Mac 0.5.1 with Sill for
  iPhone and iPad 0.5.1 (4), one version for both (the entry above; there is no
  Sill for Mac 0.4.1): the release drafts' lines held back for it (sill-handoff's
  `release-next/drafts/for-0.4.1.md`: the notes, What to Test, the site's support
  and index lines, the privacy page's date, the metadata) are on the release's
  branch, `release-0.5.1` (its privacy line was in since the merge's review).
