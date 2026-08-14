#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Discover — the merged official + Smithery catalogue.
    ///
    /// **The one rule this board is shaped around: it is never one click from a ranking to running
    /// someone's code.** A row opens a detail sheet; only the sheet installs. That is why there is no
    /// prominent action in the header and no `Add` on a row, and why `Return` opens the sheet rather
    /// than committing.
    ///
    /// Every branch below comes from `RegistryPresentation` or `RegistryCapability`, both of which
    /// are testable without a host. This file draws answers and decides nothing — which matters more
    /// here than on any other board, because Discover's decisions are honesty decisions (which
    /// universe a number is true over, what a date means, whether an argv gets shown) and an honesty
    /// decision buried in a `body` is one nobody can test.
    public struct DiscoverBoard: View {
        @Bindable private var board: DiscoverBoardModel
        @FocusState private var isSearchFocused: Bool

        public init(board: DiscoverBoardModel) {
            self.board = board
        }

        public var body: some View {
            boardColumn
                .task { await board.load() }
                // The model is owned by `ShellModel` and outlives this view, so navigating away
                // would otherwise leave a debounce to fire, issue two third-party requests, and
                // mutate a board nobody is looking at.
                .onDisappear { board.cancelPending() }
                .sheet(isPresented: sheetPresented) {
                    if let entry = board.sheetEntry() {
                        DiscoverDetailSheet(board: board, entry: entry)
                    }
                }
                .onKeyPress(.escape) {
                    board.escape()
                    return .handled
                }
                .onKeyPress(.return) {
                    board.commitDefaultAction() ? .handled : .ignored
                }
                .onKeyPress(.upArrow) {
                    board.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    board.moveSelection(by: 1)
                    return .handled
                }
                .onChange(of: board.focusSearchRequests) { _, _ in isSearchFocused = true }
        }

        /// Bound rather than stored: the model holds the sheet's entry **by id**, so the sheet reads
        /// the same row the board does and sees a completed install.
        private var sheetPresented: Binding<Bool> {
            Binding(
                get: { board.sheetEntryID != nil },
                set: { if !$0 { board.sheetEntryID = nil } }
            )
        }

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch board.state {
                case .loading:
                    header(response: nil)
                    // §5: a skeleton at the real row geometry, never a spinner over a blank pane.
                    DiscoverSkeletonRows()
                    Text(RegistryPresentation.slowSearchNote)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DiscoverBoardMetrics.gap)
                case let .loaded(response):
                    populated(response, staleError: nil)
                case let .stale(response, error):
                    populated(response, staleError: error)
                case let .failed(error):
                    // Offline has its own pane inside `ConnectionFailurePane`; every other refusal
                    // renders from the same three strings, so there is one wording per state across
                    // the app (§6). Never conflated with "the indexes did not answer", which is a
                    // warning on a loaded response rather than a failure.
                    ConnectionFailurePane(error: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(DiscoverBoardMetrics.panePadding)
            // Pinned to the top: the shell's content zone gives its pane a `minHeight`, and a VStack
            // handed more height than it needs centres itself in it. A board reads from its top edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        @ViewBuilder
        private func populated(
            _ response: RegistrySearchResponse,
            staleError: ControlAPIError?
        ) -> some View {
            header(response: response)

            if let staleError {
                StaleReadingBanner(error: staleError)
                    .padding(.bottom, DiscoverBoardMetrics.gap)
            }

            controls()
            orderingNote(response)
            columnHeaders()

            let rows = board.rows
            if let empty = RegistryPresentation.emptyMessage(
                response,
                ordering: board.ordering,
                query: board.search
            ) {
                MessageState(
                    StateMessage(title: empty.title, detail: empty.detail, actionLabel: empty.action),
                    icon: .search
                ) {
                    // The action matches its label because it reads the same judgement that wrote
                    // the label, rather than re-deciding "is there a search" against an untrimmed
                    // string the presentation layer already called blank.
                    if empty.clearsSearch { board.clearSearch() }
                    if empty.resetsOrdering { board.showBestMatch() }
                    if !empty.clearsSearch, !empty.resetsOrdering { board.submitSearch() }
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: DiscoverBoardMetrics.hairline) {
                    ForEach(rows) { entry in
                        DiscoverBoardRow(entry: entry, isSelected: board.selection == entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture { board.selection = entry.id }
                            // Opening detail is the row's only action, and it is deliberately not
                            // an install.
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                board.selection = entry.id
                                _ = board.commitDefaultAction()
                            })
                    }
                }
                // A re-query keeps its rows on screen and says they are being replaced, rather than
                // blanking to a skeleton — blanking on every keystroke is the same defect as
                // throwing away a stale reading.
                .opacity(board.isRefreshing ? 0.55 : 1)
            }

            footer(response)
        }

        private func header(response: RegistrySearchResponse?) -> some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.labelGap) {
                Text("Discover")
                    .typeRole(.title1)
                    .foregroundStyle(ColorToken.t1.color)
                // Empty while loading: a count that is not yet known is not a count, and "Loading…"
                // where a number belongs is a worse answer than nothing.
                //
                // There is deliberately no prominent action here. Discover's one primary action
                // lives in the detail sheet, which is the whole of detail-then-install.
                Text(response.map(RegistryPresentation.subtitle) ?? "")
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t2.color)
            }
            .padding(.bottom, DiscoverBoardMetrics.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func controls() -> some View {
            HStack(spacing: DiscoverBoardMetrics.gap) {
                // A segmented control switches the view in place and is never primary navigation
                // (§3.6).
                Picker("", selection: $board.ordering) {
                    ForEach(RegistryPresentation.Ordering.allCases) { ordering in
                        Text(ordering.title).tag(ordering)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                // Deliberately "Search the registries", not "Filter" — this is a query to two
                // third-party indexes, and the copy says so because the behaviour differs.
                SearchField(text: $board.search, placeholder: "Search the registries")
                    .frame(width: DiscoverBoardMetrics.searchWidth)
                    .focused($isSearchFocused)
                    .onChange(of: board.search) { _, _ in board.queryChanged() }
                    .onSubmit { board.submitSearch() }

                Spacer(minLength: 0)
            }
            .padding(.bottom, DiscoverBoardMetrics.tightGap)
        }

        /// What the current ordering set aside, or why it cannot speak at all — one quiet secondary
        /// sentence directly under the control it is about (§6).
        ///
        /// **A note on the disabled case.** §3.4 asks for a segment whose universe is empty to dim
        /// in place with its reason. AppKit's segmented control, which `.pickerStyle(.segmented)`
        /// renders, has no per-segment disabled state, and hand-rolling a segmented control to get
        /// one would trade a native control for a drawn imitation on the surface where nativeness
        /// matters most. So the reason is stated here, always visible, and the empty state below
        /// carries the recovery action (`Show best match`). The user is never left with an
        /// unexplained empty board — which is what the rule is protecting.
        @ViewBuilder
        private func orderingNote(_ response: RegistrySearchResponse) -> some View {
            let note = RegistryPresentation.disabledReason(response, ordering: board.ordering)
                ?? RegistryPresentation.exclusionNote(response, ordering: board.ordering)
            if let note {
                Text(note)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DiscoverBoardMetrics.tightGap)
            }
        }

        /// **Two headers are deliberately neutral.** The figure column holds sessions on one row and
        /// stars on the next; the date column holds "added" on one and "updated" on the next. A
        /// header naming either unit would make a claim the cells beneath it contradict, so each
        /// names what the column *is* and lets the cell say which — the same discipline as the
        /// figure carrying its own unit.
        private func columnHeaders() -> some View {
            HStack(spacing: DiscoverBoardMetrics.rowPadding) {
                Color.clear.frame(width: DiscoverBoardMetrics.tile, height: 1)
                Text("server").frame(width: DiscoverBoardMetrics.nameColumn, alignment: .leading)
                Text("source").frame(width: DiscoverBoardMetrics.markColumn, alignment: .leading)
                Text("measured").frame(width: DiscoverBoardMetrics.figureColumn, alignment: .leading)
                Text("date").frame(width: DiscoverBoardMetrics.dateColumn, alignment: .leading)
                Spacer(minLength: 0)
            }
            // Sentence case, secondary colour, no tracked uppercase (§3.2).
            .typeRole(.caption)
            .foregroundStyle(ColorToken.t3.color)
            .padding(.horizontal, DiscoverBoardMetrics.rowPadding)
            .padding(.bottom, DiscoverBoardMetrics.tightGap)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColorToken.line.color)
                    .frame(height: DiscoverBoardMetrics.hairline)
            }
        }

        /// Where the incompleteness is stated. Each sentence appears only when its condition holds,
        /// and every one is computed from the response rather than written as a constant.
        private func footer(_ response: RegistrySearchResponse) -> some View {
            VStack(alignment: .leading, spacing: DiscoverBoardMetrics.tightGap) {
                ForEach(
                    RegistryPresentation.footerNotes(for: response, ordering: board.ordering),
                    id: \.self
                ) { note in
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .typeRole(.caption)
            .foregroundStyle(ColorToken.t3.color)
            .padding(.top, DiscoverBoardMetrics.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
