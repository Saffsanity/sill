**The macOS firewall that blocks Sill's executable (2026-10-29, branch `firewall-executable-block` from main
at 150479b5; PR #250; the security batch, Noah's go of 2026-10-29).** A user's report: the firewall keeps a
rule per path, and a Mac held `/Applications/Sill.app` allowed and `…/Contents/MacOS/Sill` blocked
(`socketfilterfw --listapps`): nothing reached Sill from the network, System Settings showed it allowed, and
`--getappblocked` on the bundle said "permitted"; `sudo socketfilterfw --unblockapp` on the executable fixed it.
No wire change.
- `FirewallCheck` asks `/usr/libexec/ApplicationFirewall/socketfilterfw` `--getglobalstate`, then only while it is
  on (`asksRules`) `--getblockall`, `--getappblocked` for the running executable (`proc_pidpath`) and its bundle,
  and `--listapps`: a process each with 2 s (then SIGTERM, SIGKILL a second later), read-only, no privileges
  (macOS 27.0.1: 4–8 ms each, no prompt, no Full Disk Access needed; asked in one run the tool is killed, 137,
  when `--getstealthmode` or `--getallowsigned` follows `--getappblocked`, or `--listapps` follows it with a
  bundle's path; no `com.apple.alf.plist` there). At launch, when the listener comes up, when Sill.app's status
  menu opens (the glyph at once, its item from the next opening), when its General opens or Sill becomes active
  over it, and when a device gets in from the network while the verdict says none can (`asksAgain`); never on a
  timer.
- `FirewallRule` (pure, `Tests/checks/firewall`, 390 checks, 69 mutants): off, allows (only once `--listapps`
  was read), `blocks(executable:bundle:)` (its own answer or its rule in the list, either enough), `blocksAll`,
  unknown (with why, in the log).
  While it blocks: General's line in the Permissions style with `sudo …/socketfilterfw --unblockapp <the running
  executable's path>` (a line per option; Copy copies one line), for Block all where to turn it off; the menu's
  "Devices Can’t Connect — The macOS firewall blocks Sill’s executable." (opens General); one log line per change
  ("Firewall: …"; none for a first verdict that blocks nothing). Sill never runs the command. support.html's
  "Your Mac isn’t listed" gains the case (Sill's own line marked `<!-- Firewall`). TEST ONLY
  `SILL_TEST_FIREWALL=executable|bundle|both|all|off|allowed|unreadable` or a file holding one, test hosts only;
  the previews are the rule's verdicts on those answers; `-SillPrintMenuAfter` prints General's line.
- Verified: the check and mutants; `run-all.sh`, all 57; a clean release build (the CaptureProbe warning
  only); main's CLI output identical masked and sorted, idle and with a client; previews main's but the 16 new
  files, menu.txt's two samples and General's path; live on loopback, blocked → allowed → Block all →
  unreadable, a VPN-origin client clearing a stale verdict, the bare app's menu and line, this Mac's real
  firewall "none (allows)". Not built: an Unblock button with the admin password (`osascript` off the main
  thread, or a privileged helper), Noah's call.
- The review (2026-10-29, three lenses; each finding reproduced first, then fixed in a commit of its own;
  sill-handoff's `triage/2026-10-29-security/firewall-line-report.md`, "The review"): a block that came after
  launch (a Deny in the firewall's own prompt, Block all turned on) went unsaid until General opened or the
  listener was replaced, as `asksAgain` can only clear one (on loopback, the canned answer blocked from 2 s: a
  client at 3.6 s and the bare app's menu at 4 and 7 s said nothing): the status menu asks again as it opens
  (bd18d96b); with `--listapps` unread the verdict took the executable's own "permitted" for allowed and dropped
  why: unknown, with why, unless an answer blocks (3d10ea95); the check's usage stand-in had no "apps", so a
  reading that took any mention of apps for a list passed (56d3f3a3); the docs had the tool die whenever
  `--listapps` followed `--getappblocked` in one run (the docs commit, af3283d1; the second review measured which
  options do, below). Re-run: the check 340 and 67 of 67 mutants (64 of 64 before; two extra mutants had
  survived); `run-all.sh`, all 57; the release build, the CaptureProbe warning only; main's CLI masked and sorted,
  idle (8 lines) and with a client (three passes, as main against main); previews 162 files; on loopback a device
  in from a VPN re-asking without clearing a block that holds, and clearing a stale one.
- The second review (2026-10-29, after af3283d1; the report's "The second review"): two findings, each reproduced
  first and fixed in a commit of its own. The first review's correction of when the tool dies was wrong both ways
  (read-only, as noah, 3 runs of 3 each): `--getstealthmode` or `--getallowsigned` after `--getappblocked` kill it
  whatever the path, `--listapps` only after a bundle's, and `--getglobalstate`, `--getblockall` or another
  `--getappblocked` after it answer (78685c9a, docs). A tool that never answered was asked all five questions, and
  one that ignored SIGTERM was left running, a thread blocked on its pipe, after each (FirewallCheck's own code
  against a stand-in: 10.04 s a check; 20.11 s and 5 processes left; the state on and the rest deaf, 16.16 s and
  4), which the menu's re-asking at every opening would add up: nothing more is asked once the state decides
  (`asksRules`: off, Block all, a state that doesn't read) and an unanswered question is killed a second after
  SIGTERM (2.01, 3.01 and 12.06 s, none left; 6d836d1f). Re-run: the check 390 and 69 of 69 mutants; `run-all.sh`,
  all 57; a release build from an empty `.build`, the CaptureProbe warning only; this Mac's firewall through the
  fixed check, 19–22.5 ms for Sill.app's five questions, allows; previews 162 files; on loopback a Block all held
  against a device in from a VPN, then blocked, cleared and unreadable as the canned answer changed.
- **Untested, for Noah:** the report's state by hand (`sudo …/socketfilterfw --add …/Contents/MacOS/Sill`, then
  `--blockapp`; `--remove` after): the device's tap failing, the menu item and log line, General's line and
  Copy, the command in Terminal, then both gone without a relaunch; Block all on and off, also with Sill running
  and its menu opened twice (the glyph turns at the first, Devices Can’t Connect at the second); VoiceOver;
  macOS 14 or 15 (answers that don't read log "Firewall: couldn’t read …" once and show nothing).
