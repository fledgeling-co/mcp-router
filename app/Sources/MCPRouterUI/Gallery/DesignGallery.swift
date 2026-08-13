#if DEBUG

    import MCPRouterKit
    import SwiftUI

    /// The design system, rendered.
    ///
    /// Debug-only, and deliberately: it is a reference surface for whoever is building the next
    /// screen, not a feature. `DESIGN.md` §10 records that the breaker's motion has never been
    /// observed running — the prototype animates nothing — so the breaker section carries a real
    /// toggle, and the appearance switch exists because "light is authored" is a claim nobody could
    /// check without changing their machine's setting.
    ///
    /// The `#if DEBUG` wrapper is load-bearing rather than tidy: the acceptance harness asserts that
    /// `galleryIdentifier` does not appear in a Release binary, so this surface cannot quietly ship.
    public struct DesignGallery: View {
        /// The one string the acceptance harness greps for, in both directions — present in the
        /// running Debug app's accessibility tree, absent from the Release binary.
        public static let galleryIdentifier = "mcprouter-design-gallery"

        public enum Section: String, CaseIterable, Identifiable, Sendable {
            case colour = "Colour"
            case type = "Type"
            case icons = "Icons"
            case controls = "Controls"
            case breaker = "Breaker"
            case states = "States"

            public var id: String { rawValue }

            var icon: Icon {
                switch self {
                case .colour: .layers
                case .type: .book
                case .icons: .compass
                case .controls: .settings
                case .breaker: .bolt
                case .states: .list
                }
            }
        }

        /// Which appearance the panel is forced into. `system` follows the machine, which is the
        /// honest default; the other two exist so both authored appearances can be compared without
        /// anyone changing a system setting mid-review.
        public enum Appearance: String, CaseIterable, Identifiable, Sendable {
            case system = "System"
            case dark = "Dark"
            case light = "Light"

            public var id: String { rawValue }

            var colorScheme: ColorScheme? {
                switch self {
                case .system: nil
                case .dark: .dark
                case .light: .light
                }
            }
        }

        @State private var selection: Section = .colour
        @State private var appearance: Appearance = DesignGallery.launchAppearance()

        public init() {}

        /// The appearance to open in, taken from a launch argument when one is present.
        ///
        /// A test seam, and a deliberately visible one. Acceptance criterion 1 requires evidence
        /// that the **light** appearance actually reaches the screen — not that its values exist,
        /// which the parity suite already proves. The only ways to get that evidence from outside
        /// the process are to change the machine's system setting, or to drive a segmented control
        /// through the accessibility API. The first is not something a gate may do to a developer's
        /// machine; the second turns a colour assertion into a bet on AppleScript finding a
        /// SwiftUI picker's segments, which fails in a way that looks like the colour being wrong.
        ///
        /// So the harness passes `--gallery-appearance light`. This lives inside the `#if DEBUG`
        /// gallery, so it is absent from a Release binary along with everything else here.
        static func launchAppearance() -> Appearance {
            let arguments = ProcessInfo.processInfo.arguments
            guard let flag = arguments.firstIndex(of: "--gallery-appearance"),
                  arguments.index(after: flag) < arguments.endIndex
            else { return .system }
            let requested = arguments[arguments.index(after: flag)].lowercased()
            return Appearance.allCases.first { $0.rawValue.lowercased() == requested } ?? .system
        }

        public var body: some View {
            #if os(macOS)
                NavigationSplitView {
                    sidebar
                        .navigationSplitViewColumnWidth(MetricToken.sidebar.leadingScalar)
                } detail: {
                    detail
                }
                .accessibilityIdentifier(Self.galleryIdentifier)
            #else
                NavigationStack {
                    List(Section.allCases) { section in
                        NavigationLink(section.rawValue) {
                            detailBody(for: section)
                                .navigationTitle(section.rawValue)
                        }
                    }
                    .navigationTitle("Design system")
                    .toolbar { appearancePicker }
                }
                .preferredColorScheme(appearance.colorScheme)
                .accessibilityIdentifier(Self.galleryIdentifier)
            #endif
        }

        // MARK: - Chrome

        // Both of these are macOS-only. Their bodies are still type-checked on iOS if left
        // unguarded, and `List(_:selection:)` with a non-optional selection does not exist there —
        // so the guard is what keeps the phone build honest rather than what hides a problem.
        #if os(macOS)
            private var sidebar: some View {
                // Sentence case, secondary colour, no tracked uppercase (§3 rule 2).
                List(Section.allCases, selection: $selection) { section in
                    Label {
                        Text(section.rawValue).typeRole(.body)
                    } icon: {
                        IconView(section.icon)
                    }
                    .tag(section)
                }
                .navigationTitle("Design system")
            }

            private var detail: some View {
                detailBody(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(ColorToken.ground.color)
                    .preferredColorScheme(appearance.colorScheme)
                    // The window keeps ONE name and the section rides in the subtitle. Setting the
                    // title to the selection renamed the window as you clicked around — so the
                    // Window menu offered "Design system", and the window it opened was called
                    // "Colour". A window you cannot find again in the menu that opened it is the
                    // failure; the subtitle is where macOS puts this kind of context anyway.
                    .navigationTitle("Design system")
                    .navigationSubtitle(selection.rawValue)
                    .toolbar { appearancePicker }
            }
        #endif

        @ToolbarContentBuilder private var appearancePicker: some ToolbarContent {
            ToolbarItem {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("gallery-appearance")
            }
        }

        private func detailBody(for section: Section) -> some View {
            ScrollView {
                switch section {
                case .colour: ColourSection()
                case .type: TypeSection()
                case .icons: IconSection()
                case .controls: ControlSection()
                case .breaker: BreakerSection()
                case .states: StateSection()
                }
            }
            .background(ColorToken.ground.color)
            // One stable identifier per section, not just on the root. The harness needs to name the
            // section it is looking at; without these it can only assert that *a* gallery opened.
            .accessibilityIdentifier(Self.identifier(for: section))
        }

        /// The accessibility identifier for one section's panel.
        ///
        /// Derived from the case rather than written out, so a seventh section cannot arrive
        /// without one.
        public static func identifier(for section: Section) -> String {
            "gallery-section-\(section.rawValue.lowercased())"
        }
    }

    // MARK: - Shared furniture

    /// A titled block, so the sections cannot drift apart in spacing.
    struct GalleryGroup<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: MetricToken.selectionRadius.leadingScalar) {
                Text(title)
                    .typeRole(.title3)
                    .foregroundStyle(ColorToken.t3.color)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MetricToken.selectionRadius.leadingScalar * 2)
        }
    }

#endif
