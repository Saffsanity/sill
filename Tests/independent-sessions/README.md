# Independent stream integration check

Build the host and run:

```sh
swift build -c debug
python3 Tests/independent-sessions/check.py .build/debug/SillHost
```

The Python standard-library harness launches its own synthetic, loopback-only host. It forces the software encoder, uses a synthetic pasteboard, and logs input without posting any real Mac events. It never installs an app, reads or writes the user's clipboard, captures the real Desktop, pairs a device, or changes a running host. Its temporary host log is `/tmp/sill-independent-sessions-host.log`.

It exercises actual admitted TCP connections and the shipped coordinator/server paths: independent source selection and HEVC parameter/frame routing; separate viewport frame rates and quality settings; an idle/stopped session receiving no other session's video; coexistence with a legacy shared client; delayed first-hello output withholding; legacy no-hello fallback and explicit late-opt-in refusal; shared clipboard subscriptions; foreground modifier release before another owner's key; one scene closing while another continues; four-session capacity, refusal, and slot reclamation; unsupported-generation refusal.

The check uses the existing development-only plain CLI door. TLS admission, trust, revocation, and the paired production doors remain owned by the original root server; scoped servers never create listeners. Physical Mac window fitting, duplicate-window geometry, real foreground activation/menus, hardware input, and visionOS scene lifecycle need device testing. `Tests/checks/window-restore/run.sh` additionally checks the actual shared restore ledger with fake Accessibility access, including restoration only after the final viewer leaves.
