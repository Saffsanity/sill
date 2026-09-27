"""H3 (step 1) AskLimits mutants: each must compile and make ask-limits/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/PairingWindow.swift"
M = [
    ("quiet by key only", F, "[quietKeys[fingerprint], quietSources[source]]", "[quietKeys[fingerprint]]"),
    ("quiet by address only", F, "[quietKeys[fingerprint], quietSources[source]]", "[quietSources[source]]"),
    ("quiet for 10 minutes and a moment", F, ".compactMap { $0 }.filter { now - $0 < quietSeconds }.max()", ".compactMap { $0 }.filter { now - $0 <= quietSeconds }.max()"),
    ("quietSince: the earlier close", F, ".compactMap { $0 }.filter { now - $0 < quietSeconds }.max()", ".compactMap { $0 }.filter { now - $0 < quietSeconds }.min()"),
    ("quiet forever", F, ".compactMap { $0 }.filter { now - $0 < quietSeconds }.max()", ".compactMap { $0 }.max()"),
    ("every window ever counts", F, "        openedAt.filter { now - $0 < spanSeconds }.count", "        openedAt.count"),
    ("a window counts one span and a moment", F, "        openedAt.filter { now - $0 < spanSeconds }.count", "        openedAt.filter { now - $0 <= spanSeconds }.count"),
    ("opening forgets the others", F, "openedAt = openedAt.filter { now - $0 < spanSeconds } + [now]", "openedAt = [now]"),
    ("closing keeps no address", F, "        quietKeys[fingerprint] = now\n        quietSources[source] = now", "        quietKeys[fingerprint] = now"),
    ("an expired window does not quiet", F, "case .cancelled, .expired, .stopped: return true\n        case .used, .none: return false",
     "case .cancelled, .stopped: return true\n        case .used, .none, .expired: return false"),
    ("a stopped window does not quiet", F, "case .cancelled, .expired, .stopped: return true\n        case .used, .none: return false",
     "case .cancelled, .expired: return true\n        case .used, .none, .stopped: return false"),
    ("a used window quiets", F, "case .cancelled, .expired, .stopped: return true\n        case .used, .none: return false",
     "case .cancelled, .expired, .stopped, .used: return true\n        case .none: return false"),
    ("the override is for quiet only", F, "        spanSeconds = seconds ?? Self.span", "        spanSeconds = Self.span"),
    ("the override on any host", F, "guard testHost, let v = environment[\"SILL_TEST_ASK_QUIET\"]", "guard let v = environment[\"SILL_TEST_ASK_QUIET\"]"),
    ("the override takes 0 and infinity", F, "let s = Double(v), s.isFinite, s > 0 else { return nil }", "let s = Double(v) else { return nil }"),
]
sys.exit(0 if module.mutate("ask-limits", M, sys.argv[1]) else 1)
