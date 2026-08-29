import Foundation

/// The real runner: one CLI, no shell, bounded in time and in how much of its output is kept.
///
/// **`arguments` is passed to `Process` directly and never joined into a command line.** The prompt
/// carries excerpts of the user's own shell history, which is the most quoting-hostile input this
/// router handles — a `$(` or a backtick in something they ran would be executed by any shell that
/// saw it. There is no shell here to see it.
///
/// A lane whose binary is not on `PATH` returns `nil` rather than throwing, so the ladder falls
/// through to the next rung without recording a refusal the machine never made.
public struct AnalystProcessRunner: AnalystCommandRunning {
    /// How long one judgement may take. A cheap model on a summarised prompt answers in seconds;
    /// past this the run is abandoned rather than held open, because the caller is a button.
    public static let timeoutSeconds: Double = 120

    /// How much of the reply is kept. The parser reads one JSON object per line and a CLI that
    /// decides to print a transcript should not be able to spend the router's memory.
    public static let outputCap = 256 * 1024

    let timeoutSeconds: Double
    let environment: [String: String] // swift-wire-exempt: process environment, never serialised

    public init(
        timeoutSeconds: Double = AnalystProcessRunner.timeoutSeconds,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.environment = environment
    }

    public func run(binary: String, arguments: [String]) async -> AnalystCommandOutcome? {
        guard let executable = resolve(binary) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // The judge is asked a question, never told to do something. Closing stdin means a CLI that
        // decides to prompt gets EOF and exits rather than waiting for a person who is not there.
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let data = pipe.fileHandleForReading.readDataToEndOfFile().prefix(Self.outputCap)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            process.terminate()
            return AnalystCommandOutcome(status: 124, output: "timed out after \(timeoutSeconds)s")
        }
        return AnalystCommandOutcome(
            status: process.terminationStatus,
            // Lossy rather than failable, and this is the one place in this subsystem where that
            // is right: a CLI's stdout is whatever it wrote, and refusing the whole reply because
            // one byte was not UTF-8 would turn a readable answer into a lane refusal.
            // swiftlint:disable:next optional_data_string_conversion
            output: String(decoding: data, as: UTF8.self)
        )
    }

    /// `PATH` lookup by hand rather than `/usr/bin/env`, so a binary that is absent is reported as
    /// absent instead of as a rung that ran and exited 127.
    func resolve(_ binary: String) -> String? {
        let manager = FileManager.default
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(directory)/\(binary)"
            if manager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
