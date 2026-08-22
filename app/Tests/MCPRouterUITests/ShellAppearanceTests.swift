#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The shell's appearance rules: what its colours may mean, what its content may be made of,
    /// how it moves, and what each accessibility setting removes.
    ///
    /// Several of these are *source-level* gates rather than rendered assertions, and that is
    /// deliberate — a rule like "no file uppercases a header" is a property of the whole surface,
    /// and checking it by rendering one view would leave the other eight unchecked.
    @Suite("Mac shell — appearance, motion and accessibility")
    struct ShellAppearanceTests {
        // MARK: - A12 · sentence case, and no transform to remove

        @Test("no shell file applies an uppercasing transform")
        func noUppercasingAnywhere() throws {
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(!source.contains(".uppercased()"), "\(file) upper-cases a string it renders")
                #expect(!source.contains("textCase(.uppercase)"), "\(file) tracks a header uppercase")
            }
        }

        @Test("the group headers are the sentence-case literals, not derived from the case name")
        func headersAreLiteralSentenceCase() {
            #expect(DestinationGroup.running.rawValue == "Running")
            #expect(DestinationGroup.library.rawValue == "Library")
        }

        // MARK: - A6 · the indicator colours do only their own job

        /// Each declared use is checked against `DESIGN.md`'s own wording for the token, so "it
        /// looked good there" cannot be spelled as a justification.
        @Test("every indicator colour the shell uses is justified by the document's own meaning")
        func indicatorUsesAreJustified() throws {
            let design = try ShellTestSupport.repoFile("DESIGN.md")
            let meanings: [ColorToken: String] = [
                .accent: "selection, focus, the one primary action",
                .live: "a child process is running",
                .attention: "wants a human decision",
                .fail: "failed or tripped"
            ]
            for (token, meaning) in meanings {
                #expect(design.contains(meaning), "DESIGN.md no longer states \(token.rawValue)'s meaning")
            }

            for use in ShellChrome.indicatorUses {
                let documented = try #require(meanings[use.token], "\(use.token) is not an indicator colour")
                #expect(
                    documented.contains(use.justification),
                    "'\(use.justification)' is not part of \(use.token.rawValue)'s documented meaning"
                )
            }
        }

        /// The other direction, which is the one that actually goes wrong: a token drawn somewhere
        /// the declaration does not mention.
        @Test("no shell file draws an indicator colour the declaration does not list")
        func noUndeclaredIndicatorUse() throws {
            let declared = ShellChrome.indicatorTokensUsed
            let indicators: [ColorToken] = [.accent, .live, .attention, .fail]
            for file in ShellTestSupport.gatedFiles {
                let source = try ShellTestSupport.repoFile(file)
                for token in indicators where source.contains("ColorToken.\(tokenCaseName(token))") {
                    #expect(
                        declared.contains(token),
                        "\(file) draws \(token.rawValue) but ShellChrome does not justify it"
                    )
                }
            }
            // `--fail` is now declared and drawn, and the reason is worth keeping next to the
            // assertion it replaced. The shell alone never had a failure to report: an offline
            // router has not failed, and painting *that* red would spend the token on absence. The
            // Servers board does have one — a placarded server is inoperative and a call that
            // errored did error — so the token is spent on exactly what §2 says it means.
            #expect(declared.contains(.fail))
            for use in ShellChrome.indicatorUses where use.token == .fail {
                #expect(use.justification == "failed or tripped")
            }
        }

        private func tokenCaseName(_ token: ColorToken) -> String {
            switch token {
            case .accent: "accent"
            case .live: "live"
            case .attention: "attention"
            case .fail: "fail"
            default: token.rawValue
            }
        }

        // MARK: - A8, A10 · opaque content, arrow cursor

        /// Every way SwiftUI or AppKit can put a translucent surface behind content.
        private static let materials = [
            "ultraThinMaterial", "thinMaterial", "regularMaterial",
            "thickMaterial", "ultraThickMaterial", "VisualEffectView"
        ]

        /// The files that draw **window content**, where §3.3 forbids glass outright.
        ///
        /// `Shell/` stopped being synonymous with "content" when M8 added the menu-bar popover.
        /// §3.3's rule has two halves — *"Liquid Glass on floating chrome only; content is
        /// opaque"* — and a check that scanned every shell file could only ever express the second.
        /// Excluding the popover here does not weaken the rule: it is the only floating surface in
        /// the module, it is named rather than pattern-matched, and `popoverIsGlassAndAdapts`
        /// below asserts the *first* half against it, which nothing did before.
        private static var contentFiles: [String] {
            ShellTestSupport.shellFiles.filter { !$0.hasSuffix("MenuBarPopover.swift") }
        }

        @Test("the window's content is an opaque token, never a material")
        func contentIsOpaque() throws {
            #expect(ShellChrome.contentBackground == .ground)
            for file in Self.contentFiles {
                let source = try ShellTestSupport.repoFile(file)
                for material in Self.materials {
                    #expect(
                        !source.contains(material),
                        "\(file) puts glass on content — §3.3 allows it on floating chrome only"
                    )
                }
            }
        }

        /// The other half of §3.3, which had no test until the app grew a floating surface.
        ///
        /// The popover is chrome, so it *should* be glass — and it must fall back to an opaque
        /// token under Reduce Transparency, which is the accessibility setting §7 names.
        @Test("the menu-bar popover is glass, and becomes opaque under Reduce Transparency")
        func popoverIsGlassAndAdapts() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Shell/MenuBarPopover.swift"
            )
            #expect(
                Self.materials.contains(where: source.contains),
                "the popover is floating chrome and draws no material — §3.3 permits glass here"
            )
            #expect(
                source.contains("accessibilityReduceTransparency"),
                "the popover's glass does not honour Reduce Transparency"
            )
            #expect(
                source.contains("ColorToken.panel.color"),
                "the popover has no opaque fallback to fall back *to*"
            )
        }

        @Test("no shell element sets a pointing-hand cursor")
        func cursorIsAlwaysTheArrow() throws {
            #expect(!ShellChrome.usesPointingHandCursor)
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(!source.contains("pointingHand"), "\(file) sets a web-content cursor")
                #expect(!source.contains(".pointerStyle(.link"), "\(file) sets a link pointer")
            }
        }

        // MARK: - A30, A31 · motion and the three accessibility settings

        @Test("row selection has no transition at all, not merely a fast one")
        func selectionIsImmediate() {
            #expect(ShellMotion.selectionAnimation() == nil)
        }

        @Test("a badge count change is a transform, and Reduce Motion removes it")
        func badgeBumpIsTransformOnly() {
            #expect(ShellMotion.badgeBump(reduceMotion: false) != nil)
            #expect(ShellMotion.badgeBump(reduceMotion: true) == nil)
            // A bump, not a leap: the scale is derived from two documented values.
            #expect(ShellMotion.badgeBumpScale > 1)
            #expect(ShellMotion.badgeBumpScale < 1.2)
        }

        /// The spring is the breaker's documented rise rather than a second one invented here.
        @Test("the bump reuses the design document's own spring")
        func bumpUsesTheDocumentedSpring() {
            #expect(BreakerGeometry.standard.riseDamping < 1)
            #expect(ShellMotion.badgeBumpHold == .milliseconds(
                Int(BreakerGeometry.standard.riseResponse * 1000)
            ))
        }

        @Test("no surface file animates opacity from zero on entry")
        func neverFadesInFromZero() throws {
            for file in ShellTestSupport.animatedSurfaceFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(
                    !source.contains(".opacity(0)") || file.hasSuffix("ScrollEdge.swift"),
                    "\(file) may fade content in from nothing"
                )
                #expect(
                    !source.contains(".transition(.opacity"),
                    "\(file) names the fade explicitly as its entry transition"
                )
                // And the spelling that survives every check above: a transform combined *with* an
                // opacity fade. The named helper is still there and its own definition is untouched,
                // so nothing else in this suite would notice.
                for line in source.split(separator: "\n") where line.contains(".transition(") {
                    let declaration = line.trimmingCharacters(in: .whitespaces)
                    #expect(
                        !line.contains("opacity"),
                        "\(file) combines opacity into an entry transition: \(declaration)"
                    )
                }
            }
        }

        /// The half the grep above structurally cannot see, and the half that was wrong.
        ///
        /// **An absent transition is not "no animation".** A `ForEach` row inside an animated
        /// container takes SwiftUI's *default* insertion transition, which is `.opacity` — so the
        /// row fades in from nothing while the file contains no opacity for a grep to find. That is
        /// exactly what `ActivityBoard` did, under a comment asserting it did not.
        ///
        /// So the rule is stated positively: a file that animates a collection must say how its
        /// members enter. Passing by declaring `.transition(.opacity)` — or by combining opacity
        /// into a transform — is closed off by the assertions above.
        ///
        /// **What this does not reach, stated rather than left to be discovered.** The
        /// `.animation(` precondition is an opt-out: a file that animates its list from *outside*
        /// itself, by moving the modifier to a parent or by wrapping the mutation in
        /// `withAnimation`, is skipped entirely while its rows still animate. Two files are skipped
        /// on that basis today — `ActivityFilterBar.swift` and `ActivityRow.swift`, neither of which
        /// animates a list. Closing it properly needs a Swift parse rather than a grep, and the
        /// per-board assertion in `ActivityBoardRulesTests` is what actually holds the shipped
        /// board's row to its transition.
        ///
        /// One exemption, named rather than pattern-matched, and its reason is asserted below so it
        /// cannot quietly stop being true.
        static let noRowsEverEnter = [
            // The sidebar's `ForEach`es are over `DestinationGroup.allCases` and
            // `Destination.inGroup(_:)`, both fixed at compile time — no row is ever inserted or
            // removed, so there is no entry to declare. Its `.animation` is the badge bump on a
            // child, not a list transition.
            "app/Sources/MCPRouterUI/Shell/Sidebar.swift"
        ]

        @Test("a file that animates a list declares how its rows enter")
        func animatedListsDeclareTheirEntryTransition() throws {
            for file in ShellTestSupport.animatedSurfaceFiles {
                guard !Self.noRowsEverEnter.contains(file) else { continue }
                let source = try ShellTestSupport.repoFile(file)
                guard source.contains("ForEach"), source.contains(".animation(") else { continue }
                // **After the `ForEach`, not merely somewhere in the file.** A whole-file grep
                // passes on a view that declares a transition for something else entirely — which
                // is not hypothetical: `ActivityBoard` carries `.transition(.move(edge: .trailing))`
                // on its inspector a hundred lines above the list, and that alone satisfied this
                // check while the rows themselves fell back to SwiftUI's default `.opacity`.
                let rows = try #require(source.range(of: "ForEach("))
                #expect(
                    source[rows.upperBound...].contains(".transition("),
                    """
                    \(file) animates a ForEach without declaring a transition on it, so its rows \
                    take SwiftUI's default .opacity and fade in from zero
                    """
                )
            }
        }

        /// The exemption's own premise. A sidebar whose rows became dynamic would need an entry
        /// transition like any other list, and would otherwise keep its pass for free.
        @Test("the exempt list is exempt for the reason given")
        func theExemptionsPremiseHolds() throws {
            for file in Self.noRowsEverEnter {
                let source = try ShellTestSupport.repoFile(file)
                let iterated = ["DestinationGroup.allCases", "Destination.inGroup("]
                for collection in iterated {
                    #expect(
                        source.contains("ForEach(\(collection)"),
                        "\(file) no longer iterates \(collection), so rows may now enter it"
                    )
                }
                // And nothing else: a second `ForEach` over something dynamic would sit under the
                // same exemption and inherit a pass it has not earned.
                //
                // **The count is `iterated.count` now and was `iterated.count + 1`.** The extra one
                // was the ungrouped tail's `ForEach(Destination.inGroup(nil))`, which M15 deleted
                // along with the Settings destination it held; `Destination.inGroup(` is still
                // iterated, once, inside the group section.
                #expect(
                    source.components(separatedBy: "ForEach(").count - 1 == iterated.count,
                    "\(file) gained a ForEach the exemption does not account for"
                )
            }
        }

        /// The value itself, so the rule survives the row being rewritten.
        ///
        /// `AnyTransition` is opaque and not `Equatable`, so there is nothing to compare at runtime
        /// — asserting `!= nil` on a non-optional would be a test that cannot fail. What is
        /// checkable is the declaration, and it is one function in one place precisely so that a
        /// four-line read is the whole of it.
        @Test("a row enters by transform, and Reduce Motion removes the movement not the row")
        func rowInsertionIsTransformOnly() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Activity/ActivityChrome.swift"
            )
            let body = try #require(
                source.components(separatedBy: "func rowInsertion(").last?
                    .components(separatedBy: "}").first
            )
            #expect(body.contains(".move(edge:"), "the row no longer enters by a transform")
            #expect(body.contains(".identity"), "Reduce Motion no longer removes the movement")
            #expect(!body.contains("opacity"), "the row's entry touches opacity")
        }

        /// Each setting removes the effect and keeps the information — which is the half that is
        /// easy to fail in the flattering direction.
        @Test("Reduce Transparency makes the sidebar opaque without removing the zone")
        func reduceTransparencyKeepsTheZone() {
            #expect(ShellAccessibilityRules.sidebarIsOpaque(reduceTransparency: true))
            #expect(!ShellAccessibilityRules.sidebarIsOpaque(reduceTransparency: false))
            #expect(ShellChrome.sidebarBackground == .panel)
            #expect(ShellChrome.sidebarBackground != ShellChrome.contentBackground)
        }

        @Test("Differentiate Without Colour gives the attention badge a glyph, and only that one")
        func differentiateWithoutColourAddsAGlyph() {
            #expect(ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: true, source: .serversNeedingAttention
            ))
            // The neutral badge needs nothing: it was never telling you anything by hue.
            #expect(!ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: true, source: .serversNeverUsed
            ))
            #expect(!ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: false, source: .serversNeedingAttention
            ))
        }

        @Test("Reduce Motion removes the bump and never the new count")
        func reduceMotionKeepsTheNumber() {
            #expect(!ShellAccessibilityRules.badgeAnimates(reduceMotion: true))
            #expect(ShellAccessibilityRules.badgeAnimates(reduceMotion: false))
            // The count is rendered by `BadgeView` whatever `animates` is — only the transform is
            // conditional, which is what "removes the effect, not the information" means here.
            #expect(ShellMotion.badgeBump(reduceMotion: true) == nil)
        }
    }
#endif
