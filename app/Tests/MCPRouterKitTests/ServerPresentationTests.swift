import Foundation
import Testing
@testable import MCPRouterKit

/// The Servers board's rules, exercised without a host.
///
/// The brief names state correctness as the thing that failed twice in the prototype, so these are
/// not decorative tests: `warmNeverShowsACountdown` here and `plugNeverLiesAboutTheChild` in
/// `JackPresentationTests` are the two that encode the actual defects, and both are written as
/// **cross products** rather than as
/// examples. An example test proves a branch works for the input someone thought of; the prototype's
/// bug was in an input nobody thought of — a warm server that the router had not yet brought up.
@Suite("Servers board — presentation rules")
struct ServerPresentationTests {
    // MARK: - Building servers to think with

    static func base() throws -> MCPServer {
        try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
    }

    /// Every knob the precedence chain reads, so a case can be named rather than assembled.
    static func server(
        name: String = "s",
        state: ServerState = .idle,
        warm: Bool = false,
        inFlight: Int = 0,
        idleSec: Int = 0,
        placard: Placard? = nil,
        pendingChange: PendingChange? = nil,
        indexError: String? = nil,
        authSupported: Bool = false,
        authorized: Bool = true,
        pendingURL: String? = nil,
        projects: [String] = [],
        tools: Int = 0,
        toolNames: [String] = [],
        calls: Int = 0,
        errors: Int = 0,
        disabled: Bool = false
    ) throws -> MCPServer {
        var s = try base()
        s.name = name
        s.state = state
        s.warm = warm
        s.inFlight = inFlight
        s.idleSec = idleSec
        s.placard = placard
        s.pendingChange = pendingChange
        s.indexError = indexError
        s.auth = ServerAuth(
            supported: authSupported,
            authorized: authorized,
            authorizedAt: nil,
            pendingURL: pendingURL
        )
        s.projects = projects
        s.tools = tools
        s.toolNames = toolNames
        s.usage = ServerUsage(calls: calls, errors: errors)
        s.disabled = disabled
        return s
    }

    // MARK: - A4 · the invariant the prototype broke

    /// **No input produces a reap countdown for a warm server.**
    ///
    /// The brief states it three ways — warm implies running, the reaper skips warm, a warm server
    /// never shows a reap countdown — and the prototype implements it as `warm && running`, which is
    /// a conjunction rather than a precedence. This is the whole cross product of the knobs the chain
    /// reads before the countdown, so the branch cannot be right for the cases someone imagined and
    /// wrong for the one they did not.
    @Test("A4 — no warm server anywhere in the state space shows a reap countdown")
    func warmNeverShowsACountdown() throws {
        for state in ServerState.allCases {
            for inFlight in [0, 1] {
                for placard in [nil, Placard(reason: "boom", substitute: nil, until: nil)] {
                    for pending in [nil, PendingChange(seenAt: "2026-08-14T00:00:00Z", count: 1)] {
                        for idleSec in [0, 120, 400] {
                            let s = try Self.server(
                                state: state, warm: true, inFlight: inFlight,
                                idleSec: idleSec, placard: placard, pendingChange: pending
                            )
                            let subtitle = ServerSubtitle.forServer(s, idleMs: 300_000)
                            #expect(
                                !subtitle.text.contains("reaps in"),
                                """
                                warm server showed a countdown: state=\(state) inFlight=\(inFlight) \
                                placard=\(placard != nil) pending=\(pending != nil) → \(subtitle.text)
                                """
                            )
                        }
                    }
                }
            }
        }
    }

    /// The other half of A4: a warm server with nothing to report says so, in every lifecycle state.
    @Test("A4 — a warm server with nothing wrong reads `warm · never reaped` in every state")
    func warmReadsAsWarm() throws {
        for state in ServerState.allCases {
            let s = try Self.server(state: state, warm: true, idleSec: 400)
            #expect(ServerSubtitle.forServer(s, idleMs: 300_000).text == "warm · never reaped")
        }
    }

    /// **A5 — the exact case the prototype gets wrong.**
    ///
    /// `warm && st === 'running'` sends a warm, idle server past both branches to `dormant`, which
    /// tells the user a server the reaper will never touch is idle and reapable.
    @Test("A5 — a warm idle server is not `dormant`")
    func warmIdleIsNotDormant() throws {
        let s = try Self.server(state: .idle, warm: true)
        let subtitle = ServerSubtitle.forServer(s, idleMs: 300_000)
        #expect(subtitle.text == "warm · never reaped")
        #expect(subtitle.text != "dormant")
    }

    // MARK: - A6 · the countdown is the router's number

    @Test("A6 — the countdown is idleMs/1000 − idleSec, from the response")
    func countdownComesFromTheResponse() throws {
        let s = try Self.server(state: .running, idleSec: 40)
        #expect(ServerSubtitle.forServer(s, idleMs: 300_000).text == "reaps in 260s")
        // A router configured differently must produce a different answer, or the value is a literal
        // wearing a parameter's clothes.
        #expect(ServerSubtitle.forServer(s, idleMs: 60000).text == "reaps in 20s")
        #expect(ServerSubtitle.forServer(s, idleMs: 10000).text == "reaps in 0s")
    }

    @Test("A6 — a server past its horizon floors at zero rather than going negative")
    func countdownFloorsAtZero() throws {
        let s = try Self.server(state: .running, idleSec: 9999)
        #expect(ServerSubtitle.forServer(s, idleMs: 300_000).text == "reaps in 0s")
    }

    // MARK: - A3 · every row of the precedence table

    @Test("A3 — the precedence table, one case per row, in order")
    func precedenceTable() throws {
        let placard = Placard(reason: "1011150 invalid request IP", substitute: nil, until: nil)
        let held = PendingChange(seenAt: "2026-08-14T00:00:00Z", count: 1)

        // 1 · in flight outranks everything below it
        #expect(
            try ServerSubtitle.forServer(
                Self.server(state: .running, inFlight: 3, placard: placard), idleMs: 300_000
            ).text == "3 in flight"
        )
        // 2 · tripped, with the router's own reason
        let tripped = try ServerSubtitle.forServer(Self.server(placard: placard), idleMs: 300_000)
        #expect(tripped.text == "tripped · 1011150 invalid request IP")
        #expect(tripped.tint == .fail)
        // 3 · held, pluralised from the router's count
        #expect(
            try ServerSubtitle.forServer(Self.server(pendingChange: held), idleMs: 300_000).text
                == "1 description held"
        )
        #expect(
            try ServerSubtitle.forServer(
                Self.server(pendingChange: PendingChange(seenAt: "x", count: 3)), idleMs: 300_000
            ).text == "3 descriptions held"
        )
        // 4 · needs authorising
        let auth = try ServerSubtitle.forServer(
            Self.server(authSupported: true, authorized: false), idleMs: 300_000
        )
        #expect(auth.text == "needs authorising")
        #expect(auth.tint == .attention)
        // 5 · warm — above running
        #expect(
            try ServerSubtitle.forServer(Self.server(state: .running, warm: true), idleMs: 300_000)
                .text == "warm · never reaped"
        )
        // 6 · running
        #expect(
            try ServerSubtitle.forServer(Self.server(state: .running, idleSec: 100), idleMs: 300_000)
                .text == "reaps in 200s"
        )
        // 7, 8 · the two transient lifecycle states get their own words rather than falling to dormant
        #expect(try ServerSubtitle.forServer(Self.server(state: .starting), idleMs: 300_000)
            .text == "starting")
        #expect(try ServerSubtitle.forServer(Self.server(state: .stopping), idleMs: 300_000)
            .text == "stopping")
        // 9 · scoped, pluralised
        #expect(
            try ServerSubtitle.forServer(Self.server(projects: ["~/a"]), idleMs: 300_000).text
                == "scoped to 1 project"
        )
        #expect(
            try ServerSubtitle.forServer(Self.server(projects: ["~/a", "~/b"]), idleMs: 300_000).text
                == "scoped to 2 projects"
        )
        // 10 · dormant, at the dimmed tier because dimming is the message here
        let dormant = try ServerSubtitle.forServer(Self.server(), idleMs: 300_000)
        #expect(dormant.text == "dormant")
        #expect(dormant.tint == .t3)
    }

    /// `DESIGN.md` §2: the three indicator hues mean one thing each and nothing else. A subtitle may
    /// only ever reach for `--attn` or `--fail`, and only in the rows that mean those things.
    @Test("A32 — a subtitle never uses an indicator colour outside its meaning")
    func subtitleTintsAreExclusive() throws {
        let allowed: Set<ColorToken> = [.t2, .t3, .attention, .fail]
        for state in ServerState.allCases {
            for warm in [true, false] {
                for projects in [[], ["~/a"]] {
                    let s = try Self.server(state: state, warm: warm, projects: projects)
                    let tint = ServerSubtitle.forServer(s, idleMs: 300_000).tint
                    #expect(allowed.contains(tint))
                    // Nothing benign is ever painted with a meaning colour.
                    #expect(tint != .fail)
                    #expect(tint != .attention)
                    #expect(tint != .live)
                    #expect(tint != .accent)
                }
            }
        }
    }

    // MARK: - A7 · the indicator never lies

    // `breakerNeverLiesAboutTheLever` and `breakerColours` stood here until M16 retired the lever.
    // They are not deleted so much as **moved**: `JackPresentationTests.plugNeverLiesAboutTheChild`
    // is the same cross product over the same inputs, asserting the same thing about the mark that
    // replaced it, and `statePrecedence` carries the second. A retirement that dropped the
    // invariant with the element would have removed the one assertion this board's signature has
    // ever needed.

    // MARK: - A11 · Reset resolves to the operation that actually clears the mark

    /// `placardFor()` returns the user's placard first and the index error second, so clearing the
    /// field on an index-error server changes nothing — the router recomputes the same mark on the
    /// next describe. The two are only distinguishable because `indexError` is reported separately.
    @Test("A11 — Reset re-indexes an index failure and clears a user placard")
    func resetPicksTheRightOperation() throws {
        let placard = Placard(reason: "spawn ENOENT", substitute: nil, until: nil)
        let indexed = try Self.server(placard: placard, indexError: "spawn ENOENT")
        #expect(ServerRowAction.forServer(indexed, pendingAuth: nil) == .reset(.reindex))

        let userPlacard = try Self.server(placard: Placard(
            reason: "under maintenance",
            substitute: nil,
            until: nil
        ))
        #expect(ServerRowAction.forServer(userPlacard, pendingAuth: nil) == .reset(.clearPlacard))
    }

    // MARK: - A8, A18 · the row's action

    @Test("A8 — a healthy server offers no action, and no eval chip exists to offer")
    func healthyRowHasNoAction() throws {
        #expect(try ServerRowAction.forServer(Self.server(calls: 900), pendingAuth: nil) == nil)
        // The strings the prototype's chip would have carried appear on no action anywhere.
        let labels = Set(
            [
                ServerRowAction.reset(.reindex), .reviewHeldChange, .beginAuthorization,
                .reopenAuthorizationPage("https://x")
            ].map(\.label)
        )
        #expect(!labels.contains("passed"))
        #expect(!labels.contains("not evaluated"))
    }

    @Test("A18 — an authorisation already in flight is reopened, never begun a second time")
    func pendingAuthIsReopened() throws {
        let s = try Self.server(name: "fetch-pro", authSupported: true, authorized: false)
        let pending = PendingAuth(server: "fetch-pro", url: "https://auth.example/x")
        #expect(
            ServerRowAction.forServer(s, pendingAuth: pending)
                == .reopenAuthorizationPage("https://auth.example/x")
        )
        // A pending flow for a *different* server must not silence this one's Sign in.
        #expect(
            ServerRowAction.forServer(s, pendingAuth: PendingAuth(server: "other", url: "https://y"))
                == .beginAuthorization
        )
        // The server's own pendingURL says the same thing for this one server.
        let withOwnURL = try Self.server(
            authSupported: true, authorized: false, pendingURL: "https://auth.example/own"
        )
        #expect(
            ServerRowAction.forServer(withOwnURL, pendingAuth: nil)
                == .reopenAuthorizationPage("https://auth.example/own")
        )
    }

    @Test("A11 — a tripped server outranks a held one for the row's single action")
    func trippedOutranksHeld() throws {
        let s = try Self.server(
            placard: Placard(reason: "boom", substitute: nil, until: nil),
            pendingChange: PendingChange(seenAt: "x", count: 1)
        )
        #expect(ServerRowAction.forServer(s, pendingAuth: nil) == .reset(.clearPlacard))
    }
}
