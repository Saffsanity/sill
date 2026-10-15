"""Mutants of the clipboard's wire and rules (docs/clipboard-plan.md): each copies Sources/StreamProtocol,
changes ClipboardPolicy.swift, Clipboard.swift, StreamMessage.swift or Switcher.swift in one place, compiles
it with the check (main.swift) and expects the check to fail. usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
P = "ClipboardPolicy.swift"
MUTANTS = [
    # The wire.
    ("kind 32 as 33", "StreamMessage.swift", "case clipboard = 32", "case clipboard = 33"),
    ("the list's clipboard never stored", "Switcher.swift", "self.clipboard = clipboard\n", "self.clipboard = nil\n"),
    ("clipboard 1 by default", "Switcher.swift", "gestures: Int? = nil, clipboard: Int? = nil) {", "gestures: Int? = nil, clipboard: Int? = 1) {"),
    ("stop false by default (a subscription is no longer {})", "Clipboard.swift", "image: Data? = nil, stop: Bool? = nil) {", "image: Data? = nil, stop: Bool? = false) {"),
    ("a 512 KB cap", "Clipboard.swift", "public static let maxTextBytes = 256 * 1024", "public static let maxTextBytes = 512 * 1024"),
    ("generation 2", P, "public static let generation = 1", "public static let generation = 2"),
    ("the JSON cap the device's 4 MiB", P, "public static let maxPayload = StreamMessage.maxClientPayload", "public static let maxPayload = StreamMessage.maxOtherHostPayload"),
    ("empty text sent", P, "guard !text.isEmpty, text.utf8.count <= Clipboard.maxTextBytes else { return nil }\n        let data",
     "guard text.utf8.count <= Clipboard.maxTextBytes else { return nil }\n        let data"),
    ("the cap in characters, not bytes", P, "guard !text.isEmpty, text.utf8.count <= Clipboard.maxTextBytes else { return nil }\n        let data",
     "guard !text.isEmpty, text.count <= Clipboard.maxTextBytes else { return nil }\n        let data"),
    ("the JSON's size never checked", P, "guard !data.isEmpty, data.count <= maxPayload else { return nil }", "guard !data.isEmpty else { return nil }"),
    ("the subscription says stop", P, "public static var subscription: Data { Wire.encode(Clipboard()) }", "public static var subscription: Data { Wire.encode(Clipboard(stop: true)) }"),
    ("stopping says nothing", P, "public static var stopping: Data { Wire.encode(Clipboard(stop: true)) }", "public static var stopping: Data { Wire.encode(Clipboard()) }"),
    # The host.
    ("its own change count not its own", P, "if let own = ownChangeCount, own == changeCount { return .skip(.own) }\n", ""),
    ("no marker skipped", P, "if types.contains(where: { markerTypes.contains($0) }) { return .skip(.marked) }\n", ""),
    ("the concealed marker misspelt", P, 'public static let concealedType = "org.nspasteboard.ConcealedType"', 'public static let concealedType = "org.nspasteboard.Concealed"'),
    ("the transient marker misspelt", P, 'public static let transientType = "org.nspasteboard.TransientType"', 'public static let transientType = "org.nspasteboard.transientType"'),
    ("1Password's own marker left out", P, '"de.petermaurer.TransientPasteboardType", "com.agilebits.onepassword"]', '"de.petermaurer.TransientPasteboardType"]'),
    ("an empty pasteboard decided at once", P, "types.isEmpty && now - firstLook < settleWindow", "false && now - firstLook < settleWindow"),
    ("the settle window's end inside it", P, "types.isEmpty && now - firstLook < settleWindow", "types.isEmpty && now - firstLook <= settleWindow"),
    ("Universal Clipboard's copies sent", P, "        if types.contains(remoteClipboardType) { return .skip(.remote) }\n", ""),
    ("the text read before the markers", P,
     "        if types.contains(where: { markerTypes.contains($0) }) { return .skip(.marked) }\n        if types.contains(remoteClipboardType) { return .skip(.remote) }\n        if types.contains(ownType), ownMarker() == launchID { return .skip(.own) }\n        guard let text = text() else { return .skip(.noText) }\n",
     "        let read = text()\n        if types.contains(where: { markerTypes.contains($0) }) { return .skip(.marked) }\n        if types.contains(remoteClipboardType) { return .skip(.remote) }\n        if types.contains(ownType), ownMarker() == launchID { return .skip(.own) }\n        guard let text = read else { return .skip(.noText) }\n"),
    ("any launch's marker is its own", P, "if types.contains(ownType), ownMarker() == launchID { return .skip(.own) }", "if types.contains(ownType), ownMarker() != nil { return .skip(.own) }"),
    ("its marker read without its type", P, "if types.contains(ownType), ownMarker() == launchID { return .skip(.own) }", "if ownMarker() == launchID { return .skip(.own) }"),
    # macOS's paste privacy (the review's finding: the host read whatever macOS said).
    ("macOS's default (not asked yet) read as allowed", P, "case 0?: return .notAsked", "case 0?: return .allowed"),
    ("macOS's deny read as allowed", P, "case 3?: return .denied", "case 3?: return .allowed"),
    ("an answer this build does not know read as allowed", P, "        default: return .asks\n        }\n    }\n\n    /// Whether the host reads",
     "        default: return .allowed\n        }\n    }\n\n    /// Whether the host reads"),
    ("before macOS 15.4 read as asking", P, "case nil, 2?: return .allowed", "case 2?: return .allowed"),
    ("the host reads while macOS asks", P, "public static func hostLooks(_ access: MacAccess) -> Bool { access == .allowed }",
     "public static func hostLooks(_ access: MacAccess) -> Bool { access != .denied }"),
    ("what was copied while macOS asked sent once it allows", P, "return was.map(hostLooks) == false ? .takeAsSeen : .look", "return .look"),
    ("the first look takes the count again", P, "return was.map(hostLooks) == false ? .takeAsSeen : .look",
     "return was.map(hostLooks) != true ? .takeAsSeen : .look"),
    ("a line at every change of macOS's answer", P, "return was.map(Copy.macAccessLine) == line ? nil : line", "return was == now ? nil : line"),
    ("a line while macOS allows from the start", P, "        if was == nil && now == .allowed { return nil }\n", ""),
    ("Settings warns while every read is allowed", P, "            case .allowed: return nil\n            case .notAsked, .asks: return \"macOS asks before Sill reads the clipboard, so what you copy here stays on this Mac.\"",
     "            case .allowed: return \"\"\n            case .notAsked, .asks: return \"macOS asks before Sill reads the clipboard, so what you copy here stays on this Mac.\""),
    ("empty Mac text called too long", P, "        guard !text.isEmpty else { return .skip(.empty) }\n", ""),
    ("a device's stop ignored", P, "        if clip.stop == true { return .stop }\n", ""),
    ("stop false read as stop", P, "if clip.stop == true { return .stop }", "if clip.stop != nil { return .stop }"),
    ("a device's empty text sets", P, "guard let text = clip.text, !text.isEmpty else { return .subscribe }", "guard let text = clip.text else { return .subscribe }"),
    ("a device's text over the cap taken", P, "        guard text.utf8.count <= Clipboard.maxTextBytes else { return .refuse(.tooLong) }\n", ""),
    ("undecodable read as a subscription", P, "guard let clip = Wire.decode(Clipboard.self, from: payload) else { return .refuse(.undecodable) }",
     "guard let clip = Wire.decode(Clipboard.self, from: payload) else { return .subscribe }"),
    ("a device's text back to it too", P, "subscribers.filter { $0 != sender }", "subscribers"),
    ("every kind 32 counted against the rate (the review's finding: a stop lost to it)", P,
     "guard countsAgainstRate(ask) else { return (ask, arrivals) }", "guard true else { return (ask, arrivals) }"),
    ("a stop counted against the rate", P, "case .stop, .refuse: return false", "case .stop: return true\n        case .refuse: return false"),
    ("a refusal counted against the rate", P, "case .stop, .refuse: return false", "case .stop: return false\n        case .refuse: return true"),
    ("past the rate taken anyway", P, "return (admitted.taken ? ask : .refuse(.rate), admitted.kept)", "return (ask, admitted.kept)"),
    ("a refusal by the rate forgets the second", P, "return (admitted.taken ? ask : .refuse(.rate), admitted.kept)",
     "return admitted.taken ? (ask, admitted.kept) : (.refuse(.rate), [])"),
    ("five a second", P, "guard recent.count < perSecond else { return (false, recent) }", "guard recent.count <= perSecond else { return (false, recent) }"),
    ("a two-second window", P, "let recent = arrivals.filter { now - $0 < 1 }", "let recent = arrivals.filter { now - $0 < 2 }"),
    # The device.
    ("generation 0 taken", P, "public static func hostTakes(_ hostClipboard: Int?) -> Bool { (hostClipboard ?? 0) >= generation }",
     "public static func hostTakes(_ hostClipboard: Int?) -> Bool { hostClipboard != nil }"),
    ("the subscription kept when the Mac forgot it", P, "guard hostTakes(hostClipboard) else { return (.none, false) }", "guard hostTakes(hostClipboard) else { return (.none, subscribed) }"),
    ("never a stop", P, "        if !switchOn && subscribed { return (.stop, false) }\n", ""),
    ("a second subscription", P, "if switchOn && !subscribed { return (.subscribe, true) }", "if switchOn { return (.subscribe, true) }"),
    ("written with the switch off", P, "guard switchOn, hostTakes(hostClipboard), let clip = Wire.decode", "guard hostTakes(hostClipboard), let clip = Wire.decode"),
    ("the echo written again", P, "        if let lastSent, lastSent.text == text, lastSent.changeCount == changeCount { return nil }\n", ""),
    ("the echo judged by its text alone", P, "if let lastSent, lastSent.text == text, lastSent.changeCount == changeCount { return nil }",
     "if let lastSent, lastSent.text == text { return nil }"),
    ("the chip without text", P, "connected && hostTakes(hostClipboard) && switchOn && hasStrings && changeCount != handled",
     "connected && hostTakes(hostClipboard) && switchOn && changeCount != handled"),
    ("the chip for what was handled", P, "connected && hostTakes(hostClipboard) && switchOn && hasStrings && changeCount != handled",
     "connected && hostTakes(hostClipboard) && switchOn && hasStrings"),
    ("the chip with the switch off", P, "connected && hostTakes(hostClipboard) && switchOn && hasStrings && changeCount != handled",
     "connected && hostTakes(hostClipboard) && hasStrings && changeCount != handled"),
    ("the look's window open at its end", P, "return now >= activatedAt && now - activatedAt <= activationWindow", "return now >= activatedAt && now - activatedAt < activationWindow"),
    ("the look before the activation", P, "return now >= activatedAt && now - activatedAt <= activationWindow", "return now - activatedAt <= activationWindow"),
    ("a 30 s window", P, "public static let activationWindow = 15.0", "public static let activationWindow = 30.0"),
    ("Paste sends the last string", P, "let text = strings.first(where: { !$0.isEmpty }) else { return .nothing }", "let text = strings.last(where: { !$0.isEmpty }) else { return .nothing }"),
    ("too long said as nothing", P, "guard let data = payload(text: text) else { return .tooLong }", "guard let data = payload(text: text) else { return .nothing }"),
    ("the chip's time runs while it is hidden", P, "        onScreen && active && !voiceOver\n", "        active && !voiceOver\n"),
    ("the chip's time runs while Sill is not active", P, "        onScreen && active && !voiceOver\n", "        onScreen && !voiceOver\n"),
    ("the chip's time runs under VoiceOver", P, "        onScreen && active && !voiceOver\n", "        onScreen && active\n"),
    ("a receipt's payload the length of a ping's", P, "public static let receiptLength = 16", "public static let receiptLength = 8"),
    ("a receipt waited for without its floor", P, "{ max(4, 4 * Double(worstRttMs ?? 0) / 1000) }", "{ 4 * Double(worstRttMs ?? 0) / 1000 }"),
    ("a receipt waited for twice the round trip", P, "{ max(4, 4 * Double(worstRttMs ?? 0) / 1000) }", "{ max(4, 2 * Double(worstRttMs ?? 0) / 1000) }"),
    ("the chip under the link's line", P, "landscape && !linkLineShown ? .topTrailing : .bottomTrailing", "landscape ? .topTrailing : .bottomTrailing"),
    ("the cap in thousands", P, 'public static var cap: String { "\\(Clipboard.maxTextBytes / 1024) KB" }', 'public static var cap: String { "\\(Clipboard.maxTextBytes / 1000) KB" }'),
    ("the Mac's footnote promises every password manager's copy (the review's copy finding)", P,
     "Copies a password manager marks as concealed stay on this Mac.\"", "A password manager’s copies stay on this Mac.\""),
    ("the subtitle without the key", P, 'public static let chipSubtitle = "Then press ⌘V there."', 'public static let chipSubtitle = "Then paste there."'),
]
caught = 0
for name, file, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), src)
        path = os.path.join(src, file); text = open(path).read()
        if text.count(old) != 1:
            print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
        open(path, "w").write(text.replace(old, new, 1))
        files = [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.endswith(".swift")]
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *files, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
