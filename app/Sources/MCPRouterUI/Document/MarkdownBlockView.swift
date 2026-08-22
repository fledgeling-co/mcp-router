#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI

    /// One parsed block, drawn.
    ///
    /// A view per kind, dispatched here, which is the shape the brief settles on: the inline runs
    /// stay on the system parser and the custom work sits only where the platform draws nothing.
    /// The `switch` is exhaustive over `MarkdownBlock` on purpose — a tenth kind stops this
    /// compiling at the moment somebody should be deciding what it looks like, rather than at the
    /// moment a reader meets a blank space.
    struct MarkdownBlockView: View {
        let block: MarkdownBlock
        /// This block's position in its document. Part of the measured node's name, because
        /// `measured(_:)` requires an id unique among siblings and a document draws four headings —
        /// four nodes under one name is three nodes the recorder silently overwrites.
        let index: Int
        /// Image bytes the document arrived with, keyed by the reference as the document wrote it.
        /// Bytes rather than paths, so no view here can be talked into a fetch (A36).
        let images: [String: Data]
        let refusals: [String: PackageImageResolver.Refusal]

        var body: some View {
            switch block {
            case let .heading(level, content):
                MarkdownInlineText(inline: content, role: headingRole(level), tint: .t1)
                    .padding(.top, DocumentMetrics.headingLead)
                    .measured(
                        nodeID,
                        role: "heading",
                        kind: .text,
                        type: headingRole(level),
                        text: content.text
                    )

            case let .paragraph(content):
                MarkdownInlineText(inline: content, role: .body, tint: .t1)
                    .measured(nodeID, role: "sentence", kind: .text, type: .body, text: content.text)

            case let .codeFence(_, code):
                fence(code)

            case let .blockquote(inner):
                quote(inner)

            case let .list(list):
                listView(list)

            case let .table(table):
                MarkdownTableView(table: table)
                    // `.grid`, not `.vstack`. A `Grid` has two axes and the structure layer
                    // corroborates a declared axis against where the children actually landed —
                    // declaring this vertical while the instrumented children are its header cells
                    // reported an axis the geometry contradicts, which is the self-description the
                    // layer exists to catch. `MeasureKind.grid` carries no axis for that reason.
                    .measured(nodeID, role: "table", kind: .grid, tokens: ["background": .panel])

            case .rule:
                Rectangle()
                    .fill(ColorToken.line.color)
                    .frame(height: DocumentMetrics.hairline)
                    .measured(nodeID, role: "rule", kind: .leaf, tokens: ["background": .line])

            case let .image(image):
                figure(image)

            case let .shields(shields):
                shieldRow(shields)

            case let .plainText(text):
                // The visible fallback. Monospace, because what is on screen is the document's own
                // source rather than prose — the instrument voice is exactly right for it.
                Text(text)
                    .typeRole(.callout, monospaced: true)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(nodeID, role: "plain-text", kind: .text, type: .callout, text: text)
            }
        }

        /// A stable node name for the measurement harness, unique among a document's blocks.
        private var nodeID: String { "block-\(index)-\(block.kind.rawValue)" }

        /// The words a run of blocks contains, flattened. What a container node reports as its own
        /// text, so a pairing against a mock element that carries its subtree's words can be
        /// compared rather than classified as uncomparable.
        static func spokenText(of blocks: [MarkdownBlock]) -> String {
            blocks.map { block in
                switch block {
                case let .heading(_, content): content.text
                case let .paragraph(content): content.text
                case let .codeFence(_, code): code
                case let .blockquote(inner): spokenText(of: inner)
                case let .list(list): list.items.map(\.text).joined(separator: " ")
                case let .table(table): table.header.map(\.text).joined(separator: " ")
                case .rule: ""
                case let .image(image): image.alternateText
                case let .shields(shields): shields.map { "\($0.key) \($0.value)" }.joined(separator: " ")
                case let .plainText(text): text
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        }

        private func headingRole(_ level: Int) -> TypeToken {
            switch level {
            case 1: .title1
            case 2: .title2
            default: .title3
            }
        }

        // MARK: - Fence

        /// A fenced block on the sunken ground the mock gives it. Scrolls sideways rather than
        /// wrapping: a wrapped command line is a different command line, which is the same argument
        /// `DiscoverDetailSheet` makes for drawing an argv as separate tokens.
        private func fence(_ code: String) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .typeRole(.subheadline, monospaced: true)
                    .foregroundStyle(ColorToken.t1.color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DocumentMetrics.codePadding)
            .background {
                RoundedRectangle(cornerRadius: DocumentMetrics.codeRadius, style: .continuous)
                    .fill(ColorToken.sunken.color)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DocumentMetrics.codeRadius, style: .continuous)
                    .strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
            }
            .measured(
                nodeID, role: "codeblock", kind: .scroll,
                tokens: ["background": .sunken, "border": .line], type: .subheadline, text: code
            )
        }

        // MARK: - Quote

        private func quote(_ inner: [MarkdownBlock]) -> some View {
            HStack(alignment: .top, spacing: DocumentMetrics.quoteInset) {
                Rectangle()
                    .fill(ColorToken.lineStrong.color)
                    .frame(width: DocumentMetrics.quoteRule)
                VStack(alignment: .leading, spacing: DocumentMetrics.blockGap) {
                    ForEach(Array(inner.enumerated()), id: \.offset) { offset, block in
                        MarkdownBlockView(
                            block: block, index: index * 100 + offset, images: images, refusals: refusals
                        )
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            // The quote's own words, so the copy layer has something to compare. Without this the
            // node reported nothing readable and the pairing read `unclassified` — the gate
            // correctly refusing to call agreement between two absences a measurement.
            .measured(
                nodeID, role: "callout", kind: .hstack,
                tokens: ["border": .lineStrong], text: Self.spokenText(of: inner)
            )
        }

        // MARK: - Lists

        /// A hanging indent rather than a bullet glyph inside the text, so a wrapped second line
        /// aligns with the first word rather than with the marker.
        private func listView(_ list: MarkdownList) -> some View {
            VStack(alignment: .leading, spacing: DocumentMetrics.tightGap) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .top, spacing: 0) {
                        Text(list.isOrdered ? "\(list.start + offset)." : "•")
                            .typeRole(.body)
                            .foregroundStyle(ColorToken.t3.color)
                            .frame(width: DocumentMetrics.markerColumn, alignment: .leading)
                        MarkdownInlineText(inline: item, role: .body, tint: .t1)
                    }
                    // One node per item, because the mock's census counts `<li>` as a list row —
                    // the brief's own word — and a list measured only as a whole would report
                    // every one of its rows absent from the build.
                    .measured(
                        "item-\(offset)", role: "list-item", kind: .hstack,
                        type: .body, text: item.text
                    )
                }
            }
            .padding(.leading, DocumentMetrics.listInset)
            .measured(nodeID, role: "list", kind: .vstack, alignment: "leading")
        }

        // MARK: - Figures

        /// An image, in the bordered card the mock calls a figure, with its alternate text as the
        /// caption above it.
        ///
        /// **A refused reference is drawn, not skipped.** The placeholder says which of the four
        /// things happened — remote, absolute, escaping the package, or simply absent — because a
        /// document pointing somewhere the app will not go is a fact worth knowing about a package
        /// you are deciding whether to install.
        private func figure(_ image: MarkdownImage) -> some View {
            VStack(alignment: .leading, spacing: DocumentMetrics.tightGap) {
                if !image.alternateText.isEmpty {
                    Text(image.alternateText)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t3.color)
                }
                if let data = images[image.reference], let bitmap = NSImage(data: data) {
                    Image(nsImage: bitmap)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel(image.alternateText)
                } else {
                    Text(refusals[image.reference]?.sentence ?? PackageImageResolver.Refusal
                        .notInPackage.sentence)
                        .typeRole(.subheadline)
                        .foregroundStyle(ColorToken.t2.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DocumentMetrics.figurePadding)
            .background {
                RoundedRectangle(cornerRadius: DocumentMetrics.figureRadius, style: .continuous)
                    .fill(ColorToken.panel.color)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DocumentMetrics.figureRadius, style: .continuous)
                    .strokeBorder(ColorToken.line.color, lineWidth: DocumentMetrics.hairline)
            }
            .measured(
                nodeID, role: "card", kind: .vstack,
                alignment: "leading", tokens: ["background": .panel, "border": .line],
                text: image.alternateText
            )
        }

        // MARK: - Shields

        private func shieldRow(_ shields: [Shield]) -> some View {
            // Wrapping rather than one line: four badges is the common case and eleven is not rare,
            // and a row that overflows would push the document's own width past the sheet.
            WrappingRow(spacing: DocumentMetrics.tightGap) {
                ForEach(Array(shields.enumerated()), id: \.offset) { offset, shield in
                    ShieldView(shield: shield, index: offset)
                }
            }
            .measured(nodeID, role: "banner", kind: .hstack)
        }
    }

    /// A row that wraps onto further lines when it runs out of width.
    ///
    /// `Layout` rather than a `LazyVGrid`, because a grid puts every badge in a column of the widest
    /// badge's width and a shield's width is its text. Nothing in SwiftUI ships a flow row.
    struct WrappingRow: Layout {
        var spacing: Double

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            let width = proposal.replacingUnspecifiedDimensions().width
            let rows = arrange(subviews: subviews, in: width)
            let height = rows.reduce(0.0) { $0 + $1.height } + spacing * Double(max(rows.count - 1, 0))
            return CGSize(width: width, height: height)
        }

        func placeSubviews(
            in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()
        ) {
            var y = bounds.minY
            for row in arrange(subviews: subviews, in: bounds.width) {
                var x = bounds.minX
                for index in row.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size)
                    )
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row {
            var indices: [Int] = []
            var height: Double = 0
        }

        private func arrange(subviews: Subviews, in width: Double) -> [Row] {
            var rows: [Row] = []
            var current = Row()
            var x = 0.0
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                if !current.indices.isEmpty, x + size.width > width {
                    rows.append(current)
                    current = Row()
                    x = 0
                }
                current.indices.append(index)
                current.height = max(current.height, size.height)
                x += size.width + spacing
            }
            if !current.indices.isEmpty { rows.append(current) }
            return rows
        }
    }
#endif
