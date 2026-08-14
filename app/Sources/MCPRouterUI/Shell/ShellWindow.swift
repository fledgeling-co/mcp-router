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
            // A33: this app stores its own window frame rather than relying on SwiftUI's implicit
            // autosave — `ShellWindowFrame.swift` records what was measured wrong with that, including
            // a relaunch that restored the window off every screen. Zero-size and behind everything,
            // so it draws nothing and receives nothing.
            .background(WindowFrameRestorer(store: model.store).frame(width: 0, height: 0))
            // The window no longer *owns* the poll — `startPolling()` retains it on the model, whose
            // lifetime is the app's. M8 added a menu-bar item whose normal state is window-closed,
            // and a `.task` here would cancel the poll behind it the moment this window went away.
            // See `ShellModel.startPolling()` for the argument in full.
            .task { model.startPolling() }
            .onAppear {
                // The menu's reason walker is armed at launch, before any window exists. This is
                // where it learns which window's state to ask.
                ShellMenuReasons.provideContext { [weak model] in model?.menuContext ?? .none }
            }
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
            Group {
                if let scaffolded = ScaffoldedDestination(model.selection) {
                    outerScroll {
                        ScaffoldPane(scaffolded: scaffolded)
                            .frame(minHeight: MetricToken.sidebar.leadingScalar)
                    }
                } else if Self.boardsThatScrollThemselves.contains(model.selection) {
                    // A board that draws a column header or a filter bar has to keep them put while
                    // its rows move — one outer scroll would carry the header off the top of a
                    // five-hundred-row log. Such a board owns its own `ScrollView` and reports its
                    // geometry through the same callback, so the scroll-edge separator behaves
                    // identically over every branch rather than being a thing only some panes have.
                    board
                } else {
                    // A board with no sticky chrome of its own scrolls in the shell's scroll view,
                    // exactly as the placeholder does.
                    outerScroll { board }
                }
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
                    //
                    // It is installed over a shipped board too, and deliberately: A21's claim is
                    // that the shell does not swallow the three bare keys, and the board that now
                    // sits beside it is exactly the kind of surface that would prove it wrong if it
                    // claimed one. `Space` reaching this probe while the Activity board is on screen
                    // *is* M2's evidence that the board does not take it.
                    KeyClaimProbe()
                        // An `NSViewRepresentable` in an overlay takes the whole overlay unless it
                        // is told otherwise, and at full size this probe covered the top edge where
                        // A34 samples the scroll-edge separator — one clause's test surface eating
                        // another clause's evidence. Sized from the row token rather than a literal,
                        // like everything else the shell draws.
                        .frame(
                            width: MetricToken.tableRows.leadingScalar * 3,
                            height: MetricToken.tableRows.leadingScalar
                        )
                        .padding(MetricToken.selectionInset.leadingScalar)
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

        /// Boards that install their own `ScrollView` because they have chrome that must not move.
        ///
        /// Kept as data rather than an `if` chain so a board joining is one line, and so the
        /// distinction is legible: it is about sticky chrome, not about which item shipped it.
        private static let boardsThatScrollThemselves: Set<Destination> = [.activity]

        /// The shell's own scroll view — the one the scroll-edge separator reads.
        private func outerScroll(@ViewBuilder _ content: () -> some View) -> some View {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: scrollableMinHeight)
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                geometry.contentOffset.y
            } action: { previous, offset in
                // Both values, deliberately: the callback fires only on a change, so `previous` is
                // the only place the resting offset ever appears. See `ScrollEdgeState.observe`.
                model.observeScroll(previous: previous, offset: offset)
            }
        }

        /// The board for the selected destination.
        ///
        /// Reached only when `ScaffoldedDestination` refused to construct, which is exactly when
        /// `BoardRegistry.installed` contains the destination — so a board and its placeholder can
        /// never both be reachable, and neither can neither.
        @ViewBuilder
        private var board: some View {
            switch model.selection {
            case .activity:
                ActivityBoard(model: model.activity) { previous, offset in
                    model.observeScroll(previous: previous, offset: offset)
                }
            case .servers:
                // `ScaffoldedDestination` returning nil is the structural proof that this
                // destination has a surface, so there is no placeholder to fall back to and none
                // is written.
                ServersBoard(shell: model, board: model.serversBoard)
            case .skills:
                SkillsBoard(shell: model, board: model.skillsBoard)
            case .settings:
                SettingsBoard(shell: model)
            case .discover, .inbox, .evals, .cleanup:
                // Unreachable: every one of these is still in `scaffolded`, and the branch in
                // `body` catches them. Deliberately not a second placeholder — a placeholder here
                // is the very thing `ScaffoldedDestination` exists to make impossible. M5–M7
                // replace these cases one at a time, and the exhaustive switch is what makes each
                // one visible.
                EmptyView()
            }
        }
    }

    #if DEBUG
        /// Proves the shell does not swallow `Space`, `Return` or `Esc`.
        ///
        /// A21's honest claim is narrow, and worth stating precisely: SwiftUI has no "route this key
        /// past me" mechanism, so "the shell installs no handler" is not by itself a routing story —
        /// a focused sidebar row can consume a key before anything downstream sees it. What can be
        /// shown is that a focused surface **in the content zone** receives all three, which is what
        /// a board will be, and that is what this does.
        ///
        /// **Why this is an `NSView` rather than `Text().focusable()`.** It was the latter first, and
        /// measured on macOS 26.5 on 2026-08-14 it never took focus: clicked at its own reported
        /// `AXPosition`, it reported `AXFocused` 0 and its value stayed `none` through a `Space`. The
        /// reason is that SwiftUI's `.focusable()` only joins the key-view loop when macOS *Full
        /// Keyboard Access* is on, which is off by default — so A21's evidence would have been
        /// contingent on a System Settings toggle on whichever machine ran the gate, and would have
        /// reported "the shell swallowed Space" on a shell that had done nothing wrong.
        ///
        /// An `NSView` that accepts first responder has no such dependency. It is also the stronger
        /// probe for what the clause actually claims: if a menu had bound bare `Space`, or the
        /// sidebar had consumed it, the key would never reach a responder in the content zone at
        /// all — which is the thing being tested. Debug-only, and the Release bundle is asserted not
        /// to contain it.
        struct KeyClaimProbe: NSViewRepresentable {
            static let identifier = "mcprouter-key-probe"
            static let idle = "none"

            func makeNSView(context _: Context) -> KeyClaimView {
                KeyClaimView()
            }

            func updateNSView(_: KeyClaimView, context _: Context) {}
        }

        /// The first responder A21 sends its three keys to.
        ///
        /// It publishes what it last received as its accessibility *value*, so the acceptance script
        /// reads back a fact rather than inferring one from a screenshot.
        final class KeyClaimView: NSView {
            private var lastKey = KeyClaimProbe.idle

            override var acceptsFirstResponder: Bool { true }
            /// So the click that focuses it is not spent activating the window instead.
            override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
                true
            }

            /// Claims focus as soon as it is in a window, rather than waiting to be clicked.
            ///
            /// Clicking it is not the part of A21 that matters — *receiving the key while focused*
            /// is — and a click is the least reliable way to arrange the precondition: it depends on
            /// the probe's screen coordinates, on nothing overlapping the window, and on the click
            /// not being consumed by the scroll view it sits over. Measured on 2026-08-14 the click
            /// landed inside the probe's own reported frame and focus did not move. Claiming it here
            /// is deterministic, and it is exactly what a board will do when it wants the keyboard.
            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                guard window != nil else { return }
                // After the current layout pass: a `makeFirstResponder` issued while SwiftUI is
                // still building the content zone is discarded when it installs its own responder.
                DispatchQueue.main.async { [weak self] in
                    guard let self, let window else { return }
                    window.makeFirstResponder(self)
                }
            }

            override func mouseDown(with _: NSEvent) {
                window?.makeFirstResponder(self)
            }

            override func keyDown(with event: NSEvent) {
                switch event.keyCode {
                case 49: claim("Space")
                case 36: claim("Return")
                case 53: claim("Esc")
                // Anything else is not this probe's business and goes back to the chain, so a
                // shortcut that happens to land here is not silently eaten by the test surface.
                default: super.keyDown(with: event)
                }
            }

            private func claim(_ key: String) {
                lastKey = key
                setAccessibilityValue(key)
            }

            override func isAccessibilityElement() -> Bool {
                true
            }

            override func accessibilityRole() -> NSAccessibility.Role? {
                .staticText
            }

            override func accessibilityLabel() -> String? {
                KeyClaimProbe.identifier
            }

            override func accessibilityIdentifier() -> String {
                KeyClaimProbe.identifier
            }

            override func accessibilityValue() -> Any? {
                lastKey
            }
        }
    #endif

    // **Where the frame restoration lives, and why it is not SwiftUI's.**
    //
    // A33 asks for the window's frame to survive quit and relaunch. An earlier revision of this item
    // left that to SwiftUI: a `WindowGroup` gives its window an implicit NSWindow frame-autosave
    // name, one run measured a move surviving through it, and the bridge that had been written was
    // removed as redundant.
    //
    // Re-measured on 2026-08-14 across several runs, that conclusion does not hold. A programmatic
    // move updated the implicit autosave key on one run and left it at the launch frame on the next
    // two; the frame the app came back at was one from an earlier session rather than the last one;
    // and one relaunch restored the window to `-266,-1172`, off every attached screen, from a frame
    // saved while an external display was attached. The name is also fragile by construction — it
    // embeds the root view's type signature, so wrapping one more modifier around `ShellWindow`
    // silently starts a new saved window.
    //
    // So the frame is now the app's own, stored beside the selected destination and applied on first
    // appearance, with an explicit usability rule so an unreachable frame is never restored.
    // `ShellWindowFrame.swift` holds it; `ShellFrameRestorationTests` tests the decisions; and the
    // acceptance gate still measures a real move across a real relaunch, so a regression fails there
    // rather than going unnoticed.
#endif
