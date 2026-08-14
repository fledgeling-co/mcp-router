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
        }

        @ObservationIgnored public let client: any ControlAPIClient
        @ObservationIgnored private let service: any InboxService

        public private(set) var state: LoadState = .loading
        public private(set) var acceptState: AcceptState = .idle

        /// The item the review sheet is open for, held **by id** rather than as a captured value —
        /// M5's lesson: a copy taken when the sheet opened goes stale the moment the row does, and
        /// the sheet's action then disagrees with the board about what has already happened.
        public var sheetItemID: String?
        public var selection: String?

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

        public init(client: any ControlAPIClient, service: any InboxService) {
            self.client = client
            self.service = service
            pairing = PairingSessionModel(service: service)
        }

        // MARK: - Reading

        public func load() async {
            do {
                let snapshot = try await service.snapshot()
                guard !Task.isCancelled else { return }
                state = .loaded(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                // A previous good reading is kept and labelled rather than discarded: an empty board
                // is a stronger claim than a stale one, and "nothing is waiting" is exactly the
                // claim this surface must not make wrongly.
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
            ) else { return }

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
            if selection == disposition.item.id { selection = nil }
        }

        /// Put the last disposition back.
        ///
        /// **Declining is fully reversible; accepting is reversible only as far as the queue.** An
        /// accepted item was declared as a server, and undoing that would mean removing a server —
        /// which `DESIGN.md` §8 makes its own undoable operation on the Servers board, with its own
        /// confirmation rules and its own consequences for stored secrets. Reaching across to
        /// perform it from here would be a second implementation of a destructive action, so this
        /// restores the row and says plainly that the server stays. Reported, not silent.
        public func undoLastDisposition() {
            guard let last = lastDisposition else { return }
            dispositioned[last.item.id] = nil
            lastDisposition = nil
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

        // MARK: - Keyboard

        /// `Return` commits the view's one default action: opening the **review sheet**.
        ///
        /// Never accepting. A list row that installs is the one-click path from something a remote
        /// device asked for to code running on this Mac, which is precisely what the queue exists to
        /// prevent. Returns `false` when there is nothing selected, so the key is left unhandled
        /// rather than silently swallowed.
        public func commitDefaultAction() -> Bool {
            guard let item = selectedItem() else { return false }
            sheetItemID = item.id
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
