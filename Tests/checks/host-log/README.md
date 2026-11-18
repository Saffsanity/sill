# `host-log`

**Checks:** the log file written by two Sills at once, as at an update's hand-over, where the new copy starts while the old one still runs (docs/one-click-update-plan.md), and at a second launch that waits and leaves: each line whole, at the file's end, in the order written (found on Noah's Mac on 2026-11-14: a second Sill's first line lost, its last two inside older ones); a file one of them moved aside at 10 MB followed by the other from its next line on, the moved one kept whole and moved by the file's real length; a deleted file written again at its path; a file at 10 MB at launch moved aside before the first line. The writers are the check's own binary run twice, each with its own `HostLog`, told when to write, so the order is the same every run. 16 checks, 7 mutants.

**Compiles:** `Sources/SillHost/HostLog.swift` (with `-package-name sill`, which its `package` access needs)
