#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A batch is an explicit review of plugin changes, never blanket trust in a newer version.
    struct SkillUpdateReviewSheet: View {
        @Bindable var board: SkillsBoardModel
        @State private var selected: Set<String> = []

        var body: some View {
            VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                Text("Review skill updates")
                    .typeRole(.title2)
                    .foregroundStyle(ColorToken.t1.color)
                Text(
                    """
                    A plugin may contain several skills. Select each plugin you want to update \
                    after reviewing its changes. Nothing is downloaded by this action.
                    """
                )
                .typeRole(.body)
                .foregroundStyle(ColorToken.t2.color)
                .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: SkillsBoardMetrics.gap) {
                        ForEach(board.offers) { offer in
                            VStack(alignment: .leading, spacing: SkillsBoardMetrics.tightGap) {
                                if offer.kind == .plugins {
                                    Toggle(isOn: Binding(
                                        get: { selected.contains(offer.name) },
                                        set: { value in
                                            if value {
                                                selected.insert(offer.name)
                                            } else {
                                                selected.remove(offer.name)
                                            }
                                        }
                                    )) {
                                        Text(offer.name).typeRole(.body)
                                    }
                                    .disabled(board.writing)
                                } else {
                                    Text(offer.name).typeRole(.body)
                                    Text(
                                        "This entry has no cached plugin promotion. Update it at its source."
                                    )
                                    .typeRole(.caption)
                                    .foregroundStyle(ColorToken.t2.color)
                                }
                                Text(offer.reason).typeRole(.caption)
                                ForEach(board.changes(for: offer), id: \.self) { change in
                                    Text(change)
                                        .typeRole(.caption)
                                        .foregroundStyle(ColorToken.attention.color)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let document = board.changelogDocument(named: offer.name),
                                   let blocks = document.blocks(for: .changelog)
                                {
                                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                                        MarkdownBlockView(
                                            block: block,
                                            index: index,
                                            images: [:],
                                            refusals: [:]
                                        )
                                    }
                                } else if let note = offer.changelog?.note {
                                    Text(note).typeRole(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                        if !board.updatesChecked {
                            ProgressView("Checking available updates…")
                        } else if let error = board.updatesError {
                            Banner(icon: .warn, tint: .attention) {
                                Text("\(error.headline). \(error.advice)")
                            }
                        } else if board.offers.isEmpty {
                            Text("No update offers remain in the latest reading.")
                                .typeRole(.body)
                        }
                        ForEach(Array(board.batchResults.enumerated()), id: \.offset) { _, result in
                            Text(result).typeRole(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: DocumentMetrics.bodyMaxHeight)
                HStack {
                    if !board.batchPromotions.isEmpty {
                        Button("Undo updates") { Task { await board.undoBatchPromotions() } }
                            .buttonStyle(StandardButtonStyle())
                            .disabled(board.writing)
                    }
                    Spacer()
                    Button("Close") { board.sheet = nil }
                        .buttonStyle(StandardButtonStyle())
                    Button(board.writing ? "Updating…" : "Update selected plugins") {
                        let approved = selected
                        selected = []
                        Task { await board.promoteSelectedOffers(approved) }
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .disabled(board.writing || !board.promotesFromCache || selected.isEmpty)
                }
            }
            .padding(SkillsBoardMetrics.panePadding)
            .frame(width: SkillsBoardMetrics.sheetWidth)
            .background(ColorToken.panel.color)
        }
    }
#endif
