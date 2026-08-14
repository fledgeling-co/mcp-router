import Foundation

/// The restart the reference loses — divergence W-D1, and the whole of the `div-r2-d7` parity row.
///
/// The running router loads its upstream list at startup. The manifest hot-reloads; the upstream
/// list does not, so a server that has just been written into `servers.json` is not one the live
/// router knows how to spawn until it restarts (`watch.ts:360-364`).
///
/// **The reference loses that restart.** When `~/.claude.json` stops parsing between the initial
/// read and the pre-delete re-read, `watch.ts:299` returns — past the `restartRouter()` at `:336` —
/// having *already written* `servers.json`. On the next fire the config matches, `configChanged` is
/// false, and the restart is never issued: the adopted server can never reach the running router.
/// That is D7, registered as deferred child D-i for the TypeScript side.
///
/// Two changes close it, and the second was found by review rather than by design:
///
/// 1. The restart is issued **as soon as `servers.json` has been written**, before `~/.claude.json`
///    is touched at all, so no later early return can skip it (X6).
/// 2. It is **owed, not lost** — `restartPending` is persisted *before* the write, so a process
///    killed between the rename and any later save still leaves the debt recorded (X7).
public enum WatchRestart {
    /// Performs the restart. Returns `nil` on success, or the reason it failed.
    ///
    /// Injected so unit tests never touch the developer's launchd session; the parity lanes drive
    /// the real one under a scratch label.
    public typealias Kick = @Sendable (_ label: String) -> String?

    /// `execFileSync('/bin/launchctl', ['kickstart', '-k', 'gui/<uid>/<label>'], {timeout: 15_000})`.
    public static let launchctl: Kick = { label in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        // An argument array, never an interpolated shell string (SWIFT_PRACTICES §6).
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }

        // The reference's 15 s timeout. Polled rather than awaited: this is a synchronous one-shot
        // and a semaphore around a Task would deadlock the cooperative pool (SWIFT_PRACTICES §1).
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning, Date() < deadline {
            usleep(20000)
        }
        if process.isRunning {
            process.terminate()
            return "timed out after 15000ms"
        }
        guard process.terminationStatus == 0 else {
            return "launchctl exited \(process.terminationStatus)"
        }
        return nil
    }
}
