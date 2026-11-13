**The 0.6.1 fixes in one pull request (2026-11-09, branch `integration-0-6-1-fixes` from main at f224323d,
its own pull request, "0.6.1 fixes: …"; the resolutions, the verification of #320 and every number are in
sill-handoff's `triage/2026-11-09/int/REPORT.md`).** Noah's decisions of 2026-11-09: #228 yes; #230 yes ("keep
the iPad awake when streaming"); "Work on #114 (#223)"; "Implement #309/#320"; #229 closed. The four, each
merged with a merge commit in this order with the contributors' commits as they are, so merging this pull
request with a merge commit marks them merged: #228 (the waking click; its entry is a bullet of "A sleeping
display wakes for a device"), #230 (the device's auto-lock while a window streams), #223 (blank tiles in the
window strip, towards #114: the cause still unconfirmed) and #320 (a remote dial's failure names both ends,
#309; no entry of its own: docs/remote-access-plan.md's tables).
- Resolved against main: `StreamCoordinator.handle` (main's lock gate first, then #228's `DisplayWake.pass`,
  then `deviceActive` at the lock's reading: what the lock refuses is never held back and wakes nothing);
  `site/support.html` (#228's tap sentence on 0.6.0's shipped paragraph, in a `Display wake click` marker
  whose republish before 0.6.1 puts v0.6.0's paragraph back: docs/release-checklist.md); ci.yml's mutants
  matrix and the checks README (both sides' rows); CLAUDE.md (each side's entries).
- Maintainer commits: #230's N1 (what the device does by itself, the automatic reconnect, a stream it asked
  for again, its pointer's re-centre, no longer holds it awake: the entry below); the checklist's open
  marker; #223's panel service wording (the verification's nit 3); these docs.
- Verified: `swift build -c release` (only the CaptureProbe warning); the iOS app Debug for the simulator and for the iPad
  (signed), Release for the simulator, Xcode 27.1, only the known StreamClient capture warning; `run-all.sh`, all 65
  (display-wake 265, device-idle 48, catalog-windows 75, remote-rules 179); mutants display-wake 80 of 80 and device-idle
  17 of 17 (the rest, run after this was written, in the report); the CLI against main's (f224323d), masked and sorted:
  idle identical, with a Desktop client identical but the second the client left (as main against itself); the bare
  app's 162 previews identical to main's from one path; live on a loopback synthetic host: a tap with the display
  "asleep" held back (`disp.heldPress 1`, its release silent), the same tap at a "locked" Mac refused by the lock
  (`in.locked 3`, no hold, no wake), awake it clicked.
- **Untested, for Noah:** each PR's own list (#228's steps 1 and 2 with the display asleep, the virtual
  display's case deciding the support page's sentence; #230's on the iPad: its Auto-Lock read as Never all
  through 2026-11-09 17:37–18:17, so the run here was skipped, and this branch's Debug build, 0.6.1 (4), is
  installed on it; #223's Stage Manager probe; #320 with Tailscale off on the Mac only, and which failure the
  device's console names).
