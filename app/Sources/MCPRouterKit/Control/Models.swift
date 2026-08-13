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
    public var needsAttention: Bool {
        pendingChange != nil || (auth.supported && !auth.authorized) || indexError != nil
    }
}

public struct ServersResponse: Codable, Hashable, Sendable {
    public var port: Int
    public var idleMs: Int
    public var since: String
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
