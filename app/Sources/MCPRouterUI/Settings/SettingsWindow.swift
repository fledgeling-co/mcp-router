#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The Settings window: a 200pt-in-the-mock source list of seven panes, and a detail scroll.
    ///
    /// Declared as SwiftUI's `Settings` scene rather than as a hand-built `Window`, because the
    /// scene is what carries the disabled minimise and zoom, the titlebar height and the `⌘,`
    /// binding on this platform. `MCPRouterApp.swift` names the scene; this is what it renders.
    ///
    /// **The selection binding is this window's own** — never `ShellModel`'s and never a shared one.
    /// That is the brief's own recorded bug: in the mock the console's board switcher cleared the
    /// settings list's selection through an unscoped query, and the selected pane rendered with no
    /// fill. Two source lists, two selections.
    ///
    /// **It persists, and bare `@State` would be the wrong owner.** A `Settings` scene's window is
    /// destroyed on close, so `@State` resets the pane to Router on every `⌘,` — which is not how a
    /// settings window behaves here and is a regression against the board, where the selected
    /// destination survived because `ShellRestoration` held it. So the pane is stored the way the
    /// destination is, which also gives it the `ShellTestSupport.scratchStore()` evidence lane a
    /// scene-local `@State` has none of.
    public struct SettingsWindow: View {
        @Bindable private var shell: ShellModel
        @State private var model: SettingsWindowModel
        @State private var pane: SettingsPane
        private let buildIdentity: BuildIdentity
        private let store: ShellRestoration
        /// Closes this window. In a `Settings` scene it is the window that goes, not the app.
        @Environment(\.dismiss) private var dismiss

        /// **Exactly one initializer**, so the scene and the measurement harness construct this the
        /// same way and differ only in the store they pass. `MeasureDump` is an unsigned SwiftPM
        /// executable with no keychain access group — `SecItemCopyMatching` returns `-34018` there,
        /// which the Makefile already documents for the iOS lane — so it passes `InMemoryTokenStore`.
        public init(
            model shell: ShellModel,
            buildIdentity: BuildIdentity,
            store: (any ControlTokenStore)? = nil,
            restoration: ShellRestoration = .standard
        ) {
            self.shell = shell
            self.buildIdentity = buildIdentity
            self.store = restoration
            _model = State(wrappedValue: SettingsWindowModel(store: store ?? KeychainTokenStore()))
            _pane = State(wrappedValue: restoration.restoredSettingsPane())
        }

        /// The router's own four facts, or nil while nothing has been read.
        private var facts: SettingsPresentation.RouterFacts? {
            guard let state = shell.trackerState,
                  let port = state.port,
                  let idleMs = state.idleMs,
                  let since = state.since
            else { return nil }
            return .init(port: port, idleMs: idleMs, since: since, home: model.routerHome)
        }

        /// The router failed to answer and nothing was ever loaded. Distinct from "still loading",
        /// which draws a skeleton and says nothing.
        private var offlineError: ControlAPIError? {
            guard let state = shell.trackerState else { return nil }
            if case let .failed(error) = state.load { return error }
            return nil
        }

        public var body: some View {
            NavigationSplitView {
                sourceList
            } detail: {
                detail
            }
            .navigationTitle(SettingsPresentation.paneTitle)
            // Attached here, on the Settings window's own root, so the sheet drops from this
            // window's titlebar and is modal to it alone.
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .childPath:
                    ChildPathSheet(dismiss: { model.sheet = nil })
                }
            }
            // **Escape, and it ships because the platform does not provide it.** Measured on the
            // running build on 2026-08-22: with the Settings window open, a keycode-53 event posted
            // to the process left it open, so the `Settings` scene does not close on Escape by
            // itself. The brief asks for it, `DESIGN.md` §8 gives `Esc` to dismissing, and this is
            // the fallback D3's measurement table named for exactly this reading.
            //
            // No conflict with `keysReservedForContent`: that rule governs *menu commands*, and this
            // is a window-root handler, and the sheet below takes Escape first when it is open.
            .onExitCommand { dismiss() }
            .task { await model.load(unauthorized: offlineError == .unauthorized) }
            .onChange(of: offlineError) { _, new in
                Task { await model.load(unauthorized: new == .unauthorized) }
            }
            .measured("settings-window", role: "settings-window", kind: .hstack)
        }

        // MARK: - The source list

        /// Seven rows, one selected, arrow-key traversal from `List(selection:)` and `.sidebar`.
        private var sourceList: some View {
            List(selection: paneSelection) {
                ForEach(SettingsPane.ordered) { pane in
                    SettingsPaneRow(pane: pane, isSelected: self.pane == pane)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, MetricToken.tableRows.leadingScalar)
            .navigationSplitViewColumnWidth(SettingsMetrics.sourceListWidth)
            .accessibilityIdentifier(Self.focusOrder[0])
            .measured("source-list", role: "source-list", kind: .vstack, alignment: "leading")
        }

        /// A25's shape, for this window: source list then detail, and nothing interposed.
        public static let focusOrder = ["settings-source-list", "settings-detail"]

        /// Writes through the restoration store on every change, so the pane survives the window
        /// being destroyed at close.
        private var paneSelection: Binding<SettingsPane?> {
            Binding(
                get: { pane },
                set: { new in
                    // A `List(selection:)` hands back nil when the user deselects; requirement 5 is
                    // that exactly one pane is selected, so a deselection keeps the current one.
                    guard let new else { return }
                    pane = new
                    store.save(settingsPane: new)
                }
            )
        }

        // MARK: - The detail

        /// **This window owns its detail `ScrollView`, where the Settings board deliberately did
        /// not.** The board sat inside the shell's outer scroll and adding a second one made it
        /// publish three `AXScrollArea`s where every other board published two. There is no shell
        /// around this window, so there is no outer scroller to nest inside and the inversion is the
        /// correct port rather than a re-litigation.
        private var detail: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {
                    header
                    body(of: pane)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(SettingsMetrics.panePadding)
            }
            .accessibilityIdentifier(Self.focusOrder[1])
            .measured("detail", role: "detail", kind: .scroll, alignment: "leading")
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: SettingsMetrics.tightGap) {
                Text(pane.title)
                    .typeRole(.title1)
                    .foregroundStyle(ColorToken.t1.color)
                    .measured(
                        "pane-title", role: "board-title", kind: .text,
                        tokens: ["foreground": .t1], type: .title1, text: pane.title
                    )
                Text(pane.subtitle)
                    .typeRole(.callout)
                    .foregroundStyle(ColorToken.t2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .measured(
                        "pane-subtitle", role: "board-subtitle", kind: .text,
                        tokens: ["foreground": .t2], type: .callout, text: pane.subtitle
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .measured("pane-hero", role: "title-block", kind: .vstack, alignment: "leading")
        }

        /// The pane bodies, exhaustive over `SettingsPane` with no `default`: a pane added later
        /// stops this compiling at the moment someone should be deciding what it draws.
        @ViewBuilder
        private func body(of pane: SettingsPane) -> some View {
            switch pane {
            case .router:
                RouterPane(shell: shell, facts: facts, offlineError: offlineError)
            case .harnesses, .analyst, .updates:
                GovernedElsewherePane(pane: pane)
            case .security:
                SecurityPane(shell: shell, model: model)
            case .menuBar:
                MenuBarPane(shell: shell)
            case .advanced:
                AdvancedPane(
                    shell: shell,
                    routerHome: model.routerHome,
                    buildIdentity: buildIdentity,
                    onShowChildPath: { model.sheet = .childPath }
                )
            }
        }
    }
#endif
