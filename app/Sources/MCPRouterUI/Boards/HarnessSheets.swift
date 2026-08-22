#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The one sheet this board presents itself.
    ///
    /// **An explanation, not a fix**, and the distinction is the brief's: for a harness whose
    /// transport forces a bridge there is no fix on this side, because the transport belongs to the
    /// harness and this app does not write harness files. Offering a remedy there would offer an
    /// action that cannot work.
    ///
    /// The reconcile case is M18's panel and is deliberately not presented here — the controls that
    /// would open it are drawn dim with that reason instead, which is `DESIGN.md` §3.4's rule
    /// rather than a placeholder.
    struct HarnessSheetHost: View {
        let board: HarnessesBoardModel
        let sheet: HarnessesBoardModel.Sheet

        var body: some View {
            switch sheet {
            case let .explainShim(harness):
                ShimExplanationSheet(row: board.rows.first { $0.harness == harness }) {
                    board.sheet = nil
                }
            case .reconcile:
                // Unreachable while the reconcile controls are disabled. It is a real arm rather
                // than a `fatalError` because the state exists on the model for M18 to present
                // from, and an arm that crashes is a worse answer than one that closes.
                EmptyView()
                    .onAppear { board.sheet = nil }
            }
        }
    }

    struct ShimExplanationSheet: View {
        let row: DetectedHarness?
        let dismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: M22BoardMetrics.gap) {
                Text(HarnessBoardCopy.shimSheetTitle)
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                if let row {
                    Text(HarnessBoardCopy.shimExplanation(
                        bridge: row.bridge, capability: row.capability
                    ))
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    // The capability sentence carries its own provenance — measured on a named
                    // binary on a named day, taken on documentation, or not established at all —
                    // and it is shown rather than summarised, because which of the three it is
                    // decides whether the remedy above is an instruction or a question.
                    Text(row.httpCapability)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t3.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button(HarnessBoardCopy.shimSheetDismiss) { dismiss() }
                        .buttonStyle(ProminentButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(M22BoardMetrics.panePadding)
            .frame(width: MetricToken.sidebar.leadingScalar * 2)
        }
    }
#endif
