# Embedding the native Mac host

`SillMenuBar --embedded` is an opt-in mode for a containing application that
builds and bundles the Mac host. The normal Sill app and device wire protocol
keep their existing behavior. The containing app owns updates, signing, user
entry points and the host's lifetime; no separately installed Sill app is used.

## Private control channel

Start the bundled executable with `--embedded`, a private stdin pipe, and a
drained stdout pipe. Each command is one UTF-8, LF-terminated line:

- `settings`: show or bring forward the native Settings window.
- `pair`: show or bring forward the normal device pairing window.
- `quit`: run the existing AppKit orderly termination path.

EOF also quits, including when the parent exits or crashes. Invalid UTF-8,
unknown/empty commands, CRLF and commands longer than 32 bytes terminate the
control channel and quit. Commands received before startup completes are bounded
to 16 pending entries. Quit and EOF work before startup completes. Pairing codes
are shown only by the normal native pairing UI, never emitted by this interface.

Stdout still contains the host's normal diagnostic lines. The owner must drain
it without displaying or interpreting those lines as control. Two exact line
markers are added in embedding mode:

- `SILL_EMBEDDED_READY`: coordinator startup returned. This means the host is
  running, not that permissions, network registration or a device stream have
  been verified. The native Settings window reports those separately.
- `SILL_EMBEDDED_FAILED`: coordinator creation/startup failed. The owner should
  close stdin and surface an error. Sill remains alive until orderly shutdown.

No extra socket, URL handler or network control endpoint is added. An embedding
owner should not expose its private pipe to unrelated processes. Closing the
pipe is preferred to force-killing the host so held input and window positions
can be restored through the existing shutdown implementation.

## Bundle and state

Give the nested app its own bundle identifier, display name, signing and local
network usage description. Set `SillManagedHost` to true in its Info.plist to
refuse independent Finder/login launches that lack `--embedded`. This marker is
a packaging guard, not a security boundary. Never reuse Sill's bundle identifier,
provisioning profile or keychain entitlement.

Embedded hosts derive keychain query names from their own bundle identifier;
standalone Sill keeps the original query names. No migration reads or imports
standalone Sill identity, recognition keys, trusted devices or Require pairing.
Keychain access-group selection and fail-closed identity handling stay as before.
Local defaults use the nested bundle's own domain, and logs go under
`~/Library/Logs/<bundle identifier>/Sill.log`.

Embedding mode has no independent status item, automatic update check or login
item. The parent provides the entry points. After a permission change, Quit in
the permission pane stops the managed host; the parent starts it again. It must
not automatically relaunch as an independent Sill app. Native host settings and
pairing behavior otherwise remain Sill's, including default pairing and remote
access rules. The parent must explain separate permissions to the user.

The embedding API is a proposed integration surface (issue #125), subject to
maintainer review. A containing app should pin its source revision and retain
Sill's Apache-2.0 license and attribution. It must not use Sill's update check to
replace its nested host with a standalone release.

## Checks

`Tests/checks/embedded-control/run.sh` exercises split/batched framing, close
semantics and isolated/default keychain query names without keychain access.
After `swift build -c release --product SillMenuBar`, run
`python3 Tests/embedded-host/run.py` for real synthetic-host EOF/invalid-command
shutdown with no device, screen capture or private input. This does not prove
physical-device streaming, permission attribution or real-window restoration.
