# Scene-set recovery checks

Run `Tests/checks/vision-scene-set/run.sh` from repository root. This compiles production journal,
replay, phase, closure-batch and session-ownership policies against synthetic descriptors. It
covers legacy four-secondary migration, active primary/secondary admission at cap, hidden bound
recovery, no opening before actual Sill activation, quick reopen before closure settlement,
whole/subset discard, late native callbacks, Forget, explicit Disconnect and source/preferences.

The DEBUG fixture uses actual app windows and production bind/save/membership enrollment, with
no network client. It does not preseed the journal:

```sh
xcrun simctl install SIMULATOR /path/to/Debug-xrsimulator/SillVision.app
xcrun simctl launch --console-pty SIMULATOR me.saffer.sill.vision -SillSceneSetFixture -SillSceneSetFixtureTwo
```

The extra `FixtureTwo` flag explicitly opens typed UUID `00000000-0000-4000-8000-000000000029`.
The typed scene uses Mouse on, text scale1.25, Auto off. Use the Simulator's actual Close App UI if available, then check event3 before reopening with
only `-SillSceneSetFixture`. Home may merely overlay its launcher while scenes remain foreground;
that does not test background recovery. Both windows should
reappear without a third and with the same process PID. Do not pass `FixtureTwo` during recovery.
`simctl terminate` exercises a distinct new-process branch and cannot establish this regression.

Release numeric evidence is atomically written off the UI thread to `Caches/SillSceneRecovery.json`,
keeping the last60 events across process launches. Codes:

| Code | Meaning |
| --- | --- |
|0|process start|
|1|native bind/connect|
|2|native activate|
|3|native background|
|4|native disconnect|
|5|permanent-discard callback|
|6|closure batch settled|
|7|descriptor save accepted|
|8|descriptor save declined|
|9|explicit restore intent clear|
|10|all-background to actual activation recovery cycle|
|11|replay presentation attempted|
|12|native presentation requested (not proof of acceptance)|
|13|native primary presentation declined, numeric error only|
|14|replay deferred by transient inactive owner|
|15|requested scene subsequently actually activated/bound active|
|16|activation callback not yet mapped to an owning scene|
|17|background callback not mapped to an owning scene|
|18|disconnect callback not mapped to an owning scene|
|19|inactive callback not mapped to an owning scene|

Every event includes timestamp, secondary-role flag, descriptor/member/foreground/bound counts and
an optional numeric error. No Mac IDs, titles, UUIDs, native IDs, keys or network data are recorded.

Physical gates: actual Close Sill/Force Quit transitions, a single closed sibling without ghosts,
trusted reconnect to two real sources, confirmed sizes/settings and keyboard off. Single-window
background without disconnection cannot distinguish X from out-of-field-of-view backgrounding.
