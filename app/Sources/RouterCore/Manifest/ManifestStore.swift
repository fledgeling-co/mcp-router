import Foundation

/// Serves the manifest to a long-lived process, re-reading it when the file on disk changes.
///
/// Without this a re-index only took effect on the next restart. The check has to stay cheap
/// because it runs on every `tools/list`, so it is a stat, and the JSON is re-parsed only when
/// mtime or size actually moved.
///
/// An `actor` rather than a class: `current()` mutates three pieces of state, and a router answering
/// several sessions at once would otherwise interleave a reload with a read.
public actor ManifestStore {
    /// The reference's exact back-off after a failed reload. One second, not "a while" — a longer
    /// window would satisfy every property stated about it while leaving a corrected file unread
    /// for as long as the window lasts.
    public static let retryBackoffMilliseconds: Double = 1000

    private let path: String
    private let fileSystem: FileSystem
    private let clock: RouterClock
    /// Optional, and absent in every unit test — but present in the serving process, because the
    /// reference logs `manifest reloaded: N servers cached` on every successful re-read and
    /// `parity-log.sh` diffs the line sequence. R1 declared both events and the store never had a
    /// logger to fire them, which nothing noticed while no process ran it.
    private let log: RouterLog?
    private var manifest: Manifest
    /// `nil` stands for the reference's empty stamp string: the file could not be stat'd.
    private var stamp: FileStamp?
    private var retryAfter: Double = 0

    /// Why the last load or reload degraded, if it did. Divergence D2 — the reference records this
    /// only in a log line.
    public private(set) var lastProblem: ManifestIO.Problem?

    public init(
        path: String,
        fileSystem: FileSystem = RealFileSystem(),
        clock: RouterClock = SystemClock(),
        log: RouterLog? = nil
    ) {
        self.path = path
        self.fileSystem = fileSystem
        self.clock = clock
        self.log = log
        let load = ManifestIO.load(path: path, fileSystem: fileSystem)
        manifest = load.manifest
        lastProblem = load.problem
        // Recorded even when the load just failed. That is a latent defect in the reference and it
        // is ported: a manifest that is malformed at construction has its stamp remembered, so the
        // guard below sees an unchanged file and never retries until something writes to it. It is
        // reported as a deferred child rather than fixed here.
        stamp = try? fileSystem.attributes(atPath: path)
    }

    public func current() -> Manifest {
        let now = clock.nowMilliseconds
        if now < retryAfter { return manifest }

        guard let current = try? fileSystem.attributes(atPath: path) else {
            // The file is gone. The previous manifest keeps being served and the stamp is **not**
            // cleared — so if a file reappears with the stamp this one had, it is not re-read. The
            // second of the two latent defects, ported and reported.
            return manifest
        }
        guard current != stamp else { return manifest }

        do {
            manifest = try ManifestIO.parse(fileSystem.readFile(atPath: path))
            stamp = current
            retryAfter = 0
            lastProblem = nil
            let count = manifest.serverCount
            if let log {
                Task { await log.log(.manifestReloaded(serverCount: count)) }
            }
        } catch {
            // The stamp is deliberately not recorded: the writer may still be mid-write and finish
            // inside the same millisecond, and recording it would mean never looking again.
            retryAfter = now + Self.retryBackoffMilliseconds
            lastProblem = .malformed(path: path, reason: "\(error)")
            if let log {
                Task { await log.log(.manifestReloadFailed(reason: "\(error)")) }
            }
        }
        return manifest
    }
}
