#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Inbox board's state: what is waiting, what the user did about it, and the one undo slot.
    ///
    /// It takes the same four load states the merged boards use — `loading`, `loaded`, `stale`,
    /// `failed` — because those four are what `DESIGN.md` §5 needs and three shipped boards have
    /// proved they suffice.
    ///
    /// **What is specific to this board is that acting on a row is the only path in the product by
    /// which something a remote device asked for becomes something that runs.** So the dispositions
    /// are modelled explicitly rather than as list mutations: `rows` is derived by removing what has
    /// been dispositioned, the undo slot restores it, and the accept path takes an
    /// `AcceptableInboxItem` — which cannot be constructed for an item whose registry entry the Mac
    /// could not read.
    @MainActor
    @Observable
    public final class InboxBoardModel {
        public enum LoadState: Sendable, Equatable {
            /// No answer yet. Not the same as an answer of none.
            case loading
            case loaded(InboxSnapshot)
            /// The last good reading, under a live failure.
            case stale(InboxSnapshot, InboxServiceError)
            /// Nothing ever loaded.
            case failed(InboxServiceError)

            public var snapshot: InboxSnapshot? {
                switch self {
                case let .loaded(snapshot), let .stale(snapshot, _): snapshot
                case .loading, .failed: nil
                }
            }

            public var error: InboxServiceError? {
                switch self {
                case let .stale(_, error), let .failed(error): error
                case .loading, .loaded: nil
                }
            }
        }

        /// How an accept attempt ended, kept beside the sheet's action rather than in a banner —
        /// `DESIGN.md` §5 puts an error next to the thing that failed.
        public enum AcceptState: Equatable, Sendable {
            case idle
            case accepting
            case failed(ControlAPIError)
            /// The entry resolved, but carries no install block to declare — so there is nothing to
            /// send and no router error to report.
            ///
            /// Its own case rather than a `ControlAPIError`: every one of those says "the router"
            /// did something, and this condition is entirely local. Reporting it as a malformed
            /// router response would put a sentence about the router's version in front of a user
            /// whose router was never asked anything. Before this existed the branch returned
            /// silently, leaving the sheet on `.idle` with the press having done nothing visible.
            case notInstallable
        }

        @ObservationIgnored public let client: any ControlAPIClient
        @ObservationIgnored private let service: any InboxService
        /// Where an arrival is announced. Defaults to silence, which is the correct implementation
        /// for a process with no notification centre — every `swift test` run is one, and
        /// `UNUserNotificationCenter.current()` traps in a process with no bundle identifier rather
        /// than failing politely.
        @ObservationIgnored let notifier: any ArrivalNotifier

        /// Which ids have been announced, and the two rules about what counts as an arrival.
        @ObservationIgnored private var arrivals = ArrivalTracker()
        /// Whether authorization has been asked for in this session. Asked once, at the first
        /// snapshot reporting a paired device — before a phone is paired nothing can ever arrive, so
        /// a launch-time prompt asks permission to send notifications the app cannot generate.
        @ObservationIgnored private var askedForAuthorization = false

        /// The withdrawal started by the last disposition.
        ///
        /// Held so a clause can await the hop rather than sleep through it: withdrawing is `async`
        /// and `decline` is not, because a `Button` action is not, so the call has to cross a task
        /// boundary and a test that did not wait for it would be asserting on a race.
        @ObservationIgnored var pendingWithdrawal: Task<Void, Never>?

        /// Whether the user granted notifications, or `nil` before anyone asked.
        ///
        /// Stored as the observable that makes the ask-once rule fail when broken. No view reads
        /// this directly today (PairingSheet has no paired phase in Release, per `spec-I6.md`).
        public internal(set) var notificationsAuthorized: Bool?

        public private(set) var state: LoadState = .loading
        public internal(set) var acceptState: AcceptState = .idle

        /// A route arrived for an item that is no longer waiting.
        ///
        /// Reachable only in the microseconds between a disposition and its banner being withdrawn.
        /// It reports in the same slot the dispositions do rather than in a banner of its own —
        /// inventing a surface for a state that lives for microseconds would be furniture.
        public private(set) var routeReport: String?

        // MARK: - Seams the arrivals extension reaches

        /// Every id that has been announced. Read by the reconcile that withdraws banners for items
        /// that are no longer waiting.
        var announcedIDs: Set<String> { arrivals.announcedIDs }

        /// Feed a snapshot's items in and take back what genuinely arrived. Mutating, so it lives
        /// here with the storage rather than in the extension.
        func takeArrivals(in items: [InboxItem]) -> [InboxItem] {
            arrivals.arrivals(in: items)
        }

        var hasAskedForAuthorization: Bool { askedForAuthorization }

        func markAskedForAuthorization() {
            askedForAuthorization = true
        }

        /// The item the review sheet is open for, held **by id** rather than as a captured value —
        /// M5's lesson: a copy taken when the sheet opened goes stale the moment the row does, and
        /// the sheet's action then disagrees with the board about what has already happened.
        public var sheetItemID: String?

        /// Values typed into the review sheet's requirement fields, keyed as
        /// `RegistryCapability` keys them.
        public var requirementValues: [String: String] = [:]
        public var requirementsRevealed = false

        /// Items the user has acted on, and so are no longer waiting.
        public private(set) var dispositioned: [String: InboxDisposition] = [:]

        /// **One slot, not a stack.** `DESIGN.md` §9 asks for reversible-and-reported; a deeper
        /// history would promise a record this surface does not keep, and an undo that walked back
        /// through several installs would be a destructive operation wearing an undo's clothes.
        public private(set) var lastDisposition: InboxDisposition?

        /// The pairing sheet, which outlives any one view: a code is alive for five minutes whether
        /// or not the inbox is on screen, and the sheet opens from the File menu too.
        public let pairing: PairingSessionModel

        public init(
            client: any ControlAPIClient,
            service: any InboxService,
            notifier: any ArrivalNotifier = SilentArrivalNotifier()
        ) {
            self.client = client
            self.service = service
            self.notifier = notifier
            pairing = PairingSessionModel(service: service)
        }

        // MARK: - Reading

        public func load() async {
            do {
                let snapshot = try await service.snapshot()
                guard !Task.isCancelled else { return }
                state = .loaded(snapshot)
                await announceArrivals(in: snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                // A previous good reading is kept and labelled rather than discarded: an empty board
                // is a stronger claim than a stale one, and "nothing is waiting" is exactly the
                // claim this surface must not make wrongly.
                //
                // **Nothing is announced from here**, and that is deliberate: a read that failed is
                // not evidence that anything arrived.
                if let previous = state.snapshot {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
        }

        // MARK: - Derived

        /// What is still waiting, newest first.
        ///
        /// Dispositioned items are removed **here**, from the same array the badge counts, so the
        /// sidebar and the list cannot disagree about how much is waiting.
        public var rows: [InboxItem] {
            guard let snapshot = state.snapshot else { return [] }
            return snapshot.items
                .filter { dispositioned[$0.id] == nil }
                .sorted { $0.envelope.queuedAt > $1.envelope.queuedAt }
        }

        public var pairedDeviceName: String? {
            state.snapshot?.pairedDeviceName
        }

        /// The badge's count, and the reason it is a computed property over `rows` rather than a
        /// stored number: `DESIGN.md` §6's rule is that a displayed number is one the system
        /// observed, and the only way to guarantee the badge and the list agree is for them to be
        /// the same observation. Zero renders no badge at all, matching every other destination.
        public var waitingCount: Int? {
            let count = rows.count
            return count > 0 ? count : nil
        }

        public func sheetItem() -> InboxItem? {
            guard let sheetItemID else { return nil }
            return rows.first { $0.id == sheetItemID }
        }

        public func selectedItem() -> InboxItem? {
            guard let selection else { return nil }
            return rows.first { $0.id == selection }
        }

        // MARK: - Acting

        /// Accept an item: declare it as a server.
        ///
        /// Takes an `AcceptableInboxItem`, so there is no call site at which an unresolved item can
        /// be installed — the Partial state is enforced by the type rather than by a check the view
        /// has to remember. `force` is never passed and takes its `false` default, for M5's reason:
        /// `force: true` adopts an existing declaration, which would let something that arrived from
        /// a phone replace the command line of a server the user already trusts.
        public func accept(_ acceptable: AcceptableInboxItem) async {
            guard let declaration = RegistryCapability.declaration(
                for: acceptable.entry,
                values: requirementValues
            ) else {
                acceptState = .notInstallable
                return
            }

            acceptState = .accepting
            do {
                _ = try await client.add(declaration)
                guard !Task.isCancelled else { return }
                acceptState = .idle
                record(.accepted(acceptable.item))
                sheetItemID = nil
            } catch {
                guard !Task.isCancelled else { return }
                acceptState = .failed(error)
            }
        }

        /// Decline an item. Nothing is called on the router: declining is a local decision about
        /// something that never ran.
        public func decline(_ item: InboxItem) {
            record(.declined(item))
            if sheetItemID == item.id { sheetItemID = nil }
        }

        private func record(_ disposition: InboxDisposition) {
            dispositioned[disposition.item.id] = disposition
            lastDisposition = disposition
            // A fresh disposition supersedes an already-handled report: that report exists to answer
            // a press that found nothing, and this press found something.
            routeReport = nil
            if selection == disposition.item.id { selection = nil }
            withdrawBanner(for: disposition.item.id)
        }

        /// Put the last **decline** back.
        ///
        /// **Declining is reversible; accepting is not, and the affordance now says so.** The Phase
        /// D critic found the earlier version restoring an accepted item to the queue while the
        /// server it declared stayed installed — a control labelled "Undo" that undid neither half
        /// of what happened, and left the row acceptable a second time. Removing a server is
        /// `DESIGN.md` §8's own undoable operation on the Servers board, with its own confirmation
        /// and its own consequences for stored secrets, so performing it from here would be a
        /// second implementation of a destructive action.
        ///
        /// So an accept is recorded and reported (`InboxCopy.accepted` names where to remove it)
        /// and `isUndoable` is false for it, which is what removes the button rather than leaving
        /// one that silently does the wrong thing.
        public func undoLastDisposition() {
            guard let last = lastDisposition, case let .declined(item) = last else { return }
            dispositioned[item.id] = nil
            lastDisposition = nil
        }

        /// Whether the last disposition can be taken back — true only for a decline.
        public var isUndoable: Bool {
            if case .declined = lastDisposition { return true }
            return false
        }

        /// What the undo affordance says it will do, or nil when there is nothing to undo.
        public func undoLabel() -> String? {
            guard let last = lastDisposition else { return nil }
            return switch last {
            case let .declined(item): InboxCopy.declined(item.title)
            case let .accepted(item): InboxCopy.accepted(item.title)
            }
        }

        public func clearAcceptFailure() {
            acceptState = .idle
        }

        // MARK: - Arriving from another surface

        /// Open the review for one item, addressed by id, from the popover or a notification.
        ///
        /// **Opening a review is the whole of what an outside surface may do toward an install.**
        /// The sheet is what accepts, and it is where what the thing runs is on screen — so the one
        /// press that declares code on this Mac is always made with the capability statement in
        /// front of it. This method calls the router nothing.
        ///
        /// - Returns: `false` when the id is no longer waiting, in which case nothing is opened and
        ///   the already-handled report is set. That is a designed state rather than an error: a
        ///   banner can be pressed in the window between a disposition and its withdrawal, and the
        ///   outcome the user wanted — the item handled — already happened.
        @discardableResult
        public func review(itemID: String) -> Bool {
            guard rows.contains(where: { $0.id == itemID }) else {
                routeReport = InboxCopy.alreadyHandled
                sheetItemID = nil
                return false
            }
            routeReport = nil
            selection = itemID
            request(.approveQueuedInstall, subject: itemID)
            acceptState = .idle
            requirementsRevealed = false
            return true
        }

        /// Decline one item addressed by id, from the popover or a notification.
        ///
        /// Silent and harmless for an id that is no longer waiting: `record` is keyed by id, so this
        /// cannot double-dispose, and reporting "already handled" for a decline would announce a
        /// non-event. The review route reports because it was going to open something and did not.
        public func decline(itemID: String) {
            guard let item = rows.first(where: { $0.id == itemID }) else { return }
            decline(item)
        }

        public func clearRouteReport() {
            routeReport = nil
        }

        // MARK: - Keyboard

        /// `Return` commits the view's one default action: opening the **review sheet**.
        ///
        /// Never accepting. A list row that installs is the one-click path from something a remote
        /// device asked for to code running on this Mac, which is precisely what the queue exists to
        /// prevent. Returns `false` when there is nothing selected, so the key is left unhandled
        /// rather than silently swallowed.
        public func commitDefaultAction() -> Bool {
            guard let item = selectedItem() else { return false }
            request(.approveQueuedInstall, subject: item.id)
            acceptState = .idle
            requirementsRevealed = false
            return true
        }

        /// `Esc` dismisses the sheet first, then clears the selection — never both at once.
        public func escape() {
            if pairing.isOpen {
                pairing.close()
            } else if sheetItemID != nil {
                sheetItemID = nil
                acceptState = .idle
            } else {
                selection = nil
            }
        }

        @discardableResult
        public func moveSelection(by offset: Int) -> Bool {
            let visible = rows
            guard !visible.isEmpty else { return false }
            guard let current = selection, let index = visible.firstIndex(where: { $0.id == current })
            else {
                selection = visible[offset >= 0 ? 0 : visible.count - 1].id
                return true
            }
            selection = visible[min(max(index + offset, 0), visible.count - 1)].id
            return true
        }
    }
#endif
