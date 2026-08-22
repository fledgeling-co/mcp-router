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
            .onKeyPress(.escape) {
                board.escape()
                return .handled
            }
            .measureSurface("harnesses")
        }

        private var header: some View {
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
                SkeletonRows(count: 3)
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
                if !board.unreadable.isEmpty { unreadableSection }
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
                sectionHeader(HarnessBoardCopy.sectionDetected, id: "section-detected")
                ForEach(board.readable) { row in
                    HarnessCard(row: row, board: board)
                }
            }
            .measured("harness-list", role: "harness-list", kind: .vstack)
        }

        private var unreadableSection: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                sectionHeader("Could not be read", id: "section-unreadable")
                ForEach(board.unreadable) { row in
                    unreadableCard(row)
                }
                Text(HarnessBoardCopy.unreadableNote)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "unreadable-note", role: "callout", kind: .text,
                        tokens: ["foreground": .t2], type: .callout,
                        text: HarnessBoardCopy.unreadableNote
                    )
            }
            .measured("unreadable-section", role: "unreadable-list", kind: .vstack)
        }

        /// A harness whose configuration would not parse.
        ///
        /// Drawn as its own card with **no counts on it at all**, because the row arrives as the
        /// empty report: every figure on it reads 0 and its state reads not-wired, which is
        /// identical to a clean unwired harness. Showing those figures would be showing numbers
        /// nobody counted.
        private func unreadableCard(_ row: DetectedHarness) -> some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                Text(row.displayName)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "unreadable-name-\(row.harness)", role: "harness-name", kind: .text,
                        tokens: ["foreground": .t1], type: .title3, text: row.displayName
                    )
                Text(row.unreadable ?? "")
                    .typeRole(.caption)
                    .monospaced()
                    .foregroundStyle(ColorToken.failInk.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "unreadable-reason-\(row.harness)", role: "read-failure", kind: .text,
                        tokens: ["foreground": .failInk], type: .caption, text: row.unreadable ?? ""
                    )
                Button(HarnessBoardCopy.openConfig) { board.reveal(row.path) }
                    .buttonStyle(StandardButtonStyle())
                    .measured(
                        "unreadable-open-\(row.harness)", role: "row-action", type: .body,
                        text: HarnessBoardCopy.openConfig
                    )
            }
            .padding(M22BoardMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                    .fill(ColorToken.raised.color)
                    .overlay(
                        RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                            .strokeBorder(ColorToken.line.color, lineWidth: M22BoardMetrics.hairline)
                    )
            )
            .measured(
                "unreadable-card-\(row.harness)", role: "harness-card", kind: .vstack,
                tokens: ["background": .raised, "border": .line]
            )
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

        private func sectionHeader(_ title: String, id: String) -> some View {
            // Sentence case, system font, secondary colour. Tracked uppercase is the loudest web
            // tell and §3.2 says to remove it rather than tune it.
            Text(title)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .measured(
                    id, role: "section-header", kind: .text,
                    tokens: ["foreground": .t3], type: .subheadline, text: title
                )
        }
    }
#endif
