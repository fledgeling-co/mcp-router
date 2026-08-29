import Foundation

/// Finding a harness's session files under its root.
///
/// Split from ``TranscriptScan`` for the reason ``DiskExtensionStore`` gives for using
/// `FileManager` directly: a directory walk is a filesystem property, and the seam's in-memory
/// double lists only the files immediately under a prefix. A walk proven against that double would
/// be proven against something that is not a directory tree — so the walk is driven against real
/// temporary directories and the *rules* live next door, where the double is the right instrument.
public enum TranscriptCorpus {
    /// The extension a session file has. Claude Code writes JSONL; so does Codex.
    public static let sessionSuffix = ".jsonl"

    /// How deep the walk goes.
    ///
    /// Claude Code nests one level — `projects/<slug>/<session>.jsonl` — and Codex two. Eight is
    /// well past both and is a **termination guard rather than a limit**: a symlink pointing at an
    /// ancestor makes a filesystem walk unbounded, and a scanner that hangs on somebody's home
    /// directory is worse than one that stops early and says how deep it went.
    public static let maximumDepth = 8

    /// Everything under `root` that looks like a session file, sorted.
    ///
    /// Sorted so two scans of an unchanged corpus agree; `contentsOfDirectory` promises no order,
    /// and an unstable order would make the watermark file's diff unreadable between runs.
    ///
    /// - Returns: the paths, and the number of directories that could not be listed. The second is
    ///   returned rather than logged: a corpus where half the sessions sit behind an unreadable
    ///   directory and a corpus with half as many sessions produce the same file count, and only
    ///   this number tells them apart.
    public static func files(
        under root: String, fileSystem: any FileSystem
    ) -> (paths: [String], unreadableDirectories: Int) {
        var out: [String] = []
        var unreadable = 0
        var frontier: [(path: String, depth: Int)] = [(root, 0)]
        while let next = frontier.popLast() {
            guard next.depth <= maximumDepth else { continue }
            let names: [String]
            do {
                names = try fileSystem.contentsOfDirectory(atPath: next.path)
            } catch {
                // A path that is a file rather than a directory lands here too. It is not an error
                // — the caller handed a root and the walk found a leaf — so only a path that
                // neither lists nor exists as a file counts against the tally.
                if !fileSystem.fileExists(atPath: next.path) { unreadable += 1 }
                continue
            }
            for name in names {
                let child = (next.path as NSString).appendingPathComponent(name)
                if name.hasSuffix(sessionSuffix) {
                    out.append(child)
                } else {
                    frontier.append((child, next.depth + 1))
                }
            }
        }
        return (out.sorted(), unreadable)
    }
}
