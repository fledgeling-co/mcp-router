import Foundation
import Testing
@testable import MCPRouterKit

/// M5 · Discover — what an entry will actually do, and what may be declared from it.
///
/// Split from `RegistryPresentationTests` for length. Grouped because every clause here is about
/// the *install block*: reading it into a plain-language statement, deciding whether the entry may
/// be added at all, and building the narrow declaration that is sent if it is.
@Suite("M5 · registry capability")
struct RegistryCapabilityTests {
    // MARK: - Fixtures

    /// A row, built by naming only what the test is about.
    ///
    /// `id` carries the provenance the merge actually preserves, so a test that wants a
    /// Smithery-based row says so with the prefix rather than by setting `source`, which is the very
    /// field that cannot be trusted.
    private func entry(
        id: String = "github",
        name: String = "github",
        displayName: String = "GitHub",
        description: String = "",
        source: RegistryEntry.Source = .official,
        repository: String? = nil,
        version: String? = nil,
        updatedAt: String? = nil,
        useCount: Int? = nil,
        verified: Bool? = nil,
        stars: Int? = nil,
        pushedAt: String? = nil,
        archived: Bool? = nil,
        install: RegistryInstall? = nil,
        installed: Bool? = nil
    ) -> RegistryEntry {
        RegistryEntry(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            source: source,
            repository: repository,
            version: version,
            updatedAt: updatedAt,
            useCount: useCount,
            verified: verified,
            stars: stars,
            pushedAt: pushedAt,
            archived: archived,
            install: install,
            installed: installed
        )
    }

    private func response(
        _ results: [RegistryEntry],
        merged: Int? = nil,
        warnings: [String] = []
    ) -> RegistrySearchResponse {
        RegistrySearchResponse(
            results: results,
            sources: RegistrySources(
                official: results.count,
                smithery: results.count,
                merged: merged ?? results.count
            ),
            warnings: warnings
        )
    }

    private func smithery(_ suffix: String) -> String {
        "smithery:\(suffix)"
    }

    // MARK: - A6 · the capability statement is a reading of the install block

    @Test("the three install shapes each get their own statement")
    func capabilityStatementCoversEveryShape() {
        let stdio = RegistryCapability.statement(for: entry(install: RegistryInstall(
            type: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-github"]
        )))
        #expect(stdio.headline == "Runs a program on this Mac")
        #expect(!stdio.isRemote)
        // Separate tokens, never joined: a joined line reads as a shell command, and an entry whose
        // args contain spaces would render as a different command from the one that will run.
        #expect(stdio.argv == ["npx", "-y", "@modelcontextprotocol/server-github"])

        let http = RegistryCapability.statement(for: entry(install: RegistryInstall(
            type: .http,
            url: "https://server.smithery.ai/github/mcp"
        )))
        #expect(http.headline == "Connects to server.smithery.ai")
        #expect(http.isRemote)
        #expect(http.argv.isEmpty, "nothing runs locally, so there is no argv to show")

        // Absent entirely — a real case, since `install` is optional on the wire.
        let absent = RegistryCapability.statement(for: entry(install: nil))
        #expect(absent.headline == "Neither index says how to run this")
        #expect(absent.argv.isEmpty)
    }

    /// A hand-rolled parse is how `https://api.smithery.ai@evil.io/` gets read as the trusted host.
    @Test("the host is the URL's authority, never a substring of it")
    func hostParsingIsNotStringHandling() {
        #expect(RegistryCapability.host(of: "https://api.smithery.ai@evil.io/mcp") == "evil.io")
        #expect(RegistryCapability.host(of: "https://api.trusted.com.evil.io/x") == "api.trusted.com.evil.io")
        #expect(RegistryCapability.host(of: "not a url") == nil)
        #expect(RegistryCapability.host(of: nil) == nil)
        #expect(RegistryCapability.host(of: "") == nil)
    }

    @Test("a newline in an argument cannot inject a second line into the command block")
    func argvTokensAreSanitised() {
        let statement = RegistryCapability.statement(for: entry(install: RegistryInstall(
            type: .stdio,
            command: "npx",
            args: ["-y\nrm -rf /", "ok"]
        )))
        #expect(statement.argv == ["npx", "-yrm -rf /", "ok"])
        #expect(!statement.argv.contains { $0.contains("\n") })
    }

    // MARK: - A5 · detail-then-install, and the declaration that is built

    @Test("the ellipsis rule is a decision about the entry, not a constant")
    func actionLabelFollowsTheEllipsisRule() {
        let bare = entry(install: RegistryInstall(type: .stdio, command: "npx"))
        #expect(RegistryCapability.action(for: bare).label == "Add GitHub")
        #expect(!RegistryCapability.action(for: bare).revealsRequirements)

        let asks = entry(install: RegistryInstall(
            type: .stdio,
            command: "npx",
            requires: [RegistryRequirement(name: "GITHUB_TOKEN", isSecret: true)]
        ))
        #expect(RegistryCapability.action(for: asks).label == "Add GitHub\u{2026}")
        #expect(RegistryCapability.action(for: asks).revealsRequirements)
        // Once the fields are on screen the button commits, so it loses its ellipsis.
        let revealed = RegistryCapability.action(for: asks, requirementsRevealed: true)
        #expect(revealed.label == "Add GitHub")
        #expect(!revealed.revealsRequirements)
    }

    @Test("a disabled action dims with a stated reason rather than disappearing")
    func disabledActionsCarryTheirReason() throws {
        let already = RegistryCapability.action(for: entry(installed: true))
        #expect(!already.isEnabled)
        #expect(already.label == "Added")
        #expect(try #require(already.disabledReason).contains("github"))

        let unrunnable = RegistryCapability.action(for: entry(install: nil))
        #expect(!unrunnable.isEnabled)
        #expect(unrunnable.disabledReason != nil)

        // In flight: the prominent button must not stay live across the round trip, or a second
        // press sends a second `add` for the same entry.
        let inFlight = RegistryCapability.action(
            for: entry(install: RegistryInstall(type: .stdio, command: "npx")),
            isInstalling: true
        )
        #expect(!inFlight.isEnabled)
    }

    /// The name is the entry's `name`, never its `displayName` — the field an index lets an author
    /// choose freely — and only the values this entry actually asked for are carried.
    @Test("the declaration takes the wire name and drops values the entry never asked for")
    func declarationIsNarrow() throws {
        let row = entry(
            name: "github",
            displayName: "Totally Not Evil",
            install: RegistryInstall(
                type: .stdio,
                command: "npx",
                args: ["-y", "server"],
                requires: [RegistryRequirement(name: "GITHUB_TOKEN", isSecret: true)]
            )
        )
        let declaration = try #require(RegistryCapability.declaration(
            for: row,
            values: ["GITHUB_TOKEN": "t0ken", "SOMETHING_ELSE": "leaked"]
        ))
        #expect(declaration.name == "github")
        #expect(declaration.env?["GITHUB_TOKEN"] == "t0ken")
        #expect(
            declaration.env?["SOMETHING_ELSE"] == nil,
            "a value the user never saw must not reach the router"
        )

        // No install block means no declaration can be constructed at all.
        #expect(RegistryCapability.declaration(for: entry(install: nil), values: [:]) == nil)
    }

    @Test("an HTTP entry's values go to headers, and a stdio entry's to env")
    func declarationRoutesValuesByTransport() throws {
        let http = try #require(RegistryCapability.declaration(
            for: entry(install: RegistryInstall(
                type: .http,
                url: "https://server.smithery.ai/x",
                requires: [RegistryRequirement(name: "Authorization")]
            )),
            values: ["Authorization": "Bearer x"]
        ))
        #expect(http.headers?["Authorization"] == "Bearer x")
        #expect(http.env == nil)
    }

    @Test("a requirement with only whitespace counts as missing, not as an empty credential")
    func missingRequirementsIgnoreWhitespace() {
        let row = entry(install: RegistryInstall(
            type: .stdio,
            command: "npx",
            requires: [RegistryRequirement(name: "TOKEN")]
        ))
        // An empty credential makes the server fail with an authentication error that names nothing.
        #expect(RegistryCapability.missingRequirements(for: row, values: ["TOKEN": "   "]).count == 1)
        #expect(RegistryCapability.missingRequirements(for: row, values: ["TOKEN": "x"]).isEmpty)
    }

    @Test("archived is surfaced only where GitHub actually reported it")
    func archivedNoteIsObserved() {
        #expect(RegistryPresentation.archivedNote(for: entry(archived: true)) == "repository archived")
        #expect(RegistryPresentation.archivedNote(for: entry(archived: false)) == nil)
        #expect(RegistryPresentation.archivedNote(for: entry(archived: nil)) == nil)
    }
}
