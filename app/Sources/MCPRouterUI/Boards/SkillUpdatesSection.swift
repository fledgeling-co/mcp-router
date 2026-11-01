#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The update check's offers, on the Skills board: each installed plugin Claude's register holds a newer
    /// version of, and each stored offer the router holds, with the changelog of that version where one could
    /// be read. An offer missing from this list is not thereby current; `SkillPresentation.updatesNone` says
    /// what the check covered.
    struct SkillUpdatesSection: View {
        @Bindable var board: SkillsBoardModel

        var body: some View {
            let offers = board.offers
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                HStack {
                    Text(SkillPresentation.updatesHeading)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t1.color)
                    Spacer()
                    Button("Review updates…") { board.sheet = .updates }
                        .buttonStyle(StandardButtonStyle())
                        .disabled(board.writing || offers.isEmpty)
                }

                if let error = board.updatesError {
                    // The router refused the store's check. Its own two strings, as the marketplaces read
                    // says them (§6). The register's offers, when there are any, still stand beneath it.
                    Banner(icon: error == .routerNotRunning ? .bolt : .warn, tint: .attention) {
                        Text("\(error.headline). \(error.advice)")
                    }
                }

                if !offers.isEmpty {
                    ForEach(offers) { entry in
                        UpdateOfferRow(entry: entry, board: board)
                    }
                } else if board.updatesError == nil {
                    Text(SkillPresentation.updatesNone)
                        .typeRole(.caption)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SkillsBoardMetrics.rowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    struct UpdateOfferRow: View {
        let entry: ExtensionUpdateEntry
        @Bindable var board: SkillsBoardModel

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
                    if changelog.text != nil {
                        Button("Read changelog…") { board.sheet = .changelog(name: entry.name) }
                            .buttonStyle(StandardButtonStyle(scale: .small))
                    } else {
                        Text(changelog.note)
                            .typeRole(.caption)
                            .foregroundStyle(ColorToken.t3.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
