# Product brief — Mac window streaming for iPhone Duo and iPad

Last updated 2026-09-22. Owner: Noah.

## The idea

An iPhone/iPad app plus a free Mac companion. Streams individual Mac windows,
not the whole desktop. Each window feels like a native app on the device.
Built for the iPhone Duo (5.4" outer display, 7.6" inner display, ships
Oct 23 2026 on iOS 27.1) first, iPad second. Apple Pencil acts as the mouse.

Free, open source, tip jar. Adoption is the goal, income is not. Zero servers.

## Competition (checked 2026-09-21)

Verdict: crowded, so it wins on a different value add, not on being first.

| Product | What it does | Price | Gap we can take |
|---|---|---|---|
| Mirage (Ethan Lipnik, Jun 2026) | Mac → iPhone/iPad/Vision Pro, per-window streaming, 120fps, Pencil, Tailscale remote | Free tier (same network, non-Retina); Pro $7.99/mo, $59/yr, $199 lifetime | Closed source (MirageKit license bars competing products). Desktop-first UI. Not Duo-aware. |
| Jump Desktop | Full desktop remote, RDP/VNC/Fluid | $14.99 one-time iOS | No per-window mode |
| Screens 5 | Full desktop, best touch UI | $24.99/yr or $179.99 lifetime | No per-window mode, subscription |
| Sidecar (Apple) | Move one window to iPad; macOS 27 added direct touch | Free | Same Wi-Fi, ~10 m range, no iPhone, no remote |
| Universal Desktop | Per-window Mac streaming, Vision Pro only | $9.99 | Vision Pro only |
| Inset | View-only window preview on LAN | $3.99 | View only |
| Parallels Access | "Mac apps as iPad apps" | Discontinued Mar 2024 | Proof the demand existed |

Our angles: free and open source (vs $59/yr), phone-first and Duo-first
window UI, remote access without requiring Tailscale (later).
Claims that no longer hold: "first per-window streamer", "best picture quality".

App Store policy: guideline 4.2.7 restricts apps that mirror *specific*
software to LAN and bans iOS-style / store-style UIs. Generic window streaming
passes (Mirage is approved). Keep the app drawer a searchable list, not an icon
grid.

## Architecture decisions

- Capture: ScreenCaptureKit per-window (`SCContentFilter(desktopIndependentWindow:)`).
- Encode: VideoToolbox HEVC, real-time, no B-frames. 4:4:4 chroma / lossless
  refinement when the picture is still is a later differentiator.
- Transport: TCP for the spike; expect to move to UDP/QUIC. Bonjour discovery.
- Decode: AVSampleBufferDisplayLayer on device.
- Scale: give each device its own virtual display on the Mac at a chosen HiDPI
  size so text renders crisp at device scale (private API risk; fallback is
  resizing real windows). Minimum window sizes of Mac apps (~500–800 pt) make
  two-pane Duo layouts tight.
- Pairing: iCloud automatic (CloudKit private DB / CKShare) so a Mac on the
  same Apple Account just appears. Manual "add by address" as fallback.
- Remote: v1 is LAN + works-through-Tailscale-if-you-have-it. CloudKit
  signaling + ICE hole punching later, still no servers we run.
- Input: touch, keyboard, Pencil-as-pointer via CGEvents on the Mac.
  Companion needs Screen Recording + Accessibility permissions.

## UI (mockups on the design canvas)

https://claude.ai/artifact/J8nMsghXKkzUVKv6wkJYAn — 9 artboards:
top bar, side rail, app list drawer, two panes with a Mac prompt, laptop mode,
outer display portrait, outer display landscape, first-run pairing, unlock sheet
(now obsolete: replace with a tip jar sheet).

Agreed UI points: bar shows live window previews (thumbnail + app icon badge,
fixed order, badge on windows with open dialogs); leftmost searchable app
drawer; rightmost full-desktop button; side rail or auto-hide bar in landscape;
never span the Duo crease in half-folded posture.

## Scope

v1 objective: ship a free app that streams single Mac windows over LAN and
Tailscale with the best phone/Duo UI in the category.

Success criteria: LAN latency < ~60 ms; pairing < 2 min; 1-hour session with
no drops; approved on the App Store.

In: single-window capture + HEVC; touch/keyboard/Pencil input; live-preview
bar; full-desktop button; Duo inner + outer layouts; iCloud pairing + add by
address.
Out: hole punching, multi-window, layout customization, audio, AV1.

Milestones (solo, ~10 hrs/week; halve at 20):
1. Latency spike, capture→encode→decode — 2–3 wks  ← NOW
2. Input and window control — 3–5 wks
3. Virtual display and scaling — 2–4 wks
4. Client UI and Duo layouts — 4–6 wks
5. Pairing, encryption, reconnect — 2–4 wks
6. Shipping: notarization, permission onboarding, TestFlight, review — 2–3 wks

Costs: $99/yr developer account, domain, optionally a Duo for testing.

## Risks

1. Mirage's head start. Mitigation: use its free tier for a week, build only
   where it's weak.
2. Latency kills it. Mitigation: milestone 1 before anything else.
3. Fragile Mac side (private virtual-display API, TCC prompts change yearly).
   Mitigation: real-window fallback.
4. App Review under 4.2.7. Mitigation: early TestFlight build.
5. Revenue ceiling is low by design (tips). Fine, adoption is the goal.

## Open questions

- Hours per week Noah can really commit.
- App name.
- Apache-2.0 vs MPL-2.0.
