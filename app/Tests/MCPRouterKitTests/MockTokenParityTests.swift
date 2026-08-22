import Foundation
import Testing
@testable import MCPRouterKit

/// The token layer of the M23 conversion gate: the mock's two machine-readable blocks against the
/// shipped Swift palette.
///
/// `DesignTokenParityTests` stays exactly as it is and keeps pointing at `DESIGN.md`. The M23 brief
/// is explicit that which document is authoritative is M21's decision, and deleting the document
/// parser before that lands would leave the shipped palette with no guard at all.
@Suite("Mock token parity — design/mcp-router-console.html")
struct MockTokenParityTests {
    static func mockText() throws -> String {
        try MockTokenParser.mockText()
    }

    /// The repository root, found by walking up from this file.
    static func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw MockTokenParser.ParseError.mockNotFound(startingFrom: filePath)
    }

    // MARK: - Assertion 1 · every metric row has a Swift case with the same value

    @Test("every metric row in the mock is classified, and every matched one agrees exactly")
    func metricRowsAreClassifiedAndMatchedOnesAgree() throws {
        let rows = try MockTokenParser.metricRows(in: Self.mockText())
        #expect(!rows.isEmpty, "parsed no metric rows — the mac-craft:metrics comment changed shape")

        for row in rows {
            guard let points = row.points else {
                // A colour row inside the metrics comment. It is classified with the colours; the
                // point here is that it parsed as *something*, not that it was skipped.
                #expect(
                    row.color != nil,
                    "metrics row '\(row.name) \(row.rawValue)' is neither a length nor a colour"
                )
                continue
            }
            guard let target = MockTokenRegister.metricNameMap[row.name] else {
                #expect(
                    MockTokenRegister.pendingCitations[row.name] != nil,
                    "the mock declares metric '\(row.name)' with no Swift case and no citation"
                )
                continue
            }
            #expect(
                abs(target.points - points) < 0.0001,
                "\(row.name): mock \(row.rawValue) vs \(target.label) \(target.points)"
            )
        }
    }

    /// The eighteen metric rows that agree today, named individually.
    ///
    /// This is the ratchet under the register. Without it, a runner could satisfy "every row is
    /// classified" by reclassifying every matched row as pending and adding a citation — which is
    /// exactly the motivated classification the brief warns about, one level up. A named floor
    /// means downgrading any of these is a test edit somebody has to justify in a diff.
    ///
    /// **The ratchet extends and never shrinks.** It held eleven names while M21 was open; the
    /// seven the mock declared and Swift had no case for became `MetricToken` cases in that item,
    /// so they join. Extending is the ratchet's stated intent.
    static let mustMatchMetrics = [
        "titlebar", "unified-toolbar", "toolbar-compact", "control-mini", "control-small",
        "control-regular", "control-large", "control-xl", "body-type", "sidebar",
        "sidebar-row-medium", "sidebar-row-large", "selection-radius", "popover-radius",
        "card-radius", "grid-unit", "jack-lane", "scrollbar"
    ]

    @Test("the metric rows that agree today are still agreeing")
    func theMatchedMetricFloorHolds() throws {
        let live = try MockTokenRegister.live(from: Self.mockText())
        for name in Self.mustMatchMetrics {
            guard let row = live.rows.first(where: { $0.name == name && $0.kind == "metric" }) else {
                Issue.record("'\(name)' is on the matched floor but the mock no longer declares it")
                continue
            }
            #expect(
                row.classification == "matched",
                "'\(name)' fell off the matched floor: \(row.observed)"
            )
        }
    }

    // MARK: - Assertion 2 · every custom property, in every appearance the mock authors

    @Test("all six appearance contexts parse, and none of them is empty")
    func everyAppearanceContextParses() throws {
        let byAppearance = try Dictionary(
            grouping: MockTokenParser.declarations(in: Self.mockText()),
            by: \.appearance
        )
        for appearance in MockTokenParser.Appearance.allCases {
            let count = byAppearance[appearance]?.count ?? 0
            #expect(
                count > 0,
                """
                the \(appearance.rawValue) context declared nothing. An empty context and a \
                matching context are the same thing to a differ, which is the failure this \
                suite exists to make impossible.
                """
            )
        }
    }

    @Test("every custom property is classified against the Swift palette")
    func everyCustomPropertyIsClassified() throws {
        let live = try MockTokenRegister.live(from: Self.mockText())
        let colourRows = live.rows.filter { ["colour", "composite", "asset"].contains($0.kind) }
        #expect(!colourRows.isEmpty, "no custom properties parsed out of the mock")

        for row in colourRows where row.classification == "pending" {
            #expect(
                row.citation != nil,
                """
                '\(row.name)' is pending with no citation. A pending row without an external, \
                pre-existing reason is an unclassified token, which is a finding.
                """
            )
        }
    }

    /// The forty colours the two documents agree on.
    ///
    /// A floor for the same reason `mustMatchMetrics` is one: without it, "every token is
    /// classified" is satisfiable by moving every matched row to `pending` and pointing at an open
    /// item — motivated classification, one level up from the thing the brief warns about. None of
    /// these can become pending without somebody editing this list in a diff.
    ///
    /// **It held two names before M21 and holds the whole palette after it.** That is the item's
    /// result stated as a ratchet: `DESIGN.md` §1–2 was re-authored against the design of record,
    /// so every colour the mock declares now has a `ColorToken` carrying the same value in every
    /// context the mock authors. What is deliberately *not* here is the five composite shadow rows
    /// and the fourteen embedded assets, which keep their citations — see
    /// `MockTokenCitations.swift`.
    static let mustMatchColors = [
        "--desktop", "--ground", "--chrome", "--menubar", "--panel", "--raised", "--raised2",
        "--sunken", "--scrim", "--line", "--line-strong", "--f1", "--f2", "--f3", "--jack-off",
        "--jack-ring", "--tl-close", "--tl-min", "--tl-zoom", "--tl-off", "--focus", "--focus-halo",
        "--accent-wash", "--accent-wash-line", "--t1", "--t2", "--t3", "--t4", "--accent", "--live",
        "--attn", "--fail", "--accent-ink", "--accent-text", "--live-ink", "--attn-ink",
        "--fail-ink", "--shield-good", "--badge-bg", "--on-accent"
    ]

    @Test("every colour on the matched floor is still matched")
    func theMatchedColourFloorHolds() throws {
        let live = try MockTokenRegister.live(from: Self.mockText())
        for name in Self.mustMatchColors {
            guard let row = live.rows.first(where: { $0.name == name && $0.kind == "colour" }) else {
                Issue.record("'\(name)' is on the matched floor but the mock no longer declares it")
                continue
            }
            #expect(row.classification == "matched", "'\(name)' fell off the matched floor: \(row.observed)")
        }
    }

    /// The metrics comment and the `:root` block are two spellings of one palette, and the comment
    /// is what a converter reads first.
    @Test("the metrics comment has not drifted from the stylesheet it summarises")
    func theMetricsCommentAgreesWithTheRootBlock() throws {
        let live = try MockTokenRegister.live(from: Self.mockText())
        let colourRows = live.rows.filter { $0.kind == "metric-colour" }
        #expect(
            colourRows.count >= 12,
            "the metrics comment declares \(colourRows.count) colours, expected at least 12"
        )
        for row in colourRows {
            #expect(
                row.classification == "matched",
                "metrics comment '\(row.name)' disagrees with the :root block: \(row.observed)"
            )
        }
    }

    @Test("every ColorToken case appears in the name map, so a new one cannot go unwatched")
    func theNameMapCoversTheWholePalette() {
        let mapped = Set(MockTokenRegister.colorNameMap.values)
        for token in ColorToken.allCases {
            #expect(
                mapped.contains(token.rawValue),
                """
                ColorToken.\(token) is in no mock name map entry, so the mock is never compared \
                against it — it would drift with nothing looking.
                """
            )
        }
    }

    // MARK: - The register is a value fingerprint of both documents

    @Test("the live classification equals the committed register, values included")
    func theCommittedRegisterMatchesWhatIsOnDisk() throws {
        let live = try MockTokenRegister.live(from: Self.mockText())
        let url = try MockTokenRegister.registerURL()

        if ProcessInfo.processInfo.environment["MCP_ROUTER_WRITE_TOKEN_REGISTER"] == "1" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try MockTokenRegister.encode(live).write(to: url)
            print("MOCK-FIDELITY-TOKENS: register rewritten at \(url.path)")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("""
            no committed register at \(url.path). Regenerate it with \
            MCP_ROUTER_WRITE_TOKEN_REGISTER=1 swift test --filter MockToken and commit the result.
            """)
            return
        }

        let committed = try JSONDecoder().decode(
            MockTokenRegister.Register.self, from: Data(contentsOf: url)
        )

        let liveByName = Dictionary(uniqueKeysWithValues: live.rows.map { ("\($0.kind)/\($0.name)", $0) })
        let committedByName = Dictionary(uniqueKeysWithValues: committed.rows.map { (
            "\($0.kind)/\($0.name)",
            $0
        ) })

        let added = Set(liveByName.keys).subtracting(committedByName.keys)
        let removed = Set(committedByName.keys).subtracting(liveByName.keys)
        #expect(
            added.isEmpty,
            "the mock declares tokens the register has never classified: \(added.sorted())"
        )
        #expect(
            removed.isEmpty,
            "the register classifies tokens the mock no longer declares: \(removed.sorted())"
        )

        for key in Set(liveByName.keys).intersection(committedByName.keys).sorted() {
            guard let l = liveByName[key], let c = committedByName[key] else { continue }
            #expect(
                l.classification == c.classification,
                "\(key): classification moved \(c.classification) → \(l.classification)"
            )
            #expect(
                l.observed == c.observed,
                """
                \(key): the recorded values moved. Committed \(c.observed), live \(l.observed). \
                A pending row records both sides' values on purpose — this is a real change to \
                one of the two documents, not a bookkeeping difference.
                """
            )
            #expect(l.swift == c.swift, "\(key): the Swift symbol moved \(c.swift) → \(l.swift)")
            #expect(
                l.citation == c.citation,
                "\(key): the citation moved \(c.citation ?? "nil") → \(l.citation ?? "nil")"
            )
        }

        Self.reportCensus(live)
    }

    /// The marker the shell gate reads, and one line per pending row.
    ///
    /// Same mechanism as `PARITY-VECTORS-EXECUTED`: a check that prints nothing cannot be
    /// distinguished by a caller from a check that did not run, so the gate's `tokens` layer parses
    /// this line and treats its absence as inconclusive rather than as agreement.
    private static func reportCensus(_ live: MockTokenRegister.Register) {
        let matched = live.rows.filter { $0.classification == "matched" }.count
        let pending = live.rows.filter { $0.classification == "pending" }.count
        let uncited = live.rows.filter { $0.classification == "pending" && $0.citation == nil }.count
        print(
            "MOCK-FIDELITY-TOKENS: rows=\(live.rows.count) matched=\(matched) "
                + "pending=\(pending) uncited=\(uncited)"
        )
        for row in live.rows where row.classification == "pending" {
            let observed = row.observed
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            print(
                "MOCK-FIDELITY-PENDING: \(row.kind)/\(row.name) \(observed) "
                    + "citation=\(row.citation ?? "none")"
            )
        }
    }

    // MARK: - The mock's own literals_outside claim, measured

    // MARK: - Assertion 3 · no colour literal outside the palette type
}

/// The parser's own normalisations, tested directly rather than only through the parity checks.
@Suite("Mock token parsing")
struct MockTokenParserTests {
    @Test("hex is canonicalised to six upper-case digits, in all three lengths")
    func canonicalisesHex() {
        #expect(MockTokenParser.color(of: "#FFF") == MockTokenParser.ColorValue(hex: "#FFFFFF", alpha: 1))
        #expect(MockTokenParser.color(of: "#0088ff") == MockTokenParser.ColorValue(hex: "#0088FF", alpha: 1))
        #expect(MockTokenParser.color(of: "#00000080")?.hex == "#000000")
        #expect(MockTokenParser.color(of: "#0088FF ;") == MockTokenParser.ColorValue(
            hex: "#0088FF",
            alpha: 1
        ))
    }

    @Test("rgb and rgba become the same canonical form")
    func canonicalisesFunctionalColours() {
        #expect(MockTokenParser.color(of: "rgba(0,0,0,0.10)") == MockTokenParser.ColorValue(
            hex: "#000000",
            alpha: 0.10
        ))
        #expect(MockTokenParser.color(of: "rgb(255, 255, 255)") == MockTokenParser.ColorValue(
            hex: "#FFFFFF",
            alpha: 1
        ))
        #expect(MockTokenParser.color(of: "rgba(255,255,255,0.09)")?.alpha == 0.09)
    }

    /// The strictness that keeps a shadow from being compared against a fill.
    @Test("a value that merely contains a colour is not a colour")
    func compositeValuesAreNotColours() {
        #expect(MockTokenParser.color(of: "0 22px 70px rgba(0,0,0,0.34), 0 2px 8px rgba(0,0,0,0.18)") == nil)
        #expect(MockTokenParser.color(of: "light dark") == nil)
        #expect(MockTokenParser.color(of: "#12345") == nil)
    }

    @Test("a length is read only when the whole value is one")
    func readsLengths() {
        #expect(MockTokenParser.points(of: "33px") == 33)
        #expect(MockTokenParser.points(of: "2.5px") == 2.5)
        #expect(MockTokenParser.points(of: "#0088FF") == nil)
        #expect(MockTokenParser.points(of: "0 22px 70px") == nil)
    }

    /// An SVG sprite reference is not a colour, and the mock is full of them.
    @Test("a fragment identifier is not mistaken for a hex colour")
    func fragmentIdentifiersAreNotColours() throws {
        let sample = """
        <svg class="icon"><use href="#i-arrow-r"></use></svg>
        <section id="b-servers"></section>
        <div style="color:#0088FF"></div>
        """
        // The scan runs over lines outside the token blocks, so exercise it on the same routine
        // through a text that has both a real literal and two decoys.
        let text = try MockTokenParser.mockText()
        let stray = try MockTokenParser.strayColorLiterals(in: text + "\n" + sample)
        #expect(stray.count == 1, "expected exactly the one planted literal, got \(stray.map(\.text))")
        #expect(stray.first?.text == "#0088FF")
    }

    @Test("a missing mock fails loudly rather than skipping the layer")
    func missingMockThrows() {
        #expect(throws: MockTokenParser.ParseError.self) {
            try MockTokenParser.mockURL(from: "/nonexistent/deep/path/file.swift")
        }
    }

    @Test("an unterminated metrics comment throws rather than returning what it read so far")
    func unterminatedMetricsCommentThrows() {
        #expect(throws: MockTokenParser.ParseError.self) {
            try MockTokenParser.metricRows(in: "<!-- mac-craft:metrics\ntitlebar 33px kit\n")
        }
    }

    @Test("a missing appearance context throws rather than yielding an empty dictionary")
    func missingAppearanceContextThrows() {
        #expect(throws: MockTokenParser.ParseError.self) {
            try MockTokenParser.declarations(in: ":root{\n--a:#FFF;\n}\n")
        }
    }
}
