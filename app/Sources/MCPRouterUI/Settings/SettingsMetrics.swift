#if os(macOS)
    import MCPRouterKit

    /// Geometry the design authority documents as a range rather than a value.
    ///
    /// `MetricToken` tokenises only the **leading** scalar of each documented cell — `DESIGN.md`'s
    /// "card radius 10–14" yields 10 and "table rows 24–28" yields 24 — so this window's 32pt rows
    /// and its 150pt label column have no token to read. `SWIFT_PRACTICES.md` §5 forbids scattering
    /// them as literals, so they are named once here and derived from the documented units, exactly
    /// as `ServersBoardMetrics` does for the Servers board.
    ///
    /// Carried forward from the Settings board unchanged, plus the two the window needs and the
    /// board did not: it had no chrome of its own, because the shell drew it.
    enum SettingsMetrics {
        private static var unit: Double { MetricToken.tableRows.leadingScalar }
        private static var inset: Double { MetricToken.selectionInset.leadingScalar }

        /// The shared label column. **One constant, used by every group**, which is what makes
        /// "label-left, control-right, on one axis across the whole pane" a property of the layout
        /// rather than a coincidence four cards happen to share.
        static var labelColumn: Double { SettingsPresentation.labelColumnWidth }

        /// A settings row. Taller than a dense table row because it holds a control rather than a
        /// glyph, and the loading skeleton uses the same value so the card cannot resize when the
        /// real values land.
        static var rowHeight: Double { unit + inset * 2 }

        static var tightGap: Double { inset }
        static var gap: Double { inset * 2 }
        static var groupGap: Double { inset * 5 }
        static var cardPadding: Double { inset * 3 }
        static var panePadding: Double { MetricToken.selectionRadius.leadingScalar * 2 }
        static var cardRadius: Double { MetricToken.selectionRadius.leadingScalar + inset / 2 }
        static var chipHeight: Double { unit - inset }
        static var hairline: Double { MetricToken.focusRing.leadingScalar / 2 }

        /// The pane source list, and the one number in this window that disagrees with the mock.
        ///
        /// **This is `DESIGN.md`'s 256, and the mock's 200 is a declared disagreement rather than a
        /// value nobody could derive.** A settings source list *is* a sidebar; §2 specifies
        /// `Sidebar 256pt`; `MetricToken.sidebar` is that value. The mock's own `mac-craft:metrics`
        /// block carries `sidebar 256px` and **no 200 of any name**, so the mock disagrees with
        /// itself as well as with the document — and `DesignTokenParityTests` compares
        /// `MetricToken`'s name set against §2's table for exact equality in both directions, so a
        /// `settingsSidebar` case without a new §2 row reddens it, and authoring that row is M21's
        /// substance.
        ///
        /// Arithmetic landing on 200 — `256 - 56`, `256 * 0.78` — would be a literal wearing a
        /// token's clothes, which is the same defect one level of indirection down. The 56pt gap is
        /// declared in `planning/fidelity/settings.layers.json`'s note and reported by the geometry
        /// layer on every run, which is what the conversion contract is for.
        static var sourceListWidth: Double { MetricToken.sidebar.leadingScalar }

        /// The window's own titlebar. The mock draws 33 and `DESIGN.md` §2 records 33, so this one
        /// is a token read and nothing more.
        static var titlebarHeight: Double { MetricToken.titlebar.leadingScalar }
    }
#endif
