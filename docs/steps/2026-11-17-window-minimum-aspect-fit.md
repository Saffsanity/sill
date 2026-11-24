# Virtual-stage window aspect fitting after an app clamps its size

The Mac host requests the phone pane size, but an app may take a larger minimum.
In a ChatGPT window, a 404×252 request produced 480×600: fitting that complete
window into the phone pane left wide side bars. Enlarge the requested rectangle
uniformly to contain the accepted size (962×600 in this case), then ask the app
for that rectangle. Capture its actual bounds as before. There is no iOS or wire
change, and this applies to ordinary windows on the virtual stage only.

One aspect correction is allowed. If the app still refuses it, keep its actual
bounds rather than stretch the pixels or crop to pretend the fit succeeded.
Targets outside the display budget fall back; the height budget conservatively
reserves 100 points for the menu bar. Fixed-size windows can still letterbox.
Increasing the logical window size also makes text smaller at the same Aa setting.

ChatGPT exposed asynchronous resizing during repeated app switches: the list
could show 482×600, then 480×600, before a later 962×600 request took effect.
WindowFrameSettling requires at least 200 ms of observation and 150 ms without a
frame change (20 ms polling, 1.2 s deadline). Each target has up to two retries;
learning the minimum does not consume the corrected target's retries. The whole
placement loop is bounded to nine passes. This adds latency when an app rejects
sizes. A repeated preparation of the same window and requested size reuses the
accepted size rather than probing the minimum again.

Validation:
- capture-scale: 189 checks passed, including aspect fitting, display-budget
  fallback, and a synthetic trace of intermediate/final resize frames.
- Signed release Mac build succeeded and was installed locally.
- The tester used an iPhone Air with ChatGPT, Muse and Grok. After the settling
  fix, they reported that frequent switching no longer reproduced the black
  bars. This is one-device manual verification, not an automated real-app test.
- Full pure-check suite: see the PR for the final run result.

Related: upstream #203 approaches the same minimum-size/letterbox problem from
iOS by trying Aa scales. This offers a host-side continuous size calculation,
without claiming to replace its broader Auto-mode UI or non-virtual behavior.
