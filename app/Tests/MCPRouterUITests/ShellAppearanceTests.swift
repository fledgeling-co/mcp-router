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

        @Test("the window's content is an opaque token, never a material")
        func contentIsOpaque() throws {
            #expect(ShellChrome.contentBackground == .ground)
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                for material in Self.materials {
                    #expect(
                        !source.contains(material),
                        "\(file) puts glass on content — §3.3 allows it on floating chrome only"
                    )
                }
            }
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

        @Test("no shell file animates opacity from zero on entry")
        func neverFadesInFromZero() throws {
            for file in ShellTestSupport.shellFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(
                    !source.contains(".opacity(0)") || file.hasSuffix("ScrollEdge.swift"),
                    "\(file) may fade content in from nothing"
                )
            }
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
