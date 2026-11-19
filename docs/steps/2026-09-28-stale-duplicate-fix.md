**A Mac set up again: the old saved record retires itself (2026-09-28, branch `stale-duplicate-fix`
from main at 72d8d1d).** Noah: "When using Tailscale, it shows Noah's MacBook Pro and Noah's MacBook
Pro (2) and only 2 works." Sill for Mac 0.4.0's new key made the device pair again (#44), and the old
record stayed (#44's known gap): away from home both were Remote rows, the old one's pin refused.
Device only, no wire change:
- A remote dial of a saved Mac also takes, at one address, the key of another saved record that
  `RemoteDialPolicy.successors` names: the same name, not revoked or `newKey`, paired after the old
  one was last reached (`lastConnectedAt ?? pairedAt`), at an address that names one machine
  (Tailscale's shapes, an internet address or name; loopback in DEBUG only). A private, `.local` or
  other VPN's address never counts: another network's Mac can hold it (home and office). The key is
  taken in the verify block (`DeviceTLS.options(alsoAccept:)`, RemoteConnector's `successors` by
  candidate); once the handshake completes with it (TLS 1.3: the Mac holds that key), the old record
  is removed (`SavedMacs.superseding`: the newer takes its typed addresses, `homeTLS`, and the
  proving address as `lastWorked`) and the session goes on as the newer record. Never on the name
  alone; a record reached since the other was paired stays (two Macs in use).
- The Remote rows list one name's records together, newest first (`SavedMacs.remoteOrder`), so the
  one that works leads until the old one is tried.
- Checks: remote-rules 123 (16 new) and 72 of 72 mutants (20 new; CI's mutants matrix has it already).
- Verified on a private simulator ("Sill dupfix", deleted after) against loopback synthetic hosts
  (software encoder, `--pairing --remote=47455`, `SILL_TEST_REMOTE_DIR` per identity): paired with
  identity A, then B at the same address and port, both saved as on Noah's devices ("Noah's MacBook
  Pro (2)"); `-SillDialSaved 1` dials A as its Remote row does. Before (main's build): -9808 at
  127.0.0.1, both kept. After: "answered with the key of B …: A superseded", connected, one record,
  named without "(2)". Negatives: A and B at different ports, both running: A's dial reaches A, both
  kept; A reached after B was paired, then B at A's address: -9808, both kept. iOS Debug for the
  simulator and Release for a generic device (only the known `StreamClient` warning);
  `Tests/checks/run-all.sh` all passed.
- **Untested, for Noah:** on the iPad and iPhone with this build, away from home on Tailscale: tap
  the old "Noah's MacBook Pro" row: it connects (to the Mac's new key) and the "(2)" row is gone,
  the survivor named plainly. At home over the LAN alone the old row still says it is not the Mac
  paired with (a private address proves nothing); with Tailscale on at home it cleans up too.
