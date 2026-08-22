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
                        self.cell(
                            cell, alignment: alignment(index), role: .callout, tint: .t1,
                            node: "column-\(index)"
                        )
                        .background(ColorToken.panel.color)
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

        /// One cell. `node` instruments it, and **the instrument sits on the text rather than on
        /// the padded cell**: the type-metrics layer compares a role's measured line box against
        /// the ladder, and a node whose frame includes eight points of cell padding reported
        /// Callout at 23pt against Body's 16pt — an inverted ladder, which that layer reads as the
        /// signature of a substituted role. The padding is the cell's, not the type's.
        @ViewBuilder
        private func cell(
            _ inline: MarkdownInline,
            alignment: MarkdownTable.Alignment,
            role: TypeToken,
            tint: ColorToken,
            node: String? = nil
        ) -> some View {
            // Only a header cell is instrumented. A body cell takes no node at all rather than an
            // empty one: `measured("")` is still a node, and a table of forty cells would report
            // forty siblings under one name, of which the recorder keeps the last.
            Group {
                if let node {
                    MarkdownInlineText(inline: inline, role: role, tint: tint)
                        .measured(node, role: "column-header", kind: .text, type: role, text: inline.text)
                } else {
                    MarkdownInlineText(inline: inline, role: role, tint: tint)
                }
            }
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
