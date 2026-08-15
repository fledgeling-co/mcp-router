#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Evals board — the checks MCP Router can genuinely run, and the evidence they leave.
    ///
    /// **What this board is not, stated here rather than discovered.** There is no eval runner in this
    /// product: nothing calls a server's tools with fixtures and grades the replies, and a skill is
    /// never executed by the router at all — it is markdown the *client* loads into an agent's
    /// context, so no execution of it is observable to the process that would have to grade it. That
    /// second one is permanent; no future router item changes it.
    ///
    /// So what ships is what the router actually observes, stamped to the version it was observed
    /// against. The disclosure is the pane's permanent subtitle rather than a footnote, the vocabulary
    /// is observation rather than grading, and every check shows the field and value behind it.
    ///
    /// **The residual gap this board recorded is now closed, and the record is kept rather than
    /// deleted.** This comment used to read: "the destination is still called 'Evals' in the
    /// sidebar, the window title and the menu bar. `Destination.title` is a merged shared surface,
    /// so this item reports that change rather than making it (M9)." D2 made it. The sidebar row,
    /// the window title, the View-menu item and this board's own heading all read `Checks`; the
    /// enum case, its `rawValue` and the deep-link slug stay `evals` because they are identifiers
    /// that frame restoration and the prototype's `?pane=evals` link both persist.
    ///
    /// It is left standing because the honesty this board is about is the reason the word mattered:
    /// `Evals` was the one label in the app promising a graded verdict the product cannot produce.
    /// The disclosure inside the pane was never a substitute for the name, and now it does not have
    /// to be.
    ///
    /// As with Servers and Skills, every branch comes from `CheckPresentation` and is testable without
    /// a host. This file draws answers; it decides nothing.
    public struct EvalsBoard: View {
        @Bindable private var board: EvalsBoardModel
        @FocusState private var isSearchFocused: Bool

        public init(board: EvalsBoardModel) {
            self.board = board
        }

        public var body: some View {
            HStack(alignment: .top, spacing: 0) {
                boardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let selected = board.selectedSubject() {
                    Divider()
                    EvalsInspector(
                        subject: selected,
                        server: server(for: selected),
                        skill: skill(for: selected),
                        clients: board.state.reading?.skills?.clients ?? [],
                        history: board.history(for: selected),
                        historyError: board.store.loadError
                    )
                }
            }
            .task { await board.load() }
            .onKeyPress(.escape) {
                board.escape()
                return .handled
            }
            .onKeyPress(.return) {
                guard let selected = board.selectedSubject() else { return .ignored }
                Task { await board.recheck(selected) }
                return .handled
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

        private func server(for subject: CheckPresentation.Subject) -> MCPServer? {
            guard subject.kind == .server else { return nil }
            return board.state.reading?.servers.first { $0.name == subject.key.id }
        }

        private func skill(for subject: CheckPresentation.Subject) -> Skill? {
            guard subject.kind == .skill else { return nil }
            return board.state.reading?.skills?.skills.first { $0.path == subject.key.id }
        }

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch board.state {
                case .loading:
                    // The subtitle is present while loading: it is a statement about the product
                    // rather than about the data, and a loading pane that omitted it would be the one
                    // moment a user forms their first impression of what this pane claims.
                    header
                    M7SkeletonRows()
                case let .loaded(reading) where board.subjects.isEmpty:
                    header
                    emptyState(reading)
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
        private func emptyState(_ reading: EvalsBoardModel.Reading) -> some View {
            // The action is offered only when it is the one that would help. A user with skills but
            // no servers is not helped by "Add a server…", and an empty state whose action is
            // irrelevant to the reader is worse than one with none.
            let canAddServer = reading.servers.isEmpty
            MessageState(
                StateMessage(
                    title: CheckCopy.evalsEmptyTitle,
                    detail: CheckCopy.evalsEmptyDetail,
                    actionLabel: canAddServer ? CheckCopy.evalsEmptyAction : nil
                ),
                icon: .evals
            )
            .frame(maxWidth: .infinity)
        }

        @ViewBuilder
        private func populated(staleError: ControlAPIError?) -> some View {
            header

            if let staleError {
                StaleReadingBanner(error: staleError)
                    .padding(.bottom, M7BoardMetrics.gap)
            }
            if let skillsError = board.state.reading?.skillsError {
                // Partial: the servers half loaded and the skills half did not. Named rather than
                // rendered as an absence, because a shorter list is indistinguishable from a
                // complete one.
                PartialIndexNote(text: skillsError.userFacingDescription)
                    .padding(.bottom, M7BoardMetrics.gap)
            }
            if let writeError = board.writeError {
                PartialIndexNote(text: writeError.userFacingDescription)
                    .padding(.bottom, M7BoardMetrics.gap)
            }

            controls
            columnHeaders

            let rows = board.rows
            if rows.isEmpty {
                let copy = CheckCopy.evalsEmptyInFilter(board.filter.title)
                MessageState(
                    StateMessage(title: copy.title, detail: copy.detail, actionLabel: copy.action),
                    icon: .search
                ) {
                    board.filter = .all
                    board.search = ""
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: M7BoardMetrics.hairline) {
                    ForEach(rows) { subject in
                        EvalsBoardRow(
                            subject: subject,
                            isSelected: board.selection == subject.id,
                            isRechecking: board.recheckingSubject == subject.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { board.selection = subject.id }
                    }
                }
                Text(CheckCopy.evalsFooter)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, M7BoardMetrics.gap)
            }
        }

        private var header: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: M7BoardMetrics.labelGap) {
                    Text(CheckCopy.evalsTitle)
                        .typeRole(.title1)
                        .foregroundStyle(ColorToken.t1.color)
                    Text(CheckCopy.evalsSubtitle)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                // Standard, not accent-filled: §3.4 allows one prominent action per view and this
                // board's job is to report rather than to urge.
                Button(CheckCopy.runAllLabel) {
                    Task { await board.recheckAll() }
                }
                .buttonStyle(StandardButtonStyle())
                .disabled(board.state.reading == nil)
            }
            .padding(.bottom, M7BoardMetrics.gap)
        }

        private var controls: some View {
            HStack(spacing: M7BoardMetrics.gap) {
                Picker("", selection: $board.filter) {
                    ForEach(CheckPresentation.Filter.allCases) { filter in
                        Text(label(for: filter)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                // A real text field, so ⌘F has something to focus. A segmented control cannot take
                // typed input, which is what the first draft bound the key to.
                SearchField(text: $board.search, placeholder: "Filter subjects")
                    .frame(width: M7BoardMetrics.searchWidth)
                    .focused($isSearchFocused)

                Spacer(minLength: 0)
            }
            .padding(.bottom, M7BoardMetrics.gap)
        }

        private func label(for filter: CheckPresentation.Filter) -> String {
            // A zero count carries no badge at all rather than reading "0", which looks like a
            // condition that resolved rather than one that never applied (M4's precedent).
            guard let count = CheckPresentation.count(
                board.subjects,
                filter: filter,
                search: board.search
            ) else {
                return filter.title
            }
            return "\(filter.title) \(count)"
        }

        private var columnHeaders: some View {
            HStack(spacing: M7BoardMetrics.rowPadding) {
                Color.clear.frame(width: M7BoardMetrics.tile, height: 1)
                Text("subject").frame(width: M7BoardMetrics.nameColumn, alignment: .leading)
                Text("kind").frame(width: M7BoardMetrics.kindColumn, alignment: .leading)
                Text("checks").frame(width: M7BoardMetrics.tallyColumn, alignment: .leading)
                Text("checked against").frame(width: M7BoardMetrics.stampColumn, alignment: .leading)
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
