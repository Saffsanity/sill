**Sill's nightly key: its public half in `nightlyKeys` (2026-11-15, branch `nightly-key` from main at a186881).**

- **The key.** Noah made it on his Mac on 2026-11-15, by the plan's §16.8, in Terminal: an encrypted disk image,
  `Scripts/sign-nightly.sh --new-key --key-file` a file on it, then `gh secret set SILL_NIGHTLY_UPDATE_KEY --env
  nightly --repo Saffsanity/sill` straight from that file. Public key
  `LdPr0TWuzpFrPlCivrH1UGypmw65S2fQ76diCh+loRo=`, key ID 3e6d90f4. The private half is that secret (GitHub lists
  it since 08:50 UTC) and the file on his image; it was never in this repository, in his keychain or in a chat.
  It is not the update key (`releaseKeys`, key ID dbbd6d58), and no release is ever signed with it.
- **What changes.** One line: `UpdateManifest.nightlyKeys` lists it. A Sill built from a commit that has it shows
  "Use nightly builds" in Settings › General, off, and with it on takes a nightly whose `Sill-nightly.zip.manifest`
  this key signed, by Update Now only. nightly.yml signs each night's build from the first run on a commit that has
  the key (`Scripts/sign-nightly.sh` reads the manifest back with this line), and says so in its summary.
- **Verified.** The key is 32 bytes and its ID is the first four bytes of its SHA-256; `update-install` passes on
  this branch (it checks that every nightly key listed is usable and is no update key and not the tests' key).
- **Not in this change:** README's nightly block and the checklist's and CLAUDE.md's "empty until Noah makes the
  key" go with the release's own pull request; a nightly of a version is not yet offered that version's release
  (Noah, 2026-11-15: "Someone on a 0.6.2 nightly should get offered official 0.6.2 release.", its own branch).
