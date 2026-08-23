import Foundation
import Testing
@testable import MCPRouterKit

/// C1–C3 · the analyst finding's notification, as a value.
///
/// Its own suite beside `InboxAnnouncementTests` rather than clauses added to it, which is the same
/// separation the production code keeps: two families, and `InboxArrival.swift` left byte-identical
/// so its own enforcement goes on meaning what it meant. A shared suite would make every clause about
/// either family a clause about both, which is `DEF-004`'s shape.
///
/// **Nothing in either app target constructs an `AnalystFinding`** — the analyst is `PRD.md`
/// §6.2–§6.3 and out of M20's scope — so these fixtures are the only findings that exist. That is the
/// stated position rather than an oversight: this item builds delivery, and `spec-M20.md` §2 records
/// what deferring the whole banner until the analyst exists would have cost instead.
@Suite("M20 · the finding notification")
struct FindingAnnouncementTests {
    static func finding(id: String, evidence: Int = 14) -> AnalystFinding {
        AnalystFinding(
            id: id,
            entryID: "docker-mcp",
            subject: "docker-mcp",
            sentence: "You ran docker logs by hand \(evidence) times this week.",
            evidenceCount: evidence
        )
    }

    // MARK: - C1 · no case of either action set installs

    /// **The exhaustive switch is the enforcement**, and it is asserted in both directions: every
    /// route of every action against both identifier shapes reports `installs == false`, and the
    /// switch inside `installs` means a case added later cannot compile without being classified.
    ///
    /// The other family is walked in the same clause, because C1's wording is *either* action set and
    /// a clause that read only the new one would leave the older guarantee unexamined here.
    @Test("no route of either notification family installs anything, over every case")
    func noRouteOfEitherFamilyInstalls() {
        #expect(FindingNotificationAction.allCases.count == 3)
        #expect(
            Set(FindingNotificationAction.allCases.map(\.rawValue))
                .isDisjoint(with: Set(InboxNotificationAction.allCases.map(\.rawValue))),
            "the two identifier spaces overlap, so one family's press could resolve as the other's"
        )

        for action in FindingNotificationAction.allCases {
            for identifier in ["f-1", FindingAnnouncement.manyIdentifier] {
                let route = FindingNotificationRoute.route(action, identifier: identifier)
                #expect(!route.installs, "\(action) on \(identifier) routes to \(route), which installs")
                // Exhaustive on purpose: a case added here has to be decided before this compiles.
                switch route {
                case .openInbox, .reviewCapability, .explainFinding, .dismiss:
                    continue
                }
            }
        }

        // The arrival family, in its own terms, so this clause covers what its wording says.
        for action in InboxNotificationAction.allCases {
            switch InboxNotificationRoute.route(action, identifier: "q-1") {
            case .openInbox, .review, .decline:
                continue
            }
        }
    }

    /// Each action's own route, stated rather than only walked — so the clause fails on the mapping
    /// being wrong and not only on a case being added.
    @Test("install opens the entry, details opens the reasoning, dismiss opens nothing")
    func eachActionRoutesToItsOwnDestination() {
        #expect(
            FindingNotificationRoute.route(.install, identifier: "f-1")
                == .reviewCapability(findingID: "f-1")
        )
        #expect(
            FindingNotificationRoute.route(.details, identifier: "f-1")
                == .explainFinding(findingID: "f-1")
        )
        #expect(
            FindingNotificationRoute.route(.dismiss, identifier: "f-1") == .dismiss(findingID: "f-1")
        )
        // A banner naming several findings names no single one, so every press lands on the board —
        // including an `install` identifier delivered under an older build's category.
        for action in FindingNotificationAction.allCases {
            #expect(
                FindingNotificationRoute.route(
                    action, identifier: FindingAnnouncement.manyIdentifier
                ) == .openInbox,
                "a press on the many-finding banner acted on a finding it does not name"
            )
        }
    }

    /// A dismissal by the *system* — swiping the banner away — is not a decision about the finding.
    /// The `dismiss` case is the explicit button the mock draws, which is a different event.
    @Test("a system dismissal resolves to nothing, and the default press opens the reasoning")
    func systemDismissalDecidesNothing() {
        #expect(
            FindingNotificationAction.resolve(
                identifier: "com.apple.UNNotificationDismissActionIdentifier",
                isDefaultAction: false,
                isDismissAction: true
            ) == nil
        )
        #expect(
            FindingNotificationAction.resolve(
                identifier: "com.apple.UNNotificationDefaultActionIdentifier",
                isDefaultAction: true,
                isDismissAction: false
            ) == .details,
            "the unprompted suggestion's default press opens why, not what"
        )
        // An identifier no case names resolves to nothing rather than to the nearest branch — and
        // the arrival family's own identifiers are among those it must not resolve.
        for identifier in ["review", "decline", "approve", "anything"] {
            #expect(
                FindingNotificationAction.resolve(
                    identifier: identifier, isDefaultAction: false, isDismissAction: false
                ) == nil,
                "\(identifier) resolved in the finding family"
            )
        }
        #expect(
            FindingNotificationAction.resolve(
                identifier: "install", isDefaultAction: false, isDismissAction: false
            ) == .install
        )
    }

    // MARK: - C2 · the value and the category agree

    /// Every action set `make` can build is one a category actually draws.
    ///
    /// `drawing` resolves an unknown set to `nil` rather than to a nearest match, so the round trip is
    /// what ties the announcement's promise to the category's registration. The buttons macOS is
    /// actually handed are asserted in `ArrivalNotifierFactoryTests`, which is where the framework
    /// object is built — this is the half that lives in the Kit.
    @Test("every finding action set is one a category draws, and many drops the install")
    func actionSetsRoundTripThroughACategory() throws {
        let one = try #require(FindingAnnouncement.make(findings: [Self.finding(id: "f-1")]))
        let many = try #require(
            FindingAnnouncement.make(findings: [Self.finding(id: "f-1"), Self.finding(id: "f-2")])
        )

        #expect(one.actions == [.install, .details, .dismiss])
        #expect(many.actions == [.details, .dismiss])
        #expect(
            !many.actions.contains(.install),
            "a banner naming several findings offers an install for an entry it does not name"
        )

        for announcement in [one, many] {
            let category = try #require(
                announcement.category,
                "no category draws \(announcement.actions) — make and the category have drifted"
            )
            #expect(category.actions == announcement.actions)
        }
        #expect(one.category == .single)
        #expect(many.category == .many)
        #expect(FindingNotificationCategory.drawing([.install]) == nil, "a nearest match is not an answer")
    }

    /// One banner per batch, and nothing to announce is not an event.
    @Test("one finding names it; several are one banner, and none is not a banner")
    func oneBannerPerBatch() throws {
        #expect(FindingAnnouncement.make(findings: []) == nil)

        let one = try #require(FindingAnnouncement.make(findings: [Self.finding(id: "f-1", evidence: 1)]))
        #expect(one.id == "f-1", "a single banner is identified by the finding, so it can be withdrawn")
        #expect(one.title == "docker-mcp")
        #expect(one.subtitle == "1 observation on this Mac", "the singular is spelled, not suffixed")
        #expect(one.body == "You ran docker logs by hand 1 times this week.")
        #expect(one.findingIDs == ["f-1"])

        let many = try #require(
            FindingAnnouncement.make(
                findings: [Self.finding(id: "f-1", evidence: 3), Self.finding(id: "f-2", evidence: 4)]
            )
        )
        #expect(many.id == FindingAnnouncement.manyIdentifier)
        #expect(many.title == "2 things worth a look")
        #expect(many.subtitle == "7 observations on this Mac", "the batch's evidence is the sum")
        #expect(many.findingIDs == ["f-1", "f-2"])
    }

    // MARK: - C3 · the ellipsis grammar, and PRD §6.4's literal

    /// `DESIGN.md` §3.4 read literally: `…` promises a further view, its absence promises a commit.
    ///
    /// `Install…` opens the board where the entry and its install control are on screen, so it takes
    /// the ellipsis. `Details` and `Dismiss` do what they say where they stand, so they do not.
    /// **`PRD.md` §6.4's `[Install Now]` is the label that would lie** — it promises a commit, and no
    /// case of this set commits — and `plan-M20.md` §3.3 records the decision not to take it.
    @Test("Install carries the ellipsis, Details and Dismiss do not, and Install Now is nowhere")
    func ellipsisGrammarHolds() {
        #expect(FindingCopy.action(.install) == "Install\u{2026}")
        #expect(FindingCopy.action(.details) == "Details")
        #expect(FindingCopy.action(.dismiss) == "Dismiss")
        #expect(FindingCopy.action(.install).hasSuffix("\u{2026}"), "it opens a further view")
        #expect(!FindingCopy.action(.details).hasSuffix("\u{2026}"))
        #expect(!FindingCopy.action(.dismiss).hasSuffix("\u{2026}"))

        // The literal the requirements ask for and this build refuses, checked over every label
        // rather than only over the one it would most likely appear on.
        for action in FindingNotificationAction.allCases {
            let label = FindingCopy.action(action)
            #expect(label != "Install Now", "PRD §6.4's literal promises a commit that no case makes")
            #expect(
                !label.lowercased().contains("now"),
                "\(label) reads as a commit; nothing in this set commits"
            )
        }
        // The control: the forbidden spelling is one this assertion can actually see.
        #expect("Install Now".lowercased().contains("now"))
    }
}
