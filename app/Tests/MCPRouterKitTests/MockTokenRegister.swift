import Foundation
@testable import MCPRouterKit

/// The classification register: what every token in `design/mcp-router-console.html` is, measured
/// against the shipped Swift palette.
///
/// ## Why a register rather than a straight comparison
///
/// `DESIGN.md` specifies *Instrument Panel* and the mock builds *Patchbay*. They are two directions,
/// not two drafts of one — dark `--ground` is `#1E1E1E` in the document and `#1C1C1E` in the mock,
/// light `--accent` is `#0069CF` against `#0088FF`, and the mock carries an `--accent-ink` family
/// the document has no equivalent for. `M21-token-layer-and-design-md.md` owns that decision and
/// says so in as many words; the M23 brief says *"Which document is authoritative is M21's open
/// decision."* So a test that simply demanded equality would be red for a reason nobody intends to
/// fix this week, and the usual response to a permanently red gate is to delete it.
///
/// What this does instead is record, for every mock token, **which of the two it is**:
///
/// - `matched` — a Swift token maps to it and the values agree in every appearance the mock authors
/// - `pending` — they differ, or Swift has no such token, and a **pre-existing** citation says why
///
/// and then assert that the live classification equals the committed one, **including both observed
/// values on a `pending` row**. That is what stops the register becoming the loophole it looks like:
/// a `pending` row is not "ignore this token", it is "these two exact values, still apart". Change
/// either side of a pending pair and the fingerprint moves and the suite goes red. Add a token to
/// the mock and it is unclassified, which is a finding. Let a matched pair drift and it becomes
/// pending, which is a finding.
///
/// The register is regenerated with `MCP_ROUTER_WRITE_TOKEN_REGISTER=1 swift test --filter MockToken`,
/// the same shape as `make parity-regen`, so updating it is a deliberate, reviewable diff rather
/// than something a runner does by accident.
enum MockTokenRegister {
    // MARK: - Citations

    /// A citation is **external and pre-existing**: a file that is not this one, carrying a line
    /// that was written before this item started. `citationsResolve` asserts both halves — the file
    /// exists and the quote appears in it verbatim — so a justification composed during an audit
    /// cannot be typed in here and pass.
    struct Citation: Sendable {
        let key: String
        let file: String
        let quote: String
    }

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

    // MARK: - The name mapping

    /// Mock custom property → `ColorToken` raw value, for the tokens that name the same thing.
    ///
    /// Declared rather than inferred by string munging: `--line-strong` and `--lineS` are the same
    /// role spelled twice, and a fuzzy matcher that got that right would also pair `--accent-ink`
    /// with `--accent`, which is precisely the substitution M21 exists to prevent.
    static let colorNameMap: [String: String] = [
        "--ground": "--ground",
        "--panel": "--panel",
        "--raised": "--raised",
        "--raised2": "--raised2",
        "--line": "--line",
        "--line-strong": "--lineS",
        "--f1": "--f1",
        "--f2": "--f2",
        "--f3": "--f3",
        "--t1": "--t1",
        "--t2": "--t2",
        "--t3": "--t3",
        "--t4": "--t4",
        "--accent": "--accent",
        "--live": "--live",
        "--attn": "--attn",
        "--fail": "--fail",
        "--on-accent": "--onAccent"
    ]

    /// Metric row name → the Swift case that carries the same value.
    ///
    /// `body-type` deliberately maps to a `TypeToken`, not a `MetricToken`: the mock records the
    /// body size in its metrics block and Swift records it on the type ladder, and pretending it is
    /// chrome geometry to make the mapping uniform would put a size in two places.
    enum MetricTarget: Sendable, Equatable {
        case metric(MetricToken)
        case type(TypeToken)

        var label: String {
            switch self {
            case let .metric(m): "MetricToken.\(m.rawValue)"
            case let .type(t): "TypeToken.\(t.rawValue).size"
            }
        }

        var points: Double {
            switch self {
            case let .metric(m): m.leadingScalar
            case let .type(t): t.size
            }
        }
    }

    static let metricNameMap: [String: MetricTarget] = [
        "titlebar": .metric(.titlebar),
        "unified-toolbar": .metric(.unifiedToolbar),
        "control-mini": .metric(.controlMini),
        "control-small": .metric(.controlSmall),
        "control-regular": .metric(.controlRegular),
        "control-large": .metric(.controlLarge),
        "control-xl": .metric(.controlExtraLarge),
        "body-type": .type(.body),
        "sidebar": .metric(.sidebar),
        "selection-radius": .metric(.selectionRadius),
        "popover-radius": .metric(.popoverRadius)
    ]

    // MARK: - Classification

    enum Classification: String, Sendable, Codable {
        case matched
        case pending
    }

    /// One row of the committed register.
    struct Row: Codable, Equatable, Sendable {
        let name: String
        let kind: String
        let classification: String
        /// The Swift symbol this row was compared against, or `"—"` when Swift has no counterpart.
        let swift: String
        /// The value each side actually carries, appearance by appearance. Recorded on **every**
        /// row, matched and pending alike — this is the fingerprint that makes a pending row a
        /// measurement rather than an exemption.
        let observed: [String: String]
        /// The citation key, on a pending row only.
        let citation: String?
    }

    struct Register: Codable, Equatable, Sendable {
        let mock: String
        let note: String
        let rows: [Row]
    }

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

    // MARK: - Building the live register

    /// Classifies every mock token against the shipped Swift palette.
    ///
    /// Deliberately takes no view of what the answer should be. It reads both sides, records what
    /// each carries, and marks a row `matched` only when every appearance the mock authors agrees
    /// with the Swift value for that appearance.
    static func live(from text: String) throws -> Register {
        var rows: [Row] = []
        let byNameCache: [String: [MockTokenParser.Appearance: MockTokenParser.Declaration]]? =
            try MockTokenParser.declarationsByName(in: text)

        // ---- metric rows -------------------------------------------------------------
        for row in try MockTokenParser.metricRows(in: text) {
            if let points = row.points {
                if let target = metricNameMap[row.name] {
                    let agrees = abs(target.points - points) < 0.0001
                    rows.append(Row(
                        name: row.name,
                        kind: "metric",
                        classification: (agrees ? Classification.matched : .pending).rawValue,
                        swift: "\(target.label) = \(fmt(target.points))",
                        observed: ["mock": row.rawValue, "swift": "\(fmt(target.points))pt"],
                        citation: agrees ? nil : pendingCitations[row.name]
                    ))
                } else {
                    rows.append(Row(
                        name: row.name,
                        kind: "metric",
                        classification: Classification.pending.rawValue,
                        swift: "—",
                        observed: ["mock": row.rawValue, "swift": "absent"],
                        citation: pendingCitations[row.name]
                    ))
                }
            } else {
                // A colour row inside the metrics comment. The comment and the `:root` block are
                // two spellings of the same palette, so this row is an **internal consistency**
                // check on the mock rather than a comparison against Swift: the metrics comment is
                // what a converter reads first, and a comment that has drifted from the stylesheet
                // it summarises is a document that lies to whoever trusts the summary.
                let declared = byNameCache?["--" + row.name]?[.light]?.color
                let agrees = row.color != nil && declared != nil && row.color == declared
                rows.append(Row(
                    name: row.name,
                    kind: "metric-colour",
                    classification: (agrees ? Classification.matched : .pending).rawValue,
                    swift: "mock :root --\(row.name)",
                    observed: [
                        "metrics-comment": row.rawValue,
                        "root-light": declared?.description ?? "absent",
                        "tier": row.tier
                    ],
                    citation: agrees ? nil : pendingCitations[row.name]
                ))
            }
        }

        // ---- colour declarations ------------------------------------------------------
        let byName = byNameCache ?? [:]
        for name in byName.keys.sorted() {
            let perAppearance = byName[name] ?? [:]
            var observed: [String: String] = [:]
            for (appearance, decl) in perAppearance {
                observed["mock.\(appearance.rawValue)"] = decl.color.map(\.description) ?? decl.rawValue
            }

            guard let swiftName = colorNameMap[name], let token = ColorToken(rawValue: swiftName) else {
                rows.append(Row(
                    name: name,
                    kind: kind(of: perAppearance),
                    classification: Classification.pending.rawValue,
                    swift: "—",
                    observed: observed.merging(["swift": "absent"]) { a, _ in a },
                    citation: pendingCitations[name]
                ))
                continue
            }

            let darkValue = MockTokenParser.ColorValue(hex: token.hex, alpha: token.opacity)
            let lightValue = MockTokenParser.ColorValue(hex: token.lightHex, alpha: token.lightOpacity)
            observed["swift.dark"] = darkValue.description
            observed["swift.light"] = lightValue.description

            // Every appearance the mock authors must agree with the Swift value for its side.
            // The two increased-contrast contexts are included: Swift has no contrast variant, so a
            // token the mock re-solves for `prefers-contrast` cannot be `matched` — which is the
            // honest answer, not a gap to paper over.
            var agrees = !perAppearance.isEmpty
            for (appearance, decl) in perAppearance {
                guard let mockColor = decl.color else { agrees = false; break }
                if mockColor != (appearance.isDark ? darkValue : lightValue) { agrees = false; break }
            }

            rows.append(Row(
                name: name,
                kind: "colour",
                classification: (agrees ? Classification.matched : .pending).rawValue,
                swift: "ColorToken(\(swiftName))",
                observed: observed,
                citation: agrees ? nil : pendingCitations[name]
            ))
        }

        return Register(
            mock: "design/mcp-router-console.html",
            note: "Regenerate with MCP_ROUTER_WRITE_TOKEN_REGISTER=1 swift test --filter MockToken",
            rows: rows.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
        )
    }

    /// What a custom property carries, so a shadow list and an embedded asset are not reported as
    /// colours that failed to parse.
    private static func kind(
        of declarations: [MockTokenParser.Appearance: MockTokenParser.Declaration]
    ) -> String {
        if declarations.values.contains(where: \.isAsset) { return "asset" }
        if declarations.values.contains(where: \.isComposite) { return "composite" }
        return "colour"
    }

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    // MARK: - On disk

    static func registerURL(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let candidate = dir.appendingPathComponent("planning/fidelity/token-register.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let fidelity = dir.appendingPathComponent("planning/fidelity")
            if FileManager.default.fileExists(atPath: fidelity.path) {
                return fidelity.appendingPathComponent("token-register.json")
            }
            dir = dir.deletingLastPathComponent()
        }
        throw MockTokenParser.ParseError.mockNotFound(startingFrom: filePath)
    }

    static func encode(_ register: Register) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(register)
    }
}
