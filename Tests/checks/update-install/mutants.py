"""Update Now's mutants (docs/one-click-update-plan.md §11, G1): each changes one of the app's update files
in one place, in a copy of Sources/SillMenuBar; build.sh compiles the check from the copy and the check
reads the copy's sources, and it must fail. usage: mutants.py WORKTREE [NAME…] (only the mutants named)"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(WT, "Sources/SillMenuBar")
POL, MAN, ARC, INS, APP = "UpdateInstallPolicy.swift", "UpdateManifest.swift", "UpdateArchive.swift", "UpdateInstaller.swift", "AppUpdater.swift"
AUTO = "UpdateAutoPolicy.swift"
MUTANTS = [
    # The version rule and the release.
    ("the same version installed", POL, "guard isNewer(version, build: Int(build), than: running, runningBuild: runningBuild,", "guard version >= running || isNewer(version, build: Int(build), than: running, runningBuild: runningBuild,"),
    ("the same release fetched", POL, "guard version > running else { return .failure(.releaseNotNewer) }", "guard version >= running else { return .failure(.releaseNotNewer) }"),
    ("loose versions", MAN, "parts.allSatisfy({ (1...9).contains($0.utf8.count) && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } })", "parts.allSatisfy({ (1...9).contains($0.utf8.count) })"),
    ("drafts and prereleases", POL, "if object[\"draft\"] as? Bool == true || object[\"prerelease\"] as? Bool == true {", "if false {"),
    ("GitHub's URL for an asset", POL, "a[\"browser_download_url\"] as? String == url.absoluteString else {", "true else {"),
    ("an upload not finished", POL, "guard a[\"state\"] as? String == \"uploaded\" else {", "guard true else {"),
    ("two zips", POL, "guard matches.count == 1 else {", "guard true else {"),
    ("no manifest read as unreadable", POL, "guard let manifest = a.manifest else { return .failure(.notSigned) }\n            return .success(Release(tag: tag,", "guard let manifest = a.manifest else { return .failure(.releaseUnreadable(\"no manifest\")) }\n            return .success(Release(tag: tag,"),
    ("the manifest's size unchecked", POL, "guard m.size == r.zip.size else { return .manifestMismatch(\"size\") }", ""),
    ("GitHub's digest unchecked", POL, "if let digest = r.zip.digest, digest != m.sha256 { return .manifestMismatch(\"sha256\") }", ""),
    # Where downloads may go.
    ("credentials in an origin", POL, "url.user == nil, url.password == nil else { return nil }", "true else { return nil }"),
    ("any path on the asset host", POL, "return url.path.hasPrefix(endpoints.redirectPathPrefix)", "return true"),
    ("http to the asset host", POL, "redirectOrigins: [\"https://release-assets.githubusercontent.com\",", "redirectOrigins: [\"http://release-assets.githubusercontent.com\","),
    ("github.com as a redirect target", POL, "\"https://objects.githubusercontent.com\"],", "\"https://objects.githubusercontent.com\", \"https://github.com\"],"),
    # The trust.
    ("no team in the requirement", POL, " and certificate leaf[subject.OU] = \\\"9B2KKVM937\\\"\"", "\""),
    ("notarization not asked", POL, "signer: UpdateInstallPolicy.pinnedRequirement, notarized: true,", "signer: UpdateInstallPolicy.pinnedRequirement, notarized: false,"),
    ("no stapled ticket asked", POL, "teamID: \"9B2KKVM937\", stapledTicket: true,", "teamID: \"9B2KKVM937\", stapledTicket: false,"),
    ("the running requirement not asked", POL, "        runningRequirement: true,\n", "        runningRequirement: false,\n"),
    ("notarization ignored", POL, "if trust.notarized, !f.notarized { return .failure(.notNotarized) }", ""),
    ("any team", POL, "guard f.identifier == trust.identifier, trust.teamID == nil || f.teamID == trust.teamID else", "guard f.identifier == trust.identifier else"),
    ("the keychain group unchecked", POL, "guard case .strings(let values)? = f.entitlements[key], values.contains(value) else", "guard true else"),
    ("a debuggable build", POL, "if f.entitlements[\"com.apple.security.get-task-allow\"] == .bool(true) { return .failure(.debuggable) }", ""),
    ("any build number", POL, "guard build == manifest.build else { return .failure(.notManifest(\"build\")) }", ""),
    ("any code", POL, "guard f.cdhashes == manifest.cdhashes else { return .failure(.notManifest(\"code\")) }", ""),
    ("any macOS", POL, "guard needed <= have else { return .failure(.needsNewerMacOS(minimum)) }", ""),
    # Refusals.
    ("translocation ignored", POL, "if s.translocated { return .translocated }", ""),
    ("another account ignored", POL, "if let other = s.otherAccounts.first { return .otherAccount(other) }", ""),
    ("another owner's copy", POL, "        if !s.ownedByUser { return .otherOwner(s.ownerName) }\n", ""),
    ("no room needed to the byte", POL, "if let free = s.freeBytes, free < s.neededBytes {", "if let free = s.freeBytes, free <= s.neededBytes {"),
    # The state machine.
    ("a device joining never asked about", POL, "if Set(devices.map(\\.key)).isSubset(of: Set(s.consented)) { n.phase = .installing; return (n, [.install]) }", "n.phase = .installing; return (n, [.install])"),
    ("consent by name", POL, "        case (.confirming(let devices), .confirm):\n            n.consented = devices.map(\\.key)", "        case (.confirming(let devices), .confirm):\n            n.consented = devices.map(\\.name)"),
    ("the old copy deleted when not put back", POL, "return (n, f.cleanUp ? [.cleanUp] : [])", "return (n, [.cleanUp])"),
    ("cancel while installing", POL, "case (.ready, .cancel), (.waiting, .cancel), (.lookingAgain, .cancel), (.fetching, .cancel),", "case (.ready, .cancel), (.waiting, .cancel), (.lookingAgain, .cancel), (.installing, .cancel), (.fetching, .cancel),"),
    ("a copy not put back cleaned up", POL, "case .checkAfterSwap(_, let putBack), .didNotStart(_, let putBack): return putBack", "case .checkAfterSwap, .didNotStart: return true"),
    ("Update Now enabled when refused", POL, "p.updateNowEnabled = refusal == nil\n            p.note = refusal.map(words) ??", "p.updateNowEnabled = true\n            p.note = refusal.map(words) ??"),
    ("Install Now enabled when refused", POL, "p.updateNowEnabled = refusal == nil\n            p.updateNowTitle = \"Install Now\"", "p.updateNowEnabled = true\n            p.updateNowTitle = \"Install Now\""),
    ("the menu opens Settings when refused", POL, "if available, refusal == nil {", "if available {"),
    # The manifest.
    ("any signature", MAN, "for candidate in candidates where candidate.key.isValidSignature(signature, for: signed) { return nil }", "for _ in candidates { return nil }"),
    ("no key as an unknown key", MAN, "guard !keys.isEmpty else { return .noKey }", ""),
    ("carriage returns", MAN, "bytes.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) }) else { return .failure(.notText) }", "bytes.allSatisfy({ $0 == 0x0A || $0 == 0x0D || (0x20...0x7E).contains($0) }) else { return .failure(.notText) }"),
    ("a stop's carriage returns", MAN, "last == 0x0A, bytes.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) }) else {", "last == 0x0A, bytes.allSatisfy({ $0 == 0x0A || $0 == 0x0D || (0x20...0x7E).contains($0) }) else {"),
    ("a version that is not the tag's", MAN, "guard let versionText = field(\"version\"), versionText == String(t.dropFirst()),", "guard let versionText = field(\"version\"),"),
    ("the key line left unsigned", MAN, "let signedEnd = lines[0..<i].reduce(0)", "let signedEnd = lines[0..<(i - 1)].reduce(0)"),
    ("small-order keys", MAN, "if smallOrder.contains(where: { Array($0[0..<31]) == Array(bytes[0..<31]) && $0[31] == bytes[31] & 0x7F }) { return nil }", ""),
    ("non-canonical base64", MAN, "signature.count == 64,\n              signature.base64EncodedString() == signatureText else { return .failure(.format(\"signature\")) }", "signature.count == 64,\n              true else { return .failure(.format(\"signature\")) }"),
    ("a shorter key ID", MAN, "SHA256.hash(data: raw).prefix(4)", "SHA256.hash(data: raw).prefix(3)"),
    # The archive.
    ("non-ASCII names", ARC, "nameBytes.allSatisfy({ (0x20...0x7E).contains($0) && $0 != 0x5C }) else {", "true else {"),
    ("dot-dot", ARC, "parts.allSatisfy({ !$0.isEmpty && $0 != \".\" && $0 != \"..\" })", "parts.allSatisfy({ !$0.isEmpty })"),
    ("case-sensitive duplicates", ARC, "let key = r.components.joined(separator: \"/\").lowercased()", "let key = r.components.joined(separator: \"/\")"),
    ("writing through a link", ARC, "                case .link?: return .failure(.throughLink(e.path))\n                default: break\n                }\n            }\n            guard case .link", "                default: break\n                }\n            }\n            guard case .link"),
    ("shared bytes", ARC, "guard end <= next, i == 0 || spans[i - 1].headerOffset < r.headerOffset else { return .failure(.overlap(r.name)) }", ""),
    ("the local name unchecked", ARC, "Array(b[(headerOffset + 30)..<(headerOffset + 30 + nameLength)]) == nameBytes,", ""),
    ("encryption", ARC, "if flags & 0x0041 != 0 { return .failure(.encrypted(name)) }", ""),
    ("setuid", ARC, "guard type == 0o040000 || type == 0o100000 || type == 0o120000, mode & 0o7000 == 0 else {", "guard type == 0o040000 || type == 0o100000 || type == 0o120000 else {"),
    ("no total", ARC, "guard totalBytes <= limits.totalBytes else { return .failure(.tooLarge) }", ""),
    ("no ratio", ARC, "if method == 8 { guard compressed > 0, size <= compressed * limits.ratio else { return .failure(.badSizes(name)) } }", ""),
    ("inflate past the size", ARC, "guard produced <= size else { return .failure(.inflate(name)) }", ""),
    ("a walk through a link", ARC, "                if case .link? = kinds[walked.joined(separator: \"/\").lowercased()] { return .failure(.throughLink(e.path)) }\n", ""),
    ("links at the signature's paths", ARC, "if lower.count >= 3, lower[1] == \"contents\", lower[2] == \"_codesignature\" || (lower.count == 3 && lower[2] == \"coderesources\") {", "if false {"),
    ("16 digits of the SHA-256 in the prompt", MAN, "        var rest = Substring(hex)\n", "        var rest = Substring(hex.prefix(16))\n"),
    ("links outside", ARC, "guard let resolved = resolve(target, from: Array(e.components.dropLast())), resolved.count > 1,", "guard let resolved = Optional(Array(e.components)), resolved.count > 1,"),
    # Review 3: the prompt, the signed date, the stop.
    ("the prompt's digest shortened", MAN, '"sign Sill \\(tag) for Update Now: \\(asset), \\(size) bytes, SHA-256 \\(grouped(sha256))"', '"sign Sill \\(tag) for Update Now: \\(asset), \\(size) bytes, SHA-256 \\(grouped(String(sha256.prefix(16))))"'),
    ("any date read", MAN, "              dateText(date) == text else { return nil }", "              true else { return nil }"),
    ("the date left unsigned", MAN, 'return text + "signed \\(dateText(signedAt))\\nkey \\(keyID)\\n"', 'return text + "key \\(keyID)\\n"'),
    ("a stop's signature unchecked", MAN, "        if let problem = check(Data(bytes[0..<signedEnd]), signature, keyID: keyID, keys: keys) { return .failure(problem) }\n", ""),
    # The automatic update (UpdateAutoPolicy and its mode).
    ("no cooling-off", AUTO, "        if ghNow < ghEnd || now < localEnd { return .waitUntil(max(localEnd, byGitHub)) }\n", ""),
    # The second security pass.
    ("A1: the cooling-off from the signed line", AUTO, "        let localEnd = max(signedAt, firstSeen).addingTimeInterval(wait)\n", "        let localEnd = signedAt.addingTimeInterval(wait)\n"),
    ("A1: a first sight moved by a later read", AUTO, "        if n.seen[i].firstGitHub == nil { n.seen[i].firstGitHub = github }\n", "        n.seen[i] = Memory.Sighting(tag: tag, sha256: sha256, first: now, signed: signedAt, firstGitHub: github, published: published)\n"),
    ("A1: sightings by tag alone", AUTO, "        m.seen.first { $0.tag == tag && $0.sha256 == sha256 }\n", "        m.seen.first { $0.tag == tag }\n"),
    ("A1: a new zip kept as the old sighting", AUTO, "        guard let i = n.seen.firstIndex(where: { $0.tag == tag && $0.sha256 == sha256 }) else {", "        guard let i = n.seen.firstIndex(where: { $0.tag == tag }) else {"),
    ("A1: the first sight not taken", APP, "                    self.remember { Auto.sighted($0, tag: sightTag, sha256: p.manifest.sha256, signedAt: p.manifest.signedAt, now: now,\n", "                    self.remember { Auto.sighted($0, tag: \"x\", sha256: p.manifest.sha256, signedAt: p.manifest.signedAt, now: now,\n"),
    ("A2: the floor raised on a manifest", APP, "                    self.remember { Auto.signedRelease($0, c.version) }\n", ""),
    ("A2: the nightly floor raised on a manifest", APP, "                    self.remember { Auto.signedNightly($0, c.version, build: build) }\n", ""),
    ("A3: attempts unbounded", AUTO, "            .prefix(maxRemembered)\n            .map { ($0.key, Memory.Attempt(", "            .map { ($0.key, Memory.Attempt("),
    ("A3: old attempts kept", AUTO, "            return UpdateInstallPolicy.isNewer(v, build: b, than: running, runningBuild: runningBuild, byBuild: b != nil)\n", "            return true\n"),
    ("A3: an oversized item read as nothing", AUTO, "        guard data.count <= maxItemBytes else { return .unreadable(", "        guard data.count <= maxItemBytes else { return .noItem; _ = ("),
    ("A3: an attempt counted at the offer", APP, "                self.target = offer\n                print(\"Automatic update: \\(Policy.name(", "                self.target = offer\n                self.remember { Auto.began($0, offer.version, now: now) }\n                print(\"Automatic update: \\(Policy.name("),
    ("G1: Install Now without a second look", POL, "            n.phase = .lookingAgain(devices: devices)\n            return (n, [.lookAgain])", "            if devices.isEmpty { n.phase = .installing; return (n, [.install]) }\n            n.phase = .ready(devices: devices)\n            return (n, [])"),
    ("W2: notes read with Data(contentsOf:)", INS, "        guard let data = readSmallFile(url), let text = String(data: data, encoding: .utf8) else { return nil }", "        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }"),
    ("W2: the launch's notes read on the main actor", APP, "            let notes = await Task.detached(priority: .utility) {\n", "            let notes = await Task { @MainActor in\n"),
    ("R3: the leftover note after the last check", INS, "        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n", "        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n"),
    ("W1: the watcher starts what it didn't check", INS, "if ! whole \"$app\"; then\n    /bin/mv \"$app\" \"$dir/failed its check.app\" || exit 7\n", "if false; then\n    /bin/mv \"$app\" \"$dir/failed its check.app\" || exit 7\n"),
    ("W1: the restored note written through a link", INS, "note=$(/usr/bin/mktemp \"$restored.XXXXXX\") && /usr/bin/printf '%s\n%s\n' \"$token\" \"$why\" 1<>\"$note\" && /bin/mv -f -h \"$note\" \"$restored\"\n", "/usr/bin/printf '%s\n%s\n' \"$token\" \"$why\" > \"$restored\"\n"),
    ("no age limit", AUTO, "        if age > oldest { return .refuse(", "        if false { return .refuse("),
    ("a signature from the future", AUTO, "        if signedAt.timeIntervalSince(now) > clockSkew {", "        if false {"),
    ("a rollback by itself", AUTO, "        if let highest = m.highestSigned.flatMap(UpdateInstallPolicy.strictVersion), offered < highest {\n            return .no(", "        if let highest = m.highestSigned.flatMap(UpdateInstallPolicy.strictVersion), false, offered < highest {\n            return .no("),
    ("a third attempt", AUTO, "            if a.count >= maxAttempts { return .no(", "            if a.count > maxAttempts { return .no("),
    ("attempts back to back", AUTO, "            if now.timeIntervalSince(a.last) < retryAfter { return .no(", "            if false { return .no("),
    ("a stopped release by itself", AUTO, "        if isStopped(m, tag: offeredTag) { return .no(", "        if false { return .no("),
    ("without the daily check", AUTO, '        guard checkOn else { return .no("the daily check is off") }\n', ""),
    ("without the update key", AUTO, '        guard signed else { return .no("the release isn’t signed', '        guard true else { return .no("the release isn’t signed'),
    ("the wait back to ten minutes", AUTO, "    static let quietFor: TimeInterval = 5 * 60\n", "    static let quietFor: TimeInterval = 10 * 60\n"),
    ("a shorter cooling-off", AUTO, "    static let coolingOff: TimeInterval = 48 * 3600\n", "    static let coolingOff: TimeInterval = 24 * 3600\n"),
    ("the waiting copy's words not the rule's", POL, "        var quietMinutes = UpdateAutoPolicy.quietMinutes\n", "        var quietMinutes = 10\n"),
    ("installed over a device", AUTO, "        devices == 0 && !pairing && now.timeIntervalSince(quietSince) >= quietFor", "        !pairing && now.timeIntervalSince(quietSince) >= quietFor"),
    ("installed during a pairing", AUTO, "        devices == 0 && !pairing && now.timeIntervalSince(quietSince) >= quietFor", "        devices == 0 && now.timeIntervalSince(quietSince) >= quietFor"),
    ("a device that joined cut off", POL, "        case (.installing, .devicesJoined(let devices)) where s.mode == .manual:\n            n.phase = .ready(devices: devices)\n", "        case (.installing, .devicesJoined(let devices)) where s.mode == .manual:\n            n.phase = .installing\n"),
    ("the automatic update asks like Update Now", POL, "            if s.mode == .automatic { n.phase = .waiting; return (n, []) }\n", ""),
    # Use nightly builds (plan §16).
    ("a nightly read as a release", MAN, "            guard parsed.manifest.channel == channel else { return .failure(.format(\"first\")) }\n", ""),
    ("an update key trusted for nightlies", POL, "nightlyKeys: UpdateManifest.nightlyKeys.filter { !UpdateManifest.releaseKeys.contains($0) && $0 != UpdateManifest.testPublicKey })", "nightlyKeys: UpdateManifest.nightlyKeys)"),
    ("nightlies by version alone", POL, "        guard byBuild, let build, let runningBuild else { return false }\n        return build > runningBuild\n", "        return false\n"),
    ("a tie goes to the nightly", POL, "case (let r?, let n?): return n.version > r.version ? n : r", "case (let r?, let n?): return n.version >= r.version ? n : r"),
    ("an older nightly offered", POL, "            guard let build = o.build, isNewer(o.version, build: build, than: running, runningBuild: runningBuild, byBuild: true) else { return nil }\n", "            guard o.build != nil else { return nil }\n"),
    ("a nightly's draft read", POL, "object[\"prerelease\"] as? Bool == true, object[\"draft\"] as? Bool != true else {\n            return .failure(.releaseUnreadable(\"not the nightly pre-release\"))", "object[\"prerelease\"] as? Bool == true else {\n            return .failure(.releaseUnreadable(\"not the nightly pre-release\"))"),
    ("a half-published nightly taken", POL, "        guard m.size == l.zip.size else { return .manifestMismatch(\"size\") }\n", ""),
    ("a nightly with no switch", AUTO, '            guard m.nightly else { return .no("Use nightly builds is off") }\n', ""),
    ("no nightly floor", AUTO, "               UpdateInstallPolicy.isNewer(hv, build: hb, than: offered, runningBuild: build, byBuild: true) {\n                return .no(", "               UpdateInstallPolicy.isNewer(hv, build: hb, than: offered, runningBuild: build, byBuild: true) && false {\n                return .no("),
    ("no age limit for nightlies", AUTO, "    static let nightlyMaxAge: TimeInterval = 30 * 24 * 3600\n", "    static let nightlyMaxAge: TimeInterval = 3000 * 24 * 3600\n"),
    ("a nightly with a cooling-off", AUTO, "        let wait = wait ?? (nightly ? nightlyCoolingOff : coolingOff)\n", "        let wait = wait ?? coolingOff\n"),
    ("release V offered to nightly V", POL, "        let r = release.flatMap { $0.version > running ? $0 : nil }\n", "        let r = release.flatMap { $0.version >= running ? $0 : nil }\n"),
    ("a release's manifest ordered by build", POL, "                      byBuild: manifest.channel == .nightly) else { return .failure(.notNewer(versionText)) }", "                      byBuild: true) else { return .failure(.notNewer(versionText)) }"),
    ("a nightly's app ordered by version alone", POL, "                      byBuild: manifest.channel == .nightly) else { return .failure(.notNewer(versionText)) }", "                      byBuild: false) else { return .failure(.notNewer(versionText)) }"),
    ("release V installed by itself on V", AUTO, "        guard offered > running else { return .no(\"the offered release isn’t newer\") }", "        guard offered >= running else { return .no(\"the offered release isn’t newer\") }"),
    # The third security pass (plan §12e).
    ("CL1: GitHub's clock ignored", AUTO, "        if ghNow < ghEnd || now < localEnd { return .waitUntil(max(localEnd, byGitHub)) }\n", "        if now < localEnd { return .waitUntil(localEnd) }\n"),
    ("CL1: no date from GitHub taken as passed", AUTO, "        guard let ghNow = github.now, let ghFirst = github.firstSeen else { return .waitUntil(now < localEnd ? localEnd : nil) }\n", "        guard let ghNow = github.now, let ghFirst = github.firstSeen else { return now < localEnd ? .waitUntil(localEnd) : .go }\n"),
    ("CL1: another zone taken as GitHub's clock", POL, '(2000...2999).contains(year), p[5] == "GMT" else { return nil }', '(2000...2999).contains(year) else { return nil }'),
    ("CL1: a date with the wrong weekday taken", POL, "              let w = c.weekday, (w + 5) % 7 == weekday else { return nil }", "              let w = c.weekday, w > 0 || weekday >= 0 else { return nil }"),
    ("AU1: the publication ignored", AUTO, "        let ghEnd = max(ghFirst, github.published ?? ghFirst).addingTimeInterval(wait)\n", "        let ghEnd = ghFirst.addingTimeInterval(wait)\n"),
    ("AU1: no publication date taken", AUTO, "        if !nightly, github.published == nil { return .refuse(", "        if false { return .refuse("),
    ("AU1: a publication moved earlier", AUTO, "        if let p = published, n.seen[i].published.map({ p > $0 }) ?? true { n.seen[i].published = p }\n", "        if let p = published { n.seen[i].published = p }\n"),
    ("AU1: the remembered end without the publication", AUTO, "            if let g = s.firstGitHub, let p = s.published, p > g { end = max(end, s.first.addingTimeInterval(p.timeIntervalSince(g) + wait)) }\n", ""),
    ("AU1: published_at not read", POL, "                                    publishedAt: (object[\"published_at\"] as? String).flatMap(UpdateManifest.date)))", "                                    publishedAt: nil))"),
    ("CL1: this Mac's clock taken for GitHub's", APP, "now: p.release.answeredAt,\n", "now: Date(),\n"),
    ("CL1, AU1: the dates without GitHub's", APP, "                                              published: nightly ? nil : (sight?.published ?? p.release.publishedAt))\n", "                                              published: Date.distantPast)\n"),
    ("N10 a: a nightly key in releaseKeys trusted", POL, "        updateKeys: UpdateManifest.releaseKeys.filter { !UpdateManifest.nightlyKeys.contains($0) && $0 != UpdateManifest.testPublicKey },", "        updateKeys: UpdateManifest.releaseKeys,"),
    ("N10 g: nightly turned on without a write", AUTO, "        if next.nightly && !current.nightly { held.nightly = false }\n", ""),
    ("N10 g: the store's own hold-back", "AutoUpdateStore.swift", "        memory = UpdateAutoPolicy.heldBack(next, current: memory)\n", "        var held = next\n        if next.on && !memory.on { held.on = false }\n        memory = held\n"),
    ("N10 k: words cut by Characters", AUTO, "failure: $0.value.failure.map { utf8Prefix($0, bytes: 200) }", "failure: $0.value.failure.map { String($0.prefix(200)) }"),
    ("N10 l: stops by the tag's text", AUTO, "        return m.stopped.contains { UpdateInstallPolicy.strictTag($0) == v }\n", "        return m.stopped.contains(tag)\n"),
    ("N10 l: a stop beside the release by its text", POL, "        strictTag(stopTag) == release.version && stopSHA256 == manifestSHA256\n", "        stopTag == release.tag && stopSHA256 == manifestSHA256\n"),
    ("N10 n: the nightly asked at launch with the daily check off", APP, "        if nightliesOn, !atLaunch || checkOn() { lookAtNightly", "        if nightliesOn { lookAtNightly"),
    ("N10 n: once a day only, with nightlies too", POL, '        let ask = (nightly ? "Once a day, and with nightly builds on each time Sill opens, Sill asks GitHub whether a newer version is out."', '        let ask = (nightly ? "Once a day, Sill asks GitHub whether a newer version is out."'),
    ("NB1: the nightly words as two checks", POL, '"Nightly builds are built and signed by GitHub from Sill’s newest code; nobody looks at them first. They are less tested', '"Nightly builds are made every night from Sill’s newest code. Each is checked two ways: Apple’s signature and notarization, and Sill’s nightly key. They are less tested'),
    ("NB1: the nightly's wait changed silently", AUTO, "    static let nightlyCoolingOff: TimeInterval = 0\n", "    static let nightlyCoolingOff: TimeInterval = 12 * 3600\n"),
    ("NB1: a nightly that waits begun early", AUTO, '            if let waitUntil, now < waitUntil { return .no("nightly \\(offered) (\\(build)) cools off until', '            if false, let waitUntil, now < waitUntil { return .no("nightly \\(offered) (\\(build)) cools off until'),
    ("NB1: no wait taken as a wait", AUTO, "        guard wait > 0 else { return .go }\n", "        guard wait >= 0 else { return .go }\n"),
    ("NB1: a nightly's offer note without its wait", AUTO, "        if wait > 0 {\n            if let waitUntil {", "        if false {\n            if let waitUntil {"),
    ("W3: a new copy the watcher kept unsaid", APP, '            if restored.count > 2, restored[2] == "kept", let p = pending,', '            if false, restored.count > 2, restored[2] == "kept", let p = pending,'),
    # Sill.app's sources (T21): read by the check, not compiled by it.
    ("a default read by the installer", INS, "    let userAgent: String\n", "    let userAgent: String\n    let host = UserDefaults.standard.string(forKey: \"SillUpdateHost\")\n"),
    ("the environment read by the updater", APP, "    let available: Bool\n", "    let available: Bool\n    let override = ProcessInfo.processInfo.environment[\"SILL_UPDATE\"]\n"),
    ("endpoints of the app's own", APP, "installer = UpdateInstaller(trust: trust, endpoints: .github,", "installer = UpdateInstaller(trust: trust, endpoints: Policy.Endpoints(local),"),
    ("a trust of the app's own", APP, "let trust = Policy.Trust.release", "let trust = Policy.Trust(signer: \"anchor apple\", notarized: false)"),
]
caught = 0
ONLY = sys.argv[2:]
if ONLY: MUTANTS = [m for m in MUTANTS if m[0] in ONLY]
for name, file, old, new in MUTANTS:
    src = open(os.path.join(SRC, file)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        copy = os.path.join(t, "SillMenuBar")
        shutil.copytree(SRC, copy)
        open(os.path.join(copy, file), "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, copy], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe, copy, os.path.join(WT, "Sources")], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
