import Foundation

/// Every citation the register stands on: the external, pre-existing lines that say why a token is
/// `pending` rather than a defect.
///
/// A file of its own because the two tables are long and because they are the part a reader audits
/// most often — a citation composed during an audit is the single most common way drift ships, and
/// `citationsResolve` checks each of these against the file and the quote it names.
extension MockTokenRegister {
    static let citations: [Citation] = [
        Citation(
            key: "M21-direction-split",
            file: "planning/features-to-triage/M21-token-layer-and-design-md.md",
            quote: "This needs a decision rather than a merge"
        ),
        Citation(
            key: "M21-owns-the-mock-token-block",
            file: "planning/features-to-triage/M21-token-layer-and-design-md.md",
            quote: "Every colour lives in a token. The mock carries 89 in its token block"
        ),
        Citation(
            key: "M21-metric-rows",
            file: "planning/features-to-triage/M21-token-layer-and-design-md.md",
            quote: "`MetricToken` gains the mock's metric rows."
        ),
        Citation(
            key: "DESIGN-assets-live-in-the-catalogue",
            file: "DESIGN.md",
            quote: "an authored asset in the catalogue."
        ),
        Citation(
            key: "M21-ink-twins",
            file: "planning/features-to-triage/M21-token-layer-and-design-md.md",
            quote: "Every indicator hue needs the same twin"
        )
    ]

    /// The citation each pending row carries, keyed by token name.
    ///
    /// A pending row with no entry here is a **finding**, not a default — that is what stops
    /// "pending" from being reachable without saying why.
    static let pendingCitations: [String: String] = [
        // Colours: the two documents are two directions, and M21 owns the choice.
        "--ground": "M21-direction-split",
        "--panel": "M21-direction-split",
        "--raised2": "M21-direction-split",
        "--line": "M21-direction-split",
        "--line-strong": "M21-direction-split",
        "--f1": "M21-direction-split",
        "--f2": "M21-direction-split",
        "--f3": "M21-direction-split",
        "--t1": "M21-direction-split",
        "--t2": "M21-direction-split",
        "--t3": "M21-direction-split",
        "--t4": "M21-direction-split",
        "--accent": "M21-direction-split",
        "--live": "M21-direction-split",
        "--attn": "M21-direction-split",
        "--fail": "M21-direction-split",
        // The ink family: hues solved for the contrast floor, which Swift has no twin for yet.
        "--accent-ink": "M21-ink-twins",
        "--accent-text": "M21-ink-twins",
        "--live-ink": "M21-ink-twins",
        "--attn-ink": "M21-ink-twins",
        "--fail-ink": "M21-ink-twins",
        "--shield-good": "M21-ink-twins",
        "--badge-bg": "M21-ink-twins",
        // Everything else the mock's token block carries and Swift does not.
        "--desktop": "M21-owns-the-mock-token-block",
        "--chrome": "M21-owns-the-mock-token-block",
        "--sunken": "M21-owns-the-mock-token-block",
        "--menubar": "M21-owns-the-mock-token-block",
        "--scrim": "M21-owns-the-mock-token-block",
        "--accent-wash": "M21-owns-the-mock-token-block",
        "--accent-wash-line": "M21-owns-the-mock-token-block",
        "--jack-off": "M21-owns-the-mock-token-block",
        "--jack-ring": "M21-owns-the-mock-token-block",
        "--shadow-window": "M21-owns-the-mock-token-block",
        "--shadow-pop": "M21-owns-the-mock-token-block",
        "--shadow-sheet": "M21-owns-the-mock-token-block",
        "--shadow-card": "M21-owns-the-mock-token-block",
        "--shadow-tile": "M21-owns-the-mock-token-block",
        "--focus": "M21-owns-the-mock-token-block",
        "--focus-halo": "M21-owns-the-mock-token-block",
        "--tl-close": "M21-owns-the-mock-token-block",
        "--tl-min": "M21-owns-the-mock-token-block",
        "--tl-zoom": "M21-owns-the-mock-token-block",
        "--tl-off": "M21-owns-the-mock-token-block",
        // The mock's second top-level `:root` block: fourteen embedded WebP marketplace tiles.
        // There is no colour token to compare them against and there should not be — DESIGN.md §4
        // puts an authored asset in the catalogue, not in the palette.
        "--ic-bn-deploy": "DESIGN-assets-live-in-the-catalogue",
        "--ic-bn-market": "DESIGN-assets-live-in-the-catalogue",
        "--ic-browser": "DESIGN-assets-live-in-the-catalogue",
        "--ic-canvas": "DESIGN-assets-live-in-the-catalogue",
        "--ic-cloud": "DESIGN-assets-live-in-the-catalogue",
        "--ic-compass": "DESIGN-assets-live-in-the-catalogue",
        "--ic-db": "DESIGN-assets-live-in-the-catalogue",
        "--ic-design": "DESIGN-assets-live-in-the-catalogue",
        "--ic-files": "DESIGN-assets-live-in-the-catalogue",
        "--ic-flow": "DESIGN-assets-live-in-the-catalogue",
        "--ic-msg": "DESIGN-assets-live-in-the-catalogue",
        "--ic-obs": "DESIGN-assets-live-in-the-catalogue",
        "--ic-ts": "DESIGN-assets-live-in-the-catalogue",
        "--ic-vcs": "DESIGN-assets-live-in-the-catalogue",
        // Metric rows with no Swift case. M21 says in as many words that it takes them.
        "toolbar-compact": "M21-metric-rows",
        "sidebar-row-medium": "M21-metric-rows",
        "sidebar-row-large": "M21-metric-rows",
        "scrollbar": "M21-metric-rows",
        "card-radius": "M21-metric-rows",
        "jack-lane": "M21-metric-rows",
        "grid-unit": "M21-metric-rows"
    ]
}
