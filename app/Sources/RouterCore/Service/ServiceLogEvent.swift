import Foundation

/// Everything the serving process logs that is not the pool's and not R1's.
///
/// Its own type rather than cases on `LogEvent`, following `PoolLogEvent`'s precedent: items add
/// their lines without editing one shared enum, and the closed set is what makes it structurally
/// impossible to log a token — every associated value here is a port, a count, a server name or a
/// failure reason, and there is no case that takes a header dictionary or a config.
///
/// **The text is normative.** Each string was read off the reference's own `router.log` on
/// 2026-08-14 rather than transcribed from `src/*.ts`, and `parity-log.sh` diffs them.
public enum ServiceLogEvent: Sendable, Hashable, LoggableEvent {
    case listening(host: String, port: Int, path: String)
    case serving(tools: Int, upstreams: Int, open: Int, idleSeconds: Int)
    case notProxied(names: [String])
    case notInManifest(count: Int, names: [String])
    case wroteControlToken(path: String)
    case signalReceived(signal: String)
    case requestFailed(reason: String)
    case callFailed(server: String, tool: String, reason: String)

    public var level: RouterLog.Level {
        switch self {
        case .listening, .serving, .wroteControlToken, .signalReceived: .info
        case .notProxied, .notInManifest: .warn
        case .requestFailed, .callFailed: .error
        }
    }

    public var message: String {
        switch self {
        case let .listening(host, port, path):
            "mcp-router listening on http://\(host):\(port)\(path)"
        case let .serving(tools, upstreams, open, idleSeconds):
            "serving \(tools) tools from \(upstreams) upstreams; "
                + "\(open) open, idle window \(idleSeconds)s"
        case let .notProxied(names):
            "not proxied: \(names.joined(separator: ", "))"
        case let .notInManifest(count, names):
            "\(count) upstream(s) not in the manifest (\(names.joined(separator: ", "))); "
                + "their tools will be missing until `mcp-router index` runs."
        case let .wroteControlToken(path):
            "wrote a new control token -> \(path)"
        case let .signalReceived(signal):
            "\(signal) received; closing upstreams"
        case let .requestFailed(reason):
            "request handling failed: \(reason)"
        case let .callFailed(server, tool, reason):
            "call \(server)__\(tool) failed: \(reason)"
        }
    }
}

/// What can go wrong bringing the process up, as distinct from what can go wrong serving a request.
///
/// One case per thing a caller does something different about, per `SWIFT_PRACTICES.md` §3. The
/// `listen` case carries the reference's own message text rather than a code, because that string
/// is what the CLI prints and a user shown `nw_error 48` learns nothing about the port being taken.
public enum RouterServiceError: Error, Sendable, Equatable, CustomStringConvertible {
    case listen(String)
    case alreadyStarted
    case configuration(String)

    public var description: String {
        switch self {
        case let .listen(message): message
        case .alreadyStarted: "the router is already serving"
        case let .configuration(message): message
        }
    }
}
