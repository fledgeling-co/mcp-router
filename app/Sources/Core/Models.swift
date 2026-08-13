import Foundation

// Codable mirrors of the router's control API. Every field here exists on the wire;
// nothing is computed on this side that the router could have told us, because a
// number the app invents is a number nobody can check.

struct ServerAuth: Codable, Hashable {
    var supported: Bool
    var authorized: Bool
    var authorizedAt: String?
    var pendingUrl: String?
}

struct ServerUsage: Codable, Hashable {
    var calls: Int
    var errors: Int
    var firstSeen: String?
    var lastUsed: String?
    var projects: [String: Int]

    enum CodingKeys: String, CodingKey { case calls, errors, firstSeen, lastUsed, projects }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        calls = try c.decodeIfPresent(Int.self, forKey: .calls) ?? 0
        errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
        firstSeen = try c.decodeIfPresent(String.self, forKey: .firstSeen)
        lastUsed = try c.decodeIfPresent(String.self, forKey: .lastUsed)
        projects = try c.decodeIfPresent([String: Int].self, forKey: .projects) ?? [:]
    }
}

struct Placard: Codable, Hashable {
    var reason: String
    var substitute: String?
    var until: String?
}

struct PendingChange: Codable, Hashable {
    var seenAt: String
    var count: Int
}

struct MCPServer: Codable, Hashable, Identifiable {
    var name: String
    var transport: String
    var state: String
    /// Calls awaiting a response right now. This, and only this, blocks the reaper.
    var inFlight: Int
    /// Calls this process has answered since it started. A lifetime counter, not work
    /// outstanding — the two were the same field until they were separated, which made
    /// an idle server look permanently busy.
    var callsServed: Int
    var idleSec: Int
    var command: String?
    var args: [String]?
    var url: String?
    var envKeys: [String]?
    var headerKeys: [String]?
    var tools: Int
    var toolNames: [String]
    var indexedAt: String?
    var indexError: String?
    var projects: [String]
    var warm: Bool
    var placard: Placard?
    var pendingChange: PendingChange?
    var auth: ServerAuth
    var usage: ServerUsage

    var id: String { name }
    var isRunning: Bool { state == "running" }
    var isStarting: Bool { state == "starting" }
    var isStdio: Bool { transport == "stdio" }
    var neverUsed: Bool { usage.calls == 0 }

    /// A server needing a decision from the user. This is the whole of what the menu
    /// bar is allowed to light up for; see `MenuBarIcon` for why that list is short.
    var needsAttention: Bool {
        pendingChange != nil || indexError != nil || (auth.supported && !auth.authorized)
    }
}

struct ServersResponse: Codable {
    var port: Int
    var idleMs: Int
    var since: String
    var servers: [MCPServer]
}

struct CallRecord: Codable, Hashable, Identifiable {
    var ts: String
    var server: String
    var tool: String
    var ok: Bool
    var ms: Int
    var cold: Bool
    var pid: Int?
    var cwd: String?
    var project: String?
    var client: String?
    var err: String?

    // The router does not number its records, and two calls can share a millisecond,
    // so identity is composed rather than taken. A UUID would be worse: it changes on
    // every decode and the list would animate on every refresh.
    var id: String { "\(ts)|\(server)|\(tool)|\(pid ?? 0)" }

    var date: Date { ts.asDate ?? .distantPast }
}

struct UsageResponse: Codable {
    var since: String
    var records: [CallRecord]
}

struct ProjectUse: Codable, Hashable {
    var cwd: String
    var project: String?
    var calls: Int
}

struct ServerSummary: Codable, Hashable, Identifiable {
    var name: String
    var calls: Int
    var errors: Int
    var firstSeen: String?
    var lastUsed: String?
    var projectNames: [ProjectUse]
    var id: String { name }
}

struct SummaryResponse: Codable {
    var since: String
    var servers: [ServerSummary]
}

struct ToolChange: Codable, Hashable, Identifiable {
    struct Shape: Codable, Hashable {
        var description: String?
        var schema: String?
    }
    var kind: String
    var name: String
    var before: Shape?
    var after: Shape?
    var invisible: [String]?
    var id: String { "\(kind)|\(name)" }
}

struct ChangesResponse: Codable {
    var server: String
    var pending: Bool
    var seenAt: String?
    var changes: [ToolChange]
}

struct RegistryInstall: Codable, Hashable {
    struct Requirement: Codable, Hashable {
        var name: String
        var description: String?
        var isSecret: Bool?
    }
    var type: String
    var command: String?
    var args: [String]?
    var url: String?
    var requires: [Requirement]?
}

struct RegistryEntry: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var displayName: String
    var description: String
    var source: String
    var repository: String?
    var version: String?
    var updatedAt: String?
    var useCount: Int?
    var verified: Bool?
    var iconUrl: String?
    var stars: Int?
    var forks: Int?
    var pushedAt: String?
    var archived: Bool?
    var install: RegistryInstall?
    var installed: Bool?
}

struct RegistryResponse: Codable {
    struct Sources: Codable { var official: Int; var smithery: Int; var merged: Int }
    var results: [RegistryEntry]
    var sources: Sources
    var warnings: [String]
}

struct AuthStart: Codable {
    var server: String
    var authorizationUrl: String
}

/// What the app is allowed to hand the router when installing.
///
/// Typed rather than a free-form dictionary, for two reasons. It is `Sendable`, so it
/// can cross into the client actor without a race; and it makes the surface explicit —
/// a command, its arguments, its environment, or a URL. There is no field here for
/// anything else, so there is no path by which a registry entry's contents become part
/// of the request unexamined.
struct InstallSpec: Codable, Sendable {
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    /// "http" or "sse" for a remote server; omitted for stdio.
    var type: String?

    var isEmpty: Bool { command == nil && url == nil }
}

// `ISO8601DateFormatter` is a reference type and not Sendable, so a shared static one
// is a data race waiting to happen the moment the SSE stream and a refresh decode at
// the same time. `Date.ISO8601FormatStyle` is a value type and Sendable, so two of them
// can be held here safely — one for the router's usual fractional-second stamps, one
// for the whole-second form some fields use.
private let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let isoWhole = Date.ISO8601FormatStyle()

extension String {
    /// "2026-08-13T09:47:26.946Z" -> a Date, tolerating a missing fractional part.
    var asDate: Date? {
        (try? isoFractional.parse(self)) ?? (try? isoWhole.parse(self))
    }
}
