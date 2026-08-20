#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Servers board — the app's signature surface.
    ///
    /// One breaker per declared server, and the reason this item went first: after M1 the window
    /// opened and all seven panes said the surface was not built. This is the pane that makes the
    /// product legible.
    ///
    /// **What this file does and does not decide.** Every rule about *what a server means* — the
    /// subtitle precedence, the lever, the countdown, the filters — lives in
    /// `MCPRouterKit/Servers/ServerPresentation.swift` and is tested without a host. This file
    /// draws the answers. The split exists because the prototype's two failures were wrong answers
    /// from a branch rather than styling defects, and a branch only a running app can exercise is a
    /// branch that ships wrong.
    public struct ServersBoard: View {
        @Bindable private var shell: ShellModel
        @Bindable private var board: ServersBoardModel
        @FocusState private var isSearchFocused: Bool

        public init(shell: ShellModel, board: ServersBoardModel) {
            self.shell = shell
            self.board = board
        }

        /// What the tracker last published. Before the first publication the board is loading, which
        /// is the honest reading of "no answer yet" — and is not the same as an answer of none.
        private var state: ServerStateTracker.TrackerState {
            shell.trackerState ?? ServerStateTracker.TrackerState(load: .loading, stream: .notConfigured)
        }

        public var body: some View {
            HStack(alignment: .top, spacing: 0) {
                boardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The inspector is part of the content zone, so `Esc` clearing the selection puts
                // it away and the shell's two-column split view is untouched.
                if let selected = board.selectedServer(in: state) {
                    Divider()
                    ServerInspector(
                        server: selected,
                        board: board,
                        canWrite: board.canWrite(to: state),
                        pendingAuth: state.pendingAuth
                    )
                    .measured("inspector", role: "inspector", kind: .vstack, alignment: "leading")
                }
            }
            .sheet(item: $board.sheet) { sheet in
                ServerSheetHost(shell: shell, board: board, sheet: sheet)
            }
            .onKeyPress(.escape) {
                board.escape()
                return .handled
            }
            .onKeyPress(.space) {
                // §8 gives `Space` the selected row's breaker. The breaker is an indicator — there is
                // no start or stop operation on the control API — so it acts on `warm`, the only
                // lever the router actually offers over whether a process stays up. Gated by the
                // same rule as the toggle it mirrors, so the key cannot write where the control
                // would be dimmed.
                guard let selected = board.selectedServer(in: state),
                      board.canWrite(to: state),
                      !board.writesInFlight.contains(selected.name)
                else { return .ignored }
                Task { await board.setWarm(selected.name, to: !selected.warm) }
                return .handled
            }
            .onChange(of: board.focusSearchRequests) { _, _ in
                isSearchFocused = true
            }
        }

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch state.load {
                case .loading:
                    header
                    // §5: a skeleton at the real row geometry, never a spinner over a blank pane.
                    SkeletonRows()
                case let .loaded(servers) where servers.isEmpty:
                    header
                    MessageState(ServersBoardCopy.empty, icon: .conduit) {
                        board.sheet = .addServer
                    }
                    .frame(maxWidth: .infinity)
                case .loaded:
                    populated(staleError: nil)
                case let .stale(_, error):
                    populated(staleError: error)
                case let .failed(error):
                    // Offline is one of the nine and has its own pane; every other refusal renders
                    // from the same three strings, so there is exactly one wording per state (§6).
                    ConnectionFailurePane(error: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(ServersBoardMetrics.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .measured("board-column", role: "board-column", kind: .vstack, alignment: "leading")
        }

        // MARK: - The populated board, current or stale

        @ViewBuilder
        private func populated(staleError: ControlAPIError?) -> some View {
            header

            if let staleError {
                StaleReadingBanner(error: staleError)
                    .padding(.bottom, ServersBoardMetrics.gap)
            }
            if let note = board.header(from: state).partialNote {
                PartialIndexNote(text: note)
                    .padding(.bottom, ServersBoardMetrics.gap)
            }

            controls
            columnHeaders

            let rows = board.rows(from: state)
            if rows.isEmpty {
                emptyInFilter
            } else {
                table(rows)
                footer(shown: rows.count)
            }
        }

        // MARK: - Header

        /// The title and its three figures.
        ///
        /// It takes no "is this current" flag: an earlier version threaded one through from the load
        /// switch and then ignored it, because `board.header(from:)` already derives currency from
        /// the load state itself. Two places deciding one thing is how they come to disagree.
        private var header: some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ServersBoardMetrics.tightGap) {
                    Text(Destination.servers.title)
                        .typeRole(.title1)
                        .foregroundStyle(ColorToken.t1.color)
                        .measured(
                            "title", role: "board-title", kind: .text,
                            tokens: ["foreground": .t1], type: .title1,
                            text: Destination.servers.title
                        )
                    Text(board.header(from: state).subtitle())
                        .typeRole(.body)
                        .foregroundStyle(ColorToken.t2.color)
                        .measured(
                            "subtitle", role: "board-subtitle", kind: .text,
                            tokens: ["foreground": .t2], type: .body,
                            text: board.header(from: state).subtitle()
                        )
                }
                .measured("title-block", role: "title-block", kind: .vstack, alignment: "leading")
                Spacer(minLength: 0)
                // §3.4: exactly one prominent accent-filled action per view, trailing. This is it —
                // every other control on this board is a standard one.
                Button(MenuCommand.addServer.title) { board.sheet = .addServer }
                    .buttonStyle(ProminentButtonStyle())
                    .measured(
                        "primary-action", role: "primary-action", kind: .leaf,
                        tokens: ["background": .accent, "foreground": .onAccent],
                        type: .body, text: MenuCommand.addServer.title
                    )
            }
            .padding(.bottom, ServersBoardMetrics.gap)
            .measured("board-header", role: "board-header", kind: .hstack, alignment: "firstTextBaseline")
        }

        // How long ago the stale reading was taken is **not** shown, because nothing observes it.
        // See `ServersBoardHeader.subtitle()` for the measurement behind that.

        // MARK: - Search and filter

        private var controls: some View {
            HStack(spacing: ServersBoardMetrics.gap) {
                ServerFilterBar(
                    filter: $board.filter,
                    counts: board.counts(from: state)
                )
                .measured("filter-bar", role: "segmented-filter", kind: .hstack)
                Spacer(minLength: 0)
                ServerSearchField(query: $board.searchQuery)
                    .focused($isSearchFocused)
                    .measured("search-field", role: "search-field", kind: .leaf)
            }
            .padding(.bottom, ServersBoardMetrics.gap)
            .measured("controls", role: "controls-row", kind: .hstack)
        }

        private func table(_ rows: [ServerRowModel]) -> some View {
            LazyVStack(spacing: ServersBoardMetrics.hairline) {
                ForEach(rows) { row in
                    ServerRowView(
                        row: row,
                        isSelected: board.selection == row.id,
                        isWriting: board.writesInFlight.contains(row.id),
                        canWrite: board.canWrite(to: state),
                        error: board.rowErrors[row.id],
                        select: { board.selection = row.id },
                        act: { action in
                            guard let server = board.server(named: row.id, in: state) else { return }
                            await board.perform(action, on: server)
                        }
                    )
                }
            }
            .background(ColorToken.panel.color)
            .measured(
                "table", role: "table", kind: .vstack,
                tokens: ["background": .panel]
            )
        }

        /// The empty result, worded for the state that actually produced it.
        ///
        /// Three cases rather than one, because search and filter **compose**: a query that matches
        /// an idle server, read under the Running segment, matches nothing here while the server
        /// plainly exists. Saying "nothing is named that" then would be the same false-sentence
        /// defect this board removed from the prototype's single empty string, one level further in.
        private var emptyInFilter: some View {
            let query = board.searchQuery.trimmingCharacters(in: .whitespaces)
            let isSearching = !query.isEmpty
            let isFiltered = board.filter != .all
            let message: StateMessage = if isSearching, isFiltered {
                StateMessage(
                    title: "No \(board.filter.title.lowercased()) server matches “\(query)”",
                    detail: """
                    Another server may match — this is only the \
                    \(board.filter.title.lowercased()) view.
                    """,
                    actionLabel: "Search all servers"
                )
            } else if isSearching {
                StateMessage(
                    title: "No server matches “\(query)”",
                    detail: "Nothing is named that, and no tool on any server is either.",
                    actionLabel: "Clear search"
                )
            } else {
                {
                    let copy = board.filter.emptyMessage(
                        totalServers: state.servers.count,
                        reading: board.reading(for: state)
                    )
                    return StateMessage(
                        title: copy.title,
                        detail: copy.detail,
                        actionLabel: "Show all servers"
                    )
                }()
            }
            return MessageState(message, icon: isSearching ? .search : .servers) {
                if isSearching, isFiltered {
                    board.filter = .all
                } else if isSearching {
                    board.clearSearch()
                } else {
                    board.showAll()
                }
            }
            .frame(maxWidth: .infinity)
        }

        /// The footer.
        ///
        /// It used to end "… tools in every session's tool list", which is false the moment any
        /// server is scoped — `visibleTo(u, opts.cwd)` in `src/manifest.ts` filters scoped servers by
        /// the calling session's directory, so the same router answers a different list to a session
        /// in one repo than to one in another. The count is observed; the claim attached to it was
        /// not, and this board ships the control that creates the discrepancy.
        private func footer(shown: Int) -> some View {
            let header = board.header(from: state)
            let tools = board.rows(from: state).reduce(0) { $0 + $1.tools }
            let scoped = state.servers.filter { !$0.projects.isEmpty }.count
            return VStack(alignment: .leading, spacing: ServersBoardMetrics.tightGap) {
                Text("\(shown) of \(header.servers) servers · \(tools) tools indexed")
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .measured(
                        "footer-counts", role: "footer-counts", kind: .text,
                        tokens: ["foreground": .t3], type: .caption,
                        text: "\(shown) of \(header.servers) servers · \(tools) tools indexed"
                    )
                if scoped > 0 {
                    Text(
                        scoped == 1
                            ? "One of them is scoped, so it is not in every session's tool list."
                            : "\(scoped) of them are scoped, so they are not in every session's tool list."
                    )
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                }
            }
            .padding(.top, ServersBoardMetrics.gap)
            .measured("footer", role: "footer", kind: .vstack, alignment: "leading")
        }
    }

#endif
