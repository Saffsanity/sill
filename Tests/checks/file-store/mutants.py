"""FileStore mutants (Sources/SillHost/FileStore.swift): each must compile and make file-store/main.swift fail.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/FileStore.swift"
M = [
    ("the hash never checked", F, "guard s.written == size, digest == sha256 else { throw Failure.damaged }", "guard s.written == size else { throw Failure.damaged }"),
    ("the size never checked", F, "guard s.written == size, digest == sha256 else { throw Failure.damaged }", "guard digest == sha256 else { throw Failure.damaged }"),
    ("never quarantined", F, "        try mark(s.url, device: device)\n", ""),
    ("kept 0600", F, "guard fchmod(s.fd, 0o644) == 0 else { throw Self.failure(errno) }", "guard fchmod(s.fd, 0o600) == 0 else { throw Self.failure(errno) }"),
    ("the sender's name uncleaned", F, "let cleaned = FileNames.clean(name)", "let cleaned = name.replacingOccurrences(of: \"/\", with: \"-\")"),
    ("a link at the name replaced", F, "            guard errno == EEXIST else { throw Self.failure(errno) }\n            tried.insert(candidate.lowercased())",
     "            guard errno == EEXIST else { throw Self.failure(errno) }\n            return candidate"),
    ("a link counts as free", F, "return lstat(destination.appendingPathComponent(name).path, &st) == 0",
     "return stat(destination.appendingPathComponent(name).path, &st) == 0"),
    ("a staging file opened again", F, "O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC", "O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC"),
    ("a failed finish leaves its part", F, "        defer { discard(s) }\n", ""),
    ("leftovers kept", F, "for name in names where unlink(staging.appendingPathComponent(name).path) == 0 { gone += 1 }", "for _ in names where false { gone += 1 }"),
    ("a destination that is a link taken", F, "guard (st.st_mode & S_IFMT) == S_IFDIR else { throw Failure.cantSave(\"\\(url.lastPathComponent) is not a folder\") }\n            return",
     "_ = st\n            return"),
    ("a full volume as cantSave", F, "code == ENOSPC || code == EDQUOT ? .noRoom", "code == EDQUOT ? .noRoom"),
    ("a staging folder anyone reads", F, "try makeFolder(staging, mode: 0o700)", "try makeFolder(staging, mode: 0o755)"),
    ("a chosen link taken", F, '        if (st.st_mode & S_IFMT) == S_IFLNK { return "Choose the folder itself, not an alias or a link to it." }\n', ""),
    ("a chosen folder Sill cannot write taken", F, '        guard access(url.path, W_OK) == 0 else { return "Sill can’t save files in that folder." }\n', ""),
    ("Where from not cleaned", F, 'let from = "\\(SafeText.label(device)), through Sill"', 'let from = "\\(device), through Sill"'),
]
sys.exit(0 if module.mutate("file-store", M, sys.argv[1]) else 1)
