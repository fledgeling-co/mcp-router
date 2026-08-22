import Foundation
import Testing
@testable import MCPRouterKit

/// M12 — what a destructive dialog says about the age of the figures in it.
///
/// Two findings from M7's Phase D critic, both graded VALID and deferred to here: a `.stale` reading
/// shown in the present tense with no marker, and no as-of time for calls accruing between the poll
/// and the POST. Every branch of both is enumerated here as a pure function — two `Date`s and an
/// `Int?` in, a `Provenance` out — because that is the layer at which "the wording is right" is a
/// claim and not a hope.
@Suite("Cleanup — where a destructive dialog's figures came from")
struct CleanupProvenanceTests {
    /// A fixed pair of instants. Nothing here sleeps, and nothing reads the wall clock: a test that
    /// has to wait to reach a boundary is a test that proves nothing (`SWIFT_PRACTICES.md` §7).
    static let now = Date(timeIntervalSince1970: 1_755_000_000)
    static func earlier(by seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    // MARK: - The stamp

    /// The stamp is a **clock time**, not an elapsed age, and this is the reason.
    ///
    /// A relative phrase is computed when the view body runs, and a modal's body does not re-run
    /// while it sits open — nothing it reads changes with the clock. A dialog left open would go on
    /// saying "3m ago" indefinitely: a figure reading as fresher than it is, which is the defect M12
    /// exists to remove, rebuilt one line below the fix. The assertion is that the label does not
    /// move with `now` for the same `observedAt`.
    @Test("the as-of stamp does not decay while the dialog stays open")
    func theStampIsAbsoluteRatherThanElapsed() {
        let observed = Self.earlier(by: 60)
        let atOpen = CleanupPresentation.asOfLabel(observed, now: Self.now)
        let fifteenMinutesLater = CleanupPresentation.asOfLabel(
            observed,
            now: Self.now.addingTimeInterval(900)
        )
        #expect(
            atOpen == fifteenMinutesLater,
            "the as-of stamp changed with the render time — a relative age, not an as-of time"
        )
    }

    /// Same day states a time; another day states the date as well.
    ///
    /// Asserted as a **branch**, not as a literal: the formatter is locale-driven
    /// (`setLocalizedDateFormatFromTemplate`), so pinning "14:32" here would fail on any machine
    /// whose region formats a time differently. What is worth testing is that the two cases differ —
    /// a reading from yesterday must not render identically to one from this afternoon.
    @Test("a reading from another day is not stamped like one from today")
    func anotherDayCarriesItsDate() {
        let today = CleanupPresentation.asOfLabel(Self.earlier(by: 600), now: Self.now)
        let yesterday = CleanupPresentation.asOfLabel(Self.earlier(by: 30 * 3600), now: Self.now)
        #expect(today != yesterday, "a reading 30 hours old is stamped like one ten minutes old")
        #expect(!today.isEmpty)
    }

    // MARK: - The reset dialog

    @Test("a current reading is dated quietly, and says the figure is a floor")
    func aCurrentReadingIsDatedQuietly() {
        let provenance = CleanupPresentation.resetFigureProvenance(
            observedAt: Self.earlier(by: 180),
            isStale: false,
            calls: 812,
            now: Self.now
        )
        guard case let .quiet(text) = provenance else {
            Issue.record("a current reading was not quiet: \(provenance)")
            return
        }
        let stamp = CleanupPresentation.asOfLabel(Self.earlier(by: 180), now: Self.now)
        #expect(text.contains("taken at \(stamp)"))
        // Finding 8: what accrues between the poll and the POST is discarded too, and is not in the
        // figure. Without this clause the count reads as the whole of what is lost.
        #expect(text.contains("recorded after that is discarded as well"))
    }

    /// Finding 4. The marker is the board's own sentence, not a second phrasing for the modal.
    @Test("a stale reading is marked, in the words the board already uses")
    func aStaleReadingIsMarked() {
        let provenance = CleanupPresentation.resetFigureProvenance(
            observedAt: Self.earlier(by: 180),
            isStale: true,
            calls: 812,
            now: Self.now
        )
        guard case let .marked(text) = provenance else {
            Issue.record("a stale reading was not marked: \(provenance)")
            return
        }
        #expect(text.contains("the last reading the router gave"))
        #expect(text.contains("nothing about it is current"))
        #expect(text.contains("recorded after that is discarded as well"))
    }

    /// The branch is `calls != nil`, and reading it as `calls > 0` is the whole of mutation M2.
    ///
    /// An observed zero is a figure and it is the figure most in need of a date: "there is nothing
    /// to discard" is the claim likeliest to have gone false since the reading was taken. M7's
    /// finding 1 was this same trap one layer down.
    @Test("an observed zero is dated; an unobserved count is not")
    func zeroIsAFigureAndNilIsNot() {
        let observed = Self.earlier(by: 180)
        let zero = CleanupPresentation.resetFigureProvenance(
            observedAt: observed, isStale: false, calls: 0, now: Self.now
        )
        let unobserved = CleanupPresentation.resetFigureProvenance(
            observedAt: observed, isStale: false, calls: nil, now: Self.now
        )
        #expect(zero != .none, "an observed zero was left undated")
        #expect(
            unobserved == CleanupPresentation.Provenance.none,
            "a figure the router never gave was dated anyway: \(unobserved)"
        )

        // And the zero sentence does not contradict the consequence sitting above it, which says
        // there is nothing to discard. It must not claim a figure the reader cannot see.
        guard case let .quiet(text) = zero else {
            Issue.record("an observed zero was not quiet: \(zero)")
            return
        }
        #expect(!text.contains("This figure"), "the zero line points at a figure that is not drawn")
        #expect(text.contains("count was zero"))
    }

    /// A stale reading whose summary never answered gets its own sentence.
    ///
    /// Saying only "this is the last reading the router gave" under a consequence that says the
    /// router never gave a number reads as a claim about the count. It says what is true of the
    /// count instead.
    @Test("a stale reading with no count says so, rather than implying one")
    func aStaleReadingWithNoCountSaysSo() {
        let provenance = CleanupPresentation.resetFigureProvenance(
            observedAt: Self.earlier(by: 180),
            isStale: true,
            calls: nil,
            now: Self.now
        )
        guard case let .marked(text) = provenance else {
            Issue.record("a stale reading with no count was not marked: \(provenance)")
            return
        }
        #expect(text.contains("carried no call count"))
        #expect(
            !text.contains("discarded as well"),
            "the accrual clause qualifies a figure that this branch does not have"
        )
    }

    // MARK: - The removal dialog

    /// It does not enumerate what it is the provenance of, and that is deliberate.
    ///
    /// The obvious wording — "the tool count and the key names above" — is false for a server
    /// carrying neither env nor header keys: `removeConsequence` draws *"Nothing secret is stored on
    /// this entry"* for that case and prints no key names at all, so the line would claim provenance
    /// over something the reader cannot see. That consequence lives in `MCPRouterUI`, which this
    /// target cannot import, so the premise is checked from the UI side in
    /// `CleanupProvenanceModelTests.theRemovalLinesPremiseHolds`; this half asserts the line itself.
    @Test("the removal line claims provenance over nothing the dialog may not have drawn")
    func theRemovalLineClaimsNothingAbsent() throws {
        for stale in [false, true] {
            let text = try #require(
                CleanupPresentation.removeFigureProvenance(
                    observedAt: Self.earlier(by: 180), isStale: stale, now: Self.now
                ).text
            )
            #expect(!text.contains("key names"))
            #expect(!text.contains("tool count"))
        }
    }

    @Test("the removal dialog dates its reading, and marks it when it is stale")
    func theRemovalDialogDatesItsReading() {
        let observed = Self.earlier(by: 180)
        let stamp = CleanupPresentation.asOfLabel(observed, now: Self.now)

        let fresh = CleanupPresentation.removeFigureProvenance(
            observedAt: observed, isStale: false, now: Self.now
        )
        guard case let .quiet(freshText) = fresh else {
            Issue.record("a current reading was not quiet: \(fresh)")
            return
        }
        #expect(freshText.contains("read at \(stamp)"))

        let stale = CleanupPresentation.removeFigureProvenance(
            observedAt: observed, isStale: true, now: Self.now
        )
        guard case let .marked(staleText) = stale else {
            Issue.record("a stale reading was not marked: \(stale)")
            return
        }
        #expect(staleText.contains("nothing about it is current"))
        #expect(staleText.contains("may have changed"))
    }

    // MARK: - What provenance may not do

    /// It may not restate the figure, and it may not invent one.
    ///
    /// Restating would give the dialog two places to be wrong about the same number, and the pair
    /// could then disagree. Inventing is `DESIGN.md` §6's last bullet. The count is fed in at a value
    /// that appears nowhere in a date, so a line that echoed it would be visible here.
    @Test("provenance never restates the count and never invents a number")
    func provenanceRestatesNoFigure() {
        let observed = Self.earlier(by: 180)
        for stale in [false, true] {
            let text = CleanupPresentation.resetFigureProvenance(
                observedAt: observed, isStale: stale, calls: 4747, now: Self.now
            ).text ?? ""
            #expect(!text.contains("4747"), "the provenance line restates the count: \(text)")
        }
    }

    /// C8 — the shared consequence is not what this item changed.
    ///
    /// Two boards call `resetConsequence` so that they cannot tell the user different things about
    /// the same irreversible act. This item adds a line beside it and must not have edited it: if a
    /// provenance sentence has migrated into the consequence, these three fail.
    @Test("C8: the shared consequence sentence is untouched by the provenance layer")
    func theSharedConsequenceIsUntouched() {
        let window = CleanupPresentation.window(
            since: ISO8601DateFormatter().string(from: Self.earlier(by: 41 * 86400)),
            now: Self.now
        )
        for calls in [nil, 0, 812] as [Int?] {
            let consequence = CleanupPresentation.resetConsequence(calls: calls, window: window)
            #expect(!consequence.contains("taken at"))
            #expect(!consequence.contains("last reading the router gave"))
            #expect(!consequence.contains("discarded as well"))
        }
    }
}
