#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// A table with a header row — one of the two kinds `AttributedString(markdown:)` renders not at
    /// all, and the reason a block parser exists here.
    ///
    /// A `Grid` rather than a stack of rows, so the columns share one measurement: a per-row
    /// `HStack` gives every row its own widths and the table shears. The shape is fixed before it
    /// arrives — `MarkdownParser` pads and truncates every row to the header's width — so nothing
    /// here indexes past the end of a row a marketplace document made ragged.
    struct MarkdownTableView: View {
        let table: MarkdownTable

        var body: some View {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { index, cell in
                        self.cell(cell, alignment: alignment(index), role: .callout, tint: .t1)
                            .background(ColorToken.panel.color)
                            .measured(
                                "column-\(index)", role: "column-header", kind: .text,
                                tokens: ["background": .panel], type: .callout, text: cell.text
                            )
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                            self.cell(cell, alignment: alignment(index), role: .callout, tint: .t1)
                        }
                    }
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
            }
        }

        private func alignment(_ index: Int) -> MarkdownTable.Alignment {
            index < table.alignments.count ? table.alignments[index] : .leading
        }

        private func cell(
            _ inline: MarkdownInline,
            alignment: MarkdownTable.Alignment,
            role: TypeToken,
            tint: ColorToken
        ) -> some View {
            MarkdownInlineText(inline: inline, role: role, tint: tint)
                .frame(maxWidth: .infinity, alignment: frameAlignment(alignment))
                .padding(.vertical, DocumentMetrics.cellPaddingVertical)
                .padding(.horizontal, DocumentMetrics.cellPaddingHorizontal)
                .overlay {
                    Rectangle()
                        .strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
                }
        }

        private func frameAlignment(_ alignment: MarkdownTable.Alignment) -> Alignment {
            switch alignment {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
            }
        }
    }
#endif
