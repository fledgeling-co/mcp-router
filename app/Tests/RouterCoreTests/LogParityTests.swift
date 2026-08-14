import Foundation
import Testing
@testable import RouterCore

/// Finds files in the working tree from a test's own location, the way the design-token suite does.
enum RepoTree {
    static func root(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Makefile").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw Failure.notFound(filePath)
    }

    enum Failure: Error { case notFound(String) }

    static func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}

@Suite("Log parity with src/log.ts")
struct LogParityTests {
    /// The instant every log vector was captured at, so the emitted timestamp is comparable.
    private static let fixedMilliseconds: Double = 1_755_100_000_123

    private func event(for id: String) -> LogEvent? {
        switch id {
        case "manifest-unreadable": .manifestUnreadable(path: "/p/manifest.json", reason: "bad")
        case "manifest-reloaded": .manifestReloaded(serverCount: 3)
        case "manifest-reload-failed": .manifestReloadFailed(reason: "bad")
        case "manifest-current", "debug-suppressed-when-quiet": .manifestCurrent(server: "alpha")
        case "server-indexed": .serverIndexed(server: "alpha", toolCount: 7)
        case "server-surface-changed": .serverSurfaceChanged(server: "alpha", changeCount: 2)
        case "server-index-failed": .serverIndexFailed(server: "alpha", reason: "spawn failed")
        default: nil
        }
    }

    /// A30. Not a check that two format strings agree — these are the bytes the reference's own
    /// emitter produced for the same events, captured off its stderr.
    @Test("every log line is byte-identical to the reference's")
    func linesMatch() async throws {
        let cases = try ManifestVectors.cases("log-line")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let expected = ManifestVectors.text(testCase.member("line")) ?? ""
            let event = try #require(self.event(for: id), "no event mapped for vector \(id)")

            let sink = RecordingSink()
            let fileSystem = MemoryFileSystem()
            let log = RouterLog(
                sink: sink,
                fileSystem: fileSystem,
                clock: ManualClock(milliseconds: Self.fixedMilliseconds),
                file: "/var/router/router.log",
                // The suppression vector is the one case captured with verbosity off.
                verbose: id != "debug-suppressed-when-quiet"
            )
            await log.log(event)
            ManifestVectors.expectSameBytes(sink.text, expected, "line/\(id)")
            // A30 says "identical bytes in BOTH sinks". Comparing only stderr would pass an
            // implementation that formats the file line separately and differently — two emitters
            // agreeing on a format string is not the same claim as two emitters agreeing on bytes.
            ManifestVectors.expectSameBytes(
                fileSystem.contents(atPath: "/var/router/router.log") ?? "",
                expected,
                "file/\(id)"
            )
        }
    }

    /// A34. The claim is stronger than "nothing was written": nothing is *computed*, so a
    /// suppressed debug line costs neither a timestamp nor a string.
    @Test("a debug line reads no clock at all when verbosity is off")
    func debugComputesNothingWhenQuiet() async {
        let clock = ManualClock(milliseconds: Self.fixedMilliseconds)
        let sink = RecordingSink()
        let log = RouterLog(sink: sink, fileSystem: MemoryFileSystem(), clock: clock, verbose: false)

        await log.log(.manifestCurrent(server: "alpha"))
        #expect(sink.written.isEmpty)
        #expect(clock.readCount == 0, "the verbosity check has to come before the timestamp")

        await log.configure(file: nil, verbose: true)
        await log.log(.manifestCurrent(server: "alpha"))
        #expect(clock.readCount == 1)
        #expect(!sink.written.isEmpty)
    }

    /// A31. Asserted over the whole target rather than one call path: no source file in the router
    /// core may name stdout at all, so a later addition cannot quietly route a line there.
    @Test("no source file in the router core writes to stdout")
    func stdoutIsNeverNamed() throws {
        let sources = try RepoTree.root().appendingPathComponent("app/Sources/RouterCore")
        let files = RepoTree.swiftFiles(under: sources)
        #expect(!files.isEmpty, "the scan must actually find the sources it claims to have checked")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Comments may discuss stdout — the rule is about code.
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else { continue }
                let message = "\(file.lastPathComponent):\(number + 1) writes to stdout, "
                    + "which must stay clean for a stdio transport"
                // `print` is the hole a token scan for the FileHandle names leaves open: it writes
                // to stdout and mentions neither of them, so an out-of-family review was right that
                // scanning for the handles alone would pass the most likely way this regresses.
                #expect(
                    !code.contains("standardOutput") && !code.contains("STDOUT_FILENO")
                        && !code.contains("print(") && !code.contains("fputs(")
                        && !code.contains("FileHandle(fileDescriptor: 1"),
                    "\(message)"
                )
            }
        }
    }

    @Test("the only real sink writes to standard error")
    func defaultSinkIsStandardError() throws {
        let file = try RepoTree.root()
            .appendingPathComponent("app/Sources/RouterCore/Log/RouterLog.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("FileHandle.standardError"))
    }

    /// A32, all three properties.
    @Test("configure is re-enterable, can disable a file, and creates the directory immediately")
    func configureIsReEnterable() async {
        let fileSystem = MemoryFileSystem()
        let sink = RecordingSink()
        let log = RouterLog(sink: sink, fileSystem: fileSystem, clock: ManualClock(), verbose: false)

        await log.configure(file: "/var/router/router.log", verbose: false)
        #expect(
            fileSystem.createdDirectories.contains("/var/router"),
            "the directory is created when the path is set, not at the first write"
        )

        await log.log(.manifestReloaded(serverCount: 1))
        #expect(fileSystem.contents(atPath: "/var/router/router.log") != nil)

        // Re-entering with nil detaches the file rather than leaving it attached.
        await log.configure(file: nil, verbose: false)
        let before = fileSystem.contents(atPath: "/var/router/router.log")
        await log.log(.manifestReloaded(serverCount: 2))
        #expect(
            fileSystem.contents(atPath: "/var/router/router.log") == before,
            "a disabled file stops receiving lines"
        )
        #expect(sink.written.count == 2, "stderr keeps receiving them")
    }

    /// A32's ordering half. Two independent recorders could each be right and prove nothing about
    /// which happened first, so both write into one.
    @Test("stderr is written before the file")
    func stderrPrecedesTheFile() async {
        let recorder = OperationRecorder()
        let fileSystem = MemoryFileSystem(recorder: recorder)
        let log = RouterLog(
            sink: RecordingSink(recorder: recorder),
            fileSystem: fileSystem,
            clock: ManualClock(),
            verbose: false
        )
        await log.configure(file: "/var/router.log", verbose: false)
        recorder.reset()
        await log.log(.manifestReloaded(serverCount: 1))

        #expect(recorder.operations == ["sink", "appendFile:/var/router.log"])
    }

    /// A33 and D4. The append failure is swallowed in both implementations; the other two are the
    /// divergence — the reference's try/catch does not cover them, so a directory it cannot create
    /// or a stderr it cannot write throws out of the logger and takes the router down.
    @Test("no logging failure escapes: append, directory creation, or stderr")
    func loggingNeverThrows() async {
        let fileSystem = MemoryFileSystem()
        let sink = RecordingSink()
        let log = RouterLog(sink: sink, fileSystem: fileSystem, clock: ManualClock(), verbose: true)

        // An unwritable directory. The reference throws here; this contains it.
        fileSystem.fail("createDirectory")
        await log.configure(file: "/denied/router.log", verbose: true)
        await log.log(.manifestReloaded(serverCount: 1))
        #expect(
            sink.written.count == 1,
            "stderr still gets the line even though the file could not be set up"
        )

        // A full disk on the append. Swallowed by both.
        fileSystem.stopFailing("createDirectory")
        fileSystem.fail("appendFile")
        await log.log(.manifestReloaded(serverCount: 2))
        #expect(sink.written.count == 2)

        // stderr itself failing. The reference lets this propagate.
        sink.fail()
        await log.log(.manifestReloaded(serverCount: 3))
        #expect(sink.written.count == 2, "the failing write recorded nothing, and nothing was thrown")
    }

    /// D5, asserted rather than asserted-about. The divergence is that no entry point can be handed
    /// a config, an env dictionary or a header dictionary — enforced by the payload types, so a
    /// token reaching a log file becomes a compile error rather than a code-review habit.
    @Test("no log event carries anything but a string or an integer")
    func eventsCarryOnlyScalars() {
        let every: [LogEvent] = [
            .manifestUnreadable(path: "/p", reason: "r"),
            .manifestReloaded(serverCount: 1),
            .manifestReloadFailed(reason: "r"),
            .manifestCurrent(server: "s"),
            .serverIndexed(server: "s", toolCount: 1),
            .serverSurfaceChanged(server: "s", changeCount: 1),
            .serverIndexFailed(server: "s", reason: "r")
        ]
        // An exhaustive switch, so adding a case without revisiting this test is a compile error.
        for event in every {
            switch event {
            case .manifestUnreadable, .manifestReloaded, .manifestReloadFailed, .manifestCurrent,
                 .serverIndexed, .serverSurfaceChanged, .serverIndexFailed:
                break
            }
        }
        for event in every {
            guard let payload = Mirror(reflecting: event).children.first?.value else { continue }
            let fields = Mirror(reflecting: payload)
            let values = fields.children.isEmpty ? [payload] : fields.children.map(\.value)
            for value in values {
                #expect(
                    value is String || value is Int,
                    "\(event) carries \(type(of: value)); a container here is how a secret reaches a log"
                )
            }
        }
    }

    /// The timestamp itself, against `new Date(ms).toISOString()` over the awkward instants.
    @Test("the timestamp matches JavaScript's toISOString, including before the epoch")
    func timestampsMatch() throws {
        let cases = try ManifestVectors.cases("iso8601")
        #expect(!cases.isEmpty)
        for testCase in cases {
            let id = ManifestVectors.text(testCase.member("id")) ?? "?"
            let milliseconds = testCase.member("ms")?.asNumber ?? 0
            ManifestVectors.expectSameBytes(
                JSDate.iso8601(milliseconds: milliseconds),
                ManifestVectors.text(testCase.member("text")) ?? "",
                "iso/\(id)"
            )
        }
    }
}
