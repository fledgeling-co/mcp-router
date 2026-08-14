import Foundation
import Testing
@testable import MCPRouterKit

/// The menu bar's rules, which are mostly one rule: the status item must stay quiet enough that a
/// change in it means something.
///
/// Every test here is falsifiable against a constructed servers list rather than a running router,
/// because the conditions being asserted — a server that is held *and* failed to index, twelve
/// servers wanting attention at once — are ones no fixture happens to contain.
@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
    /// A real recorded server, mutated for the case under test. Built from the fixture for the
    /// house reason: a hand-assembled `MCPServer` lets a field drift from the shape the router
    /// actually serves.
    static func server(
        named name: String,
        held: Bool = false,
        authSupported: Bool = false,
        authorized: Bool = true,
        indexError: String? = nil,
        running: Bool = false,
        warm: Bool = false,
        tools: Int = 0
    ) async throws -> MCPServer {
        let source = try await FixtureControlAPIClient(.populated).servers().servers
        #expect(!source.isEmpty, "the populated fixture is empty; the recording changed")
        var server = source[0]
        server.name = name
        server.pendingChange = held ? PendingChange(seenAt: "2026-08-14T09:00:00Z", count: 1) : nil
        server.auth = ServerAuth(
            supported: authSupported,
            authorized: authorized,
            authorizedAt: nil,
            pendingURL: nil
        )
        server.indexError = indexError
        server.state = running ? .running : .idle
        server.warm = warm
        server.tools = tools
        return server
    }

    // MARK: - A11 · the dot appears exactly when something wants a decision

    @Test("the dot is present for each attention cause on its own, and absent for none of them")
    func dotTracksNeedsAttention() async throws {
        let quiet = try await Self.server(named: "quiet")
        #expect(!MenuBarPresentation.statusItemNeedsAttention([quiet]))
        #expect(!MenuBarPresentation.statusItemNeedsAttention([]))

        let held = try await Self.server(named: "held", held: true)
        let unauthorised = try await Self.server(named: "auth", authSupported: true, authorized: false)
        let broken = try await Self.server(named: "broken", indexError: "spawn ENOENT")

        for one in [held, unauthorised, broken] {
            #expect(
                MenuBarPresentation.statusItemNeedsAttention([quiet, one]),
                "\(one.name) should raise the dot"
            )
        }
    }

    // MARK: - A12 · the dot is never --fail

    /// The failure this guards is a tidy-looking edit: someone notices that `indexFailed` tints its
    /// row `--fail` and "simplifies" the status item to use the row's tint. That would put a red
    /// dot in the menu bar for a condition the design deliberately does not distinguish there.
    @Test("the status item's dot is --attn in every case, including a failed index alone")
    func dotIsAlwaysAttention() {
        #expect(MenuBarPresentation.statusItemDotToken == .attention)
        #expect(MenuBarPresentation.statusItemDotToken != .fail)
        #expect(MenuBarPresentation.statusItemDotToken != .live)
        // The row tint may legitimately differ, and does — that is the distinction the popover
        // draws and the bar does not.
        #expect(MenuBarPresentation.AttentionCause.indexFailed.tintToken == .fail)
    }

    // MARK: - A13 · no count in the bar

    @Test("no attention count appears in the status item's dot or its presence")
    func barCarriesNoCount() async throws {
        // The only two values the bar exposes are a Bool and a colour token. There is no count to
        // leak, and this asserts that shape rather than a rendered string: a count could only
        // appear by a new API being added here.
        var many: [MCPServer] = []
        for index in 0 ..< 12 {
            try await many.append(Self.server(named: "s\(index)", held: true))
        }
        #expect(MenuBarPresentation.statusItemNeedsAttention(many))
        #expect(MenuBarPresentation.statusItemDotToken == .attention)
    }

    // MARK: - A14 · the accessibility label

    @Test("the label names the count, and counts servers rather than causes")
    func labelCountsServers() async throws {
        let quiet = try await Self.server(named: "quiet")
        #expect(MenuBarPresentation.statusItemLabel([quiet]) == "MCP Router")
        #expect(MenuBarPresentation.statusItemLabel([]) == "MCP Router")

        let one = try await Self.server(named: "one", held: true)
        #expect(MenuBarPresentation.statusItemLabel([one]) == "MCP Router, 1 item needs a decision")

        // Three problems on one server is one item to look at, not three.
        let triple = try await Self.server(
            named: "triple",
            held: true,
            authSupported: true,
            authorized: false,
            indexError: "spawn ENOENT"
        )
        #expect(MenuBarPresentation.statusItemLabel([triple]) == "MCP Router, 1 item needs a decision")

        let two = try await Self.server(named: "two", indexError: "spawn ENOENT")
        #expect(
            MenuBarPresentation.statusItemLabel([one, two, quiet]) == "MCP Router, 2 items need a decision"
        )
    }

    // MARK: - A19 · each row names its own cause, and precedence holds

    @Test("each cause produces its own sentence")
    func causesHaveDistinctSentences() {
        let sentences = MenuBarPresentation.AttentionCause.allCases.map(\.sentence)
        #expect(Set(sentences).count == sentences.count, "two causes share a sentence")
        #expect(MenuBarPresentation.AttentionCause.heldChange.sentence
            == "changed a tool description — held, not served")
        #expect(MenuBarPresentation.AttentionCause.needsAuthorization.sentence
            == "needs authorising before it can answer")
        #expect(MenuBarPresentation.AttentionCause.indexFailed.sentence
            == "failed to index — will not retry on its own")
    }

    @Test("a server matching every cause reports the held change, and reports it once")
    func heldChangeTakesPrecedence() async throws {
        let triple = try await Self.server(
            named: "triple",
            held: true,
            authSupported: true,
            authorized: false,
            indexError: "spawn ENOENT"
        )
        let rows = MenuBarPresentation.attentionRows(from: [triple])
        #expect(rows.count == 1, "one server is one row, whatever it is wrong about")
        #expect(rows[0].cause == .heldChange)
        #expect(rows[0].opensHeldChangeSheet)
    }

    @Test("a quiet server produces no row at all")
    func quietServersAreAbsentFromTheBand() async throws {
        let quiet = try await Self.server(named: "quiet")
        #expect(MenuBarPresentation.attentionRows(from: [quiet]).isEmpty)
    }

    /// A25's half of the routing rule, asserted on the value rather than on the view.
    @Test("only the held change opens a sheet")
    func onlyHeldChangeOpensASheet() {
        #expect(MenuBarPresentation.AttentionCause.heldChange.opensHeldChangeSheet)
        #expect(!MenuBarPresentation.AttentionCause.needsAuthorization.opensHeldChangeSheet)
        #expect(!MenuBarPresentation.AttentionCause.indexFailed.opensHeldChangeSheet)
    }

    // MARK: - A16 · the header agrees with the window

    @Test("running is derived the same way the readout derives it, for one list of servers")
    func countsAgreeWithTheReadout() async throws {
        var servers: [MCPServer] = []
        for index in 0 ..< 8 {
            try await servers.append(Self.server(named: "s\(index)", running: index < 3, tools: 5))
        }
        let counts = MenuBarPresentation.counts(from: servers)
        let readout = ReadoutModel().applying(servers, at: Date())

        #expect(counts.running == 3)
        #expect(counts.running == readout.running, "the popover and the window disagree about running")
        #expect(counts.idle == 5)
        #expect(counts.tools == 40)
    }

    // MARK: - A21 · six rows, and one place that says six

    @Test("the recent-call limit is six and is a single constant")
    func recentCallLimitIsSix() {
        #expect(MenuBarPresentation.recentCallLimit == 6)
    }

    // MARK: - the instrument columns

    @Test("duration reads in milliseconds below a second and in seconds above it")
    func durationCrossesAtOneSecond() async throws {
        let source = try await FixtureControlAPIClient(.populated).usage().records
        #expect(!source.isEmpty, "the populated fixture has no calls; the recording changed")
        var record = source[0]

        record.ms = 999
        #expect(MenuBarPresentation.duration(of: record) == "999ms")
        record.ms = 1000
        #expect(MenuBarPresentation.duration(of: record) == "1.0s")
        record.ms = 1240
        #expect(MenuBarPresentation.duration(of: record) == "1.2s")
    }

    @Test("an unparseable timestamp reads as an em dash rather than as a plausible time")
    func unparseableTimestampIsNotFaked() async throws {
        let source = try await FixtureControlAPIClient(.populated).usage().records
        var record = source[0]
        record.ts = "not a date"
        #expect(MenuBarPresentation.age(of: record, now: Date()) == "—")
    }

    // MARK: - A17 · there is no skills count, structurally

    /// `Counts` has three fields and none of them is skills. The prototype's popover shows a skills
    /// figure and `ControlAPIClient` has no skills endpoint, so the number would be invented.
    /// Asserted as a reflection over the type because that is what survives someone adding a field.
    @Test("the header's counts type carries running, idle and tools, and nothing else")
    func headerHasNoSkillsField() {
        let counts = MenuBarPresentation.Counts(running: 1, idle: 2, tools: 3)
        let fields = Mirror(reflecting: counts).children.compactMap(\.label).sorted()
        #expect(fields == ["idle", "running", "tools"])
    }
}
