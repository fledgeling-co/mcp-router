import Foundation

/// The cross-process mutual exclusion `servers.json` never had.
///
/// Three processes write that file: this watcher, the daemon's control API (`ConfigEdit.edit`), and
/// the Mac app driving that API. The daemon's read-modify-write window is microseconds. The
/// watcher's is **seconds**, because it spawns and indexes a child in the middle of it, so an
/// adoption that read the file before indexing and wrote it afterwards would erase every PATCH that
/// landed in between. That is `spec-R2.md`'s W10 and the reason R2-W is a child spec at all.
///
/// **The lock object is a sidecar, `servers.json.lock`, never `servers.json` itself (X1).** Every
/// writer here commits by writing a temporary file and renaming it over the destination, which
/// replaces the inode. A lock taken on the config would therefore be held on a file that no longer
/// occupies that path, and a second writer opening the new inode would be excluded by nothing. The
/// sidecar is never renamed, never deleted, and never read — unlinking it while another process
/// holds a descriptor on it is exactly how a lock stops excluding anything.
///
/// `flock(2)` is released by the kernel when the descriptor closes, including when the process is
/// killed, so a crash cannot leave a lock file that deadlocks the next run.
public enum ConfigMutationLock {
    /// The daemon's bound. `ConfigEdit.edit` is synchronous and runs inside async control handlers,
    /// so its wait parks a cooperative-pool thread — a contended PATCH should fail fast and visibly
    /// rather than stall the control API.
    public static let daemonTimeoutMs = 2000
    /// The watcher's bound. It is a launchd one-shot with nothing waiting on it, so it can afford to
    /// wait out a whole control-API burst rather than abandon an adoption it has already paid to
    /// index.
    public static let watcherTimeoutMs = 10000

    public enum LockProblem: Error, Sendable, Equatable, CustomStringConvertible {
        case notAcquired(path: String, timeoutMs: Int)
        case reentrant(path: String)
        case couldNotOpen(path: String, reason: String)

        public var description: String {
            switch self {
            case let .notAcquired(path, timeoutMs):
                // Says what happened, who is responsible, and what was not done. Blames nobody:
                // another process writing the file is ordinary, not misuse.
                "could not lock \(path) within \(timeoutMs)ms; another process is writing it. "
                    + "Nothing was changed."
            case let .reentrant(path):
                "\(path) is already locked by this process. Nothing was changed."
            case let .couldNotOpen(path, reason):
                "could not open the lock file \(path) (\(reason)). Nothing was changed."
            }
        }
    }

    /// Lock paths held **on the current thread**.
    ///
    /// `flock` is per open file description, so a second `open` of the same lock file inside one
    /// process produces a second description that blocks against the first. Two *concurrent*
    /// callers on different threads are supposed to block against each other — that is the lock
    /// working, and the daemon relies on it, since two control handlers may PATCH at once. What must
    /// not block is a **nested** acquire on one call stack, which can never be released and would
    /// spin the whole timeout before reporting that *another process* is writing the file — a false
    /// statement about a bug in this one.
    ///
    /// Thread-local rather than process-wide for exactly that reason, and sound because `body` is
    /// synchronous: a nested acquire is always on the thread that took the outer one.
    private static let nestingKey = "gg.rhodes.mcp-router.configMutationLock"

    private static func heldOnThisThread() -> Set<String> {
        Thread.current.threadDictionary[nestingKey] as? Set<String> ?? []
    }

    private static func setHeldOnThisThread(_ paths: Set<String>) {
        Thread.current.threadDictionary[nestingKey] = paths
    }

    /// The path of the sidecar for a given config file.
    ///
    /// Standardised first, so two spellings of one file — a symlinked home, a `..` in the middle, a
    /// trailing slash — resolve to one lock and one nesting key. Without that a nested acquire
    /// through the other spelling would evade the guard, self-deadlock for the whole timeout, and
    /// then report that *another process* holds the file.
    public static func lockPath(forConfigAt path: String) -> String {
        "\((path as NSString).standardizingPath).lock"
    }

    /// The environment override, applied to either default.
    public static func timeoutMilliseconds(
        default fallback: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard let raw = environment["MCPR_CONFIG_LOCK_TIMEOUT_MS"],
              let parsed = Int(raw), parsed > 0
        else { return fallback }
        return parsed
    }

    /// Run `body` with an exclusive cross-process lock on the config at `path`.
    ///
    /// Synchronous on purpose: `ConfigEdit.edit` is synchronous, and making this `async` would
    /// either force that call site to change shape or invite a semaphore around a `Task`, which
    /// deadlocks the cooperative pool (SWIFT_PRACTICES §1).
    @discardableResult
    public static func withExclusiveLock<T>(
        forConfigAt path: String,
        timeoutMs: Int,
        _ body: () throws -> T
    ) throws -> T {
        let lock = lockPath(forConfigAt: path)

        var heldHere = heldOnThisThread()
        if heldHere.contains(lock) { throw LockProblem.reentrant(path: path) }
        heldHere.insert(lock)
        setHeldOnThisThread(heldHere)
        defer {
            var remaining = heldOnThisThread()
            remaining.remove(lock)
            setHeldOnThisThread(remaining)
        }

        try? FileManager.default.createDirectory(
            atPath: (lock as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        // O_CLOEXEC so a spawned MCP child never inherits this descriptor. The daemon is the real
        // beneficiary: its pool spawns children constantly, and an inherited lock descriptor would
        // keep the lock alive for as long as that child lived — long past the write it guarded.
        let descriptor = open(lock, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw LockProblem.couldNotOpen(path: lock, reason: String(cString: strerror(errno)))
        }
        defer { close(descriptor) }

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { break }
            // A filesystem that does not implement advisory locking at all — some network mounts —
            // must not turn a control-API PATCH that worked before this item into one that fails.
            // There was never any exclusion there to lose, so the write proceeds unlocked. Declared
            // as W-D11 rather than left as a silent behaviour change.
            if errno == ENOTSUP || errno == EOPNOTSUPP || errno == EINVAL { return try body() }
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw LockProblem.couldNotOpen(path: lock, reason: String(cString: strerror(errno)))
            }
            guard Date() < deadline else {
                throw LockProblem.notAcquired(path: path, timeoutMs: timeoutMs)
            }
            usleep(2000)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }
}
