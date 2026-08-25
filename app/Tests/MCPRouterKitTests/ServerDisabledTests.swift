import Foundation
import Testing
@testable import MCPRouterKit

/// M29 — a server that is declared and not served.
///
/// Written as **cross products** rather than as examples, for the reason
/// `ServerPresentationTests` gives: the rule under test is a precedence, and a precedence is only
/// wrong for the combination nobody thought of. The combination this feature creates is not a
/// corner either — the sheet that offers `Disable` is the held-change sheet, so *disabled while
/// holding a schema change* is the ordinary path through the feature rather than an odd one.
///
/// Oracle lines 9, 10, 11, 14, 15 and 18 of `planning/specs/spec-M29.md` live here. Lines 1–8 and
/// 13 are the vector corpus and the pool suites; 12, 16 and 17 are the board's write tests.
@Suite("M29 — declared and not served")
struct ServerDisabledTests {
    /// Every other condition the subtitle chain reads, so "whichever else is true" is a set that
    /// was actually enumerated rather than a phrase in a comment.
    ///
    /// Each entry is applied to a server that is *also* disabled. `inFlight` is deliberately absent:
    /// it counts in-flight tool calls on the server, and a disabled server has none by construction
    /// — asserting over an unreachable state would be asserting over a fiction.
    static let otherConditions: [(name: String, apply: @Sendable (inout MCPServer) -> Void)] = [
        ("nothing else", { _ in }),
        ("holding a change", { $0.pendingChange = PendingChange(seenAt: "2026-08-01T00:00:00Z", count: 3) }),
        ("index errored", { $0.indexError = "spawn failed" }),
        ("placarded", { $0.placard = Placard(reason: "under repair") }),
        ("unauthorised", { $0.auth = ServerAuth(supported: true, authorized: false) }),
        ("warm", { $0.warm = true }),
        ("running", { $0.state = .running }),
        ("scoped to a project", { $0.projects = ["/a/b"] }),
        ("carrying tools", { $0.tools = 7; $0.toolNames = ["one", "two"] }),
        ("everything at once", {
            $0.pendingChange = PendingChange(seenAt: "2026-08-01T00:00:00Z", count: 3)
            $0.indexError = "spawn failed"
            $0.placard = Placard(reason: "under repair")
            $0.auth = ServerAuth(supported: true, authorized: false)
            $0.warm = true
            $0.state = .running
            $0.tools = 7
        })
    ]

    static func disabledServers() throws -> [(String, MCPServer)] {
        try otherConditions.map { entry in
            var s = try ServerPresentationTests.server(disabled: true)
            entry.apply(&s)
            return (entry.name, s)
        }
    }

    // MARK: - Oracle 9: the subtitle wins the precedence

    @Test("a disabled server reads 'disabled by you' whichever else is true of it")
    func subtitleWinsThePrecedence() throws {
        for (label, server) in try Self.disabledServers() {
            let subtitle = ServerSubtitle.forServer(server, idleMs: 300_000)
            #expect(
                subtitle.text == "disabled by you",
                "a disabled server that is \(label) read '\(subtitle.text)'"
            )
            // `--t4` is reserved for disabled *controls* and never for live text (`DESIGN.md`:138);
            // this is a subtitle a person is meant to read, and the row's own dim is the view's job.
            #expect(subtitle.tint == .t3, "the subtitle for \(label) used \(subtitle.tint)")
        }
    }

    /// The negative control. Without it the assertion above is satisfied by a function that returns
    /// the same string for every server there is.
    @Test("a server that is not disabled never reads 'disabled by you'")
    func subtitleIsNotUniversal() throws {
        for (label, apply) in Self.otherConditions.map({ ($0.name, $0.apply) }) {
            var s = try ServerPresentationTests.server(disabled: false)
            apply(&s)
            #expect(
                ServerSubtitle.forServer(s, idleMs: 300_000).text != "disabled by you",
                "a server that is only \(label) claimed to be disabled"
            )
        }
    }

    // MARK: - Oracle 10: the count is withheld, not zeroed

    @Test("the tools cell is withheld exactly when the server is disabled")
    func toolsAreWithheldExactlyWhenDisabled() throws {
        // The router still knows the count — disabling never touches the manifest row — so the
        // withheld case is asserted against a server that HAS tools. A model that withheld the
        // figure only when it was already zero would claim nothing and prove nothing.
        var off = try ServerPresentationTests.server(tools: 7, disabled: true)
        off.toolNames = ["one", "two"]
        let offRow = ServerRowModel(server: off, idleMs: nil, pendingAuth: nil)
        #expect(offRow.tools == nil, "a disabled server reported a served count of \(offRow.tools ?? -1)")
        #expect(offRow.indexedTools == 7, "the indexed count moved when the switch did")

        let on = try ServerPresentationTests.server(tools: 7, disabled: false)
        let onRow = ServerRowModel(server: on, idleMs: nil, pendingAuth: nil)
        #expect(onRow.tools == 7)
        #expect(onRow.indexedTools == 7)

        // A server with genuinely no tools still reports the zero, because that claim is true.
        let empty = try ServerPresentationTests.server(tools: 0, disabled: false)
        #expect(ServerRowModel(server: empty, idleMs: nil, pendingAuth: nil).tools == 0)
    }

    // MARK: - Oracle 11: the action is Enable, and only Enable

    @Test("a disabled server's one action is Enable, whichever else is true of it")
    func theActionIsEnable() throws {
        for (label, server) in try Self.disabledServers() {
            let action = ServerRowAction.forServer(server, pendingAuth: nil)
            #expect(action == .enable, "a disabled server that is \(label) offered \(String(describing: action))")
        }
        #expect(ServerRowAction.enable.label == "Enable")
    }

    @Test("a server that is not disabled is never offered Enable")
    func enableIsNotOfferedToLiveServers() throws {
        for (label, apply) in Self.otherConditions.map({ ($0.name, $0.apply) }) {
            var s = try ServerPresentationTests.server(disabled: false)
            apply(&s)
            #expect(
                ServerRowAction.forServer(s, pendingAuth: nil) != .enable,
                "a server that is only \(label) was offered Enable"
            )
        }
    }

    // MARK: - Oracle 14: present in All and Idle, absent from Needs you

    @Test("a disabled server is listed under All and Idle and never under Needs you")
    func filtersPlaceADisabledServerWhereTheUserLeftIt() throws {
        for (label, server) in try Self.disabledServers() {
            #expect(ServerFilter.all.matches(server), "All dropped a disabled server that is \(label)")
            #expect(
                !ServerFilter.needsYou.matches(server),
                "Needs you summoned the user about a disabled server that is \(label)"
            )
            // `Idle` is `state != .running`, so the two entries above that set `.running` are not
            // idle and are not asserted to be. Naming that here rather than filtering silently.
            if server.state != .running {
                #expect(ServerFilter.idle.matches(server), "Idle dropped a disabled server that is \(label)")
            }
        }
    }

    /// The four inputs that would otherwise carry a server into `Needs you`, each on its own, with
    /// the switch off. A guard placed on only one limb passes a test that sets them together.
    @Test("each route into Needs you is closed by the switch on its own")
    func everyLimbOfNeedsYouIsClosed() throws {
        let limbs: [(String, @Sendable (inout MCPServer) -> Void)] = [
            ("a held change", { $0.pendingChange = PendingChange(seenAt: "2026-08-01T00:00:00Z", count: 1) }),
            ("an index error", { $0.indexError = "spawn failed" }),
            ("an unauthorised credential", { $0.auth = ServerAuth(supported: true, authorized: false) }),
            ("a placard", { $0.placard = Placard(reason: "under repair") })
        ]
        for (label, apply) in limbs {
            var live = try ServerPresentationTests.server(disabled: false)
            apply(&live)
            #expect(
                ServerFilter.needsYou.matches(live),
                "\(label) did not reach Needs you at all, so switching it off proves nothing"
            )

            var off = try ServerPresentationTests.server(disabled: true)
            apply(&off)
            #expect(!ServerFilter.needsYou.matches(off), "\(label) still summoned the user with the switch off")
        }
    }

    // MARK: - Oracle 15: it contributes nothing to any attention count

    @Test("a disabled server contributes zero to needsAttention, which the badge and the band read")
    func aDisabledServerSummonsNobody() throws {
        for (label, server) in try Self.disabledServers() {
            #expect(!server.needsAttention, "a disabled server that is \(label) still needed attention")
        }

        // The record survives; only the summons is dropped. That distinction is the whole of D11 —
        // the hold is still there for the inspector to show, it just stops putting a number on the
        // menu bar for a decision the user has already taken.
        var held = try ServerPresentationTests.server(disabled: true)
        held.pendingChange = PendingChange(seenAt: "2026-08-01T00:00:00Z", count: 3)
        #expect(held.pendingChange != nil, "disabling discarded the held change rather than the summons")
        #expect(held.indexError == nil)

        var stillHeld = try ServerPresentationTests.server(disabled: true)
        stillHeld.indexError = "spawn failed"
        #expect(stillHeld.indexError == "spawn failed", "disabling discarded the index error")
    }

    // MARK: - Oracle 18 (model half): the jack does not light

    @Test("a disabled server's plug is dormant and says which kind of dormant")
    func theJackDoesNotLie() throws {
        for (label, server) in try Self.disabledServers() {
            #expect(
                JackState.forServer(server) == .dormant,
                "a disabled server that is \(label) drew a \(JackState.forServer(server)) plug"
            )
            let condition = JackCondition.forServer(server, idleMs: 300_000)
            #expect(condition.word == "disabled by you", "the plug for \(label) said '\(condition.word)'")
            #expect(condition.contracted == "disabled")
        }

        // Including the case the plug's own invariant is about: a child that is genuinely up. The
        // reaper is on its way to close it, and until then a lit plug would be true about the
        // process and false about the product.
        let running = try ServerPresentationTests.server(state: .running, disabled: true)
        #expect(JackState.forServer(running) == .dormant)
        #expect(JackState.forServer(try ServerPresentationTests.server(state: .running)) == .live)
    }
}
