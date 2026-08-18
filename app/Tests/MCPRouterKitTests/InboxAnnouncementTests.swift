import Foundation
import Testing
@testable import MCPRouterKit

/// The arrival notification, as a value: what it says, which buttons it offers, and what counts as
/// an arrival in the first place.
///
/// Split out of `InboxBandTests.swift`, which reached the 400-line file cap and the 250-line type
/// body cap once `make format` had rewrapped it — the caps were met by splitting rather than
/// raised. Split on the seam the spec already uses: that file is "The band", this one is "The
/// notification".
///
/// The fixtures stay on `InboxBandTests` rather than being copied here. Two copies of `item(id:)`
/// drifting apart is how two suites come to disagree about what a queued item is, and the whole
/// argument for the band's header line is that one wording has one source.
@Suite("I6 · the arrival notification")
struct InboxAnnouncementTests {
    static let now = InboxBandTests.now
    static let device = InboxBandTests.device

    static func entry(id: String, stdio: Bool = true) throws -> RegistryEntry {
        try InboxBandTests.entry(id: id, stdio: stdio)
    }

    // MARK: - A8 · the action set has no install

    /// **The absence is the enforcement.** Not a comment asking nobody to add an Install button —
    /// a closed action set with nothing in it to register, asserted over every case.
    @Test("no notification action installs anything, over every case")
    func noInstallAction() throws {
        #expect(InboxNotificationAction.allCases.count == 2)
        for action in InboxNotificationAction.allCases {
            #expect(action == .review || action == .decline)
        }
        let entry = try Self.entry(id: "e-1")
        let one = try #require(
            InboxAnnouncement.make(
                arrivals: [InboxBandTests.item(id: "q-1", queuedSecondsAgo: 5, resolved: entry)],
                device: Self.device
            )
        )
        #expect(one.actions == [.review, .decline])

        let many = try #require(
            InboxAnnouncement.make(
                arrivals: [
                    InboxBandTests.item(id: "q-1", queuedSecondsAgo: 5),
                    InboxBandTests.item(id: "q-2", queuedSecondsAgo: 3)
                ],
                device: Self.device
            )
        )
        // No decline on a multi-item banner: there is no single item for it to act on, and
        // "decline all" is a bulk destructive action nobody asked for.
        #expect(many.actions == [.review])
    }

    @Test("a dismissal is not a decision, and an unknown identifier resolves to nothing")
    func dismissalIsNotADecision() {
        #expect(
            InboxNotificationAction.resolve(
                identifier: "dismiss", isDefaultAction: false, isDismissAction: true
            ) == nil
        )
        #expect(
            InboxNotificationAction.resolve(
                identifier: "install", isDefaultAction: false, isDismissAction: false
            ) == nil
        )
        #expect(
            InboxNotificationAction.resolve(
                identifier: "anything", isDefaultAction: true, isDismissAction: false
            ) == .review
        )
        #expect(
            InboxNotificationAction.resolve(
                identifier: "decline", isDefaultAction: false, isDismissAction: false
            ) == .decline
        )
    }

    // MARK: - A14 · one banner per delta

    @Test("one arrival names it; several are one banner, not several")
    func oneBannerPerDelta() throws {
        let entry = try Self.entry(id: "e-1")
        let single = try #require(
            InboxAnnouncement.make(
                arrivals: [InboxBandTests.item(id: "q-1", queuedSecondsAgo: 5, resolved: entry)],
                device: Self.device
            )
        )
        #expect(single.id == "q-1")
        #expect(single.title == entry.displayName)
        #expect(single.subtitle == InboxCopy.Arrival.subtitle(device: Self.device))
        #expect(single.body == RegistryCapability.statement(for: entry).headline)
        #expect(single.itemIDs == ["q-1"])

        let three = try #require(
            InboxAnnouncement.make(
                arrivals: (1 ... 3).map { InboxBandTests.item(id: "q-\($0)", queuedSecondsAgo: Double($0)) },
                device: Self.device
            )
        )
        #expect(three.id == InboxAnnouncement.manyIdentifier)
        #expect(three.title == "3 items are waiting")
        #expect(three.itemIDs.count == 3)
    }

    @Test("nothing arriving is not an event")
    func noArrivalsNoBanner() {
        #expect(InboxAnnouncement.make(arrivals: [], device: Self.device) == nil)
    }

    @Test("an unreadable entry says so on the banner rather than saying nothing")
    func partialBanner() throws {
        let one = try #require(
            InboxAnnouncement.make(
                arrivals: [InboxBandTests.item(id: "q-1", queuedSecondsAgo: 5, resolved: nil)],
                device: Self.device
            )
        )
        #expect(one.body == InboxCopy.Arrival.partialBody)
    }

    // MARK: - A11–A13 · what counts as an arrival

    /// A queue that was already waiting when you logged in is not an arrival. Five banners at login
    /// is the behaviour that teaches people to turn notifications off, after which the feature is
    /// absent and believed present.
    @Test("the first snapshot of a session announces nothing and seeds its ids")
    func firstSnapshotIsNotAnArrival() {
        var tracker = ArrivalTracker()
        #expect(!tracker.hasSeeded)
        let seeded = tracker.arrivals(in: [
            InboxBandTests.item(id: "a", queuedSecondsAgo: 100),
            InboxBandTests.item(id: "b", queuedSecondsAgo: 50)
        ])
        #expect(seeded.isEmpty)
        #expect(tracker.hasSeeded)
        #expect(tracker.announcedIDs == ["a", "b"])
    }

    @Test("a later snapshot announces only what is new, and only once")
    func laterSnapshotsAnnounceTheDelta() {
        var tracker = ArrivalTracker()
        _ = tracker.arrivals(in: [InboxBandTests.item(id: "a", queuedSecondsAgo: 100)])

        let second = tracker.arrivals(in: [
            InboxBandTests.item(id: "a", queuedSecondsAgo: 100),
            InboxBandTests.item(id: "b", queuedSecondsAgo: 5)
        ])
        #expect(second.map(\.id) == ["b"])

        let third = tracker.arrivals(in: [
            InboxBandTests.item(id: "a", queuedSecondsAgo: 100),
            InboxBandTests.item(id: "b", queuedSecondsAgo: 5)
        ])
        #expect(third.isEmpty)
    }

    /// Undoing a decline puts the row back. Announcing it again would be the app arguing with the
    /// user about a decision they just reversed — which is why the announced set only ever grows.
    @Test("an item that comes back after an undo is not announced a second time")
    func undoDoesNotReAnnounce() {
        var tracker = ArrivalTracker()
        _ = tracker.arrivals(in: [InboxBandTests.item(id: "a", queuedSecondsAgo: 100)])
        _ = tracker.arrivals(in: [
            InboxBandTests.item(id: "a", queuedSecondsAgo: 100),
            InboxBandTests.item(id: "b", queuedSecondsAgo: 5)
        ])
        // b is declined, so it leaves the snapshot…
        _ = tracker.arrivals(in: [InboxBandTests.item(id: "a", queuedSecondsAgo: 100)])
        // …and the undo puts it back.
        let restored = tracker.arrivals(in: [
            InboxBandTests.item(id: "a", queuedSecondsAgo: 100),
            InboxBandTests.item(id: "b", queuedSecondsAgo: 5)
        ])
        #expect(restored.isEmpty)
    }

    // MARK: - Where a press lands

    /// **The walk two doc comments already claimed existed.**
    ///
    /// `InboxNotificationRoute` was extracted from the delegate for exactly one reason, stated in
    /// its own comment: as a value it can be *"walked over every action and both identifier
    /// shapes"*, where the delegate's `perform` can only be reached from a real notification centre.
    /// The extraction happened and the walk did not — `InboxNotificationRoute` had no reference in
    /// `app/Tests` at all, so the type that exists to make the boundary checkable was checked by
    /// nothing, and the comment saying otherwise was the only evidence anyone had.
    ///
    /// This is the boundary clause at the mapping layer: `InboxArrivalTests` counts `add` on a
    /// recording client while driving the board's own methods, which catches a route that installs
    /// *by calling accept*. It cannot catch a route that installs by naming a case that installs,
    /// because it never evaluates the mapping. Both halves are needed and neither is the other.
    @Test("every action on either identifier shape routes somewhere that installs nothing")
    func noRouteInstalls() {
        for action in InboxNotificationAction.allCases {
            for identifier in ["q-1", InboxAnnouncement.manyIdentifier] {
                let route = InboxNotificationRoute.route(action, identifier: identifier)
                // Exhaustive on purpose: a case added here has to be decided in this switch before
                // the suite compiles, which is the same enforcement the delegate's switch makes.
                switch route {
                case .openInbox, .review, .decline:
                    continue
                }
            }
        }
        // Said in its own terms as well, so the clause fails on the rule rather than only on a
        // compile error: a multi-item banner names no single item, so every press on it lands on
        // the board — including a `decline` identifier delivered under an older build's category.
        for action in InboxNotificationAction.allCases {
            #expect(
                InboxNotificationRoute.route(
                    action,
                    identifier: InboxAnnouncement.manyIdentifier
                ) == .openInbox,
                "a press on the many-item banner acted on an item it does not name"
            )
        }
        #expect(InboxNotificationRoute.route(.review, identifier: "q-1") == .review(itemID: "q-1"))
        #expect(InboxNotificationRoute.route(.decline, identifier: "q-1") == .decline(itemID: "q-1"))
    }

    /// A dismissal is not a decision. Closing a banner has to resolve to no action at all, or
    /// ignoring a notification would come to mean something about the item.
    @Test("a dismissal resolves to nothing, and the default press is a review")
    func dismissalDecidesNothing() {
        #expect(
            InboxNotificationAction.resolve(
                identifier: "com.apple.UNNotificationDismissActionIdentifier",
                isDefaultAction: false,
                isDismissAction: true
            ) == nil
        )
        #expect(
            InboxNotificationAction.resolve(
                identifier: "com.apple.UNNotificationDefaultActionIdentifier",
                isDefaultAction: true,
                isDismissAction: false
            ) == .review
        )
        // An identifier no case names resolves to nothing rather than to the nearest branch.
        #expect(
            InboxNotificationAction.resolve(
                identifier: "install",
                isDefaultAction: false,
                isDismissAction: false
            ) == nil
        )
    }
}
