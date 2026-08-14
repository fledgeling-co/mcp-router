import Foundation
import Testing
@testable import MCPRouterKit

/// The derivations the shell's views read, tested where a view cannot be.
///
/// Everything here answers a clause that would otherwise rest on reading the view's source: which
/// state the readout is in, which rows may carry a badge and what it counts, and which commands the
/// app is actually responsible for putting in the menu bar.
@Suite("Shell derivations")
struct ShellDerivationTests {
    static func servers(from fixture: String) async throws -> [MCPServer] {
        try FixtureControlAPIClient.decodeFixture(fixture, as: ServersResponse.self).servers
    }

    static func response(running: Int, declared: Int, notIndexed: Int = 0) async throws -> ServersResponse {
        var base = try FixtureControlAPIClient.decodeFixture("servers", as: ServersResponse.self)
        let template = try #require(base.servers.first)
        base.servers = (0 ..< declared).map { index in
            var server = template
            server.name = "server-\(index)"
            server.state = index < running ? .running : .idle
            server.indexError = index < notIndexed ? "spawn failed" : nil
            return server
        }
        return base
    }

    // MARK: - Which state the readout is in

    @Test("no answer and no failure is loading — not empty, and not a zero")
    func initialStateIsLoading() {
        #expect(ReadoutModel().state == .loading)
    }

    @Test("a failure outranks everything, so no count is presented as current")
    func failureOutranksCounts() async throws {
        let populated = try await ReadoutModel().applying(Self.response(running: 2, declared: 5), at: .now)
        #expect(populated.state == .populated(running: 2, declared: 5))

        let failed = populated.applying(.routerNotRunning, at: .now)
        #expect(failed.state == .failed(.routerNotRunning))
    }

    @Test("a router that declares nothing is empty, which is a different state from loading")
    func emptyIsItsOwnState() async throws {
        let model = try await ReadoutModel().applying(Self.response(running: 0, declared: 0), at: .now)
        #expect(model.state == .empty)
        #expect(model.state != .loading)
    }

    /// §5's Partial: say what arrived and what did not. The count comes from `indexError`, which is
    /// the router's own report — nothing here is inferred from a short list.
    @Test("servers the router could not index put the readout in the partial state")
    func partialComesFromIndexErrors() async throws {
        let model = try await ReadoutModel()
            .applying(Self.response(running: 3, declared: 8, notIndexed: 2), at: .now)
        #expect(model.state == .partial(running: 3, declared: 8, notIndexed: 2))
        #expect(model.notIndexed == 2)
    }

    @Test("a failed poll clears the not-indexed count too, rather than leaving it stale")
    func failureClearsNotIndexed() async throws {
        let model = try await ReadoutModel()
            .applying(Self.response(running: 1, declared: 4, notIndexed: 1), at: .now)
            .applying(.unauthorized, at: .now)
        #expect(model.notIndexed == nil)
        #expect(model.state == .failed(.unauthorized))
    }

    // MARK: - Badges

    /// A13, in the direction that actually goes wrong: someone adds a plausible count to a row.
    @Test("only Servers and Cleanup can produce a badge, whatever they are handed")
    func onlyTwoDestinationsCanBadge() async throws {
        let servers = try await Self.servers(from: "servers")
        for destination in Destination.allCases where destination.badgeSource == nil {
            #expect(
                destination.badgeCount(from: servers) == nil,
                "\(destination.title) produced a badge from a source it does not have"
            )
        }
        #expect(Destination.skills.badgeCount(from: servers) == nil)
        #expect(Destination.inbox.badgeCount(from: servers) == nil)
    }

    @Test("each badge counts exactly the field its source names")
    func badgeCountsMatchTheirSource() async throws {
        let servers = try await Self.servers(from: "servers")
        #expect(Destination.servers.badgeCount(from: servers)
            == positiveOrNil(servers.filter(\.needsAttention).count))
        #expect(Destination.cleanup.badgeCount(from: servers)
            == positiveOrNil(servers.filter(\.neverUsed).count))
    }

    /// A18 again, from the badge's side: no observation means no badge, never a considered zero.
    @Test("no servers at all means no badge, which is not the same as a badge of zero")
    func absentServersProduceNoBadge() {
        #expect(Destination.servers.badgeCount(from: nil) == nil)
        #expect(Destination.cleanup.badgeCount(from: nil) == nil)
    }

    @Test("a genuine zero renders no badge either — an empty badge is noise, not information")
    func zeroRendersNoBadge() {
        #expect(Destination.servers.badgeCount(from: []) == nil)
    }

    private func positiveOrNil(_ count: Int) -> Int? {
        count > 0 ? count : nil
    }

    // MARK: - Who puts each command in the menu bar

    /// The split matters for A19: "no extras" can only be checked over items the app declares,
    /// because macOS contributes a great many the inventory does not list.
    @Test("every command is either the app's or the system's, and the split is the measured one")
    func systemProvidedSplitIsExact() {
        let system = Set(MenuCommand.allCases.filter(\.isSystemProvided).map(\.title))
        let expected: Set = [
            "Hide MCP Router", "Hide Others", "Show All", "Quit MCP Router",
            "Close",
            "Undo", "Redo", "Cut", "Copy", "Paste", "Select All",
            "Minimize", "Zoom", "Bring All to Front"
        ]
        #expect(system == expected)
        #expect(MenuCommand.appDeclared.count == MenuCommand.allCases.count - expected.count)
    }

    /// The six titles that are title case are exactly the system's, and no app-declared command
    /// borrowed the spelling. §6's sentence case still governs everything the app writes.
    @Test("no command the app declares is title case except where it names the product")
    func appDeclaredCommandsAreSentenceCase() {
        for command in MenuCommand.appDeclared {
            let words = command.title.split(separator: " ").dropFirst()
            for word in words {
                let first = word.first.map(String.init) ?? ""
                let isProductName = ["MCP", "Router", "iPhone"].contains(String(word))
                    || word.hasPrefix("Router")
                #expect(
                    first == first.lowercased() || isProductName,
                    "\(command.title) capitalises '\(word)' mid-sentence"
                )
            }
        }
    }

    /// The Help command carries no shortcut, and that is a measurement rather than an omission:
    /// `⌘?` is `⇧⌘/`, which macOS reserves for the Help menu's own search field. Binding `⌘J` to the
    /// same item in the same menu produced a shortcut immediately, so the menu is not the problem.
    @Test("the Help command claims no shortcut, because the one it wanted is reserved")
    func helpClaimsNoReservedShortcut() {
        #expect(MenuCommand.help.shortcut == nil)
    }
}
