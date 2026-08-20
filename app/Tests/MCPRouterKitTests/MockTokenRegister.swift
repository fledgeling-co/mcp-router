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

    // MARK: - Building the live register

    /// Classifies every mock token against the shipped Swift palette.
    ///
    /// Deliberately takes no view of what the answer should be. It reads both sides, records what
    /// each carries, and marks a row `matched` only when every appearance the mock authors agrees
    /// with the Swift value for that appearance.
    static func live(from text: String) throws -> Register {
        let byName = try MockTokenParser.declarationsByName(in: text)
        let rows = try metricRows(in: text, against: byName) + colorRows(from: byName)
        return Register(
            mock: "design/mcp-router-console.html",
            note: "Regenerate with MCP_ROUTER_WRITE_TOKEN_REGISTER=1 swift test --filter MockToken",
            rows: rows.sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }
        )
    }

    /// The `<!-- mac-craft:metrics -->` half, one row per metric the mock declares.
    ///
    /// `against` is the parsed stylesheet, needed because a colour row inside the metrics comment is
    /// checked against the `:root` block rather than against Swift — the comment and the block are
    /// two spellings of one palette, and a summary that has drifted from what it summarises is a
    /// document that lies to whoever reads the summary first.
    private static func metricRows(
        in text: String,
        against byName: [String: [MockTokenParser.Appearance: MockTokenParser.Declaration]]
    ) throws -> [Row] {
        var rows: [Row] = []
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
                let declared = byName["--" + row.name]?[.light]?.color
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
        return rows
    }

    /// The stylesheet half, one row per custom property across every appearance it is authored in.
    private static func colorRows(
        from byName: [String: [MockTokenParser.Appearance: MockTokenParser.Declaration]]
    ) -> [Row] {
        var rows: [Row] = []
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
        return rows
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
}
