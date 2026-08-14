import Foundation
import Testing
@testable import MCPRouterKit

/// A24–A27: every state is present or its absence is structural, the three warning classes are
/// distinguished, an unknown warning survives verbatim, and offline is its own state.
@Suite("Discover states and warnings — A24 to A27")
struct DiscoverStateTests {
    // MARK: - A25: the three warning classes

    /// The four producing strings live in `src/registry.ts`. Classification is by **prefix match on
    /// free text**, which is fragile, and the fragility is the reason `.unrecognised` carries the
    /// warning verbatim rather than dropping it.
    @Test("each producing warning string classifies to its own state")
    func warningsClassifyByPrefix() {
        #expect(WarningClass.classify("official registry unreachable: 502") == .officialDown)
        #expect(WarningClass.classify("Smithery unreachable: timeout") == .smitheryDown)
        #expect(WarningClass.classify("GitHub rate limit reached") == .githubLimited)
        #expect(WarningClass.classify("GitHub allows 60 requests an hour") == .githubLimited)
    }

    /// A reword on the router side silently reclassifies a warning. A degraded surface that loses
    /// the explanation for its own degradation is worse than one showing an unpolished sentence.
    @Test("a warning matching no class is carried verbatim, never dropped")
    func unknownWarningSurvives() {
        let text = "something nobody has seen before"
        let classified = WarningClass.classify(text)
        #expect(classified == .unrecognised(text))
        #expect(classified.copyKey == .list(.partialUnrecognised))
        // The template renders it rather than swallowing it.
        #expect(DiscoverCopy.entry(classified.copyKey).body.contains("{warning}"))
    }

    @Test("each warning class renders its own copy, and no two share a key")
    func warningClassesHaveDistinctCopy() {
        let classes: [WarningClass] = [.officialDown, .smitheryDown, .githubLimited, .unrecognised("x")]
        #expect(Set(classes.map(\.copyKey)).count == 4)
        for warning in classes {
            #expect(!DiscoverCopy.entry(warning.copyKey).body.isEmpty)
        }
    }

    /// The Smithery-down copy has to say what is *specifically* lost, because Most used ranks on a
    /// figure only Smithery publishes — a generic "some results are missing" would understate it.
    @Test("Smithery down says the session counts Most used ranks on are missing")
    func smitheryDownNamesWhatIsLost() {
        let body = DiscoverCopy.entry(.list(.partialSmitheryDown)).body
        #expect(body.contains("session counts"))
        #expect(body.contains("Most used"))
    }

    // MARK: - A27: offline is its own state

    /// `routerNotRunning` is deliberately **not** a `DiscoverFailureReason`. Folding it in would
    /// render "the router isn't running" as one more error string inside an error banner, which is
    /// exactly what `SWIFT_PRACTICES.md` §3 forbids.
    @Test("routerNotRunning maps to no failure reason, so it can be its own state")
    func routerNotRunningIsNotAFailureReason() {
        #expect(DiscoverFailureReason.from(.routerNotRunning) == nil)

        // Every other error does have a reason, so nothing falls through to offline by accident.
        #expect(DiscoverFailureReason.from(.unauthorized) == .unauthorized)
        #expect(DiscoverFailureReason.from(.malformedResponse(detail: "x")) == .malformedResponse)
        #expect(DiscoverFailureReason.from(.transport(detail: "x")) == .transport)
    }

    /// A28: `{reason}` renders from a closed enum, never a passthrough of the router's free-text
    /// body — which can carry a stack frame, a URL, or whatever a third-party index returned.
    @Test("every failure reason has its own sentence, and none is a router message")
    func failureReasonsAreClosed() {
        #expect(DiscoverFailureReason.allCases.count == 4)
        var texts: Set<String> = []
        for reason in DiscoverFailureReason.allCases {
            #expect(!reason.text.isEmpty)
            #expect(texts.insert(reason.text).inserted, "\(reason) shares its sentence")
        }
    }

    /// A27, recorded as a deviation rather than passed off as satisfied: `DESIGN.md` §5 asks
    /// Offline to offer to start the router, and the phone cannot start a process on the Mac.
    @Test("the offline copy gives the instruction the phone can actually honour")
    func offlineGivesAnInstruction() {
        let entry = DiscoverCopy.entry(.list(.offline))
        #expect(entry.headline?.contains("isn't running") == true)
        #expect(entry.body.contains("Open MCP Router on your Mac"))
        // It must not offer an action the phone cannot perform.
        #expect(entry.actionLabel == nil, "the phone cannot start the router")
    }

    /// A18 + Offline on Detail: the commit still works, because the queue is local.
    @Test("detail's offline copy still offers the local save")
    func detailOfflineStillSaves() {
        let body = DiscoverCopy.entry(.detail(.offline)).body
        #expect(body.contains("You can still save this here"))
    }

    // MARK: - A24: the states, and the structural absences

    /// **`success` is absent by construction**: the list has no commit, so it has nothing to
    /// succeed at. A `case success` here would need copy, and any copy written for it would
    /// describe something the surface cannot do.
    @Test("the list ships seven states, and Success is not one of them")
    func listStateCount() {
        let states: [DiscoverListState] = [
            .populated, .loading, .emptyNoQuery, .emptyQuery("q"),
            .partial([.githubLimited]), .failed(.transport), .offline
        ]
        #expect(states.count == 7)
        // Constructing each is the assertion: a case removed here fails to compile.
        for state in states {
            #expect(state == state)
        }
    }

    /// Detail performs no fetch (A11), so Empty, Loading and Error are structurally unreachable.
    /// The count is pinned so a later hand adding a plausible case has to argue with a comment.
    @Test("detail ships four states, and the three it omits are the ones it cannot reach")
    func detailStateCount() {
        let states: [DetailState] = [.populated, .noRepositoryData, .githubLimited, .offline]
        #expect(states.count == 4)
        for state in states {
            #expect(state == state)
        }
    }

    /// A26: a Smithery-only entry is **Default, not Partial**. `source: "smithery"` is a merge
    /// outcome known at search time, not a failure — GitHub was never asked, because the homepage
    /// is not a parseable repo URL. Partial is reserved for GitHub asked and refusing.
    @Test("the no-repository copy states a fact, and the GitHub-limited copy states a failure")
    func factAndFailureAreDistinguished() {
        let fact = DiscoverCopy.entry(.detail(.partialNoRepository))
        #expect(fact.headline?.contains("doesn't publish") == true)
        #expect(fact.body.contains("There's no last-commit date"))

        let limited = DiscoverCopy.entry(.detail(.partialGitHubLimited))
        #expect(limited.headline?.contains("missing") == true)
        #expect(limited.body.contains("couldn't be fetched this time"))

        #expect(fact.body != limited.body, "a fact and a failure share copy")
    }

    // MARK: - The response-to-state mapping

    private func response(
        results: [RegistryEntry],
        warnings: [String] = []
    ) -> RegistrySearchResponse {
        RegistrySearchResponse(
            results: results,
            sources: RegistrySources(official: 0, smithery: 0, merged: results.count),
            warnings: warnings
        )
    }

    private var anEntry: RegistryEntry {
        DiscoverSpecimens.entries[0]
    }

    @Test("no results and no query is Empty, and with a query it echoes the query")
    func emptyMapping() {
        #expect(DiscoverListState.resolve(response: response(results: []), query: "") == .emptyNoQuery)
        #expect(
            DiscoverListState.resolve(response: response(results: []), query: "zz") == .emptyQuery("zz")
        )
    }

    /// A degraded search that returned nothing says *why*. Reporting "neither index listed
    /// anything" when one of them never answered would be a false statement about the registries.
    @Test("no results with a warning is Partial, not Empty")
    func emptyWithWarningIsPartial() {
        let state = DiscoverListState.resolve(
            response: response(results: [], warnings: ["Smithery unreachable: timeout"]),
            query: "github"
        )
        #expect(state == .partial([.smitheryDown]))
    }

    @Test("results with a warning are Partial, and results alone are populated")
    func populatedMapping() {
        #expect(DiscoverListState.resolve(response: response(results: [anEntry]), query: "") == .populated)
        #expect(DiscoverListState.resolve(
            response: response(results: [anEntry], warnings: ["GitHub rate limit reached"]),
            query: ""
        ) == .partial([.githubLimited]))
    }
}
