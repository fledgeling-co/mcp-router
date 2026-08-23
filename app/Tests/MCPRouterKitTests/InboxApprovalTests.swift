import Foundation
import Testing
@testable import MCPRouterKit

/// B2 · what the menu-bar band may install, and the three conditions on it.
///
/// Split out of `InboxBandTests.swift`, which reached the 250-line type-body cap once these clauses
/// were added — the cap was met by splitting rather than raised, following the split that produced
/// `InboxAnnouncementTests.swift`. The seam is the subject: that file is what the band *draws*, this
/// one is what it is allowed to *do*.
///
/// The fixtures stay on `InboxBandTests` for that file's own stated reason — two copies of
/// `item(id:)` drifting apart is how two suites come to disagree about what a queued item is. The one
/// fixture that lives here is the entry that asks for a value, because nothing else needs it.
@Suite("M20 · approving from the band")
struct InboxApprovalTests {
    static let now = InboxBandTests.now
    static let device = InboxBandTests.device

    static func entry(id: String) throws -> RegistryEntry {
        try InboxBandTests.entry(id: id)
    }

    static func item(
        id: String,
        queuedSecondsAgo: TimeInterval,
        resolved: RegistryEntry? = nil
    ) -> InboxItem {
        InboxBandTests.item(id: id, queuedSecondsAgo: queuedSecondsAgo, resolved: resolved)
    }

    /// A resolved entry that asks for a value before it can start — the third condition on
    /// `isApprovable`. Decoded, for the same reason `entry` is.
    static func entryAskingForAValue(id: String) throws -> RegistryEntry {
        let json = """
        {"id":"\(id)","name":"\(id)","displayName":"Needs a key","description":"d",
         "source":"official",
         "install":{"type":"stdio","command":"node","args":["server.js"],
                    "requires":[{"name":"API_KEY","description":"the key","isSecret":true}]}}
        """
        return try JSONDecoder().decode(RegistryEntry.self, from: Data(json.utf8))
    }

    // MARK: - B2 · what may be installed from the band, and what may not

    /// The three conditions, each failed alone against a control that passes all three.
    ///
    /// A row that satisfies everything is asserted first, so a `false` below is the named condition
    /// failing rather than the fixture never having been approvable at all — without that control
    /// this whole clause passes on a typo in the JSON.
    @Test("a row is approvable only when the entry resolved, the preference is on and nothing is blank")
    func approvalTakesThreeConditions() throws {
        let resolved = try Self.entry(id: "e-1")

        let control = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 5, resolved: resolved)],
                device: Self.device,
                approveFromPopover: true,
                now: Self.now
            )
        )
        #expect(control.rows[0].isApprovable, "the control row must satisfy all three")

        // 1 · the preference off.
        let preferenceOff = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 5, resolved: resolved)],
                device: Self.device,
                approveFromPopover: false,
                now: Self.now
            )
        )
        #expect(!preferenceOff.rows[0].isApprovable)
        #expect(preferenceOff.rows[0].isReviewable, "the preference governs installing, not reviewing")

        // 2 · the entry could not be read.
        let unresolved = try #require(
            InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 5, resolved: nil)],
                device: Self.device,
                approveFromPopover: true,
                now: Self.now
            )
        )
        #expect(!unresolved.rows[0].isApprovable)

        // 3 · the entry asks for a value the band has no field for.
        let asksForAValue = try #require(
            try InboxBand.make(
                waiting: [Self.item(
                    id: "q-1", queuedSecondsAgo: 5, resolved: Self.entryAskingForAValue(id: "e-2")
                )],
                device: Self.device,
                approveFromPopover: true,
                now: Self.now
            )
        )
        #expect(
            !asksForAValue.rows[0].isApprovable,
            "an empty value would reach the router as a blank credential"
        )
        #expect(
            asksForAValue.rows[0].isReviewable,
            "such a row keeps Review…, which is where the fields are"
        )
    }

    /// **The default is the safe one.** A caller that does not thread the preference through gets no
    /// install control — asserted on the call `InboxBand.make` had before this preference existed,
    /// which is also the shape every earlier clause in this file still uses.
    @Test("a band built without the preference draws no approval at all")
    func approvalDefaultsClosed() throws {
        let band = try #require(
            try InboxBand.make(
                waiting: [Self.item(id: "q-1", queuedSecondsAgo: 5, resolved: Self.entry(id: "e-1"))],
                device: Self.device,
                now: Self.now
            )
        )
        #expect(!band.rows[0].isApprovable)
        #expect(InboxBand.Row(
            id: "r", title: "t", provenance: "p", capability: nil, isPartial: false
        ).isApprovable == false)
    }

    /// `canApprove` is the shared question, so the band and the shell's route cannot answer it
    /// differently. It reads the entry alone — the preference is the caller's half.
    @Test("canApprove refuses an unread entry and one with a value still blank")
    func canApproveReadsTheEntry() throws {
        let readable = try Self.item(id: "a", queuedSecondsAgo: 1, resolved: Self.entry(id: "e"))
        #expect(InboxBand.canApprove(readable))
        #expect(!InboxBand.canApprove(Self.item(id: "b", queuedSecondsAgo: 1, resolved: nil)))
        #expect(try !InboxBand.canApprove(Self.item(
            id: "c", queuedSecondsAgo: 1, resolved: Self.entryAskingForAValue(id: "e2")
        )))
    }

    /// The band's two new strings, and the reason the decline one is not the shared constant.
    @Test("the band's controls are Approve and Not now, and neither trails off")
    func bandControlCopy() {
        #expect(InboxCopy.Band.approveAction == "Approve")
        #expect(InboxCopy.Band.declineAction == "Not now")
        #expect(!InboxCopy.Band.approveAction.hasSuffix("…"), "it commits here, so it does not trail off")
        #expect(!InboxCopy.Band.declineAction.hasSuffix("…"))
        #expect(
            InboxCopy.declineAction == "Decline",
            "the board's own button keeps its wording; plan-M20 step 13's condition for a second string"
        )
        #expect(InboxCopy.reviewAction.hasSuffix("…"), "Review opens a further view")
    }
}
