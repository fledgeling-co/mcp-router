import Foundation

/// Where a log line goes. Behind a protocol so the emitted **bytes** can be captured and compared
/// against the reference's, and so a failing sink can be presented on demand.
public protocol LogSink: Sendable {
    func write(_ bytes: Data) throws
}

public struct StandardErrorSink: LogSink {
    public init() {}

    public func write(_ bytes: Data) throws {
        try FileHandle.standardError.write(contentsOf: bytes)
    }
}

/// Anything the router can write to its log.
///
/// `LogEvent` below is a closed, typed set on purpose. That is worth keeping, but it makes the enum
/// a shared surface every later item wants to append to, and two items appending to one enum is a
/// merge conflict rather than a design. This protocol is the extension point instead: each item
/// declares its own event type in its own file, and `RouterLog` keeps its single formatting path.
public protocol LoggableEvent: Sendable {
    var level: RouterLog.Level { get }
    var message: String { get }
}

/// Everything R1 logs.
///
/// This is divergence D5. The reference's `log.info(msg: string)` takes an unrestricted string, so
/// nothing stops a caller writing `log.info(\`starting ${JSON.stringify(config)}\`)` — and a token
/// that reaches a log file is not recoverable after the fact. A closed set of events with scalar
/// payloads makes that a compile error rather than a code-review habit: there is no entry point
/// that accepts a config, an env dictionary or a header dictionary, because there is no entry point
/// that accepts anything but the fields below.
///
/// The emitted bytes are still identical to the reference's (spec A30), so R4 sees no difference.
/// A later item that needs a new line declares its own `LoggableEvent` type rather than a format
/// string at the call site — the same guarantee, without the shared file.
public enum LogEvent: Sendable, Hashable {
    case manifestUnreadable(path: String, reason: String)
    case manifestReloaded(serverCount: Int)
    case manifestReloadFailed(reason: String)
    case manifestCurrent(server: String)
    case serverIndexed(server: String, toolCount: Int)
    case serverSurfaceChanged(server: String, changeCount: Int)
    case serverIndexFailed(server: String, reason: String)

    public var level: RouterLog.Level {
        switch self {
        case .manifestReloaded, .serverIndexed: .info
        case .manifestUnreadable, .manifestReloadFailed, .serverSurfaceChanged: .warn
        case .serverIndexFailed: .error
        case .manifestCurrent: .debug
        }
    }

    /// Byte-for-byte the reference's text, including its quoting and its `change(s)` plural.
    public var message: String {
        switch self {
        case let .manifestUnreadable(path, reason):
            "manifest at \(path) unreadable (\(reason)); rebuilding"
        case let .manifestReloaded(count):
            "manifest reloaded: \(count) servers cached"
        case let .manifestReloadFailed(reason):
            "manifest reload failed (\(reason)); serving the previous one"
        case let .manifestCurrent(server):
            "manifest for \"\(server)\" is current; not spawning"
        case let .serverIndexed(server, count):
            "indexed \"\(server)\": \(count) tools"
        case let .serverSurfaceChanged(server, count):
            "\"\(server)\" changed its tool surface (\(count) change(s)); "
                + "serving the approved one until it is accepted"
        case let .serverIndexFailed(server, reason):
            "failed to index \"\(server)\": \(reason)"
        }
    }
}

/// The router's structured log.
public actor RouterLog {
    public enum Level: String, Sendable, Hashable, CaseIterable {
        case info
        case warn
        case error
        case debug

        /// `level.padEnd(5)`.
        var padded: String {
            rawValue.count >= 5 ? rawValue : rawValue + String(repeating: " ", count: 5 - rawValue.count)
        }
    }

    private let sink: LogSink
    private let fileSystem: FileSystem
    private let clock: RouterClock
    private var logFile: String?
    private var verbose: Bool

    public init(
        sink: LogSink = StandardErrorSink(),
        fileSystem: FileSystem = RealFileSystem(),
        clock: RouterClock = SystemClock(),
        file: String? = nil,
        verbose: Bool = false
    ) {
        self.sink = sink
        self.fileSystem = fileSystem
        self.clock = clock
        logFile = file
        self.verbose = verbose
    }

    /// Re-enterable: calling it again replaces both settings, and passing `nil` **disables** a file
    /// that was previously configured rather than leaving it attached.
    ///
    /// The directory is created here rather than at the first write, so a misconfigured path is
    /// reported while someone is still looking at the command that set it.
    public func configure(file: String?, verbose: Bool) {
        logFile = file
        self.verbose = verbose
        guard let file else { return }
        // Divergence D4. The reference's try/catch covers only the append, so a directory it cannot
        // create throws out of `configureLogging` and takes the router down at startup. "Logging
        // must never take the router down" is the reference's own stated intent; this is the
        // intent, implemented.
        try? fileSystem.createDirectory(atPath: (file as NSString).deletingLastPathComponent)
    }

    public func log(_ event: LogEvent) {
        record(event)
    }

    /// The single formatting path, open to any item's own event type.
    ///
    /// `log(_:)` keeps its exact signature so R1's leading-dot call sites still infer `LogEvent`;
    /// a generic parameter there would have broken every one of them.
    public func record(_ event: any LoggableEvent) {
        // Nothing at all happens for a debug line when verbosity is off — not even reading the
        // clock. The check has to come first for that to be true.
        guard event.level != .debug || verbose else { return }

        let line = "\(JSDate.iso8601(milliseconds: clock.nowMilliseconds)) "
            + "\(event.level.padded) \(event.message)\n"
        let bytes = Data(line.utf8)

        // stderr first, and never stdout: stdout stays clean in case this is ever run over a stdio
        // transport, where anything written there is protocol traffic.
        try? sink.write(bytes)

        guard let logFile else { return }
        // An append failure is swallowed, matching the reference: a full disk must not stop the
        // router from routing.
        try? fileSystem.appendFile(bytes, atPath: logFile)
    }
}

/// R1's own events, on the shared extension point.
extension LogEvent: LoggableEvent {}
