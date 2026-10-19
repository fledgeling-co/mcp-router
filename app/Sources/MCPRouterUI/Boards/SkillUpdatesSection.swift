#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The update check's offers, on the Skills board: each installed item the router holds a newer version
    /// of, with
    /// that version's changelog where the router could read one. The check reads the router's own store, so
    /// an item
    /// missing from this list is not thereby current; `SkillPresentation.updatesNone` says what the check
    /// covered.
    struct SkillUpdatesSection: View {
        @Bindable var board: SkillsBoardModel

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                Text(SkillPresentation.updatesHeading)
                    .typeRole(.subheadline)
                    .foregroundStyle(ColorToken.t1.color)

                if let error = board.updatesError {
                    // The router refused the check. Its own two strings, as the marketplaces read says them
                    // (§6).
                    Banner(icon: error == .routerNotRunning ? .bolt : .warn, tint: .attention) {
                        Text("\(error.headline). \(error.advice)")
                    }
                } else if board.updates.allSatisfy({ !$0.hasUpdate }) {
                    Text(SkillPresentation.updatesNone)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(board.updates.filter(\.hasUpdate)) { entry in
                        UpdateOfferRow(entry: entry)
                    }
                }
            }
            .padding(SkillsBoardMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    struct UpdateOfferRow: View {
        let entry: ExtensionUpdateEntry

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.hairline) {
                Text(entry.name)
                    .typeRole(.body)
                    .foregroundStyle(ColorToken.t1.color)
                    .lineLimit(1)
                Text(entry.reason)
                    .typeRole(.caption)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let changelog = entry.changelog {
                    // Eight lines on the board, the full text in the held-version sheet. The line limit is
                    // display
                    // only; the router sent the whole text the cap allows.
                    Text(changelog.text ?? changelog.note)
                        .typeRole(.caption, monospaced: changelog.text != nil)
                        .foregroundStyle(ColorToken.t3.color)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The board's offer to take back the last promotion. It outlives the held-version sheet, so the undo is
    /// still there
    /// after the sheet closes, the way Triage's undo outlives its act (§9).
    struct PromotionUndoBar: View {
        @Bindable var board: SkillsBoardModel
        let promoted: SkillsBoardModel.PromotedEntry

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: SkillsBoardMetrics.gap) {
                Text(SkillPresentation.promotionCanBeUndone(plugin: promoted.plugin))
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t1.color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Undo") { Task { await board.undoLastPromotion() } }
                    .buttonStyle(StandardButtonStyle())
                    .disabled(board.writing)
            }
            .padding(SkillsBoardMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
