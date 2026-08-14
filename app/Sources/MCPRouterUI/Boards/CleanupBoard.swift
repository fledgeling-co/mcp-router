#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Cleanup board — what MCP Router has never seen used, and how much it actually knows.
    ///
    /// **Two rules the brief learned the hard way, and both are visible in this file.** There is no
    /// trash metaphor: nothing here is rubbish awaiting disposal, the icon is a download arrow rather
    /// than a bin, and nothing is tallied as reclaimed — a never-used server was never deleted. And
    /// there is no automatic cull: an invocation count cannot tell "unused because worthless" from
    /// "unused because rare but critical", so this pane proposes and the human decides.
    ///
    /// **No number here is one the router did not observe**, and the footer says so in the one place
    /// a reader would look for a memory saving. MCP Router never runs the world in which every server
    /// is resident, so it has no figure to subtract from, and inventing one would be the defect this
    /// whole product refuses.
    public struct CleanupBoard: View {
        @Bindable private var board: CleanupBoardModel
        @FocusState private var isSearchFocused: Bool

        public init(board: CleanupBoardModel) {
            self.board = board
        }

        public var body: some View {
            HStack(alignment: .top, spacing: 0) {
                boardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let selected = board.selectedCandidate() {
                    Divider()
                    CleanupInspector(board: board, candidate: selected)
                }
            }
            .task { await board.load() }
            .sheet(item: $board.sheet) { sheet in
                CleanupSheetHost(board: board, sheet: sheet)
            }
            .onKeyPress(.escape) {
                board.escape()
                return .handled
            }
            .onKeyPress(.return) {
                // Opens the inspector. It does NOT remove: the one destructive action on this board
                // is never what Return does.
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

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch board.state {
                case .loading:
                    header
                    M7SkeletonRows()
                case .loaded where board.candidates.isEmpty:
                    header
                    // No action: nothing is wrong, so there is nothing to offer. An empty state with
                    // a button invents a task.
                    MessageState(
                        StateMessage(
                            title: CleanupPresentation.emptyTitle,
                            detail: CleanupPresentation.emptyDetail,
                            actionLabel: nil
                        ),
                        icon: .cleanup
                    )
                    .frame(maxWidth: .infinity)
                case .loaded:
                    populated(staleError: nil)
                case let .stale(_, error):
                    populated(staleError: error)
                case let .failed(error):
                    ConnectionFailurePane(error: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(M7BoardMetrics.panePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }

        @ViewBuilder
        private func populated(staleError: ControlAPIError?) -> some View {
            header

            if let staleError {
                StaleReadingBanner(error: staleError)
                    .padding(.bottom, M7BoardMetrics.gap)
            }
            // The weak-window banner: "never used" over two hours is not evidence, and the pane says
            // so rather than letting the list be read as a finding.
            if let window = board.window, window.isWeak {
                PartialIndexNote(text: CleanupPresentation.weakWindowBanner(window: window))
                    .padding(.bottom, M7BoardMetrics.gap)
            }
            let held = board.heldOut
            if !held.isEmpty {
                PartialIndexNote(
                    text: CleanupPresentation.heldOutBanner(count: held.count, clients: held.clients)
                )
                .padding(.bottom, M7BoardMetrics.gap)
            }
            if let writeError = board.writeError {
                PartialIndexNote(text: writeError.userFacingDescription)
                    .padding(.bottom, M7BoardMetrics.gap)
            }

            observation
            controls
            columnHeaders

            let rows = board.rows
            if rows.isEmpty {
                MessageState(
                    StateMessage(
                        title: CleanupPresentation.emptyInFilterTitle,
                        detail: CleanupPresentation.emptyInFilterDetail,
                        actionLabel: "Show all"
                    ),
                    icon: .search
                ) {
                    board.filter = .all
                    board.search = ""
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: M7BoardMetrics.hairline) {
                    ForEach(rows) { candidate in
                        CleanupBoardRow(
                            candidate: candidate,
                            isSelected: board.selection == candidate.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { board.selection = candidate.id }
                    }
                }
                Text(CleanupPresentation.footer)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, M7BoardMetrics.gap)
            }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                        Text(CleanupPresentation.title)
                            .typeRole(.title1)
                            .foregroundStyle(ColorToken.t1.color)
                        Text(CleanupPresentation.subtitle(window: board.window))
                            .typeRole(.subheadline)
                            .foregroundStyle(ColorToken.t2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    // Standard, never accent-filled. §3.4 allows one prominent action per view and
                    // forbids a destructive one as the default; the only thing this pane proposes is
                    // a removal, so the correct number of prominent actions is zero.
                    Button(CleanupPresentation.resetLabel) { board.sheet = .resetHistory }
                        .buttonStyle(StandardButtonStyle())
                        .disabled(board.state.reading == nil)
                }
                // States what the sidebar badge counts, because it counts a subset of this list —
                // otherwise a badge of 3 against a list of 9 is left for the reader to reconcile.
                //
                // Only once a reading exists. `neverUsedServerCount` folds an absent reading to
                // zero, so rendering this unconditionally would tell a reader whose router never
                // answered that the sidebar counts zero never-used servers — a considered figure
                // derived from nothing, which is the same defect the shell's readout drops its
                // counts to avoid.
                if board.state.reading != nil {
                    Text(CleanupPresentation.badgeNote(neverUsedCount: board.neverUsedServerCount))
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, M7BoardMetrics.gap)
        }

        private var observation: some View {
            HStack(spacing: M7BoardMetrics.gap) {
                SectionLabel("Observed over")
                CleanupObservationTrack(window: board.window)
                Spacer(minLength: 0)
            }
            .padding(.bottom, M7BoardMetrics.gap)
        }

        private var controls: some View {
            HStack(spacing: M7BoardMetrics.gap) {
                Picker("", selection: $board.filter) {
                    ForEach(CleanupBoardModel.Filter.allCases) { filter in
                        Text(label(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                SearchField(text: $board.search, placeholder: "Filter proposal")
                    .frame(width: M7BoardMetrics.searchWidth)
                    .focused($isSearchFocused)

                Spacer(minLength: 0)
            }
            .padding(.bottom, M7BoardMetrics.gap)
        }

        private func label(for filter: CleanupBoardModel.Filter) -> String {
            guard let count = board.count(for: filter) else { return filter.title }
            return "\(filter.title) \(count)"
        }

        private var columnHeaders: some View {
            HStack(spacing: M7BoardMetrics.rowPadding) {
                Color.clear.frame(width: M7BoardMetrics.tile, height: 1)
                Text("capability").frame(width: M7BoardMetrics.nameColumn, alignment: .leading)
                Text("kind").frame(width: M7BoardMetrics.kindColumn, alignment: .leading)
                // "why it is here" — the observation that proposed it, never a judgement of worth.
                Text("why it is here").frame(width: M7BoardMetrics.reasonColumn, alignment: .leading)
                Spacer(minLength: 0)
            }
            .typeRole(.caption)
            .foregroundStyle(ColorToken.t3.color)
            .padding(.horizontal, M7BoardMetrics.rowPadding)
            .padding(.bottom, M7BoardMetrics.tightGap)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColorToken.line.color).frame(height: M7BoardMetrics.hairline)
            }
        }
    }
#endif
