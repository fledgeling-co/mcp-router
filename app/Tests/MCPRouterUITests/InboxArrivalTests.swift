#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// A notifier that records rather than notifies.
    ///
    /// `@MainActor` rather than lock-guarded, unlike `RecordingControlAPIClient`: every call site is
    /// already on the main actor, so the isolation is free here and a lock would be ceremony.
    @MainActor
    final class RecordingArrivalNotifier: ArrivalNotifier, @unchecked Sendable {
        var announcements: [InboxAnnouncement] = []
        var withdrawals: [[String]] = []
        var authorizationRequests = 0
        var grant = true

        nonisolated init() {}

        nonisolated func requestAuthorization() async -> Bool {
            await MainActor.run {
                authorizationRequests += 1
                return grant
            }
        }

        nonisolated func announce(_ announcement: InboxAnnouncement) async {
            await MainActor.run { announcements.append(announcement) }
        }

        nonisolated func withdraw(itemIDs: [String]) async {
            await MainActor.run { withdrawals.append(itemIDs) }
        }
    }

    /// An inbox whose snapshots are scripted, so a *sequence* of reads is assertable.
    ///
    /// The fixture service cannot do this: an arrival is a change between two snapshots, and every
    /// scenario but `.arriving` is a pure function of its construction.
    final class ScriptedInboxService: InboxService, @unchecked Sendable {
        private let snapshots: [Result<InboxSnapshot, InboxServiceError>]
        private let index = Counter()

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next(limit: Int) -> Int {
                lock.withLock {
                    defer { value = min(value + 1, limit - 1) }
                    return min(value, limit - 1)
                }
            }
        }

        init(_ snapshots: [Result<InboxSnapshot, InboxServiceError>]) {
            self.snapshots = snapshots
        }

        func snapshot() async throws(InboxServiceError) -> InboxSnapshot {
            switch snapshots[index.next(limit: snapshots.count)] {
            case let .success(snapshot): return snapshot
            case let .failure(error): throw error
            }
        }

        func availability() -> PairingAvailability {
            .noEndpoint
        }
    }

    /// The half of I6 that lives on the board: what is announced, what is withdrawn, and what a
    /// route from outside the window is allowed to do.
    @Suite("I6 · arrivals, routes and the boundary")
    @MainActor
    struct InboxArrivalTests {
        static let device = "Luke's iPhone"

        static func item(id: String, secondsAgo: TimeInterval, resolved: Bool = false) throws -> InboxItem {
            try InboxItem(
                envelope: InboxEnvelope(
                    version: 1,
                    id: id,
                    entryID: "entry-\(id)",
                    displayName: "Item \(id)",
                    queuedAt: Date().addingTimeInterval(-secondsAgo),
                    deviceName: device
                ),
                resolved: resolved ? entry() : nil
            )
        }

        /// An item whose entry asks for a value — D1's third condition.
        static func itemAskingForAValue(id: String) throws -> InboxItem {
            let json = """
            {"id":"e2","name":"e2","displayName":"Needs a key","description":"d","source":"official",
             "install":{"type":"stdio","command":"node","args":["s.js"],
                        "requires":[{"name":"API_KEY","description":"the key","isSecret":true}]}}
            """
            return try InboxItem(
                envelope: InboxEnvelope(
                    version: 1,
                    id: id,
                    entryID: "entry-\(id)",
                    displayName: "Item \(id)",
                    queuedAt: Date().addingTimeInterval(-300),
                    deviceName: device
                ),
                resolved: JSONDecoder().decode(RegistryEntry.self, from: Data(json.utf8))
            )
        }

        static func entry() throws -> RegistryEntry {
            let json = """
            {"id":"e","name":"e","displayName":"Local notes","description":"d","source":"official",
             "install":{"type":"stdio","command":"node","args":["s.js"]}}
            """
            return try JSONDecoder().decode(RegistryEntry.self, from: Data(json.utf8))
        }

        static func snapshot(_ items: [InboxItem], paired: Bool = true) -> InboxSnapshot {
            InboxSnapshot(items: items, pairedDeviceName: paired ? device : nil)
        }

        static func board(
            _ snapshots: [Result<InboxSnapshot, InboxServiceError>],
            notifier: RecordingArrivalNotifier
        ) -> (InboxBoardModel, RecordingControlAPIClient) {
            let client = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = InboxBoardModel(
                client: client,
                service: ScriptedInboxService(snapshots),
                notifier: notifier
            )
            return (board, client)
        }

        // MARK: - A10 · declining is local and reversible

        @Test("declining from outside the window calls the router nothing and is undoable")
        func declineIsLocalAndReversible() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true),
                             Self.item(id: "q-2", secondsAgo: 60, resolved: true)]
            let (board, client) = Self.board([.success(Self.snapshot(items))], notifier: notifier)
            await board.load()

            board.decline(itemID: "q-1")
            #expect(board.rows.map(\.id) == ["q-2"])
            #expect(client.calls.add == 0)
            #expect(client.calls.remove == 0)
            #expect(board.isUndoable)

            board.undoLastDisposition()
            #expect(Set(board.rows.map(\.id)) == ["q-1", "q-2"])
        }

        // MARK: - A19 · the residual race

        /// A banner can be pressed in the window between a disposition and its withdrawal. Both
        /// routes are safe and neither is silent about the one that was going to open something.
        @Test("a route for an item that is no longer waiting opens nothing and says so")
        func routeForAMissingItem() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]
            let (board, client) = Self.board([.success(Self.snapshot(items))], notifier: notifier)
            await board.load()
            board.decline(itemID: "q-1")

            #expect(!board.review(itemID: "q-1"))
            #expect(board.sheetItemID == nil)
            #expect(board.routeReport == InboxCopy.alreadyHandled)

            // A decline for a gone item is silent and cannot double-dispose: reporting "already
            // handled" for it would announce a non-event.
            board.decline(itemID: "q-1")
            #expect(client.calls.add == 0)
            #expect(board.rows.isEmpty)
        }

        // MARK: - A11–A15 · what is announced

        @Test("the first load announces nothing; the next arrival announces once")
        func announcementsFollowTheDelta() async throws {
            let notifier = RecordingArrivalNotifier()
            let first = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]
            let second = try first + [Self.item(id: "q-2", secondsAgo: 1, resolved: true)]
            let (board, _) = Self.board(
                [.success(Self.snapshot(first)),
                 .success(Self.snapshot(second)),
                 .success(Self.snapshot(second))],
                notifier: notifier
            )

            await board.load()
            #expect(notifier.announcements.isEmpty, "a queue already waiting at launch is not an arrival")

            await board.load()
            #expect(notifier.announcements.count == 1)
            #expect(notifier.announcements[0].id == "q-2")

            await board.load()
            #expect(notifier.announcements.count == 1, "the same snapshot announced twice")
        }

        /// A read that failed is not evidence that anything arrived.
        @Test("a failed read announces nothing")
        func failedReadIsSilent() async {
            let notifier = RecordingArrivalNotifier()
            let (board, _) = Self.board(
                [.failure(.unreadable(detail: "the queue file could not be read"))],
                notifier: notifier
            )
            await board.load()
            #expect(notifier.announcements.isEmpty)
            #expect(notifier.authorizationRequests == 0)
        }

        // MARK: - A16 · authorization

        @Test("authorization is asked for once, at the first snapshot reporting a paired device")
        func authorizationAskedOnceWhenPaired() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 5, resolved: true)]
            let (board, _) = Self.board(
                [.success(Self.snapshot(items)), .success(Self.snapshot(items))],
                notifier: notifier
            )
            await board.load()
            await board.load()
            #expect(notifier.authorizationRequests == 1)
            #expect(board.notificationsAuthorized == true)
        }

        /// Before a phone is paired nothing can ever arrive, so asking then is asking permission to
        /// send notifications the app has no way to generate.
        @Test("an unpaired Mac is never asked for notification permission")
        func unpairedIsNeverAsked() async {
            let notifier = RecordingArrivalNotifier()
            let (board, _) = Self.board(
                [.success(Self.snapshot([], paired: false)),
                 .success(Self.snapshot([], paired: false))],
                notifier: notifier
            )
            await board.load()
            await board.load()
            #expect(notifier.authorizationRequests == 0)
            #expect(board.notificationsAuthorized == nil)
        }

        @Test("a denied grant is recorded and nothing retries")
        func deniedIsRecordedAndNotRetried() async {
            let notifier = RecordingArrivalNotifier()
            notifier.grant = false
            let (board, _) = Self.board(
                [.success(Self.snapshot([])), .success(Self.snapshot([]))],
                notifier: notifier
            )
            await board.load()
            await board.load()
            #expect(notifier.authorizationRequests == 1)
            #expect(board.notificationsAuthorized == false)
        }

        // MARK: - A17 · withdrawal

        /// **The backstop, and it is only the backstop.** An earlier version of this comment said
        /// the withdrawal was "derived from the rows on every read rather than commanded at each
        /// disposition site". That stopped being true when `record` began calling
        /// `withdrawBanner(for:)`, and the sentence mattered: because the reconcile produces the
        /// same withdrawal one poll later, this clause is green with or without that call, so it
        /// cannot be the evidence for the spec's *"the moment"*.
        /// `withdrawalIsCommandedAtTheDisposition` is, and it runs no `load()` at all.
        ///
        /// What is real here is the case the commanded call cannot reach: an item that left the
        /// queue without passing through a disposition on this Mac, because another surface or the
        /// router itself removed it. That is why both exist and neither is the other's duplicate.
        @Test("an item gone from the queue has its banner swept on the next read, by id")
        func withdrawalIsSweptOnTheNextRead() async throws {
            let notifier = RecordingArrivalNotifier()
            let both = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true),
                            Self.item(id: "q-2", secondsAgo: 60, resolved: true)]
            let (board, _) = Self.board(
                [.success(Self.snapshot(both)), .success(Self.snapshot(both))],
                notifier: notifier
            )
            await board.load()
            #expect(notifier.withdrawals.isEmpty)

            board.decline(itemID: "q-1")
            await board.load()

            let withdrawn = try #require(notifier.withdrawals.last)
            #expect(withdrawn.contains("q-1"))
            #expect(!withdrawn.contains("q-2"))
            // The multi-item banner goes with the first withdrawal: it says "N items are waiting",
            // and the moment one is handled that sentence is false.
            #expect(withdrawn.contains(InboxAnnouncement.manyIdentifier))
        }

        // MARK: - The band's states, from the board

        @Test("loading draws no band, and a failed read draws its own named notice")
        func bandStates() async throws {
            let notifier = RecordingArrivalNotifier()
            let (loadingBoard, _) = Self.board([.success(Self.snapshot([]))], notifier: notifier)
            // Before any load, the board is `.loading`.
            #expect(loadingBoard.bandZone() == nil)

            let (failedBoard, _) = Self.board(
                [.failure(.unreadable(detail: "the queue file could not be read"))],
                notifier: notifier
            )
            await failedBoard.load()
            let zone = try #require(failedBoard.bandZone())
            guard case let .unreadable(message) = zone else {
                Issue.record("a failed read did not produce its own notice")
                return
            }
            #expect(message.title == InboxCopy.unreadableTitle)
            #expect(message.detail.contains("the queue file could not be read"))
            // The title is derived from the error rather than fixed: a queue file this Mac could
            // not open must not be announced as "the router isn't running".
            #expect(message.title != InboxCopy.routerOfflineTitle)
        }

        @Test("an empty queue draws no band at all")
        func emptyQueueDrawsNothing() async {
            let notifier = RecordingArrivalNotifier()
            let (board, _) = Self.board([.success(Self.snapshot([]))], notifier: notifier)
            await board.load()
            #expect(board.bandZone() == nil)
        }

        @Test("the report line follows the last disposition and carries undo only for a decline")
        func reportLine() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true),
                             Self.item(id: "q-2", secondsAgo: 60, resolved: true)]
            let (board, _) = Self.board([.success(Self.snapshot(items))], notifier: notifier)
            await board.load()
            board.decline(itemID: "q-1")

            let zone = try #require(board.bandZone())
            guard case let .band(band) = zone else {
                Issue.record("the band went missing after a decline left one row waiting")
                return
            }
            let report = try #require(band.report)
            #expect(report.isUndoable)
            #expect(report.sentence == InboxCopy.declined("Local notes"))
        }
    }
#endif
