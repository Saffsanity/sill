**Sill's update key: its public half in `releaseKeys` (2026-11-15, branch `update-key` from main at 19af958).**

- **The key.** Noah made it on his Mac on 2026-11-15, after the rehearsal had passed (the handoff's
  `one-click-update/rehearsal/RESULTS.md`): `Scripts/sign-update.sh --install-signer` from main at 19af958, then
  `--new-key`. Public key `VBi6RT1SKi60dit73HwGK1T3YALXQCPpq/rQX49+ZVE=`, key ID dbbd6d58. The private half is in
  his login keychain (service `me.saffer.sill.update-signing`) and in his own copy off the Mac; it was never in
  this repository, in CI or in a chat.
- **What changes.** One line: `UpdateManifest.releaseKeys` lists it. From the first release built from a commit
  that has it, Sill for Mac shows Update Now and Automatically update Sill, and installs a later release whose
  `Sill.zip.manifest` this key signed (docs/release-checklist.md, part 1 §7 and part 2). No release is signed yet,
  so nothing installs anywhere until Noah signs one.
- **For Noah after the merge:** `Scripts/sign-update.sh --install-signer` again from that commit (the trust it
  shows then lists this key), as the checklist's part 1 §7 says.
- **Verified.** `update-install` 974 of 974 on this branch (it checks that every key listed is 32 bytes, usable,
  not of small order, and not the tests' key); `swift build -c release`.
- **Not in this change:** README's Update Now block stays hidden until the release that carries the key
  (the release's pull request shows it), and the nightly key is its own step (the plan's §16.8).
