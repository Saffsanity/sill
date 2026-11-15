**The pointer-watch check's stale mutant, and checks for the no-screen hook (2026-11-12, branch
`pointer-watch-mutant` from main at 919e05a, PR #361 (a draft)).** Noah: "Run the mutants job once on GitHub". Run
43198344081 on main at 0d22bbf: 67 of the 68 checks with mutants caught every mutant, and
`pointer-watch` failed, 39 of 40, with "any value turns the software encoder on: NOT APPLIED
(pattern found 2 times)". Tests only: no app code, no wire change.
- Why: that mutant's pattern, `guard value == "1" else {`, was one line of PointerWatch.swift until
  54e46436 (2026-10-26) added `PointerTestHooks.noScreen` (SILL_TEST_NO_SCREEN) with the same guard.
  From then the pattern matched twice, `mutants.py` applies a pattern only when it is there exactly
  once, and the mutants job, which runs only by hand, failed whenever it ran. That commit added no
  check of the new hook either, so nothing said so at its pull request.
- What: the pattern now ends in the software encoder's own words. `main.swift` checks `noScreen` as
  it checks `softwareEncoder` (no variable, an empty one, 1 on a synthetic host, a real host,
  another value): 137 checks, 132 before. Two mutants for it, "a real host takes no screen" and
  "any value turns no screen on": 42 mutants, 40 before. README.md and run.sh name the hook.
- Verified on this Mac, in the heavy lock: `Tests/checks/pointer-watch/run.sh` 137 of 137;
  `run.sh --mutants` 42 of 42 caught, the repaired one at line 530 ("another value is ignored") and
  the new two at lines 540 and 542; every pattern found exactly once; `Tests/checks/repo-rules`.
- Not done, for Noah to decide: a pattern that comes to match twice still shows only in the mutants
  job. Counting each pattern in the ordinary run (seconds, no compile) would say so at the pull
  request that causes it; that belongs with the mutant scripts' other edge cases, which wait for
  his word.
