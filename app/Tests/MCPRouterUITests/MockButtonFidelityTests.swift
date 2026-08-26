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

        /// The body of a CSS rule, by a selector the rule's list contains. Returns `nil` rather
        /// than the empty string when no rule matches, so a missing rule and an empty one are
        /// distinguishable.
        static func ruleBody(containingSelector needle: String, in css: String) -> String? {
            for block in css.split(separator: "}") {
                guard let brace = block.firstIndex(of: "{") else { continue }
                let selectors = String(block[block.startIndex ..< brace])
                guard selectors.split(separator: ",").contains(where: {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines) == needle
                }) else { continue }
                return String(block[block.index(after: brace)...])
            }
            return nil
        }

        /// The property names a rule body declares.
        static func properties(of body: String) -> Set<String> {
            Set(body.split(separator: ";").compactMap { declaration in
                guard let colon = declaration.firstIndex(of: ":") else { return nil }
                let name = declaration[declaration.startIndex ..< colon]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            })
        }

        /// **The cascade, not the selector.** The first version of this test asserted only that the
        /// source contained the string `.btn.primary:disabled`, which is satisfied by a rule that
        /// exists and loses — the exact defect M31 was filed for, since `.btn:disabled` also existed
        /// and lost to `.btn.primary` on declaration order. So this reads the rule's body and holds
        /// it to the triple `DESIGN.md` §3 now states, in both spellings a mock can say "off" in.
        @Test("the design of record dims a disabled primary in every slot the accent rule fills")
        func theMockDimsTheDisabledPrimary() throws {
            let source = try Self.mock()
            for selector in [".btn.primary:disabled", ".btn.primary.disabled"] {
                guard let body = Self.ruleBody(containingSelector: selector, in: source) else {
                    Issue.record("no rule in the design of record carries the selector \(selector)")
                    continue
                }
                #expect(body.contains("color:var(--t4)"), "\(selector) labels with --t4")
                #expect(body.contains("background:var(--f3)"), "\(selector) fills with --f3")
                #expect(body.contains("border-color:var(--line)"), "\(selector) bezels with --line")
            }

            // The cascade guard proper: every property the accent rule sets must also be set by the
            // disabled rule, or that slot survives into the disabled state. This is what catches a
            // *new* declaration added to `.btn.primary` later — the way the original defect arrived.
            guard let live = Self.ruleBody(containingSelector: ".btn.primary", in: source),
                  let off = Self.ruleBody(containingSelector: ".btn.primary:disabled", in: source)
            else {
                Issue.record("the design of record is missing .btn.primary or its disabled rule")
                return
            }
            let unclaimed = Self.properties(of: live).subtracting(Self.properties(of: off))
            #expect(
                unclaimed.isEmpty,
                "a disabled primary keeps its live \(unclaimed.sorted().joined(separator: ", "))"
            )
        }

        /// The `cursor:not-allowed` decision, recorded as a test because it was landed unratified
        /// and then removed.
        ///
        /// `DESIGN.md` §3 rule 8 — *"Arrow cursor everywhere in app chrome"* — and macOS paints no
        /// `not-allowed` cursor over an unavailable control, so there is nothing for one to map to
        /// on the Swift side. It was also the only `cursor` declaration in the whole design of
        /// record, so the file is held at zero rather than at "not that one".
        @Test("the design of record declares no cursor at all (§3 rule 8)")
        func theMockDeclaresNoCursor() throws {
            let source = try Self.mock()
            let declarations = source.components(separatedBy: "cursor:").count - 1
            #expect(declarations == 0, "the design of record declares \(declarations) cursor(s)")
        }

        /// **The deliverable M31 exists for**: the semantics live in the design authority, not only
        /// in a stylesheet and a doc comment. A stylesheet can be edited into agreement with a
        /// build; `DESIGN.md` is what the build is measured against.
        @Test("DESIGN.md states the disabled-primary treatment, its ratio and its exemption")
        func theDesignAuthorityStatesTheSemantics() throws {
            let url = try SheetShortcutScan.repoRoot().appendingPathComponent("DESIGN.md")
            let design = try String(contentsOf: url, encoding: .utf8)

            #expect(design.contains("| Label | `--on-accent` | `--t4` |"), "the label row")
            #expect(design.contains("| Fill | `--accent-ink` | `--f3` |"), "the fill row")
            #expect(design.contains("| `--line` |"), "the bezel row names --line")

            // The measured pairing, which is deliberately not §2's --t4-over-ground column.
            #expect(design.contains("2.94:1"), "--t4 on --f3 in dark")
            #expect(design.contains("2.62:1"), "--t4 on --f3 in light")
            #expect(design.contains("WCAG 1.4.3"), "the exemption is claimed by name")
            #expect(
                design.contains("inactive user interface component"),
                "the clause is quoted rather than only cited by number"
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
