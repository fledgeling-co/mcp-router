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

    /// The second axis, which the binding gained when the palette did.
    ///
    /// The four contexts are authored in the kit and the nine overriding tokens are checked there;
    /// what is checked here is the *selection* — that asking for increased contrast returns the
    /// increased-contrast pair rather than the base one. A binding that quietly ignored the
    /// argument would leave the accessibility half of the palette authored, tested and unreachable,
    /// which reads on screen exactly like a palette that has no such half.
    @Test("the increased-contrast axis selects the authored contrast pair, not the base one")
    func componentsFollowTheContrastSetting() {
        for token in ColorToken.allCases {
            #expect(token.components(for: .dark, increasedContrast: true).hex == token.contrastHex)
            #expect(
                token.components(for: .dark, increasedContrast: true).opacity == token.contrastOpacity
            )
            #expect(
                token.components(for: .light, increasedContrast: true).hex == token.lightContrastHex
            )
            #expect(
                token.components(for: .light, increasedContrast: true).opacity
                    == token.lightContrastOpacity
            )
        }
        // And the axis actually moves something: at least one token must differ, or this whole
        // test would pass against a binding that returned the base pair for every argument.
        let moved = ColorToken.allCases.filter {
            $0.components(for: .dark, increasedContrast: true).hex != $0.components(for: .dark).hex
                || $0.components(for: .dark, increasedContrast: true).opacity
                != $0.components(for: .dark).opacity
        }
        #expect(moved.count == 9, "\(moved.count) tokens move under increased contrast, expected 9")
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

    /// The copy itself, verbatim.
    ///
    /// The length check above is a floor, not a check: it passes for any forty-one characters, so
    /// `partial.detail` could become unrelated prose and stay green. The spec fixes this wording —
    /// it is the deliverable, not an illustration of one — so it is asserted exactly, the way
    /// `offline` already was.
    @Test("the empty, partial and error states carry the specified wording")
    func copyIsVerbatim() {
        #expect(ServersBoardCopy.empty.title == "No servers declared yet")
        #expect(ServersBoardCopy.empty.detail == """
        MCP Router reads the servers your agents already have configured. \
        Point it at a config, or declare one by hand.
        """)

        #expect(ServersBoardCopy.partial.title == "6 of 8 servers loaded")
        #expect(ServersBoardCopy.partial.detail == """
        Two entries name a transport this version does not read. \
        The other six are live and usable.
        """)

        #expect(ServersBoardCopy.error.title == "Could not read servers.json")
        #expect(ServersBoardCopy.error.detail == """
        The file is there but line 12 is not valid JSON, so nothing was loaded rather than \
        some of it. Fix the line and it will reload on its own.
        """)

        // The error names the line and says it will recover on its own — §6 requires an error to
        // state what happened *and* what happens next, and "line 12" is the part that makes it
        // actionable rather than sympathetic.
        #expect(ServersBoardCopy.error.detail.contains("line 12"))
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
        // And the row is tall enough to carry what it exists to carry.
        //
        // **The floor moved with the signature.** It was the breaker's 48pt housing until M16
        // retired the lever; a row leading with an 8pt plug would clear that trivially, so keeping
        // it would have left an assertion that reads like a constraint and cannot fail. What sets
        // the height now is the two-line name block, which is the thing the loading skeleton has to
        // reproduce exactly or the board jumps when the data lands.
        #expect(
            MetricToken.serversRow.leadingScalar
                >= TypeToken.body.lineHeight + TypeToken.caption.lineHeight
        )
        #expect(MetricToken.serversRow.leadingScalar >= SignalPathGeometry.standard.rowPlugDiameter)
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

    /// Each section carries its own identifier, so the harness can name what it is looking at.
    ///
    /// The root identifier alone only proves *a* gallery opened. Six distinct section identifiers
    /// are what let an acceptance assertion say which panel it sampled — and deriving them from the
    /// case means a seventh section cannot arrive without one.
    @Test("every section has its own stable identifier")
    func sectionIdentifiersAreDistinct() {
        let identifiers = DesignGallery.Section.allCases.map(DesignGallery.identifier(for:))
        #expect(Set(identifiers).count == DesignGallery.Section.allCases.count)
        #expect(identifiers.allSatisfy { $0.hasPrefix("gallery-section-") })
        #expect(identifiers.contains("gallery-section-signal path"))
        // Distinct from the root, or a grep for one would match the other.
        #expect(!identifiers.contains(DesignGallery.galleryIdentifier))
    }

    /// The nine states reach the gallery through the enum rather than through nine hand-placed
    /// blocks, so the section cannot render eight of them.
    @Test("every state has a title, and the set rendered is the whole set")
    func everyStateIsTitledAndRendered() {
        let titles = SurfaceState.allCases.map { StateSection.title(for: $0) }
        #expect(titles.count == 9)
        #expect(Set(titles).count == 9, "two states share a title — one of them is mislabelled")
        #expect(titles.allSatisfy { !$0.isEmpty })
    }
}
