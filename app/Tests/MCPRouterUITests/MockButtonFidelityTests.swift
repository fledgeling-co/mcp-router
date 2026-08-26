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

        /// **The other four accent-filled controls.** M31 was filed against `.btn.primary`, but the
        /// cascade accident belongs to the fill: any rule painting `var(--accent-ink)` that is
        /// declared after, or at higher specificity than, the rule meant to dim it produces the same
        /// defect. Four more controls in the design of record did, and each failed differently —
        /// which is why each is asserted rather than covered by one loop over a token list.
        @Test("the design of record dims every control that resolves an accent fill")
        func theMockDimsEveryAccentFilledControl() throws {
            let source = try Self.mock()

            // `.tb-btn.on` (0-2-0) was declared after `.tb-btn.disabled` (0-2-0) and won the whole
            // cascade, so a disabled toolbar button was byte-identical to a live one. Enumerating
            // the accent-carrying combinations puts the disabled rule at 0-3-0.
            for selector in [".tb-btn.on.disabled", ".tb-btn.on:disabled"] {
                guard let body = Self.ruleBody(containingSelector: selector, in: source) else {
                    Issue.record("no rule in the design of record carries the selector \(selector)")
                    continue
                }
                #expect(body.contains("background:var(--f3)"), "\(selector) fills with --f3")
                #expect(body.contains("color:var(--t4)"), "\(selector) labels with --t4")
                #expect(body.contains("border-color:var(--line)"), "\(selector) bezels with --line")
            }

            // `.trow.disabled` won `color` on declaration order but never the fill, so a disabled
            // selected row drew --t4 on --accent-ink: 1.68:1 light, 1.02:1 dark. The fill has to
            // come off with the label, and the selected-row descendants have to come with it.
            guard let row = Self.ruleBody(containingSelector: ".trow.disabled", in: source) else {
                Issue.record("the design of record has no .trow.disabled rule")
                return
            }
            #expect(row.contains("background:var(--f3)"), ".trow.disabled takes the fill off the accent")
            #expect(row.contains("color:var(--t4)"), ".trow.disabled labels with --t4")
            #expect(
                Self.ruleBody(containingSelector: ".trow.disabled .c-sub", in: source) != nil,
                "the selected-row descendants are brought off --on-accent too"
            )

            // `.switch` carried a correct rule spelled for a marker the markup does not use: the
            // sheet said `:disabled`, the one disabled switch in the page says `class="switch
            // disabled"`, and the rule therefore never applied to it. Both spellings now.
            guard let track = Self.ruleBody(containingSelector: ".switch.disabled", in: source) else {
                Issue
                    .record(
                        "the design of record dims no .switch.disabled — the class spelling the markup uses"
                    )
                return
            }
            #expect(track.contains("background:var(--f3)"), ".switch.disabled drops the accent track")
            #expect(
                Self.ruleBody(containingSelector: ".switch.disabled .knob", in: source) != nil,
                "the knob is dimmed too, so the control has a foreground as well as a fill"
            )

            // `.segmented .seg[aria-pressed="true"]` had no disabled rule at all (DESIGN.md rule 4).
            #expect(
                Self.ruleBody(containingSelector: ".segmented .seg.disabled", in: source) != nil,
                "the segmented control carries a disabled state at all"
            )
        }

        /// The store page reproduced M31 on a shipped surface: its bare `.btn` **is** the
        /// accent-filled control, and `.btn[disabled]` dimmed it with `opacity:.45`, which keeps the
        /// accent under a tint — the treatment §3 refuses — and carried the `cursor:not-allowed`
        /// that §3 rule 8 does not license either.
        @Test("the store page dims its disabled primary to the ratified triple, and sets no cursor")
        func theStorePageDimsItsDisabledPrimary() throws {
            let url = try SheetShortcutScan.repoRoot()
                .appendingPathComponent("docs/mcp-router-store.html")
            let source = try String(contentsOf: url, encoding: .utf8)

            guard let body = Self.ruleBody(containingSelector: ".btn[disabled]", in: source) else {
                Issue.record("the store page has no .btn[disabled] rule")
                return
            }
            #expect(body.contains("background:var(--f3)"), "the store page's disabled .btn drops the accent")
            #expect(body.contains("color:var(--t4)"), "the store page's disabled .btn labels with --t4")
            #expect(!body.contains("opacity"), "a tinted accent is not the ratified treatment")
            #expect(!body.contains("cursor"), "§3 rule 8: a disabled control changes no cursor")
        }

        /// The sweep, run rather than described.
        ///
        /// The Swift assertions above name four controls each. This one has no list: it resolves
        /// every rule in both HTML surfaces that paints `var(--accent-ink)` and fails on any whose
        /// disabled state does not dim, so a *new* accent-filled control added later is covered
        /// without anybody remembering to add a case here.
        ///
        /// `planning/evidence/M31/arm-sweep.sh` is its presence control: six planted defects, one
        /// per failure verdict, each restored byte-identically by sha256.
        @Test("no surface in the repository draws a disabled control as though it were enabled")
        func theSweepFindsNoSurfaceDrawingADisabledAccentFill() throws {
            let root = try SheetShortcutScan.repoRoot()
            let sweep = root.appendingPathComponent("planning/evidence/M31/sweep-prominent-disabled.py")
            guard FileManager.default.fileExists(atPath: sweep.path) else {
                Issue.record("the M31 sweep is missing at \(sweep.path)")
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", sweep.path]
            process.currentDirectoryURL = root
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
            ) ?? ""
            process.waitUntilExit()
            #expect(
                process.terminationStatus == 0,
                "sweep-prominent-disabled.py exited \(process.terminationStatus):\n\(output)"
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

            // §3 refuses to tint the accent. A refusal with no number behind it is a position, so
            // the measured cost of the alternative is stated: --t4 on --accent-ink, both themes.
            #expect(design.contains("1.68:1 in light"), "--t4 on --accent-ink in light")
            #expect(design.contains("1.02:1 in dark"), "--t4 on --accent-ink in dark")

            // The rule binds the fill rather than the button, which is what makes the other four
            // accent-filled controls conformance failures rather than separate items.
            #expect(
                design.contains("Every control that resolves an accent fill"),
                "§3 generalises the treatment past the prominent button"
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
