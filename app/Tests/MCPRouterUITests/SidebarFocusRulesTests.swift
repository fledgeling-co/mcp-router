#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// A24's decision: when the sidebar shows a focus ring.
    ///
    /// **The clause was measured unmet before this existed**, which is why the suite is here rather
    /// than folded into the shell's other appearance tests. Driven against the running app on
    /// 2026-08-14: keyboard focus was moved to the sidebar over the accessibility API — the outline's
    /// `AXFocused` went 0 → 1, confirmed in the tree — and window-scoped captures before and after
    /// were **byte-identical**. Nothing on screen said where the keyboard was. The selected row was
    /// accent-tinted either way, so there was not even a weak signal to argue about.
    ///
    /// The rendered half now lives in `scripts/acceptance/mac-shell.sh`, which measures accent pixels
    /// on the selected row with the sidebar unfocused and focused. This is the half that decides.
    @Suite("Sidebar focus ring")
    struct SidebarFocusRulesTests {
        @Test("the ring is on the selected row while the sidebar holds the keyboard")
        func selectedAndFocused() {
            #expect(SidebarFocusRules.showsFocusRing(isSelected: true, isSidebarFocused: true))
        }

        @Test("an unselected row never rings, focused or not")
        func unselectedNeverRings() {
            #expect(!SidebarFocusRules.showsFocusRing(isSelected: false, isSidebarFocused: true))
            #expect(!SidebarFocusRules.showsFocusRing(isSelected: false, isSidebarFocused: false))
        }

        /// The half that would be easy to get wrong in the flattering direction: a ring that stays
        /// after focus leaves still *looks* like focus is visible, and is a claim that the keyboard
        /// is somewhere it is not.
        @Test("the ring goes when focus leaves the sidebar")
        func focusLeavingClearsTheRing() {
            #expect(!SidebarFocusRules.showsFocusRing(isSelected: true, isSidebarFocused: false))
        }

        /// The ring must be the design system's, not a number this item chose. The width and colour
        /// come from F2's `focusRing` modifier — `MetricToken.focusRing` and `ColorToken.accent` —
        /// and the raw-values lint already forbids a literal; this asserts the modifier is the one
        /// actually applied, which the lint cannot see.
        ///
        /// The second half used to be `!source.contains("MetricToken.focusRing")`, which failed
        /// against correct code: a whole-file substring search matches this rule's own explanatory
        /// comments, and it matches `badgeBumpScale`, which legitimately derives a ratio from the
        /// ring against a control rung and draws nothing. What the rule actually forbids is the row
        /// *drawing* its own ring, so assert the absence of the primitives that would do it — a
        /// claim that can genuinely fail, rather than one that fires on prose.
        @Test("the row applies F2's focus ring rather than drawing its own")
        func theRingIsTheDesignSystems() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            #expect(source.contains(".focusRing(showsFocusRing"))
            for primitive in ["lineWidth", ".stroke(", ".border("] {
                #expect(!source.contains(primitive), "the row draws its own ring with \(primitive)")
            }
        }
    }
#endif
