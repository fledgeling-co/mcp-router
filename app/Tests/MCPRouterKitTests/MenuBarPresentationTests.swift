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
        tools: Int = 0,
        disabled: Bool = false
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
        server.disabled = disabled
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

    // MARK: - M29 oracle 15 · the band is silent about a server nobody can act on

    /// The defect this guards, stated as it was measured: `causes(for:)` read `pendingChange`,
    /// `auth` and `indexError` and never `disabled`, while `MCPServer.needsAttention` did carry the
    /// term. So a disabled server holding a schema change produced `needsAttention == false` and
    /// `attentionRows == ["sift|heldChange"]` at the same instant — a band row under a dot that was
    /// not lit, opening a sheet whose `Disable` button was already dimmed. The row was a dead end
    /// and the two figures were of different things.
    @Test("a disabled server holding a change draws no band row and lights no dot")
    func aDisabledServerIsNotSummonedToTheBand() async throws {
        let off = try await Self.server(
            named: "sift",
            held: true,
            authSupported: true,
            authorized: false,
            indexError: "spawn ENOENT",
            disabled: true
        )

        #expect(MenuBarPresentation.AttentionCause.causes(for: off).isEmpty)
        #expect(
            MenuBarPresentation.attentionRows(from: [off]).map(\.id) == [],
            "a switched-off server was drawn a band row it cannot act on"
        )
        #expect(!MenuBarPresentation.statusItemNeedsAttention([off]))
        #expect(MenuBarPresentation.statusItemLabel([off]) == "MCP Router")

        // The control, in the same test: the same server switched back on is one row, so the
        // assertions above measure the switch rather than a fixture that never had a cause.
        var on = off
        on.disabled = false
        #expect(MenuBarPresentation.attentionRows(from: [on]).map(\.id) == ["sift|heldChange"])
        #expect(MenuBarPresentation.statusItemNeedsAttention([on]))
    }

    /// The invariant underneath the case above: the band lists things to look at and the dot says
    /// whether there are any, so *for one server* they can never disagree. Asserted over the whole
    /// cross product rather than on examples, because the defect was a term missing from one of two
    /// expressions that are supposed to be the same condition — and only the combination
    /// `disabled` × *a cause* exposed it.
    @Test("the band and the dot never disagree about one server, over the cross product")
    func theBandAndTheDotAgree() async throws {
        var checked = 0
        for disabled in [false, true] {
            for held in [false, true] {
                for unauthorised in [false, true] {
                    for broken in [false, true] {
                        let server = try await Self.server(
                            named: "s",
                            held: held,
                            authSupported: unauthorised,
                            authorized: !unauthorised,
                            indexError: broken ? "spawn ENOENT" : nil,
                            disabled: disabled
                        )
                        let rows = MenuBarPresentation.attentionRows(from: [server])
                        let dot = MenuBarPresentation.statusItemNeedsAttention([server])
                        let arm = "disabled=\(disabled) held=\(held) "
                            + "auth=\(unauthorised) index=\(broken)"
                        #expect(
                            rows.isEmpty == !dot,
                            "\(arm): band \(rows.count) rows, dot \(dot)"
                        )
                        #expect(
                            (MenuBarPresentation.statusItemLabel([server]) == "MCP Router")
                                == rows.isEmpty,
                            "the spoken label counts a server the band does not list"
                        )
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == 16, "the cross product shrank")
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

    // MARK: - A17 · there is no skills count, and B1 · no memory count either

    /// `Counts` has four fields and none of them is skills or memory. The prototype's popover shows
    /// a skills figure and `ControlAPIClient` has no skills endpoint; the mock's popover shows
    /// `Resident 214 MB` and `residentMb()` has zero callers in `src/pool.ts`, so it never reaches
    /// `describe()` and never reaches the wire. Either number would be invented.
    ///
    /// Asserted as a reflection over the type because that is what survives someone adding a field.
    /// An equality against the whole set rather than a `!contains` per forbidden word, so a field
    /// named something nobody thought to forbid still fails.
    @Test("the header's counts type carries running, idle, tools and declared, and nothing else")
    func headerHasNoSkillsField() {
        let counts = MenuBarPresentation.Counts(running: 1, idle: 2, tools: 3, declared: 3)
        let fields = Mirror(reflecting: counts).children.compactMap(\.label).sorted()
        #expect(fields == ["declared", "idle", "running", "tools"])
    }

    /// B1 · `declared` is every server the router named, running or not.
    ///
    /// The mock's second header cell. Checked against the list's own length rather than against
    /// `running + idle`, because those two are derived from the same list and would agree with each
    /// other while all three disagreed with reality.
    @Test("declared is the number of servers the router reported")
    func declaredIsTheServerCount() async throws {
        var servers: [MCPServer] = []
        for index in 0 ..< 11 {
            try await servers.append(Self.server(named: "s\(index)", running: index < 2, tools: 4))
        }
        let counts = MenuBarPresentation.counts(from: servers)
        #expect(counts.declared == 11)
        #expect(counts.declared == servers.count)
        #expect(counts.running == 2)
        #expect(counts.idle == 9, "idle is kept, because ReadoutModel and the subtitle still use it")
        #expect(MenuBarPresentation.counts(from: []).declared == 0)
    }

    /// The three labels the header draws, and the fourth cell the mock draws that does not ship.
    ///
    /// The mock's own words — `Running now`, `Declared`, `Tools`, `Resident` — read off
    /// `design/mcp-router-console.html:1458-1470`. The first three are asserted present and in
    /// order; `Resident` is asserted **absent from every label the type carries**, which is the
    /// structural half of the same claim `headerHasNoSkillsField` makes about the fields.
    @Test("the header's labels are the mock's three, and Resident is not among them")
    func headerLabelsAreTheMocksThree() {
        #expect(MenuBarPresentation.CountLabel.all == ["Running now", "Declared", "Tools"])
        #expect(MenuBarPresentation.CountLabel.all.count == 3)
        for label in MenuBarPresentation.CountLabel.all {
            #expect(
                !label.lowercased().contains("resident"),
                "the mock's fourth cell is a number the router does not observe"
            )
        }
    }
}
