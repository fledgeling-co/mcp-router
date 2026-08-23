#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Servers table's column headers.
    ///
    /// An extension in its own file rather than more lines in `ServersBoard.swift`, because that
    /// type had grown past the 250-line body SwiftLint allows once M23's `.measured(…)` call sites
    /// went in. The headers are the seam with nothing behind it: they read no board state, so
    /// moving them needs no access widened, which is the property that picked them over the row
    /// list sitting next to them.
    extension ServersBoard {
        // MARK: - The table

        /// Internal rather than private only because the body that uses it is in the file next
        /// door. Nothing outside `ServersBoard` calls it.
        var columnHeaders: some View {
            HStack(spacing: ServersBoardMetrics.gap) {
                // The plug's own gutter carries no label; a state mark is not a column of data.
                // One value with the row's, so the header cannot fall out of alignment with it.
                Color.clear.frame(width: ServersBoardMetrics.indicatorColumn, height: 0)
                // §3.2: sentence case, secondary colour. Tracked uppercase is the loudest web tell.
                columnLabel("server", width: ServersBoardMetrics.nameColumn, alignment: .leading)
                columnLabel("transport", width: ServersBoardMetrics.transportColumn)
                columnLabel("tools", width: ServersBoardMetrics.toolsColumn)
                columnLabel("calls", width: ServersBoardMetrics.callsColumn)
                columnLabel("last used", width: ServersBoardMetrics.lastUsedColumn)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, ServersBoardMetrics.rowPadding)
            .padding(.bottom, ServersBoardMetrics.tightGap)
            .accessibilityHidden(true)
            .measured("column-headers", role: "column-headers", kind: .hstack)
        }

        private func columnLabel(
            _ text: String,
            width: Double,
            alignment: Alignment = .trailing
        ) -> some View {
            Text(text)
                .typeRole(.caption)
                .foregroundStyle(ColorToken.t3.color)
                .frame(width: width, alignment: alignment)
                .measured(
                    "column-\(text)", role: "column-header", kind: .text,
                    tokens: ["foreground": .t3], type: .caption, text: text
                )
        }
    }
#endif
