#if os(macOS)
    import MCPRouterKit

    /// The document viewer's geometry, derived rather than picked.
    ///
    /// Same construction as `SettingsMetrics` and `DiscoverBoardMetrics`: `DESIGN.md` §2 documents
    /// the grid unit, the dense-table unit, the selection inset and radius, the control ladder and
    /// the card radius, and it documents nothing about a paragraph's spacing or a table cell's
    /// padding — because those are consequences of content. `SWIFT_PRACTICES.md` §5 forbids
    /// scattering them as literals, so they are named once here and a change to a token moves the
    /// whole document.
    ///
    /// **Two values disagree with the mock and are declared rather than derived toward.** The mock's
    /// wide sheet is `min(820px, 94%)` and its body caps at `56vh`; neither is a token, and
    /// arithmetic landing on 820 would be a literal wearing a token's clothes. Both are recorded in
    /// `planning/fidelity/readme.layers.json` and reported by the geometry layer on every run,
    /// which is what the conversion contract is for.
    enum DocumentMetrics {
        private static var unit: Double { MetricToken.gridUnit.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }
        private static var row: Double { MetricToken.tableRows.leadingScalar }

        // MARK: - The sheet

        /// Three sidebars wide. The mock's 820 has no token behind it; this is the widest value
        /// `DESIGN.md` §2 can actually be asked for, and the difference is declared.
        static var sheetWidth: Double { MetricToken.sidebar.leadingScalar * 3 }
        /// Two sidebars tall, capping the body so a long document scrolls rather than growing the
        /// sheet past its window — the brief's own requirement, at a value the document can supply.
        static var bodyMaxHeight: Double { MetricToken.sidebar.leadingScalar * 2 }
        static var titlebarHeight: Double { MetricToken.titlebar.leadingScalar }
        static var tabHeight: Double { MetricToken.titlebar.leadingScalar }
        /// The accent underline a selected tab carries, at the focus ring's own weight.
        static var tabUnderline: Double { MetricToken.focusRing.leadingScalar }

        // MARK: - Rhythm

        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }
        static var labelGap: Double { MetricToken.focusRing.leadingScalar }
        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var blockGap: Double { inset * 2 }
        /// The space above a section heading. Wider than the gap between blocks, because a heading
        /// belongs to what follows it and the whitespace is what says so.
        static var headingLead: Double { inset * 4 }
        static var bodyPadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }
        static var bandPadding: Double { unit + inset }

        // MARK: - Blocks

        static var codeRadius: Double { MetricToken.selectionRadius.leadingScalar }
        static var codePadding: Double { MetricToken.selectionRadius.leadingScalar }
        static var figureRadius: Double { MetricToken.selectionRadius.leadingScalar }
        static var figurePadding: Double { unit + inset }
        /// The rule down the left of a quote — three times a hairline, as the mock draws it.
        static var quoteRule: Double { MetricToken.focusRing.leadingScalar * 1.5 }
        static var quoteInset: Double { unit + inset }
        /// The hanging indent a list marker sits in.
        static var markerColumn: Double { row - inset }
        static var listInset: Double { inset * 2 }

        // MARK: - Tables and shields

        static var cellPaddingVertical: Double { inset }
        static var cellPaddingHorizontal: Double { unit }
        /// A shield is one small control tall, at the selection inset's radius.
        static var shieldHeight: Double { MetricToken.controlSmall.leadingScalar }
        static var shieldRadius: Double { inset }
        static var shieldPadding: Double { unit - inset / 2 }

        // MARK: - The header

        /// The capability's mark, at `DESIGN.md` §4's detail tile size.
        static var markSide: Double { row * 2 + row * 2 / 3 }
        static var markRadius: Double { MetricToken.selectionRadius.leadingScalar + inset + 2 }
        static var factPaddingVertical: Double { unit + inset / 4 }
        static var factPaddingHorizontal: Double { unit + MetricToken.focusRing.leadingScalar * 3 }
    }
#endif
