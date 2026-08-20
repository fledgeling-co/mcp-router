/// Everything the pool logs.
///
/// A closed set for the same reason R1's `LogEvent` is one: there is no entry point that accepts a
/// config, an environment dictionary or a header dictionary, so a token cannot reach a log file by
/// habit. It lives in its own file rather than as cases on `LogEvent`, so R2 and R3 can each add
/// their lines without editing the same enum.
///
/// **The text is normative.** Every string here is byte-for-byte the reference's, and the spec's
/// copy table says so; rewording one would make R4 report a difference that is only a rewording.
public enum PoolLogEvent: Sendable, Hashable, LoggableEvent {
    case spawning(server: String, command: String, args: [String])
    case connecting(server: String, transport: String, url: String)
    case ready(server: String, milliseconds: Int)
    case preOpeningWarm(count: Int, names: [String])
    case warmFailed(server: String, reason: String)
    case closingIdle(server: String, kind: Kind, calls: Int, aliveSeconds: Int)
    case closedItself(server: String)
    case needsAuthorization(server: String)
    /// The upstream refused a credential we hold. Distinct from `needsAuthorization`, which
    /// says a browser flow is waiting to be started; this says one already failed.
    case authRefused(server: String, reason: String)
    case childStderr(server: String, text: String)

    /// A stdio upstream has a child; an HTTP one has only a connection. The reference says
    /// "child" or "connection" accordingly, and the distinction is user-visible.
    public enum Kind: String, Sendable, Hashable {
        case child
        case connection
    }

    public var level: RouterLog.Level {
        switch self {
        case .spawning, .connecting, .ready, .preOpeningWarm, .closingIdle: .info
        case .warmFailed, .closedItself, .needsAuthorization, .authRefused: .warn
        case .childStderr: .debug
        }
    }

    public var message: String {
        switch self {
        case let .spawning(server, command, args):
            // The reference truncates the whole line at 200 characters, because a server's argv can
            // be arbitrarily long and this is the one log line that embeds it.
            String("spawning upstream \"\(server)\" (\(command) \(args.joined(separator: " ")))".prefix(200))
        case let .connecting(server, transport, url):
            String("connecting upstream \"\(server)\" (\(transport) \(url))".prefix(200))
        case let .ready(server, milliseconds):
            "upstream \"\(server)\" ready in \(milliseconds)ms"
        case let .preOpeningWarm(count, names):
            "pre-opening \(count) warm upstream(s): \(names.joined(separator: ", "))"
        case let .warmFailed(server, reason):
            "warm upstream \"\(server)\" did not start: \(reason)"
        case let .closingIdle(server, kind, calls, aliveSeconds):
            "closing idle \(kind.rawValue) \"\(server)\" after \(calls) call(s), \(aliveSeconds)s alive"
        case let .closedItself(server):
            "upstream \"\(server)\" closed on its own; evicting so the next call reopens it"
        case let .needsAuthorization(server):
            "upstream \"\(server)\" needs authorization — run `mcp-router auth \(server)`"
        // The reason is truncated at 120 for the same reason `childStderr` is truncated at 400:
        // the text comes from the upstream and must not be able to write unbounded lines here.
        case let .authRefused(server, reason):
            "upstream \"\(server)\" refused our credentials (\(String(reason.prefix(120)))) — "
                + "run `mcp-router auth \(server)`"
        case let .childStderr(server, text):
            // Truncated at 400, as the reference does: a chatty server must not be able to write
            // unbounded lines into the router's own log.
            "[\(server)] \(text.prefix(400))"
        }
    }
}
