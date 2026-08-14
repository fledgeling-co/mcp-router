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
                pane
                    .frame(maxWidth: .infinity, minHeight: scrollableMinHeight)
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                model.observeScroll(offset: offset)
            }
            .overlay(alignment: .top) {
                ScrollEdgeSeparator(isVisible: model.scrollEdge.isSeparatorVisible)
            }
            .overlay(alignment: .bottomTrailing) {
                #if DEBUG
                    // The test surface A21 names, kept **outside** the scrolling content on purpose.
                    // Inside it, the probe sat below a deliberately over-tall stack and its frame
                    // was off the bottom of the window — the acceptance run clicked its coordinates
                    // and hit the desktop. As an overlay it is always on screen and always
                    // clickable, and it stays what the clause needs: a focusable surface in the
                    // content zone. Bottom-trailing keeps it away from the top-edge pixel sample
                    // A34 takes 120pt in from the content's leading edge.
                    KeyClaimProbe()
                #endif
            }
            // §3.3: content is opaque. A token, never a material — there is no glass on glass here,
            // and the only Liquid Glass in this app is the menus AppKit draws itself.
            .background(ShellChrome.contentBackground.color)
        }

        /// Tall enough that the content zone always has somewhere to scroll, so A34's exercised half
        /// has a real scroll to drive rather than a view that fits and never moves.
        private var scrollableMinHeight: Double {
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
        /// `scripts/acceptance/mac-shell.sh` can focus it, send each key, and read back what arrived.
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
                    // Clicking a `.focusable()` view does not reliably give it keyboard focus on
                    // macOS, and after the ⌘-shortcut assertions focus sits on the sidebar. Without
                    // this, the acceptance run clicks the probe, sends Space to whatever still has
                    // focus, and reports that the shell swallowed a key it never received.
                    .onTapGesture { isFocused = true }
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

    // **Why there is no frame-autosave bridge here.**
    //
    // A33 asks for the window's frame to survive quit and relaunch, and it does — SwiftUI's
    // `WindowGroup` gives its window an NSWindow frame-autosave name of its own and both saves and
    // restores through it. Measured on this build: moved to 300,200 at 1000x640, quit, relaunched,
    // and the window came back at exactly 300,200 at 1000x640, with the frame written to the app's
    // defaults domain under SwiftUI's own key.
    //
    // An `NSViewRepresentable` bridge that set a *named* autosave was tried first and removed,
    // because it did not work and could not be made to: the representable's view has no window
    // when `makeNSView` runs, and SwiftUI reassigns its own autosave name afterwards regardless.
    // It wrote no key to defaults in any variant. Keeping it would have been a comment claiming
    // credit for restoration that SwiftUI was performing, which is worse than no code at all.
    //
    // The cost of relying on SwiftUI's name is that the name embeds the root view's type
    // signature, so changing the modifiers wrapped around `ShellWindow` silently starts a new
    // saved frame. That is a real fragility and it is reported rather than hidden; the acceptance
    // gate measures the frame across a real relaunch, so a regression fails there rather than
    // going unnoticed.
#endif
