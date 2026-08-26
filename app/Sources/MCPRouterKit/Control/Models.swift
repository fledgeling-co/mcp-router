import Foundation

/// The wire shapes the loopback control API speaks, transcribed from `describe()` in
/// `src/control.ts`.
///
/// **Scope.** This item owns the data shapes, the error cases and the connection contract. The
/// live transport, the control token and its Keychain storage, the streaming call log and the
/// callable operations belong to the control-client item. Keeping the shapes here lets both apps
/// and the Swift router's own tests share one definition of the wire without any of them
/// depending on a networking implementation.
public struct ServerAuth: Codable, Hashable, Sendable {
    public var supported: Bool
    public var authorized: Bool
    public var authorizedAt: String?
    public var pendingURL: String?

    private enum CodingKeys: String, CodingKey {
        case supported, authorized, authorizedAt
        case pendingURL = "pendingUrl"
    }
}

public struct ServerUsage: Codable, Hashable, Sendable {
    public var calls: Int
    public var errors: Int
    public var firstSeen: String?
    public var lastUsed: String?
    public var projects: [String: Int]

    public init(
        calls: Int = 0,
        errors: Int = 0,
        firstSeen: String? = nil,
        lastUsed: String? = nil,
        projects: [String: Int] = [:]
    ) {
        self.calls = calls
        self.errors = errors
        self.firstSeen = firstSeen
        self.lastUsed = lastUsed
        self.projects = projects
    }
}

/// Why a server is inoperative, and what stands in for it meanwhile.
public struct Placard: Codable, Hashable, Sendable {
    public var reason: String
    public var substitute: String?
    public var until: String?
}

/// A tool-description change the router has seen and is holding for review.
public struct PendingChange: Codable, Hashable, Sendable {
    public var seenAt: String
    public var count: Int
}

/// The transport a server speaks. A closed set on the wire, so it is a closed set here — an
/// unrecognised value fails decoding rather than being silently treated as stdio.
public enum ServerTransport: String, Codable, Hashable, Sendable, CaseIterable {
    case stdio
    case http
    case sse
}

/// The lifecycle state the router reports for a declared server.
public enum ServerState: String, Codable, Hashable, Sendable, CaseIterable {
    case idle
    case starting
    case running
    case stopping
}

public struct MCPServer: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var transport: ServerTransport
    public var state: ServerState
    public var inFlight: Int
    public var callsServed: Int
    public var idleSec: Int
    public var command: String?
    public var args: [String]?
    public var cwd: String?
    public var url: String?
    public var envKeys: [String]?
    public var headerKeys: [String]?
    public var hash: String?
    public var tools: Int
    public var toolNames: [String]
    public var indexedAt: String?
    public var indexError: String?
    public var projects: [String]
    public var warm: Bool
    /// Declared and not served.
    ///
    /// **Non-optional, like `warm` and unlike `placard`.** The router reports it for every server,
    /// so a response that omits it is a router this app should refuse to read rather than one it
    /// should assume is fine: defaulting a missing key to `false` would draw a disabled server as
    /// live, which is the exact class of claim `DESIGN.md` §6 forbids.
    public var disabled: Bool
    public var placard: Placard?
    public var pendingChange: PendingChange?
    public var auth: ServerAuth
    public var usage: ServerUsage

    public var id: String { name }
    public var isRunning: Bool { state == .running }
    public var isStdio: Bool { transport == .stdio }

    /// A server nobody has ever called. Cleanup uses this, and deliberately does not tally what it
    /// removes — a never-used server was never really deleted.
    public var neverUsed: Bool { usage.calls == 0 }

    /// Whether this server wants a human decision. Exactly the states the attention colour is
    /// allowed to mark.
    /// **A disabled server summons nobody, and that term is the whole of M29's D11.** The three
    /// conditions below all stay true of a server that has been switched off — a held schema change
    /// especially, since disabling is what the held-change sheet offers — and this property is read
    /// by the Servers filter, the sidebar badge, the menu-bar band and the readout. Without the
    /// term, switching a server off would leave a count on the menu bar for a decision nothing can
    /// act on and nothing is exposed to.
    ///
    /// The record survives and only the summons is dropped: `pendingChange` and `indexError` are
    /// still carried, still decoded, and still shown in the inspector.
    public var needsAttention: Bool {
        guard !disabled else { return false }
        return pendingChange != nil || (auth.supported && !auth.authorized) || indexError != nil
    }
}

public struct ServersResponse: Codable, Hashable, Sendable {
    public var port: Int
    public var idleMs: Int
    public var since: String
    /// An OAuth flow the router already has open, if any. Absent most of the time.
    public var pendingAuth: PendingAuth?
    public var servers: [MCPServer]
}

public struct CallRecord: Codable, Hashable, Sendable, Identifiable {
    public var ts: String
    public var server: String
    public var tool: String
    public var ok: Bool
    public var ms: Int
    public var cold: Bool
    public var pid: Int?
    public var cwd: String?
    public var project: String?
    public var client: String?
    public var err: String?

    public var id: String { "\(ts)|\(server)|\(tool)|\(pid ?? 0)" }
}

public struct UsageResponse: Codable, Hashable, Sendable {
    public var since: String
    public var records: [CallRecord]
}

// MARK: - The authorization the router is part-way through

/// An OAuth flow the router has opened and is waiting on.
///
/// Reported on the servers response as `pendingAuth`. Modelled rather than dropped because it is
/// the difference between "this server needs authorising" and "a browser window is already open
/// waiting for you" — a surface that cannot tell those apart offers the button twice.
public struct PendingAuth: Codable, Hashable, Sendable {
    public var server: String
    public var url: String

    public init(server: String, url: String) {
        self.server = server
        self.url = url
    }
}

// MARK: - Usage summary

/// One project's share of a server's calls, with the directory it came from.
public struct ProjectCount: Codable, Hashable, Sendable, Identifiable {
    public var cwd: String
    public var project: String?
    public var calls: Int

    public var id: String { cwd }
}

/// Per-server totals as `/usage/summary` reports them.
public struct ServerSummary: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    public var calls: Int
    public var errors: Int
    public var firstSeen: String?
    public var lastUsed: String?
    public var projects: [String: Int]
    public var projectNames: [ProjectCount]

    public var id: String { name }
}

public struct UsageSummary: Codable, Hashable, Sendable {
    public var since: String
    public var servers: [ServerSummary]
}

// MARK: - Held tool-surface changes

/// One side of a tool's shape — what it described itself as, and its input schema as a string.
public struct ToolShape: Codable, Hashable, Sendable {
    public var description: String?
    public var schema: String?
}

/// What changed in one tool between the approved surface and the pending one.
///
/// `invisible` carries codepoints that render as nothing but that a model still reads. The router
/// names them rather than silently keeping them, and so does this — a description carrying a
/// zero-width joiner is the quarantine surface's whole reason to exist.
public struct ToolChange: Codable, Hashable, Sendable, Identifiable {
    /// Closed on the wire, closed here.
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case added
        case removed
        case changed
    }

    public var kind: Kind
    public var name: String
    public var before: ToolShape?
    public var after: ToolShape?
    public var invisible: [String]?

    public var id: String { "\(kind.rawValue)|\(name)" }
}

/// The response from `/servers/:name/changes`.
public struct HeldChanges: Codable, Hashable, Sendable {
    public var server: String
    public var pending: Bool
    public var seenAt: String?
    public var changes: [ToolChange]
}

// MARK: - Write responses

/// The envelope the router puts every refusal in.
///
/// A typed model rather than an inline decode, because it is a shape the control API genuinely
/// serves — a 401, a 409 with nothing to approve, and the 422 that carries the advice for getting
/// past it all arrive in this form. `hint` is the field worth naming: it is the sentence that turns
/// a dead end into a next step, and a client that decodes only `error` drops it without noticing.
public struct RouterErrorBody: Codable, Hashable, Sendable {
    public var error: String
    public var hint: String?

    public init(error: String, hint: String? = nil) {
        self.error = error
        self.hint = hint
    }
}

/// `POST /servers`. `error` is present with `needsAuth` when the server was adopted anyway because
/// an OAuth upstream is *expected* to refuse its first connection.
public struct AddedServer: Codable, Hashable, Sendable {
    public var added: String
    public var tools: Int
    public var error: String?
    public var needsAuth: Bool?
}

public struct RemovedServer: Codable, Hashable, Sendable {
    public var removed: String
}

/// `POST /servers/:name/reindex`. Carries a structured error rather than only a status, so a
/// failure can be shown against the row it belongs to.
public struct ReindexResult: Codable, Hashable, Sendable {
    public var name: String
    public var tools: Int
    public var error: String?
}

/// `POST /servers/:name/approve`.
///
/// **Not** a server object. The router replies `{server, approved}` where `approved` is the number
/// of tools promoted — a client typed to expect a full server here fails to decode a successful
/// approval, which is why this type exists rather than reusing `MCPServer`.
public struct ApprovalResult: Codable, Hashable, Sendable {
    public var server: String
    public var approved: Int
}

/// `POST /servers/:name/auth` — the URL the app opens to begin the flow.
public struct AuthorizationStart: Codable, Hashable, Sendable {
    public var server: String
    public var authorizationURL: String

    private enum CodingKeys: String, CodingKey {
        case server
        case authorizationURL = "authorizationUrl"
    }
}

/// `DELETE /servers/:name/auth`. `signedOut` is false when there was nothing stored to clear.
public struct SignedOut: Codable, Hashable, Sendable {
    public var server: String
    public var signedOut: Bool
}

/// `POST /usage/reset`.
public struct UsageReset: Codable, Hashable, Sendable {
    public var ok: Bool
    public var since: String
}

// MARK: - The one request shape that carries a command line

/// The body of `POST /servers` — declaring a new server.
///
/// This is the **only** type in the client that carries `command`, `args` and `env`, and it is
/// deliberately a separate type from `ServerPatch` rather than a superset of it. Adding a server
/// is an explicit act with its own surface; editing one is not allowed to become that act by
/// gaining a field. Keeping them unrelated means no future edit can widen a patch into an
/// installer, because there is no shared shape to widen.
public struct NewServer: Codable, Hashable, Sendable {
    public var name: String
    public var command: String?
    public var args: [String]?
    public var env: [String: String]?
    public var cwd: String?
    public var url: String?
    public var headers: [String: String]?
    public var type: String?
    public var oauth: Bool?
    public var projects: [String]?
    public var warm: Bool?

    public init(
        name: String,
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        cwd: String? = nil,
        url: String? = nil,
        headers: [String: String]? = nil,
        type: String? = nil,
        oauth: Bool? = nil,
        projects: [String]? = nil,
        warm: Bool? = nil
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.cwd = cwd
        self.url = url
        self.headers = headers
        self.type = type
        self.oauth = oauth
        self.projects = projects
        self.warm = warm
    }
}
