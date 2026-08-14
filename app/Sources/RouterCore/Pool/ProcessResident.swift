import Foundation

/// Resident set size for a set of pids, read from `ps`.
///
/// One `ps` for every pid rather than one per server: the warm set is a budget the user sets in
/// memory, so the number behind it has to be **measured**. `DESIGN.md` §6 forbids displaying a
/// number the router does not observe, and this is where the observing happens.
///
/// Every failure path returns what it managed to read rather than throwing: a status payload
/// missing a memory figure is far better than a status endpoint that fails.
enum ProcessResident {
    static func residentKilobytes(_ pids: [Int32]) async -> [Int32: Int] {
        guard !pids.isEmpty else { return [:] }
        let output = await run(
            "/bin/ps",
            ["-o", "pid=,rss=", "-p", pids.map(String.init).joined(separator: ",")],
            timeoutSeconds: 2
        )
        var out: [Int32: Int] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let pid = Int32(parts[0]), let rss = Int(parts[1]) else { continue }
            out[pid] = rss
        }
        return out
    }

    /// Race the read against a deadline.
    ///
    /// Deliberately built from a task group rather than a continuation resumed from a termination
    /// handler and a timer: that shape needs a lock to stay safe, and a lock here would mean
    /// `@unchecked Sendable`, which the practices document and this item's own S3 clause both
    /// forbid. Whichever branch finishes first wins; if the deadline wins, the reading task is
    /// cancelled and the caller simply gets no figure for this tick.
    private static func run(_ path: String, _ arguments: [String], timeoutSeconds: Int) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await readOutput(path, arguments)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap(\.self) ?? ""
        }
    }

    /// Run the command and read it to EOF. Blocking, so it runs off the cooperative pool: EOF
    /// arrives when the child exits, which is what makes the read self-terminating.
    private static func readOutput(_ path: String, _ arguments: [String]) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return ""
            }
            let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
