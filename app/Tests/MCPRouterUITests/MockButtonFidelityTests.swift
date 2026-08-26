#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What `design/mcp-router-console.html` actually says about primary and destructive buttons,
    /// read from the file on every run.
    ///
    /// **Two claims in `Controls.swift` used to rest on literals typed into a doc comment.** One was
    /// a bare *"the 29 `btn primary` instances"* — a count whose normaliser was never named, and
    /// M18's verifier got 29, 33 and 35 over that one phrase, all three defensible. The other was
    /// that the mock draws its destructive control unfilled, which the build then contradicted by
    /// painting `--raised` behind it. Both are properties of a file in this repository, so both are
    /// derived here rather than described there.
    ///
    /// `planning/evidence/M18-gapfix-2/count-btn-primary.py` prints the same three counts with every
    /// site, and `planning/evidence/M18-gapfix-2/btn-primary-sites.md` is its committed output.
    @MainActor
    @Suite("The mock's own button rules")
    struct MockButtonFidelityTests {
        static func mock() throws -> String {
            let url = try SheetShortcutScan.repoRoot()
                .appendingPathComponent("design/mcp-router-console.html")
            return try String(contentsOf: url, encoding: .utf8)
        }

        /// Every element whose `class` attribute carries both `btn` and `primary` as whole words.
        struct Site {
            let tag: String
            let classes: [String]
            let carriesDisabled: Bool

            var isButtonElement: Bool { tag == "button" }
            /// The narrowest of the three readings: the attribute *begins* `btn primary`, which
            /// drops the `btn sm primary` variants.
            var beginsBtnPrimary: Bool { classes.prefix(2) == ["btn", "primary"] }
        }

        static func primarySites(in source: String) throws -> [Site] {
            let element = try NSRegularExpression(pattern: "<([A-Za-z][A-Za-z0-9]*)\\b[^>]*>")
            let classAttribute = try NSRegularExpression(pattern: "class=\"([^\"]*)\"")
            var sites: [Site] = []
            let whole = NSRange(source.startIndex ..< source.endIndex, in: source)
            for match in element.matches(in: source, range: whole) {
                guard let text = Range(match.range, in: source).map({ String(source[$0]) }),
                      let tag = Range(match.range(at: 1), in: source).map({ String(source[$0]) })
                else { continue }
                let tagRange = NSRange(text.startIndex ..< text.endIndex, in: text)
                guard let attribute = classAttribute.firstMatch(in: text, range: tagRange),
                      let value = Range(attribute.range(at: 1), in: text).map({ String(text[$0]) })
                else { continue }
                let classes = value.split(separator: " ").map(String.init)
                guard classes.contains("btn"), classes.contains("primary") else { continue }
                // Both spellings, because a mock can say "off" either way and matching only the
                // attribute would report `class="btn primary disabled"` as a live control.
                sites.append(Site(
                    tag: tag.lowercased(),
                    classes: classes,
                    carriesDisabled: text.contains(" disabled") || classes.contains("disabled")
                ))
            }
            return sites
        }

        /// The three numbers, each with the rule that produces it. Derived, so a mock edit that
        /// moves any of them turns this red instead of rotting the comment that cites them.
        @Test("the three primary-button counts are 35, 33 and 29, under the three named normalisers")
        func theThreeCountsAreWhatControlsClaims() throws {
            let sites = try Self.primarySites(in: Self.mock())
            #expect(sites.count == 35, "any element carrying both words")
            #expect(sites.count(where: \.isButtonElement) == 33, "<button> elements only")
            #expect(sites.count(where: \.beginsBtnPrimary) == 29, "class attributes beginning `btn primary`")
        }

        /// The conclusion the count exists to support, asserted at the **widest** reading, so it
        /// cannot be satisfied by a normaliser that happens to exclude a disabled one.
        @Test("the design of record properly dims disabled primary buttons (M31)")
        func theMockCannotSettleTheDisabledPrimary() throws {
            let source = try Self.mock()
            #expect(
                source.contains(".btn.primary:disabled"),
                "the mock has a rule that dims a primary button when disabled (M31)"
            )
        }

        /// `StandardButtonStyle.fill` returns `nil` for a destructive control. This is the sentence in
        /// the mock that makes that the right answer rather than a preference.
        @Test("the mock draws its destructive control unfilled, and keeps the bezel")
        func theMockDrawsDestructiveUnfilled() throws {
            let source = try Self.mock()
            #expect(
                source.contains(".btn.destructive{color:var(--fail-ink);background:none;box-shadow:none;}"),
                "the mock's destructive rule changed; StandardButtonStyle.fill was derived from it"
            )
            #expect(
                source.contains("border:1px solid var(--line-strong)"),
                "`.btn`'s bezel is what the destructive rule does not reset, so the build keeps it"
            )
            let pressed = "`--f1` is the only interaction fill the mock gives this control, and the "
                + "pressed state stands on it"
            #expect(source.contains(".btn.destructive:hover{background:var(--f1);}"), "\(pressed)")
            #expect(StandardButtonStyle().fill(role: .destructive, isPressed: false) == nil)
            #expect(StandardButtonStyle().fill(role: .destructive, isPressed: true) == .f1)
        }
    }
#endif
