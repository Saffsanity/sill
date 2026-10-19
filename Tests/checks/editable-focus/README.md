# Explicit editable click confirmation

`run.sh` checks the conservative editable evidence decision and generation-1 wire compatibility.
Kind 33 uses `EditableFocus(token, source, x, y, editable)`; request omits editable, reply supplies
it. WindowList.editableFocus=1 opts in. Old WindowList JSON decodes with nil; old readers skip33.
No field value/title/selection is read or sent. Client must match latest token, source, connection
and selection before requesting keyboard focus and must preserve manual dismissal/mode gating.

Host only checks its latest exact stationary down/up pair actually delivered by InputInjector,
from the requesting connection, same source/selection/mapped rectangle, younger than .8 seconds.
Any newer input/gesture/window command/selection or capture select invalidates the result.
A click held for activation, drag, uncertain frame or AX failure yields false. The request is
consumed once. Single in-flight read: one120ms settle, detached AX read with .05s per-call timeout,
.5s deadline and fixed call count; no observer/polling. Final result must remain younger than1.5s.

AX confirmation requires exact clicked element identity == focused element identity, whitelisted
text role, explicitly enabled, and settable AXValue. Window source additionally requires PID and
AXWindow frame match to the current CG source window. A fresh bounded CG snapshot before and after
the worker rejects same-PID windows sharing those bounds (no ambiguous AX-to-CG association). Focus and hit target are checked again last.
This deliberately misses editors exposing children/containers, uncertain/read-only text and first
clicks deferred for activation. Tests establish wire/policy behavior and compilation, not actual
remote Mac editor acceptance. Physical test: click editable field, Photos image/toolbar while the
previous field retains focus, readonly text, another window, quick source switch, manual keyboard
dismissal, host disconnect and old-host session; only the actual focused editable target may open.
