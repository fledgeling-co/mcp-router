/// Authored long-content fixtures, separate from captured router responses.
enum CleanupRowFixtures {
    static var skillsResponse: SkillsResponse {
        SkillsResponse(skills: skills, clients: SkillFixtures.clients)
    }

    static var skills: [Skill] {
        var skills = SkillFixtures.uninstalled
        skills[0].provenance = SkillProvenance(
            firstSeenSource: "github:acme-tools/"
                + "agent-productivity-marketplace-with-shared-team-capabilities",
            currentSource: "github:maintained-tools/"
                + "agent-productivity-marketplace-with-shared-team-capabilities",
            firstSeenAt: "2026-01-09T09:20:00.000Z"
        )
        return skills
    }

    static func serversResponse(_ response: ServersResponse) -> ServersResponse {
        var response = response
        response.servers = Array(response.servers.prefix(1)).map { server in
            var copy = server
            copy.indexError = """
            spawn ENOENT: the configured helper was not found at \
            /opt/team-tools/agent-productivity-marketplace/shared-capabilities/bin/registry-helper. \
            The router could not inspect any tools, so it has no evidence that this declaration is unused. \
            Check the installed command path before removing this server.
            """
            return copy
        }
        response.pendingAuth = nil
        return response
    }
}
