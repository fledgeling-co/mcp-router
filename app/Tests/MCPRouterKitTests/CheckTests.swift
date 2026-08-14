import Foundation
import Testing
@testable import MCPRouterKit

/// The eleven checks, asserted over cross products rather than examples.
///
/// A check is a total function of a wire type, so "over the cross product" is achievable rather than
/// aspirational here — and it is what separates a test that proves a rule from one that proves the
/// author picked a passing case.
@Suite("Server and skill checks")
struct CheckTests {
    // MARK: - A5: callsSucceed over the cross product

    @Test("A5: zero recorded calls is never observed, whatever the error count says")
    func callsSucceedNeverExercised() {
        // The load-bearing rule: zero calls with zero errors is arithmetically a clean record and is
        // NOT a confirmation. Asserted over the cross product, not over a chosen example.
        for errors in [0, 1, 9] {
            let result = ServerChecks.callsSucceed(CheckFixtures.server(calls: 0, errors: errors))
            #expect(result.verdict == .unknown, "calls=0 errors=\(errors) must be unobserved")
            #expect(result.reason == CheckCopy.neverExercised)
        }
        for calls in [1, 7] {
            for errors in [0, 1, 9] {
                let result = ServerChecks.callsSucceed(CheckFixtures.server(calls: calls, errors: errors))
                let expected: CheckVerdict = errors == 0 ? .passed : .failed
                #expect(result.verdict == expected, "calls=\(calls) errors=\(errors)")
            }
        }
    }

    @Test("A8b: a server whose history was reset reads as never exercised despite callsServed")
    func callsServedIsNotTheField() {
        // callsServed is the process's lifetime tally; usage.calls is the recorded window every
        // sentence on these panes is scoped to. Reading the wrong one makes a reset invisible.
        let reset = CheckFixtures.server(calls: 0, errors: 0, callsServed: 412)
        #expect(ServerChecks.callsSucceed(reset).verdict == .unknown)
        #expect(CleanupPresentation.candidacy(for: reset).isCandidate)
    }

    // MARK: - A5c: declaresTools under a failing index

    @Test("A5c: a stale tool count under a failing index is not observed")
    func declaresToolsUnknownWhenIndexFailing() {
        for tools in [0, 1, 30] {
            let result = ServerChecks.declaresTools(
                CheckFixtures.server(tools: tools, indexError: "spawn ENOENT")
            )
            #expect(result.verdict == .unknown, "tools=\(tools) under a failing index")
        }
        // And it still answers normally when the index is healthy.
        #expect(ServerChecks.declaresTools(CheckFixtures.server(tools: 3)).verdict == .passed)
        #expect(ServerChecks.declaresTools(CheckFixtures.server(tools: 0)).verdict == .failed)
        #expect(ServerChecks.declaresTools(CheckFixtures.server(indexedAt: nil)).verdict == .unknown)
    }

    // MARK: - A5b: no vacuous confirmations

    @Test("A5b: a question that does not arise is not applicable, never a confirmation")
    func noVacuousConfirmations() {
        // held == nil is the common case: most skills have no newer version waiting. Reporting a
        // confirmation for every one of them is a pass for a question nobody asked.
        #expect(SkillChecks.updateWantsNoMore(CheckFixtures.skill(held: nil)).verdict == .notApplicable)
        #expect(
            SkillChecks.updateWantsNoMore(
                CheckFixtures.skill(held: HeldVersion(pluginVersion: "0.5.0"))
            ).verdict == .passed
        )
        #expect(
            SkillChecks.updateWantsNoMore(
                CheckFixtures.skill(held: HeldVersion(pluginVersion: "0.5.0", addedCapabilities: ["network"]))
            ).verdict == .failed
        )

        // A standalone skill has no marketplace, so an unmoved origin is not something that can be
        // true of it.
        let standalone = CheckFixtures.skill(source: .standalone(path: "/skills/hand-placed"))
        #expect(SkillChecks.originUnchanged(standalone).verdict == .notApplicable)

        // A transport with no credentials has none to be current.
        #expect(ServerChecks.authorized(CheckFixtures.server(authSupported: false)).verdict == .notApplicable)
        #expect(
            ServerChecks.authorized(CheckFixtures.server(authSupported: true, authAuthorized: false)).verdict
                == .failed
        )
    }

    // MARK: - A6: reachable, over both unreadable signals and a missing key

    @Test("A6: reachability is unobserved when either unreadable signal fires")
    func reachableUnknownOnEitherSignal() {
        let clients = [CheckFixtures.client("claude"), CheckFixtures.client("cursor")]

        // Signal one: the per-CLIENT status.
        let byStatus = SkillChecks.reachable(
            CheckFixtures.skill(presence: ["claude": .absent, "cursor": .absent]),
            clients: [CheckFixtures.client("claude"), CheckFixtures.client("cursor", status: .unreadable)]
        )
        #expect(byStatus.verdict == .unknown, "SkillClientStatus.unreadable must suspend the judgement")

        // Signal two: the per-SKILL-per-client presence.
        let byPresence = SkillChecks.reachable(
            CheckFixtures.skill(presence: ["claude": .absent, "cursor": .unreadable]),
            clients: clients
        )
        #expect(byPresence.verdict == .unknown, "SkillPresence.unreadable must suspend it too")

        // Neither signal: every capable client was read and none has it.
        let readEverywhere = SkillChecks.reachable(
            CheckFixtures.skill(presence: ["claude": .absent, "cursor": .absent]),
            clients: clients
        )
        #expect(readEverywhere.verdict == .failed)

        // Present anywhere wins over everything.
        #expect(
            SkillChecks.reachable(
                CheckFixtures.skill(presence: ["claude": .present, "cursor": .unreadable]),
                clients: clients
            ).verdict == .passed
        )
    }

    @Test("A6: a missing presence key is not evidence of absence")
    func missingPresenceKeyIsNotAbsence() {
        // `presence` is a dictionary, not an exhaustive map. A client whose directory could not be
        // read may carry no key at all — and treating that as "not installed here" would declare a
        // skill loadable by nobody on the strength of a lookup that never happened.
        let result = SkillChecks.reachable(
            CheckFixtures.skill(presence: [:]),
            clients: [CheckFixtures.client("claude"), CheckFixtures.client("cursor", status: .unreadable)]
        )
        #expect(result.verdict == .unknown)
    }

    @Test("An unsupported client never contributes to either branch")
    func unsupportedClientsAreNotCounted() {
        let result = SkillChecks.reachable(
            CheckFixtures.skill(presence: ["claude": .present]),
            clients: [
                CheckFixtures.client("claude"),
                CheckFixtures.client("codex", supports: false, status: .unsupported)
            ]
        )
        #expect(result.verdict == .passed)
    }

    // MARK: - Totality

    @Test("Every check is total: eleven results, one per id, for any input")
    func checksAreTotal() {
        let results = ServerChecks.all(CheckFixtures.server()) + SkillChecks.all(
            CheckFixtures.skill(),
            clients: [CheckFixtures.client("claude")]
        )
        #expect(results.count == CheckID.allCases.count)
        #expect(Set(results.map(\.check)) == Set(CheckID.allCases))
    }

    @Test("A17: every verdict carries the statement it judges")
    func verdictsNeverTravelAlone() {
        // Structural rather than a string ban: `CheckResult` carries its statement, so there is no
        // call site holding a verdict without the sentence it is about.
        for check in CheckID.allCases {
            let result = CheckResult(check, .passed)
            #expect(!result.statement.isEmpty, "\(check.rawValue) has no statement")
        }
    }

    @Test("A17b: the verdict vocabulary carries no grading verb")
    func vocabularyIsObservationNotGrading() {
        let banned = ["pass", "passed", "fail", "failed", "graded", "score", "grade"]
        for word in CheckCopy.verdictVocabulary {
            #expect(
                !banned.contains(word.lowercased()),
                "\"\(word)\" is test-suite vocabulary, not observation vocabulary"
            )
        }
        #expect(CheckCopy.tallyNoun(for: .passed) == "confirmed")
        #expect(CheckCopy.tallyNoun(for: .failed) == "not met")
        #expect(CheckCopy.tallyNoun(for: .unknown) == "not observed")
    }

    // MARK: - A18/A19/A20: the disclosure

    @Test("A18: the subtitle carries its disclosure, unconditionally")
    func subtitleAlwaysDiscloses() {
        #expect(CheckCopy.evalsSubtitle.contains("No model-graded evaluation exists in this product"))
    }

    @Test("A19: the footer states skills are never executed by the router")
    func footerStatesSkillsAreNeverExecuted() {
        #expect(CheckCopy.evalsFooter.contains("Skills are never executed by the router"))
    }

    // MARK: - A20b: the input behind each check

    @Test("A20b: every check reports the field and value it was computed from")
    func everyCheckShowsItsInput() {
        // The footer promises a check is "something MCP Router performed and can show you the input
        // to". Without this the promise is unverifiable by the reader, and a derived row is
        // indistinguishable from a grade.
        let server = CheckFixtures.server()
        for check in CheckID.allCases where check.subjectKind == .server {
            let input = ServerChecks.input(check, server)
            #expect(input.contains("="), "\(check.rawValue) input names no field: \(input)")
            #expect(input != "not a server check")
        }
        let skill = CheckFixtures.skill()
        let clients = [CheckFixtures.client("claude")]
        for check in CheckID.allCases where check.subjectKind == .skill {
            let input = SkillChecks.input(check, skill, clients: clients)
            #expect(!input.isEmpty)
            #expect(input != "not a skill check")
        }
    }

    // MARK: - A10b: history invalidation

    @Test("A10b: a run gathered against a moved stamp is invalidated, over the cross product")
    func historyInvalidation() throws {
        let stamps = ["abc123", "def456"]
        for stored in stamps {
            for live in stamps {
                let run = try StoredRun(
                    stamp: #require(Stamp(stored)),
                    ranAt: Date(),
                    results: [CheckResult(.indexes, .passed)]
                )
                let state = CheckPresentation.historyRowState(run: run, live: Stamp(live))
                if stored == live {
                    #expect(!state.isInvalidated, "\(stored) vs \(live)")
                } else {
                    #expect(state.isInvalidated, "\(stored) vs \(live)")
                    #expect(state.label.contains(stored) && state.label.contains(live))
                }
            }
        }
    }

    @Test("A12: a subject with no live stamp cannot produce one")
    func unstampableSubjectsHaveNoStamp() {
        // Structural, not a rule the caller remembers: `Stamp`'s initialiser is failable and the
        // standalone case of `SkillSource` has no version field for a careless default to fill in.
        #expect(Stamp.forSkill(CheckFixtures.skill(source: .standalone(path: "/x"))) == nil)
        #expect(Stamp.forServer(CheckFixtures.server(hash: nil)) == nil)
        #expect(Stamp.forServer(CheckFixtures.server(hash: "")) == nil)
        #expect(Stamp.forServer(CheckFixtures.server(hash: "abc123"))?.value == "abc123")
    }

    // MARK: - The tally

    @Test("The tally is a list of segments and cannot collapse to one word")
    func tallyIsSegments() {
        let results = [
            CheckResult(.indexes, .passed),
            CheckResult(.declaresTools, .passed),
            CheckResult(.authorized, .notApplicable),
            CheckResult(.operative, .failed),
            CheckResult(.callsSucceed, .unknown)
        ]
        let segments = CheckPresentation.tally(results)
        #expect(segments.count == 4)
        #expect(segments.first { $0.verdict == .passed }?.count == 2)
        // Only "not met" is tinted, and it is tinted with the token that literally means it.
        let tinted = segments.filter { $0.token == .fail }.map(\.verdict)
        #expect(tinted == [.failed])
    }

    @Test("A filter with no matches carries no badge rather than a zero")
    func zeroCountCarriesNoBadge() {
        let subject = CheckPresentation.subject(for: CheckFixtures.server())
        #expect(CheckPresentation.count([subject], filter: .notMet, search: "") == nil)
        #expect(CheckPresentation.count([subject], filter: .all, search: "") == 1)
    }

    @Test("A13b: an unstamped subject has a filter segment of its own")
    func unstampedIsReachable() {
        let standalone = CheckPresentation.subject(
            for: CheckFixtures.skill(source: .standalone(path: "/skills/hand")),
            clients: [CheckFixtures.client("claude")]
        )
        #expect(standalone.stamp == nil)
        #expect(CheckPresentation.rows([standalone], filter: .unstamped, search: "").count == 1)
    }

    @Test("A28: row order is the router's own, servers then skills, stable")
    func rowOrderIsStable() {
        let servers = [CheckFixtures.server(name: "zeta"), CheckFixtures.server(name: "alpha")]
        let skills = SkillsResponse(
            skills: [CheckFixtures.skill(name: "b", path: "/b"), CheckFixtures.skill(name: "a", path: "/a")],
            clients: [CheckFixtures.client("claude")]
        )
        let names = CheckPresentation.subjects(servers: servers, skills: skills).map(\.name)
        #expect(names == ["zeta", "alpha", "b", "a"], "never re-sorted; the router's order is the order")
    }
}
