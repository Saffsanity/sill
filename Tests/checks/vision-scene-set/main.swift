import Foundation
var checks = 0
func expect(_ ok: @autoclosure () -> Bool, _ label: String) { checks += 1; precondition(ok(), label) }
let secondaryID = UUID(uuidString: "00000000-0000-4000-8000-000000000029")!
let primary = VisionSceneSet.Entry(windowID: nil, sessionID: "synthetic-primary", workspace: .init(macID: "synthetic-mac", width: 1200, height: 800))
let secondary = VisionSceneSet.Entry(windowID: secondaryID, sessionID: "synthetic-secondary", workspace: .init(macID: "synthetic-mac", width: 1800, height: 1200), preferences: .init(toolbarAutomatic: false, mouseMode: true, textScale: 1.25))
var set = VisionSceneSet(); set.upsert(primary, admitVisible: true); set.upsert(secondary, admitVisible: true)
expect(VisionSceneSet.decode(set.encoded) == set, "Durable scene set round trip")
expect(!set.encoded.contains("keyboard") && !set.encoded.contains("fingerprint") && !set.encoded.contains("recognitionKey") && !set.encoded.contains("addresses"), "No keys, routes or keyboard persisted")
var subset = set; subset.discard(["synthetic-secondary"])
expect(subset.entries == [primary], "Individual closure retires only its descriptor")
var all = set; all.discard(["synthetic-primary", "synthetic-secondary"])
expect(all.entries.count == 2 && all.entries.allSatisfy { $0.sessionID.isEmpty }, "Whole-set discard preserves logical workspace and retires native handles")
var rebound = secondary; rebound.sessionID = "synthetic-rebound"
var late = set; late.upsert(rebound); late.discard(["synthetic-secondary"])
expect(late.entry(secondaryID) == rebound, "Late discard cannot retire a rebound scene")
var unbound = all; unbound.upsert(primary); unbound.discard(["synthetic-primary"])
expect(unbound.entry(nil) == nil && unbound.entries.count == 1, "Unknown native handles cannot turn subset into whole-set discard")
var cap = set
for _ in 0..<6 { var e = secondary; e.windowID = UUID(); e.sessionID = UUID().uuidString; cap.upsert(e) }
expect(cap.entries.count == 4 && cap.entry(nil) == primary, "Cap4 preserves already admitted scenes")
var duplicate = secondary; duplicate.windowID = UUID(); duplicate.sessionID = primary.sessionID
var duplicates = set; duplicates.upsert(duplicate)
expect(duplicates.entries.count == 2, "Duplicate native session cannot belong to two logical scenes")
let badJSON = set.encoded.replacingOccurrences(of: "synthetic-secondary", with: "synthetic-primary")
expect(VisionSceneSet.decode(badJSON).entries.isEmpty, "Duplicate native session rejected on decode")
let invalidJSON = set.encoded.replacingOccurrences(of: secondaryID.uuidString, with: "not-a-uuid")
expect(VisionSceneSet.decode(invalidJSON).entries.isEmpty, "Invalid UUID rejected")
var changed = secondary; changed.preferences.textScale = 9
var invalidPrefs = set; invalidPrefs.upsert(changed)
expect(invalidPrefs == set, "Invalid preference cannot replace saved scene")
expect(VisionSceneSet.decode(String(repeating: "x", count: 20481)).entries.isEmpty, "Oversized journal rejected")
var replay = VisionSceneReplay(); expect(replay.start(), "First launch starts replay")
expect(!replay.start(), "Process active transitions do not schedule again")
expect(!replay.claim(primary, in: set, bound: ["primary"]), "Native primary binding prevents duplicate")
expect(replay.claim(secondary, in: set, bound: ["primary"]), "Missing secondary is claimed")
expect(!replay.claim(secondary, in: set, bound: ["primary"]), "Failed presentation is not retried in loop")
var restarted = VisionSceneReplay(); _ = restarted.start()
expect(restarted.claim(secondary, in: VisionSceneSet.decode(set.encoded), bound: ["primary"]), "Fresh process replays same persisted UUID")
var cancelled = VisionSceneReplay(); _ = cancelled.start(); cancelled.cancel()
expect(!cancelled.claim(secondary, in: set, bound: []), "Disconnect/closure cancels queued replay")
var forgotten = set; forgotten.retainMacs([])
var forgettingReplay = VisionSceneReplay(); _ = forgettingReplay.start()
expect(!forgettingReplay.claim(secondary, in: forgotten, bound: []), "Forget before delayed replay prevents resurrection")
var retired = set; retired.remove(secondaryID)
expect(!forgettingReplay.claim(secondary, in: retired, bound: []), "Explicit disconnect retires queued descriptor")
let launchAliases = Dictionary(uniqueKeysWithValues: set.entries.map { ($0.key, $0.sessionID) })
var reboundPrimary = primary; reboundPrimary.sessionID = "synthetic-new-primary"
var launchSet = set; launchSet.upsert(reboundPrimary)
launchSet.discard([primary.sessionID, secondary.sessionID], launchSessions: launchAliases)
expect(launchSet.entry(nil)?.sessionID == reboundPrimary.sessionID && launchSet.entry(secondaryID)?.sessionID == "", "Delayed old whole-set discard after primary rebind preserves both logical scenes")
var bindings = VisionSceneBindings()
expect(bindings.bind("primary", session: primary.sessionID), "Bind primary session")
expect(bindings.bind(secondary.key, session: secondary.sessionID), "Bind secondary session")
bindings.discard([secondary.sessionID])
expect(bindings.sessions[secondary.key] == nil, "Discard removes old binding before late view update")
expect(!bindings.bind(secondary.key, session: secondary.sessionID), "Discarded view cannot rebind itself and resurrect")
expect(bindings.bind(secondary.key, session: "replacement"), "New actual native scene can claim same stable UUID")
expect(!bindings.bind("primary", session: "replacement"), "One native scene cannot bind two logical scenes")
var normalRefresh = set; normalRefresh.retainMacs(["synthetic-mac"])
var normalReplay = VisionSceneReplay(); _ = normalReplay.start()
expect(normalReplay.claim(secondary, in: normalRefresh, bound: ["primary"]), "Unchanged admitted Macs during initial connect cannot cancel replay")
var launchReplay = VisionSceneReplay(); _ = launchReplay.start()
expect(launchReplay.claim(launchSet.entry(secondaryID)!, in: launchSet, bound: ["primary"]), "Whole-set discard during startup still replays missing secondary")
expect(!bindings.owns(secondary.key, session: secondary.sessionID), "Detached old view cannot save under new sameUUID binding")
expect(bindings.owns(secondary.key, session: "replacement"), "Rebound scene may update its own saved state")
var duplicateObject = try! JSONSerialization.jsonObject(with: Data(set.encoded.utf8)) as! [String: Any]
var duplicateEntries = duplicateObject["entries"] as! [[String: Any]]
duplicateEntries.append(duplicateEntries[1]); duplicateObject["entries"] = duplicateEntries
let duplicateText = String(data: try! JSONSerialization.data(withJSONObject: duplicateObject), encoding: .utf8)!
expect(VisionSceneSet.decode(duplicateText).entries.isEmpty, "Duplicate logical UUID rejected on decode")
var sameProcess = VisionSceneReplay(); _ = sameProcess.start()
_ = sameProcess.claim(secondary, in: set, bound: ["primary"])
sameProcess.cancel(); sameProcess.resetAfterConfirmedClosure()
expect(sameProcess.start(), "Confirmed whole-scene-set closure allows a new cycle without process death")
expect(sameProcess.claim(secondary, in: set, bound: ["primary"]), "Whole-app reopen in same process restores secondary once")
expect(!sameProcess.claim(secondary, in: set, bound: ["primary"]), "Same-process recovery remains bounded per closure cycle")
var legacyJSON = try! JSONSerialization.jsonObject(with: Data(set.encoded.utf8)) as! [String: Any]
legacyJSON["version"] = 1; legacyJSON["members"] = nil
let legacyText = String(data: try! JSONSerialization.data(withJSONObject: legacyJSON), encoding: .utf8)!
let migrated = VisionSceneSet.decode(legacyText)
expect(migrated.entries.count == 2 && migrated.members.isEmpty, "Legacy descriptors survive without inheriting stale membership")
var legacyFour = VisionSceneSet()
for i in 0..<4 { var entry = secondary; entry.windowID = UUID(); entry.sessionID = "legacy-\(i)"; legacyFour.upsert(entry) }
expect(legacyFour.entries.count == 4 && legacyFour.members.isEmpty, "Four legacy secondary descriptors start as fallback only")
expect(legacyFour.upsert(primary, admitVisible: true, protecting: [primary.key]), "An actual visible primary is admitted despite full stale cap")
expect(legacyFour.upsert(secondary, admitVisible: true, protecting: [primary.key, secondary.key]), "Actual visible secondary is admitted over stale fallback")
expect(legacyFour.members == [primary.key, secondary.key] && legacyFour.entries.count == 4, "Only actual two scenes become restore members")
var phases = VisionScenePresence()
phases.update(primary.key, phase: .active); phases.update(secondary.key, phase: .active)
phases.update(primary.key, phase: .inactive)
expect(!phases.reopenArmed, "Focus or alert inactivity doesn't arm reopening")
phases.update(primary.key, phase: .background)
expect(!phases.reopenArmed, "One backgrounded window cannot arm a whole-app reopen")
phases.update(secondary.key, phase: .background)
expect(phases.reopenArmed && phases.foreground.isEmpty, "All-background transition arms next actual Sill activation")
expect(!phases.consumeReopen(), "No windows open while Sill remains backgrounded")
phases.update(primary.key, phase: .active)
expect(phases.consumeReopen(), "First Sill activation consumes same-process workspace reopen cycle")
expect(!phases.consumeReopen(), "Repeated activations do not create new recovery cycles")
var hiddenReplay = VisionSceneReplay(); _ = hiddenReplay.start()
expect(hiddenReplay.claim(secondary, in: set, bound: phases.foreground), "Hidden but still natively bound scene is eligible for reactivation")
expect(!hiddenReplay.claim(secondary, in: set, bound: phases.foreground), "Hidden native scene only requests presentation once")
var quickPresence = VisionScenePresence()
quickPresence.update(primary.key, phase: .active); quickPresence.update(secondary.key, phase: .active)
var quickBatch = VisionSceneClosureBatch()
quickPresence.update(primary.key, phase: .background); quickBatch.observe(quickPresence)
quickPresence.update(secondary.key, phase: .background); quickBatch.observe(quickPresence)
quickBatch.disconnected[secondary.key] = secondary.sessionID
quickPresence.update(primary.key, phase: .active)
var quickBindings = VisionSceneBindings(); _ = quickBindings.bind(secondary.key, session: secondary.sessionID)
expect(quickBatch.observedWholeSetHidden && !quickBatch.shouldRetire(secondary.key, session: secondary.sessionID, bindings: quickBindings), "Quick reopen before settle preserves observed whole-workspace closure")
var individualBatch = VisionSceneClosureBatch(); individualBatch.disconnected[secondary.key] = secondary.sessionID
expect(individualBatch.shouldRetire(secondary.key, session: secondary.sessionID, bindings: quickBindings), "Individual sibling disconnect retires after settle when no whole-set closure occurred")
_ = quickBindings.bind(secondary.key, session: "replacement")
expect(!individualBatch.shouldRetire(secondary.key, session: secondary.sessionID, bindings: quickBindings), "Old disconnect cannot retire new sameUUID native binding")
var handleJournal = set; handleJournal.upsert(rebound)
handleJournal.retireHandles([secondary.sessionID])
expect(handleJournal.entry(secondaryID)?.sessionID == rebound.sessionID, "Old discard cannot clear rebound session metadata")
var inactiveSave = VisionSceneSet(); _ = inactiveSave.upsert(primary)
expect(inactiveSave.members.isEmpty && inactiveSave.entry(nil) == primary, "Inactive bind/save keeps descriptor without claiming current visibility")
_ = inactiveSave.upsert(inactiveSave.entry(nil)!, admitVisible: true, protecting: [primary.key])
expect(inactiveSave.members == [primary.key], "Actual native activation enrols existing descriptor even without SwiftUI phase change")
var inactiveFull = legacyFour
let pendingVisible = VisionSceneSet.Entry(windowID: UUID(), sessionID: "new-inactive", workspace: primary.workspace)
expect(!inactiveFull.upsert(pendingVisible), "Full fallback cap may defer inactive new descriptor")
expect(inactiveFull.upsert(pendingVisible, admitVisible: true, protecting: [pendingVisible.key]), "Retained pending descriptor is admitted on actual native activation")
// Explicit window management resolves ambiguous native background-only close delivery.
var managed = set
managed.setRestoring(secondaryID, enabled: false)
expect(managed.members == [primary.key] && managed.entry(secondaryID) != nil,
       "removing stale restore member keeps descriptor and valid primary")
managed.upsert(secondary, admitVisible: true)
expect(!managed.members.contains(secondary.key), "late active/save callback cannot re-enrol explicit close")
var decodedManaged = VisionSceneSet.decode(managed.encoded)
expect(decodedManaged == managed, "explicit exclusion persists across process relaunch")
decodedManaged.upsert(rebound, admitVisible: true)
expect(!decodedManaged.members.contains(secondary.key), "native rebind remains excluded until explicit inclusion")
var managedReplay = VisionSceneReplay(); _ = managedReplay.start()
expect(!managedReplay.claim(secondary, in: managed, bound: [primary.key]), "excluded scene cannot be replayed")
managed.retireHandles([primary.sessionID, secondary.sessionID])
expect(managed.members == [primary.key] && managed.excluded == [secondary.key],
       "delayed whole-set handle retirement preserves explicit membership choice")
managed.upsert(secondary, admitVisible: true)
expect(!managed.members.contains(secondary.key), "late save after whole-set closure still cannot resurrect exclusion")
managed.setRestoring(secondaryID, enabled: true)
expect(managed.members.contains(secondary.key) && managed.excluded.isEmpty,
       "user can explicitly restore an excluded descriptor")
managed.setRestoring(secondaryID, enabled: false)
_ = managed.discard([secondary.sessionID])
expect(managed.entry(secondaryID) == nil && managed.excluded.isEmpty && managed.members == [primary.key],
       "definite individual discard removes excluded descriptor without touching valid sibling")
var priorVersionObject = try! JSONSerialization.jsonObject(with: Data(set.encoded.utf8)) as! [String: Any]
priorVersionObject["excluded"] = nil
let priorVersionText = String(data: try! JSONSerialization.data(withJSONObject: priorVersionObject), encoding: .utf8)!
expect(VisionSceneSet.decode(priorVersionText).members == set.members,
       "build30 two-window membership survives migration with no exclusions field")
for episode in 0..<1000 {
    var trial = VisionSceneReplay(); _ = trial.start()
    let active = episode.isMultiple(of: 2) ? Set(["primary"]) : Set<String>()
    var requested = Set<String>()
    for entry in set.entries.shuffled() + set.entries.shuffled() {
        if trial.claim(entry, in: set, bound: active) { expect(requested.insert(entry.key).inserted, "Random order never claims a logical scene twice") }
    }
    expect(requested.isDisjoint(with: active), "Random order never recreates bound native scene")
}
print("vision-scene-set: \(checks) checks passed")
