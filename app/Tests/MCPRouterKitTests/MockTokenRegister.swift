import Foundation
@testable import MCPRouterKit

/// The classification register: what every token in `design/mcp-router-console.html` is, measured
/// against the shipped Swift palette.
///
/// ## Why a register rather than a straight comparison
///
/// `DESIGN.md` specified *Instrument Panel* while the mock built *Patchbay*, and they were two
/// directions rather than two drafts of one — dark `--ground` was `#1E1E1E` in the document against
/// `#1C1C1E` in the mock, light `--accent` `#0069CF` against `#0088FF`, and the mock carried an
/// `--accent-ink` family the document had no equivalent for. A test that simply demanded equality
/// would have been red for a reason nobody intended to fix that week, and the usual response to a
/// permanently red gate is to delete it.
///
/// **M21 settled it**: the console mock is the design of record, `DESIGN.md` §1–2 was re-authored
/// against it, and the colour and metric rows now agree. The register stays, and its job shifts
/// from recording a disagreement to holding the agreement in place — the shadow and asset rows are
/// still `pending` with their own citations, and any future drift on either side becomes a
/// classification that moved.
///
/// What it records, for every mock token, is **which of the two it is**:
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
    /// **This map is now the identity, and that is the outcome rather than an accident.** It used
    /// to carry two translations — `--line-strong` → `--lineS` and `--on-accent` → `--onAccent` —
    /// and its own docstring named the risk they created: a fuzzy matcher that got those right
    /// would also pair `--accent-ink` with `--accent`, which is precisely the substitution M21
    /// exists to prevent. M21 took the mock's spellings, so there is nothing left to translate.
    ///
    /// It stays declared rather than being replaced by `token.rawValue`, because
    /// `theNameMapCoversTheWholePalette` reads it to prove every `ColorToken` case is compared
    /// against something — a computed identity would prove that of itself and of nothing else.
    static let colorNameMap: [String: String] = [
        "--desktop": "--desktop",
        "--ground": "--ground",
        "--chrome": "--chrome",
        "--menubar": "--menubar",
        "--panel": "--panel",
        "--raised": "--raised",
        "--raised2": "--raised2",
        "--sunken": "--sunken",
        "--scrim": "--scrim",
        "--line": "--line",
        "--line-strong": "--line-strong",
        "--f1": "--f1",
        "--f2": "--f2",
        "--f3": "--f3",
        "--jack-off": "--jack-off",
        "--jack-ring": "--jack-ring",
        "--tl-close": "--tl-close",
        "--tl-min": "--tl-min",
        "--tl-zoom": "--tl-zoom",
        "--tl-off": "--tl-off",
        "--focus": "--focus",
        "--focus-halo": "--focus-halo",
        "--accent-wash": "--accent-wash",
        "--accent-wash-line": "--accent-wash-line",
        "--t1": "--t1",
        "--t2": "--t2",
        "--t3": "--t3",
        "--t4": "--t4",
        "--accent": "--accent",
        "--live": "--live",
        "--attn": "--attn",
        "--fail": "--fail",
        "--accent-ink": "--accent-ink",
        "--accent-text": "--accent-text",
        "--live-ink": "--live-ink",
        "--attn-ink": "--attn-ink",
        "--fail-ink": "--fail-ink",
        "--shield-good": "--shield-good",
        "--badge-bg": "--badge-bg",
        "--on-accent": "--on-accent"
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
        "toolbar-compact": .metric(.compactToolbar),
        "control-mini": .metric(.controlMini),
        "control-small": .metric(.controlSmall),
        "control-regular": .metric(.controlRegular),
        "control-large": .metric(.controlLarge),
        "control-xl": .metric(.controlExtraLarge),
        "body-type": .type(.body),
        "sidebar": .metric(.sidebar),
        "sidebar-row-medium": .metric(.sidebarRowMedium),
        "sidebar-row-large": .metric(.sidebarRowLarge),
        "selection-radius": .metric(.selectionRadius),
        "popover-radius": .metric(.popoverRadius),
        "card-radius": .metric(.cardRadius),
        "grid-unit": .metric(.gridUnit),
        "jack-lane": .metric(.jackLane),
        "scrollbar": .metric(.scrollbar)
    ]

    /// The `MetricToken` cases the mock's metrics comment declares no row for.
    ///
    /// Named individually rather than left as the gap between two sets, because
    /// `theMetricNameMapCoversTheWholeLadder` cannot demand total coverage — the mock genuinely
    /// does not publish a figure for these four — and "everything else" is the shape an exemption
    /// takes when it stops being checked. `MockTokenParityTests` re-reads the mock and fails if any
    /// of them turns out to be declared after all, so the list cannot outlive its reason.
    ///
    /// - `Table rows` and `Servers row` are `DESIGN.md`'s own. The Servers row was the breaker
    ///   housing plus its padding until M16 retired that element; the value stayed and the
    ///   derivation went, and the mock publishes no figure for either.
    /// - `Sidebar selection inset` and `Focus ring` are drawn in the mock's stylesheet rather than
    ///   summarised in its metrics comment, so there is no `name value tier` row to compare against.
    static let metricsTheMockDoesNotDeclare: [MetricToken] = [
        .tableRows, .serversRow, .selectionInset, .focusRing
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

            // All four Swift values are recorded, not two. A token that re-solves for increased
            // contrast now has somewhere for that value to be visible in the fingerprint; without
            // it, a drift in the accessibility half of the palette would move a classification
            // with nothing in the diff explaining why.
            for context in MockTokenParser.Appearance.allCases {
                let value = swiftValue(of: token, in: context)
                observed["swift.\(context.rawValue)"] = value.description
            }

            // Every appearance the mock authors must agree with the Swift value for **that
            // context** — both axes, appearance and contrast. Reading the Swift side as
            // dark-or-light alone was correct while the palette had two appearances; against a
            // palette with four it would compare a token's base value in the two contexts where it
            // overrides, so the nine tokens carrying the accessibility half could never be
            // `matched` however right they were.
            var agrees = !perAppearance.isEmpty
            for (appearance, decl) in perAppearance {
                guard let mockColor = decl.color else { agrees = false; break }
                if mockColor != swiftValue(of: token, in: appearance) { agrees = false; break }
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

    /// One Swift token's value in one of the mock's six appearance contexts.
    ///
    /// The six collapse onto four: `.is-light` mirrors `:root` and `.is-dark` mirrors the dark
    /// media block, so an override context resolves to the same pair as the block it mirrors.
    private static func swiftValue(
        of token: ColorToken,
        in appearance: MockTokenParser.Appearance
    ) -> MockTokenParser.ColorValue {
        let value = token.value(
            dark: appearance.isDark,
            increasedContrast: appearance.isIncreasedContrast
        )
        return MockTokenParser.ColorValue(hex: value.hex, alpha: value.opacity)
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
