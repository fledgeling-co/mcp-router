#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Skills board — the half of the product that is not MCP.
    ///
    /// **What this board does not show, and why it is stated here rather than discovered.** The
    /// prototype's skills table draws a run count, a last-run time and an evaluation result. None of
    /// the three exists: a skill is markdown the *client* loads into an agent's context, so it never
    /// reaches the router and no invocation of it is observable to the process that would have to
    /// report one, and there is no eval runner in this product at all. `DESIGN.md` §6 forbids
    /// displaying a figure the router does not observe, so those columns are absent rather than
    /// rendered empty — an empty cell in a populated table reads as a claim about *that row*, and
    /// the router cannot tell "never run" from "run constantly, invisibly to me". The absence is
    /// stated once, in the footer, as a property of the product, which is a claim that is true.
    ///
    /// M1 set the precedent by refusing the Skills sidebar badge this same prototype draws.
    ///
    /// As with the Servers board, every branch below comes from `SkillPresentation` and is testable
    /// without a host. This file draws answers; it decides nothing.
    public struct SkillsBoard: View {
        @Bindable private var shell: ShellModel
        @Bindable private var board: SkillsBoardModel
        @FocusState private var isSearchFocused: Bool

        public init(shell: ShellModel, board: SkillsBoardModel) {
            self.shell = shell
            self.board = board
        }

        public var body: some View {
            HStack(alignment: .top, spacing: 0) {
                boardColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let selected = board.selectedSkill(), let response = board.state.response {
                    Divider()
                    SkillInspector(skill: selected, response: response, board: board)
                }
            }
            .task { await board.load() }
            .sheet(item: $board.sheet) { sheet in
                SkillSheetHost(board: board, sheet: sheet)
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

        private var boardColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                switch board.state {
                case .loading:
                    header(response: nil)
                    // §5: a skeleton at the real row geometry, never a spinner over a blank pane.
                    SkillSkeletonRows()
                case let .loaded(response) where response.skills.isEmpty:
                    header(response: response)
                    MessageState(
                        StateMessage(
                            title: SkillPresentation.emptyTitle,
                            detail: SkillPresentation.emptyDetail,
                            actionLabel: "Manage marketplaces…"
                        ),
                        icon: .layers
                    ) {
                        board.sheet = .marketplaces
                    }
                    .frame(maxWidth: .infinity)
                case let .loaded(response):
                    populated(response, staleError: nil)
                case let .stale(response, error):
                    populated(response, staleError: error)
                case let .failed(error):
                    // Offline has its own pane; every other refusal renders from the same three
                    // strings, so there is exactly one wording per state across the app (§6).
                    ConnectionFailurePane(error: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(SkillsBoardMetrics.panePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        @ViewBuilder
        private func populated(_ response: SkillsResponse, staleError: ControlAPIError?) -> some View {
            header(response: response)

            if let staleError {
                StaleReadingBanner(error: staleError)
                    .padding(.bottom, SkillsBoardMetrics.gap)
            }
            if let note = SkillPresentation.partialNote(for: response) {
                PartialIndexNote(text: note)
                    .padding(.bottom, SkillsBoardMetrics.gap)
            }

            controls(response)
            columnHeaders(response)

            let rows = board.rows
            if rows.isEmpty, let empty = SkillPresentation.emptyInFilter(board.filter) {
                // Never the first-run empty state: the user has skills, the filter simply matches
                // none of them, and saying "no skills installed" here would be false.
                MessageState(
                    StateMessage(title: empty.title, detail: empty.detail, actionLabel: empty.action),
                    icon: .search
                ) {
                    board.filter = .all
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVStack(spacing: SkillsBoardMetrics.hairline) {
                    ForEach(rows) { skill in
                        SkillsBoardRow(
                            skill: skill,
                            response: response,
                            isSelected: board.selection == skill.id,
                            onReview: { board.sheet = .heldVersion(skillID: skill.id) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { board.selection = skill.id }
                    }
                }
                Text(SkillPresentation.observationFooter)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SkillsBoardMetrics.gap)
            }
        }

        private func header(response: SkillsResponse?) -> some View {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: SkillsBoardMetrics.labelGap) {
                    Text("Skills")
                        .typeRole(.title1)
                        .foregroundStyle(ColorToken.t1.color)
                    // Empty while loading: a count that is not yet known is not a count, and
                    // "Loading…" where a number belongs is a worse answer than nothing.
                    Text(response.map(SkillPresentation.subtitle) ?? "")
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                }
                Spacer(minLength: 0)
                Button("Manage marketplaces…") { board.sheet = .marketplaces }
                    .buttonStyle(StandardButtonStyle())
            }
            .padding(.bottom, SkillsBoardMetrics.gap)
        }

        private func controls(_ response: SkillsResponse) -> some View {
            HStack(spacing: SkillsBoardMetrics.gap) {
                // A segmented control switches the view in place and is never primary navigation
                // (§3.6).
                Picker("", selection: $board.filter) {
                    ForEach(SkillPresentation.Filter.allCases) { filter in
                        Text(label(for: filter, in: response)).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                SearchField(text: $board.search, placeholder: "Filter skills")
                    .frame(width: SkillsBoardMetrics.searchWidth)
                    .focused($isSearchFocused)

                Spacer(minLength: 0)
            }
            .padding(.bottom, SkillsBoardMetrics.gap)
        }

        private func label(for filter: SkillPresentation.Filter, in response: SkillsResponse) -> String {
            // A zero count carries no badge at all, rather than reading "0" — which looks like a
            // condition that resolved rather than one that never applied.
            guard let count = SkillPresentation.count(response.skills, filter: filter) else {
                return filter.title
            }
            return "\(filter.title) \(count)"
        }

        private func columnHeaders(_ response: SkillsResponse) -> some View {
            HStack(spacing: SkillsBoardMetrics.rowPadding) {
                Color.clear.frame(width: SkillsBoardMetrics.tile, height: 1)
                Text("skill").frame(width: SkillsBoardMetrics.nameColumn, alignment: .leading)
                Text("installed into").frame(width: SkillsBoardMetrics.slotsColumn, alignment: .leading)
                // Named "plugin version" rather than "version", because it is the version of the
                // PLUGIN that supplies the skill and a plugin can supply thirty of them. A column
                // called "version" on a skills table claims each row is versioned independently.
                Text("plugin version").frame(width: SkillsBoardMetrics.versionColumn, alignment: .leading)
                Spacer(minLength: 0)
            }
            // Sentence case, secondary colour, no tracked uppercase (§3.2).
            .typeRole(.caption)
            .foregroundStyle(ColorToken.t3.color)
            .padding(.horizontal, SkillsBoardMetrics.rowPadding)
            .padding(.bottom, SkillsBoardMetrics.tightGap)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ColorToken.line.color).frame(height: SkillsBoardMetrics.hairline)
            }
        }
    }

    /// A plain search field at the design system's control size.
    struct SearchField: View {
        @Binding var text: String
        let placeholder: String

        var body: some View {
            HStack(spacing: SkillsBoardMetrics.tightGap) {
                IconView(.search, size: TypeToken.callout.size)
                    .foregroundStyle(ColorToken.t3.color)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
            }
            .padding(.horizontal, SkillsBoardMetrics.tightGap * 2)
            .frame(height: MetricToken.controlRegular.leadingScalar)
            .background {
                RoundedRectangle(cornerRadius: MetricToken.focusRing.leadingScalar * 3, style: .continuous)
                    .fill(ColorToken.f2.color)
            }
        }
    }
#endif
