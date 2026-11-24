**Secrets on the clipboard, and Type on ‹Mac› (2026-11-19, branch `clipboard-secrets` from main at eb48ac9).**
Contributed by a user who streams a Mac to an iPhone Duo away from home and keeps passwords in 1Password on
both. The Mac's Sill.log showed copies going from the Mac to the iPhone (`clip.sent`), but the clipboard
did nothing for the password case:
- a password pasted from the iPhone stayed on the Mac's clipboard, and in its clipboard manager's history;
- one copied on the Mac stayed on the iPhone for 10 minutes;
- a field that refuses a paste took nothing.

Universal Clipboard does not reach a device away from home.
- What: docs/clipboard-plan.md, "Secrets and Type on ‹Mac› (2026-11-19)".
  - `Clipboard.secret` (optional, left out when false, no generation change).
  - A marked Mac copy goes as a secret and leaves the device in 90 s.
  - The device's Pasted Text Is Secret (on unless turned off) makes the Mac write a Paste concealed and
    transient, then clear it after 90 s while it is still the clipboard's.
  - Type on ‹Mac›: the device's copied text typed as `InputEvent.text`, never on the Mac's clipboard.
- Decisions for Noah:
  - Pasted Text Is Secret is on by default, so a Paste of ordinary text also leaves the Mac's clipboard
    after 90 s and stays out of clipboard history; flipping the default is one line.
  - Type on ‹Mac› lives with the clipboard's chip and rows, though it needs no clipboard sharing.
  - The clear is a write while the Mac may be locked (only of the host's own write, and only while macOS
    lets Sill read the change count): it makes a password leave sooner, never adds one.
- Verified:
  - `Tests/checks/clipboard` (cases and mutants).
  - `Tests/checks/run-all.sh`.
  - `swift build` and the iOS app's Debug simulator build.
  - The live loopback runs and Duo simulator photos in the plan's section.
- Untested here:
  - A real device: no signing.
  - Whether posted keys reach every secure field: 1Password's unlock field, SecurityAgent's password
    field, a terminal with Secure Keyboard Entry. Posting is not what Secure Event Input blocks, but no
    one has tried it with Sill.
