#if os(macOS)
    import AppKit
    import SwiftUI
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M36 — what a disabled phone primary actually paints, read off the render.
    ///
    /// **A token name matching in source is a different claim from the pixel resolving to it.**
    /// `ButtonPaletteTests` asserts the decision; this asserts the consequence, because the two
    /// come apart in the ways that matter here: a fill token is composited against whatever ground
    /// it lands on, and `--f3` is 5% white in dark and 3% black in light rather than an opaque
    /// value. What §3 ratifies is a *drawn* result, so the oracle is a drawn one.
    ///
    /// The comparison is against a swatch rendered in the same appearance in the same test rather
    /// than against a hex literal. That is deliberate: a literal would encode this run's appearance
    /// resolution as well as the token, and an assertion that fails when the harness resolves a
    /// different appearance is measuring the harness. Two renders of the same token must agree
    /// whatever the appearance turns out to be.
    ///
    /// **The subject is macOS, and the control ships on iOS.** `PhoneProminentButtonStyle` is not
    /// platform-gated and renders here; both platforms build the colour from the same
    /// `ColorToken.value(dark:increasedContrast:)`, differing only in whether an `NSColor` or a
    /// `UIColor` carries it. So this measures token resolution and compositing, not the iOS trait
    /// environment — that half is `PhoneSurfaceTests`' lane and is named as unmeasured here rather
    /// than assumed.
    @MainActor
    @Suite("A disabled phone primary, read off the render")
    struct PhoneProminentDisabledRenderTests {
        /// A pixel, as the three sRGB channels a comparison can be made on.
        struct Pixel: Equatable, CustomStringConvertible {
            let r: Int, g: Int, b: Int
            var description: String { String(format: "#%02X%02X%02X", r, g, b) }

            /// Two renders of the same token, sampled a pixel apart, are not bit-identical after
            /// antialiasing and colour management. Three levels is well inside the 8 that separate
            /// the two candidate fills in the light appearance, and inside the 5 in dark.
            func matches(_ other: Pixel) -> Bool {
                abs(r - other.r) <= 3 && abs(g - other.g) <= 3 && abs(b - other.b) <= 3
            }
        }

        private static let width = 240.0
        private static let height = 72.0

        /// Rasterises a view and returns a reader over its pixels.
        ///
        /// `ImageRenderer` rather than `drawHierarchy`, for the reason `PhoneSurfaceTests` records:
        /// SwiftUI draws a `ButtonStyle`'s background into its own backing layers, and
        /// `drawHierarchy` over an off-screen window came back a single flat colour — an instrument
        /// that reports one colour for every subject cannot distinguish two fills.
        static func render(_ view: some View, in scheme: ColorScheme) throws -> (Int, Int) -> Pixel {
            let renderer = ImageRenderer(
                content: view
                    .frame(width: Self.width, height: Self.height)
                    .environment(\.colorScheme, scheme)
            )
            renderer.scale = 1
            let image = try #require(renderer.cgImage, "the view did not rasterise")
            let w = image.width, h = image.height
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return { x, y in
                let i = (y * w + x) * 4
                return Pixel(r: Int(pixels[i]), g: Int(pixels[i + 1]), b: Int(pixels[i + 2]))
            }
        }

        /// The button over the ground it sits on, full width so the sample point is inside the fill.
        static func button(disabled: Bool) -> some View {
            ZStack {
                ColorToken.ground.color
                Button("Continue", action: {})
                    .buttonStyle(PhoneProminentButtonStyle(fillsWidth: true))
                    .disabled(disabled)
            }
        }

        /// One token composited over the same ground, as the thing the render is compared against.
        static func swatch(_ token: ColorToken) -> some View {
            ZStack {
                ColorToken.ground.color
                Rectangle().fill(token.color)
            }
        }

        /// Inside the fill, past the corner radius, and clear of the centred label glyphs.
        /// Sampling the centre was tried first on `PhoneSurfaceTests` and read the label's white.
        private static let fillSample = (x: 8, y: Int(height / 2))

        /// The bezel is one hairline in from the control's left edge at its vertical centre, where
        /// the rounded rect is at its widest and the stroke is horizontal.
        private static let bezelSample = (x: 0, y: Int(height / 2))

        @Test("the disabled fill lands on --f3, in both appearances", arguments: [ColorScheme.dark, .light])
        func theDisabledFillIsF3(scheme: ColorScheme) throws {
            let drawn = try Self.render(Self.button(disabled: true), in: scheme)
            let f3 = try Self.render(Self.swatch(.f3), in: scheme)
            let raised = try Self.render(Self.swatch(.raised), in: scheme)

            let fill = drawn(Self.fillSample.x, Self.fillSample.y)
            let ratified = f3(Self.fillSample.x, Self.fillSample.y)
            let previous = raised(Self.fillSample.x, Self.fillSample.y)

            let wrongFill = "a disabled phone primary painted \(fill) in \(scheme); `DESIGN.md` §3 "
                + "ratifies --f3, which composites to \(ratified) on this ground"
            #expect(fill.matches(ratified), "\(wrongFill)")
            #expect(
                !fill.matches(previous),
                "the disabled fill still paints --raised (\(previous)) — the token M36 was filed for"
            )
        }

        /// The half that makes the fix visible rather than merely correct.
        ///
        /// In the light appearance `--raised` is `#FFFFFF` and so is `--ground`, so the control
        /// this style drew before M36 had neither a fill anybody could see nor an edge. §3 rule 4
        /// is *"Disabled dims in place and never disappears"*, and `--f3` alone does not rescue
        /// that on its own — it composites to `#F7F7F7`, eight levels off white — so the `--line`
        /// bezel is what carries the boundary.
        ///
        /// **Two assertions rather than one, because the obvious one cannot fail.** "The edge
        /// differs from the ground" is already true of a bezel-less `--f3` control by those eight
        /// levels, so on its own it would pass over a control with no bezel at all — the state this
        /// style shipped in. The second names the bezel: the edge must differ from the *fill* too,
        /// which is only true when something is stroked there.
        @Test("the disabled control keeps a drawn edge", arguments: [ColorScheme.dark, .light])
        func theDisabledControlIsStillVisible(scheme: ColorScheme) throws {
            let drawn = try Self.render(Self.button(disabled: true), in: scheme)
            let ground = drawn(1, 1)
            let bezel = drawn(Self.bezelSample.x, Self.bezelSample.y)
            let fill = drawn(Self.fillSample.x, Self.fillSample.y)

            let vanished = "the disabled control's edge painted \(bezel) against a \(ground) ground "
                + "in \(scheme), so the control disappeared rather than dimming in place (§3.4)"
            #expect(!bezel.matches(ground), "\(vanished)")
            let unbezelled = "the control's edge painted \(bezel) and its fill \(fill) in \(scheme), "
                + "so nothing is stroked there and §3's --line bezel is missing"
            #expect(!bezel.matches(fill), "\(unbezelled)")
        }

        /// The live state, asserted so the fix cannot be "both states dim".
        ///
        /// This is `ButtonPaletteTests.theTwoStatesAreDistinguishable` at the pixel: what went
        /// wrong on the Mac was two states painting the same thing, and a disabled treatment that
        /// swallowed the live one would satisfy every assertion above.
        @Test("a live phone primary still paints its accent fill", arguments: [ColorScheme.dark, .light])
        func theLiveFillIsTheAccent(scheme: ColorScheme) throws {
            let live = try Self.render(Self.button(disabled: false), in: scheme)
            let accent = try Self.render(Self.swatch(.accent), in: scheme)
            let off = try Self.render(Self.button(disabled: true), in: scheme)

            let drawn = live(Self.fillSample.x, Self.fillSample.y)
            #expect(
                drawn.matches(accent(Self.fillSample.x, Self.fillSample.y)),
                "a live phone primary painted \(drawn) rather than the accent fill in \(scheme)"
            )
            #expect(
                !drawn.matches(off(Self.fillSample.x, Self.fillSample.y)),
                "the two states paint the same fill in \(scheme)"
            )
        }
    }
#endif
