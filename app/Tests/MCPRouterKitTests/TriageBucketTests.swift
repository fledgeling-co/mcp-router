import Foundation
import Testing
@testable import MCPRouterKit

/// The derived sets Triage draws its three segments from (A7), and the one line every row carries
/// (A5, A6).
///
/// These run on the macOS host and are about **derivation**, not geometry: what a 44pt target
/// measures and what wraps on a 393pt-wide phone are asserted in `MCPRouterIOSTests`, because
/// asserting them here would be a green light for something nobody measured.
@Suite("Triage buckets and the capability summary")
struct TriageBucketTests {
    // MARK: - A7: Undecided is derived, never fetched

    @Test("undecided is results minus queued minus dismissed")
    func undecidedIsTheDifference() {
        let buckets = TriageBuckets.resolve(
            results: TriageSpecimens.all,
            queuedIDs: [TriageSpecimens.stdio.id],
            dismissedIDs: [TriageSpecimens.archived.id]
        )

        #expect(buckets.queued.map(\.id) == [TriageSpecimens.stdio.id])
        #expect(buckets.dismissed.map(\.id) == [TriageSpecimens.archived.id])
        #expect(buckets.undecided.count == TriageSpecimens.all.count - 2)
        #expect(!buckets.undecided.contains { $0.id == TriageSpecimens.stdio.id })
        #expect(!buckets.undecided.contains { $0.id == TriageSpecimens.archived.id })
    }

    /// The only reason a count is permitted on this surface at all: each is the size of a set the
    /// user's own decisions produced (A8, A26).
    @Test("every segment count is the size of its own bucket")
    func countsComeOffTheSets() {
        let buckets = TriageBuckets.resolve(
            results: TriageSpecimens.all,
            queuedIDs: [TriageSpecimens.stdio.id, TriageSpecimens.remote.id],
            dismissedIDs: [TriageSpecimens.archived.id]
        )

        #expect(buckets.count(in: .queued) == 2)
        #expect(buckets.count(in: .dismissed) == 1)
        #expect(buckets.count(in: .undecided) == TriageSpecimens.all.count - 3)

        // Not `count(in:) == entries(in:).count` — `count(in:)` is *defined* as that, so the
        // comparison is a tautology. The property the surface actually depends on is that the three
        // segments partition the results: no entry is in two buckets and none is dropped.
        let total = TriageBucket.allCases.reduce(0) { $0 + buckets.count(in: $1) }
        #expect(
            total == TriageSpecimens.all.count,
            "the three buckets do not partition the results: \(total) of \(TriageSpecimens.all.count)"
        )
    }

    /// Stated in the type's own comment, so it is asserted rather than left to a reader: queueing is
    /// the later and more consequential act, so an entry in both sets reads as queued.
    @Test("an entry that is both queued and dismissed reads as queued")
    func queuedOutranksDismissed() {
        let buckets = TriageBuckets.resolve(
            results: [TriageSpecimens.stdio],
            queuedIDs: [TriageSpecimens.stdio.id],
            dismissedIDs: [TriageSpecimens.stdio.id]
        )

        #expect(buckets.queued.count == 1)
        #expect(buckets.dismissed.isEmpty)
        #expect(buckets.undecided.isEmpty)
    }

    /// A7's named exception. `installed` is a display-name collision test rather than an identity
    /// match (I2 A23), so filtering on it would silently hide rows on a heuristic that both
    /// false-positives and misses on case.
    @Test("an entry flagged installed is still offered in Undecided")
    func installedIsNotAFilter() {
        var installed = TriageSpecimens.stdio
        installed.installed = true

        let buckets = TriageBuckets.resolve(results: [installed], queuedIDs: [], dismissedIDs: [])

        #expect(buckets.undecided.map(\.id) == [installed.id])
    }

    /// Only Undecided offers a batch act, so only Undecided draws checkboxes.
    @Test("only the Undecided bucket is selectable")
    func onlyUndecidedIsSelectable() {
        #expect(TriageBucket.undecided.isSelectable)
        #expect(!TriageBucket.queued.isSelectable)
        #expect(!TriageBucket.dismissed.isSelectable)
    }

    // MARK: - A6: seven clauses, one derivation

    @Test("each of the seven plate outcomes maps to its own clause")
    func sevenClauses() {
        let cases: [(RegistryEntry, CapabilitySummary.Clause)] = [
            (TriageSpecimens.stdio, .runsLocally),
            (TriageSpecimens.remote, .remote),
            (TriageSpecimens.remoteUnknownHost, .remoteUnknownHost),
            (TriageSpecimens.credentialElsewhere, .credential),
            (TriageSpecimens.credentialSmithery, .credentialSmithery),
            (TriageSpecimens.archived, .archived),
            (TriageSpecimens.noInstall, .noInstall)
        ]

        for (entry, clause) in cases {
            let resolved = CapabilitySummary.resolve(for: entry)
            #expect(
                resolved.clauses.contains(clause),
                "\(entry.id) did not produce \(clause): got \(resolved.clauses)"
            )
        }
    }

    /// The clause vocabulary is closed, which is the only thing that makes "this line never
    /// truncates" (A5) a guarantee rather than a hope about entry names.
    /// **Not `allCases.contains(clause)`** — that is true for every value of a `CaseIterable` enum,
    /// including a broken one, so the first version of this test could not fail. What can break is
    /// the vocabulary growing without the row learning to render it, and a clause rendering to
    /// nothing or to an unsubstituted token.
    @Test("the clause vocabulary is seven, and every one of them renders")
    func vocabularyIsClosed() {
        #expect(
            CapabilitySummary.Clause.allCases.count == 7,
            "the clause vocabulary changed size — an eighth clause is a deliberate edit, not a drift"
        )

        for clause in CapabilitySummary.Clause.allCases {
            // Rendered through the same path the row uses, so a clause the presentation cannot
            // render fails here rather than reaching a user as a blank or a literal `{host}`.
            let text = TriagePresentation.summaryText(CapabilitySummary.Resolved(
                clauses: [clause],
                host: "example.com",
                wantsAttention: clause.wantsAttention,
                isSelectable: true
            ))
            #expect(!text.isEmpty, "\(clause) renders nothing")
            #expect(!text.contains("{"), "\(clause) renders an unsubstituted token: \(text)")
        }
    }

    /// A remote install whose URL will not parse has no host, and the four-row table this replaces
    /// would have rendered the literal `{host}` or an empty segment on the one clause that says
    /// where the user's tool arguments go.
    @Test("a remote install with an unparseable URL says so instead of naming an empty host")
    func unknownHostIsItsOwnClause() {
        let resolved = CapabilitySummary.resolve(for: TriageSpecimens.remoteUnknownHost)

        #expect(resolved.clauses.contains(.remoteUnknownHost))
        #expect(!resolved.clauses.contains(.remote))
        #expect(resolved.host == nil)

        let text = TriagePresentation.summaryText(resolved)
        #expect(!text.contains("{host}"), "an unsubstituted token reached the row: \(text)")
        #expect(!text.isEmpty)
    }

    @Test("a remote install whose URL parses names the host")
    func remoteNamesItsHost() {
        let resolved = CapabilitySummary.resolve(for: TriageSpecimens.remote)

        #expect(resolved.host == "mcp.example.com")
        #expect(TriagePresentation.summaryText(resolved).contains("mcp.example.com"))
    }

    // MARK: - A6: the colour rule, and the noise it exists to prevent

    /// Running a program on the user's Mac is the case the attention colour exists for.
    @Test("a stdio install wants attention")
    func stdioWantsAttention() {
        #expect(CapabilitySummary.resolve(for: TriageSpecimens.stdio).wantsAttention)
    }

    /// A secret on a host that is not Smithery's carries real signal.
    @Test("a credential on a non-Smithery host wants attention")
    func credentialElsewhereWantsAttention() {
        #expect(CapabilitySummary.resolve(for: TriageSpecimens.credentialElsewhere).wantsAttention)
    }

    /// **The assertion this criterion exists for.** Every Smithery-hosted install declares a
    /// required `Authorization` unconditionally (`src/registry.ts:172-179`), so within that subset
    /// the credential clause distinguishes nothing — and Smithery is a majority of the corpus, so
    /// an unconditional attention severity there paints the colour on most rows and stops it
    /// meaning anything. `CapabilityPlate` already admits this by choosing a different copy key;
    /// the summary has to carry the admission through in **colour**, which is the half a copy-key
    /// check cannot see.
    @Test("a Smithery credential does not want attention, because it distinguishes nothing")
    func smitheryCredentialIsNotNoise() {
        let resolved = CapabilitySummary.resolve(for: TriageSpecimens.credentialSmithery)

        #expect(resolved.clauses.contains(.credentialSmithery))
        #expect(
            !resolved.wantsAttention,
            "the Smithery credential fired the attention colour, which is the noise A6 forbids"
        )
    }

    /// A fact about the repository, not about what runs.
    @Test("archived alone does not want attention")
    func archivedIsAFact() {
        #expect(!CapabilitySummary.resolve(for: TriageSpecimens.archived).wantsAttention)
    }

    @Test("a remote install with no secret does not want attention")
    func plainRemoteIsAFact() {
        #expect(!CapabilitySummary.resolve(for: TriageSpecimens.remote).wantsAttention)
        #expect(!CapabilitySummary.resolve(for: TriageSpecimens.remoteUnknownHost).wantsAttention)
    }

    /// Colour is never the only signal (A6, A27): the attention set and the clause set move
    /// together, so a row that wants attention always states a reason in words.
    @Test("anything wanting attention also states its reason in words")
    func attentionAlwaysCarriesWords() {
        for entry in TriageSpecimens.all {
            let resolved = CapabilitySummary.resolve(for: entry)
            guard resolved.wantsAttention else { continue }
            #expect(
                !TriagePresentation.summaryText(resolved).isEmpty,
                "\(entry.id) wants attention and says nothing"
            )
        }
    }

    // MARK: - A6: one derivation, two renderings

    /// The row and the detail plate must not come to disagree about the same entry — the row is the
    /// half nobody would check.
    @Test("the row's clauses agree with the plate's lines on every specimen")
    func rowAndPlateAgree() {
        // **Correspondence, not cardinality.** Comparing counts was provably always true: both
        // sides are the same `lines` array compact-mapped through the same filter, so the counts
        // are equal by construction for every input — including one where `clause(for:)` maps the
        // wrong key, which is the single thing this test exists to catch. The expected mapping is
        // therefore declared here, independently of the implementation.
        let expected: [DiscoverCopy.PlateKey: CapabilitySummary.Clause] = [
            .stdio: .runsLocally,
            .remote: .remote,
            .unknownHost: .remoteUnknownHost,
            .credential: .credential,
            .credentialSmithery: .credentialSmithery,
            .archived: .archived,
            .noInstall: .noInstall
        ]

        for entry in TriageSpecimens.all {
            let resolved = CapabilitySummary.resolve(for: entry)
            let plateKeys = CapabilityPlate.lines(install: entry.install, archived: entry.archived)
                .compactMap { line -> DiscoverCopy.PlateKey? in
                    guard case let .plate(key) = line.copyKey else { return nil }
                    return key
                }
                .filter { $0 != .invocationLabel }

            #expect(
                resolved.clauses == plateKeys.compactMap { expected[$0] },
                "\(entry.id): row \(resolved.clauses) does not correspond to plate \(plateKeys)"
            )
        }
    }

    /// An entry with no descriptor has nothing for the Mac to review, so it never reaches the
    /// commit (A6, A12).
    @Test("an entry with no install descriptor is not selectable")
    func noInstallIsNotSelectable() {
        #expect(!CapabilitySummary.resolve(for: TriageSpecimens.noInstall).isSelectable)
        for entry in TriageSpecimens.all where entry.install != nil {
            #expect(CapabilitySummary.resolve(for: entry).isSelectable, "\(entry.id) lost selectability")
        }
    }

    /// The Queue renders a `QueuedCapability`, which carries an `install` but is not a
    /// `RegistryEntry`. Both overloads must produce the same summary or the same entry reads two
    /// ways on two surfaces.
    @Test("the install-only overload agrees with the entry overload")
    func overloadsAgree() {
        for entry in TriageSpecimens.all {
            let fromEntry = CapabilitySummary.resolve(for: entry)
            let fromInstall = CapabilitySummary.resolve(install: entry.install, archived: entry.archived)
            #expect(fromEntry == fromInstall, "\(entry.id) resolves differently through the two overloads")
        }
    }
}
