#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Harnesses board — which AI tools on this Mac actually route through here.
    ///
    /// **Nothing on it is read from disk by this app.** `no-raw-design-values.sh`'s A36 rule
    /// forbids the file manager, the two file-reading initialisers and the bundle anywhere under
    /// `Boards/`, because reading a file is one of the ways past the control API — the spellings
    /// are deliberately not written out here, since the gate is a raw source grep and a comment
    /// quoting one reads exactly like a call. Every path, count and reading below crossed the
    /// loopback boundary from `GET /harnesses`, which is why this board could not ship before that
    /// route existed.
    ///
    /// **What it does not show.** The brief asks for each harness's version and there is none here:
    /// nothing in this product observes a harness's installed version, and the nearest thing —
    /// `HTTPCapability`'s `codex 0.146.0` — names the binary a probe was taken against in August
    /// 2026 rather than the one on this machine. Rendering that as "version" would be a claim about
    /// the user's install that nothing measured, which `DESIGN.md` §6 forbids. Parked with that
    /// reason rather than filled in.
    public struct HarnessesBoard: View {
        @Bindable private var board: HarnessesBoardModel

        public init(board: HarnessesBoardModel) {
            self.board = board
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.sectionGap) {
                header
                content
            }
            .padding(M22BoardMetrics.panePadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task { await board.load() }
            .sheet(item: $board.sheet) { sheet in
                HarnessSheetHost(board: board, sheet: sheet)
            }
            .onKeyPress(.escape) {
                board.escape()
                return .handled
            }
            // The board marks its own root and nothing more. `measureSurface` belongs to
            // the measurement harness, which wraps the surface and names it
            // `<surface>.<state>`; calling it here installed a second coordinate space and
            // a second preference reader, and the dump came back rooted at `harnesses`
            // rather than at the state that was asked for.
            .measured("board-column", role: "board-column", kind: .vstack, alignment: "leading")
        }

        private var header: some View {
            HStack(alignment: .top, spacing: M22BoardMetrics.gap) {
                titleBlock
                Spacer(minLength: 0)
                actions
            }
            .measured("board-header", role: "board-header", kind: .hstack)
        }

        /// The board's own two controls.
        ///
        /// `Check again` re-runs the read, and it earns its place rather than mirroring the mock:
        /// these counts are read from files on a drift interval, the footer says how old they are,
        /// and the brief's own words are that a stale reading here is worse than no reading — so a
        /// board that can only be refreshed by leaving it is a board that shows a stale number with
        /// no way to move it.
        private var actions: some View {
            HStack(spacing: M22BoardMetrics.tightGap) {
                Button(HarnessBoardCopy.rescan) {
                    Task { await board.load() }
                }
                .buttonStyle(StandardButtonStyle())
                .measured(
                    "rescan", role: "board-action", type: .body, text: HarnessBoardCopy.rescan
                )
                Button(HarnessBoardCopy.reconcileAll) {}
                    .buttonStyle(StandardButtonStyle())
                    .disabled(true)
                    .help(HarnessBoardCopy.reconcileUnavailable)
                    .accessibilityHint(HarnessBoardCopy.reconcileUnavailable)
                    .measured(
                        "reconcile-all", role: "board-action", type: .body,
                        text: HarnessBoardCopy.reconcileAll
                    )
            }
            .measured("board-actions", role: "board-actions", kind: .hstack)
        }

        private var titleBlock: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                Text(HarnessBoardCopy.title)
                    .typeRole(.title1)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "board-title", role: "board-title", kind: .text,
                        tokens: ["foreground": .t1], type: .title1, text: HarnessBoardCopy.title
                    )
                Text(HarnessBoardCopy.subtitle)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "board-subtitle", role: "board-subtitle", kind: .text,
                        tokens: ["foreground": .t2], type: .body,
                        text: HarnessBoardCopy.subtitle
                    )
            }
            .measured("board-head", role: "board-head", kind: .vstack)
        }

        /// The four states this board answers for.
        ///
        /// `loading` and `failed` are the load's; `empty` is a real answer of none, which is a
        /// different thing and gets the board's own words. A `stale` reading still draws its rows,
        /// with the failure named above them rather than instead of them.
        @ViewBuilder
        private var content: some View {
            switch board.state {
            case .loading:
                HarnessSkeleton()
                    .measured("harnesses-loading", role: "loading", kind: .vstack)
            case let .failed(error):
                MessageState(
                    StateMessage(
                        title: error.headline, detail: error.advice,
                        actionLabel: error.actionLabel
                    ),
                    icon: .harness
                )
                .frame(maxWidth: .infinity)
                .measured("harnesses-failed", role: "error", kind: .vstack)
            case .loaded, .stale:
                if board.rows.isEmpty {
                    MessageState(
                        StateMessage(
                            title: HarnessBoardCopy.emptyTitle,
                            detail: HarnessBoardCopy.emptyBody
                        ),
                        icon: .harness
                    )
                    .frame(maxWidth: .infinity)
                    .measured("harnesses-empty", role: "empty", kind: .vstack)
                } else {
                    populated
                }
            }
        }

        private var populated: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.sectionGap) {
                if let error = board.state.error { staleBanner(error) }
                if let finding = board.finding { findingBand(finding) }
                list
                if !board.unreadable.isEmpty {
                    HarnessUnreadableSection(rows: board.unreadable, board: board)
                }
                footer
            }
            .measured("harnesses-populated", role: "board-body", kind: .vstack)
        }

        /// The finding, when there is one. Its action opens the diff of the real file before
        /// anything is written, which is what the sheet is for and what its help tag says.
        private func findingBand(_ finding: String) -> some View {
            HStack(alignment: .top, spacing: M22BoardMetrics.gap) {
                IconView(.warn, size: TypeToken.body.size)
                    .foregroundStyle(ColorToken.attentionInk.color)
                    .measured(
                        "finding-icon", role: "finding-icon",
                        tokens: ["foreground": .attentionInk]
                    )
                Text(finding)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "finding-text", role: "finding", kind: .text,
                        tokens: ["foreground": .t1], type: .body, text: finding
                    )
                Spacer(minLength: 0)
                // The brief gives the finding an action that opens the diff of the real file. That
                // panel is M18's, so the control is here and dim rather than absent, with the
                // reason in its help tag.
                Button(HarnessBoardCopy.reconcile) {}
                    .buttonStyle(StandardButtonStyle())
                    .disabled(true)
                    .help(HarnessBoardCopy.reconcileUnavailable)
                    .accessibilityHint(HarnessBoardCopy.reconcileUnavailable)
                    .measured(
                        "finding-action", role: "finding-action", type: .body,
                        text: HarnessBoardCopy.reconcile
                    )
            }
            .padding(M22BoardMetrics.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                    .fill(ColorToken.f2.color)
            )
            .measured(
                "finding-band", role: "finding-band", kind: .hstack,
                tokens: ["background": .f2]
            )
        }

        /// A reading that failed to refresh keeps its rows and says so above them. The rows are
        /// still true of the last read; what is not true is that they are current.
        private func staleBanner(_ error: ControlAPIError) -> some View {
            Text(error.userFacingDescription)
                .typeRole(.callout)
                .foregroundStyle(ColorToken.failInk.color)
                .fixedSize(horizontal: false, vertical: true)
                .measured(
                    "stale-banner", role: "stale", kind: .text,
                    tokens: ["foreground": .failInk], type: .callout,
                    text: error.userFacingDescription
                )
        }

        private var list: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                HarnessSectionHeader(title: HarnessBoardCopy.sectionDetected, id: "section-detected")
                ForEach(board.readable) { row in
                    HarnessCard(row: row, board: board)
                }
            }
            .measured("harness-list", role: "harness-list", kind: .vstack)
        }

        /// When the files were read, and what was not read at all.
        private var footer: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                if let response = board.state.response {
                    Text(HarnessBoardCopy.readAt(response.readAt))
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .measured(
                            "read-at", role: "freshness", kind: .text,
                            tokens: ["foreground": .t3], type: .caption,
                            text: HarnessBoardCopy.readAt(response.readAt)
                        )
                }
                Text(HarnessBoardCopy.scopeNote)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t3.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "scope-note", role: "scope", kind: .text,
                        tokens: ["foreground": .t3], type: .caption, text: HarnessBoardCopy.scopeNote
                    )
            }
            .measured("harnesses-footer", role: "board-footer", kind: .vstack)
        }
    }
#endif
