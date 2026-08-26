import Foundation
@testable import MCPRouterKit

/// The wire values the check suites are asserted against, held in one namespace.
///
/// Extracted from `CheckTests` for the reason `ShellTestSupport` exists: two suites over the same
/// eleven checks would otherwise each carry their own `server(...)`, and two builders that drift
/// apart make the same assertion mean two different things depending on which file it lives in.
enum CheckFixtures {
    static func server(
        name: String = "alpha",
        tools: Int = 3,
        indexedAt: String? = "2026-08-01T10:00:00Z",
        indexError: String? = nil,
        hash: String? = "abc123",
        calls: Int = 5,
        errors: Int = 0,
        callsServed: Int = 5,
        authSupported: Bool = false,
        authAuthorized: Bool = false,
        placard: Placard? = nil,
        pendingChange: PendingChange? = nil,
        disabled: Bool = false
    ) -> MCPServer {
        MCPServer(
            name: name,
            transport: .stdio,
            state: .idle,
            inFlight: 0,
            callsServed: callsServed,
            idleSec: 0,
            command: "node",
            args: ["server.js"],
            cwd: nil,
            url: nil,
            envKeys: nil,
            headerKeys: nil,
            hash: hash,
            tools: tools,
            toolNames: [],
            indexedAt: indexedAt,
            indexError: indexError,
            projects: [],
            warm: false,
            disabled: disabled,
            placard: placard,
            pendingChange: pendingChange,
            auth: ServerAuth(supported: authSupported, authorized: authAuthorized),
            usage: ServerUsage(calls: calls, errors: errors)
        )
    }

    static func client(
        _ id: String,
        supports: Bool = true,
        status: SkillClientStatus = .read
    ) -> SkillClient {
        SkillClient(id: id, displayName: id.capitalized, supportsSkills: supports, status: status)
    }

    static func skill(
        name: String = "pr-summariser",
        description: String? = "Summarises a pull request",
        path: String = "/skills/pr-summariser",
        source: SkillSource = .plugin(PluginOrigin(
            plugin: "review-kit",
            marketplace: "fledgeling",
            pluginVersion: "0.4.1"
        )),
        presence: [String: SkillPresence] = ["claude": .present],
        held: HeldVersion? = nil,
        provenance: SkillProvenance? = nil
    ) -> Skill {
        Skill(
            name: name,
            description: description,
            path: path,
            source: source,
            presence: presence,
            held: held,
            provenance: provenance
        )
    }
}
