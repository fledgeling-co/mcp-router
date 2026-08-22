#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The status pill on a harness card.
    ///
    /// **The colour never travels alone.** `DESIGN.md` §2 reserves the four indicator hues to their
    /// meanings and §6 requires a word beside every state that has a colour; the label is that
    /// word, which is also why `pairedWithAWord` exempts the hue from the 4.5:1 text floor. The dot
    /// is `nonText` and the label is a text tier, so nothing here reads a hue as a label colour.
    struct HarnessStatusPill: View {
        let status: HarnessStatus

        /// The dot's hue, and the reading it means.
        ///
        /// Exhaustive with no `default`, so a fifth reading stops this compiling — which is the
        /// moment somebody should be deciding what it looks like rather than the moment a user
        /// meets an unpainted one.
        private var tint: ColorToken {
            switch status {
            case .routedOverHTTP: .live
            case .routedViaShim: .attention
            case .routedWithDirectServers: .attention
            case let .notRouted(_, overlapping): overlapping > 0 ? .attention : .t3
            }
        }

        var body: some View {
            HStack(spacing: M22BoardMetrics.tightGap) {
                Circle()
                    .fill(tint.color)
                    .frame(width: M22BoardMetrics.dot, height: M22BoardMetrics.dot)
                    .measured(
                        "status-dot", role: "status-indicator",
                        tokens: ["background": tint]
                    )
                Text(status.label)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "status-label", role: "status-word", kind: .text,
                        tokens: ["foreground": .t1], type: .subheadline, text: status.label
                    )
            }
            .padding(.horizontal, M22BoardMetrics.pillPadding)
            .frame(height: M22BoardMetrics.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: M22BoardMetrics.pillRadius)
                    .fill(ColorToken.f2.color)
            )
            .measured("status-pill", role: "status-pill", kind: .hstack, tokens: ["background": .f2])
        }
    }

    /// One detected harness.
    ///
    /// Every sentence on it comes from ``HarnessStatus``, so the four readings cannot be described
    /// four ways by four call sites — which is what `DESIGN.md` §6's "one name per state, taken
    /// from one source" is about, and what a per-row string would quietly undo.
    struct HarnessCard: View {
        let row: DetectedHarness
        let board: HarnessesBoardModel

        private var status: HarnessStatus { HarnessStatus(row) }

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                header
                Text(status.sentence)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "harness-sentence", role: "status-sentence", kind: .text,
                        tokens: ["foreground": .t2], type: .body, text: status.sentence
                    )
                if !row.duplicates.isEmpty { duplicates }
                actions
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
                "harness-card-\(row.harness)", role: "harness-card", kind: .vstack,
                tokens: ["background": .raised, "border": .line]
            )
        }

        private var header: some View {
            HStack(alignment: .top, spacing: M22BoardMetrics.gap) {
                VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                    Text(row.displayName)
                        .typeRole(.title3)
                        .foregroundStyle(ColorToken.t1.color)
                        .measured(
                            "harness-name", role: "harness-name", kind: .text,
                            tokens: ["foreground": .t1], type: .title3, text: row.displayName
                        )
                    // Monospace, because it is a path a user could paste into a terminal — which
                    // is exactly what §2 reserves the instrument voice for.
                    Text(row.path)
                        .typeRole(.caption)
                        .monospaced()
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .measured(
                            "harness-path", role: "config-path", kind: .text,
                            tokens: ["foreground": .t3], type: .caption, text: row.path
                        )
                }
                Spacer(minLength: 0)
                HarnessStatusPill(status: status)
            }
            .measured("harness-header", role: "card-header", kind: .hstack)
        }

        /// The entries this router already serves, named individually.
        ///
        /// Both names are printed when they differ: the user has to find the harness's spelling in
        /// their own file, and the router's is what it is served under here.
        private var duplicates: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.labelGap) {
                ForEach(row.duplicates) { duplicate in
                    Text(HarnessRowCopy.duplicate(duplicate))
                        .typeRole(.caption)
                        .monospaced()
                        .foregroundStyle(ColorToken.t2.color)
                        .measured(
                            "duplicate-\(duplicate.harnessName)", role: "duplicate-entry",
                            kind: .text, tokens: ["foreground": .t2], type: .caption,
                            text: HarnessRowCopy.duplicate(duplicate)
                        )
                }
            }
            .measured("harness-duplicates", role: "duplicate-list", kind: .vstack)
        }

        private var actions: some View {
            HStack(spacing: M22BoardMetrics.tightGap) {
                Button(HarnessBoardCopy.openConfig) { board.reveal(row.path) }
                    .buttonStyle(StandardButtonStyle())
                    .measured(
                        "open-config", role: "row-action", type: .body,
                        text: HarnessBoardCopy.openConfig
                    )
                if row.duplicateCount > 0 {
                    Button(HarnessBoardCopy.reconcile) {
                        board.sheet = .reconcile(harness: row.harness)
                    }
                    .buttonStyle(StandardButtonStyle())
                    .help(HarnessBoardCopy.reconcileHelp)
                    .measured(
                        "reconcile", role: "row-action", type: .body,
                        text: HarnessBoardCopy.reconcile
                    )
                }
                // An explanation rather than a fix, because there is no fix on this side.
                if case .routedViaShim = status {
                    Button(HarnessBoardCopy.explainShim) {
                        board.sheet = .explainShim(harness: row.harness)
                    }
                    .buttonStyle(StandardButtonStyle())
                    .measured(
                        "explain-shim", role: "row-action", type: .body,
                        text: HarnessBoardCopy.explainShim
                    )
                }
                Spacer(minLength: 0)
            }
            .measured("harness-actions", role: "card-actions", kind: .hstack)
        }
    }

    /// One line of row-level copy that needed a home outside a view body.
    enum HarnessRowCopy {
        static func duplicate(_ duplicate: HarnessDuplicate) -> String {
            duplicate.harnessName == duplicate.routerName
                ? duplicate.harnessName
                : "\(duplicate.harnessName) — the router calls it \(duplicate.routerName)"
        }
    }
#endif
