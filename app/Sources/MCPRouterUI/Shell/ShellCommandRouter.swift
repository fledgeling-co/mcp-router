#if os(macOS)
    import AppKit
    import MCPRouterKit

    /// What each menu command actually does, and the one place that decision is written.
    ///
    /// **Why this type exists at all.** `app/MCPRouter` is not a SwiftPM target, so nothing there
    /// can be reached by `swift test`. When each menu item carried its own closure — `{ model?
    /// .select(target) }` — the mapping from *command* to *operation* lived in the one module no
    /// test can see, and A23's second half ("⌘2 changes the selected destination") had no evidence
    /// lane except driving the running app.
    ///
    /// That lane turned out to be unavailable without taking the user's screen, and the measurement
    /// is worth recording because it is not obvious. A menu command reaches its window through
    /// `@FocusedValue`, and an **inactive** application has no focused scene — so the value is nil,
    /// the closure runs, and nothing happens. Measured on 2026-08-14 against this build: with the app
    /// launched by `open -g` and Ghostty frontmost, `AXUIElementPerformAction(item, AXPress)` returned
    /// `.success` and the selection did not move, and a `⌘2` posted with `CGEvent.postToPid` did the
    /// same. The dispatch path itself is live — a `⌘H` posted the same way hid the app — so the only
    /// broken link was the focused value. Exercising A23 through the menu therefore requires the app
    /// to be frontmost, and `planning/practices/UI_VERIFICATION.md` rules that out.
    ///
    /// So the decision moves here, where `ShellCommandRouterTests` can assert it directly, and the
    /// assembly layer keeps only the wiring: one generic line per item that names no operation. The
    /// lint gate holds that line in place by forbidding any direct model mutation in `app/MCPRouter`.
    public enum ShellCommandRouter {
        /// What a command does, as a value — so the mapping can be asserted rather than run.
        public enum Operation: Equatable, Sendable {
            /// Make this destination the selected one.
            case select(Destination)
            /// Show or hide the sidebar column.
            case toggleSidebar
            /// macOS's standard About panel.
            case aboutPanel
            /// Nothing, in this build.
            ///
            /// Two different reasons share this case deliberately, because the shell treats them
            /// identically: macOS contributes the item and performs it itself (Cut, Minimize, Quit),
            /// or the surface the command acts on is not installed and the item is disabled and
            /// unreachable. Either way the shell must not invent an operation for it, and A22 is
            /// what proves the disabled ones still appear and still say why.
            case none
            /// Open the Servers board's add sheet — `⌘N`.
            case addServer
            /// Put the keyboard in the board's search field — `⌘F`.
            case focusSearch
            /// Clear the selected server's placard, or re-index it — `⌘R`.
            case resetSelectedServer
            /// Open the remove dialog for the selected server — `⌘⌫`.
            case removeSelectedServer
        }

        /// The whole mapping, exhaustive over `MenuCommand` so a new command cannot be added
        /// without a decision being made about what it does.
        public static func operation(for command: MenuCommand) -> Operation {
            switch command {
            case let .selectDestination(destination): .select(destination)
            // `⌘,` selects the Settings destination rather than opening a further view, which is why
            // its title carries no ellipsis (§3.4). M8 may move Settings to its own scene; this is
            // the line that would change.
            case .settings: .select(.settings)
            case .showSidebar: .toggleSidebar
            case .about: .aboutPanel
            // M3's four. Each is a real operation now rather than `.none`, which is what makes the
            // menu bar the complete command surface for this board (§3.9) rather than a list of
            // items the mouse duplicates.
            case .addServer: .addServer
            case .find: .focusSearch
            case .resetServer: .resetSelectedServer
            case .removeServer: .removeSelectedServer
            case .hide, .hideOthers, .showAll, .quit, .closeWindow,
                 .undo, .redo, .cut, .copy, .paste, .selectAll,
                 .minimise, .zoom, .bringAllToFront:
                .none
            case .addMarketplace, .pairPhone, .exportLibrary,
                 .help, .whatTheRouterDoes, .reportIssue:
                .none
            }
        }

        /// Performs a command against the focused window's model.
        ///
        /// The model is optional because `@FocusedValue` is genuinely optional — there may be no
        /// focused shell window when a command fires. A command whose operation needs a model and
        /// has none does nothing, which is the honest outcome: acting on some other window's state
        /// would be worse than not acting.
        @MainActor
        public static func perform(_ command: MenuCommand, on model: ShellModel?) {
            switch operation(for: command) {
            case let .select(destination): model?.select(destination)
            case .toggleSidebar: model?.isSidebarVisible.toggle()
            case .aboutPanel: NSApplication.shared.orderFrontStandardAboutPanel(nil)
            case .addServer:
                // Selecting the destination first, so `⌘N` from any pane lands somewhere the sheet
                // makes sense rather than opening a Servers sheet over the Skills board.
                model?.select(.servers)
                model?.serversBoard.sheet = .addServer
            case .focusSearch:
                model?.select(.servers)
                model?.serversBoard.focusSearch()
            case .resetSelectedServer:
                guard let model, let state = model.trackerState,
                      let selected = model.serversBoard.selectedServer(in: state)
                else { return }
                Task { await model.serversBoard.reset(selected) }
            case .removeSelectedServer:
                guard let model, let selection = model.serversBoard.selection else { return }
                model.serversBoard.sheet = .removeServer(server: selection)
            case .none: break
            }
        }
    }
#endif
