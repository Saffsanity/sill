**A locked Mac shows nothing of itself (2026-10-31, branch `locked-mac`, PR #271; shipped in 0.6.0, the
entry above).** The rule, the review, the open questions, the results and Noah's tests of 2026-11-01 and 02
are in `docs/locked-mac-plan.md`. In brief: three readings (`LockPolicy`, pure, `Tests/checks/lock-policy`;
`SessionLock` on `sill.lock`): unlocked, screen locked (its lock screen streams; a paired session's input
reaches it, the password included), off console (a black placeholder, `StillCapture`, and the device's cover
"Another user started controlling this Mac.", Noah's words); `LockGate` withholds windows, thumbnails, icons,
apps, launches, menus, gestures, sound, clipboard, pointer and the virtual display; `WindowList.locked` and
`offConsole` (additive). TEST ONLY: `SILL_TEST_LOCKED`, `SILL_TEST_LOCKED_FILE`, `SILL_TEST_LOCK_NOTIFY`,
`SILL_TEST_LOCK_NOTE`, `SILL_TEST_LOCK_IGNORE_MAC`, `SILL_TEST_LOCK_LOG`; `Scripts/lock-check/`; DEBUG
`-SillMacLocked 1|2|unlocking`.
- **Untested, for Noah (the plan's 1–7):** a real lock with a window streaming (Virtual Display on and off); the
  password typed from the paired iPad (secure input may refuse posted keys); another user at the login screen
  (the switched-to-another-user cover, nothing typed reaches the Mac, macOS's own lock after the switch back);
  Sill.app inactive at the lock and the unlock (`.deliverImmediately`); an unpaired device at a locked Mac; the
  rest refused and back after the unlock; mixed builds (the App Store iPad gets the black placeholder).
