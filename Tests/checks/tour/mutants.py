"""H2 (docs/first-run-walkthrough-plan.md, §14 step 1) mutants of TourPolicy.swift, and of Larger Picture's
rule in PhonePortraitLayout.swift (docs/larger-picture-plan.md): each changes one in one place, is compiled
with the check and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/TourPolicy.swift")
MUTANTS = [
    # When it shows by itself.
    ("the beat dropped", "if m.now < opens + beat { return .wait(until: opens + beat) }", "if false { return .wait(until: opens + beat) }"),
    ("activity since the picture ignored", "if let activity = m.lastActivityAt, activity >= opens { return .pass(.used) }", "if let activity = m.lastActivityAt, activity >= opens, false { return .pass(.used) }"),
    ("activity measured from the picture, not from a turn", "if let activity = m.lastActivityAt, activity >= opens {", "if let activity = m.lastActivityAt, activity >= picture {"),
    ("a rotation in the beat does not start it again", "let opens = max(picture, m.layoutAt)", "let opens = m.decided ? max(picture, m.layoutAt) : picture"),
    ("an inherited decision opens at the screen's start, not its picture", "let opens = max(picture, m.layoutAt)", "let opens = m.decided ? m.layoutAt : max(picture, m.layoutAt)"),
    ("a touch down ignored", "if m.touchesDown > 0 { return .pass(.busy) }", "if m.touchesDown > 99 { return .pass(.busy) }"),
    ("busy ignored", "if m.busy { return .pass(.busy) }", "if m.busy && false { return .pass(.busy) }"),
    ("offered ignored", "guard !m.offered else { return .pass(.nothingOwed) }", "guard !m.offered || true else { return .pass(.nothingOwed) }"),
    ("skipped ignored", "if m.skipped { return [] }", "if m.skipped && false { return [] }"),
    ("enabled inverted", "guard m.enabled else { return .pass(.nothingOwed) }", "guard !m.enabled else { return .pass(.nothingOwed) }"),
    ("a turn offers every owed step", "let list = m.decided ? owedHere.filter { only(layout).contains($0) } : owedHere", "let list = owedHere"),
    # Steps and memory.
    ("touch kept under VoiceOver", "return voiceOver ? all.filter { $0 != .touch } : all", "return all"),
    ("laptop owed in landscape", "let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .settings] : [.touch, .bar, .settings, .laptop]", "let all: [TourTopic] = layout == .landscape ? [.touch, .bar, .settings, .laptop] : [.touch, .bar, .settings, .laptop]"),
    ("Next not saving", "memory.seen.insert(t)", "_ = t"),
    ("Skip not saving", "memory.skipped = true", "memory.skipped = m.skipped"),
    ("Skip in Take the Tour turns the tour off", "run.replay ? m : skipped(m)", "skipped(m)"),
    # Sessions: the automatic reconnect's goes on with the last decision.
    ("a reconnect decides afresh", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard reconnected && false, last.decided, !last.running else { return TourSession() }"),
    ("a session the person starts goes on with the last decision", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard last.decided, !last.running else { return TourSession() }"),
    ("a run cut short is not resumed at a reconnect", "guard reconnected, last.decided, !last.running else { return TourSession() }", "guard reconnected, last.decided else { return TourSession() }"),
    ("the decision carried without its layouts", "return TourSession(decided: true, offered: last.offered, running: false)", "return TourSession(decided: true, offered: [], running: false)"),
    ("Next not advancing", "moved.at = run.steps[i + 1]", "moved.at = run.steps[i]"),
    ("carry goes to the first step, not the next one owed", "guard let next = list.first(where: { $0 > run.at && !run.passed.contains($0) }) else { return nil }", "guard let next = list.first(where: { !run.passed.contains($0) }) else { return nil }"),
    ("carry keeps a step the new layout lacks", "if list.contains(run.at) { return carried }", "if true { return carried }"),
    # Where the card goes.
    ("the crease ignored", "guard let band = DuoPosture.crease(screen, fold) else { return nil }", "guard let band = DuoPosture.crease(screen, fold), false else { return nil }"),
    ("the inferred crease unrounded", "if case .inferred = fold { return band.top.rounded() }", "if case .inferred = fold { return band.top }"),
    ("the fold's crease rounded", "return band.top.rounded() }\n        return band.top\n", "return band.top.rounded() }\n        return band.top.rounded()\n"),
    ("a card placed without the fold", "let fold = crease(screen, info)", "let fold = crease(screen)"),
    ("the book pose's card across the fold", "DuoPosture.offTheFold(x: clamped(mid), width: w, screenWidth: screen.width, margin: margin, fold: info)", "clamped(mid)"),
    ("a card wider than the book pose's page", "let page = DuoPosture.pageWidth(screenWidth: screen.width, margin: margin, fold: fold, for: targets) ?? .infinity", "let page = CGFloat.infinity"),
    ("a card as wide as the wider page whatever its targets", "fold: fold, for: targets) ?? .infinity", "fold: fold, for: nil) ?? .infinity"),
    ("the Duo told to hold it upright", 'let turn = keysOnItsSide ? "Turn your \\(device) on its side" : "Hold your \\(device) upright"', 'let turn = "Hold your \\(device) upright"'),
    ("the Duo's laptop card says upright", 'let subtitle = keysOnItsSide ? "On its side, Sill adds keys and a trackpad." : "Upright, Sill adds keys and a trackpad."',
     'let subtitle = "Upright, Sill adds keys and a trackpad."'),
    ("an iPhone told to turn it on its side", 'let turn = keysOnItsSide ? "Turn your \\(device) on its side" : "Hold your \\(device) upright"', 'let turn = "Turn your \\(device) on its side"'),
    ("a tail across the crease", "let noFold = fold.map { !(rect.maxY <= $0 && $0 <= t.minY) } ?? true", "let noFold = true"),
    ("a portrait tail at any distance", "let reaches = t.minY >= rect.maxY && t.minY - rect.maxY <= tailReach", "let reaches = t.minY >= rect.maxY"),
    ("a tail on a card over its targets", "let rect = CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y))\n            return TourPlacement(card: rect, tail: nil,", "let rect = CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y))\n            return TourPlacement(card: rect, tail: TourTail(edge: .up, x: t.midX),"),
    ("a card that never stops at the bottom margin (it runs off the screen)", "let rect = CGRect(x: cardX, y: below, width: w, height: min(h, room))", "let rect = CGRect(x: cardX, y: below, width: w, height: h)"),
    ("a landscape card over its targets while the room below holds it", "if h <= room || room >= minimumRoom {", "if h <= room {"),
    ("a scrolling card loses its tail", "let rect = CGRect(x: cardX, y: below, width: w, height: min(h, room))\n                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))", "let rect = CGRect(x: cardX, y: below, width: w, height: min(h, room))\n                return TourPlacement(card: rect, tail: h <= room ? TourTail(edge: .up, x: tip(rect, t.midX)) : nil)"),
    ("a phone's card under its targets without its tail", "let rect = CGRect(x: cardX, y: under, width: w, height: min(h, room))\n                return TourPlacement(card: rect, tail: TourTail(edge: .up, x: tip(rect, t.midX)))", "let rect = CGRect(x: cardX, y: under, width: w, height: min(h, room))\n                return TourPlacement(card: rect, tail: nil)"),
    ("an upright card grown past its targets' top", "let above = fold == nil ? min(bottom, max(top, t.minY - gap)) : pictureBottom", "let above = fold == nil ? bottom : pictureBottom"),
    ("an upright card over its targets while the room above holds it", "if fold != nil || h <= above - top || above - top >= minimumRoom {", "if fold != nil || h <= above - top {"),
    ("an upright card over its targets while it fits above them", "if fold != nil || h <= above - top || above - top >= minimumRoom {", "if fold != nil || above - top >= minimumRoom {"),
    ("a card over its targets that says it is not (sideways)", "let rect = CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y))\n            return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))", "let rect = CGRect(x: cardX, y: y, width: w, height: min(h, bottom - y))\n            return TourPlacement(card: rect, tail: nil, coversTargets: false)"),
    ("a card over its targets that says it is not (upright)", "let rect = CGRect(x: cardX, y: top, width: w, height: min(h, bottom - top))\n        return TourPlacement(card: rect, tail: nil, coversTargets: rect.intersects(lit))", "let rect = CGRect(x: cardX, y: top, width: w, height: min(h, bottom - top))\n        return TourPlacement(card: rect, tail: nil, coversTargets: false)"),
    ("the card not clamped", "return hi < lo ? (screen.width - w) / 2 : min(max(mid - w / 2, lo), hi)", "return mid - w / 2"),
    ("the card 360 pt wide on a short screen held sideways", "let preferred: CGFloat = accessibilityText ? 560 : (short ? 480 : 360)", "let preferred: CGFloat = accessibilityText ? 560 : (short ? 360 : 360)"),
    ("the width not capped by the screen", "return max(0, min(preferred, page, screen.width - 2 * margin))", "return max(0, min(preferred, page))"),
    ("a landscape card above its targets while it fits below", "let below = t.maxY + gap", "let below = t.minY - gap - h"),
    ("the home indicator ignored", "let bottom = max(top, screen.height - margin - max(0, bottomInset))", "let bottom = max(top, screen.height - margin)"),
    ("an upright card past the crease when it grows", "let above = fold == nil ? min(bottom, max(top, t.minY - gap)) : pictureBottom", "let above = fold == nil ? min(bottom, max(top, t.minY - gap)) : bottom"),
    # A phone held upright.
    ("a phone's bar without its Keyboard", "case .bar: return layout == .portrait ? [.strip, .textSize] : [.strip, .textSize, .keyboard]", "case .bar: return layout != .landscape ? [.strip, .textSize] : [.strip, .textSize, .keyboard]"),
    ("the laptop card not owed at a turn on a phone", "layout.upright ? [.laptop] : []", "layout == .portrait ? [.laptop] : []"),
    ("a phone's picture card not growing past the picture", "let reach = layout.upright && fold == nil ? bottom : lowest", "let reach = layout == .portrait && fold == nil ? bottom : lowest"),
    ("a phone's card never under its targets", "if layout == .phone && h > above - top {", "if false && h > above - top {"),
    ("a phone's card under its targets while it fits above them", "if layout == .phone && h > above - top {", "if layout == .phone {"),
    ("the halves' card under its targets too", "if layout == .phone && h > above - top {", "if layout.upright && h > above - top {"),
    ("a phone's card under a room too small for a card", "if h <= room || (room > above - top && room >= minimumRoom) {", "if h <= room || room > above - top {"),
    ("a phone's grown card from the top margin, half over a row", "let y = layout == .phone ? max(top, above - h) : top", "let y = top"),
    ("the halves' grown card standing on its targets", "let y = layout == .phone ? max(top, above - h) : top", "let y = max(top, above - h)"),
    ("a phone's card under a smaller room", "if h <= room || (room > above - top && room >= minimumRoom) {", "if h <= room || room >= minimumRoom {"),
    # The words.
    ("the Pencil row on iPhone", "if iPad { rows.append(row(\"applepencil\"", "if true { rows.append(row(\"applepencil\""),
    ("the upright row in portrait", "if layout == .landscape {\n                let turn = keysOnItsSide", "if true {\n                let turn = keysOnItsSide"),
    ("a gesture word in a VoiceOver row", "if voiceOver {\n                rows = [row(\"hand.point.up.left\"", "if false {\n                rows = [row(\"hand.point.up.left\""),
    ("the trackpad's rows under VoiceOver", "if !voiceOver {\n                rows.append(row(\"cursorarrow.click.2\"", "if true {\n                rows.append(row(\"cursorarrow.click.2\""),
    ("laptop's subtitle on a card that is not the run's first", "subtitle: firstOfRun ? subtitle : nil", "subtitle: subtitle"),
    ("one word of the copy changed", "plain(\" to scroll.\")", "plain(\" to scroll it.\")"),
    ("no Keyboard row on a phone's bar card", "if layout != .portrait { rows.append(keyboardRow) }", "if layout == .landscape { rows.append(keyboardRow) }"),
    ("the keyboard key's row on a phone", "if layout != .phone {\n                rows.append(row(\"keyboard\", [strong(\"The keyboard key\")", "if true {\n                rows.append(row(\"keyboard\", [strong(\"The keyboard key\")"),
    ("a phone's laptop hint as the halves'", 'case .phone: hint = thumbnails ? "Under the windows: the row of keys, then the trackpad." : "Under the buttons: the row of keys, then the trackpad."',
     'case .phone: hint = "Below the bar: the row of keys, then the trackpad."'),
    ("Aa not said to be a window's", "plain(\": while a window shows, touch it and slide to make its text larger or smaller.\")", "plain(\": touch it and slide to make text larger or smaller.\")"),
    ("the caps not spoken by name", "spoken: \"Command, Option, Control and Shift stay on for the next key or trackpad click: tap Command, then C, to copy.\")", "spoken: nil)"),
    # Larger Picture (docs/larger-picture-plan.md): no thumbnails on a phone.
    ("Larger Picture's bar card lights the strip", "case .bar where layout == .phone && !thumbnails: return [.apps, .textSize, .keyboard]",
     "case .bar where layout == .phone && !thumbnails: return [.strip, .textSize, .keyboard]"),
    ("Larger Picture's bar card without Apps", "case .bar where layout == .phone && !thumbnails: return [.apps, .textSize, .keyboard]",
     "case .bar where layout == .phone && !thumbnails: return [.textSize, .keyboard]"),
    ("no thumbnails in the halves too", "case .bar where layout == .phone && !thumbnails:", "case .bar where layout != .landscape && !thumbnails:"),
    ("Larger Picture's bar card about the thumbnails", "if layout == .phone && !thumbnails {\n                rows[0] = voiceOver", "if false {\n                rows[0] = voiceOver"),
    ("Apps' row says tap under VoiceOver", 'plain(" lists the apps on \\(mac). Choose an open one again for its next window.")',
     'plain(" lists the apps on \\(mac): tap an open one again for its next window.")'),
    ("Larger Picture's bar hint as the thumbnails'", 'case .phone where !thumbnails: hint = "Under the picture, in the row of buttons: Apps, Aa and Keyboard."',
     'case .phone where false: hint = "Under the picture, in the row of buttons: Apps, Aa and Keyboard."'),
    ("Larger Picture's laptop hint under the windows", 'hint = thumbnails ? "Under the windows: the row of keys, then the trackpad." : "Under the buttons: the row of keys, then the trackpad."',
     'hint = "Under the windows: the row of keys, then the trackpad."'),
    ("the picture's room ignored", "let half = room ?? stream", "let half = stream"),
]
# Larger Picture only while a window streams (Noah, 2026-10-15): the rule is PhonePortraitLayout's
# (compiled into this check), and the tour's targets, words and places follow it. Each of these
# changes PhonePortraitLayout.swift instead.
LAYOUT = os.path.join(WT, "iOSClient/PhonePortraitLayout.swift")
LAYOUT_MUTANTS = [
    ("the Desktop with Larger Picture's tour", "switchOn && streaming == .window", "switchOn && streaming != .nothing"),
    ("nothing streaming with Larger Picture's tour", "switchOn && streaming == .window", "switchOn && streaming != .desktop"),
    ("what streams ignored (the Desktop's tour about Apps, as before 2026-10-15)", "switchOn && streaming == .window", "switchOn"),
    ("the switch ignored while a window streams", "switchOn && streaming == .window", "streaming == .window"),
]
caught = 0
for (name, old, new), path in [(m, F) for m in MUTANTS] + [(m, LAYOUT) for m in LAYOUT_MUTANTS]:
    src = open(path).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, os.path.basename(path)); open(mf, "w").write(src.replace(old, new, 1))
        sources = [mf, LAYOUT] if path == F else [F, mf]
        exe = os.path.join(t, "c")
        r = subprocess.run(["swiftc", "-O", *sources, os.path.join(WT, "iOSClient/DuoPosture.swift"),
                            os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile ({r.stderr.strip().splitlines()[:1]})"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
total = len(MUTANTS) + len(LAYOUT_MUTANTS)
print(f"mutants caught: {caught} of {total}")
sys.exit(0 if caught == total else 1)
