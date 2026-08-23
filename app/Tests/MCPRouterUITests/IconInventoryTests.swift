#if canImport(AppKit)
    import AppKit
#endif
#if canImport(UIKit)
    import UIKit
#endif
import MCPRouterKit
import SwiftUI
import Testing
@testable import MCPRouterUI

// The icon set, checked against the thing that actually goes wrong.
//
// An unknown SF Symbol name does not throw and does not fail to build — it renders **nothing at
// all**. So "the mapping returns a non-empty string" is a check that stays green while the icon is
// invisible, which is why every name is resolved against the system symbol table here instead.
// Split out of DesignSystemTests.swift on 2026-08-23, when merging M16 and M22 took that file to
// 407 lines against `swiftlint --strict`'s inherited 400-line default. The five suites there are
// independent, and Icons is the one both items touched — so the cut follows the subject rather
// than the line count. Nothing in the assertions changed; the summands and every `contains` row
// arrive here exactly as the merge resolved them.

@Suite("Icons")
struct IconTests {
    /// The prototype's sprite is 21 symbols and remains the inventory's base. `frost` is the one
    /// addition, and it is here rather than in the sprite because the prototype marks a cold start
    /// with `❄` — a unicode character, which `DESIGN.md` §4 forbids ("drawn, never unicode"). The
    /// count is stated as base-plus-additions rather than as a bare 22 so that a symbol appearing
    /// without a reason still fails.
    ///
    /// M8's popover draws the same mark and arrived with its own case for it. A bare `== 22` could
    /// not tell that apart from the one addition this comment justifies, which is the argument for
    /// spelling the sum out: the duplicate was removed and the popover reuses `frost`.
    ///
    /// M22 adds the second named term. The console mock draws two destinations the prototype's
    /// sprite never had — Harnesses and Insights — so their glyphs are additions to the *sprite*
    /// rather than to the unicode replacements, and giving them their own term keeps the sum
    /// readable as a claim: 21 from one source, 1 replacing a character, 2 from the other.
    @Test("the set is the prototype's 21-symbol sprite plus the marks the document required drawn")
    func inventoryMatchesTheSprite() {
        let spriteSymbols = 21
        let drawnReplacementsForUnicode = 1 // frost, replacing the prototype's ❄
        // Each surface's additions stay a separate summand: a merged constant could not tell an
        // arrow apart from a destination, and every item stays answerable for what it added.
        let consoleMockAdditions = 1 // M16 — flow, the Signal Path rail's arrow
        let consoleMockDestinations = 2 // M22 — harness and insights, never in the sprite
        #expect(
            Icon.allCases.count
                == spriteSymbols + drawnReplacementsForUnicode
                + consoleMockAdditions + consoleMockDestinations
        )
        #expect(Icon.allCases.contains(.frost))
        #expect(Icon.allCases.contains(.flow))
        #expect(Icon.allCases.contains(.harness))
        #expect(Icon.allCases.contains(.insights))
    }

    @Test("every system icon resolves to a symbol that actually draws")
    func systemSymbolsResolve() {
        for icon in Icon.allCases {
            guard let name = icon.systemName else { continue }
            #expect(!name.isEmpty, "\(icon.rawValue) maps to an empty symbol name")
            #if canImport(AppKit)
                let drawn = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
            #elseif canImport(UIKit)
                let drawn = UIImage(systemName: name) != nil
            #else
                let drawn = false
            #endif
            #expect(drawn, "\(icon.rawValue) → '\(name)' is not a real SF Symbol; it renders blank")
        }
    }

    /// `DESIGN.md` §4 permits an authored asset exactly where no symbol fits, and forbids standing a
    /// decorative shape in for one. Exactly one icon takes that route.
    @Test("the product's own mark is authored rather than approximated")
    func conduitIsAuthored() {
        #expect(Icon.conduit.isAuthored)
        #expect(Icon.allCases.filter(\.isAuthored) == [.conduit])
    }

    /// §9: a never-used server was never deleted, so Cleanup does not use a trash metaphor. This is
    /// a product decision that a later contributor would otherwise "fix" toward the obvious icon.
    @Test("cleanup does not use a trash metaphor")
    func cleanupIsNotABin() {
        let name = Icon.cleanup.systemName ?? ""
        #expect(!name.contains("trash"))
        #expect(!name.contains("bin"))
    }

    /// The authored icon, held to the same standard as the system ones.
    ///
    /// `systemSymbolsResolve` skips every authored icon by construction — `guard let name =
    /// icon.systemName else { continue }` — so the one icon this project draws itself was the one
    /// icon nothing checked. An empty `path(in:)` renders exactly like a wrong SF Symbol name: an
    /// invisible icon and a green suite.
    @Test("the authored mark actually draws something")
    func conduitMarkDraws() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ConduitMark().path(in: box)
        #expect(!path.isEmpty, "ConduitMark draws nothing — it would render as a blank square")

        // And it fills the frame it is given rather than being a dot in a corner: the mark is two
        // runs converging into one, so it has to span most of both axes to read as that.
        let bounds = path.boundingRect
        #expect(bounds.width >= box.width * 0.6, "the mark spans \(bounds.width) of 100 horizontally")
        #expect(bounds.height >= box.height * 0.5, "the mark spans \(bounds.height) of 100 vertically")
    }
}

// The colour binding, checked at the value level.
//
// The dynamic colour itself cannot be resolved without a live trait collection, so what is testable
// — and what actually carries the risk — is that the two appearances are selected correctly and
// that the hex decoder does not quietly answer black.
