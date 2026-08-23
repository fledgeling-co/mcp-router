import Foundation
import Testing
@testable import MCPRouterKit

/// The Signal Path's rules, exercised without a host.
///
/// Written as **cross products** rather than as examples, for the reason `ServerPresentationTests`
/// gives: an example test proves a branch works for the input someone thought of, and both defects
/// this element inherits were inputs nobody thought of — a warm server the router had not yet
/// brought up, and a lever raised for a process that was not running.
///
/// Two of these encode a defect that was caught in review rather than in the field.
/// `theWordNeverCountsDownAWarmServer` is the one an out-of-family lane found in this item's plan:
/// the first draft computed the jack's word from the same chain as its plug, which would have drawn
/// `3:41 left` on a warm server while the hub above it read `1 at rest`.
@Suite("Signal Path — presentation rules")
struct JackPresentationTests {
    /// The specimen builder lives with the row's rules; a second copy would be a second set of
    /// defaults, which is how two suites come to disagree about what an ordinary server looks like.
    typealias Spec = ServerPresentationTests

    /// The router's own reap horizon in the recorded fixtures: five minutes.
    static let idleMs = 300_000

    // MARK: - The plug never lies

    /// The plug's whole meaning is "a child process is up". Lighting it for a server that is not
    /// running, or leaving it dark for one that is, is the only way this control can be wrong — so
    /// the mapping is asserted against `state` across everything else that could tempt it.
    ///
    /// This is `breakerNeverLiesAboutTheLever` carried over unchanged. The signature element
    /// changed; the invariant it has to hold did not.
    @Test("the plug is lit exactly when a child process is up")
    func plugNeverLiesAboutTheChild() throws {
        let placard = Placard(reason: "boom", substitute: nil, until: nil)
        let held = PendingChange(seenAt: "x", count: 1)
        for state in ServerState.allCases {
            for placardValue in [nil, placard] {
                for pending in [nil, held] {
                    for authorized in [true, false] {
                        for warm in [true, false] {
                            let s = try Spec.server(
                                state: state, warm: warm, placard: placardValue,
                                pendingChange: pending,
                                authSupported: true, authorized: authorized
                            )
                            let jack = JackState.forServer(s)
                            #expect(
                                jack.isLit == (state == .running),
                                "plug disagreed with state \(state): \(jack)"
                            )
                        }
                    }
                }
            }
        }
    }

    @Test("the five states, in precedence order")
    func statePrecedence() throws {
        let placard = Placard(reason: "boom", substitute: nil, until: nil)
        let held = PendingChange(seenAt: "x", count: 2)
        // Running wins even while holding a change — the attention is carried by the word, the
        // row's action and the filter, never by colour alone.
        #expect(try JackState.forServer(Spec.server(state: .running, pendingChange: held)) == .live)
        #expect(try JackState.forServer(Spec.server(placard: placard)) == .tripped)
        #expect(try JackState.forServer(Spec.server(pendingChange: held)) == .held)
        #expect(
            try JackState.forServer(Spec.server(authSupported: true, authorized: false)) == .needsSignIn
        )
        #expect(try JackState.forServer(Spec.server()) == .dormant)
    }

    /// **An index error is not a sixth state**, and this is the assertion behind that claim rather
    /// than the comment that makes it. `placardFor()` in `src/manifest.ts` returns the user's own
    /// placard first and `{ reason: entry.error }` second, so an `indexError` always reaches the app
    /// alongside a placard. The recorded fixtures are the evidence that the wire really is that
    /// shape — this asserts the app reads it correctly when it is.
    @Test("an index error arrives placarded, so it reads as tripped rather than as a sixth state")
    func indexErrorIsNotASixthState() throws {
        let s = try Spec.server(
            placard: Placard(reason: "spawn ENOENT", substitute: nil, until: nil),
            indexError: "spawn ENOENT"
        )
        #expect(JackState.forServer(s) == .tripped)
        #expect(JackCondition.forServer(s, idleMs: Self.idleMs).word == "tripped")
        #expect(JackState.allCases.count == 5, "a sixth state needs a word, a colour and a view arm")
    }

    // MARK: - The word never contradicts the hub

    /// **No input produces a reap countdown for a warm server.**
    ///
    /// The defect this rules out: the hub reads `N at rest` from the warm set, and a warm server's
    /// jack counting down to zero says the opposite about the same server on the same board. The
    /// same invariant `ServerSubtitle` has held for the row since M3 — *"a warm server never shows
    /// a reap countdown"* — now held by the band as well.
    @Test("no warm server ever shows a countdown, in either form of the word")
    func theWordNeverCountsDownAWarmServer() throws {
        for state in ServerState.allCases {
            for idleSec in [0, 42, 299, 1000] {
                let s = try Spec.server(state: state, warm: true, idleSec: idleSec)
                let c = JackCondition.forServer(s, idleMs: Self.idleMs)
                #expect(!c.word.contains(":"), "warm server counted down: \(c.word)")
                #expect(!c.contracted.contains(":"), "warm server counted down: \(c.contracted)")
            }
        }
    }

    /// The hub and the jack read one server the same way round.
    @Test("a warm running server reads never-reaped, and a warm idle one reads warm")
    func warmReadsTheSameWayTheHubDoes() throws {
        let running = try Spec.server(state: .running, warm: true)
        #expect(JackCondition.forServer(running, idleMs: Self.idleMs).word == "never reaped")
        #expect(JackState.forServer(running) == .live)

        // Warm but not up: `warmUp()` logs and swallows a start failure, so this is reachable.
        let notUp = try Spec.server(state: .idle, warm: true)
        #expect(JackCondition.forServer(notUp, idleMs: Self.idleMs).word == "warm")
        #expect(JackState.forServer(notUp) == .dormant)
    }

    // MARK: - The countdown is the row's, not a second one

    /// Two readings of one server, from one computation. A jack saying `3:41 left` beside a row
    /// saying `reaps in 190s` would be two answers to one question.
    @Test("the jack's countdown is the row subtitle's seconds, in mm:ss")
    func theCountdownIsTheRowsOwn() throws {
        for idleSec in [0, 19, 59, 60, 221, 299, 300, 5000] {
            let s = try Spec.server(state: .running, idleSec: idleSec)
            let seconds = ServerSubtitle.reapSeconds(s, idleMs: Self.idleMs)
            let c = JackCondition.forServer(s, idleMs: Self.idleMs)
            #expect(c.word == "\(JackCondition.mmss(seconds)) left")
            #expect(c.contracted == JackCondition.mmss(seconds))
        }
    }

    /// An unknown horizon draws no clock at all. The board passes `idleMs` through rather than
    /// defaulting it, because the prototype's hardcoded 300 seconds displayed as an observation is
    /// exactly what `DESIGN.md` §6 forbids.
    @Test("an unknown horizon says awake rather than counting down to a number nothing sent")
    func noHorizonMeansNoClock() throws {
        let running = try Spec.server(state: .running)
        let c = JackCondition.forServer(running, idleMs: nil)
        #expect(c.word == "awake")
        #expect(c.contracted == "awake")
        #expect(c.state == .live)
    }

    @Test("mm:ss at its boundaries, and never a negative or a rolled-over hour")
    func clockBoundaries() {
        #expect(JackCondition.mmss(0) == "0:00")
        #expect(JackCondition.mmss(9) == "0:09")
        #expect(JackCondition.mmss(60) == "1:00")
        #expect(JackCondition.mmss(221) == "3:41")
        #expect(JackCondition.mmss(3600) == "60:00")
        #expect(JackCondition.mmss(-5) == "0:00")
    }

    // MARK: - The contraction keeps the number

    /// The brief's second measured constraint: *"drop the redundant word … rather than clipping the
    /// countdown."* A contraction that lost the figure would be the tail truncation it replaces.
    @Test("the contracted form is never longer, and never loses the number")
    func contractionKeepsWhatCarriesInformation() throws {
        let cases: [MCPServer] = try [
            Spec.server(state: .running, idleSec: 59),
            Spec.server(state: .running, warm: true),
            Spec.server(placard: Placard(reason: "boom", substitute: nil, until: nil)),
            Spec.server(pendingChange: PendingChange(seenAt: "x", count: 12)),
            Spec.server(authSupported: true, authorized: false),
            Spec.server()
        ]
        for s in cases {
            let c = JackCondition.forServer(s, idleMs: Self.idleMs)
            #expect(c.contracted.count <= c.word.count, "\(c.contracted) is longer than \(c.word)")
            let digits = c.word.filter(\.isNumber)
            #expect(
                c.contracted.filter(\.isNumber) == digits,
                "the contraction dropped a figure: \(c.word) → \(c.contracted)"
            )
        }
    }

    @Test("held changes count, and are pluralised on the count the router sent")
    func heldChangesAreCounted() throws {
        let one = try Spec.server(pendingChange: PendingChange(seenAt: "x", count: 1))
        #expect(JackCondition.forServer(one, idleMs: Self.idleMs).word == "1 held change")
        let two = try Spec.server(pendingChange: PendingChange(seenAt: "x", count: 2))
        #expect(JackCondition.forServer(two, idleMs: Self.idleMs).word == "2 held changes")
        #expect(JackCondition.forServer(two, idleMs: Self.idleMs).contracted == "2 held")
    }

    // MARK: - Colour is never the only signal

    /// Every state has a word, and every lit state has a hue that means only what it means.
    @Test("five states, five words, and every lit one on a reserved hue")
    func everyStateHasAWordAndAReservedHue() {
        #expect(Set(JackState.allCases.map(\.word)).count == JackState.allCases.count)
        #expect(JackState.dormant.indicator == nil)
        for state in JackState.allCases {
            #expect(!state.word.isEmpty)
            guard let token = state.indicator else { continue }
            #expect(token.isReservedMeaning, "\(token.rawValue) is not one of the exclusive hues")
        }
        // The two that both mean "waiting on a person" share a hue and are told apart by their word.
        #expect(JackState.held.indicator == JackState.needsSignIn.indicator)
        #expect(JackState.held.word != JackState.needsSignIn.word)
    }

    // MARK: - The row and the band read one value

    @Test("the row model carries the same jack the band draws")
    func theRowAndTheBandAgree() throws {
        let s = try Spec.server(state: .running, idleSec: 19)
        let row = ServerRowModel(server: s, idleMs: Self.idleMs, pendingAuth: nil)
        #expect(row.jack == JackState.forServer(s))
        #expect(row.condition == JackCondition.forServer(s, idleMs: Self.idleMs))
    }

    // MARK: - At rest

    /// The hub's figure, and the case the out-of-family review found: a warm server whose child
    /// never came up is not a child at rest.
    @Test("at rest counts warm servers whose child is actually up")
    func atRestCountsRunningWarmChildren() throws {
        let up = try Spec.server(name: "a", state: .running, warm: true)
        let notUp = try Spec.server(name: "b", state: .idle, warm: true)
        let ordinary = try Spec.server(name: "c", state: .running)
        let header = ServersBoardHeader(servers: [up, notUp, ordinary], reading: .current)
        #expect(header.atRest == 1)
        #expect(header.running == 2)
    }

    /// A count of live child processes is a present-tense claim, and a router that has stopped
    /// answering cannot support one — the same rule `running` follows.
    @Test("at rest is withheld rather than zeroed on a reading that is not current")
    func atRestIsWithheldOnAStaleReading() throws {
        let up = try Spec.server(state: .running, warm: true)
        #expect(ServersBoardHeader(servers: [up], reading: .stale).atRest == nil)
        #expect(ServersBoardHeader(servers: [up], reading: .none).atRest == nil)
    }

    @Test("the topology line counts what is declared, and pluralises on it")
    func topologyCountsDeclaredUpstreams() throws {
        let one = try Spec.server(name: "a")
        #expect(ServersBoardHeader(servers: [one], reading: .current).topology == "1 endpoint → 1 upstream")
        let two = try Spec.server(name: "b")
        #expect(
            ServersBoardHeader(servers: [one, two], reading: .current).topology
                == "1 endpoint → 2 upstreams"
        )
        // Declared count survives a reading that is not current — it is configuration, not a claim
        // about a running process.
        #expect(
            ServersBoardHeader(servers: [one, two], reading: .stale).topology
                == "1 endpoint → 2 upstreams"
        )
    }
}
