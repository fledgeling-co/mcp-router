#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Discover board's own state, its debounced query, and its one write.
    ///
    /// It takes M4's four load states unchanged — `loading`, `loaded`, `stale`, `failed` — because
    /// those four are what `DESIGN.md` §5 needs and two merged boards have proved they suffice. What
    /// it adds is the part no other board has: **every read here is a live call to two third-party
    /// indexes**, so a keystroke is a network request, requests overtake one another, and the board
    /// has to stay honest while one is in flight.
    ///
    /// **The generation counter is the correctness mechanism, and cancellation is only an
    /// optimisation.** That order matters and is easy to get backwards:
    ///
    /// - Task cancellation is cooperative. Once `searchRegistry` has returned and its continuation
    ///   is queued on the main actor, cancelling changes nothing — the body resumes and writes
    ///   `state`. Only an explicit check stops it.
    /// - The first load comes from `.task` and is *not* the search's task, so cancelling the
    ///   debounce cannot reach it. Without a shared generation, an empty-query load issued at launch
    ///   can return after a query typed a second later and repaint the board with the whole
    ///   catalogue while the field reads `postgres`. A cold call can take minutes (two index calls at
    ///   a 12-second timeout plus up to ten sequential GitHub fetches), so that window is wide.
    /// - A cancelled transport request surfaces as `ControlAPIError.transport`. Writing that to
    ///   `state` would raise an error banner for a request the *user* superseded, so a superseded
    ///   result is discarded before its error is ever read.
    ///
    /// So every read captures `generation` and discards its result — success or failure — unless the
    /// counter still matches when it resumes.
    @MainActor
    @Observable
    public final class DiscoverBoardModel {
        public enum LoadState: Sendable {
            /// No answer yet. Not the same as an answer of none.
            case loading
            case loaded(RegistrySearchResponse)
            /// The last good reading, under a live failure.
            case stale(RegistrySearchResponse, ControlAPIError)
            /// Nothing ever loaded.
            case failed(ControlAPIError)

            public var response: RegistrySearchResponse? {
                switch self {
                case let .loaded(response), let .stale(response, _): response
                case .loading, .failed: nil
                }
            }

            public var error: ControlAPIError? {
                switch self {
                case let .stale(_, error), let .failed(error): error
                case .loading, .loaded: nil
                }
            }
        }

        /// How an install attempt ended, kept beside the sheet's action rather than in a banner —
        /// `DESIGN.md` §5 puts an error next to the thing that failed.
        public enum InstallState: Equatable, Sendable {
            case idle
            case installing
            case failed(ControlAPIError)
        }

        @ObservationIgnored public let client: any ControlAPIClient

        public private(set) var state: LoadState = .loading
        public var ordering: RegistryPresentation.Ordering = .bestMatch
        public var search: String = ""
        /// The entry the sheet is open for, held **by id**.
        ///
        /// Never a captured `RegistryEntry`. A copy taken when the sheet opened keeps
        /// `installed == false` after a successful add, so its action stays live and a second press
        /// sends a second declaration for a server that now exists. Holding the id and looking the
        /// entry up each render means the sheet sees the same row the board does.
        public var sheetEntryID: String?

        /// The board's one open sheet, as the inventory's own type.
        ///
        /// Computed from the id for `InboxBoardModel.sheet`'s reason: the entry has to be looked up
        /// fresh on every render so the sheet sees a completed install, so the id is the storage
        /// and a stored enum beside it would be a second answer to the same question.
        ///
        /// `officialMark` has no subject — it is a definition rather than a decision about a row —
        /// so it is the one case here that is genuinely a flag.
        public var sheet: RouterSheet.Discover? {
            get {
                if showsOfficialMark { return .officialMark }
                if let sheetEntryID { return .registryEntry(id: sheetEntryID) }
                return nil
            }
            set {
                switch newValue {
                case .officialMark:
                    showsOfficialMark = true
                case let .registryEntry(id):
                    sheetEntryID = id
                case nil:
                    showsOfficialMark = false
                    sheetEntryID = nil
                }
            }
        }

        /// Whether the "what does official mean" sheet is open.
        ///
        /// Storage for `sheet`'s `officialMark` case. Not `public`: the sheet is opened through
        /// `sheet` like every other, and a second public way in is a second thing to keep in step.
        var showsOfficialMark = false
        public var selection: String?
        public private(set) var installState: InstallState = .idle
        public private(set) var focusSearchRequests: Int = 0
        /// Whether a query is in flight over rows that are already on screen.
        public private(set) var isRefreshing = false

        /// Bumped by every query change and every submit. A result whose captured value no longer
        /// matches is discarded.
        @ObservationIgnored private var generation = 0
        /// The debounce. `@ObservationIgnored` because assigning it must not invalidate observers —
        /// otherwise every keystroke re-renders the board through the task property alone.
        @ObservationIgnored private var pending: Task<Void, Never>?

        /// Long enough that a typed word is one request rather than eight, short enough to feel
        /// immediate. Named rather than inlined so the test can reason about it.
        static let debounceNanoseconds: UInt64 = 400_000_000

        public init(client: any ControlAPIClient) {
            self.client = client
        }

        // MARK: - Reading

        /// The first read, from `.task`. Cancelled with the view, and generation-guarded like every
        /// other read so it cannot land on top of a newer query.
        public func load() async {
            await fetch(query: search, generation: generation)
        }

        private func fetch(query: String, generation captured: Int) async {
            if state.response != nil { isRefreshing = true }
            defer { if generation == captured { isRefreshing = false } }

            do {
                let response = try await client.searchRegistry(
                    query: query.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                // Both guards, and in this order: a superseded result is discarded even when the
                // task was never cancelled, which is the case the counter exists for.
                guard !Task.isCancelled, generation == captured else { return }
                state = .loaded(response)
            } catch {
                guard !Task.isCancelled, generation == captured else { return }
                // A previous good reading is kept and labelled rather than discarded. Throwing it
                // away would replace a true-but-old board with an empty one, and an empty board is
                // a stronger claim than a stale one.
                if let previous = state.response {
                    state = .stale(previous, error)
                } else {
                    state = .failed(error)
                }
            }
        }

        /// Called when the search text changes. Debounces, and supersedes anything in flight.
        public func queryChanged() {
            generation += 1
            let captured = generation
            let query = search
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
                guard !Task.isCancelled else { return }
                await self?.fetch(query: query, generation: captured)
            }
        }

        /// `Return` in the search field: search now.
        ///
        /// Cancels the pending debounce rather than merely running beside it. Bypassing without
        /// cancelling issues this request *and* lets the debounce fire 400 ms later, so two calls go
        /// out and the second one wins — a burst-then-Return sequence that a keystroke-only test
        /// never exercises.
        public func submitSearch() {
            generation += 1
            pending?.cancel()
            pending = nil
            let captured = generation
            let query = search
            pending = Task { [weak self] in
                await self?.fetch(query: query, generation: captured)
            }
        }

        /// Stops anything in flight. Called from `.task`'s teardown, because this model is owned by
        /// `ShellModel` and outlives the view: without it, navigating away from Discover leaves a
        /// debounce to fire, issue two third-party requests, and mutate a board nobody is looking at
        /// (`SWIFT_PRACTICES.md` §1 — no task that outlives the thing that wanted it).
        public func cancelPending() {
            pending?.cancel()
            pending = nil
        }

        // MARK: - Derived

        public var rows: [RegistryEntry] {
            guard let response = state.response else { return [] }
            return RegistryPresentation.rows(response, ordering: ordering)
        }

        /// The entry the sheet is showing, looked up fresh so it reflects a completed install.
        public func sheetEntry() -> RegistryEntry? {
            guard let sheetEntryID, let response = state.response else { return nil }
            return response.results.first { $0.id == sheetEntryID }
        }

        public func selectedEntry() -> RegistryEntry? {
            guard let selection, let response = state.response else { return nil }
            return response.results.first { $0.id == selection }
        }

        // MARK: - Writing

        /// Declare the entry as a server.
        ///
        /// **`force` is never passed.** `RegistryCapability.declaration` does not offer it, and this
        /// call takes the default `false`. `force: true` adopts an existing declaration — on a board
        /// of third-party entries that would mean a row the user found in a list could replace the
        /// command line of a server they already trust, which is the control-API guarantee the whole
        /// product is built around.
        ///
        /// `installed` is mutated only from a returned `AddedServer` — never optimistically. A
        /// refusal must leave the row saying what is true, which is that nothing was added.
        public func install(_ entry: RegistryEntry, values: [String: String]) async {
            guard let declaration = RegistryCapability.declaration(for: entry, values: values) else {
                return
            }
            installState = .installing
            do {
                _ = try await client.add(declaration)
                guard !Task.isCancelled else { return }
                installState = .idle
                markInstalled(id: entry.id)
            } catch {
                guard !Task.isCancelled else { return }
                installState = .failed(error)
            }
        }

        /// Flips one row's `installed` without refetching.
        ///
        /// No refetch on purpose: `/registry/search` is non-deterministic between calls, so
        /// re-reading it at the moment the user acted would reorder the board under them and lose
        /// the row they were looking at. The `.stale` case keeps its error, because succeeding at a
        /// write does not make a failed read current.
        private func markInstalled(id: String) {
            func mark(_ response: RegistrySearchResponse) -> RegistrySearchResponse {
                var updated = response
                updated.results = response.results.map { entry in
                    guard entry.id == id else { return entry }
                    var copy = entry
                    copy.installed = true
                    return copy
                }
                return updated
            }
            switch state {
            case let .loaded(response): state = .loaded(mark(response))
            case let .stale(response, error): state = .stale(mark(response), error)
            case .loading, .failed: break
            }
        }

        public func clearInstallFailure() {
            installState = .idle
        }

        // MARK: - Keyboard

        /// `Return` commits the view's one default action: opening the **detail** for the selection.
        ///
        /// Never installing. A list row that installs is exactly the one-click path from a ranking
        /// to executing someone's code that this board is shaped to refuse. Returns `false` when
        /// there is nothing selected, so the key is left unhandled rather than silently swallowed.
        public func commitDefaultAction() -> Bool {
            guard let entry = selectedEntry() else { return false }
            sheetEntryID = entry.id
            installState = .idle
            return true
        }

        /// `Esc` dismisses the sheet first, then clears the selection — never both at once.
        public func escape() {
            if sheetEntryID != nil {
                sheetEntryID = nil
                installState = .idle
            } else {
                selection = nil
            }
        }

        public func requestSearchFocus() {
            focusSearchRequests += 1
        }

        /// Moves the selection, and reports whether it had anywhere to move.
        ///
        /// The return value is what lets the view leave the key **unhandled** on an empty board, so
        /// an arrow key reaches the scroll view instead of being swallowed by a board with nothing
        /// to select.
        @discardableResult
        public func moveSelection(by offset: Int) -> Bool {
            let visible = rows
            guard !visible.isEmpty else { return false }
            guard let current = selection, let index = visible.firstIndex(where: { $0.id == current })
            else {
                selection = visible[offset >= 0 ? 0 : visible.count - 1].id
                return true
            }
            let next = min(max(index + offset, 0), visible.count - 1)
            selection = visible[next].id
            return true
        }

        /// Reset to the ordering that shows everything — what an emptied scoped ordering offers.
        public func showBestMatch() {
            ordering = .bestMatch
        }

        public func clearSearch() {
            search = ""
            submitSearch()
        }
    }
#endif
