import Foundation
import Testing
@testable import MCPRouterKit

/// A12–A15: the plate is derived, accumulating, honest about what it cannot distinguish, and never
/// renders an assurance nobody established.
@Suite("The capability plate — A12 to A15")
struct CapabilityPlateTests {
    private func install(
        _ type: ServerTransport,
        command: String? = nil,
        args: [String]? = nil,
        url: String? = nil,
        secret: Bool? = nil
    ) -> RegistryInstall {
        RegistryInstall(
            type: type,
            command: command,
            args: args,
            url: url,
            requires: secret.map {
                [RegistryRequirement(name: "Authorization", description: "key", isSecret: $0)]
            }
        )
    }

    // MARK: - The five derivations

    @Test("a stdio entry says a program runs on your Mac, and wants a decision")
    func stdioLine() throws {
        let lines = CapabilityPlate.lines(
            install: install(.stdio, command: "npx", args: ["-y", "thing"]),
            archived: nil
        )
        let line = try #require(lines.first)
        #expect(line.kind == .runsLocally)
        #expect(line.severity == .attention)
        #expect(line.text.contains("your own access"))
    }

    /// A13: the remote line **names the host**, because for a remote MCP server the decision that
    /// matters is that tool arguments leave the machine. Treating remote as the quiet case inverts
    /// the real risk on a surface whose job is queueing things the user has not examined.
    @Test("a remote entry names the host its requests go to")
    func remoteNamesTheHost() throws {
        let lines = CapabilityPlate.lines(
            install: install(.http, url: "https://server.example.com/mcp"),
            archived: nil
        )
        let line = try #require(lines.first)
        #expect(line.kind == .remote)
        #expect(line.text.contains("server.example.com"))
        #expect(!line.text.contains("{host}"), "the substitution never ran")
    }

    /// A line that names the wrong host is worse than one admitting it does not know which host,
    /// because the whole point of the line is telling the user where their arguments go.
    @Test("an unparseable url admits it rather than guessing a host")
    func unparseableURLAdmitsIt() throws {
        let lines = CapabilityPlate.lines(install: install(.sse, url: "not a url"), archived: nil)
        let line = try #require(lines.first)
        #expect(line.text.contains("neither index published"))
        #expect(CapabilityPlate.host(of: "not a url") == nil)
    }

    /// A13: remote is a **fact** line, not an amber one — the user is queueing for review, not
    /// granting access, and an amber block that fires on everything stops meaning anything.
    @Test("the remote line is a fact, so amber keeps its meaning")
    func remoteIsAFact() throws {
        let lines = CapabilityPlate.lines(
            install: install(.http, url: "https://example.com/mcp"),
            archived: nil
        )
        #expect(try #require(lines.first).severity == .fact)
        #expect(CapabilityPlate.severity(of: lines) == .fact)
    }

    @Test("a required secret adds a credential line that wants a decision")
    func credentialLine() throws {
        let lines = CapabilityPlate.lines(
            install: install(.stdio, command: "npx", secret: true),
            archived: nil
        )
        let credential = try #require(lines.first { $0.kind == .credential })
        #expect(credential.severity == .attention)
    }

    /// A non-secret requirement is not a credential: it is configuration, and marking it amber
    /// would spend the decision colour on something nobody has to decide.
    @Test("a requirement that is not secret adds no credential line")
    func nonSecretRequirementIsNotACredential() {
        let lines = CapabilityPlate.lines(
            install: install(.stdio, command: "npx", secret: false),
            archived: nil
        )
        #expect(!lines.contains { $0.kind == .credential })
    }

    // MARK: - A14

    /// Every Smithery-hosted install declares a required `Authorization` unconditionally, so within
    /// that subset the line distinguishes nothing. The difference between a warning and noise is
    /// whether it admits when it carries no signal.
    @Test("a Smithery-hosted credential says the key is Smithery's and sets nothing apart")
    func smitheryCredentialAdmitsItCarriesNoSignal() throws {
        let lines = CapabilityPlate.lines(
            install: install(.http, url: "https://server.smithery.ai/x/mcp", secret: true),
            archived: nil
        )
        let credential = try #require(lines.first { $0.kind == .credential })
        #expect(credential.copyKey == .plate(.credentialSmithery))
        #expect(credential.text.contains("Smithery API key"))
        #expect(credential.text.contains("doesn't set this server apart"))
    }

    @Test("a credential hosted anywhere else uses the plain line")
    func nonSmitheryCredentialIsPlain() throws {
        let lines = CapabilityPlate.lines(
            install: install(.http, url: "https://example.com/mcp", secret: true),
            archived: nil
        )
        let credential = try #require(lines.first { $0.kind == .credential })
        #expect(credential.copyKey == .plate(.credential))
    }

    // MARK: - A13 accumulation

    /// The derivations are **not** mutually exclusive, and the code must not pretend they are. A
    /// stdio entry that also needs a secret and is also archived is exactly the entry whose plate
    /// has to say all three.
    @Test("a stdio entry that needs a secret and is archived renders all three lines, in order")
    func linesAccumulateInTableOrder() {
        let lines = CapabilityPlate.lines(
            install: install(.stdio, command: "npx", secret: true),
            archived: true
        )
        #expect(lines.map(\.kind) == [.runsLocally, .credential, .archived])
        #expect(CapabilityPlate.severity(of: lines) == .attention)
    }

    @Test("the plate takes attention if any single line does, and fact when none does")
    func severityPrecedence() {
        let facts = CapabilityPlate.lines(
            install: install(.http, url: "https://example.com/mcp"),
            archived: true
        )
        #expect(CapabilityPlate.severity(of: facts) == .fact)
        #expect(CapabilityPlate.severity(of: []) == .fact)
    }

    // MARK: - A17

    @Test("no descriptor renders the one line the disabled commit points at")
    func noDescriptorLine() throws {
        let lines = CapabilityPlate.lines(install: nil, archived: nil)
        #expect(lines.map(\.kind) == [.unknownTransport])
        #expect(try #require(lines.first).text.contains("Neither index says how this server runs"))
        #expect(CapabilityPlate.invocation(install: nil) == nil)
    }

    @Test("an archived entry with no descriptor still says it is archived")
    func archivedSurvivesTheNoDescriptorPath() {
        let lines = CapabilityPlate.lines(install: nil, archived: true)
        #expect(lines.map(\.kind) == [.unknownTransport, .archived])
    }

    // MARK: - A12: the literal invocation

    /// The evidence the plain-language lines interpret. A string for a human to read: nothing on
    /// this phone executes it, and nothing on this phone can.
    @Test("the invocation is the entry's own command and arguments, joined")
    func invocationForStdio() {
        let invocation = CapabilityPlate.invocation(
            install: install(.stdio, command: "npx", args: ["-y", "obsidian-github-mcp"])
        )
        #expect(invocation == "npx -y obsidian-github-mcp")
    }

    @Test("a remote invocation is the url, and a stdio entry with no command shows nothing")
    func invocationEdges() {
        #expect(CapabilityPlate.invocation(
            install: install(.sse, url: "https://example.com/mcp")
        ) == "https://example.com/mcp")
        // No command means there is nothing true to show, and inventing one would be worse.
        #expect(CapabilityPlate.invocation(install: install(.stdio)) == nil)
    }

    // MARK: - A15

    /// `verified` is Smithery's claim about itself, the router verifies nothing, and a bare
    /// "Verified" chip would display an assurance nobody established. There is no key for it.
    @Test("no copy key renders a verified claim")
    func verifiedIsNeverRendered() {
        for key in DiscoverCopy.Key.allCases {
            let entry = DiscoverCopy.entry(key)
            let text = ((entry.headline ?? "") + entry.body + (entry.actionLabel ?? "")).lowercased()
            #expect(!text.contains("verified"), "\(key.name) renders a verification claim")
        }
    }

    /// A15: the chips are exactly source, archived, and stars where present.
    @Test("the fact chips are the three enumerated, and each names its index")
    func factChips() {
        #expect(DiscoverCopy.entry(.detail(.chipSourceOfficial)).body == "Official registry")
        #expect(DiscoverCopy.entry(.detail(.chipSourceSmithery)).body == "Smithery")
        #expect(DiscoverCopy.entry(.detail(.chipSourceBoth)).body == "Both registries")
        #expect(DiscoverCopy.entry(.detail(.chipArchived)).body == "Archived")
    }
}
