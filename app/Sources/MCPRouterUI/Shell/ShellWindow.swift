#if os(macOS)
    import AppKit
    import MCPRouterKit
    import SwiftUI

    /// The three-zone window every other Mac surface renders into.
    ///
    /// The titlebar and the unified toolbar are AppKit's own 33pt and 52pt — `DESIGN.md` §2 recorded
    /// those values rather than choosing them, and nothing in SwiftUI sets them. What this view does
    /// set is the sidebar column, pinned to `MetricToken.sidebar`, and A1's rendered half measures
    /// all three from the running app's accessibility tree rather than claiming a SwiftUI test could
    /// see them.
    public struct ShellWindow: View {
        @Bindable private var model: ShellModel

        public init(model: ShellModel) {
            self.model = model
        }

        /// A25: the shell's focus order, declared so the clause has a subject. `DESIGN.md` §8 gives
        /// sidebar → table → inspector; M1 has neither a table nor an inspector, so it ships the
        /// prefix and the content zone's own children are appended by whichever surface owns them.
        /// Nothing of the shell's is interposed between these two.
        public static let focusOrder = ["sidebar", "content"]

        public var body: some View {
            NavigationSplitView(columnVisibility: columnVisibility) {
                Sidebar(model: model)
                    .navigationSplitViewColumnWidth(MetricToken.sidebar.leadingScalar)
                    .accessibilityIdentifier(Self.focusOrder[0])
            } detail: {
                ContentZone(model: model)
                    .accessibilityIdentifier(Self.focusOrder[1])
            }
            // §3.7: the window title says what you are looking at, not the app's name.
            .navigationTitle(model.selection.title)
            // How a menu command reaches this window's state. A menu is outside every scene, so
            // there is no other supported route from a `CommandGroup` to the focused window.
            .focusedSceneValue(\.shellModel, model)
            .background(WindowFrameAutosave(name: ShellRestoration.frameAutosaveName))
            .task { await model.run() }
        }

        private var columnVisibility: Binding<NavigationSplitViewVisibility> {
            Binding(
                get: { model.isSidebarVisible ? .all : .detailOnly },
                set: { model.isSidebarVisible = $0 != .detailOnly }
            )
        }
    }

    /// The content zone: the board where one has shipped, the honest placeholder where none has, and
    /// the scroll-edge separator where it meets the toolbar.
    struct ContentZone: View {
        @Bindable var model: ShellModel

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    pane
                    #if DEBUG
                        // The test surface A21 names. Debug-only, and the acceptance gate asserts it
                        // is absent from Release exactly the way it does for the design gallery.
                        KeyClaimProbe()
                    #endif
                }
                .frame(maxWidth: .infinity, minHeight: probeMinHeight)
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                model.observeScroll(offset: offset)
            }
            .overlay(alignment: .top) {
                ScrollEdgeSeparator(isVisible: model.scrollEdge.isSeparatorVisible)
            }
            // §3.3: content is opaque. A token, never a material — there is no glass on glass here,
            // and the only Liquid Glass in this app is the menus AppKit draws itself.
            .background(ShellChrome.contentBackground.color)
        }

        /// Tall enough that the content zone always has somewhere to scroll, so A34's exercised half
        /// has a real scroll to drive rather than a view that fits and never moves.
        private var probeMinHeight: Double {
            MetricToken.sidebar.leadingScalar * 3
        }

        @ViewBuilder
        private var pane: some View {
            if let scaffolded = ScaffoldedDestination(model.selection) {
                ScaffoldPane(scaffolded: scaffolded)
                    .frame(minHeight: MetricToken.sidebar.leadingScalar)
            } else {
                // Unreachable while `BoardRegistry.installed` is empty, and the branch M2–M8 fill in.
                // Deliberately not a placeholder: a second placeholder here would be the very thing
                // `ScaffoldedDestination` exists to make impossible.
                EmptyView()
            }
        }
    }

    #if DEBUG
        /// Proves the shell does not swallow `Space`, `Return` or `Esc`.
        ///
        /// A21's honest claim is narrow, and worth stating precisely: SwiftUI has no "route this key
        /// past me" mechanism, so "the shell installs no handler" is not by itself a routing story —
        /// `onKeyPress` fires for a focused view, and a focused sidebar row can consume a key before
        /// anything downstream sees it. What can be shown is that a focused surface **in the content
        /// zone** receives all three, which is what a board will be, and that is what this does.
        ///
        /// It records the last bare key it was given and publishes it as an accessibility value, so
        /// `scripts/acceptance/shells.sh` can focus it, send each key, and read back what arrived.
        /// Debug-only, and the Release bundle is asserted not to contain it.
        struct KeyClaimProbe: View {
            static let identifier = "mcprouter-key-probe"
            static let idle = "none"

            @State private var lastKey = KeyClaimProbe.idle
            @FocusState private var isFocused: Bool

            var body: some View {
                Text(lastKey)
                    .typeRole(.caption, monospaced: true)
                    .foregroundStyle(ColorToken.t3.color)
                    .padding(MetricToken.selectionInset.leadingScalar)
                    .focusable()
                    .focused($isFocused)
                    .focusRing(isFocused)
                    .onKeyPress(.space) { claim("Space") }
                    .onKeyPress(.return) { claim("Return") }
                    .onKeyPress(.escape) { claim("Esc") }
                    .accessibilityIdentifier(Self.identifier)
                    .accessibilityLabel(Self.identifier)
                    .accessibilityValue(lastKey)
            }

            private func claim(_ key: String) -> KeyPress.Result {
                lastKey = key
                return .handled
            }
        }
    #endif

    /// Hands the window its AppKit frame autosave name.
    ///
    /// A33 asks for the window's frame to survive quit and relaunch. AppKit already does that
    /// correctly — it persists the frame on move and resize and re-applies it before the window is
    /// shown — and re-implementing it on top of `UserDefaults` would produce a worse version that
    /// also fights the system one. SwiftUI has no API for the autosave name, so this is the bridge.
    ///
    /// The name is applied once the view has reached a window. Applying it in `updateNSView` would
    /// re-run on every state change, which is the failure mode that looks like "restoration works
    /// until you use the app".
    struct WindowFrameAutosave: NSViewRepresentable {
        let name: String

        func makeNSView(context _: Context) -> NSView {
            let view = NSView(frame: .zero)
            Task { @MainActor in
                guard let window = view.window else { return }
                // Returns false when another window already owns the name, which would be two
                // windows fighting over one saved frame rather than a restored one.
                _ = window.setFrameAutosaveName(name)
            }
            return view
        }

        func updateNSView(_: NSView, context _: Context) {}
    }
#endif
