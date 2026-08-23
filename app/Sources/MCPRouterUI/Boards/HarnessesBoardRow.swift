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
                    // **Dim, not absent** (§3.4). The panel that draws the diff is M18's, and this
                    // board is one of the two surfaces it opens from. It was an enabled button
                    // setting a state nothing presented, which is the worse of the two failures:
                    // it looked like it worked.
                    Button(HarnessBoardCopy.reconcile) {}
                        .buttonStyle(StandardButtonStyle())
                        .disabled(true)
                        .help(HarnessBoardCopy.reconcileUnavailable)
                        .accessibilityHint(HarnessBoardCopy.reconcileUnavailable)
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

    /// A section title on this board.
    ///
    /// Sentence case, system font, secondary colour — §3.2, where the fix for tracked
    /// uppercase is to remove it rather than tune its tracking. Shared by the two sections
    /// rather than written twice, so a change of tier moves both.
    struct HarnessSectionHeader: View {
        let title: String
        let id: String

        var body: some View {
            Text(title)
                .typeRole(.subheadline)
                .foregroundStyle(ColorToken.t3.color)
                .measured(
                    id, role: "section-header", kind: .text,
                    tokens: ["foreground": .t3], type: .subheadline, text: title
                )
        }
    }

    /// The harnesses whose configuration would not parse, drawn apart from the readings.
    ///
    /// **Its own section and its own card, with no counts on either.** An unreadable row
    /// arrives as the EMPTY report — every figure on it is 0 and its state says not-wired,
    /// which is byte-identical to a clean unwired harness — so drawing it among the readings
    /// would put a row on the board that is a lie about the machine.
    ///
    /// A view rather than a method on the board, because the board's type body reached this
    /// repository's 250-line cap and this is the real seam: a reading and a failure to read.
    struct HarnessUnreadableSection: View {
        let rows: [DetectedHarness]
        let board: HarnessesBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                HarnessSectionHeader(title: "Could not be read", id: "section-unreadable")
                ForEach(rows) { row in
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
    }

    /// The loading frame: cards at the geometry the real ones will land at.
    ///
    /// `SkeletonRows` stands in at `MetricToken.serversRow`, which is the Servers board's 56pt row
    /// and not this board's card — a placeholder at the wrong height makes the list jump when the
    /// read completes, which is the one thing `DESIGN.md` §5 says a skeleton exists to avoid. The
    /// mock draws two; `M22BoardMetrics.harnessSkeletonHeight` is what a card actually rests at.
    struct HarnessSkeleton: View {
        var count = 2

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                ForEach(0 ..< count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: M22BoardMetrics.cardRadius)
                        .fill(ColorToken.f3.color)
                        .frame(height: M22BoardMetrics.harnessSkeletonHeight)
                        .measured(
                            "skeleton-card-\(index)", role: "skeleton-card",
                            tokens: ["background": .f3]
                        )
                }
            }
            .measured("harness-skeleton", role: "skeleton", kind: .vstack)
            .accessibilityHidden(true)
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
