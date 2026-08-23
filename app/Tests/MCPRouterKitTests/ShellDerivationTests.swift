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
    ///
    /// **The Inbox assertion below got stronger in M6, not weaker.** Inbox now has a `badgeSource`,
    /// so it no longer falls into the loop over sourceless destinations — and the explicit line
    /// asserting it produces nothing from `[MCPServer]` is now the load-bearing one: it says the
    /// inbox badge is *not* derived from server data, which is exactly the fabrication that would
    /// occur if someone wired `.queuedFromPhone` to a plausible-looking server field.
    @Test("only Servers and Cleanup can produce a badge from server data, whatever they are handed")
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
            // **`Settings…` joined at M15, and it is a reading rather than a reclassification.**
            // Declaring a `Settings` scene makes macOS contribute the item at `⌘,` on its own; the
            // app also declaring one put two items with one spelling and one chord in the app menu,
            // measured over the accessibility plane on the running build on 2026-08-22. So the app
            // declares none, and this is where that fact is pinned.
            "Settings…",
            "Close",
            "Undo", "Redo", "Cut", "Copy", "Paste", "Select All",
            "Minimize", "Zoom", "Bring All to Front"
        ]
        #expect(system == expected)
        #expect(MenuCommand.appDeclared.count == MenuCommand.allCases.count - expected.count)
    }

    /// **Every menu item is Title Case, and this used to assert the opposite.**
    ///
    /// It read *"no command the app declares is title case except where it names the product"*, and
    /// it was green while the menu bar carried `Hide Others` directly above `Add server…` — because
    /// it only ever looked at the app's thirteen and the kit's fourteen were exempted by
    /// `appDeclared`. The exemption was the evidence: `DESIGN.md`'s header says the macOS 27 kit
    /// wins where it and the document disagree, Apple's HIG specifies title-style capitalization
    /// for menu items, and six titles were already spelled the kit's way because the app cannot
    /// rename them. M20 converted the rest and §6 records the menu bar as its one named exception.
    ///
    /// This is inverted rather than deleted, and it is **stricter** than what it replaced: the old
    /// form only caught a capital where it wanted lower case, so `Add server…` and `Add SERVER…`
    /// were equally fine. This catches both directions — a word that should be capitalised and is
    /// not, and a minor word that should not be and is.
    ///
    /// It runs over `allCases` rather than `appDeclared`, so the kit's own strings are held to the
    /// same rule they are the evidence for. If one of them ever fails here, the kit has changed and
    /// the measurement in `spec-M1.md` is what needs re-taking — not this list.
    @Test("every menu item is Title Case, including the ones macOS spells")
    func menuTitlesAreTitleCase() {
        // The words title case leaves lower unless they lead or close: articles, coordinating
        // conjunctions and short prepositions. Apple's own menus follow this — `Bring All to
        // Front`, `Paste and Match Style`.
        let minor: Set = [
            "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "nor",
            "of", "on", "or", "the", "to", "with"
        ]
        // Spelled by their owner rather than by the rule. `iPhone` is Apple's and starts lower.
        let literal: Set = ["iPhone"]

        for command in MenuCommand.allCases {
            let words = command.title.split(separator: " ").map(String.init)
            for (index, word) in words.enumerated() {
                let bare = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard !bare.isEmpty, !literal.contains(bare) else { continue }
                let first = String(bare.prefix(1))
                let leadsOrCloses = index == 0 || index == words.count - 1
                if !leadsOrCloses, minor.contains(bare.lowercased()) {
                    #expect(
                        first == first.lowercased(),
                        "\(command.title) capitalises the minor word '\(bare)'"
                    )
                } else {
                    #expect(
                        first == first.uppercased(),
                        "\(command.title) leaves '\(bare)' lower case"
                    )
                }
            }
        }
    }

    /// The menu bar is the **only** surface that takes Title Case.
    ///
    /// §6's exception is named and bounded, so this is the boundary: a button that says the same
    /// words as a menu item stays sentence case. `Add Marketplace…` is the worked example — it was
    /// one literal shared between the menu item and two Skills buttons until M20, and one string
    /// could not be both once the menu moved.
    @Test("a button saying a menu item's words keeps sentence case")
    func buttonsDidNotFollowTheMenuIntoTitleCase() {
        #expect(SkillPresentation.marketplacesAction == "Add marketplace…")
        #expect(MenuCommand.addMarketplace.title == "Add Marketplace…")
        #expect(MenuCommand.addMarketplace.title != SkillPresentation.marketplacesAction)
    }

    /// The Help command carries no shortcut, and that is a measurement rather than an omission:
    /// `⌘?` is `⇧⌘/`, which macOS reserves for the Help menu's own search field. Binding `⌘J` to the
    /// same item in the same menu produced a shortcut immediately, so the menu is not the problem.
    @Test("the Help command claims no shortcut, because the one it wanted is reserved")
    func helpClaimsNoReservedShortcut() {
        #expect(MenuCommand.help.shortcut == nil)
    }
}
