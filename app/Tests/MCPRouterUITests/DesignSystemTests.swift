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

/// The icon set, checked against the thing that actually goes wrong.
///
/// An unknown SF Symbol name does not throw and does not fail to build — it renders **nothing at
/// all**. So "the mapping returns a non-empty string" is a check that stays green while the icon is
/// invisible, which is why every name is resolved against the system symbol table here instead.
@Suite("Icons")
struct IconTests {
    @Test("the set is the prototype's 21-symbol sprite, exactly")
    func inventoryMatchesTheSprite() {
        #expect(Icon.allCases.count == 21)
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
}

/// The colour binding, checked at the value level.
///
/// The dynamic colour itself cannot be resolved without a live trait collection, so what is testable
/// — and what actually carries the risk — is that the two appearances are selected correctly and
/// that the hex decoder does not quietly answer black.
@Suite("Colour binding")
struct ColorBindingTests {
    @Test("each appearance selects its own authored pair")
    func componentsFollowTheScheme() {
        for token in ColorToken.allCases {
            let dark = token.components(for: .dark)
            let light = token.components(for: .light)
            #expect(dark.hex == token.hex)
            #expect(dark.opacity == token.opacity)
            #expect(light.hex == token.lightHex)
            #expect(light.opacity == token.lightOpacity)
        }
    }

    @Test("hex decoding handles both cases and rejects malformed input")
    func hexDecoding() {
        let white = rgbChannels(of: "#FFFFFF")
        #expect(white?.r == 1 && white?.g == 1 && white?.b == 1)
        let ground = rgbChannels(of: "1E1E1E")
        #expect(ground?.r == Double(0x1E) / 255)
        #expect(rgbChannels(of: "#0091ff")?.b == 1)
    }

    /// A colour that silently becomes black is the same class of quiet-wrong-answer the router's
    /// own decoding rules forbid, so a malformed value must be distinguishable rather than plausible.
    @Test("a malformed hex is nil, not black")
    func malformedHexIsNotBlack() {
        #expect(rgbChannels(of: "#GGGGGG") == nil)
        #expect(rgbChannels(of: "#FFF") == nil)
        #expect(rgbChannels(of: "") == nil)
    }
}

/// The type binding.
@Suite("Type binding")
struct TypeBindingTests {
    /// SwiftUI's `lineSpacing` is the gap *between* lines, so the document's line height has to have
    /// the font's own line height taken off it. A negative value would tighten text below the ladder
    /// rather than match it, which is why it is clamped — and why the clamp is checked.
    @Test("leading is the documented line height minus the font's own, never negative")
    func leadingIsNonNegative() {
        for token in TypeToken.allCases {
            #expect(token.lineSpacing >= 0, "\(token.rawValue) computed a negative leading")
            #expect(token.lineSpacing == max(0, token.lineHeight - token.size * 1.2))
        }
    }

    @Test("emphasis maps to the documented weight, and nothing is lighter than semibold")
    func weightsMatchTheDocument() {
        #expect(TypeToken.largeTitle.weight == .bold)
        #expect(TypeToken.body.weight == .semibold)
        for token in TypeToken.allCases {
            #expect([Font.Weight.bold, .semibold].contains(token.weight))
        }
    }
}

/// The control ladder and the chrome that reads from it.
@Suite("Controls")
struct ControlTests {
    @Test("the five rungs take their heights from MetricToken, in order")
    func ladderMatchesTheTokens() {
        #expect(ControlScale.allCases.count == 5)
        let heights = ControlScale.allCases.map(\.height)
        #expect(heights == [16, 20, 24, 28, 36])
        #expect(heights == MetricToken.controlLadder.map(\.leadingScalar))
        #expect(heights == heights.sorted(), "the ladder is not in ascending order")
    }

    /// §3.5: hierarchy comes from label tiers and weight, never from size inflation — so every
    /// control label has to sit on the eight-role ramp.
    @Test("every rung's label role is on the ramp")
    func labelRolesAreOnTheRamp() {
        for scale in ControlScale.allCases {
            #expect(TypeToken.allCases.contains(scale.labelRole))
        }
    }

    @Test("selection and focus geometry come from the document, not from the view")
    func chromeGeometryIsTokenised() {
        #expect(MetricToken.selectionRadius.leadingScalar == 8)
        #expect(MetricToken.selectionInset.leadingScalar == 4)
        #expect(MetricToken.focusRing.leadingScalar == 2)
    }
}

/// The nine states, and the copy they carry.
///
/// The strings are asserted verbatim because they are the deliverable: `DESIGN.md` §5 requires real
/// wording for the unhappy paths, and a test that only checked "the title is non-empty" would stay
/// green through a regression to "Error".
@Suite("The nine states")
struct SurfaceStateTests {
    @Test("all nine states exist")
    func nineStates() {
        #expect(SurfaceState.allCases.count == 9)
    }

    @Test("the offline state names the real cause and offers the real fix")
    func offlineIsFirstClass() {
        let offline = ServersBoardCopy.offline
        #expect(offline.title == "The router is not running")
        #expect(offline.detail.contains("127.0.0.1"))
        #expect(offline.actionLabel == "Start the router")
        // The failure this guards: rendering it as a generic network error. Loopback cannot be
        // "offline" in the network sense, so the words must not say so.
        #expect(!offline.detail.lowercased().contains("network"))
        #expect(!offline.title.lowercased().contains("connection"))
    }

    @Test("every unhappy state says what happened and what to do")
    func unhappyStatesAreActionable() {
        let messages = [
            ServersBoardCopy.empty, ServersBoardCopy.partial,
            ServersBoardCopy.error, ServersBoardCopy.offline
        ]
        for message in messages {
            #expect(!message.title.isEmpty)
            #expect(message.detail.count > 40, "'\(message.title)' has placeholder-length copy")
            #expect(message.actionLabel != nil, "'\(message.title)' offers nothing")
        }
    }

    /// §6: buttons are verb-first and name the action; `…` means "opens a further view".
    @Test("action labels are verb-first and sentence case")
    func actionLabelsFollowTheWordRules() {
        #expect(ServersBoardCopy.empty.actionLabel == "Add server…")
        #expect(ServersBoardCopy.partial.actionLabel == "Show the two")
        #expect(ServersBoardCopy.error.actionLabel == "Reveal in Finder")
        let messages = [
            ServersBoardCopy.empty, ServersBoardCopy.partial,
            ServersBoardCopy.error, ServersBoardCopy.offline
        ]
        for message in messages {
            let label = message.actionLabel ?? ""
            #expect(!["OK", "Submit", "Continue"].contains(label), "'\(label)' names no action")
        }
    }

    @Test("the disabled reason explains rather than blames")
    func disabledReasonIsDiscoverable() {
        let reason = ServersBoardCopy.disabledReason
        #expect(reason.contains("Available once"))
        #expect(!reason.lowercased().contains("you cannot"))
    }

    /// The skeleton has to match the populated row exactly or the board jumps when data lands.
    @Test("the loading skeleton and the populated row share one height")
    func skeletonMatchesTheRealRow() {
        #expect(MetricToken.serversRow.leadingScalar == 56)
        // And the row is tall enough to carry the breaker it exists to carry.
        #expect(MetricToken.serversRow.leadingScalar >= BreakerGeometry.standard.housingHeight)
    }

    @Test("the overflow name is long enough to actually truncate")
    func overflowNameTruncates() {
        #expect(ServersBoardCopy.longServerName.count > 40)
    }
}

/// The gallery's own shape, so the reference surface cannot lose a section silently.
///
/// `@MainActor` because everything it reaches is nested inside a SwiftUI `View`, which Swift 6
/// isolates to the main actor. Annotating the suite is the honest fix; making the identifier
/// `nonisolated` to dodge it would be lowering isolation to satisfy a test.
@Suite("Design gallery")
@MainActor
struct DesignGalleryTests {
    @Test("six sections, and every one has an icon from the closed set")
    func sixSections() {
        #expect(DesignGallery.Section.allCases.count == 6)
        for section in DesignGallery.Section.allCases {
            #expect(Icon.allCases.contains(section.icon))
        }
    }

    @Test("the appearance switch offers system plus both authored appearances")
    func threeAppearances() {
        #expect(DesignGallery.Appearance.allCases.count == 3)
        #expect(DesignGallery.Appearance.system.colorScheme == nil)
        #expect(DesignGallery.Appearance.dark.colorScheme == .dark)
        #expect(DesignGallery.Appearance.light.colorScheme == .light)
    }

    /// The acceptance harness greps a Release binary for this string. If it ever became a computed
    /// or interpolated value it would stop appearing as a literal in either binary, and the
    /// absence-from-Release assertion would pass for the wrong reason.
    @Test("the gallery identifier is a stable literal the harness can grep")
    func identifierIsGreppable() {
        #expect(DesignGallery.galleryIdentifier == "mcprouter-design-gallery")
    }
}
